# kernel_budget_sensitivity.R
# TaxaExpect package
#
# Open decision #4 of ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_
# scope.md: "Report f1, f2 and the radius sensitivity next to any budget figure
# so a reader can see when it rests on four doubletons. No downside."
#
# The motivating measurements, all on real data:
#   Mugu        theta_present spans 4x   over the counting radius alone (f2 5-12)
#   GreatLakes  chao_missing  spans 21x  over the same sweep          (f2 4-11)
#   PtCon 18S   per-group theta_present spans 6x to 137x by group, with f2 in
#               single digits for every group except macroinvertebrates
# Chao = f1^2 / (2 f2) is hypersensitive to f2 in single digits, and NOTHING
# else in the pipeline constrains f2: lambda is chosen by leave-one-block-out
# COMPOSITION prediction, which has no stake in the singleton/doubleton counts,
# and `support_weight` is a fixed default nobody has ever had a reason to move.
# So a budget figure quoted without its f2 and its radius sensitivity is a
# number whose stability the reader cannot assess.

#' Sensitivity of a kernel Good-Turing budget to its counting radius
#'
#' Re-computes the `$budget` of a fitted [estimate_kernel_priors()] object
#' across a grid of counting radii (`support_weight`) and, optionally,
#' geographic bandwidths (`lambda_km`), and summarizes how far each group's
#' budget quantities move. Report this next to any `chao_missing` or
#' `theta_present` figure you intend to act on.
#'
#' @details
#' `support_weight` is the kernel weight at which a record starts counting
#' toward the discrete support statistics `f1` (singletons) and `f2`
#' (doubletons). It is a pure counting boundary: moving it changes neither
#' `theta` nor `n_eff` nor `missing_mass`'s definition, only which records are
#' inside the neighborhood being counted. Sweeping it therefore isolates the
#' budget's dependence on that boundary from every other modelling choice.
#'
#' `chao_missing` is `f1^2 / (2 f2)`, so it is quadratic in `f1` and inverse in
#' `f2`. With `f2` in single digits -- the usual case for anything but the
#' largest group -- one doubleton entering or leaving the neighborhood moves
#' the estimate by tens of percent. The `f2_min` column of `$summary` is the
#' number to look at first for that figure. `theta_present` is priced from
#' `missing_mass / f1` (2026-09-05, open decision #1 of the kernel budget/
#' pricing re-entry doc, resolved), so it no longer inherits `f2`'s
#' instability -- but it still moves with the counting radius through `f1` and
#' `missing_mass` themselves, which is what `theta_present_spread` reports.
#'
#' The sweep calls [estimate_kernel_priors()] itself rather than recomputing
#' the statistics from the fit, so the numbers reported here cannot drift from
#' what the estimator would say. That costs one O(records) pass per setting
#' (~2 s per pass at 2 million records).
#'
#' @param fit A `"taxaexpect_kernel_priors"` object from
#'   [estimate_kernel_priors()].
#' @param occurrence_data The same occurrence data `fit` was computed from. The
#'   fit does not retain the records, so they must be supplied again; passing
#'   different data silently answers a different question, and a mismatch at the
#'   fit's own settings is reported by `$reproduces_fit`.
#' @param support_weight_grid Numeric vector in (0, 1] of counting radii to
#'   sweep. Default `exp(-(1:5))`, i.e. 1 to 5 bandwidths, which brackets the
#'   `exp(-3)` default on both sides.
#' @param lambda_grid Optional numeric vector of geographic bandwidths (km).
#'   `NULL` (default) sweeps only the counting radius, holding `lambda_km` at
#'   the fit's own value -- the cleaner diagnostic, since it moves one boundary
#'   and nothing else. Supply a grid to see the joint sensitivity.
#' @param verbose Logical. Message each setting as it is computed.
#'
#' @return An object of class `"taxaexpect_kernel_budget_sensitivity"`: a list
#'   with
#'   \describe{
#'     \item{budget}{Long data frame, one row per (setting, sampling group):
#'       the `$budget` columns plus `lambda_km`, `support_weight`,
#'       `radius_lambdas` (`-log(support_weight)`) and `radius_km`.}
#'     \item{summary}{One row per sampling group: the range of `f1`, `f2`,
#'       `chao_missing` and `theta_present` over the sweep,
#'       `theta_present_spread` (max/min over settings where it is defined),
#'       `theta_present_at_fit`, and `n_unpriced` (settings where the group had
#'       no defined price).}
#'     \item{at_fit}{The budget at the fit's own settings.}
#'     \item{reproduces_fit}{Logical: whether the fit's own settings reproduced
#'       the fit's `$budget` exactly. `FALSE` means `occurrence_data` is not the
#'       data `fit` was computed from.}
#'     \item{params}{The sweep's own provenance.}
#'   }
#' @seealso [estimate_kernel_priors()], [calibrate_kernel_bandwidth()]
#' @examples
#' occ <- data.frame(
#'   taxon_name = c(rep(c("A", "B", "C"), each = 8), "D", "E", "F", "G"),
#'   decimalLatitude = 34 + rnorm(28, 0, 0.1),
#'   decimalLongitude = -119 + rnorm(28, 0, 0.1),
#'   main_habitat = "Marine"
#' )
#' fit <- estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)
#' kernel_budget_sensitivity(fit, occ)
#' @export
kernel_budget_sensitivity <- function(fit,
                                      occurrence_data,
                                      support_weight_grid = exp(-(1:5)),
                                      lambda_grid = NULL,
                                      verbose = FALSE) {
  if (!inherits(fit, "taxaexpect_kernel_priors"))
    stop("fit must be a 'taxaexpect_kernel_priors' object from estimate_kernel_priors().")
  if (!is.data.frame(occurrence_data) || nrow(occurrence_data) == 0L)
    stop("occurrence_data must be the non-empty data frame `fit` was computed from.")
  if (!is.numeric(support_weight_grid) || length(support_weight_grid) < 1L ||
      any(is.na(support_weight_grid)) || any(support_weight_grid <= 0) ||
      any(support_weight_grid > 1))
    stop("support_weight_grid must be numerics in (0, 1].")
  if (!is.null(lambda_grid) &&
      (!is.numeric(lambda_grid) || length(lambda_grid) < 1L ||
       any(is.na(lambda_grid)) || any(lambda_grid <= 0)))
    stop("lambda_grid must be positive numerics, or NULL.")

  p <- fit$params
  # Always include the fit's own settings, so the sweep contains the number the
  # caller is actually quoting and $reproduces_fit has something to check.
  sw_grid  <- sort(unique(c(support_weight_grid, p$support_weight)), decreasing = TRUE)
  lam_grid <- sort(unique(c(if (is.null(lambda_grid)) numeric(0) else lambda_grid,
                            p$lambda_km)))
  settings <- expand.grid(lambda_km = lam_grid, support_weight = sw_grid,
                          KEEP.OUT.ATTRS = FALSE)

  # Column names were not recorded before 2026-09-03; fall back to the
  # estimator's own defaults for objects fitted by an older version.
  .col <- function(nm, default) if (is.null(p[[nm]])) default else p[[nm]]

  rows <- lapply(seq_len(nrow(settings)), function(i) {
    if (isTRUE(verbose))
      message(sprintf("  lambda_km = %g, support_weight = %.4g (%.1f bandwidths)",
                      settings$lambda_km[i], settings$support_weight[i],
                      -log(settings$support_weight[i])))
    f <- estimate_kernel_priors(
      occurrence_data,
      site_lat = p$site_lat, site_lon = p$site_lon,
      site_habitat = p$site_habitat,
      lambda_km = settings$lambda_km[i], m = p$m,
      covariate_col = p$covariate_col, site_covariate = p$site_covariate,
      lambda_covariate = p$lambda_covariate, lambda_latitude = p$lambda_latitude,
      site_id = p$site_id,
      taxon_col = .col("taxon_col", "taxon_name"),
      lat_col = .col("lat_col", "decimalLatitude"),
      lon_col = .col("lon_col", "decimalLongitude"),
      habitat_col = .col("habitat_col", "main_habitat"),
      sampling_group_col = p$sampling_group_col,
      support_weight = settings$support_weight[i])
    b <- f$budget
    b$lambda_km      <- settings$lambda_km[i]
    b$support_weight <- settings$support_weight[i]
    b$radius_lambdas <- -log(settings$support_weight[i])
    b$radius_km      <- -log(settings$support_weight[i]) * settings$lambda_km[i]
    b
  })
  budget <- do.call(rbind, rows)
  budget <- budget[order(budget$sampling_group, budget$lambda_km,
                         -budget$support_weight), , drop = FALSE]
  rownames(budget) <- NULL

  at_fit <- budget[budget$lambda_km == p$lambda_km &
                     budget$support_weight == p$support_weight, , drop = FALSE]
  keep <- intersect(names(fit$budget), names(at_fit))
  reproduces <- isTRUE(all.equal(
    fit$budget[order(fit$budget$sampling_group), keep, drop = FALSE],
    at_fit[order(at_fit$sampling_group), keep, drop = FALSE],
    check.attributes = FALSE))

  .rng <- function(v) if (all(is.na(v))) c(NA_real_, NA_real_) else
    range(v, na.rm = TRUE)
  grps <- unique(budget$sampling_group)
  summary_tab <- do.call(rbind, lapply(grps, function(g) {
    s <- budget[(is.na(g) & is.na(budget$sampling_group)) |
                  (!is.na(budget$sampling_group) & budget$sampling_group == g), ,
                drop = FALSE]
    tp <- s$theta_present[is.finite(s$theta_present) & s$theta_present > 0]
    data.frame(
      sampling_group = g,
      n_settings = nrow(s),
      f1_min = min(s$f1), f1_max = max(s$f1),
      f2_min = min(s$f2), f2_max = max(s$f2),
      chao_min = .rng(s$chao_missing)[1], chao_max = .rng(s$chao_missing)[2],
      theta_present_min = if (length(tp)) min(tp) else NA_real_,
      theta_present_max = if (length(tp)) max(tp) else NA_real_,
      theta_present_spread = if (length(tp) > 1L) max(tp) / min(tp) else NA_real_,
      theta_present_at_fit = at_fit$theta_present[
        match(g, at_fit$sampling_group)],
      n_unpriced = sum(!is.finite(s$theta_present)),
      stringsAsFactors = FALSE)
  }))
  rownames(summary_tab) <- NULL

  structure(list(
    budget = budget,
    summary = summary_tab,
    at_fit = at_fit,
    reproduces_fit = reproduces,
    params = list(fit_lambda_km = p$lambda_km,
                  fit_support_weight = p$support_weight,
                  sampling_group_col = p$sampling_group_col,
                  site_id = p$site_id, site_habitat = p$site_habitat,
                  support_weight_grid = sw_grid,
                  lambda_grid = lam_grid,
                  n_settings = nrow(settings))
  ), class = "taxaexpect_kernel_budget_sensitivity")
}

