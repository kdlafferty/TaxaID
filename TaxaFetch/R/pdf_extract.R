# ==============================================================================
# pdf_extract.R
# TaxaFetch -- Stage 3: PDF occurrence extraction
#
# Exported functions:
#   build_pdf_extract_prompt()    -- build extraction prompt from pdf_structure
#   parse_pdf_extract_response()  -- parse raw LLM text to DwC tibble
#   print.pdf_extract_prompt      -- S3 print method
#
# Internal helpers:
#   .build_axis_instructions()    -- translate pdf_structure axes to prompt text
#   .build_abbrev_table_text()    -- format abbreviation inventory for prompt
#   .parse_dwc_csv()              -- strip markdown fences, find header, parse CSV
#   .strip_to_binomial()          -- strip scientificName to Genus species
#   .expand_abbreviated_names()   -- expand abbreviated binomials
#   .coerce_numeric_col()         -- safe as.numeric with warning
#   .coerce_integer_col()         -- safe as.integer with warning
#
# Design: mirrors fetch_dataone_occurrences() output contract.
# See PDF_PIPELINE_DATAONE_PARALLEL.md for full column contract.
#
# Session 24: initial implementation
# Session 25: added dpi param to build_pdf_extract_prompt(); page-count guard
#   (warn when n_send > 30 at dpi=150); chunk_pages param for prose-dense
#   large PDFs; n_chunks stored in S3 object.
# ==============================================================================

utils::globalVariables(c(
  "scientificName", "occurrenceID", "datasetID"
))


# ------------------------------------------------------------------------------
# Canonical DwC column order -- must match fetch_dataone_occurrences() output
# ------------------------------------------------------------------------------

.pdf_dwc_cols <- c(
  "occurrenceID", "datasetID", "datasetName", "institutionCode",
  "basisOfRecord", "eventDate", "year", "month", "day",
  "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
  "scientificName", "genus", "family", "specificEpithet", "vernacularName",
  "individualCount", "recordedBy", "locality", "habitat"
)

# PDF-pipeline appended columns (always present in PDF output)
.pdf_extra_cols <- c(
  "occurrenceStatus", "establishmentMeans",
  "bibliographicCitation", "associatedReferences"
)

# prevalence_abundance-only additions
.pdf_pa_cols <- c("organismQuantity", "organismQuantityType")


# ==============================================================================
# .build_axis_instructions() -- translate pdf_structure axes to prompt text
# ==============================================================================

