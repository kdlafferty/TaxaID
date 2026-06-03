---
editor_options: 
  markdown: 
    wrap: 72
---

# Statistical Methods Background -- TaxaAssign

**TaxaAssign** is the convergence point of the TaxaID ecosystem: it
combines likelihoods (from TaxaLikely or an LLM-based proxy) with priors
(from TaxaExpect or LLM estimation) to compute Bayesian posterior
probabilities for each hypothesized taxonomic assignment. It then
derives a consensus identification for each observation using either
posterior-based or (for comparison) more conventional score-based rules.

This document provides the statistical background and design rationale
for TaxaAssign's methods. It supplements the function-level roxygen
documentation and the package README.

------------------------------------------------------------------------

## 1. Problem Statement

Taxonomic assignment from observational data (DNA barcodes, images,
acoustic recordings) must compare each observation against a set of
candidate taxa and decide which assignment is most probable. Raw match
scores (e.g., percent identity from BLAST) are necessary but not
sufficient: a 99% match does not mean a 99% probability of correct
identification when multiple species can produce 99% matches, or when
geographic context makes some species far more plausible than others.

TaxaAssign formalizes this problem using Bayes' theorem. Each candidate
taxon is a competing hypothesis, and the posterior probability of each
hypothesis integrates two independent lines of evidence:

1.  **Likelihood** -- how well does the observation match this taxon,
    relative to other candidates? (From TaxaLikely or a score-based
    proxy.)
2.  **Prior** -- how likely is this taxon to occur at the sampling
    location, before seeing the observation? (From TaxaExpect or LLM
    estimation.)

TaxaAssign supports two workflows that differ in how likelihoods and
priors are obtained:

-   **Full Bayesian workflow**: calibrated likelihoods from TaxaLikely's
    hierarchical model + spatially-explicit priors from TaxaExpect's
    GLMM.
-   **LLM-shortcut workflow**: exponential score weighting as a
    likelihood proxy + LLM-estimated priors from a large language model
    acting as an expert biogeographer.

Both workflows converge on the same `compute_posterior()` function and
downstream consensus machinery.

------------------------------------------------------------------------

## 2. Bayesian Posterior Computation

### 2.1 The Update Formula

For a given observation (identified by `observation_id`), let
$H_1, H_2, \ldots, H_K$ be the competing taxonomic hypotheses. The
posterior probability of hypothesis $H_i$ given the observed data $D$
is:

$$P(H_i \mid D) = \frac{L(D \mid H_i) \times \pi(H_i)}{\sum_{j=1}^{K} L(D \mid H_j) \times \pi(H_j)}$$

where:

-   $L(D \mid H_i)$ is the likelihood of the data under hypothesis $H_i$
-   $\pi(H_i)$ is the prior probability of hypothesis $H_i$
-   The denominator is the marginal likelihood (normalizing constant)

Within each observation, likelihoods are first normalized to sum to 1
across all competing hypotheses (ensuring scale-invariance), then
multiplied by priors, and the resulting products are normalized again to
yield proper posterior probabilities.

### 2.2 Point Estimate Path

The deterministic path computes:

1.  Normalize likelihoods: $\hat{L}_i = L_i / \sum_j L_j$
2.  Raw posterior: $r_i = \hat{L}_i \times \pi_i$
3.  Normalize: $P_i = r_i / \sum_j r_j$

If all likelihoods are zero (e.g., all candidates below detection
threshold), the posterior falls back to a uniform distribution,
effectively returning the prior-weighted allocation.

### 2.3 Monte Carlo Path

When uncertainty information is available -- either non-zero
`score_likelihood_sd` from TaxaLikely's simulation or `prior_alpha`/
`prior_beta` from Beta-distributed priors -- a Monte Carlo simulation
propagates that uncertainty into the posterior.

For each of `n_sims` iterations (default 1000):

