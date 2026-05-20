# Edge: std_occurrences -> distributions
# Source: TaxaExpect/inst/TaxaExpect_workflow.R

grid_result <- TaxaExpect::optimize_grid_size(
  observation_data = {{input_var}},
  n_covariates     = 5L
)
message("Best grid size: ", grid_result$best_grid, " degrees")

distributions <- TaxaExpect::create_sites_from_grid(
  {{input_var}},
  grid_size = grid_result$best_grid
)
message("Created ", length(unique(distributions$grid_id)), " grid cells")
distributions
