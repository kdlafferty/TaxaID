# Reentry prompt: a formal P(mislabeled) for reference accessions, and folding it
# into likelihood computation

**Status: CLOSED 2026-08-08. Opus consult run same day; verdict: don't build graded
mislabel-probability weighting.** See `## Consult outcome (2026-08-08)` at the bottom
of this document for the full record, including two small adjacent items (a cache-TTL
fix; a conditional exposure-measurement follow-up) that came out of the same consult
but are explicitly NOT part of this closure -- flagged there, not attempted.

Written 2026-08-08, directly prompted by the user
after the `investigate_flagged_accession()` live-debugging session (see
`REENTRY_PROMPT_investigate_flagged_accession_prefilter_group_posthoc.md` and
`TaxaMatch/CLAUDE.md`'s 2026-08-08 top session note, which fixed a real, three-round
live-testing bug in the underlying comparison mechanism this design would build on).
This is Q1+Q2 of a three-question thread; Q3 (an empirical audit comparing the old and
new reference-screening approaches) is a separate, non-Opus document --
`REENTRY_PROMPT_screening_approach_comparison_audit.md`.

## The two questions, and why they're one document

**Q1.** Can we more formally assess the probability that a reference sequence is
correctly or incorrectly labeled, rather than the current categorical verdicts
(`hierarchy_flag`: `"congruent"`/`"incongruent"`/`"insufficient_independent_evidence"`)?

**Q2.** Can that probability feed into likelihood computation? The user's own concrete
framing: if a 97% match translates to a likelihood of 0.9 under
`train_likelihood_model()`'s bivariate-normal H1, but there's a 25% chance the reference
sequence backing that match is mislabeled, should the likelihood be adjusted -- and how?

These are one document because the right mathematical FORM for a P(mislabeled) answer
depends on how it needs to compose into TaxaLikely's existing shrinkage estimator --
designing Q1 in isolation risks producing a probability that's clean to interpret but
awkward or impossible to actually use in Q2, or vice versa.

## What already exists to build on

- `TaxaMatch::evaluate_reference_accessions()` -- per-accession diagnostics already
  computed (not yet a calibrated probability): `hierarchy_flag`,
  `frac_independent_below_min_congruent_rank` (a Jeffreys-smoothed fraction, itself
  already probability-shaped), `best_hit_pident`/`best_agreeing_pident`/
  `best_disagreeing_pident`, `congruent_evidence_exists_anywhere`.
