# Edge: likelihoods + priors + site_table -> posteriors (multi-site)
# Source: TaxaAssign join_priors() (multi-site data-frame "site" path,
#   TaxaAssign Session 138) + combine_multisite_priors() + compute_posterior()
# NOTE: {{backbone_id}} is required -- no default. Must match whichever
#   taxonomic backbone the input taxonomy was verified against (e.g. 11
#   for GBIF, 4 for NCBI).
# NOTE: {{site_habitat_lookup}} is a small data frame (spatial_group_id,
#   main_habitat) giving each site's own habitat type -- required if your
#   sites span more than one habitat. If every site shares the same
#   habitat, pass NULL here and {{main_habitat}} is used for every site.

detected_ranks <- TaxaTools::detect_ranks({{match_var}})

# --- Build the multi-site "site" data frame: one or more rows per
# observation_id (an observation detected at more than one site gets one
# row per site) ---
site_habitat_lookup <- {{site_habitat_lookup}}
if (is.null(site_habitat_lookup)) {
  site_habitat_lookup <- data.frame(
    spatial_group_id = unique({{site_table_var}}$spatial_group_id),
    main_habitat      = {{main_habitat}}
  )
}
site_spec <- merge(
  {{site_table_var}}[, c("observation_id", "lat", "lon", "spatial_group_id")],
  site_habitat_lookup,
  by = "spatial_group_id"
)
site_spec$spatial_group_id <- NULL

# --- Join priors per site, then combine multi-site candidates ---
likelihoods_ready <- TaxaAssign::join_priors(
  likelihoods       = {{lik_var}},
  taxaexpect_priors = {{priors_var}},
  site              = site_spec,
  taxonomy_lookup   = {{match_var}},
  rank_system       = detected_ranks,
  backbone_id       = {{backbone_id}}
)

# Combines duplicate (observation_id, taxon_name) rows produced by an
# observation detected at more than one site, via precision-weighted logit
# combination -- correctly discounts a low-confidence/sparse-data site
# rather than a plain average. Single-site candidates pass through
# unchanged.
likelihoods_combined <- TaxaAssign::combine_multisite_priors(likelihoods_ready)

posteriors <- TaxaAssign::compute_posterior(likelihoods_combined, n_sims = 1000L)
message("Computed posteriors for ", length(unique(posteriors$observation_id)),
        " samples across ", length(unique({{site_table_var}}$spatial_group_id)),
        " site(s)")
posteriors
