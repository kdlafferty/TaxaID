---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaExpect

Estimate spatially-explicit Bayesian priors for expected species
composition. Part of the [TaxaID](https://github.com/kdlafferty/TaxaID)
ecosystem.

An observation can easily match a similar, but implausible species.
These errors are often screened afterwards by an expert, or prevented
from occurring by reducing the reference list to known local species.
Both fixes are time consuming and problematic for several reasons.

Bayes' Theorem improves taxonomic assignment by quantifying the "prior"
plausibility of each candidate match. TaxaExpect estimates these priors
from occurrence records (e.g., positive records). A common source will
be GBIF (Global Biodiversity Information Facility; GBIF Secretariat,
Copenhagen, Denmark) records downloaded via TaxaFetch. But other data
types can be obtained through TaxaFetch, including user-supplied data.
Although occurrence data are often sparse and biased, they are usually
sufficient to distinguish among taxa with similar match scores but very
different geographic ranges. TaxaExpect's priors are compositional
shares, the expected relative share of a species at a site among similar
species (e.g., (Fish A records)/(all fish records)). Thus, priors sum to
1, which differs from an occurrence probability estimated from an
occurrence/occupancy model.

TaxaExpect predictions are spatial. They use a site-centered distance
kernel: each species' prior is its kernel-weighted share of related,
nearby occurrence records, computed directly at the query site. Weight
decays smoothly with distance (and, optionally, with a covariate such as
depth), so spatial borrowing degrades continuously rather than switching
on or off at an arbitrary distance, and even lightly-sampled sites get
informative priors by shrinking toward the surrounding region's
composition. The kernel bandwidth is chosen from data via
leave-one-block-out composition prediction
(`calibrate_kernel_bandwidth()`), not guessed, and the resulting prior
field can be mapped continuously over the study area with
`plot_theta_surface()` to generate species distribution surfaces. For
taxa never reported in the study area, TaxaExpect prices a "dark
diversity" prior from a Good-Turing/Chao- anchored presence-distance
curve.

The resulting spatial priors will often be coarse when derived from GBIF
and other similar unstandardized data sources, but are nonetheless
helpful in reducing false positives from ecologically implausible
assignments. In practice, a species with several nearby records will
have priors orders of magnitude higher than a similar species from
another continent. And that will be enough to rescue species-level
resolution that would otherwise be lost to defensive upranking.

## Overview

TaxaExpect generates theta priors for taxonomic assignment from
occurrence data. Theta is compositional: the expected relative share of
a species at a site, P(a random legitimate detection = species X). It is
not an occurrence probability, and not occupancy (see Shared detection
effort below for the formal definition). The kernel pathway
estimates expected species composition directly at a site via
distance-weighted occurrence sharing, incorporating habitat
stratification and, optionally, covariates such as depth, altitude, or
temperature.

Priors are organized into three branches (`prior_branch`):

-   `kernel_estimated`: species with kernel-weighted local occurrence
    evidence (direct estimate)
-   `resident_undetected`: species plausibly present but not locally
    recorded (singleton mirrors, a Good-Turing floor, and named
    claimants priced on a shared presence-distance curve)
-   `transport`: domestic/food/cultivar species and other non-resident
    presence hypotheses

![Interactive prior-field map produced by `plot_theta_surface()`. The
surface is the estimator evaluated continuously across a lattice, not
one value per grid cell, so it shows how a species' expected share
changes across the region rather than only at the sampling site. Here
theta for the ochre star (*Pisaster ochraceus*) declines with latitude,
the hollow circle marks the focal site. Passing several taxa to `taxon`
adds the layer toggle at top right, so priors can be compared species by
species. The surface is clipped to a supplied search polygon via `mask`,
which is why it stops at the coast instead of painting
inland.](man/figures/PisasterTheta.png)

## Assumptions

### Shared detection effort

TaxaExpect models relative abundance: the probability that a randomly
selected observation/report at a site belongs to a given taxon. The
denominator `n_total_at_site` is the total count of all "shared"
observations at a site and serves as the shared effort measure for every
taxon in the model.

All taxa in a particular model should be detected through a similar
sampling process. Combining taxa collected by very different methods
conflates effort: a phytoplankton cell count and a bird point-count
sighting are not comparable detections. Mixing them implies that
plankton-sampling effort informs expected bird relative abundance, which
is not true. The two surveys represent independent detection processes.

Clearly invalid pooling:

-   Phytoplankton cell counts + bird point counts
-   Fish from trawl surveys + vegetation transects
-   Arthropods from pitfall traps + bat vocalizations

Clearly valid pooling:

-   Fish species from a trawl survey
-   Bird species detected during point counts
-   Macroinvertebrate taxa from kick-net samples

The more similar the methods and taxa, the more valid the pooling.

This grouping is not automatic. `estimate_kernel_priors()` has no way to
tell, on its own, which taxa share a detection process. So if
`sampling_group_col` is unset, all taxa are pooled into a shared
denominator regardless of detection process, with no warning and no
error. Grouping must be done by 1) manually choosing similar taxa that
are sampled in similar ways, or 2) building separate models for each
survey type and passing the appropriate priors to TaxaAssign for the
relevant taxonomic hypotheses. Fine grouping reduces the effective
sample size and widens the standard deviations of the estimate.

In practice there is a trade-off between the convenience of pooling and
the accuracy of the shares. The consensus in TaxaAssign is less sensitive
than the shares themselves: the posterior is renormalized within each
observation, so a pooling choice that rescales every candidate for an
observation by the same factor leaves the consensus unchanged. Pooling
matters when an observation's candidates come from different detection
processes (a marine and a terrestrial candidate for the same read), and
wherever theta is read as an absolute share rather than compared within
an observation. Avoid pooling highly dissimilar taxa sampled by highly
dissimilar methods.

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

