# Edge: consensus + context_df -> reviewed
# Source: TaxaFlag/inst/review_assignments_workflow.R
# NOTE: When data comes from posterior_consensus(), run_llm_pipeline(), or
#   score_consensus(), the taxon column is "consensus_taxon" and rank column
#   is "consensus_rank". For external data (e.g. user-supplied CSV), use the
#   actual column names from the data.

reviewed <- TaxaFlag::review_assignments(
  df             = {{consensus_var}},
  taxon_col      = {{taxon_col}},
  taxon_rank_col = {{taxon_rank_col}},
  context        = {{context_var}},
  target_group   = {{target_group}},
  marker         = {{marker}},
  llm_fn         = {{llm_fn}}
)
message("Reviewed ", nrow(reviewed), " assignments")
reviewed
