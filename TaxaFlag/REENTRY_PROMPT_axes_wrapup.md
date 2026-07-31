# Re-entry: finish the Axis 1/2/3 redesign (wrap-up tasks)

**CLOSED 2026-07-30 (Sonnet 5). All tasks in this document (0/1/3/4) are shipped,
tested, and — for Mugu specifically — verified end to end against real production
data.** Task 1 (`compute_group_priors()`) went through one more full redesign after the
status block below was written: `consensus_prior` moved from a candidate-scoped MAX
to a real group-level SUM, `group_priors` was wired into all 5 real production
`posterior_consensus()` calls, and wiring it into production surfaced 3 more real bugs
in sequence (a never-reinstalled TaxaAssign package, a missing species-rank row in
`compute_group_priors()`'s own output, and a genuine Urolophus/Urobatis backbone
disagreement that turned into a full backbone-architecture review and decision — NCBI
adopted as the common working backbone for these vertebrate-focused workflows). See
`TaxaAssign/CLAUDE.md`, `TaxaFlag/CLAUDE.md`, and `TaxaID/CLAUDE.md`'s own 2026-07-30
top session notes, and `[[project_axis1_consensus_prior_group_priors]]` in the TaxaID
memory system, for the full record — this document is now historical, not the current
source of truth. Final verified state (`MuguFishWorkflow.R`, live re-run): 519
expected / 93 unexpected / 4 unprecedented. `MuguWilderFishWorkflow.R` has the
identical fix applied but not yet re-run; the 3 PtConception workflows have the fix
applied but have not been run at all this session.

**STATUS 2026-07-30, final update (Sonnet 5): Tasks 0, 1, and 3 all SHIPPED.**
Additionally: `consensus_prior`'s MAX fallback deleted (requires `group_priors` now,
no silent degrade); Axis 1 threshold made rank-relative; `posthoc_assessment`/
`vague_rank` fully retired (package + all 5 real production workflow scripts updated);
Finding B (Urolophus/salmonid gap) root-caused via source inspection — the Urolophus
theory did NOT hold up (see `[[project_urolophus_synonym_join_bug]]`, corrected), the
real salmonid cause is a habitat-scheme vocabulary gap, not a taxonomy bug. **Only Task 4
(Mugu re-run instructions) remains**, and it now needs an ADDITIONAL step beyond the
original scope: fixing the habitat scheme before re-running, if the user wants the
salmonid gap actually closed this run.

Status 2026-07-30, **revised again later the same day (Sonnet 5) — Task 0 (0a/0b/0c)
SHIPPED.** User confirmed 0a and 0b directly; 0c was clarified (it's a choice between the
original Q1 options a/b, recommending "track" over "suppress") and confirmed. All three
implemented, tested against real-shaped fixtures, `devtools::check()` clean on both
TaxaAssign and TaxaFlag. **Task 1 (sum-over-all-local-members redesign of
`consensus_prior`) is next and still needs its `group_priors` plumbing interface confirmed
with the user before building — do not guess at it.**

