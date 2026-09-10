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
#' @param lambda_latitude Optional numeric scalar. Bandwidth (km) for a
#'   climate-similarity factor `exp(-111 * ||lat| - |site_lat|| /
#'   lambda_latitude)` on the ABSOLUTE latitude difference -- records from
#'   the site's own climate band (same |latitude|, either hemisphere) keep
#'   full weight while records poleward/equatorward of it decay, making
#'   north-south kilometers cost more than east-west kilometers. `NULL`
#'   (default) disables the factor. Tunable via
#'   [calibrate_kernel_bandwidth()]'s `lambda_latitude_grid`.
#' @param site_id Character scalar. Identifier stamped on the output rows'
#'   `grid_id` column (kept under that name for downstream join
#'   compatibility; the value is treated as opaque everywhere downstream).
#'   Default: `"Site_<lat>_<lon>"`.
#' @param taxon_col,lat_col,lon_col,habitat_col Column names in
#'   `occurrence_data` (defaults `"taxon_name"`, `"decimalLatitude"`,
#'   `"decimalLongitude"`, `"main_habitat"`).
#' @param sampling_group_col Optional column naming a detection-process
#'   grouping (e.g. `"sampling_group"`). Default `NULL`: all taxa share one
#'   composition and one Good-Turing budget. \strong{This default is not a
#'   safe "do nothing" choice}: with no `sampling_group_col`, every record is
#'   pooled regardless of detection process, with no warning or error, even
#'   when that means silently mixing genuinely incompatible processes (e.g.
#'   phytoplankton cell counts with bird point counts). Grouping is never
#'   inferred automatically from taxonomy or data -- this function has no way
#'   to know which taxa were sampled by a comparable process, so it never
#'   guesses. Supplying a correct `sampling_group_col` is the caller's
#'   responsibility, built BY HAND from real knowledge of detection
#'   methodology -- there is no automated way to detect "comparable method"
#'   from taxonomy or data alone (an LLM guess is not a substitute for real
#'   methodological knowledge either). This is not a burdensome ask: this
#'   function does NOT require pre-merged, sample-size-adequate groups for
#'   statistical adequacy -- it degrades gracefully, producing honestly wide
#'   uncertainty for a sparse group on its own (empirically confirmed on a
#'   real 9-group expert classification down to a single-taxon group, see
#'   `README.md`'s "Shared detection effort" section) -- so classify at
#'   whatever granularity genuinely reflects distinct detection methods,
#'   without worrying whether each resulting group individually "has enough
#'   data." When supplied, `theta` AND the budget (`f1`, `f2`,
#'   `missing_mass`, `chao_missing`, `theta_present`) are computed WITHIN each
#'   group, because both are shared-denominator quantities that assume a
#'   common detection process. Pooling across processes dilutes a detectable
#'   taxon's share with records the assay could never amplify, and lets
#'   barely-sampled groups contribute singletons that inflate `f1` -- and so
#'   `chao_missing`, quadratically -- while adding almost nothing to
#'   `missing_mass`, deflating `theta_present` (`theta_present` is priced from
#'   `missing_mass / f1`, so a diluted `missing_mass` still deflates it even
#'   though `chao_missing` no longer sits in that formula). Note this is a
#'   no-op for a taxonomically homogeneous pool (a fish assay whose
#'   occurrence pool is all fish), which is why it changes nothing at sites
#'   like GreatLakes; it matters for broad markers (18S) spanning groups with
#'   very different detection probabilities. With more than one group the
#'   pooled scalars are `NA` by design and `$budget` is authoritative -- a
#'   single number would be silently wrong.
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
#'     \item{f1, f2}{Neighborhood-support singleton and doubleton species
#'       counts (records with kernel weight >= \code{support_weight}).}
#'     \item{chao_missing}{Chao (1984) estimated number of locally-present
#'       but unrecorded species: \code{f1^2/(2*f2)}, with the standard
#'       \code{f1*(f1-1)/2} fallback when \code{f2 = 0}; \code{0} when
#'       \code{f1 = 0}. Not part of \code{theta_present}'s price (see next
#'       item) -- kept for the budget AUDIT
#'       (\code{sum(w)} vs \code{chao_missing} in
#'       \code{\link{apply_undetected_evidence}}, reported not enforced).}
#'     \item{theta_present}{\code{missing_mass / f1}: the mean theta of the
#'       neighborhood's own observed singletons -- "a species we barely
#'       detect here" -- used by \code{\link{apply_undetected_evidence}}'s
#'       curve pricing. Deliberately NOT \code{missing_mass / chao_missing}
#'       (2026-09-05, open decision #1 of
#'       \code{REENTRY_PROMPT_kernel_budget_pricing_and_scope.md}, resolved):
#'       \code{f1} is observed directly, while \code{chao_missing} divides by
#'       the doubleton count \code{f2}, which sits in the single digits and
#'       is radius-unstable (measured 4x-21x across a plausible counting-radius
#'       range on real data) -- instability the price no longer inherits.
#'       \code{NA} when no singleton anchor exists (\code{f1 = 0}).}
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
                                   lambda_latitude = NULL,
                                   site_id = NULL,
                                   taxon_col = "taxon_name",
                                   lat_col = "decimalLatitude",
                                   lon_col = "decimalLongitude",
                                   habitat_col = "main_habitat",
                                   sampling_group_col = NULL,
                                   support_weight = exp(-3)) {
  # ---- validation -----------------------------------------------------------
  if (!is.data.frame(occurrence_data) || nrow(occurrence_data) == 0L) {
    stop("occurrence_data must be a non-empty data frame.")
  }
  for (nm in c(taxon_col, lat_col, lon_col, habitat_col)) {
    if (!nm %in% names(occurrence_data)) {
      stop(sprintf("occurrence_data is missing required column '%s'.", nm))
    }
  }
  .chk_num <- function(x, nm, min_ok = -Inf) {
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < min_ok) {
      stop(sprintf(
        "%s must be a single non-NA numeric%s.", nm,
        if (is.finite(min_ok)) sprintf(" >= %g", min_ok) else ""
      ))
    }
  }
  .chk_num(site_lat, "site_lat")
  .chk_num(site_lon, "site_lon")
  if (missing(lambda_km)) {
    stop(
      "lambda_km is required and has no default -- the defensible value is ",
      "dataset-specific. Derive it with calibrate_kernel_bandwidth() ",
      "(leave-one-block-out composition prediction)."
    )
  }
  .chk_num(lambda_km, "lambda_km", min_ok = .Machine$double.eps)
  .chk_num(m, "m", min_ok = 0)
  if (!is.character(site_habitat) || length(site_habitat) != 1L || is.na(site_habitat)) {
    stop("site_habitat must be a single non-NA character value.")
  }
  use_cov <- !is.null(covariate_col)
  if (use_cov) {
    if (!covariate_col %in% names(occurrence_data)) {
      stop(sprintf("covariate_col '%s' not found in occurrence_data.", covariate_col))
    }
    if (is.null(site_covariate) || is.null(lambda_covariate)) {
      stop("site_covariate and lambda_covariate are required when covariate_col is supplied.")
    }
    .chk_num(site_covariate, "site_covariate")
    .chk_num(lambda_covariate, "lambda_covariate", min_ok = .Machine$double.eps)
  }
  if (!is.null(lambda_latitude)) {
    .chk_num(lambda_latitude, "lambda_latitude", min_ok = .Machine$double.eps)
  }
  if (!is.numeric(support_weight) || length(support_weight) != 1L ||
    is.na(support_weight) || support_weight <= 0 || support_weight > 1) {
    stop("support_weight must be a single numeric in (0, 1].")
  }
  if (!is.null(sampling_group_col)) {
    if (!is.character(sampling_group_col) || length(sampling_group_col) != 1L) {
      stop("sampling_group_col must be a single column name, or NULL.")
    }
    if (!sampling_group_col %in% names(occurrence_data)) {
      stop(sprintf(
        "sampling_group_col '%s' not found in occurrence_data.",
        sampling_group_col
      ))
    }
  }
  if (is.null(site_id)) {
    site_id <- sprintf("Site_%.4f_%.4f", site_lat, site_lon)
  }

  # ---- habitat stratum ------------------------------------------------------
  hab <- occurrence_data[[habitat_col]]
  keep <- !is.na(hab) & hab == site_habitat & !is.na(occurrence_data[[taxon_col]]) &
    !is.na(occurrence_data[[lat_col]]) & !is.na(occurrence_data[[lon_col]])
  if (!any(keep)) {
    stop(sprintf("No usable records with %s == '%s'.", habitat_col, site_habitat))
  }
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
  if (!is.null(lambda_latitude)) {
    # Climate-similarity factor on ABSOLUTE latitude difference: two records at
    # the same |latitude| share a climate band regardless of hemisphere (a
    # 42 deg S temperate source is climatically ~0 deg from a 42 deg N site,
    # not 84 deg). Deliberately double-counts the N-S displacement already
    # inside d_km -- the product of the two decays is the intended anisotropy
    # (N-S km cost more than E-W km), same construction as the covariate
    # factor. lambda_latitude = NULL (default) disables it exactly.
    w <- w * exp(-111 * abs(abs(rec[[lat_col]]) - abs(site_lat)) / lambda_latitude)
  }
  # Fetch-radius check (2026-09-02). A record at 6 lambda carries exp(-6) =
  # 0.25% of the weight of one at the site, so if the record pool does not
  # reach ~6 lambda from the site, the kernel is being truncated by the FETCH
  # BOUNDARY rather than by distance -- the prior then reflects how far the
  # occurrence search went, not the species' distribution. Checked post hoc
  # because lambda is chosen from the data (see calibrate_kernel_bandwidth()).
  .reach <- if (length(d_km)) stats::quantile(d_km, 0.999, na.rm = TRUE) else NA_real_
  if (is.finite(.reach) && .reach < 6 * lambda_km) {
    warning(sprintf(
      "estimate_kernel_priors: the record pool reaches only ~%.0f km from the site but lambda_km = %g (6 lambda = %.0f km). The kernel is truncated by the fetch boundary; widen the occurrence search or treat these priors as radius-limited.",
      .reach, lambda_km, 6 * lambda_km
    ), call. = FALSE)
  }
  # ---- sampling-group strata ------------------------------------------------
  # Composition AND the Good-Turing budget are both shared-denominator
  # quantities: theta is a share of n_eff, and f1/f2/missing_mass describe the
  # unseen part of one sampling process. Pooling taxa that are detected by
  # DIFFERENT processes therefore breaks both -- a fish's share is diluted by
  # bird records that the assay could never have amplified, and singletons
  # contributed by barely-sampled groups inflate f1 while adding almost
  # nothing to missing_mass, deflating theta_present (= missing_mass/f1)
  # directly; f1 also inflates chao_missing (the separate budget-AUDIT
  # figure), quadratically. This is the same principle already adopted for
  # the GLMM path's effort
  # denominator (prepare_model_dataframe(sampling_group_col=), Session 149);
  # the kernel rewrite dropped it, and this restores it. Build the column
  # yourself, BY HAND, from real knowledge of detection methodology -- this
  # parameter is optional but NOT inferred automatically, and omitting it
  # silently pools every detection process with no warning (see the @param
  # doc above for the full reasoning, including why an automatic classifier
  # was tried and retired rather than recommended here).
  # NULL (default) = one group over the whole stratum = the pre-2026-09-03
  # behaviour, exactly (regression-tested).
  grp_all <- if (is.null(sampling_group_col)) {
    rep("__all__", nrow(rec))
  } else {
    as.character(rec[[sampling_group_col]])
  }
  grp_all[is.na(grp_all)] <- "__ungrouped__"
  grp_levels <- sort(unique(grp_all))

  .kernel_block <- function(idx) {
    w_g <- w[idx]
    taxa_g <- taxa[idx]
    W_g <- sum(w_g)
    if (W_g <= 0) {
      stop("All kernel weights are zero -- check coordinates and lambda_km.")
    }
    n_eff_g <- W_g^2 / sum(w_g^2)
    s_g <- n_eff_g / W_g # effective-scale factor

    # ---- compositions -------------------------------------------------------
    c_raw <- tapply(w_g, taxa_g, sum) # kernel-weighted counts
    p_reg <- table(taxa_g)
    p_reg <- p_reg / sum(p_reg) # regional back-off target
    sp <- sort(unique(taxa_g))
    c_eff <- as.numeric(c_raw[sp]) * s_g # effective-record counts
    p_i <- as.numeric(p_reg[sp])
    alpha <- c_eff + m * p_i
    beta <- (n_eff_g + m) - alpha
    theta <- alpha / (n_eff_g + m)
    theta_sd <- sqrt(alpha * beta / ((alpha + beta)^2 * (alpha + beta + 1)))

    # ---- neighborhood support + singletons ----------------------------------
    supported <- w_g >= support_weight
    n_support <- tapply(supported, taxa_g, sum)[sp]
    n_support[is.na(n_support)] <- 0L
    is_singleton <- n_support == 1L
    singles <- character(0)
    if (any(is_singleton)) singles <- sp[is_singleton]
    rec_g <- rec[idx, , drop = FALSE]
    singletons <- do.call(rbind, lapply(singles, function(s_nm) {
      j <- which(taxa_g == s_nm & supported)
      data.frame(
        taxon_name = s_nm,
        lat = rec_g[[lat_col]][j[1L]],
        lon = rec_g[[lon_col]][j[1L]],
        weight = w_g[j[1L]],
        effective_records = as.numeric(c_raw[s_nm]) * s_g,
        stringsAsFactors = FALSE
      )
    }))
    if (is.null(singletons)) {
      singletons <- data.frame(
        taxon_name = character(0), lat = numeric(0),
        lon = numeric(0), weight = numeric(0),
        effective_records = numeric(0),
        stringsAsFactors = FALSE
      )
    }
    # Weighted Good-Turing missing mass: summed effective share of singleton
    # species (reduces to f1/n under a top-hat kernel). The resident-undetected
    # branch's budget -- emitted for downstream machinery, not consumed here.
    missing_mass <- if (nrow(singletons) > 0L) {
      sum(as.numeric(c_raw[singletons$taxon_name])) / W_g
    } else {
      0
    }
    # Chao (1984) missing-species count from the neighborhood-support counts:
    # f1^2/(2 f2), with the standard f1(f1-1)/2 fallback when f2 = 0. Kept for
    # the budget AUDIT (sum(w) vs chao_missing, in apply_undetected_evidence()
    # -- an estimate of how many unseen species there are, never enforced).
    #
    # theta_present is priced from mass/f1, NOT mass/chao_missing (2026-09-05,
    # open decision #1 of REENTRY_PROMPT_kernel_budget_pricing_and_scope.md,
    # resolved). mass/Chao answers "what does the average ANONYMOUS unseen
    # species share" -- correct for that question, but Chao is radius-unstable
    # (measured: 4x at Mugu, 21x at GreatLakes, moving only the f1/f2 counting
    # radius) because it divides by f2, which sits in the single digits and
    # jitters. mass/f1 answers "what does a species we barely detect HERE
    # share" -- an OBSERVED quantity (f1 is counted, not estimated), and every
    # claimant this prices is itself a NAMED species with its own external
    # evidence (a nearby record, invasive-watch status, a verified iNat
    # range), which reads more like "a species we barely detect" than like the
    # average member of an unnamed, unobserved pool. Verified safe on real
    # GreatLakes posteriors: rescoring every curve-priced row by the resulting
    # 1.2x factor flips 0 of 880 winners. NA when f1 = 0 (no unseen-mass
    # anchor at all -- callers fall back to their own ladder).
    f1 <- sum(is_singleton)
    f2 <- sum(n_support == 2L)
    chao_missing <- if (f1 == 0L) {
      0
    } else if (f2 > 0L) {
      f1^2 / (2 * f2)
    } else {
      f1 * (f1 - 1) / 2
    }
    theta_present <- if (f1 > 0L) missing_mass / f1 else NA_real_

    list(
      sp = sp, alpha = alpha, beta = beta, theta = theta,
      theta_sd = theta_sd, c_eff = c_eff, p_i = p_i,
      n_eff = n_eff_g, W = W_g, singletons = singletons,
      missing_mass = missing_mass, f1 = f1, f2 = f2,
      chao_missing = chao_missing, theta_present = theta_present
    )
  }

  blocks <- lapply(grp_levels, function(g) .kernel_block(which(grp_all == g)))
  names(blocks) <- grp_levels
  grouped <- !is.null(sampling_group_col)

  # Single-taxon-group warning (2026-09-09). A group with exactly one
  # distinct taxon gets theta_mean = 1.0, theta_sd = 0 for that taxon --
  # mathematically correct given the compositional framing (100% of a
  # group's share when the group has one member, by construction), but not
  # an informative occurrence-probability estimate the way a multi-taxon
  # group's theta is, and could mislead a downstream reader into treating
  # "certain to be present" as the claim, rather than "the only thing we
  # have to compare it to." Computation is not blocked or altered -- this is
  # a warning, not an error -- see README.md's "Shared detection effort"
  # section for the real single-taxon-group example this is grounded in.
  if (grouped) {
    for (g in grp_levels) {
      if (length(blocks[[g]]$sp) == 1L) {
        warning(sprintf(
          "estimate_kernel_priors: sampling group '%s' contains only one distinct taxon (%s). Its theta_mean is trivially 1.0 by construction (100%% share of a group with one member) and does not reflect a real occurrence-probability estimate the way a multi-taxon group's does -- read it as \"the only thing we have to compare it to,\" not \"certain to be present.\"",
          g, blocks[[g]]$sp
        ), call. = FALSE)
      }
    }
  }

  budget <- do.call(rbind, lapply(grp_levels, function(g) {
    b <- blocks[[g]]
    data.frame(
      sampling_group = g, n_taxa = length(b$sp), n_eff = b$n_eff,
      f1 = b$f1, f2 = b$f2, missing_mass = b$missing_mass,
      chao_missing = b$chao_missing, theta_present = b$theta_present,
      stringsAsFactors = FALSE
    )
  }))
  if (!grouped) budget$sampling_group <- NA_character_
  rownames(budget) <- NULL

  # Scalars keep their meaning for the single-group case (every existing
  # caller). With real strata there is no single budget -- a scalar would be
  # silently wrong wherever it were used -- so they become NA and the per-group
  # table is authoritative. Consumers that need a scalar must fail loudly.
  one <- length(grp_levels) == 1L
  n_eff <- if (one) blocks[[1L]]$n_eff else sum(budget$n_eff)
  W <- if (one) blocks[[1L]]$W else sum(vapply(blocks, `[[`, numeric(1), "W"))
  missing_mass <- if (one) blocks[[1L]]$missing_mass else NA_real_
  f1 <- if (one) blocks[[1L]]$f1 else NA_integer_
  f2 <- if (one) blocks[[1L]]$f2 else NA_integer_
  chao_missing <- if (one) blocks[[1L]]$chao_missing else NA_real_
  theta_present <- if (one) blocks[[1L]]$theta_present else NA_real_

  singletons <- do.call(rbind, lapply(grp_levels, function(g) {
    s <- blocks[[g]]$singletons
    if (grouped && nrow(s) > 0L) s$sampling_group <- g
    s
  }))
  if (is.null(singletons)) {
    singletons <- data.frame(
      taxon_name = character(0), lat = numeric(0),
      lon = numeric(0), weight = numeric(0),
      effective_records = numeric(0),
      stringsAsFactors = FALSE
    )
  }

  sp <- unlist(lapply(blocks, `[[`, "sp"), use.names = FALSE)
  alpha <- unlist(lapply(blocks, `[[`, "alpha"), use.names = FALSE)
  beta <- unlist(lapply(blocks, `[[`, "beta"), use.names = FALSE)
  theta <- unlist(lapply(blocks, `[[`, "theta"), use.names = FALSE)
  theta_sd <- unlist(lapply(blocks, `[[`, "theta_sd"), use.names = FALSE)
  c_eff <- unlist(lapply(blocks, `[[`, "c_eff"), use.names = FALSE)
  p_i <- unlist(lapply(blocks, `[[`, "p_i"), use.names = FALSE)
  grp_of_taxon <- unlist(lapply(grp_levels, function(g) {
    rep(g, length(blocks[[g]]$sp))
  }), use.names = FALSE)

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
    # TRUE by construction (records are stratified to the focal habitat before
    # weighting) -- and load-bearing downstream: TaxaAssign::join_priors()'s
    # habitat-mismatch promotion clause falls back to legacy blanket promotion
    # when this column is absent from the priors table.
    observed_in_habitat = TRUE,
    stringsAsFactors = FALSE
  )
  # Added only when grouping is in use, so the ungrouped schema is untouched.
  if (grouped) priors$sampling_group <- grp_of_taxon
  priors <- priors[order(-priors$theta_mean), , drop = FALSE]
  rownames(priors) <- NULL
  # Return a TIBBLE, matching generate_full_priors()'s own return class: this
  # object is its drop-in replacement, and callers built against the GLMM path
  # rely on tibble `[` semantics. A plain data.frame silently DROPS a
  # single-column `[` selection to a bare vector (real breakage, found on the
  # first Mugu kernel run 2026-09-01: `priors[rows, c("taxon_name")] |>
  # left_join()` errored with "no applicable method for left_join applied to
  # an object of class character"). dplyr::bind_rows() also takes its output
  # class from its FIRST argument, so this keeps every assembled
  # taxaexpect_priors table a tibble exactly as the GLMM path did.
  priors <- tibble::as_tibble(priors)
  singletons <- tibble::as_tibble(singletons)

  structure(list(
    priors = priors,
    n_eff = n_eff,
    W = W,
    singletons = singletons,
    missing_mass = missing_mass,
    f1 = f1,
    f2 = f2,
    chao_missing = chao_missing,
    theta_present = theta_present,
    budget = budget,
    regional_composition = stats::setNames(p_i, sp),
    params = list(
      site_lat = site_lat, site_lon = site_lon,
      sampling_group_col = sampling_group_col,
      n_sampling_groups = length(grp_levels),
      site_habitat = site_habitat, site_id = site_id,
      lambda_km = lambda_km, m = m,
      covariate_col = covariate_col,
      site_covariate = site_covariate,
      lambda_covariate = lambda_covariate,
      lambda_latitude = lambda_latitude,
      support_weight = support_weight,
      # Column names recorded 2026-09-03 so the fit can be
      # re-computed from its own provenance -- kernel_budget_
      # sensitivity() re-runs the estimator rather than
      # reconstructing its statistics, and needs them.
      taxon_col = taxon_col, lat_col = lat_col,
      lon_col = lon_col, habitat_col = habitat_col,
      n_records_stratum = nrow(rec)
    )
  ), class = "taxaexpect_kernel_priors")
}

