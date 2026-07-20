# Reference-gap modeling: how TaxaID decides a species is "unreferenced"

**Written:** 2026-07-17 (Session 159, closing entry). Prompted by a real Mugu
misassignment (*Fundulus lima* vs *Fundulus parvipinnis*, ASV_300 and four
siblings) that took the whole session to run down. This document is the
conceptual explainer the debugging earned — read this before touching any of
the mechanisms it describes.

## The problem in one sentence

NCBI's reference database mixes complete mitogenomes with short barcode
fragments under the same species name, so "this species has a GenBank
record" and "this species has a record that covers *this specific query's*
genomic position" are different, and conflating them produces a real,
silent misassignment.

## The concrete case that motivated this

A Mugu 12S ASV's only real BLAST hit was *Fundulus lima*'s complete
mitogenome (`NC_063692`), at position 515–612. *Fundulus parvipinnis* — the
species field expectation actually favored — has a real 12S reference
(`OQ846298`, 168bp), but it covers position 319–486 of that same
mitogenome coordinate space. The two windows don't overlap. BLAST correctly
never returned *F. parvipinnis* as a hit, because its reference genuinely
doesn't cover the region this query amplified. But TaxaID's older logic
treated "F. parvipinnis has *some* 12S reference in NCBI" as equivalent to
"F. parvipinnis was a real candidate for this query" — which is false here.
*F. lima* won by default, every time, for every ASV hitting this mitogenome
region, regardless of how implausible *F. lima* was ecologically (it's a
Baja California / Gulf of California species; Mugu is Southern California).

## Two different kinds of "unreferenced" — do not conflate them

This is the single most important distinction in this document. TaxaID now
has two structurally different mechanisms, answering two different
questions, that both end up producing a named `"unreferenced_species"`
hypothesis. They are easy to confuse because they look similar downstream,
but they are triggered by different facts and computed by different code
paths.

### 1. Globally unreferenced (pre-existing mechanism, not new this session)

**Question:** Does this species have *any* barcode-length reference sequence
for this marker, anywhere in NCBI?

**Answered by:** `TaxaLikely::audit_barcode_coverage()`, which censuses a
genus against NCBI and reports species with zero barcode-length hits as
`coverage$unreferenced`.

**Real example:** *Citharichthys platophrys* — genuinely has zero 12S
barcode references in NCBI (confirmed directly against the real Mugu
`reference_df`: absent from it entirely). This is a real, global gap, not a
regional artifact.

**Flows into a named hypothesis via:** the `unreferenced_df` built from
`coverage$unreferenced`, filtered to species with real local plausibility
(a `TaxaExpect` prior, or `iNat`-confirmed range), then
`expand_unreferenced_hypotheses()`.

This mechanism predates this session and was not changed by it.

### 2. Regionally rejected (new this session — the actual fix)

**Question:** For *this specific query*, does the top-hit congener's own
reference sequence cover the same genomic window the query itself aligned
to — not just "does this species have a reference somewhere"?

**Answered by:** `restore_suppressed_candidates(check_regional_overlap =
TRUE)`, via the internal `.check_regional_overlap()` helper.

**Real example:** *F. parvipinnis* for the ASV described above. It is
**globally referenced** (has `OQ846298`) — it would never appear in
`coverage$unreferenced` at all, because `audit_barcode_coverage()` correctly
sees it has a barcode-length reference. It is *this query's* regional
mismatch that makes it invisible to the old logic, not a lack of any
reference.

**Flows into a named hypothesis via:** a new, `observation_id`-scoped row in
`unreferenced_df` (see "The mechanism," below) — deliberately *not* the
same global list `coverage$unreferenced` populates, because *F. parvipinnis*
is a perfectly good `specific_candidate` for a *different* query whose hit
region actually does overlap `OQ846298`. Marking it "unreferenced" globally
would be wrong.

**Why this distinction matters practically:** a species can be species #1
for one observation and species #2 (via this mechanism) for another,
*in the same dataset, same run*. That's not a bug — it's the whole point.

## The mechanism, precisely