- `TaxaMatch::investigate_flagged_accession()` -- deep-dive comparison for one flagged
  accession, now live-verified working (2026-08-08, after three rounds of real bugs
  found and fixed): `conspecific_comparison` (self-consistency identity/coverage vs.
  other real accessions of the SAME listed species) and `disagreeing_taxon_comparison`
  (cross-taxon identity/coverage vs. the specific species it's confused with). Real
  verified output for the ground-truth `MZ605481` case: self-consistency 3/3 accessions
  clearing coverage, mean 87.64% identity; cross-taxon 2/2 clearing coverage, mean
  99.42% identity. **Critically, this also names the specific `disagreeing_taxon`** --
  not just "this might be wrong" but "this looks like it's actually X."
- `diagnostics/reference_accession_ground_truth.csv` (TaxaID root) -- the ONLY real
  labeled data available to calibrate against: a real confirmed mislabel (`MZ605481`),
  real confirmed-correct-but-thin-coverage accessions, a real ambiguous pair
  (Abylopsis `KY594854`/`KX384617` -- deliberately NOT resolved one way or the other,
  see the 2026-08-07 Opus consult on that case, described as "a real identifiability
  problem from these two data points alone, not a smoothing/threshold problem"), and
  `AY850362` (a confirmed MARKER mislabel, not a species mislabel -- a different
  failure mode `check_marker_mismatch()` now screens for separately). **This is likely
  on the order of a dozen labeled cases, not hundreds** -- confirm the real count before
  assuming any calibration approach that needs real statistical power is viable.
- `TaxaLikely::train_likelihood_model()`'s Empirical Bayes shrinkage machinery --
  `H1_Lookup`'s per-species `mu_score`/`sigma_score`, shrunk toward the global mean via
  `w = N/(N+prior_weight)` where `N` is real within-species sequence/pair count. This
  is the existing, proven mechanism for "how much should one piece of reference
  evidence move a species' fitted distribution" -- any per-reference-sequence weight
  coming out of Q1 should probably enter HERE, not as a separate bolt-on.
- The binary alternative already shipped and explicitly flagged as provisional:
  `TaxaMatch::remove_incongruent_references()`/`TaxaLikely::remove_flagged_references()`
  both hard-drop an accession on a categorical verdict. Their own roxygen already says
  the graded version is real, agreed-on future work (`remove_incongruent_references()`'s
  own `@section Full-signal weighting is separate, later work`) -- this document is
  that work, finally being scoped.
- Precedent for exactly this reference-quality-degrades-confidence pattern already
  exists elsewhere in the ecosystem, worth reading before designing from scratch:
  `evaluate_likelihoods(min_coverage=)`'s `score_likelihood_cov` (inflates H1 sigma by
  `1/sqrt(coverage)`) and the Session 155/156 `evidence_col`/`score_likelihood_evidence`
  mechanism (inflates/deflates H1 sigma by evidence quality, gated by a closed-form
  crossover condition after an unconditional version was found net-negative on real
  data -- see `TaxaLikely/CLAUDE.md`'s Session 156 note for the full derivation). A
  mislabel-probability-driven sigma adjustment would be a close statistical cousin of
  both, not a new mechanism family.

## The user's own worked example, and the wrinkle worth flagging up front

"Score 97% -> likelihood 0.9, but 25% chance mislabeled -- adjust the likelihood?"

The naive reading is a simple discount/mixture: something like
`0.75 * L(H1 | correct reference) + 0.25 * (uncertainty term)`. But a plain discount
implicitly assumes we don't know what the reference is mislabeled AS -- and as of this
session, we often DO: `investigate_flagged_accession()`'s `disagreeing_taxon` names the
specific confused species. That changes the shape of the right answer from "shrink
toward uncertainty" (widen H1's sigma, roughly what `score_likelihood_cov`/
`score_likelihood_evidence` already do for other quality signals) to something closer
to a real two-component mixture: part of that reference's evidentiary weight
legitimately belongs to H1 for its claimed species, part legitimately belongs to a
competing H1-shaped hypothesis for `disagreeing_taxon`. Whether that's tractable to
wire into `train_likelihood_model()`'s existing per-species shrinkage without a
substantially bigger redesign (H1 is currently keyed by ONE species per training
sequence; a mixture-weighted sequence would need to contribute fractionally to TWO
species' `H1_Lookup` rows) is exactly the kind of structural question worth having
argued through by a second, harder-nosed pass before committing to an approach.

## Real open sub-questions to bring into the design session

1. **Where does P(mislabeled) actually apply -- training time or inference time, or
   both?** A reference sequence flagged probably-mislabeled could be down-weighted
   when `train_likelihood_model()` fits `H1_Lookup` (changes the fitted distribution
   itself, affects every future query against that species) OR could stay in training
   as-is and instead widen/adjust the likelihood at INFERENCE time for a specific query
   that happened to match closely to that one suspect reference (a `score_likelihood_
   cov`/`score_likelihood_evidence`-style per-query adjustment). These are genuinely
   different design directions with different costs and different failure modes, not
   two ways of saying the same thing.
2. **Can a genuinely useful calibrated probability be estimated from ~a dozen labeled
   cases at all**, or does the honest answer look more like the Abylopsis
   consult's own conclusion -- a real identifiability limit that no amount of clever
   smoothing removes, and the actionable output is a well-reasoned SCORE (like
   `frac_independent_below_min_congruent_rank` already is) rather than a claim of
   calibration this data can't support? If the latter, Q2's "how do we use it" question
   still stands, just with an uncalibrated-but-monotonic input instead of a true
   probability -- worth deciding explicitly rather than discovering mid-implementation.
3. **Does the mixture idea (using `disagreeing_taxon` as a real second hypothesis)
   generalize, or was `MZ605481` an easy case** (very high cross-taxon identity, a
   completely different, well-corroborated species) that won't hold for the harder,
   more ambiguous real cases (Abylopsis-shaped: high identity to a SISTER taxon, where
   "mislabeled" and "correct label, weak marker resolution" are not separable from the
   evidence alone)?
4. **How does this interact with `evaluate_reference_accessions()`'s existing
   asymmetric cache** (`"congruent"`/`"incongruent"` cached indefinitely,
   `"insufficient_independent_evidence"` expiring)? A continuous probability doesn't
   obviously map onto a binary cache-freshness rule the same way -- would need its own
   answer, not an assumed carryover.
5. **Interacts directly with Q3's audit** (`REENTRY_PROMPT_screening_approach_
   comparison_audit.md`) -- if that audit finds `flag_reference_errors()` and
   `evaluate_reference_accessions()` disagree substantially and for structurally
   different reasons (independence-filter false positives on one side, narrow-
   comparison-population false negatives on the other), a real P(mislabeled) design
   might need to reconcile BOTH signals, not just formalize the new tool's own verdict
   in isolation. Worth doing Q3 first, or at least in parallel, so this design isn't
   built on only half the available evidence.

## Why Opus

This is the same shape of problem as the 2026-08-07 Abylopsis consult (see
`TaxaMatch/CLAUDE.md`'s matching note): a real statistical identifiability question
resting on a genuinely small, hand-curated ground-truth set, where the risk of
over-fitting a clean-looking probability model to a dozen data points is real and easy
to miss from inside the same design session that built the diagnostics being calibrated.
That consult's own recommendation pattern (cheaper diagnostic fixes first, defer the
harder graded-weighting question) is direct precedent for treating this specific
question -- not the diagnostics themselves -- as the one worth a second, harder-nosed
pass. The user is a statistician who works design questions through concrete numeric
hypotheticals rather than accepting a plausible-sounding mechanism on the first pass;
a single-author design here risks the same failure mode the Abylopsis consult was
brought in to catch: a mechanism that looks reasonable and passes its own tests but
doesn't actually survive contact with how sparse the real ground truth is.

**Recommended framing for the consult:** put both Q1 (what should P(mislabeled) mean
and how should it be estimated from ~a dozen labeled cases) and Q2 (training-time vs.
inference-time application, and whether the `disagreeing_taxon` mixture idea is
tractable within `train_likelihood_model()`'s existing shrinkage machinery) in front of
Opus together, with this document's own worked example and open sub-questions as the
starting frame -- not asking for an implementation, asking for a critique of the design
space before one is chosen.

## Explicitly not in scope here

- Actually running the Q3 audit (separate document).
- Any code changes -- this is scoping for a design consult, not an implementation task.
- Extending this to non-DNA evidence types (image/acoustic classifiers have no
  equivalent "reference sequence mislabeled" concept -- this is scoped to the DNA
  reference-database pathway only, matching `flag_reference_errors()`'s own documented
  scope restriction).

## Consult outcome (2026-08-08)

Opus consult run same day (Sonnet 5 orchestrated, framed with this document's own Q1/Q2,
the worked example, all 5 open sub-questions, and the real confirmed ground-truth count
verified immediately before the consult: `diagnostics/reference_accession_ground_truth.csv`
has exactly 12 rows -- **0 confirmed mislabels, 1 unconfirmed candidate
(MZ605481), 2 deliberately-unresolved ambiguous, 4 known-correct-thin-coverage,
4 known-correct, 1 explicitly out-of-scope negative example**).

**Verdict: do not build graded P(mislabeled) likelihood weighting.** Not primarily
because of the ground-truth gap (real, but secondary) -- the numbers say the mechanism
itself doesn't work:

- **Training-time down-weighting is a ~1% effect, not a mechanism.** Worked against
  the real Mugu 12S model (`prior_weight=10`, median `n_obs_species=3`): a reference
  sequence's influence on its species' fitted `mu_score` is `1/(N+prior_weight)`;
  discounting a genuinely deviant reference to weight 0.75 moves the likelihood
  ~1% at z=1 sd. Even the hard-drop already shipped (`remove_incongruent_references()`)
  only moves it 4-9%. `build_sequence_matrix()`'s `max_dist=0.25` pair filter and the
  one-best-pair-per-sequence rule (`.prep_training_data()`) already double-bound this.
- **Sigma-widening is the wrong instrument, and the existing evidence_col crossover
  gate blocks it on exactly the case that matters.** A mislabel-driven false match
  (MZ605481-shaped) sits at z~0.187 sd -- essentially AT the trained mean, because a
  mislabel produces a GOOD match by construction. The gate (Session 156,
  `-0.5*log(c) + 0.5*z^2*(1-1/c) > 0`) blocks any variance rescale there at every
  plausible q (checked 0.10/0.25/0.50). Widening moves mass into the tails of the SAME
  hypothesis; a mislabel needs mass moved to a DIFFERENT hypothesis -- not
  approximations of each other.
- **Fractional dual-species membership in `H1_Lookup`** would need fractional
  `n_obs_species` (breaks `Var(mean)=w^2*sigma^2/n` and the H2/H3 uncertainty
  fallbacks) and a per-accession weight table `H1_Lookup`'s schema has no room for --
  a schema redesign for a ~1% effect. No.
- **The one mechanism with a real effect needs no probability at all**: admit
  `disagreeing_taxon` as a named competing hypothesis scoped to the affected
  observation, reusing the existing `attr(result, "regional_unreferenced")` ->
  `expand_unreferenced_hypotheses(unreferenced_df, observation_id=)` path already built
  2026-07-16 for the structurally identical Fundulus problem. Once the disagreeing
  taxon is on the ballot, the occurrence PRIOR does the discrimination for free (carp
  is invasive/widespread; the mislabeled claimant isn't) -- no weight required. This is
  reframed as "don't silently suppress the alternative," the same lesson this ecosystem
  has now learned three times independently (`apply_coverage_constraints()`'s
  `zero`->`relabel`, `filter_gbif_quality()`'s `exclude_institution`->
  `flag_institution`, `remove_incongruent_references()`->`flag_incongruent_references()`).

**Real failure modes surfaced that weren't in this document's own sub-question list**
(full detail in the consult transcript, not reproduced here):
1. Mislabels are batch-correlated by construction (why the independence filter exists
   at all) -- per-accession independent P(mislabeled) is backwards, not approximate.
2. 87/263 real Mugu species have exactly `n_obs_species=2` -- for those, any
   down-weighting doesn't grade, it drops the species' `H1_Lookup` row entirely (the
   same cliff as the hard-drop, not gentler).
3. Real double-counting risk: the ground-truth file's own MZ605481 note justifies
   "mislabel" partly via prior-side reasoning (carp is plausible there) -- if that
   plausibility later re-enters via `join_priors()`, it's counted twice.
4. No metric exists to validate this against (unlike every mechanism that has actually
   shipped in this ecosystem -- H1 win rate, helped/hurt counts, recall on known-high
   contaminants). Don't build a mechanism with no way to evaluate it.

**Two adjacent items from the same consult, deliberately NOT closed by this decision
(flagged for later, not attempted):**
- Key `evaluate_reference_accessions()`'s cache TTL on `n_independent_top_matches`
  rather than the binary verdict label -- the cache already stores the underlying
  evidence, so this is a cheap, unrelated correctness fix independent of the
  weighting question, matching this ecosystem's own `audit_reference_database()`/
  `classify_reference_accessions()` precedent (recompute-free threshold changes).
- Before ever revisiting graded weighting: measure real production exposure first --
  count observations across the 5 real workflows whose WINNING candidate's supporting
  accession is flagged incongruent. If that count is near-zero (plausible; the
  132-accession GreatLakes sample, deliberately enriched for flags, produced only 3
  new-only flags), the question is moot regardless of any calibration approach. This
  is also the only unbiased way to grow ground truth later (selecting cases by
  production impact, not by ease of adjudication -- the latter is exactly what makes
  the current 12-row ground-truth set structurally biased toward confirmable/easy
  cases).

See [[project_mislabel_probability_weighting_closed]] in the memory system for the
indexed record, and [[project_screening_approach_comparison_audit]] for the sibling
Q3 closure this document was always paired with.
