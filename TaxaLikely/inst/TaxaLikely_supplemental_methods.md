# TaxaLikely: Statistical Background

## From Match Scores to Likelihoods — A Generative Bayesian Framework for Open-Set Taxonomic Recognition

*This document provides the statistical rationale behind TaxaLikely. It is
intended as a manuscript-ready methods reference for the TaxaID ecosystem.*

---

## 1. Problem Statement

Traditional DNA barcoding relies on "top hit" approaches (e.g., BLAST; Hebert
et al. 2003), which assign taxonomy based strictly on the highest percentage
match. This approach fails in the context of **open-set recognition** (Scheirer
et al. 2013) — the scenario where the true species or genus of the query
sequence is absent from the reference database.

For example, a 91% match to *Luciogobius* could imply a poor-quality sequence of
a known species, a novel species within *Luciogobius*, or a novel genus entirely.
Distinguishing these scenarios requires a probabilistic framework that evaluates
not just the magnitude of the match, but the distribution of matches expected at
each taxonomic rank.

Previous work on probabilistic taxonomic assignment (Somervuo et al. 2017;
Axtner et al. 2019; Zito et al. 2023) has addressed the open-set problem by
placing prior probabilities over both known and unknown taxa. TaxaLikely extends
this approach by explicitly separating the likelihood estimation from the prior,
training a generative model on reference-vs-reference pairwise distances
(`build_sequence_matrix()` + `train_likelihood_model()`) and then applying that
model to convert per-query match scores into calibrated likelihoods
(`evaluate_likelihoods()`). Priors are estimated independently by TaxaExpect.

---

## 2. Statistical Framework: Generative vs. Discriminative

While discriminative models (e.g., logistic regression, random forests) quantify
the boundary between classes (Ng & Jordan 2001), they inherently incorporate the
class imbalance of the training data as an implicit prior. This biases assignments toward species
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

Per-species parameters are shrunk toward the global mean using a James–Stein /
Empirical Bayes estimator (Efron & Morris 1973), with weight inversely
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
distribution using a **bivariate normal density** (Genz et al. 2023):

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

### Closed-World Assumption and Posterior Inflation

Any step that reduces the hypothesis set before posterior computation introduces
a **closed-world assumption**: the model implicitly treats the retained candidates
as an exhaustive partition of the possibility space. Because TaxaAssign normalizes
posteriors by summing likelihood × prior over retained hypotheses only, removing
low-scoring candidates from the denominator inflates the posteriors of all
remaining hypotheses relative to what a full-denominator calculation would yield.
The normalized posteriors still sum to 1.0, but that 1.0 now means "probability
of being correct, *given that the true taxon is among the retained candidates*"
— not "unconditional probability of being correct."

This is a general property of truncated hypothesis-space classifiers and is not
unique to TaxaLikely. The same inflation arises in BLAST top-hit approaches, RDP
Naive Bayes (Wang et al. 2007), and any classifier that filters before
normalization. It is worth noting explicitly because it means posterior values
near 1.0 should be interpreted with some caution: they indicate strong evidence
*among the evaluated hypotheses*, not necessarily strong evidence in an absolute
sense.

Two structural features of TaxaID partially mitigate this inflation:

1. **H2 and H3 catch-all hypotheses.** `evaluate_likelihoods()` always generates
   an unreferenced-species (H2) and unreferenced-genus (H3) row for each query.
   These act as a continuous "none of the above" probability sink — when the
   observed (score, gap) pattern is more consistent with an absent taxon than with
   any referenced species, H2/H3 absorbs probability mass and suppresses the H1
   posteriors accordingly.

2. **Unreferenced-species expansion.** `TaxaAssign::expand_unreferenced_hypotheses()`
   and `TaxaLikely::unreferenced_candidates()` widen the denominator by adding
   placeholder rows for unreferenced congeners before posterior
   computation, further limiting the inflation from a short H1 list.

For applications where conservative posteriors are preferred, users can set
`ratio_threshold = 0` (retain all candidates, including very weak ones) to
maximize denominator coverage, at the cost of a larger likelihood object.

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

The result is `score_likelihood_mean` and `score_likelihood_sd` across simulations, providing
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

## 11. From match scores to likelihoods: the calibration problem

