# PDF Pipeline — DataONE Parallel Design Guide
# TaxaFetch — Reference for pdf_extract.R and pdf_workflow.R development
#
# Purpose: Keep the PDF occurrence pipeline structurally consistent with the
# vetted DataONE pipeline. Every design decision here traces to a specific
# DataONE precedent. Read this before writing or modifying any PDF pipeline
# function.
#
# Last updated: Session 23 (2026-03-17)
# Author: derived from dataone_standardize.R, dataone_geo_screening.R,
#         Dataone_workflow.R by Claude Sonnet 4.6


---

## 1. Pipeline Structure Parallel

The two pipelines are intentionally symmetric. The PDF pipeline maps onto
the DataONE pipeline stage-for-stage.

| DataONE stage | DataONE function | PDF parallel | PDF function |
|---|---|---|---|
| Catalog harvest | `harvest_dataone_catalog()` | PDF file list / OpenAlex harvest | (future) |
| Abstract screen | `build_taxon_screen_prompt()` + `parse_taxon_screening_response()` | Stage 1 abstract screen | `build_pdf_screen_prompt()` + `parse_pdf_screen_response()` |
| Structure/EML pre-screen | `screen_eml_columns()` | Stage 2 characterization | `screen_pdf_structure()` |
| Preview | `preview_dataone_occurrences()` | (no PDF equivalent — Stage 2 serves this role) | — |
| Download + standardize | `fetch_dataone_occurrences()` | Stage 3 extraction | `build_pdf_extract_prompt()` + `parse_pdf_extract_response()` |
| Stack sources | `stack_occurrences()` | identical — shared function | `stack_occurrences()` |

Both pipelines feed `stack_occurrences()` → `rename_cols()` → habitat assignment.
The shared spine is the DwC output contract (Section 3 below).


---

## 2. Canonical Column Contract

`fetch_dataone_occurrences()` defines the authoritative column order.
`parse_pdf_extract_response()` MUST produce the same columns in the same order.
This is what makes `stack_occurrences()` work without a mapping step.

### Canonical column order (from dataone_standardize.R lines 285-291)

```
occurrenceID
datasetID
datasetName
institutionCode
basisOfRecord
eventDate
year
month
day
decimalLatitude
decimalLongitude
coordinateUncertaintyInMeters
scientificName
genus
family
specificEpithet
vernacularName
individualCount
recordedBy
locality
habitat
```

Followed by any unmapped source columns (appended, not interleaved).

### PDF pipeline values for each column

| Column | DataONE source | PDF equivalent |
|---|---|---|
| `occurrenceID` | `paste0(dataset_id, "_row", seq)` | `paste0(basename(pdf_path), "_row", seq)` |
| `datasetID` | PASTA package ID e.g. `knb-lter-sbc.17.18` | PDF file path or basename |
| `datasetName` | EML `<title>` | Extracted paper title, or `NA` |
| `institutionCode` | EML `<creator><surName>` | `NA` always |
| `basisOfRecord` | `"HumanObservation"` (hardcoded default) | `"HumanObservation"` always |
| `eventDate` | ISO 8601 from data column or constructed from y/m/d | ISO 8601 if extractable, else `NA` |
| `year` / `month` / `day` | Integer columns if present | Integer if extractable, else `NA` |
| `decimalLatitude` | Numeric; `NA` when absent (see Section 4) | Numeric if `explicit_latlon` or `single_site`; `NA` for `named_localities` |
| `decimalLongitude` | As above | As above |
| `coordinateUncertaintyInMeters` | Mapped if present in source | `NA` always |
| `scientificName` | Mapped from source; constructed from genus+epithet if absent | Required; expand via `abbreviation_inventory` |
| `genus` | Mapped if present | `NA` |
| `family` | Mapped if present | `NA` |
| `specificEpithet` | Mapped if present | `NA` |
| `vernacularName` | Mapped if present | `NA` |
| `individualCount` | Mapped from count/abundance columns | `NA` for `field_survey`; populated for `prevalence_abundance` |
| `recordedBy` | Mapped from observer/collector columns | `NA` always (omitted from extraction prompt) |
| `locality` | Mapped from site/station/location_name columns | Extracted place name for `named_localities`; `NA` otherwise |
| `habitat` | Mapped from habitat/substrate columns | `NA` always (assigned downstream) |

### prevalence_abundance additions (appended after canonical columns)

```
organismQuantity      — the numeric value (infection rate, density, etc.)
organismQuantityType  — plain-language description e.g. "prevalence" / "density per m2"
occurrenceStatus      — "present" always (zeros not extracted)
```

These columns are ONLY added when `pdf_structure$observation_type == "prevalence_abundance"`.
For all other paper types they are absent — not NA, absent — to avoid polluting
`stack_occurrences()` output with mostly-NA columns.

`occurrenceStatus` is implicitly "present" for all other paper types and does not
need a column (DataONE follows the same convention).


---

## 3. Coordinate Handling

### DataONE precedent (dataone_standardize.R)

