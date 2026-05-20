#' Normalize raw match scores to the open interval (0, 1)
#'
#' Detects whether the input is on a 0–100 or 0–1 scale, rescales to \[0, 1\]
#' via min-max normalization, then clips to `(epsilon, 1 - epsilon)` so that a
#' subsequent logit transform is always finite.  `NA` values are left in place.
#'
#' Called internally by `.prep_training_data()` and `.evaluate_one_query()`.
#'
#' @param x Numeric vector of raw match scores (may contain `NA`).
#' @param bounds Optional length-2 numeric vector `c(min, max)` giving the
#'   theoretical scale of `x`.  If `NULL` (default) the scale is inferred: if
#'   `max(x, na.rm = TRUE) > 1` the scale is assumed 0–100, otherwise 0–1.
#' @param epsilon Clipping value applied symmetrically to both ends of the
#'   normalized interval.  Default `1e-6` (inference precision).  Training
#'   uses a wider `logit_epsilon = 1e-4` for robustness against extreme
#'   logit values dominating model estimation.
#'
#' @return Numeric vector the same length as `x`, with non-`NA` values in
#'   `(epsilon, 1 - epsilon)`.
#'
#' @noRd
.normalize_scores <- function(x, bounds = NULL, epsilon = 1e-6) {
  if (!is.numeric(x)) stop("x must be numeric")
  if (all(is.na(x))) return(x)
  if (!is.null(bounds)) {
    if (!is.numeric(bounds) || length(bounds) != 2L)
      stop("bounds must be a length-2 numeric vector")
    lo <- bounds[1]; hi <- bounds[2]
  } else {
    non_na <- x[!is.na(x)]
    if (length(non_na) == 0L) return(x)
    lo <- 0
    hi <- if (max(non_na) > 1) 100 else 1
  }
  if (hi == lo) {
    x[!is.na(x)] <- 1 - epsilon
    return(x)
  }
  p <- (x - lo) / (hi - lo)
  p <- pmin(pmax(p, epsilon), 1 - epsilon)
  p
}