1.  **Sample likelihoods**: draw from
    $\text{Normal}(\text{likelihood\_mean}_i, \text{likelihood\_sd}_i)$,
    floored at 0.
2.  **Sample priors**: draw from $\text{Beta}(\alpha_i, \beta_i)$ when
    alpha/beta columns are present; otherwise replicate the fixed
    `prior_mean`.
3.  **Normalize** sampled likelihoods within this simulation.
4.  **Multiply** normalized likelihoods by sampled priors.
5.  **Normalize** the resulting posterior within this simulation.

Across all simulations, the function computes:

-   `posterior_mean`: mean posterior probability across simulations
-   `posterior_sd`: standard deviation across simulations
-   `confidence_score`: fraction of simulations in which hypothesis
    $H_i$ had the highest posterior -- analogous to the "posterior
    probability of being the best hypothesis" in decision theory (Berger
    1985) 

The `confidence_score` complements `posterior_mean`: a hypothesis can
have a moderately high mean posterior but low confidence score if
another hypothesis frequently wins in individual simulations. This
distinguishes between a clearly dominant hypothesis and one that is
merely the best on average.

### 2.4 Prior Uncertainty via the Beta Distribution

Priors are modelled as $\text{Beta}(\alpha, \beta)$ rather than fixed
point estimates. The Beta distribution is the natural choice for
probabilities bounded on $[0, 1]$ (Jeffreys 1946). Key relationships:

-   **Mean**: $\mu = \alpha / (\alpha + \beta)$
-   **Concentration**: $\phi = \alpha + \beta$ controls precision. Large
    $\phi$ (e.g., 50) means high confidence in the prior estimate; small
    $\phi$ (e.g., 3) means the prior is diffuse and easily overridden by
    the likelihood.
-   **Variance**: $\sigma^2 = \mu(1 - \mu) / (\phi + 1)$

The full Bayesian workflow receives $\alpha$ and $\beta$ directly from
TaxaExpect's moment-matching procedure (see
`TaxaExpect/inst/TaxaExpect_supplemental_methods.md`). The LLM-shortcut workflow constructs them
from `prior_mean × phi` and `(1 - prior_mean) × phi`, where $\phi$ is
determined by the LLM's `information_quality` rating (see Section 4.3).

------------------------------------------------------------------------

## 3. Full Bayesian Workflow

The full Bayesian workflow chains calibrated models from TaxaLikely and
TaxaExpect. The pipeline, orchestrated by `run_bayesian_pipeline()`,
proceeds through these stages:

### 3.1 Likelihood Evaluation (TaxaLikely)

TaxaLikely's `evaluate_likelihoods()` converts raw match scores into
calibrated likelihoods using a trained hierarchical model (see
`TaxaLikely/inst/TaxaLikely_supplemental_methods.md`). For each observation, three
hypothesis types are considered:

-   **H1 (specific_candidate)**: the matched species is in the reference
    database. Likelihood computed from the bivariate normal density in
    (score_logit, gap_logit) space.
-   **H2 (unreferenced_species)**: a congener absent from the reference.
    Likelihood uses the H1 distribution shifted by a learned delta
    offset.
-   **H3 (unreferenced_genus)**: a taxon from a different genus
    entirely. Further shifted by a larger delta.

### 3.2 Unreferenced Species Expansion

TaxaLikely produces generic H2 and H3 rows at the genus and family
level. `expand_unreferenced_hypotheses()` replaces these generic rows
with named species from an `unreferenced_df` (typically from
`audit_barcode_coverage()` or `suggest_unreferenced_species()`):

-   **H2 rows**: each generic genus-level row is replaced by one row per
    unreferenced species in that genus. All inherit the generic H2
    likelihood.
-   **H3 rows**: each generic family-level row is replaced by one row
    per unreferenced species in other genera of that family (excluding
    the H2 genus). All inherit the generic H3 likelihood.

Named expansion is essential because TaxaExpect provides species-level
priors -- a generic "some unreferenced member of genus X" cannot be
matched to the prior table.

