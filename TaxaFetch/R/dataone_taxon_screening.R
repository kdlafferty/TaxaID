# ==============================================================================
# dataone_taxon_screening.R
# TaxaFetch -- LLM-based taxonomic screening for DataONE / PASTA datasets
#
# Exported functions:
#   build_taxon_screen_prompt()         Build taxon_prompt S3 object for LLM screening
#   parse_taxon_screening_response()    Parse YES/NO LLM response -> screened tibble
#
# Internal helpers (@noRd):
#   .build_taxon_prompt_single()        Build one prompt string for a chunk
#
# Intended position in pipeline (after geographic screening):
#
#   geo_screened   <- parse_geo_screening_response(llm_raw, geo_prompt)
#   accepted_geo   <- geo_screened[geo_screened$geo_match, ]
#
#   taxon_prompt   <- build_taxon_screen_prompt(
#                       catalog     = accepted_geo,
#                       taxon_scope = "marine fish",
#                       chunk_size  = 50L
#                     )
#   print(taxon_prompt)
#   cat(taxon_prompt$prompts[[1]])     # inspect first chunk
#
#   # Path 1 -- Anthropic API:
#   llm_raw2       <- prompt_api(taxon_prompt)
#
#   # Path 3 -- manual:
#   info           <- prompt_manual(taxon_prompt, out_dir = "taxon_screening",
#                                   prefix = "taxon")
#   llm_raw2       <- read_llm_response(info$response_files)
#
#   taxon_screened <- parse_taxon_screening_response(llm_raw2, taxon_prompt)
#   accepted       <- taxon_screened[taxon_screened$taxon_match, ]
#
# ==============================================================================


# ==============================================================================
# build_taxon_screen_prompt()
# ==============================================================================

