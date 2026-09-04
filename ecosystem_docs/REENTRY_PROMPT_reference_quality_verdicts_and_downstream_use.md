# REENTRY: reference-quality verdicts (recursive screening, label verdicts,
# action column) and their downstream use in likelihood modeling

Written 2026-09-02 (Fable 5, with the user) after reviewing the first
complete PtConception `evaluate_reference_accessions()` run. Design thread
NOT started -- this doc is the brief for it. Read
`TaxaMatch/CLAUDE.md`'s screen-related notes and this doc together.

## Where things stand (facts, measured 2026-09-02)

PtCon 12S screen: 995 accessions, complete. congruent 919, incongruent 12,
insufficient_independent_evidence 63, not_evaluated_oversized 1 (`HM561627`
-- the new long-sequence mechanism firing in production for the first time).
18S has NOT been screened under the current machinery.

**How the verdict is currently computed** (`.compute_hierarchy_congruence()`
+ the flag assignment in `evaluate_reference_accessions()`):

    n_independent_top_matches < min_independent_partners (3)
        -> "insufficient_independent_evidence"
    frac_independent_below_min_congruent_rank >= hierarchy_incongruent_threshold (0.5)
        -> "incongruent"
    else "congruent"

    frac = (k_disagree + 0.5) / (n_independent + 1)     # Jeffreys-smoothed

A partner "disagrees" when it shares NO rank at `min_congruent_rank`
(default family) or finer. So the verdict is a MAJORITY VOTE OVER THE TOP-N
NEIGHBOURS, and percent identity never enters it. `best_agreeing_pident`,
`best_disagreeing_pident`, `congruent_evidence_exists_anywhere` and
`congruent_evidence_best_pident` are diagnostics added later (2026-08-07
Opus consult) that NOTHING in the flag consults.

**Consequence, measured on the real PtCon run:**

| set | accessions | observations affected |
|---|---:|---:|
| all flagged incongruent | 12 | 1,688 |
| no corroboration anywhere (defensible removals) | 4 | 16 |
| agreeing evidence beats the disagreement (likely FPs) | 5 | 1,158 |

`remove_incongruent_references()` (which the PtCon/Mugu workflows call, with
LLM-review overrides) would therefore risk deleting the references behind
~1,158 observations of well-supported local species -- cabezon
(`OK172573`, 1,120 observations, agreeing hit at 100%, disagreeing at 96.79)
foremost -- to protect 16. The count rule reproduces the documented
Stereolepis false-positive mode at scale: in a thinly-covered clade the
top-5 neighbours are cross-family by construction even when the accession's
own conspecific matches at 100%.

Ecosystem position already on record (2026-08-07): `flag_incongruent_
references()` (annotate, never remove) is the RECOMMENDED default;
`remove_incongruent_references()` was demoted to a deliberate post-review
opt-in. The workflows are on the demoted path.

## Thread 1: recursive screening (the Askoldia problem)

`Askoldia variegata` (`MT627596`, itself `insufficient_independent_evidence`,
best hit 100%) is the disagreeing partner in 4 of the 12 incongruent
verdicts; `Radulinus boleoides` in 2 more. An unvetted reference is voting
local species toward deletion.

User's proposal: an accession removed as a likely error must not be used to
evaluate other references -- "just discounting removed references from the
count." Mostly right; the slot is `is_valid_partner` in
`.compute_hierarchy_congruence()` (already ANDs independence, coverage and
`is_species_resolved_y`), so a `is_trusted_y` term drops straight in.
Design questions it raises:

- **Fixpoint, not one pass.** Removing partners changes `k_disagree` AND
  `n_independent_top_matches` for everyone else, which can flip verdicts in
  both directions -- including pushing an accession below
  `min_independent_partners` into `insufficient_independent_evidence`
  (a verdict that is retryable, not removable, so this is a safe direction
  but changes counts). Iterate to a fixpoint with an iteration cap, and
  make the result order-independent (deterministic) or it is not
  reproducible.
- **Cascade risk.** Mutual disagreement between two dubious accessions can
  remove both, or oscillate. Needs an explicit rule (e.g. only accessions
  whose own verdict is a CONFIDENT removal may be discounted; never
  discount on `insufficient_*`).
- **Binary vs weighted.** Discounting is a hard 0/1. A weight
  (`trust in [0,1]`, see Thread 2) generalises it and avoids cliff effects:
  a partner's vote is scaled by its own label confidence.
- Cost: recomputation is local (no new BLAST), so iteration is cheap.

## Thread 2: a label verdict + an action column

User's proposal: (a) a column stating whether the LABEL is correct
(correct / incorrect / uncertain), and (b) a column interpreting ALL the
evidence into an action (keep / remove / inspect / caution ...), possibly
numeric rather than categorical.

Endorsed, with these design points:

