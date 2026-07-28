# CLAUDE.md — TaxaHabitat
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-28 (Sonnet 5 -- code-review-prep pass against inst/Code and Domain
# Review 2.Rmd's 5-question rubric (tidyverse style / base-R name collisions / DRY-KISS /
# naming clarity / doc accuracy), read-only findings gathered by a review agent first, then
# implemented after user sign-off. One real correctness bug found and fixed: .is_two_level()
# was defined TWICE with DIFFERENT logic -- once in build_habitat_prompt.R (correct, guards
# empty-string l2_name via nzchar/trimws) and once, apparently a stale leftover, in
# parse_habitat_response.R (missing that guard, never actually called from its own file --
# that file already has its own correctly-named .is_two_level_local() for its real bare-
# dataframe path). With no Collate: field, only one definition survives in the namespace,
# so build_habitat_prompt.R's own two call sites (.collapse_to_model_habitats(),
# .build_single_prompt()) were silently running the OTHER file's (wrong) logic --
# invisible to every existing test since no fixture used an empty-string (as opposed to NA)
# l2_name. Fixed by deleting the dead duplicate. Also fixed: two base-R name collisions
# (`det` shadowing base::det() in assign_habitat_biological.R x2, `t` shadowing base::t() in
# a flag_institution_candidates.R mapply closure -- both cosmetic, renamed to
# hab_cols_info/type); three references to functions that don't exist anywhere in the
# package (assign_habitat_to_points(), plot_habitat_points_interactive(),
# select_habitat_outliers() -- referenced in roxygen/@seealso/@examples/a utils_plot.R
# header comment across 4 files, apparently planned-but-never-built or removed without
# cleanup) stripped and replaced with real @seealso pointers to review_spatial_flags();
# stale unused @importFrom declarations trimmed (assign_habitat_biological.R's dplyr
# import cut from 13 unused functions down to the one actually called, n_distinct; its
# rlang import dropped entirely, which also required dropping rlang from DESCRIPTION
# Imports once devtools::check() flagged it as newly-unused; review_spatial_flags.R's
# unused editToolbarOptions import dropped); flag_habitat_inconsistencies.R's Freshwater
# habitats doc section updated to match what .realm()'s regex actually matches (was
# listing only Wetland/Aquatic/Freshwater, code also matches lake/river/stream/pond/
# marsh/bog/fen/riparian); TaxaHabitat-package.R's Spatial quality control section gained
# the two institution-flag functions it was missing. Also extracted two DRY helpers in
# review_spatial_flags.R (a live, untested-by-design Shiny/leaflet gadget wired into 5 real
# production workflows -- extra care taken to keep every call byte-for-byte equivalent,
# not just shorter): .add_draw_toolbar()/.reset_draw_toolbar() collapse 3 duplicated
# leaflet.extras::addDrawToolbar()+removeDrawToolbar() blocks; .add_habitat_marker()
# collapses 3 of the file's 4 duplicated single-point addCircleMarkers() calls (the 4th,
# in the initial render loop, is genuinely different -- multi-row, data=/formula-based --
# and was correctly left alone). Both helpers are closures defined just above `server <-
# function(...)`, matching the file's existing pattern of closing over pal/point_radius/pts
# from the enclosing scope rather than becoming new package-level .noRd helpers requiring
# extra parameter-passing. devtools::document() clean, devtools::test() 158/158 (0
# failures, unchanged -- confirms the .is_two_level() fix didn't change any exercised
# behavior, consistent with no existing fixture distinguishing the two definitions),
# devtools::check() 0 errors/0 warnings/0 notes (was 1 note, the newly-unused rlang import,
# until DESCRIPTION was fixed). Reinstalled to ~/Library/R/4.0/library. review_spatial_flags()
# was NOT live-tested this session (would require an interactive Shiny session) -- the DRY
# refactor there is verified by careful reading and byte-for-byte argument preservation, not
# by running the gadget; flagging this as the one part of this pass worth a live smoke-test
# before the next real workflow run that exercises it.
# Previous update, 2026-07-27 (Sonnet 5 -- geographic-outlier/institution-flag thread CLOSED OUT.
# Final bug was in a workflow script (MuguFishWorkflow.R), not this package -- a stale
# checkpoint .rds predating institution_flag's existence was being silently reloaded over the
# fresh, correct filter_gbif_quality() output; fixed by deleting the one stale file. User
# confirmed after re-running: "institution flag seems to be operating well." Closing
# verification: devtools::test() 158/158 (0 failures, includes flag_institution_candidates()),
# devtools::check() 0 errors/0 warnings/0 notes, no non-ASCII characters in either new source
# file. review_institution_flags() has no test file by design (matches review_spatial_flags()'s
# own precedent -- interactive Shiny/leaflet gadgets aren't unit-tested here). No other
# unresolved issues from this thread. See [[project_geographic_outlier_check]] for the full
# record. Previous update, 2026-07-23, continued yet further (Sonnet 5 -- real bug found on
# review_institution_flags()'s FIRST live use, by the user in the real Mugu workflow:
# occurrence markers all rendered black regardless of keep/remove decision, not matching the
# legend. Root cause confirmed empirically (not guessed): the color vector
# (decision_color[dec[sub_pts$point_id]]) carries names inherited from the indexing
# operation, and leaflet's htmlwidgets JSON layer serializes a NAMED character vector as a
# keyed JS object rather than a per-point array -- duplicate "keep"/"remove" keys silently
# collapse, so the browser-side per-marker color assignment breaks entirely and falls back to
# an undefined/black default. Verified directly by comparing the actual JSON leaflet builds
# for named vs. unnamed color vectors before shipping the fix (unname() around the color
# lookup). Also addressed three real usability points from the same live-test: institution
# markers switched from leaflet's bundled pin icon to a smaller (point_radius * 0.5), distinct
# blue circle marker (was obscuring nearby occurrence points); occurrence markers reduced to
# point_radius * 0.75 (were large enough to visually stack when geographically close); map now
# calls fitBounds() to frame the actual flagged-point extent on open (previously used
# leaflet's arbitrary default view) and raises maxZoom to 20 on both the base map and the tile
# layer (previously uncapped by us but effectively limited by leaflet's own conservative
# default). devtools::test()/check() clean. Reinstalled.
# Previous update, 2026-07-23, continued (Sonnet 5 -- review_institution_flags() added, the
# interactive-gadget half of the institution-review pair deferred earlier the same session.
# Deliberately scoped DOWN from review_spatial_flags() (~950 lines) given the real dataset
# here is small (tens of flagged records, not thousands): single view (no rectangle
# bulk-select), no habitat-reassignment-equivalent action, single-level undo. Shows two point
# layers together -- the flagged occurrence (colored circle, green=keep/red=remove) and its
# own matched institution's location (leaflet's bundled default pin marker, no external icon
# asset needed) -- so a reviewer can see directly whether a record sits AT an institution or
# genuinely nearby it (the "Avila Pier vs. inland SLO campus" ambiguity that motivated this
# whole feature). Every flagged record starts as "keep" -- nothing is ever discarded just by
# opening the gadget or clicking Done without reviewing. shiny::paneViewer(), never
# dialogViewer(), per this ecosystem's own documented leaflet-gadget footgun. No test file
# (matches review_spatial_flags()'s own precedent -- interactive gadgets requiring a live
# session aren't unit-tested in this ecosystem); relied on careful manual code review instead,
# since devtools::test()/check() can't exercise Shiny/leaflet server logic. Real ASCII-policy
# violation caught by devtools::check() itself before shipping (a Unicode arrow + bullet
# characters in gadget HTML strings), fixed with \\u2192/\\u25cf escapes matching this
# ecosystem's own established convention (review_spatial_flags() already uses the same
# escapes for the same reason). filter_gbif_quality() gained two more institution columns
# (institution_lon/institution_lat -- the matched institution's OWN coordinates, needed for
# the two-layer map, not previously stored) as a direct prerequisite. Wired into ALL FIVE real
# production workflow scripts (2 Mugu + 3 PtConception, outside this monorepo) using the
# EXACT convention already established for review_spatial_flags() in these same files (a
# plain inline call within the linear script -- these scripts are run interactively
# section-by-section by the user, not batch-executed -- with a system() sound alert and
# elapsed-time tracking around the gadget call), gated on `any(institution_flag %in% TRUE)`
# so workflows with nothing flagged skip the section entirely rather than erroring.
# devtools::test() 0 failures (TaxaFetch 553, TaxaHabitat 158, both unchanged by this gadget
# addition itself), devtools::check() 0/0/0 both packages. Reinstalled. Not yet run live by
# the user -- these are real Shiny/leaflet gadgets, genuinely exercising them is the user's
# call, not something verifiable from a non-interactive session.
# Previous update, 2026-07-23 (Sonnet 5 -- flag_institution_candidates() added, classification-
# stage half of a new two-stage QAQC pair for TaxaFetch::filter_gbif_quality()'s institution
# proximity flag (that function now flags near-institution records rather than removing them,
# same day, see TaxaFetch/CLAUDE.md -- prompted by a real Mugu false-positive: live fish
# records near a university botanical garden pond, not archived specimens). This function
# tiers those flags "high"/"low"/"ambiguous" by crossing the matched institution's real `type`
# (Herbarium/Botanic_garden/Zoo/Museum/University/Research_centre -- verified via
# CoordinateCleaner::institutions directly, not guessed) against the record's own kingdom --
# a herbarium match matters for a plant, not a fish. Deliberately mirrors
# flag_habitat_inconsistencies()'s existing role (pure classification, no interaction, no rows
# removed) ahead of a still-to-be-built interactive review gadget
# (review_institution_flags(), meant to mirror review_spatial_flags() -- same two-layer-overlay/
# paneViewer/audit-trail pattern, showing the flagged occurrence AND its matched institution's
# own location together). The gadget is the intentionally-deferred half of this feature --
# scoped in detail but not built, given real time constraints raised mid-session; see
# [[project_geographic_outlier_check]] in the memory system for the exact resume point,
# including the full architectural discussion (why TaxaHabitat over TaxaMatch, why flag-then-
# split over remove-then-restore). A real bug was found and fixed before shipping: comparing
# suspicion_rules$institution_type == t when a record's own matched institution has NO recorded
# type (real data -- e.g. some real Scripps Institution of Oceanography matches) produces an
# all-NA logical index, which subsets to NA rather than zero, silently producing
# institution_suspicion = NA instead of the documented "ambiguous" fallback -- caught by the
# console summary message itself printing "NA high, NA low, NA ambiguous" rather than real
# counts. devtools::test() 0 failures (158, up from 142), devtools::check() 0/0/0. Reinstalled
# to ~/Library/R/4.0/library.

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
| `build_habitat_prompt()` | R/build_habitat_prompt.R | Complete | Build habitat assignment prompt object. `geographic_context` param (Session 46) adds geographic hint + `ecoregion_best_guess` column. |
| `parse_hierarchical_habitat_response()` | R/parse_habitat_response.R | Complete | Parse LLM CSV response into habitat weights table. Protects `ecoregion_best_guess` from numeric detection. |
| `assign_habitat_biological()` | R/assign_habitat_biological.R | Complete | Join habitat weights to occurrence data (per-point consensus) |
| `consensus_habitat()` | R/assign_habitat_biological.R | Complete | Assemblage-level consensus habitat from per-species weights; modal ecoregion extraction. Returns one-row data frame. (Session 46) |
| `flag_habitat_inconsistencies()` | R/flag_habitat_inconsistencies.R | Complete | Flag occurrences inconsistent with habitat |
| `review_spatial_flags()` | R/review_spatial_flags.R | Complete | Interactive Shiny review of spatial flags |
| `flag_institution_candidates()` | R/flag_institution_candidates.R | Complete (2026-07-23) | Classification stage for `TaxaFetch::filter_gbif_quality()`'s `institution_flag` column -- tiers "high"/"low"/"ambiguous" by crossing matched institution `type` against record `kingdom`. Pure function, no interaction, no removal (mirrors `flag_habitat_inconsistencies()`). |
| `review_institution_flags()` | R/review_institution_flags.R | Complete (2026-07-23) | Interactive Shiny/leaflet review of `flag_institution_candidates()`'s tiers -- click a flagged record to toggle Keep/Remove, matched institution shown as a second map layer. Deliberately scoped down from `review_spatial_flags()` (single view, no bulk-select, single-level undo) given real datasets here are small. Every record starts "keep." Wired into all 5 real production workflow scripts (2 Mugu + 3 PtConception). |
| (plot helpers) | R/utils_plot.R | Complete | Internal plotting utilities |
| `.detect_habitat_cols()` | R/assign_habitat_biological.R | Internal | Shared habitat column detection logic used by `assign_habitat_biological()` and `consensus_habitat()` |

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
- The median-across-references approach for likelihood is intentional in TaxaMatch
  (not relevant here, but habitat weights follow a similar philosophy).
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

---

## Session 28 Notes (2026-03-26)
- Package created during TaxaFetch → TaxaTools/TaxaHabitat split
- All habitat files copied from TaxaFetch/R:
  - build_habitat_prompt.R, assign_habitat_biological.R,
    flag_habitat_inconsistencies.R, review_spatial_flags.R, utils_plot.R
- screen_spatial_formula.R moved to TaxaExpect (Session 29, 2026-03-27) --
  belongs with biodiversity modelling, not habitat assignment
- parse_habitat_response.R: habitat parser extracted from TaxaFetch/R/llm_api_utils.R
- LLM provider functions moved to TaxaTools/R/llm_api_utils.R
- TODO: ~~Run devtools::document() and devtools::check() on this package~~ — completed Session 46
- TODO: ~~Update @importFrom tags in habitat files to use TaxaTools:: for LLM functions~~ — completed Session 46

**Session 37 (2026-03-30)**
- `Main_Habitat` column → `main_habitat` (snake_case consistency; 145 occurrences across 20 files).
- `ctx$habitat` → `ctx$main_habitat` recognised context field in TaxaAssign.

**Session 46 (2026-04-03)**
- `geographic_context` param added to `build_habitat_prompt()`: optional geographic hint;
  adds `GEOGRAPHIC CONTEXT:` block to prompt and requests `ecoregion_best_guess` column.
- `consensus_habitat()` added to `R/assign_habitat_biological.R`: assemblage-level consensus
  from per-species weights; modal ecoregion extraction. `.detect_habitat_cols()` internal
  shared with `assign_habitat_biological()`.
- `ecoregion_best_guess` protected from numeric detection in `parse_hierarchical_habitat_response()`.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 57 (2026-04-15)**
- Duplicate `%||%` definition removed from `R/parse_habitat_response.R`; now imported from
  TaxaTools via `@importFrom TaxaTools %||%`.
- Empty `utils::globalVariables(character(0))` removed.

**Session 59 (2026-04-17)**
- `test-assign_habitat_biological.R` added (new test file, expanded coverage).
- Vignette added. `knitr` + `rmarkdown` added to Suggests; `VignetteBuilder: knitr` in DESCRIPTION.
- `.Rbuildignore` updated (`.Rhistory`, `.DS_Store`).
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 65 (2026-05-02)**
- `report_habitat()` added: generates `report_section` summarizing habitat assignment
  (scheme, n_taxa, dominant habitat). For `TaxaTools::assemble_report()`.

**Session 66 (2026-05-03)**
- Dead code cleanup; stale `@seealso` refs updated.

**Session 67 (2026-05-04)**
- `llm_fn` default in `build_habitat_prompt()` updated to
  `getOption("TaxaID.llm_fn", call_anthropic_api)`.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` ecosystem rename: TaxaHabitat does not use this column;
  no source changes required.

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 81 (2026-05-21)**
- Methods sections added to README: habitat weights, site assignment, spatial QAQC.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- `llm_fn` defaults updated across all LLM-calling functions to
  `getOption("TaxaID.llm_fn", call_anthropic_api)`.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaHabitat-specific code changes. Session 85: README expanded with spatial QAQC
  paragraph (user edit committed). Ecosystem: `call_api()` dispatcher (TaxaTools), WERC
  review integration.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/assign_habitat_workflow.R` added — teaching-oriented, fully namespaced,
  continues directly from TaxaFetch's tutorial checkpoint. Two classification steps on the
  SAME mechanism: Step A (always runs) standard habitat classification via
  `build_habitat_prompt()` → `TaxaTools::prompt_api()` → `parse_hierarchical_habitat_response()`
  → `assign_habitat_biological()`; Step B (optional, `NEEDS_SAMPLING_GROUP` toggle) reuses the
  identical chain with a sampling-group scheme instead of a habitat scheme — confirmed to need
  **zero package changes** (weight-matrix math is scheme-agnostic; `realm = NA` is a valid
  scheme value; see `ecosystem_docs/LAYER1_WORKFLOWS.md` for the full generalization
  investigation). Spatial QAQC tail (`flag_habitat_inconsistencies()`) preserved;
  `review_spatial_flags()` documented as interactive-only, not run via `source()`.
- Live-tested with a real Anthropic LLM call and real GEBCO bathymetry download. One real bug
  fixed: Step B's `assign_habitat_biological()` call would have silently overwritten Step A's
  `main_habitat` column if run on the same object (the function unconditionally drops
  pre-existing `main_habitat`/`habitat_best_guess` from its `data` argument) — fixed by running
  Step B against the original `all_occurrences` independently and joining only its renamed
  output columns back on. Full record in `ecosystem_docs/LAYER1_WORKFLOWS.md`.
