# Edge: distributions -> priors (manual path)
# Source: TaxaExpect/inst/TaxaExpect_workflow.R

model_data <- TaxaExpect::prepare_model_dataframe({{input_var}})
moran_basis <- TaxaExpect::compute_moran_basis(model_data, k = 5L)
model_data <- cbind(model_data, moran_basis)

formula_result <- TaxaExpect::screen_spatial_formula(
  model_data,
  sd_threshold = 0.20
)

model_fit <- TaxaExpect::train_biodiversity_model(
  model_data,
  formula = formula_result$formula
)

priors <- TaxaExpect::generate_full_priors(
  model_obj = model_fit,
  new_sites = model_data
)
saveRDS(model_fit, {{model_save_path}})
message("Generated priors for ", length(unique(priors$taxon_name)), " taxa")
priors
