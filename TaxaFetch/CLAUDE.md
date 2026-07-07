# CLAUDE.md — TaxaFetch
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-06 (Session 140 -- fetch_occurrences_by_taxon() added: taxon-centric
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
| `get_keys_from_context()` | Resolve hierarchy dataframe to GBIF usage keys | Complete | R/get_keys_from_context.R |
| `fetch_gbif_occurrences()` | Download occurrence records for GBIF taxon keys via GBIF occurrence API. `max_retries` (default 4) applies exponential backoff on HTTP 429 (30/60/120/240s) and HTTP 503 (5/10/20/40s). Any exhausted retry aborts immediately (no silent skipping). `cache_dir` (default: user cache dir) saves per-chunk checkpoints; re-running with same args resumes automatically. **Use for ≤~50 keys; no GBIF account required.** See `download_gbif_occurrences()` for large key sets. | Complete | R/fetch_gbif_occurrences.R |
| `download_gbif_occurrences()` | Async bulk download via GBIF download API — use for large key sets (100s–1000s) to avoid HTTP 429 rate limits. Submits `occ_download()` job; polls until complete; downloads zip to `cache_dir`. **Requires GBIF account** (`GBIF_USER`/`GBIF_PWD`/`GBIF_EMAIL` in `~/.Renviron`). Key design notes: (1) uses rank-specific OR predicate (`familyKey`/`genusKey`/`speciesKey`/`taxonKey`) because download API `taxonKey` is exact-match only, not hierarchical; (2) `limit` is per-key (group_by taxonKey + slice_head); (3) signature-based cache — re-runs with same params skip GBIF wait and load from cached zip; (4) `select_cols` trims SIMPLE_CSV to needed columns at fread time (~10× size reduction); (5) SIMPLE_CSV `issue` column renamed to `issues` for `filter_gbif_quality()` compatibility — implemented and verified working (Session 131; a Session 129 note here previously claimed otherwise, incorrectly); (6) `basis_keep` applied server-side. `bibliographicCitation` = GBIF download portal URL (avoids `occ_download_meta()` hang). Called directly, `select_cols` should reference SIMPLE_CSV's native `issue` (singular) name if customized — the function renames the output column to `issues` regardless. | Complete | R/download_gbif_occurrences.R |
| `get_gbif_occurrences()` | **Session 129 — recommended entry point**, not a replacement for the two functions above (neither is modified). Picks `fetch_gbif_occurrences()` vs `download_gbif_occurrences()` by `key_threshold` (default 50, matching both functions' own documented guidance and the manual dispatch pattern the Layer-1 tutorial already used) and standardizes both paths to one column contract. `rank_filter = "species"` (default) is a post-fetch filter only — neither GBIF API exposes a taxonomic-rank predicate to filter server-side. `columns = "standard"` (default) / `"all"` / custom vector. `familyKey`/`genusKey` are `NA` on the download path — SIMPLE_CSV doesn't carry them at all, not fixable by this wrapper. Translates the wrapper's canonical `issues` column name back to SIMPLE_CSV's native `issue` when building `select_cols` for the download path (needed because `select_cols` matches at import time, before `download_gbif_occurrences()`'s own rename runs) — this is the only issue/issues handling the wrapper does; see `download_gbif_occurrences()`'s entry above for the Session 131 correction to a false "cross-path bug" claimed here previously. | Complete | R/get_gbif_occurrences.R |
| `fetch_occurrences_by_taxon()` | **Session 140 — taxon-centric batched fetch.** Groups a fetch scope (one row per (site, candidate taxon) pair: `taxon_key` + `geometry` WKT) by taxon key instead of by observation/site: unions each taxon key's own geometry via `sf::st_union()` (dissolving the duplicate-record risk when two site boxes for the same taxon overlap), then combines different taxon keys that end up with an identical unioned geometry into one multi-key `get_gbif_occurrences()` call (`combine_shared_geometry = TRUE`, default). Neither `get_gbif_occurrences()` nor its own backends are modified — this is a pure call-grouping layer above it. Does not expose `rgbif`'s `geom_big`/`geom_size`/`geom_n` WKT-complexity escape valve and does not characterize GBIF's real WKT-size ceiling (documented as a known limitation, not silently masked). See `ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md` for the full design discussion this implements. | Complete | R/fetch_occurrences_by_taxon.R |
| `filter_gbif_quality()` | Filter GBIF records by quality criteria; default `max_coord_uncertainty = 500` m; NA retained. `exclude_absent = TRUE` removes records where `occurrenceStatus = "ABSENT"` (explicit non-detections from systematic surveys — must not be used as presence data). `require_species = FALSE` (set TRUE when querying by family/genus key — GBIF returns all ranks within the taxon including genus-only records that lack a species value). Filter order: coordinates → absent occurrences → basis of record → issue codes → coordinate uncertainty → decimal-place precision → eDNA → species-level requirement. | Complete | R/filter_gbif_quality.R |
| `report_fetch()` | Generate `report_section` summarizing occurrence fetch results for `assemble_report()` | Complete | R/report_fetch.R |
| `read_biotime_study()` | Read a BioTime study CSV into a standardized occurrence tibble | Complete | R/biotime_fetch.R |
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
7. **`check_inat_range()`** — TODO (Session 117). Implementation prompt: `TaxaFetch/inat_range_prompt.md`. Checks dark diversity taxa (eDNA detections absent from occurrence database) against iNaturalist geomodel range polygons. Returns `in_range`, `range_status`, `n_observations`, `iconic_taxon_name`. Rate-limit only the taxa API step (not S3 GeoJSON fetches). Requires `sf` in Imports. Downstream: `adjust_inat_range_priors()` in TaxaAssign (planned) applies prior boost for `in_range = TRUE` taxa above the dark diversity floor.
8. **`score_image_inat()`** — TODO (Session 117). Implementation prompt: `TaxaFetch/inat_cv_api_prompt.md`. Submits image to iNaturalist CV API; returns ranked taxon suggestions with `vision_score`, `combined_score`, `freq_score`, `geo_prior_weight` (= combined/vision ratio — iNat's continuous location prior weight). Enables image-based match objects as input to TaxaAssign. Requires `httr` in Imports (verify). `geo_prior_weight` is the continuous analogue of `check_inat_range()` binary range signal, for the image classification pathway.

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-fetch_gbif_occurrences.R | `fetch_gbif_occurrences()` | Mocked rgbif; covers 429 retry/backoff |
| test-filter_gbif_quality.R | `filter_gbif_quality()` | Fully offline |
| test-get_keys_from_context.R | `get_keys_from_context()` | Mocked rgbif |
| test-make_bbox_wkt.R | `make_bbox_wkt()` | Fully offline |
| test-stack_occurrences.R | `stack_occurrences()` | 22 tests; fully offline |
| test-report_fetch.R | `report_fetch()` | Fully offline |
| test-biotime_fetch.R | `read_biotime_study()` | Fully offline |
| test-dataone_standardize.R | `fetch_dataone_occurrences()` | Mocked DataONE API |
| test-dataone_taxon_screening_geo.R | `build_taxon_screen_prompt()`, `parse_taxon_screening_response()`, `build_geo_prompt()`, `parse_geo_screening_response()` | LLM mocked |
| test-literature_search.R | `search_literature()`, `download_literature_pdfs()` | OpenAlex calls mocked |

---

## Key Dependencies

| Package | Role | Note |
|---|---|---|
| TaxaTools | LLM provider functions, taxonomy helpers | Imports |
| httr2 | API calls (PASTA Solr, OpenAlex, Nominatim) | Imports |
| rgbif | GBIF backbone + occurrence download | Suggests |
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
