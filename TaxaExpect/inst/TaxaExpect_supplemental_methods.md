---
editor_options: 
  markdown: 
    wrap: 72
---

# TaxaExpect: Statistical Background

## Spatially-Explicit Bayesian Priors for Species Occurrence

*This document provides the statistical rationale behind TaxaExpect. It
is intended as a manuscript-ready methods reference for the TaxaID
ecosystem.*

------------------------------------------------------------------------

## 1. Problem Statement

Taxonomic assignment from DNA, images, or sound recordings is
fundamentally ambiguous when multiple candidate taxa produce similar
match scores. Resolving this ambiguity requires prior information: the
probability that each candidate taxon occurs at the sampling location.
Without spatial priors, classifiers either (a) assign the top-scoring
candidate regardless of plausibility, producing false positives for
ecologically implausible taxa, or (b) conservatively uprank to genus or
family, losing species-level resolution.

TaxaExpect estimates these priors from occurrence records (typically
GBIF observations fetched by TaxaFetch and habitat-annotated by
TaxaHabitat). The core challenge is that abundance data are often not
available in a standardize manner across taxa, and presence-absence
(occurrence) data are sparse, spatially biased, and never exhaustive --
absence of a record does not mean absence of a species. Occurrence data
is also taxonomically biased, though less so than abundance data. One
way to reduce taxonomic bias is to estimate priors separately for
different taxonomic groups (e.g., fish, mammals, birds evaluated as
distinct sampling groups). TaxaExpect estimates priors by weighting
every occurrence record's contribution to a study site by its distance
(and, optionally, its similarity on covariates such as depth) from that
site, so that spatial borrowing degrades smoothly with distance rather
than switching on or off at an arbitrary spatial boundary, and produces
informative priors even for lightly sampled sites by shrinking toward
the surrounding region's composition.

An earlier version of TaxaExpect aggregated occurrence records into a
fixed grid and fit priors with a spatial hierarchical generalized linear
mixed model (GLMM), predicting each site's priors from its single
nearest grid cell. Leave-one-block-out validation -- holding out blocks
of occurrence records and scoring composition predictions by
multinomial log-loss against the held-out records -- found that this
single-nearest-cell predictor scored *worse* than ignoring space
entirely (unweighted regional pooling), while a continuous distance
kernel beat both. That empirical result, not a stylistic preference, is
why the grid/GLMM architecture was retired in favor of the kernel
estimator described in the rest of this document (Section 5 reports the
specific numbers). The GLMM functions remain in the package, deprecated
(each emits a one-time notice pointing to its kernel replacement) for
reference and backward compatibility, but are not described further
here.

------------------------------------------------------------------------

## 2. Kernel Bandwidth Selection: Leave-One-Block-Out Composition Prediction

The kernel estimator (its functional form is defined precisely in
Section 4) has tuning values -- principally the geographic bandwidth
`lambda_km`, and optionally a covariate bandwidth and the regional
back-off mass `m` -- that must be chosen from data rather than guessed.
`calibrate_kernel_bandwidth()` chooses them by out-of-sample composition
prediction, replacing the retired architecture's AIC-based formula
screening (`screen_spatial_formula()`, no longer described here):

1.  **Partition** occurrence records into spatial blocks (default
    0.5-degree squares; a block enters scoring only if it holds at
    least `min_block_records`, default 20, records). This is the one
    place a grid survives the kernel redesign, and the only job it
    keeps: a cross-validation device that imposes no structure on the
    estimator itself.
2.  **Predict** each held-out block's species composition from every
    record *outside* it, using the same kernel machinery evaluated at
    the block's own data centroid.
3.  **Score** each candidate parameter combination by per-record
    multinomial log-loss against the block's actual records
    (Laplace-smoothed so a held-out species never scores `-Inf`), summed
    over all scored blocks and record-weighted.
4.  **Compare against two references**, scored the same way, for
    context: `regional` (all held-out records, unweighted -- tests
    whether locality is worth anything at all) and `nearest_block` (the
    single nearest other block's composition -- the retired
    one-cell-per-site architecture).

The parameter combination with the lowest weighted log-loss among
kernel rows is reported as `best`, alongside the full results table so
the choice can be audited rather than taken on faith.

**The empirical finding that motivated the redesign.** On real Great
Lakes occurrence data (Burns Harbor, 21 scored blocks), per-record
log-loss (lower is better) was: `nearest_block` (single nearest cell)
3.659 -- the *worst* of every option tested; `regional` (no spatial
structure at all) 3.526; kernel bandwidths ranging from 3.538 (10 km) to
3.267 (25 km, the interior optimum) to 3.384 (100 km). The single-cell
predictor -- the retired architecture -- scored worse than ignoring
space entirely, while the distance kernel beat both regional pooling
and the single-cell predictor at every bandwidth from 25 km to 100 km.
Adding a depth covariate kernel (Section 4.2) improved prediction
further beyond the geographic-only optimum: the best combined
configuration (geographic bandwidth 100 km, depth bandwidth 25) scored
3.214, an out-of-sample improvement earned by the covariate, not merely
correlated with it.

Bandwidths are calibrated per dataset; the numbers above are a worked
example, not universal constants. `lambda_latitude_grid` always
includes `Inf` (the absolute-latitude climate factor switched off, see
Section 4.2) explicitly in the sweep, so the no-factor case competes on
equal footing rather than being assumed necessary.