- Coordinate columns are ALWAYS present in the output tibble.
- When a record has no coordinates, `decimalLatitude` and `decimalLongitude` are `NA`.
- `.filter_to_bbox_df()` removes all `NA`-coordinate rows before returning —
  so in practice no `NA`-coordinate rows survive into the final output tibble.
- There is NO `coord_source` column. Coordinate provenance is not tracked.

### PDF pipeline — follow DataONE exactly

- `decimalLatitude` and `decimalLongitude` are always present.
- `named_localities` papers: emit `NA`. The `locality` string carries the
  information. Coordinate resolution is a downstream user responsibility.
- `single_site_rule = TRUE` papers: inject coordinates at prompt-build time
  (in `build_pdf_extract_prompt()`). The LLM sees the coordinates as a given
  and applies them to every extracted record. Output has populated coordinate
  columns, not `NA`.
- `explicit_latlon` papers: extract coordinates from the paper; populate columns.
- Do NOT add a `coord_source` column. This would break `stack_occurrences()`
  consistency and DataONE has no equivalent.
- Unlike DataONE, the PDF pipeline does NOT filter out `NA`-coordinate rows.
  A `named_localities` paper with no coordinates is still a valid occurrence
  record — the locality string is the primary data. The user can geocode
  downstream or pass `locality` to a gazetteer.


---

## 4. Identifier Column Conventions

| DataONE | PDF |
|---|---|
| `datasetID` = PASTA package ID | `datasetID` = PDF file path or basename |
| `datasetName` = EML title string | `datasetName` = extracted paper title or `NA` |
| `institutionCode` = EML creator surname | `institutionCode` = `NA` |
| `occurrenceID` = `paste0(id, "_row", seq)` | `occurrenceID` = `paste0(basename(path), "_row", seq)` |

`datasetID` is the provenance anchor. It is what lets the user trace any
extracted record back to its source PDF, just as PASTA IDs trace DataONE
records back to their dataset. Always use the full file path as `datasetID`
(not just the basename) so records remain traceable if the user has PDFs
from multiple directories.


---

## 5. NA Column Policy

DataONE uses `dplyr::select(all_of(present_dwc))` — columns that were never
mapped simply do not appear in the output. For the PDF pipeline, follow a
slightly stricter rule that aids `stack_occurrences()`:

- All 21 canonical columns MUST be present in every `parse_pdf_extract_response()`
  output, even if entirely `NA`.
- This matches the `bind_rows` contract: `stack_occurrences()` checks that
  coordinate columns are present before binding.
- Columns that are always `NA` for PDFs (`genus`, `family`, `specificEpithet`,
  `vernacularName`, `recordedBy`, `coordinateUncertaintyInMeters`,
  `institutionCode`, `habitat`) are constructed as `NA_character_` or
  `NA_real_` in `parse_pdf_extract_response()` after the LLM parse, not
  requested from the LLM.


---

## 6. LLM Prompt Architecture

### DataONE pattern

Every screening function builds an S3 prompt object of class
`c("<type>_prompt", "llm_prompt")`. The object carries:
- `$prompts` — list of prompt strings, one per chunk
- `$n_chunks`, `$n_items` — size metadata
- Type-specific payload (e.g. `$catalog_subset`, `$bbox_string`)

The object is passed to `prompt_anthropic_api()` or `prompt_manual()` unchanged.
The parser receives the raw response string and the prompt object for validation.

### PDF extraction — same pattern

`build_pdf_extract_prompt()` returns an S3 object of class
`c("pdf_extract_prompt", "llm_prompt")` carrying:
- `$prompts` — list of prompt strings (usually 1, rarely 2 for very long papers)
- `$pdf_structure` — the `pdf_structure` object from Stage 2
- `$page_table` — the filtered page table used to select images
- `$single_site_coords` — list with `lat`/`lon` if `single_site_rule = TRUE`, else `NULL`
- `$abbreviation_inventory` — named vector for expansion post-parse

The prompt object is passed to `call_api_pdf()` (not
`prompt_anthropic_api()` — the PDF function handles image blocks).

### `llm_fn` parameter

`screen_pdf_structure()` accepts `llm_fn = call_anthropic_api`.
`build_pdf_extract_prompt()` does not need `llm_fn` — it builds the prompt.
The caller decides which API function to use. See AI_CONTEXT.md for
the `llm_fn` pattern rationale.


---

## 7. Checkpoint / Workflow Pattern

### DataONE workflow stages (Dataone_workflow.R)

```
Stage 1  — harvest_dataone_catalog()      → pasta_catalog.rds
Stage 2  — build_geo_prompt()
Stage 3  — prompt_anthropic_api()
Stage 4  — parse_geo_screening_response() → geo_screened.rds
Stage 6  — build_taxon_screen_prompt()
Stage 7  — prompt_anthropic_api()         → taxon_screened.rds
Stage 8  — screen_eml_columns()           → eml_screen.rds
Stage 9  — preview_dataone_occurrences()
Stage 10 — fetch_dataone_occurrences()    → dataone_occ
```

Each expensive stage is checkpointed to `.rds`. Resume lines are provided
as comments. Stages are separated by blank lines and run section-by-section
in RStudio.

