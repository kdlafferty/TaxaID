# Edge: likelihoods + priors + site_table -> posteriors (multi-site)
# Source: TaxaAssign join_priors() (multi-site data-frame "site" path)
#   + combine_multisite_priors() + compute_posterior()
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
  # each name's own lineage from these tables as its context (kingdom to family; none where the tables disagree): it
  # refuses a cross-phylum homonym and breaks genus/species ties; at family and above the GBIF backbone decides
  .reg_ctx <- function(d, tabs) {
    lr <- c("kingdom", "phylum", "class", "order", "family", "genus")
    rows <- do.call(rbind, lapply(tabs, function(x) {
      lc <- intersect(lr, names(x)); if (!length(lc)) return(NULL); x <- as.data.frame(x); out <- list()
      mk <- function(n, r) data.frame(name = as.character(n), rank = r, value = as.character(x[[r]]), stringsAsFactors = FALSE)
      if ("taxon_name" %in% names(x)) for (r in setdiff(lc, "genus")) out[[length(out) + 1L]] <- mk(x$taxon_name, r)
      for (k in seq_along(lc)) for (r in setdiff(lc[seq_len(k - 1L)], "genus")) out[[length(out) + 1L]] <- mk(x[[lc[k]]], r)
      do.call(rbind, out)
    }))
    d$context <- NA_character_
    if (is.null(rows)) return(d)
    rows <- unique(rows[!is.na(rows$name) & !is.na(rows$value) & nzchar(trimws(rows$value)), , drop = FALSE])
    rows$rank <- factor(rows$rank, levels = lr)
    ctx <- vapply(split(rows, as.character(rows$name)), function(z) {
      if (any(tapply(z$value, z$rank, function(v) length(unique(v))) > 1L, na.rm = TRUE)) return(NA_character_)
      z <- z[order(z$rank), , drop = FALSE]; paste(unique(z$value), collapse = "|")
    }, "")
    d$context <- unname(ctx[d$verbatim_name])
    d
  }
  taxon_registry <- TaxaTools::freeze_taxon_registry(TaxaTools::build_taxon_registry(
    .reg_ctx(rbind(.reg_tab({{lik_var}}, "likelihoods"), .reg_tab({{priors_var}}, "priors")), list({{lik_var}}, {{priors_var}})),
    run_id = format(Sys.time(), "run-%Y%m%d-%H%M%S"), key_backbone_id = 11L,
    lookup = function(names, rank, context) TaxaFetch::lookup_gbif_taxa(names, rank, context, cache_dir = {{taxonomy_cache_dir}})
  ))
  invisible(TaxaTools::check_taxon_registry(taxon_registry, mode = "error"))
}
if (isTRUE({{use_taxon_registry}})) {
  {{lik_var}} <- TaxaTools::attach_taxon_ids({{lik_var}}, taxon_registry, "taxon_name", "likelihoods")
  {{priors_var}} <- TaxaTools::attach_taxon_ids({{priors_var}}, taxon_registry, "taxon_name", "priors")
}

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

# Combines duplicate (observation_id, taxon_name) rows produced by an
# observation detected at more than one site, via precision-weighted logit
# combination -- correctly discounts a low-confidence/sparse-data site
# rather than a plain average. Single-site candidates pass through
# unchanged.
likelihoods_combined <- TaxaAssign::combine_multisite_priors(likelihoods_ready)

# compute_posterior() adds pooled_n / pooled_prior_mass / pooled_taxa columns
# and the attribute "pooled_rows" (named unreferenced rows below 0.05 pooled
# into their ring); the attribute does not survive a dplyr verb.
posteriors <- TaxaAssign::compute_posterior(likelihoods_combined, n_sims = 1000L)
message("Computed posteriors for ", length(unique(posteriors$observation_id)),
        " samples across ", length(unique({{site_table_var}}$spatial_group_id)),
        " site(s)")
posteriors
