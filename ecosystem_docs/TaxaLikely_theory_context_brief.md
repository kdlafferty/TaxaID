# Context Brief for Opus: TaxaLikely Likelihood Framework — Theory Write-Up
# Copy this entire file into a new Claude Opus chat to begin the write-up session.

---

## Who I am and what we are writing

I am an ecologist developing a Bayesian pipeline for taxonomic identification from
eDNA and other biological survey data. The pipeline is implemented as a suite of R
packages called TaxaID. The package TaxaLikely converts raw match scores (BLAST
percent identity, image similarity scores, acoustic classifier scores) into
per-hypothesis likelihoods for downstream Bayesian assignment.

I need you to write a supplemental methods document — a self-contained theoretical
treatment — for the likelihood framework used in TaxaLikely. The target file is:

  /Users/lafferty/My Drive/Rscripts/projects/TaxaID/TaxaLikely/inst/TaxaLikely_supplemental_methods.md

This file already exists with 10 sections covering the generative Bayesian framework,
feature engineering, hypotheses, anchoring, and visualization. Your task is to write
a NEW section (or sections) covering the theory laid out below. Write in academic
methods-paper style: precise, mathematical where needed, but accessible to an
ecologist who is not a statistician. Use inline LaTeX-style notation for equations.
Cite real literature where indicated.

---

## The confirmed framework (do not re-derive — use these conclusions)

After extensive diagnostic work on real reference databases (12S MiFish and 18S
PtConception, California), the following has been established empirically:

### Framing B confirmed: continuous bivariate-normal

The within-species pairwise score distribution (from seq_matrix) was examined for
both markers. The "spike ratio" (count at p_match == 1.0 divided by count in the
[0.995, 1.0) bin) was 0.30–0.40 for both markers — well below the threshold of ~5
that would indicate a discrete point mass at 1.0. **Conclusion: no point mass exists
at exact match. The distribution is smooth and continuous. A unified continuous
bivariate-normal model (Framing B) is the correct representation.**

### Key empirical values from seq_matrix (wild marine taxa, after cleaning)

**12S MiFish (Bovidae/Canidae/Suidae removed):**
- p_self = P(exact match | within-species) = 0.048
- p_cross_congeneric = P(exact match | congeneric) = 0.078
- LR(H1 vs congeneric) at 100% rule = p_self / p_cross = 0.61
- Within-species median p_match = 0.992
- 31 of 34 species have p_self = 0 (never achieve exact self-match in reference)

**18S (blank-name filtered, thinned to 20 pairs/species):**
- p_self = 0.080
- p_cross_congeneric = 0.291 (29.1% of congeneric pairs score exactly 1.0!)
- LR(H1 vs congeneric) at 100% rule = 0.27
- Within-species median p_match = 0.990 (after removing blank-name artifacts)
- 181 of 210 species have p_self = 0

**Critical conclusion:** For both markers, LR(H1 vs congeneric) at the 100% rule < 1.
A 100% BLAST hit is more consistent with a congeneric hypothesis than a conspecific
hypothesis at these markers. The 100% rule cannot reliably discriminate species from
congeners. All species-level information is in the continuous score distribution,
not in a binary 100% threshold.

### anchor_perfect is justified

`train_likelihood_model()` injects synthetic (score=1.0, gap=0) observations
("anchor_perfect") to prevent the continuous bivariate model from treating rare exact
matches as anomalous. This is now theoretically justified: p_self is low (~5–8%) but
non-zero; without anchoring, the model would assign near-zero density at (1.0, 0.0),
penalizing real exact matches. The anchor correctly regularizes the boundary.

---

## The five topics to cover

### 1. The calibration problem (cite Wood & Kahl 2024; Knight et al. 2017)

Match scores — whether BLAST percent identity or BirdNET confidence scores — are
unitless quantities that resemble probabilities but are not. Wood & Kahl (2024,
Journal of Ornithology) make this point for BirdNET: "BirdNET confidence scores are
not probabilities." Knight et al. (2017, Avian Conservation and Ecology) make the
same point for acoustic recognizers generally. The same principle applies to BLAST
percent identity: a score of 98% is not a 98% probability that the match is correct.

