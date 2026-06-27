# ==============================================================================
# standardize_match_data.R
# TaxaMatch — Standardize raw match data to canonical match object
# ==============================================================================

# Extended rank list from TaxaTools (canonical source of truth).
# Used for auto-detection when rank_system = NULL.
.standard_match_ranks <- TaxaTools::extended_ranks

#' Standardize Raw Match Data to Canonical Match Object
#'
#' Reads raw match data (from a data frame or file), renames the observation
#' identifier and score columns to canonical names (`observation_id` and `score_original`),
#' auto-detects or validates taxonomic rank columns, and derives `taxon_name`
#' and `taxon_name_rank` via [TaxaTools::create_taxon_names()].
#'
#' The result is a canonical match object ready for input to TaxaLikely.
#' One row per `observation_id` x reference match (e.g. one ESV x one accession
#' hit). Sample context (site, date, replicate) is stored in a separate table
#' and joined to the likelihood output downstream — it is not part of the match
#' object.
#'
#' @param data A data frame, a file path (character string), or `NULL`. When
#'   `NULL` an interactive file chooser (`file.choose()`) opens. CSV (`.csv`)
#'   and tab-delimited (`.tsv`, `.txt`) files are supported when a path is
#'   supplied.
#' @param observation_id_col Character. Name of the column that holds the unique
#'   query identifier (e.g. `"ESVId"` for MiFish eDNA output).
#' @param score_col Character. Name of the column holding the raw match score
#'   (e.g. `"PercMatch"`). Values may be on any numeric scale; normalisation
#'   is performed later in TaxaLikely.
#' @param rank_system Character vector of taxonomic rank column names,
#'   listed broadest to finest (e.g.
#'   `c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")`).
#'   Column matching is case-insensitive. When `NULL` (default), rank columns
#'   are auto-detected by matching column names against a built-in list of
#'   standard rank names (`domain` through `form`).
#' @param coverage_col Character or `NULL`. Name of a column containing an
#'   alignment or detection quality fraction (0--1 or 0--100 scale, e.g.
#'   `"qcovs"` for BLAST query coverage).  When supplied, the column is renamed
#'   to `coverage` in the canonical output.  TaxaLikely's
#'   `evaluate_likelihoods()` accepts `min_coverage` to pre-filter candidates
#'   whose `coverage` falls below a threshold before likelihood calculation.
#'   Default `NULL` (no coverage column).
#' @param col_map Optional named character vector of additional column renames
#'   applied before the core standardisation step, via
#'   [TaxaTools::rename_cols()]. Format: `c("OldName" = "new_name")`. Useful
#'   when source files use non-standard column names that are not auto-detected.
#' @param lowercase_names Logical. When `TRUE` (default), all column names in
#'   the output are converted to lowercase as the final step. This produces a
#'   fully consistent canonical object (e.g. `kingdom`, `testid`, `accession`)
#'   and avoids case-sensitivity surprises in downstream joins. Set to `FALSE`
#'   to preserve original column name casing.
#'
#' @return A data frame with at minimum:
#' \describe{
#'   \item{`observation_id`}{Unique query identifier (renamed from `observation_id_col`).}
#'   \item{`score_original`}{Raw match score (renamed from `score_col`). Preserved unchanged
#'     throughout the pipeline; downstream functions add `score_norm`, `score_softmax`, and
#'     `score_likelihood` columns as transformations are applied.}
#'   \item{`taxon_name`}{Most specific non-NA taxon name (derived).}
#'   \item{`taxon_name_rank`}{Rank of `taxon_name`, lowercase (derived).}
#' }
#' All other input columns are retained unchanged.
#'
#' @seealso [TaxaTools::create_taxon_names()], [TaxaTools::rename_cols()]
#'
#' @examples
#' \dontrun{
#' match_obj <- standardize_match_data(
#'   data = blast_results,
#'   observation_id_col = "qseqid",
#'   score_col = "pident"
#' )
#' }
#'
#' @importFrom utils read.csv
#' @importFrom tools file_ext
#' @importFrom stats setNames
#' @importFrom TaxaTools rename_cols create_taxon_names
#'
#' @export
standardize_match_data <- function(data             = NULL,
                                   observation_id_col,
                                   score_col,
                                   rank_system   = NULL,
                                   coverage_col     = NULL,
                                   col_map          = NULL,
                                   lowercase_names  = TRUE) {

  # --- 1. Load data -----------------------------------------------------------
  if (is.null(data)) {
    path <- file.choose()
    data <- .read_match_file(path)
  } else if (is.character(data) && length(data) == 1L) {
    data <- .read_match_file(data)
  }
  if (!is.data.frame(data)) {
    stop("`data` must be a data frame, a file path, or NULL.")
  }

  # --- 2. Validate args -------------------------------------------------------
  if (!is.logical(lowercase_names) || length(lowercase_names) != 1L || is.na(lowercase_names)) {
    stop("`lowercase_names` must be TRUE or FALSE.")
  }

  # --- Validate column name arguments ----------------------------------------
  if (!is.character(observation_id_col) || length(observation_id_col) != 1L || !nzchar(observation_id_col)) {
    stop("`observation_id_col` must be a single non-empty character string.")
  }
  if (!is.character(score_col) || length(score_col) != 1L || !nzchar(score_col)) {
    stop("`score_col` must be a single non-empty character string.")
  }
  if (!observation_id_col %in% names(data)) {
    stop(sprintf("`observation_id_col` '%s' not found in data.\n  Available columns: %s",
                 observation_id_col, paste(names(data), collapse = ", ")))
  }
  if (!score_col %in% names(data)) {
    stop(sprintf("`score_col` '%s' not found in data.\n  Available columns: %s",
                 score_col, paste(names(data), collapse = ", ")))
  }

  # --- 3. Optional extra renames (before core renames) -----------------------
  if (!is.null(col_map)) {
    data <- TaxaTools::rename_cols(data, col_map = col_map)
  }

  # --- 4. Rename observation_id and score -----------------------------------------
  if (observation_id_col != "observation_id" && "observation_id" %in% names(data)) {
    stop(sprintf(
      "Cannot rename '%s' to 'observation_id': a column named 'observation_id' already exists.",
      observation_id_col
    ))
  }
  if (score_col != "score_original" && "score_original" %in% names(data)) {
    stop(sprintf(
      "Cannot rename '%s' to 'score_original': a column named 'score_original' already exists.",
      score_col
    ))
  }

  core_map <- stats::setNames(c("observation_id", "score_original"), c(observation_id_col, score_col))
  # Drop identity renames to avoid spurious rename_cols warnings
  core_map <- core_map[names(core_map) != unname(core_map)]
  if (length(core_map) > 0L) {
    data <- TaxaTools::rename_cols(data, col_map = core_map)
  }

  # --- 4b. Rename coverage column (optional) ---------------------------------
  if (!is.null(coverage_col)) {
    if (!is.character(coverage_col) || length(coverage_col) != 1L || !nzchar(coverage_col))
      stop("`coverage_col` must be a single non-empty character string or NULL.")
    if (!coverage_col %in% names(data))
      stop(sprintf("`coverage_col` '%s' not found in data.\n  Available columns: %s",
                   coverage_col, paste(names(data), collapse = ", ")))
    if (coverage_col != "coverage") {
      if ("coverage" %in% names(data))
        stop(sprintf(
          "Cannot rename '%s' to 'coverage': a column named 'coverage' already exists.",
          coverage_col
        ))
      names(data)[names(data) == coverage_col] <- "coverage"
    }
  }

  # --- 5. Detect or validate taxonomy rank columns ---------------------------
  if (is.null(rank_system)) {
    rank_system <- .detect_rank_cols(data)
    if (length(rank_system) == 0L) {
      stop(
        "No standard taxonomic rank columns detected in data.\n",
        "Supply `rank_system` explicitly, e.g.:\n",
        "  rank_system = c(\"Kingdom\", \"Family\", \"Genus\", \"Species\")"
      )
    }
    message(sprintf("standardize_match_data: detected rank columns: %s",
                    paste(rank_system, collapse = ", ")))
  } else {
    if (!is.character(rank_system) || length(rank_system) == 0L) {
      stop("`rank_system` must be a non-empty character vector.")
    }
  }

  # --- 6. Derive taxon_name + taxon_name_rank --------------------------------
  data <- TaxaTools::create_taxon_names(data, rank_system)

  # --- 7. Optionally lowercase all column names (last step) ------------------
  if (lowercase_names) names(data) <- tolower(names(data))

  data
}