Automated identification tools return a *match score* — BLAST percent identity for
sequence data, cosine or embedding similarity for images, or classifier confidence
for acoustic recordings. These scores are bounded, monotonically related to match
quality, and superficially probability-like, which invites the temptation to read
them directly as probabilities of correct identification. This temptation should be
resisted. As Wood & Kahl (2024) state for the BirdNET classifier, confidence scores
"are not probabilities"; Knight et al. (2017) reach the same conclusion for acoustic
recognizers in general. The same caution applies to BLAST percent identity: a score
of 98% is not a 98% probability that the query and reference are conspecific, and a
score of 100% is not certainty. A match score is an *unitless* quantity whose
relationship to identification accuracy must be learned, not assumed.

In a multi-hypothesis discrimination setting — *which taxon produced this
observation?* — the quantity we need is not a calibrated success probability but a
*likelihood*: the probability of observing the score we observed, given each
candidate taxon hypothesis $H$. Writing $s$ for the (transformed) score, the
likelihood is $L(H \mid s) = f_H(s)$, the value of the score density under $H$, and
posterior assignment follows from Bayes' rule,
$P(H \mid s) \propto f_H(s)\, \pi(H)$, with $\pi(H)$ the prior. Likelihoods require a
*generative* model of the score distribution under each hypothesis, which is exactly
what TaxaLikely estimates from reference data. This is also the structure underlying
model-based, decision-theoretic species assignment in the DNA-barcoding literature
(Abdo & Golding 2007), where assignment is driven by the probability of the data
under each candidate group rather than by a fixed similarity cutoff.

Our approach can be read as a generalization of the logistic-regression calibration
recommended by Wood & Kahl (2024). Their procedure regresses a binary
correct/incorrect outcome on the score to recover $P(\text{correct} \mid s)$; this is
a two-hypothesis, univariate calibration. TaxaLikely instead models the full bivariate
feature $(s, g)$ — score together with the *gap* to the next-best competing match —
under multiple competing hypotheses, yielding per-hypothesis likelihoods rather than a
single success probability. The bivariate generative model and the logistic
calibration agree in the two-class, gap-free limit, but the generative form extends
naturally to the open, multi-taxon problem that eDNA and survey identification
present.

---

## 12. The open-reference problem: closure belongs in the prior

A reference database is almost never a complete census of the taxa that could have
generated an observation. Many species in a study region have no reference sequence,
and a species with no reference simply *cannot* produce a high-scoring match to itself.
We quantify this incompleteness with a closure parameter
$\varphi = N_{\text{referenced}} / N_{\text{related}}$, where $N_{\text{related}}$
counts only the species in the genus (or family) from which the match was drawn —
the set of taxa that could plausibly have generated the observed score — not all
species in the study region. The central modelling decision is where $\varphi$ enters
the inference.

**Closure belongs in the prior, not the likelihood.** The likelihood
$f_H(s, g)$ is conditioned on the score actually observed; it answers "how probable is
this score under hypothesis $H$?" The existence — or non-existence — of an unreferenced
alternative taxon does not change the probability of observing a given score under any
of the *stated* hypotheses, so it cannot belong in $f_H$. Instead, $\varphi$ shapes the
prior probability that an unreferenced taxon is present at all. Because an unreferenced
species produces no match of its own, it can be inferred only indirectly, through
dark-diversity modelling (TaxaExpect), which supplies a prior probability of presence
for taxa absent from the reference. This is precisely the logic of occupancy models
with imperfect detection (MacKenzie et al. 2002): non-detection does not imply absence,
and the probability that a species is present given that it was not detected depends on
detection probability and occupancy (the prior), not on the value of any detection
score. Mixing $\varphi$ into the likelihood would double-count this information and
conflate "the score is low" with "the true taxon may be unreferenced."

TaxaLikely therefore frames three hypothesis types for any observation:

- $H_1$ — the match is to the *correct referenced species* (a conspecific reference
  exists and was matched);
- $H_2$ — the true species is *unreferenced but congeneric* with a referenced taxon
  (the best attainable match is to a congener, at genus level);
- $H_3$ — the true species is *unreferenced and only family-level* reference exists.

