---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaWizard

Conversational workflow designer for the
[TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem. An LLM-powered
interview identifies your inputs, parameters, and pipeline steps, then
generates a self-contained R script, methods text, or Shiny application.

The TaxaID ecosystem has many possible workflows, and choosing the
right combination of packages and parameters can be daunting.
TaxaWizard makes this easier through a guided conversation: describe
your data and goals, and it generates the appropriate script.
`workflow_app()` can also convert any R script (not just TaxaID
scripts) into a Shiny application with point-and-click inputs.

## Installation

``` r
install.packages(c("httr2", "jsonlite"))  # required
install.packages("shiny")                  # optional, for browser/viewer mode
devtools::install("path/to/TaxaWizard")
```

Requires an LLM API key (Anthropic by default). See the TaxaTools [API
Setup vignette](../TaxaTools/vignettes/api-setup.Rmd) for configuration.

## Quick Start

``` r
library(TaxaWizard)

# Launch the interview (auto-selects console, browser, or RStudio viewer)
workflow_create()

# Or specify a mode
workflow_create(mode = "browser")   # opens in web browser
workflow_create(mode = "console")   # readline in terminal
workflow_create(mode = "viewer")    # RStudio Viewer pane
```

The assistant asks about your data type, available inputs, and analysis
goals, then generates a script tailored to your path through the TaxaID
pipeline. Supported workflow paths include:

-   **eDNA / metabarcoding** — DADA2 seqtab or FASTA → BLAST →
    likelihood model → Bayesian or LLM assignment
-   **Acoustic** — BirdNET-Analyzer CSV output → match data; or
    Xeno-canto reference recordings + BirdNET → acoustic likelihood
    model
-   **Camera trap / image** — Animl, iNaturalist CV, or Wildlife Insights
    output → match data; or labeled reference images → image likelihood
    model
-   **Reference library building** — taxa names (from TaxaExpect or
    user-supplied) → site-specific NCBI reference library; or load a
    local CRABS or FASTA database
-   **Occurrence-based priors** — taxa + location → GBIF occurrences →
    habitat → spatially explicit priors
-   **Assignment convergence** — any combination of the above →
    likelihoods + priors → posteriors → consensus → report

When the interview is complete, TaxaWizard generates:

-   **R script** with checkpoint/resume, error recovery, and debug mode
-   **Methods text** summarizing the workflow for manuscripts
-   **Shiny app** (via `workflow_app()`) for point-and-click execution

## Fixing Errors in Generated Scripts

``` r
# If a generated script errors, resume the conversation with context
workflow_fix()
```

## Converting Scripts to Shiny Apps

``` r
# Convert any TaxaWizard-generated (or annotated) script to a Shiny app
workflow_app("my_workflow.R")

# Annotate a generic R script first, then convert
annotate_script("my_analysis.R")
workflow_app("my_analysis.R")
```

## Key Functions

| Function            | Purpose                                            |
|---------------------|----------------------------------------------------|
| `workflow_create()` | Launch interactive interview (main entry point)    |
| `workflow_fix()`    | Resume after script error with diagnostic context  |
| `workflow_app()`    | Convert generated script to Shiny app              |
| `annotate_script()` | Annotate generic R scripts for Shiny conversion    |
| `workflow_engine()` | Stateless LLM engine (advanced / programmatic use) |

## Part of TaxaID

TaxaWizard sits outside the TaxaID dependency chain. It reads package
metadata files and generates scripts that call the other TaxaID packages
-- it does not import them directly.

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   An LLM API key (Anthropic recommended) is required for the
    conversational engine
-   shiny (for browser/viewer chat interface and generated apps; in
    Suggests)

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic).
