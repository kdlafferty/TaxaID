# Whole-ecosystem review (Fable, 2026-09-05)

Closes `REENTRY_PROMPT_fable_ecosystem_review.md`. Preconditions as amended by the
user: the critical-fix-review pass is done and was read as a primary source
(`critical_fix_review_and_changelog_2026-09-05.md`); the live PtConception 18S run
was deliberately NOT waited for (mid-`train_likelihood_model()` at review time --
its lack of an evaluated likelihood model is expected state, not a finding, and is
not treated as one anywhere below).

Method: read the reentry doc's named sources plus the primary code for the three
new mechanisms -- `TaxaExpect/R/apply_undetected_evidence.R` (whole),
`TaxaAssign/R/update_prior_from_consensus.R` (whole),
`TaxaAssign/R/compute_posterior.R` (mixture sampler),
`TaxaMatch/R/reference_label_verdict.R` (verdict/action/refinement machinery,
targeted), `TaxaLikely/R/train.R` (training screen block),
`TaxaExpect/R/generate_inat_range_evidence.R`, plus the kernel-budget, mixture,
and reference-quality reentry docs in full, the fast-workflows README, and the
package CLAUDE.md top notes. No package source was edited. Everything numeric
below is either read from those records or derived arithmetically from them (and
labelled as derived where so).

This is a findings document per the project's "propose, confirm, then implement"
discipline. Section A is the urgent/high-confidence/small list; Sections B-E are
the larger observations, ordered by the reentry doc's five focus areas.

---

## A. Urgent / high-confidence / small

These four are flagged separately, per the deliverable spec. Each has a small,
well-bounded fix; none is proposed as an edit here.

### A1. `train_likelihood_model()` still auto-removes references on the screen this ecosystem's own audit demoted -- and the 18S run training right now inherits it

**This is the review's single most consequential finding, and it is not a new
discovery -- it is the ecosystem's own recorded verdict left unexecuted at its
most consequential call site.**

- `TaxaLikely::train_likelihood_model()` (R/train.R, ~line 975) calls
  `flag_reference_errors()` unconditionally on every training run and silently
  drops every `"likely_mislabeled"` accession -- from BOTH sides of the pair
  table (`!id_x %in% bad_ids, !id_y %in% bad_ids`), so a flagged accession also
  stops serving as a partner for clean ones.
- The 2026-08-08 screening-comparison audit measured this screen at ~6.7%
  precision against the BLAST-based screen's verdicts, and a real 40-accession
  live-BLAST pilot confirmed **0 of 40** `"likely_mislabeled"` flags as genuine.
  That audit's own written recommendation: treat `flag_reference_errors()` as
  high-recall/low-precision, "worth a review pass, not an auto-blacklist," with
  `evaluate_reference_accessions()` the recommended screen going forward.
- The bridge to fix this exists and is tested:
  `TaxaMatch::verify_flagged_references()` (2026-08-18) screens ONLY the flagged
  subset and returns a `verified_clean` vector that
  `train_likelihood_model(verified_clean=)` accepts. **It is wired into zero
  production workflows.** Per the project's own memory, the PtCon training path
  drops ~360 references with no `verified_clean` -- and the 18S model being
  trained as this review is written (21,899 references) runs the same
  unconditional screen.

Two aggravating points a package-scoped session would not put together:

1. **This is the last surviving instance of a pattern this ecosystem has
   rejected everywhere else.** `apply_coverage_constraints()` flipped
   `"zero"` -> `"relabel"`; `filter_gbif_quality()` flipped
   `exclude_institution` -> `flag_institution`;
   `remove_incongruent_references()` was demoted to a post-review opt-in with
   three hard vetoes and a pre-removal audit. Training is the one place a
   destructive default from an unreviewed heuristic still acts silently.
2. **The censoring is not statistically neutral -- it is correlated with the
   quantity H2 estimates.** 61% of the screen's measured over-flagging is
   tight-congener false positives: references whose within-species match is
   close to a congener's. Removing exactly those references before fitting
   biases the surviving pair table toward larger apparent congener divergence,
   so the genus-specific H2 deltas (the Session-151 cryptic-complex shrinkage
   machinery) are trained on a sample censored in the anti-conservative
   direction, in precisely the tight genera where congener confusion matters
   most. Magnitude unmeasured -- but note this is a *removal/censoring* effect,
   distinct from the mislabel-*weighting* idea whose ~1% effect estimate closed
   `[[project_mislabel_probability_weighting_closed]]`; that closure does not
   cover this.

