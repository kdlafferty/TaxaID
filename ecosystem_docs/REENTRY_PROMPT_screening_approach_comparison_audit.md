# Reentry prompt: empirical audit -- does the new BLAST-based reference screen
# catch what the old pairwise-matrix screen catches?

**Status: COMPLETE, 2026-08-08.** Answered using data already on disk from a
2026-08-07 session (this doc's original "design-only, not started" header,
written the next day, was stale -- the raw materials for most of this plan
already existed: the real, full 10,701-accession GreatLakes 12S audit, a
120-accession stratified comparison sample, and a real BLAST-based
`evaluate_reference_accessions()` run against it). No new BLAST/NCBI calls
were made; all numbers below come from
`diagnostics/greatlakes_screening_approach_comparison_analysis.R`, a clean,
reproducible script built for this audit (verified to run end to end,
matches every number below).

## RESULTS

**Population-level (real, full 10,701-accession GreatLakes 12S DB, no
sampling):** `flag_reference_errors()` flags 220 accessions (2.06% of the
nominal DB; 5.06% of the 4,347 accessions it can actually evaluate --
59.4% of the nominal DB never enters its pairwise matrix at all,
`excluded_from_alignment`, and gets no verdict either way).

**On the 132-accession sample actually evaluated by BOTH tools** (a
stratified, suspect-enriched sample, not representative of the true
population rate above): old flags 30/132 (22.7%), new flags 5/132 (3.8%) --
confirms the user's own observation qualitatively, but this specific 22.7%
number should not be read as a population rate (see above: true old
population rate is 2-5%, not 23%). Overlap is very low: only 2 accessions
are flagged by BOTH; 28 are old-only; 3 are new-only. Jaccard = 0.061.

**Old-only flags (28): the same-submission-batch hypothesis is real but
only PART of the answer.** 11/28 (39.3%) are confirmed same-submission-batch
artifacts (via `.same_submission_batch()`, accession-number/date proximity
between an accession and whatever gave it its `max_foreign_match`) --
exactly the PV382872-class false-positive mode
`evaluate_reference_accessions()`'s independence filter exists to close.
The remaining 17/28 (60.7%) are NOT batch artifacts, but share a distinct,
second false-positive mode: a small negative `integrity_gap` (median -0.03
to -0.12 -- self-match only marginally below max foreign match) against a
tight congener (`Cephalopholis`, `Epinephelus`, `Phoxinus` -- all
documented cryptic-species-rich genera), where
`evaluate_reference_accessions()`'s broader, independent-evidence-based
check finds real corroborating same-species matches elsewhere in GenBank
(`congruent_evidence_exists_anywhere = TRUE`, `best_agreeing_pident`
98-100% in nearly every case) that `flag_reference_errors()`'s narrow
same-database self-vs-max-foreign comparison structurally cannot see.
**Both are real, distinct false-positive mechanisms** -- an independence
filter alone would fix the first but not the second.

**New-only flags (3: X99194, PV382872, AY949420): a genuine structural
blind spot in `flag_reference_errors()`, not really a "narrower population"
miss.** All three are SINGLETONS in the old approach's own reference
database (`n_self_neighbors = 0`) with `max_foreign_match` well below
`flag_reference_errors()`'s `singleton_match_threshold` (default 0.98) --
0.926-0.931. Under that rule's own stated logic, `error_type = "clean"` is
technically correct: these accessions never got close enough to a genuinely
alarming near-duplicate match to trip the singleton rule. But 2 of the 3
disagree with independent BLAST evidence only at CLASS rank
(`finest_common_rank`), a real taxonomic red flag a hierarchy-congruence
check catches and a flat percent-identity threshold cannot express at all.
Notably, the ARCHIVED DECIPHER hierarchy check (a different, no-longer-live
mechanism) already flagged all three `"incongruent"`/`"blacklist"` too --
so this isn't a novel finding at the ecosystem level, but it does confirm
`evaluate_reference_accessions()` reproduces a real signal
`flag_reference_errors()` alone structurally lacks.

