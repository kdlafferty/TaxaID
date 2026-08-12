# Reentry prompt: a smarter second look at `evaluate_reference_accessions()`'s flagged/borderline accessions

**Status: design-only, not yet implemented.** Written 2026-08-11 after a real full
GreatLakes Goal-2 run (`AuditNCBI_Goal2_MatchCandidateScreen.R`, 1,183 accessions,
1,138 congruent / 8 incongruent / 17 insufficient_independent_evidence / 20 retrying)
surfaced two genuinely different patterns in the flagged list that the hybrid-
maternal-proxy fix (same day, see `TaxaMatch/CLAUDE.md`'s 2026-08-10/11 session notes)
correctly does NOT address, because they're different problems. Deliberately split out
of that same-day work rather than rushed -- both items below need real design thinking,
not a quick patch, and both risk repeating a mistake this ecosystem has already made
once (see the `trusted_rank` cautionary note under Question 1).

Two, related but separable, questions:

1. Should `hierarchy_flag`'s classification account for a strong single match when the
   species is taxonomically isolated (few real relatives anywhere in NCBI)?
2. Should an LLM give flagged/borderline accessions a second, contextual look, the way
   `TaxaFlag::review_assignments()` already does for posterior assignments?

Both were raised by the user directly while reviewing the real 8-row incongruent list
from today's run; this doc captures the design thinking from that conversation plus
what's needed before either gets built.

## Where this came from -- the real motivating case

Two accessions of the same species, from the real GreatLakes 12S candidate population:

| accession | listed_taxon | finest_common_rank | best_agreeing_pident | best_disagreeing_pident | congruent_evidence_exists_anywhere | hierarchy_flag |
|---|---|---|---|---|---|---|
| LC649807 | *Stereolepis doederleini* | species | 100 | 100.00 | TRUE | incongruent |
| MT083886 | *Stereolepis doederleini* | species | 100 | 100.00 | TRUE | incongruent |

Both accessions have a real, independent hit that agrees at species level at 100%
identity (`congruent_evidence_exists_anywhere = TRUE`) -- yet both still read
`"incongruent"`, because `hierarchy_flag`'s classification is driven entirely by
`frac_independent_below_min_congruent_rank >= hierarchy_incongruent_threshold` (default
0.5): the MAJORITY of the `top_n` (up to 5) closest independent hits disagree at family
or coarser, even though one of them is a real, strong match. This is the documented,
already-known "taxonomically isolated species" limitation (`AuditNCBI_README.md`'s own
problem list names it explicitly) -- *Stereolepis* is one of only 2 genera in
Polyprionidae, so there simply aren't enough real close relatives in NCBI to fill the
other `top_n` slots with anything more related than a distant fish.

**One thing NOT yet investigated, and worth doing FIRST before designing any fix**:
`best_disagreeing_pident` is ALSO exactly 100.00 for both accessions -- not just high,
identical to the agreeing match's own identity. That's consistent across two independent
accessions of the same species, which argues against pure coincidence. Two real, distinct
explanations are both plausible and have different implications:

- **Pure isolation** (the assumed story so far): the disagreeing 100%-identity hit is to
  some unrelated, distant fish, and it only "wins" a majority vote because nothing closer
  exists to compete with it for the other slots. If true, the fix is purely about how
  votes are weighted (see Question 1 below).
- **Genuine sister-species confusability**: the disagreeing hit might be *Stereolepis
  gigas* (the only other species in the genus, the giant sea bass) or another close
  relative that this marker genuinely cannot distinguish from *S. doederleini* at 100%
  identity. If true, this isn't really about isolation at all -- it's the marker's own
  resolving-power limit at the species/genus boundary for this specific pair, a different
  (and arguably more important) finding.

**First concrete step for whoever picks this up**: pull the real BLAST hit table for
both LC649807 and MT083886 (already computed once, during today's run -- either re-run
`evaluate_reference_accessions()` on just these two accessions with the real hit table
retained, or add a debug hook to surface it) and look at what taxon the 100%-identity
disagreeing hit actually is. This one cheap check should settle which of the two stories
above is true, and should shape whatever gets designed next -- don't design a general
weighting fix before knowing which of these it's actually solving.

## Question 1: should `hierarchy_flag` weight by best-match strength, not just vote fraction?

**Is this rare?** No -- the user's own instinct here is right, and it's worth stating
plainly: monotypic or near-monotypic families are genuinely common across the fish tree
of life (Polyprionidae, Niphonidae -- already independently flagged in the SAME 8-row
list, both are essentially monotypic). This will keep recurring, predictably, as the
audit scales to the full ~2,600-accession Goal-1 reference-database population, not just
this narrow Goal-2 candidate set.

**Why this needs care, not a quick patch.** This ecosystem has already built and then
REMOVED a mechanism with a very similar shape once before:
`TaxaLikely::evaluate_likelihoods()`'s `trusted_rank`/`min_rank_trust_pvalue` (built
2026-07-19, removed 2026-07-20) walked a winning hypothesis's rank coarser until an
absolute-fit test passed -- essentially "does one thing look confidently right, elevate
trust accordingly." It was removed after finding it was computed on the wrong candidate
(the top-LIKELIHOOD hypothesis, not necessarily the one that wins the POSTERIOR once
priors are applied downstream) -- a real ~30% mismatch on real data, plus a cancellation
bug where a downstream step could silently reverse it. See
`[[project_rank_trust_mechanism_removed]]` in the memory system for the full account.
The lesson that generalizes here: a mechanism that re-weights a coarse verdict based on
one strong data point needs to be checked against exactly where its OWN output actually
gets consumed, not just validated on its own inputs in isolation -- `hierarchy_flag`
today feeds `flag_incongruent_references()`/`remove_incongruent_references()`
(TaxaMatch) directly; whatever new logic is designed needs to be validated against real
before/after behavior on a real accession population, not just the two motivating rows.