- **Separate evidence from action** -- this ecosystem's own precedent
  (TaxaFlag's `observation_validity` numeric + `validity_flag` categorical;
  TaxaHabitat's classify-then-review `flag_institution_candidates()`).
- **Make the label verdict numeric** (`label_confidence` in [0, 1], or a
  posterior probability that the label is correct) and DERIVE the
  categorical action from documented thresholds. The numeric is what
  Thread 3 consumes; the categorical is for humans. Categories alone
  would throw away exactly the gradation the downstream model wants.
- **Polarity convention** (documented, load-bearing here): in this
  ecosystem HIGH = MORE concern for `*_risk`/`*_confusion_risk` names.
  Either follow it (`mislabel_risk`) or name it `label_confidence` and be
  explicit that high = good. Do not repeat the `*_support` inversion.
- **An evidence-gated rule is available today** and would fix the harm
  described above without any new machinery:
  `congruent_evidence_exists_anywhere == FALSE AND (is.na(best_agreeing_
  pident) | best_disagreeing_pident > best_agreeing_pident)` selects
  exactly the 4 defensible PtCon removals and spares all 1,158. Whether
  this becomes the flag itself, a second column, or the workflow-level
  filter is the open decision.
- **Cache discipline**: additive columns are safe; CHANGING `hierarchy_flag`'s
  meaning is not (`.EVAL_REF_ACC_VERSION`, `params_key` -- a bump forces a
  full re-BLAST of ~1,163 cached rows across GreatLakes/PtCon; the
  2026-08-25 note explains why that was reverted once already).

## Thread 3: reference quality as a covariate in likelihood modeling

User's framing: the likelihood models currently assume references are
correct AND that a match means something; a poor match to an UNCERTAIN
reference should worry us less than a poor match to a CERTAIN one.

This is the deferred "quality covariate" thread from 2026-07-10
([[project_quality_covariate_deferred]]) reaching its natural moment, and
**the mechanical slot already exists and is validated**:
`TaxaLikely::evaluate_likelihoods(evidence_col=, evidence_max_ratio=)`
rescales H1 sigma by `1/sqrt(evidence_ratio)` per candidate, gated by the
closed-form crossover criterion (`-0.5*log(c) + 0.5*z^2*(1 - 1/c) > 0`)
added 2026-07-14 after the unconditional version measured net-negative
(27 helped / 2,053 hurt) and the gated version measured 163 helped / 3 hurt
on real 12S.

Why this matters for the design:

- That gate ALREADY encodes the user's intuition formally: widening a
  candidate's sigma only pays off when the observed score sits far from the
  trained mean (large z) -- i.e. exactly for a POOR match. A poor match to
  a low-confidence reference gets forgiven; a good match is unaffected.
- The existing axis is QUERY evidence (read depth, per observation).
  Reference quality is a DIFFERENT axis (per candidate/accession) but
  enters the same multiplicative slot; the two could combine as a product
  of ratios, which needs a decision and a test.
- Principle to preserve (Session 157): reference quality should widen
  UNCERTAINTY, never shift the MEAN. A dubious reference makes us less
  sure, it does not make the species less likely a priori.
- Open: is per-accession quality the right granularity, or per-candidate-
  taxon (a taxon whose references are collectively dubious)? A taxon's
  candidates may draw on several accessions of differing quality.
- Validation path: the same harness used for the sigma gate -- real 12S
  PtCon/GreatLakes, count helped vs hurt against held-out signal, not a
  synthetic test.

## Suggested order

1. Thread 2's evidence-gated rule (smallest, fixes real harm now).
2. Thread 1 (recursive/weighted partner trust) -- needs Thread 2's numeric.
3. Thread 3 (downstream covariate) -- needs Thread 2's numeric too, and its
   own validation run.

Immediate safety valve regardless of schedule: switch the PtCon and Mugu
workflows from `remove_incongruent_references()` to
`flag_incongruent_references()`, or add the evidence gate at the call site.

## Status

- 2026-09-02: written. Threads 1-3 not started, no verdicts taken.
- 2026-09-02, same day: the **immediate safety valve is IN** (user-approved).
  Both call sites (`PtConceptionWorkflow_12S_single_site.R`,
  `MuguFishWorkflow.R` -- the only two workflows that call
  `remove_incongruent_references()`) now add an evidence-gated spare list to
  `override_accessions` alongside the LLM review's own overrides. An
  accession is removed ONLY when nothing anywhere corroborates its label AND
  something better-matching contradicts it:
  `congruent_evidence_exists_anywhere %in% TRUE |
   (!is.na(best_agreeing_pident) & (is.na(best_disagreeing_pident) |
    best_agreeing_pident >= best_disagreeing_pident))` -> spared.
  VERIFIED against the real 995-accession PtCon evaluation: 12 incongruent
  -> 8 spared (1,666 observations, cabezon included), 4 removed
  (16 observations: Cryptacanthodes maculatus, Rathbunella hypoplecta,
  Jordania zonope, Zaniolepis frenata -- exactly the no-corroboration set).
  This is a CALL-SITE filter only; `hierarchy_flag`'s own definition and the
  cached verdicts are untouched, so Thread 2's question (should the package
  itself carry an evidence-gated verdict column?) remains fully open.
- 2026-09-02, later the same day (Opus 5, branch `kernel-priors`): **all three
  threads IMPLEMENTED**, verdicts taken as recorded below. The call-site filter
  above is DELETED from both workflows -- it now lives in the package, so there
  is one definition of the rule.

## Verdicts taken (2026-09-02)

**Thread 2 -- ADDITIVE, not a redefinition.** `hierarchy_flag` keeps its exact
meaning and cached values. `TaxaMatch::score_reference_labels()` (new, exported)
adds `label_confidence` (numeric, HIGH = the label is more likely CORRECT --
named for its direction rather than following the `*_risk` convention),
`label_identity_margin`, and `reference_action`
(`keep`/`caution`/`inspect`/`remove`/`untested`). All three are a PURE FUNCTION
of columns already in the cache, derived post-hoc at the end of
`evaluate_reference_accessions()` -- the trick `listed_taxon_is_species`
already used. No `.EVAL_REF_ACC_VERSION` bump, no re-BLAST, existing
PtCon/GreatLakes caches gain them instantly, and changing `margin_scale` costs
nothing. Formula:

    logit(label_confidence) = logit(1 - frac_independent_below_min_congruent_rank)
                              + d / margin_scale
    d = (best_agreeing_pident, else congruent_evidence_best_pident)
        - best_disagreeing_pident,   capped to +/- margin_cap (5)

i.e. one percent-identity point of margin = one unit of log-odds at the default
`margin_scale = 1`. That is the ONE free parameter, and it is a stated
convention, not a fit. `"remove"` carries two HARD VETOES: only `"incongruent"`
is removable at all, and corroborating evidence anywhere spares the accession
however low its number. `remove_incongruent_references(gate = c("action",
"flag"))` defaults to the action gate; `"flag"` restores the old behaviour.

On the real 995-accession PtCon cache: 919 congruent -> all `keep`; the 12
incongruent -> 4 `remove` (exactly the no-corroboration set), 3 `inspect`,
3 `caution`, 2 `keep` (cabezon `OK172573` at 0.892 among them).

**Thread 1 -- implemented, with a blocker the brief above did not know about.**
The per-partner votes were built, summarised and DISCARDED, so no verdict could
be recomputed without a fresh BLAST. `.compute_hierarchy_congruence()` now
carries them out as an attribute and `evaluate_reference_accessions()` persists
them to a sidecar `reference_pair_cache.rds`.
`TaxaMatch::refine_reference_verdicts()` runs the trust-weighted fixpoint over
them: weighted (not binary) discounting, deterministic by construction (Jacobi
sweep + id_y tie-break), iteration cap, and the cascade guard the brief asked
for -- never discount on `insufficient_*`, and never on `congruent` either
(shaving ordinary partners to 0.999 would flip an accession with exactly three
of them below `min_independent_partners` on rounding alone).

