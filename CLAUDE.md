# CLAUDE.md — TaxaID Ecosystem
# Ecosystem-level context for Claude Code. Auto-loaded from any package subdirectory.
# Package-specific context lives in each package's own CLAUDE.md.
# Last updated: 2026-07-19, continued (Sonnet 5 -- separate, real fetch_ncbi_reference_
# sequences() bug found live-testing PtConceptionWorkflow_18S_2_single_site.R's real,
# full ~1300-genus reference fetch (unrelated to restore_suppressed_candidates() itself,
# but found via the same test-drive effort): do.call(rbind, ...) combining per-genus/
# per-batch NCBI results crashed the entire fetch ("numbers of columns of arguments do
# not match") once real taxonomy XML resolved to slightly different columns across
# genera -- the same failure class already fixed once for the BOLD fetch path, never
# applied to NCBI. Fixed across 6 call sites (dplyr::bind_rows(), matching the existing
# BOLD-path precedent). devtools::test() 0 failures (931, up from 910), devtools::check()
# 0/0/0. See TaxaLikely/CLAUDE.md's top session note for the full record. Not yet
# re-verified against the real fetch that found it (interrupted by the crash) -- left for
# the user to retry.
# Previous update, 2026-07-19 (Sonnet 5 -- second real performance bug found and fixed in
# restore_suppressed_candidates(), this time from the user actually running the updated
# PtConceptionWorkflow_12S_single_site.R against the real, full 13,442-observation dataset
# and reporting a run still going after 70+ minutes. Root cause: the "free" Levels 1-3
# hierarchy did a fresh linear scan over the whole seq_matrix (~3M rows) for every candidate
# species, every call, with zero memoization -- R's own %in%/match() rebuilds its hash table
# on every call rather than caching it, and Purpose A's unconditional genus-wide sweep
# exposed this at genera Mugu never had (Sebastes, 107 species, vs. Fundulus's 20). Fixed
# with a real accession-indexed lookup (R/restore_hierarchy.R's new .seq_matrix_partner_
# index()/.seq_matrix_lookup()), built once per call instead of scanned per candidate.
# Verified: the same real Sebastes case that took 17.64s per repeated anchor now takes 0.03s
# (~590x); the full real 13,442-observation dataset went from 70+ minutes (still running
# when interrupted) to 42.1 seconds. devtools::test() 0 failures (910, unchanged),
# devtools::check() 0/0/0. See TaxaLikely/CLAUDE.md's top session note for the full record.
# Previous update, 2026-07-18, continued yet further (Sonnet 5 -- test-drove the restore_
# suppressed_candidates() redesign against two real motivating cases at the user's request
# (Mugu Fundulus lima/parvipinnis; a newly-found PtConception Girella simplicidens/nigricans
# analog) and found a real cost problem: both real anchors are themselves occurrence-
# implausible (absent from taxaexpect_priors entirely -- exactly the case this function exists
# to handle), which made the compute-budget ratio uncomputable and sent every genus congener to
# Level 4's live alignment under Purpose A's prior-agnostic sweep (Fundulus: 20 species per
# anchor; measured 275.8s for one marker, vs. the documented pre-redesign 38s baseline). Fixed
# per the user's explicit design choice ("Option A with C as a backstop"): candidate_species_
# filter restored as Level 4's own default cost gate (falls back to the ratio only for a
# candidate not on it); new max_level4_per_anchor hard backstop cap (default 10L). Verified
# against both real cases: correctness fully preserved (F. parvipinnis still wins at
# 99.7-99.9% posterior, if anything stronger than before; G. nigricans still admitted at its
# real ~98% score), cost cut ~4x (Fundulus) / ~3x (Girella). Rolled out the same day to all
# four real production workflow scripts this whole redesign was validated against
# (MuguFishWorkflow.R, MuguWilderFishWorkflow.R, PtConceptionWorkflow_12S_single_site.R,
# PtConceptionWorkflow_18S_2_single_site.R -- all outside this monorepo, not under git): the
# now-invalid detected = detected argument removed from each; both Mugu scripts additionally
# gain model_params = lik_model (enabling Purpose A there, since lik_model is already trained
# before the restore call in both -- not true for either PtConception script, which train
# lik_model afterward, so Purpose A stays unavailable there without a larger reordering not
# attempted this session). Four OTHER real PtConception files still call the old signature and
# were flagged to the user, not touched: PtConceptionWorkflow_12S_multi_site.R (a real,
# same-day-modified sibling) plus three older/secondary files. devtools::test() 0 failures
# (910, up from 893), devtools::check() 0/0/0. See TaxaLikely/CLAUDE.md's top session note for
# the full record and [[project_restore_suppressed_candidates_implementation]] in the memory
# system.
# Previous update, 2026-07-18, continued further (Sonnet 5 -- implemented
# ecosystem_docs/SPEC_restore_suppressed_candidates_redesign.md end to end: TaxaLikely::
# restore_suppressed_candidates() ground-up redesign, reframing its job from "restore candidates so
# more can individually win" to "detect whether the anchor's apparent win is real or a suppression
# artifact." New restoration_basis column ("competitive_score"/"plausible_prior"/"both") records
# admission under Purpose A (prior-agnostic score-only outlier test, needs model_params) and/or
# Purpose B (wide max_dist floor, gated by candidate_species_filter -- re-scoped to Purpose B only,
# no longer gates all restoration). New score-sourcing hierarchy (R/restore_hierarchy.R) replaces
# the old flat anchor_score - delta imputation with real, median-aggregated evidence (free
# seq_matrix/model lookups for Levels 1-3, live Tier 2 alignment only at Level 4, now returning a
# real percent-identity score via .check_regional_overlap()'s new return_detail mode). New opt-in
# compute-budget mechanism (taxaexpect_priors) sizes Level 4 spend from the floor-vs-documented
# occurrence-prior ratio, derived from posterior_consensus()'s min_posterior = 0.05
# (R <= 19 -> worth spending; R > 19 or non-computable -> skip). BREAKING, intentionally: the scored
# pathway is now a no-op without real evidence supplied (seq_matrix and/or check_regional_overlap +
# model_params) -- the old default silently restored every same-genus congener regardless. No
# production workflow (PtConception 12S/18S_2, both Mugu scripts) has been updated to the new
# signature yet -- that rollout is a deliberate follow-on task, not attempted this session.
# devtools::test() 0 failures (893, up from ~860), devtools::check() 0/0/0, reinstalled to
# ~/Library/R/4.0/library. See TaxaLikely/CLAUDE.md's own top session note for the full record and
# [[project_edge_case_error_taxa_design]] in the memory system for the design-conversation history
# this implements.
# Previous update, 2026-07-18 (Fable -- answered the foundational "is train_likelihood_model() trained
# on data comparable to what it predicts?" question in ecosystem_docs/REENTRY_PROMPT_train_likelihood_
# model_scoring_validity.md, then shipped a fix. Verdict on real 12S: the DECIPHER-MSA-trained H1
# per-species means do NOT transfer to the external/undocumented inference scoring scale -- on the
# 8,860-obs non-circular confident set, per-species required offset vs trained mean has slope ~ -1
# (real queries collapse to ~one identity level regardless of the reference-MSA prediction), and a
# single pooled inference mean beats "per-species mean + one offset" in 5-fold CV. A single additive
# offset (calibrate_query_noise()'s original behavior) is therefore patching per-species structure
# that isn't real on the inference scale. Fix: new opt-in TaxaLikely::calibrate_query_noise(
# offset_form = "linear") level-aware recalibration (default "constant" = unchanged); remaps H1 means
# through a robust line, collapsing to pooled-location when structure doesn't transfer and reducing to
# the constant offset when it does; only H1 mean location moves, H2/H3 deltas + gap discriminators are
# untouched. Real-12S H1 win rate 74.2% -> 76.3% via the shipped function. Opt-in because the confident
# set can't test congener discrimination; not wired into any production workflow yet. TaxaLikely
# devtools::test() 0 failures / check() 0-0-0, installed to ~/Library/R/4.0/library. See TaxaLikely/
# CLAUDE.md's matching note and [[project_train_inference_scale_validity]] in the memory system.
# Continued 2026-07-18: (1) GENERALITY confirmed on 4 more real datasets -- Mugu WilderFish 12S/16S/COI
# (all BLAST-scored) collapse just like PtCon 12S (slopes -0.28/0.02/-0.21), which IS the clean
# DECIPHER-vs-BLAST test the reentry doc's Q1 wanted (BLAST doesn't preserve DECIPHER per-species locations
# either -> general aligner property, not a PercMatch artifact); PtCon 18S (2 referenced species) correctly
# falls back to constant. (2) Manuscript-quality write-up added to TaxaLikely/inst/TaxaLikely_supplemental_
# methods.md (new subsection 11A + 4 web-verified references: May 2004, Raghava & Barton 2006, Platt 1999,
# Quinonero-Candela et al. 2009) + calibrate_query_noise() roxygen + Section 16 mapping. User is a
# statistician -- references verified by search/fetch, not recited. offset_form=linear still not default,
# not wired into workflows (user validating 12S posteriors first).
# Previous update, 2026-07-17 (Session 159, PtConception rollout -- Task 1 of
# ecosystem_docs/REENTRY_PROMPT_session159_regional_overlap_rollout.md, the other two
# tasks (join_priors() coarse-rank question, broader 12S/16S/COI sanity pass) dropped
# from scope at the user's request. Both real PtConceptionWorkflow_12S_single_site.R
# and _18S_2_single_site.R (outside this monorepo, at ~/My Drive/Rscripts/eDNA/
# PtConception/) now join each ESV's raw read-file sequence onto match_obj and call
# restore_suppressed_candidates(check_regional_overlap=TRUE, sequence_col="sequence",
# candidate_species_filter=...), with attr(match_obj, "regional_unreferenced") captured
# before the post-restoration backbone conversion and folded into unreferenced_df --
# same pattern Session 159 already established for Mugu. Live-tested against the real
# cached 13,442-observation 12S checkpoint before touching the production scripts:
# confirmed the mechanism has a REAL effect (2,118 congener rows rejected on
# regional-overlap grounds across a random 2,000-observation sample, 33 restored as
# real overlapping congeners), and surfaced two more real TaxaLikely performance bugs
# via Rprof profiling -- Tier 2b's query-vs-anchor alignment recomputed once per
# candidate species instead of once per (anchor, query_sequence), and (far larger)
# Tier 1's "free" seq_matrix lookup re-stripping version suffixes via sub() over a
# real ~3-million-row seq_matrix on every single call, >90% of total wall time.
# Both fixed via align_cache (new keys, no signature change) -- see TaxaLikely/
# CLAUDE.md's own Session 159 note for the fix detail. Real, timed result: 84s -> 6.8s
# on a 300-observation subset; ~65min -> ~17min extrapolated for the full dataset, for
# this one function call alone (the full production workflow includes many other
# expensive steps not touched this session). devtools::test() all passing, reinstalled
# to both R libraries, both workflow scripts parse cleanly -- but NOT yet run
# end-to-end in production (would overwrite real checkpoints + make real GBIF/NCBI/LLM
# API calls), left for the user to trigger. See
# [[project_regional_overlap_gap_modeling]] in the memory system for the full record.
# Previous update, 2026-07-16 (Session 159, continued yet further -- three more real bugs found
# ONLY because the user pushed back with "I still get Fundulus lima" after being told the fix
# was complete, and asked for a real diagnosis rather than accepting reassurance. Each was a
# genuine correctness/performance bug in code from earlier the same session, not a stale-run
# issue this time. (1) restore_suppressed_candidates()'s check_regional_overlap never even ran
# for real 12S data: detect_suppressed_candidates() correctly found no GLOBAL suppression
# pattern (real BLAST output with score_range=8 is a genuine mix of 240 true singletons and
# 161 real multi-candidate ties, so no purity threshold clears its aggregate bar), so the
# function's original top-level gate returned before the per-observation loop ever ran, for
# ANY observation. Fixed by decoupling: when check_regional_overlap=TRUE, every observation is
# checked regardless of the global verdict, safe because every addition is still gated on real
# evidence. (2) That fix then ran for 15+ minutes on real data before being killed (confirmed
# via `ps`, genuinely CPU-bound) -- 401 real observations reduced to only 71 distinct BLAST
# anchors (one reused 113 times), but the alignment was being recomputed per OBSERVATION
# instead of per (anchor, candidate) pair. Fixed with a memoizing align_cache. (3) Even
# memoized, one real genus had 42 globally-referenced congeners, and checking all of them
# against every anchor sharing that genus still meant 2,361 real alignment pairs -- fixed with
# a new candidate_species_filter param that restricts candidates to a locally-plausible list
# BEFORE any expensive work (using taxaexpect_priors$taxon_name, the same list already applied
# downstream anyway). Real, timed result: 38 seconds for one marker, down from 15+ minutes.
# Verified end-to-end against real saved data: ASV_300 now correctly carries two competing
# hypotheses (F. lima specific_candidate + F. parvipinnis unreferenced_species) instead of
# F. lima alone with posterior=1.0. Wired into both Mugu workflows; reinstalled to BOTH the
# user and system R libraries after discovering mid-session that the Mugu scripts' own RStudio
# session (outside the TaxaID project) may resolve either one. devtools::test() 768/768 (up
# from 754), devtools::check() 0/0/0. See TaxaLikely/CLAUDE.md's matching note for full detail.
# Previous update, 2026-07-16 (Session 159, final entries -- two more fixes closing out the
# real Mugu F. lima/F. parvipinnis misassignment debugging thread this whole session's
# work has been chasing. (1) fetch_ncbi_reference_sequences(keep_out_of_range = TRUE) had
# no upper size bound -- found via a real 111,213,091bp whole-genome scaffold in the real
# Mugu reference_df.rds; fixed with max_out_of_range_len = 200000L, folded into the cache
# key too (which hadn't varied by keep_out_of_range at all -- a real staleness bug).
# (2) Diagnosed why the user's real Mugu run "didn't change the outcome" even after the
# check_regional_overlap fix was correctly rejecting F. parvipinnis per-observation: a
# rejected congener was simply OMITTED from the candidate set rather than becoming a real
# competing hypothesis, so F. lima won by default whenever nothing else was left. Built the
# extension: restore_suppressed_candidates() now records what it rejects via
# attr(result, "regional_unreferenced"); expand_unreferenced_hypotheses()'s unreferenced_df
# gained an optional observation_id column so a globally-referenced-but-regionally-rejected
# species can still compete as a named unreferenced_species hypothesis for just the one
# query that rejected it, without being treated as globally unreferenced everywhere else.
# Both additive/backward compatible. Wired into MuguFishWorkflow.R; MuguWilderFishWorkflow.R
# deliberately left unwired (its own Step 8 never calls expand_unreferenced_hypotheses() at
# all -- flagged as a pre-existing architecture gap for the user to decide on, not changed
# unilaterally). devtools::test() 754/754 (up from 706), devtools::check() 0/0/0. See
# TaxaLikely/CLAUDE.md's Session 159 final-entry note for the full record.
# Previous update, 2026-07-16 (Session 159 -- real stale cross-package reference found and
# fixed in both real Mugu production workflows (MuguFishWorkflow.R,
# MuguWilderFishWorkflow.R -- outside this monorepo, not under git, at ~/My Drive/
# Rscripts/eDNA/SepulvedaMugu/), found live: the user cleared their bbox cache to force a
# fresh run and hit "'define_search_polygon' is not an exported object from
# 'namespace:TaxaFetch'" -- reproduced directly. Root cause: define_search_polygon() moved
# TaxaFetch -> TaxaTools back in Session 134b (no forwarding alias was left behind in
# TaxaFetch, unlike this ecosystem's usual deprecated-wrapper rename pattern), and neither
# Mugu script was ever updated to the new namespace after that move -- MuguFishWorkflow.R's
# call sits behind a bbox-cache guard, so it had been silently skipped on every re-run
# since Session 134b as long as a cached bbox.rds existed; MuguWilderFishWorkflow.R has no
# such guard, so its call would fail on every single run, cache or not. Fixed by updating
# both calls to TaxaTools::define_search_polygon(). While investigating, also directly
# checked whether the two Mugu workflows share the BLANKS_MARCH-class bug just found and
# fixed in both PtConception single-site scripts (empty/near-empty "recognized" blank
# columns while real, substantially-read blanks go uncounted as field data) -- confirmed
# they do NOT: MuguFishWorkflow.R/MuguWilderFishWorkflow.R's BLANK_IDS (4 numeric sample
# IDs, X104433/X104456/X104480/X104495) rank #1/#2/#3/#8 of 63 real sample columns by total
# read count (11K-344K reads vs. a ~698K median for real field samples) -- the correct
# signature for genuine, functioning negative controls, not empty placeholders. No
# separate sample-metadata spreadsheet exists for this dataset (unlike Dangermond's file
# for PtConception) to independently cross-check completeness, but nothing found suggests
# a missed blank the way the PtConception case had. No code change needed for Mugu's blank
# identification.
# Previous update, 2026-07-15 (Session 158 -- "Job 2": TaxaLikely's unreferenced-relative
# (H2/H3) likelihood modeling, prompted by the user questioning a real posterior result
# (three unreferenced Sardinops congeners all sharing an identical 0.566 likelihood) and
# a stated intuition that tight genera (species hard to tell apart) should show LOWER,
# more consistent divergence than loose genera, with the loose genera carrying MORE
# uncertainty, not less. Testing this against real 12S congener data found the shipped
# model gets it qualitatively BACKWARDS under the package's original logit scale (a real
# genus-tightness reversal, not just an unvalidated default) -- traced to logit's
# derivative diverging fastest exactly where real barcode data concentrates (near 100%
# identity). Fixed by adding a new `score_transform` option
# (`train_likelihood_model(score_transform = "sqrt_mismatch")`, Anscombe's classical
# rare-event-count variance stabilizer, chosen after checking and rejecting probit and
# complementary log-log too) that H1/H2/H3 all move onto together -- reproduces the
# correct genus-tightness direction on real held-out cases via the actual package
# functions, not just aggregate diagnostics. Also fixed: H2's mean now anchors on the
# specific referenced species' own resolved mean rather than the population-wide
# average; H2 gets a genus-specific variance (previously only the mean shift was
# genus-specific); the pooled H2 default was quietly sourced from the wrong
# (cross-any-genus, not same-genus) population. A third, larger, unrelated bug was found
# and fixed along the way at the user's explicit request: `H1_Lookup$sigma_score` had
# been storing the square root of the intended shrunk variance since this formula was
# first written, silently understating every species-specific H1 candidate's true
# uncertainty on BOTH the old and new score scales -- invisible on logit's larger natural
# scale, unmissable once sqrt_mismatch's much smaller scale exposed it directly against a
# hand computation. `devtools::test()` 696/696 (up from 670), `devtools::check()` 0/0/0
# throughout. `score_transform = "logit"` remains the package default; `"sqrt_mismatch"`
# is opt-in, not yet rolled into any production workflow. See TaxaLikely/CLAUDE.md's
# Session 158 note and [[project_job2_unreferenced_relatives]] in the memory system for
# the full empirical derivation, including why several other candidate transforms were
# checked and rejected.
# Previous update, 2026-07-14 (Session 157 -- redesigned TaxaLikely::evaluate_likelihoods()'s
# score_likelihood_mean/score_likelihood_sd, prompted by the user stepping back from the
# evidence_col/depth work in Session 156 to ask a more fundamental question: what should
# "uncertainty around a likelihood estimate" actually mean, and does the existing n_sims
# mechanism compute that? It didn't -- it resampled the query's OBSERVED score around the
# global population dispersion (answering a sensitivity question, not a confidence-in-the-
# estimate question) and never touched evidence_vec at all. Redesigned so
# score_likelihood_sd instead reflects uncertainty in the TRAINED MEAN itself, driven by how
# much reference data calibrated it (Var(mean) ~= sigma^2/n, the standard uncertainty-in-an-
# estimated-mean result). train_likelihood_model() already computed n_obs_species (species
# reference-sequence count) for Empirical Bayes shrinkage and then discarded it -- now
# retained in H1_Lookup, with an analogous n_pairs-based treatment for H2/H3 (which
# correctly get systematically wider uncertainty than H1, since they borrow a shifted mean
# rather than being directly observed -- closing the user's explicit third ask, "add
# variance for unreferenced taxa"). Mechanically this redirects the existing n_sims loop
# (same asymptotic cost) rather than adding a new one, and reuses the already-computed
# evidence-adjusted per-candidate sigma from Session 155/156, so that mechanism's
# contribution to uncertainty falls out for free at zero extra cost -- resolving the
# "should I care about evidence" question the user posed without building anything
# evidence-specific. Fully backward compatible (falls back to the previous mechanism when a
# model_params object predates n_obs_species); no new output columns; no changes needed in
# TaxaAssign, since compute_posterior() already consumes these two columns for its own
# Beta-prior Monte Carlo. Verified with 3 new regression tests (low-n vs high-n species,
# low- vs high-n_pairs H2 delta, legacy fallback) plus a real-data check: retrained on the
# real 12S seq_matrix, ran evaluate_likelihoods() on 300 real observations at n_sims=200
# (11.2s, reasonable), confirmed median H1 sd (0.075) is meaningfully tighter than median
# H2/H3 sd (0.119) on real data. devtools::test() 674/674 (up from 670), devtools::check()
# 0/0/0. See TaxaLikely/CLAUDE.md's Session 157 note for the full derivation.
# Previous update, 2026-07-14 (Session 156 -- direct continuation of Session 155's
# evidence_col/evidence_max_ratio sigma-rescale mechanism in TaxaLikely::evaluate_likelihoods()
# ([[project_evidence_ratio_sigma_reentry]]): that mechanism was safe but validated as net
# negative even at its capped, widen-only default (27 helped, 2053 hurt on real 12S data).
# Replaced the unconditional rescale with a closed-form crossover gate, derived (not
# guessed) from the elementary fact that rescaling a Gaussian's variance by a factor c
# changes its log-density at z standard deviations from the mean by exactly
# -0.5*log(c) + 0.5*z^2*(1-1/c) -- widening (c>1) must lower the peak to raise the tails,
# since the density still integrates to 1, so it only pays off once z is large enough; most
# low-evidence real observations are still close-to-mean decent matches, which is exactly
# why the old unconditional version hurt more often than it helped. The rescale is now
# applied only when this quantity is provably >0 for that candidate -- verified numerically
# against a live dnorm() call before shipping. Re-validated same session against the real
# 12S PtConception dataset: 163 helped / 3 hurt across 24,857 real H1 rows (vs. the
# unconditional version's 27 helped / 2053 hurt), mean H1 likelihood 0.8014 -> 0.8016 (flat-
# to-slightly-positive, vs. the old real regression 0.899 -> 0.884). Traced the 3 residual
# hurt cases directly to the gate's own documented score-only-marginal approximation (the
# real score/gap covariance term is ignored by the gate but not by the density actually
# evaluated) -- confirmed via direct mvtnorm::dmvnorm computation on the real numbers, bounded
# to <1% swing, not a new bug. See TaxaLikely/CLAUDE.md's Session 156 note for the full
# derivation, code location, and validation record.
# Previous update, 2026-07-13 (Session 154 continued further -- confirmed and fixed the
# identical BLANKS_MARCH-class bug in PtConceptionWorkflow_18S_2_single_site.R, prompted
# by the user asking what to do next after the 12S fix and correctly guessing it would
# recur (the March 18S and 12S runs share the same physical Barcodes). Confirmed directly:
# BLANKS <- c("Blank1.1", "Blank2.1") -- "Blank1.1" has zero reads across every ESV in
# this file, "Blank2.1" has only 16 (both effectively-empty placeholders); the same 4 real
# Barcode-keyed blanks (2ONWVS29, S067819, PBPUPL5A, XTLNX5VZ) carry real, substantial
# reads in this file too (749 / 2071 / 2103 / 59,298 respectively -- the 18S run has only
# one replicate column per Barcode, simpler than 12S's 1-10 PCR replicates, but the same
# real blanks matter). Fixed the same way as the 12S case: BLANKS's literal value
# corrected (still a plain user-edited vector, same .resolve_base_barcode() cascade
# reused) rather than any new inference mechanism. Live-verified against the real 18S read
# file: 4 real blank event_ids now correctly identified
# (X2ONWVS29.1/PBPUPL5A.1/S067819.1/XTLNX5VZ.1); Blank2.1 correctly falls through as
# unresolved (not a real Barcode, its 16 reads are noise). Not yet re-run end to end (Step
# 1's match_obj construction needs real TaxaMatch/TaxaTools calls not exercised by this
# check) -- the user's call whether/when to re-run
# PtConceptionWorkflow_18S_2_single_site.R with the fix. Both Mugu workflows
# (MuguFishWorkflow.R, MuguWilderFishWorkflow.R) have NOT been checked for the same
# pattern -- different dataset, own blank-identification logic, no evidence either way yet.
# Previous update, same day (Session 154 continued -- Task B, Phase 2 of the multi-site
# workflow migration (see ecosystem_docs/REENTRY_PROMPT_session153_multisite_workflow_
# migration.md): PtConceptionWorkflow_12S_multi_site.R's Section 2.5 now joins the real
# Dangermond_Sample_Metadata2_31Jan24.xlsx (March 2021 run, Barcode-keyed) and sets
# spatial_group_id directly from each site row's own real Location (BioD/Cojo/Jalama) --
# live-verified end to end against the real data (Steps 1-2.5 run for real, not just
# parsed): 4 real spatial groups, BioD 10,944 / Jalama 1,756 / Cojo 1,615 / a fallback
# group of 2,897 August-only rows (no confirmed August site metadata, falls through to
# STUDY_LAT/STUDY_LON per the reentry prompt's explicit scope). Deviates from the reentry
# prompt's plan in one deliberate way, found empirically before implementing: real data
# shows 582 of 10,550 real-site ESVs (5.5%) are genuinely detected at MORE than one
# Location (BioD+Cojo 205, BioD+Jalama 225, Cojo+Jalama 38, all three 114) --
# TaxaMatch::assign_spatial_group() sets spatial_group_id by OBSERVATION_ID (moves ALL of
# an ESV's site rows at once), so calling it once per Location would silently reassign a
# genuinely multi-Location ESV's other site into whichever Location's call ran last.
# Fixed by setting spatial_group_id directly per ROW from that row's own real Location
# instead (no assign_spatial_group() call at all) -- correctly preserves these 582 ESVs as
# separate site-rows in separate groups, ready for combine_multisite_priors() (Phase 5) to
# recombine. Real read-file complication also found and solved: March's sample columns are
# NOT bare Barcodes -- "<Barcode>.<replicate#>" (1-10 PCR replicates) or
# "<Barcode>.<letter>.<replicate#>" (independent extraction replicates), plus read.csv's
# leading-"X" mangling of digit-starting names (real Barcodes also legitimately start with
# "X", so this can't be stripped unconditionally) -- a 4-step resolution cascade
# (.resolve_base_barcode(), in both workflow files) resolves 498/500 real March sample
# columns to a real Barcode. Step 8's update_prior_from_consensus(spatial_group_map =
# site_table) call is NO LONGER a no-op now that real groups exist; a real open question
# (the ~2,897 August-only fallback observations all share one coordinate and so also
# read as one large "multi-member" group, even though they don't share a real site) is
# flagged in-line at that call for Phase 3+, not resolved this session.
#
# A real, previously-unknown data-quality bug was found and fixed along the way, in BOTH
# PtConceptionWorkflow_12S_single_site.R and _multi_site.R: BLANKS_MARCH = c("Blank1.0",
# "Blank2.0") -- the March run's only recognized "blanks" -- turned out to be two literal
# read-file columns with ZERO reads across every ESV in the file (empty placeholders, not
# real controls), meaning the March run's contaminant detection had been running with
# NO real March-run controls of its own, borrowing the August run's controls as the entire
# control-side signal for both runs pooled. Meanwhile 4 real Barcode-keyed blanks
# (2ONWVS29, S067819, PBPUPL5A, XTLNX5VZ -- flagged BagID == "BLANK" in the Dangermond
# metadata, carrying real reads up to 46,752 in one ESV) were silently counted as ordinary
# field data the whole time, since nothing cross-referenced the metadata for blank status
# before this session wired that file in for the first time. Fixed by correcting
# BLANKS_MARCH's literal value (still a plain, user-edited vector -- deliberately NOT
# wrapped in an auto-inference function, per the user's explicit caution about brittleness
# across studies with different metadata conventions) plus switching March's blank-match
# logic to use the same barcode-resolution cascade. Live-verified: flag_contaminant()'s
# control count rose from 24 (August-only) to 33; high-risk contaminant ESV count rose
# from 22 to 43 on the same real 12S dataset -- a substantive change to
# decontaminated_esv_data and therefore every downstream step. The _single_site.R script
# already running in the user's RStudio session at the start of this work used the
# pre-fix logic; re-running it is the user's call, not done automatically. A general,
# NOT-yet-built design idea (cross-check/derive blank identification from site metadata
# instead of a fully independent hand-typed list, so this class of gap is caught rather
# than silently recurring per-workflow) is written up in ecosystem_docs/
# REENTRY_metadata_driven_blank_detection.md for a future session -- deliberately not a
# rigid package function, since metadata conventions vary per study and not every
# workflow has one.
# Previous update, same day (Session 154 -- Task B, Phase 1 of the multi-site workflow
# migration: new PtConceptionWorkflow_12S_multi_site.R created from the _single_site
# baseline (outside this monorepo, not under git, at ~/My Drive/Rscripts/eDNA/
# PtConception/). Section 2.5 built a site_table (TaxaMatch::build_site_table()) covering
# every ESV, but every row was deliberately given the SAME STUDY_LAT/STUDY_LON coordinate,
# so the default exact-(lat,lon)-match grouping collapsed everyone into ONE
# spatial_group_id -- a genuine no-op, not just an approximation: TaxaAssign::
# update_prior_from_consensus()'s spatial_group_map restriction only gates on whether an
# observation's group has >= 2 members, and with one group holding every observation,
# every observation cleared that bar exactly as it would with spatial_group_map = NULL
# (the _single_site call's own behavior). OUT_PREFIX changed to PtConMifishSchulteMulti so
# this file's checkpoints never collide with _single_site's (confirmed no conflict with
# the _single_site run active at session start). Fully superseded by Phase 2 above.
# Previous update, 2026-07-13 (Session 153 -- comparison + template-alignment pass across all
# four real production workflow scripts (PtConceptionWorkflow_12S.R, PtConceptionWorkflow_
# 18S_2.R, MuguFishWorkflow.R, MuguWilderFishWorkflow.R -- all outside this monorepo, not
# under git). Prompted by the user noticing the 12S workflow filters contaminants in a
# different order than inst/TaxaID_Workflow_Template_TEST.R; a systematic 4-way comparison
# (one Explore agent per workflow, rubric built from reading the template directly) found
# the same root problem in ALL FOUR: TaxaFlag::flag_contaminant() ran early and flagged
# risk correctly, but nothing ever actually EXCLUDED high-risk rows before GBIF search,
# reference-sequence fetch, or posterior computation -- only cosmetic annotation (or, for
# both Mugu workflows, no filtering at all until the final export). Fixed identically
# across all four: high-risk observation_ids are now excluded from the match/taxonomy
# object immediately after flag_contaminant() runs, before anything downstream consumes
# it. Per the user's explicit direction, split the work into two tracks: **Task A**
# (this session, complete) applies every template-alignment fix that does NOT depend on
# spatial/multi-site grouping to all four workflows; **Task B** (deferred, real per-sample
# site metadata already confirmed to exist for the March 2021 12S/18S runs via
# Dangermond_Sample_Metadata2_31Jan24.xlsx -- BioD/Cojo/Jalama, ~8km apart, genuinely
# unused today) migrates the template's Sessions 137-139 spatial-grouping architecture
# into new PtConceptionWorkflow_12S_multi_site.R / _18S_2_multi_site.R siblings, staged
# separately; see ecosystem_docs/REENTRY_PROMPT_session153_multisite_workflow_migration.md.
# The two Pt Conception workflows were renamed to *_single_site.R as part of Task A, ahead
# of that future multi-site split; the two Mugu workflows keep their names (no multi-site
# sibling planned).
#
# Task A specifics, all four workflows unless noted: (1) contaminant filtering, above.
# (2) Backbone-conversion-ordering audited against the template's "convert once early,
# convert again after restore_suppressed_candidates()" pattern -- genuinely needed only in
# PtConceptionWorkflow_18S_2_single_site.R (was missing the second conversion entirely,
# with a stale comment claiming it happened elsewhere); 12S and both Mugu workflows were
# individually verified to already be backbone-consistent via a different, equally valid
# mechanism (Mugu converts reference_df to GBIF *before* restoration, which is safe
# specifically because its match_obj is already GBIF-backbone from the upstream match-
# building scripts) -- confirmed by tracing each file's actual backbone state rather than
# applying the template's exact pattern by rote, avoiding an unnecessary and potentially
# corrupting double-conversion. (3) Reference-sequence fetch modernized to
# TaxaLikely::fetch_ncbi_reference_sequences() everywhere: 12S/18S_2 replaced hand-rolled
# rentrez::entrez_fetch() accession-reuse loops (no barcode-length filtering, so
# mitogenomes could enter the reference set); both Mugu workflows swapped the
# *deprecated* fetch_reference_sequences() name for the current one (confirmed a pure
# forwarding wrapper, zero behavioral change). (4) evaluate_likelihoods()'s
# ratio_threshold checked against the template's deliberate override (0, vs. the package
# default 0.01) -- alpha=0.001 and train_likelihood_model()'s prior_weight=10.0 already
# matched the template as package defaults and needed no change; ratio_threshold=0 was
# missing from three of the four workflows (MuguFishWorkflow.R already had it) and was
# added to match.
#
# Live-tested every actual change against real data (not just devtools::check() on
# package source, since these are workflow scripts, not package functions) -- ran each
# workflow's modified section against real cached upstream checkpoints, skipping only the
# interactive Shiny review gadgets (review_spatial_flags()/plot_theta_map_interactive()/
# define_search_polygon(), all called live/uncommented in these real scripts and all
# blocking in a non-interactive session) that sit downstream of nothing this session
# touched. This surfaced one real, previously-latent bug the static comparison alone would
# have missed: candidate_genera derivation (`filter(!is.na(genus))`, copied faithfully
# from the template's own Section 3/6a) doesn't exclude **empty-string** genus values,
# only NA -- and this real 12S/18S_2 data has them (low-confidence BLAST/GBIF matches
# leave genus = "" rather than NA). An empty string reached
# fetch_ncbi_reference_sequences() as a literal taxon name and crashed it
# (`retmax_cap[[taxa[i]]] : subscript out of bounds`). Fixed with an added `nzchar(genus)`
# guard in both PtConception workflows; confirmed both Mugu workflows already had this
# guard (`match_obj$genus != ""`) independently. **Fixed at the source, too**: the
# identical unguarded pattern exists in inst/TaxaID_Workflow_Template_TEST.R at both the
# escalation-ladder singleton-genus derivation (~line 467) and the Section 6a reference-
# fetch derivation (~line 933) -- the template's own tiny 3-ASV bundled fixture never had
# an empty-string genus to expose this, so every future workflow built from the template
# would have inherited the same latent crash. Both fixed with the same guard.
#
# One real TaxaAssign package bug found and fixed along the way (see TaxaAssign/CLAUDE.md's
# Session 153 note for full detail): update_prior_from_consensus()'s Session 149 alpha/
# beta-consistency fix didn't clamp the boosted prior_mean away from the [0,1] boundary --
# a confirmation quantile of exactly 1.0 (common: posterior_consensus() legitimately
# returns 1.0 for any unambiguously resolved single-candidate donor) produced
# prior_beta = 0, which compute_posterior() correctly rejects. This is a real regression
# introduced by Session 149's own fix (the previous design never touched prior_alpha/
# prior_beta at all). Fixed with the same boundary clamp join_priors.R's .make_ab() helper
# already uses for the identical reason. devtools::test() 548/548 (up from 544),
# devtools::check() clean.
# Previous update, 2026-07-12 (Session 152 continued -- a full, real end-to-end live run of
# inst/TaxaID_Workflow_Template_TEST.R (all 8 sections, real BLAST/GBIF-derived data/two
# real Anthropic LLM calls/real NCBI reference fetch) completed successfully, confirming
# the Template operates correctly with the ecosystem's full set of recently-updated
# functions. Along the way found and fixed a real, previously-invisible bug:
# TaxaAssign::posterior_consensus()'s internal .extract_rank_values() had a
# genus-from-binomial fallback but no equivalent species-from-taxon_name fallback, so
# consensus_posterior/consensus_confidence_score silently computed to exactly 0 for every
# single-hypothesis resolved observation whenever the input lacked an explicit "species"
# column -- exactly TaxaLikely's real sequence/BLAST pathway's shape. consensus_taxon
# itself was unaffected (a different, already-correct code path), which is why this went
# unnoticed; also surfaced a real test-coverage gap (no existing test asserted on
# consensus_posterior's VALUE at all). Fixed by mirroring the existing genus derivation.
# Two other real, separate findings surfaced during the same live-testing pass (not new
# ecosystem-function bugs, but genuine gaps worth recording): (1) a corrupted
# TaxaTools.rdb lazy-load database (fixed by clean reinstall, unrelated to any code
# change); (2) TaxaFetch::fetch_gbif_occurrences() has no HTTP timeout on its underlying
# rgbif::occ_data() call, so a family-level query needing GBIF-internal pagination can
# stall indefinitely if one page request hangs -- confirmed reproducible three times
# against the same real keys/geometry; not yet fixed, flagged for a future session.
# devtools::test() 544/544 (TaxaAssign), devtools::check() 0/0/0. See TaxaAssign/CLAUDE.md's
# Session 152 note for the posterior_consensus() fix detail.
# Previous update, same day (Session 152, branch `main` -- live-testing the reentry plan
# from ecosystem_docs/REENTRY_PROMPT_session151_debug_template_and_12S_18S.md surfaced a
# real, substantial calibration problem in Session 151's own
# TaxaFlag::flag_contaminant() fix: shrinking by SAMPLE count (not read count) capped 97%
# (12S)/88% (18S) of real PtConception taxa at "moderate" risk regardless of how much
# actual read evidence supported them, since the median real taxon in both datasets is
# detected in exactly 1 field sample. Compared against the published contamination-
# detection literature (decontam, metabaR, microDecon, occupancy models) at the user's
# request before deciding on a fix -- two decontam-style hypothesis-test prototypes
# (presence/absence hypergeometric; depth-weighted binomial-exact) were built and tested
# against real data, then REJECTED: both are one-sided tests where zero control reads
# trivially gives p=1 regardless of total evidence, reverting almost exactly to the
# pre-151 problem. A third prototype (Beta-Binomial shrinkage toward a depth-based
# background rate) was also rejected: it doesn't transfer across studies with different
# control:field depth ratios (missed 18S's one known real contaminant entirely). The fix
# that worked: keep Session 151's depth-weighted-rate/0.5-shrink-target design (it was
# already correct) and change only what the shrinkage WEIGHT is measured in -- read count,
# not sample count (`prior_weight` default `2` -> `20`, now read-equivalent units).
# Validated at `prior_weight` in {20, 50, 100, 500}: 100% of known "high"-risk taxa
# recovered with zero false positives at every value, on both real datasets, while far
# more well-supported clean taxa correctly reach "low" (12S: 330 -> 3263; 18S: 2503 ->
# 4140, at the chosen default of 20). `devtools::test()` 185/185, `devtools::check()`
# clean. See TaxaFlag/CLAUDE.md's Session 152 note for the full investigative record.
# Previous update, same day (Session 151, final entry, branch `main` -- ecosystem
# soundness-review item 16 (TaxaFlag::flag_handler()'s edge_proximity_score) fixed,
# closing out the full 16-item H-priority walk-through (ecosystem_docs/
# STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md): **16 of 16 H-priority items now
# addressed.** "Addressed" does not mean every caveat is resolved -- most rows remain
# explicitly CONDITIONAL, several fixes are opt-in with no production caller wired in yet
# (this item and item 13 both), and a few items were deliberately left unchanged by
# design after the user confirmed the flagged behavior was intentional (items 2 and 4).
# Read the review doc's own per-item status before trusting any specific row as fully
# closed. Item 16 itself: new opt-in `station_metadata` param anchors
# `flag_handler()`'s group edges on real per-station deploy/retrieve timestamps instead
# of the detection data's own min/max -- the flaw meant the very first/last GENUINE
# wildlife detection at a station was always scored maximally suspect, purely as an
# artifact of how "edge" was defined. Mirrors this ecosystem's established "external
# attribute lookup table keyed by a sample/event identifier" pattern
# (`TaxaMatch::join_event_site_metadata()`, `BLANKS_MARCH`/`BLANKS_AUG`) rather than
# inventing a new one. A group missing from `station_metadata` falls back to the old
# data-derived min/max with an explicit `warning()`; new `edge_anchor_source` column
# records which was used per row. Fully additive/backward compatible -- all 36
# pre-existing tests pass unchanged. `devtools::test()` 181/181 (up from 169),
# `devtools::check()` clean. Still true, not solved: no production workflow supplies
# `station_metadata` yet (only the vignette's own updated example does), so this
# remains the lowest-priority item in practice, exactly as the original finding said.
# See TaxaFlag/CLAUDE.md's Session 151 note and
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 16 for the full record.
# Previous update, same day (Session 151, still further, branch `main` -- ecosystem
# soundness-review item 15 (TaxaFlag::flag_contaminant()'s contaminant_score) fixed:
# depth-weighted field/control rates + Empirical Bayes shrinkage of the final ratio toward
# 0.5 (new `prior_weight`, default 2) replace the old unweighted-mean-of-proportions
# formula and its hard 0.0/1.0 edge cases -- implementing the review's stated minimum bar
# rather than adopting the `decontam` package wholesale (its own methods need per-sample
# DNA concentration data, or reduce to presence/absence only, neither a clean fit here).
# `field_rate`/`control_rate` = `sum(taxon reads in group) / sum(total reads in that
# group)`, so a proportion from 500,000 reads now outweighs one from 50. A real design bug
# was found and fixed mid-implementation, not by review alone: an earlier version shrunk
# each rate toward the taxon's own pooled field+control rate, which let a taxon's own
# (usually much larger) field read volume leak into its control-side prior and
# systematically understated genuinely clean taxa's scores whenever field sequencing depth
# dominated control depth -- caught only by running the real test suite and seeing a
# clean, field-only mock taxon score "moderate" instead of "low." Fixed by shrinking the
# FINAL ratio toward a taxon-independent 0.5 by sample-count replication instead. Also
# fixed: roxygen no longer calls the score a "probability." `devtools::test()` 169/169,
# `check()` clean. **15 of 16 H-priority items now addressed; 1 remains (item 16,
# TaxaFlag::flag_handler, genuinely unfixed -- see that item's own row for why it's lower
# priority: no live caller exists in the monorepo besides one vignette example).** See
# TaxaFlag/CLAUDE.md's Session 151 note and
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 15 for the full record.
# Previous update, same day (Session 151, yet further, branch `main` -- ecosystem
# soundness-review item 14 (TaxaMatch::blast_sequences()'s score_window) fixed: default
# `score_range` widened from 2 to 8 percentage points, backed by a real leave-one-out
# check (new `diagnostics/score_window_leave_one_out.R`) rather than a guess. The review
# flagged that a tight 2-pt tolerance window can silently drop a query's true species
# from blast_sequences()'s output entirely -- before TaxaLikely/TaxaAssign ever see it,
# unrecoverable downstream -- whenever a confusable congener happens to score higher,
# and that this had only ever been field-tested on 5 easy queries with clear top hits.
# Ran the recommended check against three independent real 12S reference-vs-reference
# distance matrices (Sebastes, 54 species; Chromis, 26 species; a 6-genus PtConception
# set): pooled, 4 of 7 real congener-outscoring events (57%) exceeded the old 2-pt
# default and would have been silently dropped, with the worst observed gap at 7.1
# points (Chromis). New default (8) covers every gap actually observed with margin --
# `max_hits=20` (unchanged) still bounds candidate volume, and the wider window is what
# lets TaxaLikely's downstream bivariate-normal model (not this coarse pre-filter) do
# the actual species-vs-congener discrimination, directly closing this review's own
# cross-cutting pattern #3. Two real workflow scripts hardcoding the old value updated.
# `devtools::test()` 451/451, `check()` clean. **14 of 16 H-priority items now
# addressed; 2 remain (items 15-16, both TaxaFlag).** See TaxaMatch/CLAUDE.md's Session
# 151 note and ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 14.
# Previous update, same day (Session 151 continued yet again, branch `main` -- ecosystem
# soundness-review item 13 (TaxaLikely::build_sequence_matrix()'s
# pairwise_distance_to_match) fixed: new opt-in `barcode_term` param auto-resolves
# `min_seq_len`/`max_seq_len` via `TaxaTools::resolve_barcode_lengths()` instead of the
# generic `[100, 2000]` default (explicit lengths still override). This is the
# documented "Paralabrax footgun" (TaxaLikely/CLAUDE.md's Known Footguns) made
# ergonomic: a broad NCBI fetch can return sequences describing a genomically different
# stretch of the same gene that still pass a length filter, silently mixing two
# amplicon windows into what looks like one self-consistent H1/H2 training set.
# `diagnostics/sebastes_chromis_confirmation.R` (the script that found this) already
# hand-implemented the fix manually; that pattern is now built into the function
# itself. Purely additive -- no existing caller's behavior changes unless
# `barcode_term` is newly supplied. Wired into the one real workflow
# (`sequence_likelihood_workflow.R`) lacking an existing length safeguard;
# deliberately not forced into `TaxaID_Workflow_Template_TEST.R`, which already made
# and documented its own wider `max_len=1200L` judgment call for real longer
# submissions -- applying a generic marker-resolved range there would have silently
# excluded data that workflow's own team already decided to keep. `devtools::test()`
# 667/667 (up from 661), `devtools::check()` clean. **13 of 16 H-priority items now
# addressed; 3 remain (items 14-16: TaxaMatch::blast_sequences, TaxaFlag x2).** See
# TaxaLikely/CLAUDE.md's Session 151 note and
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 13 for the full record.
# Previous update, same day (Session 151 continued once more, branch `main` -- ecosystem
# soundness-review item 12 (TaxaLikely::apply_coverage_constraints()'s
# completeness_penalty_weight) fixed: `constraint_behavior` default changed `"zero"` ->
# `"relabel"`. The review flagged that the old default hard-zeroed the
# "unreferenced_species" hypothesis whenever a genus census said "complete" -- treating an
# NCBI taxonomy-tree query result as certain ground truth, when synonymy/unindexed recent
# species/missed renamings can make a genus look complete when it isn't, permanently
# discarding a genuinely novel detection's correct hypothesis with no way for downstream
# evidence to recover it. Turned out `TaxaAssign::run_bayesian_pipeline()` (the real
# production entry point) already defaulted to the non-destructive `"relabel"` mode -- only
# this lower-level function's own default was still unsafe, meaning direct callers (3
# vignettes, 1 demo workflow script, the superseded monolithic workflow) got the risky
# default even though the flagship pipeline had already moved past it. Changed to match;
# the one demo script whose comments specifically narrate/count zero-suppression now
# requests `constraint_behavior = "zero"` explicitly to preserve its teaching intent, rather
# than silently drifting. `devtools::test()` 661/661 (up from 658), `check()` clean. 12 of
# 16 H-priority items now addressed; 4 remain (items 13-16, TaxaLikely/TaxaMatch/TaxaFlag).
# See TaxaLikely/CLAUDE.md's Session 151 note and
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 12 for the full record.
# Previous update, same day (Session 151 continued yet further, branch `main` -- ecosystem
# soundness-review item 9 (TaxaLikely::train_likelihood_model()'s eb_bivariate_normal) closed
# out, docs-only, after empirical verification showed the review's shrinkage-weight claim
# doesn't hold against current code: `.prep_training_data()` already collapses each
# species' O(k^2) within-species pairs down to one row per SEQUENCE before the Empirical
# Bayes shrinkage N is computed (confirmed with a synthetic 5-sequence fixture: pair count
# 20 vs. the shrinkage weight's actual N of 5) -- the `N_Obs` column the review's finding
# pointed at is unused dead code, never read again after being computed. Docs fixed rather
# than code: `N_Obs`'s roxygen now says plainly what it is; `train_likelihood_model()`
# gained a `@section Marker validation scope` for the still-real half of the finding
# (Framing B validated for 12S/18S only, run `diagnostics/seq_matrix_score_distribution.R`
# before trusting another marker). Same "verify before fixing" discipline as items 2 and 6
# in this review. `devtools::test()` 658/658 unchanged, `check()` clean. 11 of 16
# H-priority items now addressed; 5 remain (items 12-16, all TaxaLikely/TaxaMatch/TaxaFlag).
# See TaxaLikely/CLAUDE.md's Session 151 note and
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 9 for the full record.
# Previous update, same day (Session 151, branch `main` -- TaxaLikely::train_likelihood_model()
# gains per-genus H2 delta shrinkage, prompted by a manuscript peer-review comment that the
# reference-gaps section's P(E|unreferenced) ~ P(E|referenced) approximation was asserted, not
# defended, and would fail exactly where taxonomists most need help (cryptic complexes, deep
# splits, mimicry/convergent signals). H2$delta (the logit shift used to model a missing
# congener's likelihood) was a single value pooled across every genus in the training set;
# a genus-specific estimate (new H2_Lookup slot, Empirical Bayes-shrunk toward the pooled
# value using a real congener pair when one exists in the reference database) now corrects
# the *magnitude* of that shift for cryptic-complex-like genera, while a documentation-only
# addition to TaxaLikely/inst/TaxaLikely_supplemental_methods.md states the load-bearing
# assumption plainly (related taxa assumed more similar in the evidence trait than unrelated
# taxa -- true by construction for DNA, much weaker for image/acoustic mimicry/convergence,
# where no statistical fix exists and direct reference-database expansion for the mimic
# itself is the only real remedy). Fully additive and backward compatible -- no signature
# changes; model_params objects trained before this session simply have no H2_Lookup slot
# and behave exactly as before. See TaxaLikely/CLAUDE.md's Session 151 note for the full
# implementation record.
# Previous update, 2026-07-10 (Session 149 continued once more, branch `main` -- new
# TaxaExpect::compute_adaptive_sampling_groups(), prompted by a follow-up design question
# after the sampling_group_col fix below: how do you choose a good detection-process
# grouping when a user doesn't have (or doesn't want to hand-build) domain knowledge for
# it? Answer: greedily merge taxa up a taxonomic rank hierarchy (default order -> class ->
# phylum) until each candidate group's mean per-site record count clears a minimum viable
# sample size, never merging across the ceiling rank (phylum) -- "stratum collapsing" from
# survey methodology, mirroring (bottom-up, on a sample-size criterion) the same recursive
# pattern TaxaAssign::join_priors()'s dark-diversity grouping already uses top-down (on
# singleton presence). A real bug (list[[NA]] returns NULL, breaking NA-taxonomy handling)
# was found and fixed via deliberate smoke-testing before formal tests were written.
# devtools::test() 423/423 (up from 401), check() clean. This is a standalone,
# user-optional tool -- not wired into the real 18S workflow, which still uses its
# original hand-built classification. See TaxaExpect/CLAUDE.md's Session 149 notes.
# Previous update, 2026-07-10 (Session 149 continued yet further, branch `main` -- sixth
# H-priority item: TaxaExpect::train_biodiversity_model()'s shared-effort assumption
# (n_total_at_site pooled across every taxon regardless of detection process) is now
# enforced, not just documented. prepare_model_dataframe() gains sampling_group_col
# (group-aware n_total_at_site, split-and-recombine internally to avoid cross-group
# zero-fill contamination); train_biodiversity_model() refuses multi-group data; new
# train_biodiversity_model_by_group() orchestrates per-group fitting end to end. Before
# implementing, verified via a dedicated search (prompted by the user's recollection of
# past discussion) that this had never actually been fixed anywhere -- only documented,
# Session 108 -- including in the one real production workflow (PtConception 18S, 11
# sampling groups spanning phytoplankton/fish/birds/plants/parasites/etc.) that has exactly
# this scenario; that workflow (outside this monorepo, not under git) was then rewritten to
# use the new mechanism, looping model fitting per group with a tryCatch() guard for sparse
# groups, not run live this session. devtools::test() 401/401 (up from 383), check() clean.
# See TaxaExpect/CLAUDE.md's Session 149 notes for the full record.
# Previous update, 2026-07-10 (Session 149 continued, branch `main` -- fifth H-priority item from
# the statistical soundness review: TaxaAssign::update_prior_from_consensus()'s fixed
# presence_multiplier (a flat x5 boost regardless of confirmation count/confidence) replaced by
# a confirmation-quantile design, reached via an extended design discussion where the user
# proposed and pressure-tested several alternatives (max-confidence donor -> noisy-OR
# combination -> high-quantile combination) before settling on: the confirmation_quantile-th
# quantile (default 0.9) of confirming donors' consensus_posterior substitutes for a confirmed
# species' prior_mean (never lowering it) only when it clears min_confirmation_confidence
# (default 0.8, disableable via 0). Key finding along the way: a plain maximum or a
# probabilistic-OR combination across donors can both be fooled by many correlated (not
# independent) confirmations from a classifier that structurally cannot separate two similar
# species -- renormalization does NOT correct this once a third, unrelated candidate is
# present (confirmed numerically). A quantile is the more defensible choice specifically
# because it converges to a stable population value as the donor pool grows (unlike a sample
# maximum, which drifts toward the degenerate ceiling of 1.0 regardless of whether the
# evidence is real). Also fixed a latent inconsistency found along the way: prior_alpha/
# prior_beta were never rescaled to match a boosted prior_mean, so compute_posterior()'s Monte
# Carlo path could sample from a stale Beta shape -- now recomputed preserving the original
# concentration. Explicitly deferred (not solved): a quantile still can't tell "confidence
# earned by strong evidence" from "confidence attained despite thin/low-quality input" (e.g. a
# short DNA read producing a spuriously perfect match) -- flagged as its own future design
# thread (a quality covariate on match scores), prompted by the user's own camera-trap and
# short-sequence-read examples and a shared reference (Silva-Rodriguez et al. 2025, J. Appl.
# Ecol., a camera-trap QC-protocol paper -- a different layer, dataset-level audit rather than
# a per-detection statistical model, but evidence the underlying problem is recognized
# elsewhere). Signature change (breaking): presence_multiplier removed, replaced by
# confirmation_quantile/min_confirmation_confidence, propagated through
# run_bayesian_pipeline()/run_llm_pipeline()/generate_report()'s methods text/both inst/
# workflow scripts/the taxonomic-assignment vignette -- all real call sites updated.
# devtools::test() 537/537 (0 failures), devtools::check() 0/0/0. See TaxaAssign/CLAUDE.md's
# Session 149 notes for the full record, including the full sequence of rejected alternatives
# and why each failed. 12 of the original 16 H-priority items remain.
# Previous update, 2026-07-10 (Session 150, branch `main` -- package-placement fix prompted by the
# user's parallel manuscript-driven review of the ecosystem's 4 conceptual pipeline steps
# (calibrate likelihoods -> generate priors -> model missing likelihoods -> calculate
# posteriors): `expand_unreferenced_hypotheses()` moved TaxaAssign -> TaxaLikely. It models
# likelihoods for named unreferenced species (the "model missing likelihoods" step) by copying/
# medianing values from referenced relatives -- conceptually a likelihood-modeling function, not
# a posterior-computation one, so it belongs next to `unreferenced_candidates()` (candidate
# generation) rather than inside TaxaAssign. It still runs after both TaxaLikely's own output
# and a TaxaExpect-derived unreferenced-species list are available, and before
# `TaxaAssign::compute_posterior()` -- confirmed this is a workflow-ordering requirement only,
# not a package-dependency one, since the function only ever consumes plain data frames and
# never calls into TaxaExpect or TaxaAssign itself. `TaxaAssign::expand_unreferenced_hypotheses()`
# kept as a thin `.Deprecated()` forwarding wrapper (matching Session 136's
# fetch_reference_sequences() -> fetch_ncbi_reference_sequences() pattern) -- zero-risk for any
# workflow script not yet updated to the new namespaced call. All real call sites found via
# ecosystem-wide grep and updated (`run_bayesian_pipeline()`, the bayesian workflow tutorial, both
# vignette code chunks, the one live call in TaxaAssign's own integration test); the dedicated
# unit test file moved to TaxaLikely, replaced in TaxaAssign by one test confirming the wrapper
# warns and forwards identically. No TaxaWizard metadata/snippets referenced this function
# (checked, zero hits). Found and flagged (not fixed, pre-existing, unrelated) a stale 3-argument
# call in `TaxaAssign/vignettes/taxaid-ecosystem.Rmd` that doesn't match the real 2-argument
# signature -- likely the same kind of doc/metadata drift already known from the TaxaWizard
# metadata case ([[project_taxawizard_metadata_drift]]). `devtools::test()`: TaxaLikely 643/643
# (0 failures, up from 609; 15 pre-existing unrelated warnings, 1 pre-existing skip), TaxaAssign
# 522/522 (0 failures; count differs from Session 149's 544 because ~17 tests moved to TaxaLikely
# and were replaced by 1 forwarding-wrapper test, not because coverage was lost).
# `devtools::check()`: both packages 0 errors/0 warnings/0 notes.
# Previous update, 2026-07-10 (Session 149 continued, branch `main` -- ecosystem-wide statistical
# soundness review (ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md; see
# ecosystem_docs/STATISTICAL_COMPONENT_CATALOG.md for the prior cataloging-only pass), judging
# all 59 cataloged statistical components, then walking the 16 High-priority rows one at a time
# with the user. Four done so far: (1) TaxaAssign::compute_posterior()'s Monte Carlo path --
# the live winner-selection path, since posterior_consensus() defaults to reading the MC-derived
# posterior_mean -- fixed: exact truncated-normal likelihood sampling (was rnorm()+clamp-to-0,
# manufacturing a spurious point mass at 0) and the J-shaped-Beta override widened from
# prior_alpha < 1 to <= 1. (2) TaxaAssign::score_consensus()'s fixed percent-identity thresholds
# were NOT a bug -- the user clarified this function deliberately reproduces a conventional
# fixed-threshold pipeline (GITA/Jonah Ventures-style) for benchmarking against TaxaID's own
# Bayesian pathway, so its known inability to discriminate species-from-congener is the point,
# not a defect; fixed with a documentation-only `@section Purpose` clarifying this so a future
# reader doesn't make the same mistake the review did. (3) The domestic/synanthropic-species
# occurrence-floor artifact ([[project_taxaflag_domestic_species_floor_note]]): resolved as a
# split fix per the user's design -- priors get a documentation note only (recommending
# occurrence-data augmentation, in TaxaExpect::generate_undetected_diversity() +
# TaxaAssign::join_priors()), and TaxaFlag::add_posthoc_assessment() gains opt-in
# `domestic_taxa`/`domestic_prior_source` params that re-label a strong-likelihood +
# database-driven-low-tier domestic species call as `"domestic_prior_caveat"`. All three fixes
# behavioral/docs-only where applicable, fully backward compatible, every touched package's
# devtools::test()/check() re-verified clean. (4) TaxaAssign::join_priors()'s coarse-rank
# expansion (species candidates manufactured from a family-level ID, all sharing one inherited
# likelihood so the "winner" is decided by occurrence prior alone) was confirmed by the user,
# via a concrete example, to be intended behavior -- fixed by adding
# posterior_consensus()'s new winner_hypothesis_type/winner_rank_expanded output columns so a
# downstream consumer can tell a prior-only-resolved species call apart from a genuinely
# evidence-resolved one, without changing the underlying mechanism. See TaxaAssign/CLAUDE.md's,
# TaxaExpect/CLAUDE.md's, and TaxaFlag/CLAUDE.md's own Session 149 notes for the full
# per-package record. 12 H-priority items remain, being worked through one at a time with the
# user.
# Session 148, branch `main` -- full TaxaFetch code + domain
# review against inst/Code and Domain Review 2.Rmd (findings + fixes recorded in
# taxafetch_review.Rmd at the TaxaID root). Two real, fixed issues at the deep-review level:
# an SSRF gap in the DataONE pipeline (data_url read verbatim from third-party EML metadata,
# used as a full request URL with no host restriction -- fixed via a
# pasta.lternet.edu/pasta.edirepository.org allowlist, verified live against a real PASTA
# record showing legitimate vs. arbitrary-external-host <online><url> entries side by side)
# and a homonym-misresolution gap in TaxaFetch::get_keys_from_context()'s HIGHERRANK-recovery
# fallback (name_lookup() queried with no kingdom context, undermining the function's own
# stated purpose -- fixed by narrowing lookup hits to the row's own kingdom before voting,
# verified live against real GBIF *Alaria* data). Also fixed: biotime_fetch.R conflating
# unparseable ABUNDANCE/BIOMAS with confirmed occurrenceStatus = "absent" (now NA);
# filter_gbif_quality()'s eDNA-exclusion pattern over-broad ("bulk sample"/"water sample"
# alone); a zip-slip defense-in-depth check; two doc-only clarifications (make_bbox_wkt()'s
# latitude-dependent km caveat, get_gbif_occurrences()'s rank_filter subspecies-exclusion
# behavior). This session's security/domain passes went deeper than Session 131's original
# pre-review cleanup (which had found "no high-confidence vulnerabilities") specifically by
# live-testing against real external data instead of static review alone -- a corroboration
# of the ecosystem's own repeated lesson (see the pre-review-checklist memory) that live data
# surfaces real bugs static passes miss. devtools::test(): 459/459 (up from 434), 0 failures.
# devtools::check(): 0 errors, 0 warnings, 0 notes. See TaxaFetch/CLAUDE.md's Session 148
# note for the full record.
# Session 147, branch `main` -- fifth parameter-audit punch-list
# family (score floors). New diagnostics/score_floor_roc_sweep.R uses real classification
# ground truth (every pair in the real 12S seq_matrix reference data has known species/genus/
# family identity) to show raw percent-identity score alone cannot discriminate a species from
# its closest congener at almost any real-world threshold -- confirming and sharpening the
# ecosystem's own "Framing B verdict" memory at the specific parameter level. Surfaced a real,
# higher-stakes gap along the way: TaxaAssign::score_consensus()'s rank_thresholds defaulted to
# NULL, so a caller with no explicit override got zero score-based species-vs-congener
# protection, silently. Fixed: rank_thresholds now defaults to the conventional GITA/Jonah
# Ventures thresholds, auto-rescaled by /100 if the score column looks like a 0-1 proportion
# scale (matching TaxaLikely's existing scale-detection convention). Verified against every
# real call site and test before running them; devtools::test() 539/539 unchanged,
# devtools::check() clean. See TaxaAssign/CLAUDE.md's Session 147 note for the full record.
# Session 146, branch `main` -- fixed a real, silent LLM-response-
# truncation risk in TaxaAssign::assign_taxa_llm() that Session 145's sensitivity work surfaced:
# 4/5 real 30-taxon batches truncated at call_api()'s default max_tokens=3000, silently falling
# back to uniform priors with only a warning. .parse_taxa_response() now detects the truncation
# signature specifically and gives an actionable warning; taxa_per_call's default lowered
# 30->15 in both assign_taxa_llm() and run_llm_pipeline() (which forwards it), corroborated by
# TaxaFlag::review_assignments() having independently made the identical 30->15 fix for the same
# failure mode in an earlier session. suggest_unreferenced_species() still defaults
# taxa_per_call=30L, deliberately not changed (different, simpler response shape; risk not
# confirmed there). devtools::check() clean, 539 tests unchanged. See TaxaAssign/CLAUDE.md's
# Session 146 note for the full record.
# Session 145, branch `main` -- empirical sensitivity check for the
# fourth parameter-audit punch-list family: TaxaAssign::assign_taxa_llm()'s score_sharpness,
# unknown_lik_weight, prior_phi, absent_detection_prob. Small refactor first (new internal
# .merge_llm_priors() helper, behavior-preserving, 539 tests unchanged) to enable a cheap sweep
# against one real LLM response (499 real PtConception 12S observations, 5 real Anthropic API
# calls -- no usable real assign_taxa_llm() checkpoint existed anywhere beforehand). Finding:
# these four parameters mostly shape CONFIDENCE (consensus_posterior), not WHICH taxon wins
# (resolution rate was flat within ~1.5 points across every grid). unknown_lik_weight has the
# largest real effect (mean winning posterior 0.997->0.911 across a plausible range);
# score_sharpness had almost none; prior_phi's tiered default matched a flat scalar almost
# exactly (a real, still-open question about whether the tiering earns its keep);
# absent_detection_prob (tested via a disclosed synthetic overlay, since no real workflow here
# uses known_absent) showed no aggregate effect but is the weakest/most diluted result. Also
# surfaced two real, general gaps along the way (not fixed, flagged for later): TaxaTools's LLM
# provider auto-detection doesn't activate in a plain Rscript session even with
# library(TaxaTools) loaded; call_api()'s max_tokens=3000 default truncated 4/5 real 30-taxon
# LLM responses at the documented taxa_per_call=30 batch size. See TaxaAssign/CLAUDE.md's
# Session 145 note for the full record.
# Session 144, branch `main` -- empirical sensitivity check for
# TaxaAssign::posterior_consensus()'s min_posterior/cumulative_threshold defaults (0.05/0.90)
# against a real 3,000-observation PtConception 12S posterior_df. Finding: min_posterior does
# real, roughly linear work (+8.2 resolution-rate points sweeping 0->0.20); cumulative_threshold
# does comparatively little independent work once a reasonable min_posterior floor exists
# (-3.3 points sweeping 0.70->0.99, non-monotonically). The two interact sharply only in the
# unrealistic min_posterior=0 + cumulative_threshold=0.99 corner. Measures resolution RATE, not
# ACCURACY -- no ground-truth-validated observations were available to check correctness. New
# reusable diagnostics/posterior_threshold_sweep.R. See TaxaAssign/CLAUDE.md's Session 144 note
# for the full record, including why the sweep was subsampled to 3,000 of 13,483 real
# observations (the full sweep was twice interrupted at 15-17 min in this session's background-
# task setup).
# Session 143, branch `main` -- TaxaAssign::join_priors()/
# posterior_consensus()/run_bayesian_pipeline()/run_llm_pipeline() no longer have a silent
# default for backbone_id anywhere it's actually used to reconcile taxonomy against an
# external backbone -- join_priors() gains a new required backbone_id param (no default,
# errors if omitted), replacing a hardcoded backbone_id = 4L; posterior_consensus()'s default
# changed from 11L to NULL (errors only when lookup_missing_taxonomy = TRUE); the two pipeline
# wrappers lost their 4L default entirely since both forward it unconditionally downstream.
# Prompted by a parameter audit flagging the 4L (run_bayesian_pipeline) vs 11L
# (posterior_consensus) default mismatch as a possible correctness bug -- traced first and
# confirmed it was NOT live (the value is always explicitly forwarded through
# .run_consensus_and_report(), so posterior_consensus()'s own default was never actually
# reached via that path), but the user's design call was that the correct backbone depends on
# which backbone the caller's own input data used, which varies by project, so no such
# function should have a silent default. TaxaTools::fill_higher_ranks()/
# escalate_taxonomic_rank() deliberately kept their existing 4L/11L primary/fallback pair
# (a resolution strategy, not an input-backbone assumption). All ~15 real call sites across
# vignettes, workflow scripts, and TaxaWizard snippets + metadata updated; devtools::check()
# clean, 539 tests passing. See TaxaAssign/CLAUDE.md's Session 143 note for the full record,
# including a pre-existing, unrelated TaxaWizard metadata bug found and flagged (not fixed) 
# along the way.
# Session 142, branch `main` -- TaxaLikely::trim_to_amplicon() now
# supports the real eDNA/metabarcoding COI mini-barcode (Leray et al. 2013 mlCOIintF paired
# with Meyer 2003's dgHCO2198, registry key `coi-leray`), resolving the inosine blocker Session
# 141 explicitly left unimplemented (Geller et al. 2013's jgHCO2198 uses inosine, which
# Biostrings::DNAString cannot represent -- Meyer's older degenerate reverse primer binds the
# same site without it, a real published pairing, not an invented workaround). Prompted by the
# user asking to learn about the mini-barcode's known discriminatory-power limitations before
# deciding whether the implementation effort was worth it; empirically confirmed 365bp on real
# Drosophila melanogaster mtDNA, reconciling exactly to the commonly-cited "313bp Leray
# fragment" once both primers are excluded. Bare "COI" is now deliberately ambiguous between
# coi-folmer and coi-leray. See TaxaTools/CLAUDE.md's and TaxaLikely/CLAUDE.md's own Session
# 142 notes for the full literature review and verification record.
# Session 141, branch `main` -- TaxaLikely::trim_to_amplicon()
# (Session 140) now covers every mitochondrial/chloroplast marker in
# TaxaTools::barcode_length_defaults (16S, COI, cytb, rbcL, matK, trnL), not just MiFish-12S.
# Prompted by the user asking directly whether primer-trimming was worth it for 12S at all
# (yes -- safe fallback, real production impact already observed, low false-positive risk)
# and to work through the remaining mito/chloroplast markers (nuclear genes -- 18S, ITS,
# ITS2 -- explicitly excluded per the user's own instruction, no canonical primer pair
# exists for any of them). Each new primer pair verified two ways: cross-checked against
# 2-3 independent literature sources, AND empirically tested with Biostrings::matchPattern()
# against a real GenBank mitogenome/chloroplast genome fetched live via NCBI eutils -- this
# caught two real errors a literature check alone would have missed (a wrong cytb amplicon
# length two secondary sources agreed on but real data contradicted; a genuine
# forward/reverse primer mislabeling in an otherwise-authoritative matK primer table,
# resolved by testing both orientations against real chloroplast DNA). No code changes
# needed in TaxaLikely itself -- trim_to_amplicon() was already generic over any
# barcode_term with a registered primer pair. See TaxaTools/CLAUDE.md's and
# TaxaLikely/CLAUDE.md's own Session 141 notes for the full record.
# Session 140, branch `main` -- implements
# ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md's general (taxon-centric)
# fix: new TaxaFetch::fetch_occurrences_by_taxon() unions each candidate taxon's own search
# geometry and combines taxa sharing identical geometry into one GBIF call, replacing
# `TaxaID_Workflow_Template_TEST.R` Section 3's old per-observation/site fetch loop with a
# two-pass design (define all groups' geometry first, then fetch once per taxon key across
# the whole scope). `TaxaFetch::stack_occurrences()` also gained a `gbifID` dedup step
# (defense-in-depth; confirmed no dedup existed anywhere in the GBIF occurrence pipeline
# before adding it, and that `TaxaMatch::standardize_match_data()` is an unrelated pipeline
# -- classifier match records, not occurrence data -- so the gap was real, not stale). See
# TaxaFetch/CLAUDE.md's Session 140 note for the full record, including the isolated-logic-
# test verification against Session 139's own real bundled checkpoint data and the user's own
# live RStudio confirmation the same session (4 taxon keys correctly collapsed to 2 GBIF
# queries on real data).
# Session 140 continued (2026-07-06): implements
# ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md -- new
# TaxaLikely::trim_to_amplicon() locates primer-binding sites (verified MiFish-U/E only,
# Miya et al. 2015) in over-length reference sequences (e.g. full mitogenomes) via
# Biostrings in-silico PCR and extracts just the amplicon, instead of
# build_sequence_matrix()'s length filter discarding the whole sequence outright -- the
# deeper fix for the exact "No H1 pairs found" mitogenome-contamination problem the Session
# 139 note below describes fixing with length-exclusion only. Package placement (TaxaLikely,
# not TaxaFetch/TaxaMatch) argued through explicitly with the user before starting; new
# TaxaTools::barcode_primer_defaults registry deliberately populated with only MiFish-U/E
# (the sole marker with real production use in this ecosystem) rather than attempting all
# `barcode_length_defaults` markers -- 18S explicitly excluded since no single canonical
# primer pair exists to verify. See TaxaLikely/CLAUDE.md's and TaxaTools/CLAUDE.md's own
# Session 140 notes for the full record.
# Session 139, branch `main` — Phase 6 live-testing of
# `TaxaID_Workflow_Template_TEST.R` (Session 138's reentry plan) surfaced and fixed three
# more real bugs beyond Session 138's own scope. (1) Section 3/5 conflated "multiple
# different observations sharing a bounding box" with "one observation detected at
# multiple sites" -- branching now keys on distinct observation_id count, not row count;
# Section 5 generates priors per real site instead of an averaged centroid. (2) Section
# 6a built its reference sequence database by reusing whatever accessions BLAST itself
# hit, with no length control -- GenBank mixes short barcode submissions with full
# mitogenomes for the same species, and build_sequence_matrix()'s length filter silently
# dropped every within-species pair in this template's real bundled data, hard-failing
# model training ("No H1 pairs found"). (3) The same raw-BLAST-reuse approach also pulled
# in a flagged lab contaminant (Salmo salar) that had already been excluded from
# decontaminated_table -- a genuine disconnect between the analysis candidate set and the
# reference-fetch candidate set. Fixed (2) and (3) together: Section 6a now calls
# `TaxaLikely::fetch_ncbi_reference_sequences()`, deriving candidate taxa from the
# already-decontaminated `match_obj` and filtering reference sequences by barcode-
# appropriate length before download (mitogenomes never fetched at all) -- verified live
# against real NCBI data, training now succeeds (12 within-species pairs, up from 0). A
# deeper, more general version of the mitogenome problem (in-silico PCR to extract the
# amplicon region from an over-length sequence instead of discarding it outright) was
# deliberately scoped out as its own design task, not implemented --- see
# `ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md`. A related,
# separate GBIF-fetch-efficiency discussion (taxon-centric query grouping to avoid
# redundant/overlapping GBIF searches) is captured in
# `ecosystem_docs/REENTRY_PROMPT_session139_gbif_fetch_efficiency.md` -- also not yet
# implemented, scope not yet chosen with the user.
# Session 139 continued (2026-07-06): continued live testing surfaced two more real issues
# and one usability redesign, all found by actually using the pipeline, not reading code.
# (a) `TaxaMatch::build_site_table()`'s default `spatial_group_id` (previously the row's own
# `observation_id`) redesigned to group by exact `(lat, lon)` match instead -- a grid-
# snapping alternative was tried first and rejected after it collapsed four genuinely
# distinct real observations into one default cluster on this template's own bundled data.
# New `is_default_group` marker column replaces a fragile string-comparison heuristic;
# `.next_spatial_group_number()` keeps default-assigned and interactively-drawn group labels
# from colliding. (b) The spatial-grouping applet itself redesigned for clarity:
# `TaxaTools::define_search_polygon()` gained customizable `title`/`done_label`/
# `cancel_label` params (backward compatible) so `group_observations_by_bbox()` can say
# "Group These Points"/"No More Groups" instead of generic "Done"/"Cancel", show per-group
# progress in the title, and open one zoom step further out so the starting box is actually
# visible -- prompted by the user reflexively clicking "Done" on the unshrunk starting
# square and merging far more observations into one group than intended. (c) A real,
# previously-latent bug fixed along the way: `TaxaID_Workflow_Template_TEST.R`'s Section 3
# never checked whether a cancelled search-area gadget returned `NULL` before passing it to
# `TaxaFetch::get_gbif_occurrences()`, crashing several calls downstream with a confusing
# error instead of a clear one. See `TaxaMatch/CLAUDE.md`'s and `TaxaTools/CLAUDE.md`'s own
# Session 139 notes for full detail; the GBIF-fetch-efficiency reentry prompt above also
# gained a note on why this session's applet work makes a "define all boxes, then fetch"
# two-pass split a real prerequisite for that document's taxon-centric design, still not
# implemented.
# Session 138 (2026-07-05), branch `single-observation-pipeline` — Phase 5 of
# the observation-pipeline-wiring plan: multi-site posterior combination.
# `TaxaAssign::join_priors()`'s final dedup was silently collapsing a genuine multi-site
# observation (the same detection recovered at more than one real site, surfaced by Session
# 137's Phase 4 DNA/BLAST wiring) to one row per candidate per its own best site, discarding
# the site it was actually detected at — fixed by making that dedup grid_id/main_habitat-
# aware. New `TaxaAssign::combine_multisite_priors()` recombines the resulting per-site rows
# via precision-weighted combination in logit space (empirically shown to correctly discount
# a low-confidence/sparse-data site, unlike either of the two options the prior session's
# reentry prompt had proposed — see `TaxaAssign/CLAUDE.md`'s Session 138 note for the full
# empirical comparison). Wired into `TaxaID_Workflow_Template_TEST.R` Section 7.
# Session 137 continued yet further (same day, earlier) — Phase 4 (DNA/BLAST half) of the observation-pipeline-wiring plan:
# `TaxaMatch::join_event_site_metadata()` added, producing a `site_df` for
# `build_site_table()` from an event-level detections table joined against a
# user-maintained site-metadata table — generalizes the ecosystem's existing
# blank-identification lookup-table pattern (`BLANKS_MARCH`/`BLANKS_AUG`,
# `control_samples`) to carry site coordinates. Data-type-agnostic by design (DNA/BLAST
# and acoustic reduce to the same join), but only the DNA/BLAST half is wired live this
# session — `TaxaID_Workflow_Template_TEST.R`'s Section 2.5 now uses the bundled
# `Reads_Table`'s real `sample_1`/`sample_2` columns as genuinely different sites,
# surfacing and fixing a real latent bug in Section 3's multi-member-vs-singleton
# branching (`build_site_table()` hardcodes `spatial_group_N = 1L` per row regardless of
# duplicates; branching now uses `nrow(group_sites)` instead of the stored column). The
# acoustic half stays deferred — no real multi-site BirdNET deployment data exists yet to
# wire against honestly; the user described two plausible real shapes (fixed BirdWeather-
# style recorders vs. multi-site field-trip submissions) but was explicitly unsure which
# applies, so `score_acoustic_workflow.R` only gets a documentation pointer. See
# `TaxaMatch/CLAUDE.md`'s Session 137-continued note for the full record.
# Session 137 continued further (same day, earlier) — Phase 3 of the observation-
# pipeline-wiring plan:
# `TaxaMatch/inst/workflows/score_image_workflow.R` gains an `OVERRIDE_SITE_LATLNG` flag
# (default TRUE, matching this script's bundled EXIF-less trail-camera photos) so the
# previously-unconditional site-coordinate override is now explicit rather than silently
# stomping on real per-photo EXIF GPS for other users' photo sets, plus a new
# `build_site_table()` call producing a checkpointed `image_site_table`. Live-verified
# both flag settings against the real bundled 52-photo set (82%/60% top-1 accuracy,
# matching prior documented results — no regression). See `TaxaMatch/CLAUDE.md`'s Session
# 137 note for detail.
# Session 137 continued (same day, earlier) — Phase 2 of the observation-pipeline-wiring
# plan: `inst/TaxaID_Workflow_Template_TEST.R`
# (the master 8-section workflow template) now wires spatial grouping end to end. New
# Section 2.5 builds a `site_table` (`TaxaMatch::build_site_table()` +
# `group_observations_by_bbox()`); Section 3's occurrence fetch branches per
# `spatial_group_id` (pooled bbox fetch for multi-member groups, per-observation
# taxonomic-escalation fetch via `TaxaTools::escalate_taxonomic_rank()` for singletons);
# Section 5 generates `TaxaExpect` priors once per group at that group's own resolved
# grid cell instead of one global `SITE_GRID_ID`; Section 7 joins each observation
# against its own group's priors (`join_priors()`'s existing multi-site data-frame path)
# and adds a new `TaxaAssign::update_prior_from_consensus(spatial_group_map = site_table)`
# call (previously not invoked anywhere in this template). The DNA/BLAST pathway still
# has no real per-observation site metadata (Phase 4, deferred) — every observation is
# placed at one hardcoded `STUDY_LAT`/`STUDY_LON` as a documented placeholder, so real
# multi-site behavior isn't exercised by this template's bundled test data yet, only the
# wiring itself. See `TaxaID/CLAUDE.md`'s own Session 137-continued note below for the
# verification approach and what's still deferred (Phases 4-7).
# Session 137 (earlier in the same day) — TaxaTools::escalate_taxonomic_rank() added: the
# escalation-ladder function (broaden genus -> family -> order when a singleton's own
# genus has no reference/occurrence data), Phase 1 of the same plan. Live-verified against
# real NCBI data for the PtConception 12S cases and the bobcat-photo case. See
# TaxaTools/CLAUDE.md's Session 137 note for detail.
# Session 134b, branch `single-observation-pipeline` — after
# reviewing Session 134's automatic-spatial-grouping implementation, the user raised package-
# placement questions before committing (see
# ecosystem_docs/REENTRY_PROMPT_session134b_grouping_implemented.md). Resolved: the shared
# interactive polygon gadget only needed a small additive generalization (color the points
# overlay by group; reopen a previous polygon for reshaping) to serve both TaxaFetch's
# search-area purpose and TaxaMatch's spatial-group purpose, so `define_search_polygon()`
# moved TaxaFetch -> TaxaTools and `group_observations_by_bbox()` moved TaxaFetch -> TaxaMatch
# (it operates on TaxaMatch::build_site_table()'s output; a spatial-grouping concern, not a
# fetch concern). `group_observations_by_bbox()` also substantially reworked: `spatial_group_id`
# now defaults to the observation's own `observation_id` (set by `build_site_table()`, not
# invented by the grouping function), last-drawn-wins overlap resolution with a warning, and a
# new end-of-loop review/edit/delete step. New `TaxaMatch::assign_spatial_group()` manual
# helper for metadata-known groupings. All three packages (TaxaTools, TaxaFetch, TaxaMatch)
# plus TaxaAssign (doc-only cross-reference fix) `devtools::check()`-clean. Still open for a
# follow-up session: the search-area-vs-spatial-group reconciliation, fetch-scope branching
# (the escalation-ladder engineering work), the Reads-table relocation, and the TaxaAssign
# (observation_id, site) schema question -- see the reentry prompt and each touched package's
# Session 134b note for the full record. Session 133 — acoustic tau/score_sharpness re-calibrated on a real, deliberately-designed 24-species/8-cluster/2487-detection-window dataset (up from a 3-species/42-window pilot); Session 128/129's "acoustic wants tau≈1, opposite of image" conclusion did NOT hold — pooled acoustic optimum is tau≈0, same as image, though per-cluster results are genuinely heterogeneous and one global tau may not be appropriate. No current real-data evidence supports tau>0 as a default for either data type. See TaxaLikely/CLAUDE.md's Session 133 note and ecosystem_docs/REENTRY_PROMPT_acoustic_tau_calibration_expanded.md for the full record. Session 132 — TaxaMatch non-portable camera-trap filenames fixed. Session 129 — real assign_scores() score-scale bug found and fixed; TaxaExpect crash fixes for sparse real data; new TaxaFetch::get_gbif_occurrences() unified wrapper; first real TaxaAssign posterior run for the camera-trap species set. See ecosystem_docs/REENTRY_PROMPT_session129_calibration_resolved.md for that record.)

