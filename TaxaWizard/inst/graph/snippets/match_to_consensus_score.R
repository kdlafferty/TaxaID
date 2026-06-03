# Edge: match_df -> consensus (score-based, simplest)
# Source: TaxaAssign score_consensus()
# Prerequisite: match_df must have observation_id, score_original, taxon_name, taxon_name_rank

# Standardize common column name variations
if (!"observation_id" %in% names({{input_var}})) {
  sid_match <- match(TRUE, tolower(names({{input_var}})) %in% c("esvid", "esv_id", "asvid", "asv_id", "queryid", "query_id"))
  if (!is.na(sid_match)) {
    message("Renaming '", names({{input_var}})[sid_match], "' -> 'observation_id'")
    names({{input_var}})[sid_match] <- "observation_id"
  }
}
if (!"score_original" %in% names({{input_var}})) {
  sc_match <- match(TRUE, tolower(names({{input_var}})) %in% c("score", "percmatch", "perc_match", "pident", "percent_identity", "similarity"))
  if (!is.na(sc_match)) {
    message("Renaming '", names({{input_var}})[sc_match], "' -> 'score_original'")
    names({{input_var}})[sc_match] <- "score_original"
  }
}

# Detect rank columns (needed for score_consensus even if taxon_name exists)
detected_ranks <- TaxaTools::detect_ranks({{input_var}})
message("Auto-detected rank columns: ", paste(detected_ranks, collapse = ", "))

# Ensure taxon_name and taxon_name_rank exist
if (!"taxon_name" %in% names({{input_var}})) {
  # Lowercase rank columns to match TaxaID conventions
  for (.rk in detected_ranks) {
    .match <- which(tolower(names({{input_var}})) == .rk)
    if (length(.match) == 1L) names({{input_var}})[.match] <- .rk
  }
  # Clean species column: strip subspecies, hybrids, sp., cf., etc.
  if ("species" %in% names({{input_var}})) {
    {{input_var}}$species <- TaxaTools::clean_taxon_names({{input_var}}$species)
  }
  {{input_var}} <- TaxaTools::create_taxon_names(
    df          = {{input_var}},
    rank_system = detected_ranks
  )
  message("Created taxon_name column: ", length(unique({{input_var}}$taxon_name)), " unique taxa")
}

consensus <- TaxaAssign::score_consensus(
  match_df        = {{input_var}},
  min_score       = {{min_score}},
  max_gap         = {{max_gap}},
  rank_thresholds = {{rank_thresholds}},
  score_col       = "score_original",
  rank_system     = detected_ranks
)
message("Score consensus: ", sum(consensus$is_resolved), " of ",
        nrow(consensus), " samples resolved")
consensus
