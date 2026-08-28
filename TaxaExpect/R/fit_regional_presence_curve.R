# fit_regional_presence_curve.R
# TaxaExpect package

#' Fit a distance-to-presence curve for regional-proximity weights
#'
#' The per-dataset, self-calibrating alternative (2026-08-26 mixture
#' redesign, D5) to accepting
#' \code{\link{generate_regional_proximity_evidence}}'s default
#' \code{w_scale}/\code{d_half}: estimate P(locally present | nearest
#' external record at distance d) from a study's own data and read the two
#' parameters off the fit.
#'
#' @section Building the input (two general recipes):
#' \describe{
#'   \item{Leave-the-bbox-out (GBIF only, no checklist needed)}{For each
#'     species in the regional pool, \code{present} = does it have any
#'     in-bbox occurrence record; \code{distance_km} = distance from the
#'     study site to its nearest record OUTSIDE the bbox. Fully generic
#'     across taxa and geography, but note the estimand caveat: presence of
#'     RECORDS understates true presence where local effort is thin.}
#'   \item{Checklist calibration (preferred when a site checklist exists)}{
#'     Restrict to the actual application population -- candidate species
#'     with NO in-bbox records -- and let \code{present} = membership on an
#'     independent expert site checklist. This matches the deployment
#'     condition exactly (the weight is only ever applied to zero-in-bbox
#'     species). The GreatLakes2023 test case used this recipe and found 0
#'     positives in 110 candidates at 12-990 km, making the curve SHAPE
#'     unidentifiable -- only bounded -- which is exactly what this
#'     function's zero-positive path reports.}
#' }
#'
#' @section What is fitted:
#' The same functional form the generator applies,
#' \code{P(present | d) = w_scale * exp(-d / d_half)}, via a binomial GLM
#' with log link (so \code{w_scale = exp(intercept)} and
#' \code{d_half = -1/slope}). When the log-link fit fails to converge (small
#' samples, probabilities near 1) a logistic fit is tried and mapped to the
#' exponential form at its small-probability limit. With ZERO positives no
#' curve is identifiable; the function instead returns Jeffreys 95 percent
#' upper bounds on P(present) per distance bin plus pooled -- calibrate
#' \code{w_scale} against those bounds (choose a curve sitting inside them),
#' as the GreatLakes2023 case did (pooled bound 0.027 -> adopted
#' \code{w_scale = 0.05} with the default \code{d_half}, predicted pooled
#' prevalence 1.4 percent).
#'
#' @param presence_df Data frame with columns \code{present} (logical) and
#'   \code{distance_km} (numeric > 0): one row per species in the chosen
#'   recipe's population.
#' @param bins Numeric vector of distance-bin edges for the zero-positive
#'   bound table (and a fit-vs-binned diagnostic otherwise). Default
#'   \code{c(0, 100, 200, 400, 700, 1100)}.
#'
#' @return A list:
#'   \describe{
#'     \item{w_scale, d_half}{Fitted parameters (NA when unidentifiable).}
#'     \item{fit}{The glm object (or NULL).}
#'     \item{identifiable}{FALSE when zero positives (or a degenerate fit).}
#'     \item{bin_table}{Per-bin n, positives, and Jeffreys 95 percent upper
#'       bound on P(present); plus a pooled row.}
#'     \item{n, n_present}{Sample sizes.}
#'   }
#'
#' @examples
#' \dontrun{
#' curve <- fit_regional_presence_curve(presence_df)
#' if (curve$identifiable) {
#'   evidence <- generate_regional_proximity_evidence(
#'     zero_bbox_taxa, lat, lng,
#'     w_scale = curve$w_scale, d_half = curve$d_half
#'   )
#' } else {
#'   print(curve$bin_table)  # choose w_scale under these bounds
#' }
#' }
#'
#' @export
fit_regional_presence_curve <- function(
    presence_df,
    bins = c(0, 100, 200, 400, 700, 1100)
) {
  if (!is.data.frame(presence_df) ||
      !all(c("present", "distance_km") %in% names(presence_df))) {
    stop("fit_regional_presence_curve: `presence_df` must be a data frame ",
         "with columns `present` (logical) and `distance_km` (numeric).")
  }
  df <- presence_df[!is.na(presence_df$present) &
                      !is.na(presence_df$distance_km) &
                      presence_df$distance_km >= 0, , drop = FALSE]
  if (nrow(df) == 0L) {
    stop("fit_regional_presence_curve: no usable rows in `presence_df`.")
  }
  if (!is.logical(df$present)) {
    stop("fit_regional_presence_curve: `present` must be logical.")
  }

  # Jeffreys 95 percent upper bound on a binomial proportion
  .jeffreys_ub <- function(x, n) stats::qbeta(0.975, x + 0.5, n - x + 0.5)

  bin_f <- cut(df$distance_km, breaks = unique(c(bins, Inf)), include.lowest = TRUE)
  bin_n <- tapply(df$present, bin_f, length)
  bin_x <- tapply(df$present, bin_f, sum)
  keep  <- !is.na(bin_n)
  bin_table <- data.frame(
    bin        = c(names(bin_n)[keep], "pooled"),
    n          = c(as.integer(bin_n[keep]), nrow(df)),
    n_present  = c(as.integer(bin_x[keep]), sum(df$present)),
    jeffreys_ub_95 = c(.jeffreys_ub(as.integer(bin_x[keep]), as.integer(bin_n[keep])),
                       .jeffreys_ub(sum(df$present), nrow(df))),
    stringsAsFactors = FALSE
  )

  n_present <- sum(df$present)
  if (n_present == 0L) {
    message(sprintf(
      "fit_regional_presence_curve: 0 of %d species present -- the curve shape is not identifiable, only bounded. Calibrate w_scale against bin_table's Jeffreys upper bounds (see roxygen).",
      nrow(df)
    ))
    return(list(w_scale = NA_real_, d_half = NA_real_, fit = NULL,
                identifiable = FALSE, bin_table = bin_table,
                n = nrow(df), n_present = 0L))
  }

  fit <- tryCatch(
    stats::glm(present ~ distance_km, data = df,
               family = stats::binomial(link = "log"),
               start = c(log(max(mean(df$present), 1e-3)), -1/150)),
    error = function(e) NULL, warning = function(w) NULL
  )
  if (is.null(fit) || !fit$converged || stats::coef(fit)[2] >= 0) {
    # logistic fallback, mapped to the exponential form at small p
    fit <- tryCatch(
      stats::glm(present ~ distance_km, data = df, family = stats::binomial()),
      error = function(e) NULL
    )
    if (is.null(fit) || !fit$converged || stats::coef(fit)[2] >= 0) {
      message("fit_regional_presence_curve: no decreasing distance-presence fit converged -- returning bounds only.")
      return(list(w_scale = NA_real_, d_half = NA_real_, fit = fit,
                  identifiable = FALSE, bin_table = bin_table,
                  n = nrow(df), n_present = n_present))
    }
    b <- stats::coef(fit)
    w_scale <- stats::plogis(b[[1]])
    d_half  <- -1 / b[[2]]
  } else {
    b <- stats::coef(fit)
    w_scale <- min(exp(b[[1]]), 1)
    d_half  <- -1 / b[[2]]
  }

  list(w_scale = unname(w_scale), d_half = unname(d_half), fit = fit,
       identifiable = TRUE, bin_table = bin_table,
       n = nrow(df), n_present = n_present)
}
