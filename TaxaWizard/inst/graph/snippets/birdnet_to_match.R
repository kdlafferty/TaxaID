# Edge: birdnet_detections -> match_df
# Source: TaxaMatch read_birdnet_output()
# Accepts: directory of BirdNET CSV files, a single CSV path, or a
# character vector of file paths.

birdnet_raw <- TaxaMatch::read_birdnet_output(
  data           = {{input_var}},
  min_confidence = {{min_confidence}},
  top_n          = {{top_n}}
)

if (nrow(birdnet_raw) == 0L) {
  stop(
    "read_birdnet_output() returned 0 detections. Check:\n",
    "  - That '{{input_var}}' points to BirdNET CSV files\n",
    "  - That min_confidence ({{min_confidence}}) is not too high\n",
    "  - That BirdNET ran successfully (non-empty result CSVs)\n",
    call. = FALSE
  )
}

# Lowercase any rank columns (BirdNET sometimes returns capitalised names)
for (.col in TaxaTools::detect_ranks(birdnet_raw)) {
  birdnet_raw[[.col]] <- TaxaTools::clean_taxon_names(birdnet_raw[[.col]])
}

match_df <- TaxaMatch::standardize_match_data(
  data               = birdnet_raw,
  observation_id_col = "observation_id",
  score_col          = "score",
  rank_system        = {{rank_system}}
)

match_df <- TaxaMatch::filter_redundant_hypotheses(match_df)
message("BirdNET: ", length(unique(match_df$observation_id)),
        " clips, ", nrow(match_df), " candidate hypotheses")
match_df
