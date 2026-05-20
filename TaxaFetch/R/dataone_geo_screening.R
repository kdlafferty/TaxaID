# ==============================================================================
# dataone_geo_screening.R
# TaxaFetch -- LLM-based geographic screening for DataONE / PASTA datasets
#
# Exported functions:
#   build_geo_prompt()                  Build geo_prompt S3 object for LLM screening
#   parse_geo_screening_response()      Parse YES/NO LLM response -> candidate tibble
#
# Internal helpers (@noRd):
#   .scope_shortcut()                   Pre-accept/reject scopes via user-supplied lookup
#   .build_geo_prompt_single()          Build one prompt string for a chunk
#
# Workflow mirror (identical pattern to habitat assignment):
#
#   catalog    <- harvest_dataone_catalog(cache_file = "pasta_catalog.rds")
#   geo_prompt <- build_geo_prompt(catalog, bbox)
#
#   # Path 1 -- Anthropic API:
#   llm_output <- prompt_api(geo_prompt)
#
#   # Path 3 -- manual:
#   info       <- prompt_manual(geo_prompt, out_dir = "geo_screening",
#                               prefix = "geo")
#   llm_output <- read_llm_response(info$response_files)
#
#   candidates <- parse_geo_screening_response(llm_output, geo_prompt)
#
# ==============================================================================


# ==============================================================================
# build_geo_prompt()
# ==============================================================================

#' Build a Geographic Screening Prompt for DataONE Datasets
#'
#' Takes the full PASTA catalog (from \code{\link{harvest_dataone_catalog}})
#' and a target bounding box, optionally applies a user-supplied scope shortcut
#' to pre-accept or pre-reject whole dataset scopes without an LLM call,
#' deduplicates \code{geographicdescription} values, and builds one or more
#' LLM prompt strings asking whether each description falls within the bbox.
#'
#' Returns a \code{geo_prompt} S3 object (also inheriting \code{llm_prompt})
#' that can be passed directly to \code{\link[TaxaTools]{prompt_api}} or
#' \code{\link[TaxaTools]{prompt_manual}}.
#'
#' @param catalog A tibble from \code{\link{harvest_dataone_catalog}}.
#' @param bbox Numeric vector of length 4: \code{c(west, east, south, north)}
#'   in decimal degrees. Western longitudes should be negative.
#' @param scope_lookup A \code{data.frame} with columns \code{scope},
#'   \code{west}, \code{east}, \code{south}, \code{north}, and optionally
#'   \code{label}. Each row defines a dataset scope prefix (e.g.
#'   \code{"knb-lter-sbc"}) and its bounding box. Packages whose scope starts
#'   with a listed prefix are pre-accepted (bbox overlaps) or pre-rejected
#'   (no overlap) without an LLM call. Default \code{NULL} sends all packages
#'   to the LLM. Use this to save tokens when you know which scopes are
#'   relevant. Example:
#'   \preformatted{
#'   scope_lookup = data.frame(
#'     scope = c("knb-lter-fce", "knb-lter-gce"),
#'     west  = c(-81.2, -82.0),
#'     east  = c(-80.4, -80.0),
#'     south = c(25.1,  30.5),
#'     north = c(25.8,  32.5),
#'     label = c("FCE LTER", "GCE LTER")
#'   )}
#' @param chunk_size Integer. Maximum descriptions per prompt chunk.
#'   Default \code{80L}.
#' @param verbose Logical. Report shortcut and dedup statistics. Default
#'   \code{TRUE}.
#'
#' @return An object of classes \code{c("geo_prompt", "llm_prompt")}, a
#'   named list with elements:
#'   \describe{
#'     \item{prompts}{List of prompt strings, one per chunk.}
#'     \item{chunks}{List of character vectors of descriptions, one per chunk.}
#'     \item{n_chunks}{Integer.}
#'     \item{n_items}{Integer. Number of unique descriptions sent to the LLM.}
#'     \item{descriptions}{Character vector. All unique descriptions submitted
#'       (in order matching the LLM index column).}
#'     \item{desc_to_ids}{Named list. Keys are descriptions, values are
#'       character vectors of dataset IDs that share that description.}
#'     \item{shortcut_accepted}{Character vector of dataset IDs pre-accepted
#'       via scope shortcut (bbox overlap confirmed without LLM).}
#'     \item{shortcut_rejected}{Character vector of dataset IDs pre-rejected
#'       via scope shortcut (bbox overlap impossible without LLM).}
#'     \item{catalog}{The full input catalog, for joining results back.}
#'     \item{bbox}{The input bbox.}
#'   }
#'
#' @details
#' \strong{Scope shortcut:} When \code{scope_lookup} is supplied, packages
#' whose \code{scope} column starts with a listed prefix are pre-decided by
#' comparing the scope's known bounding box against the query bbox. This avoids
#' LLM calls for scopes you already know are in or out of range. The shortcut
#' is entirely user-controlled -- no geographic knowledge is hardcoded in the
#' package.
#'
#' \strong{Deduplication:} Many datasets share identical
#' \code{geographicdescription} values. Deduplication means the LLM sees each
#' unique description exactly once; \code{parse_geo_screening_response} then
#' fans the result back to all datasets sharing that description.
#'
#' \strong{NA descriptions:} Datasets with \code{NA} or blank
#' \code{geographicdescription} are excluded from LLM screening and recorded
#' in \code{$shortcut_rejected}.
#'
#' @seealso \code{\link{harvest_dataone_catalog}},
#'   \code{\link{parse_geo_screening_response}},
#'   \code{\link[TaxaTools]{prompt_api}}, \code{\link[TaxaTools]{prompt_manual}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' catalog    <- harvest_dataone_catalog()
#' bbox       <- c(-81.2, -80.4, 25.1, 25.8)  # Florida Everglades
#'
#' # Without shortcut -- all packages go to LLM:
#' geo_prompt <- build_geo_prompt(catalog, bbox)
#'
#' # With shortcut -- FCE packages pre-decided, others go to LLM:
#' geo_prompt <- build_geo_prompt(
#'   catalog,
#'   bbox,
#'   scope_lookup = data.frame(
#'     scope = "knb-lter-fce",
#'     west = -81.2, east = -80.4, south = 25.1, north = 25.8,
#'     label = "FCE LTER"
#'   )
#' )
#' print(geo_prompt)
#' }

