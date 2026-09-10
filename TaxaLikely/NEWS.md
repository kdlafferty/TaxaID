# TaxaLikely (development version)

## 2026-09-10

* `train_likelihood_model()`: new `min_pair_coverage` (default `0.8`) -- only a
  reference pair at or above the match object's own coverage floor
  (`TaxaMatch::blast_sequences(min_query_coverage)/100`) may define a reference's
  best foreign, congener or conspecific match when the gap feature is trained.
  No pair is removed and no species is dropped. Fixes a real defect: short-overlap
  100%-identity pairs defined 86% of references' "best foreign match" on real 12S
  data, training a negative gap. Every `lik_model` trained before this is stale.
* `train_likelihood_model()`: new `shrinkage = c("empirical_bayes", "fixed")`
  (default `"empirical_bayes"`): per-species H1 mean score/gap shrunk with an
  estimated between-species variance (`tau^2/(tau^2 + sigma^2/N)`) instead of the
  fixed `N/(N + prior_weight)`. `H1_Lookup` gains `shrink_w_score`/`shrink_w_gap`;
  `Stats` gains `shrinkage`, `tau2_score`, `tau2_gap`, `min_pair_coverage`,
  `n_self_fallback`, `n_foreign_unqualified`.
* `evaluate_likelihoods()`: warns when the match object admits lower alignment
  coverage than the model's `min_pair_coverage` (reads the floor recorded by
  `blast_sequences()`, else the observed minimum `query_coverage`).
* Validated on the real GreatLakes workflow code path against the Lamar species
  list: co-detections 593 -> 798, precision 0.805 -> 0.818, 29 -> 41 of 61 species.

## Polishing Phase (Sessions 57-59)

* `evaluate_likelihoods()`: new `verbose` param logs species-specific
  parameter fallback to global mean.
* `train_likelihood_model()`: `traitor_threshold` renamed to
  `mislabel_threshold`.
* `.build_search_term()`: protein-coding genes (COI, cytb) use `[GENE]`
  field tags; ribosomal subunits (12S, 16S, 18S, 28S) and primer names
  use `[All Fields]` (NCBI does not reliably index rRNA under [GENE]).
* Internal helpers moved to TaxaTools: `barcode_length_defaults`,
  `resolve_barcode_lengths()`, `is_valid_species_name()`.
* Deleted stale monolithic workflow (`inst/TaxaLikely_workflow.R`).
* Added vignette: score-to-likelihood.Rmd.
* Added tests for `fetch_reference_sequences()`, `read_reference_fasta()`,
  and `.build_search_term()`.

## 0.0.0.9000

* Package created (Session 30, 2026-03-27).
