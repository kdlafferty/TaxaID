# Reentry prompt: cheap regional-proximity check for zero-in-bbox species (design idea, not built)

**Written 2026-08-20, companion doc to `REENTRY_PROMPT_invasive_species_watch_list_priors.md`
(same session, same underlying trigger).** The user reviewed GreatLakes2023 output after
the 2026-08-08/2026-08-20 GBIF-scope broadening fix (dynamic year range + unrestricted
`basisOfRecord`) and noted `Etheostoma chlorosomum` has real GBIF reports within ~100km
south of the study site -- mostly dated (older) records -- so the fish plausibly occurs
near, if not at, the study area, and its prior "might be a bit higher than we estimate."
Per the user's own framing, this should work "kind of like how we did an iNaturalist
check" -- i.e. a cheap, opportunistic secondary lookup for exactly the species that fall
through the cracks of the primary occurrence model, not a wholesale redesign of the
priors pipeline.

**The ~100km-south / dated-records claim is the user's own recollection, not
independently verified via a live GBIF query this session -- verify it directly (e.g. a
buffered-ring GBIF search around the study bbox) before using it to validate any design
choice below.**

## The problem, generalized

Same root cause as the invasive-watch-list doc: a species with zero occurrence records
*inside* the study bbox gets no `taxaexpect_priors` row at all and falls straight to
`generate_undetected_diversity()`'s generic global floor -- identical treatment whether
it has never been recorded within a thousand kilometers, or has real, recent, well-
corroborated records just outside the bbox edge. The 2026-08-20 `basis_keep`/year-range
fix (see `TaxaID/CLAUDE.md`) already fixed the closely related "the record was inside the
bbox but got filtered out" failure mode (museum specimens, stale year cutoff) -- this is
the next layer out: records that were never fetched in the first place because they sit
outside the bbox entirely.

Real, confirmed-this-session zero-in-bbox species from GreatLakes2023 (after the
basis_keep/year-range fix, so these are not artifacts of that bug):
`Etheostoma chlorosomum`, `Ictalurus furcatus`, `Alburnus alburnus` -- all three
confirmed via `raw_gbif.rds`/`occurrences_clean.rds` to have zero hits under the current,
already-broadened search. These are a real, small, checkable set to prototype against.

## Design sketch (not built, needs a real design session)

