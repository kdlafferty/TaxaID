# TaxaLikely: Statistical Background

## From Match Scores to Likelihoods — A Generative Bayesian Framework for Open-Set Taxonomic Recognition

*This document provides the statistical rationale behind TaxaLikely. It is
intended as a manuscript-ready methods reference for the TaxaID ecosystem.*

---

## 1. Problem Statement

Traditional DNA barcoding relies on "top hit" approaches (e.g., BLAST), which
assign taxonomy based strictly on the highest percentage match. This approach
fails in the context of **open-set recognition** — the scenario where the true
species or genus of the query sequence is absent from the reference database.

For example, a 91% match to *Luciogobius* could imply a poor-quality sequence of
a known species, a novel species within *Luciogobius*, or a novel genus entirely.
Distinguishing these scenarios requires a probabilistic framework that evaluates
not just the magnitude of the match, but the distribution of matches expected at
each taxonomic rank.

TaxaLikely addresses this by training a generative model on reference-vs-reference
pairwise distances (`build_reference_matrix()` + `train_likelihood_model()`) and
then applying that model to convert per-query match scores into calibrated
likelihoods (`evaluate_likelihoods()`).

---

## 2. Statistical Framework: Generative vs. Discriminative

While discriminative models (e.g., logistic regression, random forests) quantify
the boundary between classes, they inherently incorporate the class imbalance of
the training data as an implicit prior. This biases assignments toward species
that are commonly represented in the reference library, rather than species that
are ecologically plausible at the sample location.

To separate the likelihood from the prior — allowing flexible, user-defined priors
based on geographic or ecological knowledge — the TaxaID ecosystem employs a
**generative Bayesian framework**.

The posterior probability that hypothesis *H_i* is correct given data *D* is:

    P(H_i | D) = [ P(D | H_i) * P(H_i) ] / sum_j[ P(D | H_j) * P(H_j) ]

The pipeline decomposes this into three independent stages:

| Stage | Package | Responsibility |
|-------|---------|---------------|
| **Likelihood** P(D \| H) | **TaxaLikely** | Learn class-conditional score distributions from reference data |
| **Prior** P(H) | **TaxaExpect** | Estimate taxon occurrence probability from geographic, habitat, and ecological data |
| **Posterior** P(H \| D) | **TaxaAssign** | Combine likelihood and prior via Bayes' theorem; compute posteriors with Monte Carlo uncertainty |

This separation means the same likelihood model can be reused across sites with
different priors, and priors can be updated independently as new ecological
information becomes available.

---

## 3. Feature Engineering

To calculate the likelihood P(D | H), TaxaLikely uses two features derived from
the pairwise distance matrix: the **transformed match score** (absolute fit) and
the **gap to the best alternative** (relative uniqueness). Together, the joint
distribution of these features defines the statistical fingerprint of an
identification.

### 3A. The Transformed Match Score (Logit)

Raw percentage matches (*p*, ranging from 0 to 1) are ill-suited for Gaussian
density estimation because they are bounded and asymptotic. A 1% difference at
99% is biologically far more significant than a 1% difference at 50%.

TaxaLikely applies a logit transformation to map the bounded score to an
unbounded domain:

    S = ln(p / (1 - p))

This is implemented in `.normalize_scores()`, which auto-detects the input scale
(0--1 or 0--100) and clips values at `logit_epsilon` to prevent infinite logits.

### 3B. The Gap to Best Alternative

To simultaneously assess confidence (for top hits) and rank (for lower hits),
TaxaLikely computes the gap relative to the best competing hypothesis. This
calculation is performed on the logit-transformed scores, ensuring that a 1%
difference at the high end (99.9% vs. 98.9%) produces a larger statistical gap
than the same arithmetic difference at the low end (50% vs. 49%).

    Gap = S(candidate) - S(best alternative)

Interpretation:

- **Positive gap:** The candidate is the top hit. A large positive gap implies a
  confident identification; a small positive gap implies ambiguity (open-set
  territory).
- **Negative gap:** The candidate is ranked below another taxon. The magnitude
  measures how inferior this candidate is compared to the leader.
- **Gap near zero:** Multiple candidates are nearly tied — characteristic of
  unreferenced species whose true identity is absent from the reference.

The gap is capped at `max_gap_ceiling` (default 5.0 logit units) to prevent
extreme outliers from dominating the training distribution. Gap computation is
implemented in `.prep_training_data()` for training and in
`.evaluate_one_query()` for inference.

---

## 4. The Three Hypotheses

For any query sequence, TaxaLikely evaluates three classes of hypothesis:

### H1: Known Species (`specific_candidate`)

The sequence belongs to a species present in the reference database.

- **Training profile:** Derived from within-species pairwise matches (sequence X
  matched against other sequences of the same species). Computed by
  `.prep_training_data()`.
