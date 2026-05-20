# TaxaLikely (development version)

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
