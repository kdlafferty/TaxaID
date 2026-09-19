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
  **530,558 of 531,596 rows (99.80%) were never spatially validated** -- 530,259
  freshwater-exempt, 75 unknown-realm, 224 missing habitat, leaving only 1,038
  rows actually checked. Of the exempted, 529,488 were `Coastal-Marine-Estuary-Stream` -- a *Coastal-Marine-Estuary*
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

## New features (2026-09-18)

* `review_spatial_flags()`: **polygon (lasso) selection**, alongside the
  existing rectangle. Real selection boundaries -- a coastline, a lake shore, a
  basin -- are rarely rectangular, and approximating one with repeated
  rectangles multiplied the number of review rounds. Both shapes arrive through
  the same `map_draw_new_feature` input as a GeoJSON ring, so a rectangle is
  now just the axis-aligned special case; a bounding box prefilters candidates
  and `.points_in_polygon()` does an even-odd ray cast on the survivors
  (5,000 candidates against a 60-vertex ring: **13 ms**). The cast runs in Web
  Mercator, matching the straight-line edges leaflet actually draws, so the
  selection agrees with the shape on screen. An axis-aligned rectangle skips
  the cast entirely and costs exactly what it did before. No new dependency:
  `sf`'s lon/lat predicates go through `sf_use_s2()`, which is global state an
  interactive gadget must not mutate mid-review.

* `review_spatial_flags()`: **selection size gate**, `bulk_confirm_threshold`
  (default `10000L`) and `bulk_max` (default `100000L`). At or below the
  threshold a bulk action applies straight away; above it a dialog reports the
  exact point count and requires an explicit Apply; above `bulk_max` it is
  refused. The gate deliberately **never truncates** -- a partially applied
  selection would leave the un-applied points scattered through the drawn
  shape, rendered identically to points that were never selected, invisible to
  the reviewer and indistinguishable in the output.

* `review_spatial_flags()`: **grouped undo**. Each bulk action is recorded as
  one history entry covering every point it touched, so **Undo Last** reverses
  a whole selection in a single click. Previously a 5,000-point action needed
  5,000 undo clicks, or Cancel -- which discards the entire review session. A
  single-point click is simply a one-element group. The sidebar now reports
  both counts ("N override(s) in M action(s)").

## Performance (2026-09-18)

* `review_spatial_flags()`: four loops that scaled badly with selection size
  were vectorised. These were **latent before polygon selection existed** -- a
  rectangle dragged over the whole map hit them too -- but polygon selection
  makes large selections routine rather than rare.

  1. **Done handler.** Writing reassigned habitats back looped over changed
     points, scanning every row and copying the whole habitat column each time
     (`O(n_changed * nrow)`). Measured on a 2,185,193-row input with 5,000
     changed points: **~2 minutes, reduced to 0.033 s** by a single `match()`
     pass. This was by far the most expensive thing in the gadget. It now also
     uses `which()`, so an `NA` comparison drops out instead of indexing with
     `NA`.
  2. **Marker redraw.** Bulk flag and habitat actions issued `removeMarker()`
     and `addCircleMarkers()` **per point** -- two queued websocket messages
     each, so a 5,000-point action queued 10,000. Now one vectorised
     `removeMarker()` plus one `addCircleMarkers()` per distinct habitat.
     `.add_habitat_marker()` accepts one or many rows.
  3. **Per-point row lookup.** `pts[pts$point_id == pid, ]` inside the loop was
     a full linear scan per point; replaced with one `match()`.
  4. **History growth.** `c(hist, list(...))` inside the loop copied the
     growing list on every iteration (`O(k^2)`); now one append per action.

* `review_spatial_flags()`: markers render with `preferCanvas = TRUE`. SVG
  markers stop being usable in the tens of thousands; canvas markers keep
  going well past that. This matters because the production workflows pass the
  **whole** flagged dataset in -- 1,092,230 unique points for PtCon 18S.

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