Under $H_2$ and $H_3$ no conspecific match is possible, so the observed score is
generated by a *cross-taxon* process. Their likelihoods are evaluated from the
cross-species feature distribution; $\varphi$ and TaxaExpect determine how much prior
weight these unreferenced hypotheses carry.

---

## 13. Truncation and censoring in match reporting

Match-reporting pipelines rarely return every comparison. Common retention rules
include *all-above-floor* (keep every match with score $\ge T$, e.g. $\ge 90\%$),
*100%-only* (keep only exact matches), *max-score-only* (keep the single best match per
query), and *gap-within-threshold* (keep all matches within $\delta$ of the best). Each
rule is a *selection effect*: we observe a score only conditional on its having passed
the rule. A naive likelihood that ignores this conditioning is biased.

Let $R$ denote the region of $(s, g)$ space that passes the retention rule. For an
observation retained at $(s, g)$, the corrected likelihood is

$$
L(H \mid s, g, \text{retained}) \;\propto\;
\frac{f_H(s, g)}{P(\text{retained} \mid H)},
\qquad
P(\text{retained} \mid H) = \iint_{R} f_H(s', g')\, ds'\, dg'.
$$

The denominator $P(\text{retained} \mid H)$ answers: assuming hypothesis $H$ is true
and that $H$ produces a match with score $s$ drawn from $f_H(s, g)$, what fraction of
such matches would pass the pipeline's retention rule? Crucially, $P(\text{retained} \mid H)$
does **not** cancel between $H_1$ and $H_2/H_3$, because the within-species density
$f_{H_1}$ and the cross-species densities $f_{H_2}, f_{H_3}$ have different means and
shapes. Ignoring the correction when a floor $T$ is applied gives biased likelihoods
whenever $F_{H_1}(T) \ne F_{\text{cross}}(T)$ — that is, whenever some genuine
within-species matches fall below the floor. The bias is in the direction of
over-favouring whichever hypothesis loses *less* probability mass to truncation.

Three special cases recur in practice. (i) *All-above-floor at* $T \le \min_{\text{self}}$:
if every within-species match exceeds $T$, then $P(\text{retained} \mid H_1) = 1$ and
$H_1$ needs no correction, but the cross-species hypotheses still do, since congeneric and
familial matches fail the floor more often. (ii) *Max-score-only*: the correction for
$H_1$ becomes $P(\text{best score} = s^* \mid H_1)$, the probability that the observed
score is simultaneously the maximum and equal to $s^*$; the gap dimension is degenerate
and uninformative here. (iii) *100%-only* is max-score-only at $s^* = 1.0$, so the
correction for $H_1$ is $P(\text{exact match} \mid H_1) = p_{\text{self}}$ and for $H_2$
it is $p_{\text{cross}}$. The empirical diagnostics on real California reference databases
are decisive on this last case: for 12S MiFish, $p_{\text{self}} = 0.048$ versus
$p_{\text{cross\,congeneric}} = 0.078$ (LR $= 0.61$); for 18S,
$p_{\text{self}} = 0.080$ versus $p_{\text{cross\,congeneric}} = 0.291$ (LR $= 0.27$).
For both markers the likelihood ratio of $H_1$ to congeneric $H_2$ under the 100% rule is
*below one* — a 100% BLAST hit is more consistent with a congeneric than with a conspecific
hypothesis. The familiar "100% identity = species match" heuristic is therefore not merely
imprecise but, at these markers, *anti-informative*. All reliable species-level signal lives
in the continuous score distribution, not in a binary threshold.

---

## 14. The continuous bivariate-normal as the unifying model

Rather than maintain a separate rule for each retention scheme, TaxaLikely uses a single
generative model and lets the truncation correction of Section 13 absorb the differences.
We model the transformed feature
$\mathbf{x} = \big(\operatorname{logit} s,\ \operatorname{logit} g\big)$ as bivariate
normal under each hypothesis. The logit transform maps the bounded score and gap onto the
real line, so that a Gaussian is a reasonable approximation and so that means and covariances
are unconstrained.

