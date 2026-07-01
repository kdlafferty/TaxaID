# ==============================================================================
# correct_training_bias()
# ==============================================================================

#' Correct classifier scores for training-database representation bias
#'
#' Discriminative classifiers (iNaturalist CV, BirdNET) trained by standard
#' cross-entropy estimate a Bayes posterior: their raw output for species
#' \eqn{i} is proportional to \eqn{L(obs \mid species_i) \times n_i}, where
#' \eqn{L(obs \mid species_i)} is the true visual/acoustic likelihood and
#' \eqn{n_i} is the number of training examples for species \eqn{i}. Raw
#' classifier scores therefore favor well-represented (common, well-
#' photographed/recorded) taxa over rare ones with equal true evidential
#' support. This function divides out an estimate of that training-count
#' bias so that scores across candidates are on a more comparable scale
#' before [assign_scores()] normalizes them.
#'
#' @details
#' ## Adaptive shrinkage, not a fixed exponent
#' The correction is \eqn{score_i / n_i^{\tau_i}}, where \eqn{\tau_i =
#' n_i / (n_i + prior\_weight)} rather than a fixed global exponent. This
#' mirrors the per-species shrinkage already used in
#' \code{\link{train_likelihood_model}} (\code{w = N / (N + prior_weight)}):
#' \eqn{n_i} is itself only a public-database proxy for the classifier's
#' actual internal training count, and that proxy is less trustworthy the
#' smaller it is. \eqn{\tau_i} shrinks toward 0 (no correction — trust the
#' raw score) as \eqn{n_i \to 0}, and toward 1 (full correction) as
#' \eqn{n_i} grows. This also means a missing or zero count falls through
#' to the uncorrected score automatically (\eqn{\tau_i = 0 \Rightarrow
#' n_i^{\tau_i} = 1}), with no special-case branch needed — whether the
#' `NA` reflects a genuinely rare species or a failed lookup, leaving the
#' score untouched is the conservative default in both cases.
#'
#' ## Default `prior_weight`
#' When `prior_weight = NULL` (default), it is set to
#' `median(n, na.rm = TRUE)` across `count_col` — self-normalizing to
#' whatever scale the count data actually has (iNaturalist observation
#' counts and Xeno-canto recording counts live on very different scales),
#' rather than reusing an arbitrary fixed constant. With this default,
#' a species at the median count receives exactly half-strength
#' correction (\eqn{\tau_i = 0.5}).
#'
#' ## Column contract
#' `score_col` is overwritten in place with the corrected value, so no
#' downstream call (e.g. [unreferenced_candidates()], [assign_scores()])
#' needs to change — they already consume `score_col` by default. The
#' pre-correction value is preserved under `score_uncorrected` for
#' debugging. Diagnostic columns `n_used` (the count actually applied,
#' `NA` preserved as-is) and `tau_used` (the shrinkage exponent applied)
#' are also added.
#'
#' ## Pipeline placement
#' Run this on the raw multi-candidate classifier output, before
#' [unreferenced_candidates()] adds H2/H3 placeholder rows -- those rows
#' have no real score to correct and are anchored off the corrected H1
#' rows downstream:
#' \preformatted{
#' raw scored_df -> correct_training_bias() -> unreferenced_candidates() -> assign_scores()
#' }
#'
#' @param scored_df Data frame of raw classifier output, one row per
#'   candidate species per observation. Must contain `score_col`.
#' @param count_col Character scalar. Name of the column holding each
#'   candidate's training-database representation count (e.g.
#'   `"n_observations"` for iNaturalist CV output, `"n_recordings"` for
#'   BirdNET/Xeno-canto output after joining
#'   `audit_acoustic_coverage(xc_recordings = TRUE)`'s census onto
#'   `scored_df` by taxon). If absent from `scored_df`, a warning is
#'   issued and every row falls through unchanged (equivalent to all
#'   counts being `NA`).
#' @param score_col Character scalar (default `"score_original"`, matching
#'   [assign_scores()]'s default `score_col`). Name of the raw score
#'   column to correct.
#' @param prior_weight Positive numeric scalar, or `NULL` (default).
#'   Shrinkage prior weight for \eqn{\tau_i}. `NULL` uses
#'   `median(n, na.rm = TRUE)` (see Details).
#'
#' @return `scored_df` with `score_col` overwritten by the corrected
#'   score, plus three added columns: `score_uncorrected` (pre-correction
#'   value), `n_used` (count applied per row, `NA` where unavailable),
#'   and `tau_used` (shrinkage exponent applied per row).
#'
#' @seealso [assign_scores()], [unreferenced_candidates()]
#'
#' @examples
#' scored <- data.frame(
#'   observation_id = c("obs1", "obs1", "obs2"),
#'   taxon_name     = c("Turdus migratorius", "Turdus merula", "Limosa fedoa"),
#'   score_original = c(0.9, 0.85, 0.6),
#'   n_observations = c(500000, 20, 300)
#' )
#' corrected <- correct_training_bias(scored, count_col = "n_observations")
#' corrected[, c("taxon_name", "score_uncorrected", "score_original",
#'               "n_used", "tau_used")]
#'
#' @importFrom stats median
#' @export
correct_training_bias <- function(scored_df,
                                   count_col,
                                   score_col    = "score_original",
                                   prior_weight = NULL) {

  if (!is.data.frame(scored_df))
    stop("correct_training_bias: 'scored_df' must be a data frame.", call. = FALSE)
  if (!is.character(score_col) || length(score_col) != 1L || is.na(score_col))
    stop("correct_training_bias: 'score_col' must be a single character string.",
         call. = FALSE)
  if (!score_col %in% names(scored_df))
    stop(sprintf("correct_training_bias: column '%s' not found in 'scored_df'.",
                 score_col), call. = FALSE)
  if (!is.numeric(scored_df[[score_col]]))
    stop(sprintf("correct_training_bias: column '%s' must be numeric.", score_col),
         call. = FALSE)
  if (!is.character(count_col) || length(count_col) != 1L || is.na(count_col))
    stop("correct_training_bias: 'count_col' must be a single character string.",
         call. = FALSE)
  if (!is.null(prior_weight) &&
      (!is.numeric(prior_weight) || length(prior_weight) != 1L ||
       is.na(prior_weight) || prior_weight <= 0))
    stop("correct_training_bias: 'prior_weight' must be a single positive numeric value, or NULL.",
         call. = FALSE)

  score <- scored_df[[score_col]]

  if (!count_col %in% names(scored_df)) {
    warning(sprintf(
      "correct_training_bias: column '%s' not found in 'scored_df' -- ",
      count_col),
      "no bias correction applied; every row falls through unchanged.",
      call. = FALSE)
    n <- rep(NA_real_, nrow(scored_df))
  } else {
    n <- as.numeric(scored_df[[count_col]])
  }

  if (any(n < 0, na.rm = TRUE))
    stop(sprintf("correct_training_bias: '%s' contains negative values -- must be a non-negative count or NA.",
                 count_col), call. = FALSE)

  if (is.null(prior_weight)) {
    prior_weight <- stats::median(n, na.rm = TRUE)
    if (is.na(prior_weight)) prior_weight <- 1  # all-NA counts; tau will be 0 regardless
  }

  # NA/missing counts treated as 0 for shrinkage purposes only -- tau -> 0,
  # so n^tau -> 1 and the row falls through to the uncorrected score.
  n_for_shrinkage <- ifelse(is.na(n), 0, n)
  tau <- n_for_shrinkage / (n_for_shrinkage + prior_weight)

  scored_df$score_uncorrected <- score
  scored_df[[score_col]]      <- score / (n_for_shrinkage ^ tau)
  scored_df$n_used            <- n
  scored_df$tau_used          <- tau

  scored_df
}