# 2. Estimate kernel priors at your site (kernel_estimated rows)
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

### Kernel pathway {#kernel-pathway}

Calibration:

-   `calibrate_kernel_bandwidth()`: choose the geographic bandwidth
    (and optional covariate bandwidth, and the regional back-off mass
    `m`) by leave-one-block-out composition prediction

Prior estimation:

-   `estimate_kernel_priors()`: site-centered kernel estimation of
    `kernel_estimated` priors (no grid, no model fit)
-   `generate_undetected_diversity()`: singleton-mirror and
    global-floor `resident_undetected` priors from a kernel fit
-   `generate_presence_curve_evidence()` /
    `generate_user_specified_evidence()` +
    `apply_undetected_evidence(pricing = "curve")`: price named
    unobserved claimants (regional, watch-listed, or distance-clamped)
    on a shared presence-distance curve
-   `fit_regional_presence_curve()`: fit that presence-distance
    curve's `w_scale`/`d_half` from a study's own data, as a
    self-calibrating alternative to `generate_regional_proximity_evidence()`'s
    defaults
-   `generate_regional_proximity_evidence()`: evidence rows for taxa
    with no in-bbox occurrence record but a real GBIF record just
    outside the study area, priced by distance to that record
-   `generate_inat_range_evidence()`: evidence rows for taxa inside
    their iNaturalist range polygon, sharing the same evidence-mixture
    framework as the other generators
-   `generate_invasive_watch_evidence()`: evidence rows for a
    user-supplied invasive/nonindigenous watch list, at a flat
    caller-chosen weight and confidence
-   `generate_uncertain_habitat_evidence()`: presence evidence for
    taxa whose nearby records all have unresolved habitat, so they are
    priced instead of dropped by the kernel estimator's habitat filter
-   `condition_evidence_on_habitat()`: multiply any evidence table's
    presence weights by each taxon's weight for the site habitat (from
    the cached LLM habitat lookup), floored at the zero-evidence
    clamp, so evidence obeys the same habitat stratification as the
    resident priors while habitat bleed survives in proportion
-   `generate_domestic_food_priors()`: `transport`-branch priors for
    domestic, food, and cultivar species

Diagnostics and reporting:

-   `plot_theta_surface()`: continuous prior-field map, evaluating the
    estimator on a lattice via FFT
-   `kernel_budget_sensitivity()`: reports how the Good-Turing budget
    behind `theta_present` moves across counting radius/bandwidth
    choices
-   `report_priors()`: generate report section for `assemble_report()`

## Statistical Methods

TaxaExpect's kernel pathway prices each species' prior as its
kernel-weighted share of occurrence records in the focal-habitat
stratum, shrunk toward the regional composition by `m` pseudo-records (a
Dirichlet back-off):

```         
theta_i = (c_i * s + m * p_i) / (n_eff + m)
```

where `c_i` is species i's summed distance-weighted record count
(`w_r = exp(-d_r/lambda_km)`, optionally multiplied by a covariate
factor such as depth), `s = n_eff / W` is an effective-scale factor,
`p_i` is the unweighted regional (habitat-stratified) record share, and
`n_eff = W^2 / sum(w_r^2)` is the Kish (1965) effective sample size of
the weighted neighborhood. `alpha = c_i*s + m*p_i` and
`beta = (n_eff + m) - alpha` are the row's Beta parameters directly:
no delta-method back-transformation, no phi cap/floor, no Jeffreys
fallback are needed, since `alpha`/`beta` are built from non-negative
counts and pseudo-counts by construction and cannot produce the boundary
pathologies a link-scale model can. `lambda_km` (and, if used, a
covariate bandwidth and `m`) is chosen from data by
`calibrate_kernel_bandwidth()`'s leave-one-block-out composition
prediction, never hand-set.

For undetected species, a Good-Turing/Chao-anchored presence-distance
curve (`apply_undetected_evidence(pricing = "curve")`) prices each named
claimant as a two-point presence mixture, `theta = w * theta_present`,
where `theta_present` is the neighborhood's own observed singleton mean
and `w` comes from the claimant's distance to its nearest occurrence
record (or, for iNaturalist range evidence, from independent
verification).

Real validation. Why not model on a grid? Leave-one-block-out testing,
holding out blocks of occurrence records and scoring composition
predictions against them by multinomial log-loss, found that
single-cell GLMM prediction scored worse than ignoring space entirely,
while the kernel estimator beat both regional pooling and the
single-cell predictor at every bandwidth tested. On real Great Lakes
data, the kernel estimator achieved 564 species co-detections and 0.868
precision, compared to 237 and 0.748 for a single-cell GLMM baseline
(independently validated against a held-out checklist).

For the full statistical derivation, assumptions, and references, see
[`inst/TaxaExpect_supplemental_methods.md`](inst/TaxaExpect_supplemental_methods.md).

## Part of TaxaID

TaxaExpect receives habitat-annotated occurrence data from TaxaHabitat
and produces spatially-explicit priors for TaxaAssign (posterior
computation).

Ecosystem: TaxaFetch -\> TaxaHabitat -\> TaxaExpect -\> TaxaAssign

See the [TaxaID README](https://github.com/kdlafferty/TaxaID) for
ecosystem overview and installation instructions.

## Citation

Lafferty, K.D., 2026, TaxaID, A modular R ecosystem for Bayesian
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