#' @noRd
.build_axis_instructions <- function(pdf_structure) {

  obs  <- pdf_structure$observation_type  %||% "field_survey"
  loc  <- pdf_structure$location_structure %||% "named_localities"
  dens <- pdf_structure$data_density       %||% "tabular"
  cont <- pdf_structure$contamination_risk %||% "low"

  lines <- character(0L)

  # --- observation_type instructions ---
  if (obs == "field_survey") {
    lines <- c(lines,
      "OBSERVATION TYPE: Field survey. Extract individual occurrence records.",
      "Do NOT extract records from Introduction or Discussion (background mentions).",
      "Leave individualCount blank unless explicitly stated in the source data.")
  } else if (obs == "prevalence_abundance") {
    lines <- c(lines,
      "OBSERVATION TYPE: Prevalence / abundance study.",
      "Extract non-zero detection records only. Do NOT extract zero-counts as absence records.",
      "Populate organismQuantity with the numeric value (infection rate, density, count).",
      "Populate organismQuantityType with a plain-language description",
      "  e.g. 'prevalence' / 'density per m2' / 'mean abundance'.",
      "Set occurrenceStatus = 'present' for all extracted records.")
  } else if (obs == "museum_collection") {
    lines <- c(lines,
      "OBSERVATION TYPE: Museum / herbarium collection records.",
      "Extract each specimen record. Dates may be collection dates.",
      "basisOfRecord should be 'PreservedSpecimen' for these records.")
  }

  # --- location_structure instructions ---
  if (loc == "named_localities") {
    lines <- c(lines,
      "",
      "LOCATION STRUCTURE: Named localities only.",
      "Populate 'locality' with the place name as written in the paper.",
      "Infer decimalLatitude/decimalLongitude from the place name ONLY when you are",
      "  highly confident (well-known named place with unambiguous coordinates).",
      "  Use coordinateUncertaintyInMeters tier scheme:",
      "    1000 m  -- precise named site (beach, cove, reef, station name)",
      "    5000 m  -- small region / bay / estuary",
      "    25000 m -- large region / county / island group",
      "  Leave lat/lon blank (NA) when uncertain -- do not guess.",
      "List resolution: if the text says 'A, B, and C Creeks', emit three separate rows.",
      "Distributive nouns: 'species X and Y at site Z' = two rows, same locality.")
  } else if (loc == "explicit_latlon") {
    lines <- c(lines,
      "",
      "LOCATION STRUCTURE: Explicit lat/lon coordinates provided in the paper.",
      "Extract decimalLatitude and decimalLongitude from the paper's data.",
      "Use coordinateUncertaintyInMeters tier scheme based on stated precision:",
      "    1000 m  -- coordinates stated to 4+ decimal places",
      "    5000 m  -- coordinates stated to 2-3 decimal places",
      "    25000 m -- coordinates stated to 1 decimal place or less",
      "Also populate 'locality' if a place name is given.")
  } else if (loc == "single_site") {
    lines <- c(lines,
      "",
      "LOCATION STRUCTURE: Single study site throughout.",
      "Apply the coordinates provided below to every extracted record.",
      "Also populate 'locality' if a place name is given.")
  }

  # --- data_density instructions ---
  if (dens == "tabular") {
    lines <- c(lines,
      "",
      "DATA DENSITY: Tabular. Extract from data tables.",
      "Read table column headers carefully; map to DwC fields as accurately as possible.",
      "Extract one row of output per row of source data (after list resolution).")
  } else if (dens == "prose_dense") {
    lines <- c(lines,
      "",
      "DATA DENSITY: Prose-dense species accounts.",
      "Species records are embedded in narrative text, not tables.",
      "Extract each named species + locality combination as a separate record.",
      "Date may be given once per page or section -- apply it to all records on that page.")
  } else if (dens == "mixed") {
    lines <- c(lines,
      "",
      "DATA DENSITY: Mixed (tables and prose species accounts both present).",
      "Extract from both tables and prose sections.",
      "Apply table-extraction rules to tables and prose-extraction rules to accounts.")
  } else if (dens == "supplementary") {
    lines <- c(lines,
      "",
      "DATA DENSITY: Primary data in supplementary materials.",
      "Extract what is visible in the main paper; note if supplementary tables",
      "  appear to contain additional records not sent here.")
  }

  # --- contamination_risk instructions ---
  if (!is.na(cont) && cont == "high") {
    lines <- c(lines,
      "",
      "CONTAMINATION RISK: HIGH.",
      "This paper has extensive Introduction and Discussion sections that mention",
      "  species in contexts other than direct observation (background, comparisons,",
      "  historical records, model predictions).",
      "ONLY extract records that are direct results of this study.",
      "Ignore all species mentions in Introduction, Discussion, and References.")
  }

  paste(lines, collapse = "\n")
}


# ==============================================================================
# .build_abbrev_table_text() -- format abbreviation inventory for prompt
# ==============================================================================

#' @noRd
.build_abbrev_table_text <- function(abbreviation_inventory) {
  if (length(abbreviation_inventory) == 0L) return(NULL)
  rows <- sprintf("  %-15s %s",
                  names(abbreviation_inventory),
                  unname(abbreviation_inventory))
  paste(c("ABBREVIATION KEY (expand these in scientificName):",
          rows), collapse = "\n")
}


# ==============================================================================
# .parse_dwc_csv() -- strip markdown fences, find CSV header, parse to df
# ==============================================================================

#' @noRd
.parse_dwc_csv <- function(raw_text) {
  # Remove markdown code fences
  raw_text <- gsub("```[a-z]*", "", raw_text)
  raw_text <- gsub("```", "", raw_text)

  lines <- strsplit(raw_text, "\n")[[1L]]
  lines <- trimws(lines)
  lines <- lines[nzchar(lines)]

  if (length(lines) == 0L) {
    stop("LLM response is empty after stripping markdown fences.", call. = FALSE)
  }

  # Find the header line (contains 'scientificName' or 'occurrenceID')
  header_idx <- which(
    grepl("scientificName|occurrenceID", lines, ignore.case = TRUE)
  )
  if (length(header_idx) == 0L) {
    stop(
      "Cannot locate CSV header in LLM response. ",
      "Expected a line containing 'scientificName' or 'occurrenceID'.",
      call. = FALSE
    )
  }
  header_idx <- header_idx[1L]
  csv_lines  <- lines[header_idx:length(lines)]

  # Parse with read.csv
  csv_text <- paste(csv_lines, collapse = "\n")
  tryCatch(
    read.csv(text = csv_text, stringsAsFactors = FALSE, na.strings = c("", "NA")),
    error = function(e) {
      stop(sprintf("read.csv failed on LLM response: %s", conditionMessage(e)),
           call. = FALSE)
    }
  )
}


