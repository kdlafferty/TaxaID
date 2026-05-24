---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaTools

Foundation package for the [TaxaID](https://github.com/DOI-USGS/TaxaID)
ecosystem. Provides taxonomic name handling, LLM provider functions, and
shared utilities used by all downstream TaxaID packages.

One of the most difficult aspects of biodiversity science is
standardizing taxonomic information. The taxize package was long the
standard tool for this, but it is no longer maintained. TaxaTools
replaces and extends that functionality: it cleans, verifies, and
standardizes taxonomic names across multiple backbones (GBIF, NCBI,
WoRMS, Catalogue of Life). Nomenclature inconsistencies between data
sources can cause false negatives when priors and likelihoods fail to
join on mismatched names. TaxaTools also provides a unified
interface for calling large language models (LLMs) from R, with
support for Anthropic Claude, Google Gemini, OpenAI, and local Ollama
models. LLM-assisted functions can draft Methods and Results text for
scientific papers describing how a user arrived at a particular
consensus.

## Features

-   **Name cleaning** -- strip authors, subspecies, formatting artifacts
    (`clean_taxon_names()`)
-   **Name verification** -- check spelling and resolve against GBIF,
    NCBI, WoRMS, or Catalogue of Life (`verify_taxon_names()`)
-   **Backbone translation** -- move names between taxonomic backbones
    (`change_backbone()`)
-   **Column standardization** -- rename columns to DarwinCore
    conventions (`rename_cols()`)
-   **LLM providers** -- unified interface to Anthropic Claude, Google
    Gemini, OpenAI, and local Ollama models
-   **Text generation** -- LLM-assisted drafting of Methods and Results
    sections (`draft_methods_text()`, `draft_results_text()`)
-   **Report assembly** -- combine per-package report sections into a
    unified document (`assemble_report()`)
-   **GBIF census** -- enumerate described species per genus from the
    GBIF backbone (`census_genus_species()`)

## Installation

``` r
# From local source (recommended during development)
devtools::install("path/to/TaxaTools")

# Or from the parent TaxaID directory
devtools::install("TaxaTools")
```

## Quick Start

``` r
library(TaxaTools)

# Clean messy names
clean_taxon_names(c(
  "Fundulus parvipinnis (Girard, 1854)",
  "Atherinops  affinis",
  "sp. nov."
))
#> [1] "Fundulus parvipinnis" "Atherinops affinis"   NA

# Verify against NCBI
verified <- verify_taxon_names(
 c("Fundulus parvipinnis", "Atherinops afinis"),
  backbone_id = 4
)

# Derive canonical taxon label from taxonomy columns
df <- data.frame(
  family  = "Fundulidae",
  genus   = "Fundulus",
  species = "Fundulus parvipinnis"
)
create_taxon_names(df, rank_system = c("family", "genus", "species"))

# Call an LLM
call_anthropic_api("What habitat does Fundulus parvipinnis prefer?")
```

## Taxonomic Backbone IDs

Several TaxaTools functions accept a `backbone_id` integer to specify
which taxonomic backbone to query or translate to. The supported
backbones are:

| ID  | Backbone          |
|-----|-------------------|
| 1   | Catalogue of Life |
| 3   | ITIS              |
| 4   | NCBI              |
| 9   | WoRMS             |
| 11  | GBIF              |

Full list: <https://verifier.globalnames.org/>

## API Keys

Several TaxaID functions require API keys. See the [API Setup
vignette](vignettes/api-setup.Rmd) for where to get keys and how to
configure them in `~/.Renviron`.

| Key | Purpose | Free? |
|------------------------|------------------------|------------------------|
| `ENTREZ_KEY` | NCBI taxonomy queries | Yes |
| `ANTHROPIC_API_KEY` | Claude LLM (default provider) | Paid |
| `GBIF_USER` / `GBIF_PWD` / `GBIF_EMAIL` | GBIF occurrence downloads | Yes |
| `GEMINI_API_KEY` | Google Gemini (optional) | Free tier |

## Vignettes

-   [Cleaning and Verifying Taxon Names](vignettes/name-cleaning.Rmd) --
    core taxonomy workflow
-   [Setting Up API Keys](vignettes/api-setup.Rmd) -- ecosystem-wide API
    configuration guide

## Part of TaxaID

TaxaTools is the foundation package in the TaxaID ecosystem for
probabilistic taxonomic assignment. All other packages depend on it for
name handling and LLM access.

**Ecosystem:** TaxaTools -\> TaxaFetch -\> TaxaHabitat -\> TaxaExpect
-\> TaxaAssign / TaxaMatch -\> TaxaLikely -\> TaxaAssign -\> TaxaFlag

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   An API key for at least one LLM provider (Anthropic, Google Gemini,
    OpenAI, or Ollama) is needed for text generation functions
-   rgbif (for GBIF backbone census; in Suggests)

All dependencies are declared in the DESCRIPTION file and installed
automatically.
