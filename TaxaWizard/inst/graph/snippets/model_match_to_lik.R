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
if (!"score_original" %in% names({{match_var}})) {
  sc_match <- match(TRUE, tolower(names({{match_var}})) %in%
    c("score", "percmatch", "perc_match", "pident", "percent_identity", "similarity"))
  if (!is.na(sc_match)) {
    message("Renaming '", names({{match_var}})[sc_match], "' -> 'score_original'")
    names({{match_var}})[sc_match] <- "score_original"
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
    input_df = {{match_var}}, rank_system = detected_ranks
  )
  message("Added taxon_name from ranks: ", paste(detected_ranks, collapse = ", "))
}

# Likelihoods are evaluated on the ranks the model was fitted on (model_params$Rank_System). Detecting them from the
# match table's columns instead would add any coarser column it carries (kingdom, phylum), on which the model holds no
# ring, and would name a reference identified only at such a rank there instead of returning its observation in
# $unresolved. A model that records no rank system falls back to detection from the match table.
lik_rank_system <- {{model_var}}$Rank_System
lik_result <- TaxaLikely::evaluate_likelihoods(
  match_df     = {{match_var}},
  model_params = {{model_var}},
  rank_system  = lik_rank_system,
  n_sims       = 200L
)

# evaluate_likelihoods() also reports the match on its own absolute scale, as
# unit-level columns repeated on every row of the unit: best_identity (the
# unit's best raw identity, percent), best_identity_rank (the finest rank
# whose marker-specific identity threshold it reaches, NA if none) and
# poor_absolute_fit (TRUE when it reaches no rank threshold). Likelihoods are
# normalised to the unit maximum, so the best hypothesis always scores 1 even
# when the match is poor; these three are a FLAG only and never change a
# likelihood or which hypothesis wins. They travel through the posterior and
# consensus tables to review_assignments() (see consensus_to_reviewed).
likelihoods <- TaxaLikely::filter_top_hypotheses(
  lik_result$likelihoods,
  rank_system = lik_rank_system
)
message("Evaluated likelihoods for ", length(unique(likelihoods$observation_id)), " samples")
# An observation whose matches all name a reference only above the rank system
# (only "Eukaryota", say), or whose matches the coverage check removed, has no
# likelihood row; evaluate_likelihoods() returns its match rows in $unresolved.
# They are kept as lik_unresolved, and the consensus step gives each such
# observation a no-call row (consensus_reason "no_usable_likelihood").
lik_unresolved <- lik_result$unresolved
if (nrow(lik_unresolved) > 0L) {
  message("  ", length(unique(lik_unresolved$observation_id)), " observation(s) with no usable likelihood ",
          "(", nrow(lik_unresolved), " match rows); each gets a no-call consensus row")
}
likelihoods