**Askoldia was not the culprit.** `MT627596`'s own row reads
`insufficient_independent_evidence` with a 100% agreeing hit and nothing
disagreeing -- `label_confidence` 0.999. The cascade guard correctly leaves it
at full weight: it is an under-evaluated partner, not a likely error, and the
family-level disagreement it registers is real in a thin clade. The mechanism
is right; this accession was not what it looked like.

No existing cache has pair rows, so `refine_reference_verdicts()` is a
documented no-op on PtCon/GreatLakes until those accessions are re-evaluated.
The full re-BLAST is postponed by decision;
`diagnostics/partner_trust_small_test.R` is the small-subset live-NCBI exercise
that stands in for it (two BLAST stages: the 12 flagged accessions, then the
partners that actually voted against them -- previously unknowable, since only
the disagreeing taxon's NAME was ever stored -- then the fixpoint over the
union). NOT YET RUN.

**Thread 3 -- built as a diagnostic, deliberately not adopted.**
`TaxaLikely::evaluate_likelihoods(reference_quality_col=)` multiplies the
quality ratio into the query-evidence ratio and applies the closed-form
crossover gate ONCE to the product (separately per factor would let a jointly
harmful rescale through). The granularity question is answered by existing
machinery: `flag_incongruent_references()` joins `label_confidence` per
accession, and `evaluate_likelihoods()` already medians it to the candidate
taxon exactly as it does `coverage`. Emitted as
`raw_likelihood_refq`/`score_likelihood_refq`; `score_likelihood` unchanged.
Both workflows now pass the column so the validation run becomes possible.
Real-data smoke check (not the validation): on 400 PtCon observations touching
a sub-0.75 reference, 20 of 457 H1 rows moved, 19 of them UP -- the forgiveness
direction, and rare, as the gate implies.

## 2026-09-02, small test RUN -- and it found a verdict-stability problem

`diagnostics/partner_trust_small_test.R` ran end to end against live NCBI
(exit 0): 15 accessions in stage 1, 40 disagreeing partners in stage 2,
776 pair rows cached, fixpoint converged in 8 iterations over 55 accessions.

**Thread 1's own result: 0 actions changed.** The weighting is live, not
inert -- `OR582690` (Zaprora silenus) moved 0.642 -> 0.462 with
`n_effective_partners` 3.698, i.e. partners were genuinely discounted -- it
simply does not move any accession across a threshold here. Askoldia kept
full weight exactly as the cascade guard predicts.

**The unexpected finding: the same accession gets a different verdict one day
apart under an IDENTICAL `params_key`.** Comparing the fresh run against the
PtCon cache rows written 2026-09-01:

| accession | PtCon (09-01) | fresh (09-02) |
|---|---|---|
| `OP056918` Cryptacanthodes maculatus | no agreeing hit, `anywhere = FALSE`, conf 0.001 -> **`remove`** | four conspecific hits at 100%, `congruent`, conf 0.923 -> **`keep`** |
| `NC_066931` Apodichthys flavidus | best agreeing 97.22 in top-5, conf 0.210 | no agreeing hit in top-5, conf 0.053 |
| `OR582690` Zaprora silenus | conf 0.642 | two conspecific hits at 100% |

`OP056918`'s four corroborators (`PZ284804`/`PZ284806`/`PZ284809`,
`PX704709`) were deposited 2026-01-12 and 2026-04-26 -- they were in GenBank
months before the PtCon screen ran, so this is NOT a database that grew. They
are also full mitogenomes (~16.5 kb), the same shape as the query, so it is
not a short-vs-long query-length artifact either.

**Two consequences that matter more than Thread 1:**

1. The "4 defensible removals" figure this whole document is built on is NOT
   stable. `OP056918` is one of those 4, and on the very next day it reads
   `congruent`/`keep` with 100% conspecific corroboration. Treat it as a
   likely false positive. The evidence gate and the numeric machinery are not
   at fault -- the INPUT evidence changed.
2. `"incongruent"` was cached INDEFINITELY. That policy assumed an incongruent
   verdict cannot be overturned, and this run showed it can, so a wrong
   `"incongruent"` from one unlucky BLAST call was permanent -- in the one
   verdict that is acted on destructively. **FIXED 2026-09-02**: new
   `incongruent_ttl_days` (default 30). The TTL is now per-flag and the
   asymmetry follows what each verdict CLAIMS -- `"congruent"` asserts
   evidence WAS found (nothing later can withdraw an observed match, so still
   cached forever); `"incongruent"` asserts it was NOT found, a statement about
   absence, which is exactly what later evidence overturns. 30 << 180 because
   the thing that goes stale underneath the verdict is NCBI's `nt` snapshot,
   rebuilt days-to-weeks (see the repeatability-probe section below), and
   because `"incongruent"` is ~1% of a real population -- simultaneously the
   most valuable and the cheapest recheck. `incongruent_ttl_days = Inf`
   restores the old policy.

   **Caveat for the existing caches**: the PtCon incongruent rows are dated
   2026-08-30/09-01, so under the 30-day default they will not be retried until
   the end of September. To act on this sooner, either pass a short
   `incongruent_ttl_days` for one call, or surgically drop the non-congruent
   rows from `reference_accession_cache.rds` -- the same manoeuvre this file's
   own `.EVAL_REF_ACC_VERSION` comment records doing before, and cheaper than a
   version bump because it re-BLASTs 12 accessions rather than 995.

