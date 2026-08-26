# CLAUDE.md — TaxaExpect
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-08-26, continued (Fable 5, branch undetected-evidence-mixture --
# Chunk B: apply_undetected_evidence() now emits the PRESENCE MIXTURE itself
# (prior_mix_w/prior_mix_theta_present/prior_mix_theta_absent/prior_mix_p_conc) and
# MOMENT-MATCHES the Beta summary's concentration to the mixture variance
# (v = w*Var_c + (1-w)*Var_f + w(1-w)*(theta_c-theta_f)^2; n_eff_mm = m(1-m)/v - 1,
# ~2 at this dataset's anchors) -- the free caller-chosen n_eff is RETIRED (errors
# with migration guidance when supplied without p_conc). Evidence schema: required
# taxon_name/weight/source; optional p_conc (default 1) = how much weight the
# presence claim carries against future evidence -- NOT the static prior (derived
# insight, documented in roxygen: for a two-point presence mixture, uncertainty
# about w cancels out of the marginal variance, so record age honestly cannot
# change today's prior; it changes the claim's weight in the Phase 3 confirmation
# update). generate_invasive_watch_evidence(): n_eff param -> p_conc (default 1);
# generate_regional_proximity_evidence(): n_eff_base RETIRED, p_conc =
# exp(-age_years/age_half) (fresh record = one pseudo-observation). All 6 real
# production workflows' call sites updated (INVASIVE_WATCH_N_EFF -> _P_CONC).
# Verified on real GreatLakes2023 data: rebuilt all 121 evidence rows under the new
# schema with blend means byte-identical (max delta 1.7e-18). devtools::test()
# 694/0, devtools::check() 0/0/0, reinstalled. See TaxaAssign/CLAUDE.md's top note
# for the sampler + the three-way operative-column experiment result.
# Previous update, 2026-08-26 (Fable 5, branch undetected-evidence-mixture --
# apply_undetected_evidence() gains a ceiling anchor LADDER for datasets without
# singleton mirrors, Phase 1 (D2) of the undetected-evidence mixture redesign
# (ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md). Previously,
# a taxaexpect_priors table with zero singleton_mirror rows silently set the blend
# ceiling EQUAL to the floor -- every elevation became a weight-independent no-op (with
# only a warning). The upper anchor's meaning is "the detection rate of a species
# present but rare enough to have plausibly escaped local detection," which does not
# require singletons to estimate; the ceiling now descends: (1) singleton-mirror mean
# (unchanged when mirrors exist); (2) minimum theta among genuinely modelled rows,
# site-scoped rows preferred, excluding tier_undetected_evidence/tier_domestic_food
# named rows (a no-singleton dataset detected every species >= 2 times, so min
# modelled theta mildly OVERestimates the present-but-undetected rate -- conservative
# in the safe direction); (3) 1/(median site n_obs + 1), i.e. what a singleton's rate
# would have been; (4) only when none is computable, the old floor-equals-ceiling
# warning. Companion change, same session, other package: TaxaAssign::join_priors()'s
# modelled-species floor promotion no longer promotes evidence_blend/domestic rows to
# singleton parity (see TaxaAssign/CLAUDE.md's own top note for the full record --
# that clamp had been silently erasing every weight/distance/age gradation this
# package's evidence generators compute, verified on real GreatLakes2023 data).
# Existing "no singleton rows" test rewritten for the ladder + 3 new tests (site-
# scoped min preference; effort fallback; evidence/domestic rows never serve as the
# anchor). devtools::test() 689 passed/0 failed (up from 665), devtools::check()
# 0/0/0, reinstalled and live-verified via the review's ablation harness (see the
# TaxaAssign note for the real numbers). Phase 2 (w = P(present) mixture semantics,
# moment-matched n_eff, per-dataset distance-curve fit, iNat evidence generator) not
# yet started -- see the reentry doc.
# Previous update, 2026-08-23 (Sonnet 5 -- real-production confirmation of the synonym-resolution
# fix directly below: the user re-ran generate_regional_proximity_evidence() against the full
# real 194-taxon GreatLakes2023 zero_bbox_taxa list post-fix. Result: 5 of 194 taxon/taxa
# elevated (up from the pre-fix 0 of 194), and apply_undetected_evidence() correctly added 5
# new prior rows to taxaexpect_priors. Confirms the fix holds at real production scale, not
# just against the single isolated Erimonax monachus case verified at implementation time.
# Pure verification, no code changes.
# Previous update, 2026-08-22, continued (Sonnet 5 -- a real, more serious PRE-EXISTING bug
# found the moment the batching change directly below was actually run at real production
# scale (194 real GreatLakes2023 zero_bbox_taxa): the user reported "0 of 194 taxon/taxa
# elevated" despite the console log clearly showing dozens of real Stage 2 fetches
# returning real, quality-filtered occurrence records (26/33, 43/49, 7/9, etc.). Rather
# than assume the batching change was at fault, verified directly against the user's own
# real GBIF keys from that log (`rgbif::name_usage(key=...)`): several real GreatLakes
# fish taxon names are GBIF SYNONYMS, not the currently-accepted name -- e.g. the query
# "Erimonax monachus" resolves to usageKey 2367386, GBIF status SYNONYM, whose real
# occurrence records all report the ACCEPTED name "Cyprinella monacha" in their own
# `species` field. GBIF's occurrence search transparently expands a synonym key to its
# accepted key's real records (confirmed: the fetch succeeds, 26 real records survive
# quality filtering) -- but `compute_local_occurrence_distance()`'s exact-string match
# was comparing those records' `species` field against the ORIGINAL query name, which can
# never match a record correctly filed under the accepted name. This bug was NOT
# introduced by the batching change below -- it existed identically in the original,
# pre-batching `.resolve_gbif_taxon_key()` (which also discarded GBIF's own resolved
# `species` field, keeping only the usageKey) -- it simply was never exercised by the
# original 3-species validation, since none of those three (`Etheostoma chlorosomum`/
# `Ictalurus furcatus`/`Alburnus alburnus`) happen to be under active GBIF synonymy.
#
# Fixed by having `.resolve_gbif_taxon_keys_batch()` also capture and return GBIF's own
# accepted `species` name for the resolved key (already present in the real
# `name_backbone_checklist()` response, just previously discarded) -- `generate_regional_
# proximity_evidence()`'s Stage 2 matching now uses that resolved name, not the original
# query string, to find the taxon's own records within the fetched/filtered occurrence
# data. The OUTPUT `taxon_name` column still reports the original query name unchanged --
# the caller's own priors table is keyed by whatever naming convention `zero_bbox_taxa`
# itself used (NCBI-native, in this real workflow), and this internal GBIF-name
# substitution must never leak into that join key.
#
# Live re-verified against the exact real case from the user's own log: querying
# "Erimonax monachus" now correctly resolves the same real key (2367386), fetches the
# same real 33/26 records, and produces a real evidence row (609km, 1974, weight=0.017,
# n_eff=0.156) instead of silently vanishing -- while the two previously-working species
# (`Etheostoma chlorosomum`/`Ictalurus furcatus`) reproduce byte-identical numbers to
# before this fix, confirming no regression to the already-correct non-synonym path.
# 6 new tests (2 end-to-end via `generate_regional_proximity_evidence()` including a
# negative-control test proving the ORIGINAL query name genuinely fails to match, 4 direct
# `.resolve_gbif_taxon_keys_batch()` unit tests). `.resolve_gbif_taxon_keys_batch()`'s
# return shape changed from a named numeric vector to a tibble (`taxon_name`/`usage_key`/
# `gbif_species`) to carry the new field -- purely internal (`@noRd`, never exported), no
# public signature affected. `devtools::test()` 665/665 (up from 654), `devtools::check()`
# 0/0/0, reinstalled and verified at `~/Library/R/4.0/library`.
# Previous update, 2026-08-22 (Sonnet 5 -- generate_regional_proximity_evidence()'s per-taxon
# GBIF-key resolution replaced with ONE batched rgbif::name_backbone_checklist() call,
# prompted by the user asking whether more efficient GBIF query modes exist for this
# function's "one taxon at a time" Stage 0 step. Investigated empirically (live rgbif
# tests, not assumed) before touching any code, since the same question has two very
# different answers depending on which GBIF call is involved:
#
# Stage 0 (name -> GBIF usageKey): a REAL batching win. `name_backbone_checklist()`
# resolves a whole vector of names in one HTTP round trip; live-tested against 11 real
# taxon names (9 real species, 1 bare genus, 1 fictional name): 11 individual
# `name_backbone()` calls took 3.51s, 1 batched call took 1.17s (3x on this tiny sample,
# scaling much better at real production list sizes since the batched call stays O(1)
# round trips regardless of N, chunked by rgbif's own `bucket_size` only above 300).
# Correctness verified identical between the two modes for every one of the 11 names,
# INCLUDING the pathological case that originally motivated this whole thread's rank
# validation: "Ictalurus" (a bare genus) resolves to Chordata at PHYLUM rank under BOTH
# individual and batched calls -- the same wrong-but-consistent GBIF fuzzy-match behavior,
# so `.resolve_gbif_taxon_key()`'s existing `rank == "SPECIES"` validation needed zero
# changes, just applied per-row instead of per-call (new `.resolve_gbif_taxon_keys_batch()`,
# matches results back to input names via the response's own `verbatim_name` column, never
# by row position/order).
#
# Stage 2 (occurrence fetch): investigated and explicitly REJECTED as a batching
# opportunity, based on real evidence, not assumption. `rgbif::occ_data(taxonKey = vector)`
# looks like a single batched call but isn't -- confirmed directly
# (`attr(result, "type") == "many"`, a nested per-key list, one real HTTP request issued
# per key internally) -- and `TaxaFetch::fetch_gbif_occurrences()`'s own internal
# `.fetch_chunk()` does the identical thing (a plain `for` loop calling `occ_data()` once
# per key). So the ecosystem's existing "combine several taxa into one
# `get_gbif_occurrences()` call" convention (`TaxaFetch::fetch_occurrences_by_taxon()`) is a
# code-convenience abstraction -- fewer R calls to write, shared caching/retry machinery --
# NOT a real reduction in GBIF network requests. A live 5-key test confirmed this: 5
# individual `occ_data()` calls took 1.95s; the "batched" vector-taxonKey call took 2.48s
# (slower, plus it structurally can't be treated as one data frame the way `$data` alone
# suggests). Given this, restructuring Stage 2 to share buffer geometry across taxa was
# rejected -- it would only complicate the code (losing each taxon's own precisely-sized
# buffer) for zero actual latency benefit. Stage 1 (`TaxaFlag::check_gbif_tile_range()`) was
# also confirmed to have no batching option at all -- GBIF's density-tile API is one raster
# per `(taxonKey, z/x/y)`, with no bulk-occupancy endpoint to call instead.
#
# Live end-to-end re-verified against the installed package, real GBIF, the exact three
# species this whole design thread's reentry doc names as the motivating case
# (Etheostoma chlorosomum/Ictalurus furcatus/Alburnus alburnus, lat=41.4/lng=-86.7): produces
# BYTE-IDENTICAL real numbers to the original (pre-batching) live verification -- 74km/1986/
# 40yr, weight=0.612/n_eff=0.347 for E. chlorosomum; 83km/1999/27yr, weight=0.575/n_eff=0.826
# for I. furcatus; Alburnus correctly beyond-buffer, no evidence row. `devtools::test()`
# 654/654 (up from 641 -- 16 new tests: multi-taxon batching call-count guard, 4 direct
# `.resolve_gbif_taxon_keys_batch()` unit tests covering out-of-order matching, mixed
# resolved/rejected/missing names, and graceful all-NA degradation on error/empty response,
# plus every pre-existing mock updated from `name_backbone` to `name_backbone_checklist`).
# `devtools::check()` 0/0/0. Reinstalled and verified at `~/Library/R/4.0/library`.
#
# Also fixed the same session: 3 real, pre-existing test failures surfaced by running
# TaxaExpect's FULL suite for the first time since the 2026-08-21 `clean_taxon_names()`
# fix landed (that fix's own verification only ran TaxaTools's and TaxaMatch's suites, not
# TaxaExpect's) -- `test-generate_domestic_food_priors.R`'s `expect_equal(out$taxon_name,
# "Felis catus")`-style assertions (3 of them) failed on the new `collapsed_to_genus`
# attribute `clean_taxon_names()` now attaches, exactly the same class of pre-existing-test
# fragility already fixed in TaxaTools's own test suite -- fixed identically here
# (`ignore_attr = "collapsed_to_genus"` added to the 3 affected assertions). Grepped the
# whole monorepo for any other `clean_taxon_names()`-comparing test file
# (`TaxaMatch/tests/testthat/test-evaluate-reference-accessions.R`,
# `test-convert_taxonomy_backbone.R`) -- both already passed cleanly (verified in that
# session's own full-suite runs), so this was the only fallout ecosystem-wide.
# Previous update, 2026-08-21, same day continued (Sonnet 5 -- real bug found and fixed on the
# FIRST live run of generate_regional_proximity_evidence() against the real
# GreatLakes2023_ConsensusWorkflow.R (wired into a new Step 7a.7c the same session, right
# after the invasive-watch block): internal .resolve_gbif_taxon_key() requests
# rgbif::name_backbone(name=, rank="species"), but that `rank` argument is only a matching
# HINT, not an enforced constraint -- confirmed live, a bare genus name ("Ictalurus" alone,
# candidate #3 of 350 real zero-in-bbox taxa) resolved successfully anyway, returning the
# GENUS's own usageKey, and proceeded through Stage 1/Stage 2 as if it were a real species.
# Fixed the same way this exact codebase has fixed the identical class of bug before
# (convert_taxonomy_backbone()'s "Inu Inu" fix, get_keys_from_context()'s kingdom-narrowing
# fix): check the RESOLVED rank from the response (res$rank, GBIF's own field) explicitly,
# reject anything that isn't exactly "SPECIES" the same as no match at all, rather than
# trusting the requested rank. 2 new tests (a mocked GENUS-rank response is rejected before
# ever reaching Stage 1; a response missing the rank field entirely is also treated as no
# match). devtools::test() 644/644 (up from 641), devtools::check() 0/0/0. Reinstalled,
# verified against the installed copy directly. See
# ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md's own "Resolved" section.
# Previous update, 2026-08-21, later same day (Sonnet 5 -- generate_regional_proximity_evidence()
# added (R/generate_regional_proximity_evidence.R), the regional-proximity thread's own
# evidence generator for apply_undetected_evidence() (built the same week by a parallel
# cross-session chat -- see the entry directly below). Two-stage design: Stage 1 (cheap gate)
# resolves each candidate's GBIF backbone key (new internal .resolve_gbif_taxon_key(),
# rgbif::name_backbone()) and calls TaxaFlag::check_gbif_tile_range() -- species with
# beyond_buffer = TRUE cost nothing further, no evidence row. Stage 2 (real, filtered fetch,
# only for species Stage 1 found something for) scopes TaxaFetch::get_gbif_occurrences() to a
# buffer sized from Stage 1's own reported distance (clamped [min_buffer_km, max_buffer_km],
# default [50, 1000]), runs it through TaxaFetch::filter_gbif_quality() -- the eDNA/
# coordinate-quality screening Stage 1's raw density tiles structurally cannot provide -- then
# reads the real distance and matched record's age via
# TaxaFlag::compute_local_occurrence_distance(), extended this session with a new date_col
# param (character or NULL, default NULL -- fully backward compatible, surfaces the nearest
# record's raw date/year value as a new nearest_date output column only when requested).
# weight = exp(-distance_km/d_half) (default d_half=150); n_eff = n_eff_base *
# exp(-age_years/age_half) (defaults n_eff_base=5/age_half=15) -- age drives confidence
# independently of distance's mean-shift, never discounting the mean itself, since an old
# record could reflect either a real unresurveyed population or a genuinely contracted range
# and occurrence data alone can't distinguish those. All three (d_half/age_half/n_eff_base)
# ship with a default but are fully documented/overridable per explicit user direction (NOT
# this ecosystem's usual "no default, errors if omitted" convention for values with no
# defensible number -- there is no universal dispersal-distance/staleness scale across taxa,
# but the user wanted a usable starting point, not a forced per-call decision every time).
# Watershed/basin connectivity was explicitly explored and then dropped from scope earlier in
# this same design thread (a real Chicago-Sanitary-and-Ship-Canal-style counterexample was
# worked through) -- this package needs to stay simple/generic across taxa and geography, and
# the geographic-plausibility judgment goes to a human/LLM reviewer (see
# TaxaFlag::review_assignments()'s existing GBIF-tile-context pattern) instead of a hardcoded
# gate.
#
# Live-verified against the real GBIF API (not just the offline mocked test suite) using the
# exact three species the original reentry-doc session flagged as the real motivating case
# (Etheostoma chlorosomum/Ictalurus furcatus/Alburnus alburnus, GreatLakes2023 coordinates):
# E. chlorosomum resolved to a real record 74km away from 1986 (40 years old -- a real number
# now, confirming the reentry doc's own "mostly dated" recollection), weight=0.612/
# n_eff=0.347; I. furcatus 83km/1999/weight=0.575/n_eff=0.826; A. alburnus's nearest tile hit
# was ~1690km away, beyond the 1000km fetch-buffer cap, so Stage 2 correctly returned nothing
# and the species got no evidence row at all rather than a fabricated number -- a safe
# failure, not a wrong one.
#
# 27 new tests in test-generate_regional_proximity_evidence.R (fully offline -- mocks
# rgbif::name_backbone/TaxaFlag::check_gbif_tile_range/TaxaFetch::get_gbif_occurrences/
# TaxaFetch::filter_gbif_quality at the network boundary; TaxaFlag::
# compute_local_occurrence_distance() is genuinely real and unmocked underneath, same
# "mock only the network boundary" convention TaxaFetch's own
# test-check_geographic_outliers.R established): every skip condition (no GBIF match, Stage 1
# beyond_buffer, Stage 2 zero rows, everything filtered out), multi-taxon batches (one
# failure doesn't block another success; duplicates checked once), the no-usable-year ->
# n_eff == n_eff_base-exactly case, and the weight/n_eff formulas checked against the
# function's own real returned distance (not a hardcoded assumed value -- a first draft of
# one test asserted against Stage 1's coarse tile distance instead of Stage 2's real
# haversine distance and failed against the correct code, fixed by correcting the test, not
# the code). New TaxaFlag Suggests dependency. `devtools::test()` 641/641 (up from 614),
# `devtools::check()` 0 errors/0 warnings/0 notes. Reinstalled via
# ecosystem_docs/install_all.R, verified against the installed copy directly. See
# ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md's new "Resolved" section
# and TaxaFlag/CLAUDE.md's own top session note (the compute_local_occurrence_distance()
# date_col extension) for the full cross-package record.
# Previous update, 2026-08-21 (Sonnet 5 -- REAL-DATA VERIFICATION of apply_undetected_evidence()/
# generate_invasive_watch_evidence() (built 2026-08-20, see the entry directly below for the
# full design record), wired by the user into the real production
# GreatLakes2023_ConsensusWorkflow.R (new Step 7a.7b, after the existing domestic-food-priors
# step). Real run result: Gymnocephalus cernua (Ruffe), with zero occurrence-based evidence in
# this dataset, correctly elevated to theta_mean = 0.0375 (alpha=0.150, beta=3.85,
# evidence_weight=0.6, matching INVASIVE_WATCH_WEIGHT); Neogobius melanostomus (Round Goby),
# despite also being on the same INVASIVE_TAXA list, correctly LEFT UNTOUCHED because it
# already carries a real, occurrence-fitted tier1 model row (theta_mean = 0.0141,
# undetected_type = NA) -- confirmed live by the user querying taxaexpect_priors directly.
# This is the "already observed" exclusion logic (checked via both taxon_name and
# source_taxon_name) working correctly against a real, full-scale production
# taxaexpect_priors table for the first time, not just synthetic test fixtures -- the
# mechanism correctly stayed out of the way of a species GBIF already has real local evidence
# for, rather than double-counting or overriding it. No code changes this session (pure
# verification); see ecosystem_docs/REENTRY_PROMPT_invasive_species_watch_list_priors.md's own
# new "REAL-DATA VERIFIED" section for the full record, including the exact
# GreatLakes2023_ConsensusWorkflow.R wiring (Section 0 constants + Step 7a.7b).
# Previous update, 2026-08-20, continued yet further (Sonnet 5 -- generate_invasive_watch_priors()
# (the same-day NAS-API/HUC8-based design, previous session note below) REPLACED by a
# fundamentally redesigned mechanism, reached through a real-time cross-session design
# negotiation with the concurrent chat building ecosystem_docs/REENTRY_PROMPT_
# regional_proximity_prior_check.md's companion mechanism -- see that doc and its own
# session for the full two-way record; summarized from this side below.
#
# Trigger: the user reviewed the NAS-based design and corrected the architecture directly --
# TaxaID is meant to stay a generic, taxon-/geography-agnostic toolkit; baking a narrow
# (aquatic-only, US-only) external database and freshwater-specific watershed math into a
# package function was the wrong move (see TaxaFetch/CLAUDE.md's matching removal note for
# fetch_nas_occurrences()/lookup_huc8(), deleted the same session). Redesigned around a plain
# user-supplied taxon list instead -- "if on this list AND not observed, elevate the prior,"
# no live query, no region-scoping logic of its own.
#
# Working out the actual mechanics (there is no per-species "dark diversity prior" object to
# elevate -- generate_undetected_diversity() emits exactly ONE anonymous global_floor row;
# TaxaAssign::join_priors() applies it generically to any unmodelled candidate at join time)
# surfaced that the regional-proximity chat's mechanism answers the SAME underlying question
# with different evidence (list membership vs. distance/age decay) and both were converging
# on an identical shape: blend the floor toward the site's own singleton-mirror mean by a
# weight, rather than an arbitrary multiplier -- blending toward the singleton anchor gives a
# free, principled ceiling (external evidence, however strong, can never make an unobserved
# species look more plausible than one genuinely detected once), which an arbitrary
# "multiply by X, cap somewhere" design has to hand-roll.
#
# The user then required the two mechanisms compose ADDITIVELY (a species both nearby AND
# invasive-listed should read higher than either alone, still capped at the singleton
# ceiling) -- this exposed a real design flaw in having each mechanism independently
# construct and bind_rows() its own finished prior row into taxaexpect_priors (what
# generate_domestic_food_priors() already does, and what the NAS-based design was about to
# do too): two mechanisms elevating the same species produces two rows sharing one
# taxon_name, an ambiguous join_priors() join. Fixed architecturally, not by patching around
# it: split each mechanism into a thin EVIDENCE GENERATOR (returns taxon_name/weight/n_eff/
# source, no Beta math, no knowledge of taxaexpect_priors or of other sources) and one SHARED
# APPLIER that is the only place a new row is ever written -- multi-source collisions on the
# join key become structurally impossible rather than a burden on whichever workflow author
# remembers to combine channels correctly. Weight combination across sources:
# w_combined = 1 - prod(1 - weight_i) (probabilistic-OR); n_eff (confidence/concentration,
# proposed by the regional-proximity chat to generalize "record age" without the applier
# needing to know WHY a source is less sure) combines via sum(n_eff_i). The independence
# assumption behind the OR formula is stated explicitly in the applier's own roxygen, per the
# other chat's direct citation of this exact codebase's own precedent
# (TaxaAssign::update_prior_from_consensus()'s Session 149 finding that a probabilistic-OR/max
# combination across CORRELATED donor confirmations manufactures spurious confidence) -- the
# two sources here are independent by construction (a curated database vs. raw occurrence
# geography), but a future source correlated with an existing one would need this revisited.
#
# generate_domestic_food_priors() is DELIBERATELY EXCLUDED from this shared applier, per the
# user's own catch: a food/domestic detection and an occurrence-plausibility detection
# (invasive-watch, regional-proximity) are opposite claims about the same zero-local-record
# fact (contamination-risk vs. genuine-population), so OR-combining them would conflate two
# different questions into one number. A taxon flagged both ways is a real case, left for a
# future TaxaFlag::add_posthoc_assessment()-style dual caveat, not blended here.
#
# Real, load-bearing correction found mid-negotiation by reading TaxaAssign::join_priors()'s
# actual source (not assumed): its primary join key is the FULL composite
# (taxon_name, taxon_name_rank, grid_id, main_habitat), not taxon_name alone -- so any
# elevated-evidence row needs a real, matching grid_id (and main_habitat, when the model uses
# one) to ever take effect; a generic/NA-scoped row would silently never match a real
# observation. This also surfaced (confirmed empirically by the other chat against real
# GreatLakes2023 data, immediately fixed) that generate_domestic_food_priors() itself had
# been silently inert for habitat-scoped workflows this whole time -- see the "Previous
# update, later same day" note directly below for that fix and the new join_priors()
# habitat-agnostic fallback tier it needed. apply_undetected_evidence() deliberately does NOT
# use that habitat-agnostic tier -- occurrence-plausibility evidence stays habitat-AWARE
# (a freshwater species found nearby is only locally plausible in a freshwater habitat, a
# real constraint domestic/food priors don't share), so both grid_id and main_habitat are
# required parameters here, not optional.
#
# Implementation: new apply_undetected_evidence() (R/apply_undetected_evidence.R, the shared
# applier) and generate_invasive_watch_evidence() (R/generate_invasive_watch_evidence.R, this
# side's thin evidence generator) replace generate_invasive_watch_priors()/its test file
# entirely (deleted, no deprecation shim -- added and removed same session, zero real
# callers). New undetected_type value, "evidence_blend", alongside the existing
# "singleton_mirror"/"global_floor". Live-verified end to end through the REAL pipeline (not
# just synthetic fixtures): create_sites_from_grid() -> prepare_model_dataframe() ->
# train_biodiversity_model() -> generate_undetected_diversity() -> generate_invasive_watch_
# evidence() -> apply_undetected_evidence(), confirming a real singleton-derived ceiling and
# floor blend correctly (theta_floor ~= 1/66 = 0.0152, weight = 0.6, output theta_mean =
# 0.2061, consistent with a real singleton anchor near 0.33). devtools::test() 614/614 (a net
# -6 vs. the NAS-design's 586 -- 20 tests removed with generate_invasive_watch_priors(), 18 +
# 10 = 28 new across the two new files), devtools::check() 0 errors/0 warnings/0 notes.
# Reinstalled to ~/Library/R/4.0/library. See TaxaFetch/CLAUDE.md's matching removal note and
# ecosystem_docs/REENTRY_PROMPT_invasive_species_watch_list_priors.md's own "Resolved" section
# for the full record, including the complete message-by-message cross-session negotiation.
# Previous update, 2026-08-20, later same day (Sonnet 5 -- generate_domestic_food_priors()
# gains taxon_name_rank = "species" on every emitted row, fixing a real, previously-
# undetected production bug: this column was never set, defaulting to NA via bind_rows(),
# so TaxaAssign::join_priors()'s primary composite-key join (taxon_name, taxon_name_rank,
# grid_id, main_habitat) could never match a domestic-food prior row against any real
# observation (which always carries a real taxon_name_rank). Confirmed on real GreatLakes2023
# data (a real Gadus morhua food-fish row, added by the user, alpha=5/beta=8775, theta ~=
# 0.00057) -- never applied; the affected observation instead got theta ~= 0.000167, the
# ordinary group-dark-diversity fallback, ~3.4x lower than this function actually computed
# for it. main_habitat is deliberately left NA, NOT stamped with a real value -- a food/
# domestic species has no single correct habitat (its plausibility is governed by human food
# supply, not local habitat suitability, and one grid_id can span several real habitats);
# the correct fix for THAT half lives in TaxaAssign::join_priors(), which now treats an
# NA-habitat named-species row as habitat-agnostic (applies to any habitat at that grid_id)
# rather than requiring an impossible exact match -- see TaxaAssign/CLAUDE.md's own note.
# Found while cross-session-collaborating with a parallel design chat
# (ecosystem_docs/REENTRY_PROMPT_invasive_species_watch_list_priors.md) on a shared
# evidence-combination mechanism that would need the identical habitat-agnostic-row pattern;
# tracing why the cited precedent (this function) "already handled it" surfaced that it
# didn't. 3 new tests in test-generate_domestic_food_priors.R (every row carries
# taxon_name_rank = "species"; the empty-result schema includes the column; main_habitat
# stays NA while taxon_name_rank is newly set). devtools::test() 586/586 (up from 580),
# devtools::check() 0 errors/0 warnings/0 notes. Reinstalled via ecosystem_docs/install_all.R,
# verified against the installed copy directly.
# Previous update, 2026-08-20 (Sonnet 5 -- initiates ecosystem_docs/REENTRY_PROMPT_
# invasive_species_watch_list_priors.md: new generate_invasive_watch_priors()
# (R/generate_invasive_watch_priors.R), architecturally mirroring
# generate_domestic_food_priors() -- named taxon_name rows (not anonymous Tier 3 proxies),
# match_list_taxa-gated, prior_source_type categorical column, model_tier =
# "tier_invasive_watch". Answers the same structural gap generate_domestic_food_priors()
# solved for domestic/commensal species, this time for documented invasion-front species:
# generate_undetected_diversity()'s dark-diversity floor can't distinguish "genuinely
# implausible here" from "a known invasion risk with zero local detections yet, tracked
# specifically because it's a plausible arrival." Consumes TaxaFetch::fetch_nas_occurrences()
# (new this session, see TaxaFetch/CLAUDE.md's own top note for the live-API verification and
# the real US-only-scope finding re: Alburnus alburnus).
#
# Two design decisions this session settled, both grounded in real data fetched from the live
# NAS API rather than guessed (see TaxaFetch/CLAUDE.md's matching note for the API
# verification): (1) TWO TIERS, not one flat elevated prior, driven directly by NAS's own
# per-record `status` field -- `"nonindigenous_established"` (an established/stocked NAS
# record inside the caller's own `study_huc8`) vs. `"nonindigenous_watch"` (established
# elsewhere in the US, or only a weak-status in-region record). A NAS-tracked species with
# only weak-status records all OUTSIDE `study_huc8` gets no row at all -- deliberately, per
# the reentry doc's own explicit caution against over-stating risk for a distant, unconnected
# vagrant/founder record. (2) `study_huc8` is REQUIRED, no default -- same "no safe universal
# value" convention as `join_priors(backbone_id=)`/`score_consensus(rank_thresholds=)`; a
# study's own HUC8 is a real, study-specific fact `TaxaFetch::lookup_huc8()` (new, live USGS
# Watershed Boundary Dataset query) can derive from coordinates, closing the reentry doc's own
# open "regional scoping" design question without needing a separate watershed-connectivity
# primitive built from scratch. `match_list_taxa` is likewise required (no unrestricted
# fixed-list fallback the way `generate_domestic_food_priors()` has one) -- NAS's ~1,500-
# species catalog is checked ONLY against a run's own real candidates, since blind-checking
# the whole catalog against every study would be both wasteful and mostly irrelevant.
#
# **Known, deliberate, documented limitation, not fixed this session**: NAS is United
# States-only, so a foreign-only detection -- the REAL case that originally motivated this
# whole design, a 2019-2021 Canadian eDNA detection of *Alburnus alburnus* in Nova Scotia --
# gets no elevated prior from this function at all. Confirmed live before building anything
# (per the reentry doc's own explicit "check this first" instruction) and presented to the
# user directly via AskUserQuestion before proceeding; user chose "NAS only, for now,"
# explicitly declining a global-GBIF-fallback channel that was offered as an alternative. See
# both this function's own `@section Scope` and `TaxaFetch::fetch_nas_occurrences()`'s.
#
# Live-verified end to end against the real NAS/WBD APIs (not just devtools::test()/check()):
# a real BurnsHarbor-area Lake Michigan point resolves to HUC8 "04040001" via
# `lookup_huc8()`; a full run against that HUC8 with `Gymnocephalus cernua` (Ruffe, a real,
# famous Great Lakes invader) in `match_list_taxa` correctly returns
# `"nonindigenous_watch"`, NOT `"nonindigenous_established"` -- NAS's own establishment
# records for Ruffe concentrate in the Lake Superior/Duluth-Superior basin, a DIFFERENT HUC8
# than this southern-Lake-Michigan test point, so the tier mechanism correctly distinguishes
# "established somewhere in the US" from "established in THIS region" on real data, not just
# a synthetic fixture. `Alburnus alburnus` and `Homo sapiens` (not NAS-tracked) correctly
# produced zero rows in the same real run.
#
# `devtools::test()` 580/580 (up from 555 -- 20 new tests, fully offline via
# `local_mocked_bindings()` on `TaxaFetch::fetch_nas_occurrences()`, same cross-package
# mocking pattern `test-generate_domestic_food_priors.R` already established for
# `TaxaFetch::fetch_inat_occurrences()`), `devtools::check()` 0 errors/0 warnings/0 notes.
# Reinstalled to `~/Library/R/4.0/library` (required a fresh TaxaFetch install first --
# `local_mocked_bindings()` needs the binding to exist in the INSTALLED package's namespace,
# not just the source tree, to mock it). See TaxaFetch/CLAUDE.md's own top session note for
# the acquisition-side (`fetch_nas_occurrences()`/`lookup_huc8()`) implementation record, and
# the reentry doc itself for the full design history including the still-open ESS-calibration
# and regional-proximity-mechanism-sharing questions.
# Previous update, 2026-08-04 (Sonnet 5 -- TaxaExpect's first full code review RESPONSE pass
# against inst/taxaexpect_review.Rmd (the checklist-template review itself predates this
# session; see inst/taxaexpect_review_response.md for the complete file-by-file record).
# Three real doc/logic bugs fixed: optimize_grid_size()'s own @examples passed
# grid_sizes=/min_species=, neither a real parameter of the function (would error if run);
# plot_theta_map_interactive()'s docs pointed at a plot_theta_map() function that does not
# exist anywhere in this codebase (confirmed via monorepo-wide grep); build_priors()'s
# habitat_scheme[[1]] read whichever column happened to be first in a custom habitat_scheme
# data frame instead of the specific column TaxaHabitat::build_habitat_prompt()'s own
# validator actually requires (l1_name) -- fixed to read l1_name when present.
#
# New grid_size propagation chain (the main structural addition): create_sites_from_grid()
# now records attr(result, "grid_size") <- grid_size; prepare_model_dataframe() propagates
# it through (both the single-group and sampling_group_col-split paths);
# train_biodiversity_model() stores it as $meta$grid_size; generate_full_priors() attaches
# it to its own output as attr(result, "grid_size"). plot_theta_map_interactive() now reads
# this attribute for the grid-cell half-width instead of always inferring it from centroid
# spacing (falls back to the original inference when the attribute is absent, e.g. older/
# hand-built priors objects) -- closes the review's "isn't the grid resolution also
# knowable?" finding. Verified end-to-end with a live smoke test (not just unit tests):
# create_sites_from_grid() -> prepare_model_dataframe() -> train_biodiversity_model() ->
# generate_full_priors(), confirming the attribute survives all three hops.
#
# compute_moran_basis() gains a new `coords` parameter (data frame of grid_id/lat/lon):
# when supplied, used directly instead of re-parsing grid_id's own string encoding (falls
# back to string-parsing only for any grid_id missing from coords); `coords = NULL` (the
# default) preserves the original behavior exactly. Both compute_moran_basis.R's own
# .parse_grid_id_basis() and plot_theta_map_interactive.R's separately-implemented
# .parse_grid_id() (a real, pre-existing duplication the review flagged) are now deleted in
# favor of one shared TaxaExpect:::.parse_grid_id_coords() (new R/utils_internal.R).
# TaxaExpect:::.beta_mean()/.beta_sd() and TaxaExpect:::.dark_diversity_rank_cols (also new
# in R/utils_internal.R) similarly consolidate a beta-distribution mean/SD helper and a
# genus/family/order/class/phylum rank-column vector that were each reimplemented
# identically in generate_full_priors.R, generate_undetected_diversity.R, and/or
# generate_domestic_food_priors.R.
#
# One breaking (but zero-real-caller) change: `compute_adaptive_sampling_groups(min_n =)`
# lost its `100` default and is now required -- matches this ecosystem's established
# "no safe universal default" convention (join_priors(backbone_id=), score_consensus(
# rank_thresholds=)); a viable per-site record count varies by orders of magnitude across
# study designs, and this function has never been wired into any production workflow
# (confirmed via a monorepo- and ~/My-Drive/Rscripts-wide grep), so this is zero-risk.
#
# Also: prepare_model_dataframe()'s internal .run_one_group closure (previously nested
# inside the exported function with its ~140-line body left at the SAME indentation level
# as the enclosing function, rather than one level deeper) extracted to a proper top-level
# TaxaExpect:::.prepare_one_group(data, covariates, habitat_col) helper with explicit
# params and correct indentation, and its aggregation logic converted from deeply nested
# dplyr calls to native pipes, matching this project's own stated convention. Six examples
# across add_pca_covariates()/apply_pca_transform()/create_sites_from_grid()/
# optimize_grid_size()/compute_moran_basis()/compute_adaptive_sampling_groups()/
# prepare_model_dataframe() fixed to be runnable (previously several referenced
# nonexistent objects or, in optimize_grid_size()'s case, nonexistent parameters).
# `.score_one_resolution()`'s internal (non-exported) argument list reduced from 10 to 5
# by bundling column names into a `site_cols` list and thresholds into a `thresholds` list.
#
# ~20 review items were considered and explicitly declined, most notably: renaming the
# `data`/`formula` parameters used by 5+ functions (matches TaxaMatch's own already-
# recorded precedent for declining the identical `data`-rename ask, plus a real, larger
# blast radius here -- ~20 named `data =` call sites found across several real external
# eDNA production workflow scripts, some of unconfirmed current status); redesigning
# habitat_col from character-or-NULL to a logical flag (would directly undo the 2026-07-03
# fix for a real shipped bug -- see that date's entry further below); splitting
# screen_spatial_formula() into separate fit/select functions or renaming it; folding
# train_biodiversity_model_by_group() into train_biodiversity_model(groups=) (the latter
# deliberately REFUSES multi-group data as a safety check, so absorbing grouping into it
# would undermine the check's own point). Two cross-package findings flagged but not fixed
# here (out of this package's scope): TaxaHabitat::assign_habitat_biological()'s "0 site(s)
# assigned 'Other'" message firing unconditionally, and .he() (HTML-escaping helper)
# duplicated between this package and TaxaHabitat. See inst/taxaexpect_review_response.md
# for the complete file-by-file record, including every declined item's full reasoning.
#
# `devtools::test()` 555/555 (up from 538), `devtools::check()` 0 errors/0 warnings/0
# notes, reinstalled to `~/Library/R/4.0/library`.
# Previous update, 2026-08-03 (Sonnet 5 -- screen_spatial_formula() gains generalized covariate
# screening. Found live, building a real continuous depth/elevation habitat covariate for
# GreatLakes2023_ConsensusWorkflow.R (motivated by a real finding: 95% of "Lentic"-classified
# GBIF occurrences were >50km offshore, dominated by genuinely pelagic species -- the
# harbor's own prior was being driven by open-lake ecology, not anything resembling a
# nearshore site). prepare_model_dataframe()'s `covariates=` argument is already fully
# generic (its own roxygen even uses "depth" as an illustrative example), but
# screen_spatial_formula() had never been updated to match -- it hardcoded recognition of
# only `lat_r_s`/`lon_r_s` as screenable continuous covariates, both in the VarCorr
# pre-screen filter (a literal regex, `"^B[0-9]+$|^lat_r_s$|^lon_r_s$"`) and in the whole
# candidate-formula-building mechanism. A newly-added `depth_m_s` term was therefore fit as
# a real random slope but completely invisible to this function's own model-selection
# machinery: never shown in the VarCorr table, never a candidate for removal, its AIC
# contribution never tested -- silently baked into every candidate formula regardless of
# whether its variance was meaningfully non-zero. Found only because the user noticed
# `depth_m_s` was simply absent from a real run's printed VarCorr table despite being in
# the final recommended formula.
#
# Fixed by reading the real covariate list off `prepare_model_dataframe()`'s own
# `scale_params` attribute (one entry per covariate it scaled, keyed by the raw covariate
# name) instead of a hardcoded name pair -- generalizes to ANY covariate passed to that
# function's `covariates=` argument, not just the original two. Verified first that this
# attribute survives a `dplyr::left_join()` with a Moran spatial basis (the real usage
# pattern in these workflows) before relying on it. Falls back to the original hardcoded
# `c("lat_r_s","lon_r_s")` pair when the attribute is absent (hand-built data/older
# callers), so this is fully backward compatible -- confirmed via a dedicated new test.
# Re-run against the real GreatLakes data post-fix: `depth_m_s` now correctly appears in
# the VarCorr table with SD=1.35 -- the LARGEST of any screened term (more than double
# `lon_r_s`'s 0.585) -- correctly not flagged for removal; species differ far more in
# depth-response than in raw lat/lon response. User confirmed "depth stays" after seeing
# this. 2 new regression tests (a 3rd covariate is screened when `scale_params` is
# present; the old hardcoded-pair fallback is unchanged when it's absent).
# `devtools::test()` 541/541 (up from 538), `devtools::check()` 0 errors/0 warnings/0
# notes, reinstalled to `~/Library/R/4.0/library`. See
# `[[project_depth_covariate_propagation]]` in the memory system for the full real-data
# motivating finding and what does/doesn't transfer to the Mugu/PtConception workflows.
# Previous update, 2026-07-31 (Sonnet 5 -- TaxaExpect's first full code + domain review against
# inst/Code and Domain Review 2.Rmd, closing a real gap: every other package in the ecosystem
# (TaxaTools, TaxaFetch, TaxaMatch, TaxaLikely) already had one, TaxaExpect never did. Findings
# and fixes recorded together in inst/taxaexpect_review.Rmd (new file), following the
# taxafetch_review.Rmd precedent. A background research pass read every R file against the
# template; every High-severity claim was then independently re-verified live before being
# trusted -- none were false positives at that tier. Six real functionality bugs found and
# fixed, most with real production consequence: (1) compute_moran_basis()'s eigen(M, symmetric
# = TRUE) was silently wrong for any real, irregular grid -- M was built from a row-
# standardised (asymmetric) adjacency matrix, and eigen() with symmetric=TRUE reads only the
# lower triangle with no error, producing a completely different spatial basis with no warning
# at all; fixed by building M from the underlying binary (already symmetric) adjacency matrix
# directly. (2) generate_full_priors()'s "principled" phi cap looked up
# VarCorr(...)$cond[["taxon_name.grid_id"]] (a period) when glmmTMB actually names this
# "taxon_name:grid_id" (a colon, confirmed live) -- the lookup always returned NULL, silently
# falling back to a hardcoded max_phi=1000 on every call using this package's own documented
# recommended formula. (3)/(4) prepare_model_dataframe()'s and train_biodiversity_model_by_
# group()'s sampling_group_col grouping both silently dropped every NA-grouped row (base R's
# split()/sort() default NA-dropping behavior, confirmed live) -- fixed by keeping NA as its
# own explicit group and switching to positional (not by-name) list indexing throughout, since
# list[[NA]] returns NULL rather than the actual element (the same footgun compute_adaptive_
# sampling_groups.R had already independently worked around -- that file, not the other two,
# was the correct reference pattern). prepare_model_dataframe() also had dplyr::bind_rows()
# silently keeping only the FIRST group's scale_params attribute value across every group
# after it (confirmed live) -- fixed via a new scale_params_by_group attribute. (5)
# create_sites_from_grid()'s grid_id used a fixed sprintf("%.1f", ...), silently colliding two
# genuinely distinct grid cells for any grid_size < 0.1 (confirmed live: 34.05 and 34.10 both
# format to "34.1") -- fixed by deriving decimal precision from grid_size itself. (6)
# optimize_grid_size() had two related bugs: .safe_normalise() masked +-Inf to NA without ever
# restoring the correct 1/0 value, silently disqualifying a resolution with the theoretically
# best stability score from ever being selected (NA sorts last via arrange(desc(...))); and
# Fallback C's single_grid_size formula does not actually guarantee single-cell pooling for an
# arbitrary bbox position (confirmed live with a real counterexample) -- fixed by verifying and
# growing the grid size against the real coordinates instead of trusting the unverified
# closed-form formula. A further Medium bug (train_biodiversity_model()'s Tier 2 empirical
# fallback averaged theta only over DETECTED rows, a conditional "typical rate given detected"
# instead of the marginal prevalence the docs implied -- systematically inflated for rare
# species) and a Medium UI bug (plot_theta_map_interactive()'s occ_sel() used == instead of
# %in%, a live recurrence of the exact NA-ghost-row bug class this same file was already
# debugged for once on 2026-07-24) were also found and fixed, plus several smaller domain/
# doc-accuracy findings (a default food-species name, "x Triticosecale", that can never survive
# TaxaTools::clean_taxon_names() and was silently dropped every call; report_priors()'s
# n_grid_cells missing the NA-guard its own n_taxa already has). Two pre-existing tests that
# directly encoded the old buggy .safe_normalise() behavior as their expected result were
# rewritten to assert the fix, not left broken or silently reverted. Also swept: non-ASCII
# characters in 5 files (comments/roxygen only, ecosystem-standard cleanup); a new .lintr (this
# package never had one, unlike every sibling); most real lintr findings fixed, a documented
# residual of short conventional matrix-notation variable names (W, I, M, N_total) left as
# .lintr exclusions rather than mechanically renamed across compute_moran_basis.R for cosmetic
# gain only. A live, currently-blocking roxygen2 8.0.0-vs-declared-7.3.3 incompatibility was
# also found and fixed (4 multi-line @importFrom blocks, a pre-existing ecosystem-wide pattern,
# errored under the newer parser) -- needed to get this session's own roxygen edits into the
# compiled man/ pages at all. devtools::test() 538/538 (up from 536), devtools::check() 0/0/0,
# reinstalled to ~/Library/R/4.0/library. See inst/taxaexpect_review.Rmd for the full record.
# Previous update, 2026-07-28 (Sonnet 5 -- generate_domestic_food_priors() re-implemented
# around the match-list-gated architecture confirmed with the user 2026-07-24 but not
# built until now. Two new params: match_list_taxa (character vector of taxa with real
# likelihoods this run -- e.g. unique(match_obj$taxon_name[taxon_name_rank=="species"]);
# NULL preserves the original unrestricted behavior exactly) and taxaexpect_priors
# (optional, used only to shrink the open-discovery residual pool). New 4th fixed-list
# channel, known_cultivar_taxa (216 species, patched immediately like the other two
# fixed lists -- no live check required), built from the same food-crop-genus
# cross-reference as the newly-extended food_species_taxa default (449 species, up from
# 20 -- both baked in from the scratch CSV classification work done 2026-07-24, cleaned
# further this session: 13 cultivated-food-fungi species found mixed into the source
# CSVs moved from known_cultivar_taxa into food_species_taxa, one bred cereal
# (Triticosecale) moved the same way, one non-ASCII entry dropped). New output columns:
# cultivar_evidence_source ("known_list"/"candidate_supplied"/"inat_confirmed" -- lets
# a caller tell apart the fixed-list patch, a user-supplied confirmed candidate, and an
# open-discovery-confirmed candidate, all three sharing prior_source_type =
# "domestic_plant" per the user's explicit choice). The open-discovery residual step
# (match-list taxa not already covered by a fixed list or an existing named prior,
# restricted to phylum %in% c("Streptophyta","Tracheophyta")) is deliberately NOT
# pre-restricted to known_cultivar_taxa or any other list -- the user caught this as a
# self-defeating design in an earlier draft, since the whole point of a live check is to
# catch what nothing anticipated. Real bug found and fixed during testing: when all four
# fixed/supplied channels are empty, dplyr::bind_rows() of all-empty/NULL inputs produces
# a zero-COLUMN tibble, not just zero rows -- candidates$taxon_name then errored
# downstream once match_list_taxa gating tried to reference it; fixed by giving the
# empty-candidates branch an explicit schema. Test file fully rewritten (91 tests, up
# from 50) -- also fixes a real test-suite hazard found live: several existing tests
# didn't zero out the new known_cultivar_taxa channel and weren't mocking
# fetch_inat_occurrences() in one case, so they silently iterated the (now large) default
# list against a real or accidentally-broad mock, hanging one test run past 120s.
# All four real production workflows (PtConceptionWorkflow_12S/18S_2_single_site.R,
# MuguFishWorkflow.R, MuguWilderFishWorkflow.R) rewired: match_list_taxa/taxonomy now
# sourced from each workflow's own match object (match_obj_restored for 12S -- required
# relocating the call to after that object is finalized, since it didn't exist yet at
# the call's original Step-5 location; match_obj for 18S_2; match_taxonomy/esv_expanded
# for the two Mugu scripts, both already available early). The 18S_2 script's ad hoc
# candidate_plant_taxa sourcing (GBIF-occurrence-derived sampling-group restriction) is
# fully superseded by the open-discovery residual step and removed. All four workflows
# parse cleanly; not run live (real GBIF/NCBI/iNat/LLM API calls, real checkpoints --
# the user's call). devtools::test() 0 failures (536, up from 481), devtools::check()
# 0/0/0. Reinstalled to ~/Library/R/4.0/library. See
# [[project_taxaflag_domestic_species_floor_note]] for the full record.
# Previous update, 2026-07-24, later same day (Sonnet 5 -- generate_domestic_food_priors()
# candidate names normalized via TaxaTools::clean_taxon_names() before becoming a row's
# taxon_name, prompted by the user directly catching that .default_domestic_animal_taxa's
# subspecies trinomials ("Sus scrofa domesticus", "Gallus gallus domesticus", etc.)
# contradict the ecosystem's own binomial-only convention. Confirmed a real bug, not just
# a style inconsistency: TaxaTools::clean_taxon_names() truncates every name to genus +
# epithet only, discarding a third token -- so a real query resolving to "Sus scrofa"
# (post-cleaning, as everything else in this pipeline is) would never exact-match a prior
# row of "Sus scrofa domesticus" in TaxaAssign::join_priors()'s taxon_name join
# (join_priors.R:855), silently producing NO domestic prior for exactly the taxa (pig,
# chicken, dog, mallard, turkey, rabbit -- 6 of 13 default domestic_animal_taxa entries)
# most likely to show up as food/lab contamination. Two fixes: (1) the 6 trinomial
# defaults corrected to binomials ("Canis lupus familiaris" -> "Canis lupus" also found
# and fixed, missed on the first pass and caught by a new defaults-sanity test); food_
# species_taxa's "Fragaria x ananassa" also fixed to "Fragaria ananassa" (same root cause
# -- clean_taxon_names() treats a bare "x" token as a hybrid-formula abbreviation and
# collapses to genus-only). (2) Defense-in-depth: ALL candidate names (defaults and any
# user-supplied override) are now run through TaxaTools::clean_taxon_names() right after
# the three channels are combined, before deduplication -- so this can't silently recur
# if the list is edited again. A name that cannot be cleaned to a valid binomial/genus is
# dropped with a warning() rather than passed through raw. New requireNamespace("TaxaTools")
# guard added (package already sat in Suggests, same pattern build_priors.R already uses).
# 6 new tests (default-vector sanity check for stray trinomials/hybrid-formula names;
# trinomial-in/binomial-out; hybrid-formula normalization; uncleanable-name-dropped-with-
# warning). devtools::test() 0 failures (501, up from 495), devtools::check() 0/0/0.
# Not yet reinstalled -- see the "To apply these changes" block at the end of this session.
# Previous update, 2026-07-24 (Sonnet 5 -- generate_domestic_food_priors() gains an
# iNaturalist kingdom cross-check, prompted directly by the user asking whether iNat's
# own taxonomic backbone (distinct from NCBI/GBIF) could silently resolve a name to the
# wrong organism. Real risk, confirmed: iNat's /v1/taxa search takes the single best text
# match, so a cross-kingdom homonym is possible, if rare. New optional mechanism (opt-in
# via `taxonomy`'s `kingdom` column, built into a lookup BEFORE the candidate loop so
# each candidate's own kingdom is available at check time): compares the candidate's
# known kingdom against TaxaFetch::fetch_inat_occurrences()'s new `inat_kingdom` column;
# on a mismatch, discards the local-evidence boost (n_local -> NA, warning emitted) but
# never removes the fixed-list category itself -- only the confidence a likely-wrong
# local hit would have added. New output columns `inat_kingdom`/`inat_kingdom_mismatch`,
# always present (NA/FALSE when not checkable, i.e. no `kingdom` column supplied).
# devtools::test() 0 failures (495, up from 481), devtools::check() 0/0/0. Reinstalled to
# ~/Library/R/4.0/library. See TaxaFetch/CLAUDE.md's matching note for the `inat_kingdom`
# building block, and TaxaMatch/CLAUDE.md's same-day note for the companion
# convert_taxonomy_backbone() fallback-cleaning fix from the same design conversation
# (a real match_obj$taxon_name/species had passed through with an uncleaned compound
# hybrid-formula name, found while investigating why the domestic/food residual count on
# real 18S data looked wrong).
# Previous update, 2026-07-23 (Sonnet 5 -- implements the three-vector domestic/food design from
# ecosystem_docs/REENTRY_PROMPT_domestic_food_species_priors.md. New generate_domestic_food_priors():
# domestic_animal_taxa/food_species_taxa are fixed, pre-populated (but user-overridable) vectors;
# candidate_plant_taxa is deliberately NOT a fixed default list (the reentry prompt's own
# CSV-overlap finding -- Cultivated_plants.csv/Food_Plants_Taxonomy.csv turned out to be the same
# underlying list at two processing stages, not a usable food-vs-ornamental split -- so a plant
# candidate only gets a prior row when TaxaFetch::fetch_inat_occurrences(quality_grade="casual")
# finds real local cultivated-grade evidence for it). Output rows carry a real taxon_name (unlike
# generate_undetected_diversity()'s anonymous proxies) plus a new prior_source_type categorical
# column ("domestic_animal"/"food_species"/"domestic_plant") for downstream systematic handling,
# and model_tier = "tier_domestic_food" (deliberately distinct from "tier3_undetected"). Theta
# construction reuses this function's own N_total scale via an ESS-based alpha/beta (baseline ess
# for domestic_animal/food_species even with zero local iNat evidence; capped evidence boost via
# max_ess when local iNat presence is found) -- documented as a heuristic, not yet empirically
# calibrated against real contamination data. Explicitly does NOT fix cross-genus reference gaps
# (e.g. Bison bison/Bos taurus) -- see the reentry prompt's corrected Homo sapiens finding, folded
# into [[project_taxaflag_domestic_species_floor_note]]: this function's value is the categorical
# flag plus help for weaker/degraded matches, not sequence-level resolution (which already works
# fine on strong matches regardless of prior magnitude). devtools::test() 0 failures (481, up from
# 445), devtools::check() 0/0/0. Reinstalled to ~/Library/R/4.0/library. See TaxaFetch/CLAUDE.md's
# matching note for the new fetch_inat_occurrences() building block.
# Previous update, 2026-07-11 (Session 149, one more continuation -- generate_full_priors()'s
# jeffreys_fallback (item 6, last untouched TaxaExpect H-priority soundness row) fixed:
# moment_match() no longer discards a finite point-estimate mean for the agnostic Jeffreys
# mean of 0.5 when phi (precision) is unusable -- it now builds a diffuse Beta at that SAME
# mean (concentration min_phi) whenever the mean itself is finite, degrading to true
# Beta(0.5,0.5) only when the mean is also non-finite. Traced reachability first (same
# "verify before fixing" discipline as item 2): with min_phi>0 (default), the pre-existing
# min_phi floor (2026-07-03) already rescues the "typical, extrapolating low-base-rate taxon"
# scenario this finding described -- confirmed empirically 0/1200 rows fire on real
# PtConception 18S data. What remains reachable is a genuinely non-finite SE (rarer, narrower
# than first characterized), still worth fixing since it still discarded a usable mean. 4 new
# tests (NA-SE-preserves-mean at default min_phi; large-finite-variance-preserves-mean at
# min_phi=0, restoring the historical case; genuinely-unusable-mean gets true Jeffreys).
# devtools::test() 445/445 (up from 435), check() clean. Soundness-review doc reclassified
# item 6 NO->CONDITIONAL (fixed); 8 of 16 H-priority items now addressed. Previous update,
# same day: generate_undetected_diversity()'s
# item-7 soundness finding (global_floor_beta, N_total pooled across taxonomic groups diluting
# the undetected-species floor for a minority group) is now mitigated by REUSING
# train_biodiversity_model_by_group()'s infrastructure: each per-group biofreq_model already
# carries its own correctly-scoped N_total, so calling generate_undetected_diversity() once per
# group (already demonstrated in the real-data test below) gives an automatically
# group-appropriate floor -- no new code, docs-only update pointing at the concrete tool, with a
# real confirmed number (pooling gives zooplankton a floor ~34x too low vs. its own group's true
# effort, on real PtConception 18S data). devtools::check() clean (docs-only). Previous update,
# same day: real-data testing
# against actual PtConception 18S occurrences (156,210 rows, real 11-way sampling_group
# classification) surfaced two real bugs beyond the empty-string-taxonomy one below:
# (1) compute_adaptive_sampling_groups() -- FIXED, see that entry below. (2)
# train_biodiversity_model_by_group() had no tryCatch() around its per-group fit, so one
# group's failure crashed the whole call, discarding every other group's result --
# FIXED by wrapping each group's prepare_model_dataframe()+train_biodiversity_model()
# call in tryCatch(), dropping failed groups with a warning naming them (mirrors the
# protection the real workflow script's own manual loop already had). Re-run against
# real data post-fix: of 8 real groups, 3 fit cleanly (macroinvertebrates,
# other_vascular_plants, zooplankton); macroalgae/sea_grasses hit the known
# single-habitat-level "contrasts" error (real data, not synthetic); meiofauna/
# parasites/phytoplankton have too few raw records (1-5) to clear effort_threshold.
# Real, concrete confirmation that per-group effort denominators actually matter:
# at site Grid_32p0_m118p4, old pooled n_total_at_site=550 vs. new per-group values
# macroalgae=218/macroinvertebrates=328/sea_grasses=4 (~137x difference for
# sea_grasses). devtools::test() 435/435 (up from 423), check() clean. Previous
# update, same day: compute_adaptive_sampling_groups(): automates the sampling_group classification
# (previously always hand-built, e.g. the real 18S workflow's manual 11-way case_when())
# by greedily merging taxa up a rank hierarchy (default order -> class -> phylum) until
# each group's mean per-site record count clears a minimum viable N, never crossing the
# ceiling rank. "Stratum collapsing" from survey methodology; structurally a bottom-up
# mirror of TaxaAssign::join_priors()'s existing top-down dark-diversity recursion. Found
# and fixed a real bug during testing (list[[NA]] returns NULL, not the actual element,
# breaking NA-taxonomy handling) via deliberate smoke-testing before writing formal tests.
# devtools::test() 423/423 (up from 401), check() clean. See session notes below for the
# design discussion that led here. Previous update, 2026-07-10 (Session 149 continued --
# prepare_model_dataframe() gains
# sampling_group_col (group-aware n_total_at_site); train_biodiversity_model() now refuses
# to fit against multi-group data; new train_biodiversity_model_by_group() orchestrates
# per-group fitting. This is the code-level enforcement of the long-documented "Shared
# effort assumption" (previously advisory prose only). Applied to the real PtConception 18S
# workflow (11 sampling groups). devtools::test() 401/401 (up from 383), check() clean. See
# session notes below for the full record, including the investigation confirming this had
# never actually been fixed before (only documented) despite the user's recollection of
# prior discussion. Earlier same-day: generate_undetected_diversity() gains a
# documentation-only note on the domestic/synanthropic species floor artifact, recommending
# occurrence-data augmentation rather than a code fix; see session notes below. Session 2026-07-03
# -- habitat_col = NULL support added to optimize_grid_size()/prepare_model_dataframe()/train_biodiversity_model()/generate_undetected_diversity()/generate_full_priors() -- fixes a real Tier 2 fitting bug found testing a single-observation prior pipeline. SAME session, second bug found re-verifying the first fix: theta_epsilon's singleton-mirror auto-raise was clipping ALL tiers' predictions instead of just Tier 2, flattening real Tier 1 differentiation -- fixed by scoping the raised floor to Tier 2 only. See session notes below. Session 129 — screen_spatial_formula()/generate_full_priors() fixed to handle zero-Tier-1-species real data instead of crashing; non-ASCII em-dash in generate_undetected_diversity() fixed)

---

## Package Purpose
Generates prior probability objects using occurrence and habitat data to estimate
detection probability (theta) for a taxon at a particular location. Provides tools
for spatial gridding, biodiversity modelling (binomial GLMM), and prior generation
for input to TaxaAssign.

Split note: data acquisition moved to TaxaFetch (Session 19); habitat assignment and
spatial QAQC moved to TaxaHabitat (Session 28). TaxaExpect retains gridding, modelling,
and prior generation only.

---

## Function Inventory

### Core pipeline

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `create_sites_from_grid()` | Snap lat/lon to grid cells; add `lat_r`, `lon_r`, `grid_id`. **2026-08-04:** also records `attr(result, "grid_size")` -- the resolution used, propagated by `prepare_model_dataframe()`/`train_biodiversity_model()`/`generate_full_priors()` so `plot_theta_map_interactive()` can read the real cell half-width instead of inferring it. | Complete | R/create_sites_from_grid.R |
| `prepare_model_dataframe()` | Aggregate occurrences to species × site-habitat counts; zero-fill; scale covariates. `sampling_group_col` (default `NULL`) computes `n_total_at_site` within each group rather than pooling all taxa -- the code-level fix for the long-documented-but-unenforced "Shared effort assumption" (e.g. don't mix phytoplankton counts with vertebrate counts on one denominator). **2026-08-04:** propagates `data`'s `grid_size` attribute (if present) to its own output, in both the ungrouped and grouped paths; internal single-group aggregation logic extracted to a top-level `.prepare_one_group()` helper (was a badly-indented nested closure) and converted to native pipes. | Complete | R/prepare_model_dataframe.R |
| `train_biodiversity_model()` | Fit Tier 1/2 binomial GLMM; return `biofreq_model` S3 object. Refuses to fit against data whose `sampling_group` column (from `prepare_model_dataframe(sampling_group_col=)`) spans more than one value -- use `train_biodiversity_model_by_group()` instead. **2026-08-04:** `$meta` gains `grid_size` (from `attr(data, "grid_size")`). | Complete | R/train_biodiversity_model.R |
| `train_biodiversity_model_by_group()` | **Session 149, new.** Splits raw occurrence data by `sampling_group_col` and runs `prepare_model_dataframe()` + `train_biodiversity_model()` once per group (each with its own effort denominator and covariate scaling); returns a named list of `biofreq_model` objects. Recommended entry point for broad-marker data (e.g. 18S) spanning multiple detection processes. Each group's fit is wrapped in `tryCatch()` (added after real-data testing found a single failing group crashed the whole call) -- failed groups are dropped with a `warning()` naming them, not fatal. | Complete | R/train_biodiversity_model_by_group.R |
| `compute_adaptive_sampling_groups()` | Automated alternative to hand-classifying `sampling_group`: greedily merges taxa up a taxonomic rank hierarchy (`rank_system`, finest first, e.g. `c("order","class","phylum")`) until each group's mean per-site record count clears `min_n`, never merging across the ceiling rank (default phylum). Analogous to "stratum collapsing" in survey methodology; structurally similar to `TaxaAssign::join_priors()`'s hierarchical dark-diversity grouping but merges bottom-up on a sample-size criterion rather than descending top-down on singleton presence. Groups still below `min_n` even at the ceiling are finalized anyway (never escalated further) and flagged via `sampling_group_below_min_n`. Feed its output into `prepare_model_dataframe(sampling_group_col=)`/`train_biodiversity_model_by_group()` the same as a manually-supplied grouping. **2026-08-04: `min_n` is now required (no default)** -- no safe universal value across study systems; zero real callers affected. | Complete | R/compute_adaptive_sampling_groups.R |
| `generate_undetected_diversity()` | Tier 3 proxy priors: singleton mirrors + global floor | Complete | R/generate_undetected_diversity.R |
| `generate_domestic_food_priors()` | **2026-07-23, new.** Non-GBIF prior source for domestic/commensal animal, food/crop, and cultivated-plant species -- named rows (real `taxon_name`, unlike the Tier 3 proxies above) with a `prior_source_type` categorical column and `model_tier = "tier_domestic_food"`. Implements `ecosystem_docs/REENTRY_PROMPT_domestic_food_species_priors.md`. **2026-07-24:** gains an iNaturalist kingdom cross-check -- when `taxonomy` supplies a `kingdom` column, a candidate's known kingdom is compared against `fetch_inat_occurrences()`'s `inat_kingdom`; a mismatch (likely a cross-backbone homonym) discards the local-evidence boost without removing the fixed-list category. **2026-07-28, re-implemented around match-list gating:** `domestic_animal_taxa`/`food_species_taxa` (now 449 species, up from 20) are fixed vectors checked immediately; new 4th fixed list `known_cultivar_taxa` (216 species) likewise patched immediately (`cultivar_evidence_source = "known_list"`); `candidate_plant_taxa` requires real local iNat evidence (`cultivar_evidence_source = "candidate_supplied"`); new `match_list_taxa` param (taxa with real likelihoods this run) gates all four channels to the intersection and drives an automatic open-discovery residual step (unreferenced match-list taxa, restricted to `phylum %in% c("Streptophyta","Tracheophyta")`, deliberately NOT pre-restricted to any known list -- `cultivar_evidence_source = "inat_confirmed"`) using a new `taxaexpect_priors` param to exclude already-modelled taxa. `match_list_taxa = NULL` (default) preserves the original unrestricted behavior exactly. **2026-08-20:** every emitted row now carries `taxon_name_rank = "species"` -- a real bug fix, not additive: this column was previously unset (NA via `bind_rows()`), silently defeating `TaxaAssign::join_priors()`'s primary join for every real caller since this function shipped. `main_habitat` is unchanged, still deliberately `NA` -- see `TaxaAssign::join_priors()`'s new habitat-agnostic fallback tier, the paired fix that makes an `NA`-habitat row actually apply. | Complete | R/generate_domestic_food_priors.R |
| `apply_undetected_evidence()` | **2026-08-20, new (replaces the same-day, same-session `generate_invasive_watch_priors()`).** The single shared mechanism for elevating `generate_undetected_diversity()`'s generic dark-diversity floor for named species with external occurrence-plausibility evidence -- from any number of independent sources at once, safely. Takes a plain `evidence` table (`taxon_name`/`weight`/`n_eff`/`source`, typically row-bound from one or more evidence-generating functions), excludes any taxon already observed anywhere in `taxaexpect_priors` (checked via both `taxon_name` and `source_taxon_name`), combines multiple sources per taxon via `w_combined = 1 - prod(1 - weight_i)` / `n_eff_combined = sum(n_eff_i)`, then blends `theta_floor -> theta_singleton` (the site's own singleton-mirror mean, falling back to the global one) by `w_combined` -- giving a free, principled ceiling (external evidence, however strong, can never exceed the plausibility of a genuinely observed singleton). New `undetected_type = "evidence_blend"` value. Requires `grid_id`/`main_habitat` (mirrors `generate_domestic_food_priors()`'s single-site-per-call convention -- `TaxaAssign::join_priors()`'s primary join key is the full composite `(taxon_name, taxon_name_rank, grid_id, main_habitat)`, so a row without a real, matching `grid_id` would never actually take effect). **Deliberately excludes `generate_domestic_food_priors()`** from ever being a valid evidence source -- a food/domestic detection is a contamination-risk claim, an occurrence-plausibility detection (invasive-watch, regional-proximity) is a genuine-population claim; OR-combining them would conflate two different questions about the same zero-detection fact. Implements `ecosystem_docs/REENTRY_PROMPT_invasive_species_watch_list_priors.md`, converged with a concurrent chat building `ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md`'s companion mechanism onto this exact same shared applier -- see this file's top session note for the full cross-session design record. | Complete | R/apply_undetected_evidence.R |
| `generate_invasive_watch_evidence()` | **2026-08-20, new.** Thin evidence generator for `apply_undetected_evidence()` -- given a plain, user-supplied `invasive_taxa` character vector (e.g. hand-pulled from the USGS NAS database, restricted to species relevant to your own study region) plus a caller-chosen `weight`/`n_eff` (both required, no default), returns one evidence row per listed taxon. Does no live querying, no geography/watershed reasoning, no Beta-parameter math -- deliberately simpler than the same-day, same-session, now-removed NAS-API/HUC8-based `generate_invasive_watch_priors()` (see `TaxaFetch/CLAUDE.md`'s matching removal note): region-scoping now lives entirely in how the caller builds `invasive_taxa`, not in this function. Different-confidence tiers are handled by calling this function once per tier and `dplyr::bind_rows()`-ing the results, not a built-in tiering system. | Complete | R/generate_invasive_watch_evidence.R |
| `generate_regional_proximity_evidence()` | **2026-08-21, new.** The companion evidence generator for `apply_undetected_evidence()` from the parallel `ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md` thread -- unlike `generate_invasive_watch_evidence()`, this one DOES do live querying (a two-stage design): Stage 1 resolves a GBIF backbone key and calls `TaxaFlag::check_gbif_tile_range()` as a cheap presence/absence gate; only taxa that clear it get a real, quality-filtered Stage 2 fetch (`TaxaFetch::get_gbif_occurrences()` + `filter_gbif_quality()`, scoped to a buffer sized from Stage 1's own reported distance) that reads the real distance and record age via `TaxaFlag::compute_local_occurrence_distance(date_col=)`. `weight = exp(-distance_km/d_half)`; `n_eff = n_eff_base * exp(-age_years/age_half)` -- age discounts confidence, never the mean, since old evidence is ambiguous (a real unresurveyed population vs. a contracted range), not necessarily weaker. `d_half`/`age_half`/`n_eff_base` all default but stay overridable, per explicit user direction. No connectivity/basin gate -- deliberately dropped from scope, see this file's own top session note. **2026-08-22**: Stage 1's key resolution now uses one batched `rgbif::name_backbone_checklist()` call (new internal `.resolve_gbif_taxon_keys_batch()`) instead of one `rgbif::name_backbone()` call per taxon -- a real, live-verified GBIF-level speedup (see this file's own top session note for the full investigation, including why the analogous Stage 2 batching idea was tested and rejected). Live-verified against the real GBIF API on the real motivating GreatLakes2023 species, before and after the batching change, with identical real numbers both times. **2026-08-22, continued**: fixes a real, more serious PRE-EXISTING bug found running this function at real production scale (194 taxa, 0 elevated) -- a query name matching a GBIF SYNONYM resolves to that synonym's usageKey, whose real occurrence records are filed under GBIF's currently-ACCEPTED name; Stage 2's exact-name match against the original query silently found nothing even when real, quality-filtered records existed. `.resolve_gbif_taxon_keys_batch()` now also returns GBIF's own resolved `species` name, used for internal occurrence matching (the OUTPUT `taxon_name` still reports the original query name, unaffected). Predates today's batching work -- present identically in the original single-call resolver, just never exercised by the narrower 3-species validation. | Complete | R/generate_regional_proximity_evidence.R |
| `generate_full_priors()` | Predict theta at all taxon × site × habitat; return Beta(alpha, beta) prior table. **2026-08-04:** output gains `attr(result, "grid_size")` (from `model_obj$meta$grid_size`, `NULL`-safe); `cov` loop variable renamed `covariate` (shadowed `stats::cov()`); `predict_tier()`/`predict_tier_empirical()`'s duplicated effort-flag assignment factored into a shared local helper. | Complete | R/generate_full_priors.R |

### High-level wrapper

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `build_priors()` | End-to-end pipeline: GBIF fetch → habitat → grid → model → priors → backbone translation (~18 calls → 1). Params include `search_rank` (default "family"), `max_coord_uncertainty` (default 500m), `min_phi` (default 2), `census_genera` (default TRUE — GBIF genus census attached as attribute). | Complete | R/build_priors.R |

### Supporting functions

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `add_pca_covariates()` | Replace correlated `_s` covariate columns with orthogonal PCA scores; returns same structure as `prepare_model_dataframe()` output; stores `pca_rotation` attribute for prediction-time use | Complete | R/add_pca_covariates.R |
| `apply_pca_transform()` | Apply stored PCA rotation to scaled new-site data before `generate_full_priors()` | Complete | R/add_pca_covariates.R |
| `optimize_grid_size()` | Score grid resolutions on coverage, quality, stability; return best size + fallback | Complete | R/optimize_grid_size.R |
| `compute_moran_basis()` | Build Moran Eigenvector Maps (MEM) for spatial autocorrelation covariates. **2026-08-04:** new `coords` param (data frame of `grid_id`/`lat`/`lon`) supplies real coordinates directly instead of parsing `grid_ids`' string encoding; `coords = NULL` (default) preserves the original string-parsing behavior. Internal parser consolidated into shared `TaxaExpect:::.parse_grid_id_coords()` (`R/utils_internal.R`). | Complete | R/compute_moran_basis.R |
| `screen_spatial_formula()` | Fit full spatial model, screen Moran/gradient slopes by VarCorr SD, select parsimonious formula by AIC. Gradient-covariate detection reads `data`'s own `scale_params` attribute (set by `prepare_model_dataframe()`) instead of hardcoding `lat_r_s`/`lon_r_s` -- any additional covariate (e.g. `depth_m_s`) is screened identically, not silently carried through unscreened. Falls back to the old hardcoded pair when `scale_params` is absent. | Complete | R/screen_spatial_formula.R |
| `plot_theta_map_interactive()` | Shiny gadget: Leaflet heatmap of `theta_mean` with occurrence point overlay. **2026-08-04:** grid-cell half-width now prefers `priors`'s recorded `grid_size` attribute over inferring it from centroid spacing, when present; internal grid_id parser consolidated into shared `TaxaExpect:::.parse_grid_id_coords()`; `@return` no longer references a nonexistent `plot_theta_map()` function. | Complete | R/plot_theta_map_interactive.R |

### S3 methods

| Function | Purpose | Source file |
|---|---|---|
| `print.biofreq_model()` | Compact summary of tiers, formula, convergence | R/train_biodiversity_model.R |
| `summary.biofreq_model()` | print + tier assignments + habitat screening table | R/train_biodiversity_model.R |

### Internal helpers (not exported)

**2026-08-04, new file `R/utils_internal.R`** -- consolidates helpers previously
reimplemented identically in 2-3 files each (code-review response, see
`inst/taxaexpect_review_response.md`):

| Helper | Purpose | Used by |
|---|---|---|
| `.beta_mean(a, b)` / `.beta_sd(a, b)` | Beta distribution mean/SD from alpha/beta | `generate_full_priors.R`, `generate_undetected_diversity.R`, `generate_domestic_food_priors.R` |
| `.dark_diversity_rank_cols` | `c("genus","family","order","class","phylum")` -- rank columns joined onto anonymous/named proxy prior rows | `generate_undetected_diversity.R`, `generate_domestic_food_priors.R` |
| `.parse_grid_id_coords(grid_id)` | Vectorised `grid_id` string -> centroid lat/lon parser (`sub()`-based, `NA`-safe) | `compute_moran_basis.R`, `plot_theta_map_interactive.R` |

Also new: `.prepare_one_group(data, covariates, habitat_col)` (`R/prepare_model_dataframe.R`,
the extracted single-group aggregation logic behind `prepare_model_dataframe()`) and
`.assign_effort_flag(grid)` (`R/generate_full_priors.R`, a local closure shared by
`predict_tier()`/`predict_tier_empirical()`).

---

## Function Signatures

### `create_sites_from_grid(data, grid_size, lat_col = "decimalLatitude", lon_col = "decimalLongitude")`
- Adds `lat_r`, `lon_r`, `grid_id` columns. `grid_id` format: `"Grid_{lat_r}_{lon_r}"` with `.` → `p`, `-` → `m`.
- `grid_size > 10` triggers a warning (likely km not degrees).
- **Strict rule:** `grid_id` encodes location only — never habitat.
- **2026-08-04:** attaches `attr(result, "grid_size") <- grid_size` -- propagated by
  `prepare_model_dataframe()`/`train_biodiversity_model()`/`generate_full_priors()` so
  `plot_theta_map_interactive()` can read the real resolution instead of inferring it.

### `prepare_model_dataframe(data, covariates = c("lat_r", "lon_r"), habitat_col = "main_habitat", cor_threshold = 0.7)`
- Requires: `grid_id`, `lat_r`, `lon_r`, `habitat_col` (unless NULL), `taxon_name`.
- Returns tibble with: `grid_id`, `lat_r`, `lon_r`, `<habitat_col>`, `taxon_name`, `n_species`, `n_total_at_site`, `n_other`, `is_present`, `observed_in_habitat`, `<cov>_s` columns.
- Attaches `scale_params` as attribute (list of center/scale per covariate) for use at prediction time. **2026-08-04:** also propagates `data`'s own `grid_size` attribute (if present) onto the output, in both the ungrouped and `sampling_group_col`-split paths.
- Warns on multicollinearity > `cor_threshold`; call `add_pca_covariates()` on the result to fix.
- **`habitat_col = NULL`** (Session, 2026-07-03): opts out of habitat modeling entirely. No habitat
  column required in `data`, none in the output. Two-path design: if you have a habitat column, run
  `TaxaHabitat` and pass it here so habitat enters the model as a real predictor; if you don't, pass
  `NULL` rather than faking a single constant category (see `train_biodiversity_model()` below for
  why the fake-constant path is actively broken).

### `add_pca_covariates(model_df, cor_threshold = 0.7, prefix = "PC")`
- Input: output of `prepare_model_dataframe()` (must have `_s` columns and `scale_params` attribute).
- Finds all `_s` column pairs with `|r| > cor_threshold`; applies PCA to all involved columns.
- Replaces involved `_s` columns with `<prefix>N_s` PC score columns (orthogonal by construction).
- Returns the same tibble structure suitable for `train_biodiversity_model()`.
- Attributes on output: `scale_params` (unchanged, original covariate entries); `pca_rotation` (list: `source_cols`, `pc_cols`, `rotation`, `center`, `prefix`).
- Returns input unchanged (with message) if no pairs exceed threshold.

### `apply_pca_transform(new_sites, pca_rotation)`
- Input: scaled new-site data frame (has `pca_rotation$source_cols` columns) + `pca_rotation` from `add_pca_covariates()` output attribute or `model_obj$pca_rotation`.
- Subtracts training center, applies rotation, replaces source columns with PC columns.
- Use before `generate_full_priors()` when model was trained with PCA covariates.

### `train_biodiversity_model(data, formula, taxon_col = "taxon_name", habitat_col = "main_habitat", response = c("theta", "psi"), min_obs_threshold = 5L, effort_threshold = 10L, min_positive_rows = 50L, full_data = NULL)`
- **2026-08-04:** `$meta` gains `grid_size` (from `attr(data, "grid_size")`, `NULL`-safe).
- **Tier 1** (>= `min_obs_threshold` detections): full user-supplied formula with habitat screening.
- **Tier 2** (< threshold): auto intercept-only formula `cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)`.
- `diag(main_habitat | taxon_name)` in user formula is a placeholder — rewritten to indicator-based slopes per supported habitat.
- **`habitat_col = NULL`** (Session, 2026-07-03): both Tier 1 and Tier 2 fit with no habitat term at
  all — Tier 2's formula becomes `cbind(n_species, n_other) ~ (1 | taxon_name)`. `data` must be the
  output of `prepare_model_dataframe(habitat_col = NULL)` (no habitat column). A formula with a
  `diag()` habitat term errors immediately if `habitat_col = NULL` (fail fast, not a silent
  misconfiguration). **Do not** work around a missing habitat classification by passing a single
  constant value through the real `habitat_col` argument — that previously broke Tier 2 fitting
  outright ("contrasts can be applied only to factors with 2 or more levels"), found 2026-07-03
  testing a single-observation prior pipeline that skipped `TaxaHabitat` to save cost. `habitat_col
  = NULL` is the only correct way to opt out.
- Returns `biofreq_model` S3 object (see below).
- **Recommended formula:**
  ```
  cbind(n_species, n_other) ~
    main_habitat +
    (1 | taxon_name) +
    diag(main_habitat | taxon_name) +
    (0 + lat_r_s | taxon_name) +
    (0 + lon_r_s | taxon_name) +
    (1 | taxon_name:grid_id)
  ```

### `generate_undetected_diversity(model_obj, taxonomy = NULL, jeffreys_threshold = 2L, singleton_ess = 2L)`
- **Multi-taxonomic-group markers (Session 149):** `N_total`-based global floor is diluted for
  a minority group when `model_obj` pools multiple detection-process groups. Fixed via reuse,
  not new code: call `train_biodiversity_model_by_group()` and run this function once per
  returned model instead of once on a pooled model — each group's own correctly-scoped
  `N_total` gives an automatically group-appropriate floor. See `@details` in the function's
  own roxygen for a real confirmed number (~34x dilution on real PtConception 18S data).
- Input: `biofreq_model` object.
- No habitat column on singleton-mirror/global-floor rows when `model_obj` was trained with
  `habitat_col = NULL`.
- **`taxonomy`** (Session 117): optional data frame with `taxon_name` + any subset of `{genus, family, order, class, phylum}` columns (e.g. `occurrences_std`). When supplied, taxonomy columns are joined onto singleton-mirror rows by `taxon_name` so that `join_priors()` hierarchical group priors can descend the taxonomy tree for singleton rows.
- Singleton mirrors: one proxy per singleton in training data; ESS controls diffuseness (`alpha = theta_obs * ESS`, `beta = (1 - theta_obs) * ESS`).
- Global floor: `Beta(1, N_total - 1)`; falls back to Jeffreys `Beta(0.5, 0.5)` when `N_total < jeffreys_threshold`.
- Returns tibble with `source_taxon_name` audit column linking each singleton mirror back to the observed species it was derived from. When `taxonomy` is supplied, also carries the joined taxonomy columns.

### `generate_domestic_food_priors(model_obj, lat, lng, grid_id = NA, domestic_animal_taxa = <defaults>, food_species_taxa = <defaults>, known_cultivar_taxa = <defaults>, candidate_plant_taxa = NULL, match_list_taxa = NULL, taxaexpect_priors = NULL, radius_km = 50, ess = 5, max_ess = 50, taxonomy = NULL)`
- Reads only `model_obj$N_total`/`model_obj$meta$habitat_col` (not a full model dependency) so
  output rows sit on the same theta scale as `generate_undetected_diversity()`.
- Output is `dplyr::bind_rows()`-compatible with `generate_full_priors()`'s output (or with
  `generate_undetected_diversity()`'s, modulo `model_tier`/the new `prior_source_type`/
  `cultivar_evidence_source` columns) -- append it to your final priors table directly rather
  than routing it through `generate_full_priors(undetected = ...)`, which assumes anonymous
  placeholder rows.
- `match_list_taxa` (e.g. `unique(match_obj$taxon_name[match_obj$taxon_name_rank == "species"])`)
  gates all four channels to the intersection AND drives the automatic open-discovery residual
  step -- pass it in a real workflow to avoid checking hundreds of default-list species that
  were never even candidates this run. `NULL` (default) checks every fixed-list entry
  unconditionally, matching this function's original (2026-07-23) behavior.
- The open-discovery step needs `taxonomy` with a `phylum` column to scope itself safely
  (`Streptophyta`/`Tracheophyta` -- both spellings needed, see
  `TaxaMatch::convert_taxonomy_backbone()`'s per-column NCBI fallback); without it, it's
  skipped with a message, not silently run unrestricted.
- See the function's own roxygen for the full channel-by-channel design rationale and what this
  does NOT fix (cross-genus reference gaps, e.g. `Bison bison`/`Bos taurus`).

### `generate_full_priors(model_obj, new_sites, undetected = NULL, min_phi = 2, theta_epsilon = 1e-6)`
- `new_sites` must have: `grid_id`, `lat_r`, `lon_r`, `<habitat_col>` — unless `model_obj` was trained
  with `habitat_col = NULL`, in which case no habitat column is required or used, and the output has
  none either (`habitat_col` is read from `model_obj$meta$habitat_col`, not a direct argument here).
  Optionally `n_total_at_site` (for `effort_flag`).
- Covariates scaled using training `scale_params` (not re-scaled from `new_sites`).
- Alpha/beta via moment-matching; phi capped at `1 / grid_var` (Tier 1 `taxon_name:grid_id` variance).
- **`min_phi`** (default 2): phi floor. When the phi cap is very low (high grid variance), prevents modelled priors from becoming so diffuse that MC posterior simulation is unstable and modelled priors become less informative than dark-diversity fallbacks. Matches `singleton_ess` default in `generate_undetected_diversity()`.
- **`theta_epsilon` auto-raise (Session 108):** When `undetected` is supplied and contains singleton-mirror rows, `theta_epsilon` is automatically raised to `mean(alpha/(alpha+beta))` across those rows if that value exceeds the default `1e-6`. This data-derived floor ensures Tier 2 sparse species (detected at least once in the system) always receive priors above the dark-diversity floor computed in `join_priors()`. Root cause fixed: a Tier 2 singleton with predicted theta ≈ 1e-6 was being promoted to dark_mean by `join_priors()`, producing priors identical to undetected species (e.g. `Syngnathus auliscus` vs `S. caribbaeus`). With the raise: `singleton_mirror_floor > dark_mean` (because dark_mean averages singleton mirrors + global floor, which is lower), so Tier 2 priors survive the promotion check unchanged.
- **Variance fallback (Session 149):** when phi (precision) is unusable (<=0 or non-finite --
  with `min_phi > 0`, the default, this is now almost always a non-finite SE, since the
  finite-variance case is already rescued by the `min_phi` floor), the row gets a diffuse
  Beta at the model's own predicted mean (concentration `min_phi`) if that mean is finite,
  or true Jeffreys `Beta(0.5, 0.5)` only if the mean itself is also unusable. Flagged in
  `jeffreys_fallback` column either way. Previously always used `Beta(0.5, 0.5)`, discarding
  a real (usually low-theta) mean estimate for an agnostic mean of 0.5 -- confirmed via real
  PtConception 18S data that this fires 0/1200 rows with defaults, since `min_phi` already
  neutralizes the common finite-variance case; the fix protects the rarer non-finite-SE case.
- Appends `undetected` rows if supplied. Singleton-mirror rows in `undetected` carry `source_taxon_name` (Session 117); this column is preserved in the output and used by `join_priors(singleton_taxonomy=)` to re-join taxonomy for hierarchical group priors.
- **2026-08-04:** output gains `attr(result, "grid_size")` (from `model_obj$meta$grid_size`, set when absent).

### `optimize_grid_size(observation_data, n_covariates, protected_habitat = NULL, min_s_threshold = 5, min_N_threshold = 10, min_distinct_locs = 20, min_locs_per_habitat = 3, min_grid = 0.1, max_grid = 1.0, step_grid = 0.05, lat_col = "decimalLatitude", lon_col = "decimalLongitude", species_col = "taxon_name", habitat_col = "main_habitat", weights = c(resolution = 0.4, quality = 0.4, stability = 0.2))`
- Returns named list: `$summary_table`, `$best_grid` (pass to `create_sites_from_grid`), `$explanation`, `$fallback_level` (`"none"`, `"A"`, `"B"`, `"C"`).
- Three fallback levels when no resolution meets `min_distinct_locs`.
- **`habitat_col = NULL`** (Session, 2026-07-03): resolutions scored on location count alone, no
  per-habitat stratification. Errors if `protected_habitat` is also supplied (incompatible). Uses an
  internal placeholder category to reuse the existing grouping/counting logic unchanged -- safe here
  specifically because this function never fits a model (unlike `train_biodiversity_model()`, where a
  placeholder instead of real `NULL` would still crash Tier 2).

### `screen_spatial_formula(data, formula_full, sd_threshold = 0.20, delta_aic_max = 2.0, verbose = TRUE, ...)`
- Runs after `compute_moran_basis()` + `prepare_model_dataframe()`, before `train_biodiversity_model()` for final fit.
- Two-stage: VarCorr pre-screen (flags near-zero SD slopes) → AIC comparison of up to 4 candidate models.
- Returns a `biofreq_model` object (the recommended model) with `$model_selection` appended.
- `$model_selection` contains: `aic_table`, `recommended_formula`, `flagged_terms`, `sd_table`.
- `...` passed to `train_biodiversity_model()` (e.g. `effort_threshold`, `min_obs_threshold`).

### `compute_moran_basis(grid_ids, k = 10L, distance_threshold = NULL, min_neighbours = 1L, coords = NULL)`
- Returns data frame: `grid_id`, `B1`, `B2`, ..., `Bk` (MEM columns, largest eigenvalue first).
- `distance_threshold = NULL` auto-inferred as 1.5× minimum coordinate spacing.
- Join result to model data before calling `prepare_model_dataframe()`.
- **`coords`** (2026-08-04): optional data frame with `grid_id`/`lat`/`lon` -- when supplied,
  used directly instead of parsing `grid_ids`' own string encoding (e.g.
  `dplyr::distinct(model_data, grid_id, lat = lat_r, lon = lon_r)`). Falls back to
  string-parsing for any `grid_id` missing from `coords`. Default `NULL` preserves the
  original string-parsing-only behavior.

### `plot_theta_map_interactive(priors, occurrences, occurrence_habitat_col = "main_habitat", tile = "Esri.OceanBasemap", theta_col = "theta_mean", grid_opacity = 0.7, point_radius = 4, point_color = "#ff6600")`
- Returns `NULL` invisibly. For exploration only.
- `occurrences = NULL` suppresses occurrence points.
- `occurrence_habitat_col = NULL` disables habitat colouring on points.
- **2026-08-04:** grid-cell half-width now reads `priors`'s recorded `attr(priors,
  "grid_size")` (propagated from `create_sites_from_grid()` via `generate_full_priors()`)
  when present, falling back to the original centroid-spacing inference otherwise.

---

## `biofreq_model` S3 Object

Named list, class `"biofreq_model"`:

| Slot | Type | Contents |
|---|---|---|
| `$models$tier1` | glmmTMB / NULL | Fitted Tier 1 model |
| `$models$tier2` | glmmTMB / NULL | Fitted Tier 2 model |
| `$tiers` | tibble | `taxon_name`, `tier` ("tier1"/"tier2"), `n_detections` |
| `$scale_params` | named list | Per-covariate `$center` and `$scale` |
| `$singletons` | data frame | Species seen exactly once (for Tier 3) |
| `$N_total` | integer | Sum of `n_total_at_site` across effort-passing cells |
| `$tier2_empirical` | data frame | Empirical theta mean/SD fallback for Tier 2 |
| `$habitat_screening` | list | `$supported`, `$sparse`, `$indicators`, `$min_positive_rows`, `$summary`, `$formula_used` |
| `$convergence_warnings` | character vector | Captured glmmTMB warnings |
| `$meta` | named list | `taxon_col`, `habitat_col`, `response`, thresholds, formulas, `n_sites`, `n_species_tier1`, `n_species_tier2` |

---

## Prior Object (output of `generate_full_priors()`)

Tibble, one row per taxon × site × habitat (plus Tier 3 proxies):

| Column | Type | Description |
|---|---|---|
| `taxon_name` | character | Taxon identifier (NA for undetected proxies) |
| `grid_id` | character | Spatial cell identifier |
| `main_habitat` | character | Site-level habitat category (column name follows `habitat_col` param set during training; default `"main_habitat"`) |
| `alpha` | numeric | Beta prior alpha parameter |
| `beta` | numeric | Beta prior beta parameter |
| `theta_mean` | numeric | `alpha / (alpha + beta)` |
| `theta_sd` | numeric | SD of Beta(alpha, beta) |
| `n_obs` | integer | `n_total_at_site` if supplied in `new_sites`, else NA |
| `model_tier` | character | `"tier1"`, `"tier2"`, or `"tier3_undetected"` |
| `effort_flag` | logical | TRUE if N < `effort_threshold`; NA if N not supplied |
| `observed_in_habitat` | logical | TRUE if taxon ever recorded in this habitat in training data |
| `extrapolation_warning` | logical | TRUE if any covariate |z| > 3 at this site |
| `undetected_type` | character | NA (modelled); `"singleton_mirror"`; `"global_floor"` |
| `jeffreys_fallback` | logical | TRUE if the variance/SE was unusable here. **Session 149:** if the model's own predicted mean was still finite, the row gets a diffuse Beta at that mean (concentration `min_phi`), not automatically `Beta(0.5,0.5)`; true Jeffreys `Beta(0.5,0.5)` is used only when the mean itself was also unusable. |

---

## Typical Workflow

```r
# 1. Grid occurrences (from TaxaFetch + TaxaHabitat)
sites  <- create_sites_from_grid(occurrences, grid_size = 0.5)