#' Build a Taxonomic Screening Prompt for DataONE Datasets
#'
#' Takes a geo-screened candidate tibble (or any catalog subset) and a plain-
#' language description of the target taxonomic group, and builds one or more
#' LLM prompt strings asking whether each dataset plausibly contains records
#' for that group.
#'
#' The LLM is given each dataset's \code{title}, \code{abstract} (truncated),
#' and \code{keywords} as evidence. Datasets with none of these fields
#' populated are excluded from LLM screening and flagged in
#' \code{$skipped_ids}.
#'
#' Returns a \code{taxon_prompt} S3 object (also inheriting \code{llm_prompt})
#' that can be passed directly to \code{\link[TaxaTools]{prompt_api}} or
#' \code{\link[TaxaTools]{prompt_manual}}.
#'
#' @param catalog A tibble of candidate datasets -- typically the output of
#'   \code{\link{parse_geo_screening_response}} filtered to
#'   \code{geo_match == TRUE}, or any subset of the full catalog produced by
#'   \code{\link{harvest_dataone_catalog}}. Must contain columns \code{id} and
#'   at least one of \code{title}, \code{abstract}, \code{keywords}.
#' @param taxon_scope Character string (length 1). Plain-language description
#'   of the target taxonomic group. Can be a common name, formal taxon name,
#'   or a short phrase, e.g. \code{"marine fish"}, \code{"Actinopterygii"},
#'   \code{"marine invertebrates"}, \code{"vascular plants"}, \code{"birds"}.
#'   The LLM will interpret this description and apply it to the dataset
#'   metadata.
#' @param chunk_size Integer. Maximum datasets per prompt chunk. Default
#'   \code{50L}. Smaller than the geo prompt default because title + abstract
#'   text is longer than geographic descriptions.
#' @param abstract_chars Integer. Maximum characters from the abstract to
#'   include per dataset. Default \code{300L}. Set to \code{0L} to omit
#'   abstracts entirely (faster, less accurate).
#' @param geo_scope Character string (length 1) or \code{NULL} (default).
#'   When supplied, the prompt additionally asks the LLM to assess geographic
#'   relevance, and \code{\link{parse_taxon_screening_response}} returns a
#'   \code{geo_match} column alongside \code{taxon_match}.  Use this for
#'   literature catalogs (e.g. from \code{\link{search_literature}}) where
#'   \code{\link{build_geo_prompt}} cannot be used because the catalog lacks
#'   DataONE-specific columns.  Example: \code{"Santa Barbara Channel,
#'   southern California coastal waters"}.  Leave \code{NULL} for the DataONE
#'   path.
#' @param verbose Logical. Report dataset counts and skipped entries. Default
#'   \code{TRUE}.
#'
#' @return An object of classes \code{c("taxon_prompt", "llm_prompt")}, a
#'   named list with elements:
#'   \describe{
#'     \item{prompts}{List of prompt strings, one per chunk.}
#'     \item{chunks}{List of character vectors of dataset IDs, one per chunk.}
#'     \item{n_chunks}{Integer.}
#'     \item{n_items}{Integer. Number of datasets submitted to the LLM.}
#'     \item{ids}{Character vector. All dataset IDs submitted (in order
#'       matching the LLM index column).}
#'     \item{skipped_ids}{Character vector. Dataset IDs excluded because
#'       title, abstract, and keywords are all missing.}
#'     \item{taxon_scope}{The \code{taxon_scope} string as supplied.}
#'     \item{geo_scope}{The \code{geo_scope} string, or \code{NULL}.}
#'     \item{catalog}{The input catalog, for joining results back.}
#'   }
#'
#' @details
#' \strong{Evidence used:} The prompt includes \code{title}, truncated
#' \code{abstract}, and \code{keywords} for each dataset. This is more
#' informative than \code{geographicdescription} alone for taxonomic
#' inference. Column names are matched case-insensitively; missing columns
#' are silently treated as blank.
#'
#' \strong{Bias towards inclusion:} As with geographic screening, the prompt
#' instructs the LLM to answer YES when uncertain. The intent is to avoid
#' discarding datasets that have relevant records but vague metadata -- the
#' EML screening and preview stages downstream will apply stricter filters.
#'
#' \strong{No deduplication:} Unlike geographic screening, title + abstract
#' content is usually unique per dataset, so deduplication is not applied.
#'
#' @seealso \code{\link{parse_taxon_screening_response}},
#'   \code{\link{build_geo_prompt}}, \code{\link[TaxaTools]{prompt_api}},
#'   \code{\link[TaxaTools]{prompt_manual}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' geo_screened   <- parse_geo_screening_response(llm_raw, geo_prompt)
#' accepted_geo   <- geo_screened[geo_screened$geo_match, ]
#' taxon_prompt   <- build_taxon_screen_prompt(accepted_geo, "marine fish")
#' print(taxon_prompt)
#' cat(taxon_prompt$prompts[[1]])
#' }

