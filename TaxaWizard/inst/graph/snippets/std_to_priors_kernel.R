# Edge: std_occurrences -> priors (kernel-based alternative to the GLMM/grid path)
# Source: real production kernel-priors path, e.g.
# GreatLakes2023_ConsensusWorkflow.R / PtConceptionWorkflow_18S_2_single_site.R
#
# Site-centered distance-kernel estimation -- a genuinely different estimator
# from dist_to_priors.R's GLMM/grid-cell prediction, not an add-on step, so
# this is its own edge rather than a gated extension of that one. Works
# directly on standardized occurrence data (no gridding/create_sites_from_grid()
# step needed at all -- the kernel weights each record by its own distance from
# the site, so there is no grid cell to assign records to).

std_occurrences <- {{input_var}}

# Step 1: calibrate the kernel bandwidth via leave-one-block-out composition
# prediction (this path's replacement for the GLMM path's AIC formula
# screening). Seconds, offline, no live network calls.
# lambda_grid spans 1-100 km deliberately. A grid that cannot express its own
# answer reports a boundary warning pointing the wrong way: PtConception 12S
# measured its optimum at 10 km, INTERIOR, only once 1/2/5 were offered -- the
# old c(25, 50, 100, 200) could not represent 10 at all and would have invited
# widening UPWARD. Keep this in step with the canonical workflow template.
#
# This edge is the SINGLE-group path: there is no sampling_group_col here, so
# the pooled calibration is correct. When a pool genuinely has several
# detection processes, use the dist_to_priors_by_group edge, which passes
# sampling_group_col to BOTH the calibration and the estimator.
kernel_cal <- TaxaExpect::calibrate_kernel_bandwidth(
  std_occurrences,
  site_habitat = {{site_habitat}},
  lambda_grid  = c(1, 2, 5, 10, 25, 50, 100)
)
message(sprintf(
  "Calibrated kernel bandwidth: lambda = %g km (LOBO loss %.3f)",
  kernel_cal$best$lambda_km, kernel_cal$best$weighted_logloss
))

# Is the kernel worth having at all? An interior optimum says only "best
# bandwidth offered", never that the kernel beats NOT having one. $results
# carries `regional` and `nearest_block` reference rows, by row name.
.k_loss   <- kernel_cal$best$weighted_logloss
.reg_loss <- kernel_cal$results["regional", "weighted_logloss"]
.nb_loss  <- kernel_cal$results["nearest_block", "weighted_logloss"]
message(sprintf(
  "LOBO log-loss: kernel %.4f | regional %.4f | nearest_block %.4f",
  .k_loss, .reg_loss, .nb_loss
))
.gain <- .reg_loss - .k_loss
.pct  <- 100 * .gain / .reg_loss
if (!is.na(.gain) && .gain <= 0) {
  warning(sprintf(
    paste0("kernel does NOT beat regional (%.4f vs %.4f). The answer is not a ",
           "different lambda but a smaller block_size_deg."),
    .k_loss, .reg_loss
  ), call. = FALSE)
} else {
  message(sprintf("kernel beats regional by %.4f (%.2f%%)", .gain, .pct))
  if (!is.na(.pct) && .pct < 1) {
    warning(sprintf(
      paste0("kernel margin over regional is only %.2f%% -- lambda may be an ",
             "artifact of the CV block geometry rather than a real length scale."),
      .pct
    ), call. = FALSE)
  }
}

# Step 2: estimate site priors from the calibrated bandwidth.
kernel_priors_fit <- TaxaExpect::estimate_kernel_priors(
  std_occurrences,
  site_lat     = {{lat}},
  site_lon     = {{lon}},
  site_habitat = {{site_habitat}},
  lambda_km    = kernel_cal$best$lambda_km,
  site_id      = sprintf("Site_%.2f_%.2f", {{lat}}, {{lon}})
)
print(kernel_priors_fit)

# Step 3: unseen-taxa floor (Good-Turing/Chao-based dark-diversity mirrors,
# stamped with this site's own id) -- the kernel path's analog of the GLMM
# path's generate_undetected_diversity() call.
priors_undetected <- TaxaExpect::generate_undetected_diversity(
  model_obj = kernel_priors_fit,
  taxonomy  = std_occurrences
)

