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
   `incongruent_ttl_days` (default 90). The TTL is now per-flag and the
   asymmetry follows what each verdict CLAIMS -- `"congruent"` asserts
   evidence WAS found (nothing later can withdraw an observed match, so still
   cached forever); `"incongruent"` asserts it was NOT found, a statement about
   absence, which is exactly what later evidence overturns. 90 < 180 because
   `"incongruent"` is ~1% of a real population, making it simultaneously the
   most valuable and the cheapest recheck. `incongruent_ttl_days = Inf`
   restores the old policy.

   **Caveat for the existing caches**: the PtCon incongruent rows are dated
   2026-08-30/09-01, so under the 90-day default they will not be retried until
   late November. To act on this sooner, either pass a short
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

**Open question it raises about the TTL's VALUE, not its existence:** `nt`
rebuilds run on the order of days to weeks, so a 90-day TTL can still serve a
stale `"incongruent"` for months after the evidence that would overturn it
became searchable. The recheck costs ~1% of an accession population (12 of 995
on PtCon). Shortening the default to ~30 days is cheap and better matched to
the mechanism now understood. Not changed unilaterally -- it is a cost
decision.

## What is still open

1. The Thread-3 validation run: helped-vs-hurt on real 12S PtCon/GreatLakes,
   the same harness the sigma gate itself had to pass (163/3). Until it runs,
   `score_likelihood_refq` stays a diagnostic.
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
   No correctness bug. What remains is the cost decision above: whether
   `incongruent_ttl_days` should default to 30 rather than 90.
4. `margin_scale = 1` is a convention. If a labelled set of genuinely
   mislabeled accessions ever exists, it is fittable.
5. Whether a candidate taxon whose references are COLLECTIVELY dubious wants
   its own treatment, distinct from the per-accession median.
