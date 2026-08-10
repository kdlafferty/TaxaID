# Reentry prompt: pre-filtering, group assessment, and post-hoc assessment for `investigate_flagged_accession()`

**Status: design-only, not yet implemented.** Written 2026-08-08 after the first
real live-validation run of `TaxaMatch::investigate_flagged_accession()`
(built the same week -- see `TaxaMatch/CLAUDE.md`'s top session notes and
`[[project_taxaflag_domestic_species_floor_note]]`-adjacent memory for
context) surfaced both a real bug (fixed, see below) and a real, unresolved
limitation this document is about. Nothing here has been coded yet.

## Where this came from

`investigate_flagged_accession()` (`TaxaMatch/R/investigate_flagged_accession.R`)
does a deep-dive verification pass on ONE accession that
`evaluate_reference_accessions()` already flagged `"incongruent"`: (1) a
self-consistency check (does this accession's sequence agree with other real,
independent GenBank accessions of its OWN listed species), and (2) a
cross-taxon-consistency check (does it agree with real accessions of the
species it disagrees with). Both reuse the same-submission-batch
independence filter (`.build_submission_batch_lookup()`/
`.same_submission_batch()`) `evaluate_reference_accessions()` already
established, applied to a fresh `.search_species_accessions()` (species-name
based NCBI search, not accession-based) plus a direct
`pwalign::pairwiseAlignment(type = "local")` comparison
(`.align_against_comparison_set()`).

A real coverage-blindness bug in that pairwise-alignment step was found and
fixed the same day it was built (comparing a short query against a much
longer reference can find a tiny, spuriously-perfect-identity fragment) --
fixed with a `min_coverage` floor (default 0.5) and a `meets_min_coverage`
column, reported honestly rather than hidden. Immediately after that fix
shipped, a live re-run against the real motivating case
(`investigate_flagged_accession("MZ605481")`, the current best real
`candidate_mislabel` case in
`diagnostics/reference_accession_ground_truth.csv`) came back **inconclusive
in both directions** -- 0 of 30+ real candidate accessions found via
`.search_species_accessions()` cleared the 50% coverage floor on either the
self-consistency or the cross-taxon-consistency side. Root cause: NCBI's
`[Organism]`-based species search returns records of ANY length, and most
real GenBank deposits for both the listed species (*Pseudorasbora parva*)
and the disagreeing taxon (*Cyprinus carpio*) are full mitogenomes
(~16kb) -- a 173bp flagged amplicon can only ever find a small, non-meaningful
local-alignment fragment against something that long. See the ground-truth
CSV's own MZ605481 row (corrected 2026-08-07/08) for the full write-up of
this finding.

This is a DIFFERENT problem from the coverage-blindness bug above (that one
is fixed): it's a real, structural gap in how candidate accessions are
selected before alignment is even attempted, not a bug in the alignment
math itself.

## Question 1: does `investigate_flagged_accession()` carry its weight?

Short answer: **the mechanism (independence-filtered self/cross-taxon
consistency checking) is sound and worth keeping, but the current candidate-
selection step (raw NCBI species search, no length awareness) makes it
non-functional on real, length-heterogeneous GenBank data -- exactly the
population this tool exists to review.** This is a fixable gap, not a
reason to abandon the tool. There is direct, already-solved precedent for
the fix in this ecosystem (see below) -- don't design it from scratch.

Two candidate fixes, not mutually exclusive, evaluate both before building
either:

### Fix option A (recommended starting point): stop hand-rolling pairwise alignment, reuse `blast_sequences()`

The ORIGINAL evidence that made MZ605481 a real `candidate_mislabel` in the
first place was not a pairwise alignment at all -- it was a direct
`TaxaMatch::blast_sequences()` call, which already enforces
`min_query_coverage = 80` internally (see that function's own
`R/blast_sequences.R`) and found 20 independent, real, coverage-safe
*Cyprinus carpio* hits at genuine 100% identity. That mechanism already
works on exactly this case. `investigate_flagged_accession()`'s newer,
supposedly-more-targeted pairwise-alignment path duplicates a WEAKER,
coverage-blind version of a check `blast_sequences()` already does
correctly.

