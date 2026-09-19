# TaxaHabitat 0.1.0

## New features (2026-09-19, filter counts)

* `review_spatial_flags()`: every entry in the **Habitats** sidebar filter now
  shows how many points it holds **in the view on screen** -- so a reviewer
  knows before ticking whether a category means 5 points or 5,000, and can see
  when one has been emptied by reassignment.

  A category reduced to zero is **greyed and struck through, not removed**.
  Removing entries mid-session would make the list jump under the cursor while
  the reviewer is working down it, and would erase the evidence that the group
  ever existed -- which is the accounting the count exists to provide. A
  category at `(0)` is visibly finished; an absent row is indistinguishable
  from one that was never there.

  Counts are per view, so switching Likely -> Questionable re-counts. On the
  PtConception demo the Questionable view holds only Terrestrial, so most
  categories correctly read `(0)` there.

## New features (2026-09-19, composite categories)

* `review_spatial_flags()`: **an unassigned point is no longer a single
  undifferentiated "Unknown"** -- it is labelled with the habitats actually in
  contention, e.g. `"Estuarine | Freshwater | Marine"`, and that label is a
  real category with its own colour and its own entry in the **Habitats**
  sidebar filter.

  Previously every ambiguous point looked like the same problem and could only
  be resolved one click at a time. Now the review loop is: filter to one
  signature, draw a polygon over a region, and reassign the whole group to
  whichever habitat the location implies. **Location disambiguates what the
  assemblage cannot.**

  On the PtConception demo this turns 646 "Unknown" points into 12 named
  groups -- the largest holding 248 -- and leaves zero points labelled
  "Unknown".

  Members are sorted **alphabetically**, not by proportion, so the same
  candidate set always lands in the same group; ordering by proportion would
  split one kind of problem across several sidebar entries and defeat group
  selection. Per-point proportions still appear in the Reassign dropdown.

  **The label is a display category only.** `main_habitat` stays `NA` in the
  returned data until the point is actually reassigned, because the Done
  handler writes back only habitats that differ from what the gadget started
  with. Verified on the real fixture: touching nothing returns 5,625 `NA` rows
  unchanged with zero signature strings; reassigning one group sets 21 rows and
  still leaks nothing.

## New features (2026-09-19, later still)

* `review_spatial_flags()` gains **`candidate_mass`** (default `0.8`): the
  Reassign Habitat dropdown now offers what the selected point's own assemblage
  hypothesises, rather than the whole scheme.

  When `occurrence_data` carries a `"habitat_proportions"` attribute -- which
  `assign_habitat_biological()` attaches and `flag_habitat_inconsistencies()`
  preserves, so production workflows need no change -- the dropdown lists the
  habitats covering `candidate_mass` of the consensus vector, highest first and
  labelled with their proportions. A bulk selection sums its points' vectors
  first.

  A cumulative-mass rule rather than a fixed proportion cutoff, because the
  cutoff was measured and rejected: the LLM emits round numbers, so the 5th
  percentile of non-zero proportions is already 0.10 and a 0.05 cutoff takes a
  5-habitat scheme only to 3.98 candidates. Across the 31,383 unassigned
  PtConception 12S points, `candidate_mass = 0.8` gives **mean 2.91 candidates,
  median 3**, with 90% of points landing on exactly three -- and it adapts:
  a river-mouth point reading Freshwater 0.45 / Marine 0.40 is offered only
  those two, because they already cover 0.85.

  The point's current habitat is always offered even when outside the mass, so
  a reassignment can be undone by hand; **Other** (free text) is always offered;
  and a **Show all habitats (N hidden)** checkbox restores the full scheme for
  when the consensus itself is what the reviewer disputes. With no attribute
  present the dropdown behaves exactly as before.

## New features (2026-09-19, later)

