# CLAUDE.md
# 2026-09-18, later (Opus 5): flag_habitat_inconsistencies() REALM BUG FIXED. The marine and
# freshwater name patterns were ASYMMETRIC -- marine "^"-anchored, freshwater unanchored -- so
# any habitat not STARTING with a marine word fell through to the freshwater test, and
# freshwater is exempt from spatial verification BY DESIGN. Real Mugu: 530,558 of 531,596 rows
# (99.80%) never spatially validated -- 530,259 freshwater-exempt + 75 unknown-realm + 224
# missing habitat, only 1,038 rows actually checked -- 529,488 of them "Coastal-Marine-Estuary-Stream" (marine
# name, matched freshwater on "Stream"). After the fix: 1,067 rows (0.2%) unverified, 529,996
# newly verified; on a 2,982-point sample 163 points (5.5%) come back UNLIKELY -- real errors
# that were invisible before. Same change fixed two more: every example_habitat_scheme name
# ("Rocky Intertidal", "Shallow Kelp Forest (<10m)", "Coastal Pelagic" ...) was "unknown" and
# skipped, and the unanchored freshwater pattern matched TERRESTRIAL names by accident
# ("Ponderosa Pine" -> "pond", "Fenced Grassland" -> "fen"). Patterns now live side by side as
# .marine_name_pattern/.freshwater_name_pattern with a test asserting neither uses "^".
# flag_habitat_inconsistencies() now also REPORTS what it did not check (names + counts, warns
# above 50%). devtools::test() 377+, check() clean. Found while building a gadget test fixture:
# three attempts to produce questionable/unlikely points all failed, and the reason WAS the bug.
# -- TaxaHabitat
# 2026-09-18 (Opus 5): review_spatial_flags() gains POLYGON (lasso) selection beside the
# rectangle, a never-truncating size gate (bulk_confirm_threshold=10000L / bulk_max=100000L),
# and GROUPED UNDO (one history entry per bulk action). The polygon itself was the cheap part --
# both shapes already arrived through the same map_draw_new_feature GeoJSON ring, which the old
# code collapsed to a bbox. The real work was four loops that scaled badly with selection size
# and were ALREADY latent (a whole-map rectangle hit them too): the Done handler's habitat
# write-back was O(n_changed * nrow) and measured ~2 MINUTES for 5,000 changed points over
# 2,185,193 rows, now 0.033 s; per-point removeMarker/addCircleMarkers queued 2 websocket
# messages per point; a per-point linear scan of pts; and O(k^2) history growth. Also
# preferCanvas=TRUE. devtools::test() 351/0, check() 0 errors / 0 warnings / 0 notes.
# (An earlier run of the same check showed a "checking for future file timestamps ... unable
# to verify current time" NOTE; that is R failing to reach its time server and is transient --
# it did not reproduce. Not a package problem, don't chase it.) Reinstalled. Branch
# polygon-select-review-spatial-flags, based on main, NOT COMMITTED. See "Open Questions" for
# the PtCon 18S finding this turned up. -- TaxaHabitat
# 2026-09-13, evening (Sonnet 5): ecosystem review Section L (D-A1) -- RESOLVED, was OPEN
# below. save_spatial_review_decisions() now warns, naming the count, when before = NULL
# would record habitats as reassignments -- i.e. freeze automatic classifications with no
# re-validation, silently, on first seeding. MEASURED first: all three seeded production
# decision files are clean (0 of 244,860 rows have habitat_reassigned = TRUE, 0 frozen
# habitats) and all four live call sites already pass before=. The worry behind D-A1 was
# unfounded; the guard is the only change, for any future seeding call. Full record:
# ecosystem_docs/fable_ecosystem_review_2026-09-13.md Section L. — TaxaHabitat
# Previous update, 2026-09-13 (Sonnet 5): ecosystem review, roxygen-only pass on spatial_review_decisions.R
# (save_spatial_review_decisions()/apply_spatial_review_decisions() @section notes: seeding
# with before=NULL freezes habitats at their automatic classification with no
# re-validation). inst/CITATION -> 0.1.0 + github.com/DOI-USGS/TaxaID. No code changed in
# this package today. devtools::check() 0 errors / 0 warnings on all 8 touched packages (4 top-level-file NOTEs, all from README.md.bak_* files, now .Rbuildignored in every package); all 9 packages reinstalled 2026-09-13 18:14 UTC to ~/Library/R/4.0/library; not yet reinstalled. OPEN, awaiting user verdict (not
# fixed): D-A1, seeding without before= freezes automatic habitats. Full findings:
# ecosystem_docs/fable_ecosystem_review_2026-09-13.md. — TaxaHabitat
# Previous update, 2026-09-12 (Fable 5.1): NEW save_spatial_review_decisions() / apply_spatial_review_decisions()
# (R/spatial_review_decisions.R). review_spatial_flags() returns a reviewer's DECISIONS, and every
# workflow re-opened the gadget and overwrote them on each run (the search-polygon lesson again).
# Decisions are kept in one small .rds per site keyed on point_id (stable: TaxaFetch::
# stack_occurrences() builds it from the coordinates); apply_* overwrites spatial_flag/
# main_habitat for decided points, prefixes spatial_flag_reason with "reviewer decision (date)",
# and reports n_pending_review (flagged points with no decision) so the workflow opens the gadget
# only when that is > 0 or REDO_SPATIAL_REVIEW <- TRUE. Seeded at GL / PtCon 12S / Mugu from the
# last completed runs' occurrences_clean checkpoints (every retained point = "likely" with its
# reviewed habitat; points the reviewer had excluded are NOT recoverable from that file and will
# be re-asked once). 4 tests, check clean, reinstalled. — TaxaHabitat
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Full chronological session history: ecosystem_docs/session_notes/TaxaHabitat_sessions.md
# This file holds durable reference material only (purpose, functions, design
# notes, footguns, settled decisions) plus a short recent-activity summary —
# not a growing session-by-session log. See "Recent Activity" at the bottom
# for what actually happened last, and the archive above for the full story
# behind any of it.

