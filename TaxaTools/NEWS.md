# TaxaTools (development version)

## 2026-09-12

* `scientific_to_common()` gains `cache_dir` (one `.rds` per name, keyed on
  name + `backbone_id` + `location`; a parsed "no common name" answer is
  cached, an unparseable batch and an un-asked backbone miss are not) and
  `verbose` (a summary line plus one line per LLM batch). Motivated by the
  PtConception 18S workflow: 1,151 names, 58 sequential LLM calls, no
  output, repeated on every re-run. New `taxatools_clear_cache()`.

## Polishing Phase (Sessions 57-59)

* New exports: `standard_ranks`, `extended_ranks`, `detect_ranks()`,
  `find_taxonomy_conflicts()`, `%||%`, `is_valid_species_name()`,
  `barcode_length_defaults`, `resolve_barcode_lengths()`.
* New LLM text generation: `build_report_context()`, `draft_methods_text()`,
  `draft_results_text()`.
* `clean_taxon_names()` is now length-preserving (invalid names become `NA`).
* LLM providers attach `model` attribute to returned strings.
* DESCRIPTION rewritten for CRAN compliance.
* Added vignette: name-cleaning.Rmd.
* Added tests for rank utilities, barcode utilities, and `%||%` operator.

## TaxaTools 0.0.1

* Initial development.
* Added `verify_sci_names()` to verify scientific names against taxonomic
  backbones.