In a multi-hypothesis discrimination setting (which species is this?), raw scores
must be converted to likelihoods — the probability of observing this score *given*
each taxon hypothesis. This requires a generative model of the score distribution
under each hypothesis. Wood & Kahl (2024) use logistic regression on a
binary (correct/incorrect) outcome. Our approach generalizes this to multiple
competing hypotheses and a bivariate (score, gap) feature space.

### 2. The open-reference problem

A reference database is almost never complete. Some species in the study area have
no reference sequences; their presence cannot produce a high-scoring match to their
own species. The closure parameter φ = N_referenced / N_total (where N is the
number of species relevant to a given observation) quantifies this incompleteness.

**Key point: φ belongs in the prior, not the likelihood.**

The likelihood is conditioned on the score observed. Whether an unreferenced
alternative exists does not change the probability of observing a given score under
any of the stated hypotheses. φ enters through the prior: an unreferenced species
can only be "detected" indirectly through dark diversity modeling (TaxaExpect),
which provides its prior probability of presence. This is analogous to imperfect
detection in occupancy models — the probability a species is present given it was
not detected depends on detection probability (prior/occupancy), not on the
detection score itself.

Three hypothesis types in TaxaLikely:
- H1: the match is to the correct referenced species
- H2: the true species is unreferenced, at genus level (no match possible)
- H3: the true species is unreferenced, at family level

### 3. Truncation and censoring in match reporting

Match-reporting pipelines vary. Common truncation rules include:
- **All-above-floor**: retain all matches with score ≥ T (e.g., ≥ 90%)
- **100%-only**: retain only exact matches (score = 100%)
- **Max-score-only**: retain only the single best match per query
- **Gap-within-threshold**: retain all matches within δ% of the best match

Each rule creates a selection effect. The naive likelihood ignores this: if only
retained matches are observed, the likelihood must be corrected for the probability
that a match *would* be retained at all under each hypothesis.

**General truncation correction:**

Let R denote the set of (score, gap) values that pass the retention rule. The
corrected likelihood for a retained observation at (s, g) is:

  L(H | s, g, retained) ∝ f_H(s, g) / P(retained | H)

where P(retained | H) = ∫∫_R f_H(s', g') ds' dg'.

The truncation correction P(retained | H) does NOT cancel between H1 and H2/H3
because the within-species distribution (f_H1) and the cross-species distribution
(f_H2, f_H3) have different shapes and means. Ignoring the correction when applying
a floor T gives biased likelihoods whenever F_H1(T) ≠ F_cross(T), i.e., whenever
some within-species matches fall below the floor.

Special cases:
- **All-above-floor at T ≤ min_self**: if every within-species match exceeds T, then
  P(retained | H1) = 1.0 and no correction is needed for H1. The correction still
  applies to H2/H3 (cross-species matches may fail the floor more often).
- **Max-score-only**: the correction for H1 is P(best score = s* | H1) — the
  probability that the observed score is both the best AND equals s*. The gap
  dimension becomes degenerate (uninformative) in this case.
- **100%-only**: a special case of max-score-only at s* = 1.0. As shown empirically,
  the correction for H1 is P(exact match | H1) = p_self and for H2 it is p_cross.
  Since p_cross_congeneric > p_self for both 12S and 18S, the 100% rule does not
  favor H1 over congeneric H2 for these markers.

### 4. The bivariate-normal as the unifying model

The bivariate-normal model over (logit(score), logit(gap)) provides a single
framework that handles all truncation cases through the corrected likelihood above.
No special-case rules are needed.

**H1 distribution:** species-specific bivariate normal with Empirical Bayes shrinkage
toward the global mean. Species with few reference sequences shrink toward the
pooled estimate. This is equivalent to the species-specific performance evaluation
recommended by Wood & Kahl (2024) and Knight et al. (2017), implemented
hierarchically rather than requiring separate manual validation per species.

**H2/H3 distributions:** shifted means (H2$delta, H3$delta) reflecting that
cross-species scores are systematically lower and gaps are larger.