---

## Package Purpose
Assigns habitat classifications to taxonomic occurrence records using LLM prompts
and performs spatial quality control. Receives occurrence data from TaxaFetch and
produces habitat-annotated, spatially screened records for input to TaxaExpect.
Part of the TaxaID ecosystem.

**Status: All functions passing devtools::check() (0 errors, 0 warnings, 0 notes).**

---

## Dependency Chain
TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign/TaxaMatch

TaxaHabitat depends on TaxaTools for LLM provider functions
(`call_anthropic_api`, `call_gemini_api`, `call_openai_api`, `call_ollama_api`,
`prompt_api`, `prompt_manual`, `read_llm_response`).

---

## Function Inventory

| Function | File | Status | Description |
|---|---|---|---|
| `build_habitat_prompt()` | R/build_habitat_prompt.R | Complete | Build habitat assignment prompt object. `geographic_context` param adds geographic hint + `ecoregion_best_guess` column. |
| `build_iucn_scheme()` | R/build_habitat_prompt.R | Complete | Build a `habitat_scheme` data.frame from the IUCN Habitats Classification Scheme v3.1, filtered by `realm`/`l1`/`l2`. Discovery mode (`build_iucn_scheme()`, `build_iucn_scheme(realm=...)`) lists available categories. Duplicate L2 names across L1 groups (e.g. "Boreal") are disambiguated as "Boreal (Forest)". **2026-09-04 doc gap**: exported but missing from this table since it was added; found during the ecosystem-wide accuracy pass. |
| `example_habitat_scheme` | R/build_habitat_prompt.R | Complete | Bundled example `habitat_scheme` data.frame (kelp forest/rocky reef/soft bottom/pelagic/estuarine) -- a copy-and-edit starting template for a custom scheme. **2026-09-04 doc gap**: same as above. |
| `build_scheme_prompt()` | R/build_habitat_prompt.R | Complete | Stage-0 LLM prompt builder for the auto-scheme workflow -- given a taxon list, asks the LLM to suggest `min_habitats`-`max_habitats` sensible single-level habitat categories, output parsed by `parse_scheme_response()`. **2026-09-04 doc gap**: same as above. |
| `parse_scheme_response()` | R/build_habitat_prompt.R | Complete | Parse `build_scheme_prompt()`'s raw LLM response into a single-level `habitat_scheme` data.frame (`l2_name`/`l2_code` set `NA`), suitable for `build_habitat_prompt(habitat_scheme=)`. **2026-09-04 doc gap**: same as above. |
| `report_habitat()` | R/report_habitat.R | Complete | Generate a `report_section` object (TaxaTools) summarizing habitat assignment for Methods/Results reporting; feeds `TaxaTools::assemble_report()`. **2026-09-04 doc gap**: exported since Session 65 but missing from this table; found during the ecosystem-wide accuracy pass. |
| `build_habitat_lookup()` | R/build_habitat_lookup.R | Complete (2026-09-10) | Cached one-call wrapper over `build_habitat_prompt()` -> `TaxaTools::prompt_api()` -> `parse_hierarchical_habitat_response()`. Per-taxon on-disk cache (`cache_dir=`), keyed on taxon + scheme-derived habitat columns + covariates + context + `cache_tag`; full key verified on read. Unresolved rows (`Habitat` NA) are never cached. The habitat step of all 6 production workflows + both templates now calls this. |
| `taxahabitat_clear_cache()` | R/build_habitat_lookup.R | Complete (2026-09-10) | Report/prune that cache via the shared TaxaTools cache engine (pattern `_habitat\.rds$`), matching `TaxaFlag::taxaflag_clear_cache()`. |
| `parse_hierarchical_habitat_response()` | R/parse_habitat_response.R | Complete | Parse LLM CSV response into habitat weights table. Protects `ecoregion_best_guess` from numeric detection. Repairs unquoted-comma-corrupted rows before `read.csv()` sees them (see Known Footguns). |
| `assign_habitat_biological()` | R/assign_habitat_biological.R | Complete | Join habitat weights to occurrence data (per-point consensus). Param is `occurrence_data`, not `data` — see Known Footguns. |
| `consensus_habitat()` | R/assign_habitat_biological.R | Complete | Assemblage-level consensus habitat from per-species weights; modal ecoregion extraction. Returns one-row data frame. |
| `flag_habitat_inconsistencies()` | R/flag_habitat_inconsistencies.R | Complete | Flag occurrences inconsistent with habitat. |
| `review_spatial_flags()` | R/review_spatial_flags.R | Complete | Interactive Shiny review of spatial flags. Wired into 5 real production workflows. |
| `flag_institution_candidates()` | R/flag_institution_candidates.R | Complete | Classification stage for `TaxaFetch::filter_gbif_quality()`'s `institution_flag` column — tiers "high"/"low"/"ambiguous" by crossing matched institution `type` against record `kingdom`. Pure function, no interaction, no removal (mirrors `flag_habitat_inconsistencies()`). |
| `review_institution_flags()` | R/review_institution_flags.R | Complete | Interactive Shiny/leaflet review of `flag_institution_candidates()`'s tiers — click a flagged record to toggle Keep/Remove, matched institution shown as a second map layer. Deliberately scoped down from `review_spatial_flags()` (single view, no bulk-select, single-level undo) given real datasets here are small. Every record starts "keep." Wired into all 5 real production workflow scripts (2 Mugu + 3 PtConception). |
| (plot helpers) | R/utils_plot.R | Complete | Internal plotting utilities. |
| `.detect_habitat_cols()` | R/assign_habitat_biological.R | Internal | Shared habitat column detection logic used by `assign_habitat_biological()` and `consensus_habitat()`. |

