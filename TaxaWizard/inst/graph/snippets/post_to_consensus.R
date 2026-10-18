# Edge: posteriors -> consensus
# Source: TaxaAssign/inst/TaxaAssign_bayesian_workflow.R

# Optional: group-level occurrence priors. consensus_prior
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

# Optional: species reference for posterior_consensus()'s downranking:
# a genus-level LCA is narrowed to a species only when the
# reference lists exactly one species of that genus. Because the
# priors table also holds a distance-clamp row for EVERY
# zero-record BLAST candidate, "in the priors table" does not mean
# "known locally": at Mugu a genus consensus (Pseudotolithus, three
# plausible congeners) was narrowed to P. senegallus, a West African croaker
# with posterior 0.009 that was never among the plausible set, and reported
# at the genus's 0.89. Clamp-only rows are therefore excluded here; resident,
# singleton-mirror, domestic and real-evidence (regional/invasive/iNat) rows
# stay.
# The exclusion is by prior_branch, not by the
# clamp source string. Every non-resident evidence row (distance clamp, regional
# proximity, watch list, iNat range) is resident_undetected and carries no local
# record, so none may be the sole taxon that narrows a coarse consensus. Residents
# and the named domestic/food (transport) rows remain eligible -- the same rule
# TaxaAssign::compute_group_priors(allowed_branches=) now applies at group scope.
# Set {{include_downranking}} to FALSE to skip entirely.
species_reference_df <- if (isTRUE({{include_downranking}})) {
  .not_clamp <- if ("prior_branch" %in% names({{taxaexpect_priors_var}})) {{taxaexpect_priors_var}}$prior_branch %in% c("kernel_estimated", "transport") else if ("evidence_sources" %in% names({{taxaexpect_priors_var}})) !({{taxaexpect_priors_var}}$evidence_sources %in% "distance_clamp") else rep(TRUE, nrow({{taxaexpect_priors_var}}))
  {{taxaexpect_priors_var}}[.not_clamp, , drop = FALSE] |>
    dplyr::filter(!is.na(taxon_name)) |>
    dplyr::distinct(taxon_name) |>
    dplyr::left_join({{taxonomy_map_var}}, by = "taxon_name") |>
    unique()
} else {
  NULL
}

# Consensus method: "credible_node" with robust_prior_s = 0 and
# cross_phylum_eps = 0 is the weighted LCA (node summing): the posterior of
# every hypothesis under a taxon is summed rank by rank from the finest, and
# the finest taxon holding at least cumulative_threshold of ALL the
# observation's posterior is reported. robust_prior_s = 0 turns off the
# imprecise-Dirichlet prior check and cross_phylum_eps = 0 the cross-phylum
# withholding, both of which only apply with "credible_node". The PACKAGE
# default remains consensus_method = "lca" (the lowest common taxon of the
# smallest top set reaching the threshold); this template sets the weighted
# form explicitly. Use the same three arguments in both calls below.
#
# The posterior table's pooled_n / pooled_prior_mass / pooled_taxa columns
# (see lik_prior_to_post) stay on the table: a ring row stands for the named
# unreferenced rows pooled into it, listed in pooled_taxa. posterior_consensus()
# reads the "pooled_rows" attribute to warn when min_posterior is set below the
# pooling floor (0.05), which would show those rows only through their ring;
# min_posterior = 0.05 below is not below it. The likelihoods' best_identity,
# best_identity_rank and poor_absolute_fit columns are carried onto the
# consensus table as unit-level columns, for review_assignments().
consensus <- TaxaAssign::posterior_consensus(
  {{input_var}},
  cumulative_threshold   = {{cumulative_threshold}},
  min_posterior           = 0.05,
  posterior_col           = "posterior_point_est",
  lookup_missing_taxonomy = TRUE,
  backbone_id             = 4,
  rank_system             = {{rank_system}},
  species_reference       = species_reference_df,
  group_priors            = group_priors_obj,
  consensus_method        = "credible_node",
  robust_prior_s          = 0,
  cross_phylum_eps        = 0
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
  species_reference       = species_reference_df,
  group_priors            = group_priors_obj,
  consensus_method        = "credible_node",
  robust_prior_s          = 0,
  cross_phylum_eps        = 0
) |> TaxaAssign::add_slash_taxon()
# add_slash_taxon() derives consensus_OTU + primary_taxon (present whenever
# consensus_taxon is in consensus_final).
message("Consensus: ", sum(consensus_final$is_resolved), " of ",
        nrow(consensus_final), " samples resolved")
consensus_final
