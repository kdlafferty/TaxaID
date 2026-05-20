# Edge: priors -> prior_map
# Source: TaxaExpect plot_theta_map_interactive()

saveRDS({{input_var}}, {{output_path}})
message("Saved priors to: ", {{output_path}})

# Optional interactive map (requires leaflet + shiny)
# priors_occurrences is created by the taxa_to_priors_wrapper step
if (requireNamespace("leaflet", quietly = TRUE)) {
  TaxaExpect::plot_theta_map_interactive(
    {{input_var}},
    occurrences = if (exists("priors_occurrences")) priors_occurrences else NULL
  )
}
{{input_var}}