build_geo_prompt <- function(catalog,
                             bbox,
                             scope_lookup = NULL,
                             chunk_size   = 80L,
                             verbose      = TRUE) {

  # ---- input checks ----------------------------------------------------------
  if (!is.data.frame(catalog)) {
    stop("build_geo_prompt: 'catalog' must be a dataframe from harvest_dataone_catalog().")
  }
  required_cols <- c("id", "scope", "geographicdescription", "is_candidate")
  missing_cols  <- setdiff(required_cols, names(catalog))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "build_geo_prompt: catalog missing required columns: %s.\nRun harvest_dataone_catalog() to produce a valid catalog.",
      paste(missing_cols, collapse = ", ")
    ))
  }
  if (!is.numeric(bbox) || length(bbox) != 4L ||
      any(is.na(bbox)) || any(!is.finite(bbox))) {
    stop("build_geo_prompt: 'bbox' must be a finite numeric vector of length 4: c(west, east, south, north).")
  }
  if (bbox[1] >= bbox[2]) stop("build_geo_prompt: west must be less than east.")
  if (bbox[3] >= bbox[4]) stop("build_geo_prompt: south must be less than north.")
  if (!is.null(scope_lookup)) {
    if (!is.data.frame(scope_lookup)) {
      stop("build_geo_prompt: 'scope_lookup' must be a data.frame or NULL.")
    }
    required_sl <- c("scope", "west", "east", "south", "north")
    missing_sl  <- setdiff(required_sl, names(scope_lookup))
    if (length(missing_sl) > 0L) {
      stop(sprintf(
        "build_geo_prompt: 'scope_lookup' missing required columns: %s.",
        paste(missing_sl, collapse = ", ")
      ))
    }
  }

  # ---- candidates only -------------------------------------------------------
  cands <- catalog[catalog$is_candidate, ]
  if (verbose) {
    message(sprintf(
      "build_geo_prompt: %d candidate packages (of %d total)",
      nrow(cands), nrow(catalog)
    ))
  }

  # ---- scope shortcut --------------------------------------------------------
  shortcut_result <- .scope_shortcut(cands, bbox, scope_lookup, verbose = verbose)
  undecided       <- shortcut_result$undecided   # rows not resolved by shortcut

  # ---- NA / blank description exclusion -------------------------------------
  has_desc        <- !is.na(undecided$geographicdescription) &
                     nzchar(trimws(undecided$geographicdescription))
  no_desc_ids     <- undecided$id[!has_desc]
  undecided       <- undecided[has_desc, ]

  if (verbose && length(no_desc_ids) > 0L) {
    message(sprintf(
      "build_geo_prompt: %d package(s) have no geographicdescription -- excluded from LLM screening",
      length(no_desc_ids)
    ))
  }

  # ---- deduplication ---------------------------------------------------------
  desc_vec    <- trimws(undecided$geographicdescription)
  unique_desc <- unique(desc_vec)

  # Build description -> dataset IDs mapping
  desc_to_ids <- lapply(unique_desc, function(d) undecided$id[desc_vec == d])
  names(desc_to_ids) <- unique_desc

  if (verbose) {
    message(sprintf(
      "build_geo_prompt: %d packages -> %d unique descriptions for LLM screening",
      nrow(undecided), length(unique_desc)
    ))
  }

  # ---- chunk and build prompts -----------------------------------------------
  chunk_size  <- as.integer(chunk_size)
  # Assign a 1-based index to each unique description (used as LLM CSV key)
  desc_index  <- seq_along(unique_desc)
  chunks      <- split(desc_index, ceiling(desc_index / chunk_size))
  n_chunks    <- length(chunks)

  prompts <- lapply(chunks, function(idx) {
    .build_geo_prompt_single(
      descriptions = unique_desc[idx],
      indices      = idx,
      bbox         = bbox
    )
  })

  # Reconstruct chunk character vectors (descriptions, not indices, for
  # consistency with habitat_prompt$chunks which holds taxa per chunk)
  chunk_descs <- lapply(chunks, function(idx) unique_desc[idx])

  structure(
    list(
      prompts            = prompts,
      chunks             = chunk_descs,
      n_chunks           = n_chunks,
      n_items            = length(unique_desc),
      descriptions       = unique_desc,
      desc_to_ids        = desc_to_ids,
      shortcut_accepted  = shortcut_result$accepted_ids,
      shortcut_rejected  = c(shortcut_result$rejected_ids, no_desc_ids),
      catalog            = catalog,
      bbox               = bbox
    ),
    class = c("geo_prompt", "llm_prompt")
  )
}


