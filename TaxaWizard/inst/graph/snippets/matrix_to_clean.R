# Edge: reference_matrix -> clean_refs
# Source: TaxaLikely/inst/workflows/2_flag_errors_workflow.R

errors <- TaxaLikely::flag_reference_errors({{input_var}})
message("Flagged ", sum(errors$error_type == "likely_mislabeled"), " mislabeled references")

clean_refs <- TaxaLikely::remove_flagged_references(
  match_df         = {{match_var}},
  reference_errors = errors
)
message("Removed flagged references. ", nrow(clean_refs), " rows remain.")
clean_refs