---

## ⚙️ Claude Code Behavior
- After completing any task, play a completion sound: `afplay /System/Library/Sounds/Glass.aiff`
- Always ask before making changes to multiple *existing* files at once, or before any deletions
- Run `devtools::check()` after any substantive edits to a package

---

## 📋 Pending Documentation Tasks
- **pkgdown sites**: No `_pkgdown.yml` exists for any package. Per the MEE TaxaID
  manuscript plan (manuscript-context.md in Cowork), the paper will follow the
  aniMotum precedent — a short "Application"-style paper that points readers to
  package vignettes/docs for depth rather than including a full tutorial. This
  requires each package (at least TaxaTools, TaxaFetch, TaxaHabitat, TaxaMatch,
  TaxaLikely, TaxaExpect, TaxaAssign, TaxaFlag) to have a working pkgdown site
  before submission. Flagged June 2026 during manuscript planning.

---

## ⚠️ Reminder for Claude
**At the start of any session involving function changes, new functions, or name changes:
remind the user to update CLAUDE.md — especially the Function Inventory — before ending
the session. Also add significant renames to `ecosystem_docs/NAME_CHANGE_HISTORY.md`.**

---

## ⚠️ File Loss Incident — 6 March 2026
Several TaxaExpect source files were lost during a USGS Git repository migration on
6 March 2026. Affected files were subsequently recreated from scratch. If any function
behaviour seems inconsistent with documentation, the recreated version is authoritative.
Functions confirmed recreated after the incident: `make_bbox_wkt`, `get_keys_from_context`,
`fetch_gbif_occurrences`, `create_sites_from_grid`, `optimize_grid_size`,
`filter_gbif_quality`, `assign_habitat_biological`.

