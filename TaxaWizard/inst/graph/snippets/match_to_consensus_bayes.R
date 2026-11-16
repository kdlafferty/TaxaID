# Edge: match_df + model_params + priors -> consensus (Bayesian wrapper)
# Source: TaxaLikely evaluate_likelihoods() -> TaxaAssign join_priors() ->
#         compute_posterior() -> posterior_consensus()
# Prerequisite: match_df must have observation_id, score_original, taxon_name, taxon_name_rank
# NOTE: {{backbone_id}} is required — no default. Must match whichever
#   taxonomic backbone the input taxonomy was verified against (e.g. 11
#   for GBIF, 4 for NCBI).

# Standardize common column name variations
if (!"observation_id" %in% names({{match_var}})) {
  sid_match <- match(TRUE, tolower(names({{match_var}})) %in% c("esvid", "esv_id", "asvid", "asv_id", "queryid", "query_id"))
  if (!is.na(sid_match)) {
    message("Renaming '", names({{match_var}})[sid_match], "' -> 'observation_id'")
    names({{match_var}})[sid_match] <- "observation_id"
  }
}
if (!"score_original" %in% names({{match_var}})) {
  sc_match <- match(TRUE, tolower(names({{match_var}})) %in% c("score", "percmatch", "perc_match", "pident", "percent_identity", "similarity"))
  if (!is.na(sc_match)) {
    message("Renaming '", names({{match_var}})[sc_match], "' -> 'score_original'")
    names({{match_var}})[sc_match] <- "score_original"
  }
}

# Detect rank columns (needed downstream even if taxon_name already exists)
detected_ranks <- TaxaTools::detect_ranks({{match_var}})
message("Auto-detected rank columns: ", paste(detected_ranks, collapse = ", "))

# Ensure taxon_name and taxon_name_rank exist
if (!"taxon_name" %in% names({{match_var}})) {
  # Lowercase rank columns to match TaxaID conventions
  for (.rk in detected_ranks) {
    .match <- which(tolower(names({{match_var}})) == .rk)
    if (length(.match) == 1L) names({{match_var}})[.match] <- .rk
  }
  # Clean species column: strip subspecies, hybrids, sp., cf., etc.
  if ("species" %in% names({{match_var}})) {
    {{match_var}}$species <- TaxaTools::clean_taxon_names({{match_var}}$species)
  }
  {{match_var}} <- TaxaTools::create_taxon_names(
    input_df    = {{match_var}},
    rank_system = detected_ranks
  )
  message("Created taxon_name column: ", length(unique({{match_var}}$taxon_name)), " unique taxa")
}

# 1. Scores -> likelihoods under the trained model, then keep the finest-rank
#    candidate set per observation
likelihoods <- TaxaLikely::evaluate_likelihoods(
  match_df     = {{match_var}},
  model_params = {{model_var}},
  rank_system  = detected_ranks
)$likelihoods
top_likelihoods <- TaxaLikely::filter_top_hypotheses(
  likelihoods,
  rank_system = detected_ranks
)

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
    .reg_ctx(rbind(.reg_tab(top_likelihoods, "likelihoods"), .reg_tab({{priors_var}}, "priors")), list(top_likelihoods, {{priors_var}})),
    run_id = format(Sys.time(), "run-%Y%m%d-%H%M%S"), key_backbone_id = 11L,
    lookup = function(names, rank, context) TaxaFetch::lookup_gbif_taxa(names, rank, context, cache_dir = {{taxonomy_cache_dir}})
  ))
  invisible(TaxaTools::check_taxon_registry(taxon_registry, mode = "error"))
}
if (isTRUE({{use_taxon_registry}})) {
  top_likelihoods <- TaxaTools::attach_taxon_ids(top_likelihoods, taxon_registry, "taxon_name", "likelihoods")
  {{priors_var}} <- TaxaTools::attach_taxon_ids({{priors_var}}, taxon_registry, "taxon_name", "priors")
}

# 2. Join the occurrence priors, then compute posteriors.
#    If your observations span more than one distinct site, call
#    TaxaAssign::combine_multisite_priors() on the joined table before
#    compute_posterior(), or per-site duplicate candidate rows arrive
#    uncombined.
likelihoods_ready <- TaxaAssign::join_priors(
  likelihoods       = top_likelihoods,
  taxaexpect_priors = {{priors_var}},
  site              = {{site}},
  rank_system       = detected_ranks,
  backbone_id       = {{backbone_id}},
  taxonomy_cache_dir = {{taxonomy_cache_dir}},
  registry          = taxon_registry
)
result <- TaxaAssign::compute_posterior(likelihoods_ready)

# 3. Round 1 consensus
# "credible_node" with robust_prior_s = 0 and cross_phylum_eps = 0 is the
# weighted LCA (node summing), and it is the package default. Pass
# consensus_method = "lca" for the unweighted top-set rule instead.
consensus <- TaxaAssign::posterior_consensus(
  result,
  rank_system      = detected_ranks,
  backbone_id      = {{backbone_id}},
  consensus_method = "credible_node",
  robust_prior_s   = 0,
  cross_phylum_eps = 0,
  taxonomy_cache_dir = {{taxonomy_cache_dir}},
  registry         = taxon_registry
)

# 4. Confirmation update, then Round 2 consensus. n_sims defaults to 1000,
#    which propagates uncertainty through the re-run; pass n_sims = 0 for
#    point estimates only.
result_updated <- TaxaAssign::update_prior_from_consensus(result, consensus)
consensus <- TaxaAssign::posterior_consensus(
  result_updated,
  rank_system      = detected_ranks,
  backbone_id      = {{backbone_id}},
  consensus_method = "credible_node",
  robust_prior_s   = 0,
  cross_phylum_eps = 0,
  taxonomy_cache_dir = {{taxonomy_cache_dir}},
  registry         = taxon_registry
)

message("Bayesian pathway complete. ", sum(consensus$is_resolved), " of ",
        nrow(consensus), " observations resolved")
consensus
