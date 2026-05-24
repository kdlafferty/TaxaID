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
family, etc.) is assigned via lowest common ancestor. All competing
hypotheses and their probabilities are retained in the output. The
user can also update priors iteratively: if one observation strongly
supports species A, that evidence can sharpen the prior for species A
in other observations from the same sample. By naming plausible species
missing from the reference library and assigning them likelihoods,
TaxaAssign reduces the false positives that occur when detections of
unreferenced species are incorrectly attributed to their closest
referenced relative.

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

## Statistical Methods

TaxaAssign computes Bayesian posterior probabilities for each
candidate taxonomic assignment:

$$P(H_i \mid D) = \frac{L(D \mid H_i) \times \pi(H_i)}{\sum_j L(D \mid H_j) \times \pi(H_j)}$$

where $L$ is the likelihood (from TaxaLikely or an exponential
score-weighting proxy) and $\pi$ is the prior (from TaxaExpect or
LLM estimation).

-   **Monte Carlo uncertainty propagation**: priors are modelled as
    Beta($\alpha$, $\beta$) distributions and likelihoods as
    Normal(mean, sd); 1000 simulations (default) propagate both
    sources of uncertainty into posterior means, SDs, and
    confidence scores (fraction of simulations won)
-   **Two workflows**: the full Bayesian workflow uses calibrated
    likelihoods from TaxaLikely's hierarchical model and
    spatially-explicit priors from TaxaExpect's GLMM; the
    LLM-shortcut workflow uses exponential score weighting
    ($L_i = e^{\lambda s_i}$) and LLM-estimated priors with
    information-quality-driven Beta concentration
-   **Posterior consensus**: the smallest set of hypotheses capturing
    $\geq$95% of posterior mass is identified; if multiple taxa
    remain, the lowest common ancestor (LCA) determines the consensus
    rank; downranking refines coarse assignments when only one
    finer-rank taxon exists at the study site
-   **Empirical Bayes refinement**: species confidently identified in
    one observation receive boosted priors in unresolved observations
    from the same study, analogous to shrinkage estimators (Efron and
    Morris 1973)
-   **Dark diversity fallback**: species absent from TaxaExpect's
    spatial model receive priors from Tier 3 (undetected species)
    estimates, preventing false negatives from incomplete occurrence
    data

For the full statistical derivation, assumptions, and references,
see [`inst/TaxaAssign_supplemental_methods.md`](inst/TaxaAssign_supplemental_methods.md).

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
