# Edge: posteriors -> consensus
# Source: TaxaAssign/inst/TaxaAssign_bayesian_workflow.R

# Optional: group-level occurrence priors (2026-07-30). consensus_prior
# becomes a real group-level SUM over every locally modelled member sharing
# a rank, instead of a candidate-scoped max -- a materially stronger
# occurrence-plausibility signal, since a single observation's own candidate
# set rarely contains every locally modelled group member. Requires the
# TaxaExpect priors object ({{taxaexpect_priors_var}}) and a taxonomy_map
# data frame with real genus/family columns ({{taxonomy_map_var}}, e.g. the
# occurrences_clean object from earlier in this pipeline). Set
# {{include_group_priors}} to FALSE to skip entirely.
group_priors_obj <- if (isTRUE({{include_group_priors}})) {
  TaxaAssign::compute_group_priors(
    taxaexpect_priors = {{taxaexpect_priors_var}},
    taxonomy_map      = {{taxonomy_map_var}}
  )
} else {
  NULL
}

consensus <- TaxaAssign::posterior_consensus(
  {{input_var}},
  cumulative_threshold   = {{cumulative_threshold}},
  min_posterior           = 0.05,
  posterior_col           = "posterior_point_est",
  lookup_missing_taxonomy = TRUE,
  backbone_id             = 4,
  rank_system             = {{rank_system}},
  group_priors            = group_priors_obj
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
  rank_system             = {{rank_system}},
  group_priors            = group_priors_obj
)
message("Consensus: ", sum(consensus_final$is_resolved), " of ",
        nrow(consensus_final), " samples resolved")
consensus_final