**Smallest defensible fix** (a decision, not made here): wire
`verify_flagged_references()` -> `verified_clean` into the production training
calls (the memory system already flags this as the one budget-worthy item), or
change `train_likelihood_model()`'s default from remove-silently to
flag-and-report with removal opt-in, matching every sibling default. Either way
the currently-training 18S model should be regarded as trained on the
unreviewed screen, and retrained if/when the screen verdicts arrive.

### A2. The iNat evidence weight (0.8) is on a different calibration footing than its two siblings, and sits ~16x above the blend-mode veto bound

The three evidence generators feeding `apply_undetected_evidence()` carry
weights with three different provenances:

| generator | w | provenance |
|---|---|---|
| `generate_regional_proximity_evidence()` | `0.05 * exp(-d/150)` | checklist-calibrated (0/110 zero-bbox candidates on the GL checklist; Jeffreys UB 0.027-0.107) |
| `generate_invasive_watch_evidence()` | 0.05 (workflow) | derived from the dataset-independent ordering bound (~1/19) |
| `generate_inat_range_evidence()` | **0.8 default** | design intuition from the D6 discussion ("closer to singleton, small disadvantage"), pre-dating the calibration finding; never re-examined after it |

The D4/D5 calibration's central lesson was that pre-calibration intuitions about
these weights ran ~10x high (raw `exp(-d/150)` overstated presence by an order
of magnitude), and the invasive weight was cut 0.6 -> 0.05 specifically for
violating the veto bound. The iNat generator was implemented two days AFTER
that lesson and kept 0.8, with no veto-bound discussion in its roxygen (checked:
`generate_inat_range_evidence.R` mentions the bound nowhere).

Why this is currently latent rather than live: its only wiring site
(GreatLakes 7a.7d) now runs **curve** pricing, where the veto bound
`19 * theta_singleton / theta_present` is >= 19 whenever the singleton cap
holds -- unreachable for any w <= 1, so a 0.8 row costs prior mass but cannot
veto a native. Under **blend** pricing (still the live path for PtCon and Mugu
until their kernel migration), the same bound is ~0.05, and a w = 0.8 row can
block species-level resolution of a singleton-level observed native at
likelihood parity -- the exact failure the 0.6 invasive weight caused for
yellow perch. If iNat evidence is ever wired into a blend workflow as-is, the
perch class of bug returns through a door the calibration work thought it had
closed.