When `unreferenced_df` is empty (no plausible unreferenced species), all
H2 and H3 rows are dropped rather than retained with unmatchable names.

### 3.3 GBIF Census Integration

When TaxaExpect's `build_priors()` includes a GBIF genus census (default
behavior), `run_bayesian_pipeline()` applies a three-tier logic to H2
hypotheses:

-   **Complete genera** (all described species have observations): H2
    rows are suppressed entirely. Any unreferenced species in these
    genera would lack observations and cannot appear as matches.
-   **Singleton-missing genera** (exactly one species lacks an
    observation): H2 is renamed to the specific missing species rather
    than treated generically.
-   **Incomplete genera**: generic H2 handling proceeds as normal.

This census-driven suppression prevents false positives from
unreferenced species hypotheses in well-characterized genera.

### 3.4 Prior Joining and Dark Diversity Fallback

`join_priors()` bridges TaxaLikely likelihoods and TaxaExpect priors.
For each observation, it:

1.  **Resolves the site** to a grid cell in TaxaExpect's spatial grid
    using coordinates or a direct grid_id, plus a required habitat
    specification.
2.  **Joins** on `taxon_name`, `taxon_name_rank`, `grid_id`, and
    `main_habitat` to attach `prior_alpha` and `prior_beta` from
    TaxaExpect.
3.  **Applies dark diversity fallback** for taxa without a direct prior
    match:
    -   **Site-level**: mean alpha/beta from Tier 3 (undetected) rows at
        the same grid cell and habitat.
    -   **Global**: if no Tier 3 rows exist at the site, the average
        across all Tier 3 rows.
4.  **Modelled-species floor**: a species the model has observed
    somewhere in training data but at the wrong habitat can receive a
    near-zero prior. To prevent the perverse outcome where an unobserved
    species receives more prior mass than an observed one, any modelled
    species with `prior_mean` below the dark diversity mean is promoted
    to the dark diversity level.
5.  **Taxonomy fill**: fills missing taxonomy columns from a lookup
    table and via TaxaTools backbone queries, enabling downstream LCA
    consensus computation.
6.  **Redundancy filter**: removes coarser-rank hypotheses superseded by
    finer-rank hypotheses within the same lineage (via
    `TaxaMatch::filter_redundant_hypotheses()`).

### 3.5 Posterior Computation

The joined dataframe passes to `compute_posterior()` (Section 2), which
performs both the point estimate and Monte Carlo updates.

------------------------------------------------------------------------

## 4. LLM-Shortcut Workflow

The LLM-shortcut workflow (`assign_taxa_llm()`) provides a faster
alternative when a full TaxaLikely model and TaxaExpect spatial model
are not available. It replaces calibrated likelihoods and spatial priors
with score-based proxies and LLM expert judgment, respectively.

### 4.1 Likelihood Proxy via Exponential Score Weighting

Instead of the bivariate normal density from TaxaLikely, the
LLM-shortcut workflow converts raw match scores to likelihood proxies
using an exponential weighting function:

$$L_i = \exp(\lambda \times s_i)$$

where $s_i$ is the match score for candidate $i$ and $\lambda$ is the
`score_sharpness` parameter (default 0.1). The exponential function has
two desirable properties:

1.  **Monotonicity**: higher scores always produce higher likelihoods.
2.  **Tuneable discrimination**: $\lambda$ controls how aggressively
    small score differences translate to large likelihood ratios.
    -   $\lambda = 0.1$ (default): a 10-point score difference produces
        a likelihood ratio of $e^1 \approx 2.7$, appropriate for percent
        identity scores on a 0--100 scale.
    -   Larger $\lambda$: more aggressive discrimination; suitable when
        scores are highly informative.
    -   Smaller $\lambda$: flatter discrimination; appropriate when
        scores are noisy or on a narrow range.

For each observation, scores are aggregated to one value per taxon_name
(median across reference accessions), then converted:

$$\hat{L}_i = (1 - w_u) \times \frac{\exp(\lambda \times s_i)}{\sum_j \exp(\lambda \times s_j)}$$

where $w_u$ is the `unknown_lik_weight` (default 0.05), reserved for an
`unreferenced_family` hypothesis (NA `taxon_name`) that captures the
probability that the true taxon is not among any of the candidates.

### 4.2 Unreferenced Species Insertion

When `unreferenced_taxa` is provided (typically from
`suggest_unreferenced_species()`), unreferenced species are inserted
into the likelihood table with scores derived from their referenced
congeners:

-   **Genus-level unreferenced** (`unreferenced_species`): each species
    receives the median exponential score of its congeners in the
    candidate set.
-   **Family-level unreferenced** (`unreferenced_genus`): each species
    from a represented family but unrepresented genus receives the
    median exponential score of family members.

This parallels TaxaLikely's H2/H3 hypotheses but uses score-based
proxies rather than the trained delta-offset model.

### 4.3 LLM Prior Estimation

The core innovation of the LLM-shortcut workflow is using a large
language model as an expert biogeographer to estimate priors. For each
group of observations (optionally stratified by `context_group`), the
LLM receives:

-   **Context**: ecoregion, coordinates, date/season, habitat
-   **Survey context**: known present/absent species
-   **Taxa list**: each candidate taxon with rank and hypothesis type
-   **Prior weight guide**: structured ranges mapping ecological
    categories to prior weight bounds

The LLM returns a JSON array with four fields per taxon:

| Field | Values | Purpose |
|------------------------|------------------------|------------------------|
| `range_status` | native, introduced_established, documented_nearby, not_documented, taxonomically_impossible, uncertain | Geographic presence |
| `habitat_fit` | expected, occasional, unlikely | Habitat suitability |
| `information_quality` | high, moderate, low | Data availability for this taxon in this region |
| `prior_weight` | numeric | Raw prior weight integrating range and habitat |

#### Prior Weight Guide

The `prior_weight_guide` parameter provides structured ranges that
anchor the LLM's prior weights to ecologically defensible bounds:

| Category | Default range | Rationale |
|------------------------|------------------------|------------------------|
| native + expected habitat | 0.5 -- 1.0 | Species in its primary habitat |
| native + occasional habitat | 0.03 -- 0.15 | Species uses habitat peripherally |
| native + unlikely habitat | 0.003 -- 0.03 | Right region, wrong habitat |
| documented_nearby + expected | 0.05 -- 0.3 | Broader region, could occur |
| documented_nearby + occasional/unlikely | 0.002 -- 0.05 | Marginal range, marginal habitat |
| not_documented | 0.001 -- 0.02 | No records from region |
| taxonomically_impossible | 0.0001 -- 0.002 | Wrong continent/realm |

These ranges produce approximately a 10-fold reduction per ecological
step, consistent with expert elicitation principles (O'Hagan et al.
2006). The user can customize ranges via the `prior_weight_guide`
parameter.

#### Information Quality and Beta Concentration

The LLM's `information_quality` assessment maps to Beta distribution
concentration $\phi$ via the `prior_phi` parameter:

| Quality  | Default $\phi$ | Interpretation                             |
|----------|----------------|--------------------------------------------|
| high     | 50             | Well-studied; prior tightly held           |
| moderate | 10             | Some records; prior moderately informative |
| low      | 3              | Data-deficient; prior easily overridden    |

Beta parameters are then: $\alpha = \mu \times \phi$,
$\beta = (1 - \mu) \times \phi$

where $\mu$ is the normalized prior weight from the LLM.

This design means that a data-deficient taxon with a moderate prior
weight can still be overridden by strong likelihood evidence (low $\phi$
→ wide Beta → large MC variance), while a well-studied taxon requires
stronger evidence to shift its posterior away from the prior.

### 4.4 Incorporating Local Knowledge