#' Print a geo_prompt Object
#'
#' @param x A \code{geo_prompt} object.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export

print.geo_prompt <- function(x, ...) {
  cat("<geo_prompt>\n")
  cat(sprintf("  Target bbox:        W=%.3f  E=%.3f  S=%.3f  N=%.3f\n",
              x$bbox[1], x$bbox[2], x$bbox[3], x$bbox[4]))
  if (length(x$shortcut_accepted) > 0L || length(x$shortcut_rejected) > 0L) {
    cat(sprintf("  Shortcut accepted:  %d packages\n", length(x$shortcut_accepted)))
    cat(sprintf("  Shortcut rejected:  %d packages\n", length(x$shortcut_rejected)))
  } else {
    cat("  Scope shortcut:     not used (scope_lookup = NULL)\n")
  }
  cat(sprintf("  Unique descriptions for LLM: %d\n", x$n_items))
  if (x$n_chunks == 1L) {
    cat(sprintf("  Chunks:             1 (chunk_size = %d)\n",
                length(x$descriptions)))
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
# parse_geo_screening_response()
# ==============================================================================

#' Parse an LLM Geographic Screening Response
#'
#' Parses the raw text returned by an LLM in response to a
#' \code{\link{build_geo_prompt}} prompt, fans YES/NO decisions back to all
#' datasets sharing each description, and returns a filtered tibble of
#' candidate datasets.
#'
#' @param raw_text Character. Length-1 string containing the LLM response
#'   (from \code{\link[TaxaTools]{prompt_api}} or
#'   \code{\link[TaxaTools]{read_llm_response}}).
#' @param geo_prompt A \code{geo_prompt} object from
#'   \code{\link{build_geo_prompt}}.
#'
#' @return A tibble with all columns from the input catalog plus:
#'   \describe{
#'     \item{geo_match}{Logical. \code{TRUE} = LLM said YES (or shortcut
#'       accepted); \code{FALSE} = LLM said NO (or shortcut rejected).}
#'     \item{geo_source}{Character. One of \code{"llm_yes"},
#'       \code{"llm_no"}, \code{"shortcut_accepted"},
#'       \code{"shortcut_rejected"}, \code{"no_description"},
#'       \code{"llm_no_response"}.}
#'   }
#'   The tibble includes ALL candidate packages -- filter on
#'   \code{geo_match == TRUE} to obtain the candidate list for
#'   \code{\link{screen_eml_columns}}.
#'
#' @details
#' \strong{Expected LLM output format:} A CSV with columns \code{index} and
#' \code{match}, where \code{index} is the integer row number from the prompt
#' and \code{match} is \code{YES} or \code{NO}. Markdown fences and preamble
#' text are stripped automatically.
#'
#' \strong{Shortcut packages} (pre-accepted or pre-rejected by
#' \code{\link{build_geo_prompt}}) are added back to the tibble automatically
#' with appropriate \code{geo_source} values.
#'
#' \strong{Non-candidate packages} (those where \code{is_candidate == FALSE}
#' in the catalog) are excluded from the return value -- use the original
#' catalog to recover them.
#'
#' @seealso \code{\link{build_geo_prompt}}, \code{\link[TaxaTools]{prompt_api}},
#'   \code{\link[TaxaTools]{read_llm_response}}, \code{\link{screen_eml_columns}}
#'
#' @importFrom dplyr tibble bind_rows left_join
#' @export
#'
#' @examples
#' \dontrun{
#' candidates <- parse_geo_screening_response(llm_output, geo_prompt)
#' accepted   <- candidates[candidates$geo_match, ]
#' nrow(accepted)
#' }

parse_geo_screening_response <- function(raw_text, geo_prompt) {

  if (!is.character(raw_text) || length(raw_text) != 1L) {
    stop("parse_geo_screening_response: 'raw_text' must be a length-1 character string.")
  }
  if (!inherits(geo_prompt, "geo_prompt")) {
    stop("parse_geo_screening_response: 'geo_prompt' must be a geo_prompt object from build_geo_prompt().")
  }

  # ---- parse LLM CSV ---------------------------------------------------------
  txt   <- gsub("```[a-zA-Z]*\n?", "", raw_text)
  txt   <- gsub("```", "", txt)
  lines <- trimws(strsplit(txt, "\n")[[1]])

  # Find first header row, then strip ALL duplicate header lines that
  # .combine_chunk_responses() leaves behind (it only knows habitat headers,
  # not index,match headers from geo responses).
  is_header_line <- grepl("\\bindex\\b", lines, ignore.case = TRUE) &
                    grepl("\\bmatch\\b",  lines, ignore.case = TRUE)
  header_idx     <- which(is_header_line)[1]

  llm_decisions <- if (!is.na(header_idx)) {
    data_lines <- lines[header_idx:length(lines)]
    data_lines <- data_lines[nzchar(data_lines)]
    # Remove duplicate header rows from chunks 2+ (keep only the first)
    is_dup_header <- grepl("\\bindex\\b", data_lines, ignore.case = TRUE) &
                     grepl("\\bmatch\\b",  data_lines, ignore.case = TRUE)
    is_dup_header[1] <- FALSE   # keep the first header
    data_lines <- data_lines[!is_dup_header]
    parsed <- tryCatch(
      utils::read.csv(text = paste(data_lines, collapse = "\n"),
                      stringsAsFactors = FALSE, strip.white = TRUE),
      error = function(e) NULL
    )
    if (!is.null(parsed) && all(c("index", "match") %in% tolower(names(parsed)))) {
      # Normalise column names
      names(parsed) <- tolower(names(parsed))
      parsed$match  <- toupper(trimws(parsed$match))
      parsed
    } else {
      warning(
        "parse_geo_screening_response: could not parse LLM response as index,match CSV.\n",
        "Raw response:\n", raw_text,
        call. = FALSE
      )
      NULL
    }
  } else {
    warning(
      "parse_geo_screening_response: 'index' and 'match' columns not found in LLM response.\n",
      "Raw response:\n", raw_text,
      call. = FALSE
    )
    NULL
  }

  # ---- build description-level decision lookup -------------------------------
  descriptions <- geo_prompt$descriptions   # ordered same as LLM indices

  # Default all to no_response
  desc_match  <- rep(FALSE,              length(descriptions))
  desc_source <- rep("llm_no_response",  length(descriptions))

  if (!is.null(llm_decisions)) {
    for (i in seq_len(nrow(llm_decisions))) {
      idx <- llm_decisions$index[i]
      if (!is.na(idx) && idx >= 1L && idx <= length(descriptions)) {
        if (llm_decisions$match[i] == "YES") {
          desc_match[idx]  <- TRUE
          desc_source[idx] <- "llm_yes"
        } else {
          desc_match[idx]  <- FALSE
          desc_source[idx] <- "llm_no"
        }
      }
    }
  }

  # ---- fan decisions back to dataset IDs ------------------------------------
  desc_to_ids  <- geo_prompt$desc_to_ids
  id_rows      <- vector("list", length(descriptions))

  for (i in seq_along(descriptions)) {
    d   <- descriptions[i]
    ids <- desc_to_ids[[d]]
    id_rows[[i]] <- dplyr::tibble(
      id         = ids,
      geo_match  = desc_match[i],
      geo_source = desc_source[i]
    )
  }

  llm_result <- dplyr::bind_rows(id_rows)

  # ---- add shortcut results -------------------------------------------------
  shortcut_rows <- dplyr::bind_rows(
    if (length(geo_prompt$shortcut_accepted) > 0L) {
      dplyr::tibble(id         = geo_prompt$shortcut_accepted,
                    geo_match  = TRUE,
                    geo_source = "shortcut_accepted")
    },
    if (length(geo_prompt$shortcut_rejected) > 0L) {
      dplyr::tibble(id         = geo_prompt$shortcut_rejected,
                    geo_match  = FALSE,
                    geo_source = "shortcut_rejected")
    }
  )

  all_decisions <- dplyr::bind_rows(llm_result, shortcut_rows)

  # ---- join back to catalog -------------------------------------------------
  catalog_cands <- geo_prompt$catalog[geo_prompt$catalog$is_candidate, ]
  result <- dplyr::left_join(catalog_cands, all_decisions, by = "id")

  # Rows with no decision (e.g. no description, or LLM missed them)
  result$geo_match[is.na(result$geo_match)]   <- FALSE
  result$geo_source[is.na(result$geo_source)] <- "llm_no_response"

  # Warn on missed indices
  n_no_response <- sum(result$geo_source == "llm_no_response")
  if (n_no_response > 0L) {
    warning(sprintf(
      "parse_geo_screening_response: %d package(s) received no LLM decision (geo_source = 'llm_no_response') -- treated as rejected.",
      n_no_response
    ), call. = FALSE)
  }

  dplyr::as_tibble(result)
}


# ==============================================================================
# Internal: scope shortcut
# ==============================================================================

#' Apply scope shortcut: pre-accept/reject by user-supplied scope bbox table
#'
#' @param cands Candidate rows from catalog (is_candidate == TRUE).
#' @param bbox Query bbox c(west, east, south, north).
#' @param scope_lookup data.frame with columns scope, west, east, south, north,
#'   and optionally label. NULL means no shortcut -- all packages are undecided.
#' @param verbose Logical.
#'
#' Returns list with $accepted_ids, $rejected_ids, $undecided (tibble rows
#' not resolved by the shortcut).
#' @noRd
.scope_shortcut <- function(cands, bbox, scope_lookup, verbose) {

  accepted_ids  <- character(0)
  rejected_ids  <- character(0)
  undecided_idx <- rep(TRUE, nrow(cands))

  if (is.null(scope_lookup) || nrow(scope_lookup) == 0L) {
    return(list(accepted_ids = accepted_ids,
                rejected_ids = rejected_ids,
                undecided    = cands))
  }

  for (i in seq_len(nrow(scope_lookup))) {
    row      <- scope_lookup[i, ]
    prefix   <- as.character(row$scope)
    label    <- if ("label" %in% names(row) && !is.na(row$label))
                  as.character(row$label) else prefix
    site_bbox <- c(as.numeric(row$west),  as.numeric(row$east),
                   as.numeric(row$south), as.numeric(row$north))

    in_scope <- startsWith(cands$scope, prefix)
    if (!any(in_scope)) next

    # Axis-aligned bbox overlap test
    overlaps <- !(site_bbox[2] < bbox[1] |   # site east  < query west
                  site_bbox[1] > bbox[2] |   # site west  > query east
                  site_bbox[4] < bbox[3] |   # site north < query south
                  site_bbox[3] > bbox[4])    # site south > query north

    ids_in_scope <- cands$id[in_scope]

    if (overlaps) {
      accepted_ids              <- c(accepted_ids, ids_in_scope)
      undecided_idx[in_scope]  <- FALSE
      if (verbose) {
        message(sprintf("  Shortcut ACCEPT (%d): %s",
                        length(ids_in_scope), label))
      }
    } else {
      rejected_ids              <- c(rejected_ids, ids_in_scope)
      undecided_idx[in_scope]  <- FALSE
      if (verbose) {
        message(sprintf("  Shortcut REJECT (%d): %s -- outside query bbox",
                        length(ids_in_scope), label))
      }
    }
  }

  list(
    accepted_ids = accepted_ids,
    rejected_ids = rejected_ids,
    undecided    = cands[undecided_idx, ]
  )
}


# ==============================================================================
# Internal: build one geo screening prompt string
# ==============================================================================

#' Build one geo screening prompt string for a chunk of descriptions
#'
#' @param descriptions Character vector of unique geographicdescription values.
#' @param indices Integer vector of 1-based indices (for the LLM CSV response).
#' @param bbox Numeric vector c(west, east, south, north).
#' @noRd
.build_geo_prompt_single <- function(descriptions, indices, bbox) {

  desc_block <- paste(
    sprintf("%d,%s", indices, gsub(",", ";", trimws(descriptions))),
    collapse = "\n"
  )

  paste0(
    "You are a geographic data analyst.\n\n",
    "I will provide a list of dataset geographic descriptions and a target ",
    "bounding box. For each description, determine whether the described ",
    "location could plausibly overlap with the target bounding box.\n\n",
    "TARGET BOUNDING BOX:\n",
    sprintf("  West:  %.4f\n", bbox[1]),
    sprintf("  East:  %.4f\n", bbox[2]),
    sprintf("  South: %.4f\n", bbox[3]),
    sprintf("  North: %.4f\n\n", bbox[4]),
    "RULES:\n",
    "1. Answer YES if the description could plausibly refer to a location ",
    "within or overlapping the bounding box above.\n",
    "2. Answer NO if the description clearly refers to a location outside ",
    "the bounding box, or if it is so vague as to be geographically ",
    "uninformative (e.g. 'United States', 'global', 'various locations').\n",
    "3. When in doubt, answer YES -- false positives are less harmful than ",
    "false negatives.\n",
    "4. Treat commas inside descriptions as part of the text (the list is ",
    "newline-delimited, not comma-delimited).\n",
    "5. OUTPUT FORMAT: Return ONLY a raw CSV block. Do not use Markdown ",
    "code fences. Do not include any preamble or closing text. ",
    "The first line must be the header row.\n\n",
    "REQUIRED COLUMNS (in this order): index, match\n",
    "  index = the integer from the left column below\n",
    "  match = YES or NO\n\n",
    "DATASET DESCRIPTIONS:\n",
    "(format: index,description)\n",
    desc_block, "\n"
  )
}
