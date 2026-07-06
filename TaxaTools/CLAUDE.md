# CLAUDE.md — TaxaTools
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-05 (Session 137 — escalate_taxonomic_rank() added: the escalation-
# ladder function (genus -> family -> order broadening for singleton observations with no
# reference/occurrence data at their own rank), Phase 1 of the observation-pipeline-wiring
# reentry plan. Reuses verify_taxon_names()/parse_classification_path(); same primary/
# fallback-backbone pattern as fill_higher_ranks(). Live-verified against real NCBI data for
# the PtConception 12S cases and the bobcat-photo case. See Session 137 note below.
# Session 134b — define_search_polygon() moved here from TaxaFetch:
# the shared interactive polygon gadget for both TaxaFetch's search-area use and TaxaMatch's
# spatial-group use (group_observations_by_bbox()). Added group_col (color the points overlay
# by an existing group column), init_polygon (reopen a previously drawn polygon for
# reshaping), and viewer (default shiny::paneViewer(minHeight = 500) -- RStudio's
# dialogViewer() was found, via real live-testing, to silently break this gadget's Done
# button; paneViewer() confirmed working and matches this ecosystem's other mapping
# gadgets) params. shiny/miniUI/leaflet added to Suggests. See Session 134b note below.
# Session 122 — is_valid_species_name() → is_plausible_binomial() rename; call_api()
# data-sensitivity @details added; startup message data-transmission NOTE added; README.md
# Code Style + lintr-sweep reminder added; man/figures/README-pressure-1.png debris deleted)

---

## Package Purpose
Shared helper functions for working with taxonomic name lists AND LLM API providers.
Dependency of all other TaxaID packages. Can also be used standalone for cleaning and
standardizing taxon name lists, resolving synonyms, and querying taxonomic hierarchies.

---

## Function Inventory

### Taxonomy functions

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `verify_taxon_names()` | Verify names against a taxonomic backbone via Global Names Verifier API; batched; returns `user_supplied_name`, `matched_name`, `classification_path`, `classification_ranks`, `score`, `verified`. `matched_name` contains genus + epithet only — authority strings stripped at parse time. | Complete | R/verify_taxon_names.R |
| `create_taxon_names()` | Add `taxon_name` and `taxon_name_rank` columns from separate rank columns; case-insensitive column matching; most-specific non-NA rank wins | Complete | R/create_taxon_names.R |
| `clean_taxon_names()` | Normalise, deduplicate, and filter a character vector of taxon names; removes NA, non-capital-initial, abbreviations, bracket artefacts; converts underscore-encoded binomials (`Genus_epithet`) to space-separated (Jonah Ventures / SILVA pipelines) | Complete | R/clean_taxon_names.R |
| `change_backbone()` | Post-process `verify_taxon_names()` output; rename source/translated name columns; parse pipe-delimited classification into wide rank columns | Complete | R/change_backbone.R |
| `rename_cols()` | Rename data frame columns using an explicit `col_map` or built-in case-insensitive regex patterns for common DarwinCore alternatives; `strict` arg controls missing-key behaviour | Complete | R/rename_cols.R |
| `find_taxonomy_conflicts()` | Detect higher-rank inconsistencies in taxonomy data frames; returns `taxon_name`, `taxon_rank`, `parent_rank`, `parent_values`, `n_values` | Complete | R/find_taxonomy_conflicts.R |
| `is_plausible_binomial()` | Filter out "sp.", "cf.", "aff.", uncultured, environmental, and non-binomial names; vectorised logical return | Complete | R/is_valid_species_name.R |
| `to_faire()` | Export a TaxaID data frame (match/likelihood/posterior object) to FAIRe checklist column conventions (`taxaRaw` / `taxaFinal`). Renames `observation_id` → `seq_id`, `taxon_name` → `scientificName`, etc.; constructs `verbatimIdentification`, `specificEpithet`, `checkls_ver`. Columns not in the FAIRe mapping are retained unchanged. Attaches `faire_table` attribute. | Complete | R/to_faire.R |
| `format_dwc()` | Apply per-column DarwinCore formatting rules | Planned | — |
| `validate_dwc()` | Read-only QC after formatting | Planned | — |
| `dwc_map()` | Compare input column names against full DarwinCore term list; propose `col_map` via fuzzy matching or LLM API | Planned | — |

### Rank and barcode utilities (Sessions 56-57)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `standard_ranks` | Character vector: `c("kingdom","phylum","class","order","family","genus","species")` | Complete | R/rank_utils.R |
| `extended_ranks` | Character vector: standard + subspecies, variety, form | Complete | R/rank_utils.R |
| `detect_ranks()` | Auto-detect which rank columns exist in a data frame; returns coarse-to-fine character vector | Complete | R/rank_utils.R |
| `barcode_length_defaults` | Named list of 12 barcode markers → `list(min, max)` bp ranges. MiFish range: `c(130L, 210L)` (tightened Session 116 from c(100L,600L); excludes bacterial cross-amplification at ~256bp). | Complete | R/barcode_utils.R |
| `resolve_barcode_lengths()` | Resolve min/max bp from `barcode_term` vector; takes union across multiple terms; user overrides | Complete | R/barcode_utils.R |

### LLM provider functions (moved from TaxaFetch, Session 28)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `call_anthropic_api()` | Submit one prompt string to Anthropic Claude | Complete | R/llm_api_utils.R |
| `call_gemini_api()` | Submit one prompt string to Google Gemini (free tier available) | Complete | R/llm_api_utils.R |
| `call_openai_api()` | Submit one prompt string to OpenAI ChatGPT | Complete | R/llm_api_utils.R |
| `call_ollama_api()` | Submit one prompt string to a local Ollama model (no API key) | Complete | R/llm_api_utils.R |
| `prompt_api()` | Multi-chunk llm_prompt dispatcher; default `llm_fn` from `getOption("TaxaID.llm_fn")` | Complete | R/llm_api_utils.R |
| `prompt_manual()` | Write prompt files for manual web interface submission | Complete | R/llm_api_utils.R |
| `read_llm_response()` | Read and concatenate saved LLM response files | Complete | R/llm_api_utils.R |
| `%||%` | Null-coalescing operator; exported for use by downstream packages via `@importFrom` | Complete | R/llm_api_utils.R |

### LLM provider auto-detection (Session 82)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `.onAttach()` | On `library(TaxaTools)`: scans `~/.Renviron` for API keys, sets `options(TaxaID.llm_fn)` to the detected provider function. Priority: Anthropic > Gemini > OpenAI. Skips in non-interactive sessions; respects pre-set option. | Complete | R/zzz.R |
| `.detect_llm_provider()` | Internal: returns list of available providers (key present in env vars) | Complete | R/zzz.R |

**Behaviour:**
- **0 keys found:** startup message with setup instructions (including Ollama as local option)
- **1 key found:** auto-sets `options(TaxaID.llm_fn = <provider>)`, prints provider name
- **2+ keys found:** auto-selects first by priority, prints all available + how to switch
- All `llm_fn` defaults across the ecosystem use `getOption("TaxaID.llm_fn", <fallback>)`

### GBIF backbone census (Session 77)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `census_genus_species()` | Enumerate described species per genus (or higher rank) via GBIF backbone `name_usage(children)`. `match_species` param computes reference completeness: "complete" / "singleton_missing" / "incomplete". Higher-rank recursion (family → genera → species). `rgbif` in Suggests. | Complete | R/census_genus_species.R |

### Interactive spatial gadget (Session 134b, moved from TaxaFetch)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `define_search_polygon()` | Interactive Shiny gadget: user drags corner markers on a leaflet map to define a custom polygon. Add Point inserts a vertex at the midpoint of the longest side; Remove Last Point undoes the last add (initial corners protected); Done returns a WKT POLYGON string. Requires `shiny`, `miniUI`, `leaflet` (checked at runtime). Must be run in an interactive R session. Shared by two callers: `TaxaFetch`'s search-area use (`fetch_gbif_occurrences()`/`download_gbif_occurrences()` geometry) and `TaxaMatch::group_observations_by_bbox()`'s spatial-group use -- the only generalization either needed was the `points`/`group_col`/`init_polygon` params below. `points` (data frame with `lat`/`lng`) overlays reference markers. `group_col` (Session 134b): optional column in `points` used to color the overlay by an existing group (e.g. `spatial_group_id`), with a legend -- lets a user drawing a broader search area see which points already belong to which group. `init_polygon` (Session 134b): reopen a previously returned WKT polygon for reshaping instead of starting from a fresh square -- used by `group_observations_by_bbox()`'s end-of-loop edit step. `viewer` (Session 134b): defaults to `shiny::paneViewer(minHeight = 500)` -- **not** `shiny::dialogViewer()`, which was found via real live-testing to silently swallow the Done button's return value whenever this gadget's leaflet map is present (confirmed reproducible; see Session 134b note below for the full debugging record). `paneViewer()` matches the call style already used by `TaxaHabitat::review_spatial_flags()` and `TaxaExpect::plot_theta_map_interactive()`, so all of this ecosystem's mapping gadgets now behave consistently. `browserViewer()` also confirmed working, for callers who want a separate browser tab instead. Internal helpers `.pts_to_wkt()`/`.wkt_to_pts()` are pure and unit-tested without a live gadget session. | Complete | R/define_search_polygon.R |

### Common name utilities (Session 97)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `common_to_scientific()` | Convert a character vector of common names to scientific names via LLM, with optional backbone verification via `verify_taxon_names()`. Params: `taxonomic_group`, `location`, `verify`, `backbone_id`, `llm_fn`. Returns data frame with `common_name`, `scientific_name`, `verified`, `matched_name`. | Complete | R/common_names.R |
| `fill_higher_ranks()` | Given a character vector of taxon names (typically species binomials), extract `genus` and look up `family` via a priority chain: (1) local data frames (`local_sources`), (2) primary backbone via `verify_taxon_names()` at genus level (`backbone_id = 4L`), (3) fallback backbone (`fallback_backbone_id = 11L`). Returns tibble with `taxon_name`, `genus`, `family`; warns for unresolved taxa. Internal helpers: `.build_genus_family_lookup()`, `.lookup_family_from_backbone()`, `.extract_classified_rank()`. | Complete | R/fill_higher_ranks.R |
| `escalate_taxonomic_rank()` | The escalation-ladder function (Session 137 reentry plan, Phase 1): given `taxon_name` at `current_rank`, resolves its full classification via `verify_taxon_names()` and returns the name at the next coarser rank in `rank_system` (default `standard_ranks`) -- e.g. broadening a genus with no reference sequences/occurrence records to its family. Walks up to `max_levels` (default `2L`) rank levels within one call if an intermediate rank is itself absent from the classification path (e.g. genus straight to order when family is missing), so callers get one escalation step per retry-loop iteration rather than a fixed single-rank hop. Same primary/fallback backbone pattern as `fill_higher_ranks()` (`backbone_id = 4L` NCBI, `fallback_backbone_id = 11L` GBIF). Returns `list(taxon_name, rank)`, both `NA` if already at the coarsest rank or nothing resolves within `max_levels`. Only walks the hierarchy -- has no notion of whether a fetch at any rank returned data; that's the caller's retry loop. Live-verified against real NCBI data for the PtConception 12S validation cases (*Rhacochilus*, *Embiotoca caryi* -> family `Embiotocidae`) and the bobcat-photo case (*Lynx* -> family `Felidae`). | Complete | R/escalate_taxonomic_rank.R |
| `parse_classification_path()` | Extract one rank value from the pipe-delimited `classification_path` and `classification_ranks` columns returned by `verify_taxon_names()`. Params: `path`, `ranks`, `target_rank`. Returns `NA_character_` if rank absent. Thin wrapper around `.extract_classified_rank()`; use with `mapply()` for column-level parsing. | Complete | R/fill_higher_ranks.R |
| `scientific_to_common()` | Convert scientific names to English common names. Backbone sources: GBIF (backbone_id=11, via rgbif) or ITIS (backbone_id=3, via taxize). LLM fallback when backbone returns nothing or backbone_id=NULL. `location` param biases LLM toward regionally appropriate names. Batches LLM calls (20/batch). Returns `scientific_name`, `common_name`, `common_name_alternatives` (semicolon-delimited), `source` ("gbif"/"itis"/"llm"/"none"), `backbone_id`. | Complete | R/common_names.R |

### LLM text generation functions (Session 55)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `token_usage()` | Return accumulated LLM token records as data frame. `by` param: "call" (per-call detail), "function" (totals per caller), "provider", "session" (grand total). Optional `cost_per_1k_input`/`cost_per_1k_output` adds `cost_usd` column. Auto-populated by `call_api()` — no changes needed in downstream packages. | Complete | R/token_usage.R |
| `reset_token_usage()` | Clear the session token ledger. Call before a workflow step for per-step accounting. | Complete | R/token_usage.R |
| `build_report_context()` | Domain-agnostic S3 context object with verified facts for grounding LLM output | Complete | R/draft_text.R |
| `draft_methods_text()` | Read R code and draft Methods section via LLM; context-aware; audience param | Complete | R/draft_text.R |
| `draft_results_text()` | Read R objects and draft Results section via LLM; context-aware; audience param | Complete | R/draft_text.R |

---

## Typical Workflow

```r
rename_cols()           # align column names to DarwinCore
  → create_taxon_names()   # derive best taxon name per row
  → clean_taxon_names()    # deduplicate & clean for API
  → verify_taxon_names()   # check against backbone via API
  → change_backbone()      # reshape into wide taxonomy table
```

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-verify_taxon_names.R | `verify_taxon_names()` | Offline validation + online API tests (skipped offline) |
| test-create_taxon_names.R | `create_taxon_names()` | Fully offline |
| test-clean_taxon_names.R | `clean_taxon_names()` | Fully offline |
| test-change_backbone.R | `change_backbone()` | Fully offline; uses mock verified tibbles |
| test-rename_cols.R | `rename_cols()` | Fully offline |
| test-to_faire.R | `to_faire()` | Fully offline; 52 tests covering renames, constructed columns, attribute, missing-column handling, validation |
| test-common-names.R | `common_to_scientific()`, `scientific_to_common()` | Offline; backbone calls mocked via `local_mocked_bindings()`; location param verified via prompt capture; 52 tests |
| test-fill_higher_ranks.R | `fill_higher_ranks()`, `.build_genus_family_lookup()`, `.lookup_family_from_backbone()`, `.extract_classified_rank()` | Fully offline (API mocked); 35 tests |
| test-escalate_taxonomic_rank.R | `escalate_taxonomic_rank()` | Fully offline (API mocked); 35 tests; covers immediate-parent escalation, skip-level escalation within `max_levels`, already-coarsest short-circuit, primary/fallback backbone, custom `rank_system` |
| test-token_usage.R | `token_usage()`, `reset_token_usage()` | Fully offline; mocks `.token_ledger` directly |
| test-rank_utils.R | `standard_ranks`, `extended_ranks`, `detect_ranks()` | Fully offline |
| test-barcode_utils.R | `barcode_length_defaults`, `resolve_barcode_lengths()` | Fully offline |
| test-null_coalesce.R | `%\|\|%` | Fully offline |
| test-call_api.R | `call_api()` | 21 tests; fully offline; covers input validation, `max_input_tokens` pre-flight guard, no-provider error, mocked anthropic/gemini/openai_compat response parsers, token attribute, `show_tokens` |
| test-find_taxonomy_conflicts.R | `find_taxonomy_conflicts()` | 13 tests; fully offline; covers clean data, known genus-family conflict, explicit and auto-detected rank_system, NA row skipping, multi-level conflict, output column types |
| test-is_plausible_binomial.R | `is_plausible_binomial()` | 14 tests; fully offline; covers well-formed binomials, lowercase genus, genus-only, sp./cf./aff. suffixes, uncultured/environmental/metagenome names, vectorisation, NA |
| test-llm_utils.R | `call_anthropic_api()` and other provider functions | Online tests skipped; pre-existing WARN in check |
| test-census_genus_species.R | `census_genus_species()` | Online (GBIF) tests skipped offline |
| test-draft_text.R | `build_report_context()`, `draft_methods_text()`, `draft_results_text()` | LLM calls skipped offline |
| test-model_registry.R | Model registry internals | Fully offline |
| test-report_section.R | Report section helpers | Fully offline |
| test-define_search_polygon.R | `.pts_to_wkt()`, `.wkt_to_pts()` | 8 tests; fully offline; the gadget itself requires a live interactive session and is not covered |

**Testing rules:** All tests use small inline data. No external files. No API calls except
the online group in test-verify_taxon_names.R (guarded by `skip_if_offline()`).

---

## Key Dependencies

| Package | Used for |
|---|---|
| httr | Global Names Verifier API requests |
| httr2 | LLM provider API calls (Anthropic, Gemini, OpenAI, Ollama) |
| jsonlite | JSON encoding for API body |
| dplyr | Tibble construction, data manipulation |
| tidyr | `unnest_wider()` in `change_backbone()` |
| purrr | `map2()` in `change_backbone()` |
| stringr | String cleaning in `clean_taxon_names()` |
| rlang | NSE (`:=`, `sym()`) in `change_backbone()` |
| stats | `setNames()` in `change_backbone()` |
| shiny (Suggests) | `define_search_polygon()` interactive gadget (Session 134b, moved from TaxaFetch) |
| miniUI (Suggests) | `define_search_polygon()` gadget UI (Session 134b) |
| leaflet (Suggests) | `define_search_polygon()` map rendering (Session 134b) |

---

## Design Notes
- All functions are general-purpose — no assumptions about TaxaMatch/TaxaExpect input formats
- Argument names must be consistent and intuitive (these are the most-called internal functions)
- `verify_taxon_names()` is slow for large lists — always run on a deduplicated vector, save result, load in downstream scripts
- `clean_taxon_names()` strips brackets BEFORE the capital-letter filter (bug fix Session 27)


## Renaming Log

| Old Name | New Name | Date | Notes |
|---|---|---|---|
| `f_spellcheck_sci_names` | `verify_sci_names` | 2026-02-18 | — |
| `verify_sci_names` | `verify_taxon_names` | 2026-03-26 | Consistency with package naming |
| `create_taxon_name` | `create_taxon_names` | 2026-03-26 | Plural for consistency |

---

## Session Notes

**Session 137 (2026-07-05): escalate_taxonomic_rank() -- escalation ladder, Phase 1 of the observation-pipeline-wiring reentry plan**

Branch `single-observation-pipeline`. Per `ecosystem_docs/REENTRY_PROMPT_session137_observation_pipeline_wiring.md`, the escalation ladder (broaden genus -> family -> order when a singleton's own genus has no reference data or occurrence records) had been validated by hand three separate times (Sessions 134, 134b, 134c) but never built as a real function -- the actual bottleneck blocking the single-observation and spatially-independent multi-observation cases, not the spatial-grouping mechanism itself (that part was already done). Package placement (TaxaTools vs. TaxaLikely vs. TaxaExpect) confirmed with the user before starting: TaxaTools, matching the precedent of `%||%` and `define_search_polygon()` -- generic taxonomic-hierarchy-walking logic, not fetch-API-specific, shared by both consumers (TaxaLikely for reference-sequence fetch, TaxaExpect for occurrence fetch).

`escalate_taxonomic_rank(taxon_name, current_rank, rank_system = standard_ranks, max_levels = 2L, backbone_id = 4L, fallback_backbone_id = 11L, verbose = TRUE)` added (`R/escalate_taxonomic_rank.R`). Reuses `verify_taxon_names()` + `parse_classification_path()` directly (same primary-then-fallback-backbone pattern as `fill_higher_ranks()`) rather than duplicating classification-lookup logic. Given a taxon at `current_rank`, resolves its full classification once, then walks coarser ranks in `rank_system` starting at the immediate parent, up to `max_levels` steps, returning the first rank/name pair present in the classification path. This lets one call automatically skip a rank that's genuinely absent from the backbone's own path (e.g. genus straight to order when family isn't populated) without a second API round-trip -- distinct from "no reference/occurrence data at that rank," which is the caller's retry loop's job to detect by trying a fetch and calling this function again with the returned rank/name as the new `current_rank`/`taxon_name` if that fetch is still empty. Short-circuits with no API call at all when `current_rank` is already the coarsest rank in `rank_system`.

35 tests (`test-escalate_taxonomic_rank.R`), fully offline, `verify_taxon_names()` mocked via `local_mocked_bindings()` following `test-fill_higher_ranks.R`'s established pattern. `devtools::document()` + `devtools::test()` (723 expectations ecosystem-wide, 0 failures) + `devtools::check()` (0 errors, 0 warnings, 1 pre-existing NOTE re: cross-package Rd xrefs) all clean.

Live-verified against real NCBI data (not just mocks) for the exact validation cases named in the reentry prompt: `escalate_taxonomic_rank("Rhacochilus", current_rank = "genus")` -> family `Embiotocidae`; `escalate_taxonomic_rank("Embiotoca caryi", current_rank = "species")` -> genus `Embiotoca`; and the bobcat-photo case, `escalate_taxonomic_rank("Lynx", current_rank = "genus")` -> family `Felidae`. All three match the prior sessions' ad hoc validation.

**Not done this session** (Phases 2-7 of the reentry plan): wiring spatial grouping or this function into any of the four production workflow scripts, the Reads-table relocation, the TaxaAssign `(observation_id, site)` schema question, the end-to-end test matrix, or documentation. See the reentry prompt for the full sequenced plan.

**Session 134b (2026-07-04): define_search_polygon() moved here from TaxaFetch**

Branch `single-observation-pipeline`, follow-up to TaxaFetch/TaxaMatch's Session 134
(automatic spatial grouping). After the user reviewed that session's implementation,
a design question came up before committing: could the same interactive polygon gadget
serve both TaxaFetch's search-area purpose and TaxaMatch's new spatial-group purpose
(`group_observations_by_bbox()`), or did they need separate tools? Worked out that the
only generalization needed was small and additive -- coloring the `points` overlay by an
existing group column, and letting a previously drawn polygon be reopened for reshaping --
neither changes the core interaction model. That argued for one shared gadget rather than
duplicating it, so `define_search_polygon()` moved here (a dependency both TaxaFetch and
TaxaMatch already have) and TaxaFetch/TaxaMatch call `TaxaTools::define_search_polygon()`.

- Added `group_col` param: optional column in `points` used to color the reference-marker
  overlay by group (e.g. `spatial_group_id`), with a legend.
- Added `init_polygon` param: an existing WKT POLYGON string can be passed to reopen the
  gadget seeded with that polygon's own vertices instead of a fresh square -- used by
  `TaxaMatch::group_observations_by_bbox()`'s new end-of-loop edit step.
- Refactored `.pts_to_wkt()`/`.wkt_to_pts()` (WKT <-> vertex-vector conversion) out of the
  function's closure to module scope (`@noRd`) so they're unit-testable without a live
  gadget session -- matching the pattern the ecosystem already uses for other pure
  geometry helpers (e.g. `TaxaMatch`'s `.bbox_center_radius()`).
- `shiny`/`miniUI`/`leaflet` added to this package's `DESCRIPTION` Suggests (moved from
  TaxaFetch's, which no longer calls those namespaces directly).
- 8 new tests (`test-define_search_polygon.R`), fully offline (the gadget itself still
  requires a live interactive session, same testing boundary as before the move).
  `devtools::document()` + `devtools::test()` (688 expectations, 0 failures) +
  `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.
- See TaxaFetch/CLAUDE.md and TaxaMatch/CLAUDE.md Session 134b notes for what changed on
  the calling side, and `ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md`
  for the full design discussion.

**Bug found and fixed live-testing the gadget with `points` for the first time (same
session):** the `points`/`group_col` reference-marker overlay never actually rendered --
it flashed on load and immediately vanished. Root cause: `leaflet::clearMarkers()` and
`leaflet::clearShapes()` are not scoped to the layers you just added with `addMarkers()`/
`addPolygons()` -- per the leaflet R package's own documentation, `clearMarkers()` removes
**every** marker-type layer on the map (`addMarkers()`, `addCircleMarkers()`,
`addAwesomeMarkers()` alike), and `clearShapes()` removes every polygon/line/circle layer,
regardless of which call added them. The gadget's redraw `observe()` block called both,
intending only to wipe the old draggable-vertex polygon before redrawing it -- but that
also wiped the `addCircleMarkers()` reference-point overlay added once at gadget startup,
and since that `observe()` block fires immediately on load (not just on user interaction),
the points never had a chance to stay visible. Fixed by tagging the polygon and draggable
vertices with `group = "editor"` and the reference points with `group = "reference_points"`,
then replacing the two global `clear*()` calls with a single `leaflet::clearGroup(proxy,
group = "editor")` that only touches the editor's own layers. This bug existed from the
original `points` param's introduction (TaxaFetch Session 134) -- the pure/unit-tested
helpers never exercised it, and this was the first time anyone actually ran the gadget
with `points` supplied. Re-verified: `devtools::test()` (688 expectations, 0 failures),
`devtools::check()` (0 errors, 0 warnings, 0 notes).

**Second, much larger bug found the same way (same session): RStudio's `dialogViewer()`
silently swallowed the Done button's return value for this gadget specifically.** After
the fix above, live use of `group_observations_by_bbox()` still completely failed --
clicking Done closed the dialog, but the function always behaved as if the user had
clicked Cancel (returned `NULL`), so the calling loop never recorded a polygon and never
reopened for a second box. This took an extended debugging session to isolate, because
every offline signal looked fine: the installed code was confirmed correct via
`loadNamespace()` + `deparse()` (ruling out a stale-library-cache theory that seemed very
plausible at first, given `~/.Renviron`'s `R_LIBS_USER=~/Library/R/4.0/library` -- **not**
the path documented in this file's Developer Environment table -- turned out to be the
real, active library the whole time, confirmed by starting a real `R` session from the
project directory and checking `.libPaths()`/`find.package()` directly); a minimal
`miniUI` gadget (no leaflet, just a title bar and a Done button) worked correctly with
`shiny::dialogViewer()`, ruling out a general `shiny`/`miniUI`/RStudio incompatibility;
and the actual point-in-polygon math was independently verified correct with `sf` in
isolation. The conclusive test: the *exact* production gadget code (leaflet map,
reactive observers, everything), reconstructed via `deparse()` with only
`shiny::dialogViewer(...)` swapped for `shiny::browserViewer()`, opened in a real Chrome
browser and worked perfectly on the first click -- confirmed both by inspecting the
live page (Claude's Chrome browser-automation tools: accessibility tree showed real map
tiles and a correctly-updating live WKT preview) and by the calling R session printing
the correct WKT string after the click. Root cause, narrowed to: RStudio's embedded
dialog webview specifically mishandles this gadget's Leaflet content in a way that
breaks the Done button's click-to-server round trip, while an identical non-leaflet
gadget works fine in the same viewer and this exact gadget works fine outside that one
webview. Not something this package can fix in RStudio's dialog webview -- added a
`viewer` param to `define_search_polygon()` instead of the previous hardcoded
`shiny::dialogViewer(...)`. First set to `shiny::browserViewer()` (confirmed reliable),
but the user then pointed out this ecosystem already has two other interactive mapping
gadgets (`TaxaHabitat::review_spatial_flags()`, `TaxaExpect::plot_theta_map_interactive()`)
that both use `shiny::paneViewer()` successfully -- mixing a browser-tab gadget with
pane-based ones would be a needless inconsistency for the user. Tested
`paneViewer()` directly against this exact gadget (not just the non-leaflet minimal
test) and confirmed it also round-trips Done correctly, so the **final default is
`shiny::paneViewer(minHeight = 500)`**, matching the other two gadgets' own call style
exactly. `browserViewer()` remains confirmed working and is documented as the
alternative to pass explicitly; `dialogViewer()` is documented as the one to avoid for
this function. Callers who've confirmed `dialogViewer()` works on their own machine can
still pass it explicitly. Re-verified after each change: `devtools::test()` (688
expectations, 0 failures), `devtools::check()` (0 errors, 0 warnings, 0 notes). See
`TaxaID/CLAUDE.md`'s Known R Footguns for the ecosystem-wide note (any future Shiny
gadget wrapping `leaflet` should default away from `dialogViewer()` until this is
independently reproduced/reported upstream; use `paneViewer()` for consistency with the
mapping gadgets that already exist in this ecosystem).

Sessions 27–84 archived in ecosystem_docs/session_notes/TaxaTools_sessions.md.

**Session 85 (2026-05-23)**
- `call_api()` added to `R/call_api.R`: generic LLM dispatcher. Three handler families:
  `anthropic`, `gemini`, `openai_compat`. Data-driven via `inst/model_tiers.json`.
  Attaches `model` + `provider` attributes to response.
- All five `call_*_api()` functions converted to thin wrappers around `call_api()`.
  Same signatures; HTTP logic now lives in `call_api.R`. Kept for backward compatibility.
- `options(TaxaID.provider)` new R option storing active provider name string.
  `.onAttach()` now sets both `TaxaID.provider` and `TaxaID.llm_fn = call_api`.
- `type = "openai_compatible"` → `handler_family = "openai_compat"` in `register_provider()`.
- `prompt_api()`, `draft_methods_text()`, `draft_results_text()` defaults updated to `call_api`.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes (with pre-existing WARN on test-llm_utils.R)

**Session 86 (2026-05-23)**
- No code changes. WERC peer review integration (ecosystem docs, code.json, renv removal).
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`. See TaxaID/CLAUDE.md for full log.

**Session 87 (2026-05-26)**
- `call_api()`: `images` param added (named list of base64 PNG strings, as produced by
  `.render_pdf_pages()` in TaxaFetch). Each handler family formats images in its native
  vision block format: anthropic → image content blocks (`type/source/base64`),
  gemini → `inlineData` parts (`mimeType/data`), openai_compat → `image_url` blocks
  (`data:image/png;base64,...`). Text-only calls (images = NULL) unchanged.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 113 (2026-06-19)**
- `clean_taxon_names()`: added underscore-to-space normalization for Jonah Ventures / SILVA
  pipeline names that encode binomials as `Genus_epithet`. Regex
  `^[A-Z][A-Za-z.-]+_[a-z][A-Za-z.-]*$` detects the pattern; `gsub("_", " ", ...)` converts.
  Does NOT alter OTU codes (`OTU_001`), clade codes (`MAST-4`), or multi-underscore strings.
  8 new tests in `test-clean_taxon_names.R`.
- `verify_taxon_names()`: GBIF backbone (id=11) returns `matchedName` with authority strings
  (e.g. `"Paracalanus parvus (Claus, 1863)"`). Added `strip_authority()` helper using
  `regmatches()`/`regexpr()` to extract genus + optional epithet only. Applied at parse time
  so `matched_name` is clean everywhere downstream. NCBI backbone (id=4) was unaffected.
- `devtools::check()`: 675 tests passing; 0 errors, 0 warnings, 0 notes.

**Session 106 (2026-06-10)**
- `fill_higher_ranks()` added (`R/fill_higher_ranks.R`): given a character vector of taxon
  names (typically species binomials), extracts genus (first word) and looks up family via a
  priority chain: (1) local data frames (`local_sources`), (2) `verify_taxon_names()` at
  genus level on primary backbone (`backbone_id = 4L` NCBI), (3) fallback backbone
  (`fallback_backbone_id = 11L` GBIF). Genus-level querying means species absent from a
  backbone as synonyms are still resolved if their genus is present. Returns tibble with
  `taxon_name`, `genus`, `family`; warns for unresolved taxa; preserves duplicates and order.
  Internal helpers: `.build_genus_family_lookup()`, `.lookup_family_from_backbone()`,
  `.extract_classified_rank()`.
- `parse_classification_path()` added (`R/fill_higher_ranks.R`): thin exported wrapper
  around `.extract_classified_rank()`. Parses a single rank value from the
  pipe-delimited `classification_path` / `classification_ranks` columns returned by
  `verify_taxon_names()`. Use with `mapply()` for column-level extraction. Enables
  Option C pattern: `verify_taxon_names(word(name, 1))` → `parse_classification_path()`.
- `tibble` added to `DESCRIPTION` Imports (was missing; caused R CMD check ERROR).
- 39 tests in `test-fill_higher_ranks.R` (all offline; backbone API mocked via
  `local_mocked_bindings()`).
- `devtools::check()`: vignette/Pandoc ERROR is pre-existing infrastructure issue; 0 errors
  in R code checks.

**Session 92 (2026-05-27)**
- `call_api()`: two new params + token usage reporting:
  - `show_tokens = FALSE`: when TRUE, prints `"Tokens used — input: N, output: N"` after
    each call via `message()`. Default FALSE to avoid output in batch workflows.
  - `max_input_tokens = NULL`: pre-flight guard — estimates prompt tokens as
    `ceiling(nchar(prompt_str) / 3.5)` and stops before the HTTP call if over limit.
    Provides a substitute for interactive cancellation in long-running batch loops.
  - `attr(result, "tokens")`: new attribute always attached to the returned string.
    Named list `list(input = N, output = N)` with integers from the provider's response
    body. `NA_integer_` when the provider does not report usage.
  - Internal parsers `.parse_anthropic_response()`, `.parse_gemini_response()`,
    `.parse_openai_compat_response()` now return `list(text, tokens)` instead of a bare
    string. Token field names: Anthropic `body$usage$input_tokens`/`output_tokens`;
    Gemini `usageMetadata$promptTokenCount`/`candidatesTokenCount`; OpenAI-compat
    `usage$prompt_tokens`/`completion_tokens`.
  - Provider wrapper functions (`call_anthropic_api()` etc.) unchanged — they route
    through `call_api()` and pass `...` so users can access `show_tokens`/`max_input_tokens`
    by calling `call_api()` directly.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.