The LLM may have blind spots, and users often have local knowledge
that can improve priors. `assign_taxa_llm()` provides two parameters
for injecting this knowledge:

#### Known-absent species

The `known_absent` parameter accepts a character vector of taxon names
or a data.frame with `taxon_name` and `detection_prob` columns. For
each known-absent taxon found among the candidates, the prior is
mathematically suppressed:

$$\pi'_i = \pi_i \times (1 - p_{\text{det}})$$

where $p_{\text{det}}$ is the estimated detection probability (default
0.80 for a character vector; user-specified per taxon in the data.frame
form). This is applied after LLM prior estimation but before posterior
computation. The suppression is ecologically motivated: if a species was
not detected despite adequate survey effort, its prior should be reduced
by the complement of the detection probability.

#### Known-present species

The `known_present` parameter accepts a character vector of taxon names
confirmed to occur at the site (e.g., from visual surveys, prior eDNA
studies, or expert knowledge). These names are passed to the LLM as
ecological context, allowing it to make more informed `range_status` and
`habitat_fit` judgments. However, `known_present` does not
mathematically elevate priors -- the LLM integrates this information
qualitatively when setting `prior_weight`.

Mathematical prior elevation for known-present species is handled
separately by `update_prior_from_consensus()` (Section 6), which boosts
priors for species confirmed by the data itself across multiple
observations. Direct user-specified elevation (analogous to the
`known_absent` suppression formula) is not currently implemented, as it
would risk double-counting when the LLM has already incorporated
presence information into its weights.

### 4.5 The Unreferenced-Family Hypothesis

Both workflows include an explicit `unreferenced_family` hypothesis
(Session 99+; formerly `"unknown_species"`) that captures the
probability that the observation belongs to a taxon not represented by
any named candidate. This makes it possible to discover
range expansions and newly introduced species. In the LLM-shortcut
workflow:

-   Likelihood: fixed at `unknown_lik_weight` (default 0.05)
-   Prior: set to `unknown_lik_weight` after all named priors are
    rescaled to sum to $1 - w_u$

This ensures there is always a non-zero posterior probability that the
observation is something unexpected, preventing overconfident assignment
to the best-matching candidate when that match is poor.

------------------------------------------------------------------------

## 5. Posterior Consensus

After computing posteriors for all observations, TaxaAssign derives a
single consensus taxonomic assignment per observation. Two methods are
available.

### 5.1 Posterior-Based Consensus

`posterior_consensus()` uses posterior probabilities to determine the
finest taxonomic rank at which assignment is confident:

1.  **Candidate filtering**: retain hypotheses with
    `posterior_mean ≥ min_posterior` (default 0.01). Drop
    `unreferenced_family` rows, identified by `is.na(taxon_name)` (not assignable to a named taxon).

2.  **Cumulative probability**: sort candidates by descending
    `posterior_mean` and accumulate until the running sum exceeds
    `cumulative_threshold` (default 0.95). This identifies the
    "plausible set" -- the smallest set of hypotheses that jointly
    account for ≥95% of the posterior mass.

3.  **Resolution check**: if a single species captures ≥ the threshold
    alone, the observation is **resolved** at species level.

4.  **Lowest Common Ancestor (LCA)**: when the plausible set contains
    multiple taxa, compute the LCA -- the finest taxonomic rank at which
    all plausible candidates agree. For example, if the plausible set
    contains *Fundulus parvipinnis* and *Fundulus heteroclitus*, the LCA
    is genus *Fundulus*.

5.  **Consensus reason**: each assignment is tagged with the path taken:

    -   `"unanimous"` -- single hypothesis captures 100% of posterior
    -   `"single"` -- single hypothesis exceeds cumulative threshold
    -   `"lca"` -- multiple hypotheses; LCA computed
    -   `"threshold"` -- fell below min_posterior filter