# ==============================================================================
# .strip_to_binomial() -- strip scientificName to Genus species
# ==============================================================================

#' @noRd
.strip_to_binomial <- function(x) {
  # x is a character vector
  # Remove subspecies / variety epithets and author authorities
  # Strategy: keep first two space-separated tokens only (Genus species)
  # Tokens that are purely uppercase (author names) or parenthetical are dropped
  vapply(x, function(nm) {
    if (is.na(nm) || !nzchar(trimws(nm))) return(NA_character_)
    tokens <- strsplit(trimws(nm), "\\s+")[[1L]]
    # Filter out tokens that look like author authorities:
    #   all-uppercase, or start with '(', or are pure numeric
    clean <- tokens[!grepl("^[A-Z]+$|^\\(|^[0-9]", tokens)]
    if (length(clean) < 1L) return(NA_character_)
    if (length(clean) >= 2L) {
      return(paste(clean[1L], clean[2L]))
    }
    clean[1L]  # genus only fallback
  }, character(1L), USE.NAMES = FALSE)
}


# ==============================================================================
# .expand_abbreviated_names() -- expand abbreviated binomials
# ==============================================================================

#' @noRd
.expand_abbreviated_names <- function(x, abbreviation_inventory) {
  if (length(abbreviation_inventory) == 0L) return(x)
  # abbreviation_inventory: names = key e.g. "V.", values = full binomial
  vapply(x, function(nm) {
    if (is.na(nm) || !nzchar(trimws(nm))) return(nm)
    # Check if first token matches an abbreviation key
    first_token <- strsplit(trimws(nm), "\\s+")[[1L]][1L]
    if (first_token %in% names(abbreviation_inventory)) {
      return(unname(abbreviation_inventory[first_token]))
    }
    nm
  }, character(1L), USE.NAMES = FALSE)
}


# ==============================================================================
# .coerce_numeric_col() / .coerce_integer_col()
# ==============================================================================

#' @noRd
.coerce_numeric_col <- function(x, col_name) {
  result <- suppressWarnings(as.numeric(x))
  n_fail <- sum(is.na(result) & !is.na(x) & nzchar(x))
  if (n_fail > 0L) {
    warning(sprintf(
      "Column '%s': %d value(s) could not be coerced to numeric; set to NA.",
      col_name, n_fail
    ), call. = FALSE)
  }
  result
}

#' @noRd
.coerce_integer_col <- function(x, col_name) {
  result <- suppressWarnings(as.integer(x))
  n_fail <- sum(is.na(result) & !is.na(x) & nzchar(as.character(x)))
  if (n_fail > 0L) {
    warning(sprintf(
      "Column '%s': %d value(s) could not be coerced to integer; set to NA.",
      col_name, n_fail
    ), call. = FALSE)
  }
  result
}


# ==============================================================================
# build_pdf_extract_prompt()
# ==============================================================================

