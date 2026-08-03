# CLAUDE.md — TaxaHabitat
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-08-02 (Sonnet 5 -- SEVENTH round of the review_spatial_flags()
# "can't Flag points with several Questionable points on the map" debugging thread (see
# [[project_review_spatial_flags_habitat_reassign_gap]] in the memory system for rounds
# 1-6). Two changes, both live-verified via real Chrome browser automation against a
# running gadget, not just devtools::test()/check():
# (1) Design change, at the user's request: reassigning a point's habitat via Reassign
# Habitat mode no longer forces spatial_flag to "questionable" when starting from
# Likely/Unlikely -- it now keeps the point's existing flag (confirm_habitat's handler,
# ~line 1026: `new_flag <- if (identical(old_flag, "questionable")) "likely" else
# old_flag`, was `else "questionable"`). Reassigning FROM Questionable is unchanged
# (still promotes to Likely). Halves reviewer workload for the common case and stops one
# path that inflates the Questionable view -- the view where bulk Flag-mode has
# repeatedly proven fragile across this thread's earlier rounds. roxygen `@section Click
# behaviour` updated to match.
# (2) Real, independent regression fixed, found on the user's very first live re-test of
# (1): `Error in leaflet::addCircleMarkers: unused argument (occurrence_data = hab_sub)`.
# Root cause: the 2026-08-01 session's `data` -> `occurrence_data` parameter rename
# (below) swept up an unrelated call into `leaflet::addCircleMarkers()` inside
# `output$map`'s `renderLeaflet()` (~line 647) -- that function's own `data` parameter
# belongs to the `leaflet` package, not TaxaHabitat, and was never supposed to be
# touched. This broke marker rendering in EVERY view, a far more severe regression than
# anything in the prior 6 rounds -- likely the true explanation for why the "several
# Questionable points" symptom looked newly worse (the map wasn't drawing anything at
# all, not just fragile at scale). Checked the other 4 functions touched by the same
# 2026-08-01 rename (`assign_habitat_biological()`, `flag_habitat_inconsistencies()`,
# `flag_institution_candidates()`, `review_institution_flags()`) for the identical
# mistake -- none found, an isolated one-line miss. Fixed: `occurrence_data = hab_sub`
# -> `data = hab_sub` at that one call site.
# A THIRD, separate issue surfaced immediately after, in the user's own external
# `GreatLakes2023_ConsensusWorkflow.R` (not under git, not a package bug): its
# `assign_habitat_biological(data = all_occurrences, ...)` call still used the OLD
# parameter name from before the 2026-08-01 rename -- a real call site the original
# rename's ecosystem-wide sweep missed. Fixed in the workflow file itself (`data =` ->
# `occurrence_data =`); the file's other 4 calls to renamed functions
# (`flag_institution_candidates()`, `review_institution_flags()`,
# `flag_habitat_inconsistencies()`, `review_spatial_flags()`) are all positional and
# were never at risk.
# Live verification (real 12-point synthetic dataset, `browserViewer()`, driven via
# Chrome automation against the gadget's own httpuv server -- not RStudio's Viewer
# pane): confirmed the map renders real markers with no error; reassigning a Likely
# point's habitat recolors it in place and correctly stays in the Likely view (override
# count Likely:3 unchanged) instead of disappearing into Questionable; Flag mode still
# promotes Likely -> Questionable normally afterward. `devtools::test()` 220/220
# unchanged, `devtools::check()` 0/0/0, reinstalled and confirmed at
# `~/Library/R/4.0/library` via `dirname(find.package("TaxaHabitat"))`; the shipped
# `new_flag <- ... else old_flag` logic directly confirmed present in the installed
# function body via `deparse(body(review_spatial_flags))` before live-testing.
# **Not yet confirmed against the user's real, large-scale GreatLakes dataset** -- this
# session's live test used a small synthetic fixture, the same class of gap that caused
# false "resolved" conclusions in earlier rounds of this thread. The addCircleMarkers
# fix should be unconditional (fixes a hard R error, not a scale-dependent behavior),
# but the ORIGINAL "many Questionable points, Flag-mode does nothing" bug from round 6
# is still not definitively closed -- only inferred less likely now that its probable
# proximate trigger (a completely broken map render) has been removed. The round-6
# debug `message()` logging in `map_draw_new_feature` is still installed and should be
# watched in the R console if the symptom recurs on the real dataset.
# Previous update, 2026-08-01 (Sonnet 5 -- full code + domain review response against
# inst/taxahabitat_review.Rmd (a human-authored review, not the AI-run
# "Code and Domain Review 2.Rmd" template other packages use). Full record in the new
# inst/taxahabitat_review_response.md, modeled on TaxaTools's response-doc format. One
# real, confirmed "true bug" (the reviewer's own words) fixed at the root cause: an
# unquoted comma inside an LLM-written habitat_best_guess value corrupted the whole row
# via utils::read.csv()'s row-name-inference rule (mismatched header/data field count ->
# taxon_name silently becomes an invisible row name, every later column shifts left) --
# fixed both preventively (build_habitat_prompt() now instructs the LLM to quote any
# comma-containing free-text field) and correctively (new quote-aware
# .repair_unquoted_commas() in parse_habitat_response.R merges/re-quotes an overflowing
# row before read.csv() ever sees it, so already-malformed responses parse correctly
# too). New tests/testthat/test-parse_habitat_response.R (33 tests) directly reproduces
# the exact reported scenario -- this file had ZERO test coverage before this session,
# despite being where the bug lived.
#
# A Domain Review finding turned out to be much bigger than the reviewer's own two
# flagged codes (1.3/3.3 mislabeled "Subalpine"): fetched the real IUCN Habitats
# Classification Scheme v3.1 source document directly (not from memory) and audited all
# 104 rows of .iucn_habitat_lookup against it. Confirmed and fixed: Shrubland's whole
# 3.1-3.3 ORDER was wrong (real order Subarctic/Subantarctic/Boreal, not Forest's
# Boreal/Subarctic/Subantarctic); Grassland 4.3 wrong; Marine Neritic (9.x) almost
# entirely scrambled with 3 outright fabricated entries ("Subtidal Cave and Overhangs",
# "Pelagic (Supercolumnar)", "Seamounts and Knolls" at the wrong L1 group entirely --
# Seamount is real code 11.5, under Marine Deep Ocean Floor); Marine Deep Ocean Floor
# missing "Seamount" entirely plus a wrong Hadal-zone depth threshold (>4000m vs real
# >6000m); Marine Intertidal 12.4 had a fabricated "Salt Flats" concept; Marine Coastal's
# own L1 NAME was wrong ("Supralittoral" vs real "Supratidal"); Wetlands (Inland) had a
# fabricated 19th entry and a fabricated 5.18; Artificial - Aquatic had 3 fabricated
# entries (15.10-15.12) and was missing the real 15.13; Rocky Areas (inland) and
# Introduced Vegetation are both L1-ONLY in the real scheme (no numbered L2 subcategories
# exist at all -- the real doc lists examples only as prose) but had 2 fabricated L2 rows
# each; Other/Unknown had fabricated pseudo-L2 codes ("17.0"/"18.0") the real scheme
# doesn't have. Rebuilt the whole table row-by-row against the verified source, with the
# four genuinely-L1-only groups now correctly represented as l2_code=l2_name=NA (matching
# how the rest of the package already represents L1-only rows) rather than a fabricated
# pseudo-L2. That restructuring surfaced one more real bug: build_iucn_scheme()'s
# all_l2_in_scope lookup would have let l2="all" silently pull in duplicate L1-only rows
# for those four groups via NA-matches-NA through %in%/match() -- fixed by excluding NA
# from that specific lookup.
#
# Two more real, live-reproduced bugs found and fixed while investigating adjacent
# review comments: (1) .is_iucn_scheme()'s identical(scheme, .iucn_habitat_lookup) check
# the reviewer flagged as "redundant after the OR" was actually WORSE than redundant --
# EVERY real scheme reaching this function has already passed .validate_habitat_scheme(),
# which strips l1_code and adds realm, so NEITHER of the function's two disjuncts could
# ever be true for a real scheme; flag_habitat_inconsistencies()'s own .realm() IUCN
# fallback branch was therefore silently unreachable for any real IUCN-derived scheme.
# Fixed by keeping only the actually-functional l2_code-pattern check. (2) A mixed-scale
# scheme (e.g. build_iucn_scheme(realm="terrestrial", l2="Temperate"), which legitimately
# returns both L1 fallback rows and L2 rows together) printed literal "NA" as the habitat
# name for every L1-only row in the LLM-facing prompt text ("NA  [Forest]", "NA
# [Savanna]", etc.) -- live-reproduced before fixing, fixed exactly per the reviewer's own
# suggested ifelse(is.na(l2_name), l1_name, l2_name) pattern. Related: build_iucn_scheme()
# also had a real realm=NA bug (realm="terrestrial" calls returned realm=NA on every row,
# since the internal .l1_to_realm() helper it delegated to only ever recognised
# marine/freshwater L1 groups) -- fixed by using the caller's own already-known realm
# directly when supplied, and separately expanded .l1_to_realm() itself to also recognise
# terrestrial groups (Artificial - Aquatic/Other/Unknown deliberately still NA -- genuinely
# ambiguous or answerless from the L1 name alone).
#
# `data` renamed to `occurrence_data` across 5 functions (assign_habitat_biological(),
# flag_habitat_inconsistencies(), flag_institution_candidates(), review_institution_flags(),
# review_spatial_flags()) -- same fix TaxaTools already made for its own `df` parameter.
# Every real named (`data = `) call site across the WHOLE monorepo updated, including
# TaxaExpect::build_priors() (real package code, not a workflow script -- required a
# TaxaExpect reinstall too) and TaxaWizard/inst/metadata/TaxaHabitat.json's two `"name":
# "data"` entries (TaxaWizard's own CLAUDE.md states metadata param names must exactly
# match real signatures). See TaxaID/CLAUDE.md's Recent Breaking Changes table.
#
# Investigated and confirmed NOT bugs, documented with evidence rather than guessed:
# adehabitatMA's S3-overwrite warning traced to marmap's own Suggests (confirmed via
# packageDescription("marmap")) -- not a direct or hidden dependency of this package;
# flag_institution_candidates()'s "Research_centre" confirmed as CoordinateCleaner's own
# literal external vocabulary value (verified live: sort(unique(institutions$type))), not
# a spelling choice this package made -- renaming it would break the real join;
# TaxaFetch::filter_gbif_quality()'s interface confirmed CURRENT against its real source
# (institution_flag/institution_type/institution_lon/institution_lat all present exactly
# as flag_institution_candidates()/review_institution_flags() expect) -- the review was
# likely written against an earlier snapshot. review_spatial_flags()'s "bulk flag drawing
# doesn't seem to be working" complaint was re-investigated fresh (this is the SAME
# symptom class 6 rounds of a prior session already chased, see the
# project_review_spatial_flags_habitat_reassign_gap memory) -- careful re-reading of the
# rectangle-select code path found no new, independently reproducible bug; the debug
# message() calls that prior session left in place as a safety net remain untouched. One
# investigated lead (an apparent toolbar-reset asymmetry between Flag and Reassign-Habitat
# modes) turned out to be correct-as-is on closer reading, not a bug.
#
# Also fixed: .collapse_to_model_habitats() deleted entirely (~220 lines) -- confirmed
# dead code left over from the assign_habitat_llm() pipeline removed 2026-02-27, long
# before this package existed in its current form; zzz_imports.R's unused
# call_anthropic_api import removed (never called as a bare symbol anywhere in this
# package); DESCRIPTION gained Depends: R (>= 4.1.0) (matching TaxaTools/TaxaLikely's own
# pattern, previously only an auto-detected R CMD build warning) and rnaturalearthdata in
# Suggests (already required at runtime, never declared); flag_habitat_inconsistencies()'s
# missing-package error message now gives rnaturalearthhires its own correct
# non-CRAN install line instead of a misleading blanket install.packages() call; hist ->
# flag_hist renamed in review_spatial_flags.R (shadowed stats::hist(), same class of fix
# as the 2026-07-28 session's det/t renames). devtools::test() 220/220 (up from 158,
# real new coverage not inflation -- parse_habitat_response.R had ZERO tests before this
# session), devtools::check() 0/0/0. Reinstalled via ecosystem_docs/install_all.R
# (TaxaHabitat + TaxaExpect + TaxaWizard, since real code/metadata changed in all three).
# See inst/taxahabitat_review_response.md for the complete per-comment record, including
# several comments investigated and explicitly rejected with reasoning (British spelling
# in non-user-facing prose left alone; several architecture-simplification suggestions
# noted but not actioned as out of scope for this pass).
# Previous update, 2026-07-28 (Sonnet 5 -- code-review-prep pass against inst/Code and Domain
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
