# Edge: sequences -> match_df
# Source: TaxaMatch/inst/workflow_fastq_to_match.R

seq_df <- TaxaMatch::read_sequence_table({{input_var}})

filtered_df <- TaxaMatch::filter_sequences(
  seq_df,
  barcode_term  = {{barcode_term}},
  min_abundance = {{min_abundance}}
)

blast_hits <- TaxaMatch::blast_sequences(
  filtered_df,
  method     = {{blast_method}},
  database   = "nt",
  score_range = 2,
  max_hits    = 20,
  min_score   = {{min_score}},
  email       = {{email}},
  resolve_taxonomy = TRUE
)

match_df <- TaxaMatch::standardize_match_data(
  data          = blast_hits,
  observation_id_col = "observation_id",
  score_col     = "score",
  rank_system   = {{rank_system}}
)

match_df <- TaxaMatch::filter_redundant_hypotheses(match_df)
match_df