Also worth recording (the applier's own roxygen invites it): the independence
assumption behind `w_combined = 1 - prod(1 - w_i)` is not satisfied for the
regional-proximity + iNat pair. iNaturalist research-grade records are
published INTO GBIF, so a species with iNat records just outside the bbox can
earn a regional-proximity w from GBIF copies of the very observations that
trained the iNat geomodel verdict -- two reads of one underlying fact,
OR-combined. Second-order at current weights (0.8 dominates the OR anyway),
but it is precisely the case the roxygen says "would need this revisited, not
assumed safe."

**Fix shape:** either calibrate the iNat weight by the same checklist recipe
(the GL machinery exists), or document it as curve-pricing-only until PtCon/
Mugu migrate, or have the applier warn when any evidence weight exceeds the
veto bound it already computes and prints -- it has both numbers in hand at the
same moment and currently only prints them side by side.

### A3. The Good-Turing budget audit goes stale the moment the soft confirmation update runs

Curve pricing's budget coherence statement is `sum(w)` vs `chao_missing`,
audited (never enforced) at `apply_undetected_evidence()` time -- GL: 6.67 vs
14.4. `update_prior_from_consensus()` then raises `prior_mix_w` on mixture rows
(that is its design), and nothing recomputes or re-prints the audit. Any quoted
budget-utilisation figure describes the priors as built, not the priors the
posterior actually used. Small fix: report `sum(prior_mix_w)` (before/after)
in `update_prior_from_consensus()`'s own message when mixture rows were
updated, so the audit has a post-refinement counterpart. Purely informational,
matching the audit's own audited-not-enforced philosophy.

### A4. TaxaAssign's re-moment-match of blend-mode mixture rows uses a different variance formula than TaxaExpect's original

`apply_undetected_evidence()` (blend mode) moment-matches with the full mixture
variance `v = w*Var_c + (1-w)*Var_f + w(1-w)(theta_c-theta_f)^2`. After a
confirmation update, `update_prior_from_consensus()` re-matches with
`v = w1(1-w1)(thp-tha)^2` only (R/update_prior_from_consensus.R:472) -- it
cannot do better, because the `prior_mix_*` schema does not carry the
within-state variances. For curve rows the states are points and the two agree
exactly; for blend rows the re-matched Beta is slightly over-concentrated
(dropped positive variance terms). Consistent with `compute_posterior()`'s
deliberately two-point sampler, inconsistent with the emitting package. Low
stakes today; becomes load-bearing under open decision #3 (see B4). Cheapest
fix if wanted now: carry `Var_c`/`Var_f` (or the present-state alpha/beta) in
the mixture schema.

---

## B. Cross-package statistical coherence (focus areas 1 and 3)

### B1. The double-counting audit comes back mostly clean -- name the gates so this doesn't get re-derived

The reentry doc's central question -- do kernel priors, reference screening, and
the mixture double-count or contradictorily discount evidence in the shared
posterior -- has a mostly reassuring answer, because several deliberate gates
partition the evidence:

- **Eligibility gate**: `apply_undetected_evidence()` elevates only taxa with
  no row anywhere in the priors (checked via `taxon_name` AND
  `source_taxon_name`), so occurrence-derived kernel mass and external
  evidence never stack on one taxon (verified live on real data, 2026-08-21).
- **Domestic exclusion**: transport-branch priors are structurally barred from
  the evidence applier (opposite claims about the same zero-record fact).
- **Leave-one-out** in the soft confirmation update: an observation's own
  posterior never re-enters its own prior.
- **Ceiling invariant**: w <= 1 caps any elevated/confirmed taxon at the
  singleton scale; under curve pricing with the singleton cap this makes the
  veto bound unreachable outright.
- **Reference screening feeds the likelihood side only by removing/keeping
  accessions** -- nothing consumes `label_confidence`/`reference_action`
  numerically downstream (confirmed by grep: zero consumers outside TaxaMatch).
  Thread 3 (quality as a likelihood covariate) was built, measured, and REMOVED
  by user decision -- the second independent closure. So there is no channel by
  which reference-quality evidence could be counted twice.

The two places evidence CAN still compound are A2's correlated-source
OR-combination and B2 below. Neither is a double-count of the same likelihood;
both are correlated-evidence accumulation in the presence probability.

### B2. The mixture-row confirmation update is level-blind, one-sided, and unbounded in dataset size -- it can partially rebuild the pre-calibration blocker state

`update_prior_from_consensus()`'s two update paths encode different degrees of
protection against the correlated-confirmation failure this codebase documented
when it rejected noisy-OR (Session 149):

- **Non-mixture rows** move toward a *support-weighted quantile* of
  per-observation support, capped by `q * max(theta_mean)` -- a sea of weak
  candidacies produces a low target, and a modelled native cannot be boosted
  past a fraction of the occurrence ceiling. Well-guarded.
- **Mixture rows** update `w1 = (pc*w0 + md) / (pc + md)` where
  `md = 0.25 * (leave-one-out support mass)`. This treats supporting mass as
  simultaneously the successes AND the trials: observations that fail to
  support the species contribute nothing to the denominator (never-demote by
  design), and the per-observation support LEVEL never enters -- 78
  observations at 2% move w exactly as far as ~2 observations at 78%.

Worked example on the ecosystem's own historical numbers (derived, blend
anchors, GL): under the calibrated w = 0.05, a watch-listed blocker at
likelihood parity holds ~2% posterior in each of 78 observations of a common
native (theta_blocker ~ 1.05e-3 vs perch 0.047). Mass ~1.67, `md` ~0.42,
**w: 0.05 -> 0.33** -- six times the printed veto bound -- lifting its posterior
share in those (unresolved) observations to ~12%, enough to hold the native's
cumulative share under the 0.90 resolution bar. Meanwhile the native itself
gains nothing from the same pass: its non-mixture target
`q * theta_ceiling ~ 0.7 * 0.047 = 0.033` sits BELOW its existing prior, so
`soft_gain = 0`. The refinement pass built to rescue perch-class observations
can, for a sufficiently widespread low-grade blocker, only reinforce the
blocker in them.

