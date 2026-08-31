# Reentry prompt: invasive/nonindigenous species watch-list priors (design idea, not built)

**Written 2026-08-20, prompted by the user reviewing GreatLakes2023 output post the
basis_keep/year-range GBIF broadening fix** (see `TaxaID/CLAUDE.md`'s 2026-08-08 through
2026-08-20 entries for that unrelated fix's own record). The user noticed `Alburnus
alburnus` (European bleak) has zero GBIF occurrence records in the GreatLakes study bbox
-- correctly reflecting genuine local absence -- but pointed out it has a real North
American invasion record (Nova Scotia, ~2021, per the user's own domain knowledge, **not
independently verified via GBIF/NAS this session** -- verify before relying on it) that a
pure occurrence-based prior structurally cannot see. This prompted the broader question:
should species on documented invasive/nonindigenous watch lists get an elevated floor
prior, the way `generate_domestic_food_priors()` already does for domestic/commensal
species?

## The problem, generalized

Every prior source in TaxaExpect today (`generate_full_priors()`'s modelled Tier 1/2,
`generate_undetected_diversity()`'s Tier 3 dark-diversity floor) is occurrence-data-driven
-- theta is estimated from what's actually been recorded nearby. This is exactly right for
genuinely uncertain "is this taxon here" questions, but it structurally cannot distinguish
two very different kinds of "zero local records":

1. **Genuinely implausible** -- no reason to expect this species here, ever (the dark-
   diversity floor is doing its job).
2. **A known invasion-front species** -- established or spreading in a *different* basin/
   region, actively tracked by invasion-biology watch lists specifically *because* it's a
   plausible future arrival here, even with zero local detections yet.

Right now both collapse to the identical, generic, very low
`Beta(1, N_total - 1)`-style floor from `generate_undetected_diversity()`. A confirmed
BLAST/likelihood match to an invasive species candidate gets no help distinguishing "this
is a real early detection of a documented invasion risk" from "this is almost certainly a
contaminant/misidentification" -- exactly the discrimination problem
`generate_domestic_food_priors()` already solved for a structurally similar case (a
species absent from occurrence data for a reason unrelated to true rarity: human transport
of food/commensal species, rather than the slower spread of a wild invasion front).

## Why the domestic/food-priors architecture is the right template

`TaxaExpect::generate_domestic_food_priors()` (`R/generate_domestic_food_priors.R`,
shipped 2026-07-23, redesigned around match-list gating 2026-07-28) already solves the
adjacent problem: named-species priors, independent of local occurrence-model fitting,
gated to only check species actually in play this run (`match_list_taxa`), with a
`prior_source_type` categorical column so downstream consumers (`TaxaFlag::
add_posthoc_assessment()` already has a `domestic_taxa`/`domestic_prior_source` re-label
mechanism for exactly this kind of prior) can tell a "database-driven low tier" call apart
from an ordinary occurrence-modelled one.

An invasive-species-watch-list prior is the same shape: a curated/live-sourced taxon list,
match-list-gated, producing named rows with their own `prior_source_type` (e.g.
`"invasive_watch"` or `"nonindigenous_established"` -- see the tiering question below),
appended to the final priors table the same way `generate_domestic_food_priors()`'s output
already is (`dplyr::bind_rows()`-compatible, not routed through
`generate_full_priors(undetected=)`, per that function's own documented output contract).

## Design questions not yet resolved

1. **Data source: live query vs. curated list, or both (mirroring `domestic_animal_taxa`
   vs. `food_species_taxa`'s split).** USGS's Nonindigenous Aquatic Species (NAS) database
   (`nas.er.usgs.gov`) is the natural authoritative source for Great Lakes-relevant fish
   invasion risk -- **not yet checked this session whether it has a queryable API** (vs.
   only a web query interface, which would force a static/curated-list approach instead,
   the same fallback `generate_domestic_food_priors()`'s `known_cultivar_taxa`/
   `food_species_taxa` fixed lists already use for channels without a good live-query
   option). Check this first before committing to a design.
2. **Tiering by invasion status.** A species already established regionally (multiple
   confirmed populations, actively spreading) is a materially stronger prior case than a
   single vagrant/founder record in a distant, unconnected basin (the real
   `Alburnus alburnus` case as described -- one 2021 Nova Scotia record, not Great Lakes
   itself). Collapsing both to one flat elevated prior would likely over-state risk for the
   distant-founder case and under-state it for a genuinely established nearby invader.
   Consider at least two tiers (e.g. `"nonindigenous_established"` vs.
   `"nonindigenous_watch"`), each with its own ESS/ceiling, mirroring how
   `generate_domestic_food_priors()` already distinguishes `known_list` (immediate,
   unconditional) from `candidate_supplied`/`inat_confirmed` (requires corroborating live
   evidence) via `cultivar_evidence_source`.
3. **Regional scoping.** NAS (if it has a usable API) likely supports HUC (hydrologic unit
   code) or state-level query granularity -- need to determine the right unit for a
   bbox-scoped eDNA study, and whether "documented in an adjacent/connected basin" should
   weight differently than "documented on the other side of the continent." This overlaps
   conceptually with the regional-proximity design in
   `REENTRY_PROMPT_regional_proximity_prior_check.md` (companion doc, same session) --
   worth deciding whether these two mechanisms should share a "how close/connected is
   close enough" primitive, or stay fully independent (invasion-risk lists are curated by
   people who already made that judgment call; occurrence-proximity is a raw-distance
   computation with no such judgment baked in).
4. **Whether to require `match_list_taxa` gating at all**, given the whole point is to
   catch species that *wouldn't* otherwise be a modelled candidate. Unlike
   `generate_domestic_food_priors()` (where match-list gating is a real cost-saving
   optimization over checking hundreds of default-list species blind), an invasive-watch
   list is presumably much smaller and more targeted -- gating may be unnecessary
   engineering overhead here. Decide once the real candidate list size is known.
5. **Package placement.** Following `generate_domestic_food_priors()`'s precedent, this
   belongs in TaxaExpect (prior generation), not TaxaFlag (post-hoc flagging) or TaxaFetch
   (data acquisition) -- though the live NAS query itself, if built, is arguably a TaxaFetch
   concern (`fetch_inat_occurrences()`/`fetch_gbif_occurrences()`-style acquisition
   function) with `generate_domestic_food_priors()`'s sibling then consuming it, exactly
   mirroring how `fetch_inat_occurrences()` (TaxaFetch) feeds
   `generate_domestic_food_priors()` (TaxaExpect) today.

## Real motivating case, for context

GreatLakes2023 (BurnsHarbor, 12S), post the 2026-08-20 GBIF-scope broadening fix (dynamic
year range + unrestricted `basisOfRecord`, confirmed live to recover several previously-
missing PRESERVED_SPECIMEN-only species -- see `TaxaID/CLAUDE.md`'s matching entry):
`Alburnus alburnus` still has **zero** raw GBIF records anywhere in the study bbox
(confirmed via direct inspection of `GreatLakes2023BurnsHarbor_raw_gbif.rds` and
`_occurrences_clean.rds`), correctly reflecting genuine local absence under any
occurrence-based model -- there is no occurrence-data fix that would ever surface this
species locally, unlike the PRESERVED_SPECIMEN species the same-session fix did recover
(`Minytrema melanops`, `Notropis stramineus`, `Moxostoma duquesnii`, `Etheostoma
microperca`, all with real, non-zero local GBIF hits once museum specimens were included).
This is exactly the class of case an occurrence-based prior structurally cannot help with,
and exactly the class of case an invasion-watch-list prior source would.

## Resolved, same session (2026-08-20): IMPLEMENTED, redesigned once, converged with the
## companion regional-proximity mechanism

**First pass (built, then removed the same day):** a live USGS Nonindigenous Aquatic
Species (NAS) API query (confirmed real and working, no key needed) plus HUC8 watershed
scoping (via a live USGS Watershed Boundary Dataset lookup), two tiers driven by NAS's own
`status` field. Real, load-bearing finding from checking the API before committing (per
this doc's own design question 1): NAS is US-only and has **zero** entries for `Alburnus
alburnus` -- the species that motivated this whole doc -- confirmed via NAS's full
1,515-species catalog plus a live global GBIF cross-check (133 real 2019-2021 Canadian
eDNA `MATERIAL_SAMPLE` records exist, but with no vouchered specimen and no
NAS-trackable establishment signal). Corrected directly by the user: TaxaID is meant to
stay a generic, taxon-/geography-agnostic toolkit; baking a narrow (aquatic-only, US-only)
database and freshwater-specific watershed math into a package function was the wrong
move. Both `TaxaFetch::fetch_nas_occurrences()`/`lookup_huc8()` were deleted the same
session -- see `TaxaFetch/CLAUDE.md`'s removal note.

**Final design, reached via real-time cross-session coordination with
`REENTRY_PROMPT_regional_proximity_prior_check.md`'s chat** (both mechanisms answer the
identical "external evidence this locally-undetected species is more plausible than the
generic floor" question, from different evidence -- curated list membership here, raw
occurrence distance/age there -- and the user required them to compose additively, capped
at the singleton-mirror ceiling, which forced the shared design):

- `invasive_taxa` is now a **plain user-supplied character vector** -- no live query, no
  region-scoping logic of its own. Region-scoping happens entirely in how the caller
  builds the list (e.g. hand-pull a NAS export, restrict it to species relevant to your
  own basin, pass it in).
- `TaxaExpect::generate_invasive_watch_evidence(invasive_taxa, weight, n_eff,
  match_list_taxa = NULL)` -- a thin evidence generator, no Beta math. `weight`/`n_eff`
  required, no default; tiering (if wanted) is repeated calls + `bind_rows()`, not a
  built-in tier system.
- `TaxaExpect::apply_undetected_evidence(taxaexpect_priors, model_obj, evidence, grid_id,
  main_habitat, ...)` -- the single shared applier (also consumed by the regional-
  proximity mechanism), the only place a new evidence-elevated row is ever written.
  Blends `theta_floor -> theta_singleton` (the site's own singleton-mirror mean) by the
  taxon's combined weight; combines multiple sources per taxon via
  `w_combined = 1 - prod(1 - weight_i)` / `n_eff_combined = sum(n_eff_i)`. New
  `undetected_type = "evidence_blend"`. Deliberately excludes
  `generate_domestic_food_priors()` as a valid source (opposite claim about the same
  zero-detection fact -- contamination-risk vs. genuine-population).

See `TaxaExpect/CLAUDE.md`'s top session note for the full mechanical derivation
(including why blending toward the singleton anchor beats an arbitrary multiplier: a free,
principled ceiling), the real `TaxaAssign::join_priors()` composite-join-key finding that
shaped the `grid_id`/`main_habitat`-required signature, and the real end-to-end pipeline
verification.

## REAL-DATA VERIFIED, 2026-08-21 -- wired into `GreatLakes2023_ConsensusWorkflow.R`

Integrated into the real production workflow (`~/My Drive/Stats and Data/GreatLakes data/
GreatLakes2023_ConsensusWorkflow.R`) as new Step 7a.7b, right after the existing domestic-
food-priors step, since `taxaexpect_priors`/`match_list_taxa`/`SITE_GRID_ID`/`SITE_HABITAT`/
`taxonomy_lookup_full` are all already built there. New Section 0 user inputs:
`INVASIVE_TAXA` (a starter list -- Round Goby *Neogobius melanostomus* + Ruffe
*Gymnocephalus cernua*, both real, well-documented Great Lakes AIS -- flagged in the script
itself as a placeholder for the user's own real NAS pull, not a final answer),
`INVASIVE_WATCH_WEIGHT = 0.6`, `INVASIVE_WATCH_N_EFF = 4`.

**Real run result, confirming the mechanism does exactly what it's designed to do, not
just that it executes without error:**
- *Gymnocephalus cernua* (Ruffe) -- zero occurrence-based evidence in this dataset,
  correctly elevated: `theta_mean = 0.0375` (`alpha = 0.150`, `beta = 3.85`,
  `evidence_weight = 0.6`, `evidence_sources = "invasive_watch"`).
- *Neogobius melanostomus* (Round Goby) -- correctly LEFT ALONE, not elevated, because it
  already has a real, occurrence-fitted `tier1` model row (`theta_mean = 0.0141`,
  `undetected_type = NA`) -- confirmed directly by the user querying
  `taxaexpect_priors` after the fact. This is real GBIF occurrence density doing its job:
  Round Goby is common and well-recorded enough in the Great Lakes that the ordinary
  occurrence model already gives it a real prior, so the dark-diversity evidence mechanism
  (scoped deliberately to species with ZERO occurrence evidence anywhere) correctly stayed
  out of the way rather than double-counting or overriding real data.

This is the first confirmation that `apply_undetected_evidence()`'s "already observed"
exclusion logic (checked via both `taxon_name` and `source_taxon_name`) behaves correctly
against a real, messy production `taxaexpect_priors` table, not just synthetic test
fixtures. The motivating `Alburnus alburnus` case itself remains unaddressed by design --
NAS doesn't track it -- but the mechanism itself is now proven end to end on real data.

## `INVASIVE_TAXA` replaced with the full GLANSIS Great Lakes Watch List, 2026-08-21

The starter 2-species list above was replaced with the real, official, live-queried
GLANSIS (NOAA Great Lakes Aquatic Nonindigenous Species Information System) Watch List --
27 species, `SpeciesCategory=4` at
`https://nas.er.usgs.gov/queries/greatLakes/SpeciesList.aspx?Group=Fishes`. Citation: NOAA
GLERL, https://www.glerl.noaa.gov/glansis/. See `GreatLakes2023_ConsensusWorkflow.R`
Section 0 for the full vector.

## `build_invasive_candidates.R` -- a general NAS-distance-based candidate builder, benchmarked against GLANSIS, latitude-tightened -- 2026-08-21 through 2026-08-23

`~/My Drive/Stats and Data/GreatLakes data/build_invasive_candidates.R` (NOT a TaxaID
package function, deliberately -- see the file's own header comment) is a reusable,
site-agnostic tool that AUTOMATES what curating `INVASIVE_TAXA` by hand requires: filter
the full USGS NAS species catalog by taxon group + habitat + `native_exotic`, then keep
only species with a real NAS occurrence footprint near the study site. Built to be portable
across GreatLakes/Mugu/PtConception via plain `study_lat`/`study_lon`/`taxon_group`/
`habitat_values` arguments.

**Benchmarked directly against GLANSIS's real Watch List (27 species) and Established List
(45 species), at the user's explicit request** ("build_invasive_candidates should have a
similar final effect on the priors as GLANSIS does... I'm surprised you don't seem
worried"). Two distinct findings, both real, neither fixed by more tuning:

1. **Recall ceiling, structural, NOT fixable by this approach**: 52% of GLANSIS's own
   Watch List (14/27 species) has literally ZERO occurrence records anywhere in NAS -- NAS
   tracks established/documented US occurrences, not the "not here yet but plausible"
   forward-looking judgment GLANSIS's own watch list embodies. Any NAS-occurrence-distance
   approach has a hard ceiling around 50% recall against a real expert-curated watch list,
   permanently -- this is a fundamental data-source limitation, not a bug.
2. **Precision gap, real, and addressable**: the reverse check (of NAS-distance-only
   candidates NOT on GLANSIS, how many are real vs. noise?) found the bulk were
   climate-implausible tropical aquarium-trade species passing purely on the strength of
   ONE isolated/outlier occurrence record (a stray record, or a real but climatically
   artificial thermal-discharge refugium) while >95% of that species' real occurrence
   footprint sat many latitude degrees south.

**Fixed 2026-08-23**: `build_invasive_candidates()` gained `near_lat_tolerance_deg`
(default 6, ~660km) + `near_occurrence_min_n` (default 3) -- a candidate must now have a
real CLUSTER of occurrence records near the study site's latitude, not just one nearest
point passing `max_distance_km`. Species with fewer total records than the count threshold
get a proportional fallback (ALL of their few records must be near) rather than an
impossible bar. Validated directly against the real GreatLakes/GLANSIS benchmark data
already in hand, entirely from cache (no new NAS API calls needed):
- Candidate count: 69 -> 54 (15 removed), **zero recall loss** against either GLANSIS list
  (watch-list overlap held at 7/27, established-list overlap held at 10/45).
- All 15 species removed are genuine tropical/warm-water aquarium-trade or aquaculture
  escapees (gouramis, pacus, peacock bass *Cichla*, severums, angelfish, tilapia, plecos,
  Asian swamp eels *Monopterus*, snakehead *Channa maculata*, iridescent shark catfish) --
  confirming the fix targets the real pattern broadly, not just the 2 species that
  motivated it.
- The first attempt used a tighter 3-degree tolerance, which incorrectly cost a real, well-
  documented invader: *Gymnocephalus cernua* (Ruffe, 2,310 real NAS records) was dropped
  because its established population sits in the Lake Superior/Duluth basin, ~5 degrees
  latitude from a southern-Lake-Michigan study site -- the Great Lakes basin itself spans
  more latitude than a tight tolerance allows, even though it's one connected system.
  Widened to 6 degrees, which recovers Ruffe while still excluding the tropical false
  positives. *Carassius carassius* (Crucian carp, 1 real NAS record, genuinely close) also
  required the proportional-fallback fix, since a flat count-of-3 threshold could never be
  cleared by a species with only 1 total record regardless of proximity.

## Cross-reference, 2026-08-24: unrelated infrastructure bug in the companion regional-proximity mechanism, invasive-watch-list itself unaffected

While debugging why the companion `generate_regional_proximity_evidence()` mechanism's
fix appeared to have "no effect" across several re-runs (see
`REENTRY_PROMPT_regional_proximity_prior_check.md`'s own 2026-08-24 entry for the full
trace), found and fixed a real, silent `rgbif::name_backbone_checklist()` batch-request
failure at real production scale (333 candidate taxa) -- `.resolve_gbif_taxon_keys_batch()`
now retries with progressively smaller `bucket_size`/larger `sleep` and warns loudly
instead of silently returning zero evidence for the whole batch. This function is private
to `generate_regional_proximity_evidence()` (`TaxaExpect/R/generate_regional_proximity_
evidence.R`) -- `generate_invasive_watch_evidence()` does its own, separate, much smaller
GBIF resolution (bounded by `INVASIVE_TAXA`'s ~27-species GLANSIS list, never anywhere
near the batch size that triggered this) and was not affected. Noted here only because
both mechanisms write into the same `taxaexpect_priors` table via the shared
`apply_undetected_evidence()` applier, and the run that surfaced the regional-proximity
failure also had 0 regional-proximity rows for its entire run -- so any `consensus_final`
checkpoint from that specific run should not be treated as representative of either
mechanism's real combined effect. A clean re-run with both fixes in place is still needed.

Saved result: `gl_invasive_candidates_lat_tightened.rds` (54 matched species, GreatLakes,
Freshwater fish, `native_exotic == "Exotic"` only). Not yet wired into
`GreatLakes2023_ConsensusWorkflow.R`'s `INVASIVE_TAXA` (which currently uses the full
GLANSIS list directly, above) -- this tool's real value is as a candidate-discovery aid /
cross-check for curating that list, or for sites like Mugu/PtConception that don't have a
GLANSIS-equivalent expert-curated list to draw on directly. Still pending: port to Mugu
(`habitat_values = c("Freshwater","Marine","Brackish")`) and PtConception
(`habitat_values = "Marine"`).