**Ground-truth cross-check: zero disagreements on adjudicated cases.** On
every one of the 10 real, already-adjudicated GreatLakes 12S accessions
present in this database -- including the one genuine `candidate_mislabel`
positive control (`MZ605481`, flagged by BOTH tools) and the 4 real Menidia
accessions -- old and new agree. Notably, the famous "Menidia false
positive" that originally motivated the whole BLAST-based redesign was
**never actually a `flag_reference_errors()` problem**: `error_type =
"clean"` for all 4 Menidia accessions, correctly. That false positive was
specific to the archived DECIPHER `classify_reference_accessions()`
taxon-list-scoped hierarchy check, a design that was abandoned before ever
reaching production -- so relative to the REAL old approach
(`flag_reference_errors()`), that motivating case doesn't apply as an
old-vs-new comparison at all. All divergence between the two live tools is
concentrated in the un-adjudicated old-only/new-only buckets above, which
this audit resolves for the large majority of cases.

## What this means (answers this doc's own "What done looks like")

Both hypotheses are true, for different subsets, as the doc anticipated:
- **~39% of old's extra flagging is a real structural false-positive mode**
  (no independence filter) -- confirms the reentry doc's own hypothesis.
- **~61% of old's extra flagging is a SEPARATE, larger false-positive mode**
  (naive self-vs-max-foreign comparison fooled by tight congeners) that an
  independence filter alone would NOT fix -- only a broader, corroborating-
  evidence check (what `evaluate_reference_accessions()` already does) does.
- **Old also has a real, if narrow, blind spot** (singletons with only
  moderate, coarse-rank-only foreign similarity) that new correctly closes.

**Recommendation:** since a same-submission-batch independence filter alone
would only address the smaller of old's two false-positive modes, adding
one to `flag_reference_errors()` (the "smaller, more surgical fix" this doc
originally floated) is not well-supported as a full fix by this evidence.
`evaluate_reference_accessions()` should be the recommended pre-training
screen going forward; if `flag_reference_errors()` is kept as a cheap
first-pass filter, its output should be treated as high-recall/low-precision
(worth a review pass, not an auto-blacklist) given the ~2-of-30 (6.7%)
precision observed here against the new tool's own verdict.

## Explicitly not resolved by this audit

- The true new-tool population-wide flag rate is unknown -- BLAST cost
  makes a full 10,701-accession `evaluate_reference_accessions()` run
  expensive; only the 132-accession sample above has real new-tool verdicts.
  A larger (but still sampled) run would tighten this if it matters later.