#' Build a Stage 3 extraction prompt from a characterised PDF
#'
#' @description
#' Uses the five-axis classification in \code{pdf_structure} to configure an
#' extraction prompt that instructs the LLM to produce a Darwin Core CSV table
#' of occurrence records from the targeted PDF page images.
#'
#' The returned S3 object is passed directly to \code{call_api_pdf()}.
#'
#' @param pdf_structure A \code{pdf_structure} object from
#'   \code{screen_pdf_structure()}.
#' @param single_site_coords Optional named list with elements \code{lat} and
#'   \code{lon} (numeric). Required when
#'   \code{pdf_structure$single_site_rule == TRUE} and the coordinates are not
#'   encoded in the structure object. Ignored otherwise.
#' @param dpi Integer. Resolution for page image rendering. Default \code{150L}.
#'   Reduce to \code{100L} if the page count is very large and HTTP 429 errors
#'   occur. Values above 200 are not recommended for large documents.
#' @param chunk_pages Logical. When \code{TRUE} and the number of send pages
#'   exceeds 25, split the pages into chunks of at most 25 and return one prompt
#'   string per chunk in \code{$prompts}. Set \code{$n_chunks > 1} in the
#'   returned object. Default \code{FALSE}.
#' @param verbose Logical. Print page-count and chunking information. Default
#'   \code{TRUE}.
#'
#' @return An S3 object of class \code{c("pdf_extract_prompt", "llm_prompt")}
#'   with elements:
#'   \itemize{
#'     \item \code{$prompts} -- character vector of prompt strings (length 1
#'       normally; \code{>1} when \code{chunk_pages = TRUE} and
#'       \code{n_send > 25})
#'     \item \code{$page_chunks} -- list of integer vectors, one per prompt,
#'       giving the page numbers for each chunk
#'     \item \code{$n_chunks} -- integer; number of chunks
#'     \item \code{$n_send} -- integer; total pages flagged for sending
#'     \item \code{$dpi} -- integer; dpi stored for use by caller
#'     \item \code{$pdf_structure} -- the input \code{pdf_structure} object
#'     \item \code{$single_site_coords} -- list(lat, lon) or \code{NULL}
#'     \item \code{$abbreviation_inventory} -- named character vector
#'   }
#'
#'   Returns \code{NULL} invisibly (with a message) when
#'   \code{observation_type} is \code{"analytical_modelling"} or
#'   \code{"experimental_lab"}.
#'
#' @examples
#' \dontrun{
#' prompt <- build_pdf_extract_prompt(pdf_structure)
#' print(prompt)
#' }
#'
#' @export
build_pdf_extract_prompt <- function(pdf_structure,
                                     single_site_coords = NULL,
                                     dpi                = 150L,
                                     chunk_pages        = FALSE,
                                     verbose            = TRUE) {

  stopifnot(inherits(pdf_structure, "pdf_structure"))
  dpi        <- as.integer(dpi)
  chunk_pages <- isTRUE(chunk_pages)

  # Skip non-extractable paper types
  obs <- pdf_structure$observation_type %||% "field_survey"
  if (!is.na(obs) && obs %in% c("analytical_modelling", "experimental_lab")) {
    message(sprintf(
      "build_pdf_extract_prompt: observation_type = '%s'. Skipping extraction.", obs
    ))
    return(invisible(NULL))
  }

  # Validate single_site_coords when rule is TRUE
  if (isTRUE(pdf_structure$single_site_rule)) {
    coords <- single_site_coords %||% pdf_structure$single_site_coords
    if (is.null(coords) || is.null(coords$lat) || is.null(coords$lon)) {
      stop(
        "pdf_structure$single_site_rule is TRUE but no coordinates supplied.\n",
        "  Pass single_site_coords = list(lat = ..., lon = ...) to build_pdf_extract_prompt().",
        call. = FALSE
      )
    }
  } else {
    coords <- NULL
  }

  # Identify send pages
  pt        <- pdf_structure$page_table
  send_rows <- pt[isTRUE(pt$send_image) | pt$send_image == TRUE, ]
  n_send    <- nrow(send_rows)
  send_pages <- sort(unique(send_rows$page))

  # --- Page-count guard (Session 25) ---
  if (n_send > 30L && dpi >= 150L && !chunk_pages) {
    warning(
      sprintf(
        paste0(
          "build_pdf_extract_prompt: %d pages flagged for sending at dpi=%d.\n",
          "  This may cause HTTP 429 (payload too large) at the API.\n",
          "  Options:\n",
          "    1. Reduce dpi: build_pdf_extract_prompt(..., dpi = 100L)\n",
          "    2. Enable chunking: build_pdf_extract_prompt(..., chunk_pages = TRUE)\n",
          "  Proceeding, but expect possible API failure."
        ),
        n_send, dpi
      ),
      call. = FALSE
    )
  }

  if (verbose) {
    message(sprintf(
      "build_pdf_extract_prompt: %d page(s) flagged for extraction (dpi = %d).",
      n_send, dpi
    ))
  }

  # --- Build the page chunks ---
  chunk_size <- 25L
  if (chunk_pages && n_send > chunk_size) {
    # Split send_pages into groups of at most chunk_size
    idx_groups <- split(seq_along(send_pages),
                        ceiling(seq_along(send_pages) / chunk_size))
    page_chunks <- lapply(idx_groups, function(idx) send_pages[idx])
    if (verbose) {
      message(sprintf(
        "  Chunking into %d groups of up to %d pages each.",
        length(page_chunks), chunk_size
      ))
    }
  } else {
    page_chunks <- list(send_pages)
  }
  n_chunks <- length(page_chunks)

  # --- Build core prompt components (axis instructions, abbreviations) ---
  axis_text   <- .build_axis_instructions(pdf_structure)
  abbrev_text <- .build_abbrev_table_text(
    pdf_structure$abbreviation_inventory %||% character(0L)
  )

  # Single-site coordinate injection
  coord_inject <- if (!is.null(coords)) {
    sprintf(
      paste0(
        "SINGLE STUDY SITE COORDINATES (apply to every record):\n",
        "  decimalLatitude  = %s\n",
        "  decimalLongitude = %s\n",
        "  coordinateUncertaintyInMeters = 1000\n"
      ),
      format(coords$lat, nsmall = 6L),
      format(coords$lon, nsmall = 6L)
    )
  } else NULL

  # --- Column list for the prompt ---
  pa_col_txt <- if (!is.na(obs) && obs == "prevalence_abundance") {
    paste0(
      ", organismQuantity, organismQuantityType"
    )
  } else ""

  col_list <- paste0(
    paste(.pdf_dwc_cols, collapse = ", "),
    ", occurrenceStatus, establishmentMeans, ",
    "bibliographicCitation, associatedReferences",
    pa_col_txt
  )

  # --- Build one prompt per chunk ---
  chunk_note_template <- if (n_chunks > 1L) {
    "NOTE: This is chunk %d of %d. Continue using the same CSV format.\n\n"
  } else NULL

  prompts <- lapply(seq_along(page_chunks), function(i) {

    chunk_note <- if (!is.null(chunk_note_template)) {
      sprintf(chunk_note_template, i, n_chunks)
    } else ""

    prompt_parts <- c(
      chunk_note,

      "You are extracting biodiversity occurrence records from pages of a scientific paper.\n",
      "Output a single CSV table with NO prose before or after.\n",
      "The FIRST LINE of your response must be the CSV header row.\n",
      "Use NA for any field you cannot determine.\n\n",

      "COLUMN ORDER (use exactly these names, in this order):\n",
      col_list, "\n\n",

      "FIELD RULES:\n",
      "- scientificName: Latin binomials only (Genus species). No sp. / spp. / authorities.\n",
      "  Zero tolerance for typos -- use the exact spelling from the paper.\n",
      "- occurrenceID: leave blank (will be assigned post-parse).\n",
      "- basisOfRecord: 'HumanObservation' unless source is a museum specimen.\n",
      "- eventDate: ISO 8601 (YYYY-MM-DD or YYYY-MM or YYYY). Per-row from tables.\n",
      "  Not paper-level -- extract the specific date for each record where given.\n",
      "- occurrenceStatus: always 'present' (do not extract absence/zero records).\n",
      "- establishmentMeans: fill from paper text if stated (e.g. 'native', 'introduced');\n",
      "  leave NA if not stated.\n",
      "- bibliographicCitation: construct from paper header (Author Year, Title, Journal Vol:pp).\n",
      "  Use the same value for every row in this paper.\n",
      "- associatedReferences: internal citation(s) linked to this specific record, if any.\n",
      "  Leave NA if none. Do NOT copy the full reference list.\n\n",

      "FILTERING RULES:\n",
      "- Extract ONLY records from the Results / Data sections.\n",
      "- Do NOT extract species mentions from Introduction, Abstract, Discussion,\n",
      "  or References (those are background / comparison mentions, not new observations).\n\n",

      axis_text, "\n\n",

      if (!is.null(abbrev_text)) paste0(abbrev_text, "\n\n") else "",
      if (!is.null(coord_inject)) paste0(coord_inject, "\n\n") else "",

      "Begin your response with the CSV header row now."
    )
    paste(prompt_parts, collapse = "")
  })

  # --- Assemble S3 object ---
  structure(
    list(
      prompts               = prompts,
      page_chunks           = page_chunks,
      n_chunks              = n_chunks,
      n_send                = n_send,
      dpi                   = dpi,
      pdf_structure         = pdf_structure,
      single_site_coords    = coords,
      abbreviation_inventory = pdf_structure$abbreviation_inventory %||% character(0L)
    ),
    class = c("pdf_extract_prompt", "llm_prompt")
  )
}