Note: `assign_habitat_to_points()`, `plot_habitat_points_interactive()`, and
`select_habitat_outliers()` do NOT exist in this package despite being
referenced in some older external docs/roxygen — apparently planned but
never built. Don't go looking for them; `review_spatial_flags()` is the real
interactive review entry point.

---

## LLM Workflow

The full three-path habitat assignment workflow:
1. **Path 1 (API auto):** `build_habitat_prompt()` → `prompt_api()` [TaxaTools] → `parse_hierarchical_habitat_response()`
2. **Path 2 (manual):** `build_habitat_prompt()` → `prompt_manual()` [TaxaTools] → `read_llm_response()` [TaxaTools] → `parse_hierarchical_habitat_response()`
3. **Path 3 (inline):** build prompt manually → paste response as string → `parse_hierarchical_habitat_response()`

Provider functions (`call_anthropic_api`, `call_gemini_api`, etc.) live in TaxaTools.

---

## Key Design Notes
- `parse_hierarchical_habitat_response()` returns WIDE WEIGHTED output: one row
  per species, one numeric column per habitat in the scheme (0-1 weights), plus
  `Other_weight`, `habitat_best_guess`, and `Habitat` (argmax convenience column).
- `build_habitat_prompt()` supports both IUCN and custom habitat schemes.
  The `$habitat_cols` element of the returned prompt object drives column detection
  in `parse_hierarchical_habitat_response()`.
- `build_habitat_prompt(geographic_context = "Southern California")` adds a
  `GEOGRAPHIC CONTEXT:` block to the prompt and requests an `ecoregion_best_guess`
  column. The column is stored in the returned S3 object as `$geographic_context`.