- No second real, confirmed species-identity mislabel positive control was
  found (still just `MZ605481`, per the ground-truth file's own note).
- The formal P(mislabeled)/likelihood-weighting design questions (Q1/Q2) --
  separate document, separate thread, untouched here.

---

Written 2026-08-08, prompted directly by the user
after the `investigate_flagged_accession()` live-debugging session (see
`REENTRY_PROMPT_investigate_flagged_accession_prefilter_group_posthoc.md` and
`TaxaMatch/CLAUDE.md`'s 2026-08-08 top session note): "our previous approach seems to
screen out a higher percentage" of reference sequences than the new accession-based one.
This is Q3 of a three-question thread the user raised; see the sibling doc
`REENTRY_PROMPT_mislabel_probability_and_likelihood_weighting.md` for Q1/Q2 (a formal
P(mislabeled) and folding it into likelihood computation) -- deliberately split into a
separate document because this one is a pure empirical comparison, not a design question,
and doesn't need Opus.

## What "old" and "new" actually mean here -- confirmed, not assumed

Before drafting this, it wasn't obvious which of THREE candidate "previous approach"
mechanisms in this ecosystem the user meant:

1. `TaxaLikely::flag_reference_errors()` (`R/train.R`) -- still ACTIVE, still wired into
   the real training pipeline today (`inst/workflows/2_flag_errors_workflow.R`;
   `train_likelihood_model()`'s own `reference_errors` output slot is auto-computed from
   it; `run_bayesian_pipeline()` auto-uses it).
2. `TaxaLikely::audit_reference_database()`/`classify_reference_accessions()` -- the
   DECIPHER whole-set-alignment approach, **archived** (`TaxaLikely/archive_decipher_
   reference_audit/`, deliberately `.gitignore`d) after a 2026-08-06/07 design session
   found real false positives (15 genuine Smithsonian-vouchered `Menidia` accessions
   flagged incongruent purely because `Menidia`'s family had no other representative on
   a caller's own 6-genus taxon list) and a structural false-negative gap.
3. `TaxaMatch::evaluate_reference_accessions()` -- the NEW accession-based BLAST tool
   this session's own work extended (`investigate_flagged_accession()`,
   `check_marker_mismatch()`).

Checked `TaxaLikely/CLAUDE.md` directly rather than guessing: (2) is dead code, not a
live comparison target. **(1) is the real "previous approach"** -- it's what the user's
own description matches exactly ("we first check for self v non-self matches and from
this we remove several reference sequences from the modeling data," i.e. right before
`train_likelihood_model()` runs, via `remove_flagged_references()`). Confirm this
reading with the user before spending real time on this audit if there's any doubt --
but proceed on this basis unless corrected.

## The two mechanisms, precisely

### Old: `TaxaLikely::flag_reference_errors()` + `remove_flagged_references()`

Operates on `build_sequence_matrix()`'s own pairwise distance matrix -- i.e. the
comparison population for any one accession is **whatever else is in the SAME training
reference database's own pairwise matrix**, not a broad, independent search. Computes,
per accession (`id_x`):
- `median_self_match` -- median score to within-species neighbours in this same matrix.
- `max_foreign_match` -- best score to any cross-species neighbour in this same matrix.
- `integrity_gap = median_self_match - max_foreign_match`.
- `n_self_neighbors`.

Flags:
- `"likely_mislabeled"` when `integrity_gap < -mislabel_threshold` (default `0.02`) AND
  `n_self_neighbors > 0`.
- `"unverified_singleton_high_match"` when `n_self_neighbors == 0` AND
  `max_foreign_match > singleton_match_threshold` (default `0.98`).
- `"clean"` otherwise.

**Has no same-submission-batch independence filter at all.** This is the concrete,
testable hypothesis worth checking first (see below) -- `evaluate_reference_
accessions()`'s whole independence-filter mechanism (`.build_submission_batch_lookup()`/
`.same_submission_batch()`) exists specifically because raw top hits can be same-batch
artifacts that look like severe mislabeling but aren't (the real `PV382872` case that
motivated `investigate_flagged_accession()` in the first place -- see that function's
own roxygen `@section Why this exists`: "PV382872's top hits (an eel, a catfish, a
parasitic isopod, all at ~99.5% identity) looked alarming... until direct verification
showed they were all from the SAME real submission batch as the query itself").
`flag_reference_errors()` has no equivalent defense. If PV382872 (or a similar
same-batch-artifact case) is in a real training reference database, `flag_reference_
errors()` would very plausibly flag it `"likely_mislabeled"` on the strength of its
same-batch neighbours alone -- a real, structural over-flagging risk the new mechanism
was specifically designed not to have.

Also worth checking: `min_coverage` (a real, separate param on `flag_reference_errors()`,
added later specifically to avoid a same-length-but-non-overlapping-region false
positive) -- confirm whether the real production reference databases below actually SET
this, or leave it at the default `NULL` (no coverage gate at all), before concluding
anything about over-flagging.

### New: `TaxaMatch::evaluate_reference_accessions()` + `flag_incongruent_references()`/
`remove_incongruent_references()`

BLASTs each accession against a broad, unrestricted database (`nt` by default), applies
the same-submission-batch independence filter, computes a Jeffreys-smoothed
`frac_independent_below_min_congruent_rank` and classifies `hierarchy_flag` as
`"congruent"`/`"incongruent"`/`"insufficient_independent_evidence"` (needs
`n_independent_top_matches >= min_independent_partners`, default `3L`, or reads
insufficient). See `TaxaMatch/CLAUDE.md`'s 2026-08-07 top-of-file notes for the full
design record, including the real Abylopsis ambiguous case and the 5 identity-diagnostic
columns (`best_hit_pident`/`best_agreeing_pident`/`best_disagreeing_pident`/
`congruent_evidence_exists_anywhere`/`congruent_evidence_best_pident`).

## Concrete audit plan