**The log inconsistency: CHASED, ROOT-CAUSED, FIXED -- and it is NOT the cause
of the instability.** The impossible pair of log lines ("extracted the amplicon
from 40 of 40 over-length" then "feature-table fallback rescued 40 of 40
still-over-length") had a precise cause: the 2026-09-01 caller tested an
already-primer-trimmed query against `resolve_barcode_lengths()$max_bp`.
`.trim_queries_to_amplicon()` returns a primer-INCLUSIVE span (211-233 bp for
MiFish-U); `max_bp` reports the variable region EXCLUDING primers (130-210 bp).
The windows are DISJOINT, so every correctly-trimmed query was called
"still over-length", 100% of the time. Measured on the real 15-accession set:
13 of 15 misclassified before the fix, 1 of 15 after (the one genuine
primer-extraction failure the fallback exists for).

It is the same bug twice: `.trim_queries_to_amplicon()` was itself fixed for
this exact miscalibration on 2026-08-10, and the 2026-09-01 caller reintroduced
it. The remedy is structural -- `.resolve_trimmed_span_max()` is now the one
definition both sites read. A second fix in the same area:
`.extract_feature_table_fallback()` now refuses a span that does not FIT the
sequence in hand, instead of silently clamping to `substr(seq, 1, seq_len)` and
counting an untouched sequence as a rescue.

**But it does not explain the verdict flip.** Verified directly: the fallback
was returning the trimmed sequence UNCHANGED, so the correct ~217 bp amplicon
was always what went to BLAST. The fix removes a wasted NCBI annotation
round-trip per chunk and makes the log honest; it changes no verdict.

## 2026-09-02, repeatability probe: BLAST is NOT the unstable part

`diagnostics/blast_verdict_repeatability_probe.R` evaluates the same 12
accessions three times back to back, each into its own fresh cache directory so
no replicate can be served from cache. Result:

- **All 12 accessions: identical verdict AND identical diagnostics in all 3
  replicates.**
- **All 12 hit sets identical, Jaccard 1.000 across replicates** -- not one
  partner accession differed anywhere (14-20 valid partners each).

So the two leading hypotheses are dead. It is not within-run nondeterminism in
NCBI's hit selection, and it is not degraded results under CPU pressure --
BLAST is exactly reproducible at a fixed `params_key` within a session.

The second hypothesis is dead too: the corroborating records' GenBank
`create-date` AND `update-date` are both 2026-01-12 / 2026-04-26, so they were
not released or revised recently. They had been public in Entrez for months.

**What is left, and it fits every observation:** NCBI's `nt` BLAST database is
a periodically-rebuilt SNAPSHOT, not the live Entrez/nuccore database. A record
public in nuccore since January need not be present in the `nt` volume BLAST
searches until a rebuild that includes it. That explains stability within a
day, change between days, and records that were public earlier. It cannot be
verified retrospectively -- there is no way to ask what `nt` contained on
2026-09-01 -- so this is the surviving explanation, not a proven one.

**Consequence: the flip was the screen getting BETTER, not misbehaving.** The
09-02 verdict is the correct one; the 09-01 verdict was correct given what
`nt` then contained. That reframes the whole finding -- there is no correctness
bug to chase in this pipeline -- and it makes `incongruent_ttl_days` exactly
the right fix rather than a mitigation, because the thing that goes stale is
precisely the database snapshot the verdict was computed against.

**It also sets the TTL's VALUE, and that is now DECIDED: 30 days.** `nt`
rebuilds run on the order of days to weeks, so a TTL much longer than the
rebuild interval keeps serving a stale `"incongruent"` long after the evidence
that overturns it became searchable -- the exact failure the TTL exists to
prevent. Hence 30, not the 180 of the "we do not know yet" flags. The recheck
costs ~1% of an accession population (12 of 995 on PtCon), and a test pins the
default so a future change to it is deliberate.

## 2026-09-02, Thread-3 validation run: INCONCLUSIVE, and it found a scale defect

`diagnostics/validate_reference_quality_covariate.R` (new, fully offline) is
the harness. Design, so it is not re-derived: ground truth is
`identify_confident_observations()` -- observations whose genus has exactly one
locally-plausible species in the occurrence priors, so the species call is
fixed by geography and the likelihood never enters it. The metric is the
MARGIN of the correct species over its best competitor (both columns are
normalised within an observation, so a correct candidate already winning reads
1.0 in both and would look unchanged). `evidence_col` is deliberately not
passed, isolating reference quality. Pre-registered criteria: helped:hurt
>= 10:1, plus a veto on any correct->wrong winner flip.

**It reports 34:1 helped and zero flips, and that number means nothing.** Two
reasons, both printed by the script's own power check:

**1. `label_confidence` never reaches 1, so nothing is ever a true no-op.**
The ceiling is the Jeffreys-smoothed vote plus the capped margin: a PERFECTLY
corroborated 5-partner reference scores 0.99939, not 1.0. Fed to a slot that
treats the value as an evidence ratio, that is a 0.03% sigma widening applied
to every candidate in the dataset. `reference_quality_col`'s own `@param`
promises "1 means a fully corroborated reference, which is the no-op" -- the
scale cannot deliver it. **279 of the 408 moved H1 rows have
`label_confidence > 0.99`**: they moved because of this artefact, not because
their reference was dubious. Only **5** moved rows have `label_confidence <
0.25`, the population the covariate exists for.

The fix is the one `evidence_col` already has and this axis lacks: a BASELINE.
`evidence_col` divides raw read depth by `reference_evidence`; reference
quality divides by nothing. Dividing `label_confidence` by the confidence a
maximally-corroborated reference with the same partner count would achieve
(computable per row, and it cancels the n-dependence of the Jeffreys ceiling),
capped at 1, makes a clean reference exactly 1.0. NOT IMPLEMENTED -- it changes
what the covariate means and belongs to a decision.

**2. The covariate is genuinely very sparse, independent of that defect.** It
acts only where a candidate BOTH rests on a dubious reference AND sits far
enough from its trained mean for the crossover gate to fire -- and those rarely
co-occur, because a query that matches a dubious reference *well* is near the
mean and correctly left alone. Ground-truth observations 6,429; those with a
genuinely low-confidence candidate 528; overlap 315; of that overlap, **3**
actually moved. Arm B (the exactly-0.5 "no evidence" accessions, 723
observations) moved nothing at all, so the open question of whether absence of
evidence should widen sigma is still untested rather than answered.

**Verdict: INCONCLUSIVE, not PASS.** The script now fails a third,
power criterion (>= 20 moved observations in the measured-low arm) and says so
rather than reporting the flattering ratio. `score_likelihood_refq` stays a
diagnostic. Next steps, in order: fix the scale so a clean reference maps to
1.0; re-run; if arm A is still this thin, this dataset simply cannot decide and
the test needs a reference set with more dubious accessions -- GreatLakes, or
18S, which has never been screened under the current machinery at all.

## 2026-09-02, scale fixed + consult: the covariate now measures something

Consulted Fable on the mapping from `label_confidence` to a variance ratio.
Its verdict, adopted: **(a) and (b) are not rivals, they are different layers**
-- (a) is a units fix belonging in TaxaMatch, (b) a semantics fix belonging in
TaxaLikely -- and given how sparse the covariate is, do (a) now and record (b).

**Implemented (a): `label_quality`, a second, MODEL-facing column.**
`label_confidence` is unchanged and stays the human-facing probability; 0.9994
genuinely IS the right answer from 5 partners, and rounding it to 1 to suit a
consumer would make it dishonest. `label_quality` divides it by the ceiling a
maximally-corroborated reference with that row's own partner count could
achieve, capped at 1. The split is FORCED, not stylistic: the ceiling needs
`n_independent_top_matches`, and by the time `evaluate_likelihoods()` sees a
quality value it has been medianed per candidate taxon and n is gone. Only
TaxaMatch can compute it. Consumers point at `label_quality`, never
`label_confidence`.

A bonus the normalisation buys: it removes the n-dependence. A reference that
is maximally corroborated FOR THE EVIDENCE IT HAS scores exactly 1 whether it
had 2 partners or 20 -- real case `Askoldia variegata` (`MT627596`), 2
partners, one 100% agreeing hit, `label_confidence` 0.99866, ceiling for n=2
also 0.99866, `label_quality` exactly 1 and correctly a no-op.

**Zero-partner rows are now `NA`, a documented no-op.** Their 0.5 is a Jeffreys
vote fraction with ZERO votes, not a calibrated P(label correct) -- 98.7% of
the accessions this screen actually evaluated came back `"congruent"`, so the
base rate for an unexamined label is nowhere near a coin flip, and feeding 0.5
widened sigma 41% on the strength of an absence. The rule keys on `n == 0`,
NOT on `hierarchy_flag`: an accession with 1-2 partners reads
`"insufficient_independent_evidence"` but does have real evidence, and the
ceiling normalisation already handles small n correctly.

**Re-run result.** Moved H1 rows 408 -> 30, and the ceiling artefact is gone
(0 moved rows now have quality > 0.99, vs 279 before). Arm B is empty by
construction. Every moved observation is now genuinely in arm A: **20 moved,
20 helped, 0 hurt, no winner flips**, clearing all three pre-registered
criteria including the power floor.

**Do not over-read that.** The crossover gate guarantees a widened candidate's
own density never falls, so anything that moves, moves UP -- the correct
species being widened is help BY CONSTRUCTION. Harm can only arise when a
WRONG candidate rests on the dubious reference and is widened past the correct
one, and that configuration exists in **5** ground-truth observations in the
entire dataset (it was exercised -- 5 of the 25 moved rows widened a wrong
candidate -- so the test is not blind to it, just nearly powerless). "0 hurt"
against 5 opportunities is a weak safety claim. The harness now prints this
exposure asymmetry every run so the ratio cannot be read naively.

**Recommendation: keep `score_likelihood_refq` a diagnostic.** The help side is
now real and measured; the safety side is not yet tested at any scale. Re-run
on GreatLakes or 18S when either is screened for its own reasons, and adopt
only if the harm side has genuine exposure there.

## Recorded, deliberately NOT built

**(b) the mixture-variance mapping, with its free parameter eliminated.** The
"label is wrong" distribution is already trained -- it is H2. Moment-matching
the mixture's second moment about the FIXED H1 mean (Session 157 forbids moving
the mean) gives:

    c_refq = p + (1 - p) * (sigma2^2 + (mu1 - mu2)^2) / sigma1^2