An alternative formulation is a discrete-continuous hybrid model: a point mass at
$(s, g) = (1.0, 0.0)$ combined with a continuous density for $s < 1.0$. This is
appropriate when exact matches occur far more often than the continuous distribution
predicts — signalled by a *spike ratio* (count of exact matches divided by count in the
immediately sub-perfect bin $[0.995, 1.0)$) substantially greater than one, roughly $\geq 5$.
However, the empirical evidence from real reference databases supports the unified continuous
representation over the hybrid: the spike ratio was 0.30–0.40 for both 12S MiFish and 18S
rDNA (temperate marine taxa, California). Values below 1 indicate that exact matches are
*less* common than sub-perfect matches — the opposite of what would justify a discrete atom.
There is no point mass at 1.0; the continuous bivariate-normal model is the correct
representation for these markers, and no special-case discrete rules are needed. A
discrete-continuous hybrid model is not currently implemented; it is noted as a potential
extension for markers that show a spike ratio well above 5, which can be assessed using the
diagnostic script `diagnostics/seq_matrix_score_distribution.R` before model fitting.
Among continuous parameterizations, model choice can be guided by AIC in the standard
multimodel framework (Burnham & Anderson 2002).

Under $H_1$ the distribution is *species-specific* — each taxon has its own mean and
covariance — but estimated with Empirical Bayes shrinkage toward the global (pooled) mean.
Species with few reference sequences shrink strongly toward the pool; well-sequenced species
retain their own parameters. This delivers, hierarchically and automatically, the
species-specific performance evaluation that Wood & Kahl (2024) and Knight et al. (2017)
recommend, without the manual per-species validation those papers describe. The $H_2$ and
$H_3$ distributions are obtained by shifting the mean (parameters `H2$delta`, `H3$delta`):
cross-species matches have systematically lower scores and larger gaps, and the shifts encode
this.

A subtlety at the boundary requires explicit regularization. Because $p_{\text{self}}$ is
*low but non-zero* (4–8% for the 12S and 18S markers examined in temperate-marine fish and
eukaryote communities), a continuous bivariate normal fit to the observed within-species cloud
assigns near-zero density at the corner $(s, g) = (1.0, 0.0)$, which would wrongly penalize the
genuine — if rare — exact self-match. `train_likelihood_model()` corrects this by injecting
synthetic `anchor_perfect` pseudo-observations at $(1.0, 0.0)$ before fitting, regularizing the
density at the boundary so that real exact matches are scored as plausible rather than anomalous.
The anchor is not an arbitrary fudge: it encodes the established fact that conspecific exact
matches occur at a small positive rate, and it prevents the model from over-interpreting their
rarity. Because all of these parameters are marker-dependent, they must be re-estimated for each
marker from a clean reference matrix; the diagnostic in
`diagnostics/seq_matrix_score_distribution.R` reports $p_{\text{self}}$,
$p_{\text{cross\,congeneric}}$, the spike ratio, and the LR at the 100% rule, which together
confirm that the continuous model is appropriate before it is applied. The same diagnostic can
also be used to assess the appropriateness of different matching thresholds, minimum-score
floors, and gap cutoffs for a given marker.

---

## 15. Reference-database requirements for model estimation

The bivariate-normal parameters are estimated from a *sequence matrix* (`seq_matrix`) that pairs
all reference sequences within a distance threshold and records, for each pair, whether it is
within- or cross-species together with its score and gap. The quality of the resulting
likelihood model is only as good as the cleanliness of these pairs, and four preprocessing steps
are required.

The table below maps the key quantities computed from the sequence matrix to the bivariate-normal
parameters they inform:

| seq_matrix quantity | Model parameter | How used |
|---|---|---|
| Within-species `p_match` values (logit-transformed) | `H1_Global_Mu[score_logit]`, `H1_Sigma[1,1]` | Pooled H1 score mean and variance; per-species means shrunk toward this |
| Within-species `gap` values (logit-transformed) | `H1_Global_Mu[gap_logit]`, `H1_Sigma[2,2]`, `H1_Sigma[1,2]` | H1 gap mean, gap variance, and score–gap covariance |
| Within-species pair count per species ($N$) | Empirical Bayes weight $w = N / (N + \text{prior\_weight})$ | Controls per-species shrinkage strength; low-$N$ species pulled toward pooled H1 |
| Congeneric cross-species `p_match` mean − within-species mean | `H2$delta` | Score-axis shift from H1 to H2 distribution |
| Congeneric cross-species score and gap variances | `H2$sigma` (2×2 matrix) | H2 distribution width and shape |
| Family-level cross-species score mean | `H3$delta` (= `H2$delta` + 2.0 logit units by default) | Additional rank-step offset from H2 to H3 |