1. **Pick a real, already-audited dataset with a cached `reference_df`/`seq_matrix`.**
   The GreatLakes 12S reference database is the most extensively real-tested in this
   ecosystem (per `TaxaLikely/CLAUDE.md`'s repeated hierarchy-congruence/repair-thin-
   evidence sessions -- 3,557-10,701 accessions depending on which session's snapshot).
   PtConception 12S is the second-best-documented real option. Confirm with the user
   which cached checkpoint (`AuditNCBI.R`'s own saved `.rds` files, outside this
   monorepo) is actually available and current before committing to one.

2. **Run `flag_reference_errors()`** on that dataset's real `seq_matrix` (already
   computed by `build_sequence_matrix()` as part of the existing audit pipeline -- no
   new alignment needed). Record `error_type` counts and the flagged accession list.

3. **Run `evaluate_reference_accessions()`** on the SAME set of accessions (this is a
   real cost -- one BLAST call per accession; use the existing persistent cache,
   `cache_dir` default `tools::R_user_dir("TaxaMatch", "cache")`, so a re-run doesn't
   re-pay it). Record `hierarchy_flag` counts and the flagged accession list.

4. **Compare directly:**
   - Total flagged-as-suspect count/percentage under each (old: `error_type %in%
     c("likely_mislabeled", "unverified_singleton_high_match")`; new: `hierarchy_flag ==
     "incongruent"` -- decide whether `"insufficient_independent_evidence"` counts as
     "flagged" for this comparison; it arguably shouldn't, since it isn't a positive
     mislabel claim, just an absence of enough evidence either way).
   - Overlap: flagged by both / old-only / new-only / neither. A Jaccard index is a
     reasonable single summary number, but the interesting content is in the two
     single-sided sets, not the overall overlap fraction.
   - **For a real sample of old-only flags** (accessions `flag_reference_errors()`
     calls suspect but `evaluate_reference_accessions()` doesn't): check directly
     whether they're same-submission-batch artifacts (the PV382872-class hypothesis
     above) -- pull each flagged accession's own `create_date`/accession-number
     proximity to whatever gave it its `max_foreign_match`, the same check
     `.same_submission_batch()` already does, by hand or via that exact helper. If a
     meaningful fraction turn out to be batch artifacts, that's the concrete answer to
     "why does old flag more" -- a real, structural false-positive source the new tool
     was built specifically to close.
   - **For a real sample of new-only flags** (accessions the BLAST-based tool calls
     `"incongruent"` but `flag_reference_errors()` missed): check whether these are
     real mislabels the OLD tool's narrower comparison population (limited to whatever
     else is in the SAME training reference database, not a broad NCBI search)
     structurally couldn't see -- e.g. a mislabeled accession whose true contaminating
     identity's species isn't present anywhere else in that specific training set at
     all. This is the flip side of the same structural difference and is exactly the
     kind of false-negative gap `evaluate_reference_accessions()` was built to close
     for the archived DECIPHER approach -- worth confirming it also applies here.

5. **Cross-check both tools' flagged/clean calls against the hand-curated ground truth**
   (`diagnostics/reference_accession_ground_truth.csv`, TaxaID root -- real confirmed
   mislabel `MZ605481`, real confirmed-correct-but-thin-coverage accessions, the real
   ambiguous Abylopsis pair, real Menidia accessions, `AY850362`'s real marker mislabel).
   Whichever ground-truth accessions happen to also be present in the chosen real
   reference database give a small but genuinely adjudicated spot-check, independent of
   the old-vs-new overlap analysis above.

## What "done" looks like

A clear, numbers-backed answer to: does the old approach flag more because it's
genuinely more sensitive (catching real problems the new tool misses), or because it has
a real structural false-positive mode (no independence filter) that the new tool doesn't?
Both could be true simultaneously for different subsets -- the old/new-only breakdowns
above are what would show that, not just the aggregate percentage. This directly informs
whether `flag_reference_errors()` should itself gain an independence filter (a much
smaller, more surgical fix than replacing it), whether `evaluate_reference_accessions()`
should become the recommended pre-training screen instead, or whether both should run
and their results reconciled (which is close to where Q1/Q2's formal P(mislabeled) work
would head anyway -- see the sibling document).

## Explicitly not in scope here

- Redesigning either mechanism -- this is a measurement task first.
- The formal P(mislabeled)/likelihood-weighting design questions (Q1/Q2) -- separate
  document, separate (Opus-flagged) thread.
- Any change to `flag_reference_errors()`'s or `evaluate_reference_accessions()`'s
  actual behavior, pending what this audit finds.
