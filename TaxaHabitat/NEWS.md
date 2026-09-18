# TaxaHabitat 0.1.0

## Bug fixes (2026-09-18)

* `flag_habitat_inconsistencies()`: **the two habitat-realm name patterns were
  asymmetric, and it silently exempted the majority of at least one real site
  from spatial QC.** Marine terms were `^`-anchored; freshwater terms matched
  anywhere in the name. Any habitat whose name did not *start* with a marine
  word therefore fell through to the freshwater test -- and freshwater is
  deliberately exempt from spatial verification -- so those points left QC
  carrying `"freshwater habitat not spatially verified"`, a reason that reads
  like a pass.

  Measured on the real `MuguWilderFish_blast_occurrences_clean.rds`:
  **531,063 of 531,596 rows (99.9%) were never spatially validated**, of which
  529,488 were `Coastal-Marine-Estuary-Stream` -- a *Coastal-Marine-Estuary*
  habitat classified freshwater because the anchored marine pattern could not
  see `Marine` or `Estuary` mid-name while the unanchored freshwater pattern
  matched `Stream`. After the fix the same data is 1,067 rows (0.2%)
  unverified; **529,996 rows newly enter spatial verification.**

  Both patterns are now word-boundary matched and live side by side as
  `.marine_name_pattern` / `.freshwater_name_pattern` so the symmetry is
  visible, with marine tested first so a genuinely multi-realm name is
  validated rather than exempted.

  Two further defects fell out of the same change. The anchored marine pattern
  also failed on every habitat name `example_habitat_scheme` itself teaches --
  `Rocky Intertidal`, `Rocky Subtidal`, `Sandy Subtidal`,
  `Shallow Kelp Forest (<10m)`, `Coastal Pelagic` were all `unknown` and
  skipped. And the unanchored freshwater pattern matched *terrestrial* names by
  accident: `Ponderosa Pine Forest` matched `pond`, `Fenced Grassland` matched
  `fen`. Inflections are now enumerated rather than matched as bare prefixes.

* `flag_habitat_inconsistencies()`: **reports what it did NOT check.** Every run
  now names the habitats exempted (freshwater) or unrecognised (`unknown`) with
  point counts, and warns when they are the majority. A checker that only
  reports what it examined cannot tell you what it skipped -- which is precisely
  how the defect above went unnoticed. Note `Deepwater` and `Terrestrial` remain
  `unknown` by design; they are now *reported* rather than silently absorbed,
  and `habitat_scheme=` with a `realm` column resolves them explicitly.

## Bug fixes (2026-09-15)

* `flag_habitat_inconsistencies()`: **two independent defects in
  `dist_to_coast_km`**, both of which silently produced distances that were too
  large. The code change landed in commit `69e4df0`, whose message describes
  unrelated work -- this entry is the record of what it contained.

  1. **Missing island coastlines.** The coastline came from
     `rnaturalearth::ne_coastline(scale = "large")` alone, which omits smaller
     islands. Measured on real PtConception occurrence data: **Anacapa**
     (72,685 records) scored a minimum of 8.79 km from "the coast" and
     **Santa Barbara Island** (3,119 records) 46.67 km, instead of ~0. Six of
     the eight California Channel Islands were already present and unaffected.
     Fixed by unioning in the Natural Earth 10m `minor_islands_coastline`;
     Anacapa now reads 0.08 km and Santa Barbara Island 0.19 km. If that layer
     cannot be downloaded the function warns explicitly rather than silently
     scoring islands against the mainland.

  2. **Web Mercator distance inflation.** Both the coastal buffer and the
     distance were computed in `EPSG:3857`, which inflates true ground distance
     by `1 / cos(latitude)`. Measured 2026-09-15: the 3857/geodesic ratio is
     **1.212** at Point Conception against a predicted `1 / cos(34.25) = 1.210`.
     The error grows with latitude -- roughly **21% at 34 deg, 35% at 42 deg,
     47% at 47 deg** -- so **GreatLakes was affected more than PtConception**.
     A true 4.1 km read as 4.97 km, meaning a `< 5 km` filter was behaving as a
     `< 4.1 km` filter. Fixed with a new internal `.utm_crs_for()` that selects
     the local UTM zone from the data centroid (UPS above 84 deg, warning above
     a 12 deg longitude span); UTM matches geodesic to within 0.1%.

  **This changes existing outputs.** Every `dist_to_coast_km` previously
  produced was too large, so past runs were *conservative*: re-running admits
  records that were previously excluded. Any threshold tuned against the old
  numbers -- `marine_questionable_km`, the depth-covariate work, a study's
  distance filter -- was tuned against inflated values. Habitat caches keyed on
  taxon name are unaffected; anything storing a distance is not.

  Regression tests added for UTM zone selection, geodesic agreement, and the
  presence of both islands in the minor-islands layer (`devtools::test()`
  322 passing / 0 failing, baseline 315).


## New features (2026-09-12)

* `save_spatial_review_decisions()` / `apply_spatial_review_decisions()`:
  persist a reviewer's `review_spatial_flags()` decisions per `point_id` and
  re-apply them on the next run, so the gadget opens only for flagged points
  with no decision yet. Every production workflow had been re-opening the
  gadget and overwriting the previous decisions on each run.

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