6.  **Downranking**: when the consensus resolves to a coarse rank (genus
    or family) but a `species_reference` indicates that only one
    finer-rank taxon exists in that group at the study site, the
    consensus is recursively downranked to that taxon. This prevents
    unnecessary loss of resolution when taxonomic ambiguity is an
    artifact of the reference database structure rather than genuine
    uncertainty.

Output columns include: `consensus_taxon`, `consensus_rank`,
`is_resolved` (species-level), `consensus_posterior` (summed posterior
of the plausible set at the consensus rank),
`consensus_confidence_score` (summed confidence scores), `n_hypotheses`,
and `consensus_reason`.

### 5.2 Score-Based Consensus

There are many conventional (non Bayesian) taxonomic assignment methods
that evaluate candidates according to scores. Some, for instance, keep
the highest score. Others only retain 100% matches. Some assign
taxonomic ranks based on thresholds. Some use a "white list" of
plausible taxa. TaxaAssign captures these approaches with
`score_consensus()` (no model, no priors). This enables comparison with
the posterior-based method and is useful when only match data is
available.

The function can apply combinations of filters to generate one of the
many conventional algorithms:

1.  **Minimum score** (`min_score`, default 80): drop candidates below
    this threshold.
2.  **Maximum gap** (`max_gap`, default NULL): if the gap between the
    top two scores exceeds this value, accept the top candidate.
3.  **Rank thresholds**: rank-specific minimum scores (default: species
    ≥ 98, genus ≥ 95, family ≥ 90, order ≥ 85). Accept at the finest
    rank where the top candidate exceeds the threshold.
4.  **Whitelist**: if a trusted species list is provided, candidates not
    on the list are penalized.

When multiple candidates survive all filters, LCA is computed using the
same `.find_lca()` machinery as the posterior consensus.

Score consensus and posterior consensus can be compared directly:
agreement validates the posterior approach, while disagreements
highlight where prior information or calibrated likelihoods changed the
outcome.

------------------------------------------------------------------------

## 6. Empirical Bayes Refinement

`update_prior_from_consensus()` implements a one-pass empirical Bayes
refinement that leverages resolved observations to improve unresolved
ones within the same dataset:

1.  **Identify confirmed species**: extract taxa where
    `is_resolved = TRUE` from the first-pass consensus.

2.  **Identify unresolved observations**: observations where the
    consensus did not achieve species-level resolution.

3.  **Boost priors**: for each unresolved observation, if a confirmed
    species appears among its candidate hypotheses, multiply that
    candidate's `prior_mean` by `presence_multiplier` (default 5). This
    encodes the reasoning: "if this species was confidently identified
    in another observation from the same study, it is more likely
    present in observations where assignment is ambiguous."

4.  **Recompute posteriors**: run `compute_posterior()` again on
    unresolved observations with the boosted priors.

The updated result carries `prior_updated = TRUE/FALSE` flags and
`consensus_taxon_v1` / `consensus_rank_v1` columns showing the
pre-refinement assignment, enabling comparison of pass-1 and pass-2
outcomes.

This approach is analogous to empirical Bayes methods in genomics (Efron
and Morris 1973), where information from the full dataset informs
estimation for individual observations. It is particularly effective for
studies where the same species may appear in multiple observations at
different confidence levels.

------------------------------------------------------------------------

## 7. Hypothesis Types

TaxaAssign recognizes five hypothesis types, each with distinct
statistical treatment:

| Type | Source | Description | Prior source |
|------------------|------------------|------------------|------------------|
| `specific_candidate` | TaxaLikely H1 or score-based | Species in the reference database | TaxaExpect Tier 1/2 or LLM |
| `unreferenced_species` | TaxaLikely H2 or LLM | Congener absent from reference | TaxaExpect Tier 3 or LLM |
| `unreferenced_genus` | TaxaLikely H3 or LLM | Family-level unreferenced taxon | TaxaExpect Tier 3 or LLM |
| `unreferenced_family` | assign_taxa_llm() | Uncharacterised diversity (NA taxon_name) | Fixed weight |
| `unresolved_species` | apply_coverage_constraints() | Ambiguous among referenced genus members | Inherited from genus |

