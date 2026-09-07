utils::globalVariables(c(
  "species.x", "species.y", "id_x", "id_y", "p_match", "coverage",
  "same_batch", "partner", "acc", "score_value"
))

# ==============================================================================
# Local corroboration: free reference-quality evidence from the workflow's own
# seq_matrix, and the cost filter that says which references are worth
# screening at all.
#
# Implements items 2 and 3 of
# ecosystem_docs/REENTRY_PROMPT_local_corroboration_and_primer_stripped_screen.md
# (2026-09-03). Both functions consume plain data frames -- no new
# cross-package dependency, the same reasoning as verify_flagged_references().
# ==============================================================================

#' Corroborate Reference Labels From the Local Reference Set, Without BLAST
#'
#' For each reference accession, asks whether an INDEPENDENT conspecific in
#' the caller's own reference set (the one `TaxaLikely::build_sequence_matrix()`
#' was built from) matches it at high identity over most of the amplicon. A
#' reference so corroborated does not need the BLAST screen
#' ([evaluate_reference_accessions()]) to confirm its label -- and if the
#' BLAST screen nevertheless says `"remove"`, the local evidence vetoes that
#' ([score_reference_labels()]). Zero NCBI cost.
#'
#' @section What "independent" means:
#' Exactly what it means in [evaluate_reference_accessions()]: two
#' accessions are the same submission batch if their `create_date`s are
#' within `submission_window` days OR their accession numbers are within
#' `submission_window` under the same prefix. The same internal helpers
#' (`.build_submission_batch_lookup()` / `.same_submission_batch()`) are
#' used, so "independent" means one thing in both places. A conspecific from
#' the same batch is counted in `n_conspecific` but never corroborates -- the
#' motivating true mislabel `MN883227` (*Fundulus luciae*, actually a Pacific
#' *Fundulus*) has a same-day sibling `MN883226` at 100% that must not rescue
#' it.
#'
#' @section Why the overlap filter is not optional:
#' `p_match` from `build_sequence_matrix()` is identity over the ALIGNED
#' region; `coverage` is how much of the shorter sequence that region spans.
#' `KM057967` (*Jordania zonope*) looked corroborated by `LC126244` at "100%"
#' -- over a 5.6% overlap, about 40 bp of a different 12S region. Pairs with
#' `coverage < min_overlap` (or `NA` coverage) are excluded before anything
#' is counted, so Jordania is correctly a `"singleton"`.
#'
#' @section Where 0.99 comes from:
#' `min_pident` must sit INSIDE the marker's intraspecific range. The
#' motivating true mislabel `MN883227` is corroborated locally by five
#' independent conspecifics at 0.9814 -- 98% between "conspecifics" is what a
#' sister-species swap looks like at MiFish-U, so 0.98 would veto/skip it and
#' 0.99 keeps it screened. Re-deriving this from the trained H1
#' within-species distribution is a recorded later refinement, not built.
#'
#' @param seq_matrix Data frame. `TaxaLikely::build_sequence_matrix()` output:
#'   `id_x`, `id_y`, `p_match` (0-1), `coverage` (0-1), `species.x`,
#'   `species.y`. Either a full pairwise table or one triangle -- pairs are
#'   symmetrised internally.
#' @param reference_meta Data frame. One row per reference: `composite_id` (or
#'   `accession`) and, optionally, `create_date` (a `Date`, or a string in
#'   `"%Y/%m/%d"` or `"%Y-%m-%d"` form) and `species`. The
#'   `TaxaLikely::fetch_ncbi_reference_sequences()` reference_df is exactly
#'   this. Without `create_date`, independence falls back to the
#'   accession-number heuristic alone.
#' @param min_overlap Numeric in (0, 1] (default `0.8`). Minimum `coverage`
#'   for a pair to count at all.
#' @param min_pident Numeric in (0, 1] (default `0.99`). Minimum identity of
#'   the best independent conspecific for `local_tier = "corroborated"`.
#' @param submission_window Integer (default `5L`). As in
#'   [evaluate_reference_accessions()]; pass the same value used there.
#'
#' @return A data frame, one row per accession (version suffix stripped) in
#'   the union of `reference_meta` and `seq_matrix`:
#'   \describe{
#'     \item{`accession`}{Version-stripped id.}
#'     \item{`species`}{From `reference_meta$species` when present, else the
#'       accession's `species.x` in `seq_matrix`.}
#'     \item{`n_conspecific`}{Distinct conspecific partners at
#'       `coverage >= min_overlap`, any batch.}
#'     \item{`n_independent_conspecific`}{Of those, from a different
#'       submission batch.}
#'     \item{`best_independent_pident`}{Highest `p_match` (0-1) among the
#'       independent conspecifics; `NA` if none.}
#'     \item{`best_independent_partner`}{The partner supplying it (ties
#'       broken by id, so the result is deterministic).}
#'     \item{`local_tier`}{`"singleton"` (no conspecific at sufficient
#'       overlap), `"same_batch_only"` (conspecifics, none independent),
#'       `"disagree"` (independent conspecifics, none at `min_pident`), or
#'       `"corroborated"`.}
#'   }
#'   `attr(result, "local_corroboration_params")` records `min_overlap`,
#'   `min_pident` and `submission_window`.
#'
#' @seealso [evaluate_reference_accessions()], [score_reference_labels()],
#'   [match_driving_accessions()]
#'
#' @examples
#' \dontrun{
#' local_corr <- corroborate_references_locally(seq_matrix, reference_df)
#' table(local_corr$local_tier)
#' match_eval <- evaluate_reference_accessions(
#'   match_driving_accessions(match_obj),
#'   cache_dir = "ref_eval_cache",
#'   barcode_term = "MiFishU", local_corroboration = local_corr
#' )
#' match_eval <- score_reference_labels(match_eval,
#'   local_corroboration = local_corr, overwrite = TRUE
#' )
#' }
#'
#' @export
corroborate_references_locally <- function(seq_matrix, reference_meta,
                                           min_overlap = 0.8, min_pident = 0.99,
                                           submission_window = 5L) {
  if (!is.data.frame(seq_matrix)) {
    stop("seq_matrix must be a data frame (TaxaLikely::build_sequence_matrix() output).",
      call. = FALSE
    )
  }
  if (!is.data.frame(reference_meta)) {
    stop("reference_meta must be a data frame with a composite_id (or accession) column.",
      call. = FALSE
    )
  }
  sm_needed <- c("id_x", "id_y", "p_match", "coverage", "species.x", "species.y")
  sm_missing <- setdiff(sm_needed, names(seq_matrix))
  if (length(sm_missing) > 0L) {
    stop(sprintf(
      "seq_matrix is missing required column(s): %s",
      paste(sm_missing, collapse = ", ")
    ), call. = FALSE)
  }
  .unit_scalar <- function(x, nm) {
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || x <= 0 || x > 1) {
      stop(sprintf("%s must be a single number in (0, 1].", nm), call. = FALSE)
    }
  }
  .unit_scalar(min_overlap, "min_overlap")
  .unit_scalar(min_pident, "min_pident")
  if (!is.numeric(submission_window) || length(submission_window) != 1L ||
    is.na(submission_window) || submission_window < 0) {
    stop("submission_window must be a single non-negative number.", call. = FALSE)
  }

  id_col <- if ("composite_id" %in% names(reference_meta)) {
    "composite_id"
  } else if ("accession" %in% names(reference_meta)) {
    "accession"
  } else {
    stop("reference_meta needs a composite_id or accession column.", call. = FALSE)
  }

  meta_acc <- .strip_acc_version(as.character(reference_meta[[id_col]]))
  meta_ok <- !is.na(meta_acc) & nzchar(meta_acc)
  meta_acc <- meta_acc[meta_ok]

  # Dates: the screen's own lookup builder parses "%Y/%m/%d" strings (the
  # GBSeq reformatting convention); a Date passes through as.Date() unchanged
  # and an ISO "%Y-%m-%d" string is common in hand-built tables, so normalise
  # to Date here and hand the builder Dates.
  meta_date <- if ("create_date" %in% names(reference_meta)) {
    .parse_create_date(reference_meta$create_date[meta_ok])
  } else {
    rep(as.Date(NA), length(meta_acc))
  }

  sm_x <- .strip_acc_version(as.character(seq_matrix$id_x))
  sm_y <- .strip_acc_version(as.character(seq_matrix$id_y))
  all_acc <- unique(c(meta_acc, sm_x, sm_y))
  all_acc <- all_acc[!is.na(all_acc) & nzchar(all_acc)]

  lookup <- .build_submission_batch_lookup(data.frame(
    composite_id = c(meta_acc, setdiff(all_acc, meta_acc)),
    create_date = c(meta_date, rep(as.Date(NA), length(setdiff(all_acc, meta_acc)))),
    stringsAsFactors = FALSE
  ))

  # Conspecific pairs at sufficient overlap. NA coverage fails the filter:
  # an overlap that cannot be verified must not corroborate (the Jordania
  # lesson), which is deliberately stricter than the screen's own
  # is.na(coverage) | coverage >= min_coverage rule for BLAST hits, where
  # coverage is a query-coverage percentage that is essentially always
  # populated.
  cov <- suppressWarnings(as.numeric(seq_matrix$coverage))
  keep <- !is.na(seq_matrix$species.x) & !is.na(seq_matrix$species.y) &
    seq_matrix$species.x == seq_matrix$species.y &
    !is.na(sm_x) & !is.na(sm_y) & sm_x != sm_y &
    !is.na(cov) & cov >= min_overlap &
    !is.na(seq_matrix$p_match)
  pairs <- data.frame(
    acc = c(sm_x[keep], sm_y[keep]),
    partner = c(sm_y[keep], sm_x[keep]),
    p_match = c(seq_matrix$p_match[keep], seq_matrix$p_match[keep]),
    stringsAsFactors = FALSE
  )
  if (nrow(pairs) > 0L) {
    # Symmetrised above, so a triangular seq_matrix and a full one give the
    # same answer; a full one now carries each pair twice -- keep the
    # highest identity per (acc, partner).
    pairs <- pairs[order(pairs$acc, pairs$partner, -pairs$p_match), , drop = FALSE]
    pairs <- pairs[!duplicated(pairs[, c("acc", "partner")]), , drop = FALSE]

    xi <- match(pairs$acc, lookup$composite_id)
    yi <- match(pairs$partner, lookup$composite_id)
    pairs$same_batch <- .same_submission_batch(
      lookup$acc_date[xi], lookup$acc_prefix[xi], lookup$acc_num[xi],
      lookup$acc_date[yi], lookup$acc_prefix[yi], lookup$acc_num[yi],
      submission_window
    )
  } else {
    pairs$same_batch <- logical(0L)
  }

  n_consp <- tapply(
    pairs$partner, factor(pairs$acc, levels = all_acc),
    function(v) length(unique(v))
  )
  indep <- pairs[!pairs$same_batch, , drop = FALSE]
  n_indep <- tapply(
    indep$partner, factor(indep$acc, levels = all_acc),
    function(v) length(unique(v))
  )
  # Best independent partner: highest p_match, ties broken by partner id so
  # the answer does not depend on input order.
  indep <- indep[order(indep$acc, -indep$p_match, indep$partner), , drop = FALSE]
  best <- indep[!duplicated(indep$acc), , drop = FALSE]
  bi <- match(all_acc, best$acc)

  n_consp <- as.integer(ifelse(is.na(n_consp), 0L, n_consp))
  n_indep <- as.integer(ifelse(is.na(n_indep), 0L, n_indep))
  best_p <- best$p_match[bi]

  tier <- ifelse(
    n_consp == 0L, "singleton",
    ifelse(n_indep == 0L, "same_batch_only",
      ifelse(!is.na(best_p) & best_p >= min_pident, "corroborated", "disagree")
    )
  )

  species <- rep(NA_character_, length(all_acc))
  if ("species" %in% names(reference_meta)) {
    species <- as.character(reference_meta$species[meta_ok])[match(all_acc, meta_acc)]
  }
  need_sp <- is.na(species)
  if (any(need_sp)) {
    sx <- as.character(seq_matrix$species.x)
    first_x <- sx[match(all_acc[need_sp], sm_x)]
    first_y <- as.character(seq_matrix$species.y)[match(all_acc[need_sp], sm_y)]
    species[need_sp] <- ifelse(is.na(first_x), first_y, first_x)
  }

  out <- data.frame(
    accession = all_acc,
    species = species,
    n_conspecific = n_consp,
    n_independent_conspecific = n_indep,
    best_independent_pident = as.numeric(best_p),
    best_independent_partner = best$partner[bi],
    local_tier = tier,
    stringsAsFactors = FALSE
  )
  rownames(out) <- NULL
  attr(out, "local_corroboration_params") <- list(
    min_overlap = min_overlap, min_pident = min_pident,
    submission_window = submission_window
  )
  out
}

