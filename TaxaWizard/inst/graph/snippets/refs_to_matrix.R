# Edge: reference_df -> reference_matrix
# Source: TaxaLikely build_reference_matrix()

ref_matrix <- TaxaLikely::build_reference_matrix(
  reference_df = {{input_var}}
)
message("Built reference matrix: ", nrow(ref_matrix), " pairwise comparisons")
ref_matrix
