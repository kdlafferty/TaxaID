---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaAssign

Bayesian taxonomic assignment from match scores and priors. Part of the
[TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem.

## Overview

TaxaAssign makes a consensus taxonomic assignment for each
observation. It multiplies the likelihood that a match score
corresponds to a particular species (from TaxaLikely) by the prior
probability that the species occurs at the sampling location (from
TaxaExpect). A key feature is bridging gaps between these two inputs:
TaxaAssign generates likelihoods for species that have occurrence
records but are missing from the reference database, and generates
priors for species that appear in the reference but lack local
occurrence records (potential invaders or rare species). After
normalization and Monte Carlo simulation, each candidate receives a
posterior probability. If a single candidate has strong support, it is
assigned as the consensus taxon; otherwise, a coarser rank (genus,
family, etc.) is assigned via least common ancestor. All competing
hypotheses and their probabilities are retained in the output. The
user can also update priors iteratively: if one observation strongly
supports species A, that evidence can sharpen the prior for species A
in other observations from the same sample.

Two workflows:

\- **Full Bayesian** -- TaxaLikely likelihoods + TaxaExpect priors

\- **LLM-shortcut** -- exponentially-weighted scores + LLM biogeographic
priors

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaAssign")
```

## Quick Start

### LLM-shortcut workflow (simplest)

``` r
library(TaxaAssign)

out <- run_llm_pipeline(
  match_df        = match_obj,      # from TaxaMatch
  geographic_hint = "Southern California",
  barcode_term    = "12S"
)
head(out$consensus)
```

### Full Bayesian workflow

``` r
out <- run_bayesian_pipeline(
  match_df          = match_obj,         # from TaxaMatch
  model_params      = trained_model,     # from TaxaLikely
  taxaexpect_priors = priors,            # from TaxaExpect
  site = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine")
)
head(out$consensus)
```

### Step-by-step

``` r
# 1. Join priors to likelihood output
joined <- join_priors(likelihoods, priors,
                      site = list(grid_id = "G1", main_habitat = "Marine"))

# 2. Compute posteriors via Monte Carlo
posteriors <- compute_posterior(joined, n_sims = 1000)

# 3. Consensus taxonomy (LCA among plausible hypotheses)
consensus <- posterior_consensus(posteriors)

# 4. Generate report
report <- generate_report(posteriors, consensus)
```

## Key Functions

**Core assignment:** - `compute_posterior()` -- Bayes' theorem with MC
uncertainty - `assign_taxa_llm()` -- LLM-shortcut (priors + likelihoods
in one call) - `join_priors()` -- merge TaxaExpect priors with
likelihood output

**Consensus:** - `posterior_consensus()` -- LCA from posterior
probabilities - `score_consensus()` -- conventional score-based
consensus - `update_prior_from_consensus()` -- empirical Bayes
refinement

**Unreferenced species:** - `suggest_unreferenced_species()` --
LLM-first detection of missing taxa - `expand_unreferenced_hypotheses()`
-- name generic H2/H3 rows

**High-level wrappers:** - `run_bayesian_pipeline()` -- full Bayesian
(TaxaLikely + TaxaExpect -\> posteriors) - `run_llm_pipeline()` --
LLM-shortcut (match_df -\> posteriors in one call)

**Context and reporting:** - `build_context()` -- auto-populate site
context from taxon names - `generate_report()` -- publication-ready
Methods + Results text - `report_assign()` -- lightweight section for
`assemble_report()`

## Vignettes

-   [Taxonomic Assignment](vignettes/taxonomic-assignment.Rmd) -- full
    workflow
-   [TaxaID Ecosystem Overview](vignettes/taxaid-ecosystem.Rmd) --
    cross-package guide

## Part of TaxaID

TaxaAssign is the convergence point of the TaxaID ecosystem. It receives
likelihoods from TaxaLikely and priors from TaxaExpect, then passes
assignments to TaxaFlag for quality screening.

**Ecosystem:** TaxaLikely + TaxaExpect -\> **TaxaAssign** -\> TaxaFlag

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   TaxaTools (foundation package)
-   TaxaLikely and TaxaExpect (for the Bayesian workflow; in Suggests)
-   An LLM API key is needed for the LLM-shortcut workflow

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