Earlier revision context (Opus 5, same day): the user asked for a skeptical evaluation of
the consensus-prior math. Task 1's original noisy-OR recommendation was WRONG (see Task 1
below, unchanged from that revision). Task 0 was added ahead of it, at the user's explicit
sequencing instruction ("we first need to decide the candidate level prior and updated
prior before calculating the upranked prior").

Read `REENTRY_PROMPT_axis2_multifactor_diagnostic_redesign.md` first (it has the FALSIFIED
banner + WHAT SHIPPED section). This file supersedes its "NOT done" list.

## State: what is already built, tested, NOT YET reinstalled

- **Axis 2 categorical — SHIPPED**: `primary_discrimination` / `consensus_discrimination`
  replacing `confusion_risk_flag`. Do not revisit.
- **Task 0a — SHIPPED**: `posterior_consensus()` gains `winner_theta_mean`;
  `consensus_prior` now reads `theta_mean` (still MAX + candidate-scope -- Task 1 upgrades
  the aggregation, not this). `add_posthoc_assessment()`'s `winner_prior_col`/
  `expected_prior_threshold` replaced by `winner_theta_col`/`expected_theta_threshold`
  (the latter has **no default** -- required, mirrors `backbone_id`/`rank_thresholds`
  convention. Recommended value: `median(taxaexpect_priors$theta_mean, na.rm = TRUE)`).
  One threshold applied uniformly across primary/consensus scope for now -- a fully
  rank-aware version needs Task 1's aggregation.
- **Task 0b — SHIPPED**: `update_prior_from_consensus()`'s confirmation-quantile
  substitution rescaled onto the occurrence scale when `result` carries `theta_mean`:
  `prior_new <- max(prior_old, q * max(result$theta_mean, na.rm = TRUE))`. Falls back to
  the old direct-substitution behavior when `theta_mean` is absent (e.g. LLM-pathway
  priors from `assign_taxa_llm()`, not occurrence-share-based to begin with).
- **Task 0c — SHIPPED**: new `confirmed_without_occurrence_record` output column on
  `update_prior_from_consensus()` -- `TRUE` for a boosted row whose taxon has `theta_mean`
  `NA` (no occurrence record at all). Tracks, does not suppress -- suppression stays unsafe
  until Finding B's join bug is fixed (see below).
- **Tests**: TaxaAssign 591/591 (up from 567), TaxaFlag 249/249 (up from 239).
  `devtools::check()` 0 errors/0 warnings/0 notes on TaxaAssign; TaxaFlag clean apart from
  the pre-existing, unrelated `build_review_covariates` warning+note.
- **NOT YET reinstalled to `~/Library/R/4.0/library`** -- run before any real workflow
  (including any diagnostic re-verification against real Mugu data) picks these up.
- **`confusion_risk` fixes** in `TaxaLikely/R/support_curves.R` (Jeffreys floor +
  interpolation; raw and smoothed columns kept separate so `compute_rank_thresholds()`
  stays bit-identical).
- **`absolute_fit_pvalue` retired** everywhere — see
  `[[project_absolute_fit_pvalue_retired]]`.

---

## THE LOAD-BEARING FINDING (2026-07-30, revised): theta is a compositional share

Confirmed by reading `TaxaExpect/R/prepare_model_dataframe.R` directly. The GLMM response
is `cbind(n_species, n_other)` where `n_other = n_total_at_site - n_species`, and
`n_total_at_site` is the count of **all records from every taxon** at that site (within a
sampling group). So:

> `theta_mean` = E\[share of all local records belonging to taxon *i*\].
> It is a **categorical probability over taxa** — one record belongs to exactly one taxon —
> **not** a Bernoulli presence probability.

Empirical corroboration on the real Mugu prior table (244 modelled taxa):

| quantity | value |
|---|---|
| `sum(theta_mean)` over all 244 | **1.173** |
| … over `tier1` + `tier2` only | **1.083** |
| `max(theta_mean)` | **0.0865** |
| `median(theta_mean)` | **0.00254** |
| Beta concentration `alpha+beta` | exactly **2** for 230 of 244 rows |

Independent presence probabilities have no reason to sum to ~1. A categorical
distribution's probabilities must. The ~17% excess is the `tier3_undetected` (0.089) and
`tier_domestic_food` (0.0006) floor rows being appended *outside* the fitted composition,
plus GLMM estimation error (`tier1` alone sums to 0.883).

**Everything below follows from this one fact.** Read it before touching either task.

---

## Task 0 — `update_prior_from_consensus()` is a units error (DONE)

**All three parts shipped 2026-07-30 (Sonnet 5).** Kept below for the record of the
diagnosis; see "State" above for what was actually built.

### What was measured

`update_prior_from_consensus()` substitutes the `confirmation_quantile`-th quantile of
confirming donors' `consensus_posterior` for `prior_mean`, never-demote, with **no gate on
whether the taxon has any occurrence record at all**.

`consensus_posterior` is P(hypothesis | evidence) **within one observation** — a
probability over competing hypotheses. `prior_mean` is a **compositional share of the local
record pool**. These are different sample spaces. Never-demote guarantees the substitution
only ever inflates.

Reconstructed **exactly** by diffing the real pre-boost round-1 posteriors
(`MuguWilderFish_blast_r1_{12s,16s,coi}.rds`, each a list — use `$posteriors`) against
`MuguWilderFish_blast_all_posteriors_r2.rds`. Do not infer boosts from `prior_updated`;
that column is `TRUE` for every row of an unresolved observation, boosted or not.

- **220 of 2540 rows were actually boosted**, spanning 19 taxa.
- **220 of 220 land in \[0.951, 1.0\]** — i.e. **every** boost overshoots
  `max(theta_mean) = 0.0865` by 11x to 1000x. Median boost: 0.0046 → 1.000 (218x).
- **All 220 rows with `prior_mean >= 0.5` are boosted rows. Zero exceptions.**

### Measured consequences, in order of severity

1. **Axis 1 is fully circular — this is the real damage.** 110 of 616 winners have
   `winner_prior >= 0.5`, and every one is a boost. So **every `expected` call Axis 1
   currently makes means "this dataset confirmed the taxon in another observation"**, not
   "this taxon is expected here on occurrence grounds". This *is* Finding A, now with an
   exact cause and count rather than a gap-in-the-histogram argument.
2. **Confidence is inflated.** Recomputing posteriors with a correctly-scaled version of
   the same boost (`q * max(theta_mean)`, never-demote): ASV_444 0.988 → 0.885, ASV_617
   0.992 → 0.916, the three *Cyprinus carpio* observations 0.99 → 0.96. This flows into
   `consensus_posterior`, `is_resolved`, `min_posterior`/`cumulative_threshold`, and — if
   the step were ever iterated — into the next round's own confirmation quantile.
3. **Decisions: no measured change.** Same recomputation gives an **identical winner set,
   0 of 616 observations differ**. Honest statement: on this dataset the scale error costs
   calibration, not calls. Do not oversell it as flipping IDs.
4. **The no-record case is real but rare here: 1 of 220.** That one row is exactly the
   ASV_13 *Oncorhynchus mykiss* case (`model_tier` NA, `theta_mean` NA, boosted
   0.00085 → 0.9754, `score_likelihood` 0.00069 vs *O. kisutch* 1.0, yet
   `posterior_mean` 0.288). The other 219 boosted rows all carry a real `model_tier`.

The 20-22 real winner changes the boost causes are **not** obviously wrong — e.g.
*Cyprinus rubrofuscus* → *C. carpio* and *Hyperprosopon anale* → *Cymatogaster aggregata*
are both cases where a locally common, confirmed species beats a marginally better BLAST
score. **The mechanism earns its keep; it is the scale that is wrong.** Do not propose
deleting it.

### Recommendation to put to the user (three parts, decide separately)

Neither option (a) "never boost a no-record taxon" nor (b) "boost but flag it" is
sufficient on its own — both address 1 of 220 rows and leave the 219-row scale error
untouched.

- **(0a) Axis 1 and `consensus_prior` read `theta_mean`, never `prior_mean`.**
  Necessary and sufficient for the axes work, and it requires **no decision about the boost
  at all** — a boost that cannot reach the occurrence columns cannot corrupt them.
  **`theta_mean` is already carried through onto `posterior_df` by `join_priors()`
  (verified on the real object) — no new join, param, or network call is needed for the
  primary/species scope.** Do this regardless of what is decided about 0b/0c.
- **(0b) Rescale the boost instead of substituting it** — its own decision, because it
  changes posteriors. Keep the confirmation-quantile logic and never-demote; change the
  target onto the occurrence scale, e.g.
  `prior_new <- max(prior_old, q * max(theta_mean over locally modelled taxa))`.
  Bounded, unit-correct, still sensitive to donor strength via `q`, and the ceiling is the
  model's own observed maximum rather than a fitted constant.
- **(0c) Track the no-record state — prefer option (b), NOT (a), for now.** A
  `confirmed_without_occurrence_record` flag records the ASV_13 pattern without suppressing
  it. **Suppressing (option a) is currently unsafe because of the upstream join bug**
  (`[[project_urolophus_synonym_join_bug]]`): a taxon can have abundant real occurrence
  records yet no `taxaexpect_priors` row (all salmonids; *Urolophus halleri*, ~1,749 GBIF
  records — confirmed again this session, `Salmonidae` is absent from the prior table
  entirely). Gating on `model_tier` would silently punish exactly those taxa. Option (a)
  becomes the right answer **once that bug is fixed**; say so explicitly when proposing it.

---

## Task 1 — redesign `consensus_prior`: SUM, not max, and **not noisy-OR** (DONE)

**Shipped 2026-07-30 (Sonnet 5).** `TaxaAssign::compute_group_priors(taxaexpect_priors,
taxonomy_map, rank_cols = c("genus", "family"))` (new, `R/group_priors.R`) computes the
SUM of `theta_mean` per (rank, taxon) group over every LOCALLY MODELLED member -- caller
supplies `taxonomy_map` (e.g. `occurrences_clean`, which has real genus/family columns
`taxaexpect_priors` itself lacks). `posterior_consensus(group_priors = ...)` (new optional
param) uses the matching `theta_sum` for `consensus_prior` when `group_priors` has a row
for that observation's `(consensus_rank, consensus_taxon)`; falls back to the unchanged
candidate-scoped MAX otherwise (fully backward compatible, `group_priors = NULL` default).
`theta_sum` capped at 1 as a defensive guard. TaxaAssign 611/611 (up from 591),
`devtools::check()` 0/0/0.

**NOT done, deliberately out of scope for this pass**: `add_posthoc_assessment()`'s
`expected_theta_threshold` still applies ONE scalar uniformly across primary/consensus
scope (see Task 0a). Now that `group_priors` exists, a fully rank-aware version is
possible -- compare each rank's `consensus_prior` against the MEDIAN `theta_sum` at that
SAME rank (species/genus/family), rather than one species-scale value everywhere. Natural
follow-up, not yet built or asked for.

**No production workflow wired yet** -- `compute_group_priors()` needs a real
`taxonomy_map` (e.g. from a workflow's own `occurrences_clean`), which is workflow-specific
and hasn't been supplied by any real call site.

Original diagnosis kept below for the record.

**The earlier noisy-OR recommendation in this file was wrong.** It assumed `theta_mean`
values are independent Bernoulli presence probabilities. They are not (see the load-bearing
finding above). Corrected reasoning:

- Records are **mutually exclusive** across taxa, so for a group *G*,
  `P(a local record belongs to G) = sum_{i in G} theta_i` — **exactly, by finite
  additivity.** No independence assumption is required at all.
- Noisy-OR is the right combiner only for *independent Bernoulli* events. Wrong on two
  counts here: wrong sample space (a per-record share is not a per-site presence
  probability), and — even under a reinterpretation — shares of a fixed total are
  **negatively** dependent by construction, the opposite of what noisy-OR assumes, so it
  would systematically overstate.
- The old "sum is unbounded in principle" worry is backwards: under the compositional model
  a subset sum **cannot** exceed 1 if the model is exact. Observed max family sum on real
  Mugu = **0.177**, 0 of 28 families exceed 1. If one ever did, that is a diagnostic signal
  of over-fit priors, not a reason to reach for a formula from the wrong sample space. A
  defensive `min(sum, 1)` is fine.
- Practically the two differ by **at most 4.9%** across the 28 real families, so this is a
  correctness/interpretability fix, not a numbers fix.

**Use `sum`. Use `theta_mean`, never `prior_mean`** — `prior_mean` saturates any aggregate
(sum *or* max) at ~1.0 the moment a single member was confirmed anywhere in the dataset
(all 220 `prior_mean >= 0.5` rows are boosts), and it re-introduces the Task 0 circularity.

Real Mugu, locally-modelled members, taxonomy mapped from
`MuguWilderFish_blast_occurrences_clean.rds` (175 of 244 prior taxa map to a family/genus):

| family | n | max (current) | noisy-OR (rejected) | **sum (use this)** |
|---|---|---|---|---|
| Paralichthyidae | 8 | 0.0865 | 0.1682 | **0.1768** |
| Cottidae | 30 | 0.0429 | 0.1147 | **0.1205** |
| Sciaenidae | 9 | 0.0658 | 0.0989 | **0.1016** |
| Embiotocidae | 15 | 0.0219 | 0.0625 | **0.0641** |
| Gobiidae | 13 | 0.0164 | 0.0309 | **0.0313** |

### ⚠️ New finding: the break must be RANK-RELATIVE

Aggregates and individuals live on the same scale, so one threshold across ranks is
systematically biased — a family clears a species-calibrated break just by summing more
terms. Measured: **27 of 28 families (96%) exceed the species-level median**, whereas 14 of
28 exceed the family-level median by construction.

| rank | n groups | median aggregate |
|---|---|---|
| species | 244 | 0.00254 |
| genus | 125 | 0.00254 |
| family | 28 | 0.01655 |

So compare each taxon against the median at **its own rank** in the local assemblage.

### Plumbing (option B confirmed, with one simplification)

- **Primary/species scope: nothing new needed.** `theta_mean` is already on `posterior_df`.
- **Consensus scope (genus/family aggregate): one small precomputed lookup.**
  `taxaexpect_priors` has all-`NA` `genus`/`family`, and the aggregate must span *all* local
  members, not just the observation's candidates — so it cannot be computed from
  `posterior_df` alone. Pass one optional argument to `posterior_consensus()`, e.g.
  `group_priors` = a data frame of `rank` / `taxon` / `theta_sum` / `n_members`, built once
  upstream. Cheapest option and it matches the user's stated "minimal overhead on
  PtConception workflows" constraint. **Confirm the interface with the user before
  building.**

---

## Finding B — `unprecedented` is contaminated by a real upstream bug (unchanged)

See `[[project_urolophus_synonym_join_bug]]`. Species with abundant real occurrence records
reach `taxaexpect_priors` with **no row at all**: ~1,749 GBIF records for *Urolophus
halleri*; 195 real *Oncorhynchus* records in `occurrences_clean` vs 0 salmonids in
`taxaexpect_priors` (re-confirmed this session). **At least 5 of the 14 `unprecedented`
winners are artifacts.** Axis 1 works correctly and is a good *detector* for this, but
`unprecedented` means "absent from `taxaexpect_priors`", which equals "never reported" only
if that table is complete. It is not. **Document the caveat in
`add_posthoc_assessment()`'s `@section Occurrence plausibility` regardless.** See Task 0c —
this bug is also why the no-record *gate* should not ship yet.

---

## Finding A — RESOLVED by Task 0 (kept for the record)

The `expected` tier's 0.5 threshold was justified partly on an "11x empty gap" between
0.0865 and 0.966 in the real prior distribution. That gap is **the boundary between
modelled priors and empirical-Bayes-boosted priors**, not a natural break in occurrence
plausibility — now confirmed exactly: all 220 rows above 0.5 are boosts, and no modelled
occurrence prior exceeds 0.0865. Task 0a (compute Axis 1 on `theta_mean`) is the fix; it is
the old option (a), and the "no natural break to anchor a new threshold" objection is
answered by the rank-relative options below.

### Candidate breaks on the `theta_mean` scale — all relative, none fitted

| break | value (species rank) | % of taxa above | mass above | reading |
|---|---|---|---|---|
| **median at own rank** (user's proposal) | 0.00254 | 50% by construction | 0.96 | "more expected than the typical local taxon at this rank" |
| `1 / n_obs` | 0.00260 (= 1/384) | 26% | 0.79 | "expected to appear more than once in the local record pool" — this is already the pipeline's own singleton floor value |
| `1 / N` (N = modelled taxa) | 0.00410 | 16% | 0.73 | "above the share of an average assemblage member" |

**Recommend the rank-relative median** (the user's own proposal): it is robust to the heavy
tie mass sitting exactly at the singleton floor, and needs no assumption about `n_obs`.
`1/n_obs` is the most *interpretable* if an absolute anchor is wanted. **Put this to the
user — they proposed the median but have not confirmed it.**

---

## Task 3 — retire the old column (do LAST, after Tasks 0 and 1)

**Not yet done.** `vague_rank` is still live and still short-circuits `posthoc_assessment`
for every non-species rank. Retire together:

- `posthoc_assessment` (all 9 categories, incl. `vague_rank`, `modeled`,
  `domestic_prior_caveat`)
- `confusion_risk_flag` — already superseded and removed by the shipped Axis 2 categorical.

Measured justification: on the real 616-observation dataset **109 observations get
`vague_rank`** and are therefore never assessed at all; Axis 1 classifies all 109
(78 `expected`, 22 `unexpected`, 9 `unprecedented`). That is the original
ASV_379/*Chaenogobius* bug. **Note the 78 `expected` will be recounted once Task 0a lands** —
they are currently boost artifacts.

Check `domestic_taxa`/`domestic_prior_source` before deleting — `domestic_prior_caveat` may
deserve to survive as its own small column. See
`[[project_taxaflag_domestic_species_floor_note]]`.

## Task 4 — Mugu re-run instructions (deliver when Tasks 0–3 land)

- The Jeffreys half of the `confusion_risk` fix changes **stored curves**, so it only takes
  effect on a **retrain** — `train_likelihood_model()` then `evaluate_likelihoods()` must
  both re-run. The interpolation half already applies to cached curves.
- Every cached `*_lik_model_*.rds` / `*_lik_result_*.rds` still holds pre-fix
  `confusion_risk` values until then.
- `MuguWilderFishWorkflow.R:784` calls `calibrate_query_noise()` **after** the model
  checkpoint is written, so the saved model has no `Query_Calibration` slot even though
  calibration ran. **Do not infer calibration state from the saved model object.**

## Working style (unchanged, and load-bearing here)

- Ground every claim in real data or a source read. Several confident claims in earlier
  versions of this file did not survive checking — the `Dr = X` assumption, the COI-ceiling
  claim, the "structural zeros" reading, the 0.5-threshold justification, **and this file's
  own noisy-OR recommendation.**
- No implementation without explicit go-ahead.
- The user pressure-tests with concrete numbers — treat that as the primary validation
  mechanism, not friction.