* `assign_habitat_biological()` gains **`main_habitat_prop`** and
  **`main_habitat_breadth`**, and attaches the full per-point consensus vector
  as **`attr(result, "habitat_proportions")`**.

  The function already computed the winning proportion and the whole proportion
  matrix, then discarded both -- so two very different points came back
  identically as `main_habitat = NA`: one clearly Marine at 0.48 just under a
  0.5 threshold, and one genuinely mixed at 0.35/0.33/0.32. `main_habitat_prop`
  separates them and `main_habitat_breadth` (Levins' B, effective number of
  habitats) quantifies the spread. Both are populated **regardless of**
  `threshold`, so they describe exactly the points the threshold rejected --
  which is the purpose.

  Measured on the real PtConception 12S data at the workflow's own
  `threshold = 0.5`, reproducing its saved output exactly (495,014 NA rows /
  31,383 NA points): **89% of NA points are genuinely mixed (breadth >= 3.0,
  median 3.57) and NONE are high-proportion near-misses.** Lowering the
  threshold would not rescue them -- there is no population of unambiguous
  points being wrongly rejected. They need a reviewer choosing among the
  habitats actually hypothesised there, not a different cutoff.

  `"Other"` is excluded from the breadth calculation, matching the taxon-level
  `habitat_breadth`: it measures failure to place taxa in the scheme, not a
  genuinely broad assemblage. It IS retained in the proportions attribute,
  which is the raw consensus vector.

  The proportions are an attribute rather than columns because they are one
  value per habitat per point while the result is one row per occurrence;
  widening them would repeat the same vector across every record at a location.

## New features (2026-09-19)

* **`drop_stale_seeded_decisions()`** -- removes seeded spatial-review decisions
  that the automatic classifier has since overtaken.

  A decisions file seeded with `before = NULL` records "accept the automatic
  classification" for every point, with `decided_at` set to a `"seeded from ..."`
  string rather than a timestamp. When the classifier later changes its mind --
  a bug fixed, a vocabulary extended, a threshold moved -- the seeded verdict
  silently overrides the new one and `apply_spatial_review_decisions()` reports
  `n_pending_review = 0`. The site looks fully reviewed while carrying the old
  classifier's answer.

  Audited on 2026-09-19: **all three production decision files were 100% seeded
  -- 244,860 decisions, zero real reviews**, all from runs of 2026-09-11. Two
  were masking live changes: Mugu 1,044 points (`likely` -> `unlikely`, from the
  realm fix in c1fd1a1) and PtConception 12S 2,000 points (`likely` ->
  `questionable`, predating that work -- terrestrial points sitting at 0.8-1.0 km
  against a 1 km coastal buffer, tipped across by a `dist_to_coast_km` change
  since seeding). GreatLakes had none.

  Only **seeded** decisions are eligible. A real reviewer decision survives a
  classifier change, because the reviewer overrode the classifier deliberately
  and a later change of its mind must not erase that judgement. `dry_run = TRUE`
  is the default and the file is backed up before any write.

## Bug fixes (2026-09-19)

* `flag_habitat_inconsistencies()`: **`Lentic` and `Lotic` are now recognised as
  freshwater.** They are the standard limnological terms for standing and
  flowing water and are what the GreatLakes sites actually use -- and neither was
  in the vocabulary, so **both GreatLakes plates classified 100% of points as
  realm `unknown` and were skipped entirely**: 6,217 and 11,154 rows, every run,
  reported as `habitat 'Lentic' not found in habitat scheme -- skipped`.
  Verified against both saved `occurrences_clean` checkpoints.

  Note this makes GreatLakes *correctly classified*, not *verified*: freshwater
  is exempt from spatial verification by design, so those points remain
  unchecked -- now for a stated reason that appears in the exemption report
  rather than as an unrecognised name.

* `flag_habitat_inconsistencies()`: **`Deepwater` is now recognised as marine.**
  It is a realm term, not a depth term and not a water-column position. At Mugu
  it carries demersal taxa -- *Microstomus pacificus*, *Xeneretmus ritteri*,
  *Bathyagonus pentacanthus*, *Icelinus* spp. -- on the bottom between -798 m and
  the shelf, so mapping it to `Pelagic` would assert a position those species do
  not occupy. Depth is carried separately by the bathymetry zones
  (`marine_shallow` / `marine_deep` / `marine_abyssal`). 72 previously
  unverified Mugu rows now enter spatial verification.

