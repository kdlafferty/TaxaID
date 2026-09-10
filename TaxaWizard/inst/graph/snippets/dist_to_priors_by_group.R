# Edge: std_occurrences -> priors (grouped by sampling/detection process, kernel path)
# Source: TaxaExpect kernel-priors redesign (2026-08-30/31) + the 2026-09-03
#   sampling_group_col restoration, e.g. PtConceptionWorkflow_18S_2_single_site.R
# NOTE: {{sampling_group_col}} identifies which DETECTION METHOD/PROCESS
#   each row belongs to (e.g. "fish" vs "birds" vs "phytoplankton" surveyed
#   with different effort) -- this is NOT the same thing as a physical site.
#   Pooling groups with very different sampling effort into one estimate
#   silently distorts every group's estimated composition AND its Good-Turing
#   budget (a barely-sampled group's singletons inflate f1 -- hence
#   chao_missing, quadratically -- while adding almost nothing to
#   missing_mass). Use this path only when {{input_var}} already has a column
#   identifying detection group; otherwise use the plain std_to_priors_kernel
#   path.
# 2026-09-09: rewritten from the retired GLMM-path wrapper
#   train_biodiversity_model_by_group() to the kernel-path equivalent. A
#   single estimate_kernel_priors(sampling_group_col=) call handles every
#   group at once (no per-group model-fitting loop needed) -- this snippet
#   works directly on standardized occurrence data, no gridding step
#   (create_sites_from_grid()/the old "distributions" intermediate) needed,
#   so this edge's own `from` was corrected from "distributions" to
#   "std_occurrences" the same session the whole GLMM chain (including
#   "distributions"'s only other consumer, dist_to_priors) was archived --
#   see TaxaExpect/archive_glmm_prior_pipeline/ and TaxaExpect/CLAUDE.md's
#   2026-09-09 session note.

std_occurrences <- {{input_var}}

# Step 1: calibrate the kernel bandwidth once, on the POOLED data -- lambda_km
# describes spatial decay, not detection-process membership, so one bandwidth
# applies across every group.
kernel_cal <- TaxaExpect::calibrate_kernel_bandwidth(
  std_occurrences,
  site_habitat = {{site_habitat}},
  lambda_grid  = c(25, 50, 100, 200)
)
message(sprintf(
  "Calibrated kernel bandwidth: lambda = %g km (LOBO loss %.3f)",
  kernel_cal$best$lambda_km, kernel_cal$best$weighted_logloss
))

# Step 2: estimate site priors, computing composition AND the Good-Turing
# budget WITHIN each sampling_group_col value rather than pooled. With more
# than one group the pooled f1/f2/chao_missing/theta_present scalars are NA
# by design (no single budget exists across detection processes) -- $budget
# is the authoritative per-group table.
kernel_priors_fit <- TaxaExpect::estimate_kernel_priors(
  std_occurrences,
  site_lat           = {{lat}},
  site_lon           = {{lon}},
  site_habitat       = {{site_habitat}},
  lambda_km          = kernel_cal$best$lambda_km,
  site_id            = sprintf("Site_%.2f_%.2f", {{lat}}, {{lon}}),
  sampling_group_col = {{sampling_group_col}}
)
print(kernel_priors_fit)
message("Per-group budget:")
print(kernel_priors_fit$budget)

# Step 3: unseen-taxa floor (Good-Turing/Chao-based dark-diversity mirrors,
# stamped with this site's own id). Each singleton mirror is scaled by its
# OWN group's n_eff (not the pooled total), so this single call correctly
# handles every group at once -- no per-group loop needed.
priors_undetected <- TaxaExpect::generate_undetected_diversity(
  model_obj = kernel_priors_fit,
  taxonomy  = std_occurrences
)

priors <- dplyr::bind_rows(kernel_priors_fit$priors, priors_undetected) |>
  dplyr::mutate(taxon_name_rank = "species")

message(sprintf(
  "Generated priors for %d resident taxa + %d undetected/dark-diversity row(s) across %d sampling group(s)",
  sum(priors$prior_branch == "resident_observed", na.rm = TRUE),
  sum(priors$prior_branch == "resident_undetected", na.rm = TRUE),
  dplyr::n_distinct(std_occurrences[[{{sampling_group_col}}]])
))

# Optional: add named domestic/commensal-animal and food-species priors --
# these are a contamination-risk claim, not an occurrence-plausibility one,
# and are deliberately priced on a POOLED fit, not per-group: a domestic/food
# species isn't scoped to one detection process. Set
# {{include_domestic_priors}} to FALSE to skip this step entirely.
if (isTRUE({{include_domestic_priors}})) {
  kernel_priors_pooled <- TaxaExpect::estimate_kernel_priors(
    std_occurrences,
    site_lat     = {{lat}},
    site_lon     = {{lon}},
    site_habitat = {{site_habitat}},
    lambda_km    = kernel_cal$best$lambda_km,
    site_id      = kernel_priors_fit$params$site_id
  )
  domestic_priors <- TaxaExpect::generate_domestic_food_priors(
    model_obj = kernel_priors_pooled,
    lat       = {{lat}},
    lng       = {{lon}},
    grid_id   = kernel_priors_fit$params$site_id
  )
  priors <- dplyr::bind_rows(priors, domestic_priors)
  message("Added ", nrow(domestic_priors), " domestic/food-species prior row(s)")
}

priors <- TaxaTools::verify_taxon_names(priors, taxon_col = "taxon_name")
priors <- TaxaMatch::convert_taxonomy_backbone(
  priors,
  target_backbone_id = {{target_backbone_id}},
  taxon_col           = "taxon_name"
)
message("Generated priors for ", length(unique(priors$taxon_name)), " taxa across ",
        dplyr::n_distinct(std_occurrences[[{{sampling_group_col}}]]), " sampling group(s)")
priors