#' @export
print.taxaexpect_kernel_priors <- function(x, ...) {
  cat(sprintf(
    "taxaexpect_kernel_priors: %d taxa at %s (%s)\n  n_eff = %.0f effective records (of %d in stratum), lambda = %g km%s, m = %g\n  singletons: %d, Good-Turing missing mass: %.3g\n",
    nrow(x$priors), x$params$site_id, x$params$site_habitat,
    x$n_eff, x$params$n_records_stratum, x$params$lambda_km,
    paste0(
      if (!is.null(x$params$covariate_col)) {
        sprintf(
          ", %s kernel lambda = %g", x$params$covariate_col,
          x$params$lambda_covariate
        )
      } else {
        ""
      },
      if (!is.null(x$params$lambda_latitude)) {
        sprintf(", |lat| kernel lambda = %g km", x$params$lambda_latitude)
      } else {
        ""
      }
    ),
    x$params$m, nrow(x$singletons), x$missing_mass
  ))
  ng <- x$params$n_sampling_groups %||% 1L
  if (!is.null(x$params$sampling_group_col) && ng > 1L) {
    cat(sprintf(
      "  %d sampling groups ('%s') -- theta and the Good-Turing budget are WITHIN group;\n  the pooled f1/f2/Chao/theta_present scalars are NA by design, see $budget:\n",
      ng, x$params$sampling_group_col
    ))
    b <- x$budget
    b$n_eff <- round(b$n_eff, 1)
    b$missing_mass <- signif(b$missing_mass, 3)
    b$chao_missing <- round(b$chao_missing, 1)
    b$theta_present <- signif(b$theta_present, 3)
    print(b, row.names = FALSE)
  } else {
    # Print f1 and f2 with the budget they produce, ALWAYS -- not only in the
    # grouped case. theta_present is priced from mass/f1 (2026-09-05, open
    # decision #1, resolved), an OBSERVED quantity, so it no longer inherits
    # chao_missing's own doubleton-count instability -- but chao_missing
    # itself still does (f1^2/(2 f2), hypersensitive to f2 in single digits),
    # and it still drives the separate budget AUDIT (sum(w) vs chao_missing
    # in apply_undetected_evidence()), so it's still worth a reader's eye.
    # kernel_budget_sensitivity() quantifies the audit's own radius sensitivity.
    cat(sprintf(
      "  budget: f1 = %d, f2 = %d, chao_missing = %.3g, theta_present = %.3g\n",
      x$f1, x$f2, x$chao_missing, x$theta_present
    ))
  }
  # Both branches: name the doubleton counts chao_missing (the AUDIT figure,
  # not the price) is actually resting on. Only groups with a singleton
  # anchor (f1 > 0) have a budget to rest on.
  f2v <- x$budget$f2[!is.na(x$budget$f1) & x$budget$f1 > 0]
  f2v <- f2v[!is.na(f2v)]
  if (length(f2v) && min(f2v) < 10) {
    cat(sprintf(
      "  CAUTION: chao_missing (the budget AUDIT figure, not theta_present's price) rests on as few as %d doubleton(s) -- see kernel_budget_sensitivity(),\n           and report the radius sensitivity next to any audit figure.\n",
      min(f2v)
    ))
  }
  invisible(x)
}