build_taxon_screen_prompt <- function(catalog,
                                      taxon_scope,
                                      geo_scope      = NULL,
                                      chunk_size     = 50L,
                                      abstract_chars = 300L,
                                      verbose        = TRUE) {

  # ---- input checks ----------------------------------------------------------
  if (!is.data.frame(catalog)) {
    stop("build_taxon_screen_prompt: 'catalog' must be a dataframe.")
  }
  if (!"id" %in% names(catalog)) {
    stop("build_taxon_screen_prompt: 'catalog' must contain an 'id' column.")
  }
  if (!is.character(taxon_scope) || length(taxon_scope) != 1L ||
      is.na(taxon_scope) || !nzchar(trimws(taxon_scope))) {
    stop("build_taxon_screen_prompt: 'taxon_scope' must be a non-empty character string.")
  }
  if (!is.null(geo_scope)) {
    if (!is.character(geo_scope) || length(geo_scope) != 1L ||
        is.na(geo_scope) || !nzchar(trimws(geo_scope))) {
      stop("build_taxon_screen_prompt: 'geo_scope' must be a non-empty character string or NULL.")
    }
    geo_scope <- trimws(geo_scope)
  }
  chunk_size     <- as.integer(chunk_size)
  abstract_chars <- as.integer(abstract_chars)
  if (!is.logical(verbose) || length(verbose) != 1L || is.na(verbose)) {
    stop("build_taxon_screen_prompt: 'verbose' must be TRUE or FALSE.")
  }

  taxon_scope <- trimws(taxon_scope)

  if (verbose) {
    message(sprintf(
      "build_taxon_screen_prompt: %d datasets to screen for '%s'",
      nrow(catalog), taxon_scope
    ))
  }

  # ---- locate text columns (case-insensitive) --------------------------------
  col_lower <- tolower(names(catalog))

  get_col <- function(df, target) {
    idx <- match(target, tolower(names(df)))
    if (is.na(idx)) rep(NA_character_, nrow(df)) else as.character(df[[idx]])
  }

  expected_text <- c("title", "abstract", "keywords")
  found_text <- expected_text[expected_text %in% col_lower]
  missing_text <- setdiff(expected_text, col_lower)
  if (length(missing_text) > 0L && verbose) {
    message(sprintf(
      "build_taxon_screen_prompt: text column(s) not found in catalog: %s",
      paste(missing_text, collapse = ", ")
    ))
  }
  if (length(found_text) == 0L) {
    stop("build_taxon_screen_prompt: catalog has none of the expected text columns ",
         "(title, abstract, keywords) -- cannot build prompt.")
  }

  titles    <- get_col(catalog, "title")
  abstracts <- get_col(catalog, "abstract")
  keywords  <- get_col(catalog, "keywords")
  ids       <- catalog$id

  # ---- identify and skip datasets with no usable metadata --------------------
  has_text <- vapply(seq_len(nrow(catalog)), function(i) {
    !all(is.na(c(titles[i], abstracts[i], keywords[i])) |
           !nzchar(trimws(c(
             if (is.na(titles[i]))    "" else titles[i],
             if (is.na(abstracts[i])) "" else abstracts[i],
             if (is.na(keywords[i]))  "" else keywords[i]
           ))))
  }, logical(1L))

  skipped_ids <- ids[!has_text]
  keep        <- catalog[has_text, ]
  ids_keep    <- ids[has_text]

  if (verbose && length(skipped_ids) > 0L) {
    message(sprintf(
      "build_taxon_screen_prompt: %d dataset(s) skipped (no title, abstract, or keywords)",
      length(skipped_ids)
    ))
  }

  if (nrow(keep) == 0L) {
    stop("build_taxon_screen_prompt: no datasets have title, abstract, or keyword metadata -- cannot build prompt.")
  }

  # ---- refresh text vectors for kept rows ------------------------------------
  titles_k    <- get_col(keep, "title")
  abstracts_k <- get_col(keep, "abstract")
  keywords_k  <- get_col(keep, "keywords")

  # ---- truncate abstracts ----------------------------------------------------
  if (abstract_chars > 0L) {
    abstracts_k <- ifelse(
      !is.na(abstracts_k) & nchar(abstracts_k) > abstract_chars,
      paste0(substr(abstracts_k, 1L, abstract_chars), "..."),
      abstracts_k
    )
  } else {
    abstracts_k <- rep(NA_character_, length(abstracts_k))
  }

  # ---- chunk and build prompts -----------------------------------------------
  n_items  <- nrow(keep)
  indices  <- seq_len(n_items)
  chunks   <- split(indices, ceiling(indices / chunk_size))
  n_chunks <- length(chunks)

  prompts <- lapply(chunks, function(idx) {
    .build_taxon_prompt_single(
      ids        = ids_keep[idx],
      titles     = titles_k[idx],
      abstracts  = abstracts_k[idx],
      keywords   = keywords_k[idx],
      indices    = idx,
      taxon_scope = taxon_scope,
      geo_scope   = geo_scope
    )
  })

  chunk_ids <- lapply(chunks, function(idx) ids_keep[idx])

  if (verbose) {
    message(sprintf(
      "build_taxon_screen_prompt: %d dataset(s) -> %d chunk(s) for LLM screening",
      n_items, n_chunks
    ))
  }

  structure(
    list(
      prompts     = prompts,
      chunks      = chunk_ids,
      n_chunks    = n_chunks,
      n_items     = n_items,
      ids         = ids_keep,
      skipped_ids = skipped_ids,
      taxon_scope = taxon_scope,
      geo_scope   = geo_scope,
      catalog     = catalog
    ),
    class = c("taxon_prompt", "llm_prompt")
  )
}


