# Statistical Defensibility Review — TaxaID Ecosystem

**Generated:** 2026-04-13 (Session 56)
**Scope:** All statistical decisions in TaxaLikely, TaxaExpect, TaxaAssign
**Purpose:** Assess whether each statistical choice is grounded in theory or ad hoc; propose principled alternatives or document tradeoffs.

---

## Table of Contents

1. [Likelihood Model (TaxaLikely)](#1-likelihood-model-taxalikely)
2. [Empirical Bayes Shrinkage](#2-empirical-bayes-shrinkage)
3. [H2/H3 Hypothesis Construction](#3-h2h3-hypothesis-construction)
4. [Pseudo-Data Anchoring](#4-pseudo-data-anchoring)
5. [Monte Carlo Simulation](#5-monte-carlo-simulation)
6. [Prior Construction (TaxaExpect)](#6-prior-construction-taxaexpect)
7. [LLM Prior Assignment (TaxaAssign)](#7-llm-prior-assignment-taxaassign)
8. [Posterior Computation](#8-posterior-computation)
9. [Consensus Taxonomy Rules](#9-consensus-taxonomy-rules)
10. [Empirical Bayes Update from Consensus](#10-empirical-bayes-update-from-consensus)
11. [Reference QC (Mislabel Detection)](#11-reference-qc-mislabel-detection)
12. [Score Normalization](#12-score-normalization)
13. [Summary and Recommendations](#13-summary-and-recommendations)

---

## 1. Likelihood Model (TaxaLikely)

### Decision: Bivariate Normal in (score_logit, gap_logit) for H1

**Assessment: Well-grounded with minor caveats.**

The logit transform maps (0,1) scores to (-∞, +∞) where normality is more plausible than on the raw scale. The bivariate normal over (score, gap) captures two distinct discriminating features: absolute match quality and relative separation from the runner-up.

**Strengths:**
- Logit transform is the canonical variance-stabilizing transform for proportions (Warton & Hui, 2011).
- The gap feature is genuinely informative: a 95% match with a 5% gap to the second-best is much more diagnostic than a 95% match with a 0.1% gap. This is well-established in the BLAST literature (Koski & Golding, 2001).
- MVN with 2 features is parsimoniously identified even with modest data.

**Caveats:**
- MVN assumes elliptical contours. If the score-gap relationship is nonlinear (e.g., gap shrinks at very high scores because multiple species co-converge), the elliptical assumption may underweight high-score, low-gap observations. **Recommendation:** Add a diagnostic to `interpret_model()` — a scatter plot of (score_logit, gap_logit) overlaid with the fitted ellipse. If systematic deviations are visible, document that a copula or kernel density alternative exists.
- The choice of `mvtnorm::dmvnorm()` for density evaluation is correct and numerically stable.

**Alternative approaches (document for users):**
- Kernel density estimation (KDE): non-parametric, no distributional assumptions; requires more data per species.
- Mixture models: accommodate multi-modal species distributions (e.g., subspecies clusters). Heavier parameterization; only justified with >50 reference sequences per species.

### Decision: 1D Normal fallback for singleton queries

**Assessment: Principled and necessary.**

When only one candidate taxon exists for a query, the gap is artificial (set to `max_gap_ceiling`). Reducing to 1D avoids the gap dimension contributing meaningless information.

**No change needed.** This is correct. The code at `evaluate.R:97` cleanly detects singletons and switches.

### Decision: Median score per taxon_name before likelihood evaluation

**Assessment: Well-grounded.**

`evaluate.R:86-91` takes the median score across multiple reference accessions per taxon before computing likelihoods. This is robust to outlier accessions (e.g., a mislabeled reference that inflates the max) and reduces sample-size bias (taxa with more references would otherwise dominate).

**The median is preferable to the mean** for this purpose because a single contaminated reference can pull the mean but not the median. **No change needed.**

---

## 2. Empirical Bayes Shrinkage

### Decision: w = N / (N + prior_weight) shrinkage toward global mean

**Assessment: Well-grounded — standard Empirical Bayes.**

The shrinkage formula at `train.R:487`:
```r
w = n_obs_species / (n_obs_species + prior_weight)
shrunk_mu = w * species_mean + (1 - w) * global_mean
```

This is the textbook James-Stein / Efron-Morris shrinkage estimator for Normal means (Efron & Morris, 1973). When N is small, the estimate is pulled strongly toward the global mean; when N is large, the species-specific estimate dominates.

**prior_weight = 10.0:**
Interpreted as the "equivalent sample size" of the prior. With N=10 observations, the species mean and global mean receive equal weight. This is a reasonable default for barcode data where most species have 3-20 reference sequences.

**Recommendation:** Add a code comment citing Efron & Morris (1973) and noting the interpretation of prior_weight as equivalent sample size. Expose in the roxygen docs: "Set prior_weight = 2 for minimal shrinkage (large reference databases with many sequences per species) or prior_weight = 50 for aggressive shrinkage (sparse reference databases)."

### Decision: Shrinkage applied to variance as well as mean

**Assessment: Principled but slightly non-standard.**

At `train.R:490`:
```r
shrunk_sigma = sqrt(w * species_var + (1 - w) * global_var)
```

This shrinks the species-specific variance toward the global variance, which prevents extreme variance estimates from species with very few sequences. The linear combination of variances (not SDs) is the correct operation; the outer `sqrt` converts back to SD for storage.

**However:** The standard Empirical Bayes treatment of variances uses a different shrinkage formula (typically inverse-chi-squared prior). The linear combination used here is an approximation that works well in practice but is not the theoretically optimal estimator. Given the data sizes involved (typically 3-20 observations per species), the practical difference is negligible.

**Recommendation:** Add comment: "Variance shrinkage via linear combination is an approximation to the inverse-chi-squared posterior. Adequate for typical barcode reference sizes."

### Decision: Optional lme4 random intercepts for hierarchical estimation

**Assessment: Well-grounded — superior to flat EB when data support it.**

`train.R:446-468` fits `lme4::lmer()` with random intercepts per taxonomic rank above species. This borrows strength across the taxonomic hierarchy (e.g., a genus-level mean informed by all species in that genus). Falls back gracefully to the global mean when lme4 fails to converge.

**This is the recommended approach** for large reference databases with multiple genera and families. The `bobyqa` optimizer is a good choice for convergence.

**No change needed.**

---

## 3. H2/H3 Hypothesis Construction

### Decision: H2 delta = observed foreign-match offset (default 3.0 logit units)

**Assessment: Data-driven default, well-designed.**

At `train.R:509-523`, the H2 delta is estimated from the actual foreign-match distribution in the training data:
```r
h2_delta_val <- max(0.5, mu_score_global - mean(h2_scores))
```

The default of 3.0 is only used when insufficient foreign-match data exists. When data is available, the delta is empirically estimated. This is correct: the offset should reflect the actual separation between within-species and between-species score distributions in the specific reference database.

**The `max(0.5, ...)` floor** prevents H2 from overlapping with H1, which is principled: by definition, a missing species should score lower than a matching species.

**Recommendation:** Add comment: "3.0 logit units ≈ 95% vs 50% on the probability scale — a reasonable default for typical barcode markers (COI, 12S). Marker-specific tuning is handled automatically when sufficient foreign-match data exists."

### Decision: H3 delta = H2 delta + 2.0

**Assessment: Ad hoc but reasonable.**

The +2.0 increment has no formal derivation. It represents the intuition that a missing-genus taxon should score lower than a missing-species taxon by roughly one additional taxonomic rank step.

**Tradeoff:** In practice, the H3 hypothesis is rarely the winner. It serves as a "catch-all" for truly novel diversity. Making it too close to H2 would make H2 and H3 difficult to distinguish; making it too far would make H3 irrelevant.

**Recommendation:** Add comment: "The +2.0 increment is a heuristic representing one additional taxonomic rank step. Users can inspect H3 delta via `interpret_model()` and assess whether it is appropriate for their marker."

**Alternative (for future consideration):** Estimate H3 delta from the training data by computing the mean score when species are matched against a different genus. This would make H3 empirically calibrated like H2. Implementation would require tracking genus-level vs family-level foreign matches separately in `.prep_training_data()`. Low priority — H3 is a minor contributor in most analyses.

### Decision: H2/H3 sigma matrices are 2x2 with diagonal structure

**Assessment: Principled simplification.**

`train.R:520-521`:
```r
h2_sigma_mat <- matrix(c(h2_var, 0, 0, 1.0), ncol = 2L)
```

The off-diagonal is zero (no score-gap correlation for foreign matches), and the gap variance is fixed at 1.0. This is appropriate: for a non-matching species, the gap is essentially random (driven by whichever other species happens to be the best match), so assuming unit variance and zero correlation is defensible.

**No change needed.**

---

## 4. Pseudo-Data Anchoring

### Decision: Inject synthetic perfect-match observations into H1 training data

**Assessment: Well-motivated, but the execution has a minor statistical concern.**

**The problem it solves:** Without anchoring, the H1 MVN mean sits at the training mean (e.g., logit(0.985)). A perfect 100% match falls in the upper tail of the distribution and receives a *lower* likelihood than a 98.5% match. This "perfection penalty" is a real artifact of the MVN assumption when the true distribution is right-skewed on the logit scale.

**The solution:** Inject anchor points at logit(1-ε) with gap at the 95th percentile of observed positive gaps. This shifts the H1 mean upward and widens the covariance, eliminating the penalty.

**Statistical concern:** Anchor points are treated as real observations in the global mean and covariance calculation. At 10% of the data, they influence the global estimates. This is intentional (the whole point is to shift the mean), but it means the global covariance is slightly inflated. In practice, the inflation is modest because the anchors are placed at the theoretical boundary, not at an extreme outlier position.

**The anchor count formula** (`max(5, 10% of data)`) is adequate:
- The minimum of 5 prevents anchoring from being negligible for small datasets.
- 10% is a moderate fraction — enough to shift the mean but not enough to dominate.

**Recommendation:** Add comment: "Anchoring is a form of informative pseudo-data, analogous to Bayesian prior pseudo-counts. The 10% fraction is chosen to nudge the global mean by ~0.5 logit units without overwhelming real data. For markers with very few reference sequences (<50 total), anchoring has a larger relative effect; inspect `interpret_model()` output to verify the anchor did not distort the H1 landscape."

**No change to code needed.** The feature is well-designed and already exposed via the `anchor_perfect` parameter.

---

## 5. Monte Carlo Simulation

### Decision: Score perturbation via N(score_logit, model_sd_score)

**Assessment: Principled but simplified.**

In `evaluate.R:244-253`, MC simulation perturbs scores by sampling from a Normal distribution centered at the observed logit score with SD equal to the global model SD. This propagates measurement uncertainty through the likelihood calculation.

**Simplification:** The SD used is the global model SD (`sqrt(global_sigma[1,1])`), not the species-specific SD. This is computationally convenient but slightly underestimates uncertainty for high-variance species and overestimates it for low-variance species.

**Practical impact:** MC is primarily used for posterior uncertainty propagation in `compute_posterior()`. The global-vs-species SD choice affects `likelihood_sd` but not `likelihood_point_est`. Since TaxaAssign's Beta prior system provides independent uncertainty propagation, the MC impact is secondary.

**Recommendation:** Add comment at `evaluate.R:247`: "Uses global model SD for computational efficiency. Species-specific SD could be used but adds complexity with minimal impact on posterior uncertainty, which is dominated by prior uncertainty from `prior_alpha`/`prior_beta`."

### Decision: n_sims = 0 default in evaluate_likelihoods(), 1000 in compute_posterior()

**Assessment: Appropriate asymmetry.**

Likelihood MC (`n_sims=0` default in TaxaLikely) is turned off by default because it is computationally expensive and adds relatively little information when the Bayesian pipeline handles uncertainty via Beta priors.

Posterior MC (`n_sims=1000` in TaxaAssign) is on by default because Beta prior uncertainty is genuinely informative — it propagates the uncertainty from prior estimation through to the final assignment.

**No change needed.**

---

## 6. Prior Construction (TaxaExpect)

### Decision: glmmTMB binomial GLMM for theta estimation

**Assessment: Well-grounded — the standard modern approach.**

`train_biodiversity_model()` fits a binomial GLMM (generalized linear mixed model) via glmmTMB. This is the correct model family for presence/absence data at sites. The logit link function maps theta to (-∞, +∞) where linear predictors are appropriate.

**Key structural elements:**
- Fixed effects: habitat + spatial covariates
- Random intercepts: `(1 | taxon_name)` for species-specific baselines
- Random slopes: `(0 + hab_X | taxon_name)` for species-habitat interactions (when data supports them)
- Observation-level: `(1 | taxon_name:grid_id)` for overdispersion

**Strengths:**
- Borrows strength across species via the random intercept structure.
- Habitat-specific random slopes allow species to respond differently to habitats without requiring independent per-species models.
- The tiered system (Tier 1 with random slopes, Tier 2 with random intercepts only) gracefully handles the common case where some species have enough data for random slopes and others do not.

**No change needed.** This is methodologically sound.

### Decision: Habitat random slope screening (min_positive_rows threshold)

**Assessment: Principled model-building strategy.**

`screen_habitat_slopes()` only includes habitat random slopes for habitat levels with sufficient positive observations. This prevents lme4/glmmTMB from fitting degenerate random effects (variance converging to zero or infinity).

**The threshold** (controlled by `min_positive_rows`) is passed through from `train_biodiversity_model()`. This is appropriate — the user should set it based on their data richness.

**No change needed.**

### Decision: Delta-method back-transform for alpha/beta conversion

**Assessment: Well-grounded — standard approximate inference.**

`generate_full_priors()` uses the delta method to convert logit-scale predictions and SEs to probability-scale mean and variance, then moment-matches to Beta(alpha, beta):

```r
m = plogis(eta)        # logit^{-1}
v = se^2 * (m*(1-m))^2 # delta method variance
phi = m*(1-m)/v - 1    # Beta precision
alpha = m * phi
beta = (1-m) * phi
```

This is the textbook approach (Bolker, 2008). The delta method is an approximation that works well when the logit-scale SE is moderate (< ~2). For extreme predictions (theta near 0 or 1), the phi cap prevents degeneracy.

### Decision: Phi cap from taxon:grid_id random effect variance

**Assessment: Excellent — principled and self-calibrating.**

The phi cap is derived from the model's own estimate of grid-level variance:
```r
max_phi = 1 / grid_var
```

This is principled: the model itself quantifies how much site-level noise exists in theta estimates, so the prior cannot claim more precision than the model supports. This eliminates the need for an arbitrary phi cap parameter.

**Recommendation:** Add code comment citing the rationale: "Phi cap from grid-level variance is analogous to a moment-matched upper bound on the Beta concentration parameter, preventing the prior from being more concentrated than the model's own site-level uncertainty allows."

### Decision: Jeffreys prior Beta(0.5, 0.5) fallback

**Assessment: Principled — the standard non-informative prior for Bernoulli parameters.**

When phi ≤ 0 (variance exceeds the Bernoulli maximum) or when N_total is below the threshold, the code falls back to the Jeffreys prior Beta(0.5, 0.5). This is the reference prior for a Bernoulli parameter (Jeffreys, 1946), the most commonly used non-informative Beta prior.

**No change needed.**

### Decision: Singleton mirrors for undetected diversity

**Assessment: Innovative and well-motivated.**

`generate_undetected_diversity()` creates anonymous proxy species mirroring each singleton's location, habitat, and theta. The rationale is sound: singletons indicate the boundary of sampling completeness, and their distribution reveals where undetected diversity is most likely.

**The singleton_ess = 2 default** produces a diffuse Beta prior, which is appropriate: we have minimal information about an undetected species, so the prior should be weak. ESS=2 is the minimum ESS that produces a proper Beta distribution with a unique mode.

**Recommendation:** Add comment: "ESS=2 is the minimum that produces a proper unimodal Beta. Higher values (5-10) concentrate the prior more tightly around the observed singleton theta; use only if you have external evidence that undetected species have similar detectability to observed singletons."

### Decision: Global floor prior Beta(1, N_total - 1)

**Assessment: Well-grounded — the posterior from a uniform prior after observing 0 successes in N trials.**

Beta(1, N) is the posterior of a uniform Beta(1,1) prior updated with 0 successes in N-1 trials (since the convention here uses N_total - 1 as beta). This places the prior mean at 1/N_total, which is the expected theta if an undetected species appeared exactly once across all sampling effort. This is a principled lower bound.

**No change needed.**

---

## 7. LLM Prior Assignment (TaxaAssign)

### Decision: LLM as prior elicitor

**Assessment: Novel and defensible for the stated use case.**

Using an LLM (Claude, GPT, Gemini) as an expert prior elicitor is unconventional but well-motivated: the LLM synthesizes published range maps, habitat associations, and taxonomic knowledge into a prior probability that a given taxon would be found at a given location and habitat. This information is genuinely available in the scientific literature but tedious to compile manually.

**Key statistical considerations:**
1. The LLM output is stochastic — different runs may produce different prior weights. This is acknowledged in the documentation and mitigated by the `information_quality` → `prior_phi` system.
2. LLM priors are on the [0, 1] scale (as probability weights), normalized to sum to 1 within each context group. This is consistent with a Dirichlet allocation.

### Decision: prior_phi = c(high=50, moderate=10, low=3) for Beta concentration

**Assessment: Reasonable defaults with clear interpretation.**

The prior_phi mapping converts the LLM's self-assessed `information_quality` into a Beta concentration parameter. When `information_quality = "high"` and `prior_weight = 0.7`:

```
alpha = 0.7 * 50 = 35
beta  = 0.3 * 50 = 15
Beta(35, 15) has SD = 0.063
```

This means the prior is concentrated within about ±6 percentage points of 70% — tight but not dogmatic. For `low`:

```
alpha = 0.7 * 3 = 2.1
beta  = 0.3 * 3 = 0.9
Beta(2.1, 0.9) has SD = 0.22
```

This is very diffuse — appropriate when the LLM acknowledges limited data.

**The mapping from information_quality to phi has no formal derivation** but is interpretable: phi is the "effective sample size" of prior knowledge. phi=50 means "this prior is worth about 50 observations of data," which is reasonable for a well-studied species in a well-documented region.

**Recommendation:** Add to roxygen: "phi values have the interpretation of 'equivalent data weight.' phi=50 (high) means the prior is as informative as 50 observations; phi=3 (low) means it is as informative as 3 observations. Adjust based on how much you trust the LLM's ecological knowledge for your study system."

### Decision: score_sharpness = 0.1 for score-to-likelihood translation

**Assessment: Ad hoc but with a clear functional role.**

`assign_taxa_llm.R` computes likelihoods as:
```r
exp_scores <- exp(score_sharpness * (agg$score - score_threshold))
```

This is a softmax-like transformation that converts raw match scores into relative likelihoods. The `score_sharpness` parameter controls how strongly score differences translate to likelihood differences:
- `score_sharpness = 0` → uniform likelihoods (scores ignored)
- `score_sharpness = 1` → strong score dominance
- `score_sharpness = 0.1` (default) → mild score influence

**The default of 0.1 is chosen so that the LLM prior, not the score, drives the assignment.** This makes sense for the LLM workflow: the score determines which candidates to consider, but the LLM's ecological assessment determines the prior ranking.

**Recommendation:** Document the interaction explicitly: "In the LLM workflow, likelihoods are a weak function of scores (sharpness=0.1) because the LLM prior provides the main discriminating information. In the Bayesian workflow, TaxaLikely provides properly calibrated likelihoods. The two workflows are intentionally different in how they weight scores vs. priors."

### Decision: Prior weight ranges in LLM prompt (e.g., native + expected = 0.5-1.0)

**Assessment: Expert elicitation guidance — not arbitrary but not formally calibrated.**

The 7 range-status × habitat-fit combinations provide the LLM with guidance on the scale of prior weights. These ranges were developed through iterative testing (Session 45) and represent ecological expert judgment about the relative plausibility of different range/habitat combinations.

**Statistical status:** These are analogous to a calibrated elicitation protocol in formal prior elicitation (O'Hagan et al., 2006). The ranges constrain the LLM's output to ecologically plausible values.

**Concern:** The ranges are hard-coded in the prompt text and not user-adjustable. For different ecosystems or taxonomic groups, the appropriate ranges may differ significantly (e.g., marine vs. freshwater, vertebrates vs. invertebrates).

**Recommendation (Prompt 10):** Expose the prior weight ranges as a parameter (e.g., `prior_weight_guide`) so users can customize them for their study system. Document the default ranges with ecological rationale.

---

## 8. Posterior Computation

### Decision: Posterior ~ Likelihood × Prior with per-sample normalization

**Assessment: Correct application of Bayes' theorem.**

`compute_posterior.R:136-138`:
```r
norm_lik <- normalize_vec(chunk$likelihood_point_est)
raw_post <- norm_lik * chunk$prior_mean
posterior <- normalize_vec(raw_post)
```

This is the standard discrete Bayesian update: P(H_i | data) ∝ P(data | H_i) × P(H_i). The normalization ensures posteriors sum to 1 within each sample.

**No change needed.** This is textbook Bayesian inference.

### Decision: Beta(alpha, beta) sampling for prior uncertainty propagation

**Assessment: Excellent — correctly bounded and well-implemented.**

`compute_posterior.R:150-164` samples priors from Beta(alpha, beta), which is correctly bounded on [0, 1] by construction. This replaced the earlier Normal prior sampling (which could produce negative priors requiring clipping). The Beta distribution is the conjugate prior for the Bernoulli, making this the natural choice for probability parameters.

**No change needed.** This was a significant improvement in Session 47.

### Decision: Normal(mean, sd) sampling for likelihood uncertainty

**Assessment: Adequate approximation.**

Likelihoods are sampled from N(mean, sd) with a floor at 0. On the logit scale, normality is a reasonable approximation for the MVN-derived likelihoods from TaxaLikely. The floor at 0 handles the tail of the Normal that would produce negative likelihoods.

**Minor concern:** For LLM-derived likelihoods (`assign_taxa_llm`), `likelihood_sd = 0`, so no sampling occurs. This is correct — the LLM workflow does not provide likelihood uncertainty. Posterior uncertainty is driven entirely by prior uncertainty via the Beta sampling.

**No change needed.**

### Decision: Confidence score = fraction of simulations won

**Assessment: Well-defined and interpretable.**

`compute_posterior.R:193-195`:
```r
winners <- apply(sim_probs, 2, which.max)
win_counts <- table(factor(winners, levels = 1:n_rows))
confidence_score <- as.numeric(win_counts) / n_sims
```

This is a simulation-based analogue of the "posterior probability of being the best hypothesis." It captures uncertainty that `posterior_mean` averages away: a hypothesis can have a high mean posterior but low confidence score if another hypothesis frequently wins in simulations.

**No change needed.** This is a useful complementary measure.

---

## 9. Consensus Taxonomy Rules

### Decision: LCA among plausible hypotheses

**Assessment: Well-grounded — LCA is the standard conservative consensus method.**

Lowest Common Ancestor is the standard approach in molecular systematics for assigning taxonomy to ambiguous matches (Huson et al., 2007; MEGAN). The implementation walks from finest to coarsest rank and stops at the first rank where all plausible hypotheses agree.

**No change needed.**

### Decision: Cumulative threshold for plausible set selection (default 0.9)

**Assessment: Principled — analogous to a credible interval.**

The cumulative threshold selects the minimum set of hypotheses whose posterior mass reaches 90% of the named-taxon mass. This is directly analogous to a 90% highest posterior density (HPD) interval.

**Recommendation:** Add comment: "cumulative_threshold = 0.9 is analogous to a 90% credible interval. Increase toward 0.95-0.99 for more conservative assignments (more upranking to genus/family); decrease to 0.8 for more aggressive species-level calls."

### Decision: min_posterior = 0.05 exclusion threshold

**Assessment: Principled — prevents noise hypotheses from influencing LCA.**

Hypotheses with posterior < 5% are excluded before cumulative threshold selection. Without this filter, a long tail of near-zero hypotheses could force the LCA to an unnecessarily coarse rank.

**Recommendation:** Document interaction: "min_posterior and cumulative_threshold interact: min_posterior removes obvious noise first, then cumulative_threshold selects the plausible set from the remainder. Setting min_posterior = 0 disables noise filtering; setting it too high (e.g., 0.3) may exclude genuine competing hypotheses."

### Decision: consensus_posterior computed over all named hypotheses (pre-filter)

**Assessment: Correct — independent of threshold settings.**

`posterior_consensus.R:340-350` computes consensus_posterior using `named_all` (before min_posterior and cumulative_threshold filtering). This ensures the reported consensus posterior is a genuine probability, not inflated by the filtering step. This is the right design: the consensus posterior should reflect how much probability mass the consensus taxon actually has, regardless of how the plausible set was selected.

**No change needed.**

### Decision: Downranking via species_reference

**Assessment: Sound heuristic with conservative behavior.**

`.downrank_consensus()` downgrades a genus-level LCA to species when the reference contains exactly one species in that genus. This is conservative: it only downranks when the evidence is unambiguous. The recursive walk (family → genus → species) handles multi-level downranking correctly.

**No change needed.**

---

## 10. Empirical Bayes Update from Consensus

### Decision: presence_multiplier for confirmed species in unresolved samples

**Assessment: Ad hoc but well-motivated empirical Bayes.**

`update_prior_from_consensus()` multiplies `prior_mean` by `presence_multiplier` (default 5) for species confirmed in resolved samples. This is a form of empirical Bayes: site-level presence evidence from resolved samples informs the priors for unresolved samples at the same site.

**Statistical status:** This is a one-pass approximation to a full hierarchical model where species presence at a site is shared across samples. A full model would jointly estimate posteriors for all samples, but this is computationally expensive and the one-pass approximation is adequate.

**The default of 5 is ad hoc** but interpretable: a confirmed species gets 5× the prior weight, which is a moderate boost. After normalization, this means a confirmed species that started at 10% prior would move to roughly 33% (10×5 / (10×5 + 90×1)).

**Recommendation:** Add comment: "presence_multiplier = 5 is a moderate boost. Increase to 10-20 for datasets where species identity is highly consistent within a site (e.g., eDNA from a single water body). Decrease to 2 for datasets with high spatial heterogeneity within the site."

**Alternative (for future consideration):** A formally correct approach would be to fit a Beta-Binomial hierarchical model over species × sample within a site, then use the posterior as the updated prior. This preserves the correct uncertainty propagation but is significantly more complex. Low priority — the multiplier approach works well in practice.

---

## 11. Reference QC (Mislabel Detection)

### Decision: Integrity gap = median_self - max_foreign

**Assessment: Sound heuristic.**

`flag_reference_errors()` uses the difference between a sequence's median within-species match and its best cross-species match to detect mislabeling. This is a standard approach in reference database QC (e.g., Kozlov et al., 2016 for phylogenetic placement).

**mislabel_threshold = 0.02 (2 percentage points):**
This is a conservative threshold — a sequence must match foreign species better than its own species by at least 2% to be flagged. This minimizes false positives (correct sequences with anomalously high foreign matches due to genuine taxonomic similarity).

### Decision: Singleton high-match threshold = 0.98

**Assessment: Reasonable heuristic.**

Singletons (no within-species neighbors) are flagged as `"unverified_singleton_high_match"` when their best foreign match exceeds 98%. The 98% threshold is conventional for barcode-level species-level identity.

**Recommendation:** Add comment: "98% identity is the conventional barcode gap threshold for many markers. For ITS (fungi) where within-species variation is higher, consider raising to 99%."

---

## 12. Score Normalization

### Decision: Auto-detection of 0-100 vs 0-1 scale

**Assessment: Practical and robust.**

`.normalize_scores()` checks `max(x) > 1` to decide the input scale. This handles the two most common cases (percent identity 0-100, fractional similarity 0-1) without requiring user input.

**Edge case:** A dataset with all scores in (0, 1) but on a 0-100 scale (e.g., all matches <1%) would be misdetected as 0-1. This is extremely unlikely in practice.

**No change needed.** The `bounds` parameter exists as an escape hatch.

### Decision: Logit epsilon = 1e-4 (training), 1e-6 (normalization)

**Assessment: Principled — prevents logit singularities.**

Two different epsilons serve different purposes:
- `logit_epsilon = 1e-4` in training clips at a wider margin, preventing extreme logit values from dominating model estimation.
- `epsilon = 1e-6` in `.normalize_scores()` clips at a tighter margin, preserving more dynamic range for inference.

The asymmetry is intentional: training benefits from robustness, while inference benefits from precision.

**Recommendation:** Add comment explaining the different scales: "Training uses 1e-4 for robustness; inference uses 1e-6 for precision."

---

## 13. Summary and Recommendations

### Decisions Requiring No Change (Well-Grounded)

| Decision | Location | Basis |
|---|---|---|
| MVN over (score_logit, gap_logit) | TaxaLikely evaluate.R | Standard multivariate density; logit is canonical VST for proportions |
| 1D Normal fallback for singletons | TaxaLikely evaluate.R | Gap is artificial when no competition exists |
| Median per taxon before evaluation | TaxaLikely evaluate.R | Robust to outlier accessions and sample-size bias |
| EB shrinkage w = N/(N+prior_weight) | TaxaLikely train.R | James-Stein / Efron-Morris (1973) |
| lme4 random intercepts | TaxaLikely train.R | Standard hierarchical borrowing of strength |
| Data-driven H2 delta estimation | TaxaLikely train.R | Empirically calibrated from foreign-match distribution |
| Posterior = Likelihood × Prior | TaxaAssign compute_posterior.R | Bayes' theorem |
| Beta(alpha, beta) prior sampling | TaxaAssign compute_posterior.R | Conjugate, correctly bounded on [0,1] |
| LCA consensus | TaxaAssign posterior_consensus.R | Standard in molecular systematics (Huson et al., 2007) |
| glmmTMB binomial GLMM | TaxaExpect train_biodiversity_model.R | Standard for presence/absence with covariates |
| Delta-method alpha/beta conversion | TaxaExpect generate_full_priors.R | Standard approximate inference |
| Phi cap from grid variance | TaxaExpect generate_full_priors.R | Self-calibrating; prevents degeneracy |
| Jeffreys prior fallback | TaxaExpect generate_full_priors.R | Standard non-informative prior |
| Beta(1, N-1) global floor | TaxaExpect generate_undetected_diversity.R | Posterior from uniform prior with 0 successes |

### Decisions Requiring Documentation Only

| Decision | Location | Action |
|---|---|---|
| prior_weight = 10.0 | TaxaLikely train.R | Add code comment citing Efron-Morris; document as equivalent sample size |
| H3 delta = H2 + 2.0 | TaxaLikely train.R | Document as rank-step heuristic |
| Anchor fraction 10%, min 5 | TaxaLikely train.R | Document as pseudo-count analogy |
| Variance shrinkage (linear combo) | TaxaLikely train.R | Note it is an approximation to inverse-chi-squared posterior |
| MC uses global SD | TaxaLikely evaluate.R | Document as computational simplification |
| score_sharpness = 0.1 | TaxaAssign assign_taxa_llm.R | Document intentional weakness; contrast with Bayesian workflow |
| prior_phi = c(50, 10, 3) | TaxaAssign assign_taxa_llm.R | Document phi as equivalent sample size |
| cumulative_threshold = 0.9 | TaxaAssign posterior_consensus.R | Document as credible interval analogy |
| min_posterior = 0.05 | TaxaAssign posterior_consensus.R | Document interaction with cumulative_threshold |
| presence_multiplier = 5 | TaxaAssign update_prior_from_consensus.R | Document as moderate empirical Bayes boost |
| singleton_ess = 2 | TaxaExpect generate_undetected_diversity.R | Document as minimum proper unimodal Beta |
| mislabel_threshold = 0.02 | TaxaLikely train.R | Document as conservative QC threshold |
| singleton high-match = 0.98 | TaxaLikely train.R | Document as conventional barcode threshold |

### Decisions Where an Alternative Should Be Noted

| Decision | Location | Alternative | Priority |
|---|---|---|---|
| MVN density (elliptical contours) | TaxaLikely evaluate.R | KDE for non-elliptical distributions | Low — add diagnostic to interpret_model() |
| LLM prior weight ranges (hard-coded) | TaxaAssign assign_taxa_llm.R | Expose as `prior_weight_guide` parameter | **Medium** — do in Prompt 10 |
| H3 delta from heuristic | TaxaLikely train.R | Estimate from genus-level foreign-match data | Low — H3 rarely decisive |
| One-pass EB update | TaxaAssign update_prior_from_consensus.R | Full hierarchical model across samples | Low — one-pass adequate in practice |

### References

- Bolker, B.M. (2008). Ecological Models and Data in R. Princeton University Press.
- Efron, B. & Morris, C. (1973). Stein's estimation rule and its competitors. JASA 68(341):117-130.
- Huson, D.H. et al. (2007). MEGAN analysis of metagenomic data. Genome Res. 17(3):377-386.
- Jeffreys, H. (1946). An invariant form for the prior probability in estimation problems. Proc. Royal Soc. A 186:453-461.
- Koski, L.B. & Golding, G.B. (2001). The closest BLAST hit is often not the nearest neighbor. J Mol Evol 52:540-542.
- Kozlov, A.M. et al. (2016). Phylogeny-aware identification and correction of taxonomically mislabeled sequences. Nucleic Acids Res 44(11):5022-5033.
- O'Hagan, A. et al. (2006). Uncertain Judgements: Eliciting Experts' Probabilities. Wiley.
- Warton, D.I. & Hui, F.K.C. (2011). The arcsine is asinine: the analysis of proportions in ecology. Ecology 92(1):3-10.