#' @export
print.taxaexpect_kernel_budget_sensitivity <- function(x, ...) {
  p <- x$params
  cat(sprintf(
    "taxaexpect_kernel_budget_sensitivity: %d setting(s) at %s (%s)\n  counting radius %.1f-%.1f bandwidths, lambda %s km; fit sits at %.1f bandwidths, lambda %g km\n",
    p$n_settings, p$site_id, p$site_habitat,
    min(-log(p$support_weight_grid)), max(-log(p$support_weight_grid)),
    paste(format(p$lambda_grid, trim = TRUE), collapse = "/"),
    -log(p$fit_support_weight), p$fit_lambda_km))
  if (!isTRUE(x$reproduces_fit))
    cat("  ! the fit's own settings did NOT reproduce its $budget -- occurrence_data\n",
        "    is not the data this fit was computed from.\n", sep = "")
  s <- x$summary
  out <- data.frame(
    group = ifelse(is.na(s$sampling_group), "(pooled)", s$sampling_group),
    f1 = sprintf("%d-%d", s$f1_min, s$f1_max),
    f2 = sprintf("%d-%d", s$f2_min, s$f2_max),
    chao = sprintf("%.3g-%.3g", s$chao_min, s$chao_max),
    theta_present = sprintf("%.3g", s$theta_present_at_fit),
    spread = ifelse(is.na(s$theta_present_spread), "-",
                    sprintf("%.3gx", s$theta_present_spread)),
    unpriced = s$n_unpriced,
    stringsAsFactors = FALSE)
  print(out, row.names = FALSE)
  thin <- s[is.finite(s$f2_min) & s$f2_min > 0 & s$f2_min < 10, , drop = FALSE]
  if (nrow(thin) > 0L)
    cat(sprintf(
      "  CAUTION: chao_missing rests on single-digit doubleton counts in %d group(s) (f2 as low as %d: %s).\n           Chao = f1^2/(2 f2) is hypersensitive there; quote the spread with the figure.\n",
      nrow(thin), min(thin$f2_min),
      paste(utils::head(ifelse(is.na(thin$sampling_group), "(pooled)",
                               thin$sampling_group), 4L), collapse = ", ")))
  if (any(s$n_unpriced > 0L))
    cat("  NOTE: some settings leave a group with no defined theta_present (f1 = 0 --\n        no singleton anchor at that counting radius).\n")
  invisible(x)
}
