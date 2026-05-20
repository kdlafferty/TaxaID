# Edge: consensus + context_df -> reviewed
# Source: TaxaFlag/inst/review_assignments_workflow.R
# NOTE: posterior_consensus() and run_llm_pipeline()$consensus produce
#   consensus_taxon (not taxon_name) and consensus_rank (not taxon_name_rank).
#   score_consensus() also uses consensus_taxon / consensus_rank.

reviewed <- TaxaFlag::review_assignments(
  df             = {{consensus_var}},
  taxon_col      = "consensus_taxon",
  taxon_rank_col = "consensus_rank",
  context        = {{context_var}},
  target_group   = {{target_group}},
  marker         = {{marker}},
  llm_fn         = {{llm_fn}}
)
message("Reviewed ", nrow(reviewed), " assignments")
reviewed
