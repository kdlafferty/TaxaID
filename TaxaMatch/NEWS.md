# TaxaMatch (development version)

## 2026-09-10

* `blast_sequences()`: `attr(out, "report_params")` now records
  `min_query_coverage`, the coverage floor the match object was built under,
  read by `TaxaLikely::evaluate_likelihoods()` to check it against the model's
  `min_pair_coverage`.
* `verify_removal_candidates()`: `spared` is `NA` (was `TRUE`) when the audit's
  own BLAST never completed (`action_audit` untested/NA); the summary message
  names un-audited accessions separately. Seen live on a real audit where all 8
  candidates timed out at NCBI and every row read "spared".

## Polishing Phase (Sessions 57-59)

* `filter_redundant_hypotheses()`: `rank_order` param renamed to
  `rank_system` for ecosystem consistency.
* Removed duplicate `%||%` definition (now imported from TaxaTools).
* Replaced inline rank definitions with `TaxaTools::standard_ranks`.
* Added vignette: match-standardization.Rmd.
