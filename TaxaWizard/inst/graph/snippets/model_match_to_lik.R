# Edge: match_df + model_params -> likelihoods
# Source: TaxaLikely evaluate_likelihoods() + filter_top_hypotheses()
# NOTE: {{match_var}} should be the output of match_to_taxa (taxa_df),
# which already has taxon_name/taxon_name_rank. If not, we add them here.

# Standardize column names if needed
if (!"observation_id" %in% names({{match_var}})) {
  sid_match <- match(TRUE, tolower(names({{match_var}})) %in%
    c("esvid", "esv_id", "asvid", "asv_id", "queryid", "query_id"))
  if (!is.na(sid_match)) {
    message("Renaming '", names({{match_var}})[sid_match], "' -> 'observation_id'")
    names({{match_var}})[sid_match] <- "observation_id"
  }
}
if (!"score" %in% names({{match_var}})) {
  sc_match <- match(TRUE, tolower(names({{match_var}})) %in%
    c("percmatch", "perc_match", "pident", "percent_identity", "similarity"))
  if (!is.na(sc_match)) {
    message("Renaming '", names({{match_var}})[sc_match], "' -> 'score'")
    names({{match_var}})[sc_match] <- "score"
  }
}

# Ensure taxon_name exists (added by match_to_taxa step via create_taxon_names)
if (!"taxon_name" %in% names({{match_var}})) {
  detected_ranks <- TaxaTools::detect_ranks({{match_var}})
  for (.rk in detected_ranks) {
    .m <- which(tolower(names({{match_var}})) == .rk)
    if (length(.m) == 1L) names({{match_var}})[.m] <- .rk
  }
  # Clean species column: strip subspecies, hybrids, sp., cf., etc.
  if ("species" %in% names({{match_var}})) {
    {{match_var}}$species <- TaxaTools::clean_taxon_names({{match_var}}$species)
  }
  {{match_var}} <- TaxaTools::create_taxon_names(
    df = {{match_var}}, rank_system = detected_ranks
  )
  message("Added taxon_name from ranks: ", paste(detected_ranks, collapse = ", "))
}

lik_result <- TaxaLikely::evaluate_likelihoods(
  match_df     = {{match_var}},
  model_params = {{model_var}},
  n_sims       = 200L
)

likelihoods <- TaxaLikely::filter_top_hypotheses(
  lik_result$likelihoods
)
message("Evaluated likelihoods for ", length(unique(likelihoods$observation_id)), " samples")
if (nrow(lik_result$unresolved) > 0L) {
  message("  ", nrow(lik_result$unresolved), " unresolved rows (no usable likelihoods)")
}
likelihoods