exactly 1 at p = 1 by construction, with the bad component's mean shift
honestly converted into spread. Every quantity is already fitted, so there is
no `sigma_wide` knob for `arbitrariness_audit.md` to register beyond the choice
of H2 (rather than H3) as the bad component -- the conservative,
smallest-inflation choice. Belongs inside `.calc_likelihoods()` where
`use_mu`, `use_sigma` and the H2 params are all in scope, combined as
`c_total = c_evidence * c_refq` with the gate applied once. Build this only if
the covariate ever earns adoption.

**The generatively exact treatment**, for completeness: not a widened Gaussian
at all but the explicit two-component density
`p*N(mu1, sigma1^2) + (1-p)*N_H2(x)`, which needs no gate because the diffuse
component supplies the forgiveness. It multiplies a PERFECT match's density by
~p, i.e. punishes good matches to dubious references. Defensible (a perfect
match to a probably-wrong label is evidence for the disagreeing taxon) but it
crosses this project's deliberate forgive-only line and the hard lesson of the
27:2053 experiment. Noted, not proposed.

**A units discrepancy in PRE-EXISTING code, found by the consult and verified.**
`use_sigma[1,1]` is a VARIANCE (`model_sd_score <- sqrt(global_sigma[1,1])`;
`z_sq` divides by it un-squared). But the coverage inflation reasons in SD --
"SE(logit) proportional to 1/sqrt(N_aligned) ... so sigma_eff = sigma /
sqrt(coverage)" -- and applies `/sqrt(coverage)` to the variance slot. If
SE is proportional to 1/sqrt(N) then variance is proportional to 1/N, so the
variance factor should be `1/coverage`. Same shape for the evidence axis
(`1/sqrt(ratio)`). Nothing is broken: the gate treats `c` as the variance
factor consistently throughout, so the mechanism is self-consistent, merely
weaker than its own stated derivation implies. **DO NOT "fix" this casually** --
the evidence axis was validated at 163 helped / 3 hurt AT THIS STRENGTH, so
changing it invalidates that result. It is a comments-vs-code discrepancy
needing its own decision and its own re-validation.

**This thread is a re-entry of a CLOSED one.** `[[project_mislabel_probability_weighting_closed]]`
(2026-08-08) closed graded P(mislabeled) weighting after an Opus consult
returned "don't build it", citing a ~1% effect and, verbatim, sigma-widening
being "structurally blocked by a mechanism already shipped" -- the gate. The
Thread-3 measurement is that prediction confirmed on independent machinery. Any
future session proposing reference quality as a likelihood covariate should
read that closure FIRST.

**Why the sparseness is structural, not a property of this dataset.** The
target population is an intersection of four conditions, three of which the
ecosystem itself shrinks: dubious references are ~1-8% of accessions;
`remove_incongruent_references()` DELETES the worst of them, cannibalising
exactly the accessions this covariate exists for and leaving the
moderately-dubious spared set where honest inflation is small; the crossover
gate restricts action to tail matches, and a query matching a dubious reference
WELL is near the mean by definition; and then it intersects with a deliberately
small truth set. A different dataset moves only the first of those.

## 2026-09-02, FINAL: Thread 3 REMOVED from the packages (user decision)

