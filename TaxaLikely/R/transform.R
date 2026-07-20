# transform.R
# Session 158: shared score-transform helpers, factored out so
# train_likelihood_model()/.prep_training_data() (training) and
# evaluate_likelihoods()/.evaluate_one_query() (inference) apply the exact
# same transform -- H1/H2/H3 must be compared on one consistent scale, or
# their relative densities are not a valid likelihood ratio (see
# [[project_job2_unreferenced_relatives]] in the TaxaID memory system for the
# full derivation of why this matters and why "logit" alone was found to give
# qualitatively backwards behavior for cryptic/tightly-clustered genera).

#' Transform a raw match proportion onto a modeling scale
#'
#' `"logit"` is the package's original scale (`log(p/(1-p))`), unbounded but
#' with a derivative that diverges as `1/(1-p)` near `p = 1` -- real barcode
#' match data concentrates heavily near this boundary, and that divergence
#' was found to distort genus-level variance comparisons (a genuinely tight,
#' hard-to-distinguish genus can appear to have HIGHER logit-scale variance
#' than a loose, easily-distinguished one, backwards from the truth on the
#' raw proportion scale). `"sqrt_mismatch"` (`-sqrt(1-p)`) treats the
#' mismatch/divergence side as a rare-event count near the region where real
#' data lives (few mismatches out of many aligned bases), for which
#' square-root is the classical (Anscombe) variance-stabilizing transform;
#' empirically it recovers the correct qualitative genus-tightness ordering
#' where logit does not (Session 158). It is bounded to `[-1, 0]` rather than
#' the whole real line -- a Gaussian fit to it is technically an
#' approximation for that reason, but a mild one: real observations
#' concentrate near 0 (good matches), far from the -1 end, so the boundary
#' this transform CAN'T avoid is one the data essentially never reaches.
#'
#' @param p Numeric vector of proportions in `[0, 1]`.
#' @param method `"logit"` or `"sqrt_mismatch"`.
#' @param epsilon Clipping value used only by `"logit"` (avoids `-Inf`/`Inf`
#'   at `p = 0`/`1`). Unused by `"sqrt_mismatch"`, which is finite over the
#'   whole closed interval.
#' @return Numeric vector, same length as `p`.
#' @noRd
.transform_p <- function(p, method = c("logit", "sqrt_mismatch"), epsilon = 1e-4) {
  method <- match.arg(method)
  p <- pmin(pmax(p, 0), 1)
  if (method == "logit") {
    p_b <- pmin(pmax(p, epsilon), 1 - epsilon)
    log(p_b / (1 - p_b))
  } else {
    -sqrt(1 - p)
  }
}

#' Default `max_gap_ceiling` for a given score_transform
#'
#' Matches each scale's own version of the package's original derivation
#' ("roughly the gap between a 99.3% and a 50% match"): `logit` keeps the
#' existing `5.0` default; `sqrt_mismatch`'s equivalent gap
#' (`-sqrt(1-0.993) - (-sqrt(1-0.5))`) is `~0.6234`.
#' @noRd
.default_gap_ceiling <- function(method = c("logit", "sqrt_mismatch")) {
  method <- match.arg(method)
  if (method == "logit") 5.0 else 0.6234
}

#' Resolve a possibly-NULL max_gap_ceiling against score_transform
#' @noRd
.resolve_gap_ceiling <- function(max_gap_ceiling, score_transform) {
  if (is.null(max_gap_ceiling)) .default_gap_ceiling(score_transform) else max_gap_ceiling
}

#' Inverse of .transform_p() -- recover a raw match proportion from a
#' transformed score, for display/reporting purposes (e.g. verbose messages
#' that show a calibration shift in percent-identity terms).
#' @noRd
.untransform_p <- function(x, method = c("logit", "sqrt_mismatch")) {
  method <- match.arg(method)
  if (method == "logit") stats::plogis(x) else 1 - x^2
}

#' Unit-size ratio of a score_transform relative to logit
#'
#' Several small constants in this package (the H1-H2 minimum separation
#' floor, the H2 variance floor, `min_observed_sigma`'s default) were chosen
#' as round numbers in LOGIT units, with no derivation beyond "a small
#' positive floor." Rather than invent fresh magic numbers for
#' `sqrt_mismatch`, they are rescaled by this ratio -- the same
#' `.default_gap_ceiling()` reference point ("gap between a 99.3% and a 50%
#' match") used consistently across the package, so a single conversion
#' factor keeps every rescaled constant internally consistent with each
#' other rather than each picking its own ad hoc equivalence.
#' @noRd
.transform_unit_ratio <- function(method = c("logit", "sqrt_mismatch")) {
  method <- match.arg(method)
  .default_gap_ceiling(method) / .default_gap_ceiling("logit")
}
