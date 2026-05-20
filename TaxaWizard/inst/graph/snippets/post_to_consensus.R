# Edge: posteriors -> consensus
# Source: TaxaAssign/inst/TaxaAssign_bayesian_workflow.R

consensus <- TaxaAssign::posterior_consensus(
  {{input_var}},
  cumulative_threshold   = {{cumulative_threshold}},
  min_posterior           = 0.05,
  posterior_col           = "posterior_point_est",
  lookup_missing_taxonomy = TRUE,
  backbone_id             = 4,
  rank_system             = {{rank_system}}
)

# Optional: empirical Bayes refinement
posteriors_updated <- TaxaAssign::update_prior_from_consensus({{input_var}}, consensus)
consensus_final <- TaxaAssign::posterior_consensus(
  posteriors_updated,
  cumulative_threshold   = {{cumulative_threshold}},
  min_posterior           = 0.05,
  posterior_col           = "posterior_point_est",
  lookup_missing_taxonomy = TRUE,
  backbone_id             = 4,
  rank_system             = {{rank_system}}
)
message("Consensus: ", sum(consensus_final$is_resolved), " of ",
        nrow(consensus_final), " samples resolved")
consensus_final