#' Print a taxon_prompt Object
#'
#' @param x A \code{taxon_prompt} object.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export

print.taxon_prompt <- function(x, ...) {
  cat("<taxon_prompt>\n")
  cat(sprintf("  Taxon scope:        %s\n", x$taxon_scope))
  if (!is.null(x$geo_scope)) {
    cat(sprintf("  Geo scope:          %s\n", x$geo_scope))
  }
  cat(sprintf("  Datasets for LLM:   %d\n", x$n_items))
  if (length(x$skipped_ids) > 0L) {
    cat(sprintf("  Skipped (no text):  %d\n", length(x$skipped_ids)))
  }
  if (x$n_chunks == 1L) {
    cat(sprintf("  Chunks:             1 (chunk_size = %d)\n", x$n_items))
  } else {
    chunk_sizes <- vapply(x$chunks, length, integer(1L))
    cat(sprintf("  Chunks:             %d (sizes: %s)\n",
                x$n_chunks, paste(chunk_sizes, collapse = ", ")))
  }
  cat(sprintf("  Prompt tokens (approx): ~%d per chunk\n",
              nchar(x$prompts[[1]]) %/% 4L))
  invisible(x)
}


# ==============================================================================
# parse_taxon_screening_response()
# ==============================================================================

#' Parse an LLM Taxonomic Screening Response
#'
#' Parses the raw text returned by an LLM in response to a
#' \code{\link{build_taxon_screen_prompt}} prompt, matches YES/NO decisions
#' back to dataset IDs, and returns the input catalog annotated with
#' \code{taxon_match} and \code{taxon_source} columns.
#'
#' @param raw_text Character. Length-1 string containing the LLM response
#'   (from \code{\link[TaxaTools]{prompt_api}} or
#'   \code{\link[TaxaTools]{read_llm_response}}).
#' @param taxon_prompt A \code{taxon_prompt} object from
#'   \code{\link{build_taxon_screen_prompt}}.
#'
#' @return A tibble with all columns from the input catalog plus:
#'   \describe{
#'     \item{taxon_match}{Logical. \code{TRUE} = LLM said YES for taxon;
#'       \code{FALSE} = LLM said NO or no response received.}
#'     \item{taxon_source}{Character. One of \code{"llm_yes"},
#'       \code{"llm_no"}, \code{"skipped"} (no metadata available),
#'       \code{"llm_no_response"} (index missing from LLM output).}
#'     \item{geo_match}{Logical. Only present when \code{taxon_prompt} was
#'       built with a \code{geo_scope} argument. \code{TRUE} = LLM said YES
#'       for geographic relevance.}
#'   }
#'   Includes ALL input datasets -- filter on \code{taxon_match == TRUE} to
#'   obtain candidates for \code{\link{screen_eml_columns}}.
#'
#' @details
#' \strong{Expected LLM output format:} A CSV with columns \code{index} and
#' \code{match}, where \code{index} is the integer row number from the prompt
#' and \code{match} is \code{YES} or \code{NO}. Markdown fences and preamble
#' text are stripped automatically. Duplicate header rows from multi-chunk
#' responses are handled automatically.
#'
#' \strong{Skipped datasets} (those in \code{taxon_prompt$skipped_ids}) are
#' added back with \code{taxon_match = FALSE} and
#' \code{taxon_source = "skipped"}.
#'
#' @seealso \code{\link{build_taxon_screen_prompt}},
#'   \code{\link[TaxaTools]{prompt_api}}, \code{\link[TaxaTools]{read_llm_response}},
#'   \code{\link{screen_eml_columns}}
#'
#' @importFrom dplyr tibble bind_rows left_join as_tibble
#' @export
#'
#' @examples
#' \dontrun{
#' taxon_screened <- parse_taxon_screening_response(llm_raw2, taxon_prompt)
#' accepted       <- taxon_screened[taxon_screened$taxon_match, ]
#' nrow(accepted)
#' table(taxon_screened$taxon_source)
#' }