Threads 1 and 2 are kept and integrated. **Thread 3 -- reference quality as a
likelihood covariate -- is deleted from the code.** `TaxaLikely/R/evaluate.R`
is byte-identical to its pre-session state (`reference_quality_col`,
`refq_vec`, `raw_likelihood_refq`, `score_likelihood_refq` and their tests all
gone); `label_quality` and `.label_confidence_ceiling()` are gone from
TaxaMatch; `diagnostics/validate_reference_quality_covariate.R` is deleted;
both workflows no longer pass the covariate. Nothing in either package
consumes reference quality as a likelihood input.

**Before proposing it again, read this and
`[[project_mislabel_probability_weighting_closed]]` (2026-08-08), which had
ALREADY closed the idea** -- predicting a ~1% effect and sigma-widening
"structurally blocked by a mechanism already shipped" (the crossover gate).
The 2026-09-02 measurement confirmed that prediction on independent machinery.
That is two independent closures now.

The findings worth keeping, none of which require the code:

- **`label_confidence` cannot reach 1.** Jeffreys floors the disagreement
  fraction at `0.5/(n+1)` and the identity margin is capped, so a perfectly
  corroborated 5-partner reference scores 0.99939. Correct for a human-facing
  probability. But ANY future consumer that reads it as a ratio where 1 means
  "no adjustment" must normalise by the per-row achievable ceiling
  (`plogis(qlogis(1 - 0.5/(n+1)) + margin_cap/margin_scale)`) first, or it
  silently adjusts every candidate in the dataset. That normalisation also
  cancels the n-dependence -- maximally corroborated FOR THE EVIDENCE IT HAS
  scores exactly 1 whether n was 2 or 20.
- **Zero-partner rows must be a no-op, not 0.5.** Their 0.5 is a Jeffreys vote
  fraction with zero votes, not a calibrated P(label correct); the base rate is
  98.7% congruent among evaluated accessions. Key that decision on `n == 0`,
  not on `hierarchy_flag` -- 1-2 partners is thin evidence, not no evidence.
- **The sparseness is structural.** Dubious references are ~1-8% of accessions;
  `remove_incongruent_references()` deletes the worst, cannibalising the target
  population; the gate only fires on tail matches, and a query matching a
  dubious reference WELL is near the mean. A different dataset moves only the
  first of those.
- **The (b) mixture-variance design with its free parameter eliminated** (H2 is
  the already-trained "label is wrong" distribution;
  `c = p + (1-p)(sigma2^2 + (mu1-mu2)^2)/sigma1^2`) is recorded above. It is
  the right shape IF this is ever revisited -- but the reason not to build it
  was never the mapping.

## What is still open

1. ~~The Thread-3 ADOPTION decision.~~ CLOSED: removed from the packages,
   2026-09-02. Superseded text follows for the record.
1-old. The Thread-3 adoption decision. The scale defect is fixed and the re-run
   clears all three criteria (20 helped / 0 hurt), but only 5 ground-truth
   observations could possibly have been hurt, so the safety side is untested.
   Re-run on GreatLakes or 18S when either is screened; adopt only if the harm
   side has real exposure there. `score_likelihood_refq` stays a diagnostic
   until then. If the harm side is thin there too, write the closure doc on the
   `widen_blast` precedent and retire it as an adoption candidate.
1b. The variance-vs-SD units discrepancy recorded above -- its own decision,
   and it would require re-validating the evidence axis.
2. ~~`diagnostics/partner_trust_small_test.R` has not been run against live
   NCBI.~~ RUN 2026-09-02 -- see the section above. It raised two NEW open
   items: whether `"incongruent"` should get a TTL, and the amplicon-trimming
   count inconsistency.
3. The full PtCon/GreatLakes re-BLAST that would give Thread 1 pair data at
   scale -- postponed, not cancelled.
3b. ~~**The verdict instability itself.**~~ RESOLVED 2026-09-02 by
   `diagnostics/blast_verdict_repeatability_probe.R` -- BLAST is exactly
   reproducible (3/3 replicates, Jaccard 1.000 on every hit set), so the
   surviving explanation is an `nt` snapshot rebuild between the two dates.
   No correctness bug -- and the mechanism set the TTL's value:
   `incongruent_ttl_days` defaults to 30, matching the `nt` rebuild cadence.
   Nothing outstanding on this item.
4. `margin_scale = 1` is a convention. If a labelled set of genuinely
   mislabeled accessions ever exists, it is fittable.
5. Whether a candidate taxon whose references are COLLECTIVELY dubious wants
   its own treatment, distinct from the per-accession median.

## 2026-09-04: the removal veto is TRUNCATION-BLIND (measured)

This document's entire removal argument rests on
`congruent_evidence_exists_anywhere` -- the hard veto that spares an accession
however low its `label_confidence`. That column is documented as walking the
full independence-filtered pool, "not limited to top_n". It is still limited by
`max_hits` (default 20), and on the real PtCon 12S screen **899 of 989
accessions (91%) come back AT that cap**. So "anywhere" has always meant
"anywhere in the top 20", and the doc-vs-code gap was never noticed because the
column's own name and roxygen both say otherwise.

This matters more now than it would have on 2026-09-02: the primer-stripped v5
re-run cut `reference_action == "remove"` from 4 accessions to 2, so the veto
carries nearly the whole destructive decision.

`diagnostics/veto_truncation_probe.R` (new) re-evaluates the veto-critical
accessions at `max_hits = 100`, into its own cache dir. `max_hits` is in
`params_key`, so this cannot collide with production. Live result, 15
accessions (5 incongruent + 8 zero-partner insufficient + 2 congruent
controls):

| finding | count |
|---|---:|
| `congruent_evidence_exists_anywhere` flipped FALSE -> TRUE | **8 of 15** |
| `reference_action` changed | 8 |
| no longer removable | 1 (`OQ846263`) |
| controls unchanged | 2 of 2 (probe sound) |

- **`OQ846263` (*Rathbunella hypoplecta*) is one of the only two PtCon
  `"remove"` accessions, and at 100 hits it is no longer removable** -- it
  drops to `"inspect"`. The removal set halves again, 2 -> 1.
- **`KM057967` (*Jordania zonope*) still reads `"remove"` at 100 hits.** That
  is the right answer -- 2026-09-03 established it as a genuine singleton whose
  apparent corroborator matched over 5.6% overlap -- and it is what makes the
  `OQ846263` result credible: the probe discriminates, it does not simply flip
  everything it widens.