Three sharpenings, in decreasing confidence:

1. The constant `a0 = 0.25` is documented as "~4 correlated observations worth
   1 independent one," but it does not saturate with N: 400 correlated
   same-site observations are treated as worth 100 independent presence
   confirmations, which for one water body's shared DNA pool is hard to
   defend. Ibrahim-Chen power priors discount a likelihood exponent; a
   constant multiplier on a mass that grows linearly in dataset size is only
   its counting analog at small N. GreatLakes (885 observations) validated
   well; PtCon-scale datasets (13k+) are 15x further into the regime where
   `s_sat -> 1` and `md` dwarfs `pc`.
2. The printed veto bound is therefore a statement about the prior BEFORE
   refinement only. Nothing says so at either print site.
3. The asymmetry (mixture rows uncapped up to their ceiling, modelled natives
   capped at `q * theta_ceiling`) means confirmation systematically favors
   evidence-elevated taxa over occurrence-modelled ones at equal support.

**Recommendation (decision for the user):** make the mixture update
level-aware -- e.g. use the species' support-weighted quantile (already
computed as `species_target`) as the success rate,
`w1 = (pc*w0 + md*q_species)/(pc + md)`, or count trials as
`a0 * n_observations` so w moves toward the observed support rate rather than
monotonically toward 1. Either preserves continuity (D7's requirement) and
never-demote can be kept as a floor. At minimum, cap post-update `w` at the
veto bound unless the TaxaFlag watch caveat has fired -- that routes the
"blocker outscores natives everywhere" case to the surveillance channel that
was explicitly built for it, instead of the prior.

**Resolved (2026-09-07): the "at minimum" cap was built and is sufficient --
the deeper level-aware redesign is a closed pre-publication decision, not a
deferred one.** `update_prior_from_consensus()` now caps post-update `w` at
`prior_mix_veto_bound` when that column is present and non-`NA`
(`TaxaAssign/R/update_prior_from_consensus.R`). Given this review's own
framing as a final pre-publication screen with no opportunity to revisit,
the decision was made from real evidence, not by default:

1. **The exact worked example above is closed.** Reproduced arithmetically
   (`diagnostics/b2_mixture_update_veto_cap_check.R`): uncapped w1 = 0.3298
   (matches this section's own 0.33 to the digit), capped at exactly the
   0.05 veto bound -- a 6.6x reduction, matching this section's own "6x"
   figure. The specific correlated-confirmation runaway this finding is
   built around no longer happens.
2. **Real-data validation shows no regression.** A fresh, full production
   run of GreatLakes2023BurnsHarbor (real cached GBIF/NCBI data, not
   synthetic) with the fix live: 2792 presence-mixture rows updated by
   cross-observation support, `sum(prior_mix_w)` 110 -> 386 (a real, large
   aggregate w-inflation -- not a quiet dataset). Held-out Lamar validation
   afterward: species-level co-detections 602 (established 2026-08-31
   curve-pricing benchmark: 594), precision 602/706 = 0.8527 (benchmark:
   0.853), unique-species intersection 29/61 (benchmark: 28/61),
   overconfidence check 1/1081 (benchmark: 1/1081, exact match). No
   degradation despite substantial real w-inflation.
3. **A structural finding sharpens why:** the veto-bound cap never actually
   fired on that real run (`n_capped = 0` throughout) -- GreatLakes now runs
   CURVE pricing, and `prior_mix_veto_bound` is only ever non-`NA` under
   BLEND pricing (curve pricing retired the bound as part of resolving open
   decision #1: `theta_present` is pinned to the singleton mean, so the
   bound would be a fixed, always-unreachable `(1-m)/m = 19`). Curve pricing
   has a STRONGER guarantee than the cap it replaced: `theta = w *
   theta_present` means an elevated species' theta cannot exceed a
   genuinely-observed-once native's plausibility no matter how large w
   grows -- the failure mode this whole finding is about cannot occur under
   curve pricing by construction. The cap therefore only does real work for
   PtCon/Mugu, which still run blend pricing until D3's migration -- and
   point 1 above is the direct proof it works there.

Not independently re-verified: item 3's asymmetry concern ("confirmation
systematically favors evidence-elevated taxa over occurrence-modelled ones
at equal support") -- flagged as the lowest-confidence of the three
sharpenings in this section's own text, and not measured here. See
`TaxaID/CLAUDE.md`'s matching 2026-09-07 entry.

### B3. The two reference screens are not just different tools -- they are opposite philosophies applied to overlapping populations in one pipeline

Beyond A1's default question, the coherence issue: an accession can be
match-screened by TaxaMatch (annotate-first, three-veto removal, pre-removal
audit, TTLs, human/LLM review) and simultaneously training-screened by
TaxaLikely (silent heuristic removal). The same accession can be kept as a
match candidate and removed from training, or vice versa, with no record that
the two disagreed. Since `evaluate_reference_accessions()`'s cache is
cumulative and accession-keyed, a cheap coherence layer exists: at training
time, look flagged accessions up in the project's reference-evaluation cache
(free for any accession the match screen already paid for) before believing
the heuristic. `verify_flagged_references(cache_dir=)` already implements
exactly this join -- A1's fix and this coherence gap close together.

### B4. The two open kernel decisions DO interact with the mixture machinery -- one simplifies it, the other spans three functions in two packages

The reentry doc asked whether open decisions #1 (mass/f1) and #3
(theta-as-distribution) touch the mixture redesign in ways a package-scoped
session would miss. They do:

- **#1 (price at `mass/f1`)** would make `theta_present` identically the
  singleton mean, so the curve veto bound becomes exactly `(1-m)/m = 19` --
  always unreachable -- and `cap_at_singleton` becomes a no-op by construction.
  Two guards and their messaging simplify away. It also changes what a
  fully-confirmed mixture row (w -> 1) can reach: exactly the singleton mean
  rather than a group-dependent multiple/fraction of it, which makes B2's
  ceiling argument uniform across groups. And it is defined for every group
  with a singleton, eliminating the `f1 = 1, f2 = 0` "mass but no price" guard
  case. In short: #1 is not only a pricing choice, it is a
  complexity-reduction of the cross-package veto/cap machinery. (GL is already
  proven robust to it: 0/880 flips.)
- **#3 (theta distribution)** is usually described as "extend
  `compute_posterior()`'s existing Bernoulli sampler" -- true but incomplete.
  It requires the `prior_mix_*` schema to carry the present-state
  distribution, which touches **three** functions in **two** packages:
  `apply_undetected_evidence()` (emit), `compute_posterior()` (draw theta as
  well as z), and -- the one a package-scoped session would miss --
  `update_prior_from_consensus()`'s re-moment-match (A4), which currently
  hard-codes the two-point variance and would silently drop the new
  within-state term, shrinking the refreshed Beta summary. Decision #3's
  implementation checklist should name all three.

### B5. `max_hits` / false-rescue: correctly resolved, with one remaining unexamined door

The changelog's verdict (audit-before-removal via
`verify_removal_candidates()`, default unchanged) is the right resolution and
this review found nothing to add to the default question itself. The
mechanism finding that generalises -- one mislabel can rescue another
(`KJ135626` <- `MZ605481`), and `refine_reference_verdicts()` cannot discount a
corroborator that is "merely a BLAST hit, not itself in the screened
population" -- has been applied to the removal veto (corroborators now named,
1-2-partner spares warned). Two adjacent doors have NOT been examined under
the same light:

1. **`"locally_corroborated"` is cached with infinite TTL and is exempt from
   trust refinement** (`refine_reference_verdicts()` skips locally-corroborated
   rows; the verdict asserts a match was observed, which is permanent). But
   the corroborating *deposit's own label* is exactly as falsifiable as
   `MZ605481`'s was -- the match is permanent, its evidential value is not. A
   local corroboration resting on a single conspecific deposit that is later
   proven mislabeled would persist forever. Worth the same transparency
   treatment the veto got: record the corroborating accession(s) on
   locally-corroborated rows, and consider whether a corroborator later
   verdicted `incongruent`/`remove` in the same cache should reopen the row.
2. **On-demand screening of thin corroborators.** For a spare resting on 1-2
   corroborators, those corroborators are ordinary accessions; evaluating them
   through the same cumulative cache (bounded cost -- a handful per audit, and
   removal candidates are ~2-4 per site) would close the "no verdict to
   discount" gap in the one place it is destructive, without touching
   `max_hits` or the fixpoint's guards.

---

## C. Shared-concept drift across package boundaries (focus area 2)

Surveyed "confidence," "evidence," "corroboration," and "plausibility" across
the nine packages' exported vocabulary. Overall: better than expected -- most
overloads are documented at their definition sites, the polarity convention
(HIGH = concern for `*_risk`, stated direction otherwise) is consistently
applied post-rename, and the one measured live contradiction ("insufficient
independent evidence" describing rows that HAVE evidence) was already found and
dispositioned on 2026-09-04. Residuals, by term:

- **"confidence"** names at least five quantities: `label_confidence`
  (TaxaMatch; a bounded, deliberately-ceilinged vote-plus-margin, NOT
  calibrated, NA when unearned), `confidence_score` (TaxaAssign; fraction of
  MC simulations won), `consensus_confidence_score` (same idea at consensus
  scope), `confirmation_discount`'s support mass (TaxaAssign; presence
  pseudo-observations), and `p_conc` ("presence-claim confidence" in
  pseudo-observations). These never numerically touch each other, so the drift
  is a reader hazard, not a computation hazard. The one live rule worth
  centralising: **`label_confidence` cannot reach 1 and must be
  ceiling-normalised by any future ratio-style consumer** -- currently recorded
  only inside the reference-quality reentry doc, i.e. in exactly the kind of
  place a future consumer won't look. It belongs in
  `score_reference_labels()`'s roxygen as a named contract (part of it is
  there; the normalisation formula is not).
