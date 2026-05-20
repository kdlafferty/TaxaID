# Edge: match_df + model_params + priors -> consensus (Bayesian wrapper)
# Source: TaxaAssign run_bayesian_pipeline()
# Prerequisite: match_df must have observation_id, score, taxon_name, taxon_name_rank

# Standardize common column name variations
if (!"observation_id" %in% names({{match_var}})) {
  sid_match <- match(TRUE, tolower(names({{match_var}})) %in% c("esvid", "esv_id", "asvid", "asv_id", "queryid", "query_id"))
  if (!is.na(sid_match)) {
    message("Renaming '", names({{match_var}})[sid_match], "' -> 'observation_id'")
    names({{match_var}})[sid_match] <- "observation_id"
  }
}
if (!"score" %in% names({{match_var}})) {
  sc_match <- match(TRUE, tolower(names({{match_var}})) %in% c("percmatch", "perc_match", "pident", "percent_identity", "similarity"))
  if (!is.na(sc_match)) {
    message("Renaming '", names({{match_var}})[sc_match], "' -> 'score'")
    names({{match_var}})[sc_match] <- "score"
  }
}

# Detect rank columns (needed for run_bayesian_pipeline even if taxon_name exists)
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
    df          = {{match_var}},
    rank_system = detected_ranks
  )
  message("Created taxon_name column: ", length(unique({{match_var}}$taxon_name)), " unique taxa")
}

bayes_result <- TaxaAssign::run_bayesian_pipeline(
  match_df     = {{match_var}},
  model_params = {{model_var}},
  taxaexpect_priors = {{priors_var}},
  site         = {{site}},
  rank_system  = detected_ranks,
  verbose      = TRUE
)
consensus <- bayes_result$consensus
message("Bayesian pipeline complete. ", sum(consensus$is_resolved), " of ",
        nrow(consensus), " samples resolved")
consensus