- **7 of the 8 zero-partner `"insufficient"` accessions resolved to
  `"congruent"`** (*Stenella attenuata* x5, *Homo sapiens* x2). So `max_hits`,
  not the submission-batch independence filter, is what was starving them --
  which also partly answers the separate "what should `insufficient` mean"
  question. `MH177754` (*Gorilla beringei*) still reads 0 partners at 99 hits;
  that one is genuinely filtered, not truncated.

**Caveat, and it is not a small one: all 15 come back at 99-100 hits.** 100 is
also a truncated window. This establishes that the veto is truncation-
SENSITIVE; it does not establish where the sensitivity ends, and a run at 500
could move more.

**Deliberately NOT acted on.** Raising the `max_hits` default would change
`params_key` and invalidate every cached row across PtCon and the three
GreatLakes caches (~3,000 rows, the expensive kind). That is a user decision.
The options, in rough cost order: (a) leave the default and pass
`max_hits = 100` only for a deliberate pre-removal audit of the handful of
accessions that would actually be removed; (b) decouple the "anywhere" walk
from the verdict's own hit budget, so the veto sees a wider pool than the vote
without changing what the vote is computed from -- this is the principled fix,
since the two questions genuinely want different windows, but it is a real
design change and `params_key` would have to reflect it; (c) raise the default
and pay the full re-BLAST.

**Do not confuse this with
`[[project_widen_blast_unsupported_candidates_closed]]`** (2026-08-26), which
measured 0/22 flagged ASVs ever hitting `max_hits = 20` and closed the idea.
That was the MATCH path (`blast_sequences()` on ASVs); this is the reference
SCREEN, where saturation is 91% rather than 0%. The closure's evidence does
not transfer, in either direction.

## 2026-09-04: what "insufficient_independent_evidence" is actually made of

It is the largest non-congruent population in every real screen and nothing had
ever looked at it -- every prior thread went after `"incongruent"`, which is
~0.5% of a population and merely the only verdict acted on destructively.

**The offline decomposition splits it exactly in two, with no overlap, in four
independent caches:**

| cache | insufficient | zero-partner | 1-2 partners |
|---|---:|---:|---:|
| PtCon (live v5 key) | 34 | 17 | 17 |
| GreatLakes goal2 | 13 | 7 | 6 |
| GreatLakes Plate1 | 27 | 24 | 3 |
| GreatLakes pilot | 79 | 50 | 29 |
| **total** | **153** | **98** | **55** |

Two invariants hold across all 153 rows with **zero exceptions**:

1. **Every row with at least one valid partner has corroborating evidence**
   (55/55 `congruent_evidence_exists_anywhere == TRUE`, PtCon median best
   agreeing identity 98.2%). It reads `"insufficient"` only because the VOTE
   wants `min_independent_partners` (3). `reference_action` already reads
   `"keep"` for every one of them, so the harm is confined to the flag's own
   name -- it says "insufficient evidence" about accessions that have evidence.
2. **Every zero-partner row has none** (0/98), scores `label_confidence`
   EXACTLY 0.500, and reads `reference_action = "caution"`.

That 0.500 is not a measurement. With no valid partners,
`frac_independent_below_min_congruent_rank` falls back to its 0.5 default and
the identity margin is `NA`, so `plogis(qlogis(0.5) + 0) = 0.5` -- a prior with
zero data, landing squarely in the `"caution"` band (0.25-0.75). The screen is
therefore reporting concern earned by an absence, against a base rate of
931/989 congruent. This is the same defect recorded on 2026-09-02 under
"zero-partner rows must be a no-op, not 0.5" -- that note was written about the
(since deleted) likelihood covariate and was never applied to
`label_confidence`/`reference_action` themselves, where it is still live.

## The truncation test, and what it does NOT explain

`diagnostics/insufficient_evidence_probe.R` re-evaluated all 34 PtCon
insufficient accessions at `max_hits = 100` (sharing the veto probe's cache, so
8 were free). Result:

- **12 of 34 (35%) are no longer `"insufficient"`** -- they read `"congruent"`.
- Zero-partner arm: **7 of 17 resolved**, and all 7 moved `caution -> keep`.
  Those seven are the five *Stenella attenuata* (`KX8572xx`/`KX8573xx`, one
  sequential submission batch) plus two *Homo sapiens*. So for a
  batch-dominated clade, the independence filter was correct AND the
  independent partners existed -- just past rank 20.
- 1-2 partner arm: 5 of 17 resolved.
- **But 21 of 34 gained NO hits at all when the window quintupled.** Their
  thinness is real and no widening will fix it: *Chilara taylori*,
  *Hypsoblennius gilberti*, *Leiocottus hirundo*, *Neoclinus blanchardi*,
  *Rhinogobiops nicholsii*, *Ruscarius creaseri*, *Typhlogobius
  californiensis*, *Gorilla beringei* and two more *Homo sapiens* are genuine
  singletons in `nt` at this marker.
- 13 of 34 are still saturated at 100 hits, so 100 is not the end of it either.

**Reading:** truncation is a real but MINORITY cause -- about a third. This is
the second independent line of evidence that `max_hits = 20` is too tight for
this screen (the first being the removal veto, same day), and the two together
are the case for revisiting that default. But it is NOT the whole story, and a
`max_hits` change alone would leave ~65% of the population exactly where it is.

## What this means for the flag's meaning

The invariants above survive the widening (after it, every partnered row still
reads `keep` and every zero-partner row still reads `caution`), so the split is
structural rather than incidental to one dataset. Three candidate changes, in
increasing order of how much they touch:

1. **`label_confidence = NA` when `n_independent_top_matches == 0`**, which
   flows through the existing `is.na(label_confidence) -> "untested"` rule and
   makes those rows read `"untested"` instead of `"caution"`. This is the
   change the evidence most directly supports: it stops the screen reporting
   concern it has not earned, it reuses machinery already present, it keys on
   `n == 0` rather than on `hierarchy_flag` (as the 2026-09-02 note insisted),
   and it is a derived post-hoc column, so no cache is invalidated. Cost: it
   changes a shipped column's values -- PtCon 17 rows, GreatLakes 81 --
   and `"untested"` currently means "never submitted to BLAST", which these
   accessions WERE. That second meaning would have to widen to "no usable
   evidence was obtained", which is defensible but is a real redefinition.
2. **Split the flag** into a genuinely-thin case and a corroborated-but-
   under-partnered case, so the name stops contradicting the diagnostics for
   the 55 partnered rows. Cost: a new `hierarchy_flag` value is additive, but
   this one would REPLACE `"insufficient_independent_evidence"` on real rows
   rather than sitting beside it, which is the kind of change
   `.EVAL_REF_ACC_VERSION` exists to gate.
