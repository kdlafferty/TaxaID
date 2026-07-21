# CLAUDE.md — TaxaFetch
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-20, continued yet further (Sonnet 5 -- a real GBIF API timeout during
# the user's own re-verification of the cc_outl() fix (below) surfaced a second, independent
# real bug in fetch_gbif_occurrences()'s checkpoint logic, pre-existing, unrelated to today's
# other changes. With keys split into chunks, global_pos was advanced by the FULL chunk size
# even when a chunk aborted partway through -- so the checkpoint's remaining_keys was computed
# from a position AFTER the whole aborted chunk, silently excluding the very key that failed
# (and any others queued after it in that same chunk) from ever being retried on resume: a
# real violation of this function's own stated "never silently skip a key" design. Also
# produced a misleading "Enable cache_dir for resumable fetches" message on the user's actual
# run even though cache_dir WAS enabled and a real checkpoint HAD been saved after the prior
# chunk -- global_pos coincidentally landed exactly on length(keys), making the (buggy)
# resumability check evaluate false. Fixed: the abort check now runs BEFORE global_pos is
# advanced past the aborting chunk, and the checkpoint's remaining_keys re-includes the WHOLE
# aborting chunk (not just the failed key onward) so a resume cleanly re-fetches it rather than
# risk duplicate rows from any partial success within it. New regression test asserts the
# failed key is present in the saved remaining_keys (it wasn't, under the old logic). No user
# action needed for the checkpoint file from the actual failed run -- resuming with the same
# call still works, since that specific abort happened to land after a real prior-chunk
# checkpoint. devtools::test() 0 failures (487, up from 483), devtools::check() 0/0/0.
# Reinstalled to ~/Library/R/4.0/library. See this file's Session Notes for the full record.
# Previous update, 2026-07-20, continued (Sonnet 5 -- real production bug found and fixed on
# check_geographic_outliers()'s FIRST live run, wired into MuguFishWorkflow.R/
# MuguWilderFishWorkflow.R the same day: CoordinateCleaner::cc_outl()'s "distance" method
# silently switches EVERY species in a single call to a coarser "raster approximation" (its
# own term) whenever ANY ONE species in that call has >=10,000 records -- confirmed directly
# from cc_outl()'s own source (`if (any(record_numbers >= 10000)) warning("Using raster
# approximation.")`, scoped to the whole call, not per species). check_geographic_outliers()
# batches every locally-rare species into one cc_outl() call for efficiency, but a species
# rare in the LOCAL bbox can still be globally common -- one such species in the real
# ~51-species/193,458-record Mugu batch silently degraded every other species' precision,
# clearing a real, obvious ~9,000km outlier (the exact motivating Mugu Pseudotolithus
# epipercus/La Jolla case). Found live with the user: two hypotheses tested and refuted first
# (a gbifID type mismatch between download_gbif_occurrences()'s bit64::integer64 output and
# fetch_gbif_occurrences()'s character output -- ruled out directly, match() handles the
# coercion correctly even unattached; a species-crossing distance bug -- ruled out via a
# synthetic decoy-species reproduction) before the user's own diagnostic re-run surfaced the
# literal "Using raster approximation" warning, which traced directly to cc_outl()'s source.
# Fixed: cc_outl() now called once PER SPECIES instead of once for the whole batch, so the
# raster-mode decision is scoped to each species' own record count. New regression test
# (mocks CoordinateCleaner::cc_outl() directly, asserts one call per species) added rather
# than trying to synthesize a 10,000+ row fixture to reproduce the raster branch itself --
# the original unit tests (max ~17 rows) never exercised this path at all, the same "check
# dataset scale before trusting synthetic tests generalize" lesson this ecosystem has hit
# before (see TaxaLikely's restore_suppressed_candidates() history). devtools::test() 0
# failures (483, up from 481), devtools::check() 0/0/0. Reinstalled to
# ~/Library/R/4.0/library. See this file's Session Notes for the full record.
# Previous update, 2026-07-20 (Sonnet 5 -- new check_geographic_outliers(): for GBIF species
# with few records inside a bbox-scoped local search (default threshold n<5), fetches that
# species' unrestricted global GBIF distribution (fetch_gbif_occurrences(geometry = NULL),
# newly supported -- geometry was previously a required WKT string; a real nchar(NULL)
# checkpoint-signature bug was fixed alongside it) and runs CoordinateCleaner::cc_outl()
# against it, flagging a local record that's a geographic outlier relative to the species'
# real range (the general version of Mugu's real Pseudotolithus epipercus/La Jolla case --
# see [[project_edge_case_error_taxa_design]]). filter_gbif_quality() also gains three new
# CoordinateCleaner-backed checks (cc_equ/cc_zero/cc_gbif), default TRUE -- a real behavioral
# default change for every existing caller, not just an addition (see that function's
# Function Inventory entry below for the affected real call sites). CoordinateCleaner added
# to Suggests only, deliberately -- its cc_sea()/cc_coun()/cc_urb() functions need terra/
# rnaturalearth, but those three don't fit this ecosystem (marine-eDNA-hostile or already
# redundant with GBIF's own issue-code filtering) and aren't used; the functions actually
# called here don't need those dependencies. check_inat_range() (Session 118) found MISSING
# from this file's own Function Inventory table and Next Steps TODO list while working
# nearby -- real doc drift, corrected same session, not implemented new. devtools::test()
# 0 failures (481, up from 459), devtools::check() 0 errors/0 warnings/0 notes. Reinstalled
# to ~/Library/R/4.0/library.
# Previous update, 2026-07-09 (Session 148 -- full code + domain review against
# inst/Code and Domain Review 2.Rmd, findings and fixes in taxafetch_review.Rmd at the
# TaxaID root. Two real, fixed issues: an SSRF gap in the DataONE pipeline (data_url read
# verbatim from third-party EML metadata with no host restriction -- fixed via a
# pasta.lternet.edu/pasta.edirepository.org allowlist) and a homonym-misresolution gap in
# get_keys_from_context()'s HIGHERRANK recovery path (name_lookup() fallback dropped all
# kingdom context -- fixed by narrowing lookup hits to the row's own kingdom before voting).
# Also fixed: biotime_fetch.R conflating unparseable ABUNDANCE/BIOMAS with confirmed
# occurrenceStatus = "absent" (now NA); filter_gbif_quality()'s eDNA-exclusion pattern was
# overly broad ("bulk sample"/"water sample" alone, narrowed to the three eDNA-specific
# terms); doc-only clarifications for make_bbox_wkt()'s latitude-dependent km caveat and
# get_gbif_occurrences()'s rank_filter subspecies-exclusion behavior; a zip-slip defense-in-
# depth check added to download_gbif_occurrences(). Corrects Session 131's Pass 7a note
# ("no high-confidence vulnerabilities found") -- that pass did not live-test DataONE's EML
# handling against real PASTA data, which is what surfaced the SSRF gap this session.
# devtools::test(): 459 expectations (up from 434), 0 failures. devtools::check(): 0 errors,
# 0 warnings, 0 notes. See Session 148 note below for the full record. Session 140 --
# fetch_occurrences_by_taxon() added: taxon-centric
# batched GBIF fetch, implementing the general-fix design from
# ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md. stack_occurrences() also
# gained a gbifID dedup step. See Session 140 note below for the full record. Session 134b --
# define_search_polygon() and group_observations_by_bbox() moved OUT of this package:
# define_search_polygon() -> TaxaTools (shared gadget, now also used for TaxaMatch's spatial
# grouping), group_observations_by_bbox() -> TaxaMatch (it operates on
# TaxaMatch::build_site_table()'s output; a spatial-grouping concern, not a fetch concern).
# shiny/miniUI/leaflet dropped from this package's Suggests accordingly. See TaxaTools/CLAUDE.md
# and TaxaMatch/CLAUDE.md Session 134b notes for the new homes.)

---

## Package Purpose
Occurrence data acquisition (GBIF, DataONE, PDF, literature search) and source combination.
Habitat assignment and spatial QAQC are now in **TaxaHabitat**. LLM provider functions are
now in **TaxaTools**. Split from TaxaExpect in Session 19; further split in Session 28.

**Dependency chain:** TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign/TaxaMatch

---

## Function Inventory

**Note (Session 134b):** the interactive polygon gadget formerly documented here,
`define_search_polygon()`, is now `TaxaTools::define_search_polygon()` -- moved so
TaxaMatch's `group_observations_by_bbox()` (spatial grouping) can share it with this
package's search-area use. `make_bbox_wkt()` below still links to it for the
non-interactive-vs-interactive comparison.

### DataONE / GBIF pipeline

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `stack_occurrences()` | Row-bind occurrence data frames; accepts list OR `...`; drops NULL; adds `point_id`; single-frame OK. **Session 140:** drops rows with a duplicate non-`NA` `gbifID` (first kept) when that column is present -- defense-in-depth against double-counting the same GBIF record, since no earlier step in the GBIF pipeline dedupes by key. | Complete | R/stack_occurrences.R |
| `make_bbox_wkt()` | Build WKT POLYGON bounding box (scripted, non-interactive) | Complete | R/make_bbox_wkt.R |
| `get_keys_from_context()` | Resolve hierarchy dataframe to GBIF usage keys. **Session 148:** its `HIGHERRANK`-recovery path (`.recover_higherrank()`) now narrows `rgbif::name_lookup()` hits to the row's own kingdom (when available) before majority-voting a `nubKey`, closing a homonym-misresolution gap; the resulting `matchType = "LOOKUP_RECOVERED"` is now documented and included in the "review these rows" advice. | Complete | R/get_keys_from_context.R |
| `fetch_gbif_occurrences()` | Download occurrence records for GBIF taxon keys via GBIF occurrence API. `max_retries` (default 4) applies exponential backoff on HTTP 429 (30/60/120/240s) and HTTP 503 (5/10/20/40s). Any exhausted retry aborts immediately (no silent skipping). `cache_dir` (default: user cache dir) saves per-chunk checkpoints; re-running with same args resumes automatically. **Use for ≤~50 keys; no GBIF account required.** See `download_gbif_occurrences()` for large key sets. **2026-07-20:** `geometry` now accepts `NULL` for an unrestricted global search (previously required a WKT string); the checkpoint-signature helper's `nchar(NULL)` bug (returned `integer(0)`, would have broken `sprintf`) fixed alongside it. Added for `check_geographic_outliers()`, below. **2026-07-20, continued:** real, pre-existing checkpoint bug fixed, found via a real GBIF timeout mid-run -- `global_pos` was previously advanced by a chunk's FULL size even when that chunk aborted partway through, so the saved checkpoint's `remaining_keys` silently excluded the key that actually failed (and any others queued after it in the same chunk), meaning it would never be retried on resume. Also caused a misleading "Enable cache_dir for resumable fetches" message on a real run where `cache_dir` genuinely was enabled and a checkpoint genuinely had been saved. Fixed: abort check now runs before `global_pos` advances past the aborting chunk; the checkpoint re-includes the WHOLE aborting chunk (not just the failed key onward) so resume can't produce duplicate rows from a partial in-chunk success. | Complete | R/fetch_gbif_occurrences.R |
| `download_gbif_occurrences()` | Async bulk download via GBIF download API — use for large key sets (100s–1000s) to avoid HTTP 429 rate limits. Submits `occ_download()` job; polls until complete; downloads zip to `cache_dir`. **Requires GBIF account** (`GBIF_USER`/`GBIF_PWD`/`GBIF_EMAIL` in `~/.Renviron`). Key design notes: (1) uses rank-specific OR predicate (`familyKey`/`genusKey`/`speciesKey`/`taxonKey`) because download API `taxonKey` is exact-match only, not hierarchical; (2) `limit` is per-key (group_by taxonKey + slice_head); (3) signature-based cache — re-runs with same params skip GBIF wait and load from cached zip; (4) `select_cols` trims SIMPLE_CSV to needed columns at fread time (~10× size reduction); (5) SIMPLE_CSV `issue` column renamed to `issues` for `filter_gbif_quality()` compatibility — implemented and verified working (Session 131; a Session 129 note here previously claimed otherwise, incorrectly); (6) `basis_keep` applied server-side. `bibliographicCitation` = GBIF download portal URL (avoids `occ_download_meta()` hang). Called directly, `select_cols` should reference SIMPLE_CSV's native `issue` (singular) name if customized — the function renames the output column to `issues` regardless. | Complete | R/download_gbif_occurrences.R |
| `get_gbif_occurrences()` | **Session 129 — recommended entry point**, not a replacement for the two functions above (neither is modified). Picks `fetch_gbif_occurrences()` vs `download_gbif_occurrences()` by `key_threshold` (default 50, matching both functions' own documented guidance and the manual dispatch pattern the Layer-1 tutorial already used) and standardizes both paths to one column contract. `rank_filter = "species"` (default) is a post-fetch filter only — neither GBIF API exposes a taxonomic-rank predicate to filter server-side. `columns = "standard"` (default) / `"all"` / custom vector. `familyKey`/`genusKey` are `NA` on the download path — SIMPLE_CSV doesn't carry them at all, not fixable by this wrapper. Translates the wrapper's canonical `issues` column name back to SIMPLE_CSV's native `issue` when building `select_cols` for the download path (needed because `select_cols` matches at import time, before `download_gbif_occurrences()`'s own rename runs) — this is the only issue/issues handling the wrapper does; see `download_gbif_occurrences()`'s entry above for the Session 131 correction to a false "cross-path bug" claimed here previously. | Complete | R/get_gbif_occurrences.R |
| `fetch_occurrences_by_taxon()` | **Session 140 — taxon-centric batched fetch.** Groups a fetch scope (one row per (site, candidate taxon) pair: `taxon_key` + `geometry` WKT) by taxon key instead of by observation/site: unions each taxon key's own geometry via `sf::st_union()` (dissolving the duplicate-record risk when two site boxes for the same taxon overlap), then combines different taxon keys that end up with an identical unioned geometry into one multi-key `get_gbif_occurrences()` call (`combine_shared_geometry = TRUE`, default). Neither `get_gbif_occurrences()` nor its own backends are modified — this is a pure call-grouping layer above it. Does not expose `rgbif`'s `geom_big`/`geom_size`/`geom_n` WKT-complexity escape valve and does not characterize GBIF's real WKT-size ceiling (documented as a known limitation, not silently masked). See `ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md` for the full design discussion this implements. | Complete | R/fetch_occurrences_by_taxon.R |
| `filter_gbif_quality()` | Filter GBIF records by quality criteria; default `max_coord_uncertainty = 500` m; NA retained. `exclude_absent = TRUE` removes records where `occurrenceStatus = "ABSENT"` (explicit non-detections from systematic surveys — must not be used as presence data). `require_species = FALSE` (set TRUE when querying by family/genus key — GBIF returns all ranks within the taxon including genus-only records that lack a species value). Filter order: coordinates → absent occurrences → basis of record → issue codes → coordinate uncertainty → decimal-place precision → eDNA → species-level requirement → CoordinateCleaner checks. **Session 148:** the eDNA-exclusion pattern narrowed to `edna`/`environmental dna`/`metabarcod` -- dropped the generic `bulk sample`/`water sample` phrases, which risked over-excluding legitimate non-eDNA presence data. **2026-07-20 (behavioral default change):** new filter step 9 calls `CoordinateCleaner::cc_equ()`/`cc_zero()`/`cc_gbif()` (identical lat/lon, near-(0,0), near GBIF's Copenhagen HQ) via new `exclude_equal_coords`/`exclude_near_zero`/`exclude_near_gbif_hq` params, each default `TRUE`. Uses that package's own internal buffer defaults rather than hand-copied constants -- see the function's own roxygen `@details` for why. Skips with a message (not an error) if `CoordinateCleaner` is not installed, matching every other optional-column/optional-package filter in this function. Every real in-repo caller (`TaxaExpect::build_priors()`, `TaxaExpect/inst/workflows/generate_priors_workflow.R`, `TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R`, `TaxaWizard/inst/graph/snippets/taxa_to_occ.R`) calls with no override, so all now pick up the new checks automatically wherever `CoordinateCleaner` happens to be installed. | Complete | R/filter_gbif_quality.R |
| `check_geographic_outliers()` | **2026-07-20, new.** Flags bbox-scoped occurrence records that are geographic outliers against a species' own global GBIF distribution -- the generic version of "single citizen-science record from the wrong continent slips into a local species list" (motivating real case: Mugu's *Pseudotolithus epipercus*, an African species with one errant La Jolla observation, see `[[project_edge_case_error_taxa_design]]` in the memory system). For species with fewer than `min_local_n` (default 5) local records, fetches that species' unrestricted global occurrences via `fetch_gbif_occurrences(geometry = NULL)` and runs `CoordinateCleaner::cc_outl()` (`method = "distance"`, `tdi = 1000` km default) **once per species** against its own global cloud. Well-supported local species are never checked -- the global fetch is the expensive step. **2026-07-20, same-day fix (real production bug, first live run):** originally called `cc_outl()` once across the WHOLE batch of rare species combined -- that function's `"distance"` method silently switches every species in a single call to a coarser raster approximation whenever any ONE species in that call has >=10,000 records, and a locally-rare species can still be globally common. This let one common species in a real ~51-species Mugu batch silently degrade every other species' precision, clearing a real, obvious ~9,000km outlier (the exact motivating *Pseudotolithus epipercus* case). Fixed by scoping each `cc_outl()` call to one species at a time. Adds `local_n`/`global_n_unique`/`outlier_status` columns; `outlier_status` is always one of `"not_tested_sufficient_local_data"` / `"insufficient_global_data"` / `"outlier"` / `"consistent"` -- never a bare logical, so "not tested" and "tested and passed" stay distinct (mirrors `check_inat_range()`'s `range_status` convention, immediately below). `min_occs` (default 7, matching `cc_outl()`'s own default) is enforced explicitly rather than trusted to `cc_outl()`'s own silent-pass-below-threshold behavior, since that function's own warning about it is suppressed here (redundant with the structured status column). Requires `CoordinateCleaner` (`Suggests`, hard error if missing -- no sensible fallback exists, unlike `filter_gbif_quality()`'s graceful per-check skip). | Complete | R/check_geographic_outliers.R |
| `check_inat_range()` | Point-in-polygon range check against iNaturalist geomodel range polygons, for the dark-diversity use case (eDNA detections absent from the occurrence database, checked for range plausibility as a prior-boost signal). Implemented Session 118 -- **missing from this table until 2026-07-20**, a real doc-drift gap; see the corrected Next Steps entry below. Returns `in_range`, `range_status` (`"in_range"`/`"out_of_range"`/`"taxon_not_found"`/`"no_polygon"`), `n_observations`, `iconic_taxon_name`, `inat_kingdom`. Evidence is asymmetric by design: `in_range = FALSE` must not suppress a prior (false negatives are common for aquatic/marine taxa given low iNaturalist observer effort there) -- worth remembering before using this as a fallback alongside `check_geographic_outliers()`, whose primary use case (12S/18S fish eDNA) is exactly the domain this function is weakest in. Downstream: `TaxaAssign::adjust_inat_range_priors()`. | Complete | R/check_inat_range.R |
| `report_fetch()` | Generate `report_section` summarizing occurrence fetch results for `assemble_report()` | Complete | R/report_fetch.R |
| `read_biotime_study()` | Read a BioTime study CSV into a standardized occurrence tibble. **Session 148:** `occurrenceStatus` is now `NA` (not `"absent"`) when neither `ABUNDANCE` nor `BIOMAS` parses to a number, since an unparseable/missing value is not a confirmed non-detection. | Complete | R/biotime_fetch.R |
| `screen_eml_columns()` | Fetch EML; check bbox overlap; detect lat/lon columns | Complete | R/dataone_eml_screen.R |
| `preview_dataone_occurrences()` | Pre-download scout; `dataone_preview` S3 class | Complete | R/dataone_preview.R |
| `print.dataone_preview()` | S3 print method | Complete | R/dataone_preview.R |
| `search_dataone()` | Legacy convenience search | Complete | R/dataone_occurrence_search.R |
| `fetch_dataone_eml()` | Fetch and parse EML XML for one PASTA dataset ID | Complete | R/dataone_occurrence_search.R |
| `fetch_dataone_occurrences()` | Download occurrence records; six-pass architecture | Complete | R/dataone_standardize.R |
| `harvest_dataone_catalog()` | Paginated full PASTA Solr harvest; disk-cached | Complete | R/dataone_catalog.R |
| `build_geo_prompt()` | Build `geo_prompt` S3 for LLM geographic screening — DataONE path only | Complete | R/dataone_geo_screening.R |
| `parse_geo_screening_response()` | Parse YES/NO LLM response → filtered candidate tibble | Complete | R/dataone_geo_screening.R |
| `build_taxon_screen_prompt()` | Build `taxon_prompt` S3; `geo_scope` param enables combined taxon+geo screening | Complete | R/dataone_taxon_screening.R |
| `print.taxon_prompt()` | S3 print method; shows `geo_scope` when present | Complete | R/dataone_taxon_screening.R |
| `parse_taxon_screening_response()` | Parse LLM response → `taxon_match` + optional `geo_match`; auto-drops stale columns | Complete | R/dataone_taxon_screening.R |

### Literature search pipeline (Session 25)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `search_literature()` | Query OpenAlex API; reverse-geocode bbox via Nominatim; return catalog tibble | Complete | R/literature_search.R |
| `download_literature_pdfs()` | Download PDFs; adds `local_pdf_path`; validates PDF magic bytes; `overwrite` param | Complete | R/literature_search.R |

### PDF pipeline (Sessions 23–25)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `extract_pdf_text()` | Extract text by section; returns `$sections`, `$page_map`, `$has_headers`, `$n_pages`, `$pdf_path` | Complete | R/pdf_text.R |
| `call_api_pdf()` | Send selected PDF pages as images to Anthropic API (Anthropic-only) | Complete | R/pdf_api.R |
| `screen_pdf_structure()` | Five-axis characterisation; `llm_fn` param | Complete | R/pdf_characterize.R |
| `print.pdf_structure()` | S3 print method | Complete | R/pdf_characterize.R |
| `build_pdf_extract_prompt()` | Configure extraction prompt; `dpi` param (default 150L); `chunk_pages` param | Complete | R/pdf_extract.R |
| `print.pdf_extract_prompt()` | S3 print method | Complete | R/pdf_extract.R |
| `parse_pdf_extract_response()` | CSV → DwC tibble; strips subspecies; expands abbreviations | Complete | R/pdf_extract.R |
| `build_pdf_screen_prompt()` | Stage 1 abstract screener | Planned | R/pdf_screen.R |
| `parse_pdf_screen_response()` | Parse Stage 1 screening response | Planned | R/pdf_screen.R |

### Functions moved in Session 28 (now in other packages)

| Function | Now in | File |
|---|---|---|
| `call_anthropic_api()` | TaxaTools | R/llm_api_utils.R |
| `call_gemini_api()` | TaxaTools | R/llm_api_utils.R |
| `call_openai_api()` | TaxaTools | R/llm_api_utils.R |
| `call_ollama_api()` | TaxaTools | R/llm_api_utils.R |
| `prompt_api()` | TaxaTools | R/llm_api_utils.R |
| `prompt_manual()` | TaxaTools | R/llm_api_utils.R |
| `read_llm_response()` | TaxaTools | R/llm_api_utils.R |
| `parse_hierarchical_habitat_response()` | TaxaHabitat | R/parse_habitat_response.R |
| `build_habitat_prompt()` | TaxaHabitat | R/build_habitat_prompt.R |
| `assign_habitat_biological()` | TaxaHabitat | R/assign_habitat_biological.R |
| `flag_habitat_inconsistencies()` | TaxaHabitat | R/flag_habitat_inconsistencies.R |
| `review_spatial_flags()` | TaxaHabitat | R/review_spatial_flags.R |
| `screen_spatial_formula()` | TaxaHabitat | R/screen_spatial_formula.R |
| (plot helpers) | TaxaHabitat | R/utils_plot.R |

---

## Pipeline Architectures

### DataONE pipeline
```
harvest_dataone_catalog() → build_geo_prompt() → build_taxon_screen_prompt()
  → screen_eml_columns() → preview_dataone_occurrences() → fetch_dataone_occurrences()
```

### GBIF pipeline
```
make_bbox_wkt()                        [scripted square bbox]
TaxaTools::define_search_polygon()     [interactive polygon gadget — interactive sessions only]
  ↓
get_keys_from_context() → get_gbif_occurrences()           [Session 129: picks the path below by key count]
                            ↳ fetch_gbif_occurrences()      [≤~50 keys, no account]
                            ↳ download_gbif_occurrences()   [100s–1000s keys, account required]
                        → filter_gbif_quality()
                        → check_geographic_outliers()   [optional, 2026-07-20 -- species below
                                                          min_local_n only; needs CoordinateCleaner]
```

**Session 140 -- taxon-centric batched fetch (a scope-building layer above `get_gbif_occurrences()`):**
```
build a (taxon_key, geometry) fetch scope, one row per (site, candidate taxon)
  ↓
fetch_occurrences_by_taxon()   [unions each taxon key's own geometry, combines
                                 taxa sharing identical geometry, one call per
                                 group via get_gbif_occurrences()]
  ↓
stack_occurrences()             [row-bind + gbifID dedup, Session 140]
```
Use this instead of calling `get_gbif_occurrences()` directly whenever the
fetch scope spans more than one site/observation and search areas can
overlap or coincide -- see `fetch_occurrences_by_taxon()`'s own entry above
and `inst/TaxaID_Workflow_Template_TEST.R` Section 3 for a worked example
(multi-member cluster + single-observation escalation ladder, unified into
one taxon-key map).

### Literature + PDF pipeline
```
search_literature() → build_taxon_screen_prompt(geo_scope=...) [optional]
  → download_literature_pdfs() → extract_pdf_text() → screen_pdf_structure()
  → build_pdf_extract_prompt() → call_api_pdf() → parse_pdf_extract_response()
  → stack_occurrences()
```

After TaxaFetch: pass occurrence data to **TaxaHabitat** for habitat assignment.

**Key difference:** `build_geo_prompt()` requires DataONE-specific catalog columns — cannot
be used on OpenAlex output. For the literature path, use `build_taxon_screen_prompt(geo_scope=...)`.

---

## LLM Dispatch Architecture (`llm_fn` pattern)

Provider functions (`call_anthropic_api`, `call_gemini_api`, etc.) live in **TaxaTools**.
Since TaxaFetch imports TaxaTools, they are available directly without `TaxaTools::` prefix.

| Function | Provider | Free? | Key env var |
|---|---|---|---|
| `call_anthropic_api()` | Anthropic | No | `ANTHROPIC_API_KEY` |
| `call_gemini_api()` | Google Gemini | Yes (free tier) | `GEMINI_API_KEY` |
| `call_openai_api()` | OpenAI | No | `OPENAI_API_KEY` |
| `call_ollama_api()` | Ollama (local) | Yes (always) | none |

Non-default model/key via closure:
```r
my_fn <- function(p, ...) TaxaTools::call_gemini_api(p, model = "gemini-2.5-flash")
screen_pdf_structure(pdf_content, llm_fn = my_fn)
```

`call_api_pdf()` is Anthropic-only (vision API); provider-neutral image upload is future work.

---

## Key Notes for Claude

- `search_literature()` output column is `id` (not `catalog_id`) — matches `harvest_dataone_catalog()`
- Always drop stale `geo_match`/`taxon_match` columns before rebuilding screening prompts
- `taxon_match` and `geo_match` from `parse_taxon_screening_response()` are **logical**
- `abstract_chars = 2000L` recommended for literature papers (default 300L is too short)
- HTTP 403 on PDF downloads is a publisher restriction, not a bug
- `OPENALEX_API_KEY` in `~/.Renviron`; free tier is sufficient
- `%||%` is an internal operator defined in `get_keys_from_context.R` and `dataone_standardize.R`
  — do not redefine in other TaxaFetch files
- Habitat assignment is now in **TaxaHabitat** — do not add habitat functions back here

---

## Known Issues

- HTTP 403 on publisher PDF downloads: manual download path in workflow
- Section assignment imperfect for two-column layouts (cosmetic only)
- `build_geo_prompt()` not usable on OpenAlex catalog (DataONE-specific columns)
- `call_api_pdf()` is Anthropic-only; provider-neutral image upload is future work

---

## Next Steps

1. ~~Run `devtools::check()`~~ — verified clean (Session 63)
2. ~~`pdf_screen.R`~~ — resolved: `build_taxon_screen_prompt(geo_scope=...)` already handles literature catalog screening in combined mode (Session 63)
3. ~~`stack_occurrences` tests~~ — already written and passing (22 tests, Session 63)
4. ~~GITA multi-table functions~~ — dropped: `rename_cols()` + `stack_occurrences()` cover the same use case (Session 63)
5. ~~Data source citation capture~~ — implemented (Session 63): `bibliographicCitation` column added to `fetch_gbif_occurrences()`, `standardize_dataone_occurrences()`, `read_biotime_study()`; PDF pipeline already had it via `search_literature()`
6. ~~ReefCheck + Reef Life Survey~~ — resolved (Session 64): both already in GBIF (RLS global reef fish dataset, RCCA rocky reef dataset, Reef Check Taiwan). No separate fetch functions needed.
7. ~~`check_inat_range()`~~ — implemented Session 118 (`R/check_inat_range.R`); this Next Steps entry and the Function Inventory table above both went stale until corrected 2026-07-20 -- see `[[project_inat_image_analyzer]]` in the memory system.
8. **`score_image_inat()`** — implemented Session 119, but lives in **TaxaMatch**, not this package -- see that package's own CLAUDE.md. Not tracked further here.
9. **`check_geographic_outliers()`** — implemented 2026-07-20 (`R/check_geographic_outliers.R`), see the Function Inventory table above.

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-fetch_gbif_occurrences.R | `fetch_gbif_occurrences()`, `.gbif_checkpoint_path()` | Mocked rgbif; covers 429 retry/backoff; 2026-07-20 added `geometry = NULL` global-search coverage |
| test-filter_gbif_quality.R | `filter_gbif_quality()` | Fully offline; 2026-07-20 added `cc_equ`/`cc_zero` CoordinateCleaner-check coverage (real package calls, `skip_if_not_installed`) |
| test-check_geographic_outliers.R | `check_geographic_outliers()` | 2026-07-20, **new file**. Mocks `rgbif::occ_data` (same layer as test-fetch_gbif_occurrences.R) so the real `fetch_gbif_occurrences()` and `CoordinateCleaner::cc_outl()` both run underneath -- genuine end-to-end coverage of the outlier/insufficient-data/consistent three-way split, not just the plumbing. Same-day addition: a regression test mocking `CoordinateCleaner::cc_outl()` directly to assert it's called once per species (not once for the whole batch) -- guards the real raster-approximation bug found on first live use; deliberately not a synthetic 10,000+ row fixture, which would be slow and still wouldn't exercise the actual bug (that needed real GBIF data's clustering, not synthetic data -- see Session Notes) |
| test-get_keys_from_context.R | `get_keys_from_context()`, `.recover_higherrank()` | Mocked rgbif; Session 148 added kingdom-narrowing coverage via a synthetic mixed-kingdom fixture |
| test-make_bbox_wkt.R | `make_bbox_wkt()` | Fully offline |
| test-stack_occurrences.R | `stack_occurrences()` | 22 tests; fully offline |
| test-report_fetch.R | `report_fetch()` | Fully offline |
| test-biotime_fetch.R | `read_biotime_study()` | Fully offline; Session 148 added NA-vs-absent `occurrenceStatus` coverage |
| test-dataone_standardize.R | `fetch_dataone_occurrences()`, `.is_trusted_pasta_url()`, `.download_data_table()` | Mocked DataONE API; Session 148 added SSRF host-allowlist coverage |
| test-dataone_preview.R | `.preview_one_entity()` (guard only) | Session 148, **new file** -- `preview_dataone_occurrences()` itself remains untested, a pre-existing gap |
| test-dataone_taxon_screening_geo.R | `build_taxon_screen_prompt()`, `parse_taxon_screening_response()`, `build_geo_prompt()`, `parse_geo_screening_response()` | LLM mocked |
| test-literature_search.R | `search_literature()`, `download_literature_pdfs()` | OpenAlex calls mocked |

---

## Key Dependencies

| Package | Role | Note |
|---|---|---|
| TaxaTools | LLM provider functions, taxonomy helpers | Imports |
| httr2 | API calls (PASTA Solr, OpenAlex, Nominatim) | Imports |
| rgbif | GBIF backbone + occurrence download | Suggests |
| CoordinateCleaner | `cc_equ`/`cc_zero`/`cc_gbif` in `filter_gbif_quality()`; `cc_outl()` in `check_geographic_outliers()` | Suggests (2026-07-20). Deliberately not `Imports` -- its own heavy deps (`terra`, `rnaturalearth`) are needed only by the `cc_sea()`/`cc_coun()`/`cc_urb()` functions this ecosystem doesn't use (poor fit for marine eDNA / redundant with existing GBIF-issue-code filtering); the functions actually used here don't need them. |
| data.table | Fast TSV import for `download_gbif_occurrences()` | Suggests |
| dplyr | Data manipulation | Imports |
| stringr | String operations | Imports |
| tibble | Tibble construction | Imports |
| readr | CSV parsing | Imports |
| xml2 | EML XML parsing | Imports |
| rlang | NSE utilities | Imports |
| stats | Internal use | Imports |
| utils | URL encoding etc. | Imports |
| pdftools | `pdf_text()`, `pdf_render_page()` | Suggests (PDF pipeline only) |
| png | `writePNG()` for image encoding | Suggests (PDF pipeline only) |
| base64enc | `base64encode()` for API image blocks | Suggests (PDF pipeline only) |

**Session 134b:** `shiny`/`miniUI`/`leaflet` removed from Suggests -- they were only used
by `define_search_polygon()`, which moved to TaxaTools this session (see Session 134b note
below and TaxaTools/CLAUDE.md).

---

## Session Notes

**2026-07-20, continued yet further (Sonnet 5): `fetch_gbif_occurrences()` checkpoint bug -- found via a real GBIF timeout**

Branch not tracked. Direct continuation: after the `cc_outl()` per-species fix (below), the
user re-verified it against the real Mugu data with a targeted re-run
(`raw_gbif %>% filter_gbif_quality(...) %>% check_geographic_outliers(cache_dir =
CACHE_DIR_GBIF_GLOBAL)`). That run hit a real GBIF API timeout on key 43 of 51
(`Timeout was reached [api.gbif.org]: Operation too slow`) -- an external, environmental
failure, not a code bug. But the resulting error message was: `"fetch_gbif_occurrences:
fetch aborted early.\n  Enable cache_dir for resumable fetches."`, even though the user HAD
passed `cache_dir = CACHE_DIR_GBIF_GLOBAL`.

- **Root cause, found by re-reading `fetch_gbif_occurrences()`'s chunk loop directly:** with
  51 keys and the default `chunk_size = 20`, chunks are `[1-20]`, `[21-40]`, `[41-51]` (11
  keys); key 43 is the 3rd key of the 3rd chunk. `global_pos <- global_pos + length(chunk_keys)`
  ran unconditionally, BEFORE the abort check -- so on this chunk's abort, `global_pos` jumped
  from 40 to `40 + 11 = 51`, exactly `length(keys)`. The abort branch's own resumability check
  (`global_pos < length(keys)`) then evaluated `FALSE`, routing to the generic "enable
  cache_dir" message instead of the "progress saved" one, even though a real checkpoint HAD
  already been written after chunk 2 completed (`global_pos = 40 < 51` was true then).
- **A more serious problem than the misleading message, found by tracing the logic further:**
  the same `global_pos`-after-full-chunk computation is ALSO used to build the checkpoint's own
  `remaining_keys` (`keys[(global_pos + 1L):length(keys)]`) in the branch where a checkpoint
  IS saved. Using a post-chunk `global_pos` there means `remaining_keys` always starts AFTER
  the whole aborting chunk -- silently excluding the specific key that failed, and any others
  queued after it in that same chunk, from `remaining_keys` entirely. On resume, that key would
  never be retried again. This directly contradicts the function's own documented design
  ("Any exhausted retry aborts immediately (no silent skipping)") -- the abort itself wasn't
  silent, but a retried key being permanently dropped from the retry set would have been.
- **Fix:** moved the abort check to run BEFORE `global_pos` advances past the aborting chunk,
  so checkpoint computations always use the position from the START of that chunk. The whole
  aborting chunk (not just the failed key onward) is included in `remaining_keys` on resume,
  deliberately discarding any of that chunk's own partial success (e.g. key 3 succeeding before
  key 4 failed) in favor of a clean re-fetch -- avoids any risk of duplicate rows from a key
  that both partially succeeded pre-abort and gets refetched.
- **New regression test** (`test-fetch_gbif_occurrences.R`): 5 keys, `chunk_size = 2`, key 4
  (2nd key of the 2nd chunk, after key 3 succeeds within the same chunk) mocked to fail --
  asserts the saved checkpoint's `remaining_keys` includes key 4 itself (it didn't, under the
  old logic) and, per the fix's own re-fetch-whole-chunk design, keys 3-5 together.
- **Practical note for the user's own blocked run:** no action needed for the checkpoint file
  from the actual failed run specifically -- that abort happened to land right after chunk 2's
  real checkpoint save, so simply re-running the same `fetch_gbif_occurrences()`/
  `check_geographic_outliers()` call resumes from key 41 rather than restarting. The fix
  matters for the general case (e.g. a timeout in the very FIRST chunk of a run, before any
  prior chunk had a chance to checkpoint, which the old logic could have silently mishandled).
- `devtools::test()` 0 failures (487, up from 483), `devtools::check()` 0/0/0. Reinstalled to
  `~/Library/R/4.0/library`.

**2026-07-20, continued (Sonnet 5): real production bug found on `check_geographic_outliers()`'s first live run**

Branch not tracked. Direct continuation of the same-day work below: the function was wired
into `MuguFishWorkflow.R`/`MuguWilderFishWorkflow.R` (outside this monorepo, not under git)
and run for real against the full Mugu dataset -- the very first live test. The user's own
result was the tell: `Pseudotolithus epipercus` -- the exact motivating case for this whole
mechanism (an African species with one errant citizen-science record in La Jolla) -- came
back `outlier_status = "consistent"`, not `"outlier"`. The literal case the function exists
to catch wasn't caught, on the first real run.

- **Two hypotheses tested and refuted before finding the real cause**, both live-verified
  with actual R code rather than asserted: (1) a `gbifID` type mismatch between
  `download_gbif_occurrences()`'s output (`bit64::integer64`, via `data.table::fread()`
  inferring the type for GBIF IDs exceeding 32-bit range) and `fetch_gbif_occurrences()`'s
  output (plain character, via `rgbif`) -- tested directly with a realistic reproduction
  (`fread()`-typed `integer64` vector subset via a logical mask, `match()`ed against a
  character vector, at the real scale); `match()` correctly coerces and finds every match
  even with `bit64` never explicitly attached (`MuguFishWorkflow.R` doesn't `library(bit64)`).
  Not the bug. (2) A species-crossing distance computation in `cc_outl()` (i.e. the "distance"
  method comparing across species when other rare species have geographically nearby points)
  -- tested with a synthetic "decoy species" reproduction placing points near California
  alongside the real 12-point *P. epipercus* global cloud; `cc_outl()` correctly restricted
  distance comparisons to same-species pairs regardless. Not the bug.
- **The user's own diagnostic re-run of the real, full batch surfaced the actual cause
  directly**: `Warning message: ... Using raster approximation.` Read `cc_outl()`'s own
  source (`print(CoordinateCleaner::cc_outl)`) rather than guessing further --
  `record_numbers <- unlist(lapply(splist, nrow)); if (any(record_numbers >= 10000) |
  thinning) { warning("Using raster approximation."); ras <- ras_create(...) }` -- confirmed
  this check is scoped to the WHOLE call (`any()` across every species' `splist` entry), not
  per species. `check_geographic_outliers()` batches every locally-rare species into one
  `cc_outl()` call for fetch efficiency; the real Mugu batch was 51 species / 193,458 total
  records, meaning at least one locally-rare-but-globally-common species pushed the whole
  call onto the coarser raster path, degrading precision for every other species sharing the
  call -- including the sparse, obviously-isolated *P. epipercus* data.
- **Fix verified two ways before shipping:** (1) direct source reading confirmed the
  mechanism unambiguously; (2) a synthetic reproduction (the real 12-point *P. epipercus*
  cloud plus a synthetic 10,500-row uniform-random "common species") confirmed the warning
  genuinely fires in a batched call of this shape -- though this particular synthetic
  "common species" wasn't extreme enough to flip the final flag from `FALSE` to `TRUE`,
  meaning the real failure depends on the actual clustered shape of real GBIF data in a way
  a quick synthetic test couldn't fully reproduce. Shipped the fix anyway on the strength of
  the source-level mechanism plus the real production evidence, rather than insisting on a
  synthetic repro of the exact wrong-answer case -- the per-species-call design is strictly
  more conservative regardless (a species-crossing raster decision has no legitimate reason
  to exist in this function at all).
- **Fix:** `CoordinateCleaner::cc_outl()` now called once PER SPECIES (looping over
  `unique(global_occ$species)`) instead of once for the combined batch, so the raster-mode
  decision is scoped to each species' own record count -- exactly where `cc_outl()`'s own
  design intends it. R-level loop overhead is negligible next to the GBIF fetch itself.
- **New regression test** (`test-check_geographic_outliers.R`) mocks
  `CoordinateCleaner::cc_outl()` directly and asserts it receives exactly one species per
  call -- encodes the fix permanently without needing a slow, hard-to-construct 10,000+ row
  fixture to reproduce the raster branch itself. The original test suite (max ~17 rows
  across all fixtures) never exercised this code path at all -- clean `devtools::test()`
  gave false confidence, the same "check dataset scale before trusting synthetic tests
  generalize" lesson this ecosystem has hit before with `restore_suppressed_candidates()`
  (see `[[project_restore_suppressed_candidates_implementation]]` in the memory system) --
  worth remembering as a recurring pattern, not a one-off.
- `devtools::test()` 0 failures (483, up from 481), `devtools::check()` 0/0/0. Reinstalled to
  `~/Library/R/4.0/library`. Not yet re-run end-to-end against the real full Mugu dataset with
  the fix in place -- left for the user, since it involves real GBIF API calls and would
  overwrite the real `_geo_outlier_check.rds` checkpoint (delete it first, or it'll load the
  stale pre-fix result via the workflow's own `.use_cache()` gate).

**2026-07-20 (Sonnet 5): `check_geographic_outliers()` -- geographic-outlier detection for rare-in-bbox species**

Branch not tracked (no git repo at the monorepo root in this session's environment).
Prompted by the user's real Mugu edge case (*Pseudotolithus epipercus*, an African species
with a single errant citizen-science observation in La Jolla, `COORDINATE_REPROJECTION_
SUSPICIOUS`/`CONTINENT_DERIVED_FROM_COORDINATES`/`TAXON_ID_NOT_FOUND` in its `issues` field)
asking for a *generic* fix, not a fix for that one species -- see
`[[project_edge_case_error_taxa_design]]` in the memory system for the fuller design
conversation this implements.

- **Design arc, briefly:** considered (1) trusting GBIF's own `issues` quality flags more --
  rejected as weak/non-generalizing, those three codes describe GBIF's own geoprocessing
  history, not species-range plausibility; (2) `TaxaFetch::check_inat_range()`
  (point-in-polygon against iNaturalist's range model) -- real and reusable, but its own
  documented caveat (false negatives common for aquatic/marine taxa given low iNat observer
  effort there) makes it a poor primary signal for this ecosystem's dominant 12S/18S fish
  eDNA use case; kept as a secondary/fallback idea, not built this session; (3) a
  self-referential geographic-outlier test -- the one built. Initially scoped as "does this
  species' own already-fetched occurrence cloud contain an isolated point," but the user
  corrected the premise: `get_gbif_occurrences()`'s search is always bbox-scoped, so a local
  pull never contains the wider distribution needed to test against, and a *global*
  distance-matrix package like `CoordinateCleaner` fetching worldwide data for every
  candidate species would be needlessly expensive. Real fix: gate the (expensive) global
  fetch to only species with few *local* (bbox) records -- exactly the "singleton in our
  bounding box" case the user meant by "suspicious of singletons," not a global-record-count
  reading.
- **`CoordinateCleaner` adoption, narrowed twice:** first considered hand-rolling
  `cc_outl()`'s logic to avoid the package's `terra`/`rnaturalearth` dependency weight; a full
  function-by-function inventory (sourced from the live CRAN reference manual, not memory)
  showed those two heavy deps are needed only by `cc_sea()`/`cc_coun()`/`cc_urb()` -- exactly
  the functions that don't fit this ecosystem (marine-hostile, or redundant with
  `COUNTRY_COORDINATE_MISMATCH` already in `filter_gbif_quality()`'s `bad_issues`) -- while
  the useful functions (`cc_outl`, `cc_equ`, `cc_zero`, `cc_gbif`, plus `cc_cen`/`cc_cap`/
  `cc_inst` for a possible future session) either need no reference data or only the
  package's own small bundled tables. `Suggests`-gated the whole package rather than hand-roll
  anything. Second correction, same session: an attempt to hand-replicate `cc_zero()`'s/
  `cc_gbif()`'s buffer defaults for `filter_gbif_quality()`'s new checks hit genuinely
  conflicting numbers across sources (and a fabricated-looking GBIF-HQ coordinate from a web
  search) -- since `CoordinateCleaner` was already an accepted `Suggests` dependency for
  `cc_outl()`, there was no remaining reason to reimplement three more functions with
  constants that couldn't be verified; switched to calling `cc_equ()`/`cc_zero()`/`cc_gbif()`
  directly, using the package's own internal defaults.
- **`fetch_gbif_occurrences(geometry = NULL)`:** required for the global re-fetch step;
  confirmed via direct code read (not assumed) that this was NOT previously supported --
  `geometry` had a hard `is.character()`/length-1 validation with no `NULL` path,  even
  though the underlying `rgbif::occ_data()` call natively supports an unrestricted search.
  Relaxed the check; found and fixed a real latent bug in the same area while there --
  `.gbif_checkpoint_path()`'s `nchar(geometry)` would have returned `integer(0)` for `NULL`
  geometry, breaking its `sprintf("%d", ...)` checkpoint-filename signature on the very first
  call. `get_gbif_occurrences()` needed no change -- it has no geometry validation of its own
  and just forwards the value through.
- **`check_geographic_outliers()` (new function, `R/check_geographic_outliers.R`):** tallies
  local (bbox) record counts per species; for species below `min_local_n` (default `5L`),
  fetches that species' global distribution via `fetch_gbif_occurrences(geometry = NULL)`
  (all rare species batched into one call, reusing that function's existing chunking/retry/
  checkpoint machinery) and runs `CoordinateCleaner::cc_outl(method = "distance", tdi = 1000)`
  against the combined cloud. Adds `local_n`/`global_n_unique`/`outlier_status` columns.
  `outlier_status` is deliberately 4-valued, never a bare logical --
  `"not_tested_sufficient_local_data"` / `"insufficient_global_data"` / `"outlier"` /
  `"consistent"` -- mirroring `check_inat_range()`'s `range_status` convention, so "we
  couldn't check" is never silently folded into "we checked and it's fine." `min_occs`
  (default `7L`, matching `cc_outl()`'s own default) is re-checked explicitly against the
  real global count rather than trusted to `cc_outl()`'s own silent-pass-below-threshold
  behavior; that function's own console warning about it is suppressed (`suppressWarnings()`)
  since it's redundant with the structured status column this function already returns.
- **Testing:** all three changes covered offline. `test-fetch_gbif_occurrences.R` gained a
  `geometry = NULL` case (mocked `rgbif::occ_data`, asserts the captured argument is
  genuinely `NULL`) and a direct `.gbif_checkpoint_path()` unit test. `test-filter_gbif_
  quality.R` gained real (not mocked) `CoordinateCleaner` calls for the equal-coordinate and
  near-zero cases, `skip_if_not_installed`-guarded, plus the standard missing-package
  skip-with-message test mirroring the existing `rgbif` pattern. New `test-check_geographic_
  outliers.R` mocks only `rgbif::occ_data` (the network boundary) so the real
  `fetch_gbif_occurrences()` and real `CoordinateCleaner::cc_outl()` both run underneath --
  genuine coverage of all three `outlier_status` outcomes (an isolated point flagged, a
  too-sparse species correctly reported as untested rather than silently passed, a point
  inside its real cluster left alone), not just the plumbing between them.
  `CoordinateCleaner` (3.0.1) installed and verified loadable before running any of this.
  `devtools::document()`/`test()`/`check()` all clean: 481 expectations (up from 459), 0
  failures; 0 errors/0 warnings/0 notes. Reinstalled to `~/Library/R/4.0/library`.
- **Real call-site impact:** `filter_gbif_quality()`'s three new checks default `TRUE`, so
  every existing in-repo caller (`TaxaExpect::build_priors()`, `TaxaExpect/inst/workflows/
  generate_priors_workflow.R`, `TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R`,
  `TaxaWizard/inst/graph/snippets/taxa_to_occ.R`) now applies them automatically wherever
  `CoordinateCleaner` happens to be installed -- a behavioral default change, not just an
  addition; logged in `TaxaID/CLAUDE.md`'s breaking-changes table. `check_geographic_
  outliers()` itself is new and not yet wired into any production workflow (PtConception/
  Mugu, outside this monorepo) -- that rollout, plus a possible follow-on session adding
  `cc_cen()`/`cc_cap()`/`cc_inst()` (country-centroid/capital/biodiversity-institution
  proximity checks, scoped but not built this session), are both left open.
- **Found, not fixed (pre-existing, out of scope):** `filter_gbif_quality()`'s steps 7
  (eDNA) and 8 (species-level requirement) never reassign `n_current` after removing rows,
  so if both steps remove rows in the same call, step 8's printed "Removed N records" message
  can overcount by including step 7's removals too. Cosmetic (affects only the informational
  message, not the actual filtering result or `data` itself) and pre-existing, not touched
  by this session's own step 9, which computes its own accurate before/after count instead
  of relying on the stale variable.

**Session 148 (2026-07-09): full code + domain review (`inst/Code and Domain Review 2.Rmd`)**

Branch `main`. Full pass-by-pass code and domain review, findings and fixes recorded in
`taxafetch_review.Rmd` at the TaxaID root (following the `taxatools_review.Rmd`/
`taxatools_review_response.md` precedent, combined into one document since review and
fix happened in the same pass). Passes 1/2/5 (debris, ASCII, lintr) were already clean
from Session 131; this session re-ran Pass 6 (`check()`/`test()`), then did a deeper
Pass 7 (security + algorithm/domain correctness) than Session 131's had covered,
live-testing against real PASTA/GBIF data rather than static review alone.

- **SSRF (Medium-High, fixed).** `.download_data_table()` (`dataone_standardize.R`) and
  `.preview_one_entity()` (`dataone_preview.R`, via `.get_content_length()`/
  `.stream_n_rows()`) used `data_url` -- read verbatim from third-party EML metadata --
  as the full request URL (host and scheme included) with no restriction. Verified live
  against a real PASTA record (`edi.1290.9`): legitimate entity-download URLs
  consistently resolve to `pasta.lternet.edu`, while other `<online><url>` entries in the
  same record pointed at five unrelated external hosts, confirming the risk is real. User
  decision: add a host allowlist. New `.pasta_trusted_hosts`/`.is_trusted_pasta_url()`
  (`dataone_standardize.R`) restrict requests to `pasta.lternet.edu`/
  `pasta.edirepository.org` over https; both call sites now skip untrusted URLs with a
  clear reason instead of requesting them. **This corrects Session 131's Pass 7a note**
  ("no high-confidence vulnerabilities found") -- that pass was a static
  `/security-review` run, not a live test against real DataONE EML data, which is what
  surfaced this gap.
- **Homonym misresolution (Medium-High, fixed).** `get_keys_from_context()`'s
  `.recover_higherrank()` (the `HIGHERRANK`-result recovery path) called
  `rgbif::name_lookup()` with no kingdom/phylum context, undermining the function's own
  stated purpose of preventing cross-kingdom homonym errors (its own documented example:
  *Alaria*, a brown alga and a trematode worm). Verified live against real GBIF data for
  *Alaria* -- confirmed `name_lookup()`'s kingdom field is genuinely noisy across
  checklist datasets, and that GBIF's backbone can even collapse distinct kingdoms to the
  same `nubKey` regardless (a GBIF data-quality limitation, not fixable here, now
  disclosed in the function's own roxygen). User decision: filter lookup hits by kingdom
  before voting. `.recover_higherrank()` gained a `context` parameter; falls back to the
  previous unfiltered behavior when no kingdom is available. `matchType =
  "LOOKUP_RECOVERED"` (a real return value the roxygen previously omitted) added to the
  documented enum and review-advice list.
- **BioTime NA-vs-absent conflation (Medium, fixed).** `read_biotime_study()` coded
  `occurrenceStatus` as `"absent"` whenever `ABUNDANCE`/`BIOMAS` was missing or failed
  `as.numeric()` coercion, not just when a value was validly zero -- risked treating
  malformed source data as a confirmed non-detection. Now `NA` when neither field parses;
  `"absent"` only for an explicit valid zero.
- **eDNA filter over-broad (Low-Medium, fixed).** `filter_gbif_quality()`'s
  `exclude_edna` pattern included generic `"bulk sample"`/`"water sample"` phrases that
  could over-exclude legitimate non-eDNA presence data; narrowed to the three
  eDNA-specific terms (`edna`, `environmental dna`, `metabarcod`).
- **Doc-only clarifications:** `make_bbox_wkt()`'s km-conversion reference didn't
  disclose it only holds along the north-south axis (`cos(latitude)` shrinkage
  east-west); `get_gbif_occurrences()`'s `rank_filter = "species"` default's exact-match
  behavior (drops `SUBSPECIES`/`VARIETY`/`FORM`) wasn't documented -- assessed as
  plausibly intentional (every existing caller already expects species-rank-only output)
  rather than changed behaviorally.
- **Zip-slip (Low, hardened defensively).** `.read_gbif_zip()` gained an entry-path check
  before `unzip()` -- `zip_path` is GBIF's own trusted API output today, but nothing
  downstream re-validates that trust.
- Test coverage: 25 new tests across `test-dataone_standardize.R` (+6),
  `test-dataone_preview.R` (**new file** -- this package's `dataone_preview.R` had zero
  test coverage before this session; `preview_dataone_occurrences()` itself is still
  untested beyond the new guard, a pre-existing gap out of scope here), `test-
  get_keys_from_context.R` (+3, synthetic mixed-kingdom fixture -- real GBIF *Alaria*
  data was tried first but is too noisy to isolate the narrowing logic cleanly),
  `test-biotime_fetch.R` (+2), `test-filter_gbif_quality.R` (+1).
- `.lintr`: added an `object_usage_linter` exclusion for `dataone_preview.R:544`
  (`.is_trusted_pasta_url()` cross-file call, same false-positive class as the existing
  `get_gbif_occurrences.R:217` exclusion, confirmed via `codetools::checkUsage()` on the
  loaded namespace); updated `get_gbif_occurrences.R`'s `commented_code_linter` line
  number (293 -> 300, drifted by this session's own doc edit above it -- see the
  pre-review-checklist memory's Pass 5 note on exclusion line-number drift).
- `devtools::document()`/`test()`/`check()` all clean: 459 expectations (up from 434),
  0 failures; 0 errors, 0 warnings, 0 notes.

**Session 140 (2026-07-06): fetch_occurrences_by_taxon() -- taxon-centric batched GBIF fetch**

Branch `main`. Implements the general-fix scope from
`ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md`, confirmed with the user
over the narrow fix (union just one multi-site observation's own sites) after re-verifying
Phase 6's live RStudio run had completed successfully post-Session-139's Section 3/5 fix.

- `fetch_occurrences_by_taxon()` added (`R/fetch_occurrences_by_taxon.R`): takes a
  `taxon_geometry_map` (one row per (site, candidate taxon) pair -- `taxon_key` + `geometry`
  WKT), unions each taxon key's own geometry via `sf::st_union()`, then (`combine_shared_geometry
  = TRUE`, default) combines taxon keys whose resulting unioned geometry is byte-identical into
  one multi-key `get_gbif_occurrences()` call. This is a pure call-grouping layer -- neither
  `get_gbif_occurrences()` nor its backends are touched. 22 new tests
  (`test-fetch_occurrences_by_taxon.R`), fully offline (`get_gbif_occurrences()` mocked via
  `local_mocked_bindings()`), covering input validation, same-taxon-overlapping-geometry union,
  different-taxa-same-geometry combination, `combine_shared_geometry = FALSE`, disjoint
  geometry (no wasted combination), duplicate-row and NA-row cleaning, and param forwarding.
- `stack_occurrences()`: added a `gbifID` dedup step (drops rows with a duplicated non-`NA`
  `gbifID`, keeps first) -- defense-in-depth per the reentry prompt's "worth doing regardless"
  recommendation. Checked first whether this was still needed given
  `TaxaMatch::standardize_match_data()` might already cover it: confirmed that function
  standardizes classifier match records (DNA/BLAST, image, acoustic -- the
  TaxaMatch -> TaxaLikely -> TaxaAssign chain) and has zero row-level dedup logic of its own; it
  is not in the GBIF occurrence -> `TaxaExpect::build_priors()` -> `model_data` path at all, so
  the gap was real, not stale. Confirmed no dedup existed anywhere in that path
  (`get_gbif_occurrences()`, `filter_gbif_quality()`, `stack_occurrences()` all checked
  directly) before adding it. 3 new tests in `test-stack_occurrences.R`.
- `inst/TaxaID_Workflow_Template_TEST.R` Section 3 restructured into the two-pass split the
  reentry prompt identified as a hard prerequisite (the old single-pass loop interleaved
  box-definition and fetching per group, making a whole-scope taxon union impossible): Pass 1
  defines every `spatial_group_id`'s search geometry with no fetching (interactive polygon for
  multi-member groups, automatic per-site bbox for single-observation groups), guarding a
  cancelled gadget immediately; Pass 2 builds one taxon_key/geometry map spanning both branches
  and fetches once via `fetch_occurrences_by_taxon()`. The escalation ladder (genus -> family ->
  order for single-observation candidates with zero hits) is now decided per starting genus
  rather than per site -- sites sharing a candidate genus already share the same escalation
  path, and this session worked through why a nonzero result anywhere in that genus's unioned
  search area means real local data exists for it, so no per-site spatial containment check is
  needed to decide whether an individual site would have escalated on its own. Zero-hit
  detection matches on the taxonomic text column (`genus`/`family`/`order`) rather than a
  `*Key` column, since not every rank has a corresponding key column in
  `.gbif_standard_columns()` (no `orderKey`) -- this makes the check rank-agnostic with no
  extra columns needed. Verified via an isolated logic test against the real
  `TaxaID_test_site_table.rds`/`TaxaID_test_BLAST.rds` checkpoints from Session 139's live run
  (mocking `get_keys_from_context()`, `escalate_taxonomic_rank()`, and `get_gbif_occurrences()`,
  since the real multi-member group in that data requires the interactive
  `define_search_polygon()` gadget): confirmed the 4-member cluster's family keys combine into
  one call (not four), a zero-hit genus is escalated and successfully refetched at its family
  rank in round 1, and the final `gbif_occurrences` assembles correctly across both rounds.
- `devtools::document()` + `devtools::test()` (434 expectations, 0 failures, 4 pre-existing
  warnings, 2 pre-existing skips) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all
  clean.
- **Live-verified by the user in a real RStudio run, same session:** 3 spatial groups (2
  multi-member, 1 singleton) -- Pass 1 correctly drew search areas for the 2 multi-member
  groups and computed an automatic bbox for the singleton; Pass 2's round 0 found 4 distinct
  taxon keys (2 family, 2 genus) and issued only **2** GBIF queries, confirming the
  same-geometry-taxa combination worked on real data, not just the mocked isolated test.
  226 + 10,576 species-rank records returned; `gbif_occurrences` came back with the expected
  31-column standard schema. One cosmetic artifact noted and explained: `class` came back
  `<lgl>` (all `NA`) rather than `<chr>` -- confirmed by the user to be a known GBIF backbone
  gap for bony fishes (Actinopterygii/Actinopteri routinely missing a populated `class`
  field), not a fetch bug; the logical-vs-character type is just `get_gbif_occurrences()`'s
  pre-existing NA-fill behavior for an entirely-absent column, unrelated to this session's
  changes.
- **Not done this session:** characterizing GBIF's actual WKT-complexity ceiling (documented
  as a known, non-silently-masked limitation on `fetch_occurrences_by_taxon()` instead, per the
  reentry prompt's own item 4); cross-round query merging (an escalated taxon key can be
  re-queried in a later round at a different geometry than an earlier round's use of the same
  key, which is correct but not maximally efficient -- the final `gbifID` dedup step is the
  safety net for any resulting overlap, not a further optimization).

**Session 134b (2026-07-04): define_search_polygon() and group_observations_by_bbox() moved out**

Follow-up to Session 134 below, after the user reviewed that session's implementation and
raised package-placement questions before committing (see
`ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md`). Resolution: the only
generalization `define_search_polygon()` needed to serve both a search-area purpose (this
package) and a spatial-group purpose (`TaxaMatch::group_observations_by_bbox()`) was letting
its `points` overlay be colored by an existing group column, plus letting a previously drawn
polygon be reopened for reshaping (`init_polygon` param) -- neither changes the core
interaction model, so one shared gadget covers both rather than two divergent ones.

- `define_search_polygon()` moved to **TaxaTools** (`R/define_search_polygon.R` there),
  with the `group_col` and `init_polygon` additions. Call it as
  `TaxaTools::define_search_polygon()` from this package now (see the GBIF pipeline diagram
  above). `make_bbox_wkt()`'s cross-reference updated accordingly.
- `group_observations_by_bbox()` moved to **TaxaMatch** (it operates on
  `TaxaMatch::build_site_table()`'s output -- a spatial-grouping concern, not a fetch
  concern) and was substantially reworked there (default-to-`observation_id` behavior,
  last-drawn-wins overlap rule, end-of-loop review/edit/delete step, new
  `assign_spatial_group()` manual-assignment helper). See TaxaMatch/CLAUDE.md's Session
  134b note for the full design.
- `shiny`/`miniUI`/`leaflet` dropped from this package's `DESCRIPTION` Suggests (moved to
  TaxaTools's Suggests instead) -- nothing in this package calls those namespaces directly
  anymore.
- Two workflow scripts fixed to call the new location:
  `inst/TaxaID_Workflow_Template.R` and `inst/TaxaID_Workflow_Template_TEST.R`
  (`TaxaFetch::define_search_polygon()` -> `TaxaTools::define_search_polygon()`).
- `devtools::document()` + `devtools::test()` (407 expectations, 0 failures, 4 pre-existing
  warnings/2 skips) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean after
  the move.

**Session 134 (2026-07-03): group_observations_by_bbox() -- automatic spatial grouping**

*(Historical record -- this function and `define_search_polygon()` moved out of this
package in Session 134b, see that note above. Kept here for the original design
rationale, which still mostly applies at the new location.)*

Branch `single-observation-pipeline`. Implements the "automatic grouping" design from
`ecosystem_docs/REENTRY_PROMPT_session134_single_observation_pipeline.md`'s Thread 2 /
step 3, with one deliberate deviation from that prompt's original spec: **observations
outside every drawn group polygon (or all of them, if the user draws no polygon at all)
are placed in their own single-observation spatial group, not dropped.** The original
design (written mid-session before the user weighed in) called for dropping them with
an alert; the user redirected this before implementation started -- dropping silently
discards data the pipeline can still handle via the single-observation escalation path,
whereas keeping it as its own group costs nothing and is strictly more useful. A
`message()` always explains the reclassification (distinct wording for "some points
outside every box" vs. "no box drawn at all").

**Naming, settled before commit:** the column/param started out as `group_id`/`group_map`
with a special `"independent_<id>"` string for unboxed observations. The user flagged
this before committing: "group" is already used for unrelated concepts elsewhere in the
ecosystem (`TaxaAssign::assign_taxa_llm()`'s `context_group`/`.build_group_map()` for
LLM-batching context groups; `TaxaExpect` also uses "group" for taxonomic grouping), and
"cluster" -- the other candidate -- is *already taken* by `TaxaLikely`'s acoustic
calibration work (`cluster`/`true_cluster`/`CLUSTER_MAP` = confusable-species groups, a
completely different concept). Renamed to `spatial_group_id`/`spatial_group_map`
throughout, and dropped the separate `"independent_*"` naming convention entirely per the
user's direction: a single-observation spatial group isn't a different kind of thing, so
it gets a `spatial_group_id` with the exact same `"spatial_group_<n>"` shape as any other
group (continuing the same sequential numbering), just with one member. This cost nothing
downstream -- `update_prior_from_consensus()`'s eligibility check already worked by
counting how many observations share a `spatial_group_id` (`table()` + `>= 2L`), never by
pattern-matching the id string, so removing the special prefix required no logic changes,
only renaming.

- `define_search_polygon()`: added `points` param (data frame with `lat`/`lng`),
  overlaid as small non-interactive `addCircleMarkers()` so the user can see the actual
  observation cloud while drawing. Backward compatible (`NULL` default, no behavior
  change when omitted).
- `group_observations_by_bbox()` (new, `R/group_observations_by_bbox.R`): loops
  `define_search_polygon()`, re-centring each call on the bounding box of whatever
  observations are still ungrouped (via `.bbox_center_radius()`), until the user cancels
  the gadget (signals "done drawing groups" -- does not discard groups already
  recorded). Final assignment via `.assign_spatial_groups_from_polygons()`:
  point-in-polygon test using `sf::st_within()` (same pattern already used in
  `check_inat_range()`), first-match-wins draw order, singleton-group reclassification
  with message as described above. Both internal helpers are pure (no Shiny dependency)
  and fully unit-tested -- the interactive loop itself is not (same testing boundary as
  `define_search_polygon()` already has, gated by `interactive()`).
- Consequence for `TaxaAssign::update_prior_from_consensus()`: single-observation spatial
  groups produced here (including the newly-singleton unboxed ones) must never contribute
  to or receive that function's consensus-based prior boost -- implemented this same
  session via that function's new `spatial_group_map` param (see `TaxaAssign/CLAUDE.md`).
- 15 new tests (`test-group_observations_by_bbox.R`), fully offline. `devtools::test()`:
  422 expectations, 0 failures (4 warnings/2 skips pre-existing). `devtools::check()`:
  0 errors, 0 warnings, 0 notes.
- **Not done this session** (see `ecosystem_docs/REENTRY_PROMPT_session134...` follow-up
  for the next session): wiring `spatial_group_id` into the actual occurrence/reference
  fetch calls (pooled fetch for multi-member groups vs. per-observation taxonomic
  escalation for single-observation groups) -- the escalation ladder itself (genus ->
  family -> order) was only validated empirically in ad hoc session scripts last session,
  not yet built as a reusable function anywhere in the ecosystem.

Sessions 26–80 archived in ecosystem_docs/session_notes/TaxaFetch_sessions.md.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- `combine_occurrence_sources()` dead code deleted (superseded by `rename_cols()` +
  `stack_occurrences()` since Session 19). File + Rd deleted; `@seealso` refs updated.
- 5 stale inst/ files deleted: `TaxaFetch_workflow copy.R`, `migrate_prompt_api.R`,
  `habitat_scheme_workflow.R`.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaFetch-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools),
  WERC review integration. Deferred: `call_api_pdf()` generic (multimodal/PDF
  call cannot be trivially unified with `call_api`; tracked as TODO in TaxaID/CLAUDE.md).

**Session 86 (2026-05-23)**
- `screen_pdf_structure()`: `llm_fn` fallback updated from `call_anthropic_api` to
  `TaxaTools::call_api`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).

**Session 87 (2026-05-26)**
- `call_api_pdf()` generalized to support any vision-capable LLM provider.
  Replaces hardcoded Anthropic HTTP block with `TaxaTools::call_api(images = page_images)`.
  New params: `provider`, `tier`, `base_url`; `model` and `api_key` now default NULL
  (resolved by `call_api()`). Clears TODO from Sessions 83-85.
  Providers: Anthropic (claude-sonnet-4-6), Gemini (2.5 Flash/Pro), OpenAI (GPT-4o),
  Ollama vision models (llava-llama3). PDF rendering (.render_pdf_pages) unchanged.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 105 (2026-06-10)**
- `fetch_gbif_occurrences()`: HTTP 503 "Service Unavailable" errors now retried with
  exponential backoff (5/10/20/40 sec) in addition to existing 429 retry (30/60/120/240 sec).
  Previously 503s were silently skipped, causing all keys to fail during an outage.
- **Abort-on-exhaustion policy**: any key that exhausts all retries now causes an
  immediate `stop()` rather than silently skipping. Skipping would produce
  session-inconsistent results (different keys processed on different runs).
- **Checkpoint / resume**: `cache_dir` parameter added (default:
  `tools::R_user_dir("TaxaFetch", "cache")`). Progress saved after each completed
  chunk. On abort, re-running with the same arguments resumes automatically.
  Checkpoint filename encodes the call signature (key count, key sum, geometry
  length, year range, limit) so changed parameters start fresh without collisions.
  `.gbif_checkpoint_path()` internal helper builds the deterministic path.
- `.fetch_chunk()` return value changed from bare data.frame/NULL to
  `list(records, aborted)` to propagate abort signal to the outer loop cleanly.
- Diagnosis: GBIF API returned `"HTTP 503 Backend fetch failed"` (request XID in
  response body) for all keys during a confirmed infrastructure outage; confirmed
  by raw `curl` to the GBIF occurrence search endpoint.
- `devtools::test()` (test-fetch_gbif_occurrences.R): 18 pass, 0 fail, 2 skip.
  Tests updated to use `out$records`, and resilience test updated to expect
  `stop()` (not warning + partial results) on key failure.

**Session 114 (2026-06-22)**
- `filter_gbif_quality()`: `exclude_absent = TRUE` parameter added (new filter step 2, before basis-of-record).
  Removes records where `occurrenceStatus = "ABSENT"` — explicit non-detections from systematic surveys.
  These are present in GBIF downloads and must not be used as presence data for priors or occurrence modelling.
  Root cause: GBIF `occurrenceStatus = "ABSENT"` rows were inflating occurrence counts (e.g. Haliotis corrugata).
  Filter logic: `is.na(occurrenceStatus) | toupper(trimws(occurrenceStatus)) != "ABSENT"` (retains NA rows).
  `"occurrenceStatus"` added to `utils::globalVariables()`. `@param exclude_absent` roxygen doc added.
  Filter order updated: coordinates → absent occurrences → basis → issues → uncertainty → precision → eDNA → species.

**Session 111 (2026-06-16)**
- `define_search_polygon()` added: interactive Shiny gadget for defining custom WKT search polygons.
  Replaces `make_bbox_wkt()` when a non-rectangular region is needed (e.g. coastal transects where
  a square bbox wastes download bandwidth over open ocean / inland areas).
- Signature: `define_search_polygon(lat, lon, radius_deg, tile = "Esri.OceanBasemap")`.
- Initial square: 4 corner markers (SW→SE→NE→NW, counter-clockwise, IDs 1–4).
- Vertex dragging via `leaflet::addMarkers(options = markerOptions(draggable = TRUE))` — NOTE:
  `addCircleMarkers(draggable = TRUE)` does NOT work (Leaflet.js `L.CircleMarker` limitation).
- Add Point: finds longest segment by squared Euclidean distance, inserts new draggable vertex at midpoint.
- Remove Last Point: removes highest `id > 4` row; protects original 4 corners.
- Returns WKT `POLYGON ((lng lat, ...))` string; ring closed (first == last vertex).
- Requires `shiny`, `miniUI`, `leaflet` (checked at runtime with informative error if missing).
- Tested against Mugu workflow coordinates via `devtools::load_all()`.

**Session 107 (2026-06-11)**
- `download_gbif_occurrences()` added: async GBIF bulk download for large key sets (100s–1000s).
  Root cause of existing 429 rate limits: `fetch_gbif_occurrences()` hit key 511/1598 before abort.
- Critical bug fixed during development: GBIF download API `taxonKey` predicate is exact-match only
  (not hierarchical like `occ_data()`). Fix: `pred_or(pred_in("familyKey",...), pred_in("genusKey",...),
  pred_in("speciesKey",...), pred_in("taxonKey",...))`. Without this, family-level queries returned
  only family-rank-identified records (no species data).
- SIMPLE_CSV format notes: `familyKey`, `genusKey` etc. are DWCA-only and absent from SIMPLE_CSV —
  hierarchy validation removed. The `issue` (singular) → `issues` (plural) rename for
  `filter_gbif_quality()` compatibility is implemented in this function (see the
  `simple_csv_renames` block after import) and works correctly. **Correction (Session 131):**
  a Session 129 note here previously claimed this rename "was never actually implemented" and
  that the column comes out as `issue`, not `issues` — that claim was wrong. Re-verified directly
  against a real cached SIMPLE_CSV file (`.read_gbif_zip()` + the rename block, run against a real
  download zip): before the rename block runs, the column is `issue`; after, it is `issues`. The
  code has been unchanged since this function's first commit. The false claim led
  `get_gbif_occurrences()` to carry a redundant (harmless, but dead) second rename — removed in
  Session 131.
- `filter_gbif_quality()`: `require_species` parameter added (filter 7). Needed because GBIF returns
  all ranks within a queried family/genus, including genus-only records with no species value.
- `data.table` added to DESCRIPTION Suggests; `quote=""` in fread suppresses spurious quoting
  warnings on GBIF TSV data.
- User-facing messaging improved: cache directory printed at start; "still working" message after
  rgbif "succeeded" output (which misleadingly appears before import completes).

**Session 129 (2026-07-03): get_gbif_occurrences() unified entry point**
- `R/get_gbif_occurrences.R` added — formalizes the manual dispatch pattern the Layer-1
  tutorial (below) already documented informally: picks `fetch_gbif_occurrences()` vs
  `download_gbif_occurrences()` by `key_threshold` (default 50), standardizes both paths
  to one column contract, and defaults to species-rank-only output (`rank_filter =
  "species"`, post-fetch only — neither GBIF API has a rank predicate to filter
  server-side). Neither `fetch_gbif_occurrences()` nor `download_gbif_occurrences()` is
  modified. **Correction (Session 131):** this entry originally said the wrapper "fixes
  the issue/issues column-name mismatch on the download path" — `download_gbif_occurrences()`
  already renames it correctly on its own (see that function's Session 131 correction
  above); there was no mismatch to fix. `get_gbif_occurrences()`'s redundant second
  rename was removed in Session 131; the wrapper's `select_cols` translation (`issues`
  → `issue`, needed because `select_cols` matches SIMPLE_CSV's native column names at
  import time, before the rename happens) is unaffected and still correct.
- **Known pre-existing issue found while running a final test pass, NOT related to the
  above:** `tests/testthat/test-build_iucn_scheme.R`, `test-llm_api_utils.R`, and
  `test-parse_hierarchical_habitat_response.R` all test functions that moved to
  TaxaHabitat/TaxaTools in the Session 28 package split and no longer exist in this
  package — they've been failing since before any tracked git history. **Deleted this
  session (confirmed by user) — see follow-up note below.**

**Session 130 (2026-07-03): stale test files deleted; check()-vs-test_dir() root-caused**
- Deleted the 3 stale test files noted above. `devtools::test()`: 0 failures, 0 errors.
  `devtools::check()`: 0 errors, 0 warnings, 0 notes.
- While re-verifying, a bare `testthat::test_dir("tests/testthat")` run (not
  `devtools::test()`) flagged a 4th apparently-stale file, `test-biotime_fetch.R`
  (`could not find function "read_biotime_study"`) — a false alarm. `read_biotime_
  study()` is real and correctly exported (`R/biotime_fetch.R`); bare `test_dir()`
  doesn't `load_all()`/attach the package first, so it can spuriously report missing
  functions. This is almost certainly the explanation for the earlier `check()`-vs-
  `test_dir()` discrepancy noted above — `devtools::check()`'s bundled test run does the
  equivalent of `load_all()` first, which is why its summary was trustworthy the whole
  time. Root-caused; written into the pre-review-checklist memory as the general rule
  (always use `devtools::test()`, never bare `test_dir()`).

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/fetch_occurrences_workflow.R` added — teaching-oriented, fully namespaced,
  runnable top to bottom on a built-in tutorial example (genus *Gadus*, North Atlantic).
  Demonstrates `get_keys_from_context()` → GBIF two-path dispatch (`fetch_gbif_occurrences()`
  vs. `download_gbif_occurrences()`, threshold at ~50 keys) → `filter_gbif_quality()` →
  `stack_occurrences()`. Narrow/broad-marker VARIANT A/B preserved from the old monolithic
  templates; broad-marker sampling_group assignment left as a TODO pointer (see
  `ecosystem_docs/LAYER1_WORKFLOWS.md`), not inline code.
- Live-tested against real GBIF (part of a 5-package full-chain smoke test through TaxaFlag).
  Full design rationale, cross-package continuity conventions, and bugs found/fixed during
  testing are in `ecosystem_docs/LAYER1_WORKFLOWS.md` — see that file, not this one, for the
  complete record.

**Session 131 (2026-07-03): pre-code-review cleanup, all 9 checklist passes**

Full pass-by-pass cleanup ahead of TaxaFetch's scheduled code review (continuing from
Session 130's stale-test-file deletion). `devtools::test()`: 407 expectations, 0 failures,
0 errors (2 expected skips, 4 expected warnings from tests deliberately checking warning
messages). `devtools::check()`: 0 errors, 0 warnings, 1 NOTE (`unable to verify current
time` -- an environment/clock artifact, not code-related).

- **Pass 1 (debris):** deleted `inst/Habitat_assign_workflow.R` (called 5 functions moved
  to TaxaHabitat in the Session 28 split, same stale-debris pattern as the 3 test files
  Session 130 deleted) and `inst/all_occurrences.rds` (806KB untracked leftover, unreferenced
  by any script). Removed a dead `.Rbuildignore` entry for a file already deleted Session 82.
- **Pass 2 (ASCII):** swept all of `R/` for non-ASCII characters (em-dashes, en-dashes,
  arrows, box-drawing separator lines) across 9 files -- none had been checked since before
  this session; all replaced with ASCII equivalents, no semantic changes.
- **Pass 3 (naming) -- major correction:** re-verified the Session 129 claim that
  `download_gbif_occurrences()` doesn't rename SIMPLE_CSV's `issue` column to `issues`.
  **That claim was wrong.** Tested the actual rename block directly against a real cached
  GBIF SIMPLE_CSV zip: the rename works correctly, and has been in place unchanged since the
  function's first commit (2026-06-11) -- there was never a version without it. Corrected
  the false claim everywhere it had propagated: this file's Session 107/129 notes, and
  `get_gbif_occurrences()`'s roxygen `@details` (which described fixing a "known asymmetry"
  that didn't exist). Removed `get_gbif_occurrences()`'s now-provably-dead redundant second
  rename block (its guard condition was never true) and the now-stale
  `utils::globalVariables("issue")` declaration alongside it. Also renamed 3 ALLCAPS
  module-level constants in `dataone_occurrence_search.R` (`.PASTA_SOLR`, `.PASTA_META`,
  `.DEFAULT_BIO_KEYWORDS` → `.pasta_solr_url`, `.pasta_meta_url`, `.default_bio_keywords`)
  and one over-length internal helper name in `pdf_characterize.R`
  (`.non_occurrence_legend_keywords` → `.non_occurrence_keywords`, was 31 chars) for
  lintr's `object_length_linter` and ecosystem naming consistency.
- **Pass 4 (doc completeness):** `check_inat_range()` was the only exported function
  missing `@examples` -- added a `\dontrun{}` example (requires `INAT_API_TOKEN`).
  Also found and removed a stale "withr dependency" note in this file's "Key Notes for
  Claude" and "Key Dependencies" sections -- no test in the package uses `withr`, and it
  was never actually added to `DESCRIPTION` Suggests despite the note's claim.
- **Pass 5 (lintr):** created `.lintr` (line length 120, UTF-8). Fixed for real:
  10 `brace_linter` (inconsistent if/else brace usage), 10 `semicolon_linter` (compound
  statements split to separate lines in `dataone_occurrence_search.R`), 3
  `object_name_linter` (the constant renames above), 1 `object_length_linter` (the helper
  rename above), 8 `line_length_linter` (long `stop()`/`warning()`/`message()` strings
  split via `paste0()`), 2 `trailing_blank_lines_linter`, 1 `trailing_whitespace_linter`,
  2 `return_linter` (`return(NULL)` → bare `NULL` in `tryCatch` error handlers). Added
  `.lintr` `exclusions` for ~60 `commented_code_linter` false positives (legitimate
  top-of-file "workflow mirror" example comments and short English phrases that happen to
  parse as valid R, e.g. `# ID / citation` as a division expression) and one
  `object_usage_linter` false positive in `get_gbif_occurrences.R` (confirmed via
  `codetools::checkUsage()` against the loaded namespace that the flagged
  `exclude_absent = exclude_absent` forwarding is real and correct; `lint_package()`'s
  per-file static analysis just doesn't resolve the cross-file call).
- **Pass 6:** re-ran `devtools::document()`/`test()`/`check()` after all edits above --
  still clean.
- **Pass 7a (security):** `/security-review` found no high-confidence vulnerabilities.
  All external API calls (GBIF, DataONE, OpenAlex, iNaturalist, LLM providers) use
  environment-variable credentials, trusted per this project's security model.
- **Pass 7b (algorithm/domain correctness):** a 6-angle `/code-review` pass (line-by-line,
  removed-behavior audit, cross-file tracer, reuse, simplification/efficiency,
  altitude/conventions) over the full session diff found: the stale `globalVariables`
  declaration (fixed, see Pass 3 above); the new `test-download_gbif_occurrences.R`
  reimplementing an env-var save/restore dance for a credential-missing test when passing
  empty-string args directly (matching `test-check_inat_range.R`'s existing convention) was
  simpler -- rewritten; the same test's synthetic-zip fixture builder used an unnecessary
  `setwd()`/`on.exit()` dance and depended on an external `zip` binary via `utils::zip()` --
  rewritten using `zip::zip()`'s `root` argument (added `zip` to `DESCRIPTION` Suggests),
  which is both simpler and removes the external-binary portability risk; a hand-rolled
  `runif()`-based temp-directory-uniqueness scheme was replaced with `tempfile()`. Also
  added `tests/testthat/test-get_gbif_occurrences.R` (9 tests) -- `get_gbif_occurrences()`
  had zero test coverage of its own before this session, including of the exact
  column-name-translation logic (`select_cols_dl`) that the Pass 3 correction above was
  about; this closes that gap so the false claim's root cause (an unverified assumption,
  never pinned down by a test) can't recur silently.
- **Cross-package fallout from the `inst/Habitat_assign_workflow.R` deletion:** two review
  agents independently found the deletion left 5 dangling path references in *other*
  packages (found via full-monorepo grep, confirmed with the user before fixing, since it
  touches files outside TaxaFetch): `TaxaID/README.md`'s workflow-script table, both the
  diagram and prose in `ecosystem_docs/ECOSYSTEM_WORKFLOW.md`, a comment in
  `TaxaExpect/inst/TaxaExpect_workflow.R` (two spots), and a comment in
  `TaxaWizard/inst/graph/snippets/occ_to_std.R`. All 5 repointed to TaxaHabitat's current
  script, `TaxaHabitat/inst/workflows/assign_habitat_workflow.R`.
