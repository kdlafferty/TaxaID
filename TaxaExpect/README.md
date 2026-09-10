---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaExpect

Estimate spatially-explicit Bayesian priors for species occurrence. Part
of the [TaxaID](https://github.com/DOI-USGS/TaxaID) ecosystem.

A taxonomic assignment based on a match to a reference can propose an
implausible species. These are sometimes accepted as fact, but often are
screened afterwards, or prevented from occuring by reducing the
reference list to known local species.

Bayes' Theorem improves taxonomic assignment by considering the prior
probability that a hypothesized taxon occurs at the sampling location.
TaxaExpect estimates these priors from occurrence records. This is
typically GBIF (Global Biodiversity Information Facility; GBIF
Secretariat, Copenhagen, Denmark) records fetched via TaxaFetch, or
user-supplied data. Although occurrence data are often sparse and
biased, they are usually sufficient to distinguish among taxa with
similar match scores but very different geographic ranges. Various
species distribution models could be used to generate species priors.
TaxaExpect is one such method.

TaxaExpect uses a **site-centered distance kernel**: each species' prior
is its kernel-weighted share of related, nearby occurrence records,
computed directly at the query site. Weight decays smoothly with
distance (and, optionally, with a covariate such as depth), so spatial
borrowing degrades continuously rather than switching on or off at an
arbitrary cell boundary, and even lightly-sampled sites get informative
priors by shrinking toward the surrounding region's composition. The
kernel bandwidth is chosen from data via leave-one-block-out composition
prediction (`calibrate_kernel_bandwidth()`), not guessed, and the
resulting prior field can be mapped continuously over the study area
with `plot_theta_surface()`. For taxa never reported in the study area,
TaxaExpect prices a "dark diversity" prior from a Good-Turing/Chao-
anchored presence-distance curve.

The resulting spatial priors are helpful in reducing false positives
from ecologically implausible assignments and can break ties between
similar-scoring species, rescuing species-level resolution that would
otherwise be lost to defensive upranking.

## Overview

TaxaExpect generates theta priors (occupancy x detectability) for
taxonomic assignment from occurrence data. The current (kernel) pathway
estimates expected species composition directly at a site via
distance-weighted occurrence sharing, incorporating habitat
stratification and, optionally, a covariate such as depth.

Priors are organized into three branches (`prior_branch`):

-   **`resident_observed`** -- species with kernel-weighted local
    occurrence evidence (direct estimate)
-   **`resident_undetected`** -- species plausibly present but not
    locally recorded (singleton mirrors, a Good-Turing floor, and named
    claimants priced on a shared presence-distance curve)
-   **`transport`** -- domestic/food/cultivar species and other
    non-resident presence hypotheses

## Assumptions

### Shared detection effort

TaxaExpect models *relative* abundance: the probability that a randomly
selected observation at a site belongs to a given taxon. The denominator
`n_total_at_site` is the total count of all observations at a site and
serves as the shared effort measure for every taxon in the model.

**All taxa in a particular model should be detected through a similar
sampling process.** Combining taxa collected by incommensurable methods
corrupts the shared denominator: a phytoplankton cell count and a bird
point-count sighting are not equivalent detection events. Mixing them
implies that plankton-sampling effort informs expected bird relative
abundance, which is not true. The two surveys represent independent
detection processes.

*Problematic mixing (do not combine in a single model):*

-   Phytoplankton cell counts + bird point counts
-   eDNA reads from different gene markers (e.g. 12S fish reads combined
    with COI invertebrate reads; amplification efficiency differs
    between markers, so read counts are not on a shared effort scale)
-   Arthropods from pitfall traps + arthropods from Malaise traps

*Valid pooling:*

-   All fish species from the same eDNA marker on the same filter
-   All bird species detected during the same standardized point count
-   All macroinvertebrate taxa from the same kick-net sample

**This grouping is not automatic, and there is no automated way to make
it automatic.** `estimate_kernel_priors()` has no way to tell, on its
own, which taxa share a detection process -- if you leave
`sampling_group_col` unset, it silently pools every taxon into one
shared denominator regardless of detection process, with no warning and
no error. Supplying a correct grouping is your responsibility, and it
must be done by hand, from real knowledge of how each taxon was
detected -- there is no way to infer "comparable detection method" from
taxonomy or occurrence data alone (two co-occurring taxa sampled by
different gear look identical in an occurrence table). Automatic, data-driven classification of detection process does not
work reliably for this: tested against a real, full-scale expert-
classified dataset, it answered a different question than
`sampling_group` is meant to answer (whether a group clears a per-site
record-count floor, not whether it shares a detection process) -- it
fragmented a single real detection process into dozens of spurious
groups, and separately conflated two taxa an expert had deliberately
kept apart (a genuine marine survey target and likely airborne
contamination) purely because neither cleared the floor on its own. An
LLM guess at the grouping is not a substitute for
real methodological knowledge either, for the same reason: the
distinction lives in how the data were collected, not in anything
visible in the records themselves. Two options remain: 1) manually
choose similar taxa that are sampled in similar ways, the approach
this project's own analysts have used successfully for every real
dataset handled so far; or 2) build separate models for each survey
type and pass the appropriate priors to TaxaAssign for the relevant
taxonomic hypotheses.