# 2. Optional: check grid resolution
opt    <- optimize_grid_size(occurrences, n_covariates = 3)
sites  <- create_sites_from_grid(occurrences, grid_size = opt$best_grid)

# 3. Optional: Moran basis for spatial autocorrelation
basis  <- compute_moran_basis(unique(sites$grid_id), k = 10L)
sites  <- dplyr::left_join(sites, basis, by = "grid_id")

# 4. Prepare model data
mdf    <- prepare_model_dataframe(sites, habitat_col = "main_habitat")

# 5. Optional: screen spatial formula for parsimony
full_formula <- cbind(n_species, n_other) ~
  main_habitat + (1 | taxon_name) +
  (0 + B1 | taxon_name) + (0 + B2 | taxon_name) + (0 + B3 | taxon_name) +
  (0 + lat_r_s | taxon_name) + (0 + lon_r_s | taxon_name) +
  (1 | taxon_name:grid_id)
screened <- screen_spatial_formula(mdf, full_formula, effort_threshold = 10L)
# screened$model_selection$recommended_formula is the parsimonious formula

# 6. Fit model (or use screened directly)
formula <- cbind(n_species, n_other) ~
  main_habitat + (1 | taxon_name) +
  diag(main_habitat | taxon_name) +
  (0 + lat_r_s | taxon_name) + (0 + lon_r_s | taxon_name) +
  (1 | taxon_name:grid_id)
