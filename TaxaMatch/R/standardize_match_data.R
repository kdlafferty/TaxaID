# ==============================================================================
# standardize_match_data.R
# TaxaMatch — Standardize raw match data to canonical match object
#
# Exported functions:
#   standardize_match_data()      Rename/derive columns into the canonical match object
#   filter_redundant_hypotheses() Drop coarser-rank rows superseded by finer-rank rows
#
# Internal helpers (@noRd):
#   .read_match_file()     Read a CSV/TSV match data file
#   .detect_rank_cols()    Auto-detect taxonomic rank columns
#   .check_col_exists()    Shared "column not found" validation
#   .check_rename_safe()   Shared rename-collision guard
#   .validate_rank_system() Shared rank_system input validation
# ==============================================================================

#' Stop with a consistent "column not found" message
#' @noRd
.check_col_exists <- function(data, col, arg_name) {
  if (!col %in% names(data)) {
    stop(sprintf("`%s` '%s' not found in data.\n  Available columns: %s",
                 arg_name, col, paste(names(data), collapse = ", ")))
  }
  invisible(TRUE)
}

#' Stop if renaming `from` to `to` would collide with an existing column
#' @noRd
.check_rename_safe <- function(data, from, to) {
  if (from != to && to %in% names(data)) {
    stop(sprintf(
      "Cannot rename '%s' to '%s': a column named '%s' already exists.",
      from, to, to
    ))
  }
  invisible(TRUE)
}