priors <- dplyr::bind_rows(kernel_priors_fit$priors, priors_undetected) |>
  dplyr::mutate(taxon_name_rank = "species")

message(sprintf(
  "Generated priors for %d resident taxa + %d undetected/dark-diversity row(s) (kernel n_eff = %.0f)",
  sum(priors$prior_branch %in% c("kernel_estimated"), na.rm = TRUE),
  sum(priors$prior_branch == "resident_undetected", na.rm = TRUE),
  kernel_priors_fit$n_eff
))

# Optional: add named domestic/commensal-animal and food-species priors --
# same rationale as the GLMM path's dist_to_priors.R (GBIF/iNaturalist
# occurrence data structurally under-counts these species). Set
# {{include_domestic_priors}} to FALSE to skip this step entirely.
if (isTRUE({{include_domestic_priors}})) {
  domestic_priors <- TaxaExpect::generate_domestic_food_priors(
    model_obj = kernel_priors_fit,
    lat       = {{lat}},
    lng       = {{lon}},
    grid_id   = kernel_priors_fit$params$site_id
  )
  priors <- dplyr::bind_rows(priors, domestic_priors)
  message("Added ", nrow(domestic_priors), " domestic/food-species prior row(s)")
}

# Optional: evidence block (curve pricing) -- elevates the dark-diversity
# floor for candidates with a regional record just outside the site, a named
# invasive/watch-listed species, or a verified iNaturalist range, instead of
# leaving every zero-record candidate at one flat clamp. Faithful port of the
# real production block (PtConceptionWorkflow_12S_single_site.R, curve-pricing
# branch, ~line 1485-1590). Set {{include_evidence_block}} to FALSE to skip
# entirely.
if (isTRUE({{include_evidence_block}})) {
  # ==========================================================================
  # Curve pricing: theta = w * theta_present (theta_present from the kernel
  # fit's own Good-Turing budget; theta_absent = 0). One presence-distance
  # curve prices every unobserved claimant; a watch-listed species gets a
  # K_LIFT bandwidth stretch at its own nearest-record distance; leftovers
  # get the distance clamp. w_scale = 0.05 carries the GreatLakes checklist
  # calibration -- recalibrate per-site when a local checklist is in hand
  # (TaxaExpect::fit_regional_presence_curve()).
  # ==========================================================================
  W_SCALE <- 0.05; D_HALF <- 150; D_CAP <- 1000; K_LIFT <- 2
  # The zero-evidence clamp -- DERIVED, never a literal (a
  # hardcoded 0.05 * exp(-1000/150) drifts out of sync with W_SCALE/D_CAP/
  # D_HALF above; this is the real failure mode it guards against).
  W_CLAMP <- W_SCALE * exp(-D_CAP / D_HALF)

  # {{match_list_taxa}}: character vector of every candidate taxon this run
  # needs evidence-priced -- e.g. the species-rank taxon names from the
  # match/BLAST object earlier in this pipeline:
  #   unique(stats::na.omit(match_df$taxon_name[match_df$taxon_name_rank == "species"]))
  # Zero-record ("clamp") taxa = match-list taxa absent from the priors table.
  zero_bbox_taxa <- setdiff({{match_list_taxa}}, priors$taxon_name)

  # --- Habitat conditioning of presence evidence ----------------------------
  # Evidence rows must obey the SAME habitat stratification the resident
  # priors already do (a record only enters the site pool when its point
  # carries the site habitat) -- otherwise a distant record of a species that
  # never occupies the site habitat can be priced above a local population of
  # the same species. w_site = max(w * H_site, W_CLAMP); H_site is the
  # taxon's weight for {{site_habitat}} from the SAME habitat lookup the
  # residents' point votes use. {{habitat_lookup_var}} is the habitat lookup
  # table built in the occ_to_std edge (TaxaHabitat::build_habitat_lookup());
  # any evidence taxon not already classified there (e.g. a regional/
  # zero-bbox candidate never seen in the occurrence data) is classified
  # fresh here, served from the same cache_dir so nothing already-classified
  # is re-asked.
  .habitat_condition <- function(ev) {
    if (is.null(ev) || nrow(ev) == 0L) return(ev)
    .hab <- {{habitat_lookup_var}}
    .new_taxa <- setdiff(unique(ev$taxon_name), .hab$taxon_name)
    if (length(.new_taxa) > 0L) {
      .hab_new <- TaxaHabitat::build_habitat_lookup(
        .new_taxa,
        habitat_scheme = {{habitat_scheme}},
        llm_fn         = {{llm_fn}},
        cache_dir      = {{habitat_cache_dir}},
        verbose        = FALSE
      )
      .hab <- dplyr::bind_rows(.hab, .hab_new)
    }
    TaxaExpect::condition_evidence_on_habitat(
      ev, .hab, {{site_habitat}}, w_floor = W_CLAMP
    )
  }

  # Step A: regional-proximity evidence -- a real, quality-filtered GBIF
  # record just outside the site elevates the floor by w = w_scale *
  # exp(-distance_km/d_half). {{year_range}} is the study's OWN window (e.g.
  # "1995,2026") -- the package default (2000-to-now) is deliberately NOT
  # relied on here, since an out-of-window museum specimen can otherwise
  # drive a species call on its own.
  regional_evidence <- TaxaExpect::generate_regional_proximity_evidence(
    zero_bbox_taxa = zero_bbox_taxa,
    lat            = {{lat}},
    lng            = {{lon}},
    year_range     = {{year_range}},
    w_scale        = W_SCALE
  )
  regional_evidence <- .habitat_condition(regional_evidence)

  # Step B: named invasive/watch-listed species get a K_LIFT bandwidth
  # stretch at their own nearest-record distance instead of the plain
  # regional curve. {{invasive_taxa}}: character vector of watch-listed
  # taxon names, or NULL to skip this sub-step entirely (no default watch
  # list exists generically -- supply one from an invasive-species
  # candidate table if this study has one).
  if (!is.null({{invasive_taxa}})) {
    watch_in_list <- intersect({{invasive_taxa}}, {{match_list_taxa}})
    d_lookup <- stats::setNames(regional_evidence$distance_km, regional_evidence$taxon_name)
    if (length(watch_in_list) > 0L) {
      watch_evidence <- TaxaExpect::generate_presence_curve_evidence(
        watch_in_list,
        w_scale     = W_SCALE,
        distance_km = d_lookup,
        d_half      = D_HALF,
        d_cap       = D_CAP,
        k           = K_LIFT,
        p_conc      = {{invasive_watch_p_conc}},
        source      = "invasive_watch"
      )
      watch_evidence <- .habitat_condition(watch_evidence)
      priors <- dplyr::bind_rows(priors, TaxaExpect::apply_undetected_evidence(
        priors, kernel_priors_fit, watch_evidence,
        grid_id      = kernel_priors_fit$params$site_id,
        main_habitat = {{site_habitat}},
        taxonomy     = {{taxonomy_lookup}},
        pricing      = "curve"
      ))
    }
    regional_kept <- dplyr::filter(regional_evidence, !taxon_name %in% watch_in_list)
  } else {
    regional_kept <- regional_evidence
  }
  if (nrow(regional_kept) > 0L) {
    priors <- dplyr::bind_rows(priors, TaxaExpect::apply_undetected_evidence(
      priors, kernel_priors_fit, regional_kept,
      grid_id      = kernel_priors_fit$params$site_id,
      main_habitat = {{site_habitat}},
      taxonomy     = {{taxonomy_lookup}},
      pricing      = "curve"
    ))
  }

  # Step C: iNaturalist range evidence -- a zero-bbox candidate whose
  # verified iNat range covers the site is close to observed (w = 0.8
  # default, gated on name_match). Live iNat API call; needs
  # {{inat_cache_dir}} (a directory for its own persistent cache) and the
  # INAT_API_TOKEN environment variable.
  zero_bbox_remaining <- setdiff(zero_bbox_taxa, priors$taxon_name)
  if (length(zero_bbox_remaining) > 0L) {
    .inat_cache_dir <- {{inat_cache_dir}}
    if (!dir.exists(.inat_cache_dir)) dir.create(.inat_cache_dir, recursive = TRUE)
    inat_zero_bbox <- TaxaFetch::check_inat_range(
      taxon_names = zero_bbox_remaining,
      lat         = {{lat}},
      lng         = {{lon}},
      api_token   = Sys.getenv("INAT_API_TOKEN"),
      cache_dir   = .inat_cache_dir,
      verbose     = FALSE
    )
    inat_evidence <- TaxaExpect::generate_inat_range_evidence(inat_zero_bbox)
    inat_evidence <- .habitat_condition(inat_evidence)
    priors <- dplyr::bind_rows(priors, TaxaExpect::apply_undetected_evidence(
      priors, kernel_priors_fit, inat_evidence,
      grid_id      = kernel_priors_fit$params$site_id,
      main_habitat = {{site_habitat}},
      taxonomy     = {{taxonomy_lookup}},
      pricing      = "curve"
    ))
  }

  # Step D: everything still zero-record after A-C gets the plain distance
  # clamp (no regional/watch/iNat evidence found at all).
  clamp_taxa <- setdiff({{match_list_taxa}}, priors$taxon_name)
  if (length(clamp_taxa) > 0L) {
    clamp_evidence <- TaxaExpect::generate_presence_curve_evidence(
      clamp_taxa, w_scale = W_SCALE, d_half = D_HALF, d_cap = D_CAP
    )
    priors <- dplyr::bind_rows(priors, TaxaExpect::apply_undetected_evidence(
      priors, kernel_priors_fit, clamp_evidence,
      grid_id      = kernel_priors_fit$params$site_id,
      main_habitat = {{site_habitat}},
      taxonomy     = {{taxonomy_lookup}},
      pricing      = "curve"
    ))
  }

  # ---- Branch-budget audit (an AUDIT, never a gate -- nothing here refuses
  # or rescales a price; it only reports sum(w) against the kernel fit's own
  # Chao estimate of locally-present-but-unrecorded species, so a reader can
  # see whether the evidence just added is plausible in aggregate) ---------
  evb <- priors[!is.na(priors$undetected_type) & priors$undetected_type == "evidence_blend", ]
  sw <- tapply(evb$prior_mix_w, evb$evidence_sources, sum)
  message("\n---- BRANCH-BUDGET AUDIT (curve pricing) ----")
  message(sprintf(
    "  theta_present = %.3g (GT mass %.3g / Chao %.1f; f1 = %d, f2 = %d)",
    kernel_priors_fit$theta_present, kernel_priors_fit$missing_mass,
    kernel_priors_fit$chao_missing, kernel_priors_fit$f1, kernel_priors_fit$f2
  ))
  message(paste(sprintf("  sum(w) %-28s = %6.2f", names(sw), sw), collapse = "\n"))
  message(sprintf(
    "  TOTAL sum(w) = %.2f vs Chao %.1f expected present unseen species %s",
    sum(evb$prior_mix_w), kernel_priors_fit$chao_missing,
    if (sum(evb$prior_mix_w) <= kernel_priors_fit$chao_missing) "(within budget)" else "(OVER budget -- recalibrate w)"
  ))
}

# Optional: static KDE prior-field map for one focal taxon
# (TaxaExpect::plot_theta_surface()) -- the kernel path's own visualizer,
# replacing the retired plot_theta_map_interactive() (GLMM/grid path --
# it parsed Grid_<lat>_<lon> ids into centroids and
# had nothing to draw for a single opaque kernel site_id).
# Needs kernel_priors_fit itself (not just the flattened priors table), so
# this lives here rather than in the generic priors_to_map.R edge. Set
# {{plot_theta_surface_taxon}} to NULL (default) to skip; a real taxon_name
# string (e.g. "Gadus morhua") renders the field for just that taxon.
if (!is.null({{plot_theta_surface_taxon}})) {
  theta_surface <- TaxaExpect::plot_theta_surface(
    kernel_fit      = kernel_priors_fit,
    occurrence_data = std_occurrences,
    taxon           = {{plot_theta_surface_taxon}}
  )
  print(theta_surface)
}

message("Generated priors for ", length(unique(priors$taxon_name)), " taxa (kernel path)")
priors