mod     <- train_biodiversity_model(mdf, formula)

# 6. Undetected diversity priors
undet   <- generate_undetected_diversity(mod)

# 7. Generate prior table
priors  <- generate_full_priors(mod, new_sites = sites, undetected = undet)

# 8. Explore
plot_theta_map_interactive(priors, occurrences)
```

---

## Key Design Notes
- `grid_id` encodes **location only** — habitat is never part of the identifier
- `observed_in_habitat` is computed from positive detections only, before zero-filling
- **Phi cap + floor:** `generate_full_priors()` caps phi at `1 / grid_var` (the model's own estimate of grid-level uncertainty) and floors at `min_phi` (default 2). The cap prevents overconfidence; the floor prevents MC instability when grid variance is high.
- **`search_rank`** in `build_priors()`: controls what taxonomic rank GBIF queries are made at (default "family"). Species-level names are still verified against GBIF backbone first to resolve cross-backbone disagreements (e.g. Girellidae→Kyphosidae), then collapsed to unique families for querying.
- **`max_coord_uncertainty`** in `build_priors()`: passed to `filter_gbif_quality()` (default 500m). Endangered species often have intentionally degraded coordinates (~28km); a species purge warning is emitted when taxa lose ≥80% or 100% of records.
- **`search_center` attribute:** `build_priors()` attaches `attr(out, "search_center") <- list(lat, lon)` to both the return list and the `$priors` data frame. Used by `TaxaAssign::join_priors()` as the default site when `site = NULL`.
- `add_pca_covariates()` and `apply_pca_transform()` implemented in Session 106 (see Supporting functions above)
- `assign_habitat_to_points()` and `assign_habitat_biological()` are now in **TaxaHabitat**, not TaxaExpect

---

## `spatial_flag` Values (historical; spatial QAQC now in TaxaHabitat)
| Value | Meaning |
|---|---|
| `"likely"` | Spatially credible (was `"ok"` before Session 22) |
| `"questionable"` | Needs review (was `"suspect"`) |
| `"unlikely"` | Probable error (was `"likely_error"`) |

---

## Test Coverage

614 expectations, 0 failures (2026-08-20, continued -- `test-generate_invasive_watch_priors.R`
(20 tests, the NAS-based design) removed along with the function it tested; new
`test-apply_undetected_evidence.R` (18 tests) and `test-generate_invasive_watch_evidence.R`
(10 tests), both fully offline, no live queries or cross-package mocking needed).
`devtools::check()` 0 errors/0 warnings/0 notes.

555 expectations, 0 failures (2026-08-04, up from 538). `tests/testthat/` has 14
correctly-named files, including separate `test-generate_undetected_diversity.R` and
`test-screen_spatial_formula.R`; `devtools::check()` runs clean. New file
`test-plot_theta_map_interactive.R` (6 tests) covers the shared
`TaxaExpect:::.parse_grid_id_coords()` and `TaxaExpect:::.truncate_label()` pure helpers --
the gadget itself remains untested (requires a live interactive session, same testing
boundary as before). `test-compute_adaptive_sampling_groups.R` and
`test-optimize_grid_size.R` updated for the `min_n`-required and
`.score_one_resolution(site_cols=, thresholds=)` signature changes, respectively. See
`inst/taxaexpect_review_response.md` for the full 2026-08-04 code-review response record.

---

## Key Dependencies

| Package | Used for |
|---|---|
| glmmTMB | Binomial GLMM fitting (Tier 1 and Tier 2 models) |
| dplyr | Data manipulation throughout |
| tidyr | `complete()` for zero-filling, `crossing()` for prediction grid |
| rlang | NSE (`sym`, `:=`) |
| stats | `predict()`, `plogis()`, `binomial()`, `as.formula()` |
| shiny / miniUI | `plot_theta_map_interactive()` gadget |
| leaflet / leaflet.extras | Interactive map rendering |
| stringr | `grid_id` string manipulation in `create_sites_from_grid()` |
| tibble | `tibble()` in `generate_undetected_diversity()` |

---

## Renaming Log

| Old Name | New Name | Date | Notes |
|---|---|---|---|
| `integrate_local_sources` | `combine_occurrence_sources` | 2026-02-27 | — |
| `make_hierarchical_habitat_prompt` | `build_habitat_prompt` | 2026-02-27 | Moved to TaxaFetch, then TaxaHabitat |
| `call_anthropic_api` | `prompt_api` | 2026-02-27 | Moved to TaxaFetch, then TaxaTools |
| `submit_manual` | `prompt_manual` | 2026-02-27 | Moved to TaxaFetch, then TaxaTools |
| `make_habitat_prompt` | *(deleted)* | 2026-02-27 | Flat pipeline removed |
| `assign_habitat_llm` | *(deleted)* | 2026-02-27 | — |
| `parse_habitat_response` | *(deleted)* | 2026-02-27 | — |
| `build_neighbor_graph` | *(deleted)* | 2026-03-01 | Superseded |
| `compute_species_amplitude` | *(deleted)* | 2026-03-01 | Superseded |
| `update_theta_local` | *(deleted)* | 2026-03-01 | Superseded |
| `calibrate_prior_cap` | *(deleted)* | 2026-03-01 | Superseded |
| `combine_occurrence_sources` | *(retired)* | 2026-03-13 | Replaced by `rename_cols()` + `stack_occurrences()` |
| habitat/spatial functions | Moved to TaxaHabitat | 2026-03-26 | Session 28 |

---

## Session Notes

**Session 149 (2026-07-10): domestic/synanthropic species documentation note**

Prompted by the ecosystem statistical soundness review's dark-diversity-floor finding
(`ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`): GBIF/iNaturalist-derived
occurrence data structurally under-index captive/domestic organisms, so a domestic
species with no detections gets the same tiny global-floor prior as a genuinely
implausible candidate. The user's design call: this is a training-data problem, not
something `generate_undetected_diversity()` can fix on its own (it has no way to
distinguish "genuinely undetected" from "under-counted by this data source") -- the
right fix is a documentation note telling users to augment their occurrence data with
known local domestic-species presence before training, if relevant to their study.
`generate_undetected_diversity()` gained a new `@section Domestic/synanthropic species`
roxygen block explaining this at the actual point where the floor is computed, and
pointing to `TaxaFlag::add_posthoc_assessment(domestic_taxa = ...)` (added same session)
for flagging the resulting low-prior-vs-strong-likelihood contrast when augmentation
isn't practical. Docs-only, no behavior change: `devtools::test()` 383/383 unchanged,
`devtools::check()` 0/0/1 (pre-existing clock-check NOTE). See `TaxaFlag/CLAUDE.md`'s
own Session 149 note for the full cross-package record.

**Session 149 continued (same day): group-aware effort denominators -- the "Shared
effort assumption" is now enforced, not just documented.**

Sixth H-priority item from the soundness-review walk-through:
`train_biodiversity_model::tier1_binomial_glmm` treats `n_species/n_total_at_site` as
an equal-detectability community sample, and `n_total_at_site` is pooled across every
taxon in the input data regardless of detection process. The user recalled discussing
this before, specifically in the context of the PtConception 18S workflow mixing
phytoplankton counts with vertebrate counts, and asked to verify (not assume) what had
actually been done before proceeding, to avoid duplicating work.

**Investigation (via a dedicated Explore agent) found:** the exact file recalled
(`PtConceptionWorkflow_18S_phytoplankton.R`) no longer exists; the real script with this
scenario is `PtConceptionWorkflow_18S_2.R` (outside this monorepo, at
`~/My Drive/Rscripts/eDNA/PtConception/`), which computes an 11-way `sampling_group`
classification (phytoplankton, fishes, birds_mammals, macroalgae, zooplankton, parasites,
meiofauna, terrestrial_arthropods, macroinvertebrates, sea_grasses, other_vascular_plants)
but uses it **only** to split output CSVs after modelling -- never to split the data
before `prepare_model_dataframe()`/`train_biodiversity_model()`, which is called once,
pooled, across all 11 groups. The package's own "Shared effort assumption" docs (Session
108) already use phytoplankton-vs-bird-point-counts as their own illustrative example of
what not to do -- but until now this was advisory prose only, never enforced anywhere,
and no memory or session note recorded ever actually fixing this specific case. Confirmed
safe to proceed without duplicating prior work.

**Package-level fix:**
- `prepare_model_dataframe()` gains `sampling_group_col` (default `NULL`). When supplied,
  the function splits `data` by that column and runs its existing (unmodified)
  single-group aggregation logic on each split independently, then recombines with a
  `sampling_group` output column -- deliberately not attempting to make a single shared
  `tidyr::complete()` call respect group boundaries, which would risk re-introducing
  cross-group zero-fill contamination (a phytoplankton taxon zero-filled into a
  vertebrate-group site row, or vice versa).
- `train_biodiversity_model()` now errors if its input carries a `sampling_group` column
  spanning more than one value -- turning the "shared effort assumption" from a
  recommendation a caller could silently ignore into an enforced guard. Only fires when
  such a column is present (i.e. the data came from
  `prepare_model_dataframe(sampling_group_col=)`); ungrouped callers are unaffected.
- New `train_biodiversity_model_by_group()` orchestrates the recommended path end to end:
  splits raw occurrence data by group, calls `prepare_model_dataframe()` +
  `train_biodiversity_model()` independently per group (each gets its own correctly-scoped
  `scale_params`, not a combined-then-resplit set that would lose the attribute), and
  returns a named list of `biofreq_model` objects. Deliberately does *not* reuse
  `prepare_model_dataframe(sampling_group_col=)`'s combined output internally, to sidestep
  attribute-loss-on-subset entirely -- that combined-output path remains available as an
  independent, standalone capability for exploration/diagnostics.

14 new tests across `test-prepare_model_dataframe.R` and the new
`test-train_biodiversity_model_by_group.R` (group-scoped `n_total_at_site` computed
correctly and NOT pooled; no cross-group zero-fill; `NULL` default fully backward
compatible; missing-column and single-group-warning validation; `train_biodiversity_model()`
itself refuses multi-group data). `devtools::test()`: 401/401 passing (0 failures, up from
383). `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Applied to the real workflow** (per the user's explicit request, "both -- package fix,
then apply it to the real workflow"): `PtConceptionWorkflow_18S_2.R` rewritten so Step 5
now calls `prepare_model_dataframe(sampling_group_col = "sampling_group")` and loops
`screen_spatial_formula()` once per group (wrapped in `tryCatch()`, since several of the
11 groups -- e.g. `sea_grasses`, `parasites` -- are plausibly too sparse for the full
spatial formula to converge, a risk that didn't exist before when there was only ever one
combined fit), collecting results into a named `model_fits` list. `generate_undetected_
diversity()`/`generate_full_priors()` also now run once per group against that group's own
site-data slice, then `dplyr::bind_rows()`d into the same `priors_combined`/
`taxaexpect_priors` objects the rest of the workflow (Steps 6+) already expects unchanged
-- downstream TaxaAssign wiring required no changes. Grid optimisation, gridding, the
focal-site grid-cell lookup, and the Moran spatial basis are all still computed once
(shared spatial structure, independent of sampling group). Fixed one leftover reference to
the old singular `model_fit` object further down the script (a run-metadata summary block)
to sum Tier 1/2 counts across all groups' models instead. Verified the edited script parses
cleanly (`parse()`); **not run live** against real GBIF/PtConception data this session --
that requires live API calls and interactive Shiny gadgets (per this workflow's own
established pattern), left for the user to run. This script is not under version control
(outside the monorepo, no git), so there is no diff/rollback via git if a revert is ever
wanted -- flagging this since it differs from every other edit this session.

**Session 149 continued once more (same day): compute_adaptive_sampling_groups() --
automating the manual sampling_group classification, prompted by a design discussion
about how to choose the denominator N well.**

After finishing the `sampling_group_col`/`train_biodiversity_model_by_group()` fix above,
the user pushed on a real follow-up question: choosing a good detection-process grouping
involves two competing goals -- (1) enough sample size in the denominator to trust an
estimate, and (2) not mixing genuinely different detection processes ("apples and
oranges") -- and asked whether a grouping could be computed automatically by starting at
a fine taxonomic rank and escalating to a coarser one only where a candidate group's
sample size is too thin, rather than requiring a hand-built classification (like the real
PtConception 18S workflow's 11-way manual `case_when()`) every time.

**Design worked through explicitly before coding:** confirmed this is conceptually
different from (not solved by) either `sampling_group_col` (which answers "were these
taxa even measured comparably," a domain-knowledge question no sample-size check can
answer) or `generate_undetected_diversity()`'s `N_total` stratification (item #7 in the
soundness review, not yet reached -- a genuinely analogous sample-size problem, but for
undetected-species floor priors, not the Tier 1/2 GLMM denominator). Landed on a
precedented pattern: "stratum collapsing" from survey methodology (merge an
under-sized stratum with an adjacent one until it's viable), implemented as a bottom-up
mirror of `TaxaAssign::join_priors()`'s existing top-down `.compute_dark_diversity_groups()`
recursion (phylum -> genus), but merging on a sample-size criterion instead of
singleton presence.

**Implementation:** `compute_adaptive_sampling_groups(data, rank_system = c("order",
"class", "phylum"), min_n = 100, grid_col = "grid_id", habitat_col = NULL)`. At each rank
(finest to the ceiling rank, the last element of `rank_system`), every not-yet-resolved
candidate group's mean per-site (or per site x habitat, if `habitat_col` supplied) record
count is checked against `min_n`; groups that clear it are finalized immediately, groups
that don't are left unresolved and picked up again at the next (coarser) rank's grouping
-- which automatically pools exactly the taxonomically-adjacent shortfall groups, since
they're grouped by their shared value at that coarser rank, while already-resolved finer
groups are excluded and untouched. Never merges across the ceiling rank; a group still
below `min_n` even there is finalized anyway (per the user's explicit choice) and flagged
via `sampling_group_below_min_n`, never silently treated as if the floor were met.
Rows with `NA` taxonomy at the rank currently being evaluated are held back rather than
merged into a same-rank "NA bucket," and finalize into a single `"unknown"` group only if
still `NA` at the ceiling.

**One real bug found and fixed during testing** (a good example of why the "verify"
convention in this codebase's checklists matters): the NA-handling path initially crashed
with "missing value where TRUE/FALSE needed." Root cause: iterating
`for (val_chr in names(idx_by_val))` and then indexing `idx_by_val[[val_chr]]` -- when
`val_chr` is the literal value `NA` (the explicit NA factor level's name), `list[[NA]]`
returns `NULL`, not the actual list element, silently breaking the lookup. Fixed by
iterating by position (`for (i in seq_along(idx_by_val))`, `idx_by_val[[i]]`) instead of
by name, which is unaffected by NA names. Caught by deliberately smoke-testing the NA
path before writing formal tests, not by code review alone.

22 new tests (clean resolution at the finest rank; sibling-order pooling at a shared
class; escalation all the way to a flagged ceiling-level pool; an independently-resolved
finer group correctly excluded from a coarser pool; the ceiling-crossing guard; both NA
paths, including the bug above; `habitat_col`; input validation). `devtools::test()`:
423/423 passing (up from 401), 0 failures. `devtools::check()`: 0 errors, 0 warnings, 0
notes. Not yet wired into the real `PtConceptionWorkflow_18S_2.R` workflow (that workflow
still uses its original manual 11-way classification) -- this is offered as an available
alternative, not a replacement forced onto existing hand-curated groupings.

**Session 149 continued yet again (2026-07-11): real-data validation of the new
sampling-group infrastructure against actual PtConception 18S occurrences**

Per the user's request to actually test the new functions (`prepare_model_dataframe(
sampling_group_col=)`, `train_biodiversity_model_by_group()`,
`compute_adaptive_sampling_groups()`) against real data rather than only synthetic
fixtures, ran the full chain against
`~/My Drive/Rscripts/eDNA/PtConception/PtCon18SSchulte_occurrences_clean.rds` (156,210
real rows, existing real 11-way `sampling_group` classification: macroinvertebrates,
other_vascular_plants, macroalgae, zooplankton, sea_grasses, phytoplankton, meiofauna,
parasites).

**Bug 1 (already recorded above): empty-string taxonomy in `compute_adaptive_
sampling_groups()`** -- 13 real rows had `phylum == ""` rather than `NA`; fixed via
`dplyr::na_if()` normalization, matching the existing `join_priors()` convention.

**Bug 2: `train_biodiversity_model_by_group()` had no failure isolation between
groups.** Running it against the real data with formula
`cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)`, the `macroalgae` group
(8,463 records) got through effort filtering and tier assignment (101 Tier 1, 98 Tier
2, 34 singletons) but then failed to fit with `Error: contrasts can be applied only to
factors with 2 or more levels` (the same known real-data failure mode fixed for a
different function on 2026-07-03) -- and this crashed the entire
`train_biodiversity_model_by_group()` call, discarding every other group's result,
including groups (`macroinvertebrates`, `zooplankton`) that would otherwise fit fine.
This is exactly the failure mode the real `PtConceptionWorkflow_18S_2.R` workflow
script's own manual loop already guards against with a `tryCatch()` -- that protection
had never been added to the package function itself.

**Fix:** wrapped each group's `prepare_model_dataframe()` + `train_biodiversity_model()`
call in `tryCatch()`; a failing group is dropped (with a `message()` if `verbose=TRUE`)
and every dropped group is named in one summary `warning()` after the loop completes.
`@return`/new `@section` documents this. 12 new tests (11 pre-existing +1 new
regression: one group with a single collapsed habitat level fails, the other group
still fits and is returned). `devtools::test()`: 435/435 (up from 423).
`devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Concrete real-data results post-fix:** of the 8 real sampling groups present after
gridding (0.8-degree grid, 21 cells), 3 fit cleanly end-to-end --
`macroinvertebrates` (87,665 records -> 255 Tier 1 / 412 Tier 2 / 142 singletons),
`other_vascular_plants` (53,907 -> 141 Tier 1 / 201 Tier 2 / 51 singletons),
`zooplankton` (4,255 -> 9 Tier 1 / 36 Tier 2 / 12 singletons). `macroalgae` and
`sea_grasses` both hit the single-habitat-level contrasts error post-effort-filtering
(a real, not hypothetical, data configuration). `meiofauna`, `parasites`, and
`phytoplankton` have too few raw records (1-5 each) to clear even one effort-threshold
cell and are excluded before a model is ever attempted -- expected given the sample
sizes, not a bug.

**Also confirmed with a real concrete number why the whole `sampling_group_col`
mechanism matters**, not just in the abstract: at real site `Grid_32p0_m118p4`, the
OLD pooled `n_total_at_site` was 550 (summed across every taxon regardless of
detection process), while the NEW per-group values are `macroalgae=218`,
`macroinvertebrates=328`, `sea_grasses=4` -- i.e. the pooled denominator overstated
`sea_grasses`' true sampling effort by roughly 137x at that one site.

Not yet done: `generate_undetected_diversity()`/`generate_full_priors()` have not yet
been run per-group against this real data (planned next); item #7's `min_n`
criterion for `generate_undetected_diversity()`'s own `N_total` stratification is
still an open design question, unconfirmed by the user.

**Session 77 (2026-05-19)**
- `build_priors()`: added `census_genera` parameter (default TRUE). After Stage 1
  (`create_taxon_names()`), extracts unique `genusKey` values from GBIF occurrence
  data and calls `TaxaTools::census_genus_species()` to enumerate described species
  per genus. Census attached as `attr(output, "gbif_genus_census")` on both the
  return list and `$priors` data frame.
- No additional GBIF API calls for key resolution — `genusKey` is free in occurrence records.
- Census enables three-tier H2 phantom suppression in `TaxaAssign::run_bayesian_pipeline()`.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` ecosystem rename: TaxaExpect does not use this column
  directly; no source changes required.

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 81 (2026-05-21)**
- `habitat_observed_elsewhere` column → `observed_in_habitat` (43 occurrences across 9 files).
  TRUE = species recorded in this habitat type during training; FALSE = habitat extrapolation.
- `moran_k = 0` support added to `build_priors()`: skips Moran eigenvector computation entirely.
  Default remains 5. Useful for non-spatial data or debugging.
- `inst/TaxaExpect_supplemental_methods.md` renamed from `inst/methods_background.md`.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- `llm_fn` defaults updated to `getOption("TaxaID.llm_fn", call_anthropic_api)` in `build_priors()`.
- `leaflet`, `shiny`, `miniUI` moved from Imports to Suggests (only used in
  `plot_theta_map_interactive()` which already had `requireNamespace()` guards).

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaExpect-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools),
  WERC review integration. See TaxaID/CLAUDE.md for full log.

**Session 86 (2026-05-23)**
- `build_priors()`: `llm_fn` fallback updated from `TaxaTools::call_anthropic_api` to
  `TaxaTools::call_api`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`.

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/generate_priors_workflow.R` added — the modelling step is genuinely
  data-hungry (`optimize_grid_size()`'s real minimum-data thresholds; a binomial GLMM needs
  co-occurring species to estimate relative abundance), so DEBUG_MODE cannot use a sub-minute
  toy example the way TaxaFetch's/TaxaHabitat's scripts do. It tries TaxaHabitat's checkpoint
  first (with a species-breadth pre-flight check, not just a location-count one), and falls
  back to a wider live GBIF fetch (family Gadidae) when the upstream data is too narrow.
- Live-tested end to end (real GBIF fetch, real glmmTMB fit) as part of a 5-package chain.
  Six real bugs found and fixed by actually running it (none caught by reading alone) —
  hardcoded `compute_moran_basis()` k crashing on sparse grids; a `paste0()` zero-length-vector
  quirk silently building a formula term for a nonexistent column; `screen_spatial_formula()`'s
  `recommended_formula` being a character string, not a formula object (needs `as.formula()`);
  and more. Full list in `ecosystem_docs/LAYER1_WORKFLOWS.md` — read that before touching this
  script again, several of these are exactly the kind of thing that would silently recur.

**Session 129 (2026-07-03): screen_spatial_formula()/generate_full_priors() fixes for zero-Tier-1-species real data**

Both surfaced running `TaxaAssign::camera_trap_posterior_workflow.R`'s real GBIF-prior
pipeline on a small/sparse real dataset (all species below `min_obs_threshold`, so
`train_biodiversity_model()` legitimately produces `models$tier1 = NULL` by design).

- `screen_spatial_formula()` called `glmmTMB::VarCorr(model_full$models$tier1)`
  unconditionally at its VarCorr pre-screen step, crashing (`no applicable method for
  'VarCorr' applied to an object of class 'NULL'`) whenever this happened. Fixed with an
  early-return guard — same "nothing to screen, return the fitted model as-is" pattern
  the function already used for formulas with no screenable spatial terms.
- `generate_full_priors()` then failed downstream with "no predictions generated": when
  `models$tier2` is also `NULL` (Tier 2 GLMM failed to fit, e.g. a single-level habitat
  factor), `predict_tier()` returns `NULL` for every candidate, even though
  `train_biodiversity_model()`'s own docs promise "Tier 2 species will fall back to
  empirical means" — nothing downstream ever consumed `$tier2_empirical` to actually do
  that. Added `predict_tier_empirical()`, using the same moment-matching helper the GLMM
  path already uses; wired in as the fallback specifically when `models$tier2` is `NULL`.
  Not spatially resolved (no GLMM to interpolate from), and only covers species x habitat
  combinations with at least one positive training detection — species with zero
  detections still correctly fall through to `generate_undetected_diversity()`'s
  dark-diversity handling, unchanged.

Both verified against synthetic reproductions of the exact failure conditions, and
against the full TaxaExpect test suite (386 expectations, 0 failures, both before and
after). Separately, `devtools::check()` found a pre-existing non-ASCII em-dash in
`generate_undetected_diversity()`'s warning text (unrelated to the above, same fix
pattern as TaxaAssign's Session 122 ASCII cleanup) — fixed, `check()` now 0/0/0.

**Session (2026-07-03): habitat_col = NULL support -- fixes a real Tier 2 fitting bug found designing a single-observation prior pipeline**

Found while testing whether TaxaExpect's community-level prior pipeline could be run on
a *narrow*, candidate-only occurrence fetch as a stand-in for a full regional model (part
of `single-observation-pipeline` branch design work, not yet merged). Skipping
`TaxaHabitat` (to avoid the LLM cost for a small ad hoc species list) and hardcoding
`main_habitat` to one constant value broke `train_biodiversity_model()`'s Tier 2 fit
outright: `Error: contrasts can be applied only to factors with 2 or more levels`. Root
cause: Tier 2's formula was hardcoded inside the function
(`cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)`, `habitat_col` not
nullable) with no way for a caller to opt out — asymmetric with Tier 1, whose formula is
built by the *calling script* and already had an `if (n_habitat_levels >= 2L)` guard, but
that guard lived outside the package and only ever covered Tier 1.

Confirmed with the user this was a known recurring pain point ("I have encountered this
problem with the habitat model before"), and agreed on a two-path design: if you have a
habitat column, run `TaxaHabitat` and supply it so habitat enters the model as a real
predictor; if you don't, pass `habitat_col = NULL` and skip habitat entirely, rather than
faking a single hardcoded category.

**Changes**, all four touching `habitat_col`:
- `prepare_model_dataframe(habitat_col = NULL)`: uses a single internal placeholder
  column so existing aggregation logic runs unchanged, then drops it from the final
  output entirely (no habitat column at all) instead of exposing it.
- `train_biodiversity_model(habitat_col = NULL)`: the real fix. Tier 2's formula omits
  the habitat term entirely (`cbind(n_species, n_other) ~ (1 | taxon_name)`) instead of
  hardcoding one. `N_total`, singleton identification, and `tier2_empirical` all branch
  on `is.null(habitat_col)` rather than assuming a habitat column exists. A formula with
  a `diag()` habitat term now errors immediately and specifically
  (`"habitat_col = NULL was supplied"`) if `habitat_col = NULL`, checked right after
  formula validation so it fires before the generic "column not found" error would.
- `generate_undetected_diversity()`: singleton-mirror/global-floor rows skip adding a
  habitat column when `model_obj$meta$habitat_col` is `NULL` (two direct
  `df[[habitat_col]] <-` assignments would otherwise error on a NULL subscript). The
  `taxonomy` join (genus/family/order/class/phylum hierarchy) is unaffected.
- `generate_full_priors()`: the most deeply embedded — `observed_combos` lookup,
  `predict_tier()`/`predict_tier_empirical()`'s site-column vectors, and both final
  `select()` calls all read `habitat_col` from `model_obj$meta$habitat_col` and now
  branch throughout. `predict_tier_empirical()`'s join to prediction sites becomes a
  cross join (`tidyr::crossing()`) rather than a keyed join when there is no habitat
  column to join on, since `tier2_empirical` then carries one row per taxon with no
  location dimension at all.

9 new tests across all four functions' test files, covering the specific regression
(Tier 2 must fit successfully with no habitat term, not error), the `diag()`-term/NULL
conflict error, and end-to-end `generate_full_priors()` output with no habitat column.
Full suite: `devtools::test()` reports 378 passing, 0 failing. `devtools::check()`:
0 errors, 0 warnings, 0 notes.

**Not done**: no ecosystem workflow script was changed to actually use
`habitat_col = NULL` yet (this was a package-level fix, not a workflow rewrite); the
`single-observation-pipeline` branch design work that surfaced this is still in progress
and unmerged.

**Second, unrelated bug found and fixed the same session while re-verifying the fix above against real data**: user asked, correctly, why priors for six real bobcat-photo candidates (*Canis latrans*, *Felis catus*, *Lynx rufus*, *Procyon lotor*, *Puma concolor*, *Urocyon cinereoargenteus*) all came out as the exact same `theta_mean` (0.0530) despite wildly different real detection counts (*Canis latrans*: 688 total detections, 6 at the focal grid cell alone; *Urocyon cinereoargenteus*: 27 total, 0 at that cell). Confirmed via `ranef()` that the fitted model itself had real, well-differentiated per-species random intercepts (+2.55 to -0.59 logit units) -- so the bug was downstream, in `generate_full_priors()`, not in model fitting. Isolated by manually replicating `predict_tier()`'s exact internal steps outside the function (correctly differentiated) versus calling the real exported function (flattened) -- the only difference was `theta_epsilon`'s singleton-mirror-derived auto-raise (Session 108), confirmed by testing with `undetected = NULL` (bypasses the raise entirely): predictions became correctly differentiated and matched hand-computed values almost exactly.

Root cause: the auto-raised `theta_epsilon` floor (here, 0.053 -- the mean singleton-mirror detection rate) was applied as a hard clip (`moment_match()`'s `m <- pmax(pmin(m, 1-epsilon), epsilon)`) to **every** tier's predictions, not just Tier 2 (the only tier it was ever meant to protect, per its own original design rationale -- preventing Tier 2 from being conflated with the dark-diversity floor in `join_priors()`). With a broadened, realistic candidate pool (21 real species, the point of the single-observation-pipeline broadening work), many genuinely low-but-differentiated Tier 1 probabilities fell below 0.053 and all collapsed to that identical floor value -- invisible with a small, well-separated candidate list (which is why this was never caught before), very visible and wrong with a more realistic one.

Fix: split into `theta_epsilon` (base, applied to Tier 1 predictions as supplied -- default `1e-6`) and `theta_epsilon_floor` (the auto-raised value, applied only to Tier 2's GLMM predictions and to `predict_tier_empirical()`'s fallback). `predict_tier()`/`predict_tier_empirical()` now take an explicit `epsilon` argument instead of closing over one shared variable. New regression test asserts Tier 1 output is byte-identical whether or not `undetected` is supplied (the thing that triggers the raise) -- directly encodes the invariant the bug violated. Full suite: 379 passing (up one), `devtools::check()`: 0/0/0.

Re-verified end-to-end against the real bobcat-photo data with both fixes applied together: Tier 2 fits (first fix), and priors are now genuinely differentiated in the correct rank order matching raw detection counts (*Canis latrans* highest at 0.0077, *Urocyon cinereoargenteus* lowest at 0.00089).

**Third change, same session, before committing**: user asked to assess whether `optimize_grid_size()` (which also requires `habitat_col` unconditionally, discovered while re-verifying the above) should get the same `habitat_col = NULL` treatment, or whether a placeholder constant habitat value upstream would be simpler. Traced `.score_one_resolution()`'s internals to answer precisely: this function never fits a statistical model, only groups/counts, so a constant placeholder would *not* trigger the Tier-2-style crash here -- but that same placeholder, if passed through by name to `train_biodiversity_model()`, would still trigger it there, meaning a placeholder-based approach requires two different "no habitat" conventions in one pipeline (real placeholder for grid sizing, genuine `NULL` for model fitting). Decided against that: extended `habitat_col = NULL` to `optimize_grid_size()` too, for one consistent convention across all three functions.

Implementation: `no_habitat <- is.null(habitat_col)`; errors clearly if `protected_habitat` is supplied with `habitat_col = NULL` (incompatible); otherwise injects a single internal placeholder category (safe here specifically because no model is fit) so `.score_one_resolution()`'s grouping/counting logic runs unchanged, with `min_locs_per_habitat` becoming redundant with (not contradictory to) `min_distinct_locs`. 4 new tests (basic run, `protected_habitat` conflict error, and an equivalence check that a single real habitat category scores identically to `habitat_col = NULL`). Full suite: 383 passing, `devtools::check()`: 0/0/0.

Final end-to-end re-verification with all three fixes chained together, no workarounds: `optimize_grid_size(habitat_col = NULL)` -> `create_sites_from_grid()` -> `prepare_model_dataframe(habitat_col = NULL)` -> `train_biodiversity_model(habitat_col = NULL)` -> `generate_undetected_diversity()` -> `generate_full_priors()`, against the real bobcat-photo data. Confirmed Tier 2 fits and priors are genuinely differentiated in the correct rank order.

Sessions 28, 29, 62, 73 archived in ecosystem_docs/session_notes/TaxaExpect_sessions.md.
