# Edge: likelihoods + priors -> posteriors
# Source: TaxaAssign join_priors() + compute_posterior()
# NOTE: {{lat}} and {{lon}} are numeric coordinates of the sampling site.
#   {{main_habitat}} is the habitat type (e.g. "Freshwater", "Marine",
#   "Estuarine"). This is required — the pipeline does not guess which
#   habitat your samples came from.
# NOTE: {{backbone_id}} is required — no default. Must match whichever
#   taxonomic backbone the input taxonomy was verified against (e.g. 11
#   for GBIF, 4 for NCBI).

# --- Build site specification ---
site_spec <- list(lat = {{lat}}, lon = {{lon}}, main_habitat = {{main_habitat}})

# --- Join + posterior ---
detected_ranks <- TaxaTools::detect_ranks({{match_var}})

likelihoods_ready <- TaxaAssign::join_priors(
  likelihoods       = {{lik_var}},
  taxaexpect_priors = {{priors_var}},
  site              = site_spec,
  taxonomy_lookup   = {{match_var}},
  rank_system       = detected_ranks,
  backbone_id       = {{backbone_id}}
)

# compute_posterior() pools named unreferenced rows whose point posterior is
# below 0.05 into their ring (the coarser relative they descend from) instead
# of carrying each as a candidate. Its output always has three pooled columns:
# pooled_n (rows pooled), pooled_prior_mass (their summed prior) and
# pooled_taxa (their names joined by "; "); they are NA on rows that are not
# rings. The pooled rows themselves are in attr(posteriors, "pooled_rows")
# (observation_id, ring_taxon, taxon_name, prior_mean, posterior_point_est).
# Attributes do NOT survive a dplyr verb: read it before any join or mutate.
posteriors <- TaxaAssign::compute_posterior(likelihoods_ready, n_sims = 1000L)
message("Pooled ", nrow(attr(posteriors, "pooled_rows")), " named unreferenced row(s) into rings")
message("Computed posteriors for ", length(unique(posteriors$observation_id)), " samples")
posteriors