#' Parse create_date values in the forms this ecosystem actually produces
#' @noRd
.parse_create_date <- function(x) {
  if (inherits(x, "Date")) {
    return(x)
  }
  if (inherits(x, "POSIXt")) {
    return(as.Date(x))
  }
  x <- as.character(x)
  d <- suppressWarnings(as.Date(x, format = "%Y/%m/%d"))
  iso <- is.na(d) & !is.na(x)
  if (any(iso)) d[iso] <- suppressWarnings(as.Date(x[iso], format = "%Y-%m-%d"))
  d
}

#' Which Reference Accessions Ever Drive a Likelihood?
#'
#' Returns the accessions that are the max-scoring accession of their species
#' for at least one observation (ties kept). `TaxaLikely::evaluate_likelihoods()`
#' reads the per-species best match, so every other accession never drives a
#' likelihood and no verdict on it can change an assignment. This is a COST
#' FILTER for the BLAST screen ([evaluate_reference_accessions()]), not a
#' change to the match object: on the real PtConception 12S match object it
#' keeps 709 of 995 candidate accessions.
#'
#' `RESTORED_*` provenance accessions (from
#' `TaxaLikely::restore_suppressed_candidates()`) are dropped -- they are
#' not GenBank records and cannot be screened. The Mugu workflow did this by
#' hand at its call site; it is done here once.
#'
#' @param match_df Data frame. A standardized match object with the four
#'   columns named below.
#' @param score_col,obs_col,species_col,accession_col Character. Column
#'   names; defaults `"score_original"`, `"observation_id"`, `"species"`,
#'   `"accession"`.
#'
#' @return Character vector of accessions, exactly as they appear in
#'   `match_df` (version suffixes untouched, so they key the same cache rows
#'   a plain `unique(match_df$accession)` would), unique, in first-appearance
#'   order.
#'
#' @seealso [evaluate_reference_accessions()], [corroborate_references_locally()]
#'
#' @export
match_driving_accessions <- function(match_df, score_col = "score_original",
                                     obs_col = "observation_id", species_col = "species",
                                     accession_col = "accession") {
  if (!is.data.frame(match_df)) {
    stop("match_df must be a data frame.", call. = FALSE)
  }
  cols <- c(score_col, obs_col, species_col, accession_col)
  missing_cols <- setdiff(cols, names(match_df))
  if (length(missing_cols) > 0L) {
    stop(sprintf(
      "match_df is missing required column(s): %s",
      paste(missing_cols, collapse = ", ")
    ), call. = FALSE)
  }

  acc <- as.character(match_df[[accession_col]])
  score <- suppressWarnings(as.numeric(match_df[[score_col]]))
  ok <- !is.na(acc) & nzchar(acc) & !grepl("^RESTORED_", acc) & !is.na(score)
  if (!any(ok)) {
    return(character(0L))
  }

  key <- paste(as.character(match_df[[obs_col]])[ok],
    as.character(match_df[[species_col]])[ok],
    sep = "\r"
  )
  score <- score[ok]
  acc <- acc[ok]
  best <- stats::ave(score, key, FUN = max)
  unique(acc[score == best])
}