Choosing a grouping by hand does not require worrying about sample
size. `estimate_kernel_priors()` does **not** need pre-merged,
sample-size-adequate groups for statistical adequacy -- it produces
honestly wide uncertainty for a small group on its own (confirmed on a
real 9-group expert classification, including a single-taxon group and
a 3-taxon group, both of which fit cleanly with appropriately wide
`theta_sd`). Classify at whatever granularity genuinely reflects
distinct detection methods, and let the estimator's own uncertainty
reflect how much data backs each group -- there is no separate merging
step to get right.

## Installation

``` r
# Requires TaxaTools (foundation package)
devtools::install("path/to/TaxaTools")
devtools::install("path/to/TaxaExpect")
```

## Quick Start

``` r
library(TaxaExpect)

# 1. Calibrate the kernel bandwidth (and regional back-off m) by
#    leave-one-block-out composition prediction -- never hand-set.
calib <- calibrate_kernel_bandwidth(
  occurrence_data = occurrences,   # habitat-labelled occurrence records
  site_habitat    = "Marine",
  lambda_grid     = c(10, 25, 50, 100, 200)   # km
)
lambda_km <- calib$best$lambda_km

# 2. Estimate kernel priors at your site (resident_observed rows)
kernel_fit <- estimate_kernel_priors(
  occurrence_data = occurrences,
  site_lat        = 34.45,
  site_lon        = -120.47,
  site_habitat    = "Marine",
  lambda_km       = lambda_km
)

# 3. Add resident_undetected rows (singleton mirrors + Good-Turing floor)
undetected <- generate_undetected_diversity(kernel_fit)

# 4. Assemble the prior table for TaxaAssign
priors <- dplyr::bind_rows(kernel_fit$priors, undetected)

# 5. Explore the prior field
plot_theta_surface(kernel_fit, occurrence_data = occurrences,
                    taxon = "Girella nigricans")
```

## Key Functions

### Kernel pathway (current, recommended) {#kernel-pathway-current-recommended}

**Calibration:** - `calibrate_kernel_bandwidth()` -- choose the
geographic bandwidth (and optional covariate bandwidth, and the regional
back-off mass `m`) by leave-one-block-out composition prediction

**Prior estimation:** - `estimate_kernel_priors()` -- site-centered
kernel estimation of `resident_observed` priors (no grid, no model
fit) - `generate_undetected_diversity()` -- singleton-mirror and
global-floor `resident_undetected` priors (accepts kernel or GLMM
input) - `generate_presence_curve_evidence()` /
`generate_user_specified_evidence()` +
`apply_undetected_evidence(pricing = "curve")` -- price named unobserved
claimants (regional, watch-listed, or distance-clamped) on a shared
presence-distance curve - `generate_domestic_food_priors()` --
`transport`-branch priors for domestic, food, and cultivar species

