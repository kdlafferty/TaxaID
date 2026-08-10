# Edge: distributions -> priors (grouped by sampling/detection process)
# Source: TaxaExpect_workflow.R + train_biodiversity_model_by_group()
# NOTE: {{sampling_group_col}} identifies which DETECTION METHOD/PROCESS
#   each row belongs to (e.g. "fish" vs "birds" vs "phytoplankton" surveyed
#   with different effort) -- this is NOT the same thing as a physical site.
#   Pooling groups with very different sampling effort into one model
#   silently distorts n_total_at_site for every taxon. Use this path only
#   when {{input_var}} already has a column identifying detection group;
#   otherwise use the plain dist_to_priors path.

model_data <- TaxaExpect::prepare_model_dataframe(
  {{input_var}},
  sampling_group_col = {{sampling_group_col}}
)
moran_basis <- TaxaExpect::compute_moran_basis(model_data, k = 5L)
model_data <- cbind(model_data, moran_basis)

formula_result <- TaxaExpect::screen_spatial_formula(
  model_data,
  sd_threshold = 0.20
)

# Fits one model per sampling_group_col value; sparse groups are dropped
# with a warning rather than failing the whole call.
group_models <- TaxaExpect::train_biodiversity_model_by_group(
  data               = {{input_var}},
  formula            = formula_result$formula,
  sampling_group_col = {{sampling_group_col}}
)
message("Fit ", length(group_models), " group-specific model(s): ",
        paste(names(group_models), collapse = ", "))

priors_list <- lapply(names(group_models), function(g) {
  group_sites <- model_data[model_data[[{{sampling_group_col}}]] == g, , drop = FALSE]
  TaxaExpect::generate_full_priors(
    model_obj = group_models[[g]],
    new_sites = group_sites
  )
})
priors <- dplyr::bind_rows(priors_list)

# Optional: add named domestic/commensal-animal and food-species priors
# (occurrence-database-under-counted species) -- set {{include_domestic_priors}}
# to FALSE to skip this step entirely.
if (isTRUE({{include_domestic_priors}})) {
  domestic_priors <- TaxaExpect::generate_domestic_food_priors(
    model_obj = group_models[[1]],
    lat       = {{lat}},
    lng       = {{lon}},
    grid_id   = NA_character_
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
        length(group_models), " sampling group(s)")
priors