Concretely: replace `.align_against_comparison_set()`'s
`pwalign::pairwiseAlignment()` loop with a `blast_sequences()` call scoped
to the flagged accession as query, restricted (via BLAST's own `entrez_query`
gi-list mechanism, or post-hoc filtering of `blast_sequences()`'s hit
accessions against the candidate set already fetched by
`.search_species_accessions()`) to just the comparison-set accessions. This
gets coverage-safety for free, is less code than maintaining a second
alignment path, and is proven on the one real case tested so far. The
tradeoff: a remote BLAST call per investigation is slower (RID polling, not
a local alignment) -- likely fine for a "small subset of already-flagged
accessions" tool (per the user's own framing of what this tool is for), but
worth confirming against real usage volume before committing.

### Fix option B: length-aware candidate filtering (adapt `repair_thin_evidence()`'s precedent)

If Option A's per-investigation BLAST cost turns out to be a real problem,
there IS already a solved version of "how do you avoid comparing a short
sequence against a long one" in this ecosystem's archived code:
`TaxaLikely/archive_decipher_reference_audit/R/repair_thin_evidence.R`
(moved out of the shipped package 2026-08-06/07 when
`evaluate_reference_accessions()` superseded the DECIPHER-whole-set-alignment
approach it was part of, but the file itself is kept for reference, not
deleted -- see `REENTRY_PROMPT_blast_based_reference_quality.md`).

The relevant design principle (`repair_thin_evidence.R`'s own "Scope,
deliberately bounded" section, roughly lines 104-133): **every CANDIDATE a
repair attempt aligns against must itself already be short enough to have
been a real, vetted participant in the audit's own `seq_matrix`** -- an
over-length/unvetted accession is never used as another one's anchor. This
is exactly the constraint `investigate_flagged_accession()` is missing:
`.search_species_accessions()` currently returns accessions of ANY length,
with no filter at all.

`investigate_flagged_accession()` has no `seq_matrix` to check "already
vetted" against (it's a standalone per-accession tool, not an audit-scale
batch process), so the direct adaptation would be a **length-ratio filter**
on `.search_species_accessions()`'s candidate list relative to the flagged
accession's own length -- e.g. only keep candidates within some multiple
(2-3x?) of the flagged accession's length, or add a cheap length field to
`.search_species_accessions()`'s NCBI ESummary call (already batched, `slen`
is already returned by ESummary for free -- no extra round trip) and filter
before ever fetching full sequence content or attempting alignment. This is
cheaper per-candidate than Option A (no BLAST call needed) but doesn't fully
solve the problem: a species genuinely represented in GenBank ONLY by
mitogenome-scale deposits (real, not rare) would still have zero
length-comparable candidates, and the check would correctly-but-uselessly
report "no comparable data," same as today's honest-but-empty result.

**Recommendation for whoever picks this up:** try Option A first (less
code, proven, coverage-safe by construction). Only build Option B's
length-filter machinery if Option A's per-call BLAST cost proves impractical
at real usage volume -- and even then, Option B is a *filter*, not a
replacement alignment mechanism; it would still feed into whatever
comparison step is used.

## Question 2: pre-filtering -- avoid deep-diving into easily-verifiable accessions

Every one of these can be computed from `evaluate_reference_accessions()`'s
own EXISTING output columns (the 5 diagnostic columns added in the Opus
consult follow-up: `best_hit_pident`, `best_agreeing_pident`,
`best_disagreeing_pident`, `congruent_evidence_exists_anywhere`,
`congruent_evidence_best_pident`) -- no new fetches needed to triage a
flagged-accession list BEFORE deciding which ones are worth the expense of
`investigate_flagged_accession()`'s deep dive.

1. **`congruent_evidence_exists_anywhere` as a priority filter.** An
   accession where this is `TRUE` (some real corroborating same-species
   evidence exists SOMEWHERE in the BLAST hit pool, just not enough to clear
   the `top_n`/independence bar used for the headline verdict) is a weaker
   deep-dive candidate than one where it's `FALSE` (zero corroborating
   evidence anywhere) -- the `FALSE` case is exactly what made MZ605481 the
   strongest real candidate found this session; the Abylopsis pair
   (`congruent_evidence_exists_anywhere` presumably `TRUE`, needs
   confirming) is the `ambiguous` case, already correctly triaged lower in
   the ground-truth CSV. Formalize this as an explicit priority tier on any
   future batch-review tooling, not just an implicit reading of the CSV
   notes.

2. **`best_disagreeing_pident` as a strength-of-evidence filter.** A
   disagreement at ~100% identity against a completely different,
   well-corroborated species (MZ605481: 100% against 20 independent *C.
   carpio* accessions) is categorically stronger evidence than a
   disagreement at, say, 75-85% against a distant relative -- the latter is
   much more likely to resolve to "marker has poor resolving power here" (the
   Abylopsis story) than "real mislabel." A minimum `best_disagreeing_pident`
   threshold (worth calibrating empirically, not guessing a number) could
   gate which flagged accessions are even worth deep-diving.