**Diagnostics and reporting:** - `plot_theta_surface()` -- continuous
prior-field map, evaluating the estimator on a lattice via FFT -
`kernel_budget_sensitivity()` --
reports how the Good-Turing budget behind `theta_present` moves across
counting radius/bandwidth choices - `report_priors()` -- generate report
section for `assemble_report()`

## Statistical Methods

TaxaExpect's current pathway prices each species' prior as its
kernel-weighted share of occurrence records in the focal-habitat
stratum, shrunk toward the regional composition by `m` pseudo-records (a
Dirichlet back-off):

```         
theta_i = (c_i * s + m * p_i) / (n_eff + m)
```

where `c_i` is species *i*'s summed distance-weighted record count
(`w_r = exp(-d_r/lambda_km)`, optionally multiplied by a covariate
factor such as depth), `s = n_eff / W` is an effective-scale factor,
`p_i` is the unweighted regional (habitat-stratified) record share, and
`n_eff = W^2 / sum(w_r^2)` is the Kish (1965) effective sample size of
the weighted neighborhood. `alpha = c_i*s + m*p_i` and
`beta = (n_eff + m) - alpha` are the row's Beta parameters directly --
no delta-method back-transformation, no phi cap/floor, no Jeffreys
fallback are needed, since `alpha`/`beta` are built from non-negative
counts and pseudo-counts by construction and cannot produce the boundary
pathologies a link-scale model can. `lambda_km` (and, if used, a
covariate bandwidth and `m`) is chosen from data by
`calibrate_kernel_bandwidth()`'s leave-one-block-out composition
prediction -- never hand-set.

For undetected species, a Good-Turing/Chao-anchored presence-distance
curve (`apply_undetected_evidence(pricing = "curve")`) prices each named
claimant as a two-point presence mixture, `theta = w * theta_present`,
where `theta_present` is the neighborhood's own observed singleton mean
and `w` comes from the claimant's distance to its nearest occurrence
record (or, for iNaturalist range evidence, from independent
verification).

**Real validation.** Leave-one-block-out testing -- holding out blocks
of occurrence records and scoring composition predictions against them
by multinomial log-loss -- found that single-cell GLMM prediction
scored *worse* than ignoring space entirely, while the kernel estimator
beat both regional pooling and the single-cell predictor at every
bandwidth tested. On real Great Lakes data, switching from the GLMM
baseline to the kernel estimator raised species co-detections from 237
to 564 and precision from 0.748 to 0.868 (independently validated
against a held-out checklist).

For the full statistical derivation, assumptions, and references, see
[`inst/TaxaExpect_supplemental_methods.md`](inst/TaxaExpect_supplemental_methods.md).

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

-   R (\>= 4.1.0; R Core Team 2025)
-   TaxaTools (foundation package)
-   TaxaFetch, TaxaHabitat (for fetching and habitat-labeling occurrence
    records upstream of the kernel pathway; in Suggests)

All dependencies are declared in the DESCRIPTION file and installed
automatically.

Developed with [Claude Code](https://claude.ai/code) (Anthropic PBC, San
Francisco, California).

## References

Chao, A. (1984). Nonparametric estimation of the number of classes in a
population. *Scandinavian Journal of Statistics*, 11(4), 265--270.

Good, I.J. (1953). The population frequencies of species and the
estimation of population parameters. *Biometrika*, 40(3-4), 237--264.

Kish, L. (1965). *Survey Sampling*. New York: Wiley.

R Core Team (2025). R: A Language and Environment for Statistical
Computing. V.4.5.2. R Foundation for Statistical Computing, Vienna,
Austria. <https://www.r-project.org>
