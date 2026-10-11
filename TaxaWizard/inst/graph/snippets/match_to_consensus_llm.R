# Edge: match_df -> consensus (LLM-shortcut pathway)
# Source: TaxaAssign assign_taxa_llm() -> posterior_consensus() ->
#         update_prior_from_consensus() -> posterior_consensus()
# Prerequisite: match_df must have observation_id, score_original, taxon_name, taxon_name_rank
# If taxon_name is missing, create it from taxonomy columns first.
# NOTE: {{backbone_id}} is required -- no default. Must match whichever
#   taxonomic backbone the input taxonomy was verified against (e.g. 11
#   for GBIF, 4 for NCBI).

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
    input_df    = {{input_var}},
    rank_system = detected_ranks
  )
  message("Created taxon_name column: ", length(unique({{input_var}}$taxon_name)), " unique taxa")
}

# 1. Ecological context for the LLM, built once from the confident taxa
context <- TaxaAssign::build_context(
  taxon_names     = unique({{input_var}}$taxon_name[
    {{input_var}}$score_original >= {{score_threshold}}
  ]),
  geographic_hint = {{geographic_hint}},
  date            = {{date}},
  habitat_scheme  = {{habitat_scheme}},
  llm_fn          = {{llm_fn}}
)

# 2. LLM-generated priors and likelihood proxies, then posteriors
#    data_type = "eDNA": sequence matches. Image or acoustic input needs
#    its own unreferenced_taxa list instead.
result <- TaxaAssign::assign_taxa_llm(
  match_df        = {{input_var}},
  context         = context,
  llm_fn          = {{llm_fn}},
  score_threshold = {{score_threshold}}
)

# 3. Round 1 consensus
consensus <- TaxaAssign::posterior_consensus(
  result,
  backbone_id = {{backbone_id}}
)

# 4. Confirmation update, then Round 2 consensus.
#    LLM priors are not occurrence-based (no theta_mean), so Round 2's
#    support columns cannot be supplied here.
result_updated <- TaxaAssign::update_prior_from_consensus(
  result, consensus,
  require_support_columns = FALSE
)
consensus <- TaxaAssign::posterior_consensus(
  result_updated,
  backbone_id = {{backbone_id}}
)

message("LLM pathway complete. ", sum(consensus$is_resolved), " of ",
        nrow(consensus), " observations resolved")
consensus
