# Reentry prompt: widen BLAST when an ASV's whole candidate set has no local occurrence support (design idea, not built)

**Written 2026-08-26, prompted by a real GreatLakes2023 case found investigating a
Venn-diagram-style TaxaID-vs-Lamar comparison** (see the GreatLakes data directory's
`LamarComparisonReport_draft.md` and its companion analysis scripts, not under git).
`Nemacheilidae`/`Barbatula` showed up as one of only two TaxaID-only families in that
comparison -- an Old World stone-loach family/genus with no plausible presence in a
Lake Michigan harbor. Investigated directly (not assumed): one real ASV
(`P2_ASV_0336`, 727 reads, sample GLM-23-090's sibling GLM-23-123), whose entire
candidate set (7 *Barbatula* species, scores 0.688-1.0) has **zero rows anywhere in
`taxaexpect_priors`** -- no occurrence support at any tier, not even the generic
dark-diversity floor computed for it explicitly. The user's diagnosis: a species (or
whole candidate set) with no local support that still wins on raw likelihood is
exactly the situation where the ORIGINAL BLAST call might have stopped too early --
`TaxaMatch::blast_sequences()`'s own `max_hits`/`score_range`/`max_hits_per_taxon`
caps could have cut off a real, locally-plausible candidate sitting just below the
threshold, one that a real occurrence prior might have let compete on more even
footing had it been included at all.

## The problem, generalized

Every candidate-generation step in this ecosystem (`blast_sequences()`'s BLAST
call, `restore_suppressed_candidates()`'s rescue of candidates already IN
`match_obj`) operates on a FIXED-size hit list decided at match-building time,
before priors exist. If the true local species happens to score just outside that
window -- crowded out by several near-identical relatives from an entirely wrong
region, as happened here -- it never becomes a candidate at all, and no downstream
mechanism (including `restore_suppressed_candidates()`, which can only rescue
candidates already present) can help. This is a different, earlier-stage problem
than anything `restore_suppressed_candidates()` already solves: that function
rescues real candidates BLAST already found but a downstream filter excluded; this
is about candidates BLAST never returned in the first place.

**Proposed mechanism:** after priors exist (`taxaexpect_priors` built), identify ASVs
whose ENTIRE candidate set has no occurrence support at any tier (not just the
top hit -- the whole set). For those ASVs only, re-run `blast_sequences()` with a
substantially widened `score_range`/`max_hits` and no `max_hits_per_taxon` cap, to
check whether a locally-plausible candidate was sitting just below the original
cutoff. If one turns up, fold it into the candidate set (via the same mechanism
`restore_suppressed_candidates()` already uses to add a hypothesis) and let the
existing Bayesian machinery -- likelihood x prior -- decide honestly whether it
should compete, rather than assuming a wider net always finds something worth
promoting.

## Real test case, run before deciding this is worth building: a genuine negative result

Before scoping this further, the *Barbatula* case itself was used as a live test of
whether widening would actually have helped -- since a mechanism motivated by one
case should be checked against that case, not assumed to work. Live re-ran
`TaxaMatch::blast_sequences()` on `P2_ASV_0336`'s real raw sequence (recovered via
`GreatLakes_blast_combined_plates.R`'s own `id_lookup.rds` checkpoint, which maps
`canonical_id` -> raw DADA2 sequence -- the original per-ASV sequence was not
directly available in any later checkpoint), with `score_range` widened from the
original call's `8` to `25`, `max_hits` widened from `20` to `100`, and
`max_hits_per_taxon` removed entirely (was `3`). Result: **still zero North
American candidates.** All 100 returned hits (31 unique taxa) are Old World
Cobitoidea/Nemacheilidae relatives -- `Barbatula` (53 hits), plus `Parabotia`,
`Oreonectes`, `Triplophysa`, `Micronemacheilus`, `Erromyzon`, `Lefua`, `Schistura`,
`Barbucca`, `Gastromyzon`, `Karstsinnectes`, `Liniparhomaloptera`,
`Neonoemacheilus`, `Paracanthocobitis` -- overwhelmingly East/Southeast Asian
stone-loach genera, no exceptions.

**This is a genuine, informative negative result, not a failed test:** it rules out
"reference-database coverage gap for the true local species" as the explanation for
this specific case (a wider, uncapped search against the SAME database still finds
nothing local), leaving only a genuine exotic detection (aquarium release) or lab/
reference contamination as live explanations -- neither fixable by any BLAST-side
mechanism. **Any future implementation of this widen-on-no-support idea must be
built and evaluated with this case in mind: it will not always find a rescue
candidate, and should not be presented to a reviewer as if it does.** The value of
the mechanism (if built) is in the cases where a real local candidate WAS crowded
out -- this needs its own real, positive motivating case before being trusted, not
just the one negative case documented here.

## Design questions, not yet resolved

1. **Trigger definition.** "No local support" needs a precise, defensible
   threshold -- literally zero rows in `taxaexpect_priors` for every candidate (the
   `Barbatula` case), or a broader "no candidate clears some minimal theta" cut?
   The former is unambiguous but may be too narrow to catch real cases; the latter
   needs a real threshold choice with no obviously correct default (matching this
   ecosystem's own repeated "no safe universal default" pattern for thresholds like
   this).