#' Validate a rank_system argument shared by multiple functions in this file
#' @noRd
.validate_rank_system <- function(rank_system) {
  if (!is.character(rank_system) || length(rank_system) == 0L) {
    stop("`rank_system` must be a non-empty character vector.")
  }
  invisible(TRUE)
}

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
#'   \item{`taxon_name_rank`}{Rank of `taxon_name`, lowercase (derived). Useful
#'     for reporting what proportion of observations resolved to
#'     species/genus/family level, per eDNA minimum-information reporting
#'     guidelines (e.g. Thalinger et al. 2021).}
#' }
#' All other input columns are retained unchanged -- **except** that when
#' `lowercase_names = TRUE` (the default), every column name in the output,
#' including retained ones, is converted to lowercase; the underlying data
#' is untouched, only the names.
#'
#' @seealso [TaxaTools::create_taxon_names()], [TaxaTools::rename_cols()],
#'   [filter_redundant_hypotheses()] (the natural next pipeline step, when
#'   BLAST/classifier output returns both a species- and genus-level hit for
#'   the same lineage)
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
    if (!interactive()) {
      stop("`data = NULL` requires an interactive session (opens file.choose()). ",
           "Pass a data frame or file path in non-interactive contexts (Rmd/Quarto, batch scripts, CI).")
    }
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
  if (!is.null(col_map) && (!is.character(col_map) || is.null(names(col_map)))) {
    stop("`col_map` must be a named character vector (or NULL), e.g. c(\"OldName\" = \"new_name\").")
  }

  # --- Validate column name arguments ----------------------------------------
  if (!is.character(observation_id_col) || length(observation_id_col) != 1L || !nzchar(observation_id_col)) {
    stop("`observation_id_col` must be a single non-empty character string.")
  }
  if (!is.character(score_col) || length(score_col) != 1L || !nzchar(score_col)) {
    stop("`score_col` must be a single non-empty character string.")
  }
  .check_col_exists(data, observation_id_col, "observation_id_col")
  .check_col_exists(data, score_col, "score_col")

  # --- 3. Optional extra renames (before core renames) -----------------------
  if (!is.null(col_map)) {
    data <- TaxaTools::rename_cols(data, col_map = col_map)
  }

  # --- 4. Rename observation_id and score -------------------------------------
  .check_rename_safe(data, observation_id_col, "observation_id")
  .check_rename_safe(data, score_col, "score_original")

  core_map <- stats::setNames(c("observation_id", "score_original"), c(observation_id_col, score_col))
  # Drop identity renames to avoid spurious rename_cols warnings
  core_map <- core_map[names(core_map) != unname(core_map)]
  if (length(core_map) > 0L) {
    data <- TaxaTools::rename_cols(data, col_map = core_map)
  }

  # --- 5. Rename coverage column (optional) -----------------------------------
  if (!is.null(coverage_col)) {
    if (!is.character(coverage_col) || length(coverage_col) != 1L || !nzchar(coverage_col))
      stop("`coverage_col` must be a single non-empty character string or NULL.")
    .check_col_exists(data, coverage_col, "coverage_col")
    .check_rename_safe(data, coverage_col, "coverage")
    if (coverage_col != "coverage") {
      names(data)[names(data) == coverage_col] <- "coverage"
    }
  }

  # --- 6. Detect or validate taxonomy rank columns ----------------------------
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
    .validate_rank_system(rank_system)
  }

  # --- 7. Derive taxon_name + taxon_name_rank ---------------------------------
  data <- TaxaTools::create_taxon_names(data, rank_system)

  # --- 8. Optionally lowercase all column names (last step) -------------------
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
#'   unchanged and a warning is emitted listing the unrecognised values. Rows
#'   with `NA` `taxon_name_rank` are also silently retained (no warning) --
#'   they cannot be compared against `rank_system` at all. Two species-level
#'   rows for different species sharing the same genus/family (e.g.
#'   *Gobius paganellus* and *Gobius bucchichi*) are both retained and
#'   neither's genus row is dropped -- this function only removes strictly
#'   redundant ancestor rows, not competing same-rank candidates
#'   (disambiguating those is TaxaLikely's job).
#' @param rank_system Character vector of taxonomic rank names in
#'   **coarsest-to-finest** order. Defaults to
#'   `c("kingdom","phylum","class","order","family","genus","species")`.
#'   Each name must match both an element of `taxon_name_rank` **and** a column
#'   name in `match_df` (case-sensitive after `standardize_match_data()` has
#'   lowercased everything) -- if `match_df` has not been through
#'   `standardize_match_data()`, rank column names may not match this
#'   default and no rows will be removed (a `warning()` is issued when none
#'   of `rank_system` matches a `match_df` column at all).
#'
#' @return A data frame with the same columns as `match_df` but with redundant
#'   higher-rank rows removed. Row order and all other attributes are preserved.
#'
#' @note This is particularly valuable for eDNA workflows where BLAST may
#'   return both a species-level hit (e.g. *Oncorhynchus mykiss*) and a
#'   genus-level hit (*Oncorhynchus*, from a different accession) for the
#'   same query. Without this filtering step, TaxaLikely would treat the
#'   genus and species rows as independent competing hypotheses, inflating
#'   uncertainty that the data doesn't actually support.
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
  .validate_rank_system(rank_system)
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
  if (length(rank_cols_present) == 0L) {
    warning(
      "filter_redundant_hypotheses: none of `rank_system` matches a column ",
      "name in `match_df` -- no rows will be removed. This usually means ",
      "`match_df` has not been through standardize_match_data() (which ",
      "lowercases column names to match the default rank_system), or ",
      "rank_system contains a typo."
    )
  } else {
    # `rank_system`'s own FINEST (last) entry is never consulted as a
    # "coarser-or-equal" comparison column for any row's redundancy check: a
    # row AT that rank is always skipped before its own column would be
    # needed (nothing is finer, so it can never be superseded), and no
    # coarser row's own comparison columns can include it either, since its
    # position in `rank_system` is always last. A missing column for it is
    # therefore provably inert -- confirmed 2026-09-07 tracing the exact
    # comparison loop below, after this warning fired on every real
    # TaxaAssign::join_priors() call whose `likelihoods` input was
    # TaxaLikely::evaluate_likelihoods() output (which carries only
    # taxon_name/taxon_name_rank forward by documented design, never a
    # literal "species" column, even though "species" is routinely the
    # finest entry callers pass). Only a genuinely load-bearing (non-finest)
    # missing column is worth warning about.
    load_bearing_missing <- setdiff(rank_system[-length(rank_system)], rank_cols_present)
    if (length(load_bearing_missing) > 0L) {
      warning(sprintf(
        "filter_redundant_hypotheses: rank_system name(s) not found as a column in match_df (check for typos): %s",
        paste(load_bearing_missing, collapse = ", ")
      ))
    }
  }

  # --- assign numeric rank scores ---------------------------------------------
  rank_score <- match(match_df$taxon_name_rank, rank_system)  # NA for unknown ranks

  # --- identify redundant rows ------------------------------------------------
  # Invariant: row i is redundant if and only if there exists a row j in the
  # same observation_id with a strictly finer rank than i that shares all of
  # row i's own lineage column values, from the coarsest rank up to and
  # including rank_system[rank_score[i]] -- i.e. j's ancestry passes through
  # exactly the taxon row i names, so i adds no information beyond j.
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
#'
#' Delimiter is inferred from the file extension (\code{.tsv}/\code{.txt} ->
#' tab, otherwise comma) -- a file with the "wrong" extension for its actual
#' delimiter (e.g. a tab-delimited file saved as \code{.csv}) would otherwise
#' be silently misread as one column. A post-read check warns when only one
#' column is detected, the most common symptom of this.
#' @noRd
.read_match_file <- function(path) {
  if (!file.exists(path)) stop(sprintf("File not found: %s", path))
  ext <- tolower(tools::file_ext(path))
  sep <- if (ext %in% c("tsv", "txt")) "\t" else ","
  result <- utils::read.csv(path, sep = sep, stringsAsFactors = FALSE, check.names = FALSE)
  if (ncol(result) == 1L) {
    warning(sprintf(
      paste0(
        "%s parsed to a single column using delimiter '%s' (inferred from ",
        "the .%s extension); if the file actually uses a different ",
        "delimiter, rename it or read it manually first."
      ),
      basename(path), if (sep == "\t") "\\t" else sep, ext
    ), call. = FALSE)
  }
  result
}

#' Auto-detect taxonomic rank columns in a data frame
#'
#' Matches column names case-insensitively against
#' \code{TaxaTools::extended_ranks} and returns the matching column names in
#' hierarchical order (broadest first). \code{TaxaTools::extended_ranks} is
#' read here (inside the function, called only when needed) rather than at
#' package load time -- top-level code with side effects at attach time is
#' an R CMD CHECK-flagged pattern.
#' @noRd
.detect_rank_cols <- function(df) {
  standard_match_ranks <- TaxaTools::extended_ranks
  df_lower    <- tolower(names(df))
  found_lower <- intersect(standard_match_ranks, df_lower)  # preserves rank order
  if (length(found_lower) == 0L) return(character(0))
  names(df)[match(found_lower, df_lower)]  # original (possibly mixed-case) names
}
