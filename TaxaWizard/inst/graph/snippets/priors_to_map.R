# Edge: priors -> prior_map
# Save-only. TaxaExpect::plot_theta_map_interactive() (GLMM/grid path,
# an interactive-map step) is retired
# along with the rest of the GLMM prior-fitting chain. The current visualizer,
# TaxaExpect::plot_theta_surface() (kernel path), needs the full kernel_fit
# object -- not just this flattened priors table -- so it is wired directly
# inside std_to_priors_kernel.R / dist_to_priors_by_group.R instead of here.

saveRDS({{input_var}}, {{output_path}})
message("Saved priors to: ", {{output_path}})
{{input_var}}