# ==============================================================================
# filter_redundant_hypotheses
# ==============================================================================

#' Filter Redundant Higher-Rank Hypotheses
#'
#' Removes coarser-rank rows that are superseded by finer-rank rows within the
#' same lineage and `observation_id`. Redundancy is **lineage-local**: a genus-level
#' row for *Gobius* is dropped only if a *Gobius* species row also exists for
#' the same `observation_id`. A genus row for a different lineage (e.g.,
#' *Acanthogobius*) is retained even when *Gobius* species rows are present.
#'
#' Should be called **after** [standardize_match_data()] (or any step that
#' populates `taxon_name_rank`) so that rank labels are already in the canonical
#' lowercase form used by `rank_system`.
#'
#' @param match_df A data frame with at minimum the columns `observation_id`,
#'   `taxon_name_rank`, and one column for each rank named in `rank_system`.
#'   Rows whose `taxon_name_rank` is not found in `rank_system` are retained
#'   unchanged and a warning is emitted listing the unrecognised values.
#' @param rank_system Character vector of taxonomic rank names in
#'   **coarsest-to-finest** order. Defaults to
#'   `c("kingdom","phylum","class","order","family","genus","species")`.
#'   Each name must match both an element of `taxon_name_rank` **and** a column
#'   name in `match_df` (case-sensitive after `standardize_match_data()` has
#'   lowercased everything).
#'
#' @return A data frame with the same columns as `match_df` but with redundant
#'   higher-rank rows removed. Row order and all other attributes are preserved.
#'
#' @examples
#' df <- data.frame(
#'   observation_id       = "S1",
#'   kingdom         = "Eukaryota",
#'   phylum          = "Chordata",
#'   class           = "Actinopteri",
#'   order           = "Gobiiformes",
#'   family          = "Gobiidae",
#'   genus           = c("Gobius", "Gobius", "Acanthogobius"),
#'   species         = c("Gobius paganellus", NA, NA),
#'   taxon_name      = c("Gobius paganellus", "Gobius", "Acanthogobius"),
#'   taxon_name_rank = c("species", "genus", "genus"),
#'   score_original  = c(99, 95, 88),
#'   stringsAsFactors = FALSE
#' )
#' filter_redundant_hypotheses(df)
#' # The Gobius genus row is dropped; the Acanthogobius genus row is kept.
#'
#' @export
filter_redundant_hypotheses <- function(
    match_df,
    rank_system = c("kingdom", "phylum", "class", "order", "family", "genus", "species")
) {
  # --- validate inputs --------------------------------------------------------
  if (!is.data.frame(match_df)) stop("`match_df` must be a data frame.")
  if (!is.character(rank_system) || length(rank_system) == 0L) {
    stop("`rank_system` must be a non-empty character vector.")
  }
  required_cols <- c("observation_id", "taxon_name_rank")
  missing_req <- setdiff(required_cols, names(match_df))
  if (length(missing_req) > 0L) {
    stop(sprintf("`match_df` is missing required column(s): %s",
                 paste(missing_req, collapse = ", ")))
  }

  # --- warn about ranks present in data but absent from rank_system ------------
  present_ranks <- unique(match_df$taxon_name_rank)
  unknown_ranks <- setdiff(present_ranks[!is.na(present_ranks)], rank_system)
  if (length(unknown_ranks) > 0L) {
    warning(sprintf(
      "filter_redundant_hypotheses: %d row(s) have taxon_name_rank not in rank_system and will be retained: %s",
      sum(match_df$taxon_name_rank %in% unknown_ranks, na.rm = TRUE),
      paste(unknown_ranks, collapse = ", ")
    ))
  }

  # --- identify rank columns present in both rank_system and match_df ----------
  rank_cols_present <- intersect(rank_system, names(match_df))

  # --- assign numeric rank scores ---------------------------------------------
  rank_score <- match(match_df$taxon_name_rank, rank_system)  # NA for unknown ranks

  # --- identify redundant rows ------------------------------------------------
  n <- nrow(match_df)
  redundant <- logical(n)

  # Warn about NA observation_ids
  n_na_sid <- sum(is.na(match_df$observation_id))
  if (n_na_sid > 0L) {
    warning(sprintf(
      paste0("filter_redundant_hypotheses: %d row(s) have NA observation_id. ",
             "These rows cannot be grouped and will be retained as-is."),
      n_na_sid
    ))
  }

  # Group by observation_id for efficiency: iterate per observation
  samples <- unique(match_df$observation_id[!is.na(match_df$observation_id)])
  for (sid in samples) {
    rows_in_sample <- which(match_df$observation_id == sid)
    if (length(rows_in_sample) < 2L) next

    scores_in_sample <- rank_score[rows_in_sample]

    for (i in rows_in_sample) {
      ri <- rank_score[i]
      if (is.na(ri)) next  # unknown rank — keep

      # Candidate superseding rows: same sample, finer rank
      finer_idx <- rows_in_sample[!is.na(scores_in_sample) & scores_in_sample > ri]
      if (length(finer_idx) == 0L) next

      # Ranks coarser-or-equal to row i, restricted to columns present in df.
      # match() may return NA if rank_system[ri] not in rank_cols_present.
      ri_in_present <- match(rank_system[ri], rank_cols_present)
      if (is.na(ri_in_present)) next
      cols_to_check <- rank_cols_present[seq_len(ri_in_present)]

      if (length(cols_to_check) == 0L) next

      # Values of those columns for row i
      vals_i <- unlist(match_df[i, cols_to_check, drop = FALSE])

      # Check if any finer row shares all those values
      for (j in finer_idx) {
        vals_j <- unlist(match_df[j, cols_to_check, drop = FALSE])
        # NA-safe comparison: NA in row i's lineage columns means unknown ancestor —
        # do not treat as a match (conservative: retain the row)
        if (any(is.na(vals_i))) break
        if (identical(vals_i, vals_j)) {
          redundant[i] <- TRUE
          break
        }
      }
    }
  }

  match_df[!redundant, , drop = FALSE]
}

# ==============================================================================
# Internal helpers
# ==============================================================================

#' Read a match data file (CSV or tab-delimited)
#' @noRd
.read_match_file <- function(path) {
  if (!file.exists(path)) stop(sprintf("File not found: %s", path))
  ext <- tolower(tools::file_ext(path))
  sep <- if (ext %in% c("tsv", "txt")) "\t" else ","
  utils::read.csv(path, sep = sep, stringsAsFactors = FALSE, check.names = FALSE)
}

#' Auto-detect taxonomic rank columns in a data frame
#'
#' Matches column names case-insensitively against `.standard_match_ranks` and
#' returns the matching column names in hierarchical order (broadest first).
#' @noRd
.detect_rank_cols <- function(df) {
  df_lower    <- tolower(names(df))
  found_lower <- intersect(.standard_match_ranks, df_lower)  # preserves rank order
  if (length(found_lower) == 0L) return(character(0))
  names(df)[match(found_lower, df_lower)]  # original (possibly mixed-case) names
}
