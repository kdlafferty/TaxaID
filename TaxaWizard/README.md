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

The assistant will ask about your data type (eDNA, camera trap,
acoustic), available inputs, and analysis goals. When finished, it
generates:

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