- **Expected fingerprint:** High match score, large positive gap.
- **Per-species parameters:** Species-specific mean and variance, shrunk toward
  the global mean via Empirical Bayes (see Section 5).

### H2: Unreferenced Species (`unreferenced_species`)

The sequence belongs to a species absent from the reference database, within a
genus that *is* represented. This is the "sister species" scenario — the query
matches its closest relative but not itself.

- **Training profile:** Derived from the best cross-species match within the same
  genus. TaxaLikely parameterizes this as the H1 distribution shifted left by
  `H2$delta` logit units (typically ~3.0, estimated from observed foreign-match
  scores in the training data).
- **Expected fingerprint:** Moderate match score (~90--95%), gap near zero
  (multiple congeners match similarly).

### H3: Unreferenced Genus (`unreferenced_genus`)

The sequence belongs to a genus absent from the reference database, within a
family that *is* represented. The query's best match is to a different genus
entirely.

- **Training profile:** H1 mean shifted further left by `H3$delta` (= `H2$delta`
  + 2.0 logit units — one additional taxonomic rank step).
- **Expected fingerprint:** Lower match score (typically <90%), small gap.

Both H2 and H3 are evaluated at the best-scoring candidate's position in the
(score, gap) space. This means the model asks: "Given the best match we see,
how likely is it that the true taxon is actually absent?" These generic H2/H3
rows can later be expanded into named unreferenced species by
`TaxaAssign::expand_unreferenced_hypotheses()` using taxonomic plausibility
information.

---

## 5. Hierarchical Parameter Estimation

Many taxa are rare or sparsely sampled, making it difficult to estimate robust
means and covariances directly. TaxaLikely addresses this with two complementary
strategies:

### 5A. Empirical Bayes Shrinkage

Per-species parameters are shrunk toward the global mean with weight inversely
proportional to sample size:

    w = N_obs / (N_obs + prior_weight)
    mu_species = w * mu_observed + (1 - w) * mu_global

A species with many reference sequences retains its own estimate (w -> 1); a
species with few observations is pulled toward the global mean (w -> 0). The
`prior_weight` parameter (default 10.0) controls the shrinkage strength. This is
implemented in `train_likelihood_model()`.

### 5B. Optional lme4 Random Intercepts

When `use_hierarchy = TRUE`, `train_likelihood_model()` fits linear mixed-effects
models with random intercepts per taxonomic rank (genus, family, etc.) using
`lme4::lmer()`. This "borrows strength" from related groups, ensuring that a rare
species with only a single validation sequence shrinks toward its genus-level mean
rather than having a variance of zero. The lme4 fit is used to refine the global
intercept; if it fails (e.g., insufficient rank diversity), training falls back
gracefully to the simple global mean.

### 5C. Pseudo-Data Anchoring

When `anchor_perfect = TRUE` (the default), synthetic "perfect match"
observations are injected into the H1 training data before fitting the global
mean. This prevents the **perfection penalty** — a pathology where a 100% match
receives a lower likelihood than the training mean (e.g., 98.5%) because the
Gaussian density peaks at the estimated mean.

Anchoring shifts the H1 mean toward the theoretical maximum and expands the
covariance, producing a monotonically increasing likelihood surface as match
quality approaches 100%. The number of anchor points is 10% of the H1 training
rows (minimum 5), and the anchor gap is set to the 95th percentile of observed
positive gaps.

---

## 6. Likelihood Calculation

To capture the interaction between score and gap (e.g., a small gap is more
tolerable if the score is extremely high), TaxaLikely models the joint
distribution using a **bivariate normal density**:

    L(H) = P(score, gap | mu_H, Sigma_H)

Where `mu_H` is the 2D mean vector and `Sigma_H` is the 2x2 covariance matrix
for hypothesis H. This is evaluated via `mvtnorm::dmvnorm()` inside
`.evaluate_one_query()`.

For queries with only a **single candidate taxon** (no meaningful gap), TaxaLikely
automatically falls back to a 1D normal over score alone.

An optional Mahalanobis distance check (`alpha` parameter) rejects extreme
outliers before density evaluation, preventing numerically spurious likelihoods.

### Likelihood Normalization

Raw density values are normalized to likelihood ratios: each hypothesis's
density is divided by the maximum density across all hypotheses for that query.
The best hypothesis always has a likelihood ratio of 1.0; weaker hypotheses have
ratios less than 1.0. Candidates below `ratio_threshold` (default 0.01) are
dropped — TaxaAssign treats absent rows as likelihood = 0.

---

## 7. Multi-Candidate Evaluation

Rather than evaluating only the top hit, `evaluate_likelihoods()` evaluates **all
candidate taxa** for every query (`observation_id`):

- **For each known candidate:** The H1 likelihood is calculated using the
  candidate's species-specific parameters (with hierarchical fallback to genus,
  then global mean).
