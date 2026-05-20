# Edge: match_df -> taxa
# Source: TaxaTools create_taxon_names()

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

detected_ranks <- TaxaTools::detect_ranks({{input_var}})
message("Auto-detected rank columns: ", paste(detected_ranks, collapse = ", "))
# Lowercase rank columns to match TaxaID conventions
for (.rk in detected_ranks) {
  .match <- which(tolower(names({{input_var}})) == .rk)
  if (length(.match) == 1L) names({{input_var}})[.match] <- .rk
}

# Clean species/genus columns: strip subspecies trinomials, hybrid crosses,
# "sp.", "cf.", and other non-conforming labels to standard binomials.
# This is essential for match data from BLAST or other tools.
if ("species" %in% names({{input_var}})) {
  n_before <- dplyr::n_distinct({{input_var}}$species, na.rm = TRUE)
  {{input_var}}$species <- TaxaTools::clean_taxon_names({{input_var}}$species)
  n_after <- dplyr::n_distinct({{input_var}}$species, na.rm = TRUE)
  if (n_before != n_after) {
    message(sprintf("Cleaned species column: %d -> %d unique names.", n_before, n_after))
  }
}

taxa_df <- TaxaTools::create_taxon_names(
  df          = {{input_var}},
  rank_system = detected_ranks
)
message("Unique taxa: ", length(unique(taxa_df$taxon_name)))
taxa_df
