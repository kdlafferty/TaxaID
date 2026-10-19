# CLAUDE.md -- TaxaFetch

Occurrence-data acquisition: GBIF, iNaturalist, DataONE, PDF and literature search, and source combination.

Ecosystem-level context is in the repository root's CLAUDE.md, which is auto-loaded
from any package subdirectory.

## Development history

The narrative history of this package -- session notes, past decisions and the
reasoning behind them -- lives in the TaxaID_dev repository at
`ecosystem_docs/session_notes/TaxaFetch_CLAUDE_2026-10.md`. This file carries current
state only.

## Exported functions (32)

| Function | Purpose |
|---|---|
| `build_geo_prompt` | Build a Geographic Screening Prompt for DataONE Datasets |
| `build_pdf_extract_prompt` | Build a Stage 3 extraction prompt from a characterised PDF |
| `build_taxon_screen_prompt` | Build a Taxonomic Screening Prompt for DataONE Datasets |
| `call_api_pdf` | Send Selected PDF Pages to an LLM Vision API |
| `check_geographic_outliers` | Flag Geographically Isolated Occurrence Records Against a Species' Global Range |
| `check_inat_range` | Check whether taxa fall within iNaturalist range polygons |
| `dedupe_occurrences` | Remove Duplicate Occurrence Records |
| `download_gbif_occurrences` | Download GBIF Occurrence Records via the Async Download API |
| `download_literature_pdfs` | Download PDFs for papers in a screened literature catalog |
| `extract_pdf_text` | Extract Text by Section from a PDF File |
| `fetch_dataone_occurrences` | Download and Standardize Occurrence Records from DataONE / EDI |
| `fetch_gbif_occurrence_counts` | Fetch species-level GBIF record counts in distance bands around a site |
| `fetch_gbif_occurrences` | Fetch GBIF Occurrence Records for a Set of Taxon Keys |
| `fetch_inat_occurrence_counts` | Fetch local iNaturalist observation counts, including casual-grade records |
| `filter_gbif_quality` | Filter GBIF Occurrence Records by Quality |
| `get_gbif_occurrences` | Fetch GBIF Occurrences -- Unified Entry Point |
| `get_keys_from_context` | Fetch GBIF Taxon Keys Using Full Taxonomic Context |
| `harvest_dataone_catalog` | Harvest the Full PASTA / EDI Dataset Catalog |
| `make_bbox_wkt` | Create a WKT Bounding Box Around a Central Point |
| `parse_geo_screening_response` | Parse an LLM Geographic Screening Response |
| `parse_pdf_extract_response` | Parse a raw LLM extraction response to a Darwin Core tibble |
| `parse_taxon_screening_response` | Parse an LLM Taxonomic Screening Response |
| `plan_gbif_fetch` | Plan a GBIF fetch: price the records path against the counts path |
| `preview_dataone_occurrences` | Preview DataONE/EDI Datasets Before Full Download |
| `read_biotime_study` | Read and DwC-map a downloaded BioTime study CSV |
| `report_fetch` | Generate a Report Section for Data Acquisition |
| `screen_eml_columns` | Pre-Screen DataONE Candidates via EML Metadata |
| `screen_pdf_structure` | Characterize a PDF Paper on Five Axes for Occurrence Extraction |
| `search_dataone` | Discover Occurrence-Bearing Datasets from EDI / PASTA |
| `search_literature` | Search the OpenAlex literature catalog for occurrence-relevant papers |
| `stack_occurrences` | Stack Multiple Occurrence Data Frames |
| `taxafetch_clear_cache` | Report and clear TaxaFetch's on-disk cache |

## Current behaviour worth knowing

- No behaviour changed this cycle; the package's own README and roxygen were brought up to date.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
