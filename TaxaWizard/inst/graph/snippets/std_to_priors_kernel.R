# Edge: std_occurrences -> priors (kernel-based alternative to the GLMM/grid path)
# Source: real production kernel-priors path (2026-08-30/31 redesign), e.g.
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
kernel_cal <- TaxaExpect::calibrate_kernel_bandwidth(
  std_occurrences,
  site_habitat = {{site_habitat}},
  lambda_grid  = c(25, 50, 100, 200)
)
message(sprintf(
  "Calibrated kernel bandwidth: lambda = %g km (LOBO loss %.3f)",
  kernel_cal$best$lambda_km, kernel_cal$best$weighted_logloss
))

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
  sum(priors$prior_branch == "resident_observed", na.rm = TRUE),
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

# Optional: static KDE prior-field map for one focal taxon (2026-09-01,
# TaxaExpect::plot_theta_surface()) -- the kernel path's own visualizer,
# replacing plot_theta_map_interactive() (which parses Grid_<lat>_<lon> ids
# into centroids and has nothing to draw for a single opaque kernel site_id).
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
