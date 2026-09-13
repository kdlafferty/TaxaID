# Edge: consensus + context_df -> reviewed
# Source: TaxaFlag/inst/review_assignments_workflow.R
# NOTE: When data comes from posterior_consensus(), run_llm_pipeline(), or
#   score_consensus(), the taxon column is "consensus_taxon" and rank column
#   is "consensus_rank". For external data (e.g. user-supplied CSV), use the
#   actual column names from the data.

# cache_dir (2026-09-04): a per-taxon verdict cache, keyed on everything that
# can move a verdict. Without it, the review is not reproducible -- two real
# GreatLakes runs 50 minutes apart on identical input disagreed about a
# species' geographic plausibility ("possible" then "unlikely"), so it
# appeared in one exported species list and not the other. Force fresh
# verdicts with TaxaFlag::taxaflag_clear_cache(<that directory>).
reviewed <- TaxaFlag::review_assignments(
  input_df       = {{consensus_var}},
  taxon_col      = {{taxon_col}},
  taxon_rank_col = {{taxon_rank_col}},
  context        = {{context_var}},
  target_group   = {{target_group}},
  marker         = {{marker}},
  llm_fn         = {{llm_fn}},
  cache_dir      = {{review_cache_dir}}
)
message("Reviewed ", nrow(reviewed), " assignments")
reviewed
