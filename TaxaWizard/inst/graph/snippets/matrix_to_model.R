# Edge: reference_matrix -> model_params
# Source: TaxaLikely train_likelihood_model()

model_params <- TaxaLikely::train_likelihood_model(
  raw_df        = {{input_var}},
  # Must equal the coverage floor the match object was built under:
  # TaxaMatch::blast_sequences(min_query_coverage = 80) -> 0.8.
  min_pair_coverage = 0.8,
  anchor_perfect = TRUE
)
message("Model trained: ", model_params$Stats$n_species, " species, AIC = ",
        round(model_params$Stats$AIC_Score, 1))
model_params
