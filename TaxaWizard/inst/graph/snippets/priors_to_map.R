# Edge: priors -> prior_map
# Save-only. The interactive-map step this edge used to include,
# TaxaExpect::plot_theta_map_interactive() (GLMM/grid path), was archived
# 2026-09-09 along with the rest of the GLMM prior-fitting chain (see
# TaxaExpect/CLAUDE.md's 2026-09-09 session note). The current visualizer,
# TaxaExpect::plot_theta_surface() (kernel path), needs the full kernel_fit
# object -- not just this flattened priors table -- so it is wired directly
# inside std_to_priors_kernel.R / dist_to_priors_by_group.R instead of here.

saveRDS({{input_var}}, {{output_path}})
message("Saved priors to: ", {{output_path}})
{{input_var}}
