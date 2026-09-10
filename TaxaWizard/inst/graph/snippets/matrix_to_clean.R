# Edge: reference_matrix + reference_df -> clean_refs
# Source: TaxaLikely/inst/workflows/2_flag_errors_workflow.R (rewritten 2026-09-08
# around TaxaMatch, after TaxaLikely::flag_reference_errors()'s retirement)

local_corr <- TaxaMatch::corroborate_references_locally(
  seq_matrix     = {{input_var}},
  reference_meta = {{refs_var}}
)
message("Local corroboration tiers: ", paste(names(table(local_corr$local_tier)), table(local_corr$local_tier), sep = "=", collapse = ", "))

ref_eval <- TaxaMatch::evaluate_reference_accessions(
  accessions                = unique({{refs_var}}$composite_id),
  barcode_term               = {{barcode_term}},
  local_corroboration        = local_corr,
  skip_locally_corroborated  = TRUE
)
bad_accessions <- ref_eval$accession[ref_eval$reference_action == "remove"]
message(length(bad_accessions), " accession(s) recommended for removal.")

clean_refs <- {{refs_var}}[!{{refs_var}}$composite_id %in% bad_accessions, ]
message("Removed flagged references. ", nrow(clean_refs), " rows remain.")
clean_refs