------------------------------------------------------------------------

## 3. Occurrence Data and Habitat Stratification

`estimate_kernel_priors()` takes cleaned, habitat-labelled occurrence
records (one row per record: taxon name, latitude, longitude, habitat
category, and optionally a numeric covariate such as depth) plus the
query site's own coordinates, focal habitat, and calibrated bandwidth.

**Habitat stratification happens first, before any distance weighting.**
Records are restricted to `habitat_col == site_habitat` before the
kernel is ever evaluated -- a species recorded only in a different
habitat contributes zero weight to this site's estimate. This is
stricter than the retired architecture, which could extrapolate a
species into a habitat it had never been recorded in via the model's
fixed habitat effect (with the `observed_in_habitat` flag marking that
extrapolation as risky, Section 3 of the retired design). Under the
kernel estimator, every `resident_observed` row carries
`observed_in_habitat = TRUE` by construction, because a row simply
cannot exist otherwise -- there is no cross-habitat interpolation risk
left to flag for these rows. The corresponding gap this stratification
opens (a species genuinely present but recorded in the *wrong* habitat)
is not resolved by widening the stratum; it is addressed, where it is
addressed at all, by the separate transport branch (Section 7.4).

**Covariates** are supplied per record and per site (e.g. `depth_m`);
records with a missing covariate value receive the neutral weight 1 for
the covariate factor (the geographic distance factor still applies)
rather than being dropped, so a covariate gap in older records does not
silently shrink the effective neighborhood.

**Site identity.** The site is identified by a `site_id` string, stamped
into the output table's `grid_id` column for downstream join
compatibility with `TaxaAssign::join_priors()`; the value is opaque
everywhere downstream of TaxaExpect (it need not, and under this
architecture does not, name an actual grid cell).

------------------------------------------------------------------------

## 4. The Kernel Estimator

Each species' prior is its kernel-weighted share of occurrence records
in the focal-habitat stratum, shrunk toward the regional composition by
`m` pseudo-records:

```         
theta_i = (c_i * s + m * p_i) / (n_eff + m)
```

where `c_i` is species *i*'s summed record weight, `s = n_eff / W` is an
effective-scale factor, `p_i` is the unweighted regional (habitat-
stratified) record share, and `n_eff` is the Kish (1965) effective
sample size of the weighted neighborhood (Section 4.3). `alpha_i = c_i *
s + m * p_i` and `beta_i = (n_eff + m) - alpha_i` are the row's Beta
parameters directly (Section 6); `effective_records_i = c_i * s` is
reported as its own column, in units of records (Section 4.3).

### 4.1. Geographic Kernel

Each record's weight decays exponentially with its great-circle-
approximate distance to the site:

```         
d_r = 111 * sqrt( (lat_r - site_lat)^2 +
                   ((lon_r - site_lon) * cos(site_lat * pi/180))^2 )   # km
w_r = exp(-d_r / lambda_km)
```

with longitude cosine-corrected for the site's latitude. `lambda_km` has
no default: the defensible value is dataset-specific, so it must come
from `calibrate_kernel_bandwidth()` (Section 2) rather than being
guessed or hand-set. A hard grid cell is the special case of a top-hat
kernel: with all weights equal, `theta` reduces to ordinary record
shares, `n_eff` to the raw record count, and the singleton set (Section
7.1) to species seen exactly once -- the classical grid quantities are
a limiting case of this estimator, not a different one.

### 4.2. Covariate and Latitude Kernels

An optional numeric covariate (e.g. depth, distinguishing pelagic from
nearshore species) multiplies the geographic factor as a product kernel:

```         
w_r = exp(-d_r / lambda_km) * exp(-|cov_r - site_cov| / lambda_cov)
```

`lambda_cov` is likewise calibrated, never hand-set. At Great Lakes this
factor validated out-of-sample under leave-one-block-out prediction
(Section 2: 3.267 -> 3.214 combined-best log-loss), so it is included by
default there; the improvement is a data-supported inclusion decision,
not an assumption.

An optional absolute-latitude climate-similarity factor was also
implemented:

```         
w_r = w_r * exp(-111 * ||lat_r| - |site_lat|| / lambda_latitude)
```

The factor is built on *absolute* latitude so that a record from the
same climate band in the opposite hemisphere (e.g. 42 deg S relative to
a 42 deg N site) is not penalized as if it were 84 degrees away -- the
intent is to make north-south kilometers cost more than east-west
kilometers, capturing climate rather than raw distance. It is opt-in
(`lambda_latitude = NULL` disables it exactly) and was evaluated by the
same leave-one-block-out procedure as every other bandwidth. It was
**rejected at regional scale by both datasets tested**: `lambda_latitude
= Inf` (the factor switched off) won the sweep at both Great Lakes and
Point Conception. This is reported as an honest negative result, not
omitted: at the geographic extent of a single study site, latitude and
geographic distance are too collinear for the factor to add distinct
information. Its more plausible home is a continental-scale presence
curve for unobserved taxa (Section 7.2), where it has not yet been
wired in.

### 4.3. Regional Back-off and Schema