**Candidate approaches, not mutually exclusive, none decided:**

- **A. Identity-weighted voting**: instead of a flat fraction of disagreeing hits,
  weight each independent hit's vote by its own percent identity (or some function of
  it) before comparing to `hierarchy_incongruent_threshold`. A single 100%-identity
  agreeing hit would then outweigh several lower-identity disagreeing hits, rather than
  counting as one vote each. Directly addresses the motivating case if the "pure
  isolation" story above is confirmed. Needs real-data calibration (what weighting
  function, does it change verdicts elsewhere in ways that need checking) before
  shipping, the same way `hierarchy_incongruent_threshold`/`min_congruent_rank` were
  originally chosen with real reasoning documented, not picked arbitrarily.
- **B. A distinct third verdict tier**, e.g. `"congruent_but_isolated"` or
  `"strong_match_thin_relatives"`, fired when `congruent_evidence_exists_anywhere = TRUE`
  at high identity AND the species/genus has few real independent relatives in NCBI
  (already knowable from `n_top_matches_available`/genus-level accession counts) --
  keeps the existing vote-fraction logic completely unchanged, just adds a caveat-flagged
  escape hatch for this specific, identifiable situation instead of reweighting the core
  mechanism. Lower risk (doesn't touch the existing `"incongruent"`/`"congruent"` logic
  at all), but doesn't help a genuinely confusable-congener case if that turns out to be
  what's actually happening here (see the sister-species possibility above) -- a
  genuinely confusable pair shouldn't get waved through with a special tier, since that
  IS a real ambiguity worth a human look, not a false alarm to suppress.
- **C. Do nothing to the classification; rely on the identity diagnostics already
  shipped (2026-08-07) and reviewer judgment.** The columns needed to make this call by
  eye already exist (`best_agreeing_pident`, `best_disagreeing_pident`,
  `congruent_evidence_exists_anywhere`) -- this is the status quo, and it already
  correctly never auto-removes anything (`flag_incongruent_references()` is the
  recommended default, not `remove_incongruent_references()`). The cost is purely
  reviewer time on an at-scale audit, not correctness.

No recommendation is made between A/B/C here -- that's exactly the design work this
reentry prompt exists to defer, not to resolve prematurely. Do the BLAST-hit-identity
check above first; it may make the choice among these obvious (or reveal a fourth option
not listed here).

## Question 2: an LLM second-look reviewer for flagged accessions

**Real precedent exists and should be followed, not reinvented.**
`TaxaFlag::review_assignments()` already does exactly this shape of thing for posterior
taxonomic assignments: an LLM narrative-judgment layer added ON TOP of statistical
flags, never replacing them, never auto-acting -- it surfaces a reviewer-facing comment,
nothing more. The same pattern applied to `evaluate_reference_accessions()`'s flagged/
borderline output is a natural, low-risk extension, and there's real value an LLM adds
that the statistical checks structurally can't: recognizing "Ctenopharyngodon idella x
Megalobrama amblycephala" as a known Chinese aquaculture hybrid, recognizing "Serranidae
sp. JL-2015" as an informal specimen code, or noticing a real taxonomic literature fact
(a recent species split/synonymy) that would explain an apparent disagreement.