3. **Rank-of-disagreement is NOT a reliable standalone triage signal --
   confirmed the hard way this session, don't reuse this idea naively.**
   Initial hypothesis was "a disagreement resolved only at a coarse rank
   (family/order/phylum) suggests a marker/gene mislabel (the AY850362
   16S-deposited-as-12S case), while a disagreement at genus/species
   suggests a real species mislabel." This does NOT hold as stated:
   MZ605481's own disagreement is *also* recorded at `finest_common_rank =
   "order"` (Cyprinidae vs. whatever *P. parva*'s own family resolves to)
   yet is the strongest real candidate species mislabel found this session,
   not a marker mislabel. What actually distinguished the AY850362 case was
   the record's own **annotated gene/product metadata**, not its taxonomic
   rank of disagreement -- see item 4.

4. **GBSeq metadata cross-check (marker/gene mismatch) -- new, cheap, not
   yet built.** Before investigating a flagged accession as a possible
   SPECIES mislabel, do a single cheap GBSeq XML fetch (reuse
   `.fetch_reference_accession_records()`, already built) and check the
   record's own `/gene` or `/product` feature-table qualifier against the
   marker the evaluation was scoped to (e.g. does a "12S"-scoped audit's
   flagged record actually say `/product="16S ribosomal RNA"`?). This is
   directly grounded in the real AY850362 lesson from this session (a
   genuine 16S-vs-12S marker mislabel, not a species mislabel -- see that
   row's note in `reference_accession_ground_truth.csv`) and is a single
   record fetch, no BLAST, no alignment -- much cheaper than the deep-dive
   this document is otherwise about, and would route a flagged accession to
   a completely different (and much simpler) resolution path before ever
   reaching `investigate_flagged_accession()`.

## Question 3: group assessment -- shared work across a list of flagged accessions

The core observation: `investigate_flagged_accession()` currently treats
every call as fully independent -- no cache, no cross-call sharing, even
though real flagged-accession lists will often share species on either side
of the comparison.

1. **No persistent cache exists for this function at all.** Unlike
   `evaluate_reference_accessions()`'s own accession-keyed, asymmetric-TTL
   cache (confident verdicts cached indefinitely;
   `"insufficient_independent_evidence"` expires and retries -- see that
   function's own design notes), `investigate_flagged_accession()` re-runs
   every NCBI search and re-fetches every sequence from scratch on every
   call, even for the identical accession twice. Add a cache keyed on
   `(accession, species override)`, same asymmetric-TTL philosophy: a
   `"inconclusive_length_mismatch"`-class result (the real MZ605481 outcome)
   should probably expire and retry (new, shorter GenBank deposits for
   either species could genuinely change the answer), while a real
   confident self/cross-taxon confirmation should be cached longer.

2. **Share `.search_species_accessions()` results across accessions in one
   batch.** If a caller runs `investigate_flagged_accession()` over a whole
   flagged-accession list (the natural next step after this session's
   120-accession comparison run), and several flagged accessions share the
   same `listed_species` -- or, less obviously, the same `disagreeing_taxon`
   -- the species-level accession list only needs to be fetched from NCBI
   ONCE per species per batch, not once per flagged accession. This is a
   straightforward memoization win, no new science needed -- just don't
   design `investigate_flagged_accession()` as a single-accession-only
   function forever; a natural `investigate_flagged_accessions()` (plural)
   batch wrapper could share a single in-memory (or on-disk) lookup
   environment across its calls.

3. **Cluster-level mislabel detection -- a real, higher-value signal a
   single-accession tool structurally cannot see.** When investigating a
   LIST together (not one at a time), group by `disagreeing_taxon`: if
   several INDEPENDENTLY-flagged accessions (different `listed_species`,
   confirmed not same-submission-batch via the existing independence
   filter) all disagree toward the SAME species, that is much stronger,
   and much more actionable, evidence of either a real systemic
   contamination pattern (e.g. one lab/pipeline routinely cross-contaminating
   with a common local species) or a genuinely common co-occurring species
   in the underlying eDNA samples -- than any one accession's isolated
   verdict. This is a direct, natural extension of the same
   Jeffreys-smoothed-independence-filter logic already used per-accession
   (`.compute_hierarchy_congruence()`'s design, archived at
   `TaxaLikely/archive_decipher_reference_audit/R/hierarchy_congruence.R`),
   just applied one level up, across a batch rather than within one
   accession's own hit pool. Not designed yet -- flag as real future work,
   likely the single highest-value idea in this document since it surfaces
   a pattern no per-accession tool, however good, can see on its own.

## Question 4: other post-hoc investigations worth automating

Beyond the metadata-mismatch check (Question 2, item 4) and the
cluster-level detector (Question 3, item 3), both already substantial:

1. **Voucher/publication-context check.** This session's manual review
   already distinguished real cases by hand on exactly this axis: KX384617
   (Abylopsis, voucher-backed NHMUK specimen, peer-reviewed checklist paper)
   vs. KY594854 (Abylopsis, unvouchered environmental-amplicon-only clone)
   vs. MZ605481 (unvouchered eDNA amplicon clone, unpublished study) vs.
   AY850362 (a genuine marker mislabel, unrelated axis). A voucher-backed
   record disagreeing with the corroborating pool is much stronger evidence
   of a genuine field misidentification (not just a lab/pipeline artifact)
   than an unvouchered environmental clone disagreeing. GBSeq XML's
   `/specimen_voucher` qualifier (when present) plus a check for a real
   linked PubMed/DOI reference (already parseable from the same XML this
   package already fetches) could turn this from "something I noticed by
   reading records by hand" into a real, automatable evidence-strength
   column.

2. **Geographic/range plausibility, reusing existing cross-package
   machinery.** `TaxaLikely::fetch_ncbi_reference_sequences(include_location
   = TRUE)` (Session 135) already parses `lat`/`lon`/`country` out of GBSeq
   XML via `.parse_lat_lon()` -- the identical XML this package's own
   `.fetch_reference_accession_records()` already fetches, just discarding
   those fields today. If a flagged accession carries a real collection
   locality, cross-checking it against `TaxaFetch::check_geographic_
   outliers()`'s existing GBIF-range machinery (built for a related but
   different purpose -- catching misidentified GBIF occurrence records, not
   reference sequences) could add a real, independent line of evidence: does
   the flagged accession's own collection locality look plausible for the
   LISTED species, or better fit the DISAGREEING species' known range? Not
   wired up anywhere between these two packages today -- would be new,
   real cross-package work, not a trivial add.

3. **Submission-batch-wide pattern check.** The existing independence
   filter (`.same_submission_batch()`) already identifies whether OTHER
   accessions share a flagged accession's submission batch -- but only ever
   uses that to EXCLUDE same-batch neighbors from counting as independent
   evidence. It never asks whether the batch ITSELF looks suspicious --
   e.g., do MOST accessions from the same real submission batch as a
   flagged one also independently disagree with their own claimed species?
   That would be a real signal of a batch-wide pipeline/lab error (worth
   flagging the whole batch for review) rather than a one-off individual
   mislabel. Not designed -- would need `evaluate_reference_accessions()`'s
   own cached verdicts for every OTHER accession in the same batch, which
   may or may not already exist in the persistent cache depending on what's
   been evaluated so far.

## Suggested next-session scope (not decided, pick based on what's most useful)

None of the above has been prioritized against the others yet -- this is a
menu, not a plan. Candidates for a focused single-session build, roughly
ordered by (estimated value) / (estimated effort):

1. **Question 1's fix (Option A first)** -- makes the tool actually usable
   on real data again; the MZ605481 case is sitting there as a ready-made
   regression test the moment this ships.
2. **Question 2, item 4 (GBSeq metadata/marker-mismatch check)** -- cheap,
   single-fetch, directly grounded in a real, already-confirmed lesson
   (AY850362), and would have caught that case earlier than the manual
   re-investigation this session actually needed.
3. **Question 3, items 1-2 (basic caching + batch-level NCBI search
   sharing)** -- necessary infrastructure before any real batch-review
   workflow is practical; low risk, mechanical, mirrors
   `evaluate_reference_accessions()`'s own already-proven cache design.
4. **Question 3, item 3 (cluster-level mislabel detection)** -- highest
   potential value, but needs real batch data (a list of several genuinely
   independent flagged accessions with actual disagreement-taxon overlap)
   to design and test against meaningfully; may be premature until more
   real flagged accessions have been reviewed one at a time first.
5. Question 4's items -- real, worth doing eventually, lower urgency than
   1-3; item 1 (voucher check) is probably the cheapest of the three.