`m` pseudo-records of the region's own (unweighted, habitat-stratified)
composition `p_i` are blended in as a Dirichlet back-off, shrinking
lightly-supported species toward the surrounding region rather than
toward a flat global mean. The default `m = 1` is a weakly-informative
single pseudo-record; `m = 0` disables shrinkage entirely; both `m` and
`lambda_km` can be swept jointly by `calibrate_kernel_bandwidth()`.

`n_eff = W^2 / sum(w_r^2)` is the Kish (1965) design-effect / effective
sample size of the weighted neighborhood -- the same construction used
to correct variance estimates for unequal sampling weights in survey
statistics, applied here to a neighborhood defined by distance rather
than a sampling design. It is the total concentration `alpha + beta =
n_eff + m` backing every row at this site: a site with many effectively
equal-weight nearby records has high `n_eff` and a tightly concentrated
prior; a site whose only nearby evidence is a few weakly-overlapping
distant records has low `n_eff` and a diffuse one, whatever the raw
record count in the stratum happens to be.

The output table's schema reflects this directly, replacing the retired
architecture's discrete `model_tier` vocabulary (`"tier1"` /
`"tier2"` / `"tier3_undetected"`) with two columns:

-   **`prior_branch`** (character): which part of the framework a row
    belongs to. `"resident_observed"` marks the kernel-fitted rows
    described in this section; `"resident_undetected"` marks the
    floor/singleton/evidence rows described in Section 7; `"transport"`
    marks domestic/food rows (Section 7.4). `TaxaAssign::join_priors()`
    reads this column directly, rather than checking `model_tier`
    values, to decide which rows are eligible for its habitat-mismatch
    promotion logic.
-   **`effective_records`** (numeric, continuous): the kernel-effective
    record count `c_i * s` backing the row, in count units. A species
    with 4.3 effective records is priced continuously on that scale,
    rather than being binned into a `>= 5 detections` / `< 5 detections`
    tier split as the retired architecture did.

`model_tier` is retained on rows built by the still-functional (but
deprecated) GLMM path, and on a handful of downstream columns for
backward compatibility, but carries no meaning on kernel-estimated
rows.

### 4.4. Computation

The estimator is exactly that -- an estimator evaluated once at
prediction time, never a latent spatial model. One pass over the
occurrence records computes every species' weight simultaneously (0.11
seconds at 1.8 million records, measured), so cost is independent of
species count and there is no iterative optimization or convergence
step to monitor, unlike the retired GLMM's Laplace-approximation fit
(minutes-scale, with its own convergence diagnostics, Section 4.4 of
the retired design). Per-species latent spatial fields (Gaussian
process / SPDE / per-taxon GAMM smooths) were considered during the
original design and are deliberately excluded: that family is
computationally infeasible at many-species scale (an hours-scale cost
the original exploration hit directly), and the kernel achieves
comparable or better held-out predictive performance (Section 2)
without paying it.

------------------------------------------------------------------------

## 5. Validation

Reported here as fact, with its scope stated plainly: these are the
two datasets validated as of this writing, and the numbers below are
specific to them, not universal guarantees.

**Great Lakes (held-out external checklist, Lamar validation harness).**
Relative to the GLMM baseline evaluated at the correct grid cell
(species co-detections 237, precision `both/(both+ours_only)` 0.748):
switching to the kernel estimator alone raised species co-detections to
564 and precision to 0.868. Layering curve pricing for unobserved taxa
(Section 7) on top raised co-detections further to 594, with precision
easing slightly to 0.853 -- still comfortably above the 0.748 baseline
and gate. Resolution of held-out observations rose from 211 to 489 (of
885) at the kernel step and to 506 with curve pricing; species gained
across both changes were overwhelmingly corroborated by the independent
Lamar checklist (27 of 29 newly-resolved unique species at the kernel
step; the curve-pricing step's four additional species gains were
strictly additive, zero losses).

**Point Conception (a data-rich site, used as a near-invariance
control, not a discovery test).** Comparing the kernel estimator
against the workflow's exact GLMM fit on the same occurrence pool
(1.25 million Marine-stratum records; kernel bandwidth 25 km,
leave-one-block-out chosen): the kernel reproduced the GLMM's
abundant-species estimates within 3-5% (top-10 species by `theta`,
`|log10(kernel/GLMM)| <= 0.05`). Across all 507 shared species, Spearman
rank correlation was 0.923 overall and 0.927 restricted to the GLMM's
tier-1 (best-supported) rows. The larger divergences were concentrated
in rows the GLMM had priced either by its wrong-habitat promotion clause
(a real species detected in the wrong habitat, promoted to singleton
parity by the retired architecture) or by its own epsilon-clamp
artifact (`theta = 1e-6` exactly -- not a model prediction, a numerical
floor); the kernel prices both classes of row far lower and, per the
same leave-one-block-out predictive standard used at Great Lakes, more
honestly. The control's purpose -- no wild behavior at a site with
abundant local data -- is met: the head of the distribution is
essentially invariant, and the tail is corrected in the direction both
datasets' predictive validation favors.

Both datasets independently rejected the absolute-latitude climate
factor (Section 4.2) at regional scale.

------------------------------------------------------------------------

## 6. From Kernel Weights to Beta Priors

### 6.1. Direct Construction

