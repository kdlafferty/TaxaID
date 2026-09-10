---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaAssign

Bayesian taxonomic assignment from match scores and priors. Part of the
[TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem.

## Overview

TaxaAssign makes a consensus taxonomic assignment for the several
hypothesized matches to each observation. It uses Bayes' theorem to
multiply the likelihood that a match score corresponds to a particular
species (from TaxaLikely) by the prior probability that the species
would be selected at random from a sample of similar species at that
site and habitat (from TaxaExpect). After normalization and Monte Carlo
simulation, each candidate receives a posterior probability. If a single
candidate has strong support, it is assigned as the consensus taxon;
otherwise, a coarser rank (genus, family, etc.) is assigned via lowest
common ancestor. All competing hypotheses and their probabilities are
retained in the output. The user can also update priors iteratively: if
one observation strongly supports species A, that evidence can sharpen
the prior for species A in other observations from the same sample.

Two workflows:

\- **Full Bayesian** -- TaxaLikely's trained likelihood model +
TaxaExpect's occurrence-modelled priors. The recommended pathway for any
real analysis: publication-quality, and every one of this ecosystem's
real production workflows uses it exclusively.

\- **LLM-shortcut** -- an approximate *stand-in* for the pathway above,
substituting an exponential score-weighting proxy for TaxaLikely's
modeled likelihood and an LLM's biogeographic judgment for TaxaExpect's
modeled occurrence prior. It exists for exploratory analysis when a
trained TaxaLikely model or TaxaExpect priors aren't available yet (or
as a quick comparison against the Full Bayesian result on data you
already have both for). This fast path is better than relying on scores,
but **not** the statistically defendable outcome that most users want.

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaAssign")
```

## Quick Start

### Full Bayesian workflow (recommended)

``` r
out <- run_bayesian_pipeline(
  match_df          = match_obj,         # from TaxaMatch
  model_params      = trained_model,     # from TaxaLikely
  taxaexpect_priors = priors,            # from TaxaExpect
  site = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine")
)
head(out$consensus)
```

### LLM-shortcut workflow (fast approximation -- no trained model/priors needed)

``` r
library(TaxaAssign)

out <- run_llm_pipeline(
  match_df        = match_obj,      # from TaxaMatch
  geographic_hint = "Southern California",
  barcode_term    = "12S"
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
in one call; accepts named unreferenced species from
`TaxaLikely::suggest_unreferenced_species()` via `unreferenced_taxa` --
see TaxaLikely's README for the full unreferenced-species mechanism) -
`join_priors()` -- merge TaxaExpect priors with likelihood output

**Consensus:** - `posterior_consensus()` -- LCA from posterior
probabilities - `score_consensus()` -- conventional score-based
consensus - `update_prior_from_consensus()` -- empirical Bayes
refinement

**High-level wrappers:** - `run_bayesian_pipeline()` -- Full Bayesian
(TaxaLikely + TaxaExpect -\> posteriors) -- recommended -
`run_llm_pipeline()` -- LLM-shortcut approximation (match_df -\>
posteriors in one call, no trained TaxaLikely model or TaxaExpect priors
needed)

**Context and reporting:** - `build_context()` -- auto-populate site
context from taxon names - `generate_report()` -- publication-ready
Methods + Results text - `report_assign()` -- lightweight section for
`assemble_report()`

## Statistical Methods

TaxaAssign computes Bayesian posterior probabilities for each candidate
taxonomic assignment:

$$P(H_i \mid D) = \frac{L(D \mid H_i) \times \pi(H_i)}{\sum_j L(D \mid H_j) \times \pi(H_j)}$$

where $L$ is the likelihood (TaxaLikely's trained model, or the
LLM-shortcut pathway's exponential score-weighting proxy) and $\pi$ is
the prior (TaxaExpect's occurrence model, or the LLM-shortcut pathway's
LLM-estimated biogeographic prior).

-   **Monte Carlo uncertainty propagation**: priors are modelled as
    Beta($\alpha$, $\beta$) distributions and likelihoods as
    Normal(mean, sd); 1000 simulations (default) propagate both sources
    of uncertainty into posterior means, SDs, and confidence scores
    (fraction of simulations won)
-   **Two workflows**: the full Bayesian workflow uses calibrated
    likelihoods from TaxaLikely's hierarchical model and
    spatially-explicit priors from TaxaExpect's kernel-based occurrence
    estimator; the LLM-shortcut workflow uses exponential score
    weighting ($L_i = e^{\lambda s_i}$) and LLM-estimated priors with
    information-quality-driven Beta concentration
-   **Posterior consensus**: the smallest set of hypotheses capturing
    \$\geq\$95% of posterior mass is identified; if multiple taxa
    remain, the lowest common ancestor (LCA) determines the consensus
    rank; downranking refines coarse assignments when only one
    finer-rank taxon exists at the study site
-   **Empirical Bayes refinement**: species confidently identified in
    one observation receive boosted priors in unresolved observations
    from the same study, analogous to shrinkage estimators (Efron and
    Morris 1973)
-   **Dark diversity fallback**: "dark diversity" is an ecological
    concept (Partel et al. 2011) for species that belong to the regional
    species pool and could plausibly occur at a site given its
    environmental conditions, but have not actually been observed there.
    TaxaExpect computes per-species Tier 3 ("undetected species")
    estimates using this concept -- see TaxaExpect's README for the full
    occurrence-modeling mechanism. For species with no prior row from
    TaxaExpect at all, `join_priors()` builds its own fallback from
    those Tier 3 estimates -- site-level or global averaging, or (with
    `singleton_taxonomy`) mass-conserving hierarchical group priors --
    preventing false negatives from incomplete occurrence data. See
    `join_priors()`'s own documentation for the full mechanism.

For the full statistical derivation, assumptions, and references, see
[`inst/TaxaAssign_supplemental_methods.md`](inst/TaxaAssign_supplemental_methods.md).

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

-   R (\>= 4.1.0; R Core Team 2025)
-   TaxaTools (foundation package)
-   TaxaLikely and TaxaExpect (for the Bayesian workflow; in Suggests)
-   An Application Programming Interface (API) key for an LLM provider
    (Anthropic Claude, Google Gemini, OpenAI, or local Ollama -- see
    TaxaTools) is needed for the LLM-shortcut workflow

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic PBC, San
Francisco, California).

## References

R Core Team (2025). R: A Language and Environment for Statistical
Computing. V.4.5.2. R Foundation for Statistical Computing, Vienna,
Austria. <https://www.r-project.org>