The `unreferenced_family` hypothesis is excluded from consensus (it
represents the possibility that no named hypothesis is correct, but does
not itself name a taxon). All other types participate in LCA
computation.

------------------------------------------------------------------------

## 8. Pipeline Position and Data Flow

```         
TaxaMatch ──→ TaxaLikely ──→┐
                             ├──→ TaxaAssign ──→ TaxaFlag
TaxaFetch → TaxaHabitat ──→ TaxaExpect ──→┘

Within TaxaAssign:
  Full Bayesian:
    evaluate_likelihoods() → expand_unreferenced_hypotheses()
    → join_priors() → compute_posterior()
    → posterior_consensus() → update_prior_from_consensus()

  LLM-shortcut:
    assign_taxa_llm() [internally: .score_to_likelihood()
    → LLM prior estimation → compute_posterior()]
    → posterior_consensus() → update_prior_from_consensus()
```

------------------------------------------------------------------------

## 9. Assumptions and Limitations

### Independence assumptions

-   **Conditional independence of observations**: each observation is
    treated independently given its candidate set. In practice,
    observations from the same sample may share species composition --
    the empirical Bayes refinement (Section 6) partially addresses this,
    but a full hierarchical model across observations is not
    implemented.

-   **Independence of likelihood and prior**: the Bayesian update
    assumes the likelihood and prior are derived from independent data.
    This holds when TaxaLikely's reference library and TaxaExpect's
    occurrence data are separate from the observation being classified.

### LLM-shortcut workflow limitations

-   **Exponential weighting is not calibrated**: unlike TaxaLikely's
    trained model, the exponential score transformation is a monotone
    proxy, not a density estimate. Score differences may not accurately
    reflect true likelihood ratios.

-   **LLM prior stochasticity**: LLM responses are stochastic -- the
    same prompt may produce different prior weights on different calls.
    The Beta concentration parameter ($\phi$) captures this uncertainty
    in the Monte Carlo simulation, but the prior_weight itself is a
    single draw from the LLM.

-   **Prior weight guide ranges are heuristic**: the default ranges were
    calibrated against expert judgment for coastal California eDNA data.
    Other systems (tropical forests, deep-sea, etc.) may require
    different ranges.

### Consensus limitations

-   **LCA is conservative**: when the plausible set spans multiple
    genera, the consensus jumps to family level even if one genus
    dominates. The `consensus_posterior` and `n_hypotheses` columns help
    users assess how informative the coarser assignment still is.
    Furthermore, plausible candidates and their scores are retained so a
    user can determine which subset of species a higher rank most likely
    refers to.

-   **Downranking requires a reference**: downranking only fires when
    a `species_reference` is supplied to `posterior_consensus()`. This
    reference is a lookup table of plausible species at the study site
    -- typically an `unreferenced_species_result` object (from
    `suggest_unreferenced_species()`) or a data.frame with species,
    genus, and family columns (e.g., from a GBIF census). When a
    consensus resolves to a coarse rank (say genus *Fundulus*), the
    function checks the reference for finer-rank taxa under that
    group; if exactly one species of *Fundulus* is plausible at the
    site, the consensus is downranked to that species. Without a
    reference, the function cannot distinguish a genuinely ambiguous
    genus from one that contains only a single plausible species, so
    it conservatively reports the coarser rank.

### Dark diversity assumptions

-   The dark diversity fallback (Section 3.4) assumes that a species
    absent from TaxaExpect's spatial model should receive a prior
    comparable to undetected species at that site. This is conservative:
    the species could be truly absent (deserving a near-zero prior) or
    simply under-sampled (deserving a higher prior). The design errs on
    the side of inclusion to avoid false negatives. But inclusion may
    also lead to implausible candidates becoming the consensus. The
    TaxaFlag package is designed to identify these outcomes for further
    consideration.

