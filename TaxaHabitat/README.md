---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaHabitat

Habitat assignment and spatial quality control for the
[TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem. Classifies
species into habitat categories using LLM-based biological consensus,
assigns habitats to sampling sites, and flags spatial outliers.

Habitat is a key predictor of which species are plausible at a
sampling location. Ideally, a knowledgeable user assigns each taxon to
its habitat. When the species list is long, LLMs can do a reasonable
job of classifying species into habitat categories. As with any LLM
output, users should review the results.
`flag_habitat_inconsistencies()` provides an interactive map that
makes errant classifications easy to spot and correct.

## Habitat Schemes

| Scheme | Categories | Use case |
|------------------------|------------------------|------------------------|
| **3-category** (default) | Marine / Freshwater / Terrestrial | Most eDNA studies |
| **IUCN Level 1** | 18 IUCN habitat categories | Fine-grained habitat mapping |
| **Custom** | User-defined | Specialized study designs |

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaHabitat")
```

## Quick Start

``` r
library(TaxaHabitat)

# 1. Build an LLM prompt for habitat classification
prompt <- build_habitat_prompt(
  c("Fundulus parvipinnis", "Cottus asper", "Anas platyrhynchos")
)

# 2. Submit to an LLM provider
raw_text <- TaxaTools::prompt_api(prompt)

# 3. Parse response into per-species habitat weights
habitat_weights <- parse_hierarchical_habitat_response(raw_text, prompt)
# taxon_name           Marine_weight  Freshwater_weight  Terrestrial_weight
# Fundulus parvipinnis  0.85           0.15               0.0
# Cottus asper          0.0            1.0                0.0
# Anas platyrhynchos    0.05           0.60               0.35

# 4. Assign habitat to sampling sites based on species composition
occurrences_with_habitat <- assign_habitat_biological(
  occurrences, habitat_weights
)

# 5. Flag spatial outliers (marine species at inland sites, etc.)
flagged <- flag_habitat_inconsistencies(occurrences_with_habitat)
```

## Key Functions

**Habitat classification:** - `build_habitat_prompt()` -- create LLM
prompt for species habitat weights -
`parse_hierarchical_habitat_response()` -- parse LLM output to numeric
weights - `assign_habitat_biological()` -- assign site habitat from
species composition - `consensus_habitat()` -- assemblage-level
consensus with ecoregion extraction

**Custom schemes:** - `build_iucn_scheme()` -- generate IUCN Level 1
habitat scheme - `example_habitat_scheme()` -- example custom scheme for
reference - `build_scheme_prompt()` / `parse_scheme_response()` --
custom scheme workflow

**Spatial QC:** - `flag_habitat_inconsistencies()` -- flag records
inconsistent with site habitat - `review_spatial_flags()` -- interactive
Leaflet map for manual review

**Reporting:** - `report_habitat()` -- summarize habitat assignment for
`assemble_report()`

## LLM Integration

TaxaHabitat uses the `llm_fn` pattern from TaxaTools. The default
provider is `call_anthropic_api()`, but any compatible provider works:

``` r
# Use Gemini instead
raw_text <- TaxaTools::prompt_api(prompt, llm_fn = TaxaTools::call_gemini_api)
```

## API Keys

Requires an LLM API key (Anthropic by default). See the TaxaTools [API
Setup vignette](../TaxaTools/vignettes/api-setup.Rmd) for configuration.

## Vignettes

-   [Habitat Assignment](vignettes/habitat-assignment.Rmd) -- full
    workflow guide

## Part of TaxaID

TaxaHabitat receives occurrence data from TaxaFetch and produces
habitat-annotated records for TaxaExpect (prior estimation).

**Ecosystem:** TaxaTools -\> TaxaFetch -\> **TaxaHabitat** -\>
TaxaExpect -\> TaxaAssign

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   TaxaTools (for LLM provider functions)
-   An LLM API key is required for habitat assignment via
    `build_habitat_prompt()`

All dependencies are declared in the DESCRIPTION file and installed
automatically.

## U.S. Geological Survey Disclaimer

This software is preliminary or provisional and is subject to revision.
It is being provided to meet the need for timely best science. The
software has not received final approval by the U.S. Geological Survey
(USGS). No warranty, expressed or implied, is made by the USGS or the
U.S. Government as to the functionality of the software and related
material nor shall the fact of release constitute any such warranty. The
software is provided on the condition that neither the USGS nor the U.S.
Government shall be held liable for any damages resulting from the
authorized or unauthorized use of the software.

*Non-endorsement of commercial products and services*: Any use of trade,
firm, or product names is for descriptive purposes only and does not
imply endorsement by the U.S. Government.