First, **binomial name cleaning** (step 0; `TaxaTools::clean_taxon_names()`). Reference
sequences are frequently annotated with taxonomic authority strings appended to the binomial
name (e.g., *Gadus morhua* Linnaeus, 1758). If authority suffixes are not removed before
pairing, identical species annotated with and without an authority string will generate spurious
cross-species pairs, because the two label forms are treated as distinct taxa. Applying
`TaxaTools::clean_taxon_names()` to the species column before calling
`build_sequence_matrix()` ensures all records of the same species share a canonical label,
preventing this class of spurious cross-species pairing.

Second, **error correction** (`flag_reference_errors()`). Mislabelled reference sequences create
false within-species pairs — cross-species comparisons masquerading as conspecific — which
simultaneously inflate $p_{\text{cross}}$ and deflate $p_{\text{self}}$ and so bias the likelihood
ratio toward the unreferenced hypotheses $H_2/H_3$. Flagging and removing suspected mislabels
before estimation protects the within-species distribution from contamination.

Third, **blank-name filtering** (`filter_unnamed = TRUE` in `build_sequence_matrix()`).
Sequences lacking a species-level identifier generate spurious within-species pairs whenever two
unnamed records are compared (blank matched to blank). The magnitude of this artifact is large: in
an 18S rDNA database, blank-name pairs accounted for 69% of apparent within-species pairs before
filtering, badly distorting the estimated $f_{H_1}$. Excluding unnamed sequences from the
within-species count is therefore not optional housekeeping but a prerequisite for an unbiased fit.

Fourth, **thinning** (`max_seqs_per_taxon` in `build_sequence_matrix()`). Heavily sequenced model
organisms — domestic livestock, common laboratory species — contribute combinatorially many
within-species pairs and can dominate the pooled within-species distribution. In a 12S MiFish
database, *Ovis aries* (domestic sheep) accounted for 89% of within-species pairs before thinning.
Capping each taxon at roughly 10–20 sequences balances contributions across species so that the
fitted $f_{H_1}$ reflects the community rather than a handful of over-represented taxa. These four
steps together implement, at the level of the reference matrix, the balanced and species-specific
validation design that Wood & Kahl (2024) recommend for score-performance assessment.

---

## 16. Application: mapping the theory to TaxaLikely functions

The theoretical pieces above correspond directly to stages of the TaxaLikely workflow.
`build_sequence_matrix()` constructs the within-/cross-species pair table and applies the
blank-name filtering (Section 15, step 3) and thinning (step 4) needed for an unbiased fit;
`flag_reference_errors()` performs the mislabel error correction (step 2); binomial name
cleaning (step 1) is applied upstream via `TaxaTools::clean_taxon_names()` before building
the matrix. The diagnostic script `diagnostics/seq_matrix_score_distribution.R` then verifies
the modelling assumptions of Section 14 — continuity (spike ratio), $p_{\text{self}}$,
$p_{\text{cross\,congeneric}}$, and the LR at the 100% rule — confirming that the continuous
bivariate-normal model is appropriate for the marker at hand. `train_likelihood_model()`
estimates the species-specific $H_1$ distribution with Empirical Bayes shrinkage and the shifted
$H_2/H_3$ distributions, and injects the `anchor_perfect` pseudo-observations that regularize
the boundary (Section 14). Finally, `evaluate_likelihoods()` applies the calibrated generative
model (Section 11) together with the truncation correction appropriate to the reporting rule in
force (Section 13), returning per-hypothesis likelihoods $L(H_1), L(H_2), L(H_3)$ for a given
$(s, g)$. The closure parameter $\varphi$ and the dark-diversity priors from TaxaExpect
(Section 12) are combined with these likelihoods at the posterior-assignment stage, keeping
reference incompleteness firmly in the prior where it belongs.

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
| **spike ratio** | Count of exact matches ($p = 1.0$) divided by count in the immediately sub-perfect bin $[0.995, 1.0)$; values $\geq 5$ suggest a discrete atom at exact match |
| **$\varphi$ (phi)** | Reference closure: $N_{\text{referenced}} / N_{\text{related}}$, where $N_{\text{related}}$ is the number of species in the relevant genus or family that could plausibly have generated the observed score |

