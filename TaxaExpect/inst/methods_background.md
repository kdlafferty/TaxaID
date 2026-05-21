# TaxaExpect: Statistical Background

## Spatially-Explicit Bayesian Priors for Species Occurrence

*This document provides the statistical rationale behind TaxaExpect. It is
intended as a manuscript-ready methods reference for the TaxaID ecosystem.*

---

## 1. Problem Statement

Taxonomic assignment from DNA, images, or sound recordings is fundamentally
ambiguous when multiple candidate taxa produce similar match scores. Resolving
this ambiguity requires prior information: the probability that each candidate
taxon occurs at the sampling location. Without spatial priors, classifiers
either (a) assign the top-scoring candidate regardless of plausibility,
producing false positives for ecologically implausible taxa, or (b) conservatively
uprank to genus or family, losing species-level resolution.

TaxaExpect estimates these priors from occurrence records (typically GBIF
observations fetched by TaxaFetch and habitat-annotated by TaxaHabitat). The
core challenge is that occurrence data are sparse, spatially biased, and never
exhaustive -- absence of a record does not mean absence of a species. TaxaExpect
addresses this through a hierarchical generalized linear mixed model (GLMM) that
borrows strength across species and locations, producing informative priors even
for poorly sampled areas.

---

## 2. Grid Optimization

Occurrence records arrive as point coordinates with irregular spatial density.
TaxaExpect aggregates these into grid cells before modeling, trading spatial
resolution for statistical power. The grid resolution is chosen automatically
by `optimize_grid_size()`, which searches a range of cell sizes (default
0.1°--1.0° in 0.05° steps) and scores each on a composite index of three
criteria:

1. **Resolution** (log-scaled distinct location count): rewards finer grids,
   with diminishing returns on a log scale to avoid over-splitting sparse data.
2. **Quality** (median observations per cell): rewards cells with enough
   observations for stable theta estimates.
3. **Stability** (inverse coefficient of variation of N): penalizes grids where
   effort is unevenly distributed across cells.

The three criteria are combined with user-adjustable weights (default:
resolution 0.4, quality 0.4, stability 0.2). When no resolution meets
minimum coverage thresholds, progressive fallbacks ensure a usable grid is
always returned, down to a single cell spanning the full bounding box.

---

## 3. Data Preparation

`prepare_model_dataframe()` converts raw occurrence records into the
species × site-habitat matrix required by the model:

1. **Covariate scaling:** Spatial covariates (latitude, longitude, and any
   user-supplied predictors) are centered and scaled to zero mean / unit
   standard deviation. Scaling parameters are stored as attributes and
   reapplied at prediction time to ensure consistency.
2. **Multicollinearity screening:** Pairwise correlations among covariates
   are checked against a threshold (default |r| > 0.7, following Dormann
   et al. 2013). Collinear pairs trigger a warning suggesting PCA reduction.
3. **Zero-filling:** The species × site matrix is completed with explicit
   zeros for species not observed at a site -- essential for the binomial
   likelihood.
4. **Habitat flag:** A `habitat_observed_elsewhere` indicator records whether
   each species has been detected in a given habitat type at any site,
   distinguishing model interpolation from habitat extrapolation.

---

## 4. Model Structure

TaxaExpect fits the occurrence data using a binomial generalized linear mixed
model (GLMM) via glmmTMB (Brooks et al. 2017). The response variable is the
number of records of species *s* at site *g*, out of the total community count
at that site:

    n_{s,g} ~ Binomial(N_g, theta_{s,g})

where theta is the relative abundance of species *s* at site *g* -- the
probability that a randomly sampled individual from the community at that
location belongs to species *s*.

The default model formula on the logit scale is:

    logit(theta_{s,g}) =
        beta_0 +                          # global intercept
        beta_h * habitat_g +              # fixed habitat effects
        u_s +                             # random intercept per species
        v_{s,h} * I(habitat_g = h) +      # random habitat slopes (screened)
        w_s * lat_g + z_s * lon_g +       # random spatial gradients
        r_{s,g}                           # random species × grid deviation

### 4.1. Fixed Effects