**Real design questions to resolve before writing code** (mirrors the exact list
`review_assignments()` itself had to answer, worth reading that function's own
implementation/roxygen as the starting template rather than designing from scratch):

- **What does the LLM see per accession?** At minimum: `listed_taxon`, `hierarchy_flag`,
  `finest_common_rank`, the identity diagnostics
  (`best_agreeing_pident`/`best_disagreeing_pident`/`congruent_evidence_exists_anywhere`),
  and (new, from today) `taxonomy_resolution_source`/`listed_taxon_is_species`. Open
  question: does it also need the actual disagreeing taxon's NAME (not currently
  retained in `evaluate_reference_accessions()`'s output at all -- would need a new
  column, or a fresh lookup)? Probably yes -- "flagged because it disagrees with X" is
  much more useful context than "flagged, disagreement fraction 0.8."
- **What does it output?** Following `review_assignments()`'s own precedent: a free-text
  reviewer comment, not a structured re-verdict -- avoids the exact trap Question 1's
  `trusted_rank` history warns about (an LLM re-deciding the verdict risks the same
  "computed on the wrong thing, silently overridden downstream" failure class; a comment
  a human reads before acting has no such risk).
- **Cost/scale**: the real Goal-2 population is ~1,183 accessions; a full Goal-1
  reference-database audit will be ~2,600+. Running an LLM call per accession for the
  WHOLE population is unnecessary and expensive -- scope this to the flagged/borderline
  subset only (`hierarchy_flag %in% c("incongruent", "insufficient_independent_evidence")`,
  plus now `listed_taxon_is_species == FALSE`), which today's real run puts at
  8 + 17 + 57 = 82 of 1,183 (~7%), a genuinely tractable batch size.
- **Where does it live?** Given the pattern match to `review_assignments()`, likely
  TaxaFlag (which already owns LLM-based post-hoc review) rather than TaxaMatch (which
  owns the statistical evaluation itself) -- but confirm this against TaxaFlag's actual
  current scope/dependency direction before assuming; TaxaMatch->TaxaFlag is not
  currently a dependency edge in this ecosystem and may not want to become one just for
  this. Worth a deliberate package-placement conversation before writing code, the same
  way `evaluate_reference_accessions()`'s own placement (TaxaMatch, not TaxaLikely) was
  argued through explicitly rather than assumed.

## What's already shipped, for context (2026-08-10/11, same broader thread)

Not part of what this reentry prompt defers -- already built, tested, and live:

- `TaxaMatch::evaluate_reference_accessions(barcode_term = "MiFishU")` amplicon-
  extraction plausibility-bound fix (was rejecting every genuine hit as "implausible"),
  fixed in both TaxaMatch and the duplicated `TaxaLikely::trim_to_amplicon()` algorithm.
- A real, pre-existing crash fixed: `evaluate_reference_accessions()` errored instead of
  degrading gracefully when 100% of a call's accessions failed BLAST (a real NCBI
  server-side CPU-budget total-rejection event).
- The hybrid-maternal-proxy mechanism itself (`taxonomy_resolution_source`
  `"hybrid_maternal_proxy"`/`"hybrid_unresolved"`), plus its generalization into
  `TaxaTools::clean_taxon_names(strip_modifiers = )` -- a curated, safety-vetted list of
  breeding/ploidy-manipulation terms (androgenetic, autodiploid, autotetraploid, etc.),
  deliberately NOT a generic "strip any leading lowercase word" (would risk silently
  rescuing genuine uncertainty-hedge words like "possible"/"putative" past the
  capital-letter filter).
- `evaluate_reference_accessions()` gains `listed_taxon_is_species` (via
  `TaxaTools::is_plausible_binomial()`, computed post-hoc, no new NCBI calls, no cache
  invalidation) -- a structurally different signal from both mislabeling and
  hybrid-labeling: does this reference even claim species-level resolution at all. Real
  yield on the GreatLakes population: 57 of 1,183 accessions (~5%) are not species-
  resolved -- genus-only "sp." entries, "cf."/"aff." tentative IDs, hybrid formulas,
  ploidy-manipulated lineages, and the original motivating family-level case
  ("Serranidae sp. JL-2015").

See `TaxaMatch/CLAUDE.md`'s 2026-08-10/11 session notes for the full implementation
record of all of the above.
