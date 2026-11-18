# Edge: likelihoods + priors -> posteriors
# Source: TaxaAssign join_priors() + compute_posterior()
# NOTE: {{main_habitat}} is the habitat type (e.g. "Freshwater", "Marine",
#   "Estuarine"). This is required — the pipeline does not guess which
#   habitat your samples came from.
# NOTE: {{backbone_id}} is required — no default. Must match whichever
#   taxonomic backbone the input taxonomy was verified against (e.g. 11
#   for GBIF, 4 for NCBI).

# --- Build site specification ---
# The kernel prior is centred on the site: its rows carry the fit's own site id
# (kernel_priors_fit$params$site_id) in their grid_id column, and the site is
# named by that id. Without a kernel fit in the session, the prior table's one
# site id is used.
.site_key <- if (exists("kernel_priors_fit")) kernel_priors_fit$params$site_id else NULL
if (is.null(.site_key)) {
  .site_key <- unique(stats::na.omit(as.character({{priors_var}}$grid_id)))
  if (length(.site_key) != 1L) {
    stop("lik_prior_to_post: no kernel_priors_fit in the session, and the prior table holds ",
         length(.site_key), " site ids in grid_id (need exactly one); ",
         "use the multi-site step for several sites.")
  }
}
site_spec <- list(grid_id = .site_key, main_habitat = {{main_habitat}})

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