# ==============================================================================
# print.pdf_extract_prompt
# ==============================================================================

#' Print a pdf_extract_prompt Object
#'
#' @description Displays a compact summary of the PDF extraction prompt.
#' @param x A \code{pdf_extract_prompt} object.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export
print.pdf_extract_prompt <- function(x, ...) {
  cat("<pdf_extract_prompt>\n")
  cat(sprintf("  Pages to send  : %d\n", x$n_send))
  cat(sprintf("  dpi            : %d\n", x$dpi))
  cat(sprintf("  Chunks         : %d\n", x$n_chunks))
  obs <- x$pdf_structure$observation_type %||% "(unknown)"
  cat(sprintf("  Observation    : %s\n", obs))
  loc <- x$pdf_structure$location_structure %||% "(unknown)"
  cat(sprintf("  Location struct: %s\n", loc))
  if (!is.null(x$single_site_coords)) {
    cat(sprintf("  Single-site lat: %s  lon: %s\n",
                x$single_site_coords$lat, x$single_site_coords$lon))
  }
  if (length(x$abbreviation_inventory) > 0L) {
    cat(sprintf("  Abbreviations  : %d\n", length(x$abbreviation_inventory)))
  }
  if (x$n_chunks > 1L) {
    for (i in seq_along(x$page_chunks)) {
      pg <- x$page_chunks[[i]]
      cat(sprintf("  Chunk %d: pages %d-%d (%d pages)\n",
                  i, min(pg), max(pg), length(pg)))
    }
  }
  invisible(x)
}


