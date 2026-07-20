# Reentry prompt: regional-overlap rollout + open questions

**From:** Session 159 (2026-07-16/17), the *F. lima* / *F. parvipinnis* Mugu
misassignment thread. **Read `ecosystem_docs/reference_gap_modeling.md`
first** — it explains the mechanism this prompt assumes you already
understand. Do not re-derive it from scratch; that document is the record
of a full session's worth of real-data debugging.

## State at handoff (all done, real-data-verified)

- `TaxaLikely::restore_suppressed_candidates(check_regional_overlap = TRUE)`:
  three-tier position-aware overlap check, `align_cache` memoization,
  `candidate_species_filter`, `attr(result, "regional_unreferenced")`.
- `TaxaLikely::expand_unreferenced_hypotheses()`: `unreferenced_df` accepts
  an optional per-row `observation_id` column.
- `TaxaLikely::fetch_ncbi_reference_sequences()`: `keep_out_of_range` +
  `max_out_of_range_len` (200,000bp default).
- `TaxaMatch::blast_sequences()`: `subject_start`/`subject_end` columns.
- Both `MuguFishWorkflow.R` and `MuguWilderFishWorkflow.R` wired end to end.
- Real result, verified against actual posterior output: ASV_300/328/329/
  354/433 all correctly flip from *F. lima* to *F. parvipinnis* (98.5–99.7%
  posterior). Real timing: one marker, 401 observations, 38 seconds.
- `devtools::test()` 768/768, `devtools::check()` 0/0/0, TaxaLikely
  installed to both the user (`~/Library/R/4.0/library`) and system
  (`/Library/Frameworks/.../Resources/library`) R libraries.
- CLAUDE.md updated (TaxaID root + TaxaLikely) with the full record,
  including three real bugs found only via live-testing (not by review):
  a global-rule-detection gate that skipped the whole mechanism, an
  unmemoized O(observations) alignment loop, and an unfiltered
  O(genus size) candidate set.

## Task 1 — Apply to PtConception (explicitly deferred, not started)

`PtConceptionWorkflow_12S_single_site.R` and
`PtConceptionWorkflow_18S_2_single_site.R` build `match_obj` from an
externally pre-computed match table — **no live BLAST step**, so
`subject_start`/`subject_end` don't exist. This forces Tier 2b (derive the
query's position by aligning its own raw sequence against the anchor),
which needs `sequence_col` wired to the read file's actual sequence column
(not currently joined onto `match_obj` in either script — confirmed still
open as of Session 159).

**Before wiring this in, budget for the same three-round pattern Mugu just
went through** — each was only found by actually running against real data
with timing, not by reasoning ahead of time:
1. Check whether `detect_suppressed_candidates()` finds a global rule on
   PtConception's real match data. If not (likely, given BLAST alternatives
   or a wide score window), the gating-decouple fix already handles this —
   but confirm `check_regional_overlap=TRUE` actually reaches the
   per-observation loop, don't assume it.
2. Time a real run before trusting it. PtConception's Tier 2b path aligns
   the *query* against the anchor on top of aligning *each candidate*
   against the anchor — a real, not-yet-measured additional cost per
   observation the Mugu Tier 2a path didn't have to pay. Profile before
   wiring into the full workflow.
3. Build `candidate_species_filter` from that workflow's own
   `taxaexpect_priors` (or equivalent) the same way, from the start —
   don't wait for a 15-minute run to discover it's needed again.

## Task 2 — Resolve the no-reference/no-prior edge case (real open question, not yet investigated)

From `reference_gap_modeling.md`'s "real, unresolved edge case" section: a
species with neither an NCBI reference nor a TaxaExpect prior is invisible
to the whole pipeline. Specifically unconfirmed: does
`TaxaAssign::join_priors()`'s existing coarse-rank / dark-diversity
mechanism give such a species *any* path to compete at genus or family
rank without a species-level prior row, or does it just drop silently?
Read `join_priors()` directly (don't guess) and report back — this affects
whether the plausibility-filter design in `reference_gap_modeling.md` is
actually complete or has a real gap worth closing.

## Task 3 — Broader sanity pass (user's own suggestion, not yet done)

The user asked for a check across the *rest* of the 12S consensus output
(not just the five Fundulus ASVs) to confirm nothing else regressed, and
the same for 16S/COI once 12S is reviewed. Not started — the conversation
moved to documentation before this happened. Do this first if picking the
thread back up, since it's cheap and closes out Mugu properly before
PtConception work begins.

## Context you do NOT need to re-derive

The full mechanism design, the real motivating numbers, the three
performance bugs and their fixes, and the marker/scope boundaries are all
in `ecosystem_docs/reference_gap_modeling.md`. The session-by-session blow-
by-blow (including two rounds of "still get Fundulus lima" that turned out
to be a stale-run issue and then two further real bugs) is in
`TaxaLikely/CLAUDE.md`'s top few Session 159 entries and
`TaxaID/CLAUDE.md`'s matching entries, if you need the full narrative for
some reason — but the explainer document should be sufficient for actually
continuing the work.
