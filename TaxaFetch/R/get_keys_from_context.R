#' Fetch GBIF Taxon Keys Using Full Taxonomic Context
#'
#' Resolves a dataframe of scientific names to GBIF usage keys by supplying the
#' full taxonomic hierarchy (kingdom, phylum, class, etc.) as context to the
#' GBIF name backbone API. Providing hierarchy context prevents homonym errors
#' where identical names refer to different organisms in different kingdoms.
#'
#' @param hierarchy_df A dataframe. Each row is one taxon. Columns should be
#'   named for Linnaean ranks (case-insensitive): \code{kingdom},
#'   \code{phylum}, \code{class}, \code{order}, \code{family}, \code{genus},
#'   \code{species}. Not all ranks need to be present. For each row, the
#'   most specific rank provided is used as the lookup target; higher ranks
#'   are passed as disambiguation context.
#'
#' @return The input dataframe with three columns appended:
#'   \describe{
#'     \item{usageKey}{Integer. GBIF usage key for the matched name, or
#'       \code{NA} if no match was found.}
#'     \item{matchType}{Character. GBIF match quality: \code{"EXACT"},
#'       \code{"FUZZY"}, \code{"HIGHERRANK"}, \code{"NONE"},
#'       \code{"NO_DATA"} (no rank columns present in this row), or
#'       \code{"ERROR"} (API call failed).}
#'     \item{gbif_rank}{Character. The rank GBIF assigned to the matched
#'       record, or \code{NA} if no match.}
#'   }
#'
#' @details
#' \strong{Homonym prevention:} Many scientific names are valid in multiple
#' kingdoms (e.g., \emph{Alaria} is both a brown alga and a trematode worm).
#' Supplying the full hierarchy ensures GBIF resolves the name to the correct
#' lineage. Rows that provide only a species name with no higher-rank context
#' may return incorrect matches for homonyms.
#'
#' \strong{Target rank selection:} For each row the function identifies the
#' most specific non-empty rank (species > genus > family > order > class >
#' phylum > kingdom) and treats it as the lookup target. Column names are
#' matched case-insensitively, so \code{Kingdom}, \code{KINGDOM}, and
#' \code{kingdom} all work.
#'
#' \strong{Errors and missing matches:} API failures for individual rows
#' produce a warning and return \code{matchType = "ERROR"} for that row
#' rather than stopping the entire run. Review rows with
#' \code{matchType \%in\% c("NONE", "FUZZY", "ERROR")} before downstream use.
#'
#' \strong{rgbif:} This function requires the \code{rgbif} package, listed
#' under \code{Suggests} because it is only needed for the data-ingest
#' portion of the pipeline. Install with \code{install.packages("rgbif")}.
#'
#' @seealso \code{\link{fetch_gbif_occurrences}}, which accepts the
#'   \code{usageKey} column as its \code{keys} argument.
#'
#' @examples
#' \dontrun{
#' keys <- get_keys_from_context(hierarchy_df)
#' head(keys[, c("inputName", "usageKey", "matchType")])
#' }
#'
#' @importFrom dplyr bind_rows bind_cols
#' @export

get_keys_from_context <- function(hierarchy_df) {

  # --- Dependency check -------------------------------------------------------
  if (!requireNamespace("rgbif", quietly = TRUE)) {
    stop(
      "get_keys_from_context: package 'rgbif' is required.\n",
      "Install it with: install.packages('rgbif')"
    )
  }

  # --- Input checks -----------------------------------------------------------
  if (!is.data.frame(hierarchy_df)) {
    stop("get_keys_from_context: 'hierarchy_df' must be a dataframe.")
  }
  if (nrow(hierarchy_df) == 0) {
    stop("get_keys_from_context: 'hierarchy_df' has zero rows.")
  }

  valid_ranks <- c("kingdom", "phylum", "class", "order",
                   "family", "genus", "species")

  rank_cols_present <- names(hierarchy_df)[
    tolower(names(hierarchy_df)) %in% valid_ranks
  ]

  if (length(rank_cols_present) == 0) {
    stop(
      "get_keys_from_context: no rank columns found in 'hierarchy_df'.\n",
      "Expected column names (case-insensitive): ",
      paste(valid_ranks, collapse = ", ")
    )
  }

  ranks_not_found <- setdiff(valid_ranks, tolower(names(hierarchy_df)))
  if (length(ranks_not_found) > 0L) {
    warning(
      "get_keys_from_context: the following rank columns were not found in ",
      "'hierarchy_df' (case-insensitive): ",
      paste(ranks_not_found, collapse = ", "),
      ". Rows lacking all present rank values will return matchType = 'NO_DATA'.",
      call. = FALSE
    )
  }

  # --- Process each row -------------------------------------------------------
  message(sprintf(
    "get_keys_from_context: resolving %d taxon row(s) against GBIF backbone...",
    nrow(hierarchy_df)
  ))

  row_list <- split(hierarchy_df, seq_len(nrow(hierarchy_df)))

  results <- dplyr::bind_rows(
    lapply(row_list, .process_gbif_row, valid_ranks = valid_ranks)
  )

  message(sprintf(
    "get_keys_from_context: done. %d matched (%d EXACT, %d FUZZY, %d NONE/ERROR).",
    sum(!is.na(results$usageKey)),
    sum(results$matchType == "EXACT",  na.rm = TRUE),
    sum(results$matchType == "FUZZY",  na.rm = TRUE),
    sum(results$matchType %in% c("NONE", "NO_DATA", "ERROR"), na.rm = TRUE)
  ))

  dplyr::bind_cols(hierarchy_df, results)
}


# ------------------------------------------------------------------------------
# Internal helper -- not exported
# ------------------------------------------------------------------------------

