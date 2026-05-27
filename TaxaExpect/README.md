---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaExpect

Estimate spatially-explicit Bayesian priors for species occurrence. Part
of the [TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem.

Bayes' Theorem improves taxonomic assignment by considering the prior
probability that a hypothesized taxon occurs at the sampling location.
TaxaExpect estimates these priors from occurrence records (from
TaxaFetch or user-supplied data). Although occurrence data are often
sparse and biased, they are usually sufficient to distinguish among taxa
with similar match scores but very different geographic ranges.

TaxaExpect places occurrence data on a spatial grid (whose resolution is
optimized automatically) and fits a hierarchical model that accounts for
habitat type and spatial autocorrelation. These grid-based priors can be
mapped over occurrences using `plot_theta_map_interactive()`, so that
TaxaExpect becomes a full species distribution model.
The model can also incorporate environmental covariates such as
temperature or altitude, and it adjusts confidence based on sampling
effort at each site. For taxa never reported in the study area,
TaxaExpect generates "dark diversity" priors based on singleton
observations elsewhere. Spatial priors reduce false positives from
ecologically implausible assignments and can break ties between
similar-scoring species, rescuing species-level resolution that would
otherwise be lost to defensive upranking.

## Overview

TaxaExpect generates theta priors (occupancy x detectability) for
taxonomic assignment from occurrence data. Uses hierarchical spatial
models to estimate expected species composition at grid cells,
incorporating habitat type and geographic distance effects.

Three model tiers: - **Tier 1** -- species observed at the site (direct
estimate) - **Tier 2** -- species observed nearby (spatial
interpolation) - **Tier 3** -- species expected but unobserved (dark
diversity).

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaExpect")
```

## Quick Start

``` r
library(TaxaExpect)

# Option A: End-to-end wrapper (fetches GBIF, assigns habitat, builds priors)
priors <- build_priors(
  taxa = species_df,          # data frame with taxonomy columns
  geometry = bbox_wkt,        # WKT bounding box from TaxaFetch
  main_habitat = "Marine"     # site habitat
)

# Option B: Step-by-step pipeline
# 1. Grid the occurrence data
sites <- create_sites_from_grid(occurrences, grid_size = 0.25)

# 2. Optimize grid resolution
grid_results <- optimize_grid_size(occurrences, n_covariates = 2)

# 3. Prepare model data (zero-fill, add covariates)
model_df <- prepare_model_dataframe(sites)

# 4. Fit the spatial model
model_fit <- train_biodiversity_model(
  model_df,
  formula = presence ~ lat_r + lon_r + (1 | taxon_name)
)

# 5. Generate priors (Tier 1 + 2 + 3)
priors <- generate_full_priors(model_fit)
```

## Key Functions

**High-level wrapper:** - `build_priors()` -- end-to-end: GBIF fetch -\>
habitat -\> grid -\> model -\> priors

**Gridding:** - `create_sites_from_grid()` -- generate spatial grid
cells from occurrences - `optimize_grid_size()` -- find optimal grid
resolution for the study area

**Modeling:** - `prepare_model_dataframe()` -- zero-fill and add spatial
covariates - `compute_moran_basis()` -- Moran eigenvector maps for
spatial autocorrelation - `screen_spatial_formula()` -- evaluate
candidate model formulas - `train_biodiversity_model()` -- fit
hierarchical spatial model (glmmTMB)

**Prior generation:** - `generate_full_priors()` -- predict priors at
target sites (Tier 1 + 2) - `generate_undetected_diversity()` -- dark
diversity priors (Tier 3)

**Diagnostics and reporting:** - `plot_theta_map_interactive()` --
interactive Leaflet map of priors - `report_priors()` -- generate report
section for `assemble_report()`

## Statistical Methods

TaxaExpect fits a binomial generalized linear mixed model (GLMM) via
glmmTMB (Brooks et al. 2017). The response is the count of species *s*
at site *g* out of the total community count, modelled on the logit
scale with:

-   **Fixed habitat effects** capturing baseline differences across
    habitat types (Marine, Freshwater, Terrestrial, or IUCN L1
    categories)
-   **Random species intercepts** allowing each species its own baseline
    rarity, shrunk toward the global mean
-   **Random habitat slopes** (screened for data sufficiency) giving
    each species its own habitat preference
-   **Random spatial gradients** (latitude, longitude) per species,
    capturing geographic range trends
-   **Species x grid deviations** capturing local departures from the
    spatial surface; the variance of this term provides the principled
    ceiling for prior concentration

Model predictions are back-transformed via the delta method and
converted to Beta(alpha, beta) priors through moment-matching. A phi cap
(from the grid-level variance) prevents astronomically tight priors near
boundary theta values, while a phi floor (default 2) prevents modelled
priors from becoming less informative than dark diversity fallbacks. For
undetected species, singleton mirrors and a global floor prior Beta(1,
N-1) provide Tier 3 coverage.

Moran eigenvector maps (Dray et al. 2006) capture fine-scale spatial
autocorrelation beyond the latitude/longitude gradients and are included
by default in `build_priors()` (`moran_k = 5`).

For the full statistical derivation, assumptions, and references, see
[`inst/TaxaExpect_supplemental_methods.md`](inst/TaxaExpect_supplemental_methods.md).

## Vignettes

-   [Building Priors](vignettes/building-priors.Rmd) -- full workflow
    guide

## Part of TaxaID

TaxaExpect receives habitat-annotated occurrence data from TaxaHabitat
and produces spatially-explicit priors for TaxaAssign (posterior
computation).

**Ecosystem:** TaxaFetch -\> TaxaHabitat -\> **TaxaExpect** -\>
TaxaAssign

See the [TaxaID README](https://github.com/DOI-USGS/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID -- A modular R ecosystem for Bayesian
taxonomic assignment: U.S. Geological Survey software release,
<https://doi.org/10.5066/xxxxxx>.

## Software Requirements

-   R (\>= 4.1.0)
-   glmmTMB (for hierarchical biodiversity models)
-   TaxaTools, TaxaFetch, TaxaHabitat (for the `build_priors()`
    high-level wrapper; in Suggests)

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic).
