# Phase 2 of the kernel-priors redesign (2026-08-30): site-centered
# distance-kernel estimation of relative detection priors, replacing the
# grid-cell GLMM prediction path. Design record:
# ecosystem_docs/REENTRY_PROMPT_evidence_ceiling_and_habitat_bleed.md
# ("PHASE 1 SPEC" + "Phase 2 verdicts" sections). Deliberately an ESTIMATOR,
# never a latent spatial model -- per-species latent fields are the documented
# hours-scale performance trap this design explicitly forbids.

#' Estimate site priors by distance-kernel weighting of occurrence records
#'
#' Computes each species' expected share of legitimate detections at a
#' sampling site (`theta`) directly from habitat-stratified occurrence
#' records, weighting every record by its distance to the site:
#' \deqn{w_r = \exp(-d_r/\lambda) \times \exp(-|c_r - c_{site}|/\lambda_c)}
#' where \eqn{d_r} is the great-circle-approximate distance (km, cosine-
#' corrected longitude) and the optional second factor is a covariate kernel
#' (e.g. depth -- distinguishes pelagic from nearshore species; see
#' `covariate_col`). Species shares are shrunk toward the regional
#' composition by `m` pseudo-records (Dirichlet back-off):
#' \deqn{\theta_i = (c_i s + m p_i) / (n_{eff} + m)}
#' with \eqn{c_i} the species' summed record weights, \eqn{s = n_{eff}/W} the
#' effective-scale factor, \eqn{W} the total weight, \eqn{n_{eff} = W^2 /
#' \sum w^2} (Kish effective sample size), and \eqn{p_i} the regional
#' (unweighted, habitat-stratified) composition. `alpha`/`beta` carry a
#' Beta parameterization with total concentration \eqn{n_{eff} + m}, so the
#' prior's spread honestly reflects how many effective records back it.
#'
#' A hard grid cell is the special case of a top-hat kernel: with all
#' weights equal, `theta` reduces to ordinary record shares, `n_eff` to the
#' record count, and the singleton set to species seen exactly once.
#'
#' @section Why an estimator, not a spatial model:
#' Leave-one-cell-out validation on real Great Lakes data (2026-08-30 Phase 1
#' diagnostic) found distance-kernel composition prediction beats both a
#' single nearest cell (the previous architecture; worst of all options
#' tested) and unweighted regional pooling, with an interior bandwidth
#' optimum. The kernel runs in O(records) with no optimization step (~0.1 s
#' at 1.8 million records), so cost is independent of species count. Do NOT
#' replace this with per-species latent spatial fields (GP/SPDE/GAMM): that
#' family was evaluated during the original model design and is
#' computationally infeasible at many-species scale.
#'
#' @section Output schema (kernel-priors redesign):
#' The returned `$priors` table uses the post-redesign schema: `prior_branch`
#' (here always `"resident_observed"`: species with real local evidence in
#' the focal habitat) and `effective_records` (the species' kernel-effective
#' record count `c_i * n_eff / W`, in units of records) replace the retired
#' `model_tier` tier1/tier2 vocabulary. Undetected/evidence/domestic rows
#' belong to other branches and are appended by their own generators, not
#' this function.
#'
#' @param occurrence_data Data frame of cleaned, habitat-labelled occurrence
#'   records (one row per record).
#' @param site_lat,site_lon Numeric scalars. The sampling site coordinates.
#' @param site_habitat Character scalar. Focal habitat; records are
#'   stratified to `habitat_col == site_habitat` before any weighting.
#' @param lambda_km Numeric scalar. Geographic kernel bandwidth in km.
#'   Required, no default: the defensible value is dataset-specific -- derive
#'   it with [calibrate_kernel_bandwidth()] (leave-one-block-out composition
#'   prediction) rather than guessing.
#' @param m Numeric scalar >= 0. Regional pseudo-records for the Dirichlet
#'   back-off (default `1`, a weakly-informative single pseudo-record;
#'   tunable via [calibrate_kernel_bandwidth()]). `m = 0` disables
#'   shrinkage.
#' @param covariate_col Optional character. Name of a numeric record column
#'   (e.g. `"depth_m"`) for the product kernel. `NULL` (default) disables it.
#' @param site_covariate Numeric scalar. The site's own value of
#'   `covariate_col`. Required when `covariate_col` is supplied.
#' @param lambda_covariate Numeric scalar. Covariate kernel bandwidth, in the
#'   covariate's own units. Required when `covariate_col` is supplied.
#'   Records with `NA` covariate values receive the neutral weight 1 for the
#'   covariate factor (distance factor still applies) rather than being
#'   dropped.
#' @param site_id Character scalar. Identifier stamped on the output rows'
#'   `grid_id` column (kept under that name for downstream join
#'   compatibility; the value is treated as opaque everywhere downstream).
#'   Default: `"Site_<lat>_<lon>"`.
#' @param taxon_col,lat_col,lon_col,habitat_col Column names in
#'   `occurrence_data` (defaults `"taxon_name"`, `"decimalLatitude"`,
#'   `"decimalLongitude"`, `"main_habitat"`).
#' @param support_weight Numeric in (0, 1]. A record counts toward the
#'   discrete neighborhood-support statistics (singleton detection, record
#'   counts) when its total kernel weight is at least
#'   `support_weight` (default `exp(-3)`, i.e. within ~3 bandwidths).
#'   Continuous quantities (`theta`, `n_eff`) always use all records.
#'
#' @return An object of class `"taxaexpect_kernel_priors"`: a list with
#'   \describe{
#'     \item{priors}{Data frame: `taxon_name`, `grid_id`, `main_habitat`,
#'       `alpha`, `beta`, `theta_mean`, `theta_sd`, `prior_branch`,
#'       `effective_records`.}
#'     \item{n_eff}{Kish effective sample size at the site.}
#'     \item{W}{Total kernel weight.}
#'     \item{singletons}{Data frame of neighborhood singletons (species with
#'       exactly one supporting record): `taxon_name`, record `lat`/`lon`,
#'       `weight`, `effective_records`.}
#'     \item{missing_mass}{Weighted Good-Turing missing mass: the summed
#'       effective share of singleton species -- the budget available to the
#'       resident-undetected branch (consumed by later machinery, not here).}
#'     \item{regional_composition}{Named numeric: the unweighted
#'       habitat-stratified composition used for back-off.}
#'     \item{params}{The call's tuning values, for provenance.}
#'   }
#' @seealso [calibrate_kernel_bandwidth()] to choose `lambda_km`,
#'   `lambda_covariate`, and `m` by held-out prediction.
#' @export
estimate_kernel_priors <- function(occurrence_data,
                                   site_lat,
                                   site_lon,
                                   site_habitat,
                                   lambda_km,
                                   m = 1,
                                   covariate_col = NULL,
                                   site_covariate = NULL,
                                   lambda_covariate = NULL,
                                   site_id = NULL,
                                   taxon_col = "taxon_name",
                                   lat_col = "decimalLatitude",
                                   lon_col = "decimalLongitude",
                                   habitat_col = "main_habitat",
                                   support_weight = exp(-3)) {
  # ---- validation -----------------------------------------------------------
  if (!is.data.frame(occurrence_data) || nrow(occurrence_data) == 0L)
    stop("occurrence_data must be a non-empty data frame.")
  for (nm in c(taxon_col, lat_col, lon_col, habitat_col))
    if (!nm %in% names(occurrence_data))
      stop(sprintf("occurrence_data is missing required column '%s'.", nm))
  .chk_num <- function(x, nm, min_ok = -Inf) {
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < min_ok)
      stop(sprintf("%s must be a single non-NA numeric%s.", nm,
                   if (is.finite(min_ok)) sprintf(" >= %g", min_ok) else ""))
  }
  .chk_num(site_lat, "site_lat"); .chk_num(site_lon, "site_lon")
  if (missing(lambda_km))
    stop("lambda_km is required and has no default -- the defensible value is ",
         "dataset-specific. Derive it with calibrate_kernel_bandwidth() ",
         "(leave-one-block-out composition prediction).")
  .chk_num(lambda_km, "lambda_km", min_ok = .Machine$double.eps)
  .chk_num(m, "m", min_ok = 0)
  if (!is.character(site_habitat) || length(site_habitat) != 1L || is.na(site_habitat))
    stop("site_habitat must be a single non-NA character value.")
  use_cov <- !is.null(covariate_col)
  if (use_cov) {
    if (!covariate_col %in% names(occurrence_data))
      stop(sprintf("covariate_col '%s' not found in occurrence_data.", covariate_col))
    if (is.null(site_covariate) || is.null(lambda_covariate))
      stop("site_covariate and lambda_covariate are required when covariate_col is supplied.")
    .chk_num(site_covariate, "site_covariate")
    .chk_num(lambda_covariate, "lambda_covariate", min_ok = .Machine$double.eps)
  }
  if (!is.numeric(support_weight) || length(support_weight) != 1L ||
      is.na(support_weight) || support_weight <= 0 || support_weight > 1)
    stop("support_weight must be a single numeric in (0, 1].")
  if (is.null(site_id))
    site_id <- sprintf("Site_%.4f_%.4f", site_lat, site_lon)

  # ---- habitat stratum ------------------------------------------------------
  hab <- occurrence_data[[habitat_col]]
  keep <- !is.na(hab) & hab == site_habitat & !is.na(occurrence_data[[taxon_col]]) &
    !is.na(occurrence_data[[lat_col]]) & !is.na(occurrence_data[[lon_col]])
  if (!any(keep))
    stop(sprintf("No usable records with %s == '%s'.", habitat_col, site_habitat))
  rec <- occurrence_data[keep, , drop = FALSE]
  taxa <- as.character(rec[[taxon_col]])

  # ---- kernel weights -------------------------------------------------------
  d_km <- 111 * sqrt((rec[[lat_col]] - site_lat)^2 +
                     ((rec[[lon_col]] - site_lon) * cos(site_lat * pi / 180))^2)
  w <- exp(-d_km / lambda_km)
  if (use_cov) {
    cv <- rec[[covariate_col]]
    w_cov <- ifelse(is.na(cv), 1, exp(-abs(cv - site_covariate) / lambda_covariate))
    w <- w * w_cov
  }
  W <- sum(w)
  if (W <= 0) stop("All kernel weights are zero -- check coordinates and lambda_km.")
  n_eff <- W^2 / sum(w^2)
  s <- n_eff / W  # effective-scale factor

  # ---- compositions ---------------------------------------------------------
  c_raw <- tapply(w, taxa, sum)                       # kernel-weighted counts
  p_reg <- table(taxa); p_reg <- p_reg / sum(p_reg)   # regional back-off target
  sp <- sort(unique(taxa))
  c_eff <- as.numeric(c_raw[sp]) * s                  # effective-record counts
  p_i <- as.numeric(p_reg[sp])
  alpha <- c_eff + m * p_i
  beta <- (n_eff + m) - alpha
  theta <- alpha / (n_eff + m)
  theta_sd <- sqrt(alpha * beta / ((alpha + beta)^2 * (alpha + beta + 1)))

  # ---- neighborhood support + singletons ------------------------------------
  supported <- w >= support_weight
  n_support <- tapply(supported, taxa, sum)[sp]
  n_support[is.na(n_support)] <- 0L
  is_singleton <- n_support == 1L
  singles <- character(0)
  if (any(is_singleton)) singles <- sp[is_singleton]
  singletons <- do.call(rbind, lapply(singles, function(s_nm) {
    idx <- which(taxa == s_nm & supported)
    data.frame(taxon_name = s_nm,
               lat = rec[[lat_col]][idx[1L]],
               lon = rec[[lon_col]][idx[1L]],
               weight = w[idx[1L]],
               effective_records = as.numeric(c_raw[s_nm]) * s,
               stringsAsFactors = FALSE)
  }))
  if (is.null(singletons))
    singletons <- data.frame(taxon_name = character(0), lat = numeric(0),
                             lon = numeric(0), weight = numeric(0),
                             effective_records = numeric(0),
                             stringsAsFactors = FALSE)
  # Weighted Good-Turing missing mass: summed effective share of singleton
  # species (reduces to f1/n under a top-hat kernel). The resident-undetected
  # branch's budget -- emitted for downstream machinery, not consumed here.
  missing_mass <- if (nrow(singletons) > 0L)
    sum(as.numeric(c_raw[singletons$taxon_name])) / W else 0

  priors <- data.frame(
    taxon_name = sp,
    grid_id = site_id,
    main_habitat = site_habitat,
    alpha = alpha,
    beta = beta,
    theta_mean = theta,
    theta_sd = theta_sd,
    prior_branch = "resident_observed",
    effective_records = c_eff,
    stringsAsFactors = FALSE
  )
  priors <- priors[order(-priors$theta_mean), , drop = FALSE]
  rownames(priors) <- NULL

  structure(list(
    priors = priors,
    n_eff = n_eff,
    W = W,
    singletons = singletons,
    missing_mass = missing_mass,
    regional_composition = stats::setNames(p_i, sp),
    params = list(site_lat = site_lat, site_lon = site_lon,
                  site_habitat = site_habitat, site_id = site_id,
                  lambda_km = lambda_km, m = m,
                  covariate_col = covariate_col,
                  site_covariate = site_covariate,
                  lambda_covariate = lambda_covariate,
                  support_weight = support_weight,
                  n_records_stratum = nrow(rec))
  ), class = "taxaexpect_kernel_priors")
}

#' @export
print.taxaexpect_kernel_priors <- function(x, ...) {
  cat(sprintf(
    "taxaexpect_kernel_priors: %d taxa at %s (%s)\n  n_eff = %.0f effective records (of %d in stratum), lambda = %g km%s, m = %g\n  singletons: %d, Good-Turing missing mass: %.3g\n",
    nrow(x$priors), x$params$site_id, x$params$site_habitat,
    x$n_eff, x$params$n_records_stratum, x$params$lambda_km,
    if (!is.null(x$params$covariate_col))
      sprintf(", %s kernel lambda = %g", x$params$covariate_col,
              x$params$lambda_covariate) else "",
    x$params$m, nrow(x$singletons), x$missing_mass))
  invisible(x)
}
