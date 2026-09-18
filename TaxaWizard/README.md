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
Although one could use other LLMs to do the same, TaxaWizard comes
pre-informed with context about the TaxaID package.

The TaxaID ecosystem has many possible workflows, and choosing the right
combination of packages and parameters can be daunting. TaxaWizard makes
this easier through a guided conversation: describe your data and goals,
and it generates the appropriate script. `workflow_app()` can also
convert any R script (not just TaxaID scripts) into a Shiny application
with point-and-click inputs.

## Installation

``` r
install.packages(c("httr2", "jsonlite"))  # required
install.packages("shiny")                  # optional, for browser/viewer mode
devtools::install("path/to/TaxaWizard")
```

Requires an Application Programming Interface (API) key for an LLM
provider (Anthropic Claude -- Anthropic PBC, San Francisco, California
-- by default; Google Gemini, OpenAI, or local Ollama are also supported
via TaxaTools). See the TaxaTools [API Setup
vignette](../TaxaTools/vignettes/api-setup.Rmd) for configuration.

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

-   **eDNA / metabarcoding** — DADA2 seqtab or FASTA → BLAST (Basic
    Local Alignment Search Tool; Altschul et al. 1990, hosted by NCBI,
    the National Center for Biotechnology Information, U.S. National
    Library of Medicine, National Institutes of Health, Bethesda,
    Maryland) → likelihood model → Bayesian or LLM assignment
-   **Acoustic** — BirdNET-Analyzer (Cornell Lab of Ornithology, Cornell
    University, Ithaca, New York) CSV output → match data; or Xeno-canto
    (Xeno-canto Foundation, Netherlands) reference recordings + BirdNET
    → acoustic likelihood model
-   **Camera trap / image** — `animl` (Conservation Technology Lab, San
    Diego Zoo Wildlife Alliance, San Diego, California), iNaturalist CV
    (a joint initiative of the California Academy of Sciences and the
    National Geographic Society, San Francisco, California), or
    SpeciesNet (Google LLC, Mountain View, California) output → match
    data; or labeled reference images → image likelihood model
-   **Reference library building** — taxa names (from TaxaExpect or
    user-supplied) → site-specific NCBI reference library; or load a
    local CRABS or FASTA database
-   **Occurrence-based priors** — taxa + location → GBIF (Global
    Biodiversity Information Facility; GBIF Secretariat, Copenhagen,
    Denmark) occurrences → habitat → spatially explicit priors
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
# Convert any TaxaID-generated (or annotated) script to a Shiny app that your clients could use to do run their own taxonomic consensus without having to run R.
workflow_app("my_workflow.R")

# Annotate a generic R script first, then convert
annotate_script("my_analysis.R")
workflow_app("my_analysis.R")
```

## Checking your setup

``` r
# Is this machine ready to run TaxaID workflows? R version, the 8 TaxaID
# packages (+ Bioconductor/optional extras), package caches, and -- narrowed
# to a specific path through the workflow graph -- the API keys, network
# services, and binaries that path needs.
workflow_check()

# Narrow to what one workflow step actually needs (e.g. only the BLAST/NCBI
# requirements, not GBIF's):
workflow_check(edges = "seq_to_match")
```

Every generated script starts with the same check as its "Step 0" and stops
before running anything if a required key/package/binary is missing --
`workflow_check()`'s `fix` column says exactly what to do. Key checks report
set/unset only; a key's value is never printed, logged, or returned. Set
`options(TaxaWizard.offline = TRUE)` to skip the live network checks (e.g. in
a script that must not depend on connectivity at generation time).

``` r
# What input-graph node does this file look like? (FASTA, a DADA2 seqtab
# .rds, BirdNET/Animl/iNaturalist-CV/SpeciesNet output, a CRABS or
# FASTA+taxonomy reference database, an occurrence/match/taxon/consensus
# table, ...)
sniff_input("my_data.csv")
```

## Key Functions

| Function                    | Purpose                                                        |
|------------------------------|----------------------------------------------------------------|
| `workflow_create()`          | Launch interactive interview (main entry point)                |
| `workflow_fix()`              | Resume after script error with diagnostic context              |
| `workflow_app()`              | Convert generated script to Shiny app                          |
| `annotate_script()`           | Annotate generic R scripts for Shiny conversion                |
| `workflow_check()`            | Report setup readiness: R, packages, keys, network, cache, binaries |
| `sniff_input()`               | Guess which workflow-graph input node a file looks like        |
| `workflow_export_prompts()`   | Export a portable prompt pack for use with any LLM (no TaxaWizard install needed) |
| `workflow_engine()`           | Stateless LLM engine (advanced / programmatic use)             |
| `workflow_registry()`         | Introspect the installed TaxaID packages' functions (advanced) |

## Using TaxaID with any LLM

TaxaWizard's own interview (`workflow_create()`) needs an API key and this
package installed. If you want to design a workflow with a different LLM --
a plain chat window, someone else's agentic coding tool, a colleague with no
R environment set up -- export a portable prompt pack instead:

``` r
workflow_export_prompts("taxaid_prompts")
```

This writes a self-contained folder (packages, function signatures, the
workflow graph, setup requirements -- all generated from the TaxaID packages
installed on your machine, never hand-typed) that any LLM can be pointed at.
Give the folder to an agentic tool (Claude Code, Cursor, a Copilot agent) and
tell it to start with `START_HERE.md`; for a plain chat window, paste
`START_HERE.md` and `CONTEXT_TaxaID.md` in first. A ready-to-use copy (with a
placeholder setup report, since it isn't any one machine) ships at the
repository root in
[`llm_prompts/`](https://github.com/DOI-USGS/TaxaID/tree/main/llm_prompts).

## Part of TaxaID

TaxaWizard sits outside the TaxaID dependency chain. It introspects the
other TaxaID packages' installed functions (see `workflow_registry()`)
and generates scripts that call them -- it does not import them directly.

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0; R Core Team 2025)
-   An LLM API key (Anthropic recommended) is required for the
    conversational engine
-   shiny (for browser/viewer chat interface and generated apps; in
    Suggests)

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic PBC, San
Francisco, California).

## References

Altschul, S.F., Gish, W., Miller, W., Myers, E.W. and Lipman, D.J.
(1990). Basic local alignment search tool. *Journal of Molecular
Biology*, 215(3), 403--410.

R Core Team (2025). R: A Language and Environment for Statistical
Computing. V.4.5.2. R Foundation for Statistical Computing, Vienna,
Austria. <https://www.r-project.org>
