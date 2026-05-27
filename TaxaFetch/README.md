---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaFetch

Taxonomic assignments are more accurate when they consider which
species are plausible at the sampling location. Without this context,
classifiers frequently assign detections to ecologically implausible
taxa. TaxaFetch compiles species occurrence records from multiple
sources -- GBIF, DataONE, BioTIME, and published literature -- and
combines them into a standardized format for downstream habitat
assignment (TaxaHabitat) and prior estimation (TaxaExpect).

## Data Sources

| Source | Function | What it provides |
|----|----|----|
| **GBIF** | `fetch_gbif_occurrences()` | Global occurrence records via download API |
| **DataONE** | `fetch_dataone_occurrences()` | Ecological datasets from DataONE repositories |
| **BioTIME** | `read_biotime_study()` | Time-series biodiversity data |
| **Literature** | `search_literature()` | OpenAlex scholarly search + PDF download |
| **PDFs** | `extract_pdf_text()` | Extract occurrence data from published PDFs |

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaFetch")
```

## Quick Start

``` r
library(TaxaFetch)

# 1. Define a bounding box (Southern California coast)
bbox <- make_bbox_wkt(lat_min = 33.5, lat_max = 34.5,
                      lon_min = -120.0, lon_max = -118.5)

# 2. Get GBIF taxon keys from verified names
keys <- get_keys_from_context(
  c("Fundulus parvipinnis", "Atherinops affinis"),
  backbone_id = 11  # GBIF backbone
)

# 3. Fetch GBIF occurrences
gbif_data <- fetch_gbif_occurrences(keys = keys$usageKey, geometry = bbox)

# 4. Filter to high-quality records
filtered <- filter_gbif_quality(gbif_data, max_coord_uncertainty = 500)

# 5. Stack multiple sources into one table
all_data <- stack_occurrences(gbif = filtered)
```

## Key Functions

**GBIF pipeline:** - `make_bbox_wkt()` -- create WKT bounding box for
spatial queries - `get_keys_from_context()` -- resolve taxon names to
GBIF usage keys - `fetch_gbif_occurrences()` -- download occurrence
records - `filter_gbif_quality()` -- remove low-quality records

**DataONE pipeline:** - `search_dataone()` -- find datasets by taxon and
location - `harvest_dataone_catalog()` -- build a dataset catalog with
LLM screening - `fetch_dataone_occurrences()` -- download and
standardize occurrence tables

**Literature + PDF pipeline:** - `search_literature()` -- OpenAlex
scholarly search - `download_literature_pdfs()` -- batch PDF download -
`extract_pdf_text()` -- section-aware text extraction -
`screen_pdf_structure()` -- LLM-based relevance screening -
`build_pdf_extract_prompt()` / `parse_pdf_extract_response()` -- LLM
data extraction

**Combining sources:** - `stack_occurrences()` -- row-bind sources into
a single standardized table - `report_fetch()` -- summarize data
acquisition for reports

## API Keys

TaxaFetch uses GBIF credentials for occurrence downloads and OpenAlex
for literature search. See the TaxaTools [API Setup
vignette](../TaxaTools/vignettes/api-setup.Rmd) for configuration.

## Vignettes

-   [Data Acquisition](vignettes/data-acquisition.Rmd) -- end-to-end
    guide

## Part of TaxaID

TaxaFetch is the data acquisition layer in the TaxaID ecosystem. Its
output feeds into TaxaHabitat (habitat assignment) and TaxaExpect (prior
estimation).

**Ecosystem:** TaxaTools -\> **TaxaFetch** -\> TaxaHabitat -\>
TaxaExpect -\> TaxaAssign

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   TaxaTools (foundation package, installed first)
-   rgbif (for GBIF occurrence queries)
-   An LLM API key is needed for literature screening and PDF extraction

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic).
