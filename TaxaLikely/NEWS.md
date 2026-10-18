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

## New features

* `evaluate_likelihoods()` builds one unreferenced ring per genus and one per
  family present among the candidates, plus a ring at every coarser rank that
  at least three groups of matches support. Each ring is valued and named at a
  deterministic anchor candidate: the best candidate of that genus, family or
  unit, chosen by transformed score, then a real hit over a restored row, then
  H1 density, then raw identity. Only an exact tie falls to candidate order, so
  rings do not depend on row order. Candidates without a usable genus (blank
  or a placeholder such as "unclassified") are never anchors.
* `evaluate_likelihoods()` returns `best_identity` (the unit's best raw match
  identity, percent), `best_identity_rank` (the finest rank whose Youden's J
  threshold it reaches) and `poor_absolute_fit` (`TRUE` when it reaches none).
  Likelihoods are normalised to the unit maximum, so the best hypothesis of a
  poor match still scores 1; these columns report the match on its own scale.
  They are a flag only: no likelihood or call changes.
* `match_reference_region()` places each reference on the span the study's
  sequences (ESVs) cover, and `build_sequence_matrix()` refuses unplaced rows of a
  region-matched set.

## Changed behaviour

* `expand_unreferenced_hypotheses()` copies each genus ring onto the species of
  its own genus only. No family-level ring names a species. A species whose
  genus has references for the marker (a `specific_candidate` row anywhere in
  `likelihood_df`) is withheld from every coarser ring because its genus's
  references were compared with the read and did not match; each withheld
  species is listed in `attr(, "unreferenced_withheld")` with its reason
  (`"genus_referenced_unmatched"` or `"no_own_genus_ring"`). Rows with no
  species name are dropped with a message and a species listed twice for one
  observation scope is one hypothesis.
* `evaluate_likelihoods()` keeps the generic unreferenced rows past the final
  ratio filter, which drops only specific candidates. A genus lookup row with a
  non-finite delta or non-positive variance values its ring from the pooled
  parameters and reports `global_fallback` as the ring's `h2_delta_source`.
* `train_likelihood_model()` measures the genus-to-family step (H3) from
  confamilial pairs, and runs the training passes in blocks of references to
  bound memory.
* `apply_coverage_constraints(constraint_behavior = "relabel")` relabels the
  unsequenced-congener row of a closed genus (every species sequenced) as
  `unresolved_species` and leaves its likelihoods alone; `TaxaAssign::compute_posterior()`
  moves its posterior to the genus's referenced species. `"zero"` mode also
  scales `score_likelihood_sd`, so the Monte Carlo path honours the zero.
* `calibrate_query_noise()` measures query noise on observed rows only and
  excludes rows added by `restore_suppressed_candidates()` from the confident
  set. Its default `offset_form` is `"constant"`.

## New arguments

* `audit_barcode_coverage(on_lookup_failure = c("warn", "error"))` controls a
  failed taxid resolution, species enumeration or barcode check. The failed
  genus is never checkpointed, contributes nothing to `$unreferenced` and has
  `is_complete = FALSE`; the census gains `lookup_failed` and the result
  `attr(, "lookup_failures")`. `"error"` stops an unattended run instead of
  caching a truncated set.