- **Habitat** (`main_habitat`): Categorical fixed effect capturing baseline
  differences in community composition across habitat types (e.g., Marine vs.
  Freshwater vs. Terrestrial). The reference level is set by R's default factor
  ordering.

### 4.2. Random Effects

- **Species intercept** `(1 | taxon_name)`: Captures overall rarity independent
  of habitat preference. Without this term, all species would share the same
  baseline and a globally rare species would be predicted at the global average
  rate in any habitat where it has not been observed. The intercept shrinks
  toward the global mean across all species -- appropriate when the species pool
  has a right-skewed abundance distribution (most species rare).

- **Habitat random slopes** `diag(main_habitat | taxon_name)`: Species-specific
  habitat preferences. Before fitting, `train_biodiversity_model()` screens each
  habitat level for sufficient Tier 1 coverage (at least `min_positive_rows`
  positive observations, default 50). Supported habitats receive species-specific
  random slopes via indicator variables; sparse habitats are captured by the
  fixed habitat effect only. This prevents convergence failures from near-empty
  random effect levels.

- **Spatial gradients** `(0 + lat_r_s | taxon_name)` and
  `(0 + lon_r_s | taxon_name)`: Species-specific latitude and longitude slopes
  allow each species to have its own spatial range trend. Scaled covariates
  ensure comparable variance contributions.

- **Species × grid deviation** `(1 | taxon_name:grid_id)`: Captures local
  grid-level deviations from the spatial surface for each species. Its variance
  is estimated from data, removing the need for manual prior caps. This variance
  also serves as the principled ceiling for prior concentration (phi cap; see
  Section 6).

### 4.3. Species Tiers

Not all species have sufficient data for the full model. TaxaExpect assigns
species to three tiers:

| Tier | Criterion | Model |
|------|-----------|-------|
| **Tier 1** | >= `min_obs_threshold` detections (default 5) | Full formula with all random effects |
| **Tier 2** | < `min_obs_threshold` detections but > 0 | Simplified: `habitat + (1 | taxon_name)` only |
| **Tier 3** | Never detected in the dataset | Not modelled; handled by `generate_undetected_diversity()` |

The effort threshold (`effort_threshold`, default 10 total observations per
cell) excludes poorly sampled cells from the likelihood, preventing singletons
in low-effort cells from driving parameter estimates.

### 4.4. Fitting

The model is fitted via maximum likelihood using the Laplace approximation
implemented in glmmTMB. Convergence warnings (non-positive-definite Hessian)
are captured and stored in the model object; if persistent, they indicate that
the formula should be simplified or `min_positive_rows` increased.

---

## 5. Spatial Autocorrelation: Moran Eigenvector Maps

Species occurrences are spatially autocorrelated -- nearby sites tend to share
species. The latitude/longitude random slopes in the default formula capture
broad spatial gradients, but finer-scale autocorrelation (e.g., clustered
occurrences along a coastline) may remain.

`compute_moran_basis()` provides an optional set of Moran eigenvector maps
(MEM; Dray et al. 2006; Griffith and Peres-Neto 2006) that can be added as
fixed-effect covariates:

1. Parse grid cell identifiers to centroid coordinates.
2. Build a binary adjacency matrix *W* based on a distance threshold (default:
   1.5× the minimum grid spacing, capturing first-order neighbours).
3. Row-standardize *W* to *W\**.
4. Doubly-centre to form the symmetric Moran operator *M = HW\*H*, where
   *H = I - 11'/n*.
5. Extract the *k* eigenvectors with the largest positive eigenvalues (default
   *k* = 10). These represent decreasing scales of positive spatial
   autocorrelation.

The resulting basis columns (B1, B2, ..., B*k*) are joined to the model
dataframe and included as fixed effects. Each eigenvector captures a spatial
pattern at a particular scale, from broad regional gradients (B1) to
fine-scale clustering (B*k*). Including them reduces residual spatial
autocorrelation without requiring an explicit spatial covariance function.

---

## 6. From Predictions to Beta Priors

`generate_full_priors()` converts model predictions into Beta(alpha, beta)
priors suitable for TaxaAssign's Bayesian posterior computation.

### 6.1. Delta-Method Back-Transformation