---

## Developer Environment

| Item | Value |
|---|---|
| OS | macOS |
| R version | R version 4.5.2 (2025-10-31) |
| Primary IDE | RStudio |
| Git remotes | `origin` → https://github.com/kdlafferty/TaxaID (public monorepo, Session 80) |
| R library | `~/Library/R/4.0/library` — set via `R_LIBS_USER` in `~/.Renviron`, **not** `~/.Rprofile` (corrected Session 134b; see that session's TaxaTools/CLAUDE.md note). This project has its own `TaxaID.Rproj` + project-level `.Rprofile`, which RStudio sources *instead of* `~/.Rprofile` when the project is open — so `~/.Rprofile`'s own `.libPaths()` call (pointing at a directory that doesn't even exist, `~/Library/R/4.5-arm64/library`) never actually runs in this project. Confirmed directly: a real `R` session started **from the project root** resolves `.libPaths()[1]` to `~/Library/R/4.0/library`, and that's where `find.package()` finds every TaxaID package. **CORRECTED Session 159** (the earlier claim below was wrong and cost real install time): a bare `Rscript -e '...'` invoked from an ARBITRARY directory (e.g. `cd`'d into a package's own subfolder, like `TaxaLikely/` or `TaxaMatch/`) does **NOT** reliably pick up `R_LIBS_USER` into `.libPaths()` on its own — confirmed directly, twice, the hard way: `devtools::install()` run this way silently installed to the **system default library** (`/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/library`, i.e. `.Library`) instead, even though `Sys.getenv("R_LIBS_USER")` correctly returned the right (unexpanded, `~`-relative) string the whole time. Root cause: it's specifically the **project-level `.Rprofile`** (sourced only when R starts with the TaxaID project as its working directory, or via the RStudio Project file) that wires `R_LIBS_USER` into `.libPaths()` -- not something R itself does automatically at every startup regardless of context. A plain `Rscript` run from inside a package subdirectory has no project context and skips that `.Rprofile` entirely. **Fix, confirmed working**: before calling `devtools::install()`/`devtools::load_all()` from a bare `Rscript` outside the project root, explicitly run `.libPaths(c(path.expand(Sys.getenv("R_LIBS_USER")), .libPaths()))` first (or `cd` to the TaxaID project root before invoking `Rscript`). Always verify after any Rscript-driven install with `dirname(find.package("<pkg>"))` — don't assume it landed in the right place. The system default library (`.Library`) is a same-R-version fallback that can silently accept an install without erroring, which is exactly what makes this mistake invisible until something checks `find.package()` directly. |
| ANTHROPIC_API_KEY | Set in `~/.Renviron` |
| GEMINI_API_KEY | Set in `~/.Renviron` — free tier; get key at aistudio.google.com/apikey |
| OPENAI_API_KEY | Set in `~/.Renviron` — paid account required |
| OPENALEX_API_KEY | Set in `~/.Renviron` — required since February 2026; free at openalex.org/settings/api |
| AZURE_OPENAI_API_KEY | Set in `~/.Renviron` — DOI employees only; requires DOI network or VPN |

---

## The TaxaID Ecosystem

| Package | Purpose | Status |
|---|---|---|
| TaxaTools | Name verification, cleaning, parsing, rank lookup, column standardisation; **LLM provider functions** (call_api, call_anthropic_api etc.); **LLM text generation** (draft_methods_text, draft_results_text); **GBIF backbone census** (census_genus_species); **Common name lookup** (common_to_scientific) | In development |
| TaxaFetch | Occurrence data acquisition (GBIF, DataONE, PDF, literature search), source combination | In development |
| TaxaHabitat | Habitat assignment via LLM, spatial QAQC; depends on TaxaTools for LLM calls | New (Session 28) |
| TaxaMatch | Sequence input (DADA2/FASTA), BLAST search, match standardization; BirdNET/image classifier ingestion | In development |
| TaxaLikely | Convert match scores to likelihoods using hierarchical Bayesian model; reference QC | New (Session 30) |
| TaxaExpect | Use occurrence and habitat data to estimate a theta prior for a taxon at a particular location | In development |
| TaxaAssign | Calculate posterior probability for a taxonomic assignment given a likelihood and a prior | In development |
| TaxaFlag | Flag anomalous detections: contamination (lab/field blanks), allochthonous transport, taxonomic scope, handler artifacts | New (Session 60) |
| TaxaWizard | Conversational workflow designer: LLM-powered interview → .R script, .md methods, or Shiny app | New (Session 68) |

**Ecosystem logic (scored pathway):** TaxaTools cleans names → TaxaFetch fetches occurrence data → TaxaHabitat assigns habitats → TaxaMatch standardizes match data → TaxaLikely converts scores to likelihoods → TaxaExpect builds priors → TaxaAssign computes posteriors → TaxaFlag flags anomalous detections. TaxaWizard sits outside the dependency chain (generates scripts that call the other packages).

**Ecosystem logic (no-score pathway):** When match scores are unavailable or a single best candidate is returned, TaxaMatch and the likelihood model are bypassed. `TaxaLikely::unreferenced_candidates()` adds H2/H3 placeholder rows; `TaxaLikely::assign_scores()` sets likelihoods: (1) `score_type = "none"` — uniform likelihoods = 1.0, posteriors proportional to priors (morphology / expert IDs); (2) `score_type = "similarity_softmax"` — for single-score classifiers (e.g. BirdNET top-1), modulates likelihoods by classifier confidence; (3) upranked consensus — same as (1). `expand_consensus_candidates()` is deprecated (Session 99). Output feeds TaxaAssign normally.

**Dependency chain:** TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign → TaxaFlag
TaxaMatch → TaxaLikely → TaxaAssign → TaxaFlag
consensus df → TaxaLikely (unreferenced_candidates + assign_scores) → TaxaAssign → TaxaFlag
TaxaWizard: no TaxaID dependencies (uses metadata JSON files as interface)

**Package split notes:**
- Session 19: TaxaFetch split out of TaxaExpect (owns data acquisition)
- Session 28: TaxaHabitat split out of TaxaFetch (owns habitat assignment + spatial QAQC); LLM provider functions moved to TaxaTools
- Session 30: TaxaMatch scope revised to thin shell; TaxaLikely created to own score→likelihood conversion
- Session 60: TaxaFlag created for post-assignment anomalous detection flagging
- Session 68: TaxaWizard created for conversational workflow design (outside dependency chain)

**Licensing:** All packages use CC0 1.0 (public domain, per USGS policy). TaxaExpect depends on glmmTMB (GPL >= 3); source is CC0 but binary distributions bundling glmmTMB may be subject to GPL terms.

---

## Shared Data Interface

- Classification paths: pipe `|` delimited
- Rank labels: pipe `|` delimited, aligned positionally with classification path
- Spatial terminology (strict):
  - `point_id` = exact lat/lon coordinate identifier (created before gridding)
  - `grid_id` = aggregated spatial cell identifier (encodes location ONLY — never habitat)
- Likelihood / prior / posterior object structure: TBD — see TaxaAssign CLAUDE.md

---

## Taxonomic Backbone ID Reference

| ID | Backbone |
|---|---|
| 1 | Catalogue of Life |
| 3 | ITIS |
| 4 | NCBI |
| 9 | WoRMS |
| 11 | GBIF |

Full list: https://verifier.globalnames.org/

---

## Developer Workflow Reminder (macOS / RStudio)

```r
devtools::document()   # ALWAYS: regenerates NAMESPACE and .Rd files
devtools::test()       # run tests within the package project (uses load_all)
devtools::install()    # required before using library(Package) from another project
```

**When to run what:**

| Situation | Command | Speed |
|---|---|---|
| Editing code, running `devtools::test()` inside the package | Nothing extra — `load_all()` is implicit | Fast |
| Changed roxygen docs or added/removed exports | `devtools::document()` | Fast |
| Need to use the package from another project (`library(Package)`) | `devtools::install()` | Slow |
| Stale namespace / unexplained errors after switching branches | Restart R, then `library(Package)` | Medium |

**Rule:** `document()` alone for in-package editing/testing; add `install()` when
switching to another project that calls the package.

**⚠️ Claude Code instruction: whenever you make changes that require reinstall,**
**end your response with an explicit "To apply these changes" block using this exact pattern:**

**If only TaxaTools changed:**
```r
.rs.restartR()
devtools::install("~/My Drive/Rscripts/projects/TaxaID/TaxaTools")
.rs.restartR()
```

**If multiple packages changed, or if unsure which downstream packages are affected:**
```r
.rs.restartR()
source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/install_all.R")
.rs.restartR()
```

**Always include two `.rs.restartR()` calls** — the first clears the stale session before
installing, the second ensures the freshly installed packages are loaded cleanly.
The `source()` line installs all packages in dependency order without opening each project.
Do not tell the user to use Session → Restart R or Cmd+Shift+F10 (does not work on this machine).

---

## Coding Conventions

- Native pipe `|>` throughout — never `%>%`
- `utils::globalVariables()` must be **first line** of every R file that uses NSE column names; omit entirely from files with no NSE references
- No blank lines inside `@param` roxygen blocks
- Helper/internal functions: `.` prefix + `@noRd`
- `package::function()` style for cross-package calls
- `%||%` exported from TaxaTools — never redefine in downstream packages; import via `@importFrom TaxaTools %||%`
- **`llm_fn` pattern**: LLM-calling functions accept `llm_fn = call_api` param (default via `getOption("TaxaID.llm_fn")`); users pass compatible wrapper for other providers

---

## ⚠️ Known R Footguns

### Split-string sprintf bug (recurring)
`sprintf()` does NOT concatenate multiple string arguments.
```r
# WRONG — crashes with "invalid format '%d'"
warning(sprintf("Message with %d items: ", "extra string", count))
# CORRECT
warning(sprintf("Message with %d items: extra string", count))
```
Check all `sprintf`/`warning`/`message`/`stop` calls before delivering any file.

### Roxygen blank lines inside @param
Blank line inside `@param` block → `devtools::document()` fails silently.

### read.csv numeric coercion of IUCN codes
`read.csv` parses `"9.2"` as `<double>`. Always `as.character()` before joining
against `.iucn_habitat_lookup$l2_code`.

### Logical parameter NA validation
`is.logical(NA)` returns `TRUE`. Always add `|| is.na(x)`:
```r
if (!is.logical(strict) || length(strict) != 1L || is.na(strict)) stop(...)
```

### \tabular in roxygen blocks
Use `\itemize` or `\describe` instead. If `devtools::document()` runs but does not
print "Writing <function>.Rd", a broken `\tabular` block is the first thing to check.

### taxon_match / geo_match column collision (Session 25)
`search_literature()` pre-initialises `geo_match = NA` and `taxon_match = NA`.
If screening fails partway and leaves stale values, a subsequent `left_join` creates
`.x`/`.y` duplicates. Always drop stale screening columns before rebuilding the prompt.

### prompt_api() breaking change (Session 26)
Renamed from `prompt_anthropic_api` to `prompt_api`. Params `model`, `max_tokens`,
`api_key` removed — now handled via closure passed to `llm_fn`. See TaxaFetch CLAUDE.md.

### PCRE `sub()` does not match newlines without `(?s)` (Session 33)
`sub(".*?(\\[[\\s\\S]*\\]).*", "\\1", x, perl=TRUE)` silently returns `x` unchanged
when `x` contains newlines, because `.*` in PCRE does not match `\n` by default.
Fix: add `(?s)` inline flag: `sub("(?s).*?(\\[...]\\]).*", "\\1", x, perl=TRUE)`.
This affected `assign_taxa_llm()` in TaxaAssign — LLM responses wrapped in markdown
fences were never parsed, causing all-NA `range_status` and uniform priors.

### `.resolve_llm_fn()` default silently degrades under fully-namespaced calls (Session 123)
`assign_taxa_llm()`, `run_llm_pipeline()`, `build_context()`, `suggest_unreferenced_species()`
(TaxaAssign) and `review_assignments()` (TaxaFlag) all default `llm_fn` to
`getOption("TaxaID.llm_fn", TaxaTools::call_api)`. `call_api()`'s provider
auto-detection depends on `TaxaTools::.onAttach()` having run, which only happens via
`library(TaxaTools)` — never via `TaxaTools::function()`. Code that calls these
functions using only namespaced (`::`) calls therefore never triggers auto-detection,
and `call_api()` **silently falls back to uniform/degraded output instead of
erroring**. No warning, no error — just a suspiciously uniform result. Caught only by
noticing the output looked wrong, in the TaxaID Layer-1 workflow scripts (which use
namespaced calls exclusively). Fix: always pass `llm_fn` explicitly when calling any
of the five functions above from a fully-namespaced script:
```r
llm_fn = getOption("TaxaID.llm_fn", TaxaTools::call_anthropic_api)
```

### `library(TaxaTools)` alone does not activate provider auto-detection in a plain `Rscript` session (found Session 145)
The Session 123 footgun above prescribes `library(TaxaTools)` as the fix for `call_api()`'s
provider auto-detection. That's necessary but **not sufficient** in a non-interactive
`Rscript` session (as opposed to RStudio): confirmed directly that `library(TaxaTools);
call_api(prompt)` still errors `"no LLM provider configured"` even with a real
`ANTHROPIC_API_KEY` set in `~/.Renviron`, because `getOption("TaxaID.provider")` /
`getOption("TaxaID.llm_fn")` stay `NULL` after attach in that context. Whatever sets those
options interactively (RStudio session init, or an `.Rprofile` hook) doesn't fire for a bare
`Rscript` batch run. Not investigated further (out of scope for the session that found it) --
the workaround is to pass an explicit provider:
```r
llm_fn <- function(prompt) TaxaTools::call_api(prompt, provider = "anthropic")
```
Relevant any time you write a one-off `Rscript` (not run inside RStudio) that needs to make a
real LLM call — e.g. diagnostic/sensitivity-sweep scripts under `diagnostics/`.

### Xeno-canto v2 API is dead; v2→v3 migration in Session 87 missed one call site (found Session 124, FIXED Session 125)
`ecosystem_docs/NAME_CHANGE_HISTORY.md` records the v2→v3 migration as done in Session 87
(`fetch_reference_recordings()` updated), but `TaxaLikely::.xc_recording_count()`
(`R/coverage.R`, added Session 119 — *after* that migration) was never updated and called
the dead v2 endpoint. Because `.xc_recording_count()` checked `resp_status != 200L` and
returned `NA_integer_` silently, `audit_acoustic_coverage(xc_recordings = TRUE)` had
returned `NA` for every species, with no warning, from the moment it was written. Fixed
Session 125: switched to the v3 endpoint, added a required `key` param (read from the
`XC_API_KEY` env var), and rewrote the query to v3's tag-based syntax
(`gen:X sp:Y type:call`). Live-verified against real species. See
`TaxaLikely/CLAUDE.md`'s Known Footguns for the fix detail.

### RStudio's `dialogViewer()` can silently swallow a Shiny gadget's Done button when the gadget contains a `leaflet` map (found Session 134b)
`TaxaTools::define_search_polygon()` (a `miniUI`/`shiny` gadget with a `leaflet` map)
worked fine in earlier sessions but started returning `NULL` on every call in Session
134b, even when the user clicked **Done** (not Cancel) -- confirmed reproducible, not a
one-off. A *minimal* gadget (title bar + Done button, no leaflet) worked correctly with
`shiny::dialogViewer()` in the same RStudio session, ruling out a general
`shiny`/`miniUI` problem. The *exact* production gadget code worked correctly when its
viewer was swapped to `shiny::browserViewer()` (opens in a real browser) -- confirmed
both via the calling R session receiving the correct return value and via directly
inspecting the live page with Claude's Chrome browser-automation tools. `paneViewer()`
was then also tested directly against this exact gadget and confirmed working too.
Conclusion: on at least one real RStudio setup, the embedded `dialogViewer()` webview
specifically mishandles a gadget's Leaflet content in a way that breaks the Done
button's click-to-server round trip, while the identical gadget works fine via either
`browserViewer()` or `paneViewer()`. **If you write or modify any Shiny gadget in this
ecosystem that embeds a `leaflet` map, do not assume `dialogViewer()` works -- use
`shiny::paneViewer()` instead**, matching this ecosystem's existing mapping gadgets
(`TaxaTools::define_search_polygon()`, `TaxaHabitat::review_spatial_flags()`,
`TaxaExpect::plot_theta_map_interactive()` all use it, for one consistent
map-interaction style) -- and only use `dialogViewer()` if you've confirmed it
round-trips a real click on the actual machine you're targeting.
Also see this same debugging session's now-corrected R library documentation just above
(Developer Environment table) -- a stale-library-cache theory looked very plausible for
several rounds before being ruled out by directly checking `.libPaths()` from a real
session; don't skip that direct check next time something "should be fixed but isn't."
See `TaxaTools/CLAUDE.md`'s Session 134b note for the full multi-round debugging record.

---

## Recent Breaking Changes

Full history (Sessions 19–123) in `ecosystem_docs/NAME_CHANGE_HISTORY.md`. This table
holds only changes newer than that archive — trimmed to empty as of Session 124 (the
prior "Sessions 47+" table fully duplicated the archive, which had already grown to
cover the same range; see `ecosystem_docs/REENTRY_PROMPT_session124...` for the note).
Add new rows here as breaking changes land; archive + clear again once this grows long.

| Session | Change | Package | Notes |
|---|---|---|---|
| 125 | `audit_acoustic_coverage(xc_recordings = TRUE)` now returns real data | TaxaLikely | Behavioral, not signature. `.xc_recording_count()` migrated to Xeno-canto v3; requires `XC_API_KEY` env var (previously silently returned `NA` for every species regardless of key). |
| 125 | `correct_training_bias()` added | TaxaLikely | New preprocessing step, not yet called by any workflow. Divides classifier scores by an adaptive-shrinkage estimate of training-database representation bias before `unreferenced_candidates()`/`assign_scores()`. Overwrites `score_original` in place; raw value preserved in `score_uncorrected`. |
| 127 | `correct_training_bias(prior_weight = NULL)` → `correct_training_bias(tau = 1.0)` | TaxaLikely | Signature change. `prior_weight` param removed; `tau` added (single fixed global exponent, not adaptive per-candidate). Literature-grounded revision (Menon et al. 2020 logit adjustment) — see `TaxaLikely/CLAUDE.md`'s Session 127 note. Still not called by any workflow, so no downstream callers affected. |
| 136 | `fetch_reference_sequences()` → `fetch_ncbi_reference_sequences()` | TaxaLikely | Function rename. Old name didn't say NCBI anywhere; needed to disambiguate once a second live-API reference source (`fetch_bold_reference_sequences()`, BOLD Systems) existed. Old name kept as a deprecated forwarding alias (`.Deprecated()`, matches `audit_barcode_coverage_ncbi()`'s pattern) — all internal call sites (`build_site_reference()`, workflows, README, TaxaWizard snippets) updated to the new name directly. |
| 136 | `fetch_bold_reference_sequences()` added | TaxaLikely | New reference-fetch function, BOLD Systems analog of `fetch_ncbi_reference_sequences()`. Talks directly to BOLD's real v5 Data Portal API via `httr2` (no `bold` package dependency — that package targets BOLD's now-retired v3/v4 API and no longer works). Live-tested end to end. See `TaxaLikely/CLAUDE.md`'s Session 136 note. |
| 138 | `join_priors()` output is now site-preserving for multi-site observations | TaxaAssign | Behavioral, not signature. Final `distinct()` call now also keys on `grid_id`/`main_habitat` (bug fix — previously collapsed a multi-site observation to one row per candidate per its own best site). Any caller using `join_priors()`'s multi-site `site` data-frame path must now call the new `combine_multisite_priors()` before `compute_posterior()`. |
| 138 | `combine_multisite_priors()` added | TaxaAssign | New function, inserted between `join_priors()` and `compute_posterior()`. Combines per-site prior rows via precision-weighted logit combination. See `TaxaAssign/CLAUDE.md`'s Session 138 note. |
| 140 | `stack_occurrences()` now drops duplicate-`gbifID` rows | TaxaFetch | Behavioral, not signature. Rows with a duplicated non-`NA` `gbifID` are dropped (first kept) whenever that column is present. Defense-in-depth against double-counted GBIF records; sources without a `gbifID` column (literature/DataONE) are unaffected. See `TaxaFetch/CLAUDE.md`'s Session 140 note. |
| 140 | `fetch_occurrences_by_taxon()` added | TaxaFetch | New function. Taxon-centric batched GBIF fetch -- unions each candidate taxon's own search geometry and combines taxa sharing identical geometry into one `get_gbif_occurrences()` call. See `TaxaFetch/CLAUDE.md`'s Session 140 note. |
| 140 | `trim_to_amplicon()` added | TaxaLikely | New function. In-silico PCR: extracts the amplicon region from over-length reference sequences (e.g. full mitogenomes) via primer matching, instead of `build_sequence_matrix()`'s length filter discarding them outright. See `TaxaLikely/CLAUDE.md`'s Session 140 note. |
| 140 | `barcode_primer_defaults` / `resolve_barcode_primers()` added | TaxaTools | New registry + resolver, consumed by `TaxaLikely::trim_to_amplicon()`. Populated only with verified MiFish-U/E (12S) primers so far. See `TaxaTools/CLAUDE.md`'s Session 140 note. |
| 141 | `barcode_primer_defaults` gains 6 more entries (16S, COI, cytb, rbcL, matK, trnL) | TaxaTools | Behavioral, not signature. Every mito/chloroplast marker in `barcode_length_defaults` now has a verified primer pair; nuclear markers (18S/ITS/ITS2) deliberately still unpopulated. See `TaxaTools/CLAUDE.md`'s Session 141 note. |
| 142 | `barcode_primer_defaults` gains `coi-leray`; bare `"COI"` now ambiguous | TaxaTools | Behavioral, not signature. The real eDNA COI mini-barcode (mlCOIintF/dgHCO2198) is now registered alongside `coi-folmer`. Any existing caller passing bare `barcode_term = "COI"` to `resolve_barcode_primers()`/`trim_to_amplicon()` must now specify `"COI-Folmer"` or `"COI-Leray"` explicitly -- bare `"COI"` now errors instead of resolving. See `TaxaTools/CLAUDE.md`'s Session 142 note. |
| 143 | `join_priors(backbone_id = ...)` added, no default | TaxaAssign | New required parameter (errors if omitted). Replaces a previously hardcoded, un-overridable `backbone_id = 4L` inside `join_priors()`'s taxonomy-fallback fill (`R/join_priors.R`). No safe default exists -- the correct backbone depends on which backbone the caller's input taxonomy was verified against, which varies by project. All in-repo call sites updated to pass it explicitly. |
| 143 | `posterior_consensus(backbone_id = 11L)` default removed | TaxaAssign | Signature change: default changed from `11L` to `NULL`. Errors only when `lookup_missing_taxonomy = TRUE` and `backbone_id` is not supplied (lazy validation -- most call sites never touch this path and are unaffected). |
| 143 | `run_bayesian_pipeline(backbone_id = 4L)` default removed | TaxaAssign | Signature change: `backbone_id` is now required, no default (errors immediately if omitted). Previously defaulted to `4L` (NCBI) although the parameter is forwarded unconditionally into `join_priors()`/`posterior_consensus()` -- there is no backbone choice that is safe for every project. All in-repo call sites updated to pass it explicitly. |
| 143 | `run_llm_pipeline(backbone_id = 4L)` default removed | TaxaAssign | Same change as `run_bayesian_pipeline()` above, same reasoning. All in-repo call sites updated to pass it explicitly. |
| 146 | `assign_taxa_llm(taxa_per_call = 30L)` → `15L` | TaxaAssign | Behavioral default change. Lowered after confirming a real batch of 30 taxa truncated 4/5 times at `call_api()`'s default `max_tokens = 3000`, silently falling back to uniform priors. Matches `TaxaFlag::review_assignments()`'s own independently-made `30L → 15L` fix for the identical failure mode. |
| 146 | `run_llm_pipeline(taxa_per_call = 30L)` → `15L` | TaxaAssign | Same change, forwarded to `assign_taxa_llm()`. |
| 146 | `.parse_taxa_response()` gives a truncation-specific warning | TaxaAssign | Behavioral, not signature. When the LLM response has no closing `]` at all (truncation signature), the warning now names the real cause and two concrete fixes instead of the old generic "failed to parse" message. |
| 147 | `score_consensus(rank_thresholds = NULL)` → `c(species=98, genus=95, family=90, order=85)` | TaxaAssign | Signature + behavioral change. A caller relying on the old default silently got zero score-based species-vs-congener discrimination -- see `TaxaAssign/CLAUDE.md`'s Session 147 note for the ROC-sweep evidence. Pass `rank_thresholds = NULL` explicitly to restore old behavior. Auto-rescaled by /100 if `score_col` looks like a 0-1 proportion scale. Verified against every real call site and test; none broken (539/539 tests unchanged). |
| 149 | `compute_posterior()`'s Monte Carlo path: truncated-normal likelihood sampling + widened J-shape prior guard (`prior_alpha < 1` → `<= 1`) | TaxaAssign | Behavioral, not signature. Fixes a spurious point-mass-at-0 in likelihood draws and a missed exact-`alpha==1` case in the fixed-at-mean override, on the path `posterior_consensus()` reads by default (`posterior_mean`). See `TaxaAssign/CLAUDE.md`'s Session 149 note and `ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`. `devtools::test()` 544/544 (up from 539), `devtools::check()` clean. |
| 150 | `expand_unreferenced_hypotheses()` moved TaxaAssign → TaxaLikely | TaxaLikely (new home), TaxaAssign (deprecated alias) | Package-placement fix, not a math change -- same algorithm, same output. `TaxaAssign::expand_unreferenced_hypotheses()` kept as a `.Deprecated()` forwarding wrapper to `TaxaLikely::expand_unreferenced_hypotheses()`. Callers using the bare (unqualified) name inside TaxaAssign, or `TaxaAssign::expand_unreferenced_hypotheses()` explicitly, still work but now warn; update to `TaxaLikely::expand_unreferenced_hypotheses()` to silence the warning. See `TaxaID/CLAUDE.md`'s Session 150 note above for the full reasoning and verification record. |
| 149 | `update_prior_from_consensus(presence_multiplier = 5)` → `confirmation_quantile = 0.9, min_confirmation_confidence = 0.8` | TaxaAssign | Signature + behavioral change. The flat multiplier ignored confirmation count/confidence entirely; the new design substitutes the confirmation-quantile of confirming donors' `consensus_posterior` (never lowering the existing prior), gated by a minimum confidence floor. Also fixes a latent `prior_alpha`/`prior_beta` staleness bug. Propagated through `run_bayesian_pipeline()`, `run_llm_pipeline()`, `generate_report()`, both `inst/` workflow scripts, and the `taxonomic-assignment` vignette. See `TaxaAssign/CLAUDE.md`'s Session 149 notes and `ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`. `devtools::test()` 537/537, `devtools::check()` clean. |
| 149 | `prepare_model_dataframe(sampling_group_col = ...)` added; `train_biodiversity_model()` refuses multi-group data; `train_biodiversity_model_by_group()` added | TaxaExpect | Additive, backward compatible (`sampling_group_col` defaults `NULL`, no behavioral change for existing callers) -- except `train_biodiversity_model()` now errors if its input happens to already carry a `sampling_group` column spanning >1 value (previously would have silently fit a pooled model). Code-level enforcement of the "Shared effort assumption" that was previously advisory documentation only. See `TaxaExpect/CLAUDE.md`'s Session 149 notes. `devtools::test()` 401/401 (up from 383), `devtools::check()` clean. |
| 151 | `correct_training_bias(tau = 1.0)` → `tau = 0` | TaxaLikely | Behavioral default change (soundness-review item 11, the review's own "single clearest actionable bug"). Every real calibration run against this function (image, pooled acoustic across two sample sizes) found `tau ≈ 0` optimal, contradicting the shipped `tau = 1.0` default. A caller who does nothing now gets no correction instead of one contradicted by every real result obtained so far. Not called by any production workflow with an explicit `tau` override, so no real call site's behavior changed. `devtools::test()` 658/658, `devtools::check()` clean. |
| 151 | `apply_coverage_constraints(constraint_behavior = "zero")` → `"relabel"` | TaxaLikely | Behavioral default change (soundness-review item 12). The old default hard-zeroed the `"unreferenced_species"` hypothesis whenever a genus census said "complete" -- treating an NCBI-query estimate as certain ground truth. `TaxaAssign::run_bayesian_pipeline()` already defaulted to `"relabel"`; this brings the low-level function's own default in line. Any caller relying on the implicit old default (three vignettes, `TaxaLikely/inst/workflows/5_audit_coverage_workflow.R`, the superseded `TaxaLikely_workflow.R`) now gets the non-destructive mode; the two workflow scripts whose comments specifically narrate zero-suppression now request `constraint_behavior = "zero"` explicitly to preserve that. `devtools::test()` 661/661 (up from 658), `devtools::check()` clean. |
| 151 | `build_sequence_matrix(barcode_term = NULL)` added | TaxaLikely | Additive, backward compatible (soundness-review item 13) -- no behavioral change for existing callers, since `barcode_term` defaults `NULL` and explicit `min_seq_len`/`max_seq_len` always override it. When supplied, auto-resolves the length window via `TaxaTools::resolve_barcode_lengths()` instead of the generic `[100, 2000]` default, closing the documented "Paralabrax footgun" (a broad NCBI fetch can silently mix two different amplicon windows into one training set) ergonomically. Wired into `sequence_likelihood_workflow.R`. `devtools::test()` 667/667 (up from 661), `devtools::check()` clean. |
| 151 | `blast_sequences(score_range = 2)` → `8` | TaxaMatch | Behavioral default change (soundness-review item 14). The old 2-pt tolerance window could silently drop a query's true species from the output entirely whenever a confusable congener scored higher -- a real leave-one-out check against 3 real 12S reference datasets found this happened in 4/7 real congener-outscoring events (57%), worst gap 7.1 points. New default covers every observed gap with margin. Any caller relying on the implicit old default now retains more candidates per query (bounded by `max_hits`, unchanged at 20); two real workflow scripts hardcoding `score_range = 2` explicitly (`blast_sequences_workflow.R`, `workflow_fastq_to_match.R`) updated to `8`. `devtools::test()` 451/451, `devtools::check()` clean. |
| 151 | `flag_contaminant()`'s `contaminant_score` formula changed; `prior_weight = 2` added | TaxaFlag | Behavioral change (soundness-review item 15), affects every existing caller since the score formula itself changed, not just a parameter default. Old: unweighted mean of per-sample proportions, hard 0.0/1.0 for taxa absent from one side. New: depth-weighted `field_rate`/`control_rate` (reads-weighted, not sample-count-weighted), Empirical-Bayes-shrunk toward 0.5 by total sample-count replication. `mean_prop_field`/`mean_prop_control` still returned (informational only); new `field_rate`/`control_rate`/`n_field_present` columns added. `prior_weight = 0` reproduces the old exact-0/1 boundary behavior on the new depth-weighted rates (not byte-identical to the pre-Session-151 formula, which used unweighted per-sample means). `devtools::test()` 169/169, `devtools::check()` clean. |
| 151 | `flag_handler(station_metadata = NULL, deploy_col = "deploy_time", retrieve_col = "retrieve_time")` added; new `edge_anchor_source` output column | TaxaFlag | Additive, backward compatible (soundness-review item 16, the review's final H-priority item) -- no behavioral change for existing callers, since `station_metadata` defaults `NULL` and every one of the 36 pre-existing tests passes unchanged. When supplied, anchors group edges on real deploy/retrieve timestamps instead of the detection data's own min/max, fixing the flaw where the first/last genuine detection at a station was always scored maximally suspect. A group missing from `station_metadata` falls back to the old behavior with an explicit `warning()`. `devtools::test()` 181/181 (up from 169), `devtools::check()` clean. |
| 152 | `flag_contaminant()`'s shrinkage denominator changed from sample count to read count; `prior_weight = 2` → `20` (now read-equivalent units) | TaxaFlag | Behavioral change, affects every existing caller. Found via live-testing `TaxaID_Workflow_Template_TEST.R` and both real PtConception workflows (`ecosystem_docs/REENTRY_PROMPT_session151_debug_template_and_12S_18S.md`): Session 151's sample-count shrinkage conflated a 2-read detection with a 500,000-read detection whenever both came from one sample, capping 97% (12S)/88% (18S) of real taxa at `"moderate"` regardless of actual evidence strength (median real taxon in both datasets: 1 field sample). Three alternatives (decontam-style hypergeometric/binomial prevalence tests; Beta-Binomial shrinkage toward a depth-based background rate) were prototyped against real 12S/18S data and rejected -- the first two degenerate to `p=1` whenever a taxon has zero control reads regardless of total evidence (reverting almost exactly to the pre-151 problem); the third doesn't transfer across studies with different control:field depth ratios (missed the known real 18S contaminant entirely). Read-count-based shrinkage in the existing depth-normalized rate space needed no new anchor point and was validated at `prior_weight` in `{20, 50, 100, 500}`: 100% of known `"high"`-risk taxa recovered with zero false positives at every value, on both real datasets. New `n_reads_total` output column exposes the quantity now driving shrinkage; `n_field_present`/`n_controls_present`/`n_controls_total` remain, informational only. `devtools::test()` 185/185, `devtools::check()` clean. |
| 152 | `posterior_consensus()`'s internal `.extract_rank_values()` gains a species-from-`taxon_name` fallback | TaxaAssign | Behavioral bug fix, not a signature change. Found via a full real end-to-end run of `TaxaID_Workflow_Template_TEST.R`: `consensus_posterior`/`consensus_confidence_score` silently computed to exactly `0` for every single-hypothesis resolved observation whenever the input had no explicit `species` column (TaxaLikely's real sequence/BLAST pathway never produces one) -- confirmed against real Template output where the winning candidate's own `posterior_mean` was 0.999/0.938/1.0 but `consensus_posterior` read `0` for all three. `consensus_taxon` itself was unaffected (a different code path). Fix mirrors the function's existing genus-from-binomial derivation. `devtools::test()` 544/544, `devtools::check()` clean. |
| 153 | `update_prior_from_consensus()`'s boosted `prior_mean` clamped to `[1e-9, 1-1e-9]` before deriving `prior_alpha`/`prior_beta` | TaxaAssign | Behavioral bug fix, not a signature change. A regression in Session 149's own alpha/beta-consistency fix: a confirmation quantile of exactly `1.0` (common in practice) produced `prior_beta = 0`, which `compute_posterior()` correctly rejects. `prior_mean` itself is left unclamped (`1.0` is a legitimate point estimate); only the Beta-shape derivation is clamped, mirroring `join_priors.R`'s `.make_ab()` boundary guard. Found live-testing `PtConceptionWorkflow_12S.R`. `devtools::test()` 548/548 (up from 544), `devtools::check()` clean. |
| 153 | `candidate_genera`/singleton-genus derivation in `inst/TaxaID_Workflow_Template_TEST.R` gains an `nzchar(genus)` guard (two call sites: Section 3's escalation ladder, Section 6a's reference fetch) | TaxaID (template only, not a package function) | Behavioral bug fix. The prior `!is.na(genus)` filter let an empty-string genus (a real, common shape for low-confidence BLAST/GBIF matches) through as a literal taxon name, crashing `TaxaLikely::fetch_ncbi_reference_sequences()`. Never triggered by the template's own tiny bundled fixture; found live-testing the real `PtConceptionWorkflow_12S_single_site.R`/`_18S_2_single_site.R` workflows built from this pattern -- fixed at the source so future workflows built from the template don't inherit it. |
| 2026-07-18 (Fable) | `calibrate_query_noise()` default `offset_form` flipped `"constant"` -> `"linear"`; wired into all 6 workflow call sites | TaxaLikely + workflows | Behavioral default change (unpublished pkg, so no external breakage). `"linear"` (affine, level-aware) is now the default after the generality test (5 real datasets) confirmed the per-species-means-don't-transfer collapse holds for BLAST- and external-scored DNA markers alike; `"constant"` retained as opt-out. Wired explicitly: `"linear"` in PtConceptionWorkflow_12S_single/_multi_site.R + Mugu{Fish,WilderFish}Workflow.R; `"constant"` in PtConceptionWorkflow_18S_2_single_site.R (only 2 referenced species -> affine unfittable) and inst/TaxaID_Workflow_Template_TEST.R (tiny fixture), both with comments. Real edge-case bug fixed en route: 1 confident species made `sd()` NA and crashed the fallback warning (`isTRUE()` guard added). `devtools::test()` 0 fail (423), `check()` 0/0/0. See TaxaLikely 11A. |
| 2026-07-18 (Fable) | `calibrate_query_noise(offset_form = "linear"\|"constant", min_calib_species = 8L)` added | TaxaLikely | Additive, fully backward compatible (default `"constant"` = the original single-additive-offset behavior, byte-identical; all pre-existing tests unchanged). `"linear"` remaps every H1 mean through a robustly-fit `intercept + slope*trained_mean` line (per-species medians, weighted, evidence-range-clamped) instead of one constant — a level-aware generalization for train-vs-inference score-scale gaps that aren't a pure location shift. Motivated + validated on real 12S PtConception: the DECIPHER-MSA per-species H1 means do not transfer to the external `PercMatch` scoring scale (robust slope→0, per-species offset-vs-trained-mean slope ~ −1, single pooled mean beats "per-species + offset" in CV), H1 win rate 74.2%→76.3% via the shipped function. Only H1 mean location is remapped; H2/H3 congener-divergence deltas + gap feature (the discriminators) are untouched. Opt-in (the confident calibration set can't test congener discrimination); falls back to `"constant"` with a warning if `< min_calib_species` confident species. `$Query_Calibration` gains `offset_form`/`slope`/`intercept`. Not wired into any production workflow. See TaxaLikely/CLAUDE.md's 2026-07-18 note and `[[project_train_inference_scale_validity]]`. `devtools::test()` 0 failures (422), `devtools::check()` 0/0/0. |
| 158 | `train_likelihood_model(score_transform = "logit"\|"sqrt_mismatch")` added; `H1_Lookup$sigma_score` bug fix; `H2_Lookup$var_shrunk` added; H2 mean anchor fixed | TaxaLikely | Additive param (default `"logit"`, fully backward compatible) + a real, pre-existing bug fix + two behavioral fixes to H2/H3's construction. `score_transform` lets H1/H2/H3 be modeled on `sqrt_mismatch` instead of `logit` -- found necessary because logit gives a qualitatively backwards answer for whether a genus's species are hard or easy to tell apart, confirmed on real 12S congener data (genuinely tight genera can show HIGHER logit-scale variance than loose ones, the opposite of the raw-proportion-scale truth). Independently, `H1_Lookup$sigma_score` had been storing `sqrt(shrunk variance)` instead of the variance itself since the formula was first written -- every species-specific H1 candidate's uncertainty has been systematically understated (evaluated against roughly the fourth root of the intended variance, not the square root) on both scales, for as long as this formula has existed. `devtools::test()` 696/696 (up from 670), `devtools::check()` clean. See TaxaLikely/CLAUDE.md's Session 158 note and `[[project_job2_unreferenced_relatives]]` for the full record. |
| 158 (2026-07-16) | `calibrate_query_noise()`/`evaluate_likelihoods(evidence_col=, min_coverage=)` now work on `"sqrt_mismatch"`-trained models instead of erroring | TaxaLikely | Behavioral correction, not a signature change. The Session 158 guards blocking these mechanisms on non-`"logit"` models were based on a mistaken premise (delta-method re-derivation showed `SE(transform(score)) propto 1/sqrt(N)` holds for any transform, not just logit); found live-testing `sqrt_mismatch` against the real `PtConceptionWorkflow_12S_single_site.R`, which uses both. `devtools::test()` 698/698, `check()` clean. Wired into that real workflow (`train_likelihood_model(score_transform = "sqrt_mismatch")`). See `[[project_job2_unreferenced_relatives]]`'s "Correction (2026-07-16)" section. |
| 158 (2026-07-16) | `expand_unreferenced_hypotheses()` now copies `score_likelihood_cov`/`score_likelihood_evidence`/`h2_delta_source` onto expanded H2/H3 rows when present | TaxaLikely | Behavioral change, not a signature change. Previously these were left `NA` on every expanded named-species row along with genuinely row-specific extra columns (e.g. `constraint_applied`) -- found live-testing the real `sqrt_mismatch` workflow run, where `h2_delta_source` read `NA` in post-`join_priors()` output instead of `"genus_specific"`/`"global_fallback"`. `devtools::test()` 706/706, `check()` clean. |
| 157 | `train_likelihood_model()`'s `H1_Lookup` gains `n_obs_species`; `Stats` gains `n_h1_pooled`/`n_h2_pooled`/`prior_weight`; `evaluate_likelihoods()`'s `score_likelihood_mean`/`score_likelihood_sd` redesigned | TaxaLikely | Additive schema change + behavioral change to an existing output's meaning (not a signature change -- no new params on either function). `score_likelihood_sd` previously came from resampling the query's own observed score around the global H1 population dispersion; now it reflects shrinkage-consistent uncertainty in the trained mean itself (`Var = w^2*sigma^2/n`, `w` the same shrinkage weight as the point estimate), scaled by how much reference data calibrated it. Real-data live-testing the same day caught two real issues in the first version and both are fixed: (1) using naive (non-shrinkage-discounted) `sigma^2/n` overstated uncertainty for the many real species with only 2-3 reference sequences; (2) the true pooled training count was wrongly used as "n" for candidates/genera with NO local data at all, making them look MORE confident than well-referenced ones -- now uses `prior_weight` (the codebase's existing "equivalent sample size of the prior") instead, so H2/H3 are reliably wider than H1 again. Falls back to the exact previous behavior for any `model_params` trained before this change (missing `n_obs_species`). No change needed in `TaxaAssign::compute_posterior()`. `devtools::test()` 674/674 (up from 670), `devtools::check()` clean. |
| 156 | `evaluate_likelihoods(evidence_col=)`'s H1 sigma rescale is now gated, not unconditional | TaxaLikely | Behavioral change, not a signature change (no new params). Session 155's rescale applied `1/sqrt(evidence_ratio)` to every candidate whenever `evidence_ratio < 1`, and was found net negative on real 12S data even at the widen-only default (27 helped, 2053 hurt) -- an elementary property of the Gaussian (widening variance must lower the peak while raising the tails, since the density still integrates to 1) meant most low-evidence real observations, being close-to-mean decent matches, paid the peak-lowering cost with no tail benefit. Now the rescale is applied only when an exact, closed-form criterion (`-0.5*log(c) + 0.5*z^2*(1-1/c) > 0`, `c` = variance-rescale factor, `z` = the candidate's own standardized distance from its trained mean) says doing so does not lower that candidate's density -- verified numerically against a live `dnorm()` call before shipping. Any existing caller passing `evidence_col` gets fewer, more conservative rescales than before (a strict subset of the previous behavior in the widen direction). `devtools::test()` 670/670 (up from 667), `devtools::check()` clean. **Re-validated against the real 12S PtConception dataset the unconditional version was tested on**: 163 helped / 3 hurt (vs. 27/2053), mean H1 likelihood 0.8014 -> 0.8016 (vs. the old regression 0.899 -> 0.884) -- see `TaxaLikely/CLAUDE.md`'s Session 156 note for the full result, including the 3 residual hurt cases traced to the gate's documented score-only-marginal approximation. **Wired into `PtConceptionWorkflow_12S_single_site.R`** (new Step 7a.6 + `evidence_col`/`evidence_max_ratio` added to the existing calibrate/evaluate calls) as an additive parallel diagnostic column only -- `join_priors()`/`compute_posterior()` still consume `score_likelihood`/`score_likelihood_mean` unchanged. Not yet live-run end to end in the full workflow, and not yet propagated to the `_multi_site` sibling or any other workflow. |
| 159 (final entry) | `fetch_ncbi_reference_sequences(max_out_of_range_len = 200000L)` added | TaxaLikely | Additive param, fully backward compatible (only relevant when `keep_out_of_range = TRUE`). Fixes a real gap found in the real Mugu `reference_df.rds` (142MB, a 111,213,091bp whole-genome scaffold pulled in because `keep_out_of_range = TRUE` had no upper size bound at all). Also folded into the cache key, which previously didn't vary by `keep_out_of_range` at all (a real staleness bug). `devtools::test()` 754/754 (up from 706), `devtools::check()` clean. |
| 159 (final entry) | `restore_suppressed_candidates()` gains `attr(result, "regional_unreferenced")`; `expand_unreferenced_hypotheses(unreferenced_df)` gains optional `observation_id` column | TaxaLikely | Additive, fully backward compatible -- no signature changes, existing callers unaffected. A congener rejected by `check_regional_overlap` is no longer just dropped; it's recorded (`observation_id`/`species`/`genus`/`family`) and returned as an attribute, in exactly the shape `expand_unreferenced_hypotheses()`'s new `observation_id`-scoped `unreferenced_df` rows expect (`NA`/absent = global, as before; a real `observation_id` restricts that row to one observation). Lets a species that IS globally referenced (so it would never appear via `audit_barcode_coverage()`) still compete as a named `unreferenced_species` hypothesis for the one query whose anchor doesn't overlap its reference. Closes the real "Mugu outcome didn't change" gap the earlier Session 159 entries left open -- see `TaxaLikely/CLAUDE.md`'s Session 159 final-entry note for the full record. Wired into `MuguFishWorkflow.R`; `MuguWilderFishWorkflow.R` deliberately NOT wired (its `.run_round1()` never calls `expand_unreferenced_hypotheses()` at all -- a pre-existing architecture gap flagged for the user, not fixed unilaterally). `devtools::test()` 754/754, `devtools::check()` clean. |
| 2026-07-18 (Sonnet 5) | `restore_suppressed_candidates()` ground-up redesign: `detected`/`perfect_threshold`/`purity_threshold`/`singleton_threshold` params removed; `delta` now only affects the no-score pathway; `model_params`/`alpha`/`max_dist`/`taxaexpect_priors`/`grid_id_col`/`taxon_col`/`grid_col`/`theta_col`/`budget_ratio_cap` added; new `restoration_basis` output column; `candidate_species_filter` re-scoped to gate Purpose B only | TaxaLikely | **Breaking, intentionally**, for the scored pathway. Implements `ecosystem_docs/SPEC_restore_suppressed_candidates_redesign.md`. Every observation is now checked unconditionally (no longer gated by a globally detected suppression rule); admission splits into Purpose A (`"competitive_score"`, prior-agnostic score-only outlier test, needs `model_params`) and Purpose B (`"plausible_prior"`, wide `max_dist` floor, gated by `candidate_species_filter`), or `"both"`. Restored scores now come from a median-aggregated, cheap-to-expensive hierarchy (new `R/restore_hierarchy.R`) instead of a flat `anchor_score - delta`. **A bare call with no `seq_matrix`/`model_params`/`check_regional_overlap` is now correctly a no-op** -- the old default restored every same-genus congener unconditionally. `.check_regional_overlap()` gains a `return_detail = TRUE` mode (default `FALSE`, fully backward compatible) returning a real percent-identity `pid` alongside the overlap verdict. `attr(result, "regional_unreferenced")` gains a `basis` column (`"regional_reject"` vs `"no_reference_data"`, additive). `devtools::test()` 0 failures (893, up from ~860), `devtools::check()` 0/0/0. See `TaxaLikely/CLAUDE.md`'s top session note for the full record. **Superseded/extended same day** by the Option A/C cost-control revision (next row) and rolled out to production workflows then, not at the time this row was written. |
| 2026-07-18 (Sonnet 5, continued) | `restore_suppressed_candidates()` Level 4 cost-control revision: `.worth_tier2_budget()` renamed `.worth_level4_check()`, gains `candidate_species_filter` param; new `max_level4_per_anchor` param (default `10L`) | TaxaLikely | Behavioral + signature change, found necessary by live-testing the redesign above against two real motivating cases (Mugu `Fundulus`, PtConception `Girella`) at the user's request. Both real anchors are themselves absent from `taxaexpect_priors` (correctly -- they're occurrence-implausible), which made the original ratio-only gate uncomputable and skip Level 4 for every candidate, including the one that matters; measured real cost of the resulting unrestricted sweep: 275.8s for one marker (vs. the pre-redesign 38s baseline). Fix: `candidate_species_filter` is Level 4's own default gate again (falls back to the ratio only for a candidate not on it) -- Levels 1-3 remain fully filter-independent, so this only affects the one expensive step. `max_level4_per_anchor` is an independent hard backstop cap. Verified against both real cases: cost cut ~4x (Fundulus) / ~3x (Girella), correctness preserved (if anything strengthened) in both. Rolled out same day to `MuguFishWorkflow.R`, `MuguWilderFishWorkflow.R`, `PtConceptionWorkflow_12S_single_site.R`, `PtConceptionWorkflow_18S_2_single_site.R` (all outside this monorepo). `devtools::test()` 0 failures (910, up from 893), `devtools::check()` 0/0/0. See `TaxaLikely/CLAUDE.md`'s top session note and `[[project_restore_suppressed_candidates_implementation]]` for the full record. |
| 2026-07-19 (Sonnet 5) | `restore_suppressed_candidates()` performance fix: new `.seq_matrix_partner_index()`/`.seq_matrix_lookup()` in `R/restore_hierarchy.R`, Levels 0-3 rewired onto them | TaxaLikely | Behavioral (no signature change) -- found when the user actually ran the updated `PtConceptionWorkflow_12S_single_site.R` against the real, full 13,442-observation dataset and the restoration step was still running after 70+ minutes. Root cause: the free Levels 1-3 hierarchy did a fresh linear `%in%` scan over the whole `seq_matrix` (~3M rows) per candidate species per call, with zero memoization -- R's `%in%`/`match()` rebuilds its hash table on every call rather than caching it, and Purpose A's unconditional genus-wide sweep exposed this at real genera Mugu never had (`Sebastes`, 107 species, vs. `Fundulus`'s 20). Fix builds a real accession-indexed lookup once per call instead. Verified: a real repeated `Sebastes` anchor lookup went from 17.64s to 0.03s (~590x); the full real 13,442-observation dataset went from 70+ minutes (still running when interrupted) to 42.1 seconds. `devtools::test()` 0 failures (910, unchanged), `devtools::check()` 0/0/0. See `TaxaLikely/CLAUDE.md`'s top session note and `[[project_restore_suppressed_candidates_implementation]]` for the full record. |
| 2026-07-19 (Sonnet 5) | `evaluate_likelihoods(min_rank_trust_pvalue = 0.001)` added; `$likelihoods` gains `absolute_fit_pvalue`/`trusted_rank`/`rank_trust_basis` | TaxaLikely | Additive, fully backward compatible -- no existing caller's behavior changes. The "rank-trust mechanism": answers whether the WINNING hypothesis's own absolute fit is believable (one-sided score-only test against its own trained mu/sigma), not just whether it beat the other candidates -- a real blind spot `score_likelihood` alone has, motivated by real PtConception contamination-pattern edge cases (Hylobatidae etc.) winning at likelihood=1.0 despite every specific candidate fitting poorly in absolute terms. Deliberately one-sided (unlike the existing, unchanged two-sided `alpha` gate) so a BETTER-than-typical match (e.g. a literal 100% identity hit) can never lose trust for being too good. See `TaxaLikely/CLAUDE.md`'s top session note for the full real-data validation record. Wired into `PtConceptionWorkflow_12S_single_site.R`'s `evaluate_likelihoods()` call (explicit `min_rank_trust_pvalue`, plus a new summary diagnostic message); not yet in any other workflow. |
| 2026-07-19 (Sonnet 5) | `posterior_consensus(uprank_trust_pvalue = 0)` added; output gains `winner_absolute_fit_pvalue`/`winner_trusted_rank`/`winner_rank_trust_basis`; new `consensus_reason = "trust_upranked"` value | TaxaAssign | Additive, fully backward compatible -- default `0` means never act (a p-value is never `< 0`), matching this ecosystem's threshold-disables-at-its-own-boundary convention rather than a separate boolean. Consumes TaxaLikely's rank-trust mechanism (row above) to broaden `consensus_taxon`/`consensus_rank` when the winning hypothesis's own absolute fit fails AND the trusted rank is coarser than what LCA/disagreement logic already produced -- never narrower. Targets a case LCA upranking structurally cannot reach: a single hypothesis winning outright (`n_plausible = 1`), nothing to disagree with. Only a PARTIAL decoupling from TaxaLikely's own `min_rank_trust_pvalue` -- gates whether to act on the winner's raw p-value, but *where* to broaden to still comes from `winner_trusted_rank` as already computed upstream. Real-data validated against the full real 13,442-observation PtConception dataset (0 false positives on every known-good case; `0.001` is a complete no-op there, `0.01` catches a real previously-undetected bug -- 8 observations misreporting real terrestrial canid DNA at species level). Wired into `PtConceptionWorkflow_12S_single_site.R` at `uprank_trust_pvalue = 0.01`. See `TaxaAssign/CLAUDE.md`'s top session note for the full record. |
| 2026-07-19 (Sonnet 5) | `add_posthoc_assessment(trusted_rank_col = "winner_trusted_rank")` added; new `posthoc_assessment` category `"unsupported_rank"` | TaxaFlag | Additive, fully backward compatible -- silently skipped when `trusted_rank_col` absent from `consensus_df` (optional upstream output). Overrides ANY of the existing 3x2 tier x likelihood categories, including `"sensible"`, since `winner_likelihood`'s ratio-normalization (best hypothesis always exactly 1.0) can look like strong evidence even when every candidate fit poorly in absolute terms -- catches exactly that gap using TaxaLikely's rank-trust signal (two rows above), passed through by `TaxaAssign::posterior_consensus()` (row above). Purely informational -- never changes `consensus_taxon`/`consensus_rank` itself (that's `posterior_consensus()`'s own separate opt-in `uprank_trust_pvalue`). **Real bug found and fixed the same session** via a full real-data run: the first version used plain string inequality instead of comparing canonical rank order, mislabelling 48% of its own flagged rows (cases where `trusted_rank` was FINER than `consensus_rank`, not coarser -- not a real mismatch). Fixed with a new `.std_rank_order` constant; corrected real count 2,501/13,442 (18.6%). Wired into `PtConceptionWorkflow_12S_single_site.R`. See `TaxaFlag/CLAUDE.md`'s top session note. |
| 2026-07-19 (Sonnet 5) | `fetch_reference_sequences()` and `audit_barcode_coverage_ncbi()` removed entirely (not just deprecated) | TaxaLikely | **Breaking**, but no real callers left. Both were `.Deprecated()` forwarding aliases from earlier renames (-> `fetch_ncbi_reference_sequences()` Session 136, -> `audit_barcode_coverage()` Session 113). Removed at the user's request after questioning why a not-yet-released package needed review/test coverage for a migration path with no external users. `audit_barcode_coverage_ncbi()` had zero real callers. `fetch_reference_sequences()` had 4 real in-monorepo callers (`TaxaAssign/vignettes/taxaid-ecosystem.Rmd`, `TaxaLikely/vignettes/score-to-likelihood.Rmd`, `diagnostics/Barcode_similarity_matrix.R`, `diagnostics/sandpiper_12S_similarity.R`) -- all four updated to the current name first. The two real external Mugu production workflows already called the current name (only a stale comment mentioned the old one, left as-is). `expand_consensus_candidates()` -- a different kind of deprecation, a superseded design pathway with its own teaching workflow rather than a plain rename -- deliberately left untouched. `devtools::test()` 0 failures, `devtools::check()` 0 errors/0 warnings/1 pre-existing environmental note. |
| 2026-07-20 (Sonnet 5) | `evaluate_likelihoods(min_rank_trust_pvalue=)` removed; `$likelihoods` no longer has `trusted_rank`/`rank_trust_basis` | TaxaLikely | **Supersedes the two rows above adding this mechanism** (2026-07-19). `trusted_rank` was found to be computed off `evaluate_likelihoods()`'s own top-LIKELIHOOD hypothesis, not necessarily the hypothesis that wins the POSTERIOR once TaxaExpect priors are applied downstream -- confirmed a real ~30% mismatch rate on the real 12S PtConception dataset, plus a second cancellation bug where `posterior_consensus()`'s own downranking step could silently reverse a correct upranking. `absolute_fit_pvalue` itself (the per-row one-sided fit p-value everything was built on) is UNCHANGED and still computed on every row -- only the ladder-walk-to-a-trusted-rank built on top of it is gone. `posterior_consensus(uprank_trust_pvalue=)` and `add_posthoc_assessment()`'s `"unsupported_rank"` category (both added the two rows above) were updated the same day to read `absolute_fit_pvalue` directly off the winning row instead -- see `TaxaAssign/CLAUDE.md`'s and `TaxaFlag/CLAUDE.md`'s own same-day notes for those two changes; `winner_trusted_rank`/`winner_rank_trust_basis`/`trusted_rank_col` are correspondingly stale references in those two rows above, not live behavior. `devtools::test()` 0 failures, `devtools::check()` 0/0/1 (pre-existing environmental note). See `TaxaLikely/CLAUDE.md`'s top session note and `[[project_job2_unreferenced_relatives]]` for the full record. |
| 2026-07-20 (Sonnet 5) | `expand_consensus_candidates()` removed entirely (not just deprecated) | TaxaLikely | **Breaking**, but no real callers left anywhere in the monorepo or the two real external Mugu/PtConception production workflows (confirmed by grep before deleting). Deprecated since Session 99 in favor of `unreferenced_candidates()` + `assign_scores()`; same "no external users yet" reasoning as the row above. Deleted `R/expand_consensus.R` (its only function), `tests/testthat/test-expand-consensus.R`, and its own dedicated teaching workflow `inst/workflows/expand_consensus_demo.R`. Fixed one stale cross-reference in `compute_likelihoods()`'s own roxygen. `devtools::test()` 0 failures, `devtools::check()` 0 errors/0 warnings/1 pre-existing environmental note. |