- `consensus_habitat()` computes assemblage-level consensus from per-species habitat
  weights (equal-weight sum → argmax with threshold). Returns `main_habitat`,
  `ecoregion` (modal `ecoregion_best_guess`), and `habitat_best_guess` in a one-row
  data frame. `attr(result, "habitat_proportions")` has the full proportion vector.
- `%||%` is defined internally in `parse_habitat_response.R` and is available
  throughout the package namespace.
- **`review_spatial_flags()`'s Reassign-Habitat click behavior**: reassigning a
  point's habitat when its `spatial_flag` is already Likely/Unlikely keeps that
  flag as-is (does NOT force it to "questionable"). Reassigning FROM Questionable
  still promotes to Likely. This was a deliberate design change at the user's
  request (2026-08-02) to halve reviewer workload for the common case.
- The IUCN Habitats Classification Scheme lookup table (`.iucn_habitat_lookup`)
  was fully rebuilt row-by-row against the real IUCN v3.1 source document
  (2026-08-01) after a domain review found ~15 real errors (wrong ordering,
  wrong codes, several outright fabricated entries) that had gone undetected
  for a long time. If this table is ever extended, verify new rows against the
  primary IUCN document directly — do not trust secondary sources or memory.

---

### The habitat LLM step MUST be cached (2026-09-10)

A habitat verdict is not cosmetic: it decides which of a species' occurrence records
count toward a habitat-stratified site prior in TaxaExpect. Uncached, the verdict can
differ between two runs on identical input, and a species then moves between
`resident_observed` and `resident_undetected` with its kernel prior changing by orders
of magnitude. Measured on the real 2026-09-10 GreatLakes run: *Moxostoma
macrolepidotum*'s 16 nearby records all read Lotic, it fell to the undetected branch
(theta 1.1e-5 vs 0.06 in the 2026-09-07 baseline), *M. anisurum* (one Lentic record
140 km away) won 28 observations and was then amplified 478x by the consensus prior
update, and Lamar precision fell 0.853 -> 0.805 with the reference screen's own
likelihood effect measured at ~0. `build_habitat_lookup(cache_dir=)` is the fix; it is
the same design `TaxaFlag::review_assignments(cache_dir=)` adopted on 2026-09-04 for the
same reason. Do not re-introduce the bare three-step pattern in a workflow.

The cache freezes whichever verdict came first. That is the point (reproducibility),
but it means a wrong verdict persists until someone clears it
(`taxahabitat_clear_cache()`) or changes `cache_tag`. The per-taxon files are plain
`list(key, row)` .rds and can be inspected directly.

## Known Footguns

- **`flag_habitat_inconsistencies()` reports "likely" for points it never
  checked.** Freshwater is exempt from spatial verification by design (to avoid
  false positives), and an unrecognised habitat name is skipped entirely. BOTH
  return `flag = "likely"` with a reason that reads like a pass
  (`"freshwater habitat not spatially verified"`,
  `"habitat '<x>' not found in habitat scheme -- skipped"`). A site can
  therefore pass QC almost untouched and look fine -- Mugu did, at 99.9%, for
  months. The function now names the skipped habitats and their counts every
  run and warns above 50%, but **read that report**: "0 unlikely" means
  "nothing was wrong" only if the verified share was high. When adding a new
  habitat vocabulary, pass `habitat_scheme=` with a `realm` column rather than
  relying on name matching.


- **A bulk gadget action must never silently truncate its selection.** The
  obvious cap for a large lasso selection -- "apply to the first N" -- is
  wrong here: `pts` is ordered by the occurrence data's own row order
  (taxon/accession), not spatially, so "the first N" inside a drawn shape is an
  arbitrary SCATTERED subset of it. The un-applied points stay on the map in
  their old colour, interleaved with the applied ones and visually identical to
  points that were never selected, and the reviewer has no way to see which is
  which. `review_spatial_flags()` therefore gates by size (apply / confirm /
  refuse) and never truncates. Rejected 2026-09-18 after the user proposed the
  first-N form; the reasoning applies to any future bulk action in any gadget
  in this ecosystem.


- **`leaflet`'s own `data` parameter can collide with an ecosystem-wide
  rename sweep.** When `assign_habitat_biological()` et al.'s `data` param
  was renamed to `occurrence_data` (2026-08-01), a find/replace also touched
  an unrelated `leaflet::addCircleMarkers(data = ...)` call inside
  `review_spatial_flags()`'s own map renderer — `leaflet`'s `data` argument
  belongs to that package, not ours, and the collision broke ALL marker
  rendering until caught and fixed the next day. If you ever rename a
  parameter that happens to share a name with a `leaflet`/`shiny`/other
  dependency's own argument, grep specifically for calls INTO that
  dependency before trusting a bulk rename.
