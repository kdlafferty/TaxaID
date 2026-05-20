# Edge: likelihoods -> likelihood_df
# Source: save + summarize

saveRDS({{input_var}}, {{output_path}})
message("Saved likelihoods to: ", {{output_path}})

cat("\n=== Likelihood summary ===\n")
cat("Samples:", length(unique({{input_var}}$observation_id)), "\n")
cat("Taxa:", length(unique({{input_var}}$taxon_name)), "\n")
cat("Hypothesis types:\n")
print(table({{input_var}}$hypothesis_type))
{{input_var}}