* `parse_hierarchical_habitat_response()`: the `Habitat` column's documentation
  claimed it was "used by downstream functions (`assign_habitat_biological`)
  that expect a single primary habitat label per species". **That was false** --
  `assign_habitat_biological()` sums each species' full weight vector per point
  and never reads it. Audited across all nine packages, its only functional
  consumer is `build_habitat_lookup()`, which uses `!is.na(Habitat)` to decide
  cacheability. Now documented as diagnostic only, with a pointer to the weight
  columns, `main_habitat` and `habitat_breadth` instead. A doc asserting a
  contract the code does not honour is worse than no doc, because it invites
  someone to build on it.

## New features (2026-09-18, later)

* `parse_hierarchical_habitat_response()` and `build_habitat_lookup()` gain a
  **`habitat_breadth`** column: Levins' niche breadth, `B = 1/sum(p^2)`,
  over the scheme's habitat columns, in units of **effective number of
  habitats** (1 = pure specialist, maximum = number of habitat columns).

  `Habitat` is an argmax, so it renders a near-uniform weight vector and a
  decisive one as the same confident-looking string. On the real PtConception
  12S lookup, *Larus delawarensis* and *Chroicocephalus philadelphia* carry
  identical weights (Marine 0.30 / Estuarine 0.20 / Freshwater 0.30 /
  Terrestrial 0.20) and both read `"Marine"`, while *Gelochelidon nilotica*
  (0.20/0.20/0.30/0.30) reads `"Freshwater"` -- the label is decided by column
  order. Of 681 taxa, 16 have breadth >= 3.5 (near-uniform across all four
  habitats) and 425 have breadth <= 1.2; the broad ones are gulls, terns and
  cormorants, exactly the taxa a single-label scheme cannot represent.

  `Other_weight` is deliberately excluded from the calculation. It measures the
  model failing to place a taxon in the scheme at all -- "no information" --
  which is a different quantity from a taxon that genuinely spans habitats.
  Read the two together.

  The column is **derived, never stored**, and is recomputed in
  `build_habitat_lookup()` after the cache combine. Entries cached before it
  existed carry the weights but not the breadth, and `bind_rows()` would have
  filled those with `NA` silently and permanently for every already-cached
  taxon. Deriving it means no cache-key bump and no re-running the LLM over
  thousands of settled taxa.

* `parse_hierarchical_habitat_response()` and `build_habitat_lookup()` now
  record an **`"habitat_cols"` attribute** naming the weight columns, and
  `assign_habitat_biological()` prefers it over scanning for numeric columns.

  This was not optional. `.detect_habitat_cols()` inferred the weight set by
  column type, excluding only `taxon_col`, `habitat_best_guess`,
  `ecoregion_best_guess` and `Habitat` -- so adding a numeric `habitat_breadth`
  column made it a sixth habitat weight. Because breadth is on the scale
  "effective number of habitats" (up to ~4) rather than 0-1, it outweighs every
  real weight and **always** wins the argmax: reproduced before the fix, a
  generalist came back with `main_habitat = "habitat_breadth"`, no error and a
  plausible-looking result. The taxa the column exists to identify were exactly
  the ones it would have corrupted.

  The declared set is `c(<scheme habitat cols>, "Other_weight")` -- precisely
  what the type scan picks up today, with a test asserting the two paths agree,
  so recording the contract does not quietly change it. The fallback scan also
  excludes `habitat_breadth` by name, so a hand-assembled table with no
  attribute is safe. A stale attribute naming absent columns falls back to
  scanning rather than silently narrowing the weight set.

  Caught before release by a peer session that recognised the collision in its
  own run log.

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