Unlike the retired architecture, the kernel estimator's Beta parameters
are not back-transformed from a link-scale prediction and standard
error -- they are built directly from the same count-like quantities
used to compute `theta`:

```         
alpha = c_i * s + m * p_i
beta  = (n_eff + m) - alpha
theta_mean = alpha / (alpha + beta)
theta_sd   = sqrt( alpha * beta / ((alpha + beta)^2 * (alpha + beta + 1)) )
```

The concentration `alpha + beta = n_eff + m` is the effective sample
size backing the estimate: higher concentration (more effectively
supporting records, or a larger back-off mass at a data-poor site) means
a more informative prior, exactly as in the retired architecture's
`phi`, but now equal to a quantity the estimator already computes for
`theta` itself rather than a separate variance-propagation step.

### 6.2. Why the Retired Safeguards No Longer Apply

The retired architecture needed a phi cap (bounding concentration by the
model's own `taxon_name:grid_id` random-effect variance), a phi floor
(a minimum concentration, `min_phi`), a Jeffreys fallback (Beta(0.5,
0.5) when phi collapsed to zero or below), and extrapolation warnings
(flagging sites far outside the training covariate range) because its
predictions were made on the logit link scale and back-transformed by
the delta method -- a transformation that can produce concentration
values that explode near `theta` = 0 or 1, or collapse to zero or
negative under covariate extrapolation. (One of these, the phi cap, was
already failing open in production before the kernel redesign: its
`VarCorr` lookup for the `taxon_name:grid_id` term was silently falling
back to a fixed value of 1000 rather than the intended model-derived
ceiling -- a pre-existing bug, not something the kernel path
introduces or must reproduce.)

The kernel estimator has no analogous failure mode to guard against:
`alpha` and `beta` are built from non-negative counts and pseudo-counts
by construction, so they cannot go negative and there is no link-scale
transformation to blow up. None of the four safeguards above are
needed on kernel-estimated rows. (The global floor prior for genuinely
undetected species, Section 7.1, retains its own small-`N` Jeffreys
fallback, which is a different mechanism serving a different purpose
and is unaffected by this.)

------------------------------------------------------------------------

## 7. Unobserved Taxa: Presence-Distance Curve Pricing

A species with a detection in the sequence (or image, or acoustic) data
but no occurrence record anywhere in the focal-habitat stratum cannot
receive a `resident_observed` row -- there is nothing local to weight.
`apply_undetected_evidence()`'s curve pricing prices such a candidate as
a two-point presence mixture:

```         
theta = w * theta_present,   theta_absent = 0
```

with probability `w` the species is locally present, contributing
`theta_present`; with probability `1 - w` it is absent, contributing
nothing. This replaces an earlier floor-additive blend (`theta = floor +
w * (ceiling - floor)`) whose additive floor term dominated nearly every
elevated row regardless of the evidence weight; the two-point mixture
is the more literal reading of what the evidence is actually claiming.

### 7.1. Good-Turing and Chao Anchors: `theta_present`

Within the kernel neighborhood, a species counts as a **singleton** if
exactly one of its supporting records carries kernel weight at or above
`support_weight` (default `exp(-3)`, i.e. within about 3 bandwidths);
`f1` and `f2` are the counts of singleton and doubleton species by the
same criterion. (Continuous quantities -- `theta`, `n_eff` -- always use
every record regardless of this support-weight cutoff; `f1`/`f2` are
discrete-support statistics only.)

-   **Missing mass** (Good 1953): the summed effective share of
    singleton species, `sum(c_i for i in singletons) / W`. Under a
    top-hat kernel this reduces to the classical `f1 / n`. It is the
    fraction of a random draw expected to belong to a species not yet
    recorded at all in the neighborhood -- the resident-undetected
    branch's total budget.
-   **Chao missing-species count** (Chao 1984): `f1^2 / (2*f2)`, with
    the standard `f1*(f1-1)/2` fallback when `f2 = 0`, and `0` when
    `f1 = 0` (no anchor at all).
-   **`theta_present` = missing mass / Chao missing-species count**: the
    typical unseen resident's share if present -- the missing-mass
    budget divided evenly across the estimated number of species that
    hold it. This single per-species rate is applied to *every*
    unobserved claimant at a site, regardless of identity: absence of
    any record already caps the plausible share-if-present for a
    generic unseen species (an occurrence-generating process with a
    materially higher share would very likely have produced at least
    one record in the effective neighborhood already).

A concrete illustration of how this scales with local sampling density:
at Point Conception (data-rich; `f1 = 48`, `f2 = 16`, missing mass
1.86e-4), `theta_present = 2.59e-6`. At the Great Lakes Burns Harbor
site (far less densely sampled), the corresponding missing mass and
Chao estimate give `theta_present = 2.04e-4` -- about 80 times coarser.
A data-poor neighborhood spreads its (larger, less precisely
partitioned) missing-mass budget across a much smaller estimated number
of unseen species, so each one is priced, if present, at a
correspondingly higher rate; a data-rich neighborhood prices unseen
species far more finely. This is the intended behavior of a Good-
Turing/Chao-anchored rate, not an artifact.

### 7.2. The Presence-Distance Curve

`w`, the presence probability multiplying `theta_present`, comes from
one shared distance curve serving three claimant classes:

```         
w = w_scale * exp( -min(d, d_cap) / (k * d_half) )
```

-   **`w_scale`**: the curve's ceiling -- the presence probability for a
    species with a record at the site itself. Calibrated against a
    local checklist, not hand-set: at Great Lakes, `w_scale = 0.05`
    (zero of 110 zero-local-record checklist candidates were actually
    present).
-   **`d_half` (default 150 km)** and **`d_cap` (default 1000 km)**: the
    curve's e-folding half-distance and instrument-cap distance. Beyond
    `d_cap` the curve is deliberately flat rather than extrapolated
    toward zero, because the far tail beyond the search radius is
    judged to be dominated by distance-insensitive human-vectored
    transport rather than biogeographic range decay -- a stated
    modeling judgment, not a measured constant. At the adopted defaults
    this **distance clamp** prices every candidate with no measured
    distance at `w_scale * exp(-d_cap/d_half) = 6.4e-5`.
-   **`k` (default 1; `k = 2` for watch-listed species)**: a bandwidth
    stretch. A listed invasive/watch species is priced with its
    bandwidth stretched `k`-fold, which is an exact log-space
    half-way interpolation toward full plausibility (`exp(-d/(k*
    lambda)) = [exp(-d/lambda)]^(1/k)`), evaluated at that species' own
    distance to its nearest record or nearest established population.
-   **Plain regional pricing** (`k = 1` with a measured distance): named
    species with a real occurrence record just outside the study area,
    priced by their actual distance.

**Independent-instrument treatment of iNaturalist range evidence.**
Verified iNaturalist range coverage is priced on its own scale
(`w = 0.8`, name-gated) rather than folded into the distance curve: a
recent, human-verified, name-matched observation is evidentially a
different kind of claim than distance-decayed historical occurrence
density, and is not naturally comparable on the same distance scale.

**A safety check on the clamp.** Of 221 non-regional candidates priced
at the distance clamp in the Great Lakes validation run, zero were
later confirmed present; a Jeffreys-interval upper bound on the true
miss rate from that 0-of-221 count is about 2.3e-3. Any future confirmed
clamp-priced detection is a documented tripwire for revisiting the
clamp value, not something the current design assumes cannot happen.

**User-specified overrides.** `generate_user_specified_evidence()` lets
a caller assert a presence probability directly for a named species
(e.g. a deliberate surveillance policy), bypassing the distance curve
entirely. Because `theta_present` sits near the singleton scale, a
weight above about 1/9 begins materially reducing a co-occurring
singleton-level observed native's posterior share at likelihood parity;
the function discloses this automatically whenever a supplied weight
crosses that threshold. The outright veto bound (the weight at which an
unobserved candidate could block species-level resolution of an
observed native entirely) works out to roughly 19-23 times
`theta_present` at the datasets validated so far -- unreachable for any
admissible weight `<= 1`, and printed exactly, per dataset, by
`apply_undetected_evidence()`.

### 7.3. Budget Audit

`theta_present * chao_missing = missing_mass` by construction, so the
sum, in count units, of presence probabilities `w` across all named
zero-record claimants can be compared against the Chao estimate of the
number of locally-present-but-unrecorded species as a diagnostic: how
much of the Good-Turing unseen-mass budget did the named claimants
collectively draw on? At Great Lakes, `sum(w) = 6.67` against a Chao
estimate of 14.4 missing species (comfortably within budget; iNaturalist
evidence alone accounted for 4.0 of the 6.67).

This audit is deliberately **reported, not enforced**. Renormalizing
named claimants' weights so they sum exactly to the Chao budget was
considered and rejected: it would make any one species' prior depend on
how many *other* species happen to be enumerated as candidates in a
given run -- a property of the candidate list, not of the species
itself; it would erase the graded, per-species distance/evidence
structure the curve was built to preserve; and it degenerates when
`f1 = 0` (no singleton anchor at all), zeroing the entire branch rather
than falling back gracefully. Probability constraints are enforced
instead where they actually bind operationally: at per-observation
renormalization across the candidate set in
`TaxaAssign::compute_posterior()`, not at prior-construction time.

### 7.4. The Compositional Framework

`theta_i` is defined compositionally throughout this document: the
expected share of a random legitimate detection at the site/habitat
that belongs to species *i*. Only ratios reach posteriors -- per-
observation renormalization is where probability actually binds.

The community whose shares sum to 1 is the **resident community**:
observed shares (`resident_observed` rows, Section 4) plus the Good-
Turing unseen mass (Section 7.1-7.3), whose interior -- which
unrecorded species, in what proportion -- is deliberately never
enumerated by any single named row. Each named `resident_undetected`
evidence row is a claim *on a slice of* that mass, not a partition of
it (Section 7.3's audit measures, rather than enforces, how much of the
slice a run's named claimants have taken).

Non-regional species, watch-listed invaders, and transport (domestic and
food species now; cross-habitat DNA bleed, not yet built, would join
this branch) are presence-weighted hypotheses that sit **outside** that
simplex, each calibrated against its own measurement: a local checklist
for the regional/invasive `w_scale`; iNaturalist's own verification
process for its `w`; a measured transport read-share for domestic/food
species (Section 7.4's own generator, below, and the analogous future
bleed generator). These branches are commensurable with the resident
branch -- expressed in the same units, expected share of a random
record -- because rows from every branch meet inside one
TaxaAssign candidate set and must be compared directly. Commensurability
is what makes that comparison meaningful; it is not a claim that every
branch together sums to exactly 1 -- only the resident simplex does.

`generate_domestic_food_priors()` populates the transport branch for
domestic animals, food species, and known/candidate cultivars, stamping
`prior_branch = "transport"` and a finer `prior_source_type`
(`"domestic_animal"`, `"food_species"`, `"domestic_plant"`, etc.) for
provenance. Under the kernel path, a wild species detected only outside
its recorded habitat (the cross-habitat "bleed" case) is not yet priced
by any transport-branch mechanism: unlisted wild bleeders fall to the
resident-undetected floor until a dedicated bleed generator exists.
Listed domestic species already carry a transport row close to the
measured bleed rate; this gap is acknowledged here as a known,
interim limitation rather than something the current curve silently
papers over.

------------------------------------------------------------------------

## 8. Assembling the Prior Table

There is currently no single kernel-path equivalent of the retired
`build_priors()` wrapper (which remains the GLMM-only convenience
function, deprecated but unchanged in behavior). The kernel pipeline is
assembled from its component functions, typically in this order:

1.  Fetch and habitat-label occurrence records (TaxaFetch, TaxaHabitat --
    unchanged from the retired pipeline).
2.  `calibrate_kernel_bandwidth()` -- choose `lambda_km` (and, if used,
    `lambda_covariate`, `lambda_latitude`, `m`) by leave-one-block-out
    prediction (Section 2).
3.  `estimate_kernel_priors()` -- fit the `resident_observed` rows at
    the study site (Sections 4, 6).
4.  `generate_undetected_diversity()` -- `resident_undetected`
    floor/singleton rows from the same kernel object (Section 7.1); the
    function's rules are unchanged from the retired architecture, only
    re-plumbed onto kernel ingredients (`N` becomes the Kish `n_eff`;
    singletons are the kernel's neighborhood singletons, stamped with
    the site's own id rather than a distant donor cell's).
5.  `generate_presence_curve_evidence()` and/or
    `generate_user_specified_evidence()`, combined via
    `apply_undetected_evidence(pricing = "curve")` -- price named
    unobserved claimants (Section 7.2).
6.  `generate_domestic_food_priors()` -- transport-branch rows
    (Section 7.4).
7.  `dplyr::bind_rows()` the results into one `taxaexpect_priors`
    table, which `TaxaAssign::join_priors()` consumes exactly as it did
    the retired architecture's output -- `grid_id` remains an opaque
    join key throughout.

------------------------------------------------------------------------

## 9. Assumptions and Limitations

**Sampling bias:** Occurrence records from GBIF and similar sources are
opportunistic, not systematic. The kernel's regional back-off (Section
4.3) and distance weighting partially mitigate this, but cannot fully
correct geographic or taxonomic sampling bias. As before, posteriors
depend on the *contrast* between priors for competing hypotheses, not
on the absolute accuracy of any single prior, and this contrast is
often robust to sampling bias for the same two reasons as before: (1)
biases tend to be taxonomically correlated -- congeners in the same
region are usually sampled with similar effort, preserving relative
ordering even when absolute values are poorly calibrated; and (2) the
most common disambiguation scenario involves congeners with non-
overlapping ranges, where even coarse occurrence data reliably
distinguishes the locally present species from a distant relative.

**Effective sample size reflects effort, not community size:** `n_eff`
(Section 4.3) reflects how much effectively-independent local evidence
exists, which tracks sampling effort more than true community size --
the same caveat that applied to the retired architecture's raw record
count `N`. Unlike the retired architecture, the kernel estimator does
not exclude low-effort sites outright (there is no `effort_threshold`
cell exclusion); instead, low `n_eff` sites lean more heavily on the
`m`-pseudo-record regional back-off, continuously rather than via a
hard cutoff.

**Habitat classification:** Records are stratified to the site's own
habitat before any weighting (Section 3), so a misclassified habitat
record contributes zero weight to that site's estimate rather than
propagating an incorrect extrapolated prior, as could happen under the
retired architecture's fixed habitat effect. The corresponding tradeoff
is Section 7.4's transport-branch gap: a genuinely present species
recorded only in the wrong habitat currently receives a transport row
only if it is on the domestic/food list; other wrong-habitat wild
species fall to the resident-undetected floor until a dedicated bleed
generator is built.

**Local representativeness:** The kernel assumes that locally-weighted
composition, out to roughly the calibrated bandwidth, is representative
of the site itself. A sharp ecological boundary closer than the
bandwidth (e.g. a biogeographic transition) is smoothed across rather
than respected exactly; a covariate kernel correlated with the boundary
(e.g. depth) can sharpen this where validated (Section 4.2), but the
absolute-latitude climate factor tested as a general-purpose fix was
rejected by leave-one-block-out prediction at regional scale at both
datasets tested (Section 4.2, Section 5).

**Unobserved-taxa pricing is uniform by design, and audited rather than
constrained:** `theta_present` (Section 7.1) applies the same rate to
every unobserved claimant at a site regardless of identity; a
claimant's own establishment or abundance evidence raises its presence
probability `w`, never `theta_present` itself. The budget audit (Section
7.3) reports, but does not enforce, how much of the Good-Turing
unseen-mass budget a run's named claimants collectively draw on.
`TaxaAssign::suggest_unreferenced_species()` (LLM-based plausibility)
remains the complementary mechanism for diversity too poorly recorded
to reach any occurrence-based estimate at all.

------------------------------------------------------------------------

## 10. Output: The Prior Object

The final prior table has one row per taxon x site x habitat
combination, assembled by `dplyr::bind_rows()` across the generators
in Section 8:

| Column | Description |
|----------------------------|--------------------------------------------|
| `taxon_name` | Species identifier (NA for singleton-mirror/global-floor proxy rows) |
| `grid_id` | Site identifier (opaque join key; no longer names a grid cell under the kernel path) |
| `main_habitat` | Habitat at this site |
| `alpha` | Beta distribution alpha parameter |
| `beta` | Beta distribution beta parameter |
| `theta_mean` | Prior mean: alpha / (alpha + beta) |
| `theta_sd` | Prior SD: sqrt(alpha*beta / ((alpha+beta)\^2*  (alpha+beta+1))) |
| `prior_branch` | `"resident_observed"`, `"resident_undetected"`, or `"transport"` (replaces `model_tier`) |
| `effective_records` | Kernel-effective record count backing a `resident_observed` row (replaces the tier1/tier2 split) |
| `observed_in_habitat` | TRUE by construction for `resident_observed` rows |
| `undetected_type` | NA, `"singleton_mirror"`, `"global_floor"`, or `"evidence_blend"` (`resident_undetected` rows only) |
| `evidence_weight`, `evidence_sources` | Audit columns on `evidence_blend` rows: the combined presence weight and contributing evidence sources |
| `prior_mix_w`, `prior_mix_theta_present`, `prior_mix_theta_absent`, `prior_mix_p_conc` | The presence mixture itself, on `evidence_blend` rows, for `TaxaAssign::compute_posterior()`'s presence-draw sampler |
| `prior_source_type` | Finer transport-branch provenance (`"domestic_animal"`, `"food_species"`, `"domestic_plant"`, etc.), `transport` rows only |
| `model_tier` | Present only on rows built by the still-functional but deprecated GLMM path; carries no meaning on kernel-estimated rows |

`TaxaAssign::join_priors()` joins this table to likelihood output on the
composite key `(taxon_name, taxon_name_rank, grid_id, main_habitat)` and
uses the alpha/beta parameters for Beta-distributed priors in Monte
Carlo posterior estimation -- the join key and downstream consumption
are unchanged from the retired architecture.

------------------------------------------------------------------------

## Glossary

| Term | Definition |
|--------------------------|----------------------------------------------|
| **site** (`grid_id`) | A query location: a coordinate pair and a focal habitat. `grid_id` is the column name kept for downstream join compatibility; under the kernel path it identifies a site, not a grid cell. |
| **kernel bandwidth** (`lambda_km`) | The geographic kernel's e-folding distance; chosen by leave-one-block-out composition prediction, never hand-set |
| **Kish effective sample size** (`n_eff`) | `W^2 / sum(w_r^2)`: the design-effect-corrected effective count of the weighted neighborhood (Kish 1965) |
| **effective_records** | Kernel-effective record count backing a species' estimate, in count units; replaces the discrete tier1/tier2 split |
| **prior_branch** | Which part of the framework a row belongs to: `resident_observed`, `resident_undetected`, or `transport`; replaces `model_tier` |
| **resident community** | The P=1 simplex: observed shares plus the Good-Turing unseen mass, whose interior is not enumerated |
| **theta_present** | The Good-Turing missing mass divided by the Chao missing-species count: the typical unseen resident's share if present |
| **presence-distance curve** | `w = w_scale * exp(-min(d,d_cap)/(k*d_half))`: prices an unobserved claimant's presence probability from its distance to the nearest occurrence record |
| **distance clamp** | The presence-distance curve evaluated at `d_cap` for a claimant with no measured distance -- deliberately flat beyond the instrument's search radius |
| **budget audit** | Comparing the summed presence-weight of named unobserved claimants against the Chao missing-species estimate; reported, not enforced |
| **transport branch** | Presence-weighted hypotheses (domestic/food species; cross-habitat DNA bleed, not yet built) outside the resident simplex, each calibrated against its own measurement |
| **theta** | Expected relative share of a species at a site: P(random legitimate detection = species X) |
| **dark diversity** | Species plausibly present but not yet recorded (Pärtel et al. 2011) |

------------------------------------------------------------------------

## Key Functions (TaxaExpect)

| Function | Role in Pipeline |
|---------------------------|---------------------------------------------|
| `calibrate_kernel_bandwidth()` | Choose kernel bandwidths (and `m`) by leave-one-block-out composition prediction |
| `estimate_kernel_priors()` | Site-centered kernel estimation of `resident_observed` priors |
| `generate_undetected_diversity()` | Singleton-mirror and global-floor `resident_undetected` priors (kernel or GLMM ingredients) |
| `generate_presence_curve_evidence()` | Price unobserved claimants (regional, watch-lifted, or distance-clamped) on the shared presence-distance curve |
| `generate_user_specified_evidence()` | Caller-asserted presence weights for named species, with dilution-threshold disclosure |
| `apply_undetected_evidence()` | Combine evidence sources into elevated `resident_undetected` priors (`pricing = "blend"` or `"curve"`) |
| `generate_domestic_food_priors()` | `transport`-branch priors for domestic, food, and cultivar species |
| `build_priors()` | End-to-end GLMM wrapper (deprecated; no kernel-path equivalent yet) |
| `plot_theta_map_interactive()` | Interactive Leaflet map of priors (deprecated GLMM branch only; parses `Grid_*` ids) |

------------------------------------------------------------------------

## Pipeline Position

```         
TaxaFetch (occurrence data)
    |
    v
TaxaHabitat (habitat assignment)
    |
    v
TaxaExpect (this package)
    |-- calibrate_kernel_bandwidth()               # choose lambda_km, m, ...
    |-- estimate_kernel_priors()                    # resident_observed rows
    |-- generate_undetected_diversity()             # resident_undetected floor/singleton rows
    |-- generate_presence_curve_evidence() /
    |     generate_user_specified_evidence() +
    |     apply_undetected_evidence(pricing="curve") # resident_undetected evidence rows
    |-- generate_domestic_food_priors()             # transport rows
    |
    v
TaxaAssign
    |-- join_priors(): match priors to query site
    |-- compute_posterior(): combine with TaxaLikely likelihoods
```

(The retired GLMM chain -- `build_priors()`, `optimize_grid_size()`,
`prepare_model_dataframe()`, `compute_moran_basis()`,
`screen_spatial_formula()`, `train_biodiversity_model()`,
`generate_full_priors()` -- remains in the package, deprecated, and is
not shown above.)

------------------------------------------------------------------------

## References

Chao, A. (1984). Nonparametric estimation of the number of classes in a
population. *Scandinavian Journal of Statistics*, 11(4), 265-270.

Gelman, A., Carlin, J.B., Stern, H.S., Dunson, D.B., Vehtari, A. and
Rubin, D.B. (2013). *Bayesian Data Analysis*. 3rd edn. CRC Press.

Good, I.J. (1953). The population frequencies of species and the
estimation of population parameters. *Biometrika*, 40(3-4), 237-264.

Jeffreys, H. (1946). An invariant form for the prior probability in
estimation problems. *Proceedings of the Royal Society of London A*,
186(1007), 453--461. <doi:10.1098/rspa.1946.0056>

Kish, L. (1965). *Survey Sampling*. New York: Wiley.

MacKenzie, D.I., Nichols, J.D., Lachman, G.B., Droege, S., Royle, J.A.
and Langtimm, C.A. (2002). Estimating site occupancy rates when
detection probabilities are less than one. *Ecology*, 83(8), 2248--2255.
[doi:10.1890/0012-9658(2002)083[2248:ESORWD]2.0.CO;2](doi:10.1890/0012-9658(2002)083%5B2248:ESORWD%5D2.0.CO;2){.uri}

Pärtel, M., Szava-Kovats, R. and Zobel, M. (2011). Dark diversity:
shedding light on absent species. *Trends in Ecology & Evolution*,
26(3), 124--128. <doi:10.1016/j.tree.2010.12.004>

Warton, D.I., Blanchet, F.G., O'Hara, R.B., Ovaskainen, O., Taskinen,
S., Walker, S.C. and Hui, F.K.C. (2015). So many variables: joint
modeling in community ecology. *Trends in Ecology & Evolution*, 30(12),
766--779. <doi:10.1016/j.tree.2015.09.007>

*The following references pertain to the retired grid/GLMM prior
architecture (Section 1), which remains in the package as deprecated
functions but is not otherwise described in this document.*

Brooks, M.E., Kristensen, K., van Benthem, K.J., Magnusson, A., Berg,
C.W., Nielsen, A., Skaug, H.J., Maechler, M. and Bolker, B.M. (2017).
glmmTMB balances speed and flexibility among packages for zero-inflated
generalized linear mixed modeling. *The R Journal*, 9(2), 378--400.
<doi:10.32614/RJ-2017-066>

Dormann, C.F., Elith, J., Bacher, S., Buchmann, C., Carl, G., Carré, G.,
Marquéz, J.R.G., Gruber, B., Lafourcade, B., Leitão, P.J., Münkemüller,
T., McClean, C., Osborne, P.E., Reineking, B., Schröder, B., Skidmore,
A.K., Zurell, D. and Lautenbach, S. (2013). Collinearity: a review of
methods to deal with it and a simulation study evaluating their
performance. *Ecography*, 36(1), 27--46.
<doi:10.1111/j.1600-0587.2012.07348.x>

Dray, S., Legendre, P. and Peres-Neto, P.R. (2006). Spatial modelling: a
comprehensive framework for principal coordinate analysis of neighbour
matrices (PCNM). *Ecological Modelling*, 196(3--4), 483--493.
<doi:10.1016/j.ecolmodel.2006.02.015>

Griffith, D.A. and Peres-Neto, P.R. (2006). Spatial modeling in ecology:
the flexibility of eigenfunction spatial analyses. *Ecology*, 87(10),
2603--2613.
[doi:10.1890/0012-9658(2006)87[2603:SMIETF]2.0.CO;2](doi:10.1890/0012-9658(2006)87%5B2603:SMIETF%5D2.0.CO;2){.uri}
