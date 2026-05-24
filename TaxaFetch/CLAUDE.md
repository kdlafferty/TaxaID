# CLAUDE.md — TaxaFetch
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-23 (Session 86 — no package changes; last package changes Session 72)

---

## Package Purpose
Occurrence data acquisition (GBIF, DataONE, PDF, literature search) and source combination.
Habitat assignment and spatial QAQC are now in **TaxaHabitat**. LLM provider functions are
now in **TaxaTools**. Split from TaxaExpect in Session 19; further split in Session 28.

**Dependency chain:** TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign/TaxaMatch

---

## Function Inventory

### DataONE / GBIF pipeline

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `stack_occurrences()` | Row-bind occurrence data frames; accepts list OR `...`; drops NULL; adds `point_id`; single-frame OK | Complete | R/stack_occurrences.R |
| `make_bbox_wkt()` | Build WKT POLYGON bounding box | Complete | R/make_bbox_wkt.R |
| `get_keys_from_context()` | Resolve hierarchy dataframe to GBIF usage keys | Complete | R/get_keys_from_context.R |
| `fetch_gbif_occurrences()` | Download occurrence records for GBIF taxon keys | Complete | R/fetch_gbif_occurrences.R |
| `filter_gbif_quality()` | Filter GBIF records by quality criteria; default `max_coord_uncertainty = 500` m; NA retained | Complete | R/filter_gbif_quality.R |
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
| `call_anthropic_api_pdf()` | Send selected PDF pages as images to Anthropic API (Anthropic-only) | Complete | R/pdf_api.R |
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
make_bbox_wkt() → get_keys_from_context() → fetch_gbif_occurrences() → filter_gbif_quality()
```

### Literature + PDF pipeline
```
search_literature() → build_taxon_screen_prompt(geo_scope=...) [optional]
  → download_literature_pdfs() → extract_pdf_text() → screen_pdf_structure()
  → build_pdf_extract_prompt() → call_anthropic_api_pdf() → parse_pdf_extract_response()
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

`call_anthropic_api_pdf()` is Anthropic-only (vision API); provider-neutral image upload is future work.

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
- `withr` dependency: tests use `withr::with_envvar()` — ensure in DESCRIPTION Suggests
- Habitat assignment is now in **TaxaHabitat** — do not add habitat functions back here

---

## Known Issues

- HTTP 403 on publisher PDF downloads: manual download path in workflow
- Section assignment imperfect for two-column layouts (cosmetic only)
- `build_geo_prompt()` not usable on OpenAlex catalog (DataONE-specific columns)
- `call_anthropic_api_pdf()` is Anthropic-only; provider-neutral image upload is future work

---

## Next Steps

1. ~~Run `devtools::check()`~~ — verified clean (Session 63)
2. ~~`pdf_screen.R`~~ — resolved: `build_taxon_screen_prompt(geo_scope=...)` already handles literature catalog screening in combined mode (Session 63)
3. ~~`stack_occurrences` tests~~ — already written and passing (22 tests, Session 63)
4. ~~GITA multi-table functions~~ — dropped: `rename_cols()` + `stack_occurrences()` cover the same use case (Session 63)
5. ~~Data source citation capture~~ — implemented (Session 63): `bibliographicCitation` column added to `fetch_gbif_occurrences()`, `standardize_dataone_occurrences()`, `read_biotime_study()`; PDF pipeline already had it via `search_literature()`
6. ~~ReefCheck + Reef Life Survey~~ — resolved (Session 64): both already in GBIF (RLS global reef fish dataset, RCCA rocky reef dataset, Reef Check Taiwan). No separate fetch functions needed.

---

## Key Dependencies

| Package | Role | Note |
|---|---|---|
| TaxaTools | LLM provider functions, taxonomy helpers | Imports |
| httr2 | API calls (PASTA Solr, OpenAlex, Nominatim) | Imports |
| rgbif | GBIF backbone + occurrence download | Suggests |
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
| withr | Used in tests only | Suggests |

---

## Session Notes

**Session 26 (2026-03-24)**
- Added `call_gemini_api()`, `call_openai_api()`, `call_ollama_api()`
- `prompt_anthropic_api` renamed to `prompt_api`; `llm_fn` param added

