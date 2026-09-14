# Re-entry prompt — Should `train_likelihood_model()` floor alignment coverage on the FOREIGN side of the H1 gap?

**Written 2026-09-10 (Fable 5.1), after the first full GreatLakes run on the rewired
reference screen.** Status: **RESOLVED the same day — built, validated, default-on.**

## Resolution (2026-09-10, later)

User decision: the floor is a requirement, not an opt-in, and its value is the match
object's own floor (`blast_sequences(min_query_coverage = 80)`, now recorded in the
match object's `report_params`; `evaluate_likelihoods()` checks the two agree). For the
gap, the user preferred data-driven shrinkage over globalising: the per-species gap
means are now shrunk with an estimated between-species variance (`shrinkage =
"empirical_bayes"`), which on this data gives `tau/sigma` = 0.00 for score (collapses
to global) and 0.50 for gap (real signal kept, weights 0.34–0.72). Model D below is
withdrawn: it discarded that signal. Shrinkage cannot produce absurd values (a
weighted average of two finite means); the extrapolation risk belongs to the affine
remap in `calibrate_query_noise()`, which touches score only.

Validated on the REAL workflow's code path, not the fastpath: `REVIEW_coverage_floor_
arms.R` (GreatLakes data dir) executes `GreatLakes2023_ConsensusWorkflow.R`'s own
lines 7b.5 → 8h against the 2026-09-10 checkpoints, `.save()` redirected, one arm per
model; the control arm reproduced production `consensus_final` in 884/885 observations.
Priors were identical across arms, so only `lik_model` differed. Lamar scoring
(`REVIEW_lamar_score_arm.R`, species level, matched samples):

| Arm | both | ours-only | precision | recall | species | overconfident |
|---|---|---|---|---|---|---|
| A control (production model) | 593 | 144 | 0.805 | 0.549 | 29/61 | 1/1081 |
| B floor 0.8, fixed shrinkage | 802 | 191 | 0.808 | 0.742 | 42/61 | 0/1081 |
| **C floor 0.8, EB shrinkage (adopted)** | 798 | 177 | **0.818** | 0.738 | 41/61 | 0/1081 |

Species-rank observations 543 → 690; 13 species newly resolved, none lost. Grass carp
back at species rank (5 ASVs; 8 Lamar-supported sample calls). Largest gains, all
Lamar-confirmed: *Lepomis cyanellus* +25, *Ambloplites rupestris* +24, *Micropterus
salmoides* +23, *Notropis stramineus* +21, *Catostomus commersonii* +20. The one new
unsupported species is *Fundulus notatus* (10 sample calls, 0 Lamar); *Notropis
hudsonius* remains the largest ours-only taxon (26). B vs C differ on three taxa only
(*Ameiurus natalis* 2/15 in B, absent in C; *Catostomus commersonii* 24 vs 22).

Not yet done: the same arms at the PtConception sites (no independent ground truth
there; the check is `evaluate_likelihoods()`'s warning plus a species-list diff), and a
full end-to-end GreatLakes run to refresh the report tail.

---

## Original analysis (kept as written)

Every number below is from real GreatLakes 12S data (`GreatLakes2023BurnsHarbor_*.rds`,
run of 2026-09-10; seq_matrix 2.83M pairwise comparisons, 2,750 references, 885 ASVs).
The retrained models used below are NOT saved anywhere durable; they take 2.4 s to
rebuild from the checkpoints with the code in the "How to reproduce" section.

## Why this is a different question from the one archived on 2026-09-09

The archived `calibrate_coverage_filter()`/`coverage_threshold()` pair EXCLUDED every
reference pair below a calibrated coverage (0.995 on PtCon) from ALL of training — the
score dimension, the gap dimension, H1 pairs, congener pairs, everything. That is why it
had the cost the 2026-09-09 note records (species dropping out of training, unresolved
queries) and why it was archived under this ecosystem's "flag, don't exclude" rule. The
pros/cons recalled for it ("better win rate" vs "biases which species get trained") are
correct **for that mechanism**.

This note is about a narrower thing: **which pair is allowed to define a reference's
"best foreign match"** when training the gap feature. No H1 pair is excluded, no species
loses its parameters, nothing is dropped from the score dimension. The argument is
train/inference distribution matching, not data quality.

## The defect, in one paragraph

`train.R` STEP 3 sets each reference's `max_foreign_score` to the best `p_match` over
ALL cross-species pairs, with no coverage condition. On real data 86% of references get
a `p_match = 1.0` foreign "best match" whose alignment covers a median **4.6%** of the
sequence (*Ctenopharyngodon idella* vs *Argyrosomus inodorus*, a marine drum;
*Hypophthalmichthys nobilis* vs *Menidia menidia*). So 89% of references train with
`raw_gap <= 0` — the model learns that the true species is normally *beaten or tied* by
a foreign reference. The global expected gap is −0.010 (sqrt-mismatch scale) and every
per-species `mu_gap` is negative. At inference the gap is computed among BLAST candidates
whose `query_coverage` is **never below 80** (min 80.1, median 100), so a query can
never produce the kind of gap the model was trained on. A perfect 100% match with a real
+3% gap over the next genus is therefore "atypical" and marked down; a 96.4% match with a
−3.6% gap is "typical" and marked up. That is exactly how grass carp (100% to 6 *C.
idella* references) lost to bighead carp (96.4%) on this run: H1 likelihood 0.77 vs
0.95, then equal priors, then a family-rank consensus. Hand-computed Mahalanobis
distances confirm the gap dimension, not the score dimension, is what inverts them.

## The models compared

| Model | Training change | What it tests |
|---|---|---|
| **A** | none (production `lik_model.rds`) | baseline |
| **B** | cross-species pairs must have `coverage >= 0.8` before they can be a reference's `max_foreign_score`; same-species pairs untouched | the foreign-side floor alone |
| **C** | `coverage >= 0.8` on ALL pairs (the archived mechanism's shape, at a milder threshold) | what exclusion costs |
| **D** | B, plus per-species `mu_gap` replaced by the global mean (per-species `mu_score` kept) | B + the deferred `mu_gap` overfitting concern |
| **E** | A, plus per-species `mu_gap` replaced by the global mean | is the per-species gap the culprit on its own? |

0.8 is not tuned: it is the inference-side minimum `query_coverage` the match object
actually carries (80.1). Any floor at or below that value is defensible on the same
grounds; anything above it is a tuning choice.

## What each model does to training

| | A | B | C | D |
|---|---|---|---|---|
| species with H1 params | 402 | **402** | 386 (−16) | 402 |
| singletons (global params) | 363 | 360 | 421 | 360 |
| references losing every pair | 0 | 3 | 3 | 3 |
| global `mu_gap` | −0.010 | +0.122 | +0.120 | +0.122 |
| references with `raw_gap <= 0` | 89% | 22% | 22% | 22% |
| H2 (congener) global delta | 0.085 | 0.098 | 0.097 | 0.098 |

C loses 16 species' parameters (*Notropis topeka*, *Fundulus notatus*, *Percina rex*,
…), which is the archived mechanism's known cost. B and D lose none: the only pairs
that stop mattering are cross-species pairs at <80% overlap, which no query can
produce. The three references that lose all pairs had nothing but short-overlap foreign
pairs and were global-parameter singletons already.

## What each model does at inference (all 885 ASVs, uncalibrated, priors not applied)

"Near-tie" = top H1 candidate's likelihood within 1.5× of the runner-up. "Agrees with
best hit" = the top H1 candidate is the species of the single best-scoring BLAST
accession; the second column restricts to ASVs with a unique best hit at >= 99.5%
identity, where the H1 model has no honest reason to disagree with BLAST.

| | A | B | C | D | E |
|---|---|---|---|---|---|
| near-ties | **728**/885 | 295 | 296 | 308 | 734 |
| median top/second ratio | 1.05 | 2.02 | — | 2.29 | 1.07 |
| agrees with best hit | 493/885 | 637 | — | **714** | 493 |
| … among unique best >= 99.5% | 178/326 | 244 | — | **269** | 178 |
| top H1 candidate changes vs A | — | 322 | 324 | 294 | 187 |

Read: under production, the H1 likelihood is a near-tie on 82% of observations, so the
prior decides almost everything — which is why an uncached habitat verdict flipping one
species' prior could move 56 consensus calls on this run. E shows the per-species gap
alone is not the cause (734 near-ties, same agreement). B/D fix it; D is the most
consistent with BLAST.

Where A→D changes the top candidate (top pairs): *Ictalurus furcatus*→*I. punctatus* 46,
*Perca* (genus-only reference name)→*Perca flavescens* 41, *Catostomus fumeiventris*→
*C. commersonii* 33, *Micropterus treculii*→*M. dolomieu* 13, *Ictalurus punctatus*→
*Pylodictis olivaris* 11, *Etheostoma vitreum*→*E. nigrum* 8, *Ictiobus niger*→*I.
bubalus* 8. Mostly the regionally plausible congener replacing a Texan/Californian/Gulf
one, but *Pylodictis* (flathead catfish) replacing channel catfish on 11 ASVs is worth a
look, not an assumption.

Spot checks:

| ASV | A | B | D |
|---|---|---|---|
| grass carp P1_ASV_0392 | *C. idella* > *Opsariichthys* (1.00) | *C. idella* (18×) | *C. idella* (18×) |
| *Notropis stramineus* P1_ASV_0098 | > *N. topeka* (1.04) | 5.3× | 4.6× |
| alewife P1_ASV_0417 (99.5% alewife, 99.0% blueback) | alewife (1.04) | **blueback** (1.10) | alewife (1.70) |

The alewife row is why D exists: under B, *A. pseudoharengus*'s per-species `mu_gap`
(0.19, from n = 10 references) is large, so a real query that is only 0.5% clear of
blueback looks "atypical" for alewife and blueback wins with a lower score. The
per-species gap spread across species (sd 0.029) is a quarter of the gap noise sd
(0.125), so per-species gap means carry little signal and n = 2–10 estimates of them add
noise — the [[project_h1_mu_gap_overfitting_concern]] memory, now with a number on it.

## What this does NOT establish

- Nothing here went through priors, `calibrate_query_noise()`, the consensus update, or
  `posterior_consensus()`. The only validation that counts is a full run scored against
  Lamar (`REVIEW_formal_lamar_check.R`) with the habitat cache in place, so the prior
  side is held fixed while the likelihood side changes.
- "Agrees with best hit" is a yardstick, not truth. A best hit can be a mislabel; the
  point of H1 is to disagree with BLAST when the reference structure says to. But 45%
  disagreement on clean unique >= 99.5% hits (A) is not that; D's 17% is a more
  plausible rate.
- The same-species side is also touched by short overlaps: 8.5% of references' best
  conspecific pair has coverage < 0.8, and 20% of best-congener pairs (H2's delta).
  Neither was changed in B/D. A consistent design would apply the same
  inference-side floor when *selecting* the best conspecific / best congener pair,
  falling back to the unfiltered best only when no qualifying pair exists (so no
  species is ever dropped). Not measured.

## The decision, as I would frame it

- **Do nothing**: the H1 likelihood stays nearly non-discriminating (82% near-ties) and
  the published list stays a function of the prior, which the habitat cache now makes
  stable but not more right. Grass carp stays lost whenever a congener shares its prior.
- **B or D as a `train_likelihood_model()` parameter** (`foreign_min_coverage = NULL`
  default, workflows pass the match object's own minimum, 0.8): no exclusion, no
  species dropped, additive, reversible per run. D additionally needs a
  `gap_shrinkage`/`global_gap = TRUE` switch (or shrinkage of per-species `mu_gap` toward
  the global mean weighted by n, the same shape as H2's `delta_shrunk`).
- **Validate** with one full GreatLakes run per arm against Lamar (precision 0.853 was
  the pre-drift benchmark; 0.805 is where the drift left it). If D wins, flip the
  default and record it in NAME_CHANGE_HISTORY as a behaviour change.

## How to reproduce (2.4 s per retrain, ~60 s per full-dataset evaluation)

```r
P  <- "GreatLakes2023BurnsHarbor_"
sm <- readRDS(paste0(P, "seq_matrix.rds")); re <- readRDS(paste0(P, "ref_eval.rds"))
bad <- re$accession[re$reference_action == "remove"]
smc <- dplyr::filter(sm, !id_x %in% bad, !id_y %in% bad)
smB <- dplyr::filter(smc, species.x == species.y | coverage >= 0.8)          # model B
lmB <- TaxaLikely::train_likelihood_model(smB, rank_system = c("family","genus","species"),
                                          prior_weight = 10, score_transform = "sqrt_mismatch")
lmD <- lmB; lmD$H1_Lookup$mu_gap <- lmB$H1_Global_Mu[["gap_logit"]]          # model D
mo  <- readRDS(paste0(P, "match_obj_restored.rds"))
lik <- TaxaLikely::evaluate_likelihoods(mo, lmD, rank_system = c("family","genus","species"),
                                        n_sims = 20L, ratio_threshold = 0)
```

Related: `TaxaLikely/CLAUDE.md` 2026-09-09 (the archival note this does not reopen),
[[project_train_inference_scale_validity]], [[project_quality_covariate_deferred]],
`REENTRY_PROMPT_post_reference_screen_full_workflow_runs.md` (the run that surfaced it).