- **"evidence"** names three different substances crossing boundaries: query
  evidence (read depth; `evaluate_likelihoods(evidence_col=)`), occurrence/
  presence evidence (the generators' `weight`, `evidence_weight`,
  `evidence_sources`, `undetected_type = "evidence_blend"`), and BLAST
  corroboration evidence (`congruent_evidence_exists_anywhere`,
  `insufficient_independent_evidence`). Context disambiguates in code; prose
  ("the evidence") frequently doesn't. No fix proposed beyond the glossary
  below.
- **"corroboration" is the real drift case.** Three trust levels share the
  word: (i) `locally_corroborated` -- the dataset's own match candidates,
  treated as permanently valid; (ii) `n_corroborators`/`corroborators` in
  `verify_removal_candidates()` -- arbitrary unscreened BLAST hits, now known
  to be false-rescue-capable; (iii) "Lamar-corroborated" -- external
  independent-pipeline validation, the strongest sense, used throughout the
  session notes. A reader seeing "corroborated" cannot tell whether the
  corroborator was itself vetted, which after the `KJ135626` finding is the
  load-bearing distinction. Suggest qualifying (ii) in output/messages as
  "unscreened corroborators" or similar.
- **"plausibility"** has three senses (TaxaFlag's LLM categorical
  likely/possible/unlikely; the prior-side plausible-competitor mask read off
  `prior_branch`; the consensus `plausible_taxa` set from posterior
  thresholds). All well-separated by column naming; lowest risk of the four.

**Cheap mitigation for all of it:** a one-page glossary in `ecosystem_docs/`
mapping each overloaded term to its package-qualified meanings, written once
and linked from the manuscript-facing docs. The confusion-risk rename history
shows this project already knows a vocabulary decision is load-bearing; the
glossary is the flag-don't-rename version of that discipline.

---

## D. Architectural fit against the ecosystem's own principles (focus area 4)

### D1. What the new mechanisms get right (worth saying, so it isn't re-litigated)

