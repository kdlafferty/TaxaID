# CLAUDE.md — TaxaHabitat
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

## Known Footguns

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
