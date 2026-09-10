# TaxaHabitat 0.1.0

## New features (2026-09-10)

* `build_habitat_lookup()`: cached one-call habitat classification
  (`build_habitat_prompt()` -> `TaxaTools::prompt_api()` ->
  `parse_hierarchical_habitat_response()`), asking the LLM only about taxa not
  already classified under the same scheme (per-taxon on-disk cache, full key
  verified on read, unresolved verdicts never cached). Every production
  workflow now uses it: an uncached verdict that differed between runs moved a
  species' kernel prior by orders of magnitude and cost 0.05 of Lamar precision
  on the 2026-09-10 GreatLakes run.
* `taxahabitat_clear_cache()`: report/prune that cache via the shared TaxaTools
  cache engine.

## Bug fixes (2026-09-10)

* `report_habitat()`: hardened the dispatch between
  `parse_hierarchical_habitat_response()`'s weight table and
  `assign_habitat_biological()`'s occurrence-level output. The previous
  `[0, 1]` range test passed vacuously for an all-NA numeric column (common in
  GBIF exports: `depth`, `elevation`, `coordinatePrecision`) and for any
  genuinely proportional non-habitat column, either of which summarised
  occurrence data from its coordinate columns
  ("Dominant habitat: decimalLatitude (mean weight 3506%)"). Dispatch now
  requires positive evidence of a weight table: every candidate column must
  carry real data in [0, 1.05], and the columns must sum to ~1.0 across a row.

* `report_habitat()`: `n_taxa` on the weight branch now resolves the taxon
  column the same way the `main_habitat` branch already did. Because
  `parse_hierarchical_habitat_response()` always names its taxon column
  `taxon_name` while `report_habitat()` defaults to `"scientificName"`, the
  documented call `report_habitat(parse_output)` fell through to `nrow()` and
  reported records as taxa.

## Polishing Phase (Sessions 57-59)

* Removed duplicate `%||%` definition (now imported from TaxaTools).
* Removed empty `globalVariables(character(0))` calls.
* Added vignette: habitat-assignment.Rmd.
* Added tests for `assign_habitat_biological()`, `build_iucn_scheme()`,
  and `example_habitat_scheme`.