# ==============================================================================
# parse_pdf_extract_response()
# ==============================================================================

#' Parse a raw LLM extraction response to a Darwin Core tibble
#'
#' @description
#' Parses the raw text returned by \code{call_api_pdf()} into a tidy
#' Darwin Core tibble compatible with \code{stack_occurrences()}.
#'
#' The function:
#' \itemize{
#'   \item Strips markdown fences and locates the CSV header
#'   \item Coerces columns to correct types
#'   \item Strips \code{scientificName} to binomial (removes subspecies /
#'     authorities) via \code{.strip_to_binomial()}
#'   \item Expands abbreviated binomials via the \code{abbreviation_inventory}
#'   \item Assigns \code{occurrenceID} as
#'     \code{paste0(basename(pdf_path), "_row", seq)}
#'   \item Ensures all 21 canonical DwC columns are present (NA-filled if absent)
#'   \item Appends PDF-pipeline extra columns (\code{occurrenceStatus},
#'     \code{establishmentMeans}, \code{bibliographicCitation},
#'     \code{associatedReferences})
#'   \item Appends \code{organismQuantity} / \code{organismQuantityType} only
#'     when \code{observation_type == "prevalence_abundance"}
#' }
#'
#' @param raw_text Character string. Raw response from
#'   \code{call_api_pdf()}.  When chunked extraction was used, pass
#'   the concatenated responses as a single string before calling this function:
#'   \code{paste(responses, collapse = "\n")}.
#' @param extract_prompt A \code{pdf_extract_prompt} object from
#'   \code{build_pdf_extract_prompt()}.
#'
#' @return A tibble with Darwin Core columns. Returns \code{NULL} invisibly
#'   (with a warning) if parsing fails.
#'
#' @examples
#' \dontrun{
#' occurrences <- parse_pdf_extract_response(raw_text, extract_prompt)
#' }
#'
#' @export
parse_pdf_extract_response <- function(raw_text, extract_prompt) {

  stopifnot(is.character(raw_text), length(raw_text) == 1L)
  stopifnot(inherits(extract_prompt, "pdf_extract_prompt"))

  pdf_structure         <- extract_prompt$pdf_structure
  abbreviation_inventory <- extract_prompt$abbreviation_inventory

  # Retrieve pdf_path from structure for occurrenceID construction
  pdf_path <- pdf_structure$pdf_path %||% "unknown_pdf"

  obs <- pdf_structure$observation_type %||% "field_survey"

  # Parse CSV
  df <- tryCatch(
    .parse_dwc_csv(raw_text),
    error = function(e) {
      warning(sprintf(
        "parse_pdf_extract_response: CSV parse failed for '%s'.\n  %s",
        basename(pdf_path), conditionMessage(e)
      ), call. = FALSE)
      return(NULL)
    }
  )
  if (is.null(df)) return(invisible(NULL))
  if (nrow(df) == 0L) {
    warning(sprintf(
      "parse_pdf_extract_response: zero rows extracted from '%s'.",
      basename(pdf_path)
    ), call. = FALSE)
    return(invisible(NULL))
  }

  # --- scientificName: expand abbreviations then strip to binomial ---
  if ("scientificName" %in% names(df)) {
    df$scientificName <- .expand_abbreviated_names(
      df$scientificName, abbreviation_inventory
    )
    df$scientificName <- .strip_to_binomial(df$scientificName)
  }

  # --- Coerce numeric / integer columns ---
  for (col in c("decimalLatitude", "decimalLongitude",
                "coordinateUncertaintyInMeters")) {
    if (col %in% names(df)) {
      df[[col]] <- .coerce_numeric_col(df[[col]], col)
    }
  }
  for (col in c("year", "month", "day", "individualCount")) {
    if (col %in% names(df)) {
      df[[col]] <- .coerce_integer_col(df[[col]], col)
    }
  }
  if ("organismQuantity" %in% names(df)) {
    df$organismQuantity <- .coerce_numeric_col(df$organismQuantity,
                                               "organismQuantity")
  }

  # --- Assign occurrenceID ---
  df$occurrenceID <- paste0(basename(pdf_path), "_row", seq_len(nrow(df)))

  # --- Assign fixed PDF-pipeline columns ---
  df$datasetID        <- pdf_path
  df$institutionCode  <- NA_character_
  df$basisOfRecord    <- ifelse(
    "basisOfRecord" %in% names(df) & !is.na(df$basisOfRecord),
    df$basisOfRecord, "HumanObservation"
  )
  df$genus           <- NA_character_
  df$family          <- NA_character_
  df$specificEpithet <- NA_character_
  df$recordedBy      <- NA_character_

  # --- Ensure all 21 canonical DwC columns present ---
  for (col in .pdf_dwc_cols) {
    if (!col %in% names(df)) {
      # Determine NA type
      if (col %in% c("decimalLatitude", "decimalLongitude",
                     "coordinateUncertaintyInMeters")) {
        df[[col]] <- NA_real_
      } else if (col %in% c("year", "month", "day", "individualCount")) {
        df[[col]] <- NA_integer_
      } else {
        df[[col]] <- NA_character_
      }
    }
  }

  # --- Reorder to canonical DwC column order ---
  extra_names <- setdiff(names(df), .pdf_dwc_cols)
  df <- df[, c(.pdf_dwc_cols, extra_names), drop = FALSE]

  # --- Append PDF-pipeline extra columns (always present) ---
  for (col in .pdf_extra_cols) {
    if (!col %in% names(df)) {
      df[[col]] <- NA_character_
    }
  }
  # Ensure occurrenceStatus is "present" (LLM may have filled it)
  df$occurrenceStatus <- "present"

  # --- prevalence_abundance extras ---
  if (!is.na(obs) && obs == "prevalence_abundance") {
    for (col in .pdf_pa_cols) {
      if (!col %in% names(df)) {
        if (col == "organismQuantity") {
          df[[col]] <- NA_real_
        } else {
          df[[col]] <- NA_character_
        }
      }
    }
  } else {
    # Remove any LLM-generated PA columns for non-PA papers
    df <- df[, setdiff(names(df), .pdf_pa_cols), drop = FALSE]
  }

  # Final reorder: canonical + extra + (PA if applicable)
  final_cols <- c(
    .pdf_dwc_cols,
    .pdf_extra_cols,
    if (!is.na(obs) && obs == "prevalence_abundance") .pdf_pa_cols else character(0L),
    setdiff(names(df), c(.pdf_dwc_cols, .pdf_extra_cols, .pdf_pa_cols))
  )
  df <- df[, final_cols[final_cols %in% names(df)], drop = FALSE]

  tibble::as_tibble(df)
}