### PDF workflow (to be written as pdf_workflow.R)

Mirror the same structure:

```
Stage 0  — Clean session + reload; define pdf_paths and bbox/taxon_scope
Stage 1  — extract_pdf_text() for each PDF         → pdf_contents list
Stage 2  — screen_pdf_structure() for each PDF     → pdf_structures list + checkpoint
Stage 3  — [optional] build_pdf_screen_prompt() abstract screen  → screened list
Stage 4  — Inspect structures; drop analytical_modelling, lab papers
Stage 5  — build_pdf_extract_prompt() for each PDF → extract_prompts list
Stage 6  — call_api_pdf() for each PDF   → raw responses list + checkpoint
Stage 7  — parse_pdf_extract_response() for each   → pdf_occ (list of tibbles)
Stage 8  — stack_occurrences(pdf_occ)              → all_pdf_occ
Stage 9  — Merge with DataONE / GBIF via stack_occurrences() + rename_cols()
```

Checkpoint files:
```
pdf_structures.rds    — Stage 2 output
pdf_raw_responses.rds — Stage 6 output (API calls are expensive)
pdf_occ_raw.rds       — Stage 7 output before stacking
```


---

## 8. Error / Skip Handling

### DataONE precedent

- Per-dataset errors are caught by `tryCatch`; a warning is printed;
  `NULL` is returned for that dataset.
- `Filter(Negate(is.null), results)` drops failed datasets silently.
- If no datasets survive, `invisible(NULL)` is returned with a message.
- The caller is responsible for checking the result before proceeding.

### PDF pipeline — follow DataONE

- Per-PDF errors in `parse_pdf_extract_response()` should warn and return
  `NULL` for that PDF, not stop the loop.
- `observation_type == "analytical_modelling"` or `"experimental_lab"`:
  return `NULL` with a visible message (not just a warning) since this is
  an expected skip, not an error.
- `stack_occurrences()` handles `NULL` entries in its input list gracefully
  (it filters them before binding).


---

## 9. Text Extraction vs. Image Extraction

This is the key architectural difference between DataONE and PDF.

| DataONE | PDF |
|---|---|
| Downloads tabular data files (CSV/TSV) | Sends page images to vision API |
| Column mapping via regex patterns | Structured prompt instructs field extraction |
| `NA` for unmapped columns | `NA` constructed post-parse for absent fields |
| No token budget concern | Token budget critical — 150 dpi, targeted pages only |

The PDF pipeline's equivalent of DataONE's `.default_dwc_map` is the
extraction prompt template in `build_pdf_extract_prompt()`. Both translate
heterogeneous source formats into the same canonical DwC columns.

The PDF pipeline's equivalent of DataONE's `.classify_entity()` /
`.attempt_dwc_join()` is the `pdf_structure` axis system — it characterizes
what kind of data is present and how to extract it, just as DataONE's entity
classification determines which download/join strategy to use.


---

## 10. `scientificName` Construction and Abbreviation Expansion

### DataONE precedent (dataone_standardize.R lines 526-538)

When `scientificName` is absent, construct it from `genus + specificEpithet`:
```r
sn <- trimws(paste(genus, specificEpithet))
scientificName <- ifelse(nzchar(sn), sn, NA_character_)
```
Falls back to `genus` alone if `specificEpithet` is absent.

### PDF pipeline

The LLM extracts `scientificName` directly. However, the paper may use
abbreviated binomials (e.g. `V. princeps` for `Valencienea princeps`).

Post-parse expansion step in `parse_pdf_extract_response()`:
```r
# pdf_structure$abbreviation_inventory is a named character vector
# names = abbreviation key (e.g. "V."), values = full binomial
# Apply to scientificName column after parsing
```

This is the PDF equivalent of DataONE's genus+epithet construction:
both are post-parse name normalisation steps that ensure `scientificName`
is a complete binomial ready for `verify_taxon_names()`.

Spelling variants are stored in `attr(abbreviation_inventory, "spelling_variants")`.
Log them in `parse_pdf_extract_response()` but do not attempt to resolve them —
pass `scientificName` as-is to `verify_taxon_names()` downstream.


---

## 11. What NOT to Copy from DataONE

These DataONE patterns have no PDF equivalent and should not be added:

- **`gbif_snapshot_path` / deduplication**: PDF records are primary literature,
  not repackaged GBIF data. No dedup step.
- **`extra_dwc_map`**: The PDF extraction prompt is a natural language template,
  not a regex column map. There is no user-extensible mapping layer.
- **`bbox` filter on output**: DataONE filters out `NA`-coordinate rows via bbox.
  The PDF pipeline does NOT do this — `named_localities` records with `NA`
  coordinates are valid and must be preserved.
- **`odm_variable`**: LTER ODM join logic is specific to DataONE structured
  datasets. No PDF equivalent.
- **`site_lookup`**: DataONE uses this to override EML site codes. The PDF
  equivalent is `single_site_coords` passed to `build_pdf_extract_prompt()` —
  a simpler scalar injection, not a lookup table.
