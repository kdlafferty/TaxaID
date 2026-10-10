# TaxaLikely 1.0.0

* Initial release.
* `annotate_reference_support()` adds four information-only columns saying how
  much per-species reference data the trained model had for a call's taxon:
  `n_references` (`H1_Lookup$n_obs_species`), `reference_weight` (the
  empirical-Bayes weight those observations earned), `reference_basis` (the
  documented reason for every `NA`, including `"no_model_row"` for taxa too
  thinly referenced to have a row at all) and `at_model_max` (the count is
  censored by the matrix build's `max_seqs_per_taxon`). A post-hoc lookup, so
  it annotates results produced earlier without re-evaluating; nothing
  thresholds or filters on it, and a low count is not evidence a call is wrong.
* `restore_suppressed_candidates()` scores a restored congener by aligning the
  query to the candidate's own references (`sequence_col`, `min_query_coverage`),
  reported in `restored_score_source` / `restored_reason`. The hierarchy's
  identities, including Level 4's `pid`, are reference-to-reference (Level 4
  aligns the candidate's reference to the anchor's reference; the query only
  locates the anchor range), so they are used only as an imputed fallback,
  `anchor - (100 - ref_ref)`, which never exceeds the anchor.
* `restore_suppressed_candidates(dropped_matches =)` offers a dropped hit's
  species back through its kept references, scored by the same direct
  alignment, so dropping one accession does not drop a species that has other
  good references.
* `calibrate_query_noise()` measures query noise on OBSERVED rows only: rows
  added by `restore_suppressed_candidates()` are hypotheses and are excluded
  from the confident set (`Query_Calibration$n_restored_rows_excluded`).
