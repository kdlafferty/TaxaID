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

# --- The run's taxon registry (taxa matched by GBIF id, not by name) ---
# The registry built once for the run (edge tables_to_registry) is reused here; the
# likelihoods and priors are stamped with it and join_priors() / posterior_consensus()
# match taxa by id. Used on its own (no earlier registry), this step builds one from
# the likelihood and prior names. Set {{use_taxon_registry}} to FALSE to join on names.
if (!exists("taxon_registry")) taxon_registry <- NULL
if (isTRUE({{use_taxon_registry}}) && is.null(taxon_registry)) {
  .reg_tab <- function(x, tab) {
    d <- unique(data.frame(verbatim_name = as.character(x$taxon_name),
                           rank_given = if ("taxon_name_rank" %in% names(x)) as.character(x$taxon_name_rank) else NA_character_,
                           source_table = tab, stringsAsFactors = FALSE))
    d[!is.na(d$verbatim_name) & nzchar(d$verbatim_name), , drop = FALSE]
  }
  taxon_registry <- TaxaTools::freeze_taxon_registry(TaxaTools::build_taxon_registry(
    rbind(.reg_tab({{lik_var}}, "likelihoods"), .reg_tab({{priors_var}}, "priors")),
    run_id = format(Sys.time(), "run-%Y%m%d-%H%M%S"), key_backbone_id = 11L,
    lookup = function(names, rank, context) TaxaFetch::lookup_gbif_taxa(names, rank, context, cache_dir = {{taxonomy_cache_dir}})
  ))
  invisible(TaxaTools::check_taxon_registry(taxon_registry, mode = "error"))
}
if (isTRUE({{use_taxon_registry}})) {
  {{lik_var}} <- TaxaTools::attach_taxon_ids({{lik_var}}, taxon_registry, "taxon_name", "likelihoods")
  {{priors_var}} <- TaxaTools::attach_taxon_ids({{priors_var}}, taxon_registry, "taxon_name", "priors")
}

# --- Join + posterior ---
detected_ranks <- TaxaTools::detect_ranks({{match_var}})

likelihoods_ready <- TaxaAssign::join_priors(
  likelihoods       = {{lik_var}},
  taxaexpect_priors = {{priors_var}},
  site              = site_spec,
  taxonomy_lookup   = {{match_var}},
  rank_system       = detected_ranks,
  backbone_id       = {{backbone_id}},
  taxonomy_cache_dir = {{taxonomy_cache_dir}},
  registry          = taxon_registry
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
