# TaxaTools (development)

## New features (2026-09-19)

* **`taxaid_build_manifest()`, `write_taxaid_manifest()`,
  `check_taxaid_manifest()`** -- record which TaxaID code a run actually used,
  and stop a workflow whose library has drifted.

  Every TaxaID package sits at version 0.1.0 and is reinstalled constantly, so
  the version string is silent by construction and "what was installed" is a
  memory rather than a fact. Two runs a week apart can report identical
  versions and have executed materially different code.

  **The signal is a hash of the installed code, not the `Built` timestamp.**
  That distinction is what makes the check survivable, and it was verified
  against real installs rather than simulated hashes: rebuilding TaxaFlag with
  no source change moved `Built` from 05:56:58 to 05:59:33 and left the hash at
  `2f88726842e6...`, while adding a single function moved it to
  `93bd9e9905c8...`; reverting restored the original. A `Built`-based check
  would have fired on the harmless rebuild, and a guard that cries wolf is a
  guard someone switches off. The hash is also stable across separate R
  processes. Internals are included in the hash, because a behaviour change
  need not touch an exported signature -- all three column-inference bugs fixed
  the same day lived in internal helpers.

  **Absence is reported first.** A package named in the manifest but missing
  from the library is listed ahead of CHANGED and EXTRA, and packages that are
  not installed are kept as rows with `installed = FALSE` rather than dropped:
  a checker that only compares what it finds on both sides cannot report what
  is gone.

  Wired into `PtConceptionWorkflow_12S_single_site.R` as the reference
  implementation -- writes the manifest on first run, checks it thereafter, and
  errors before any result exists.

## 2026-09-13

* New exported sampling-group classifier: `default_sampling_scheme()` +
  `assign_sampling_group()`. Ports, clause-for-clause, the inline
  `dplyr::case_when()` that has been duplicated across five workflow files
  (PtConception 18S, PtConception 12S, GreatLakes, the shared template, and
  CaliforniaIntertidal) and had drifted three times before this fix -- ray-
  finned fishes/Elasmobranchii missing (2026-09-03, 484,072 records),
  Phaeophyceae missing (2026-09-06, 11,605 records), Dinophyceae missing
  (2026-09-06, 1,192 records), and Bacillariophyceae/Copepoda missing
  (2026-09-13, 2,773 + 66 records). The scheme is an ordered,
  first-match-wins list of OR/AND clauses; `assign_sampling_group()` adds a
  `kingdom_guard` (default `TRUE`) that sends an unmatched non-animal row to
  `NA` instead of the catch-all, closing the open-ended protist tail without
  enumerating classes forever, and an opt-in `harmonise` (default `FALSE`)
  that converts an NCBI-backbone input to GBIF vocabulary first via
  `verify_taxon_names()`/`change_backbone()` (costs one backbone lookup per
  unique finest-rank name). Includes the two 2026-09-13 fixes directly:
  `Bacillariophyceae` (diatoms) -> `"phytoplankton"` (class-level only --
  GBIF places diatoms in phylum Ochrophyta, the same phylum as the kelps, so
  a phylum-level rule would misclassify one or the other), and `Copepoda` ->
  `"zooplankton"` alongside the existing `Hexanauplia` spelling (both
  backbones' names for the same class now map to the same group).
  Regression-validated against the real 2,185,193-row
  `PtCon18SSchulte_occurrences_clean.rds` checkpoint: 2,070,407 exact
  agreements with the ported inline classifier, 35 intended-fix
  disagreements, 114,751 kingdom-guard disagreements (a real,
  previously-undetected gap surfaced by this work: the live workflow's
  `other_vascular_plants` clause omits class `Liliopsida`, so 114,744
  monocot records were silently falling into `"macroinvertebrates"`), 0
  unexplained.

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