**Session 27 (2026-03-26)**
- CLAUDE.md restructured: ecosystem context in `TaxaID/CLAUDE.md`; this file is package-specific
- pdf_characterize_v2.R → pdf_characterize.R; pdf_text_v2.R → pdf_text.R (old v1 deleted)

**Session 28 (2026-03-26)**
- LLM provider functions (`call_*_api`, `prompt_api`, `prompt_manual`, `read_llm_response`)
  moved to TaxaTools/R/llm_api_utils.R
- Habitat functions moved to TaxaHabitat (new package)
- `parse_hierarchical_habitat_response` moved to TaxaHabitat/R/parse_habitat_response.R
- DESCRIPTION: removed sf, terra, leaflet, shiny, miniUI, rnaturalearth, rnaturalearthdata;
  added note these are now in TaxaHabitat
- `screen_pdf_structure()` in pdf_characterize.R: added `@importFrom TaxaTools call_anthropic_api`

---

## TODO

### Distributed report architecture (Session 64 — planned for Session 65)
TaxaFetch should export a `report_fetch()` function that summarizes data
acquisition: n_records per source, geographic/temporal scope, and
`unique(df$bibliographicCitation)`. This feeds into a final assembled report
alongside per-package report sections from TaxaMatch, TaxaLikely, TaxaHabitat,
TaxaExpect, TaxaAssign, and TaxaFlag.

Key: citations must be captured BEFORE TaxaExpect aggregation destroys row-level
data. The `bibliographicCitation` column (implemented Session 63) is the capture
mechanism; `report_fetch()` extracts and formats it.

### Resolved items
- ~~Data source citation capture~~ — implemented Session 63 via `bibliographicCitation` column
- ~~ReefCheck + Reef Life Survey~~ — resolved Session 64 (both already in GBIF)
- ~~PDF pipeline crash~~ — fixed Session 64 (subprocess rendering + pdf_path propagation)
- ~~Distributed report architecture~~ — implemented Session 65 via `report_fetch()` (see below)

---

## Session Notes (Sessions 65–86)

**Session 65 (2026-05-02)**
- `report_fetch()` added to `R/report_fetch.R`: summarizes data acquisition (sources, bbox,
  year range, citations from `bibliographicCitation` column). Returns `report_section` S3
  object for `TaxaTools::assemble_report()`.
- `report_params` attribute added to `stack_occurrences()` output: attaches `citations`
  (unique `bibliographicCitation`), `n_records`, `n_sources`.
- `report_params` attribute added to `fetch_gbif_occurrences()` output: attaches `source`,
  `n_keys`, `n_records`, `geometry` (WKT), `year_range`.

**Session 66 (2026-05-03)**
- LaTeX `\$` fix in `search_literature.Rd` (escaped dollar in roxygen source).
- Dead code removed; stale `@seealso` refs updated.

**Session 67 (2026-05-04)**
- `llm_fn` default in `screen_pdf_structure()` updated to
  `getOption("TaxaID.llm_fn", call_anthropic_api)`.

**Session 72 (2026-05-11)**
- `.recover_higherrank()` internal function added: when `name_backbone()` returns HIGHERRANK
  with rank jump >1 level, falls back to `name_lookup()` with rank constraint. Rank-agnostic.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` ecosystem rename: TaxaFetch does not use this column;
  no source changes required.

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- `combine_occurrence_sources()` dead code deleted (superseded by `rename_cols()` +
  `stack_occurrences()` since Session 19). File + Rd deleted; `@seealso` refs updated.
- 5 stale inst/ files deleted: `TaxaFetch_workflow copy.R`, `migrate_prompt_api.R`,
  `habitat_scheme_workflow.R`.

**Sessions 83–86 (2026-05-21 to 2026-05-23)**
- No TaxaFetch-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools),
  WERC review integration. Deferred: `call_anthropic_api_pdf()` generic (multimodal/PDF
  call cannot be trivially unified with `call_api`; tracked as TODO in TaxaID/CLAUDE.md).
  See TaxaID/CLAUDE.md for full log.