------------------------------------------------------------------------

## 10. Glossary

| Term | Definition |
|------------------------------------|------------------------------------|
| **observation_id** | Unique identifier for a single observation (e.g., an ASV, image, sound clip) |
| **hypothesis** | A candidate taxonomic assignment for an observation |
| **likelihood** | $L(D \mid H)$: probability of the observed data given that hypothesis $H$ is true |
| **prior** | $\pi(H)$: probability of hypothesis $H$ before seeing the data |
| **posterior** | $P(H \mid D)$: probability of hypothesis $H$ after incorporating the data |
| **confidence_score** | Fraction of MC simulations in which a hypothesis had the highest posterior |
| **cumulative_threshold** | Minimum posterior mass that the plausible set must capture (default 0.95) |
| **LCA** | Lowest Common Ancestor: finest rank at which all plausible candidates agree (can lead to upranking). |
| **score_sharpness** | $\lambda$ in the exponential weighting function (LLM-shortcut workflow) |
| **prior_phi** | $\phi = \alpha + \beta$: Beta concentration controlling prior tightness |
| **dark diversity** | Species expected to occur at a site but not yet observed there |
| **unreferenced species** | Described species absent from the reference database |
| **downranking** | Refining a coarse consensus to a finer rank when only one candidate exists |
| **empirical Bayes refinement** | Using resolved observations to update priors for unresolved ones |

------------------------------------------------------------------------

## Key Functions

| Function | Purpose |
|------------------------------------|------------------------------------|
| `compute_posterior()` | Bayesian update: likelihood × prior → posterior (point + MC) |
| `join_priors()` | Bridge TaxaLikely likelihoods + TaxaExpect priors; dark diversity fallback |
| `expand_unreferenced_hypotheses()` | Replace generic H2/H3 rows with named unreferenced species |
| `assign_taxa_llm()` | LLM-shortcut: score weighting + LLM priors → posterior |
| `posterior_consensus()` | Posterior-based consensus: cumulative threshold + LCA |
| `score_consensus()` | Score-based consensus: rank thresholds + LCA (no model required) |
| `update_prior_from_consensus()` | Empirical Bayes: boost confirmed species in unresolved observations |
| `run_bayesian_pipeline()` | High-level wrapper for full Bayesian workflow |
| `run_llm_pipeline()` | High-level wrapper for LLM-shortcut workflow |
| `suggest_unreferenced_species()` | LLM-first unreferenced species detection |
| `build_context()` | Auto-populate ecological context from taxon names via LLM |

------------------------------------------------------------------------

## References

Berger, J.O., 1985, Statistical Decision Theory and Bayesian Analysis,
2nd ed.: Springer-Verlag, New York, 617 p.

Brooks, M.E., Kristensen, K., van Benthem, K.J., Magnusson, A., Berg,
C.W., Nielsen, A., Skaug, H.J., Maechler, M., and Bolker, B.M., 2017,
glmmTMB balances speed and flexibility among packages for zero-inflated
generalized linear mixed modeling: The R Journal, v. 9, no. 2, p.
378--400.

Efron, B., and Morris, C., 1973, Stein's estimation rule and its
competitors -- an empirical Bayes approach: Journal of the American
Statistical Association, v. 68, p. 117--130.

Huson, D.H., Auch, A.F., Qi, J., and Schuster, S.C., 2007, MEGAN
analysis of metagenomic data: Genome Research, v. 17, p. 377--386.

Jeffreys, H., 1946, An invariant form for the prior probability in
estimation problems: Proceedings of the Royal Society of London, Series
A, v. 186, p. 453--461.

O'Hagan, A., Buck, C.E., Daneshkhah, A., Eiser, J.R., Garthwaite, P.H.,
Jenkinson, D.J., Oakley, J.E., and Rakow, T., 2006, Uncertain Judgements
-- Eliciting Experts' Probabilities: John Wiley and Sons, Chichester,
321 p.