parse_taxon_screening_response <- function(raw_text, taxon_prompt) {

  if (!is.character(raw_text) || length(raw_text) != 1L) {
    stop("parse_taxon_screening_response: 'raw_text' must be a length-1 character string.")
  }
  if (!inherits(taxon_prompt, "taxon_prompt")) {
    stop("parse_taxon_screening_response: 'taxon_prompt' must be a taxon_prompt object from build_taxon_screen_prompt().")
  }

  # ---- strip markdown fences and parse CSV -----------------------------------
  txt   <- gsub("```[a-zA-Z]*\n?", "", raw_text)
  txt   <- gsub("```", "", txt)
  lines <- trimws(strsplit(txt, "\n")[[1]])

  combined_mode <- !is.null(taxon_prompt$geo_scope)

  # Header detection differs by mode:
  #   solo mode     : columns are  index, match
  #   combined mode : columns are  index, taxon_match, geo_match
  is_header_line <- if (combined_mode) {
    grepl("\\bindex\\b",       lines, ignore.case = TRUE) &
    grepl("\\btaxon_match\\b", lines, ignore.case = TRUE) &
    grepl("\\bgeo_match\\b",   lines, ignore.case = TRUE)
  } else {
    grepl("\\bindex\\b", lines, ignore.case = TRUE) &
    grepl("\\bmatch\\b",  lines, ignore.case = TRUE)
  }
  header_idx <- which(is_header_line)[1L]

  llm_decisions <- if (!is.na(header_idx)) {
    data_lines <- lines[header_idx:length(lines)]
    data_lines <- data_lines[nzchar(data_lines)]
    # Remove duplicate header rows from chunks 2+
    is_dup_header <- if (combined_mode) {
      grepl("\\bindex\\b",       data_lines, ignore.case = TRUE) &
      grepl("\\btaxon_match\\b", data_lines, ignore.case = TRUE)
    } else {
      grepl("\\bindex\\b", data_lines, ignore.case = TRUE) &
      grepl("\\bmatch\\b",  data_lines, ignore.case = TRUE)
    }
    is_dup_header[1L] <- FALSE
    data_lines <- data_lines[!is_dup_header]
    parsed <- tryCatch(
      utils::read.csv(text = paste(data_lines, collapse = "\n"),
                      stringsAsFactors = FALSE, strip.white = TRUE),
      error = function(e) NULL
    )
    if (combined_mode) {
      req_cols <- c("index", "taxon_match", "geo_match")
    } else {
      req_cols <- c("index", "match")
    }
    if (!is.null(parsed) && all(req_cols %in% tolower(names(parsed)))) {
      names(parsed) <- tolower(names(parsed))
      if (combined_mode) {
        parsed$taxon_match <- toupper(trimws(parsed$taxon_match))
        parsed$geo_match   <- toupper(trimws(parsed$geo_match))
      } else {
        parsed$match <- toupper(trimws(parsed$match))
      }
      parsed
    } else {
      warning(
        "parse_taxon_screening_response: could not parse LLM response as expected CSV.\n",
        "Raw response:\n", raw_text,
        call. = FALSE
      )
      NULL
    }
  } else {
    warning(
      "parse_taxon_screening_response: expected column names not found in LLM response.\n",
      "Raw response:\n", raw_text,
      call. = FALSE
    )
    NULL
  }

  # ---- build dataset-level decision lookup -----------------------------------
  ids_submitted <- taxon_prompt$ids
  n             <- length(ids_submitted)

  id_match     <- rep(FALSE,             n)
  id_geo_match <- rep(FALSE,             n)
  id_source    <- rep("llm_no_response", n)

  if (!is.null(llm_decisions)) {
    for (i in seq_len(nrow(llm_decisions))) {
      idx <- llm_decisions$index[i]
      if (!is.na(idx) && idx >= 1L && idx <= n) {
        if (combined_mode) {
          tm <- llm_decisions$taxon_match[i] == "YES"
          gm <- llm_decisions$geo_match[i]   == "YES"
          id_match[idx]     <- tm
          id_geo_match[idx] <- gm
          id_source[idx]    <- if (tm) "llm_yes" else "llm_no"
        } else {
          if (llm_decisions$match[i] == "YES") {
            id_match[idx]  <- TRUE
            id_source[idx] <- "llm_yes"
          } else {
            id_match[idx]  <- FALSE
            id_source[idx] <- "llm_no"
          }
        }
      }
    }
  }

  if (combined_mode) {
    llm_result <- dplyr::tibble(
      id           = ids_submitted,
      taxon_match  = id_match,
      geo_match    = id_geo_match,
      taxon_source = id_source
    )
  } else {
    llm_result <- dplyr::tibble(
      id           = ids_submitted,
      taxon_match  = id_match,
      taxon_source = id_source
    )
  }

  # ---- add skipped datasets --------------------------------------------------
  skipped_rows <- if (length(taxon_prompt$skipped_ids) > 0L) {
    if (combined_mode) {
      dplyr::tibble(
        id           = taxon_prompt$skipped_ids,
        taxon_match  = FALSE,
        geo_match    = FALSE,
        taxon_source = "skipped"
      )
    } else {
      dplyr::tibble(
        id           = taxon_prompt$skipped_ids,
        taxon_match  = FALSE,
        taxon_source = "skipped"
      )
    }
  } else {
    NULL
  }

  all_decisions <- dplyr::bind_rows(llm_result, skipped_rows)

  # ---- join back to input catalog --------------------------------------------
  # Drop any pre-existing screening columns from the catalog snapshot to
  # prevent .x/.y collision if search_literature() pre-populated them as NA
  # or if a previous failed parse partially wrote them.
  stale_cols <- intersect(
    names(taxon_prompt$catalog),
    c("taxon_match", "taxon_source", "geo_match")
  )
  catalog_clean <- if (length(stale_cols) > 0L) {
    taxon_prompt$catalog[, setdiff(names(taxon_prompt$catalog), stale_cols),
                         drop = FALSE]
  } else {
    taxon_prompt$catalog
  }

  result <- dplyr::left_join(catalog_clean, all_decisions, by = "id")

  # Guard: rows with no decision (shouldn't happen)
  result$taxon_match[is.na(result$taxon_match)] <- FALSE
  result$taxon_source[is.na(result$taxon_source)] <- "llm_no_response"
  if (combined_mode) {
    result$geo_match[is.na(result$geo_match)] <- FALSE
  }

  n_no_response <- sum(result$taxon_source == "llm_no_response")
  if (n_no_response > 0L) {
    warning(sprintf(
      "parse_taxon_screening_response: %d dataset(s) received no LLM decision (taxon_source = 'llm_no_response') -- treated as rejected.",
      n_no_response
    ), call. = FALSE)
  }

  dplyr::as_tibble(result)
}