#' Resolve one row of a hierarchy dataframe against the GBIF backbone
#'
#' @param row A one-row dataframe (one element from split(hierarchy_df, ...)).
#' @param valid_ranks Character vector of recognised rank names (lowercase).
#' @return A one-row dataframe with columns usageKey, matchType, gbif_rank.
#' @noRd

.process_gbif_row <- function(row, valid_ranks) {

  # Identify which rank columns are present in this row
  present_cols <- names(row)[tolower(names(row)) %in% valid_ranks]

  # Build a clean named list: lowercase rank -> trimmed value (omit NAs/blanks)
  rank_values <- list()
  for (col in present_cols) {
    val <- row[[col]]
    if (length(val) == 1 && !is.na(val) && nzchar(trimws(val))) {
      rank_values[[tolower(col)]] <- trimws(as.character(val))
    }
  }

  if (length(rank_values) == 0) {
    return(data.frame(usageKey = NA_integer_,
                      matchType = "NO_DATA",
                      gbif_rank = NA_character_,
                      stringsAsFactors = FALSE))
  }

  # Find the most specific rank present (species is most specific)
  rank_order  <- rev(valid_ranks)   # species first in search order
  target_rank <- NULL
  target_name <- NULL

  for (r in rank_order) {
    if (r %in% names(rank_values)) {
      target_rank <- r
      target_name <- rank_values[[r]]
      break
    }
  }

  # Build API call args: context is all ranks except the target itself
  api_args <- rank_values
  api_args[[target_rank]] <- NULL   # remove self-reference from context
  api_args$name    <- target_name
  api_args$rank    <- toupper(target_rank)
  api_args$verbose <- FALSE

  # Call GBIF backbone with full context
  tryCatch({
    record   <- do.call(rgbif::name_backbone, api_args)
    usage_key <- record$usageKey
    if (is.null(usage_key) || length(usage_key) == 0) usage_key <- NA_integer_

    result <- data.frame(
      usageKey  = as.integer(usage_key),
      matchType = as.character(record$matchType %||% NA_character_),
      gbif_rank = as.character(record$rank       %||% NA_character_),
      stringsAsFactors = FALSE
    )

    # --- HIGHERRANK recovery via name_lookup() ---
    # When name_backbone() resolves to a rank much coarser than expected
    # (e.g. Cyprinidae -> Animalia), try name_lookup() to find the correct
    # key at the expected rank. This handles deprecated/split taxa that
    # name_backbone() fails to resolve.
    result <- .recover_higherrank(result, target_name, target_rank, valid_ranks)

    result
  }, error = function(e) {
    warning(sprintf(
      "get_keys_from_context: API call failed for '%s' -- %s",
      target_name, conditionMessage(e)
    ), call. = FALSE)
    data.frame(usageKey  = NA_integer_,
               matchType = "ERROR",
               gbif_rank = NA_character_,
               stringsAsFactors = FALSE)
  })
}


#' Recover from HIGHERRANK resolution via name_lookup()
#'
#' When name_backbone() resolves a name to a drastically coarser rank
#' (e.g. family -> kingdom), attempts recovery by searching GBIF's
#' name_lookup() for the name at the expected rank. Uses the nubKey
#' (GBIF backbone key) from search results.
#'
#' @param result One-row data.frame from name_backbone() (usageKey, matchType, gbif_rank).
#' @param target_name Character. The taxon name that was queried.
#' @param target_rank Character (lowercase). The expected rank (e.g. "family").
#' @param valid_ranks Character vector of rank names from coarsest to finest.
#' @return The original result if no recovery needed/possible, or an updated
#'   result with the recovered key and matchType = "LOOKUP_RECOVERED".
#' @noRd
.recover_higherrank <- function(result, target_name, target_rank, valid_ranks) {

  if (is.na(result$matchType) || result$matchType != "HIGHERRANK") return(result)

  # Check rank distance: is the resolved rank much coarser than expected?
  rank_hierarchy <- toupper(valid_ranks)
  expected_pos <- match(toupper(target_rank), rank_hierarchy)
  resolved_pos <- match(toupper(result$gbif_rank), rank_hierarchy)

  if (is.na(expected_pos) || is.na(resolved_pos)) return(result)
  if (resolved_pos >= expected_pos - 1L) return(result)  # allow 1-level coarsening

  # Rank jump is too large — attempt recovery via name_lookup()
  recovered <- tryCatch({
    lookup <- rgbif::name_lookup(
      query = target_name,
      rank  = toupper(target_rank),
      limit = 20L
    )

    if (is.null(lookup$data) || nrow(lookup$data) == 0L) return(result)

    hits <- lookup$data

    # Filter to rows at the correct rank with a nubKey (GBIF backbone key)
    if (!"rank" %in% names(hits) || !"nubKey" %in% names(hits)) return(result)
    hits <- hits[!is.na(hits$rank) & toupper(hits$rank) == toupper(target_rank), ]
    hits <- hits[!is.na(hits$nubKey), ]

    if (nrow(hits) == 0L) return(result)

    # Use the most common nubKey (consensus across checklist datasets)
    nub_counts <- table(hits$nubKey)
    best_nub <- as.integer(names(which.max(nub_counts)))

    message(sprintf(
      "  get_keys_from_context: '%s' resolved to %s via name_backbone; recovered %s key %d via name_lookup.",
      target_name, result$gbif_rank, toupper(target_rank), best_nub
    ))

    data.frame(
      usageKey  = best_nub,
      matchType = "LOOKUP_RECOVERED",
      gbif_rank = toupper(target_rank),
      stringsAsFactors = FALSE
    )
  }, error = function(e) {
    warning(sprintf(
      "get_keys_from_context: name_lookup recovery failed for '%s' -- %s",
      target_name, conditionMessage(e)
    ), call. = FALSE)
    result
  })

  recovered
}