### Step 1 — three-tier regional-overlap check

`.check_regional_overlap(anchor_accession, candidate_accessions,
reference_df, seq_matrix, anchor_subject_range, query_sequence,
min_coverage)` (`TaxaLikely/R/regional_overlap.R`) decides, for one
candidate congener against one query's anchor hit, whether real evidence
supports overlap:

1. **Tier 1 (free):** look up `seq_matrix` (already computed once per genus
   at training time) for an existing pairing. Safe to trust "any
   coverage ≥ threshold" here with no position check, because
   `build_sequence_matrix()` only ever includes properly-sized barcode
   sequences — never a whole genome — so a `seq_matrix` anchor can't have
   the "trivially overlaps everything" problem below.
2. **Tier 2a:** when `match_obj` carries `subject_start`/`subject_end` for
   this observation (from a live `TaxaMatch::blast_sequences()` run —
   confirmed present for all three real Mugu markers, COI/12S/16S), align
   the candidate against the anchor's own sequence and check whether the
   candidate's aligned position overlaps the query's real hit position.
3. **Tier 2b:** for match objects with no live BLAST step at all (e.g.
   PtConception's externally pre-computed match tables), derive the query's
   own position within the anchor by aligning the raw query sequence
   directly, then proceed as 2a.

**The bug this design specifically avoids:** an early draft checked only
"does the candidate align anywhere in the anchor's full sequence" — true
almost by construction once the anchor is a whole mitogenome (it contains
every sub-region of the marker gene). Confirmed wrong on the real case:
*F. parvipinnis*'s reference aligns fine to *F. lima*'s mitogenome
*somewhere* (319–486) — just not where the query itself hit (515–612). The
fix requires the *position* to overlap, not just "an alignment exists."

A verdict of `NA` (no tier could reach a conclusion — e.g. no
`subject_start`/`subject_end` and no `query_sequence`) is treated the same
as a confirmed non-overlap by every caller: there is no basis to assume
overlap either.

### Step 2 — record the rejection, don't just drop it

`restore_suppressed_candidates()` used to simply omit a congener that
failed the overlap check. That was the actual bug behind "the outcome
didn't change" after the check itself was working correctly: F. lima was
still the only *named* candidate left, so it won by default with
posterior ≈ 1.0 regardless of how implausible it was.

Now, a rejected congener is recorded — `observation_id` / `species` /
`genus` / `family`, one row per rejection — and returned via
`attr(result, "regional_unreferenced")`.

### Step 3 — expand it into a real, named, observation-scoped hypothesis

`expand_unreferenced_hypotheses()`'s `unreferenced_df` parameter now
accepts an optional `observation_id` column:

- `NA` or absent → applies globally (the original behavior, used by the
  `coverage$unreferenced` global-list pathway, mechanism #1 above).
- A real `observation_id` → applies **only** to that one observation.

A workflow binds `attr(match_restored, "regional_unreferenced")` onto its
own `unreferenced_df` before calling `expand_unreferenced_hypotheses()`.
The species gets a real, named `"unreferenced_species"` row — sharing the
same generic genus-level H2 likelihood value every unreferenced-species
expansion already used (this part of the design is unchanged; see
"What the likelihood value does and doesn't mean," below) — for that one
observation, while remaining an ordinary `specific_candidate` everywhere
else it's the genuine best hit.

## The plausibility filter, and what it does and doesn't change

Both mechanisms are filtered to `species %in% taxaexpect_priors$taxon_name
| species %in% inat_confirmed` before a generic H2/H3 row gets expanded
into a named one. This is not new — it already existed for mechanism #1
(`coverage$unreferenced`) before this session, and the same filter was
applied to mechanism #2 (`regional_unreferenced`) from the moment it was
first built.

**A separate, later addition — `candidate_species_filter` on
`restore_suppressed_candidates()` — applies the *same* filter earlier, for
performance only.** Without it, every same-genus congener with *any*
reference in NCBI gets checked for regional overlap regardless of local
relevance. On real Mugu 12S data this meant checking congeners in a genus
with 42 referenced species against every anchor sharing that genus — 2,361
distinct alignment pairs, several against 16.5kb mitogenomes (measured at
~2.7s each), over 15 minutes for one marker. Restricting the *candidates
even considered* to `unique(taxaexpect_priors$taxon_name)` before running
any alignment cut this to 416 pairs and 38 seconds — because
`.run_round1()` was going to apply the identical filter to the result
anyway. **This does not change which species can ultimately become a named
hypothesis** — it only changes how early an already-certain exclusion
happens.

### The real, unresolved edge case

A species with **no reference in NCBI and no TaxaExpect prior** is
invisible to the entire pipeline, not just to these two mechanisms — even
if it received a likelihood value somehow, `join_priors()` has no prior
row to join it to. This is a pre-existing limitation, not something this
session's fixes created or could fix by relaxing `candidate_species_filter`
(relaxing it doesn't help: the species still has nothing to join to
downstream). What is **not yet confirmed**: whether `join_priors()`'s
existing coarse-rank / dark-diversity mechanism gives such a species *any*
path to compete at genus or family rank even without a species-level prior
row. This needs a direct read of `join_priors()`, not speculation — see the
reentry prompt.

## What the likelihood value does and doesn't mean

Every named `"unreferenced_species"` hypothesis — whether from mechanism #1
or #2 — shares the *same* generic genus-level H2 likelihood value computed
by `evaluate_likelihoods()`. It does not depend on which specific species
is being named. For the real Mugu case, this means the posterior swing from
*F. lima* (98.6%+ before the fix) to *F. parvipinnis* (98.6%+ after) is
driven almost entirely by the **prior** gap — *F. lima*'s real occurrence
support near zero at this site, *F. parvipinnis*'s real and substantial —
not by the likelihood discriminating between the two species. That is
arguably correct here (raw sequence similarity structurally cannot
discriminate between two congeners when one's reference doesn't cover the
query region at all), but it should be stated plainly rather than left
implicit: **this mechanism lets occurrence evidence decide when sequence
evidence structurally can't**, it does not manufacture new sequence-level
discriminating power.

## Scope

- **Marker-general by construction.** Nothing in `.check_regional_overlap()`
  or `restore_suppressed_candidates()` is 12S-specific; it operates on
  `accession`/`subject_start`/`subject_end`/`composite_id`/`sequence`
  columns present for any DNA marker run through
  `TaxaMatch::blast_sequences()`. Confirmed live for COI, 12S, and 16S on
  the real Mugu match objects.
- **DNA-only.** `check_regional_overlap = TRUE` requires an `accession_col`
  in `match_obj` (validated; errors if absent) — image and acoustic match
  objects never populate this, so the no-score pathway
  (`assign_scores()`) and image/acoustic workflows are structurally
  untouched.
- **Not yet applied to PtConception.** PtConception's match objects use
  Tier 2b (no live BLAST step — position derived from a raw query sequence
  instead) rather than Tier 2a. Tier 2b is unit-tested but has not had the
  same real-data trial that surfaced three real bugs in the Tier 2a/Mugu
  path (a global-rule-detection gate that silently skipped everything, an
  unmemoized alignment loop, and an unfiltered candidate set) — all found
  only by running against real data with timing, not by review. Apply the
  same discipline before trusting the PtConception result.

## Real validated numbers (Mugu 12S, this session)

| ASV | Winner before fix | Winner after fix | Posterior |
|---|---|---|---|
| ASV_300 | *F. lima* | *F. parvipinnis* | 98.55% |
| ASV_328 | *F. lima* | *F. parvipinnis* | 99.65% |
| ASV_329 | *F. lima* | *F. parvipinnis* | 99.65% |
| ASV_354 | *F. lima* | *F. parvipinnis* | 99.62% |
| ASV_433 | *F. lima* | *F. parvipinnis* | 99.64% |

Performance: 15+ minutes (killed, unfinished) → 38 seconds, one marker,
401 real observations, after `align_cache` + `candidate_species_filter`.
