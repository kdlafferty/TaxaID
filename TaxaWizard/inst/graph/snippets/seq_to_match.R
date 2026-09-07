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
  score_range = 8,
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

# Optional: BLAST-based reference-accession quality screening (2026-08-08
# audit's recommended pre-training screen). For each reference accession a
# hypothesis in match_df is based on, checks whether independent GenBank
# evidence agrees taxonomically -- flags likely mislabeled/contaminated
# reference submissions (hierarchy_flag = "incongruent") without discarding
# them outright, since a flag can also mean "this marker has poor resolving
# power here", not necessarily a genuine mislabel -- see
# evaluate_reference_accessions()'s own documentation. Costly (one BLAST
# round-trip per unique accession) -- set {{screen_reference_accessions}} to
# FALSE to skip entirely.
if (isTRUE({{screen_reference_accessions}})) {
  accession_eval <- TaxaMatch::evaluate_reference_accessions(
    accessions = unique(match_df$accession),
    method     = {{blast_method}}
  )
  match_df <- TaxaMatch::flag_incongruent_references(match_df, accession_eval)
  message(
    "Reference-accession screening: ",
    sum(match_df$hierarchy_flag == "incongruent", na.rm = TRUE),
    " of ", nrow(match_df), " match rows rest on an incongruent reference accession"
  )

  # Optional: LLM second-look review of flagged/borderline accessions (2026-08-13,
  # TaxaMatch::review_flagged_accessions()). A raw "incongruent" verdict alone can't
  # distinguish a genuine mislabel from a correctly-labeled record with poor marker
  # resolving power or thin corroborating coverage -- this gives every flagged
  # accession a real LLM second look before anything is ever removed. Never
  # re-decides hierarchy_flag itself; only produces overrides an explicit removal
  # step can choose to honor. Set {{review_flagged_references}} to FALSE to skip.
  if (isTRUE({{review_flagged_references}})) {
    accession_review <- TaxaMatch::review_flagged_accessions(
      accession_eval,
      llm_fn = {{llm_fn}}
    )
    accession_overrides <- TaxaMatch::resolve_review_overrides(accession_review)
    message(
      "LLM review: ", length(accession_overrides),
      " flagged accession(s) confirmed safe to keep (poor marker resolution/thin coverage/hybrid artifact, not a genuine mislabel)"
    )

    # Optional, separately gated: actually DROP rows resting on an accession
    # still judged "remove" after the review overrides above (the harder,
    # deliberate opt-in -- flag_incongruent_references() above already
    # annotated everything without removing anything, the recommended
    # default). Set {{remove_incongruent_references}} to TRUE only after
    # reviewing the flags/review comments yourself.
    if (isTRUE({{remove_incongruent_references}})) {
      match_df <- TaxaMatch::remove_incongruent_references(
        match_df, accession_eval,
        override_accessions = accession_overrides
      )
      message("Removed match rows resting on a reference accession still judged incongruent after review")
    }
  }
}

match_df