3. **Leave it.** Defensible on the grounds that `reference_action` -- the
   column consumers are told to read -- is already correct for all 55
   partnered rows, and that the flag is accurate about the vote it names.
   The cost is that the 98 zero-partner rows keep reading `"caution"`.

RECOMMENDATION: (1) alone. It fixes the only case where the current output
actively misleads (concern from an absence), costs nothing in cache terms, and
leaves the flag's own definition untouched. (2) is a rename in search of a
problem now that `reference_action` is the documented consumer surface. NOT
BUILT -- this is a decision, and it is the user's.

## 2026-09-04: three verdicts taken, all implemented

The user was asked for three decisions and took the recommended option on each.

**1. Zero-partner rows -> `"untested"`.** `label_confidence` is now `NA` when
`n_independent_top_matches == 0`, which flows through the existing
`is.na() -> "untested"` rule. Keyed on the partner COUNT, not on
`hierarchy_flag`, exactly as the 2026-09-02 note insisted. Derived post-hoc
column, so no cache was invalidated. Real effect: 98 rows move
`caution -> untested` (PtCon 17, GL goal2 7, GL Plate1 24, GL pilot 50), and
PtCon's `"caution"` band drops 21 -> 4 -- it now means mixed evidence rather
than no evidence. `"untested"` correspondingly widens from "never submitted to
BLAST" to "no usable evidence obtained"; both routes are documented in
`score_reference_labels()`'s new `@section No partners is not a coin flip`.

**2. `max_hits` stays at 20; audit instead.** New exported
`TaxaMatch::verify_removal_candidates()` re-evaluates ONLY the accessions
actioned `"remove"` at a wider window (default 100) and reports which stop
being removable. Zero NCBI calls when nothing would be removed. It compares its
own `params_key` against the production evaluation's and warns, naming the
fields, if anything but `max_hits` differs -- a caller who forgets to forward
`barcode_term` otherwise gets a comparison that means nothing, which is the
specific failure this guard exists for. It also returns `still_saturated` per
row, so a "still removable" verdict from a row that was itself at the audit cap
is read as the weaker claim it is.

Raising the default was declined on cost: `max_hits` is in `params_key`, so it
would re-BLAST ~3,000 rows across four caches for a screen that has been
NCBI-throttled before -- and the insufficient-evidence probe showed truncation
explains only ~35% of that population, so it would not have been a fix anyway.

**3. `OQ846263` spared in production.** Added to
`PtConceptionWorkflow_12S_single_site.R`'s `override_accessions` as
`VETO_AUDIT_SPARED`, with the `verify_removal_candidates()` call that
supersedes the hardcoded vector written out in the comment above it. The PtCon
removal set is now 1: `KM057967` (*Jordania zonope*), which still removes at
100 hits and should -- it is the genuine singleton whose apparent corroborator
matched over 5.6% overlap.

**What is still open on this thread.** 13 of 34 PtCon insufficient rows are
saturated at 100 hits too, so 100 is not where the truncation question ends;
the 21 of 34 that gained no hits at all when the window quintupled are
genuinely thin and no widening helps them. GreatLakes and Mugu have still never
been live-run on the v5 amplicon path, so none of the four probes' numbers have
a GreatLakes counterpart yet -- and GL Plate1's zero-partner population (24 of
27 insufficient, dominated by *Phoxinus* and *Etheostoma*) has a different
shape from PtCon's, so it should not be assumed to behave the same way.

## 2026-09-04: the GreatLakes audit found a FALSE RESCUE -- read this before trusting `spared`

`verify_removal_candidates()` was run on GreatLakes' two removal candidates
(2 BLAST calls). Result, and it cuts both ways:

| accession | taxon | at 20 hits | at 100 hits | corroborators |
|---|---|---|---|---|
| `KJ135626` | *Pseudorasbora parva* | remove | **inspect (spared)** | **1**, at species rank |
| `NC_028197` | "Serranidae sp. JL-2015" | remove | remove (still saturated) | 0 |

**The `KJ135626` rescue is spurious, and the LLM reviewer was right.** Its sole
corroborator is `MZ605481` -- which this project's own
`diagnostics/reference_accession_ground_truth.csv` records as a
`candidate_mislabel` whose real identity is *Cyprinus carpio* (20 independent
carp accessions at 100%, coverage-enforced). `KJ135626`'s own best DISAGREEING
hit is also *Cyprinus carpio* at 100%. The two accessions are almost certainly
the same error twice -- carp sequence carrying the *P. parva* name --
corroborating each other. `review_flagged_accessions()` independently called
`KJ135626` `"genuine_mislabel"` at high confidence, and that is the better
answer. **Do NOT add it to `override_accessions`.**

`NC_028197` is already in the LLM overrides
(`"hybrid_or_specimen_code_artifact"`, high confidence) so it is not actually
removed in production, and it is separately caught by
`listed_taxon_is_species = FALSE`. GreatLakes therefore needs no workflow
change at all from this audit.

**The mechanism finding, which generalises.**
`congruent_evidence_exists_anywhere` counts a corroborating partner with no
notion of whether that partner's own label is trustworthy, so one mislabel can
rescue another. `refine_reference_verdicts()` cannot close this: it discounts a
partner by that partner's OWN verdict, and a corroborator that is merely a
BLAST hit -- not itself in the screened population -- has no verdict to
discount. Widening `max_hits` makes the exposure LARGER, not smaller, because
it admits more potential bad corroborators. This is a real limit on the
"audit before removing" strategy, not a reason to abandon it.

`verify_removal_candidates()` now returns `n_corroborators`,
`best_corroborator_rank` and `corroborators` (the strongest few, named), and
prints an explicit CHECK THESE BY HAND warning for any row spared on 1-2
partners. On re-running the GL audit it names `MZ605481` unprompted -- the
thing that had to be dug out by hand.

**A correction to the PtConception result recorded above.** `OQ846263` was
described as "corroborated"; be precise about what that means. Its evidence is
7 INDEPENDENT Bathymasteridae records at 97.6% agreeing at FAMILY rank, not a
conspecific match. That is legitimate under the rule's own definition
(agreement at `min_congruent_rank` or finer) and 7 independent partners is not
a single-source rescue, so the spare stands -- but it is weaker evidence than
the earlier wording implied, and the difference between it and `KJ135626` is
exactly what the new columns exist to show.
