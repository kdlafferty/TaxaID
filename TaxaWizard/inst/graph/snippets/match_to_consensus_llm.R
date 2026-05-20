# Edge: match_df -> consensus (LLM-shortcut wrapper, recommended)
# Source: TaxaAssign run_llm_pipeline()
# Prerequisite: match_df must have observation_id, score, taxon_name, taxon_name_rank
# If taxon_name is missing, create it from taxonomy columns first.

# Standardize common column name variations
if (!"observation_id" %in% names({{input_var}})) {
  sid_match <- match(TRUE, tolower(names({{input_var}})) %in% c("esvid", "esv_id", "asvid", "asv_id", "queryid", "query_id"))
  if (!is.na(sid_match)) {
    message("Renaming '", names({{input_var}})[sid_match], "' -> 'observation_id'")
    names({{input_var}})[sid_match] <- "observation_id"
  }
}
if (!"score" %in% names({{input_var}})) {
  sc_match <- match(TRUE, tolower(names({{input_var}})) %in% c("percmatch", "perc_match", "pident", "percent_identity", "similarity"))
  if (!is.na(sc_match)) {
    message("Renaming '", names({{input_var}})[sc_match], "' -> 'score'")
    names({{input_var}})[sc_match] <- "score"
  }
}

# Ensure taxon_name and taxon_name_rank exist
if (!"taxon_name" %in% names({{input_var}})) {
  detected_ranks <- TaxaTools::detect_ranks({{input_var}})
  message("Auto-detected rank columns: ", paste(detected_ranks, collapse = ", "))
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

llm_result <- TaxaAssign::run_llm_pipeline(
  match_df        = {{input_var}},
  geographic_hint = {{geographic_hint}},
  date            = {{date}},
  habitat_scheme  = {{habitat_scheme}},
  llm_fn          = {{llm_fn}},
  score_threshold = {{score_threshold}},
  verbose         = TRUE
)
consensus <- llm_result$consensus
message("LLM pipeline complete. ", sum(consensus$is_resolved), " of ",
        nrow(consensus), " samples resolved")
consensus