Measured against the ecosystem's own precedents, the three big mechanisms are
notably well-behaved: additive-column discipline throughout
(`label_confidence`/`reference_action` beside `hierarchy_flag`, not replacing
it; `refine_reference_verdicts()` writes parallel `*_trust` columns instead of
overwriting -- the `trusted_rank` lesson visibly learned); no-silent-default
convention honored (per-group pricing errors on an unassigned taxon rather
than guessing from taxonomy; `sampling_group` never inferred); explicit
failure over silent guess everywhere the guards fire; and the budget is
audited, not enforced -- the correct posture for a diagnostic quantity with
measured 1.9x-137x radius sensitivity. No rejected pattern has been rebuilt
wholesale. The nearest miss is B2: the mixture w-update partially resembles
the rejected accumulate-correlated-confirmations design that the non-mixture
quantile path was specifically built to avoid.

### D2. `model_tier` retirement is not mechanical -- one consumer has no `prior_branch` fallback

`model_tier` is doc-deprecated (kernel schema: `prior_branch` +
`effective_records`) but nine files still read it. The legacy-fallback readers
(`join_priors()` promotion gate, `posterior_consensus()` Axis-1) branch on
`prior_branch` when present and are retirement-safe. One is not:
`apply_undetected_evidence()`'s blend-mode ceiling-anchor ladder
(R/apply_undetected_evidence.R:527-533) excludes evidence/domestic rows from
serving as the ceiling anchor via `model_tier` values ONLY, guarded by
`"model_tier" %in% names(modelled)` -- when the column retires, the guard makes
the filter silently vanish and an evidence-blend row can become the ceiling
anchor for the next evidence row (evidence anchoring evidence, exactly what
the exclusion prevents). The existing "evidence rows never serve as the
anchor" test would keep passing on legacy fixtures. Before retiring
`model_tier`, add a `prior_branch`-based clause to that filter (and grep the
other seven files). Filed as a retirement-checklist item, not a current bug.

### D3. Finish the PtCon/Mugu kernel migration sooner rather than later -- the dual-schema period has already produced one full semantic inversion

The GLMM path is deliberately retained until PtCon/Mugu migrate; that is fine.
But the cost of the dual period is now measured, not hypothetical: the Axis-1
`model_tier` reading was **fully inverted** on kernel tables (873/885
"unprecedented", locally-evidenced species reading FALSE, zero-record species
reading TRUE) and shipped that way until caught. A2's veto-bound divergence
(blend ~0.05 vs curve unreachable) is a second place where the same evidence
weight means different things per branch. Every additional mechanism built
during the dual period has to be reasoned about twice and can be wrong on
exactly one branch, silently. This review's concrete instances (A2, D2) are an
argument for prioritising the migration over further parallel-branch features.

---

## E. Performance and footprint (focus area 5)

### E1. Two structural scaling walls, both on the reference side; the prior side scales fine

The kernel-priors architecture does NOT make footprint structurally worse:
`estimate_kernel_priors()` is linear in records (2.19M-record 18S diagnostic
ran as a subset job), `plot_theta_surface()` is FFT-binned (~2s for 512x512
from 1.25M records), `kernel_budget_sensitivity()` is a bounded grid of the
same estimator. GBIF caches grew because `limit = NULL` is now correct policy;
`keep_zip = FALSE` + the clear-cache tooling is adequate mitigation. The two
real walls are on the reference/likelihood side, and both are design-level
(neither is "the 18S run hasn't finished," which is expected state):

1. **`train_likelihood_model()`'s whole-set MSA.** The 18S reference set
   (21,899 sequences, 1,412 genera) is ~2x the ecosystem's historical maximum,
   and the training step's alignment cost grows superlinearly in set size. The
   quantities actually consumed downstream are within-genus pairs (H1/H2) and
   a cross-clade sample (H3) -- neither requires one global alignment. A
   per-genus alignment strategy (plus sampled cross-genus pairs for H3) would
   turn the dominant cost from O(N^2)-ish in the whole set to a sum over
   genus-size squares (mean 15.5 sequences/genus here). This is a design
   decision with validation implications (score scale is trained-scale
   sensitive -- see `[[project_train_inference_scale_validity]]`), not a patch;
   flagged because reference sets are on a growth trajectory and 18S will not
   be the largest for long.
