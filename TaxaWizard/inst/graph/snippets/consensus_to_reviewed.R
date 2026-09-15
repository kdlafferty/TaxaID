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
  cache_dir      = {{review_cache_dir}},
  # Abort rather than export a silently short species list. An LLM review can
  # parse cleanly, return the right number of objects, and still OMIT specific
  # taxa -- consistently the long compound slash labels, i.e. the hardest
  # rows. Those get NA in every llm_ column, and the usual export filters
  # (`llm_* != "unlikely"`) DISCARD NA, so the observation leaves the final
  # species list without a word. Measured on a real PtConception 12S run:
  # 20 observations across 3 plausible local fishes, gone. review_assignments()
  # now re-asks for omitted taxa; "error" makes any residue that survives the
  # re-ask stop the run instead of reaching the filters below.
  on_unreviewed  = "error"
)
message("Reviewed ", nrow(reviewed), " assignments")

# Always check: attributes do NOT survive a dplyr verb, so read this before
# any join or mutate.
if (length(attr(reviewed, "unreviewed_taxa"))) {
  message("  !! unreviewed: ",
          paste(attr(reviewed, "unreviewed_taxa"), collapse = ", "))
}
reviewed
