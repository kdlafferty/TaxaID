# Edge: likelihoods + priors -> posteriors
# Source: TaxaAssign join_priors() + compute_posterior()
# NOTE: {{lat}} and {{lon}} are numeric coordinates of the sampling site.
#   {{main_habitat}} is the habitat type (e.g. "Freshwater", "Marine",
#   "Estuarine"). This is required — the pipeline does not guess which
#   habitat your samples came from.

# --- Build site specification ---
site_spec <- list(lat = {{lat}}, lon = {{lon}}, main_habitat = {{main_habitat}})

# --- Join + posterior ---
detected_ranks <- TaxaTools::detect_ranks({{match_var}})

likelihoods_ready <- TaxaAssign::join_priors(
  likelihoods       = {{lik_var}},
  taxaexpect_priors = {{priors_var}},
  site              = site_spec,
  taxonomy_lookup   = {{match_var}},
  rank_system       = detected_ranks
)

posteriors <- TaxaAssign::compute_posterior(likelihoods_ready, n_sims = 1000L)
message("Computed posteriors for ", length(unique(posteriors$observation_id)), " samples")
posteriors