- **A NAMED character vector passed to leaflet as a per-marker color/value
  vector serializes to JSON as a keyed object, not a per-marker array** —
  duplicate names (e.g. repeated "keep"/"remove" labels) silently collapse,
  and markers fall back to an undefined/black default with no error. Always
  `unname()` a color-lookup vector before passing it to any `leaflet::add*()`
  call.
- **`utils::read.csv()`'s row-name inference silently corrupts a row with an
  unquoted comma in a free-text field.** An LLM-generated CSV response with
  an unquoted comma inside a value (e.g. `habitat_best_guess`) causes a
  field-count mismatch that `read.csv()` "fixes" by treating the first
  column as an invisible row name — every later column silently shifts left,
  and nothing errors. `build_habitat_prompt()` now instructs the LLM to
  quote comma-containing fields, and `parse_hierarchical_habitat_response()`
  defensively repairs an already-malformed row before parsing — but any new
  LLM-response-parsing code in this package should assume this failure mode
  can recur and guard against it explicitly, not rely on the LLM following
  instructions perfectly.

---

## Closed Questions & Rejected Approaches

- **`.collapse_to_model_habitats()`** — confirmed dead code (leftover from
  the `assign_habitat_llm()` pipeline removed 2026-02-27, before this
  package existed in its current form). Deleted 2026-08-01. If it's ever
  referenced anywhere else (old docs, memory), it no longer exists — don't
  try to resurrect or call it.
- **A hard "force to Questionable on reassignment" rule for
  `review_spatial_flags()`** — this was the ORIGINAL behavior and was
  deliberately changed (see Key Design Notes above); don't revert without
  checking with the user first, it was a direct request.
- **Several code-review comments investigated and confirmed as non-bugs,
  not fixed**: the `adehabitatMA` S3-overwrite startup warning (traced to
  `marmap`'s own Suggests, not something this package controls);
  `flag_institution_candidates()`'s `"Research_centre"` label (this is
  `CoordinateCleaner::institutions`'s own literal external vocabulary value
  — do not "fix" the spelling, it would break the join); a reviewer comment
  claiming `TaxaFetch::filter_gbif_quality()`'s interface had drifted
  (checked directly against source, found current — the review was against
  a stale snapshot).
- **`review_spatial_flags()`'s "bulk flag drawing doesn't work" complaint**
  — investigated fresh in the 2026-08-01 review pass (same symptom class as
  an earlier 6-round debugging thread) and, again, no new independently
  reproducible bug was found in the rectangle-select code path itself. See
  Open Questions below — this is different from, and less certain than, the
  2026-08-02 map-rendering regression that was found and fixed.

---

## Open Questions

- **PtConception 18S is running with NO spatial review at all.** Found
  2026-09-18 while sizing the polygon-selection work.
  `PtConceptionWorkflow_18S_2_single_site.R:961` has the call commented out and
  replaced with a bare filter:
  ```r
  #reviewed_spatial    <- review_spatial_flags(occurrences_flagged)
  occurrences_clean <- occurrences_flagged %>% filter(spatial_flag=="likely")
  ```
  That dataset is 2,185,193 rows / **1,092,230 unique points**, and the
  workflows pass the WHOLE flagged table to the gadget -- nothing prefilters to
  pending points. With SVG markers that could not have opened, which is the
  most likely reason it was commented out. `preferCanvas = TRUE` (2026-09-18)
  raises the marker ceiling by roughly an order of magnitude but has NOT been
  tested against this dataset, and rendering only pending points -- the deeper
  fix -- was explicitly deferred by the user as a behaviour change. Do not
  assume the 18S call can simply be uncommented; measure first.


- **The original "many Questionable points, Flag-mode does nothing" symptom
  is NOT definitively closed.** A large, unrelated map-rendering regression
  (the `leaflet` `data=` collision, see Known Footguns) was found and fixed
  2026-08-02 and may have been the true cause of the original symptom
  looking worse than it should — but this has only been verified against a
  small synthetic dataset, not the user's real large-scale GreatLakes data.
  Debug `message()` logging is still installed in `map_draw_new_feature`
  (`review_spatial_flags.R`) specifically to catch a recurrence. If the
  symptom comes back on real data, start there rather than re-diagnosing
  from scratch — see `ecosystem_docs/session_notes/TaxaHabitat_sessions.md`'s
  2026-08-02 entry (and the linked `[[project_review_spatial_flags_habitat_reassign_gap]]`
  memory) for the six earlier rounds of this thread.