- **For unreferenced hypotheses:** The H2 and H3 likelihoods are calculated using
  the best available match's position in (score, gap) space and the shifted
  distributions.

These likelihoods are then passed to TaxaAssign, where they are combined with
candidate-specific priors (from TaxaExpect) to calculate final posterior
probabilities across the entire candidate set.

---

## 8. Monte Carlo Uncertainty

When `n_sims > 0`, `evaluate_likelihoods()` propagates score uncertainty through
the model via Monte Carlo simulation. In each iteration:

1. Scores are perturbed by drawing from a normal distribution centered on the
   observed logit score with the model's global score standard deviation.
2. Gaps are recomputed from the perturbed scores (since gap depends on the
   relative ranking).
3. Likelihoods are recalculated and normalized.

The result is `likelihood_mean` and `likelihood_sd` across simulations, providing
a measure of how sensitive the likelihood ratios are to measurement uncertainty
in the match scores.

---

## 9. Reference Quality Control

Mislabeled reference sequences can corrupt model training. TaxaLikely provides
two pre-training quality checks:

### 9A. Error Detection (`flag_reference_errors()`)

Examines the pairwise distance matrix and flags mislabeled sequences — references
whose best match is to a different species than their own label. Detected
mislabeled sequences are automatically removed before training by
`train_likelihood_model()`.

### 9B. Coverage Auditing

Two functions assess whether the reference database is complete enough for
reliable inference:

- **`audit_barcode_coverage()`** — For DNA barcoding: queries NCBI to identify
  described species within each genus that have no barcode sequence at all
  (unreferenced species that can never appear as a match candidate).
- **`audit_reference_coverage()`** — For non-barcode applications: queries NCBI
  taxonomy to identify all described species and compares against the reference.

Coverage audit results feed into `apply_coverage_constraints()`, which suppresses
H2 (unreferenced species) hypotheses for genera that are fully sampled in the
reference.

---

## 10. Visualizing the Likelihood Landscape

The standalone script `inst/plot_likelihood_landscape.R` produces a two-panel
figure showing the H1 and H2 probability density surfaces in (score, gap) space,
with labeled example points illustrating how different match outcomes map onto
the landscape.

This visualization shows that taxonomy assignment is not a simple threshold on
match percentage — it is a joint evaluation of how well the score matches the
expected distribution *and* how distinct the match is from competing
alternatives. A 95% match with a large gap (clear winner) is a more confident
H1 identification than a 98% match with a tiny gap (several species nearly
tied). Conversely, a moderate score with no gap is consistent with H2 — the true
species is absent and the query is matching its closest relative in the
reference.

---

## Glossary

| Term | Definition |
|------|-----------|
| **score_logit** | Logit-transformed match score: `ln(p / (1-p))` |
| **gap_logit** | Logit score of candidate minus logit score of best alternative |
| **H1 / specific_candidate** | Query belongs to a species in the reference |
| **H2 / unreferenced_species** | Query belongs to a species absent from the reference, in a represented genus |
| **H3 / unreferenced_genus** | Query belongs to a genus absent from the reference, in a represented family |
| **delta** | Logit offset from H1 global mean used to position H2/H3 distributions |
| **prior_weight** | Controls Empirical Bayes shrinkage strength (higher = more shrinkage) |
| **anchor_perfect** | Pseudo-data injection to prevent penalizing perfect matches |
| **taxa_model_params** | S3 class returned by `train_likelihood_model()` containing all fitted parameters |

---

## Key Functions (TaxaLikely)

| Function | Role in Pipeline |
|----------|-----------------|
| `fetch_reference_sequences()` | Acquire reference sequences from NCBI |
| `read_reference_fasta()` | Load local reference FASTA + taxonomy |
| `build_reference_matrix()` | Align sequences, compute pairwise distance matrix |
| `flag_reference_errors()` | Detect mislabeled references |
| `train_likelihood_model()` | Fit hierarchical model, produce `taxa_model_params` |
| `interpret_model()` | Summarize model parameters in human-readable form |
| `evaluate_likelihoods()` | Apply model to queries, produce likelihood ratios |
| `filter_top_hypotheses()` | Retain finest-rank candidates per query |
| `audit_barcode_coverage()` | Identify unreferenced species (DNA barcoding) |
| `audit_reference_coverage()` | Identify unreferenced species (general) |
| `apply_coverage_constraints()` | Suppress H2 for fully-sampled genera |

---

## Pipeline Position

```
TaxaMatch (standardize scores)
    |
    v
TaxaLikely (this package)
    |-- train_likelihood_model() on reference-vs-reference data
    |-- evaluate_likelihoods() on query match scores
    |-- audit coverage, apply constraints
    |
    v
TaxaAssign
    |-- combine with TaxaExpect priors
    |-- compute_posterior()
    |-- posterior_consensus()
```