**Mechanism shape:** for a species with zero in-bbox occurrence records, run a cheap,
opportunistic buffered-region GBIF query (same idea as
`TaxaFetch::check_geographic_outliers()`'s existing global-fetch pattern, `R/
check_geographic_outliers.R` -- gated to species with few/zero LOCAL records, fetches a
wider search and reports back a verdict) but scoped to "nearby region" rather than
"anywhere on Earth." Report back at minimum: distance to the nearest real record, that
record's age, and some notion of habitat/basin connectivity (the user's own phrase: "known
from the same land or water mass" -- see below, this is the hard part).

**Open design questions, none resolved yet:**

1. **How far to search, and how to turn distance-plus-age into a prior adjustment.** A
   flat radius (e.g. 100km, matching the user's own example) is the simplest starting
   point, but a continuous decay (closer + more recent = more weight) is probably more
   defensible than a hard in/out cutoff -- similar in spirit to how
   `generate_domestic_food_priors()`'s ESS-based construction already turns "how much
   local evidence" into "how concentrated/diffuse the resulting Beta prior is," rather
   than a binary include/exclude.
2. **Record age.** The user explicitly flagged the Etheostoma chlorosomum records as
   "mostly dated" and said "I'm not sure what to make of them" -- old records could mean
   a real, still-extant nearby population never resurveyed, OR a range that has since
   contracted away from the study area, and occurrence data alone can't distinguish these.
   Whatever mechanism gets built should treat record age as a real, documented source of
   uncertainty (e.g. widening the resulting Beta rather than pretending a 40-year-old
   record and a 2-year-old record carry equal weight), not silently average over it.
3. **"Same land or water mass" -- the genuinely hard part.** Raw km distance is a poor
   proxy for a freshwater fish specifically: 80km within the same connected lake/river
   system is a completely different plausibility claim than 80km across a terrestrial
   drainage divide into an unconnected watershed. A real implementation likely needs
   either (a) a basin/watershed-connectivity data source (e.g. USGS Watershed Boundary
   Dataset HUC polygons -- same-HUC or adjacent-connected-HUC as a coarse connectivity
   test) rather than raw distance alone, or (b) for this specific Great Lakes study, a
   simpler hardcoded "same Great Lakes basin vs. not" categorical check that would NOT
   generalize to other TaxaID study systems (Mugu, PtConception are marine/coastal, where
   the connectivity question looks completely different again). Decide explicitly whether
   this needs a general, reusable primitive or a per-study judgment call -- don't build a
   false-generality abstraction if only one study currently needs it.
4. **Where the resulting prior lands.** Should be additive/flagged, not silently folded
   into the existing dark-diversity floor -- matches this ecosystem's repeated, hard-
   learned convention (`hierarchy_flag` kept additive rather than folded into
   `error_type`'s override chain; the `trusted_rank` ladder-walk built, then removed,
   specifically because a recomputing/overriding mechanism misfired -- see
   `[[project_rank_trust_mechanism_removed]]` in the memory system). Likely a new
   `undetected_type` value (alongside the existing `"singleton_mirror"`/`"global_floor"`)
   or a new `prior_source_type`, not a silent adjustment to the existing floor's alpha/
   beta.
5. **Relationship to the invasive-watch-list mechanism (companion doc).** Both answer a
   "how should a locally-absent species' prior differ from the generic floor" question,
   but from different evidence: this one is raw nearby-occurrence proximity (no human
   judgment about invasion status involved), the watch-list one is curated invasion-
   biology expertise (a human/database already decided this species is a real risk here,
   independent of whether anyone's recorded it nearby yet). Decide whether they should
   share underlying machinery (e.g. both feed into one generalized "external-evidence
   floor elevation" prior-source function) or stay fully separate mechanisms -- not
   resolved this session, and probably shouldn't be decided until at least one of the two
   is prototyped against real data.

## Not proposed as an iNat-only mechanism

The user's own phrasing ("kind of like how we did an iNaturalist check") suggests
`TaxaFetch::check_inat_range()`/`TaxaFetch::fetch_inat_occurrences()` as a possible
building block (an existing, cheap secondary-source check already used elsewhere in this
ecosystem for a related purpose -- iNat's own broader, less curated observation index can
surface records GBIF's stricter indexing misses). Worth checking whether iNat alone
already has enough regional signal for the real Etheostoma chlorosomum case before
building a GBIF-buffered-ring mechanism from scratch -- iNat may be the cheaper, simpler
first thing to try, with a GBIF buffered fetch as a fallback if iNat's own regional
coverage proves too thin.

## Resolved this session (2026-08-20, continued): mechanism design, largely settled

Design-only discussion continued the same day, no code written yet. Landed on a shape
that reuses existing TaxaFetch/TaxaFlag machinery almost entirely -- see below for exactly
what's new vs. what's just re-pointed.

**Mechanism, two stages:**

1. **Stage 1 (cheap gate):** `TaxaFlag::check_gbif_tile_range()`, unchanged, run against
   each zero-in-bbox species. Fully generic (any point, any taxon) -- this is the
   "opportunistic, cheap secondary lookup" the original framing called for. Most
   zero-in-bbox species are expected to come back empty even after escalation; that IS
   the answer, no further cost, no prior touched.
2. **Stage 2 (only for species Stage 1 finds something for):** a real, geographically
   SCOPED `TaxaFetch::fetch_gbif_occurrences()` call (bounded to a small buffer around
   the Stage 1 patch, not a global/unrestricted fetch) run through
   `TaxaFetch::filter_gbif_quality()` -- the same eDNA-exclusion/CoordinateCleaner/
   institution checks every other GBIF pull in this ecosystem already gets, resolving
   the "don't want this cheap fix to report errors" concern directly: a bad single
   record can trigger a wasted Stage 2 query but can never itself move a prior, since
   only the filtered survivors do -- then `TaxaFlag::compute_local_occurrence_distance()`
   against the survivors for the real distance. Needs one small, not-yet-built extension:
   that function doesn't currently return the matched record's `eventDate`/`year`, needed
   for age.

**Item 3 (basin/watershed connectivity) is DROPPED, not solved.** Explored a USGS
Watershed Boundary Dataset (HUC) point-in-polygon connectivity gate first, motivated by a
real case: much of the "~100km south of Lake Michigan" territory is Illinois River/Upper
Mississippi drainage, hydrologically separate from the Great Lakes basin except via the
artificial Chicago Sanitary and Ship Canal -- raw distance alone would misread this one.
**Explicitly rejected per the user's direction: this needs to stay simple and apply
across a wide range of taxa and geographic settings, and hydrological connectivity is a
Great-Lakes-specific solve, not a generalizable primitive worth the complexity.** Distance
is the only generic signal being used going forward. The geographic-plausibility judgment
(is a record 100km away actually reachable, given basin/dispersal-barrier structure) moves
to the LLM reviewer instead of a hardcoded rule -- new optional
`dist_nearest_regional_km_col`-style params on `TaxaFlag::review_assignments()`, matching
the exact established pattern already used there for GBIF-tile/iNat spatial context
(facts-only annotation, a conditional GUIDELINES bullet for interpretation, no
server-side rule).

**Prior-adjustment mechanism -- the harder question, how distance actually changes a
number.** Worked through via a concrete example: two species, both currently at the pure
dark-diversity floor, one with a real record 100km away, one 3000km away -- should these
get different priors, and how much? Landed on treating this as this ecosystem's own
recurring Empirical-Bayes-shrinkage pattern (same shape as `flag_contaminant()`'s
read-count shrinkage, `TaxaLikely`'s per-species shrinkage,
`generate_domestic_food_priors()`'s ESS construction) rather than inventing a new
mechanism: a new `undetected_type` value in `TaxaExpect::generate_undetected_diversity()`
whose theta is a distance-weighted BLEND of the two anchor values that function already
produces (`global_floor` and `singleton_mirror`), not a new prior source:

```
theta_regional = theta_floor + (theta_singleton - theta_floor) * w(d)
w(d) = exp(-d / d_half)      # saturating decay: w -> 1 as d -> 0, w -> 0 as d -> infinity
```

`d_half` (the distance at which the pull toward the singleton value has decayed halfway)
has **no universally defensible value** -- a freshwater darter's plausible unaided range
and a pelagic seabird's are different orders of magnitude, and this needs to generalize.
Resolved with the user: **ship a default, but make it a real, user-adjustable parameter
with clear roxygen documentation of exactly how it shapes the output** (matching, e.g.,
how `flag_contaminant()`'s `prior_weight` or `check_geographic_outliers()`'s `tdi` are
documented -- a default trustworthy enough to not touch, but overridable with real
understanding of the consequence) -- explicitly NOT the "no default, errors if omitted"
pattern this ecosystem uses elsewhere for parameters with no defensible number at all
(`join_priors(backbone_id=)`, `score_consensus(rank_thresholds=)`). Concrete numeric
default not yet chosen.

**Age's role stays separate from `d_half`/`w(d)`:** per the earlier same-day discussion,
age does not shift `theta_regional`'s mean -- it widens/narrows the resulting Beta's
concentration (older evidence = same point estimate, less effective sample size backing
it), keeping "how far" and "how stale" as two independent knobs rather than conflating
them into one composite score.

**Cross-reference for the parallel invasive-species-watch-list thread
(`REENTRY_PROMPT_invasive_species_watch_list_priors.md`): both mechanisms are now
shaping up as the same underlying move** -- a new `undetected_type` value in
`TaxaExpect::generate_undetected_diversity()` whose theta is a weighted blend of the
existing `global_floor`/`singleton_mirror` anchors, differing only in what drives the
weight (`w(d)` here vs. presumably a watch-list risk-tier-driven weight there). Worth
deciding explicitly, once both threads have landed on their own weight function, whether
they should share one general internal helper
(`.blend_undetected_prior(theta_floor, theta_singleton, w)`, callable from either
mechanism) rather than two independent implementations of the identical blend formula --
**not decided yet**, per the original item 5's own "don't decide until at least one is
prototyped against real data" deferral, still in force.

**Not yet implemented -- everything above is still design-only.** Next concrete steps, in
order: (1) extend `compute_local_occurrence_distance()` to surface the matched record's
date; (2) build the Stage 1 -> Stage 2 wrapper (a new, small function, not yet named);
(3) add the new `undetected_type` blend to `generate_undetected_diversity()`; (4) wire the
new distance/age facts into `review_assignments()`'s optional `_col` params. Verification
against the real `Etheostoma chlorosomum`/`Ictalurus furcatus`/`Alburnus alburnus`
zero-in-bbox cases (flagged at the top of this doc as still not done) remains the right
first real-data test once any of this is built.

## Resolved, 2026-08-21: implemented and live-verified

Items (3)/(4) above ended up superseded, not built as originally sketched, by a real-time
cross-session design negotiation with a parallel chat working
`REENTRY_PROMPT_invasive_species_watch_list_priors.md` (the same underlying "elevate the
dark-diversity floor for a named species given external evidence" problem, different
evidence source). Rather than each thread inventing its own `undetected_type` blend inside
`generate_undetected_diversity()`, the two threads converged on one shared applier:
**`TaxaExpect::apply_undetected_evidence(taxaexpect_priors, model_obj, evidence, grid_id,
main_habitat, ...)`** (built by the invasive-watch-list chat, TaxaExpect/CLAUDE.md's own
2026-08-20 note has the full design record) -- the single place a new elevated-prior row is
ever created, taking a thin, source-agnostic `evidence` table
(`taxon_name`/`weight`/`n_eff`/`source`) from any number of generators, combining multiple
sources per taxon via `w_combined = 1 - prod(1 - weight_i)`/`n_eff_combined = sum(n_eff_i)`,
and blending `theta_floor -> theta_singleton` by `w_combined`. This is architecturally
cleaner than the originally-sketched per-mechanism blend: it makes the "two evidence rows
for one taxon collide in `join_priors()`'s composite-key join" failure mode structurally
impossible, since only one function ever writes a row.

Item (1) is done: `TaxaFlag::compute_local_occurrence_distance()` gained `date_col`
(character or `NULL`, default `NULL`, fully backward compatible), surfacing the matched
nearest record's raw date/year as `nearest_date`.

Items (2)+(3)+(4) landed as **`TaxaExpect::generate_regional_proximity_evidence()`**
(`R/generate_regional_proximity_evidence.R`), this thread's own evidence generator for the
shared applier -- the Stage 1/Stage 2 design exactly as sketched above (Stage 1 =
`TaxaFlag::check_gbif_tile_range()`, a cheap gate; Stage 2 = a real, quality-filtered
`TaxaFetch::get_gbif_occurrences()` + `filter_gbif_quality()` fetch, scoped to a buffer
sized from Stage 1's own distance, only for species Stage 1 found something for). Distance
drives `weight = exp(-distance_km/d_half)`; record age drives `n_eff = n_eff_base *
exp(-age_years/age_half)` independently -- age widens/narrows confidence, never shifts the
mean, resolving this doc's own item 2 (record age) exactly as decided: an old record's
ambiguity (real unresurveyed population vs. contracted range) is represented as
uncertainty, not a directional discount. Item 3 (connectivity) was formally dropped from
scope, not solved -- see the design conversation above; the geographic-plausibility
judgment goes to a human/LLM reviewer instead.

**`review_assignments()` wiring (item 4) was NOT done** -- the shared-applier convergence
made it partly redundant (the elevated prior itself already carries the evidence's
`weight`/`n_eff`/`source` as audit columns via `apply_undetected_evidence()`'s output), and
wiring the raw distance/age facts into `review_assignments()`'s prompt context as an
*additional*, separate annotation (as originally sketched) is still a real, open, smaller
follow-up if a reviewer wants the raw numbers alongside the LLM's own judgment, not just the
resulting prior.

**Live-verified against the real GBIF API using the exact three species this doc's own
top section named as the real motivating case** (GreatLakes2023, lat=41.4/lng=-86.7):
`Etheostoma chlorosomum` resolved to a real record 74km away from 1986 (40 years old --
confirming this doc's own "mostly dated" recollection with a real number this time),
`weight=0.612`/`n_eff=0.347`; `Ictalurus furcatus` 83km/1999/`weight=0.575`/`n_eff=0.826`;
`Alburnus alburnus`'s nearest tile hit was ~1690km away, beyond the 1000km fetch-buffer
cap, so Stage 2 correctly found nothing and it got no evidence row at all -- a safe,
disclosed failure mode, not a wrong number. `TaxaFlag`/`TaxaExpect` `devtools::test()`/
`check()` both clean (419/419 and 641/641, 0/0/0). See `TaxaExpect/CLAUDE.md`'s and
`TaxaFlag/CLAUDE.md`'s own top session notes for the full record.

## Real-run consequence found + fixed, 2026-08-23: isolated-record safeguard ported from `build_invasive_candidates()`

Wired into `GreatLakes2023_ConsensusWorkflow.R` alongside the invasive-watch-list
mechanism (Step 7a.7c) and run against the real full dataset (885 observations). The
mechanism fires exactly as designed -- but far more broadly than intended: 143 of 307
`taxaexpect_priors` rows ended up regional-proximity-elevated, touching 751/885 (85%) of
observations, and **species-level resolution collapsed to 0% for every touched
observation** (vs. 8.2% for the 134 untouched by either evidence mechanism; 1.2% overall,
11/885). Root cause, found by direct inspection of the real output: for genus-heavy
congener groups (`Etheostoma`, `Salvelinus`, `Micropterus`, `Gambusia`), the mechanism was
finding a nonzero regional record for a large fraction of the ENTIRE North American
congener pool of some genera -- because it had no defense against a single isolated/
outlier GBIF record (a stray point, thermal-discharge refugium, aquarium escapee) counting
as "regional evidence," the exact failure mode `build_invasive_candidates()`'s own
benchmark work found and fixed (see the companion invasive-watch-list doc) THE SAME WEEK,
in a sibling tool -- but never ported back into this function, the one actually wired into
the live workflow.

**Fixed**: `generate_regional_proximity_evidence()` gains `near_lat_tolerance_deg` (default
`6`, ~660km) + `near_occurrence_min_n` (default `3L`), identical mechanism and defaults to
`build_invasive_candidates()`'s own tuned values -- a taxon's Stage-2-filtered occurrence
records must include a real CLUSTER within `near_lat_tolerance_deg` of the study latitude,
not just one nearest point; taxa with fewer total filtered records than
`near_occurrence_min_n` get the same proportional fallback (ALL of their few records must
be nearby). 8 new tests (isolated-far-record rejected, isolated-close-record accepted via
proportional fallback, insufficient-cluster rejected, sufficient-cluster accepted,
`near_occurrence_min_n = 0` disables the test, input validation). `devtools::test()`
672/672 (up from 641), `devtools::check()` 0/0/0, reinstalled.

**Re-run, live-verified the isolated-record safeguard fix works (2026-08-23/24):**
`Micropterus treculii`/`Notropis oxyrhynchus` (two of the real biogeographically-implausible
false positives the safeguard targets) now correctly rejected in a real, fresh, direct
call. Took several re-run cycles to actually SEE this confirmed in the real workflow's own
saved output -- not because the fix was wrong, but because of an entirely separate,
unrelated infrastructure problem (see below) that made the workflow's real output look
byte-for-byte identical to the pre-fix state across four consecutive re-runs, long after
the fix was correctly installed and verified in isolation.

## Real, separate root cause of "the fix has no effect," found and fixed 2026-08-24

Two distinct problems stacked on top of each other this week, and had to be diagnosed and
resolved in order:

**Problem 1 (real, but NOT the persistent one): 9 stale duplicate TaxaID package copies in
the macOS system R library** (`/Library/Frameworks/R.framework/Versions/4.5-arm64/
Resources/library/`), all ~1 month out of date, shadowing the correct, current copies at
`~/Library/R/4.0/library`. Removed. This was a real, confirmed problem worth fixing, but
turned out NOT to be what was still causing identical output after its removal --
confirmed directly by having the user check `packageDescription("TaxaExpect")$Built` in
their actual live session (correctly showed the current build) immediately before a run
that STILL produced the old, pre-fix numbers.

**Problem 2 (the actual persistent cause): a real, silent `rgbif::name_backbone_checklist()`
batch-request failure at real production scale.** `generate_regional_proximity_evidence()`
resolves every `zero_bbox_taxa` name to a GBIF key in ONE batched call
(`.resolve_gbif_taxon_keys_batch()`, added 2026-08-22 for a ~3x speed win over one call per
taxon). At the real GreatLakes2023 scale (333 zero-bbox candidate taxa in the run that
finally surfaced this), that single batched call failed outright with
`"Status: 0 - try lower bucket_size or larger sleep"` -- a transient GBIF-side rejection
NOT reproducible at the small batch sizes (4-11 names) this function's own tests and every
manual spot-check used, and NOT deterministic (an earlier, smaller real 156-candidate batch
from the same study succeeded fine at rgbif's own defaults). The function's original
single-attempt `tryCatch(error = function(e) NULL)` caught this identically to "nothing in
this batch resolved" and silently returned an all-`NA` result for literally every one of
the 333 taxa -- zero evidence rows, zero warning, zero indication anything had gone wrong.
This is what made the real workflow output look unchanged run after run: the mechanism was
never actually running the correctly-fixed per-species logic at all, it was failing before
ever reaching it, silently, at the very first step.

**Fixed**: `.resolve_gbif_taxon_keys_batch()` now retries up to 3 times with progressively
smaller `bucket_size`/larger `sleep` (300/1s -> 100/2s -> 50/3s -- exactly rgbif's own
suggested mitigation in that error message) before giving up, and emits a loud `warning()`
naming the real cause if every attempt still fails, instead of silently returning as if
genuinely nothing resolved. Live-verified against the exact real 333-name batch that
failed: 0/333 resolved before the fix, 327/333 after. 6 new tests (retry succeeds on a
later attempt with smaller bucket_size/larger sleep; loud warning on total failure;
regression guard that a clean first attempt doesn't retry or warn). `devtools::test()`
683/683 (up from 672), `devtools::check()` 0/0/0, reinstalled.

**Still not confirmed**: the full workflow has not yet been re-run end-to-end with BOTH
fixes in place (isolated-record safeguard + batch-retry). The run that surfaced Problem 2
had zero regional-proximity evidence rows for its entire 333-taxon candidate pool (a
complete resolution failure, not a "correctly rejected by the safeguard" result) --
`consensus_final` from that run should NOT be treated as representative of either fix's
real effect. A genuinely clean re-run, with both fixes and no infrastructure failure, is
the next real step.