2. **Architectural ordering.** This mechanism needs `taxaexpect_priors` to exist
   (to know a candidate set lacks support) but modifies the candidate set BLAST
   produces (a step that happens BEFORE priors are built in every current
   workflow). That's a real two-pass requirement: build match_obj -> build priors
   -> identify unsupported ASVs -> re-BLAST just those -> re-derive their
   candidates -> re-check against (already-built) priors -> feed into likelihood/
   posterior computation. None of the 5 real production workflows (GreatLakes,
   Mugu x2, PtConception x3) currently loop back on themselves this way; this would
   be a new control-flow pattern for this ecosystem, not a drop-in function call.
3. **Cost.** Remote NCBI BLAST is the most expensive step in every real workflow
   already (the whole `verify_flagged_references()`/rate-limit-resilience thread
   this ecosystem built earlier exists because of this). Scoping "re-BLAST only
   ASVs with zero candidate-set-wide support" should be a small fraction of any
   real ASV table, but this needs verifying against real production data before
   assuming it's cheap -- count how many real ASVs in a real dataset (GreatLakes,
   Mugu, PtConception) would actually qualify before committing to build this.
4. **Package placement.** Likely `TaxaMatch` (it operates on the BLAST/match step,
   same as `blast_sequences()` itself) with a new function rather than an
   extension of `restore_suppressed_candidates()` (`TaxaLikely`) -- that function's
   whole design assumes candidates already exist in `match_obj`; this is a
   different, earlier problem (candidates that were never fetched at all).
5. **Genus-level framing.** Should this trigger on "no SPECIES in the candidate set
   has support" (species-level, matches the `Barbatula` case) or also/instead on
   "no candidate's GENUS has support" (coarser, might catch different cases)? Not
   decided -- the one real test case doesn't distinguish these, since neither
   `Barbatula` the genus nor any of its 7 candidate species have any prior support
   at all.

## Why this isn't built yet

Purely a scoping/cost question, not a rejected idea: the one real test case
performed came back negative, so there is not yet a real, positive motivating
example proving this mechanism would have rescued a genuine local species. Before
building the two-pass architecture change this requires, find (or wait for) a real
case where a locally-plausible candidate genuinely was crowded out of the original
BLAST call's hit list -- that positive case, not the `Barbatula` negative one,
should drive the concrete design (trigger threshold, cost-scoping, where in the
workflow it re-enters) rather than guessing at parameters against a case that
doesn't exercise them.

## Resolved (2026-08-26, Sonnet 5) -- decision: do not build

Answered design question 3 (real-scale cost/frequency) directly against cached
production checkpoints before writing any code, per the user's explicit choice when
asked how to proceed. Used `match_obj_restored`/`taxaexpect_priors` for GreatLakes2023
BurnsHarbor (real, current) and the raw BLAST `match`/`taxaexpect_priors` checkpoints
for MuguWilderFish's three markers (pre-`restore_suppressed_candidates()`, the
candidate set BLAST itself produced -- no PtConception checkpoint was available on
disk to include). For each ASV, counted whether EVERY species-level candidate has
zero rows in `taxaexpect_priors` (the trigger this doc proposes).

**Rate is not uniformly small, contrary to this doc's own assumption:** GreatLakes
0.1% (1/885 -- correctly reproduces the `Barbatula` case itself, a good sanity check
on the method), but Mugu 2.7-8.8% depending on marker (21/622 pooled across
12S/16S/COI). That gap alone would have been reason enough to look closer before
committing to "small fraction of any real ASV table."

**But looking closer closed the question instead of reopening it.** Pulled the raw
BLAST hit count for all 21 flagged Mugu ASVs: `1 1 1 1 1 1 1 2 2 2 3 4 4 5 5 8 9 10
10 11 14` -- every single one is below `max_hits`'s current cap of 20 (Session 151
default). **None of the 21 real flagged ASVs were ever truncated by `max_hits` or
`score_range` in the first place.** `blast_sequences()` already returned every hit
NCBI has for each of these queries; there is no hidden tail below the cutoff for a
widened search to reveal, because nothing was cut off. This is a stronger and more
general negative result than the original `Barbatula` test (which showed widening
doesn't help for one case) -- it shows the mechanism's own precondition (a real
candidate suppressed by the hit-list window) doesn't occur in either real dataset
checked, at all, for any of the 22 total flagged ASVs across both.

Inspecting what the 21 Mugu ASVs actually are confirmed why: 5 are the already-known
`Fundulus lima`/`parvipinnis` case (a single reference hit, no wider search possible --
already solved by `restore_suppressed_candidates()`'s regional-overlap mechanism, a
different tool for a different problem); most of the rest are cold-water Salmonidae
(`Coregonus`/`Prosopium`/`Salmo`/`Thymallus`) with no Southern-California congener to
find in GenBank at any window size -- biogeographic absence, not a truncated search,
exactly the `Barbatula` pattern recurring; one is the already-documented
`Pseudotolithus` geographic-outlier case (`check_geographic_outliers()`); one is the
already-documented `Inu`/`Luciogobius` poor-marker-resolution case
(`[[reference_accession_evaluation_guide]]`-style). Every real case checked is either
structurally unreachable by this mechanism (no truncation to widen into) or already
handled by a different, existing tool.

**Decision, confirmed with the user directly (their own prior guess, verified rather
than assumed): do not build this.** The premise motivating it -- a real local
candidate crowded out by a fixed-size hit list -- has now been checked against every
real flagged ASV in two production datasets and never once observed. No code changed;
this is a closed design question, not a deferred one. If a future case surfaces where
a flagged ASV's hit count actually reaches `max_hits`/the edge of `score_range` (which
none did here), that would be the first real evidence the precondition can occur and
would justify reopening this doc.