glmmTMB predictions on the link (logit) scale include a standard error.
These are back-transformed to the probability scale using the delta method:

    theta_mean = plogis(eta)              # inverse logit
    theta_var  = se^2 * (theta * (1 - theta))^2

where eta is the linear predictor and se is the standard error on the logit
scale. The delta method approximation is standard for GLMMs and is accurate
when the logit-scale distribution is approximately normal.

### 6.2. Moment-Matching to Beta Parameters

The predicted mean and variance are converted to Beta distribution parameters
via moment-matching:

    phi   = theta_mean * (1 - theta_mean) / theta_var - 1
    alpha = theta_mean * phi
    beta  = (1 - theta_mean) * phi

where phi = alpha + beta is the concentration parameter (effective sample
size of the Beta prior). Higher phi means a more concentrated (informative)
prior.

### 6.3. Phi Cap (Upper Bound)

When theta is near 0 or 1, the Bernoulli variance theta(1-theta) is tiny and
phi can explode to astronomically large values even with a modest logit-scale
standard error. TaxaExpect caps phi at 1/sigma^2_grid, where sigma^2_grid is
the variance of the `taxon_name:grid_id` random effect from the Tier 1 model.
This is principled: the model's own estimate of grid-level uncertainty sets the
ceiling on prior concentration. No user tuning is required.

### 6.4. Phi Floor (Lower Bound)

Conversely, when the phi cap is very low (high grid-level variance), unchecked
phi can produce alpha and beta values so small that Monte Carlo posterior
simulation becomes unstable. The `min_phi` parameter (default 2) ensures that
modelled priors are always at least as informative as the singleton-based
dark diversity priors (Section 7). This guarantees that species observed in
training data receive more informative priors than undetected species.

### 6.5. Jeffreys Fallback

If phi <= 0 after capping (variance exceeds the Bernoulli maximum), the row
receives a Jeffreys prior Beta(0.5, 0.5) -- the standard non-informative prior
for a Bernoulli parameter (Jeffreys 1946). This indicates extreme uncertainty,
typically from covariate extrapolation.

### 6.6. Extrapolation Warnings

Prediction sites where any scaled covariate exceeds |z| > 3 (i.e., more than
3 standard deviations from the training mean) are flagged with
`extrapolation_warning = TRUE`. Priors at these sites should be treated with
caution.

---

## 7. Dark Diversity: Tier 3 Priors for Undetected Species

Species that are plausibly present in the regional pool but were never recorded
in the dataset cannot be modelled directly. `generate_undetected_diversity()`
constructs two types of proxy priors for these Tier 3 species:

### 7.1. Singleton Mirrors

For each species observed exactly once across all samples (a "singleton"),
one anonymous undetected species proxy is created, inheriting the singleton's
habitat, location, and observed theta. The rationale is that locations and
habitats with many single-detection species indicate high undetected diversity.

The observed theta (n=1/N) is converted to Beta parameters using a fixed
effective sample size:

    alpha = theta_obs * ESS
    beta  = (1 - theta_obs) * ESS

The default ESS = 2 produces a weak, diffuse prior -- intentionally
conservative for a species seen exactly once. Note that "singleton" here refers
to detection frequency (species observed once in the dataset), not to
"singleton sequences" in TaxaLikely (reference sequences with no within-species
neighbours).

### 7.2. Global Floor Prior

A single effort-based prior is always included regardless of whether singletons
are present:

    theta_floor = 1 / N_total
    parameterized as Beta(1, N_total - 1)

This represents the expected theta if an undetected species appeared exactly
once across all sampling effort. It is always smaller than any singleton-derived
theta in a well-sampled dataset and ensures TaxaAssign always has at least one
undetected competitor hypothesis. When N_total is very small (< 2), a Jeffreys
prior Beta(0.5, 0.5) is used instead.

---

## 8. The build_priors() Wrapper

For convenience, `build_priors()` wraps the entire pipeline into a single
function call:

1. Resolve taxon names to GBIF backbone keys (via TaxaTools)
2. Fetch GBIF occurrence records (via TaxaFetch)
3. Assign habitat to sites (via TaxaHabitat)
4. Optimize grid resolution
5. Create spatial grid and prepare model dataframe
6. Fit the biodiversity model
7. Generate Tier 3 (dark diversity) priors
8. Combine all tiers into the final prior object
9. Optionally translate taxonomy to a target backbone

The output carries metadata attributes (`habitat_scheme`, `search_center`,
`gbif_genus_census`) that downstream packages (TaxaAssign) use for site
resolution and unreferenced species logic.

---

## 9. Assumptions and Limitations

**Sampling bias:** Occurrence records from GBIF and similar sources are
opportunistic, not systematic. TaxaExpect partially mitigates this through the
effort threshold (excluding poorly sampled cells) and the hierarchical model
(shrinking species with few records toward the global mean), but cannot fully
correct for geographic or taxonomic sampling bias.

**Closed community assumption:** The binomial model assumes that the total
community count N at a site represents the pool from which each species is
drawn. In practice, N reflects sampling effort more than true community size.
The effort threshold mitigates this by excluding cells with very low N.

**Habitat classification:** The model conditions on habitat labels from
TaxaHabitat. Misclassified habitats propagate to incorrect priors. The
`habitat_observed_elsewhere` flag identifies predictions that extrapolate a
species into a habitat where it has never been observed.

**Spatial stationarity:** The latitude/longitude random slopes assume linear
spatial gradients per species. Non-linear range boundaries (e.g., a species
present north of a mountain range but absent south of it) are captured only
approximately, through the species × grid random effect and optional Moran
eigenvectors.

**Dark diversity completeness:** Singleton mirrors provide proxy priors only
for habitats and locations where singletons were observed. True undetected
diversity at locations with no singletons is represented only by the global
floor prior, which may underestimate the number of plausible competitors.
TaxaAssign's `suggest_unreferenced_species()` complements this with LLM-based
plausibility estimates.

---

## 10. Output: The Prior Object

The final prior table has one row per taxon × site × habitat combination:

| Column | Description |
|--------|-------------|
| `taxon_name` | Species identifier (NA for Tier 3 proxies) |
| `grid_id` | Spatial grid cell identifier |
| `main_habitat` | Habitat at this site |
| `alpha` | Beta distribution alpha parameter |
| `beta` | Beta distribution beta parameter |
| `theta_mean` | Prior mean: alpha / (alpha + beta) |
| `theta_sd` | Prior SD: sqrt(alpha*beta / ((alpha+beta)^2 * (alpha+beta+1))) |
| `model_tier` | "tier1", "tier2", or "tier3_undetected" |
| `undetected_type` | NA, "singleton_mirror", or "global_floor" |
| `effort_flag` | Was sampling effort below the training threshold? |
| `habitat_observed_elsewhere` | Was this species ever recorded in this habitat? |
| `extrapolation_warning` | Is this site outside the training covariate range? |

TaxaAssign joins this table to likelihood output on `taxon_name` and uses
the alpha/beta parameters to compute Beta-distributed priors for Monte Carlo
posterior estimation.

---

## Glossary

| Term | Definition |
|------|-----------|
| **theta** | Expected relative abundance of a species at a site: P(random individual = species X) |
| **phi** | Concentration parameter of the Beta prior: alpha + beta (effective sample size) |
| **phi cap** | Upper bound on phi from the taxon_name:grid_id variance |
| **min_phi** | Lower bound on phi preventing unstable MC posteriors |
| **Tier 1** | Species with >= `min_obs_threshold` detections; full model |
| **Tier 2** | Species with < threshold detections; intercept-only model |
| **Tier 3** | Undetected species; singleton mirror or global floor prior |
| **singleton mirror** | Proxy prior for an undetected species, based on a species observed exactly once |
| **global floor** | Beta(1, N_total - 1); minimum prior for any undetected species |
| **dark diversity** | Species plausibly present but not yet recorded (Pärtel et al. 2011) |

---

## Key Functions (TaxaExpect)