**anchor_perfect regularization:** synthetic (1.0, 0.0) observations are injected
during training to regularize the model at the boundary. This is necessary because
p_self — the probability of an exact within-species match — is typically low
(4–8% for 12S and 18S MiFish/rDNA markers in temperate marine fish communities)
but non-zero. Without anchoring, the continuous model assigns near-zero density at
(1.0, 0.0), incorrectly penalizing the rare genuine exact matches.

**Marker specificity:** the bivariate-normal parameters are marker-specific and
should be estimated from a clean seq_matrix for each marker. The diagnostic in
`diagnostics/seq_matrix_score_distribution.R` computes the key properties
(p_self, p_cross_congeneric, spike ratio, LR at 100%) needed to verify that the
model is appropriate before use.

### 5. Reference database requirements for model estimation

The bivariate-normal model is estimated from a reference sequence matrix (seq_matrix)
that pairs all sequences within a distance threshold. Three cleaning steps are
required before estimation:

1. **Error correction** (`flag_reference_errors()`): mislabeled sequences create
   false within-species pairs (cross-species pairs masquerading as within-species).
   These inflate p_cross and deflate p_self, biasing the LR toward H2.

2. **Blank-name filtering** (`filter_unnamed = TRUE` in `build_sequence_matrix()`):
   sequences with no species-level identification produce spurious within-species
   pairs (blank == blank). In an 18S rDNA database, blank-name pairs accounted for
   69% of apparent within-species pairs before filtering.

3. **Thinning** (`max_seqs_per_taxon` in `build_sequence_matrix()`): heavily-
   sequenced model organisms (domestic livestock, common lab species) can dominate
   the within-species distribution. In a 12S MiFish database, Ovis aries (domestic
   sheep) accounted for 89% of within-species pairs before thinning. A cap of
   ~10–20 sequences per species balances the contribution of each taxon.

These requirements parallel Wood & Kahl's (2024) recommendation that score
performance be evaluated on balanced, species-specific validation sets.

---

## Literature to cite (with context)

- **Wood & Kahl (2024)** — Journal of Ornithology. doi:10.1007/s10336-024-02144-5
  Cite for: (1) scores are unitless, not probabilities; (2) species-specific
  evaluation required; (3) logistic regression as a calibration approach (contrast
  with our bivariate-normal generalization); (4) validation dataset requirements.

- **Knight et al. (2017)** — Avian Conservation and Ecology 12:14
  Cite for: general principles for interpreting automated detector scores;
  species-specific thresholds.

- **Burnham & Anderson (2010)** — Model selection and multimodel inference.
  Springer. (cited by Wood & Kahl; relevant for AIC model selection of the
  bivariate-normal)

- Additional citations to find/add: any standard reference for likelihood-ratio
  methods in species identification (e.g., DNA barcoding literature); occupancy
  modeling literature for the detection-probability analogy (MacKenzie et al.
  2002 is standard).

---

## What already exists in the file

The existing TaxaLikely_supplemental_methods.md has 10 sections covering:
generative Bayesian framework, feature engineering (logit score, logit gap),
H1/H2/H3 hypothesis structure, Empirical Bayes shrinkage, anchor_perfect
pseudo-data, coverage sigma-inflation, visualization. You are adding to this,
not replacing it. The new content should integrate with the existing statistical
design notes without duplicating them.

---

## Tone and format

- Academic methods style, as would appear in a Methods in Ecology and Evolution
  supplemental document
- Mathematical notation inline: use standard probability notation
  (f_H(s,g), P(H|s,g), L(H|s,g)) and define terms on first use
- Accessible to a quantitative ecologist who is not a statistician
- Each section: 2–4 paragraphs with key equations displayed
- Total target length: 1,500–2,500 words for the new sections
- End with a brief "Application" section mapping the theory to TaxaLikely functions:
  build_sequence_matrix → flag_reference_errors → train_likelihood_model →
  evaluate_likelihoods, noting where each theoretical piece is implemented

---

## Output

Please write the complete text of the new section(s) as Markdown, ready to
append to TaxaLikely_supplemental_methods.md. I will review it before saving.
