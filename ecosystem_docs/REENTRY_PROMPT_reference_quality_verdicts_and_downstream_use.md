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

- 2026-09-02: written. Nothing implemented. No verdicts taken.