| Function | Role in Pipeline |
|----------|-----------------|
| `build_priors()` | End-to-end wrapper: GBIF → habitat → grid → model → priors |
| `optimize_grid_size()` | Find optimal grid resolution for the study area |
| `create_sites_from_grid()` | Generate spatial grid cells from occurrence records |
| `prepare_model_dataframe()` | Zero-fill, scale covariates, check collinearity |
| `compute_moran_basis()` | Moran eigenvector maps for spatial autocorrelation |
| `screen_spatial_formula()` | Evaluate candidate model formulas |
| `train_biodiversity_model()` | Fit hierarchical GLMM (glmmTMB) |
| `generate_full_priors()` | Predict priors at target sites (Tier 1 + 2) |
| `generate_undetected_diversity()` | Dark diversity priors (Tier 3) |
| `plot_theta_map_interactive()` | Interactive Leaflet map of priors |

---

## Pipeline Position

```
TaxaFetch (occurrence data)
    |
    v
TaxaHabitat (habitat assignment)
    |
    v
TaxaExpect (this package)
    |-- optimize_grid_size() + create_sites_from_grid()
    |-- prepare_model_dataframe()
    |-- train_biodiversity_model()
    |-- generate_full_priors() + generate_undetected_diversity()
    |
    v
TaxaAssign
    |-- join_priors(): match priors to query site
    |-- compute_posterior(): combine with TaxaLikely likelihoods
```

---

## References

Brooks, M.E., Kristensen, K., van Benthem, K.J., Magnusson, A., Berg, C.W.,
Nielsen, A., Skaug, H.J., Maechler, M. and Bolker, B.M. (2017). glmmTMB
balances speed and flexibility among packages for zero-inflated generalized
linear mixed modeling. *The R Journal*, 9(2), 378--400.
doi:10.32614/RJ-2017-066

Dormann, C.F., Elith, J., Bacher, S., Buchmann, C., Carl, G., Carré, G.,
Marquéz, J.R.G., Gruber, B., Lafourcade, B., Leitão, P.J., Münkemüller, T.,
McClean, C., Osborne, P.E., Reineking, B., Schröder, B., Skidmore, A.K.,
Zurell, D. and Lautenbach, S. (2013). Collinearity: a review of methods to
deal with it and a simulation study evaluating their performance. *Ecography*,
36(1), 27--46. doi:10.1111/j.1600-0587.2012.07348.x

Dray, S., Legendre, P. and Peres-Neto, P.R. (2006). Spatial modelling: a
comprehensive framework for principal coordinate analysis of neighbour
matrices (PCNM). *Ecological Modelling*, 196(3--4), 483--493.
doi:10.1016/j.ecolmodel.2006.02.015

Gelman, A., Carlin, J.B., Stern, H.S., Dunson, D.B., Vehtari, A. and
Rubin, D.B. (2013). *Bayesian Data Analysis*. 3rd edn. CRC Press.

Griffith, D.A. and Peres-Neto, P.R. (2006). Spatial modeling in ecology:
the flexibility of eigenfunction spatial analyses. *Ecology*, 87(10),
2603--2613. doi:10.1890/0012-9658(2006)87[2603:SMIETF]2.0.CO;2

Jeffreys, H. (1946). An invariant form for the prior probability in
estimation problems. *Proceedings of the Royal Society of London A*,
186(1007), 453--461. doi:10.1098/rspa.1946.0056

MacKenzie, D.I., Nichols, J.D., Lachman, G.B., Droege, S., Royle, J.A. and
Langtimm, C.A. (2002). Estimating site occupancy rates when detection
probabilities are less than one. *Ecology*, 83(8), 2248--2255.
doi:10.1890/0012-9658(2002)083[2248:ESORWD]2.0.CO;2

Pärtel, M., Szava-Kovats, R. and Zobel, M. (2011). Dark diversity: shedding
light on absent species. *Trends in Ecology & Evolution*, 26(3), 124--128.
doi:10.1016/j.tree.2010.12.004

Warton, D.I., Blanchet, F.G., O'Hara, R.B., Ovaskainen, O., Taskinen, S.,
Walker, S.C. and Hui, F.K.C. (2015). So many variables: joint modeling in
community ecology. *Trends in Ecology & Evolution*, 30(12), 766--779.
doi:10.1016/j.tree.2015.09.007
