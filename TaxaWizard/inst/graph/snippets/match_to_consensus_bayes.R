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
  backbone_id       = {{backbone_id}}
)
result <- TaxaAssign::compute_posterior(likelihoods_ready)

# 3. Round 1 consensus
consensus <- TaxaAssign::posterior_consensus(
  result,
  rank_system = detected_ranks,
  backbone_id = {{backbone_id}}
)

# 4. Confirmation update, then Round 2 consensus
result_updated <- TaxaAssign::update_prior_from_consensus(result, consensus)
consensus <- TaxaAssign::posterior_consensus(
  result_updated,
  rank_system = detected_ranks,
  backbone_id = {{backbone_id}}
)

message("Bayesian pathway complete. ", sum(consensus$is_resolved), " of ",
        nrow(consensus), " observations resolved")
consensus