---

## Recent Activity

**2026-09-10** (Opus 5): Hardened `report_habitat()`'s Shape A/Shape B dispatch.
The 2026-09-08 test — `any(vapply(candidate_cols, \(hc) all(is.na(x) | (x >= 0 & x <= 1))))`
— had two holes, both confirmed by direct evaluation and then reproduced end-to-end on the
real `PtConMifishSchulte_occurrences_clean.rds`: (1) it passes **vacuously** for an all-NA
numeric column, because `is.na(x)` is TRUE everywhere and the range half of the `|` is never
reached — GBIF exports routinely carry `depth`/`elevation`/`coordinatePrecision` like this;
(2) it passes for any genuinely proportional non-habitat column (a `coordinatePrecision` of
0.001, or a `dist_to_coast_km` that is 0 for every record in a coastal-only survey). Either
one sends occurrence-level data back down the weight branch and reprints the exact pre-fix
symptom: adding one all-NA `depth` column turned "356 taxa … Dominant habitat: Marine (89%
of assigned records)" into "20000 taxa … Dominant habitat: decimalLatitude (mean weight
3506%)". Replaced with `.looks_like_habitat_weights()`, which requires **positive** evidence:
every candidate column has ≥1 non-NA value AND lies in [0, 1.05], AND the columns compose —
over rows with any positive weight, >half sum to 1.0 within 0.05, deliberately the same
`abs(row_sums - 1) > 0.05 & row_sums > 0` rule `parse_hierarchical_habitat_response()` itself
uses. Chosen over the minimal `any(!is.na(x)) && all(...)` patch (closes hole 1 only) and over
purely structural dispatch (a hand-assembled table can carry `main_habitat` and real weights
together — this file's own "excludes known non-habitat columns" test does). **No current
production caller was affected**: audited PtCon 12S/18S and both GreatLakes occurrence
objects, and `decimalLatitude` is out of range in every one, so all four already dispatched
correctly — this is a latent guard, not a live fix. 6 regression tests added.
`devtools::test()` 287/0, `check()` 0/0/0. Reinstalled.

Same session, second fix: `n_taxa` on the WEIGHT branch used the raw `taxon_col`
while only `.summarise_main_habitat()` went through `.resolve_taxon_col()`. Since
`parse_hierarchical_habitat_response()` always emits `taxon_name` and
`report_habitat()` defaults to `"scientificName"`, the documented Shape A call
`report_habitat(parse_output)` silently fell through to `nrow()` — same class as
the "1419840 taxa" bug, on the other branch. Now resolved ONCE in
`report_habitat()` and handed to both branches; `.resolve_taxon_col()` is
idempotent so the helpers stay correct if called directly. An explicitly named,
present `taxon_col` still wins. 2 more regression tests.

**2026-09-10** (Fable 5.1): NEW `build_habitat_lookup()` + `taxahabitat_clear_cache()`
(R/build_habitat_lookup.R, 8 tests, no LLM call in tests). Motivated by the first full
GreatLakes run after the reference-screen rewiring: 56/885 consensus calls moved and
Lamar precision fell 0.853 -> 0.805, traced to run-to-run habitat-verdict drift, not to
the screen (see Key Design Notes above and TaxaID/CLAUDE.md 2026-09-10). All 6 production
workflows (GreatLakes, PtCon 12S single/multi, PtCon 18S, Mugu Fish/WilderFish) and both
templates rewired to it with `cache_dir = <OUT_PREFIX>_habitat_cache`; external files
backed up as `*.bak_pre_habitat_cache`. TaxaWizard metadata entry added.
`devtools::test()` 274/0, `check()` see session report.

**2026-08-02**: Fixed `review_spatial_flags()`'s Reassign-Habitat mode to
preserve a point's existing `spatial_flag` instead of resetting it to
Questionable (user request). Found and fixed a real regression from the
prior day's `data` → `occurrence_data` rename that had broken ALL map marker
rendering (an unrelated `leaflet::addCircleMarkers(data=)` call got swept up
in the same find/replace). Also fixed a stale call in the external
GreatLakes workflow that still used the pre-rename parameter name.
Live-verified via Chrome browser automation against a real running gadget.
Not yet confirmed against the real large-scale GreatLakes dataset — see Open
Questions above.

Full history: `ecosystem_docs/session_notes/TaxaHabitat_sessions.md`
