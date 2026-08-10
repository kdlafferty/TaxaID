# Reentry prompt: BLAST-based reference-accession quality evaluation

**Status: design fully worked through with the user across a long session
(2026-08-06/07), NOT YET IMPLEMENTED.** Nothing described below exists in
code yet except the archival step (moving the superseded approach out of
the shipped package -- done). This document is the handoff for whoever
builds it next, possibly a different session/model.

## Why the previous approach (DECIPHER whole-set alignment, taxon-list-scoped) was abandoned

`TaxaLikely::audit_reference_database()`/`classify_reference_accessions()`/
`repair_thin_evidence()` (built earlier the same session, then superseded
within the same session -- see `TaxaLikely/CLAUDE.md`'s session history for
the full incremental record: `min_coverage`/`min_coverage_floor` split,
primer-neutral `repair_thin_evidence()` scope widening, the O(n^2)
performance bugs found and fixed) all shared one structural constraint: the
"among"/foreign comparison population for ANY accession is *exactly* and
*only* whatever else got fetched under the caller's own `taxa` argument to
`audit_reference_database()`. There is no broader NCBI comparison anywhere
in that pipeline, for any accession, in either check.

The user identified (2026-08-06/07 design conversation) that this
invalidates the tool's own stated goal ("identify mislabeled references")
in two directions at once, both confirmed with real data before abandoning
anything -- **do not re-litigate this from scratch, the evidence already
exists**:

- **False positives** (real, found and live-verified this session): a real
  6-genus GreatLakes 12S test subset flagged 15 `Menidia`/`Menidia
  beryllina` accessions `"incongruent"`. Live NCBI lookup on 6 of them
  confirmed every one is a genuine, correctly-labeled, Smithsonian-vouchered
  specimen (USNM), all part of one real 2023/10/25 SERC Fish field-survey
  submission. Root cause: `Menidia` (family Atherinopsidae) was the *only*
  genus from that family anywhere in the 6-genus test list, so once the
  independence filter correctly excluded the whole same-day survey as
  non-independent, the hierarchy check had nothing real left to compare
  against except four completely unrelated families -- guaranteed to read
  "incongruent" regardless of whether the labels were right.
- **False negatives** (structural, confirmed by direct code-path tracing,
  not yet observed in real data but not in doubt either): a mislabeled
  accession's *true* identity is fetched by its claimed label, not its real
  sequence content, so it always enters `reference_df`. But if the true
  contaminating species' genus isn't on the `taxa` list, nothing genuinely
  resembling its real DNA exists to compare against -- it reads as an
  ordinary low-similarity-to-everything record. `max_foreign_match` stays
  low (no real foreign match found), `integrity_gap` doesn't go negative,
  and the hierarchy check has nothing independent to disagree with. **It
  reads `"clean"`.** Neither check can ever prove an accession is correctly
  identified in an absolute sense -- only "not contradicted by anything I
  happened to compare it against."

Both directions have the same root cause and the same fix direction: stop
bounding the comparison population by a hand-picked `taxa` list at all.

## The agreed design

**Core mechanism**: for a single accession, BLAST it against a broad,
unrestricted database (not scope-limited to any caller-chosen taxon list),
apply the *existing, validated* independence filter (same-submission-batch
exclusion -- this stays necessary regardless of scope, see below) to the
hits, then compute the same kind of Jeffreys-smoothed congruence verdict
`.compute_hierarchy_congruence()` already computed, just fed from real
BLAST hits instead of a `seq_matrix` built from a narrow fetch.

**This is genuinely a fix, not a workaround** -- it also happens to remove
the entire reason `min_coverage_floor`/`repair_thin_evidence()` needed to
exist: those existed specifically to compensate for one whole-set DECIPHER
MSA being unable to handle long-vs-short or narrow-window sequences
together. A per-accession BLAST search has no such constraint.

### Package placement: TaxaMatch, not TaxaLikely

Settled explicitly with the user, reversing an earlier recommendation.
Reasoning: this function's primary real use is editing/filtering the match
object, which must happen **before** `TaxaExpect` ever builds a taxon_name
list to generate priors for -- i.e. strictly upstream of any TaxaLikely
call. Since `TaxaMatch -> TaxaLikely` is the existing, documented
dependency direction in this ecosystem, and TaxaLikely must never depend on
TaxaMatch, the function has to live in TaxaMatch.

Two real costs of this the user explicitly accepted:

1. **`.build_submission_batch_lookup()`/`.same_submission_batch()`**
   (the same-submission-batch independence-filter helpers, needed
   regardless of comparison scope) currently live as internal,
   unexported helpers in TaxaLikely (now archived along with the rest --
   see below). To keep TaxaMatch genuinely independent of TaxaLikely,
   **duplicate these two small helpers (~30-40 lines) into TaxaMatch**
   rather than reach across packages via `:::`. This mirrors an
   *already-existing* precedent between these exact two packages:
   `.parse_lat_lon()` is deliberately duplicated between
   `TaxaLikely/R/fetch.R` and `TaxaMatch/R/blast_sequences.R` for the
   identical "small, pre-manuscript, not worth a shared-package
   extraction yet" reason. Follow that precedent, don't invent a new one
   (e.g. don't move these to TaxaTools mid-build -- that's a bigger
   decision the user hasn't asked for).
2. **TaxaMatch's own documented package purpose currently contradicts
   this.** `TaxaMatch/CLAUDE.md`'s "Package Purpose" section says
   verbatim: *"TaxaMatch does NOT perform score-to-likelihood conversion
   or reference quality checks — those functions live in TaxaLikely."*
   The user confirmed (explicitly, "2. yes") this boundary should be
   revised, framed narrowly: this is screening match data against
   reference quality *in service of producing a clean match object* (a
   natural reading of "standardizes match data"), not a wholesale
   takeover of reference-database auditing as a discipline. **Update
   that purpose statement when this is built** -- don't leave it
   silently contradicted.

### Evaluate, don't filter -- a real correction from the user mid-design

The core function is a **pure evaluator**. It computes and returns a
quality verdict per accession; it does not itself decide what to do with
that verdict. Two separate, later consumers:

1. **Early, narrow hard filter (TaxaMatch, right after evaluation)** --
   drops only confidently-blacklisted accessions from the match object.
   Mirrors the existing `remove_flagged_references()` pattern (which
   currently consumes `flag_reference_errors()`'s output) but fed from
   the new BLAST-based verdict instead.
2. **Graded weighting (TaxaLikely, later, NOT YET DESIGNED)** -- the full
   per-accession quality signal (not just the binary blacklist decision)
   needs to *survive* through to `evaluate_likelihoods()` so it can
   inflate/discount likelihood the same way `score_likelihood_cov`
   already does for alignment coverage. **This means the evaluation
   columns must propagate through the match object across every
   TaxaMatch/TaxaLikely transformation between the early filter and
   `evaluate_likelihoods()` -- don't let the early-filter step consume
   and discard the full signal.** This TaxaLikely-side consumption is
   real, agreed-on future work, explicitly NOT designed yet (no
   signature, no mechanism decided) -- flag it as its own task when
   picked up, likely modeled directly on `score_likelihood_cov`'s
   existing `1/sqrt(coverage)`-style sigma inflation.

### Caching, and why it's not just a performance optimization

The user's own framing, confirmed correct: within-call dedup
(`unique(accessions)` before evaluating, rejoin after) is necessary
regardless of caching -- never re-evaluate the same accession twice within
one call. A **persistent, cross-run cache** underneath that is what gives
this a real, compounding advantage over the old `AuditNCBI.R` design: the
cache is keyed by **accession**, not by taxon/genus/project, so scope grows
organically as real projects run -- a new project only pays evaluation cost
for accessions it references that are genuinely new or previously
out-of-scope everywhere else. No more choosing a `taxa` list up front.

**Cache staleness handled asymmetrically (user's explicit choice, option
"b" of two offered)**: confidently `"congruent"`/`"incongruent"` verdicts
are cached indefinitely (an accession's own sequence/label doesn't change
once deposited, so these are unlikely to flip). Only
`"insufficient_independent_evidence"` verdicts expire on a TTL and get
re-tried -- these are exactly the ones where new NCBI deposits could
genuinely change the answer. Don't build a flat TTL for everything; that
wastes BLAST budget re-checking things unlikely to have changed.

### Sketch signature (not finalized, starting point only)

```r
# TaxaMatch::evaluate_reference_accessions()
evaluate_reference_accessions(
  accessions,                              # character vector, deduped internally
  cache_dir = tools::R_user_dir("TaxaMatch", "cache"),
  insufficient_evidence_ttl_days = 180,
  top_n = 5L,
  min_congruent_rank = "family",
  submission_window = 5L,
  method = c("remote", "local"), database = "nt",
  score_range = 8, min_score = 70, max_hits = 20L,  # pass through to blast_sequences()
  verbose = TRUE
)
# returns: accession, listed_taxon, n_independent_top_matches,
#          n_top_matches_available, frac_independent_below_min_congruent_rank,
#          hierarchy_flag, evaluated_at, cache_hit
```

Both use cases become thin callers of this ONE function, not separate
mechanisms:

- **Use case 1 (primary): screen a real match object.**
  `evaluate_reference_accessions(unique(match_df$accession))`, then
  `dplyr::left_join(match_df, result, by = "accession")` -- same
  consumption shape `remove_flagged_references()` already establishes.
  Must run before any TaxaExpect/TaxaLikely call, right after
  `standardize_match_data()` (and whatever existing match-cleaning steps
  run today -- `filter_redundant_hypotheses()`, `add_lowest_consistent_
  rank()`, `convert_taxonomy_backbone()`).
- **Use case 2 (derivative): compile a standing white/black list.** Same
  function, called with a much larger accession list (e.g. everything
  `TaxaLikely::fetch_ncbi_reference_sequences()` pulls for a taxon list).
  No separate code path -- this naturally supersedes what `AuditNCBI.R`'s
  batch-audit half did, just without needing a `taxa` list decided in
  advance for correctness (still useful for *scoping* a first big
  compilation run, just not required for the check to be valid).

## What's been done this session (real, verified)

- The superseded approach's source moved OUT of the shipped package to
  `TaxaLikely/archive_decipher_reference_audit/` (both `R/` and `tests/`
  subfolders) -- **not deleted**, kept for reference. Added to both
  `.gitignore` and `.Rbuildignore` (not committed, not part of any future
  build). `.compute_hierarchy_congruence()`/`.build_submission_batch_
  lookup()`/`.same_submission_batch()` were extracted out of
  `TaxaLikely/R/train.R` into the archive as their own file
  (`hierarchy_congruence.R`); `train_likelihood_model()`/`.prep_training_
  data()`/`flag_reference_errors()`/`.compute_reference_qc_stats()` (the
  latter's `min_coverage`/`foreign_match_coverage`/`median_self_coverage`
  additions from this session) were all left in place -- they're real,
  independent, still-active mechanisms, not part of what's being
  superseded. `devtools::test()` 0 failures (952, down from 1081 --
  exactly the ~130 archived tests removed), `devtools::check()` 0/0/0,
  reinstalled and verified at `~/Library/R/4.0/library`.
- The external GreatLakes `AuditNCBI.R` script (outside this monorepo, not
  under git) got a loud header warning that it will now error if re-run --
  the underlying functions no longer exist in the installed package.
  `AuditNCBI_README.md` was NOT touched/marked -- still describes the
  superseded approach accurately for historical reference, but is now
  stale relative to the installed package. Not deleted; still useful
  background reading on the "two independent checks, don't fold into one
  score" design principle, which carries over to the new approach
  unchanged.
- Real supporting evidence gathered this session, useful context for
  whoever calibrates the new approach's parameters (`score_range`,
  `min_congruent_rank`, TTL, etc.): a real GreatLakes `min_coverage`/
  `min_coverage_floor` split showed 67% of a real 10,701-accession 12S
  fetch had ZERO `seq_matrix` presence at all (confirmed via live NCBI
  lookup to be overwhelmingly real mitogenome-scale records, median
  16,454bp, each genuinely carrying an annotated ~950bp 12S region); the
  primer-neutral `repair_thin_evidence()` scope-widening recovered 90.5%
  of thin-evidence accessions on a real 580-accession test (2,798 pairs
  added, `excluded_from_alignment` collapsed from 72.5% to 4.9%) before
  being superseded by this same design conversation.

## What's NOT done -- the actual next-session work

1. Build `TaxaMatch::evaluate_reference_accessions()` (or whatever name
   sticks) per the sketch above -- caching layer, dedup, BLAST call via
   `blast_sequences()`, congruence-verdict computation adapted from
   `.compute_hierarchy_congruence()`'s math (now archived at
   `TaxaLikely/archive_decipher_reference_audit/R/hierarchy_congruence.R`
   -- read it for the Jeffreys-smoothing/independence-filter logic, don't
   re-derive from scratch, but expect real adaptation work since BLAST hit
   shape differs from `seq_matrix` pair shape).
2. Duplicate `.build_submission_batch_lookup()`/`.same_submission_batch()`
   into TaxaMatch (see the archived file for the exact, already-working
   implementation).
3. Build the early hard-filter consumer (Use Case 1's match-object-editing
   step) -- confident blacklist only, mirroring `remove_flagged_
   references()`.
4. Update `TaxaMatch/CLAUDE.md`'s "Package Purpose" statement to reflect
   the (deliberate, user-confirmed) scope revision.
5. Decide and document exactly which match-object columns the evaluator's
   output should leave behind for later TaxaLikely consumption, and where
   in the pipeline (which function, which stage) that later weighting
   step gets built -- this is real, still-undesigned work, not just an
   implementation detail of item 1.
6. Decide what becomes of `AuditNCBI.R`/`AuditNCBI_README.md` once the new
   tool exists -- rewrite against the new function, or retire in favor of
   a from-scratch new workflow script. Not decided.
7. Local BLAST (`method = "local"`) is a real, faster alternative for
   large batch compilations (Use Case 2) once a local database is set up
   -- not evaluated this session, worth considering if remote rate limits
   (11s/batch minimum, real per-batch search+poll time up to 600s) make
   large compilations impractical.