2. **The reference-quality screen cannot be run 18S-shaped.** Per-accession
   remote BLAST for 21,899 accessions under a throttle that has already
   blocked 995-accession runs is not a feasible first screen. The scoping
   tools already exist -- `match_driving_accessions()` and the
   flagged-subset-only posture of `verify_flagged_references()` -- and the
   2026-08-18 design ("BLAST only the disputed ~230-280, not the thousands")
   is the right doctrine. Recommend promoting it from an implicit practice to
   the documented default for large markers: screen match-driving accessions
   and training-screen-flagged accessions; the full-population screen stays a
   deliberate, budgeted choice. (This also concentrates screening exactly
   where A1's fix needs it.)

### E2. `diagnostics/fast_workflows/` is the right mitigation for iteration speed, with one maintenance note

The fixture approach (real curated subsets, seconds-scale smoke tests, both of
its first-run findings already fixed in the critical-fix pass) addresses the
iteration-speed half of the footprint concern well. It does not and cannot
address production-run wall time (E1's walls). Maintenance note: the 18S
fixture was deliberately built from a live run's stable stage and will need
rebuilding as that run progresses -- already documented in its README; keep it.

### E3. Operational reminder (owed per project memory, surfacing here as promised)

After the PtConception 18S run fully completes, the TaxaFetch cache (~17GB,
mostly GBIF zips; the repaired 18S zip lives there and must survive until the
run no longer needs it) is due for clearing via
`taxafetch_clear_cache()`/`zips_only`. `orphans_only` reclaims zero; age (or
`zips_only` with `keep_zip = FALSE` going forward) is the lever.

---

## Verdict summary

| # | Finding | Severity / confidence | Size of fix |
|---|---|---|---|
| A1 | Training auto-removes on the demoted screen; `verified_clean` bridge unwired; censoring anti-conservative in tight genera; live in the 18S training | High / high | Small (wire existing bridge or flip default) |
| A2 | iNat w=0.8 uncalibrated, above blend veto bound; correlated with regional-proximity source | Medium (latent) / high | Small (calibrate, gate, or warn) |
| A3 | Budget audit stale after confirmation pass | Low / high | Tiny (report Σw post-update) |
| A4 | Blend re-moment-match drops within-state variance | Low / high | Small (carry state variance) |
| B2 | Mixture w-update level-blind, one-sided, N-unbounded; veto bound pre-refinement only | Medium-high / medium (worked example, not yet measured on real data) | Medium (level-aware update or bound cap) |
| B3 | Two opposite screening philosophies on overlapping accessions, no reconciliation record | Medium / high | Small (cache lookup at training; joins with A1) |
| B4 | Open decisions #1/#3 have cross-package reach (#1 simplifies veto/cap; #3 touches 3 fns / 2 pkgs incl. the re-match) | Informational for the pending decisions | -- |
| B5 | False-rescue doors: infinite-TTL local corroboration + refinement exemption; thin-corroborator screening | Medium / medium | Small-medium |
| C | Concept drift: "corroboration" trust levels; `label_confidence` ceiling contract buried in a reentry doc | Low-medium / high | Tiny (glossary + roxygen contract) |
| D2 | `model_tier` retirement: ceiling-ladder exclusion has no `prior_branch` fallback | Medium (future) / high | Tiny (checklist item) |
| D3 | Dual GLMM/kernel period has measured inversion cost; prioritise migration | Architectural | -- |
| E1 | Whole-set MSA and full-population screening don't scale to 18S-sized reference sets | Architectural / high | Design decisions |

Nothing here contradicts the validated real-data results (Lamar precision
0.853, the strictly-additive +4 species, 0/880 pricing flips, the soft-update
axis sweep) -- those stand. The findings concentrate where mechanisms meet:
weights calibrated in one regime crossing into another (A2, B2), verdicts made
under one philosophy consumed under its opposite (A1, B3), and schemas mid-
transition (D2, D3). That is the expected shape for a system built
package-by-package to a high local standard, and it is a short list.