---

## Key Functions (TaxaLikely)

| Function | Role in Pipeline |
|----------|-----------------|
| `fetch_reference_sequences()` | Acquire reference sequences from NCBI |
| `read_reference_fasta()` | Load local reference FASTA + taxonomy |
| `build_sequence_matrix()` | Align sequences, compute pairwise distance matrix |
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

---

## References

Abdo, Z., and G. B. Golding. 2007. A step toward barcoding life: a model-based,
decision-theoretic method to assign genes to preexisting species groups.
*Systematic Biology* 56(1):44–56. doi:10.1080/10635150601167005

Axtner, J., Crampton-Platt, A., Hoerig, L.A., Mohamed, A., Xu, C.C.Y.,
Yu, D.W. and Wilting, A. (2019). An efficient and robust laboratory workflow
and target capture method for species identification from environmental DNA.
*Molecular Ecology Resources*, 19(2), 524–541.
doi:10.1111/1755-0998.12969

Burnham, K. P., and D. R. Anderson. 2002. *Model selection and multimodel inference: a
practical information-theoretic approach.* 2nd ed. Springer, New York.

Efron, B. and Morris, C. (1973). Stein's estimation rule and its
competitors — an empirical Bayes approach. *Journal of the American
Statistical Association*, 68(341), 117–130.
doi:10.1080/01621459.1973.10481350

Genz, A., Bretz, F., Miwa, T., Mi, X., Leisch, F., Scheipl, F. and
Hothorn, T. (2023). *mvtnorm: Multivariate Normal and t Distributions*.
R package. doi:10.5281/zenodo.10021696

Hebert, P.D.N., Cywinska, A., Ball, S.L. and deWaard, J.R. (2003).
Biological identifications through DNA barcodes. *Proceedings of the
Royal Society of London B*, 270(1512), 313–321.
doi:10.1098/rspb.2002.2218

Knight, E. C., K. C. Hannah, G. J. Foley, C. D. Scott, R. M. Brigham, and E. Bayne. 2017.
Recommendations for acoustic recognizer performance assessment with application to five
common automated signal recognition programs. *Avian Conservation and Ecology* 12(2):14.
doi:10.5751/ACE-01114-120214

MacKenzie, D. I., J. D. Nichols, G. B. Lachman, S. Droege, J. A. Royle, and C. A. Langtimm.
2002. Estimating site occupancy rates when detection probabilities are less than one.
*Ecology* 83(8):2248–2255. doi:10.1890/0012-9658(2002)083[2248:ESORWD]2.0.CO;2

Ng, A.Y. and Jordan, M.I. (2001). On discriminative vs. generative
classifiers: a comparison of logistic regression and naive Bayes.
*Advances in Neural Information Processing Systems*, 14, 841–848.

Scheirer, W.J., de Rezende Rocha, A., Sapkota, A. and Boult, T.E. (2013).
Toward open set recognition. *IEEE Transactions on Pattern Analysis and
Machine Intelligence*, 35(7), 1757–1772.
doi:10.1109/TPAMI.2012.256

Somervuo, P., Koskela, S., Pennanen, J., Nilsson, R.H. and Ovaskainen, O.
(2017). Unbiased probabilistic taxonomic classification for DNA barcoding
and DNA metabarcoding. *Bioinformatics*, 33(19), 2997–3005.
doi:10.1093/bioinformatics/btx369

Wang, Q., Garrity, G.M., Tiedje, J.M. and Cole, J.R. (2007). Naïve Bayesian
classifier for rapid assignment of rRNA sequences into the new bacterial
taxonomy. *Applied and Environmental Microbiology*, 73(16), 5261–5267.
doi:10.1128/AEM.00062-07

Wood, C. M., and S. Kahl. 2024. Guidelines for appropriate use of BirdNET scores and other
detector outputs. *Journal of Ornithology* 165:777–782. doi:10.1007/s10336-024-02144-5

Zito, A., Rigon, T., Ovaskainen, O. and Dunson, D.B. (2023). Bayesian
nonparametric modelling of sequential discoveries. *Methods in Ecology
and Evolution*, 14(6), 1373–1385.
doi:10.1111/2041-210X.14009