# ==============================================================================
# Internal: build one taxon screening prompt string
# ==============================================================================

#' Build one taxonomic screening prompt string for a chunk of datasets
#'
#' @param ids Character vector of dataset IDs (for logging only; not in prompt).
#' @param titles Character vector of dataset titles (NA = blank).
#' @param abstracts Character vector of (truncated) abstracts (NA = blank).
#' @param keywords Character vector of keywords (NA = blank).
#' @param indices Integer vector of 1-based indices (for the LLM CSV response).
#' @param taxon_scope Character string describing the target taxonomic group.
#' @param geo_scope Character string describing the target geographic area, or
#'   NULL for taxon-only screening.
#' @noRd

.build_taxon_prompt_single <- function(ids, titles, abstracts, keywords,
                                       indices, taxon_scope, geo_scope = NULL) {

  fmt_field <- function(label, val) {
    if (is.na(val) || !nzchar(trimws(val))) return("")
    sprintf("  %s: %s", label, trimws(val))
  }

  dataset_block <- paste(
    vapply(seq_along(indices), function(i) {
      fields <- c(
        fmt_field("Title",    titles[i]),
        fmt_field("Abstract", abstracts[i]),
        fmt_field("Keywords", keywords[i])
      )
      fields <- fields[nzchar(fields)]
      paste0(
        sprintf("%d.", indices[i]),
        if (length(fields) == 0L) " (no metadata)" else paste0("\n", paste(fields, collapse = "\n"))
      )
    }, character(1L)),
    collapse = "\n\n"
  )

  if (is.null(geo_scope)) {
    # --- Solo mode: taxon only (DataONE path) ---
    paste0(
      "You are a taxonomic data analyst.\n\n",
      "I will provide metadata for a set of ecological datasets. For each ",
      "dataset, determine whether it plausibly contains occurrence or ",
      "abundance records for the following taxonomic group:\n\n",
      sprintf("  TARGET TAXONOMIC GROUP: %s\n\n", taxon_scope),
      "RULES:\n",
      "1. Answer YES if the dataset title, abstract, or keywords suggest it ",
      "contains or likely contains records of organisms in the target group.\n",
      "2. Answer NO if the dataset clearly focuses on a different taxonomic ",
      "group (e.g. birds, plants, bacteria) with no plausible overlap with ",
      "the target group.\n",
      "3. When in doubt, answer YES -- false positives are less harmful than ",
      "false negatives. A dataset on 'kelp forest community ecology' should ",
      "be YES for marine fish even if fish are not mentioned explicitly.\n",
      "4. Datasets on physical environment, water chemistry, or habitat ",
      "structure with no mention of organisms should be answered NO.\n",
      "5. OUTPUT FORMAT: Return ONLY a raw CSV block. Do not use Markdown ",
      "code fences. Do not include any preamble or closing text. ",
      "The first line must be the header row.\n\n",
      "REQUIRED COLUMNS (in this order): index, match\n",
      "  index = the integer from the numbered list below\n",
      "  match = YES or NO\n\n",
      "DATASETS:\n",
      dataset_block, "\n"
    )
  } else {
    # --- Combined mode: taxon + geo (literature path) ---
    paste0(
      "You are an ecological data analyst.\n\n",
      "I will provide metadata for a set of scientific papers. For each paper, ",
      "make two independent YES/NO assessments:\n\n",
      sprintf("  TARGET TAXONOMIC GROUP: %s\n", taxon_scope),
      sprintf("  TARGET GEOGRAPHIC AREA: %s\n\n", geo_scope),
      "TAXON RULES:\n",
      "1. taxon_match = YES if the paper plausibly contains occurrence or ",
      "abundance records for the target taxonomic group.\n",
      "2. taxon_match = YES when in doubt -- a paper on 'kelp forest community ",
      "ecology' is YES for marine fish even if fish are not mentioned explicitly.\n",
      "3. taxon_match = NO only if the paper clearly focuses on a completely ",
      "different group (e.g. vascular plants, birds) with no plausible overlap.\n\n",
      "GEOGRAPHY RULES:\n",
      "4. geo_match = YES if the paper's study area overlaps with or is contained ",
      "within the target geographic area.\n",
      "5. geo_match = YES when in doubt -- a paper on 'California coastal fish' ",
      "is YES for Santa Barbara Channel.\n",
      "6. geo_match = NO only if the paper clearly studies a different region ",
      "with no overlap (e.g. Atlantic species when target is Pacific).\n\n",
      "OUTPUT FORMAT: Return ONLY a raw CSV block. Do not use Markdown code ",
      "fences. Do not include any preamble or closing text. ",
      "The first line must be the header row.\n\n",
      "REQUIRED COLUMNS (in this order): index, taxon_match, geo_match\n",
      "  index       = the integer from the numbered list below\n",
      "  taxon_match = YES or NO\n",
      "  geo_match   = YES or NO\n\n",
      "PAPERS:\n",
      dataset_block, "\n"
    )
  }
}
