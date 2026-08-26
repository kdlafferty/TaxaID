# CLAUDE.md — TaxaAssign
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-08-26 (Fable 5, branch undetected-evidence-mixture -- join_priors()'s
# Session-117 modelled-species floor promotion SCOPED BY CAUSE, Phase 1 of the
# undetected-evidence mixture redesign (design spec:
# ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md; motivating
# evidence: the 2026-08-26 GreatLakes upranking review, REVIEW_fable_conservative_
# upranking.md in the GreatLakes data dir). The old blanket condition (`has_model <-
# !is.na(alpha)` + below-singleton-mean) promoted EVERY joined prior row below the
# singleton-mirror mean to exact singleton parity -- including every
# TaxaExpect::apply_undetected_evidence() evidence_blend row and every
# generate_domestic_food_priors() row, whose sub-singleton theta is the DESIGN, not an
# artifact. Verified consequence on real GreatLakes2023 data before fixing: posteriors
# reduced to pure normalized likelihood ratios (Ictaluridae example reproduced to 3
# decimals from likelihoods alone), consensus output byte-identical across a 4x d_half
# sweep (the decay parameters were dead code in effect), 3,326 candidate rows promoted.
# New condition: (a) evidence-derived rows (undetected_type == "evidence_blend",
# model_tier tier_undetected_evidence/tier_domestic_food) are NEVER promoted; (b)
# modelled rows are promoted only on a genuine habitat mismatch (observed_in_habitat
# explicitly FALSE -- the rule's actual Session-117 motivating case: habitat-conditional
# extrapolation collapsing theta toward 0), never for a genuinely low in-habitat
# estimate (real rarity signal); (c) priors carrying no observed_in_habitat column at
# all keep the old blanket behavior (backward compatible -- all pre-existing tests pass
# unchanged). Supporting changes: the habitat-agnostic fallback tier now also carries
# model_tier/undetected_type provenance onto rescued rows (so a rescued domestic row is
# recognizable at promotion time), and coarse-rank expansion's override_cols gains
# model_tier/observed_in_habitat (so expanded rows carry their own species' provenance,
# not the template's NAs). New roxygen @section "Modelled-species floor (scoped by
# cause)". 5 new tests in test-join_priors.R (evidence row never promoted; rescued
# domestic row not promoted; habitat-mismatch row promoted; in-habitat low-theta row
# NOT promoted; no-column blanket fallback retained). devtools::test() 670 passed/0
# failed (up from 664), devtools::check() 0/0/0, reinstalled and live-verified against
# the real GreatLakes2023 checkpoints via the review's ablation harness: promotion count
# 3,326 -> 112 rows; species-resolved observations 33 -> 103 (6 -> 12 unique species,
# 9/12 corroborated by the independent Lamar pipeline); the d_half sweep now changes
# real output (121 observations differ at d_half=75), confirming the graded evidence
# design finally reaches the posterior. NOT yet done (Phase 2+, see the reentry doc):
# w-as-P(present) semantics, moment-matched n_eff, mixture-aware compute_posterior()
# sampling, invasive w recalibration (w=0.6 still blocks yellow perch/round goby --
# expected at this phase), adjust_inat_range_priors() conversion to an evidence
# generator, soft confirmation update.
# Previous update, 2026-08-20 (Sonnet 5 -- join_priors() gains a new habitat-agnostic
# named-species prior fallback tier, closing a real production gap confirmed on real
# GreatLakes2023 data: TaxaExpect::generate_domestic_food_priors() rows carry
# main_habitat = NA by design (a food/domestic species has no single correct habitat --
# its plausibility is governed by human food supply, not local habitat suitability, and one
# grid_id can span several real habitats) but the primary composite-key join
# (taxon_name, taxon_name_rank, grid_id, main_habitat) requires an EXACT match, so such a
# row could never join against a real observation's own (non-NA) habitat -- silently falling
# back to the generic dark-diversity floor instead of the tailored prior computed for it.
# Confirmed with real numbers before fixing, not assumed: a real Gadus morhua domestic-food
# row (alpha=5, beta=8775, theta ~= 0.00057) never matched; the affected observation's
# applied prior came out theta ~= 0.000167 instead (~3.4x lower). New fallback tier
# (right after the primary join, before coarse-rank expansion) re-matches any row whose
# primary join failed on (taxon_name, taxon_name_rank, grid_id) alone against
# main_habitat = NA taxaexpect_priors rows -- ranked below a real per-habitat match (which
# always wins when one exists) and above the dark-diversity/global-floor fallback. When more
# than one habitat-agnostic row exists for the same key (e.g. two independent evidence
# sources naming the same species), the strongest (highest theta_mean) is used, matching
# this function's own final-dedup convention, rather than an ambiguous many-to-many join.
# Paired fix: TaxaExpect::generate_domestic_food_priors() also had taxon_name_rank unset
# entirely (a second, independent reason the same rows never matched) -- see
# TaxaExpect/CLAUDE.md's own top session note. Found while cross-session-collaborating on a
# parallel prior-mechanism design (regional-proximity/invasive-watch-list evidence,
# ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md) that needed the identical
# habitat-agnostic-row pattern; tracing why the cited precedent (generate_domestic_food_
# priors()) "already handled this" surfaced that it didn't. General primitive, not a
# food-specific patch -- reusable by any future habitat-agnostic evidence source (the
# regional-proximity/invasive-watch mechanism itself was judged to legitimately want to STAY
# habitat-AWARE, unlike food -- a freshwater species found nearby is only plausible in a
# freshwater habitat locally, a real physical constraint food doesn't have -- so this tier is
# available to it, not automatically used by it). 5 new tests in test-join_priors.R (rescue
# on primary-join failure; a real per-habitat match still wins; multiple habitat-agnostic
# rows for one taxon collapse to the strongest; a habitat-agnostic row at a DIFFERENT
# grid_id is never applied; the applied-count message). New `.ha_theta_mean` global-variable
# declaration (internal grouping column). devtools::test() 664/664 (up from 655),
# devtools::check() 0 errors/0 warnings/0 notes. Reinstalled via ecosystem_docs/install_all.R,
# verified against the installed copy directly (not just the reinstall exit status).
# Previous update, 2026-08-07 (Sonnet 5 -- second full code + domain review response, against a
# fresh inst/taxaassign_review.Rmd (20 files, dozens of line-specific comments; distinct from
# and later than the 2026-08-04 review below). Findings and fixes recorded in the new
# inst/taxaassign_review_response.md. Two real bugs found and fixed, both via direct empirical
# verification, not just reasoning from the code: (1) update_prior_from_consensus()'s final
# attr(out, "report_params") <- list(...) OVERWROTE (not merged with) whatever report_params
# the input result already carried -- since run_llm_pipeline()'s .run_consensus_and_report()
# always calls this function before generate_report(), every real LLM-pipeline report's
# Methods text silently fell back to hardcoded defaults (e.g. "sharpness parameter = 0.1")
# instead of the real assign_taxa_llm() values actually used (score_sharpness,
# unknown_lik_weight, score_threshold, top_n), for every real run, not an edge case. Fixed via
# utils::modifyList() (merge, not overwrite). (2) .find_nearest_grid() (site_utils.R) used
# plain Euclidean distance in (lat, lon) degree-space, which over-weights longitude
# differences away from the equator (a degree of longitude is cos(latitude) times shorter than
# a degree of latitude) and can silently select the wrong "nearest" grid cell -- fixed with a
# cosine-latitude-corrected (equirectangular) distance; confirmed via a constructed
# counterexample at 60N that the two formulas genuinely disagree on the nearer cell. Also
# restructured so .find_nearest_grid() returns the distance it already computes internally,
# so .latlon_to_grid() no longer recomputes the identical calculation a second time.
#
# Real, previously-undocumented production landmine closed: compute_group_priors()'s default
# rank_cols changed from c("genus","family") to c("species","genus","family"), with "species"
# auto-derived as taxon_col's own identity when taxonomy_map has no explicit species column.
# posterior_consensus()'s group_priors lookup is keyed on (lca$rank, lca$taxon), and most real
# consensus calls resolve at species rank -- the old default produced zero rank=="species" rows,
# so consensus_has_occurrence_record read FALSE (not NA) for the vast majority of real calls
# purely from this gap (the exact 504/616 real Mugu "unprecedented" false-positive bug from the
# 2026-07-30 session below). The fix that shipped at the time was a manual per-workflow shim
# (taxonomy_map$species <- taxonomy_map$taxon_name, still present verbatim in the real
# MuguFishWorkflow.R) rather than a package default change, reasoned at the time as "trivially
# expressible via the existing mechanism, not worth a new package-level case." This session's
# reviewer independently flagged the same landmine on sight with no access to that history
# ("should rank_cols have a default?") -- exactly the discoverability risk that reasoning
# under-valued. Purely additive; an explicit "species" column or omitting "species" from
# rank_cols both still override it.
#
# Also: join_priors()'s site = list(main_habitat = ...) now auto-fills coordinates from
# attr(taxaexpect_priors, "search_center") (set by TaxaExpect::build_priors()) instead of
# hard-erroring when only main_habitat is supplied and coordinates are already known;
# .resolve_llm_fn()'s known "silently degrades under fully-namespaced calls" footgun (already
# documented in this file's own Known R Footguns, Session 123) now emits a real cli_warn() at
# the point it becomes likely, rather than only being documented; generate_report()/
# report_assign() both gain an optional workflow = "bayesian"/"llm" override for the
# column-presence-guessing workflow auto-detection (default NULL preserves old behavior);
# add_slash_taxon() switched from positional to name-based lookup into plausible_posteriors
# (a NAMED vector keyed by taxon_name, not just positionally aligned with plausible_taxa) --
# closes a real, if latent, desync risk the review's own "could the list-column order get
# corrupted?" question raised, since positional indexing was silently discarding an
# already-available self-describing structure. expand_unreferenced_hypotheses() (the
# TaxaAssign-side deprecated forwarding wrapper) removed entirely -- confirmed zero real
# callers use the qualified TaxaAssign:: name (every real external workflow uses the bare,
# unqualified name, which now resolves directly to TaxaLikely::expand_unreferenced_hypotheses()
# via the normal search path with no behavior change). New test-site_utils.R (32 tests, 0
# prior coverage for any of these internal helpers). Several TaxaID/CLAUDE.md cross-references
# in error messages/roxygen (unreachable to an end user installing TaxaAssign standalone)
# replaced with pointers to TaxaTools::verify_taxon_names()'s own docs. 13 @examples blocks
# rewritten from broken (referencing files that don't exist anywhere in the monorepo, e.g.
# TaxaMatch's nonexistent match_obj.rds) or \dontrun{}-hidden to genuinely runnable --
# verified by devtools::check() actually executing them, not just visual inspection.
# devtools::test() 655/655 (0 failures, up from 615), devtools::check() 0 errors/0 warnings/0
# notes, reinstalled and verified against the installed copy directly (not just the reinstall
# command's exit status). See inst/taxaassign_review_response.md for the complete file-by-file
# record, including ~9 items considered and explicitly declined with reasoning (e.g. NOT
# requiring TaxaTools as a hard Imports dependency; NOT unifying join_priors()'s and
# .resolve_site()'s two independently-evolved, overlapping site-resolution code paths, a real
# duplication found but judged too risky to consolidate in a single review-response pass).
# Previous update, 2026-08-04 (Sonnet 5 -- TaxaAssign's first full code + domain review against
# inst/Code and Domain Review 2.Rmd, closing the one remaining gap in this ecosystem's review
# coverage (TaxaTools/TaxaFetch/TaxaMatch/TaxaLikely/TaxaExpect all already had one). No
# functionality bugs found -- this package had already been through many rounds of ecosystem-
# wide correctness fixes (see the session notes below). Findings were style/consistency/
# documentation only, all fixed: (1) base R stop()/warning()/message() used inconsistently
# with the package's own declared `cli` Imports convention -- 5 files (site_utils.R,
# run_bayesian_pipeline.R, build_context.R, group_priors.R, report_assign.R) used base calls
# exclusively (most strikingly, run_bayesian_pipeline.R and run_llm_pipeline.R had the
# identical backbone_id validation check written with stop() in one and cli::cli_abort() in
# the other), plus a handful of stray base calls in otherwise-cli files (compute_posterior.R,
# posterior_consensus.R x2, join_priors.R, slash_taxon.R); all 31 converted to cli::, with
# every substring an existing expect_error()/expect_warning() regex checks verified preserved
# before editing. (2) A ~15-line LLM-prompt "Context:" block was independently triplicated
# verbatim across assign_taxa_llm.R's .build_taxa_prompt() and suggest_unreferenced_species.R's
# .build_plausible_prompt()/.build_family_prompt() (differing only in one field name); extracted
# to a new shared .build_context_block() helper in site_utils.R. (3) compute_posterior.R's
# internal rtruncnorm_at_zero(n, mean, sd) shadowed base::mean/stats::sd as parameter names --
# not an active bug (never called internally), but exactly the base-R-collision class this
# review's own template asks to check for; renamed to mu/sigma. (4) A latent packaging bug
# (not introduced this session, but blocking): 4 multi-line @importFrom roxygen blocks
# (assign_taxa_llm.R x2, join_priors.R, suggest_unreferenced_species.R) are a hard error under
# the locally installed roxygen2 8.0.0 (tolerated by older versions) -- silently aborted
# devtools::document() partway through; split into single-line tags, same fix pattern
# TaxaExpect's own 2026-07-31 review already applied to an identical issue in that package.
# devtools::test() 615/615 unchanged (0 failures; 13 pre-existing informational warnings, 1
# pre-existing skip, both unchanged -- no test asserted on exact message wording beyond the
# substrings preserved). devtools::check() 0 errors/0 warnings/0 notes. Reinstalled to
# ~/Library/R/4.0/library. See inst/taxaassign_review.Rmd for the full record.
# Previous update, 2026-07-30 (Sonnet 5 -- consensus_prior redesigned from a candidate-scoped
# MAX to a real group-level SUM, closing out Task 1 of TaxaFlag/REENTRY_PROMPT_axes_wrapup.md
# (deferred at the end of the 2026-07-28 session below). New exported
# compute_group_priors(taxaexpect_priors, taxonomy_map, rank_cols = c("genus","family"))
# (R/group_priors.R) aggregates theta_mean to genus/family by finite additivity (records are
# mutually exclusive across taxa, so a group's true share is the exact sum of its locally
# modelled members' shares -- no independence assumption, unlike a noisy-OR combination).
# posterior_consensus() gains a new optional group_priors param (a compute_group_priors()
# result); when supplied, consensus_prior is now the SUM of theta_mean across every group
# member with a real occurrence record (was: MAX among candidates actually surfaced for one
# observation -- a materially different, weaker statement, since a single observation's
# candidate set rarely contains every locally-modelled group member). consensus_prior is
# NA_real_ (not a candidate-scoped fallback) when group_priors is NULL or has no matching row
# -- the MAX fallback was deleted entirely per explicit user instruction ("delete the
# backwards compatibility to max").
#
# Real production bug found and fixed the same day, via live Mugu testing (not caught by the
# test suite): consensus_prior's NA meant TWO different things once the MAX fallback was gone
# -- "checked, no local record" (real absence) vs. "group_priors never supplied at all"
# (unknown) -- and add_posthoc_assessment()'s consensus_plausibility inferred presence from
# consensus_prior's NA-ness alone, so EVERY observation read "unprecedented" the moment
# group_priors was wired into a real workflow (confirmed: 100% of 616 real Mugu rows). Fixed
# with a dedicated presence column, consensus_has_occurrence_record (mirrors the existing
# winner_has_occurrence_record pattern at primary scope exactly): NA when group_priors was
# never supplied or the LCA rank/taxon is NA; TRUE/FALSE from a real lookup otherwise. See
# TaxaFlag/CLAUDE.md's matching note for the consuming-side fix and
# [[project_axis1_consensus_prior_group_priors]] in the TaxaID memory system for the full
# debugging record, including two FURTHER real bugs found only via live end-to-end Mugu
# testing after this fix shipped: (1) TaxaAssign itself had never actually been reinstalled
# after this exact source change landed earlier the same session -- devtools::install() had
# never been re-run, so consensus_has_occurrence_record was live in source but absent from
# the installed package the user was testing against; caught by a direct smoke test showing
# the column missing from real posterior_consensus() output, not by inference. (2)
# compute_group_priors()'s own rank_cols default (c("genus","family")) has no species-rank
# concept at all -- wiring a genus/family-only group_priors into a real workflow made
# consensus_has_occurrence_record read FALSE (not NA, since group_priors WAS supplied) for
# every SPECIES-rank consensus_taxon, the vast majority of real calls, producing 504/616 real
# "unprecedented" false positives including common local species (Leptocottus armatus, Mugil
# cephalus, Oncorhynchus mykiss...). Not a package fix -- resolved at the WORKFLOW level (a
# species-rank identity-aggregation row added to the taxonomy_map passed into
# compute_group_priors(), not a change to the function's own default) since the right
# species-rank behavior is "sum over one member = itself", trivially expressible via the
# existing rank_cols mechanism rather than a new package-level case.
#
# Real-data verification (MuguFishWorkflow.R, live end-to-end re-run, not just source
# review): consensus_plausibility went 100% unprecedented -> 504/616 (Bug B found) -> 7/616
# (Bug B fixed) -> reintroduced to 7/616 by a THIRD, independent real bug (Urolophus
# halleri/Urobatis halleri backbone disagreement between match-side and prior-side
# taxonomy -- a full backbone-architecture review, not just a patch; see
# TaxaID/CLAUDE.md's own 2026-07-30 note on the NCBI-common-backbone decision) -> 4/616 final
# verified state (519 expected / 93 unexpected / 4 unprecedented, the 4 being genus-level
# taxa already flagged as genuinely suspect in earlier project investigation, not a bug).
# group_priors wired into all 5 real production posterior_consensus() calls that feed
# add_posthoc_assessment() (2 Mugu + 3 PtConception workflows, outside this monorepo, not
# under git) -- only MuguFishWorkflow.R live-verified end to end; MuguWilderFishWorkflow.R has
# the identical fix but has not yet been re-run; the 3 PtConception workflows have the fix
# applied but have not been run at all this session (no cache found newer than mid-July).
# devtools::test() 615/615 (0 failures), devtools::check() 0 errors/0 warnings/0 notes.
# Reinstalled to ~/Library/R/4.0/library (this time actually verified via a direct smoke test
# of the installed package's own output, not just the reinstall command's exit status --
# see Bug A above for why that distinction mattered this session).
# Previous update, 2026-07-28, later (Opus 5 -- posterior_consensus() gains two columns
# supporting Axis 1 (occurrence plausibility): winner_has_occurrence_record (logical) and
# consensus_prior (numeric). Same split as Axis 2 -- numerics here, categorical in
# TaxaFlag::add_posthoc_assessment().
#
# The load-bearing design point, from the user's own definition ("unprecedented = a taxon
# that has never been reported; a singleton is NOT unprecedented even though it may have
# the same prior value"): record presence and prior VALUE are different signals and
# neither substitutes for the other. Verified on real Mugu data before designing --
# 0 of 1014 floor-prior rows carry a model_tier, but 547 rows carry NO tier yet a prior
# ABOVE the floor, one reaching 0.975 because its dark-diversity group had only three
# members. Thresholding the prior value alone would have called that never-reported taxon
# "expected". Hence winner_has_occurrence_record as an explicit signal rather than a lower
# cutoff. (model_tier is populated only for taxa with a real occurrence record; a
# dark-diversity or floor fallback leaves it NA. Also confirmed: tier3_undetected never
# lands on a named taxon -- 0 rows -- as the old reentry doc claimed.)
#
# consensus_prior is the HIGHEST prior among candidates that both carry an occurrence
# record AND fall inside the consensus taxon; NA when none do, so NA doubles as the
# consensus-scope never-reported signal and no second presence column is needed. MAX is
# deliberate, not convenience: the question is "is this GROUP expected here", and a group
# is expected if any member is -- max is the tightest valid lower bound on P(at least one
# member present) without assuming independence. A sum would double-count shared
# occurrence evidence; a mean would dilute a common member with its rare congeners. This
# is explicitly NOT the mass-conserving hierarchical prior over a coarse taxon that
# TaxaExpect does not yet provide (see [[project_dark_diversity_redesign]] Issue 3) -- it
# is a best-member statement and is documented as such, per the previous reentry doc's own
# warning not to build a fake consensus-taxon prior to unblock this work.
#
# Real full-dataset verification: 616 observations in 1.3 s. 14 primary-scope and 11
# consensus-scope unprecedented. devtools::test() 567 pass / 0 fail; devtools::check()
# 0 errors / 0 warnings / 0 notes. Reinstalled.
# Previous update, 2026-07-28 (Opus 5 -- winner_absolute_fit_pvalue REMOVED from
# posterior_consensus(), following TaxaLikely's removal of the underlying
# absolute_fit_pvalue column. See [[project_absolute_fit_pvalue_retired]] in the TaxaID
# memory system for the audit that drove it (written BEFORE the removal, at the user's
# request, so the decision can be revisited). Purely a pass-through column with no
# behavior attached, so nothing else in this package changes. The surviving
# winner_*_confusion_risk pass-throughs are unaffected and keep the identical
# optional-upstream-output contract. devtools::test() 567 pass / 0 fail (down from 574 --
# the 7 removed are that column's own tests); devtools::check() 0 errors / 0 warnings /
# 1 note (pre-existing environmental timestamp). Reinstalled.
# Previous update, 2026-07-27 (Opus 5 -- posterior_consensus() gains three additive columns
# implementing Axis 2 of the add_posthoc_assessment() axes redesign (see
# TaxaFlag/REENTRY_PROMPT_axis2_multifactor_diagnostic_redesign.md, whose top now carries a
# FALSIFIED banner for the `Ds`/`P` plan these columns replace). Axis 2 asks two questions, and
# the existing winner_*_confusion_risk pass-throughs can only answer the first:
#   1. Could a relative have looked this good?      -> *_confusion_risk
#   2. Did any plausible relative actually compete? -> the new counts
# A confusion-risk value describes the marker's discriminating power for a taxon in the
# abstract and never sees this observation's candidate set, so on its own it cannot distinguish
# "won a real contest" from "won by default because nothing locally plausible was ever in the
# running" -- the latter being a reference-database representation gap that no threshold on the
# existing candidates can detect (the real Sciaenidae/ASV_382 case that motivated this).
#
# NEW COLUMNS (all additive, present in the main path and in .empty_consensus_row()'s NA
# fallback; no signature change, no new parameter, no new data input):
#  - consensus_confusion_risk: the same confusion-risk quantity, rank-matched to
#    consensus_rank rather than to primary_taxon's own rank (which is what
#    winner_own_rank_confusion_risk reports). When the LCA has climbed to genus or family the
#    species-level value answers the wrong question. Differs from winner_own_rank on 72/606
#    real rows, so the rank-matching does real work rather than duplicating an existing column.
#  - primary_n_plausible_competitors / consensus_n_plausible_competitors: how many
#    locally-plausible RIVAL candidates actually competed.
#
# THREE DESIGN POINTS, deliberate -- do not "fix" without re-reading:
#  (a) "Plausible" is read off `model_tier` (supplied upstream by join_priors() from TaxaExpect
#      priors), NOT off prior_mean's value. A taxon never reported locally has model_tier = NA
#      while a genuine singleton has a real tier, even though both can share the same numeric
#      floor prior -- which is exactly the Axis-1 "a singleton is not unprecedented" distinction,
#      and prior_mean alone cannot express it. This is also why no new join/param/network call
#      was needed: the signal is already on the post-join_priors rows.
#  (b) Counted over every NAMED hypothesis (pre-min_posterior/cumulative_threshold), not the
#      post-filter plausible set -- a candidate that competed and lost still competed. Mirrors
#      consensus_posterior's own documented precedent for using named_all.
#  (c) The row's OWN taxon is excluded from its count (assistant's call, flagged to the user for
#      review). Whether the winner itself is plausible is a prior-side question already answered
#      by winner_prior; keeping the two independent is the point of the axes redesign. So a
#      count of 0 means "nothing plausible to lose to", never "the winner is implausible".
#
# REAL-DATA VERIFICATION (the full real 616-observation MuguWilderFish posteriors object, all
# three markers, via the real all_posteriors_r2 checkpoint): 1.4 SECONDS for 616 observations --
# negligible added overhead, which was an explicit user requirement for the PtConception
# workflows. 58% of observations won with zero plausible rivals. The counts discriminate the
# investigation's own anchor cases unprompted: ASV_371 (Salmonidae) and ASV_382 (Sciaenidae) --
# both flagged by the user as "why was no local congener proposed here?" -- come back with 0
# plausible rivals, while the Gobiidae the user confirmed as genuinely plausible
# (ASV_363/430/463) each have 1. A cross-tab of Axis 2 tier x rival count surfaces a cell no
# single column could: 77 real observations are `discriminating` AND had 0 rivals (looks clean,
# never actually competed).
#
# Axis 2 tier names/breaks settled with the user: < 0.05 `discriminating` / 0.05-0.5 `weak` /
# >= 0.5 `indistinguishable`. Both breaks are interpretable statements about a genuine one-sided
# tail probability rather than fitted cutoffs, and both populate well on all three markers (12S
# species 15/31/54%, 16S 14/44/42%, COI 33/9/58%). NOTE the polarity runs OPPOSITE to the
# earlier goodness_of_fit tiers -- here HIGH = worse.
#
# 9 new tests in test-posterior_consensus.R (108 in that file, up from 99). devtools::test() 574
# pass / 0 fail; devtools::check() 0 errors / 0 warnings / 0 notes. Reinstalled to
# ~/Library/R/4.0/library. NOT done: the TaxaFlag categorical column that would consume these
# (names approved, but which column drives it and whether it replaces the existing
# confusion_risk_flag were left as a real decision rather than a guess -- the user explicitly
# warned against column inflation); no workflow rewired; nothing re-run end to end.
# Previous update, 2026-07-23, later same day (Sonnet 5 -- renamed posterior_consensus()'s
# winner_species_support/winner_genus_support/winner_family_support/winner_own_rank_support ->
# *_confusion_risk, matching the same-day TaxaLikely/TaxaFlag renames -- see TaxaID/CLAUDE.md's
# top session note for the full cross-package record. Pure rename, no math changed. The note
# below (same day, earlier) describes the original implementation and now uses the corrected
# names throughout.
# Previous update, 2026-07-23 (Sonnet 5 -- implements both tasks of ecosystem_docs/REENTRY_PROMPT_
# score_support_posthoc_and_rank_thresholds.md (full cross-package record in TaxaID/CLAUDE.md's
# top session note). Task 1: posterior_consensus() gains winner_species_confusion_risk/
# winner_genus_confusion_risk/winner_family_confusion_risk/winner_own_rank_confusion_risk, mirroring the existing
# winner_absolute_fit_pvalue pass-through pattern exactly (read from the winning row, NA when
# TaxaLikely::evaluate_likelihoods()'s new species_confusion_risk/genus_confusion_risk/family_confusion_risk/
# own_rank_confusion_risk columns are absent from posterior_df, present in both the main result path
# and .empty_consensus_row()'s NA-filled fallback). Task 2: score_consensus(rank_thresholds=)
# loses its Session 147 GITA/Jonah Ventures default entirely -- now a required argument, no
# default, errors immediately if omitted, mirroring join_priors(backbone_id=)'s exact
# missing()/cli::cli_abort() precedent (Session 143) rather than continuing to ship a
# plausible-looking but potentially-wrong universal constant (this function has no way to know
# what marker/data type score_col was scored against). The error message points at two options:
# supply real thresholds directly, or derive marker-specific ones via the new
# TaxaLikely::compute_rank_thresholds() (per-rank Youden's J on a real seq_matrix -- see that
# package's own top session note). Passing rank_thresholds = NULL explicitly still means
# "disable rank capping" unchanged, since that's an explicit value, not an omission. Real
# call-site survey (already done in the reentry doc) turned out to need less fixing than
# flagged: both TaxaAssign_llm_workflow.R calls (score_con_wilder/score_con_JV) already passed
# rank_thresholds = NULL EXPLICITLY, so neither actually relied on the removed default and
# neither needed a code change -- only one bare score_consensus(match_df) call in
# vignettes/taxaid-ecosystem.Rmd and ~20 test-file call sites (mostly testing gap/whitelist/LCA
# behavior unrelated to rank capping, needed rank_thresholds = NULL added explicitly to keep
# exercising what they actually test) were updated. devtools::test() 0 failures (256, up from
# 255), devtools::check() 0 errors/0 warnings/0 notes. Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-20 (Sonnet 5 -- posterior_consensus() loses uprank_trust_pvalue and
# the winner_trusted_rank/winner_rank_trust_basis pass-through columns entirely, one day
# after they were added (see the Session 2026-07-19 note directly below for the original
# design). winner_absolute_fit_pvalue is UNCHANGED and still present -- only the
# rank-changing action (uprank_trust_pvalue) and the two columns sourced from
# TaxaLikely::evaluate_likelihoods()'s now-removed trusted_rank/rank_trust_basis are gone.
# Root cause, found by the user pressure-testing the mechanism against their own real 12S
# run rather than trusting the prior session's validation numbers: winner_trusted_rank was
# computed upstream for evaluate_likelihoods()'s own top-LIKELIHOOD hypothesis for a query
# -- not necessarily the same hypothesis that ends up winning the POSTERIOR here, once
# TaxaExpect occurrence priors are multiplied in. A live diagnostic
# (~/My Drive/Rscripts/eDNA/PtConception/diagnose_trusted_rank_mismatch.R, written this
# session, kept in place for future reuse) run against the user's real posteriors_updated/
# consensus_final objects confirmed this concretely: of 1120-1122 real observations where
# winner_trusted_rank read coarser than consensus_rank (looking, on the surface, like
# uprank_trust_pvalue should have fired), only ~30% were genuine likelihood/posterior-
# winner mismatches (real Sardinops sagax examples, winner_absolute_fit_pvalue ~0.43,
# comfortably clearing any tested threshold -- the flag was describing a DIFFERENT
# hypothesis, e.g. Sardinops ocellatus, that had briefly led on raw likelihood before
# losing on prior). The remaining ~70% turned out to be a SECOND, independent problem: even
# when uprank_trust_pvalue genuinely fired and broadened species -> genus correctly,
# `species_reference`'s own downranking post-processing step (already documented,
# Session 149) could immediately narrow it right back down whenever the locally-plausible
# reference showed only one species in that genus -- two individually reasonable
# mechanisms cancelling each other out, confirmed via the real `downranked` column. The
# fix the user proposed and this session implemented: `winner_absolute_fit_pvalue` alone
# (already correctly anchored to whichever row is the REAL posterior winner here, with no
# ladder-walk to go stale) is sufficient for a downstream consumer to flag weak evidence --
# see TaxaFlag::add_posthoc_assessment()'s new `absolute_fit_pvalue_col`/
# `weak_evidence_pvalue` design (same-day note in that package's CLAUDE.md), which replaces
# the rank-comparison logic entirely rather than trying to fix the two-mechanism
# interaction. `devtools::test()` 556/556 (0 failures), `devtools::check()` 0/0/0.
# Reinstalled to `~/Library/R/4.0/library`. See
# [[project_rank_trust_mechanism_removed]] in the TaxaID memory system for the full
# investigation, including the diagnostic script and the worked real-data numbers.
# `winner_absolute_fit_pvalue` alone (no H2/H3 pass-through) was confirmed sufficient
# for TaxaFlag's own downstream flagging need -- no further pass-through columns planned
# here.
# Previous update, 2026-07-19 (Sonnet 5 -- posterior_consensus() gains an opt-in
# uprank_trust_pvalue param (default 0 = off) plus three pass-through columns
# (winner_absolute_fit_pvalue/winner_trusted_rank/winner_rank_trust_basis), consuming
# TaxaLikely::evaluate_likelihoods()'s new rank-trust mechanism (see TaxaLikely/CLAUDE.md's
# top session note). Grew directly out of the user asking whether the LCA/disagreement-based
# uprank mechanism already covered this: worked through it and confirmed the two are mostly
# DISJOINT, not overlapping -- LCA upranking needs >1 plausible hypothesis to find
# disagreement among, so it structurally cannot act when a single hypothesis wins outright
# (n_plausible=1), which is exactly the case a weak, absolute-likelihood-poor match can win
# by default with nothing to compete against. uprank_trust_pvalue targets specifically that
# gap. Default `0` is a threshold, not a boolean (a p-value is never < 0), matching this
# codebase's existing convention (ratio_threshold=0, evidence_max_ratio=1 as no-op defaults)
# rather than adding a separate on/off flag -- the user's own suggestion. When the winning
# hypothesis's own absolute_fit_pvalue is below the threshold, consensus_taxon/consensus_rank
# are broadened to winner_trusted_rank (new consensus_reason = "trust_upranked") -- but ONLY
# when that is coarser than what LCA already produced, so this can only make a call more
# conservative, never less. Deliberately a PARTIAL decoupling from TaxaLikely's own
# min_rank_trust_pvalue, documented as such: this parameter gates a binary act/don't-act
# decision using the winner's raw absolute_fit_pvalue, but WHERE to broaden to still comes
# from winner_trusted_rank as already computed upstream -- not a fully independent re-walk of
# the rank ladder (would need every hypothesis's own p-value passed through, not just the
# winner's). Default 0/off, per this ecosystem's established "default-safe, opt-in-aggressive"
# pattern (same reasoning as apply_coverage_constraints()'s Session 151 constraint_behavior
# default change) -- changing actual reported output on an under-tested threshold (validated
# on only 2 real datasets so far) is a bigger commitment than the informational TaxaFlag
# annotation path (see TaxaFlag/CLAUDE.md), which stays the safer default. 17 new tests in
# test-posterior_consensus.R (100 total, up from 83 in that file); devtools::test() 565/565 (0
# failures), devtools::check() 0/0/0. Reinstalled to ~/Library/R/4.0/library.
#
# REAL-DATA VALIDATION, same session: reconstructed a real posterior_df (join_priors() +
# compute_posterior(), n_sims=0) from the real PtConMifishSchulte checkpoints (13,442 real
# observations) plus a fresh full evaluate_likelihoods() run carrying the new rank-trust
# columns (186s for the full dataset). Confirmed join_priors()/compute_posterior() both
# pass extra columns through unchanged, as documented (no plumbing gap in practice, not
# just in theory). Swept uprank_trust_pvalue in {0, 1e-4, 0.001, 0.01, 0.05}: the target
# scenario (n_plausible=1, winner_absolute_fit_pvalue poor) is genuinely rare on real data
# -- 0.00% at 0.0001/0.001 (both are complete no-ops on this dataset), rising to only
# 0.06%/0.10% at 0.01/0.05 (9/14 of 13,442 real observations). Zero false positives across
# all 24 real "prior-orphaned high-confidence match" observations (Ovis aries, Salmo
# salar, etc. -- see [[project_edge_case_error_taxa_design]]) at every threshold tested.
# At 0.05, the real upranked cases include a genuinely new finding: 8 real observations
# previously reported as Urocyon cinereoargenteus/Canis lupaster (real terrestrial canids)
# at SPECIES level in this marine 12S survey (absolute_fit_pvalue ~ 0.002-0.004),
# correctly coarsened to "Canidae"; plus 3 species->genus and 2 species->family
# corrections among real fish taxa. Wired into PtConceptionWorkflow_12S_single_site.R at
# uprank_trust_pvalue = 0.01 (both posterior_consensus() calls, including the pass feeding
# update_prior_from_consensus() -- an actively-upranked row correctly gets is_resolved =
# FALSE there, so it's excluded from the confirmed-species donor pool rather than wrongly
# boosting other observations' priors on under-supported evidence). Reconstruction
# deliberately simplified (no expansion_taxonomy/singleton_taxonomy -- coarse-rank H2/H3
# placeholder rows fall back to the dark-diversity floor instead of full named-species
# expansion; does not affect specific_candidate rows, which is where this mechanism's
# real value concentrates) -- disclosed, not hidden, as a real scope limitation of this
# validation pass.
# Previous update, 2026-07-13 (Session 153 -- real bug found and fixed while debugging
# PtConceptionWorkflow_12S.R against this ecosystem's recent breaking changes:
# update_prior_from_consensus()'s Session 149 alpha/beta-consistency fix (which recomputes
# prior_alpha/prior_beta to match a boosted prior_mean, preserving the original Beta
# concentration) didn't clamp the boosted prior_mean away from the [0,1] boundary before
# deriving the new alpha/beta. A confirmation quantile of exactly 1.0 -- common in practice,
# since posterior_consensus() legitimately returns consensus_posterior = 1.0 for any
# unambiguously resolved single-candidate donor observation -- produced
# new_beta = (1 - 1) * phi = 0, which compute_posterior() correctly rejects ("N row(s) have
# non-positive or non-finite prior_alpha/prior_beta"). This is a real regression introduced
# by the Session 149 fix itself: the previous design never touched prior_alpha/prior_beta at
# all (that omission was the bug Session 149 fixed), so this boundary case didn't exist
# before. Fix: clamp the boosted prior_mean to [1e-9, 1-1e-9] before deriving new_alpha/
# new_beta (new_prior_mean itself is left unclamped -- 1.0 is a legitimate point estimate;
# only the Beta-shape derivation needs the clamp), mirroring the identical boundary-guard
# pattern join_priors.R's own .make_ab() helper already uses for the same reason. 1 new
# regression test reproduces the exact failure (a confirmation quantile of 1.0 must not
# zero out prior_beta) and confirms compute_posterior() accepts the result at both
# n_sims = 0 and n_sims > 0 (the Monte Carlo path is what the real failure surfaced on).
# devtools::test() 548/548 (0 failures, up from 544), devtools::check() clean.
# Previous update, 2026-07-12 (Session 152 -- real bug found and fixed via a full end-to-end live
# run of inst/TaxaID_Workflow_Template_TEST.R (part of debugging the Template against the
# ecosystem's recently-updated functions): posterior_consensus()'s internal
# .extract_rank_values() had a genus-from-binomial fallback but no equivalent species-from-
# taxon_name fallback. Whenever the input posterior_df had no explicit "species" column --
# exactly TaxaLikely's real sequence/BLAST pathway's shape (only taxon_name/family/genus,
# never a literal "species" column) -- consensus_posterior/consensus_confidence_score
# silently computed to exactly 0 for every single-hypothesis resolved observation, even
# though the winning candidate's own posterior_mean was correctly high (observed: 0.999,
# 0.938, 1.0 for the three real Template test observations, all reported as
# consensus_posterior = 0). consensus_taxon itself was unaffected -- .find_lca()'s
# nrow(plausible) == 1 shortcut reads taxon_name/taxon_name_rank directly, a different code
# path -- which is exactly why this went unnoticed: the final assigned taxon always looked
# right, only the confidence columns were silently wrong. Also a real, separate test-coverage
# gap: no test in test-posterior_consensus.R asserted on consensus_posterior's VALUE at all
# before this session, only on consensus_taxon/consensus_rank/is_resolved -- despite most of
# that file's own mock fixtures also omitting an explicit species column, so the bug's own
# exact trigger condition was already present throughout the existing suite and still went
# uncaught. Fix: added a species branch to .extract_rank_values() mirroring the existing
# genus derivation (derive species = taxon_name when taxon_name_rank == "species", prefer an
# explicit species column's non-NA values when present). 2 new regression tests added,
# directly reproducing the real Template data's exact shape and confirming
# consensus_posterior now equals the winner's posterior_mean instead of 0.
# devtools::test() 544/544 (0 failures), devtools::check() 0 errors/0 warnings/0 notes.
# Previous update, 2026-07-10 (Session 150 -- expand_unreferenced_hypotheses() moved to TaxaLikely
# (package-placement fix, not a math change); TaxaAssign::expand_unreferenced_hypotheses() is now
# a thin .Deprecated() forwarding wrapper. See TaxaID/CLAUDE.md's Session 150 note for the full
# reasoning. devtools::test() 522/522 (0 failures; count differs from Session 149's 544 because
# ~17 tests moved to TaxaLikely, not because coverage was lost), devtools::check() clean.)
# Previous update, 2026-07-09 (Session 149 -- compute_posterior() Monte Carlo fixes, prompted by
# the ecosystem statistical soundness review (ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_
# REVIEW.md): (1) likelihood draws now sampled from an exact truncated-normal via a new
# embedded rtruncnorm_at_zero() helper instead of rnorm()+clamp-to-0, removing a spurious
# point mass at exactly 0 that wasn't part of the modelled distribution; (2) the J-shaped-Beta
# simulation override widened from prior_alpha < 1 to <= 1, catching the real, non-negligible
# (~14-20% of bundled fixture rows) exact-alpha-1 case (e.g. TaxaExpect's global-floor
# Beta(1, N_total-1)) that the old strict cutoff missed. Both are behavioral, no signature
# change. 2 new regression tests confirmed to fail against the pre-149 logic before being
# added. devtools::test() 544/544 (up from 539), devtools::check() 0/0/0. See this file's own
# Session 149 note below for the full record, including what's deliberately left open (whether
# the alpha boundary should extend further -- needs a larger real prior_alpha distribution than
# the bundled fixtures to decide with evidence rather than a guess).
# Session 147 -- fifth parameter-audit punch-list family (score
# floors: score_consensus::min_score, assign_taxa_llm::score_threshold). New
# diagnostics/score_floor_roc_sweep.R gives this family something the earlier ones lacked: REAL
# ground truth, not a resolution-rate proxy -- every pair in the real 12S seq_matrix reference
# data has known species/genus/family identity on both sides, so TPR (within-species) and FPR
# (congeneric/confamilial/cross-family) at each percent-identity threshold are actual
# classification metrics. Finding: TPR and FPR_congeneric track almost identically from
# threshold 70 to 96 (e.g. at 90: TPR=1.000, FPR_congeneric=0.991) -- raw percent-identity score
# alone cannot discriminate a species from its closest congener at almost any real-world
# threshold, directly confirming and sharpening the ecosystem's own prior "Framing B verdict"
# memory ("100% rule unreliable at congeneric level") at the specific parameter level.
# score_threshold=80/min_score=0 both turn out fine for what they actually do (coarse
# cross-family pre-filtering; assign_taxa_llm()'s LLM prior and score_consensus()'s
# rank_thresholds are what do the real species-level discrimination) -- but pursuing that second
# half surfaced a real, higher-stakes gap, not just an unvalidated default: score_consensus()'s
# rank_thresholds defaulted to NULL, so a caller with no explicit override got ZERO score-based
# species-vs-congener protection, silently. Fixed: rank_thresholds now defaults to the
# conventional GITA/Jonah Ventures thresholds c(species=98, genus=95, family=90, order=85),
# auto-rescaled by /100 if score_col looks like a 0-1 proportion scale rather than 0-100 percent
# identity (matching the `if (max(x) > 1) treat-as-percent else treat-as-proportion` convention
# already used in TaxaLikely's .normalize_scores()/assign_scores()/
# restore_suppressed_candidates()$delta -- confirmed via search before implementing, not
# invented fresh). Verified this doesn't break existing behavior: walked every real call site
# and every score_consensus() test manually before running them -- all either explicitly
# override rank_thresholds already, or use synthetic scores high enough (>=97) that the new
# default's capping never actually engages (rank_thresholds only ever demotes an LCA that's
# FINER than what the score justifies, never promotes one that's already coarser) --
# devtools::test() confirmed 539/539 unchanged, devtools::check() 0 errors/0 warnings/1
# pre-existing NOTE (unrelated clock-check artifact), vignettes rebuilt clean. Also fixed an
# adjacent, unrelated TaxaWizard metadata bug found while updating rank_thresholds' JSON entry:
# min_score's documented default was 80, but the real function default is 0.
# Session 146 -- fixed the silent LLM-response-truncation risk
# assign_taxa_llm() Session 145 surfaced (not a punch-list item itself, but a real,
# higher-stakes finding hit along the way: 4/5 real 30-taxon batches truncated at
# call_api()'s default max_tokens=3000, silently falling back to uniform priors with only a
# warning). Two changes: (1) .parse_taxa_response() now detects the truncation signature
# specifically (response has no closing "]" at all) and gives an actionable warning naming the
# real cause and two concrete fixes, instead of the old generic "failed to parse" message --
# verified directly against both a synthetic truncated response and a synthetic
# complete-but-malformed one, confirmed each hits the intended branch. (2) taxa_per_call's
# default lowered assign_taxa_llm() 30->15 (also propagated to run_llm_pipeline(), which
# forwards it, and to the real example call in TaxaAssign_llm_workflow.R) -- corroborated by
# discovering TaxaFlag::review_assignments() had independently hit and fixed the identical
# failure mode in an earlier session with the same 30->15 change, so this isn't just one
# session's single real trial. suggest_unreferenced_species() still defaults taxa_per_call=30L
# and was deliberately NOT changed -- it batches genera with a simpler response shape, and the
# same risk wasn't confirmed for it this session (flagged for a future check, not assumed).
# devtools::check() 0 errors/0 warnings/0 notes, 539 tests unchanged.
# Session 145 -- empirical sensitivity check for the fourth
# parameter-audit punch-list family: assign_taxa_llm()'s score_sharpness, unknown_lik_weight,
# prior_phi, absent_detection_prob. Unlike Session 143/144's targets, these four are consumed
# upstream of compute_posterior() (baked into score_likelihood/prior_alpha/prior_beta), not a
# downstream filter -- but all four turned out to be deterministic post-processing on
# already-fetched LLM output, so no LLM re-call was needed per sweep grid point. Small
# behavior-preserving refactor first: extracted the merge/rescale/Beta-construction block
# (previously inline in assign_taxa_llm()) into new internal helper .merge_llm_priors()
# (R/assign_taxa_llm.R) so it can be re-run cheaply against a fixed LLM response;
# devtools::test() unchanged (539 passing) confirming no behavior change. No usable real
# assign_taxa_llm()/run_llm_pipeline() checkpoint existed anywhere in the repo or the eDNA data
# tree (every real workflow there uses the Bayesian pathway) -- ran assign_taxa_llm()'s real
# LLM-call stage once for real (5 Anthropic API calls, 499 real PtConception 12S observations,
# 143 unique taxa; script not committed, see scratchpad note in
# diagnostics/llm_prior_shape_sweep.R's header) and checkpointed the pre-merge intermediates.
# Hit and fixed two real snags getting that one real run to work: (1) TaxaTools's LLM provider
# auto-detection doesn't activate in a plain Rscript session even with library(TaxaTools)
# loaded (confirmed directly -- getOption("TaxaID.provider") stayed NULL); worked around with
# an explicit provider argument, not investigated further since it's a TaxaTools-level gap,
# out of scope here. (2) call_api()'s default max_tokens=3000 truncated 4/5 real 30-taxon-batch
# JSON responses (the one 23-taxon batch succeeded) -- confirmed this is a REAL, not
# hypothetical, risk of the documented default taxa_per_call=30; worked around locally with
# max_tokens=8000, not promoted to a fix in assign_taxa_llm()/call_api() itself (flagged for a
# future punch-list pass, not fixed this session). Finding, once a clean real checkpoint
# existed: these four parameters mostly shape CONFIDENCE (consensus_posterior), not WHICH taxon
# wins (pct_resolved was flat within ~1.5 points across every grid tested). unknown_lik_weight
# has the largest real effect (mean winning posterior 0.997->0.911 sweeping 0.01->0.20).
# score_sharpness had almost no effect (0.9922->0.9936 across the full 0-1 range) -- the LLM
# prior is doing nearly all the discriminating work, as intended. prior_phi: a flat scalar
# (5-80) matched the tiered default's resolution/confidence almost exactly -- a real, still-open
# question about whether the tiered complexity earns its keep, not resolved this session.
# absent_detection_prob: tested via a disclosed SYNTHETIC known_absent overlay (no real
# ecosystem workflow currently supplies known_absent) -- no aggregate effect detected, but this
# is the weakest/most diluted result of the four (5/143 taxa affected across 499 observations),
# not a validated finding either way. Findings written into assign_taxa_llm()'s own @details
# section. devtools::document()/test() clean throughout. Reclassified in the audit table
# (GROUND_TRUTH -> DOCUMENT) per user's choice to document rather than dig deeper on any of the
# open questions (flat-vs-tiered phi, absent_detection_prob dilution) this session.
# Session 144 -- empirical sensitivity check for
# posterior_consensus()'s min_posterior/cumulative_threshold defaults (0.05/0.90), the second
# item on the parameter-audit punch list after Session 143's backbone_id work. Reconstructed a
# real posterior_df (44,442 rows / 13,483 observations) offline from PtConception 12S
# checkpoints (Step 7a.5 through compute_posterior(), no live GBIF/DECIPHER calls, a modest
# number of TaxaTools::verify_taxon_names() calls for taxonomy gaps) via a one-off
# reconstruction script (session-local, not committed -- see scratchpad note in
# diagnostics/posterior_threshold_sweep.R's header). New diagnostics/posterior_threshold_sweep.R
# grid-sweeps min_posterior x cumulative_threshold against a 3,000-observation real subsample
# (subsampled after the full-13,483/56-grid-point sweep proved too slow for this session's
# background-task setup -- twice interrupted at ~15-17 min; the subsampled sweep finished in
# 215s and produces the same qualitative picture). Finding: the two defaults are NOT equally
# load-bearing. min_posterior does real, roughly linear work (sweeping 0->0.20 at the
# cumulative_threshold default moves resolution rate by +8.2 points); cumulative_threshold does
# comparatively little independent work once a reasonable min_posterior floor exists (sweeping
# 0.70->0.99 at the min_posterior default moves resolution by only -3.3 points, and
# non-monotonically -- more "conservative" values don't cleanly increase caution). The two
# interact sharply only in the unrealistic min_posterior=0 + cumulative_threshold=0.99 corner
# (resolution craters to 57.9%), confirming the documented interaction mechanism is real but not
# a practical risk at the shipped defaults. Explicitly caveated in both the roxygen and here:
# this sweep measures resolution RATE (how often the pipeline commits to a finest-rank call),
# not ACCURACY (whether that call is correct) -- no ground-truth-validated observation set was
# available, so this closes the "is there a citable empirical characterization" gap the
# parameter audit flagged (GROUND_TRUTH -> DOCUMENT) without claiming the defaults are proven
# optimal. Findings written into posterior_consensus()'s own @details "Threshold interaction"
# section (not duplicated here beyond this summary). devtools::document() clean. join_priors()'s
# mirrored expansion_min_prior/expansion_cumulative_prior params were deliberately NOT touched
# this session (user's choice) -- still flagged GROUND_TRUTH in the audit table, open for later.
# Session 143 -- backbone_id no longer has a silent default anywhere
# it's actually used for taxonomy reconciliation. join_priors() gains a new required
# backbone_id param (no default, errors if omitted), replacing a hardcoded, un-overridable
# backbone_id = 4L inside its taxonomy-fallback fill. posterior_consensus()'s backbone_id
# default changed from 11L to NULL (errors only when lookup_missing_taxonomy = TRUE and
# backbone_id is omitted -- lazy, since most callers never touch that path).
# run_bayesian_pipeline()/run_llm_pipeline()'s backbone_id lost its 4L default entirely and is
# now required (errors immediately if omitted), since both forward it unconditionally into
# join_priors()/posterior_consensus(). Prompted by a parameter audit flagging the 4L vs 11L
# default mismatch between run_bayesian_pipeline() and posterior_consensus() as a possible
# correctness bug; traced first and confirmed it was NOT live (run_bayesian_pipeline() always
# explicitly forwards its own backbone_id through .run_consensus_and_report() into
# posterior_consensus(), so posterior_consensus()'s own default was never actually reached
# through that call path) -- but the user's design call was that no function reconciling
# input taxonomy against an external backbone should have a silent default at all, since the
# correct backbone depends on which backbone the caller's own input data used and this varies
# by project. TaxaTools::fill_higher_ranks()/escalate_taxonomic_rank() were evaluated against
# the same rule and deliberately left with their existing 4L/11L primary/fallback defaults,
# since that pair is a resolution strategy (try NCBI, then GBIF as cross-check) rather than an
# assumption about the input data's own backbone. All ~15 real in-repo call sites (vignettes,
# workflow scripts, TaxaWizard snippets + metadata) and all test call sites updated to pass
# backbone_id explicitly; devtools::check() 0 errors/0 warnings/1 pre-existing NOTE, 539 tests
# passing. Found and flagged (not fixed, out of scope) a pre-existing, unrelated bug while
# here: TaxaWizard's inst/metadata/TaxaAssign.json join_priors entry uses param names
# (likelihoods_df/priors_df/grid_id/main_habitat) that don't match the real signature
# (likelihoods/taxaexpect_priors/site) at all.
# Session 138 — multi-site posterior combination. join_priors()'s
# final distinct() call is now grid_id/main_habitat-aware, fixing a real bug where a
# multi-site observation had each candidate cherry-pick its own best site instead of being
# joined against the site it was actually detected at. New combine_multisite_priors()
# combines the resulting per-site prior rows via precision-weighted logit combination (not
# a plain product of means, and not raw Monte Carlo simulation -- both were shown empirically
# to fail to discount a low-confidence site relative to a well-supported one). See Session
# 138 note below. Session 134 — update_prior_from_consensus() gains a spatial_group_map
# param to skip single-observation spatial groups, see Session 134 note below. Session 129 — camera_trap_posterior_workflow.R
# added: first real TaxaAssign run for the camera-trap image species set, real GBIF priors,
# calibrated-vs-old-default posterior comparison)

---

## Package Purpose
Implements Bayesian taxonomic assignment by combining likelihood and prior objects to
compute posterior probabilities. Final step in the TaxaID pipeline. Designed to accept
any conforming likelihood and prior objects — inputs may come from TaxaMatch/TaxaExpect
or be user-supplied from outside the ecosystem.

**Status: Thirteen working functions (10 core + 3 wrappers/utilities). All planned functions removed — superseded by inline workflow logic or existing function internals.**

---

## The Bayes Step

1. Normalize likelihoods *within* `observation_id` across all competing hypotheses (sum to 1)
2. Multiply normalized likelihood × prior
3. Normalize product to produce posterior (sum to 1 per `observation_id`)
4. Optional Monte Carlo path: sample likelihoods from Normal(mean, sd), priors from Beta(alpha, beta); propagate both sources of uncertainty into posterior

---

## Function Inventory

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `adjust_inat_range_priors()` | Elevate `prior_alpha`/`prior_beta`/`prior_mean` to Tier 2 singleton-mirror floor for unmodelled taxa confirmed `in_range = TRUE` by iNaturalist geomodel with sufficient observation coverage. Adds `inat_range_elevated` column. Guard: no elevation when singleton floor ≤ current prior. | Complete | R/adjust_inat_range_priors.R |
| `compute_posterior()` | Core Bayes update: likelihood × prior → posterior | Complete | R/compute_posterior.R |
| `compute_group_priors()` | **2026-07-30.** Aggregates `theta_mean` (occurrence-model share) to genus/family (or any `rank_cols`) by SUM over locally modelled members with a real occurrence record -- finite additivity, no independence assumption, since a compositional share's group total is exact by construction. Builds the `group_priors` lookup `posterior_consensus(group_priors = ...)` consumes for a genuinely group-level `consensus_prior`. See this file's own top session note for the full derivation and two real bugs found wiring it into production (the never-reinstalled-package bug, and the missing-species-rank bug). **2026-08-07: default `rank_cols` changed from `c("genus","family")` to `c("species","genus","family")`** -- `"species"` is auto-derived as `taxon_col`'s own identity when `taxonomy_map` has no explicit `species` column, closing the missing-species-rank landmine at the package level instead of requiring every caller to hand-add a `taxonomy_map$species <- taxonomy_map$taxon_name` shim (as the real `MuguFishWorkflow.R` still does). Purely additive; pass an explicit `species` column or omit `"species"` from `rank_cols` to override. | Complete | R/group_priors.R |
| `combine_multisite_priors()` | **Session 138.** Combines `join_priors()`'s per-site prior rows for a single observation detected at more than one real site (e.g. the same eDNA ASV recovered at two different sample sites) into one row per candidate, via precision-weighted combination in logit space: `logit(Beta(a,b))` has exact mean `digamma(a)-digamma(b)` and variance `trigamma(a)+trigamma(b)`; combining with inverse-variance weighting discounts a sparse/low-confidence site relative to a well-supported one. The combined Beta's own concentration is derived from the pooled logit variance (large-phi delta-method approx), so `compute_posterior()`'s existing Beta-sampling MC path needs no changes. Adds `n_sites_combined` and `combined_sites` (pipe-delimited `grid_id` list, `NA` for single-site rows); `grid_id`/`main_habitat` set to `NA` on combined rows. Single-site observations pass through unchanged. Insert between `join_priors()` and `compute_posterior()`. | Complete | R/combine_multisite_priors.R |
| ~~`expand_unreferenced_hypotheses()`~~ | **Removed (2026-08-07).** Moved to `TaxaLikely::expand_unreferenced_hypotheses()` (Session 150); the TaxaAssign-side `.Deprecated()` forwarding wrapper was removed entirely in the 2026-08-07 review response -- zero real callers used the qualified `TaxaAssign::` name, so bare/unqualified calls now resolve directly to the TaxaLikely function via the normal search path. Use `TaxaLikely::expand_unreferenced_hypotheses()` directly. | Removed | (was R/expand_unreferenced.R) |
| `suggest_unreferenced_species()` | LLM-first unreferenced species detection: plausible species per genus → reference-check → unreferenced vector; optional family expansion. data_type param ("eDNA"/"acoustic"/"image") routes to NCBI queries (eDNA) or set-membership check vs reference_species (acoustic/image). | Complete | R/suggest_unreferenced_species.R |
| `assign_taxa_llm()` | LLM-shortcut pipeline: score-based likelihoods + LLM priors → posteriors. **Session 145:** merge/rescale/Beta-construction step factored into new internal `.merge_llm_priors()` helper (deterministic, no LLM calls -- enables cheap re-sweeping against a fixed LLM response). Empirical sensitivity findings for `score_sharpness`/`unknown_lik_weight`/`prior_phi`/`absent_detection_prob` in its own `@details`. | Complete | R/assign_taxa_llm.R |
| `posterior_consensus()` | LCA-based consensus from posterior dataframe; one row per `observation_id`. **Session 149:** adds `winner_hypothesis_type`/`winner_rank_expanded` columns -- `winner_rank_expanded = TRUE` flags a species-level `consensus_taxon` that was decided entirely by occurrence-prior mass among `join_priors()`-manufactured `"rank_expanded"` candidates sharing one inherited likelihood, not by real sequence/image/acoustic evidence. **2026-07-19 (removed 2026-07-20):** added `winner_absolute_fit_pvalue`/`winner_trusted_rank`/`winner_rank_trust_basis` pass-through columns + opt-in `uprank_trust_pvalue` param, broadening `consensus_taxon`/`consensus_rank` when the winner's own absolute fit was poor. `winner_trusted_rank`/`winner_rank_trust_basis` and `uprank_trust_pvalue` were removed the next day -- found unreliable on real data (the underlying `trusted_rank` was computed for a different hypothesis than the one that actually wins the posterior here ~30% of the time) and separately prone to being silently reversed by `species_reference`'s own downranking step. `winner_absolute_fit_pvalue` remains, unchanged, as the column downstream consumers should use directly (see `TaxaFlag::add_posthoc_assessment()`'s `absolute_fit_pvalue_col`). See this file's own top session note. **2026-07-23:** gains `winner_species_confusion_risk`/`winner_genus_confusion_risk`/`winner_family_confusion_risk`/`winner_own_rank_confusion_risk` -- same optional-pass-through contract as `winner_absolute_fit_pvalue`, sourced from `TaxaLikely::evaluate_likelihoods()`'s new score-only, model-independent `*_support` columns (LOWER = stronger evidence). See `TaxaLikely/CLAUDE.md`'s matching note. **2026-07-30:** gains `winner_has_occurrence_record`/`consensus_prior`/`consensus_has_occurrence_record` (Axis 1 support) and a new optional `group_priors` param (see `compute_group_priors()` above) -- `consensus_prior` redesigned from a candidate-scoped MAX to a real group-level SUM; `consensus_has_occurrence_record` added as a dedicated presence signal since `consensus_prior`'s own `NA`-ness cannot distinguish "checked, absent" from "never checked" (`group_priors` not supplied). See this file's own top session note for the full record. | Complete | R/posterior_consensus.R |
| `add_slash_taxon()` | Appends `slash_taxon_name` (ornithological slash-species notation; NA for singletons/unresolved) and `irreducible_consensus` (TRUE when the candidate set can't be further decomposed elsewhere in the dataset) to `posterior_consensus()` output. **Session 123:** when `consensus_taxon` is present, also adds `consensus_OTU` (single reporting label — `slash_taxon_name` when non-NA, else `consensus_taxon`) and `primary_taxon` (`consensus_OTU` reduced to one taxon by dropping everything after the first `/` or ` + `) — logic previously hand-duplicated identically in 3 real workflows. | Complete | R/slash_taxon.R |
| `score_consensus()` | Conventional score-based consensus (min_score, max_gap, rank_thresholds, whitelist); one row per `observation_id`. **Session 147:** `rank_thresholds` default changed `NULL` → `c(species=98, genus=95, family=90, order=85)` (the conventional GITA/JV thresholds) after an ROC sweep against real 12S reference data showed `min_score`/`max_gap` alone provide essentially no species-vs-congener discrimination -- a caller with no explicit `rank_thresholds` previously got zero protection against confusing a species with its congener. Auto-rescales by /100 if `score_col` looks like a 0-1 proportion scale. Pass `rank_thresholds = NULL` to restore old behavior. **2026-07-20:** fourth tier relabeled `order` → `phylum` -- the literature this 85% value is corroborated by (Ransome et al. 2017 and others, per `ecosystem_docs/AQUARIUM_BENCHMARK_DESIGN.md`) treats it as a phylum-level cutoff, not order-level; no genuine order-level COI threshold exists to substitute in. Numerically identical, label-only fix. **2026-07-23:** `rank_thresholds` loses its default entirely -- now required, no default, errors immediately if omitted (mirrors `join_priors(backbone_id=)`'s precedent). No single fixed threshold set is safe to assume since this function has no way to know the marker/data type. Error message points at supplying real thresholds directly or deriving marker-specific ones via the new `TaxaLikely::compute_rank_thresholds()`. Pass `rank_thresholds = NULL` explicitly to disable rank capping (unchanged meaning). | Complete | R/score_consensus.R |
| `update_prior_from_consensus()` | Boost priors for confirmed species in unresolved samples; re-run `compute_posterior()`. **Session 134:** optional `spatial_group_map` param (`observation_id`/`spatial_group_id`) restricts both the confirmation source and the update target to observations sharing a `spatial_group_id` with >= 1 other observation (a multi-member spatial group) -- observations in a single-observation spatial group (whether a genuine single observation or one that fell outside a drawn group, per `TaxaMatch::group_observations_by_bbox()` -- there's no separate naming for these, just a singleton group) are always returned unchanged, since another unrelated observation's confirmed presence says nothing about them. **Session 149:** the fixed `presence_multiplier` (removed) replaced by `confirmation_quantile`/`min_confirmation_confidence` -- for each confirmed species, the confirmation_quantile-th quantile (default 0.9) of confirming donors' `consensus_posterior` substitutes for `prior_mean` (never lowering it) only when it clears `min_confirmation_confidence` (default 0.8, set to 0 to disable). `prior_alpha`/`prior_beta` are now recomputed consistently with a boosted `prior_mean` (preserving the original concentration), fixing a latent inconsistency with `compute_posterior()`'s Monte Carlo path. | Complete | R/update_prior_from_consensus.R |
| `build_context()` | Auto-populate `ctx` (ecoregion, main_habitat, date) from taxon names via TaxaHabitat + LLM synthesis | Complete | R/build_context.R |
| `generate_report()` | Publication-ready Methods + Results text; hybrid template (Methods) + LLM (Results) with template fallback. **2026-08-07:** gains optional `workflow = "bayesian"\|"llm"` param overriding the column-presence-based workflow auto-detection (default `NULL` preserves old behavior). | Complete | R/generate_report.R |
| `join_priors()` | Bridge likelihoods to priors: join TaxaExpect priors with dark diversity fallback, fill taxonomy, filter redundant hypotheses. `site` requires `main_habitat` — accepts `list(lat, lon, main_habitat)` or `list(grid_id, main_habitat)` or multi-site data frame. Modelled species with habitat-mismatch priors promoted to dark diversity floor. **Session 108:** unmodelled species (never detected) now fall back to the `global_floor` row (Beta(1, N_total-1)) rather than the site-level dark mean. **Session 109:** `expansion_taxonomy`, `expansion_min_prior` (default 0.05), `expansion_cumulative_prior` (default 0.90) params added. When a likelihood row has `taxon_name_rank` coarser than species (e.g. family-rank identification), and `expansion_taxonomy` is supplied (a `fill_higher_ranks()` result mapping priors species to genus/family), the coarse-rank row is replaced by species-level hypothesis rows filtered by the same cumulative-threshold logic as `posterior_consensus()`. Rows without matching species in priors fall back to dark floor. `hypothesis_type = "rank_expanded"` marks expanded rows. When `expansion_taxonomy` is NULL and coarse-rank rows are present, a warning with instructions is emitted. **Session 117:** `singleton_taxonomy` param added (optional data frame with `taxon_name` + taxonomy columns, e.g. `occurrences_std`). When supplied, unmodelled (unreferenced) candidates receive hierarchical mass-conserving group priors via `.compute_dark_diversity_groups()` (phylum→class→order→family→genus recursive descent) rather than a flat global floor. Candidates with unknown phylum (`no_phylum` group) fall back to the global floor individually. Adds three diagnostic columns to output: `dark_diversity_group` (character — taxonomy label of group), `n_singletons_group` (integer — singletons in the group), `n_undetected_group` (integer — unmodelled candidates in the group). Requires TaxaExpect >= Session 117 (`source_taxon_name` in `generate_full_priors()` output and `taxonomy` param in `generate_undetected_diversity()`). **Session 138:** the final `distinct(observation_id, taxon_name, taxon_name_rank, .keep_all = TRUE)` dedup now also keys on `grid_id`/`main_habitat`, fixing a real bug where a genuine multi-site observation (the same `observation_id` detected at more than one site) had each candidate collapse to only its own highest-`prior_mean` site — discarding the site it was actually detected at. Output is now site-preserving (one row per candidate per site); pass it through the new `combine_multisite_priors()` before `compute_posterior()` to recombine. The first `left_join()` (likelihoods → event_meta) now declares `relationship = "many-to-many"` since a multi-candidate, multi-site observation legitimately fans out on both sides. **Session 143:** new required `backbone_id` param (no default, errors if omitted), replacing a previously hardcoded, un-overridable `backbone_id = 4L` inside the taxonomy-fallback fill -- the correct backbone depends on which backbone the caller's input taxonomy was verified against. **2026-08-07:** `site = list(main_habitat = ...)` alone (no `lat`/`lon`/`grid_id`) now auto-fills coordinates from `attr(taxaexpect_priors, "search_center")` when present, instead of hard-erroring; `main_habitat` itself is still never guessed. **2026-08-20:** gains a habitat-agnostic named-species prior fallback tier -- a `taxaexpect_priors` row with a real `taxon_name` but `main_habitat = NA` (by design, e.g. `TaxaExpect::generate_domestic_food_priors()` output) now matches any observation's habitat at that `grid_id` via a dedicated fallback, instead of silently never matching the primary composite-key join at all. Fixes a real, previously-shipping gap confirmed on real GreatLakes2023 data -- see this file's own top session note. | Complete | R/join_priors.R |
| `run_bayesian_pipeline()` | High-level wrapper: TaxaLikely likelihoods + TaxaExpect priors → full Bayesian workflow (~10 calls → 1). Auto-filters errors from model_params, auto-resolves site habitat. Stage 1b: three-tier H2 phantom suppression via GBIF genus census (suppress complete, rename singleton-missing, keep incomplete). GBIF species list fed to `audit_barcode_coverage(species_list=)`. | Complete | R/run_bayesian_pipeline.R |
| `run_llm_pipeline()` | High-level wrapper: LLM-shortcut workflow (~7 calls → 1); optional auto-context + unreferenced detection + report. Optional `reference_errors` param. | Complete | R/run_llm_pipeline.R |
| `report_assign()` | Generate `report_section` summarizing taxonomic assignment (workflow type, resolution rate, posterior/score stats). For `assemble_report()`. **2026-08-07:** gains the same optional `workflow` override as `generate_report()`. | Complete | R/report_assign.R |

**Internal helpers (not exported):**

| Function | Purpose | Source file |
|---|---|---|
| `.resolve_llm_fn()` | NULL-default resolver: returns user-supplied `llm_fn`, then checks `getOption("TaxaID.llm_fn")` (set by TaxaTools `.onAttach()`), then falls back to `TaxaTools::call_anthropic_api`; clear error if TaxaTools not installed | R/site_utils.R |
| `.resolve_site()` | Site resolution: lat/lon → nearest grid_id from priors; multi-site support | R/site_utils.R |
| `.latlon_to_grid()` | Haversine nearest-grid lookup with habitat auto-selection | R/site_utils.R |
| `.run_consensus_and_report()` | Shared consensus → empirical Bayes → report helper for both pipeline wrappers | R/run_bayesian_pipeline.R |
| `.merge_llm_priors()` | **Session 145.** Merges per-observation likelihoods with LLM-derived priors, applies `known_absent` suppression + `unknown_lik_weight` rescaling, constructs Beta `prior_alpha`/`prior_beta` from `prior_phi`. Factored out of `assign_taxa_llm()`'s main body (pure post-processing on already-fetched LLM output, no LLM calls) so it can be re-run cheaply for a sensitivity sweep — see `diagnostics/llm_prior_shape_sweep.R`. | R/assign_taxa_llm.R |

---

## Function Signature

### `compute_posterior(likelihood_w_prior, n_sims = 1000)`

**Input:** dataframe, one row per hypothesis per sample. Required columns:

| Column | Type | Description |
|---|---|---|
| `observation_id` | any | Groups competing hypotheses; one unique value per observation |
| `score_likelihood` | numeric | Point estimate of likelihood for this hypothesis |
| `score_likelihood_mean` | numeric | Mean of likelihood distribution |
| `score_likelihood_sd` | numeric | SD of likelihood distribution (NA → replaced with 0 + warning) |
| `prior_mean` | numeric | Prior probability for this hypothesis |
| `prior_alpha` | numeric | Beta shape1 parameter (optional; enables Beta-distributed prior sampling) |
| `prior_beta` | numeric | Beta shape2 parameter (optional; must accompany `prior_alpha`) |

When `prior_alpha`/`prior_beta` are present, MC samples priors from `Beta(alpha, beta)` — correctly bounded [0,1]. When absent, priors are treated as fixed (no prior uncertainty in MC). `prior_sd` is no longer used (removed 2026-04-04).

Any additional columns (e.g. `taxon_name`, `rank`, `hypothesis_type`) are passed through unchanged.

**Output:** same dataframe + 4 columns, sorted by `observation_id` asc then `posterior_mean` desc:

| Column | Description |
|---|---|
| `posterior_point_est` | Deterministic posterior from point estimates |
| `posterior_mean` | Mean posterior across Monte Carlo simulations (= `posterior_point_est` if no sims) |
| `posterior_sd` | SD of posterior across simulations (= 0 if no sims) |
| `confidence_score` | Fraction of simulations in which this hypothesis had the highest posterior |

**Two computation paths:**
- **Point estimate path** — always runs; uses `score_likelihood` and `prior_mean`
- **Monte Carlo path** — runs only when `n_sims > 0` AND at least one source of uncertainty exists (non-zero `score_likelihood_sd`, or `prior_alpha`/`prior_beta` present). Likelihoods sampled from `Normal(mean, sd)` floored at 0; priors sampled from `Beta(alpha, beta)`.

**Internal helper:** `normalize_vec(x)` — normalizes vector to sum to 1; returns uniform distribution if all zeros (prevents division by zero).

---

## Function Signature: `assign_taxa_llm()`

```r
assign_taxa_llm(match_df,
                context               = NULL,
                context_group         = NULL,
                rank_system           = NULL,
                llm_fn                = TaxaTools::call_anthropic_api,
                score_threshold       = 80,
                top_n                 = 10L,
                score_sharpness       = 0.1,
                unknown_lik_weight    = 0.05,
                unreferenced_taxa     = NULL,
                known_present         = NULL,
                known_absent          = NULL,
                absent_detection_prob = 0.80,
                taxa_per_call         = 30L,
                pause_seconds         = 1,
                prior_phi             = c(high = 50, moderate = 10, low = 3),
                prior_weight_guide    = list(...),  # 7 range-status x habitat-fit ranges
                n_sims                = 1000L,
                verbose               = FALSE)
```

**Output columns** (all input columns preserved + posterior columns):
`observation_id`, `taxon_name`, `taxon_name_rank`, `hypothesis_type`, `range_status`,
`habitat_fit`, `information_quality`, `score_likelihood`, `score_likelihood_mean`, `score_likelihood_sd`,
`prior_mean`, `prior_alpha`, `prior_beta`, `posterior_point_est`, `posterior_mean`, `posterior_sd`,
`confidence_score`. Taxonomy columns from `match_df` (e.g. `family`, `genus`, `species`)
are carried through via `rank_system` detection and used by `consensus_taxonomy()`.
`hypothesis_type` values: `"specific_candidate"`, `"unreferenced_species"` (congener without barcode reference),
`"unreferenced_genus"` (family-level unreferenced taxon), `"unreferenced_family"` (catch-all; `taxon_name = NA`).
`prior_alpha`/`prior_beta` present when `prior_phi` is non-NULL.

**Key parameters:**

| Parameter | Purpose |
|---|---|
| `unreferenced_taxa` | `unreferenced_species_result` from `suggest_unreferenced_species()`; unreferenced congeners inserted per sample; `unreferenced_family` attribute activates family-level unreferenced taxon insertion |
| `known_present` | Character vector; passed to LLM as ecological context to sharpen co-occurrence and habitat reasoning — no math step |
| `known_absent` | Character vector or data frame (`taxon_name` + `detection_prob`); passed to LLM as context AND applies mathematical suppression: `prior × (1 - p_det)`, then renormalize |
| `absent_detection_prob` | Default detection probability (0.80) when `known_absent` has no per-species values |
| `score_sharpness` | Controls likelihood discrimination; higher = more weight on score differences; 0 = uniform likelihood |
| `prior_phi` | Named numeric vector mapping `information_quality` → Beta concentration (phi = alpha + beta). Default `c(high = 50, moderate = 10, low = 3)`. Scalar = uniform phi. NULL = fixed priors (no Beta sampling). |
| `prior_weight_guide` | Named list of 7 prior weight ranges guiding LLM assignments. Each element is `c(min, max)`. Keys: `native_expected`, `native_occasional`, `native_unlikely`, `nearby_expected`, `nearby_occasional_unlikely`, `not_documented`, `taxonomically_impossible`. Defaults reproduce Session 45 ranges. Customize for different ecosystems or taxonomic groups. |
| `n_sims` | Monte Carlo simulations for `compute_posterior()`. Default 1000 (changed from 0 in Session 47). |

**LLM prior prompt** asks for `range_status` + `habitat_fit` + `information_quality` + `prior_weight` per taxon.
`habitat_fit` values: `"expected"`, `"occasional"`, `"unlikely"`.
`information_quality` values: `"high"`, `"moderate"`, `"low"` — reflects how much published data
exists about the taxon's distribution in the focal region (NOT confidence in the weight itself).
Mapped to phi via `prior_phi`; alpha = prior_mean × phi, beta = (1 − prior_mean) × phi.
Prior weight scale integrates both dimensions: native+expected = 0.5–1.0; native+unlikely = 0.003–0.03.
Now user-customizable via `prior_weight_guide` parameter (Session 57).
`ctx$main_habitat` (renamed from `ctx$habitat`) is the recognized context field for site habitat;
in the full pipeline this should be populated from the `main_habitat` column produced by TaxaHabitat.
When `known_present`/`known_absent` are supplied, a "Survey context" block is prepended.

**Internal helpers:** `.score_to_likelihood()`, `.build_group_map()`, `.collect_unique_taxa()`,
`.get_group_context()`, `.build_taxa_prompt()`, `.parse_taxa_response()`.

**Family-level unreferenced taxon insertion** (in `.score_to_likelihood()`): activated when `unreferenced_taxa` carries
an `unreferenced_family` attribute (from `suggest_unreferenced_species(expand_to_family=TRUE)`). Inserts
species whose genus is absent from candidates but whose family is represented; likelihood
proxy = median exp-score of all candidates in that family.

---

## Function Signature: `posterior_consensus()` (formerly `consensus_taxonomy()`)

```r
posterior_consensus(posterior_df,
                    rank_system             = NULL,
                    cumulative_threshold    = 0.9,
                    min_posterior           = 0.05,
                    posterior_col           = "posterior_mean",
                    lookup_missing_taxonomy = FALSE,
                    backbone_id             = NULL,
                    species_reference       = NULL)
```

**Output:** one row per `observation_id` with columns: `consensus_taxon`, `consensus_rank`,
`consensus_reason`, `is_resolved`, `consensus_posterior`, `consensus_confidence_score`,
`n_plausible`, `winner_prior`, `winner_likelihood`, `winner_likelihood_cov`,
`winner_hypothesis_type`, `winner_rank_expanded`, `winner_absolute_fit_pvalue`,
`winner_species_confusion_risk`, `winner_genus_confusion_risk`, `winner_family_confusion_risk`,
`winner_own_rank_confusion_risk` (2026-07-23, see below),
`plausible_taxa` (list), `plausible_posteriors` (list).
`consensus_reason` values: `"unanimous"` (all plausible agree at finest rank), `"single"`
(only one plausible hypothesis), `"lca"` (multiple plausible, LCA at coarser rank), or `NA`.
`winner_prior` = `prior_mean` of highest-posterior hypothesis; `winner_likelihood` =
`score_likelihood`; `winner_likelihood_cov` = `score_likelihood_cov`. All three are `NA`
when the source column is absent (e.g. `assign_taxa_llm()` input) or consensus is `NA`.
**`winner_hypothesis_type`** (Session 149) = `hypothesis_type` of the winning row (e.g.
`"specific_candidate"`, `"rank_expanded"`). **`winner_rank_expanded`** = `TRUE` when that
winner came from `join_priors()`'s coarse-rank expansion (`.expand_coarse_rank_rows()`) --
meaning every candidate in that expansion inherited one identical, uninformative
likelihood from the original coarse-rank (e.g. family-level) identification, so the
species-level winner was decided entirely by occurrence-prior mass, not by any real
sequence/image/acoustic evidence. This is intentional, sound behavior (confirmed with the
user during the statistical soundness review, see
`ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`) -- the flag exists so a
downstream consumer can distinguish it from a genuinely evidence-resolved species call,
not to suppress or "fix" it.
Use these columns with `TaxaFlag::flag_prior_mismatch()` to detect implausible winners
(e.g. a low-prior taxon winning due to a reference error or sequencer 100%-rule artefact).
When `result2` from `update_prior_from_consensus()` is passed as input, also adds:
`prior_updated`, `consensus_taxon_v1`, `consensus_rank_v1`, `taxon_changed`.
When `species_reference` is non-NULL, also adds: `downranked` (logical).

**LCA logic:** all named hypotheses contribute (`specific_candidate`, `unreferenced_species`,
`unreferenced_genus`); only `unreferenced_family` catch-all (NA taxon_name) is excluded. Plausible set = top
hypotheses summing to `cumulative_threshold` of named-taxon mass, after dropping any below
`min_posterior`. Genus is derived from binomial when explicit column has NA (e.g. unreferenced rows).
`lookup_missing_taxonomy = TRUE` calls `TaxaTools::verify_taxon_names()` + `change_backbone()`
to fill family/genus/species for unreferenced rows. `backbone_id` passed through -- required
(errors) when `lookup_missing_taxonomy = TRUE`; no default, since the correct backbone
depends on which backbone the input taxonomy was verified against (Session 143).

**Renormalization note:** cumulative proportions are renormalized (post-`min_posterior` filter)
only for selecting the plausible set. The reported `consensus_posterior` is the raw sum of
posteriors within the LCA taxon from all named hypotheses (pre-filter), so it is never inflated.
**Session 152:** this sum depends on correctly matching rows to the LCA taxon via
`.extract_rank_values()`, which now derives a species value from `taxon_name` when no
explicit `species` column exists (mirroring its existing genus-from-binomial derivation) --
previously this returned all-`NA` for that common real shape (TaxaLikely's sequence/BLAST
pathway never has a `species` column), silently zeroing `consensus_posterior`/
`consensus_confidence_score` for every single-hypothesis resolved observation.

**`species_reference` (downranking):** after LCA, unresolved coarse-rank rows are downranked
when the reference contains exactly one finer taxon at each step (recursive: family → genus →
species in one pass if unambiguous at each step). Accepts either a `taxaexpect_species_df`
data.frame (Bayesian workflow) or an `unreferenced_species_result` object (LLM workflow —
uses `attr(x, "plausible")`, which includes referenced species the LLM flagged as plausible).
Conservative: stops at any rank with >1 option. `downranked = TRUE` flags changed rows.

**`winner_species_confusion_risk`/`winner_genus_confusion_risk`/`winner_family_confusion_risk`/
`winner_own_rank_confusion_risk`** (2026-07-23): pass-through of
`TaxaLikely::evaluate_likelihoods()`'s new `species_confusion_risk`/`genus_confusion_risk`/
`family_confusion_risk`/`own_rank_confusion_risk` columns for the winning row -- same optional-upstream-
output contract as `winner_absolute_fit_pvalue` (`NA` when the source column is absent from
`posterior_df`, or `consensus_taxon` is `NA`). A model-independent, score-ONLY diagnostic:
LOWER values mean STRONGER evidence for the resolved rank (a one-sided tail probability, not
the usual higher-is-better sense) -- see `TaxaLikely::evaluate_likelihoods()`'s own
`@section Confusion risk` for the full interpretation. Purely informational, never changes
`consensus_taxon`/`consensus_rank`.

**Internal helpers:** `.consensus_one_sample()`, `.find_lca()`, `.extract_rank_values()`,
`.empty_consensus_row()`, `.build_species_ref()`, `.downrank_consensus()`.

---

## Function Signature: `score_consensus()`

```r
score_consensus(match_df,
                min_score       = 0,
                max_gap         = Inf,
                whitelist       = NULL,
                score_col       = "score_original",
                rank_system     = NULL,
                rank_thresholds)
```

**Output:** one row per `observation_id` with columns: `consensus_taxon`, `consensus_rank`,
`consensus_reason`, `is_resolved`, `top_score`, `n_retained`, `n_taxa`, `retained_taxa` (list).
`consensus_reason` values: `"unanimous"`, `"single"`, `"lca"`, `"threshold"` (rank_thresholds demoted), or `NA`.
When `rank_thresholds` is non-NULL, also adds: `rank_capped` (logical).
When `whitelist` is non-NULL, also adds: `whitelist_capped` (logical).

**Algorithm:** (1) discard hits below `min_score`; (2) keep hits within `max_gap` of
top score per sample; (3) LCA of retained hits; (4) cap rank by `rank_thresholds`
(finest rank whose threshold the top score meets); (5) uprank to whitelist if consensus
taxon absent.

**`rank_thresholds` has NO DEFAULT (2026-07-23)** -- moved to the end of the signature and
required; errors immediately (`missing()` + `cli::cli_abort()`, mirroring
`join_priors(backbone_id=)`'s exact Session 143 precedent) if omitted, since this function
has no way to know the marker/data type `score_col` was scored against. Supply either your
own thresholds (e.g. the conventional GITA/Jonah Ventures
`c(species = 98, genus = 95, family = 90, phylum = 85)`, fourth tier corrected `order` ->
`phylum` 2026-07-20) or marker-specific ones derived from real reference data via the new
`TaxaLikely::compute_rank_thresholds()`. Pass `rank_thresholds = NULL` explicitly (a real
value, not an omission) to disable rank-based capping entirely.

**Reuses** `.find_lca()` and `.extract_rank_values()` from `posterior_consensus.R`.

**Internal helpers:** `.score_consensus_one()`, `.cap_rank_by_threshold()`,
`.uprank_to_whitelist()`.

---

## Function Signature: `update_prior_from_consensus()`

```r
update_prior_from_consensus(result,
                             consensus,
                             confirmation_quantile       = 0.9,
                             min_confirmation_confidence = 0.8,
                             n_sims              = 0,
                             spatial_group_map    = NULL)
```

One-pass empirical Bayes refinement. Extracts `is_resolved = TRUE` species from `consensus`
as confirmed-present evidence; re-runs `compute_posterior()` on unresolved samples only.
Resolved samples are returned unchanged. Also joins `consensus_taxon_v1` / `consensus_rank_v1`
/ `prior_updated` columns into the returned dataframe for downstream propagation by
`posterior_consensus()`.

**Confirmation-quantile boost (Session 149, replaces the old fixed `presence_multiplier`):**
for each confirmed species, take the `confirmation_quantile`-th quantile (default 0.9) of
`consensus_posterior` across all resolved donor observations naming it. If that value clears
`min_confirmation_confidence` (default 0.8; `0` disables the gate), it substitutes for
`prior_mean` in matching unresolved-observation hypothesis rows -- but only where it exceeds
the existing prior (never-demote). A high quantile behaves like a near-maximum for a small
donor pool (rewarding one strong confirmation) but, unlike a plain maximum, converges to a
stable value as the donor pool grows rather than drifting toward 1.0 regardless of whether the
evidence is real -- important specifically for a pair of species a classifier can't reliably
separate, where many weak correlated confirmations split between them would otherwise
manufacture unwarranted confidence for one or both. When `prior_alpha`/`prior_beta` are
present, they are recomputed for boosted rows too, preserving the original concentration
(`alpha + beta`) but recentering at the new mean -- fixes a latent inconsistency where only
`prior_mean` was rescaled and `compute_posterior()`'s Monte Carlo path (`n_sims > 0`) could
sample from a stale Beta shape. See `update_prior_from_consensus.R`'s own "Confirmation-quantile
design" roxygen section for the full rationale, including the deliberately-not-solved
correlated-confusion problem and the deferred quality-covariate idea it depends on.

**Circularity guard:** a sample's own posterior never feeds back into its own prior — only
other samples' confirmations are used.

**Multi-member-vs-single-observation spatial group guard (`spatial_group_map`, Session 134):**
when supplied (`observation_id`/`spatial_group_id`, e.g. from
`TaxaMatch::group_observations_by_bbox()`), only observations sharing a `spatial_group_id`
with >= 1 other observation (a multi-member spatial group) can act as a confirmation source or
receive the boost. Observations in a single-observation spatial group — whether a genuine
single observation or one that fell outside every drawn group polygon — are always returned
unchanged, same as already-resolved observations. There is no separate naming convention for
these: eligibility is determined purely by counting group membership (`table()` + `>= 2L`),
never by the id's shape or format. (Session 134b: `TaxaMatch::build_site_table()`/
`group_observations_by_bbox()` now default an ungrouped observation's `spatial_group_id` to
its own `observation_id` rather than a `"spatial_group_<n>"` string -- this function's logic
required no changes, since it was already counting membership, not pattern-matching the id.)
Without `spatial_group_map` (default `NULL`), behavior is unchanged from before Session 134:
every observation participates.

---

## Function Signature: `build_context()`

```r
build_context(taxon_names,
              geographic_hint = NULL,
              date            = NULL,
              habitat_scheme  = NULL,
              llm_fn          = TaxaTools::call_anthropic_api,
              chunk_size      = 60L)
```

Auto-populates the `context` argument for `assign_taxa_llm()` from a list of candidate taxon
names. Requires TaxaHabitat (in Suggests).

**Pipeline:** `build_habitat_prompt()` → `llm_fn()` per chunk → `parse_hierarchical_habitat_response()`
→ `consensus_habitat()` → short LLM synthesis call → one-row `ctx` data frame.

The synthesis call asks the LLM to describe the likely sampling habitat from the habitat
proportions + species list in 3-8 words. This produces more informative labels for transitional
environments (e.g. "coastal lagoon / estuary") than the mechanical argmax of habitat weights.
Falls back to the consensus argmax if synthesis parsing fails.

**Output:** one-row data frame with `ecoregion`, `main_habitat`, `date`.
`attr(ctx, "habitats_df")` = per-species habitat weight table.
`attr(ctx, "habitat_proportions")` = named numeric vector of habitat proportions.

**Internal helpers:** `.build_synthesis_prompt()`, `.parse_synthesis_response()`.

---

## Interface Contract

This is the confirmed column contract between TaxaAssign and its upstream packages.
TaxaMatch must produce these columns; TaxaExpect prior output maps as noted.

### Likelihood Object (from TaxaMatch — not yet built)

| Column | Type | Notes |
|---|---|---|
| `observation_id` | character | Unique observation identifier |
| `score_likelihood` | numeric | Point estimate likelihood |
| `score_likelihood_mean` | numeric | Mean of likelihood distribution |
| `score_likelihood_sd` | numeric | SD of likelihood distribution |

### Prior Object (from TaxaExpect `generate_full_priors()`)

TaxaExpect outputs `taxon_name`, `alpha`, `beta`, `theta_mean`, `theta_sd`.
`join_priors()` maps these to `compute_posterior()` columns:

| TaxaExpect column | Maps to | Notes |
|---|---|---|
| `alpha` | `prior_alpha` | Beta shape1; passed through via `coalesce(alpha, dark_alpha)` |
| `beta` | `prior_beta` | Beta shape2; passed through via `coalesce(beta, dark_beta)` |
| `theta_mean` | `prior_mean` | Derived: `prior_alpha / (prior_alpha + prior_beta)` |
| `taxon_name` | must join on `label` or equivalent | — |

`join_priors()` handles the likelihood–prior join, aligning on `observation_id` × taxon label
with dark diversity fallback for taxa without model predictions.

### Posterior Object (output of `compute_posterior()`)

All input columns preserved, plus: `posterior_point_est`, `posterior_mean`,
`posterior_sd`, `confidence_score`.

---

## Developer Workflow — When to Run What

| Situation | Command | Speed |
|---|---|---|
| Editing code, running `devtools::test()` inside the package | Nothing extra — `load_all()` is implicit | Fast |
| Changed roxygen docs or added/removed exports | `devtools::document()` | Fast |
| Need to use the package from another project (`library(TaxaAssign)`) | `devtools::install()` | Slow |
| Stale namespace / unexplained errors after switching branches | Restart R, then `library(TaxaAssign)` | Medium |

**Rule:** `document()` is enough when staying inside the package. `install()` is only needed when crossing the package boundary into a workflow script or another package.

---

## Key Design Notes

- Native pipe `|>` used throughout (magrittr removed from Imports in Session 37)
- S3 dispatch (`compute_posterior.point()`, `.parametric()`, `.sampled()`) is documented
  in a comment but **not implemented** — current function handles all paths internally
- `normalize_vec()` is an embedded helper (not `@noRd` tagged, but acceptable as private)
- `confidence_score` without simulation: set to 1 for the winning hypothesis, 0 for others
  (binary, not fractional)

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-compute_posterior.R | `compute_posterior()` | 12 tests: Beta prior, uncertainty propagation, MC, n_sims=0, NA handling, sort order |
| test-assign_taxa_llm.R | `assign_taxa_llm()` | LLM calls mocked |
| test-build_context.R | `build_context()` | Fully offline |
| test-combine_multisite_priors.R | `combine_multisite_priors()` | Fully offline (Session 138); includes the precision-weighted-vs-plain-product worked comparison as a regression test |
| test-group_priors.R | `compute_group_priors()` | Fully offline (2026-07-30); SUM-not-count aggregation, multi-rank output, taxa absent from the theta column excluded, empty-result-per-rank edge case |
| test-generate_report.R | `generate_report()` | Fully offline |
| test-integration.R | Full pipeline integration | Uses minimal fixtures |
| test-join_priors.R | `join_priors()` | Fully offline; Session 138 added a genuine multi-site preservation test |
| test-posterior_consensus.R | `posterior_consensus()` | Includes winner_prior/winner_likelihood/winner_likelihood_cov columns (Session 101) |
| test-report_assign.R | `report_assign()` | Fully offline |
| test-run_pipelines.R | `run_bayesian_pipeline()`, `run_llm_pipeline()` | Mocked LLM |
| test-score_consensus.R | `score_consensus()` | Fully offline |
| test-site_utils.R | `.parse_grid_ids()`, `.find_nearest_grid()`, `.build_context_block()`, `.check_rank_system_order()`, `.beta_mean()`, `.resolve_site()`, `.latlon_to_grid()` | **New, 2026-08-07.** 32 tests; these internal helpers had zero prior dedicated coverage. Includes a constructed 60N counterexample confirming the cosine-latitude distance-correction fix. |
| test-suggest_unreferenced_species.R | `suggest_unreferenced_species()` | LLM mocked |
| test-update_prior.R | `update_prior_from_consensus()` | Fully offline |

---

## Dependencies

| Package | Used for |
|---|---|
| cli | `cli_abort()`, `cli_warn()`, `cli_inform()` for user-facing messages |
| dplyr | `group_split()`, `arrange()`, `n_distinct()` |
| purrr | `map_dfr()` to apply over `observation_id` groups |
| stats | `rnorm()`, `rbeta()`, `sd()`, `setNames()`, `median()` for Monte Carlo and likelihood helpers |
| rlang | `.data` pronoun |
| TaxaTools | `verify_taxon_names()` + `change_backbone()` (Suggests; used only when `lookup_missing_taxonomy = TRUE`) |
| TaxaHabitat | `build_habitat_prompt()`, `parse_hierarchical_habitat_response()`, `consensus_habitat()` (Suggests; used only by `build_context()`) |

---

## Renaming Log

| Old Name | New Name | Date | Notes |
|---|---|---|---|
| `calculate_final_posteriors` | `compute_posterior` | 2026-02-19 | — |
| `prior_df` | `likelihood_w_prior` | 2026-02-19 | Input dataframe |
| `Query_ID` | `observation_id` | 2026-02-19 | — |
| `LR_PointEst` | `score_likelihood` | 2026-02-19 | — |
| `LR_Mean` | `score_likelihood_mean` | 2026-02-19 | — |
| `LR_SD` | `score_likelihood_sd` | 2026-02-19 | — |
| `Prior_Prob` | `prior_mean` | 2026-02-19 | — |
| `Posterior_Mean` | `posterior_mean` | 2026-02-19 | — |
| `Posterior_SD` | `posterior_sd` | 2026-02-19 | — |
| `Posterior_PointEst` | `posterior_point_est` | 2026-02-19 | — |
| `Confidence_Score` | `confidence_score` | 2026-02-19 | — |
| `ghost` (bool column) | `hypothesis_type` (character) | 2026-03-30 | Values: "specific_candidate" / "unreferenced_species" / "unreferenced_genus" |
| `habitat_affinity` | `habitat_fit` | 2026-03-30 | LLM categorical: "expected"/"occasional"/"unlikely"; distinct from TaxaHabitat's numeric habitat weights |
| `missing_species` | `unreferenced_species` | 2026-03-30 | `hypothesis_type` value; species absent from reference DB but described |
| `missing_genus` | `unreferenced_genus` | 2026-03-30 | `hypothesis_type` value; family-level unreferenced taxon or uncharacterised diversity |
| `ctx$habitat` | `ctx$main_habitat` | 2026-03-30 | Recognized context field in `assign_taxa_llm()`; aligns with TaxaHabitat/TaxaExpect column |
| `Main_Habitat` | `main_habitat` | 2026-03-30 | Site-level habitat column; ecosystem-wide rename for snake_case consistency |
| `prior_sd` (Normal) | `prior_alpha`/`prior_beta` (Beta) | 2026-04-04 | `compute_posterior()` now samples priors from Beta(alpha, beta); `prior_sd` removed. `assign_taxa_llm()` maps `information_quality` → phi → alpha/beta. `join_priors()` passes TaxaExpect alpha/beta directly. |

---

## Session Notes

**Session 149 (2026-07-09): compute_posterior() Monte Carlo fixes -- truncated-normal likelihood sampling + widened J-shape prior guard**

Prompted by the ecosystem-wide statistical soundness review
(`ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`, same day), which flagged
`compute_posterior()`'s Monte Carlo path as High priority: `posterior_consensus()` defaults
to reading `posterior_mean` (the MC mean), so this is the live winner-selection path for the
whole Bayesian pipeline, not just a confidence estimate.

Two fixes, both behavioral (no signature change):

1. **Likelihood draws are now sampled from a truncated normal, not clamped.** The previous
   `rnorm(mean, sd)` followed by `sim_lik[sim_lik < 0] <- 0` manufactured a spurious point
   mass at exactly 0 that isn't part of the modelled Normal(mean, sd) distribution -- any
   probability mass below 0 was being piled onto 0 itself rather than reflecting a genuinely
   truncated density. Replaced with `rtruncnorm_at_zero()`, a new embedded (non-exported)
   helper doing exact inverse-CDF truncated-normal sampling via `stats::pnorm`/`qnorm`/
   `runif` (no new package dependency -- deliberately avoided adding `truncnorm` to Imports
   for a three-line closed-form sampler). `sd == 0` rows remain deterministic, matching the
   old `rnorm(sd = 0)` behavior.
2. **The J-shaped-Beta simulation override widened from `prior_alpha < 1` to `prior_alpha <= 1`.**
   The exact boundary case `prior_alpha == 1` (e.g. `TaxaExpect::generate_undetected_diversity()`'s
   global-floor `Beta(1, N_total - 1)`) has the same "density strictly decreasing away from 0"
   shape that makes simulation draws unreliable for comparing tiny prior means, but was not
   being caught by the old strict `< 1` cutoff. Checked against the real (if small, 5-7 row)
   bundled fixtures (`TaxaID_test_likelihoods_w_prior*.rds`) before deciding this was worth
   fixing now rather than deferring: `prior_alpha == 1` appears in 1 of 7 and 1 of 5 rows in
   those fixtures respectively (~14-20%) -- a real, non-negligible share, not a hypothetical
   edge case. **Left deliberately unresolved:** whether the boundary should extend further
   (e.g. `prior_alpha` moderately above 1 with high relative uncertainty) -- the bundled
   fixtures are too small to characterize that continuum, and inventing a threshold without
   real data would just be swapping one unvalidated constant for another. Needs a larger real
   `prior_alpha` distribution (e.g. reconstructing Session 144's ~44k-row `posterior_df`) to
   settle with evidence rather than a guess.

Both changes are pure MC-internals changes with no parameter/column signature change, so no
call site anywhere in the ecosystem needed updating. Added 2 new regression tests to
`test-compute_posterior.R` (13 → 15 tests in this file) that specifically lock in the fixes
and were confirmed to fail against the pre-149 logic before being added (verified by
re-running the old `rbeta`/`rnorm`+clamp logic standalone: the old cutoff misses
`prior_alpha == 1` entirely, and the old clamp triggers the all-zero-likelihood
uniform-fallback warning in ~22% of 2000 simulations for a mean-near-0 test case that no
longer warns at all under the fix). `devtools::test()`: 544/544 passing (up from 539, 0
failures) -- the pre-existing 13 warnings/1 skip are unrelated informational messages,
unchanged. `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 149 continued (same day): `score_consensus()` purpose clarified -- not a bug,
a documentation gap.** Next item on the soundness-review walk-through was
`score_consensus::rank_threshold_capping`, flagged High priority because fixed
percent-identity thresholds can't reliably separate a species from its closest congener
when the congener is absent from the reference. The user's context reframed this
entirely: `score_consensus()` exists specifically to *reproduce* a conventional
fixed-threshold pipeline's decision rule (GITA/Jonah Ventures-style), so a user can
compare what a conventional pipeline would call against TaxaID's own Bayesian pathway
(`TaxaLikely` -> `compute_posterior()` -> `posterior_consensus()`) on the same data. Given
that purpose, percent-identity's known inability to discriminate species from congener
is not a defect here -- it is a faithful reproduction of the exact same limitation the
mimicked pipeline has. The review's original recommendation (gate on reference
completeness, or route through the bivariate-normal model) would have been wrong --
that would defeat the comparison this function exists to provide, and duplicate
`posterior_consensus()`'s actual job. **Fix: documentation only, no behavior change.**
Added a `@section Purpose` block to `score_consensus()`'s roxygen stating explicitly that
this is a mimicry/benchmarking tool, not TaxaID's species-level discriminator, and
reframed the existing "why `rank_thresholds` defaults to non-`NULL`" note -- the default
isn't there to make species-level calls "safe" (no such thing is this function's job),
it's there so the reproduction matches what a real conventional pipeline actually does
(every real fixed-threshold workflow has a rank-threshold step) rather than an
accidental TaxaID-only permissive default nothing real mimics. `devtools::document()`
+ `test-score_consensus.R` re-run: 51/51 passing, 0 warnings, unchanged. Soundness-review
doc updated: this row reclassified CONDITIONAL/H -> YES (Session 149 counts: 9 sound=YES
ecosystem-wide, up from 8; 14 of the original 16 H-priority rows remain open).

**Session 149 continued further (same day): domestic-species floor mitigation (see
TaxaExpect/CLAUDE.md and TaxaFlag/CLAUDE.md for the primary changes) -- join_priors()'s
"Dark diversity fallback" roxygen section gains a cross-reference to
TaxaExpect::generate_undetected_diversity()'s new documentation on the
domestic/synanthropic-species floor artifact and the recommended fix (augment occurrence
data before training). No code change in this package for this item.**

**Session 149 continued once more (same day): posterior_consensus() gains
`winner_hypothesis_type`/`winner_rank_expanded` -- flags prior-only species resolution,
per the user's explicit direction not to change the underlying behavior.**

Fourth H-priority item from the soundness review walk-through:
`join_priors::coarse_rank_expansion_credible_set` (`.expand_coarse_rank_rows()`). When a
likelihood row arrives at a coarser-than-species rank (e.g. a family-level image/sequence
ID) with no species-level match data, this function expands it into the top species-level
candidates by occurrence-prior mass -- but every expanded candidate inherits the exact
same (flat, uninformative) likelihood from the original coarse row, since there is no new
evidence to discriminate between them. The concern the review raised: `compute_posterior()`
then picks a "winner" among these purely by prior mass, and nothing downstream distinguishes
this from a genuinely evidence-resolved species call.

Walked through with the user using a concrete example (a Felidae-family-only camera-trap ID
expanded into `Lynx rufus` vs `Puma concolor`, both sharing one inherited likelihood, winner
decided by which is locally more common) before asking the design question. First round of
discussion clarified this is a *different* mechanism than TaxaMatch's existing
`filter_redundant_hypotheses()` (which already removes a genuinely redundant coarser-rank
row when a finer-rank row for the same lineage/observation already exists, called as
`join_priors()`'s very last step) -- `.expand_coarse_rank_rows()` only fires when there is
no species-level candidate at all, so there's nothing "redundant" to remove; it's
*manufacturing* species candidates from prior mass alone, not deduplicating existing ones.

**User's verdict: this is intended behavior -- flag it, don't change it.** Implemented as
two new columns on `posterior_consensus()`'s output (not a `join_priors()` change, since the
`hypothesis_type = "rank_expanded"` marker already exists at the row level from Session 109
-- what was missing was surfacing it in the final consensus output):
- `winner_hypothesis_type`: the `hypothesis_type` of the winning (highest-posterior) row,
  general-purpose diagnostic (not `rank_expanded`-specific).
- `winner_rank_expanded`: `TRUE` when that winner's `hypothesis_type == "rank_expanded"` --
  the direct, actionable flag a downstream consumer (e.g. a future TaxaFlag check, or a
  human reviewer) can filter on to know "this species-level call was a prior tie-break of a
  coarse ID, not real discriminating evidence."

Both new columns are additive (present in the main result path and in
`.empty_consensus_row()`'s NA-filled fallback) -- no existing column changed, no signature
change, fully backward compatible. 4 new tests added to `test-posterior_consensus.R`
(columns present; `FALSE` for a normal `specific_candidate` winner; `TRUE` for a
`rank_expanded` winner, using the Felidae example verified end-to-end; `NA` in the empty-row
case). `devtools::test()`: 553/553 passing (up from 544), 0 failures. `devtools::check()`:
0 errors, 0 warnings, 0 notes. Soundness-review doc updated: this row marked "flagged, not
fixed, per explicit user direction" -- still CONDITIONAL/H, since the underlying mechanism
is unchanged and intentional; the fix is visibility, not behavior change.

**Session 149 continued yet further (same day): update_prior_from_consensus() redesigned --
fixed presence_multiplier replaced by a confirmation-quantile boost, arrived at through an
extended design discussion with the user working through several candidate mechanisms and
their failure modes before settling on one.**

Fifth H-priority item from the soundness-review walk-through: the old design multiplied a
confirmed species' `prior_mean` by a flat `presence_multiplier` (default 5) in every
unresolved observation sharing a spatial group, regardless of how many observations
confirmed it or how confident those confirmations were (`confirmed_species <-
unique(...)` collapsed straight to a set of names). The user proposed and the two of us
worked through several alternatives in sequence, each rejected for a specific, checkable
reason before arriving at the final design:

1. **Max-confidence single donor** (user's opening proposal): substitute the prior with the
   most confident confirming observation's own posterior, never updating that donor's own
   prior (circularity). Confirmed circularity is a non-issue for this one-pass design by
   construction (donors are always in the *resolved* set, receivers always in the
   *unresolved* set, disjoint) -- but would need an explicit guard if this function is ever
   run iteratively.
2. **Noisy-OR combination across all donors** (`1 - prod(1 - p_i)`) proposed as a way to
   let a single strong donor dominate while still letting additional donors contribute,
   addressing max's blindness to confirmation count. **User pressure-tested this with a
   sharp hypothetical** (a classifier that structurally cannot distinguish two species A/B,
   producing many observations resolved 50/50-ish to one or the other by chance) and asked
   whether renormalization would correct for the resulting spurious accumulation. Worked
   the actual math: renormalization exactly restores 50/50 *only* in the degenerate
   exactly-two-candidate, exactly-equal-donor-count case; it does NOT hold once donor
   counts differ by chance (a real, arbitrary tilt persists) or once a third, genuinely
   unrelated candidate is present (its relative mass is deflated purely by A/B's spurious
   accumulation, confirmed numerically: a candidate's normalized share dropped from 40% to
   17% with no change to its own evidence). This ruled out naive noisy-OR/max-as-primary as
   a full fix.
3. Investigated whether a `min_donor_confidence` gate on individual donors would help
   noisy-OR -- concluded it would make noisy-OR behave *like* max when only one donor
   clears the bar, without being max, so not obviously better than just using max.
4. **User asked whether plain max already "scales with N"** (an insight prompted by real
   camera-trap experience: most images in a burst are poor, but the rare excellent one is
   what should establish presence -- correctly identified as a genuine extreme-value-theory
   property, max of k i.i.d. draws is stochastically increasing in k). Checked this
   carefully: true, but this property does NOT protect against the A/B confusion scenario
   specifically -- the same accumulation mechanism inflates both sides' max as N grows, and
   max (a single order statistic) is *more* volatile than noisy-OR's aggregate, not less,
   making it *more* exposed to one spurious extreme donor, not immune. The real fix needed
   is a way to get max's "reward one strong donor" behavior without max's degenerate
   climb-toward-1.0-regardless-of-truth behavior as N grows.
5. **User proposed a high quantile (e.g. 90th percentile) as an interim "near-max but not
   stuck on one outlier" solution.** Verified this is the right fix, with a precise
   justification: unlike the sample max (which climbs toward the support boundary as N
   grows, uninformatively, for real or spurious evidence alike), a sample quantile
   converges to the *true population quantile* as N grows (standard order-statistics
   result). For a genuinely confused A/B pair drawing from the same underlying
   confusion-noise distribution, both sides' quantile estimates converge to the *same*
   value as N grows (restoring symmetry, unlike max); for a genuinely separable species,
   its true quantile sits above the confusion-noise floor, so discriminating power is
   preserved. For small N, a high quantile behaves like max (little difference) -- which is
   fine, since that's also the lower-risk regime. Explicitly still arbitrary in *which*
   quantile to use, but a much milder arbitrariness than a multiplicative constant, since
   the qualitative behavior (bounded, convergent, not degenerate) holds across a wide range
   of reasonable choices.
6. **User then asked whether the quantile should always apply, or be gated by an absolute
   confidence floor** -- correctly identifying that never-demote alone doesn't stop a
   barely-resolved confirmation (e.g. quantile = 0.51) from injecting a large, unwarranted
   jump into a rare species' prior (e.g. 0.02 -> 0.51) just because 0.51 exceeds the old
   value. Agreed: gate on the *aggregate* quantile (simpler than filtering individual
   donors) via a new `min_confirmation_confidence` parameter, default 0.8 (placeholder, not
   empirically calibrated, same caveat as every other threshold surfaced in this review),
   disableable via `0`.

**Final design implemented:** for each confirmed species, compute
`quantile(donor consensus_posterior, probs = confirmation_quantile)` (default 0.9); only use
it if it clears `min_confirmation_confidence` (default 0.8, `0` disables); substitute it for
`prior_mean` in matching unresolved rows only where it exceeds the existing value
(never-demote). **Also fixed the latent alpha/beta inconsistency** flagged along the way: the
old code rescaled only `prior_mean`, leaving `prior_alpha`/`prior_beta` stale, so
`compute_posterior()`'s Monte Carlo path (`n_sims > 0`) could sample from the pre-boost Beta
shape while the point estimate used the boosted mean. Fixed by preserving the original
concentration (`alpha + beta`) and recentering it at the new mean for boosted rows.

**Explicitly deferred, not solved here** (documented in the function's own roxygen and
flagged for a dedicated future design thread, prompted by the user sharing Silva-Rodríguez
et al. 2025, *J. Appl. Ecol.*, a camera-trap dataset-QC protocol paper -- itself a different
layer, dataset-level audit/reporting rather than a per-detection statistical model, but
useful as evidence the underlying data-quality problem is real and recognized elsewhere): a
quantile still cannot distinguish "confidence earned by genuinely strong evidence" from
"confidence attained despite thin/low-quality input" (e.g. a short, low-coverage sequence
read producing a spuriously perfect match). That would need a quality covariate on the
underlying match scores -- connects to (and would generalize) `TaxaLikely::
evaluate_likelihoods()`'s existing but unvalidated coverage-based sigma inflation,
`TaxaMatch::bbox_coverage`, and `build_sequence_matrix()`'s coverage statistic, all flagged
separately in the soundness review. Bigger than one H-priority item; not attempted this
session.

**Signature change (breaking):** `presence_multiplier` removed entirely, replaced by
`confirmation_quantile = 0.9` and `min_confirmation_confidence = 0.8`. Propagated through
`update_prior_from_consensus()`, `.run_consensus_and_report()` (internal), `
run_bayesian_pipeline()`, `run_llm_pipeline()`, `generate_report()`'s methods-text template
(rewrote the empirical-Bayes paragraph to describe the new mechanism), both `inst/`
workflow scripts, and the `taxonomic-assignment.Rmd` vignette -- all real call sites found
via ecosystem-wide grep and updated; no residual `presence_multiplier` references remain in
executable code or user-facing docs (historical session notes/reentry prompts describing
the *old* design were deliberately left as-is, since they're a record of past state, not
current documentation). `consensus` now requires a `consensus_posterior` column (already
present in real `posterior_consensus()` output; only synthetic test fixtures needed
updating). `test-update_prior.R` rewritten with 15 test blocks covering the quantile
computation across multiple donors, the confidence gate (both engaged and disabled), the
never-demote guard, and the alpha/beta consistency fix -- each verified to exercise the
actual mechanism, not just check it runs. `devtools::test()`: 537/537 passing, 0 failures,
13 pre-existing warnings/1 skip unchanged. `devtools::check()`: 0 errors, 0 warnings, 0
notes.

**Session 138 (2026-07-05): multi-site posterior combination -- join_priors() dedup fix + combine_multisite_priors()**

Branch `single-observation-pipeline`. Implements
`ecosystem_docs/REENTRY_PROMPT_session138_multisite_posterior_combination.md` (Phase 5 of
the observation-pipeline-wiring plan). Phase 4's DNA/BLAST wiring (Session 137) made a real
multi-site single observation reachable in this ecosystem's own bundled test data for the
first time (`OQ846725`, real reads at both `sample_1` and `sample_2`); testing what
`join_priors()` actually does with such an observation found a real, currently-shipping bug.

**Bug, reproduced before touching code:** `join_priors()`'s final
`distinct(observation_id, taxon_name, taxon_name_rank, .keep_all = TRUE)` call kept only the
highest-`prior_mean` site *per candidate* -- each candidate ended up matched to its own most
favorable site rather than the site it was actually detected at. A synthetic repro (one
observation, two candidates, two sites, strong-prior-at-one-site/weak-at-the-other for each
candidate) confirmed exactly the reentry prompt's description: two rows total instead of
four, collapsing what should be combined evidence into an arbitrary per-candidate site pick.

**Fix 1 (`join_priors()`):** the `distinct()` call now also keys on `grid_id`/
`main_habitat`, so a genuine multi-site observation keeps one row per candidate per site
instead of collapsing across sites, while still deduping same-site duplicates (the original
purpose of this call, from coarse-rank expansion). Traced `.expand_coarse_rank_rows()` first
to confirm it wouldn't need reordering relative to this fix -- it already keys candidates by
`(taxon_name_rank, taxon_name, grid_id, main_habitat)`, so it was already site-safe; the bug
was isolated to this one `distinct()` call. The first `left_join()` (likelihoods →
event_meta) now declares `relationship = "many-to-many"` explicitly, since a multi-candidate,
multi-site observation legitimately fans out on both sides of that join (this stopped being
incidental once multi-site became an intentional, tested code path).

**Fix 2 (new `combine_multisite_priors()`):** combines join_priors()'s now-preserved
per-site rows into one row per candidate. **Design decision revised from the reentry
prompt's two options** (simulation-based product vs. moment-matched Beta approximation of a
plain product-of-means), after the user raised a concrete concern mid-session: shouldn't a
site with little supporting data count for less than one with strong, high-quality support?
Checked this empirically before implementing (not asserted): in a worked example (site A,
phi=100, confidently favors candidate X at 0.8; site B, phi=5, sparse data weakly favoring
candidate Y at 0.6 -- a spurious signal in the opposite direction), a plain product-of-means
gives X only 72.7% of the combined mass, and running the reentry prompt's own recommended
full Monte Carlo simulation (draw `theta_site ~ Beta`, multiply, renormalize per draw) does
NOT fix this -- it shifts weight *toward* the noisier site's minority pick (69.2%), a known
statistical artifact of averaging a renormalized ratio of random variables, unrelated to
confidence. **Implemented instead: precision-weighted combination in logit space.**
`logit(Beta(a,b))` has an *exact* mean (`digamma(a) - digamma(b)`) and variance
(`trigamma(a) + trigamma(b)`), via the Gamma-ratio representation of a Beta variate;
inverse-variance-weighting these and converting back with `plogis()` gives X 78.5% in the
same worked example -- the only one of the three approaches that actually discounts a
low-confidence site (about 16x less weight here, from the ratio of logit variances) rather
than counting it at face value or distorting the result in an uncontrolled direction. The
combined Beta's own concentration is derived from the pooled logit variance via the
large-phi delta-method approximation `Var(logit(Beta(m*phi,(1-m)*phi))) ~= 1/(phi*m*(1-m))`,
solved for phi, so `compute_posterior()`'s existing Beta-sampling Monte Carlo path needs no
changes at all.

Function/package placement (`TaxaAssign::combine_multisite_priors()`, the reentry prompt's
placeholder name) confirmed with a grep across the monorepo before implementing -- no
collision, only the reentry prompt itself used the name (see
`~/.claude/projects/-Users-lafferty/memory/feedback_naming_collision_check.md`).

Re-ran the OQ846725-style repro end to end after implementing: the old buggy cherry-pick
behavior gave a near-toss-up (57.1%/42.9%) on an asymmetric two-candidate/two-site fixture
built to mirror the design-discussion scenario; the fixed path (`join_priors()` →
`combine_multisite_priors()` → `compute_posterior()`) gives the correctly-supported
candidate a decisive 78.5%/21.5% win. (A separate, perfectly-symmetric mirror-image fixture,
closer to the reentry prompt's own literal repro numbers, correctly reduces to an exact
50/50 tie under both old and new logic -- that fixture doesn't discriminate between the two
implementations, since the underlying evidence really is symmetric; it's kept as a
combination-mechanics test, not a bug-fix regression test.)

Wired into `inst/TaxaID_Workflow_Template_TEST.R` Section 7, right after `join_priors()` and
before `compute_posterior()` (no-op for the template's current single-site bundled data).

7 new tests in `test-combine_multisite_priors.R` (validation, single-site passthrough,
multi-site combination, the precision-weighting worked comparison as a regression test,
column inheritance, mixed single/multi-site batches) plus 1 new multi-site-preservation test
in `test-join_priors.R`. Full TaxaAssign suite: 539 expectations, 0 failures (up from 516 in
Session 129's count). `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Not done:** Phase 6's test matrix (the four-scenario real end-to-end run, still blocked on
live BLAST/NCBI/GBIF + an interactive RStudio session for the two Shiny gadgets) -- see the
reentry prompt's own Phase 6 section, unaffected by this session's Phase 5 work.

**Session 134 (2026-07-03): update_prior_from_consensus() spatial_group_map guard**

Branch `single-observation-pipeline`. Implements the decision tree item from
`~/.claude/projects/-Users-lafferty/memory/project_clustered_vs_independent_reframe.md`:
`update_prior_from_consensus()` is only valid when other observations genuinely share a
local species pool (a multi-member spatial group), and must be skipped for single
observations and independent observations, since another unrelated observation's
confirmed presence would smuggle in a false shared-context assumption.

Added optional `spatial_group_map` param (`observation_id`/`spatial_group_id`, matching
`TaxaMatch::group_observations_by_bbox()`'s output shape). When supplied: (1) only
`consensus` rows whose `observation_id` belongs to a `spatial_group_id` shared with >= 1
other observation contribute to `confirmed_species`; (2) `unresolved_ids` is intersected
with that same multi-member-group set before the boost is applied, so an observation in
a single-observation spatial group's unresolved rows fall through to the
unchanged/"resolved" branch of the existing resolved/unresolved split with no other code
path changes needed. Default `NULL` preserves the exact pre-Session-134 behavior (every
observation participates) — non-breaking.

This also covers the specific case this session's work introduced: an observation that
fell outside every user-drawn group polygon in `group_observations_by_bbox()` and was
placed in its own single-observation spatial group (not dropped) is, correctly, still
excluded here — landing in a single-observation group for that reason carries the same
"no shared local species pool" implication as being a genuine single observation.

**Naming, settled before commit:** started as `group_map`/`group_id`, renamed to
`spatial_group_map`/`spatial_group_id` after the user flagged that bare "group" already
means something else in this very package (`assign_taxa_llm()`'s `context_group`/
`.build_group_map()` — LLM-batching context groups, unrelated to spatial location) and
that "cluster" (the other candidate) is taken by `TaxaLikely`'s confusable-species
`cluster`/`true_cluster` concept. Also dropped the separate `"independent_*"` id
convention per the user's direction — a single-observation spatial group isn't a
different kind of thing, it's a `spatial_group_id` like any other with one member. No
logic changes were needed for this: eligibility was already determined by counting
group membership (`table(spatial_group_map$spatial_group_id) >= 2L`), never by
pattern-matching the id string.

7 new tests added to `test-update_prior.R` (a shared-group pair still boosts; a pair
each in their own single-observation group blocks the boost; a third, single-observation
group in an otherwise-grouped dataset is skipped while the shared-group pair still
updates normally; missing-column validation). `devtools::test()`: 0 failures (12
warnings/1 skip pre-existing). `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Not done this session:** the deeper `(observation_id, site)` schema question for
`join_priors()`/`compute_posterior()`/`posterior_consensus()` (needed once sequence
ASVs detected at multiple real sites become the true analysis unit) remains open —
flagged in `ecosystem_docs/REENTRY_PROMPT_session134_single_observation_pipeline.md`
as probably deserving its own session; unaffected by this session's `spatial_group_map` addition.

Sessions 29–77 archived in ecosystem_docs/session_notes/TaxaAssign_sessions.md.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` rename across all 13 R source files, 12 test files, 2 vignettes,
  5 inst/ files, dev/ files, and README. Largest package: ~361 occurrences.
- `sample_meta` → `event_meta` throughout (variable name for L1 collection event metadata)
- `globalVariables("sample_id")` → `globalVariables("observation_id")` in `R/assign_taxa_llm.R`
- `generate_report.R`: prose changed from "samples" to "observations" in `.build_results_template()`
- Required reinstalling TaxaMatch, TaxaLikely, TaxaFlag for cross-package `filter_redundant_hypotheses()` calls
- 412 tests passing (4 warnings, 1 skip — pre-existing)

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaAssign-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), model
  registry enhancements, WERC peer review integration. See TaxaID/CLAUDE.md for full log.

**Session 86 (2026-05-23)**
- `.resolve_llm_fn()` in `R/site_utils.R`: fallback updated from `TaxaTools::call_anthropic_api`
  to `TaxaTools::call_api`. Covers `assign_taxa_llm()`, `run_llm_pipeline()`, `build_context()`,
  `suggest_unreferenced_species()`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`.

**Session 99 (2026-06-02)**
- Column renames (breaking — ecosystem-wide):
  - `score` → `score_original`: `score_consensus()` default `score_col` updated; all tests and
    workflows updated; `TaxaAssign_llm_workflow.R` had 3 missed `$score` / `score_col="score"`
    references fixed during workflow testing
  - `likelihood_point_est`/`_mean`/`_sd` → `score_likelihood`/`_mean`/`_sd`: all R source,
    tests, inst/ files updated
  - `"unknown_species"` hypothesis_type → `"unreferenced_family"` with `NA` `taxon_name`:
    `assign_taxa_llm.R` updated; `posterior_consensus.R` filter changed from
    `taxon_name == "unknown_species"` to `is.na(taxon_name)`;
    `TaxaAssign_supplemental_methods.md` updated throughout
- `assign_taxa_llm.R` bug fix: column collision guard added before `dplyr::left_join()`
  (prior_df columns `hypothesis_type`/`taxon_name_rank` caused `.x`/`.y` split, making
  `merged$hypothesis_type` NULL); `unk_idx` changed from
  `merged$hypothesis_type == "unreferenced_family"` to `is.na(merged$taxon_name)` (more robust)
- Test fixes: 6 assertions in `test-assign_taxa_llm.R` gained `!is.na(result$taxon_name) &`
  guards (NA comparison `NA == "..."` returns NA, not FALSE, causing spurious row inclusion)
- Workflows: `TaxaAssign_bayesian_workflow.R` and `TaxaAssign_llm_workflow.R` updated for
  all column renames; workflow testing confirmed all stages pass with real data

**Session 89 (2026-05-27)**
- `suggest_unreferenced_species()`: `data_type` param added (`"eDNA"` default / `"acoustic"` / `"image"`). eDNA path: existing NCBI nucleotide count queries. Acoustic/image path: set-membership check against `reference_species` (character vector of classifier's known species list). LLM prompt `ref_filter_note` switches text accordingly via `switch(data_type, ...)`. `barcode_term`, `max_date`, and `rentrez` requireNamespace guard now all wrapped in `if (data_type == "eDNA")`. `reference_species` param added (required for acoustic/image; ignored for eDNA).

**Session 123 (2026-07-01)**
- `add_slash_taxon()` gains two new output columns, `consensus_OTU` and `primary_taxon`,
  computed only when `consensus_taxon` is present in `consensus_df`. `consensus_OTU` =
  `slash_taxon_name` when non-`NA`, else `consensus_taxon`. `primary_taxon` = `consensus_OTU`
  with everything from the first `/` or ` + ` dropped. This is logic that
  `PtConceptionWorkflow_12S.R`, `PtConceptionWorkflow_18S_2.R`, and `MuguFishWorkflow.R`
  had each independently hand-derived identically (as `most_likely_slash`) — now computed
  once in the package; all three workflows updated to drop the hand-rolled block and
  rename `most_likely_slash` → `primary_taxon` throughout. 4 new tests added to
  `test-slash_taxon.R` (22 total, all passing). `devtools::check()`: 0 errors, 0 warnings.

**Session 122 (2026-06-27)**
- `is_valid_species_name()` → `is_plausible_binomial()`: all calls updated across R source and tests.
- Non-ASCII chars replaced with ASCII equivalents in two files: `expand_unreferenced.R`
  (em-dashes `—` → `--`) and `join_priors.R` (em-dashes `—` → `--`; `×` → `x`; `≈` → `~=`).
  These were comment-decoration characters that failed `R CMD check` CRAN portability check.
- Peer-review pass (TaxaTools reviewer checklist): no TaxaAssign-specific function changes required.
- Debris deleted: `dev/test_compute_posterior.R` (dev scaffold), `README.Rmd` (template source).

**Session 129 (2026-07-03): camera_trap_posterior_workflow.R — first real TaxaAssign run for the camera-trap image species set**

`inst/workflows/camera_trap_posterior_workflow.R` added — not new package code (every
function it calls already exists and is exercised by the five-package Gadus/GBIF chain),
but the first time TaxaAssign's actual posterior machinery ran on the real camera-trap
mammal species (8 species, 52 photos) that TaxaMatch/TaxaLikely's image tutorial had
stopped short of, per that tutorial's own header note that a full TaxaAssign run "would
need real occurrence-based priors... a separate task."

Builds real GBIF priors for all 8 species via TaxaHabitat's LLM habitat classification
and TaxaExpect's biodiversity model (uncovered and fixed two real TaxaExpect bugs along
the way — see that package's own Session 129 note), then runs `join_priors ->
compute_posterior -> posterior_consensus -> add_slash_taxon` twice per run: once with
`TaxaLikely::correct_training_bias()`/`assign_scores()`'s empirically calibrated
parameters (`tau = 0`, `score_sharpness = 10` — see `TaxaLikely/CLAUDE.md`'s Session 129
note for how these were derived), once with the old Session 127 theoretical defaults
(`tau = 1`, `score_sharpness = 0.1`), so the calibration's real effect on the final
posterior is directly visible rather than asserted. `consensus_calibrated` is the
recommended result; `consensus_old_default` is kept only for comparison.

Full TaxaAssign test suite: 516 expectations, 0 failures, 0 errors, unaffected by this
new script (no R/ source changes in this package this session).

