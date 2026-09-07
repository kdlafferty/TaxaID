# CLAUDE.md — TaxaID Ecosystem
# Ecosystem-level context for Claude Code. Auto-loaded from any package subdirectory.
# Package-specific context lives in each package's own CLAUDE.md.
# Last updated: 2026-09-07, later (Sonnet 5 -- production-workflow section/structure
# standardization pass, per the user's own outline-first-then-canonical-then-apply
# process (ecosystem_docs/REENTRY_PROMPT_workflow_structure_audit.md). Deliberately kept
# the two established numbering families separate (single-marker 0-10 vs multi-marker
# 0-11/0-12 -- they genuinely do a different number of things), standardizing WITHIN each
# rather than merging them.
#
# Single-marker family (PtCon 12S single/multi, PtCon 18S_2, GreatLakes): fixed a real,
# shared duplicate-label bug in all 3 PtCon files (Section 8 reused 8e/8f twice each --
# join-priors=8e/iNat-elevation=8f, then compute-posterior=8e AGAIN/consensus=8f AGAIN --
# adopted GreatLakes' already-correct, non-duplicated 8a-8k lettering as the family
# standard); relabeled GreatLakes' colliding 7a.6 (reference-quality screen, collided with
# its own correctly-numbered read-depth block) to 7a.10 to match its 3 siblings, and
# shifted its 7a.7/7a.7b/7a.7c to 7a.7/7a.8/7a.9 (7a.7d, a genuinely different kernel-
# priors-specific mechanism, kept its own distinct 7a.9b suffix rather than being merged
# in). All relabeling confirmed comment/banner-only -- no variable, column, or cache
# filename anywhere is keyed off a step number, so this carries zero data-dependency risk.
# Two capability backports, both per the user's explicit go-ahead: regional-proximity
# priors (7a.9) into 12S_multi_site.R (the one single-marker file missing it entirely);
# GreatLakes' verify_flagged_references() training-screen mechanism (relabeled 7a.11) into
# all 3 PtCon files, each wired into its own train_likelihood_model(verified_clean=) call.
#
# Multi-marker family (Mugu Fish/Wilder): already internally consistent (Wilder's +1 step
# offset from building its own match objects was already fully accounted for everywhere).
# Added a marker-qualified message (not a bare numbered banner, since the block runs once
# per marker inside a shared function) to both files' reference-quality screen.
#
# Both workflow TEMPLATES separately backported the same 2 universal gaps every real
# production workflow already had (review-assignments cache_dir; check_geographic_
# outliers()/institution review) -- the generic template was ALSO missing
# filter_gbif_quality() entirely (a bigger, previously-unflagged gap found while wiring
# the others in). A third file (this canonical PtCon template itself) turned out to carry
# the same stale lab_contaminant_risk/score reference (6 sites) already fixed elsewhere --
# fixed here too, closing a gap the original 2-file audit scope had missed.
#
# Along the way, investigating a warning the newly-unblocked PtConception 18S fast smoke
# test surfaced led to a real, previously-unnoticed ecosystem-wide false-positive fix in
# TaxaMatch::filter_redundant_hypotheses() (see TaxaMatch/CLAUDE.md's own top note for the
# full trace/proof) -- it warned on every real single-marker production join_priors()
# call, harmlessly, since the missing column was always rank_system's own finest entry
# (which the algorithm provably never needs). Fixed, tested, live-verified byte-identical
# output; the PtConception 18S fast smoke test itself was also unblocked and built this
# session (see diagnostics/fast_workflows/README.md) -- all 4 real sites now have one.
#
# All 9 packages reinstalled and verified in a fresh session afterward (all built
# 2026-09-07, correct library path, only the standing benign glmmTMB/TMB warning).
# None of the 6 real production workflow files are under git (backed up individually
# before each edit, per this project's own established convention); the two templates +
# TaxaMatch fix + new 18S smoke test are committed to this repo across several commits.
#
# Previous update, 2026-09-07 (Sonnet 5 -- CLOSED, pre-publication: reconciled a third,
# separate dormant Claude Code session's uncommitted work (idle since 2026-09-05) across
# TaxaAssign/TaxaExpect/TaxaLikely/TaxaMatch, implementing most of the
# fable_ecosystem_review_2026-09-05.md findings (A1, A2, A3, A4, B5, C, D2, E1's screening
# doctrine) plus TaxaExpect's own kernel-budget open decision #1 (mass/f1, not
# mass/chao_missing). Verified clean on all four packages (devtools::test()/check(), 0
# failures, 0 errors/warnings) before committing as four separate package commits, each
# reviewed line-by-line, not trusted blind. Then closed B2, the review's one remaining
# substantive item, from real evidence rather than picking the cheap default: the
# committed veto-bound cap (the review's own "at minimum" floor) reproduces the review's
# exact worked example correctly (uncapped w1 = 0.3298 -> capped 0.05, a 6.6x reduction,
# matching the review's own numbers to the digit -- diagnostics/
# b2_mixture_update_veto_cap_check.R) AND held up on a fresh, full real GreatLakes
# production run (2792 real mixture-row updates, sum(prior_mix_w) 110 -> 386) with a
# held-out Lamar validation matching or beating the established 2026-08-31 curve-pricing
# benchmark (precision 0.8527 vs 0.853, co-detections 602 vs 594, unique-species
# intersection 29 vs 28, overconfidence 1/1081 both times) -- no degradation despite
# substantial real w-inflation. A structural finding sharpened WHY: the cap never actually
# fired on that run, because GreatLakes now runs curve pricing and `prior_mix_veto_bound`
# is only ever non-NA under blend pricing -- but curve pricing has a STRONGER built-in
# guarantee (`theta = w * theta_present`, pinned to the singleton mean, so an elevated
# species' theta cannot exceed a genuinely-observed native's regardless of w) that makes
# the whole failure class structurally impossible, not just capped. The deeper level-aware
# redesign (support-weighted-quantile success rate, or n_observations-scaled trials) is
# NOT built -- a closed decision, not deferred, made explicitly because this is a final
# pre-publication screen with no opportunity to revisit. See
# `ecosystem_docs/fable_ecosystem_review_2026-09-05.md`'s own B2 "Resolved" section for
# the full record.
#
# Also this session: cleaned up `ecosystem_docs/` (63 files -> 25 + 2 deliberate archive
# subdirs), removing closed REENTRY_PROMPT design threads and one-time April-July 2026
# audit reports whose findings were never referenced again by any later session, and
# relocating 2 copyrighted journal PDFs + a supplementary .docx + an unrelated personal
# HTML file out of this public repo entirely (to a sibling, non-git
# `TaxaID_reference_material/` directory) -- each removal individually verified as
# closed/superseded before deleting, not a blanket sweep. REENTRY_PROMPT_
# workflow_structure_audit.md kept deliberately (explicit user request, to be implemented
# later), as were the two review docs themselves and several genuinely-still-open design
# docs.
#
# Previous update, 2026-09-06, later still (Sonnet 5 -- three follow-ups to the
# review_assignments() rename entry directly below. (1) REAL GAP FOUND: the rename sweep
# had been scoped to ~/My Drive/Rscripts/eDNA/, missing GreatLakes2023_ConsensusWorkflow.R
# entirely -- it lives at ~/My Drive/Stats and Data/GreatLakes data/, outside eDNA/ (same
# "lives outside eDNA/" trap [[project_greatlakes_workflow_debug_notes]] already
# documents). Fixed the same way as the other 7 files (backed up as
# *.bak_pre_llm_column_rename, parses cleanly); it's the 8th and last real production
# workflow needing this rename, not 7. (2) Both real review_assignments() caches that had
# actually been run since the 2026-09-04 cache_dir feature shipped (GreatLakes, 72 entries;
# PtCon 18S, 1,731 entries) were pruned via TaxaFlag::taxaflag_clear_cache() -- every entry
# was orphaned by the rename's own taxa_info-hash mechanism (new has_unprecedented/
# has_indistinguishable columns changed every cache key), so nothing live was discarded.
# (3) A small, comment/heading-only cleanup pass on 3 files (12S_single_site,
# 12S_multi_site, GreatLakes -- each backed up as *.bak_pre_section_heading_cleanup): added
# an explicit "10. FILTER + OUTPUT" section banner + Step message right after the
# review_assignments() save point, matching the convention 18S_2 and both Mugu workflows
# already use (those three previously folded the identical filter-and-write logic into an
# unlabeled tail alongside the session-metadata/report code). Two heading-inconsistency
# HYPOTHESES raised earlier the same day were investigated and found NOT to be real:
# GreatLakes' "6. MATCH STANDARDISATION (TaxaMatch)" heading looked mismatched against its
# actual "Joining contaminant flags for provenance" content, but the step's own inline
# comment already explains this correctly (standardisation genuinely happened at Step 1 for
# this dataset; Step 6 is a deliberately-thin provenance join, not drift) -- left untouched,
# per [[feedback_verify_purpose_before_flagging]]. Several apparently-"unlabeled" `# ===`
# dividers (GreatLakes, PtCon 12S multi-site) turned out to be real, sensibly-titled
# sub-sections (`1.5`, `2.5`, `8j`, `8k`) that a too-strict header regex simply failed to
# match during the initial survey -- not orphaned markers, no fix needed.
#
# TWO REAL FINDINGS surfaced by this pass, deliberately NOT fixed here (more than cosmetic,
# left for explicit decision): (a) both `inst/TaxaID_Workflow_Template_TEST.R` and
# `PtConceptionWorkflow_12S_multi_site.R` still filter on the literal column name
# `lab_contaminant_risk` -- a name `flag_contaminant()` stopped emitting on 2026-07-24 (see
# this file's own Recent Breaking Changes table), replaced by the unified
# `validity_flag`/`observation_validity` schema. Run as written today, both filters would
# error (column not found) rather than silently misbehave. (b) `inst/
# TaxaID_Workflow_Template_TEST.R` (the generic, package-level template) has no explicit
# "1. LOAD INPUT DATA" section at all -- it jumps straight from "0. CONFIGURATION" to
# "2. CONTAMINANT DETECTION" -- and has zero `message("\n--- Step N: ...")` console
# announcements anywhere, unlike every real production workflow and unlike
# `PtConception/TaxaID_eDNA_Workflow_Template.R` (a separate, more evolved, clearly
# actively-maintained site template the 3 PtConception production scripts were built
# from). This raises a real question -- is the generic template stale/abandoned relative
# to the PtCon one? -- that the user asked to defer to a dedicated audit rather than decide
# ad hoc. See `ecosystem_docs/REENTRY_PROMPT_workflow_structure_audit.md` for the full
# write-up and the wider "outline every real workflow, cross-reference against TaxaWizard's
# graph" plan this pass fed into.
#
# STEP-NUMBERING FAMILIES (recorded here so a future reader doesn't mistake a real
# structural difference for drift): PtCon 12S/18S_2 + GreatLakes share one 0-10 scheme
# (single-marker). Both Mugu workflows use a longer, genuinely different scheme (per-marker
# scored likelihoods -> per-marker Round 1 -> cross-marker prior update -> Round 2 ->
# TaxaFlag -> Filter+Output) because they score more than one marker per observation and
# combine posteriors across markers -- MuguFishWorkflow.R is 0-11, MuguWilderFishWorkflow.R
# is 0-12 (one extra step: it builds per-marker match objects itself, where MuguFishWorkflow
# loads them pre-built). "Step 9" is TaxaFlag review in the single-marker family and
# "cross-marker prior update" in Mugu's -- a real difference in what each pipeline does, not
# a numbering bug to reconcile.
# Previous update, 2026-09-06, later (Sonnet 5 -- TaxaFlag::review_assignments() column rename +
# skepticism gate + deterministic disagreement flag, prompted by a real, surprising output
# row (Musculus discors: posterior=1 forced by single-candidate normalisation against a
# ~6.5e-6 prior, pipeline flags both unprecedented AND indistinguishable, yet
# geographic_plausibility came back "likely" with no legible justification). Three-part
# fix, all in TaxaFlag: (1) the four LLM-sourced output columns renamed with an llm_ prefix
# (llm_habitat_plausibility/llm_geographic_plausibility/llm_scope_plausibility/
# llm_contamination_risk) so a "likely"/"unlikely" verdict's SOURCE is legible from the
# column name alone, not just documentation -- these are independent LLM judgments, never
# derived from or gated by any pipeline value; (2) a new consensus-scope skepticism
# GUIDELINES bullet requires the LLM to cite specific site-relevant evidence before rating
# a taxon flagged "unprecedented" (no local record) and/or "indistinguishable" (a
# confusable relative scores equally well) as likely/possible, declared a hard requirement
# (the one exception to review_assignments()'s own "bracket informs, never overrides" rule);
# (3) a new deterministic, code-computed geographic_disagreement_basis column fires
# whenever the LLM rates likely/possible despite either ground (OR, per the user's explicit
# direction) -- built because an LLM cannot be trusted to reliably self-flag its own
# disagreement in prose (this ecosystem's own trusted_rank removal precedent). Also widened
# the pipeline-context prompt formatter so near-zero priors render in scientific notation
# instead of masking as "0.00" under %.2f. All 7 real external eDNA workflow scripts
# (PtConception x4, Mugu x2, the shared Template) updated for the rename, backed up first
# (*.bak_pre_llm_column_rename); TaxaFlag devtools::test() 456/456, check() 0/0/0,
# reinstalled. See TaxaFlag/CLAUDE.md's own top session note for the full record.
# Previous update, 2026-09-06 (Sonnet 5 -- the by_genus fix (below) also wired into
# PtConceptionWorkflow_18S_2_single_site.R, the real 1,412-genus dataset that motivated
# the whole redesign, the same day the user stopped that workflow's own live 5+-hour
# whole-set alignment run via RStudio. Wired on the strength of the Mugu/PtCon-12S
# validation, NOT independently re-measured at 18S's own much larger scale (a live
# 1,412-genus NCBI fetch needed for that was flagged as itself a long, historically-
# throttled operation and deliberately not run this session, per the user's choice). See
# TaxaLikely/CLAUDE.md's own top note for the full record.
# Previous update, 2026-09-05/06 (Sonnet 5, branch kernel-priors -- E1's per-genus alignment
# redesign (fable_ecosystem_review_2026-09-05.md) CLOSED OUT: TaxaLikely::
# build_sequence_matrix(by_genus=) went through a full false-start-and-recovery arc --
# a representative-only first version validated H2/H3 well but measurably inflated H1's
# "gap" discriminator for non-representative sequences; the obvious fix (give every genus's
# alignment a copy of every OTHER genus's representative) fixed the statistics but was found,
# on real data, to cost MORE than whole-set alignment and get WORSE as genus count grows
# (exactly backwards); a capped version (`max_foreign_reps_per_genus`, default 20) restored
# the win (~2-2.7x faster than whole-set on two independent real datasets, 88 and 221 genera)
# while roughly halving the gap-inflation. Package default kept `FALSE` (by_genus=TRUE hard-
# requires a genus column, unsafe as a universal default); wired explicitly instead into
# MuguWilderFishWorkflow.R and PtConceptionWorkflow_12S_single_site.R, the two real datasets
# it was validated against. Full arc + exact numbers in TaxaLikely/CLAUDE.md's own top note.
# TaxaLikely devtools::test() 1075/0, check 0/0/0, reinstalled.
# Previous update, 2026-09-04, later (Opus 5 -- PER-GROUP CURVE PRICING BUILT, closing open
# decision #2 of ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_scope.md (read its
# "2026-09-04 UPDATE" section). apply_undetected_evidence(pricing = "curve") used to REFUSE a
# multi-group kernel fit; it now prices each evidence taxon at its OWN sampling group's
# Good-Turing budget, justified by the 1859x per-group spread the 18S diagnostic measured the
# day before. Group assignment is NEVER inferred from taxonomy -- an unassigned taxon errors
# with guidance, because the classification that built the occurrence pool's groups lives in
# the workflow and a wrong group mis-prices SILENTLY. THREE GUARDS, every one of which fires on
# the real 10-group PtCon 18S fit: SUPPORT (min_group_n_eff = 100 / min_group_f1 = 1 -- stops a
# 27-effective-record group pricing an unseen plant at 2.1% of its own community; at lambda 10
# terrestrial_arthropods reaches 0.755, i.e. 75%), a SINGLETON CAP (binds exactly when
# f1 < 2*f2 -- real zooplankton f1=3/f2=7/Chao=0.64 was priced 4.7x ABOVE a species seen once;
# deliberately NOT open decision #1, which binds the other way), and a GROUP-WISE
# pooled-qualifying fallback (unseen counts add across disjoint groups, missing masses combine
# as an n_eff-weighted average -- never by re-pooling records, which would reintroduce the f1
# inflation the mechanism removes). Every row records sampling_group + pricing_basis and the
# call prints the whole per-group budget: a borrowed price is never silent. SINGLE-GROUP FITS
# ARE BYTE-IDENTICAL (verified old-vs-new on the real GreatLakes checkpoint, max |delta| = 0 on
# alpha/beta/theta_mean) -- the guards police borrowing BETWEEN groups, which only exists once
# there is more than one, so the Lamar-validated GL result does not move. SECOND REAL BUG found
# by building it: generate_undetected_diversity()'s kernel adapter divided every singleton
# mirror by the POOLED n_eff, understating each group's mirrors by 1.86x (fishes) to 4295x
# (terrestrial arthropods). NEW diagnostics/per_group_curve_pricing_18S_check.R; PtCon 18S
# workflow wired (WATCH_SAMPLING_GROUP <- "fishes", 1.26x the pooled price), NOT run end to
# end. Decisions #1 (mass/f1) and #3 (theta distribution) remain open and untouched.
# TaxaExpect 1018 tests, check 0/0/0.)
# Previous update, 2026-09-04 (Sonnet 5, branch cache-management -- persistent on-disk
# cache audit + fixes across TaxaFetch/TaxaLikely/TaxaTools, prompted by the user
# reporting ~/Library/Caches/org.R-project.R/R/TaxaFetch at 23GB. Real bug found and
# fixed: download_gbif_occurrences()'s GBIF-zip cache silently ORPHANED the
# previous cached zip on overwrite = TRUE (repointed the query's metadata at the
# fresh download without deleting the stale one) -- fixed with an interactive
# confirmation prompt plus unconditional cleanup of the superseded zip either way.
# New taxafetch_clear_cache(orphans_only=, older_than_days=, dry_run=) reports/
# clears the cache; live dry-run on the user's real cache found 13 orphaned
# zips/6.3GB, confirmed and cleared, bringing it to 17GB (genuinely distinct
# per-query downloads, not further orphans).
#
# A full 9-package audit for the same accumulation pattern (requested by the user
# before extending the fix anywhere else) found exactly one more real instance --
# TaxaLikely's fetch_ncbi_reference_sequences()/audit_barcode_coverage() cache,
# same unbounded-file-per-query shape, currently small (2,538 files/2.3MB) but no
# eviction and no clear-cache tool -- new TaxaLikely::taxalikely_clear_cache()
# added preemptively. TaxaHabitat/TaxaExpect/TaxaAssign/TaxaWizard have no
# persistent cache at all; TaxaTools' own model_registry.json is a single small
# file, not a concern.
#
# TaxaMatch's reference-evaluation caches (evaluate_reference_accessions()/
# investigate_flagged_accession()/review_flagged_accessions()) were checked
# closely and deliberately EXCLUDED from this fix, at the user's explicit
# prompt to look carefully before reusing the same logic: they are a
# structurally different, CUMULATIVE cache (one consolidated file per cache_dir,
# read-modify-write merge, row-level asymmetric TTL) where "congruent"/
# "locally_corroborated" verdicts are cached with infinite TTL BY DELIBERATE
# DESIGN ("nothing a later BLAST returns can withdraw a match that was already
# observed" -- the package's own comment). A directory-scan-and-delete tool
# would destroy exactly the permanently-valid, NCBI-budget-expensive verdicts
# that design is protecting. That package's own TTL system + migrate_
# reference_cache() (which backs up before ever touching the file) is already
# correct and was left untouched.
#
# Given two packages needed the identical ~40-line validate/report/delete
# engine, it now lives once in TaxaTools (both TaxaFetch/TaxaLikely already
# import it, same precedent as %||%): new list_cache_files()/
# report_and_clear_cache(), exported. Each package keeps its own separately-
# named, separately-exported wrapper (never one shared bare function name --
# two loaded packages both exporting clear_cache() would mask each other).
# TaxaFetch's orphan-detection stayed local (no TaxaLikely analog).
#
# devtools::test()/check() clean on all three touched packages (TaxaTools
# 893/0, TaxaFetch 676/0 [2 pre-existing unrelated CoordinateCleaner/terra
# environment failures], TaxaLikely 1034/0; check 0/0/0 all three),
# reinstalled and verified at ~/Library/R/4.0/library. See each package's own
# CLAUDE.md top note for the full record. Not yet merged into kernel-priors or
# main -- this work is unrelated to that branch's topic, done on its own
# cache-management branch per this project's own feature-branch convention.
# Previous update, 2026-09-03 (Opus 5, branch kernel-priors -- PRIOR-SIDE 18S BUDGET
# DIAGNOSTIC + open decision #4. Full record in ecosystem_docs/REENTRY_PROMPT_kernel_
# budget_pricing_and_scope.md (READ ITS CLOSING "2026-09-03 UPDATE" SECTION FIRST --
# it supersedes that doc's own next-step, cost estimate, and part of its Finding 2).
# (1) REAL BUG, PtConception 18S sampling groups: the fishes clause
# (class %in% c("Actinopteri","Chondrichthyes","Myxini")) matched 5 of 484,077 real
# fish records -- GBIF's backbone carries NO class for ray-finned fishes and names
# sharks/rays "Elasmobranchii" -- so 484,072 fish fell into the macroinvertebrates
# CATCH-ALL, making the largest group 54% fish, silently (a catch-all cannot fail
# loudly). Fixed in PtConceptionWorkflow_18S_2_single_site.R (+ empty-string na_if
# normalization + a regression guard), TaxaID_eDNA_Workflow_Template.R, and
# 18S_stuff/PtConception18S_groupings.r. (2) THE 18S DIAGNOSTIC (NEW diagnostics/
# kernel_budget_18S_sampling_groups.R, no network at all -- it sidesteps the NCBI
# throttling that has blocked PtCon since 2026-08): the doc's claim that 18S has no
# occurrence checkpoint was WRONG; a verified 2,185,193-record one has been in the
# project root since 2026-06-15. Per-group Good-Turing budgets span 1859x (441x
# restricting to groups the assay can amplify, or to n_eff >= 100; 6644x under
# compute_adaptive_sampling_groups()), and the single pooled price sits BELOW all
# seven priced groups (1.26x fishes to 2343x land plants). Per-group curve pricing
# is JUSTIFIED but NOT BUILT -- the diagnostic also enumerates the guards it needs
# (3/10 groups have no singleton anchor; Chao can fall below ONE species; a group
# can price a single unseen species at 0.755 of its own community). (3) FINDING 2
# CORRECTED: mass/Chao is NOT always below the singleton mean -- that needs
# f1 > 2*f2, and real 18S zooplankton (f1=3, f2=7) prices 4.7x ABOVE it. (4) OPEN
# DECISION #4 IMPLEMENTED: NEW TaxaExpect::kernel_budget_sensitivity(); ungrouped
# print() now shows f1/f2/chao/theta_present; apply_undetected_evidence(curve) names
# the f1/f2 behind its price. TaxaExpect 956 tests pass, check 0/0/0 (also fixed a
# PRE-EXISTING check ERROR: building-priors.Rmd's opts_chunk$set(purl=FALSE) is not
# honoured by knitr::purl(), so the whole documentation-only vignette was being
# tangled and sourced). Decisions #1 (mass/f1) and #3 (theta distribution) untouched.)
# Previous update, 2026-08-30/31 (Fable 5, branch kernel-priors -- a landmark two-day arc,
# full record in ecosystem_docs/REENTRY_PROMPT_evidence_ceiling_and_habitat_bleed.md
# (READ ITS LATER SECTIONS FIRST -- they supersede this file's older prior-related
# claims). (1) FOCAL-GRID BUG: "most-represented grid" SITE_GRID_ID selection was an
# alphabetical tie-break on zero-filled model frames -- PtCon 12S priors were evaluated
# at a San Diego cell 292 km off-site across the Point Conception biogeographic
# boundary; GreatLakes' cell was 40 km off (inland, 18 records vs the shore cell's 82).
# Fixed in 5 workflows incl. both package tutorials (TaxaExpect's own KNOWN FOOTGUN
# comment RECOMMENDED the pattern). GL re-run at the correct grid: Lamar precision
# 0.710 -> 0.748 but breadth 18 -> 13/61 (small-n cell compression) -- which exposed the
# real problem: single-cell priors waste neighborhood data. (2) GENERAL PRIOR
# FRAMEWORK designed with the user (compositional priors; Good-Turing/Chao budgets;
# branch taxonomy resident_observed/resident_undetected/transport; count reframing) --
# decision points deferred until after (3). (3) KERNEL-PRIORS PHASE 2 (grid -> site-
# centered distance-kernel estimation) DESIGNED, BUILT, VALIDATED: NEW
# TaxaExpect::estimate_kernel_priors() (geo x depth product kernel, Kish n_eff, Beta
# concentration = n_eff + m, m-pseudo-record regional back-off, weighted GT singletons;
# schema: prior_branch + effective_records replace model_tier on kernel output) + NEW
# calibrate_kernel_bandwidth() (leave-one-block-out composition prediction -- replaces
# AIC screening; single-nearest-cell scored WORSE than ignoring space entirely, the
# empirical nail in the old architecture). generate_undetected_diversity()/
# apply_undetected_evidence()/generate_domestic_food_priors() accept kernel objects
# (adapters; two-scale floor/ceiling fix); TaxaAssign::join_priors() gates promotion on
# prior_branch. GL workflow runs the kernel path (USE_KERNEL_PRIORS switch; GLMM path
# retained until PtCon migrates -- B7 deprecation pending). NEW
# GreatLakes_kernel_fastpath.R (GL data dir): prior-side-only iteration, zero NCBI,
# ~minutes. VALIDATION (Lamar): species co-detections 237 -> 564, precision 0.868,
# unique species 27/61, missed-species 1/1081; yellow perch back (78 obs) with walleye
# resolving separately. Also fixed live: kingdom-vocabulary false homonym in
# generate_domestic_food_priors (Metazoa vs Animalia). PtCon accession screen still
# NCBI-throttled; PtCon kernel migration + near-invariance control + post-Phase-2
# unobserved-taxa redesign are the next chat's work. All committed on kernel-priors.)
# Previous update, 2026-08-28 (Fable 5, branch undetected-evidence-mixture -- ALL SEVEN
# remaining mixture-redesign items implemented in one pass (user: "Do them all in
# order"); the reentry doc now carries a full per-item status ledger. (1) NEW
# TaxaFlag::flag_watch_candidates(): the likelihood-side surveillance guarantee --
# flags any observation where a watch-list species' RAW match score ties/beats the
# winner's own best; wired into GreatLakes 8i.5. (2) apply_undetected_evidence() now
# PRINTS the dataset-specific veto bound at call time. (3) D6 iNat:
# TaxaFetch::check_inat_range() gains a derived name_match column (computed at
# assembly, never cached-stale) closing the fuzzy-misresolution TODO
# ([[project_inat_range_backbone_mismatch_todo]]); NEW
# TaxaExpect::generate_inat_range_evidence() (w=0.8) feeds the shared applier;
# TaxaAssign::adjust_inat_range_priors() name-gated (require_name_match=TRUE) and
# marked superseded for the mixture pathway; GreatLakes Step 7a.7d wired. (4) D7
# SOFT CONFIRMATION UPDATE replaces the hard 0.8 donor gate in
# update_prior_from_consensus(): every observation's posterior support aggregates as
# fractional presence evidence (leave-one-out), discounted by NEW
# `confirmation_discount` a0=0.25 (power prior -- Ibrahim & Chen 2000 Stat Sci
# 15:46-60; soft-vs-classification EM -- Celeux & Govaert 1992 CSDA 14:315-332;
# occupancy analog -- Dorazio & Erickson 2018 MER 18:368-380; all three VERIFIED via
# live search, not recalled), saturating m/(1+m) move toward a support-weighted
# confirmation quantile; mixture rows update prior_mix_w itself (replaces the
# interim clearing rule); `min_confirmation_confidence` REMOVED (breaking)
# everywhere; continuity regression-tested across the old gate. Held-out-Lamar
# validation on identical production inputs: soft beats hard on every axis --
# co-detections 236->238, uncorroborated ours_only 120->97, unique species 17->23,
# Lamar-corroborated 12->18, sample-level precision 0.66->0.71 (the hard cascade's
# bulk resolutions were largely uncorroborated repetition). (5) D8:
# posterior_consensus() default posterior_col aligned to "posterior_point_est"
# (drift resolved). (6) D9: domestic rows verified at design magnitudes (theta
# 4.8e-4, 5x floor, correctly ordered); found+fixed: the workflow never passed
# domestic_taxa to add_posthoc_assessment(), so domestic_prior_caveat was silently
# inert (0/885) -- now wired from the priors table. (7) NEW
# TaxaExpect::fit_regional_presence_curve(): the generic D5 leave-the-bbox-out /
# checklist distance-to-presence fitter (log-link binomial GLM to
# w_scale*exp(-d/d_half); zero-positive case returns Jeffreys bounds first-class,
# exactly the real GreatLakes outcome). Two real bugs found by testing, both fixed:
# 0-row scalar assignment in the all-unresolved split; test fixtures/examples
# relying on the old posterior_mean default. Tests: TaxaAssign 691/0, TaxaExpect
# 731/0, TaxaFlag 434/0, TaxaFetch 620/2-preexisting-env; check 0/0/0 all four;
# reinstalled. See both packages' top notes + the reentry doc ledger.
# Previous update, 2026-08-26, later still (Fable 5 -- w-CALIBRATION + HELD-OUT LAMAR
# VALIDATION close out the mixture redesign's Phase 2 calibration (D4/D5).
# TaxaExpect::generate_regional_proximity_evidence() gains `w_scale` (default 1;
# GreatLakes workflow sets 0.05, calibrated against the site checklist with Lamar
# sealed: 0/110 zero-bbox candidates on the checklist at any distance); all 6
# workflows' INVASIVE_WATCH_WEIGHT 0.6 -> 0.05 (0.6 violated the ordering bound).
# Held-out Lamar validation of the a-priori-declared primary config: species
# co-detections 74 -> 224, unique-species intersection 4 -> 11 of 61, no_match
# 1/1081, overconfidence 0; perch + flathead catfish resolve; mechanism
# ambiguous_rank_fallback 515 -> 205. Full record: reentry doc "D4/D5
# CALIBRATION DONE" section + REVIEW_w_calibration_run.R /
# REVIEW_formal_lamar_check.R in the GreatLakes data dir. TaxaExpect test 697/0,
# check 0/0/0, reinstalled. STILL OPEN (Phase 2/3): iNat evidence generator (D6,
# blocked on the fuzzy-match TODO), TaxaFlag surveillance caveat (D4), veto-bound
# printer, soft confirmation update (D7, literature check first), D9 domestic
# sanity pass, posterior_consensus default-column alignment.
# Previous update, 2026-08-26, continued (Fable 5, branch undetected-evidence-mixture --
# Chunk B (Phase 2 core) of the mixture redesign implemented: presence-mixture
# schema + moment-matched n_eff in TaxaExpect::apply_undetected_evidence() (free
# n_eff/n_eff_base knobs RETIRED; generators emit p_conc instead -- see the two new
# Recent Breaking Changes rows), presence-draw sampler in
# TaxaAssign::compute_posterior() (mixture rows bypass the J-guard via an explicit
# Bernoulli presence draw), prior_mix_* pass-through in join_priors(), and mixture
# clearing on confirmation in update_prior_from_consensus(). Three-way operative-
# column experiment on real GreatLakes2023: point_est 103 species obs (12 unique,
# 9 Lamar) vs J-guarded MC 95 (10, 7) vs mixture-aware MC 93 (10, 8) -- column
# choice is second-order vs w calibration; recommendation (verdict pending): keep
# posterior_point_est operative. Updated Lamar comparison (post-Phase-1 production
# consensus): species-consensus 12 taxa, 9 on Lamar's list (was 6/4 pre-fix). Both
# packages test 682/694 passed, 0 failed; check 0/0/0; reinstalled; all 6 real
# workflows' generator call sites migrated to p_conc. See
# ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md (D8 updated
# with the experiment result) and both packages' own top notes.
# Previous update, 2026-08-26 (Fable 5, branch undetected-evidence-mixture -- Phase 1 of the
# undetected-evidence MIXTURE REDESIGN implemented: TaxaAssign::join_priors()'s
# Session-117 modelled-species floor promotion scoped by cause, and
# TaxaExpect::apply_undetected_evidence() gains a ceiling anchor ladder for
# no-singleton datasets. Motivated by the same-day statistical review of GreatLakes2023
# conservative upranking (GreatLakes data/REVIEW_fable_conservative_upranking.md +
# REVIEW_uprank_ablation.R), whose central finding: the blanket promotion clamped every
# evidence_blend/domestic prior row to exact singleton parity, erasing the entire
# graded weight=exp(-d/150) design (consensus output byte-identical across a 4x d_half
# sweep; posteriors reduced to pure likelihood ratios, reproduced to 3 decimals;
# 3,326 rows promoted; yellow perch suppressed in 78 observations by the watch-listed,
# not-established-in-NA zander). Full settled design (all user verdicts recorded):
# ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md -- w reread as
# P(locally present | evidence) via a presence-mixture interpretation of the linear
# blend, moment-matched n_eff, per-dataset GBIF distance-curve fit, iNat as a third
# evidence generator, likelihood-side TaxaFlag surveillance caveat, soft (power-prior/
# soft-EM) confirmation update replacing the hard 0.8-threshold donor rule, and a
# mixture-aware compute_posterior() sampler feeding a three-way operative-column
# decision experiment. Phase 1 live-verified against the real GreatLakes2023
# checkpoints via the review's ablation harness: promotion 3,326 -> 112 rows;
# species-resolved observations 33 -> 103 (6 -> 12 unique species, 9/12
# Lamar-corroborated); the d_half sweep now changes real output (121 observations
# differ at d_half=75) -- the graded design finally reaches the posterior. Both
# packages devtools::test() 0 failures (TaxaAssign 670, TaxaExpect 689),
# devtools::check() 0/0/0, reinstalled. Phases 2-3 not started; the GreatLakes
# workflow's cached *_consensus_final.rds/posterior checkpoints are STALE for any
# re-run against the new install. See both packages' own CLAUDE.md top notes.
# Previous update, 2026-08-25 (Sonnet 5 -- uprank/downrank terminology audit, no code changes.
# PROMPT_uprank_downrank_consistency.md asked for a full-monorepo inventory of "uprank"/
# "downrank" usage against the agreed convention (uprank = toward a COARSER rank,
# downrank = toward a FINER rank), specifically flagging two suspected inconsistencies to
# verify directly against source: TaxaAssign::posterior_consensus()'s `downranked` output
# column, and TaxaAssign::generate_report()'s auto-generated methods/results narration.
# Grepped the whole monorepo (all 9 packages, inst/workflows, vignettes, tests, roxygen,
# man/*.Rd, ecosystem_docs, session-note archives) for uprank/downrank/upranked/downranked:
# 190 hits across ~40 files. Read every hit in context rather than trusting the count.
# Verdict: EVERY SINGLE occurrence already follows the agreed convention correctly --
# including the two specifically-flagged suspects. `.downrank_consensus()`/`downranked` in
# TaxaAssign::posterior_consensus() (R/posterior_consensus.R) narrows a coarse LCA to a
# FINER rank when species_reference shows exactly one plausible finer taxon (`downranked =
# TRUE` means "moved to a finer rank") -- correct, not backwards. generate_report()'s
# narration ("Upranked to coarser rank due to ambiguity", "Downranked to finer taxonomic
# level via species reference") is likewise correct. No inconsistency found anywhere: not
# in TaxaAssign::score_consensus()'s whitelist-upranking, TaxaFlag::review_assignments()/
# add_posthoc_assessment(), TaxaLikely::compute_likelihoods(), TaxaExpect's README/
# supplemental-methods prose, any package's CLAUDE.md, any man/*.Rd (auto-generated, so
# expected to match), any test file, or any ecosystem_docs design/audit doc. No breaking
# change, no rename, no reinstall needed -- this was a verification-only pass with a null
# result. Created (but did not need) a feature branch, `uprank-downrank-consistency`, per
# this ecosystem's own [[feedback_git_branches]] convention; no package source was touched.
# Recorded here so a future session doesn't re-run this same audit from scratch believing
# the two flagged spots are still open questions -- they were checked directly against
# source, not assumed correct.
# Previous update, 2026-08-23 (Sonnet 5 -- real-production confirmation of the GBIF synonym-
# resolution fix in generate_regional_proximity_evidence() (see the entry directly below):
# the user re-ran it against the full real 194-taxon GreatLakes2023 zero_bbox_taxa list.
# Result: 5 of 194 taxa elevated (up from 0), apply_undetected_evidence() correctly added 5
# new prior rows. Confirms the fix at real production scale, not just the single isolated
# case verified at implementation time. Pure verification, no code changes. See
# TaxaExpect/CLAUDE.md's own top note for the full record.
# Previous update, 2026-08-22, continued (Sonnet 5 -- a real, more serious PRE-EXISTING bug
# found when the batching change below was actually run at real production scale (194
# real GreatLakes2023 taxa): the user reported 0 of 194 elevated despite the log clearly
# showing dozens of real, quality-filtered Stage 2 fetches succeeding. Verified directly
# against the user's own real GBIF keys (not assumed): several real fish taxon names are
# GBIF SYNONYMS (e.g. "Erimonax monachus" -> usageKey 2367386, status SYNONYM, real
# occurrence records filed under the ACCEPTED name "Cyprinella monacha") -- GBIF's
# occurrence search transparently resolves a synonym key to its accepted key's real
# records (the fetch genuinely succeeds), but matching those records' `species` field
# against the ORIGINAL query name (what the code did) can never succeed, since the
# records are filed under the accepted name instead. This bug predates today's batching
# work entirely -- it existed identically in the original single-call resolver, just
# never exercised by the 3-species validation, since none of those three happen to be
# under active GBIF synonymy. Fixed by capturing GBIF's own resolved `species` name
# alongside the usageKey and using it (not the query string) for internal occurrence
# matching -- the OUTPUT `taxon_name` still reports the original query name, so the
# caller's own join key is unaffected. Live re-verified against the user's exact real
# case: "Erimonax monachus" now correctly produces a real evidence row instead of
# silently vanishing, while the two already-working species reproduce byte-identical
# results. `devtools::test()` 665/665 (up from 654), `devtools::check()` 0/0/0,
# reinstalled. See TaxaExpect/CLAUDE.md's own 2026-08-22-continued top note for the full
# investigation record.
# Previous update, 2026-08-22 (Sonnet 5 -- generate_regional_proximity_evidence()'s per-taxon
# GBIF-key resolution replaced with one batched rgbif::name_backbone_checklist() call,
# after the user asked whether more efficient GBIF query modes exist for its "one taxon at
# a time" Stage 0 step. Investigated with real, live rgbif tests (not assumed) before
# writing any code: Stage 0 (name -> key) is a genuine batching win (11 individual calls
# 3.51s vs. 1 batched call 1.17s, correctness identical including the pathological bare-
# genus-resolves-to-a-coarser-rank case); Stage 2 (occurrence fetch) was investigated and
# explicitly REJECTED as a batching opportunity once `rgbif::occ_data(taxonKey = vector)`
# was confirmed to be a client-side loop (`attr(., "type") == "many"`, one real HTTP request
# per key) rather than a true single-request batch -- and `TaxaFetch::fetch_gbif_
# occurrences()`'s own internal per-key loop does the identical thing, so the ecosystem's
# existing "combine taxa into one call" convention there is a code-convenience abstraction,
# not a real network-request reduction. Live end-to-end re-verified against the installed
# package and the real GBIF API: reproduces byte-identical real numbers to the original
# pre-batching verification for the same three motivating species. `devtools::test()`
# 654/654 (up from 641), `devtools::check()` 0/0/0, reinstalled. Also fixed, found only by
# running TaxaExpect's full suite for the first time since the "Ictalurus" fix below landed:
# 3 pre-existing test assertions in `test-generate_domestic_food_priors.R` broke on
# `clean_taxon_names()`'s new `collapsed_to_genus` attribute (that fix's own verification
# only ran TaxaTools's/TaxaMatch's suites) -- fixed the same way as TaxaTools's own test
# suite (`ignore_attr = "collapsed_to_genus"`); confirmed via grep this was the only
# ecosystem-wide fallout. See TaxaExpect/CLAUDE.md's own 2026-08-22 top note for the full
# record, including why Stage 2 batching was rejected.
# Previous update, 2026-08-21, still later (Sonnet 5 -- the "Ictalurus" root-cause fix directly
# below was verified against a REAL re-run of GreatLakes2023 and still found 33 stale rows --
# the first fix was real but incomplete, not a stale-cache artifact. Root-caused a SECOND,
# structurally different failure mode by reading the real query's own `taxonomy_collision`
# value directly, not by guessing: NCBI's own taxonomy DB genuinely contains real leaf-level
# nodes for informally-named specimens (e.g. `"Ictalurus sp. UM 105-1789"`), RANKED "species"
# BY NCBI ITSELF -- found in the target backbone, `matched_rank` genuinely IS "species" (fully
# backbone-consistent, so the existing rank-mismatch-driven correction correctly does nothing
# at all), but the classification path's own species-rank VALUE is that same informal label,
# which `clean_taxon_names()` correctly collapses to "Ictalurus" -- a case no rank-MISMATCH-
# based correction can ever catch, since the backbone's own rank claim is genuinely self-
# consistent. Generalized the not-found-only fix into ONE unified mechanism covering all
# three sources that can populate `taxon_name` in `TaxaMatch::convert_taxonomy_backbone()`,
# rather than adding a third parallel patch. Deliberately rejected a shape-based re-
# derivation (`TaxaTools::is_plausible_binomial()` on the final value) in favor of tracking
# the actual collapse event through the pipeline -- the shape-based regex would have wrongly
# demoted every real hyphenated-genus species (e.g. *Pseudo-nitzschia*), confirmed via a
# dedicated regression test. Live-verified against the installed package for both real cases
# side by side. `devtools::test()` 883/883 (up from 876), `devtools::check()` 0/0/0,
# reinstalled. See TaxaMatch/CLAUDE.md's own 2026-08-21-continued top note for the full
# second-round investigation.
# Previous update, 2026-08-21, later still (Sonnet 5 -- root-cause fix for the real "Ictalurus"
# bug found live-debugging the GreatLakes2023 regional-proximity work below: 33 real
# `match_obj_restored` rows had `taxon_name = "Ictalurus"` (bare genus) but
# `taxon_name_rank = "species"`, having already been shown to cause a genus-vs-species
# GBIF-lookup bug in `generate_regional_proximity_evidence()` (fixed there as a downstream
# safeguard, this session's earlier work). Per the user's explicit "we have not shipped the
# package... a robust way to fix this problem that does not require repeated post-hoc
# fixes" instruction, traced the full function chain rather than patching the symptom:
# `TaxaTools::clean_taxon_names()` gains a new `collapsed_to_genus` attribute (surfacing an
# already-computed-but-discarded internal signal); `TaxaMatch::convert_taxonomy_backbone()`
# gains a second, independent rank-correction mechanism for NOT-found rows (the existing
# 2026-07-25 "Inu Inu" mechanism only ever covers rows the target backbone DID find, just at
# a coarser rank) using that new attribute. Confirmed `TaxaTools::fill_higher_ranks()` is
# genuinely unrelated (different signal, doesn't call `clean_taxon_names()`) before
# concluding the fix belonged in exactly these two places. Both packages' `devtools::test()`/
# `check()` clean (TaxaTools 847/847, TaxaMatch 876/876; 0/0/{0,1} both, the 1 note pre-
# existing/environmental), both reinstalled and live-verified end to end against the
# installed packages. See TaxaTools/CLAUDE.md's and TaxaMatch/CLAUDE.md's own 2026-08-21
# top session notes for the full chain-of-functions investigation and fix record.
# Previous update, 2026-08-21, later same day (Sonnet 5 -- builds
# TaxaExpect::generate_regional_proximity_evidence(), the regional-proximity thread's own
# evidence generator, closing out ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_
# check.md against the shared TaxaExpect::apply_undetected_evidence() applier the parallel
# invasive-watch-list chat built (see the entries directly below). Two-stage design, exactly
# as planned: Stage 1 (cheap gate) calls TaxaFlag::check_gbif_tile_range() per candidate
# taxon (after resolving a GBIF backbone key via a new internal .resolve_gbif_taxon_key(),
# rgbif::name_backbone()); species with beyond_buffer = TRUE cost nothing further. Stage 2
# (real, filtered fetch, only for species Stage 1 found something for) scopes a real
# TaxaFetch::get_gbif_occurrences() call to a buffer sized from Stage 1's own reported
# distance (clamped [50km, 1000km]), runs it through TaxaFetch::filter_gbif_quality() (the
# eDNA/coordinate-quality screening Stage 1's raw density tiles structurally cannot
# provide), then reads the real distance and the matched record's age via
# TaxaFlag::compute_local_occurrence_distance() (extended this session with a new date_col
# param -- fully backward compatible, NULL default). Distance drives weight
# (exp(-distance_km/d_half)); age drives n_eff independently (n_eff_base *
# exp(-age_years/age_half)) -- age widens/narrows confidence, never shifts the mean, per the
# design conversation's own resolution of "an old record could mean a real unresurveyed
# population or a contracted range, and occurrence data alone can't tell." Both
# d_half/age_half ship with a default but are fully documented/overridable, per explicit
# user direction (not the "no default, errors if omitted" convention used elsewhere in this
# ecosystem for values with no defensible number). Watershed/basin connectivity was
# explicitly dropped from scope earlier in this same design thread (this package needs to
# stay simple/generic across taxa and geography); the geographic-plausibility judgment goes
# to a human/LLM reviewer instead of a hardcoded gate.
#
# Live-verified against the real GBIF API, not just synthetic tests -- the same three
# species the very first reentry-doc session flagged as the real motivating case
# (Etheostoma chlorosomum/Ictalurus furcatus/Alburnus alburnus, GreatLakes2023, lat=41.4/
# lng=-86.7): E. chlorosomum resolved to a real record 74km away from 1986 (40 years old --
# confirming the reentry doc's own "mostly dated" recollection with a real number),
# weight=0.612/n_eff=0.347 (a real pull, appropriately loosely held given the record's
# age); I. furcatus 83km/1999/weight=0.575/n_eff=0.826; A. alburnus's nearest tile hit was
# ~1690km away, beyond the 1000km fetch-buffer cap, so Stage 2 correctly found nothing and
# the species got no evidence row at all rather than a fabricated number.
#
# TaxaFlag devtools::test() 419/419 (up from 415), TaxaExpect devtools::test() 641/641 (up
# from 614), both devtools::check() 0/0/0. Both reinstalled via ecosystem_docs/
# install_all.R and verified against the installed copies directly. Both this session's own
# generator and the applier it targets were read/verified directly against source before
# either side trusted the other's summary -- see the 2026-08-20 entry below for two real,
# unrelated production bugs (TaxaExpect::generate_domestic_food_priors()/
# TaxaAssign::join_priors()) found and fixed along the way while cross-checking the
# applier's design. See TaxaExpect/CLAUDE.md's and TaxaFlag/CLAUDE.md's own top session
# notes, and ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md's own new
# "Resolved" section, for the full per-package record.
# Previous update, 2026-08-21 (Sonnet 5 -- real-data verification of the invasive-watch-list
# evidence mechanism (TaxaExpect::generate_invasive_watch_evidence()/
# apply_undetected_evidence(), built 2026-08-20 -- see the entry directly below for the full
# design record). Wired by the user into the real production
# GreatLakes2023_ConsensusWorkflow.R. Real result: Gymnocephalus cernua (Ruffe), with zero
# occurrence evidence in this dataset, correctly elevated from the dark-diversity floor;
# Neogobius melanostomus (Round Goby), on the same watch list, correctly left untouched
# because it already has a real, occurrence-fitted tier1 model prior -- confirming the
# "already observed" exclusion logic works against a real production taxaexpect_priors
# table, not just synthetic fixtures. Pure verification, no code changes. See
# TaxaExpect/CLAUDE.md's and ecosystem_docs/REENTRY_PROMPT_invasive_species_watch_list_
# priors.md's own top/new sections for the full record.
# Previous update, 2026-08-20, continued yet further (Sonnet 5 -- the invasive-species watch-list
# prior mechanism (ecosystem_docs/REENTRY_PROMPT_invasive_species_watch_list_priors.md) is
# redesigned and re-implemented, closing out the real-time cross-session negotiation with the
# concurrent regional-proximity chat recorded in the entry directly below. Two real
# architecture corrections came out of that negotiation, both landed the same session:
#
# (1) The first pass (a live USGS NAS API query + HUC8 watershed scoping, built and verified
# working earlier the same day) was REMOVED at the user's direct instruction: TaxaID is meant
# to stay a generic, taxon-/geography-agnostic toolkit, and a narrow (aquatic-only, US-only)
# external database plus freshwater-specific watershed math doesn't belong baked into a
# package function -- see TaxaFetch/CLAUDE.md's removal note for the distinguishing principle
# (broad infrastructure like iNat/GBIF, already relied on elsewhere, is fine; a single-
# country single-taxon-group database is not).
#
# (2) The replacement mechanism converged with the regional-proximity chat's own design onto
# one shared architecture, reached via several rounds of direct cross-session messages (both
# sides' full exchange is summarized in each package's own top session note --
# TaxaExpect/CLAUDE.md carries the fullest record). The key insight: neither mechanism has a
# real per-species "dark diversity prior" object to adjust -- generate_undetected_diversity()
# emits one anonymous global_floor row, applied generically by TaxaAssign::join_priors() at
# join time -- so "elevate this species' floor" has to mean creating a genuinely named row.
# Once the user required the two mechanisms to compose ADDITIVELY (a species both nearby and
# invasive-listed should read higher than either alone, capped at the singleton-mirror
# ceiling), having each mechanism independently bind_rows() its own row became a real bug
# risk (two rows sharing one join key is an ambiguous join) -- fixed architecturally by
# splitting each mechanism into a thin evidence generator (taxon_name/weight/n_eff/source, no
# prior-construction knowledge) and one shared applier,
# TaxaExpect::apply_undetected_evidence(), that is the only place a new row is ever written.
# generate_domestic_food_priors() was deliberately excluded from ever feeding this shared
# applier -- a food/domestic detection and an occurrence-plausibility detection are opposite
# claims about the same zero-detection fact (contamination-risk vs. genuine population), not
# combinable evidence.
#
# TaxaExpect devtools::test() 614/614, devtools::check() 0/0/0; TaxaFetch devtools::test()
# 619/619 (2 pre-existing, unrelated CoordinateCleaner/terra environment failures),
# devtools::check() 0/0/0. Both reinstalled. Live-verified end to end through the REAL
# pipeline (create_sites_from_grid() through generate_undetected_diversity() through the new
# evidence mechanism), not just synthetic test fixtures. See TaxaExpect/CLAUDE.md's and
# TaxaFetch/CLAUDE.md's own top session notes and the reentry doc's own new "Resolved"
# section for the complete record.
# Previous update, 2026-08-20, later same day (Sonnet 5 -- real production bug found and fixed
# while cross-session-collaborating on the regional-proximity/invasive-watch prior-mechanism
# design (see ecosystem_docs/REENTRY_PROMPT_regional_proximity_prior_check.md). Diagnosing
# how a habitat-agnostic evidence source should join into taxaexpect_priors surfaced a real
# question about TaxaExpect::generate_domestic_food_priors() (the existing precedent both
# design threads were citing), which the user then confirmed empirically on their own real
# GreatLakes2023 data before any fix was written: a real Gadus morhua domestic-food row
# (alpha=5, beta=8775, theta ~= 0.00057) never actually applied to the matching real
# observation -- TaxaAssign::join_priors() gave it theta ~= 0.000167 instead (~3.4x lower,
# the ordinary group-dark-diversity fallback), meaning this function's whole elevated-prior
# mechanism has been silently inert for every habitat-scoped study since it shipped
# (2026-07-23). Root cause, two independent gaps in the SAME rows: taxon_name_rank was never
# set (defaulted NA via bind_rows(), now fixed to "species"); main_habitat is deliberately
# NA (a food species has no single correct habitat -- a grid_id can span several, and
# plausibility here is governed by human food supply, not habitat suitability) but
# join_priors()'s primary composite-key join treated NA as literal, not a wildcard. Fixed at
# the correct layer per the user's own explicit framing ("food does not have a habitat" --
# don't stamp a real habitat value, fix the join instead): join_priors() gains a new
# habitat-agnostic named-species prior fallback tier, re-matching a failed primary-join row
# on (taxon_name, taxon_name_rank, grid_id) alone against main_habitat = NA rows, ranked
# below a real per-habitat match and above the generic floor -- a general primitive, not a
# food-specific patch, reusable by any future habitat-agnostic evidence source (flagged to
# the parallel invasive-watch-list design chat, whose regional/watch-list evidence was
# judged to legitimately want to STAY habitat-aware, unlike food -- a freshwater species
# found nearby is only plausible in a freshwater habitat locally, a real physical
# constraint food doesn't have). TaxaExpect devtools::test() 586/586 (up from 580),
# devtools::check() 0/0/0; TaxaAssign devtools::test() 664/664 (up from 655), devtools::check()
# 0/0/0. Both reinstalled via ecosystem_docs/install_all.R and verified against the
# installed copies directly (not just the reinstall command's exit status). See
# TaxaExpect/CLAUDE.md's and TaxaAssign/CLAUDE.md's own top session notes for the full
# per-package record, and this file's own Recent Breaking Changes table below for the two
# new rows.
# Previous update, 2026-08-20 (Sonnet 5 -- initiates ecosystem_docs/REENTRY_PROMPT_
# invasive_species_watch_list_priors.md end to end, the same day it was written (a design-
# idea reentry doc prompted by the user reviewing real GreatLakes2023 output: Alburnus
# alburnus has zero GBIF records in the study bbox, correctly reflecting genuine local
# absence, but has a real North American invasion record the user recalled from domain
# knowledge -- should a species on a documented invasive-species watch list get an elevated
# prior the way generate_domestic_food_priors() already does for domestic species?). New
# TaxaFetch::fetch_nas_occurrences()/lookup_huc8() (acquisition side, live-queries the real
# USGS Nonindigenous Aquatic Species API and Watershed Boundary Dataset) feed new
# TaxaExpect::generate_invasive_watch_priors() (prior-generation side, architecturally
# mirroring generate_domestic_food_priors() -- named taxon_name rows, match_list_taxa-gated,
# prior_source_type categorical column). Full design record, real-API verification, and the
# real Alburnus/Ruffe live-test results are in TaxaFetch/CLAUDE.md's and TaxaExpect/
# CLAUDE.md's own top session notes -- summarized here: (1) the reentry doc's own design
# question 1 ("check whether NAS has a queryable API before committing to a design") was
# answered by directly querying the real API before writing any code -- yes, a real, no-key-
# needed JSON API exists, and its per-record `status` field (established/stocked/collected/
# failed/unknown) and huc8/10/12 codes turned out to answer the doc's own design questions
# 2 (tiering) and 3 (regional scoping) almost for free. (2) A real, load-bearing finding from
# that same API check: NAS is United States-only and has ZERO entries for Alburnus alburnus
# -- the species that motivated the whole doc -- confirmed via NAS's full species catalog
# plus a live global GBIF cross-check (133 real 2019-2021 Canadian eDNA MATERIAL_SAMPLE
# records exist, no vouchered specimen, no NAS-trackable establishment signal). Presented to
# the user directly (AskUserQuestion) before proceeding rather than silently building around
# or past it; user chose "NAS only, for now," explicitly accepting this as a known,
# documented gap over a broader (weaker-confidence) global-GBIF-fallback alternative that was
# offered and declined. (3) Live end-to-end verification against the real APIs found a
# genuine, non-trivial correctness result, not just a passing test suite: Gymnocephalus
# cernua (Ruffe, a real, famous Great Lakes invader) correctly resolves to
# "nonindigenous_watch" rather than "nonindigenous_established" at a real southern-Lake-
# Michigan HUC8, because NAS's own establishment records for Ruffe concentrate in the Lake
# Superior/Duluth-Superior basin -- a genuinely different HUC8 -- demonstrating the two-tier
# design correctly distinguishes "established somewhere in the US" from "established in THIS
# region," on real data. Both packages' `devtools::test()`/`check()` clean (TaxaFetch
# 671/671, 2 pre-existing unrelated CoordinateCleaner/terra environment failures; TaxaExpect
# 580/580, 0/0/0), both reinstalled. Companion doc REENTRY_PROMPT_regional_proximity_prior_
# check.md remains untouched -- its own text says the machinery-sharing question with this
# mechanism "probably shouldn't be decided until at least one of the two is prototyped
# against real data," and this session prototyped only the invasive-watch side.
# Previous update, 2026-08-18 (Sonnet 5 -- closes out a real, previously-unnoticed train/inference
# reference-screening inconsistency the user asked to discuss after the same-day TaxaMatch
# rate-limit-resilience work: does TaxaLikely::train_likelihood_model() screen its own training
# reference_df at all, given TaxaMatch::evaluate_reference_accessions()/
# flag_incongruent_references() exist to screen match-candidate accessions? First answer given
# was WRONG (grepped only for external workflow calls to flag_reference_errors()/
# remove_flagged_references(), found none, concluded no screening happens) -- corrected after
# the user pushed back ("I had thought this was the whole point of the code we wrote"):
# train_likelihood_model() calls flag_reference_errors() UNCONDITIONALLY on every real training
# run (R/train.R:940-950, "Removing mislabeled references...") and silently drops every
# "likely_mislabeled" accession before fitting H1/H2/H3 -- this has always been true, just never
# checked by reading the function body instead of grepping for external callers. So training IS
# screened, automatically, using the OLDER, known-over-flagging heuristic (2026-08-08 audit:
# 39% same-submission-batch artifacts + 61% tight-congener false positives), while TaxaMatch's
# newer, stronger BLAST-based screen exists but isn't even switched on yet in the one real
# workflow that computes it (AuditNCBI_Goal2_MatchCandidateScreen.R's own
# flag_incongruent_references() call is still commented out, pending review).
#
# Real numbers gathered before recommending anything (not guessed): GreatLakes 12S training
# reference_df is actually LARGER than the match-candidate population TaxaMatch's rate-limit
# work was built for this same day (2,638-2,653 unique accessions vs. the 1,183-accession Goal-2
# run that already tripped a real NCBI CPU-budget rejection) -- ruling out "just BLAST the whole
# training set with the better tool" as a naive fix, given the user's explicit concern about
# repeated NCBI shutouts. flag_reference_errors() itself flags 231/280 accessions
# "likely_mislabeled" per dataset (~9-11%) -- the ONLY category train_likelihood_model() actually
# removes by default ("unverified_singleton_high_match" is computed but never acted on). A real,
# live 40-accession pilot BLAST verification of BurnsHarbor's "likely_mislabeled" subset (run in
# the background, ~40 min real NCBI queue time) found **0 of 40 confirmed as genuine mislabels;
# 34/40 (85%) "congruent" (false positives), 6/40 "insufficient_independent_evidence"** -- a
# concrete, real confirmation that this over-flagging is not hypothetical for this dataset.
#
# Design chosen (per the user's explicit direction: "skip straight to building the correction
# mechanism"), deliberately NOT touching train_likelihood_model()'s existing, always-on
# flag_reference_errors() call (a "don't break what works" constraint the user raised directly)
# and deliberately NOT BLASTing the whole reference set (the NCBI-cost constraint): (1)
# TaxaLikely::flag_reference_errors() gains `verified_clean` (character vector of accession IDs,
# default NULL) -- forces those accessions to `error_type = "clean"` regardless of what the
# heuristic computes, so a confirmed false positive survives every future retrain without needing
# reference_df pre-filtering (which alone wouldn't work -- the SAME accessions would just get
# re-flagged and re-removed on the next call, since nothing about removing OTHER accessions
# changes why one specific accession trips the heuristic). Only ever rescues, never removes.
# `train_likelihood_model()` gains the identical param, forwarded straight to its internal call.
# (2) New `TaxaMatch::verify_flagged_references()` (R/evaluate_reference_accessions.R) bridges
# the two packages without adding a new cross-package Imports dependency either direction
# (confirmed TaxaLikely's DESCRIPTION has no TaxaMatch dependency; the bridge lives in TaxaMatch,
# which already owns evaluate_reference_accessions()) -- takes flag_reference_errors()'s own
# output (or a plain accession vector), screens ONLY the flagged subset (default
# error_types = "likely_mislabeled", matching what train_likelihood_model() actually removes;
# "unverified_singleton_high_match" is opt-in via error_types, since verifying it too would
# roughly double NCBI cost for a category that changes nothing today), and returns
# `verified_clean` -- everything NOT confirmed `"incongruent"` -- ready to pass straight into
# `flag_reference_errors(verified_clean=)`/`train_likelihood_model(verified_clean=)`. Turns
# "BLAST thousands of training accessions" into "BLAST only the ~230-280 actually disputed."
# `cache_dir` shares evaluate_reference_accessions()'s own default and convention -- pointing it
# at the SAME project cache_dir a real match-candidate screen already used means any accession
# appearing in both populations (real, if limited, overlap exists) is served free from cache.
#
# 12 new tests (TaxaLikely: 6 in test-train.R, including one exercising the full
# train_likelihood_model() pipeline via the existing 5-species .make_genus_raw_df() fixture --
# had to relocate the new test block below that fixture's own definition after a first attempt
# failed with "could not find function" from being sourced before the fixture existed;
# TaxaMatch: 7 in new test-verify-flagged-references.R, offline via
# local_mocked_bindings(evaluate_reference_accessions=, .package="TaxaMatch"), covering the
# data-frame/character-vector input forms, error_types scoping, trust_insufficient_evidence,
# the "incongruent never counts as verified" invariant, the zero-NCBI-call short circuit when
# nothing matches, and input validation). devtools::test() 0 failures both packages (TaxaLikely
# 1051/1051 up from 1040, TaxaMatch 845/845 up from 832), devtools::check() 0/0/0 both,
# reinstalled and verified at ~/Library/R/4.0/library. Not yet run against the FULL real
# 231/280-accession "likely_mislabeled" populations (only the 40-accession BurnsHarbor pilot) --
# left for the user to run when ready, using the new verify_flagged_references() mechanism
# directly rather than the throwaway pilot script (DoesTrainingScreenMatter_Pilot.R, GreatLakes
# data directory, not under git).
# Previous update, 2026-08-09 (Sonnet 5 -- TaxaWizard's first full code + domain review against
# inst/Code and Domain Review 2.Rmd, closing the last gap in this ecosystem's review coverage
# (every other package already had one). Findings + fixes recorded in new TaxaWizard/inst/
# taxawizard_review.Rmd. Two real, fixed security findings: an eval(parse(text = input$...))
# call in every workflow_app()-generated Shiny app had no server-side validation against its
# nominally-fixed selectInput() choices, a real code-injection vector in any deployed/shared
# app (fixed with a shared allow-list checked before eval()); .save_session() persisted
# api_key/llm_fn (often a closure capturing a provider key) to a plaintext tempdir() RDS with
# default permissions (now chmod'd 0600). Also fixed: .generate_app() was a non-functional
# placeholder despite a complete app generator (workflow_app()) already existing in the same
# package -- now delegates to it; workflow_engine()'s model default didn't match its own
# documented design (opus vs. the intended sonnet); the last `df`-shadows-stats::df() instance
# in the ecosystem; an undeclared `lifecycle` roxygen-time dependency; three orphaned ~120KB
# *.rds fixtures bundled into every install with zero references anywhere. New
# tests/testthat/test-output.R closes the largest test-coverage gap (the actual script-
# generation logic behind this package's core deliverable had zero prior coverage). New
# TaxaWizard/inst/taxawizard_reviewer_demo.R exercises every exported function against a real
# Azure OpenAI (DOI) backend via an explicit llm_fn closure (TaxaWizard has no hard TaxaTools
# dependency, so this is the documented way to point it at Azure), plus an offline-only
# section needing no API key. `devtools::test()` 696/696 (up from 655), `devtools::check()`
# 0/0/0 (unchanged), reinstalled and verified at ~/Library/R/4.0/library. See TaxaWizard/
# CLAUDE.md's own top session note for the full record.
# Previous update, 2026-08-08, continued yet again (Sonnet 5 -- closed out ecosystem_docs/
# REENTRY_PROMPT_screening_approach_comparison_audit.md (Q3 of the day's 3-question thread):
# does TaxaLikely::flag_reference_errors() (the REAL live "old" pre-training reference screen,
# confirmed against remove_flagged_references()'s production wiring, NOT the archived DECIPHER
# classify_reference_accessions()) flag more references than TaxaMatch::
# evaluate_reference_accessions() (the NEW BLAST-based screen) because it's genuinely more
# sensitive, or a real structural false-positive mode? Pure empirical analysis, no code
# touched -- and no new BLAST/NCBI calls needed, since the raw materials already existed from a
# 2026-08-07 session one day before this reentry doc was written (its own "design-only, not
# started" header was stale). Answer, from the real full 10,701-accession GreatLakes 12S
# database plus a 132-accession sample evaluated by both tools: BOTH hypotheses hold, for
# different subsets, not one or the other. Of old's 28 "old-only" flags (vs. new), 39.3% are
# confirmed real same-submission-batch artifacts (via .same_submission_batch(), exactly the
# PV382872-class false positive the new tool's independence filter exists to close) -- but the
# other 60.7% are a SEPARATE false-positive mode an independence filter alone would NOT fix:
# small negative integrity_gap against a tight congener (Cephalopholis/Epinephelus/Phoxinus,
# all documented cryptic-species-rich genera) where the new tool finds real independent
# corroborating evidence the old tool's narrow same-database comparison structurally can't see.
# Old also has a genuine, narrower blind spot the new tool closes: 3 new-only flags are all
# singletons whose max_foreign_match (0.93) never clears flag_reference_errors()'s hardcoded
# singleton_match_threshold (0.98), even though 2 of 3 disagree with independent evidence at
# CLASS rank -- a real taxonomic red flag a hierarchy-congruence check catches and a flat
# percent-identity threshold structurally cannot express. Ground-truth cross-check (10 real
# adjudicated GreatLakes accessions, including the one confirmed candidate_mislabel positive
# control MZ605481) found zero disagreements between the two tools -- and surfaced that the
# famous "Menidia false positive" motivating the whole BLAST-based redesign was NEVER actually
# a flag_reference_errors() problem (error_type="clean" for all 4 Menidia accessions,
# correctly) -- it was specific to the archived DECIPHER hierarchy check, a design abandoned
# before reaching production. Recommendation: an independence filter alone for
# flag_reference_errors() (this doc's own originally-floated "smaller, more surgical fix")
# would only address ~39% of its real over-flagging -- evaluate_reference_accessions() should
# be the recommended pre-training screen going forward, with flag_reference_errors() (if kept
# at all) treated as high-recall/low-precision (~6.7% precision against the new tool's
# verdict on this sample), worth a review pass, not an auto-blacklist. New, reusable
# diagnostics/greatlakes_screening_approach_comparison_analysis.R reproduces every number
# above from existing checkpoints (verified to run end to end); the reentry doc itself now
# carries the full write-up. No package code changed, no reinstall needed.
# Previous update, 2026-08-08, continued (Sonnet 5 -- TaxaLikely's first human-authored code +
# domain review response (Micah Wright, replacing the prior Claude-authored review's
# response doc entirely -- see TaxaLikely/inst/taxalikely_review_response.md and
# TaxaLikely/CLAUDE.md's own top session note for the full comment-by-comment record). 17 real
# bugs fixed, all input-validation/messaging/documentation/dead-code/naming -- no statistical
# formula touched: assign_scores()'s no-H1 branch reported score_likelihood_sd = 0 instead of
# NA; a genuine split-string sprintf() bug (this project's own documented recurring footgun)
# in restore_suppressed_candidates()'s no-score verbose message; flag_reference_errors()'s
# 0.98 singleton-match threshold was hardcoded with a comment suggesting it be adjustable but
# no actual parameter -- now real (singleton_match_threshold, additive); .parse_lat_lon() had
# no coordinate-plausibility guard; an unexplained 1985 date-floor literal inconsistent with
# this ecosystem's own "1900/01/01" sentinel convention; plus df/file/line base-function-
# shadowing fixes, including one EXPORTED signature change (read_crabs_output(file=) ->
# crabs_file=, propagated to its one real cross-package caller in TaxaWizard). Dead code
# removed: audit_barcode_coverage_gbif() (confirmed via full monorepo grep + NAMESPACE:
# unexported, untested, zero real callers -- a genuinely abandoned draft, not just a
# stylistic duplicate as the reviewer described it) and rgbif dropped from Suggests. Several
# real statistical/design questions answered in full with verified derivations rather than
# deflected (transform.R's 99.3%/50% gap-ceiling thresholds -- confirmed by direct computation
# that 5.0, not 99.3%, is the actually-chosen value; train.R's pseudo-data anchoring confirmed
# to be a real Bayesian mechanism via the standard prior-as-pseudo-observations equivalence,
# not a workaround). devtools::test() 974 pass/0 fail/56 warn (expected, matching this
# package's own prior documented baseline)/1 skip; devtools::check() 0/0/0 (run twice);
# lintr::lint_dir("R") 0 hits; reinstalled, verified at ~/Library/R/4.0/library.
#
# Note, found while reconciling test counts, resolved (NOT data loss, NOT part of the human
# review): TaxaLikely's own CLAUDE.md documents a "Module B-QC2" reference-database-auditing
# feature set (audit_reference_database()/classify_reference_accessions()/
# repair_thin_evidence()/.compute_hierarchy_congruence(), 2026-08-04 through 2026-08-06
# entries) that is absent from the current TaxaLikely source tree -- initially looked like data
# loss, but is actually a real, already-documented, already-completed archival: the same
# 2026-08-06/07 design session that built this module found it has a genuine false-positive
# mode (real Smithsonian-vouchered accessions flagged "incongruent" purely from a too-narrow
# taxon-list-scoped comparison population) and a structural false-negative gap, abandoned the
# whole DECIPHER-based approach, and moved its source + tests intact to
# TaxaLikely/archive_decipher_reference_audit/ (deliberately gitignored, confirmed present on
# disk) -- see ecosystem_docs/REENTRY_PROMPT_blast_based_reference_quality.md. Its BLAST-based
# replacement is fully designed there but explicitly not yet implemented. This explains the
# ~101-test gap between this session's observed devtools::test() count (974) and TaxaLikely/
# CLAUDE.md's own (now-superseded) 2026-08-06 claim of 1075. The one real, still-open gap: that
# file's 2026-08-04 through 2026-08-06 entries still describe the archived module as live
# shipped code -- a documentation-drift cleanup flagged for whenever the BLAST-based
# replacement is actually built, not attempted this session.
# Previous update, 2026-08-08 (Sonnet 5 -- TaxaFetch's first human-authored code + domain review
# response (the user replaced the old Claude-authored inst/taxafetch_review.Rmd, Session 148,
# with a fresh human-authored one by Micah Wright, same 24-file structure). Full record in
# TaxaFetch/inst/taxafetch_review_response.md and TaxaFetch/CLAUDE.md's own top session note.
# Nine real bugs found and fixed, each confirmed via direct standalone testing before
# shipping, not just reading the diff: search_dataone()'s coordinate parsing never matched
# PASTA's real spatialCoverage/coordinates XML structure or its Solr
# ENVELOPE(minX,maxX,maxY,minY) string (coordinates_raw was NA for every real record,
# reproduced with the reviewer's own live SBC LTER example); dataone_catalog.R's authors/
# keywords_str columns came back NA for every real record (XPath now tries several real
# candidate node shapes); dataone_standardize.R's .extract_eml_sites() site-code regex
# silently failed on any geographicDescription containing an embedded newline (missing PCRE
# (?s) flag -- the same documented footgun class already in this package's own Known
# Footguns section, reproduced with the reviewer's real "ABUR: Arroyo Burro Reef..."
# example); fetch_gbif_occurrences(year_range = NULL) crashed with cache_dir enabled -- a
# real, reachable path via TaxaExpect::build_priors()'s own year_range=NULL default
# forwarding straight through; a shared hardcoded year_range default ("2000,2024", identical
# across five functions) was already silently excluding all 2025+ GBIF data for any
# default-argument caller by the time of this review, fixed with a call-time-computed
# default instead of a fixed literal (see Recent Breaking Changes below); filter_gbif_
# quality()'s basisOfRecord filter compared exact case/whitespace, inconsistent with its own
# occurrenceStatus filter's normalization; pdf_extract.R was applying TaxaTools's
# deliberately NULL-only %||% to four screen_pdf_structure() axis fields that explicitly
# return NA_character_ (not NULL) on LLM-characterization failure, confirmed via a real
# bundled PDF where every one of these fields came back NA and stayed NA through prompt
# building; pdf_text.R's two-column-layout header detection never matched a NUMBERED header
# ("2.1 RESULTS ...") since it tested against the raw line without first stripping the
# leading number the way its own single-column pass already does; pdf_api.R's
# build_pdf_extract_prompt() @examples used entirely wrong parameter names. Also fixed: a
# stale "TaxaExpect --" header banner (pre-Session-19-split doc drift) in 7 files; pdf_api.R
# and this package's own Function Inventory table both still claimed call_api_pdf() was
# "Anthropic-only," predating Session 87's provider generalization (the function body itself
# already dispatched through TaxaTools::call_api(), only the docs were wrong); two real
# df-shadows-stats::df() local-variable violations (dataone_taxon_screening.R,
# pdf_extract.R, matching this ecosystem's established df -> input_df convention); several
# genuine DRY duplications consolidated. Several other review comments were investigated and
# found to be already-correct design or genuine-but-out-of-scope architecture questions
# flagged for a future session rather than fixed unilaterally (data.frame vs. tibble
# consistency ecosystem-wide; EDIutils adoption; httr vs. httr2 consistency; three separate
# .bbox_overlaps()-style implementations across three files; inconsistent bbox-argument
# conventions within TaxaFetch's own functions) -- see the response doc for the full
# file-by-file record, including reviewer suggestions that were checked and found incorrect
# before being rejected (not just dismissed). New test coverage for 3 previously-untested
# files. TaxaFetch devtools::test() 616/618 (2 pre-existing failures, confirmed via git
# stash to be present and identical before this session -- a CoordinateCleaner/terra/sf
# environment version issue, unrelated to any fix here), up from 565/565; devtools::check()
# 0 errors/0 warnings/0 notes; reinstalled and verified at ~/Library/R/4.0/library.
# Previous update, 2026-08-08 (Sonnet 5 -- implements ecosystem_docs/REENTRY_PROMPT_
# investigate_flagged_accession_prefilter_group_posthoc.md's top three menu items, per that
# doc's own priority ranking: (1) TaxaMatch::investigate_flagged_accession()'s two
# comparisons now run via BLAST itself (new internal .blast_against_comparison_set(),
# reusing blast_sequences()'s own proven coverage-safety) instead of a hand-rolled
# pwalign::pairwiseAlignment() loop -- fixes the real MZ605481 "inconclusive in both
# directions" regression the reentry doc itself documents (a short amplicon vs.
# length-unaware NCBI species search returning mostly full mitogenomes). (2) new
# TaxaMatch::check_marker_mismatch() -- a single cheap GBSeq feature-table fetch
# cross-checking a flagged accession's own annotated /gene or /product qualifier against
# the marker an evaluation was scoped to, directly grounded in the real confirmed AY850362
# marker-mislabel case (a hypothesis based on taxonomic rank of disagreement was tried
# first and refuted directly against MZ605481, a real species mislabel that ALSO disagrees
# only at a coarse rank). (3) investigate_flagged_accession() gains a persistent,
# asymmetric-TTL cache (mirrors evaluate_reference_accessions()'s own design) plus a new
# plural investigate_flagged_accessions() batch wrapper sharing NCBI species-search results
# across a flagged-accession list. Deliberately NOT done, per the reentry doc's own
# deferral: cluster-level mislabel detection across a batch (the doc's own highest-value
# idea, needs real batch data with genuine disagreement-taxon overlap to design against
# meaningfully) and the Question 4 items (voucher/publication-context check,
# geographic/range plausibility cross-check, submission-batch-wide pattern check).
# TaxaMatch devtools::test() 679/679 (0 failures, up from 605), devtools::check() 0
# errors/0 warnings/0 notes, reinstalled and verified at ~/Library/R/4.0/library. See
# TaxaMatch/CLAUDE.md's own top session note for the full implementation record.
# Same day, continued (Sonnet 5 -- the fix above was live-tested against the real MZ605481
# case immediately after shipping (user's request: "what's next, test or code?" -> "y") and
# failed twice more before actually working -- each failure diagnosed and fixed via direct
# live debugging: (1) .blast_against_comparison_set()'s post-hoc-filter design returned
# ZERO matches even for accessions confirmed to exist, since comparison-set accessions
# never ranked among an unrestricted BLAST's own top hits -- fixed via NCBI's ENTREZ_QUERY
# mechanism, which restricts the search space itself. (2) Still zero matches -- root cause
# traced to Pseudorasbora parva having a published reference genome, so a plain species-name
# search returned mostly whole-chromosome assembly records (60-80M bp) instead of short
# barcode deposits, confirming the reentry doc's own originally-deferred "Option B" (length-
# ratio candidate filtering) is a REQUIRED companion to Option A, not an alternative --
# implemented in TaxaMatch::.search_species_accessions() via NCBI's own [SLEN] Entrez query
# field (server-side length restriction, found necessary after a client-side widen-then-
# filter approach both hit an HTTP 414 batching error and still failed for Cyprinus carpio's
# 67,744 total records). Final live re-run produced exactly the pattern this whole mechanism
# exists to detect: MZ605481 (a confirmed candidate_mislabel) shows 87.64% mean self-
# consistency identity to its own listed species vs. 99.42% mean cross-taxon identity to
# Cyprinus carpio. TaxaMatch devtools::test() 696/696 (0 failures), devtools::check() 0/0/0,
# reinstalled and re-verified after each fix. See TaxaMatch/CLAUDE.md's own same-day
# continued note for the full multi-round debugging record.
# Previous update, 2026-08-07, continued once more (Sonnet 5 -- TaxaAssign's second full code +
# domain review response, against a fresh inst/taxaassign_review.Rmd (20 files). Two real bugs
# found and fixed via direct empirical verification: update_prior_from_consensus() was
# silently OVERWRITING (not merging) any report_params already attached to its input `result`,
# meaning every real run_llm_pipeline() report's Methods text silently used hardcoded defaults
# instead of the real assign_taxa_llm() parameters actually used; .find_nearest_grid()'s plain
# Euclidean lat/lon-degree distance wasn't spherical-correct (over-weights longitude away from
# the equator) and could pick the wrong nearest grid cell, fixed with a cosine-latitude
# correction confirmed via a constructed 60N counterexample. Also closed a real, previously-
# documented production landmine at the package level: compute_group_priors()'s default
# rank_cols changed from c("genus","family") to c("species","genus","family") (auto-deriving
# "species" as taxon identity) -- the old default was the root cause of the 504/616 real Mugu
# "unprecedented" false-positive bug from the 2026-07-30 entry below, patched at the time with
# a manual per-workflow shim rather than a package default change; this session's reviewer
# independently flagged the same landmine with no access to that history, which is exactly the
# discoverability risk that earlier reasoning under-valued. expand_unreferenced_hypotheses()'s
# TaxaAssign-side deprecated forwarding wrapper removed entirely (zero real qualified callers).
# 13 broken/\dontrun{}-hidden @examples blocks rewritten to genuinely runnable, verified by
# devtools::check() actually executing them. devtools::test() 655/655 (up from 615),
# devtools::check() 0/0/0, reinstalled and verified against the installed copy directly. See
# TaxaAssign/CLAUDE.md's own top session note and inst/taxaassign_review_response.md for the
# complete file-by-file record.
# Previous update, 2026-08-07, continued yet again (Sonnet 5 -- TaxaFlag::review_spatial_context(),
# closing out the whole nine-round spatial-review-gadget thread with a dedicated test-
# coverage pass, prompted by the user asking to make sure all docs/tests were properly
# written up after confirming the tileSize=512/zoomOffset=-1 fix worked. Two pieces of real
# logic that had only ever existed as inline variables inside the gadget's reactive/render
# closures -- the GBIF tile URL's .point->.poly auto-upgrade/bin-param/Heat-exclusion logic,
# and the per-style legend gradient lookup -- were extracted into standalone `@noRd`
# functions (`.gbif_tile_url()`, `.gbif_legend_swatch()`) specifically so they're
# independently unit-testable, not just implicitly exercised through the full gadget. This
# matters because the exact bug class this thread shipped twice (a real, correctly-verified
# value that wasn't actually wired to, or re-checked against, the code path a real user's
# parameters would hit) is precisely what inline-only logic can't catch. 15 new tests added
# (5 for the URL builder, 3 for the legend lookup, 2 for `.fetch_inat_points()` which had no
# direct test coverage at all before this pass). devtools::test() 382/382 (up from 360),
# devtools::check() 0 errors/0 notes, reinstalled. Pure refactor + additive tests, no
# behavioral change. See TaxaFlag/CLAUDE.md's top session note and
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued once more (Sonnet 5 -- TaxaFlag::review_spatial_context(),
# fourth round of real click-through feedback. Two items: (1) reverted the prior round's iNat
# marker clustering + radius bump entirely, per direct user feedback ("The iNat points were
# fine before") -- back to plain, unclustered radius=2 circleMarkers, no clusterOptions.
# (2) GBIF tiles still too small, with an explicit "don't use clustering to solve this."
# Rather than tune squareSize yet again, investigated the deeper display-size question left
# unresolved since the original tileSize regression: GBIF's z/x/y addressing follows the
# standard 256px-grid convention (confirmed repeatedly this thread via real occupied-pixel
# checks) while its @1x.png response is a real 512x512 image -- i.e. GBIF's default tile is
# already a "retina"/@2x tile for its own addressed area, the exact shape Leaflet's own
# `tileSize`+`zoomOffset` pairing exists for. Verified live before shipping (not reasoned
# from memory, specifically because a prior round's superficially similar tileSize-only
# change caused a real regression): built a standalone non-Shiny leaflet page with
# `tileOptions(tileSize=512, zoomOffset=-1)` alongside the old default, screenshotted both
# via real Chrome browser automation at the gadget's real zoom and after zooming in twice
# more -- confirmed correctly positioned, visibly ~2x larger squares, zero tile gaps, zero
# console errors. Shipped to the GBIF tile layer specifically. devtools::test() 360/360
# unchanged, devtools::check() 0 errors/0 notes, reinstalled. See TaxaFlag/CLAUDE.md's top
# session note, this file's own "Known R Footguns" tileSize entry (updated with the correct
# paired-usage finding), and [[project_gbif_tile_spatial_review_functions]] for the full
# record.
# Previous update, 2026-08-07, continued yet again (Sonnet 5 -- TaxaFlag::review_spatial_context(),
# third round of real click-through feedback. Study Site marker fix confirmed correct; three
# more real issues fixed: the GBIF legend color was STILL wrong once the user's own call
# actually used gbif_style="purpleHeat.point" -- the prior round's fix hardcoded "classic"'s
# real sampled colors but never read the actual configured style, so it kept showing
# yellow/orange/red regardless. Rebuilt as a real per-style lookup (5 styles sampled live:
# classic + all 4 Heat variants), falling back to a neutral gray for anything unverified
# rather than another guess. The iNat search radius (raised to 500km last round) had no
# visual boundary, risking "no points here" being misread as "no iNat data at all" -- fixed
# with a dashed leaflet::addCircles() boundary plus the actual km value in the legend text,
# both driven by one new inat_radius_km param so they can't drift apart. iNat points were
# barely visible when zoomed in since a fixed-screen-pixel circleMarker never grows with
# zoom and un-clustered points spread apart at high zoom -- fixed with Leaflet's own bundled
# marker-clustering plugin (leaflet::markerClusterOptions(), confirmed natively supported,
# no new dependency). devtools::test() 360/360 unchanged, devtools::check() 0 errors/0
# notes, reinstalled. See TaxaFlag/CLAUDE.md's top session note and
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued once more (Sonnet 5 -- TaxaFlag::review_spatial_context(),
# second round of real click-through feedback on the SAME fixes just shipped: legend/toggles
# now show, but the GBIF legend color was a never-sampled guess (fixed by reading real pixel
# RGB values off live tiles: yellow/orange/dark-red, not the paler ramp guessed before), the
# Study Site legend swatch was a generic pin emoji rather than the real marker (fixed by
# embedding leaflet's own bundled marker-icon.png as a runtime-generated base64 data URI,
# pixel-identical to the real map marker), iNat points were confined to a small region -- a
# real regression from switching off the old world-spanning raster tile in favor of a
# hardcoded 50km point search (fixed: default radius raised to 500km, confirmed live the
# spread is genuinely wide again), and the GBIF tile bin-size fix from the prior round was
# real but tuned against the wrong reference case (a maximally common species) -- re-measured
# against this thread's own real sparse GreatLakes species at the actual study-site tile and
# raised the default squareSize 64->256, which real data showed makes a genuine, not marginal,
# visual difference for the sparse species this gadget actually reviews. `devtools::test()`
# 360/360 unchanged, `devtools::check()` 0 errors/0 notes, reinstalled. See TaxaFlag/CLAUDE.md's
# top session note and [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued (Sonnet 5 -- TaxaFlag::review_spatial_context()'s FIRST
# real RStudio click-through by the user, 4 concrete points: occurrence points "just right"
# (unchanged), iNat markers too large, GBIF tiles still too small, no legend, no toggles.
# All fixed with live-verified levers, not guesses: iNat's own points-tile API has NO working
# size parameter at all (confirmed directly -- 6 candidate param names all byte-identical to a
# bare request) so the raster tile layer was replaced entirely with real point markers (new
# `.fetch_inat_points()`, same `/v1/observations` endpoint `TaxaFetch::fetch_inat_occurrences()`
# counts against, no auth needed) sized to match the already-approved occurrence-point styling;
# GBIF's `bin=square`/`squareSize` binning params (confirmed live to be silent no-ops on
# `.point`-suffixed styles) now auto-upgrade the style to its `.poly` counterpart, chosen at
# `squareSize=64` from a real measured sweep (~36x more visible area than raw pixels); a static
# HTML legend and `leaflet::addLayersControl()` toggles were added -- the latter was removed in
# an earlier round on suspicion it caused a real regression that was later proven (via reading
# Leaflet's own source) to be an unrelated `tileSize` bug, so it's back now that a real browser
# session exists to verify it in. `devtools::test()` 360/360 unchanged, `devtools::check()` 0
# errors/0 notes, reinstalled. See TaxaFlag/CLAUDE.md's top session note and
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued once more (Sonnet 5 -- TaxaMatch follow-up on the
# real Abylopsis eschscholtzii ambiguity from the same-day BLAST-based reference-quality
# work: an Opus design consult (requested by the user directly: "is it time to ask Opus")
# found the current hierarchy_flag/finest_common_rank columns cannot distinguish a genuine
# mislabel from "correct label, but this marker (18S) has poor resolving power at this rank
# for this clade and GenBank coverage is thin" -- both produce identical output for the two
# real accessions in question. Recommended two concrete fixes before attempting any
# graded-likelihood-weighting mechanism (the reentry doc's own deferred item 5, still not
# attempted): (1) surface percent-identity of agreeing/disagreeing hits (already computed,
# previously discarded) plus whether ANY corroborating evidence exists anywhere in the full
# hit pool, not just the top_n slice used for the verdict; (2) stop hard-dropping on an
# unreviewed "incongruent" verdict by default, citing this ecosystem's own precedent of
# making and reverting that exact mistake twice before (apply_coverage_constraints()'s
# zero->relabel default; filter_gbif_quality()'s exclude_institution->flag_institution).
# Both implemented same-day: evaluate_reference_accessions() gains 5 new diagnostic columns;
# new flag_incongruent_references() (annotate, never remove) is now the documented
# recommended default, with remove_incongruent_references() demoted to a deliberate,
# post-review opt-in. Also added: a small curated ground-truth accession list
# (diagnostics/reference_accession_ground_truth.csv, TaxaID repo root) -- a real confirmed
# mislabel, real confirmed-correct-but-thin-coverage accessions, the real ambiguous
# Abylopsis pair, and real Menidia accessions, all from this ecosystem's own prior
# real-data audits -- wired into both real external AuditNCBI.R workflow scripts
# (GreatLakes and PtConception, outside this monorepo) as a per-run sanity check.
# `devtools::test()` 601/601 (up from 577), `devtools::check()` 0/0/0, reinstalled. The
# graded-weighting question itself remains open, per the consult's own recommendation to
# try the cheaper fixes first and revisit weighting only if they prove sufficient at scale
# -- not yet tested at scale. See TaxaMatch/CLAUDE.md's own top session note for the full
# record, including the consult's core finding (this is a real identifiability problem
# from these two data points alone, not a smoothing/threshold problem).
# Previous update, 2026-08-07, continued (Sonnet 5 -- TaxaFlag::review_spatial_context()
# gains an opt-in live TaxaFetch::check_inat_range() fallback (new live_inat_check/
# inat_cache_dir params on review_spatial_context() and its internal server), closing a real
# coverage gap the user hit repeatedly across three different real taxa spanning both
# "unexpected" and "expected" plausibility tiers: the pipeline's own static inat_range is
# scoped to its "unprecedented"-tier undetected-diversity candidates only, so most of a real
# consensus table has no row in it at all -- not a bug, a real structural limitation, verified
# directly against real data before building the fallback rather than patched blind a second
# time. The stats-panel iNat message no longer claims "not in the supplied inat_range" when a
# live check may also have run, and now surfaces the real range_status when a check (static or
# live) genuinely finds nothing. A pre-existing test-suite gap (the test file's own server-
# construction helper hadn't been updated for a REQUIRED param this same round's signature
# threading had already added, surfacing as an opaque testServer() promise error rather than a
# clear missing-argument message) was found and fixed while getting to a clean test run.
# devtools::test() 360/360 (up from 356), devtools::check() 0 errors/0 notes, reinstalled. Still
# not done: the user's own live RStudio click-through -- every round of this thread has been
# verified via shiny::testServer()/direct API calls/source reading so far, not a real browser
# session by me. See TaxaFlag/CLAUDE.md's top session note and
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued yet again (Sonnet 5 -- TaxaFlag::review_spatial_context()
# refined from the user's first real click-through: dropped an unneeded tile-opacity
# override (GBIF's tiles now render as GBIF itself serves them, not dimmed further), toned
# down the occurrence-point styling so it doesn't visually overwhelm the tile layer, made
# the iNat panel always show an explicit line (real data or "no data for this taxon")
# rather than silence, and added a new excluded_occurrence_data overlay for GBIF records
# this study's own quality/outlier/institution filtering excluded. That last point was
# investigated against the real GreatLakes2023 checkpoints rather than assumed: 0
# geographic-outlier removals, 0 institution removals, but a real 530 records excluded by
# filter_gbif_quality() (recoverable via a plain anti_join on gbifID between raw_gbif and a
# post-filter checkpoint). devtools::test() 354/354, devtools::check() 0 errors/0 notes.
# Still open: a real interactive click-through in RStudio hasn't happened yet. See
# TaxaFlag/CLAUDE.md's top session note and [[project_gbif_tile_spatial_review_functions]].
# Previous update, 2026-08-07, continued once more (Sonnet 5 -- implements ecosystem_docs/
# REENTRY_PROMPT_blast_based_reference_quality.md: TaxaMatch gains
# evaluate_reference_accessions() (per-accession BLAST-based reference-quality
# evaluation, replacing the taxon-list-scoped DECIPHER whole-set-alignment approach a
# prior 2026-08-06/07 design session abandoned after finding real false positives --
# 15 genuine Smithsonian-vouchered Menidia accessions flagged "incongruent" purely
# because Menidia's family had no other representative on a real 6-genus GreatLakes
# test's `taxa` list -- and a structural false-negative gap that approach could never
# close) + remove_incongruent_references() (the early hard-filter consumer, mirrors
# TaxaLikely::remove_flagged_references()'s pattern). BLASTs each accession against a
# broad, unrestricted database instead of a caller-scoped taxon list, reusing (duplicated,
# not cross-package-reached-for, per the documented TaxaMatch->TaxaLikely dependency
# direction) the archived .build_submission_batch_lookup()/.same_submission_batch()/
# .compute_hierarchy_congruence() machinery unchanged -- what's new is the caller, which
# adapts real BLAST hits into the same id_x/id_y/{rank}.x/{rank}.y pair-table shape that
# machinery already expects. Persistent accession-keyed cache with the user's chosen
# asymmetric TTL (congruent/incongruent cached indefinitely; insufficient_independent_
# evidence expires and retries). A real, structural bug was found and fixed via testing
# the common "brand-new accession, zero BLAST hits" case, not by inspection: the initial
# empty-hits fallback silently dropped such accessions from the output entirely (a
# downstream merge()'s right side had no columns to bring in) -- fixed with a properly-
# shaped empty frame, guarded by a dedicated regression test. TaxaMatch's own Package
# Purpose statement updated to reflect this narrow, match-object-cleaning scope revision
# (confirmed with the user during the design session: "screening match data against
# reference quality in service of producing a clean match object," not a takeover of
# reference-database auditing as a discipline -- that stays TaxaLikely's domain).
# devtools::test() 576/576 (0 failures, up from 523), devtools::check() 0 errors/0
# warnings/0 notes, reinstalled and verified at ~/Library/R/4.0/library. Not done this
# session, explicitly flagged as real future work (the reentry doc's own item 5,
# deliberately left undesigned): the full per-accession quality signal surviving through
# to TaxaLikely::evaluate_likelihoods() for graded likelihood weighting -- no mechanism or
# signature decided yet. See TaxaMatch/CLAUDE.md's own top session note for the full
# record, including two smaller real bugs found and fixed the same way (a base merge()
# column-name ambiguity, a zero-row scalar-column-assignment error).
# Previous update, 2026-08-07, continued yet further (Sonnet 5 -- TaxaFlag gains
# review_spatial_context(), a click-through leaflet + miniUI gadget closing out the
# original brainstorm this whole multi-day thread started from -- taxon dropdown
# (filterable by plausibility), a live pannable/zoomable GBIF density-tile map layer, a
# sidebar with the already-built check_gbif_tile_range()/compute_local_occurrence_
# distance()/iNat context, and an opt-in "Run AI Review" button (the only billed step,
# never automatic). Standard browser-automation tooling hung indefinitely against the
# running gadget waiting for "network idle," which a Shiny app's persistent WebSocket
# never reaches -- confirmed not a gadget bug (a plain curl request got a fast, correct
# response) before abandoning that path per this project's own "avoid rabbit holes"
# guidance. Pivoted to shiny::testServer() instead (a small refactor exposed the server
# function directly), which caught a real bug before any user would have: an unresolvable
# taxon name silently blanked the ENTIRE stats panel, not just the intended message,
# because shiny::req()'s silent-stop propagates to any caller reading that reactive.
# devtools::test() 350/350, devtools::check() 0 errors/0 notes. Still needs the user's own
# live click-through in RStudio -- testServer() verifies the reactive logic, not the full
# rendered browser experience. See TaxaFlag/CLAUDE.md's top session note and
# [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07, continued (Sonnet 5 -- TaxaFlag::review_assignments() wired to
# the new spatial-review functions (check_gbif_tile_range()/
# compute_local_occurrence_distance() + TaxaFetch::check_inat_range()): six new optional
# `_col` params, purely additive to the LLM prompt (facts only, e.g. "GBIF: nearest
# occurrence ~6517km away, patch ~7.3km across; iNat: matched to 'Gasterosteus aculeatus'
# (name differs from query), in range, 10135 obs"), with the interpretive caveats -- a
# small isolated GBIF patch may be a bad record, not real presence; a mismatched iNat
# matched_name may describe a different species -- as a conditional GUIDELINES bullet
# rather than a server-side pre-judgment. That last point was a deliberate design choice,
# citing this ecosystem's own trusted_rank precedent (built, then removed after misfiring
# on real data) for why a rigid disagreement rule wasn't built instead. Also surfaced,
# same real-data comparison: TaxaFetch::check_inat_range() resolved a query for the
# European Gasterosteus gymnurus to Gasterosteus aculeatus (a different, North American
# species) via a fuzzy name match, returning a misleading in_range=TRUE -- filed as its
# own separate TODO ([[project_inat_range_backbone_mismatch_todo]]), not fixed here, since
# it has a live production consequence (TaxaAssign::adjust_inat_range_priors() already
# elevates priors from this unchecked verdict) independent of the prompt-wiring work.
# devtools::test() 334/334, devtools::check() 0 errors/0 notes. See TaxaFlag/CLAUDE.md's
# top session note and [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-07 (Sonnet 5 -- TaxaFlag::check_gbif_tile_range() refined from
# real user feedback on the real GreatLakes2023 data: two genuinely "unprecedented"
# European fish species came back NA/beyond_buffer at the default zoom, which the user
# flagged as uninformative (a reviewer wants "very far" over "unknown"), and raw
# patch_size_px was hard to interpret without knowing the zoom's real-world scale. Both
# fixed: new `escalate`/`min_zoom` params widen the tile search to coarser zoom levels
# only when nothing is found, stopping as soon as something is (live-verified: both real
# species now resolve at zoom 3 to real, plausible transatlantic distances ~6500km,
# while the already-working case does not escalate at all); new `patch_area_km2`/
# `patch_diameter_km` convert the raw pixel count to real-world units. devtools::test()
# 320/320, devtools::check() 0 errors/0 notes. See TaxaFlag/CLAUDE.md's top session note
# and [[project_gbif_tile_spatial_review_functions]] for the full record.
# Previous update, 2026-08-06 (Sonnet 5 -- TaxaFlag gains two new standalone functions giving
# a reviewer spatial context for a taxon flagged "unexpected"/"unprecedented":
# compute_local_occurrence_distance() (free -- reuses a workflow's own already-fetched
# TaxaFetch occurrence data, no new network call) and check_gbif_tile_range() (cheap --
# reads presence/absence from GBIF's occurrence-density map tiles' alpha channel, giving
# the global range context a bbox-limited local fetch structurally can't). Neither
# distinguishes a data error from a genuine rarity/vagrancy report -- that's
# TaxaFetch::check_geographic_outliers()'s separate, prior job; these answer a downstream
# question (how isolated is a detection already judged plausible). A real performance
# problem (unbounded patch-growth taking 13-22s for a densely-covering species) was found
# and fixed via live-verification against real GBIF tiles before shipping, not caught by
# synthetic tests. devtools::test() 297/297, devtools::check() 0 errors/0 notes (1
# pre-existing unrelated warning). See TaxaFlag/CLAUDE.md's top session note for the full
# design record, including the real empirically-verified GBIF tile facts (512px tiles,
# not 256px; HTTP 204 for empty tiles) that would have silently broken the georeferencing
# math if assumed instead of checked.
# Previous update, 2026-08-06, continued yet again (Sonnet 5 -- `repair_thin_evidence()`'s
# scope widened to also rescue accessions with ZERO `seq_matrix` presence (over-length
# records, e.g. full mitogenomes) -- a real GreatLakes 12S check found 67% of a real audit's
# accessions fell in this bucket, live-confirmed against NCBI as genuine mitogenome-scale
# records each carrying a real, annotated 12S region. A primer-based rescue
# (`trim_to_amplicon()`, already built) was deliberately rejected by the user on a real
# design objection: whether an accession gets checked for mislabeling must not depend on
# which primer an analyst happened to try. Fixed primer-neutrally instead, reusing
# `repair_thin_evidence()`'s existing same-species/genus pairwise-alignment machinery with
# one added safeguard -- every candidate must already be a real, vetted `seq_matrix`
# participant, never another unvetted long/thin accession. devtools::test() 0 failures
# (1079), devtools::check() 0/0/1 (pre-existing environmental note), reinstalled. See
# TaxaLikely/CLAUDE.md's own top session note for the full record, including real-scale
# validation against the GreatLakes cached checkpoint.
# Previous update, 2026-08-06, continued once more (Sonnet 5 -- TaxaLikely: closes out a
# statistical-critique investigation (mechanics trace + real-data empirical scan + Opus
# critique) the user requested after noticing train_likelihood_model()'s fitted
# score->likelihood relationship can peak below a perfect match rather than at it. Verdict:
# expected/correct behavior (a Gaussian peaks at its fitted mean, which real data sits below
# the ceiling), and the property that actually matters -- monotone likelihood ratio -- held
# in every real production model checked. Three real fixes shipped anyway: evaluate.R's H1
# outlier-rejection gate changed from two-sided to one-sided (a real, if latent, structural
# incoherence independent of the main question -- H2/H3 can never fit a too-high score better
# than H1, so only a too-LOW score should ever zero H1); evaluate_likelihoods() now warns
# rather than silently defaulting to the more fragile `"logit"` transform when a model
# object's Score_Transform field is absent; train_likelihood_model() gained an automatic
# post-training monotone-likelihood-ratio diagnostic (new `.check_score_ratio_monotonicity()`,
# `Stats$mlr_violations`/`max_ceiling_z`). Per the user's explicit choice, the analysis is
# documented in train_likelihood_model()'s own roxygen (a new `@section Non-monotonic
# score->likelihood shape`) rather than a new standalone design doc. `devtools::test()` 0
# failures (1075), `devtools::check()` 0/0/1 (pre-existing environmental note), reinstalled.
# Still open, not resolved: no live Pt. Conception `lik_model` was found on disk to confirm
# it isn't still the stale, `Score_Transform`-less object the empirical scan flagged as the
# one real severe case found. See TaxaLikely/CLAUDE.md's own top session note for the full
# record.
# Previous update, 2026-08-06, continued yet further (Sonnet 5 -- `audit_reference_database()`/
# `classify_reference_accessions()`'s `min_coverage` split into two params
# (`min_coverage_floor`, a permissive sanity minimum for computing raw stats; `min_coverage`,
# now purely a downstream trust gate on the specific pair driving a flag), fixing a real,
# measured problem: at a real Youden's-J-calibrated `min_coverage = 0.95`, 54% of a real
# 10,701-accession GreatLakes 12S audit had zero surviving self-comparisons, even after the
# same-day `repair_thin_evidence()` repair pass. Prompted by the user's own design question
# and proposed fix. New `foreign_match_coverage`/`median_self_coverage` output columns.
# devtools::test() 0 failures (1061), devtools::check() 0/0/0, reinstalled. Wired into the
# external GreatLakes `AuditNCBI.R` workflow (not under git). See TaxaLikely/CLAUDE.md's own
# top session note for the full record.
# Previous update, 2026-08-06, continued (Sonnet 5 -- TaxaLikely gains
# `repair_thin_evidence()`, a targeted pairwise repair pass for reference-database-audit
# accessions a broad-marker-search + strict-`min_coverage` alignment left thin-evidenced
# even though real corroborating data exists, just sequenced with a different primer
# subset. Wired into the external GreatLakes `AuditNCBI.R` workflow (not under git).
# devtools::test() 0 failures (1045), devtools::check() 0/0/0, reinstalled. See
# TaxaLikely/CLAUDE.md's own top session note for the full record, including a real bug
# found and fixed via dry-run testing (scope was gated on `qc$excluded_from_alignment`,
# which conflates a genuine non-entrant with an accession every one of whose pairs merely
# failed `min_coverage` -- fixed to check raw `seq_matrix` presence directly).
# Previous update, 2026-08-06 (Sonnet 5 -- implements ecosystem_docs/REENTRY_PROMPT_
# reference_database_audit_hierarchy_check.md: TaxaLikely gains a taxonomic-hierarchy-
# congruence check for its reference-database audit tooling, closing out the design
# thread begun 2026-08-04 (a full critical re-design after an Opus-model architecture
# review found the first version would not have caught the motivating case -- a parasite
# correctly identified morphologically whose sequenced DNA is actually the host's,
# replicated across several individuals from the same sample). New internal
# `.compute_hierarchy_congruence()` walks each accession's independent (not
# same-submission-batch) close matches for taxonomic-rank agreement, Jeffreys-smoothed
# and vectorised (1M-row real-scale `seq_matrix` in 1.39s); wired into
# `audit_reference_database()`/`classify_reference_accessions()`'s new `hierarchy_flag`
# column, kept deliberately additive (never folded into the existing `error_type`
# override chain -- this ecosystem has already run that "fold a new signal in" experiment
# twice, both times finding the additive-column design safer). Also documents (in one
# pass, per this project's own end-of-session convention) the three functions this same
# design thread shipped 2026-08-04/05 -- `estimate_reference_scope()`,
# `audit_reference_database()`, `classify_reference_accessions()` -- left undocumented at
# the time pending real-data testing. Two required cache-staleness fixes made along the
# way in `fetch_ncbi_reference_sequences()` (folding `rank_system` into its per-taxon
# cache key; adding a `create_date` column, live-verified present on NCBI's real
# ESummary DocSum). `devtools::test()`/`check()` clean (0 failures, 0/0/0), reinstalled.
# See `TaxaLikely/CLAUDE.md`'s top session note and its new "Reference database auditing
# (Module B-QC2)" Function Inventory section for the full record.
# Continued, same day, real production use against real GreatLakes 12S data (156 genera,
# 3557 accessions) found a real bug: `audit_reference_database()` never passed
# `keep_out_of_range` through to `fetch_ncbi_reference_sequences()`, so a caller using a
# length-specific `barcode_term` (e.g. `"MiFishU"`, 130-210bp, the fix for a separate,
# real, non-bug finding -- several accessions flagged `hierarchy_flag = "incongruent"`
# turned out to be genuine 12S sequences from an OLDER, non-MiFish amplicon window, live-
# verified against real NCBI records) silently lost every off-window accession before it
# ever reached `qc` -- not flagged, just gone, taking over half the species in a real test
# run with it. Fixed: `audit_reference_database()` now retains out-of-range accessions
# through fetch so they correctly surface as `excluded_from_alignment = TRUE` instead of
# vanishing, matching its own "Deliberately exhaustive" design intent (which had only ever
# covered count-based subsampling, not the length filter). `devtools::test()`/`check()`
# clean, reinstalled. See `TaxaLikely/CLAUDE.md`'s same-day continued note.
# Previous update, 2026-08-03 (Sonnet 5 -- two real fixes from a long GreatLakes2023
# debugging/design session (production workflow, outside this monorepo, not under git).
# (1) TaxaMatch::blast_sequences() real bug: the subject-length filter checked `slen`
# (whole GenBank record length) instead of `length` (aligned region length), silently
# discarding real congener matches deposited as long mitogenomes -- found live debugging
# why real Ameiurus melas/natalis reference sequences never appeared as BLAST candidates
# for a real GreatLakes 12S ASV despite the user directly confirming (via
# pairwiseAlignment()) that real, well-matching references existed. Also added explicit
# `megablast` param (default FALSE, matches prior implicit behavior -- tested and ruled
# out as the actual bug, kept anyway per the user's "let's fix both") and a new
# `max_hits_per_taxon` param (needed a `.attach_taxonomy()`/`stage=` restructuring since
# remote BLAST XML never populates real per-hit taxids). Live-verified: 9 unique species
# across 3 genera now correctly surface for the motivating ASV (previously 1).
# Separately, the GreatLakes production pipeline itself was restructured
# (`GreatLakes_blast_combined_plates.R`, new) to merge Plate 1 + Plate 2 sequences BY
# IDENTITY before BLASTing, not after reconciling two separately-BLASTed match objects --
# 1,457 shared sequences were being BLASTed twice for the identical query string, wasted
# volume plus a real (if usually small) risk of the same physical sequence getting two
# different answers. `devtools::test()` 523/523, `devtools::check()` 0/0/0, reinstalled.
# (2) TaxaExpect::screen_spatial_formula() real bug, found building a continuous
# depth/elevation habitat covariate for the same GreatLakes workflow (motivated by a real
# finding: 95% of "Lentic"-classified occurrences were >50km offshore, dominated by
# genuinely pelagic species): the function hardcoded recognition of only
# `lat_r_s`/`lon_r_s` as screenable covariates, so a newly-added `depth_m_s` term was fit
# as a real random slope but never shown in the VarCorr screen table, never tested for
# removal, and never actually justified by AIC -- silently kept in every candidate
# formula regardless of whether its variance was meaningfully non-zero. Fixed to read the
# real covariate list off `prepare_model_dataframe()`'s own `scale_params` attribute
# instead of a hardcoded pair (verified it survives a `left_join()` with a Moran spatial
# basis, the real usage pattern), generalizing to any future covariate with zero further
# package work. Re-run post-fix: `depth_m_s` has SD=1.35, the largest of any screened
# term, correctly retained. `devtools::test()` 541/541 (up from 538), `devtools::check()`
# 0/0/0, reinstalled. See `[[project_depth_covariate_propagation]]` in the memory system
# for the full record, including what does/doesn't transfer to the Mugu/PtConception
# workflows (flagged there as a future task, deliberately not delegated to an agent --
# needs the same per-site empirical bathymetry-source verification this session did for
# Lake Michigan). See TaxaMatch/CLAUDE.md's and TaxaExpect/CLAUDE.md's own top session
# notes for the full per-package record.
# Previous update, 2026-08-02 (Sonnet 5 -- TaxaHabitat::review_spatial_flags(), seventh round
# of a recurring debugging thread (GreatLakes2023_ConsensusWorkflow.R, see
# [[project_review_spatial_flags_habitat_reassign_gap]] in the memory system for the full
# 7-round history). Two changes: (1) a design change at the user's request -- reassigning
# a point's habitat via Reassign Habitat mode no longer force-resets spatial_flag to
# "questionable" when starting from Likely/Unlikely, it now keeps the point's existing
# flag (reassigning FROM Questionable is unchanged, still promotes to Likely). Halves
# reviewer workload and stops one path that inflates the Questionable view -- the view
# where bulk Flag-mode has repeatedly proven fragile in this thread. (2) A real,
# independent regression fixed: the prior day's ecosystem-wide `data` -> `occurrence_data`
# rename (Session 2026-08-01, below) had swept up an unrelated call into
# `leaflet::addCircleMarkers()` inside `review_spatial_flags()`'s own map renderer --
# that function's `data` parameter belongs to the `leaflet` package, not TaxaHabitat, and
# was never supposed to be touched. This broke marker rendering in EVERY view of the
# gadget, a far more severe regression than anything found in the prior 6 rounds, and is
# the likely true explanation for why the original bug symptom looked worse on
# re-test. A third, separate issue was found in the user's own external
# `GreatLakes2023_ConsensusWorkflow.R` (not under git, not a package bug): one real call
# site the original rename's ecosystem-wide sweep had missed
# (`assign_habitat_biological(data = ...)`, still the pre-rename name) -- fixed directly
# in the workflow file. Both package-level fixes live-verified via real Chrome browser
# automation against the gadget's own running httpuv server (not just
# devtools::test()/check()) -- see TaxaHabitat/CLAUDE.md's top session note for the full
# verification record, including what's still NOT confirmed (the original "many
# Questionable points" bug, against the user's real large-scale dataset). `devtools::test()`
# 220/220 unchanged, `devtools::check()` 0/0/0, reinstalled.
# Previous update, 2026-07-31 (Sonnet 5 -- TaxaExpect's first full code + domain review against
# inst/Code and Domain Review 2.Rmd, closing the one remaining gap in this ecosystem's review
# coverage (TaxaTools/TaxaFetch/TaxaMatch/TaxaLikely all already had one). Six real, live-
# verified functionality bugs found and fixed in TaxaExpect's spatial-modelling machinery,
# most with real prior-quality consequence: compute_moran_basis() silently produced a wrong
# Moran spatial basis on any real, irregular grid (eigen(symmetric=TRUE) on an asymmetric,
# row-standardised operator, no error or warning); generate_full_priors()'s "principled" phi
# cap never fired on this package's own recommended formula (a glmmTMB VarCorr() lookup used
# "." where glmmTMB actually uses ":"); prepare_model_dataframe()/train_biodiversity_model_
# by_group() both silently dropped every NA-grouped row from the Session 149 group-aware
# effort-denominator feature (base R split()/sort() NA-dropping); prepare_model_dataframe()
# also silently discarded every group's scale_params but the first via dplyr::bind_rows()'s
# attribute handling; create_sites_from_grid()'s grid_id collided distinct cells for any
# grid_size < 0.1; optimize_grid_size() had a resolution-scoring Inf-handling bug and an
# unverified single-cell-pooling guarantee in its sparsest fallback. Plus a Medium statistical
# bias (train_biodiversity_model()'s Tier 2 empirical fallback averaged theta only over
# detected rows, not the full zero-filled set) and a Medium UI bug (plot_theta_map_
# interactive()'s occ_sel() used == instead of %in%, a live recurrence of the exact NA-ghost-
# row bug class already fixed once in this same file). devtools::test() 538/538 (up from
# 536), devtools::check() 0/0/0, reinstalled. See TaxaExpect/CLAUDE.md's top session note and
# TaxaExpect/inst/taxaexpect_review.Rmd for the full record.
# Previous update, 2026-07-30 (Sonnet 5 -- closes out TaxaFlag/REENTRY_PROMPT_axes_wrapup.md's
# remaining tasks (0/1/3/4, all now shipped) plus a real, unplanned backbone-architecture
# review triggered by live-testing the result. TaxaAssign::compute_group_priors() (new) +
# posterior_consensus(group_priors=) redesign consensus_prior from a candidate-scoped MAX to
# a real group-level SUM; TaxaFlag::add_posthoc_assessment() rebuilt around theta_mean instead
# of prior_mean for the same reason (prior_mean can be inflated by update_prior_from_
# consensus()'s confirmation boost, theta_mean can't) -- see TaxaAssign/CLAUDE.md's and
# TaxaFlag/CLAUDE.md's own top session notes for the full per-package record. Both packages
# devtools::test()/check() clean (TaxaAssign 615/615, TaxaFlag 240/240; 0/0/0 both, TaxaFlag's
# pre-existing unrelated build_review_covariates.R warning+note untouched), reinstalled.
#
# Wiring `group_priors` into a real production workflow (MuguFishWorkflow.R) surfaced three
# more real bugs in quick succession, none caught by the test suite -- all found via actual
# live end-to-end runs, not source review: (1) TaxaAssign had never actually been reinstalled
# after the consensus_has_occurrence_record source fix landed earlier the same session --
# devtools::install() output looks identical whether or not there was anything new to install,
# so this went undetected until a direct smoke test of the installed package's own output.
# (2) compute_group_priors()'s rank_cols default (genus/family only) has no species-rank
# concept, so wiring it into posterior_consensus() made every SPECIES-rank consensus_taxon --
# the vast majority of real calls -- read "unprecedented", a 504/616-row false-positive
# regression; fixed at the workflow level with a species-identity-aggregation row, not a
# package default change. (3) A THIRD, independent, real backbone bug: Urolophus halleri vs
# Urobatis halleri disagreed between match-side and prior-side taxonomy again, traced to
# `Mugu_Match_from_BLAST.R`/`Mugu_Match_from_Wilder.R` (the prerequisite match-building
# scripts, outside the 5 workflow files an EARLIER session's backbone fix had touched) still
# converting match objects to GBIF's own backbone, whose name-verification service resolves
# this species to the older synonym.
#
# That third bug prompted stepping back from patching individual files to a full backbone-
# architecture review with the user: three real objects (match_object, native NCBI;
# reference_df, native NCBI; raw GBIF occurrence downloads, native GBIF) need a COMMON
# backbone to join priors against likelihoods. **Decision: NCBI adopted as this ecosystem's
# common working backbone for vertebrate-focused eDNA workflows (Mugu, PtConception), not
# GBIF.** Two independent reasons, both load-bearing: (1) COST -- every backbone-conversion
# call already dedupes to unique taxon names before looking anything up, so cost scales with
# distinct-taxon count, not row count; match_object/reference_df are small (bounded by what
# was actually sequenced) and already NCBI-native, while the occurrence side is the large pool
# (the whole regional species list, for dark-diversity modelling) and already gets converted
# TO NCBI -- so NCBI-common means the small objects need NO real cross-backbone shift at all,
# while GBIF-common would mean converting the large pool instead. (2) DEPENDABILITY -- the
# Urolophus/Urobatis case is a real, not hypothetical, data point: GBIF's own name-
# verification service lags current ichthyological usage here; NCBI matches both current
# convention and the raw GBIF occurrence data's own scientificName field, and is also the same
# authority the sequence evidence itself already comes from (BLAST against NCBI GenBank).
# Scoped explicitly to this study's vertebrate-heavy taxonomic focus, not claimed as a
# universal ranking -- a plant- or invertebrate-focused workflow elsewhere in this ecosystem
# might reasonably prefer GBIF/WoRMS-integrated naming instead.
#
# Applied identically across all 5 real production workflows plus their 2 prerequisite
# match-building scripts (all outside this monorepo, not under git, at ~/My Drive/Rscripts/
# eDNA/): `Mugu_Match_from_BLAST.R`, `Mugu_Match_from_Wilder.R`, `MuguFishWorkflow.R`,
# `MuguWilderFishWorkflow.R`, `PtConceptionWorkflow_12S_single_site.R`,
# `PtConceptionWorkflow_12S_multi_site.R`, `PtConceptionWorkflow_18S_2_single_site.R` -- each
# match-object `convert_taxonomy_backbone()` call now targets `MATCH_BACKBONE_ID` (no real
# shift, a same-backbone synonym-clean pass) instead of `PRIOR_BACKBONE_ID`; each
# `join_priors(backbone_id=)` call updated to match. The 18S_2 script's separate, earlier,
# pre-GBIF-search-purpose conversion (a different legitimate use, deliberately left GBIF-
# targeted in an earlier session) was correctly NOT touched. Only `MuguFishWorkflow.R` has
# been live re-run and verified end to end (final real state: 519 expected / 93 unexpected /
# 4 unprecedented, the 4 being genus-level taxa already flagged as genuinely suspect in
# earlier project investigation, not a bug) -- `MuguWilderFishWorkflow.R` has the identical
# fix but hasn't been re-run; the 3 PtConception workflows have the fix applied but have not
# been run at all this session (no cache found newer than mid-July). All 7 files parse
# cleanly. See [[project_axis1_consensus_prior_group_priors]] in the TaxaID memory system for
# the full multi-bug debugging record, including the real numbers at each stage.
# Previous update, 2026-07-28 (Sonnet 5 -- generate_domestic_food_priors() re-implemented
# around the match-list-gated architecture the user confirmed 2026-07-24 (this session
# picked back up after a multi-day gap; the name-normalization/kingdom-cross-check work
# already shipped 2026-07-24 was a real but separate improvement, not the redesign
# itself). New `match_list_taxa` param (taxa with real likelihoods this run) gates all
# four fixed/supplied channels to the intersection and drives an automatic open-
# discovery residual step for genuinely unanticipated cultivated species, restricted to
# `phylum %in% c("Streptophyta","Tracheophyta")` and deliberately NOT pre-restricted to
# any known list. New 4th fixed list `known_cultivar_taxa` (216 species) plus a much
# larger `food_species_taxa` default (449, up from 20) -- both drawn from the CSV
# cross-reference classification work already done 2026-07-24, cleaned further this
# session (13 cultivated-food-fungi species and one bred cereal found mixed into the
# source "cultivar" list were moved into `food_species_taxa`). New
# `cultivar_evidence_source` output column distinguishes the three ways a
# `prior_source_type = "domestic_plant"` row can arise. All four real production
# workflows rewired to source `match_list_taxa`/`taxonomy` from each script's own match
# object -- the 12S script's call had to move to after `match_obj_restored` is
# finalized, since that object didn't exist yet at the call's original location. A real
# zero-column-tibble bug (from `dplyr::bind_rows()` of all-empty channels) and a test-
# suite hazard (existing tests not zeroing out the new 4th channel, one hanging past
# 120s on live network calls) were both found and fixed live. `devtools::test()` 0
# failures (536, up from 481), `devtools::check()` 0/0/0. Reinstalled to
# ~/Library/R/4.0/library. See `TaxaExpect/CLAUDE.md`'s top session note and
# `[[project_taxaflag_domestic_species_floor_note]]` for the full record.
# Previous update, 2026-07-25, later same day (Sonnet 5 -- closed a real consistency gap the
# user asked to double-check after the same-day verify_taxon_names()/convert_taxonomy_
# backbone() fix (see this file's own note directly below): TaxaTools::fill_higher_ranks()
# was checked for the same class of bug and found NOT to have the exact "Inu Inu"
# fabrication issue (it's genus-only by design, never touches matched_name), but a live
# check confirmed a real, related gap -- its `genus` output stayed the locally-extracted
# query string even when the backbone flagged it as a synonym (e.g. "Inu", not corrected
# to "Luciogobius" the way convert_taxonomy_backbone() now is). Traced a concrete
# consequence: TaxaAssign::join_priors()'s .expand_coarse_rank_rows() does an exact-string
# match between a likelihood-side coarse taxon_name (now correctly resolved to the current
# name, post the earlier fix) and expansion_taxonomy's genus column (built via
# fill_higher_ranks()) -- before today, both sides agreed on the synonym form by
# coincidence; after fixing only one side, that join would have started silently failing,
# losing real occurrence-based coarse-rank species expansion for affected taxa. Fixed:
# fill_higher_ranks() now corrects `genus` to the backbone's resolved name whenever a
# lookup shows it's a synonym cleanly resolved at genus rank, restoring agreement between
# the two functions. Separately, escalate_taxonomic_rank() was checked and confirmed to
# have NO analogous issue at all -- it never reads matched_name, and looks up each rank by
# NAME (not by trusting the caller's current_rank to index a specific position), so a
# rank mismatch degrades to an honest NA rather than a fabricated value; no changes needed.
# TaxaTools devtools::test() 829/829 (up from 824), devtools::check() 0/0/0, reinstalled.
# Live-reverified against the real Inu case post-reinstall. See TaxaTools/CLAUDE.md's own
# same-day note for the full record.
# Previous update, 2026-07-25 (Sonnet 5 -- fixed a real "Inu Inu" fabricated-pseudo-binomial
# artifact the user found in real Mugu review_assignments() output, tracing a full chain
# from TaxaFlag through TaxaAssign to its true root in TaxaTools/TaxaMatch. Real chain,
# each link independently confirmed against live data before the next was investigated:
# (1) TaxaFlag::review_assignments()'s LLM reviewer speculated "possibly a canid
# contaminant" for a taxon named "Inu Inu" -- purely a lexical association ("inu" is
# Japanese for dog), since the LLM has no access to the underlying match evidence, not a
# real finding -- prompting the user to ask where "Inu Inu" itself came from. (2) Traced
# to TaxaAssign::add_slash_taxon()'s .make_slash_name(): a single-word taxon_name with no
# space (the mislabeled bare genus "Luciogobius"... no, "Inu") falls back to using the
# whole string as BOTH genus and epithet when building a mixed-genus slash label,
# producing "Inu Inu". (3) Traced further to TaxaMatch::convert_taxonomy_backbone():
# taxon_name correctly fell back to a coarser resolved name ("Luciogobius", GBIF's
# genus-only match) when no species-level target existed, but taxon_name_rank kept its
# stale "species" label -- so the bare genus was reported AS IF still species-level. (4)
# Traced to the true root, TaxaTools::verify_taxon_names(): the underlying NCBI reference
# ("Inu sp. 1 sensu Shibukawa et al., 2020.", a real informally-named goby) resolves
# against GBIF's backbone to genus "Luciogobius" via a genuine SYNONYM relationship --
# GBIF considers "Inu" Snyder 1909 a synonym of "Luciogobius" Gill 1859 -- but
# verify_taxon_names() read GNVerifier's matchedName (the synonym form) instead of
# currentName (the accepted form) despite the API's own isSynonym flag saying to prefer
# it, AND had no way to report that the match only resolved to genus rank at all. A
# second, independent bug was found and fixed in the same function while there: the
# authority-stripping regex only captured "genus + at most one lowercase word," silently
# truncating any subspecies-rank match to a binomial (confirmed live: "Delphinus delphis
# ponticus Barabash, 1935" -> "Delphinus delphis", dropping the subspecies epithet).
#
# Fixed at the two correct layers, not just patched at the symptom: TaxaTools::
# verify_taxon_names() now sources matched_name from GNVerifier's own
# matchedCanonicalSimple/currentCanonicalSimple fields (authority-free, rank-complete,
# no local regex) and prefers the current name when isSynonym is TRUE; gains new
# matched_rank (the rank the match ACTUALLY resolved at) and is_synonym output columns.
# TaxaMatch::convert_taxonomy_backbone() now uses matched_rank to correct
# taxon_name_rank whenever the name itself falls back to a coarser value, closing the
# gap that let a genus-only match keep a stale species-level label. Verified backbone-
# general, not GBIF-specific, before shipping either fix: live-queried the same real
# name across 5 backbones (Catalogue of Life, ITIS, NCBI, WoRMS, GBIF) -- matched_rank is
# normalised identically by GNVerifier across all of them (a mechanism, not a GBIF
# quirk); is_synonym/currentName differ in real underlying DATA by backbone (NCBI's own
# taxonomy genuinely does not consider "Inu" a synonym at all -- a real cross-authority
# disagreement, not a bug), and since `dataSources` scopes every verify_taxon_names()
# call to exactly one backbone, the fix always reports that one backbone's own answer,
# never blending or overriding one backbone's judgment with another's. `backbone_id = 4`
# (NCBI) bypasses this API path entirely (`.verify_via_ncbi()`) and so never gets
# synonym resolution, but gets matched_rank identically via a shared helper.
#
# Both packages: devtools::test() clean (TaxaTools 824/824 up from ~818; TaxaMatch
# 504/504, convert_taxonomy_backbone.R's own file 43/43 up from 41), devtools::check()
# 0/0/0 both, both reinstalled to ~/Library/R/4.0/library. New tests directly reproduce
# the real Inu case (both the genus-synonym-resolution case and the subspecies-truncation
# case) rather than only synthetic fixtures. See TaxaTools/CLAUDE.md's and TaxaMatch/
# CLAUDE.md's own top session notes for the full per-package record, and the Recent
# Breaking Changes table below for the exact signature/behavior changes.
# Previous update, 2026-07-24 (Sonnet 5 -- two fixes from continued design discussion on the
# domestic/food-species priors work: (1) TaxaMatch::convert_taxonomy_backbone() now cleans
# its not-found (fallback-to-original) path via TaxaTools::clean_taxon_names(), not just the
# target-backbone-matched path -- found because the user asked why a compound hybrid-formula
# name ("((Citrus unshiu x Citrus sinensis) x Citrus reticulata) x Citrus reticulata", a real
# NCBI reference accession label) reached match_obj$taxon_name/species completely unmodified
# during the 18S residual-count exercise. (2) TaxaFetch::fetch_inat_occurrences() gains
# inat_kingdom + TaxaExpect::generate_domestic_food_priors() gains a kingdom cross-check
# against it, prompted by the user directly asking whether iNaturalist's own taxonomic
# backbone (distinct from NCBI/GBIF) could cause a name search to resolve to the wrong
# organism -- confirmed real (a cross-kingdom homonym is possible via iNat's single-best-
# text-match search), so a mismatch now discards the local-evidence boost (not the fixed-
# list category itself) rather than trusting a possibly-wrong hit. All three packages
# devtools::test()/check() clean (TaxaMatch 500/500, TaxaFetch 541/541, TaxaExpect 495/495,
# all 0/0/0). Reinstalled to ~/Library/R/4.0/library. See each package's own CLAUDE.md top
# session note for the full record.
# Previous update, 2026-07-24, later same day (Sonnet 5 -- TaxaFlag::flag_contaminant()/
# flag_handler() redesigned around a unified observation_validity/validity_flag/
# validity_reason schema (replacing contaminant_score/{type}_risk/{type}_reason and
# flag_handler/flag_handler_score/flag_handler_reason), closing out the two names the
# 2026-07-23 polarity audit had flagged but deferred. A real correction was made mid-design:
# the audit had mischaracterized both as "high=more risk" -- verified directly against
# source before touching any file and found actually HIGH=GOOD/genuine, LOW=likely
# contaminant/handler artifact; a "_risk"-style rename would have been actively backwards,
# not just a missed improvement. Final schema, reached through several rounds of user
# brainstorming (autonomous_operation_score -> validity_score -> observation_validity),
# then a further simplification (single column + type-qualified companion value, matching
# add_posthoc_assessment()'s existing "one column, many type-qualified string values"
# precedent): observation_validity (numeric 0-1, high=good), validity_flag ("valid"/
# "questionable_{type}"/"invalid_{type}"), validity_reason. contaminant_type no longer
# parameterizes column NAMES (verified first that no real workflow used that multi-call-
# merge capability) -- the type now lives in validity_flag's VALUE instead.
# report_flags() gained a third, additive auto-detection branch reading the type qualifier
# out of validity_flag's values, alongside its two pre-existing naming-era branches.
# Same day, wired into both real PtConception production workflows
# (PtConceptionWorkflow_12S_single_site.R, PtConceptionWorkflow_18S_2_single_site.R --
# outside this monorepo, not under git), replacing every real lab_contaminant_risk/score
# reference with the new schema; 18S_2's own pre-existing Session-101 cached-RDS name-
# migration block was extended (not replaced) with a second branch forward-migrating
# lab_contaminant_risk/score/reason values to the new schema, verified against both real
# cached *_contaminant_flags.rds checkpoints (12S 43/10300/3254, 18S 1/18693/2503
# high/moderate/low -- both still pre-2026-07-24 schema, confirming the migration path is
# genuinely exercised). devtools::test() 0 failures (123, up from 119), devtools::check()
# 0 errors/0 warnings (1 pre-existing, unrelated warning+note, untouched). Both workflow
# files parse cleanly; not yet run end to end (would trigger live GBIF/NCBI/LLM calls) --
# left for the user to trigger. See TaxaFlag/CLAUDE.md's top session note for the full
# record.
# Previous update, 2026-07-23, later same day (Sonnet 5 -- renamed the whole
# species_support/genus_support/family_support/own_rank_support family (TaxaLikely),
# their TaxaAssign::posterior_consensus() winner_* pass-through, and TaxaFlag's
# score_support_flag mechanism -- all to a "*_confusion_risk" naming, prompted by the user
# noticing the original names inverted this ecosystem's own polarity convention: every
# other risk-style metric here (TaxaFlag::flag_contaminant()'s contaminant_score, {type}_
# risk columns) already uses HIGH = MORE of the named concern, but "*_support" implied the
# opposite (higher = more backing) while the values themselves are one-sided tail
# probabilities (P(a confusable congener/confamilial/cross-family relative would score
# this high or higher)) -- i.e. HIGH = MORE confusable = WEAKER evidence, backwards from
# what the name suggested. Considered taking the complement (1 - value) instead, framing
# it as a "confidence" -- rejected: that would invite the classic p-value fallacy
# (conflating 1-p with an actual posterior probability of correctness), since these are
# genuine empirical tail probabilities, not calibrated confidences. Pure rename, NO math
# changed: `species_support`->`species_confusion_risk`, `genus_support`->
# `genus_confusion_risk`, `family_support`->`family_confusion_risk`, `own_rank_support`->
# `own_rank_confusion_risk` (TaxaLikely::evaluate_likelihoods()); `model_params$
# Support_Curves`->`Confusion_Risk_Curves` and `.lookup_support_value()`->
# `.lookup_confusion_risk_value()` (TaxaLikely, internal); `winner_species_support`/etc.
# -> `winner_species_confusion_risk`/etc. (TaxaAssign::posterior_consensus()); TaxaFlag::
# add_posthoc_assessment()'s `score_support_flag`->`confusion_risk_flag`,
# `own_rank_support_col`->`own_rank_confusion_risk_col`,
# `weak_score_support_threshold`->`high_confusion_risk_threshold`, and its two flag
# values `"weak_score_support"`/`"adequate_score_support"` ->
# `"high_confusion_risk"`/`"low_confusion_risk"`. Re-verified end to end against the same
# real Mugu 12S data used to validate the original implementation (same numbers, new
# names). `devtools::test()` 0 failures on all three touched packages (TaxaLikely 463,
# TaxaAssign 256, TaxaFlag 119 -- TaxaFlag gained no new tests, existing ones renamed
# in place); `devtools::check()` 0/0/0 on TaxaLikely (1 pre-existing unrelated timestamp
# NOTE only) and TaxaAssign, TaxaFlag's pre-existing unrelated `build_review_covariates.R`
# warning+note untouched. Reinstalled to `~/Library/R/4.0/library`. Also wired
# `TaxaLikely::compute_rank_thresholds()` into both real Mugu production workflows
# (`MuguFishWorkflow.R`/`MuguWilderFishWorkflow.R`, outside this monorepo, not under git,
# backed up first as `*.bak_pre_rank_thresholds`): each marker's `score_con` call now uses
# thresholds derived from that marker's own `seq_matrix` (cached the same way as
# `lik_model`) instead of one hardcoded GITA/JV vector applied uniformly across markers --
# real derived values differ meaningfully by marker (COI species=98/genus=89/family=87 vs.
# 12S 99/97/93 vs. 16S 99/96/96), confirming the pooled-threshold approach really was
# wrong for at least COI. Verified via a standalone simulation against real cached
# `seq_matrix`/`match` objects for all three markers (not yet run through the actual
# production scripts end to end, to avoid triggering live NCBI/GBIF calls without asking).
# See each touched package's own CLAUDE.md for its own note.
# Previous update, 2026-07-23, same day, yet another follow-up (Sonnet 5 -- TaxaFetch::
# dedupe_occurrences() split out of stack_occurrences() entirely, prompted by a user
# naming/design critique: "stack_occurrences" implies pure combination, so bundling
# dedup logic inside it risked a single-source caller reading the name, concluding
# stacking didn't apply to them, and skipping deduplication altogether -- confirmed via
# the documented GBIF-only pipeline (get_gbif_occurrences() -> filter_gbif_quality(), no
# stack_occurrences() call at all) and confirmed NOT new to this session's own
# collapse_duplicate_occasions addition (the pre-existing Session 140 gbifID dedup has
# the identical single-frame blind spot). Both mechanisms moved into new
# dedupe_occurrences(data, ...), which takes one frame (stacked or not);
# stack_occurrences() now only row-binds + adds point_id. Every real call site across
# the monorepo updated to add an explicit dedupe_occurrences() call, including
# TaxaExpect::build_priors() (real package code) and 8 inst/vignette files spanning
# TaxaAssign/TaxaExpect/TaxaFetch -- necessary since the pre-existing gbifID protection
# would otherwise silently vanish for every caller. devtools::test() 0 failures (563, up
# from 553), devtools::check() 0/0/0. See TaxaFetch/CLAUDE.md's top session note.
# Previous update, 2026-07-23, continued yet further (Sonnet 5 -- TaxaHabitat::
# review_institution_flags() built, closing out the institution-review feature deferred
# earlier the same session. Deliberately scoped DOWN from review_spatial_flags() (~950 lines)
# given real datasets here are small (single view, no bulk-select, single-level undo). Shows
# the flagged occurrence AND its matched institution's own location together on one map (a new
# institution_lon/institution_lat pair added to filter_gbif_quality()'s institution columns to
# support this), so a reviewer can see directly whether a record sits at the institution or
# genuinely nearby it. Every record starts "keep" -- nothing discarded without review. No test
# file, matching review_spatial_flags()'s own precedent for interactive gadgets in this
# ecosystem; relied on careful manual review instead. A real ASCII-policy violation (Unicode
# arrow/bullet characters) was caught by devtools::check() itself and fixed before shipping.
# Wired into all 5 real production workflow scripts (2 Mugu + 3 PtConception) using the exact
# convention review_spatial_flags() already established in those same files -- a plain inline
# call, sound alert, elapsed-time tracking, gated so workflows with nothing flagged skip the
# section. devtools::test()/check() clean both packages. Not yet run live -- the user's call.
# See TaxaHabitat/CLAUDE.md's top session note and [[project_geographic_outlier_check]] for
# the full record.
# Previous update, 2026-07-23, continued once more (Sonnet 5 -- implements both tasks from
# ecosystem_docs/REENTRY_PROMPT_score_support_posthoc_and_rank_thresholds.md, after
# confirming the two open design questions with the user first (package placement in
# TaxaLikely near evaluate_likelihoods(); EB-shrunk curves stored in model_params$
# Support_Curves, computed once by train_likelihood_model() rather than recomputed per
# query; all three *_support values always populated, plus an own_rank_support
# convenience column). Task 1: new internal TaxaLikely::.compute_rank_score_curves()
# (R/support_curves.R) makes diagnostics/score_floor_roc_sweep.R's genus-/family-equal-
# weighted, Empirical-Bayes-shrunk per-rank TPR/FPR curves real package machinery;
# train_likelihood_model() stores them in Support_Curves; evaluate_likelihoods() gains
# species_support/genus_support/family_support/own_rank_support (a model-independent,
# score-ONLY diagnostic, deliberately separate from the model-based absolute_fit_pvalue --
# LOWER values mean STRONGER evidence, a p-value-like quantity, not the usual higher-is-
# better "support" sense); TaxaAssign::posterior_consensus() gains the matching
# winner_*_support pass-through columns (same pattern as winner_absolute_fit_pvalue);
# TaxaFlag::add_posthoc_assessment() gains a new, deliberately SEPARATE score_support_flag
# column (not folded into posthoc_assessment's override chain -- the trusted_rank
# ladder-walk's 2026-07-20 removal is the cautionary precedent for why a recomputing/
# overriding mechanism was avoided here). Task 2: TaxaAssign::score_consensus(
# rank_thresholds=) loses its GITA/Jonah Ventures default entirely -- now required, errors
# with guidance (mirrors join_priors(backbone_id=)'s exact missing()/cli_abort() precedent)
# pointing at either supplying real thresholds or deriving marker-specific ones via the new
# TaxaLikely::compute_rank_thresholds() (per-rank Youden's J, sharing the same curve
# machinery as Task 1). Real call-site survey from the reentry doc turned out to need less
# fixing than flagged: both TaxaAssign_llm_workflow.R calls already passed
# rank_thresholds = NULL EXPLICITLY (not omitted), so neither broke; only one vignette call
# and ~20 test call sites needed rank_thresholds = NULL added. TaxaWizard's TaxaAssign.json
# metadata entry updated to required=true with the new guidance. devtools::test() clean on
# all four touched packages (TaxaLikely 463, TaxaAssign 256, TaxaFlag 119, TaxaWizard 70,
# 0 failures each); devtools::check() 0 errors/0 warnings/0 notes on TaxaLikely/TaxaAssign/
# TaxaWizard, TaxaFlag has 1 pre-existing warning+note in build_review_covariates.R
# (untouched this session, confirmed via git diff). All four reinstalled via
# ecosystem_docs/install_all.R, verified at ~/Library/R/4.0/library. See the Recent
# Breaking Changes table below for the four new rows, and each touched package's own
# CLAUDE.md for its own top session note.
# Previous update, 2026-07-23, continued yet further (Sonnet 5 -- TaxaFetch::stack_occurrences()
# gains collapse_duplicate_occasions (default TRUE): collapses rows sharing the same species x
# date x rounded-location combination, catching repeat citizen-science reports of one detection
# occasion (e.g. many eBird checklists for one rare-bird-alert individual, many iNaturalist
# uploads from one bioblitz) across DIFFERENT records/platforms -- the existing gbifID dedup
# (Session 140) can't touch these since each is a genuinely distinct GBIF record. Defaulted on
# after verifying directly (per the user's request, not assumed) that TaxaExpect::
# prepare_model_dataframe() counts raw records as both the binomial numerator (n_species) and
# shared effort denominator (n_total_at_site) -- uncollapsed repeat reports inflate a species'
# modeled relative detection frequency directly, and this ecosystem's occupancy-style priors
# should be keyed on detection occasions, not report counts. devtools::test() 0 failures (549,
# up from 539), devtools::check() 0/0/0. See TaxaFetch/CLAUDE.md's top session note.
# SAME DAY, immediate follow-up: fetch_dataone_occurrences(gbif_snapshot_path=) removed entirely
# (zero real callers anywhere in the monorepo, superseded by and less safe than the new
# collapse_duplicate_occasions step above -- it coalesced missing name/date/coords to blank/zero
# before hashing instead of skipping incomplete rows). gbif_hashes removed from 5 internal call
# sites; .load_gbif_hashes()/.deduplicate_against_gbif() deleted. devtools::test() 0 failures
# (553, up from 549), devtools::check() 0/0/0.
# Previous update, 2026-07-23 (Sonnet 5 -- implements ecosystem_docs/REENTRY_PROMPT_domestic_food_
# species_priors.md's three-vector domestic/food design: TaxaFetch::fetch_inat_occurrences()
# (new -- counts real local iNaturalist observations, with captive/quality_grade filters that
# can surface casual-grade cultivated/captive records GBIF-style indexing excludes) plus
# TaxaExpect::generate_domestic_food_priors() (new -- domestic_animal_taxa/food_species_taxa
# fixed vectors with populated defaults; candidate_plant_taxa deliberately has no default list,
# per the reentry prompt's CSV-overlap finding that Cultivated_plants.csv/Food_Plants_Taxonomy.csv
# are the same underlying list at two processing stages, not a usable food-vs-ornamental split --
# a plant candidate only gets a prior row when a live iNat casual-grade check finds real local
# evidence for it). Output rows carry a real taxon_name, a new prior_source_type categorical
# column, and model_tier = "tier_domestic_food". Reflects the reentry prompt's corrected finding
# that Homo sapiens sequence resolution already works fine on real PtConception 12S data
# regardless of prior magnitude -- this fix's value is the categorical flag plus help for
# weaker/degraded matches, not sequence-level resolution -- and does not address cross-genus
# reference gaps (Bison bison/Bos taurus). Both packages devtools::test() 0 failures (TaxaFetch
# 539/539 up from 506, TaxaExpect 481/481 up from 445), devtools::check() 0/0/0 both. Reinstalled
# to ~/Library/R/4.0/library. See TaxaFetch/CLAUDE.md's and TaxaExpect/CLAUDE.md's own top
# session notes for the full record, and [[project_taxaflag_domestic_species_floor_note]] in the
# memory system.
# Previous update, 2026-07-23, continued yet further (Sonnet 5 -- TaxaFetch::filter_gbif_quality()'s
# institution check redesigned to flag, never remove, after the user reviewed the real 29
# flagged Mugu records and found several likely-genuine observations (live fish near a
# university botanical garden pond) alongside likely-genuine errors -- proximity to an
# institution can't be auto-removed the way the other five CoordinateCleaner checks can, since
# field stations/marine labs are often sited exactly where good habitat is. Renamed
# exclude_institution -> flag_institution; flagged rows are RETAINED with 4 new columns
# instead of moving to removed_records. New TaxaHabitat::flag_institution_candidates()
# classifies flagged rows "high"/"low"/"ambiguous" by crossing the matched institution's real
# type against the record's kingdom, mirroring flag_habitat_inconsistencies()'s existing
# classify-then-review two-stage pattern -- deliberately, after a design discussion comparing
# TaxaHabitat vs. TaxaMatch as the right home (TaxaHabitat won: same pipeline lane as the GBIF
# reference-occurrence data this operates on, and "archived vs. wild" is fundamentally a
# habitat question). A real bug (all-NA logical-index subsetting for institution matches with
# no recorded type) was found and fixed before shipping. The interactive map review gadget
# (review_institution_flags(), meant to mirror review_spatial_flags()) is intentionally
# deferred -- scoped in detail, not built, given real time constraints raised mid-session.
# devtools::test() 0 failures (TaxaFetch 515/515, TaxaHabitat 158/158), devtools::check() 0/0/0
# both packages. See TaxaFetch/CLAUDE.md's and TaxaHabitat/CLAUDE.md's top session notes, and
# [[project_geographic_outlier_check]] in the memory system for the full record and resume
# point.
# Previous update, 2026-07-23, continued (Sonnet 5 -- filter_gbif_quality() redesigned around a
# full removal audit trail, prompted by the user noticing the new cc_cen/cc_cap/cc_inst checks
# (below) produced no visible output, then explicitly widening scope from "just the
# CoordinateCleaner step" to all nine filters: repair mistaken exclusions, surface real GBIF
# data-quality problems worth reporting back to GBIF, and make two users' differing filter
# arguments produce comparable results. attr(result, "removed_records") is always present (a
# data frame, possibly zero rows, never NULL), every original column plus filter_reason --
# GBIF-issue-code and CoordinateCleaner removals get the SPECIFIC matched code/check(s), not
# just a generic tag (verified: (0.01, 0.01) simultaneously trips both cc_equ and cc_zero,
# reason = "equal_coordinates;near_zero"). Return contract unchanged (still just the cleaned
# data frame) -- purely additive via attr(). Internals fully rewritten to explicit keep-masks,
# which incidentally fixed a real pre-existing message-accuracy bug (steps 7/8 never refreshed
# a stale count variable, flagged but left alone 2026-07-20). A real "split-string sprintf"
# bug (this file's own documented footgun) was caught in my own first draft before shipping,
# by re-reading the diff rather than trusting it. devtools::test() 0 failures (506, up from
# 494), devtools::check() 0/0/0. See TaxaFetch/CLAUDE.md's top session note for the full
# record.
# Previous update, 2026-07-23 (Sonnet 5 -- closed out the two deferred pieces from the 2026-07-20
# geographic-outlier design thread. (1) filter_gbif_quality() gains the three CoordinateCleaner
# checks originally deferred as needing reference data (cc_cen/cc_cap/cc_inst -- near a country/
# province centroid, national capital, biodiversity institution), each called with only lon/
# lat/value so their ref = NULL default resolves to that package's own bundled data (verified
# via source inspection, no network call); confirmed via source that none of the three share
# cc_outl()'s record-count-triggered raster-approximation batching risk. Benchmarked at Mugu's
# real ~122k-row scale: 1.37s, no performance concern. New tests pull REAL coordinates live from
# CoordinateCleaner's own bundled reference data rather than guessing values, avoiding the
# earlier problem where hand-replicating cc_zero()/cc_gbif()'s buffers hit conflicting numbers.
# (2) check_geographic_outliers() wired into all three real PtConception workflow scripts
# (outside this monorepo, not under git), the same pattern already validated on both real Mugu
# workflows -- not yet run against real PtConception data. devtools::test() 0 failures (494, up
# from 487), devtools::check() 0/0/0. See TaxaFetch/CLAUDE.md's top session note for the full
# record.
# Previous update, 2026-07-20, continued yet further (Sonnet 5 -- a real GBIF timeout during the
# user's own re-verification of the cc_outl() fix surfaced a second, independent, pre-existing
# bug in fetch_gbif_occurrences()'s checkpoint logic: global_pos was advanced by a chunk's FULL
# size even when that chunk aborted partway through, so the checkpoint's remaining_keys was
# computed from a position AFTER the whole aborted chunk -- silently excluding the very key
# that failed from ever being retried on resume, and producing a misleading "enable cache_dir"
# message even when cache_dir genuinely was enabled with a real checkpoint already saved.
# Fixed: abort check now runs before global_pos advances past the aborting chunk; the whole
# chunk (not just the failed key onward) is re-included in remaining_keys on resume. New
# regression test confirms the failed key is present in the saved checkpoint (it wasn't under
# the old logic). devtools::test() 0 failures (487, up from 483), devtools::check() 0/0/0. See
# TaxaFetch/CLAUDE.md's top session note for the full record.
# Previous update, 2026-07-20, continued (Sonnet 5 -- real production bug found and fixed on
# check_geographic_outliers()'s FIRST live run, wired into both real Mugu workflows the same
# day: CoordinateCleaner::cc_outl()'s "distance" method silently switches EVERY species in a
# single call to a coarser raster approximation whenever ANY ONE species in that call has
# >=10,000 records (confirmed directly from cc_outl()'s own source) -- a locally-rare species
# can still be globally common, so batching all rare species into one call let one common
# species degrade every other species' precision, clearing a real ~9,000km outlier (the exact
# motivating Pseudotolithus epipercus case) on the real ~51-species/193,458-record Mugu batch.
# Two other hypotheses (a gbifID type mismatch between download-path bit64::integer64 and
# fetch-path character output; a species-crossing distance bug) were tested directly and
# refuted before the user's own diagnostic re-run surfaced the actual "Using raster
# approximation" warning. Fixed: cc_outl() now called once per species instead of once for
# the whole batch. New regression test mocks cc_outl() directly to assert one call per
# species -- the original tests (max ~17 rows) never exercised this path, the same
# "check dataset scale before trusting synthetic tests generalize" lesson this ecosystem hit
# before with restore_suppressed_candidates(). devtools::test() 0 failures (483, up from
# 481), devtools::check() 0/0/0. See TaxaFetch/CLAUDE.md's top session note for the full
# record, including the two refuted hypotheses.
# Previous update, 2026-07-20 (Sonnet 5 -- TaxaFetch gains check_geographic_outliers(): a
# generic (not species-specific) fix for the real Mugu Pseudotolithus epipercus/La Jolla
# misidentification case -- an African species with one errant citizen-science observation
# far outside its range, discovered by eyeballing GBIF's global distribution map. Design
# went through two real corrections from the user before landing: (1) GBIF's own issues
# quality-flag columns were considered and rejected as too weak/non-generalizing; (2) a
# self-referential outlier test was first scoped against a species' own already-fetched
# occurrence cloud, but get_gbif_occurrences() is always bbox-scoped, so that cloud never
# contains the wider distribution needed -- corrected to gate an additional GLOBAL GBIF
# fetch (geometry = NULL, newly supported in fetch_gbif_occurrences(), previously a required
# WKT string) to only species with few LOCAL (bbox) records, i.e. "singleton within our
# search area," not "globally rare." CoordinateCleaner adopted as a Suggests-only dependency
# for cc_outl() (the actual outlier test) after a full function-by-function inventory (from
# the live CRAN docs, not memory) showed its heavy deps (terra/rnaturalearth) are needed only
# by functions that don't fit this ecosystem (cc_sea/cc_coun/cc_urb -- marine-hostile or
# already redundant with GBIF's own issue-code filtering), not the useful ones. filter_gbif_
# quality() gains 3 new checks (cc_equ/cc_zero/cc_gbif) via the same dependency, default TRUE
# -- see the breaking-changes table below, this changes real existing callers' behavior, not
# just adds an option. devtools::test() 0 failures (481, up from 459), devtools::check()
# 0/0/0. See TaxaFetch/CLAUDE.md's top session note for the full record, including a real
# pre-existing (unrelated, not fixed) filter_gbif_quality() message-accuracy bug found along
# the way, and a real doc-drift gap (check_inat_range(), Session 118, was missing from
# TaxaFetch's own Function Inventory table until this session).
# Previous update, 2026-07-19, continued (Sonnet 5 -- separate, real fetch_ncbi_reference_
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
**end your response with an explicit "To apply these changes" block using this exact pattern.**
**The block must always cover all four steps below — restart, install, un-cache, load —**
**never just restart+install.** Real incident (2026-08-24): a stale-in-memory-package bug
took three re-run cycles to diagnose because the block only said restart+install; the user
kept forgetting the explicit `library()` reload was a separate, required step, and asked
that this be made permanent going forward — see `[[feedback_restart_install_cache_library_checklist]]`
in the memory system.

**If only TaxaTools changed:**
```r
.rs.restartR()
devtools::install("~/My Drive/Rscripts/projects/TaxaID/TaxaTools")
.rs.restartR()
library(TaxaTools)
packageDescription("TaxaTools")$Built   # confirm this session picked up the fresh build, not a stale one
```

**If multiple packages changed, or if unsure which downstream packages are affected:**
```r
.rs.restartR()
source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/install_all.R")
.rs.restartR()
library(TaxaTools)  # repeat for every touched package
packageDescription("TaxaTools")$Built
```

**Always include two `.rs.restartR()` calls** — the first clears the stale session before
installing, the second ensures the freshly installed packages are loaded cleanly.
The `source()` line installs all packages in dependency order without opening each project.
Do not tell the user to use Session → Restart R or Cmd+Shift+F10 (does not work on this machine).

**Always include an explicit `library(Package)` + `packageDescription()$Built` check as its
own visible step, even though restarting R and reattaching would normally cover it** — do
not assume the user's next script will call `library()` itself, and do not assume a restart
alone is sufficient proof the fix is live. This is the single most common way a real fix
silently fails to take effect: the workflow session that actually runs the long script was
never itself the one restarted, so it keeps using whatever version of the package it loaded
earlier in that same session, regardless of what's now on disk. `packageDescription($Built)`
is the cheap, concrete way to confirm which build is actually loaded before trusting any
output from a long run.

**Always call out, by name, any stale cache that could hide the fix**, whenever the change
touches something with its own on-disk cache independent of the R package build itself —
e.g. a `TaxaFetch`/`TaxaFlag` `cache_dir` (`tools::R_user_dir("TaxaFetch", "cache")` by
default), or a workflow's own `.rds` checkpoint files (the `.save()`/`file.exists()` gate
pattern several of the external eDNA workflows use — see this file's own caching-gate notes
elsewhere). State plainly whether the specific fix needs a cache cleared or not — don't make
the user guess or ask; a raw-data fetch cache generally does NOT need clearing when only
downstream filtering/statistical logic changed (the cached raw records are still valid
inputs), but say so explicitly rather than leaving it ambiguous.

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

### `leaflet::tileOptions(tileSize = ...)` changes which tiles get requested, not just their display size (found 2026-08-07)
Setting a custom `tileSize` on `leaflet::addTiles()` to match a tile provider's real image
dimensions (e.g. GBIF's `@1x.png` tiles are genuinely 512x512, not the 256px Leaflet
assumes by default) looks like a safe display-only fix -- it is not. Confirmed by reading
Leaflet.js's own bundled source directly (`system.file("htmlwidgets/lib/leaflet/leaflet.js",
package = "leaflet")`, minified but greppable): `getPixelWorldBounds()` (the map's shared
world-pixel bounds at a given zoom) comes from the map's CRS alone, identical for every
layer; `_pxBoundsToTileRange()` then divides those SAME shared bounds by
`this.getTileSize()` -- **each layer's own** `tileSize` -- to compute that layer's tile
x/y indices. A layer with `tileSize = 512` therefore requests DIFFERENT x/y indices than
a layer left at the 256px default, at the identical zoom and viewport. If the tile
provider's own server-side addressing uses the standard 256px-grid convention regardless
of what pixel resolution its response images actually are (true for GBIF, and true for
most slippy-map tile services), overriding `tileSize` desyncs your requested indices from
what the server expects -- tiles silently stop rendering (wrong/out-of-range indices),
not just "display at the wrong size." Real production consequence: a `TaxaFlag::
review_spatial_context()` fix meant to enlarge GBIF's rendered density tiles broke tile
rendering entirely instead, found only via the user's own live click-through, then
diagnosed correctly (not guessed a second time) by reading the actual Leaflet source
rather than reasoning from memory of how `tileSize` "should" work. If a tile provider's
own images genuinely don't match Leaflet's 256px default, the correct levers are
`detectRetina`/`zoomOffset` (Leaflet's own purpose-built retina-tile mechanism, which
Leaflet itself uses instead of a raw `tileSize` override) or simply raising the map's
initial/default zoom level (verified separately, via real `check_gbif_tile_range()`
output, to genuinely increase a GBIF density blob's on-screen pixel footprint) -- never a
bare `tileSize` change on one layer alone.

**Update, 2026-08-07, later same thread -- the correct paired fix, verified live:** `tileSize`'s addressing
change (above) can be used SAFELY when paired with `zoomOffset`, which is exactly the
compensation Leaflet's own docs recommend for a provider whose default tile is already
higher-resolution than the 256px convention for the SAME addressed area (a real "retina"
tile, which is what GBIF's `@1x.png` genuinely is here -- confirmed elsewhere in this file
that GBIF's z/x/y follows the standard 256px-grid convention while returning a real 512px
image for that identical area). `leaflet::tileOptions(tileSize = 512, zoomOffset = -1)`
together: `zoomOffset = -1` requests one zoom level COARSER, whose standard-grid tile
covers exactly the geographic area a `tileSize = 512` on-screen slot spans at the map's
displayed zoom -- so the real, correctly-addressed 512px image fills that slot with no
forced downscaling and no addressing mismatch. **Verified live before shipping this
time, specifically to avoid repeating the mistake above**: built a standalone (non-Shiny)
leaflet HTML page (served over a local `python3 -m http.server`, since Chrome blocks
`file://` navigation via the extension) with this option pair alongside the no-override
default, side by side, screenshotted both via real Chrome browser automation at the
gadget's real zoom (7) and again after zooming in twice more -- confirmed visibly larger,
correctly positioned squares (same real coordinates/species, matching clusters exactly)
with zero tile gaps, zero basemap misalignment, and zero console errors at either zoom.
The lesson from the original entry stands (a BARE `tileSize` change alone is still a real
bug) -- this is the verified-safe paired form, not a contradiction of it. See
`TaxaFlag/CLAUDE.md`'s own top session note for where this landed
(`review_spatial_context()`'s GBIF tile layer).

### Single-column `[` drops a data.frame to a vector (but not a tibble) (found 2026-09-01)
`df[rows, c("one_col")]` returns a bare VECTOR when `df` is a plain
`data.frame`, and a one-column data frame when `df` is a `tbl_df`. Any
pipeline written against a tibble-returning function silently breaks if that
function's return class later changes to `data.frame` -- the failure surfaces
far downstream as an opaque method error, e.g.
`Error in UseMethod("left_join") : no applicable method for 'left_join'
applied to an object of class "character"`. Real incident: the kernel-priors
migration replaced `generate_full_priors()` (returned a tibble) with
`estimate_kernel_priors()` (returned a plain `data.frame` built by
`data.frame()`), and four production workflows' `taxaexpect_species_df <-
priors[rows, c("taxon_name")] |> left_join(...)` line crashed on the first
real Mugu run. Note `dplyr::bind_rows()` takes its output class from its
FIRST argument, so one data.frame at the head of an assembly propagates the
class through the whole table. Fixed at both layers, and both are worth
copying: (1) the estimator now returns `tibble::as_tibble()` output, restoring
drop-in class parity with the function it replaces (a returned class is part
of a function's contract); (2) the workflow lines were rewritten
class-agnostically as `filter() |> distinct() |> left_join()`. When replacing
any function, check its return CLASS as deliberately as its columns.

### A cache gate that tests only file.exists() silently serves stale results (found 2026-09-01)
Every workflow in this ecosystem checkpoints intermediate objects and skips
recomputation when the file exists (`.use_cache(path, step)` /
`if (file.exists(path))`). Neither form compares the checkpoint against the
files it was DERIVED from, so refreshing an upstream checkpoint leaves every
downstream one silently stale -- no warning, no error, just old results that
look current. Real incident (Mugu, found by tracing a scientific oddity, not
by any test): `raw_gbif` was refreshed 2026-08-29, but the cached
`geo_outlier_check` (2026-07-26) and `occurrences_clean` (2026-07-30) were
reused, so a month of new GBIF occurrence data -- including EVERY tidewater
goby record, 38 of them -- never reached the priors. The species' entire
prior rested on one literature record, and the resulting species call was
argued about for some time before the cause was found. Note the workflow had
already grown one hand-rolled patch for this exact class
(`.match_src_newer`), and a comment admitting `.use_cache()` "has no
automatic staleness check" -- a documented gap nobody generalised.
FIX, now in all four exposed workflows: the gate takes an `inputs =`
argument naming the files the cache derives from, and rejects the cache when
any input is NEWER (`file.mtime`), printing `STALE CACHE: <file> predates
<input> -- regenerating`. Wired across the real dependency chain
(`raw_gbif -> geo_outlier_check -> occurrences_clean -> model_fit/priors`).
`inputs = NULL` keeps the old existence-only behaviour, so un-wired call
sites are unaffected -- and note the NULL case must be guarded explicitly:
`file.exists(NULL)` ERRORS ("invalid 'file' argument"), which a unit test
caught before it reached a real run. When you add a checkpoint, declare what
it derives from.

### A per-key GBIF `limit` truncates by RETURN ORDER, not by sampling (found 2026-09-02)
`get_gbif_occurrences(limit =)` / `download_gbif_occurrences(limit =)` cap
records **per taxon key**, and the records kept are GBIF's own return order --
a non-random prefix. On the download backend the cap is applied AFTER import,
so it buys nothing: `limit = NULL` keeps everything and costs no extra API
load. Real damage, found only by chasing why every species' prior map looked
identical: with `GBIF_LIMIT <- 10000L`, 45 of Mugu's 231 taxa (95% of the
pool) and 110 of PtCon's 666 (61%) sat exactly at the cap. Because each
species' first 10,000 records came from the same few large multi-species
survey datasets, all 45 capped taxa emerged with an IDENTICAL spatial
distribution (per-species median distance 104 km, IQR 104-104 -- versus
81-217 for uncapped taxa), so both abundance and spatial pattern were
truncation artifacts and the composition priors were near-uniform and
near-uninformative. Great Lakes was unaffected (0 capped), which is why its
validation still stands. FIXES: `get_gbif_occurrences()` now detects any key
returning exactly `limit`, reports it via `attr(x, "capped_keys")`, and takes
`on_cap = c("warn", "escalate", "error")` -- `"escalate"` re-fetches those
keys through the download API with `limit = NULL`. `download_gbif_occurrences()`
(which the production workflows call DIRECTLY, bypassing the wrapper -- so the
guard had to live in both) now raises a WARNING rather than a message when
`limit` truncates a key, exposes `attr(x, "capped_keys")`, and takes
`on_cap = c("warn", "error")`. All three workflows now pass `limit = NULL`. Related post-hoc guards, since the
fetch radius cannot be chosen from lambda a priori (lambda is estimated FROM
the fetched data): `calibrate_kernel_bandwidth()` warns when the best lambda
sits at the top of `lambda_grid`, and `estimate_kernel_priors()` warns when
the record pool does not reach ~6 lambda from the site (beyond which a record
carries <0.25% weight) -- i.e. when the kernel is truncated by the fetch
boundary rather than by distance.

### A term that is correct for one resolver can be silently unsearchable in another (found 2026-09-02)
`barcode_term` is read by three different resolvers with three different
vocabularies: `TaxaTools::resolve_barcode_primers()` needs a PRIMER VARIANT
(`"COI-Folmer"`), `resolve_barcode_lengths()` accepts either, and every
NCBI query builder needs a term NCBI actually INDEXES. No GenBank record is
tagged "Folmer" -- so a variant-named query matches nothing. The failure is
silent in the worst way: "no sequences found" is a legitimate outcome of a
search, so it reads downstream as "this taxon has no barcode", not as "this
query was malformed". Real damage: changing a workflow's COI term from
`"COI"` to `"COI-Folmer"` (a correct fix for a genuine
`resolve_barcode_primers()` ambiguity) returned 0 hits for all 23 genera,
and confirmed live that EVERY registered variant except the MiFish pair had
the same defect all along -- `16S-Palumbi`, `cytb-Kocher`, `rbcLa`,
`matK-Kim`, `trnL-Taberlet` (live counts, Leptocottus COI: 0 broken vs 23
fixed). The reference fetch at least crashed a few lines later; the two
SILENT consumers were worse -- `audit_barcode_coverage()` and
`TaxaAssign::suggest_unreferenced_species()` would have reported every
species as having no barcode, inflating `unreferenced` and feeding
`apply_coverage_constraints()` and the unobserved-taxa machinery a fiction
that looks like a finding.
FIX: `TaxaTools::resolve_barcode_marker()` maps a variant to the marker it
amplifies (identity for anything unrecognised, so custom terms still search
as themselves; MiFish deliberately NOT remapped, since records really are
annotated with that primer name). All three query builders now resolve
through it, while primers/lengths keep using the caller's own tighter term.
The general rule: when one user-facing string feeds several resolvers, the
one whose failure mode is an EMPTY RESULT rather than an ERROR is the one
that will burn you -- check it explicitly. Related: the empty-result shape
matters too. `fetch_ncbi_reference_sequences()`'s zero-hit early return was
a bare 2-column frame, so the caller's next line
(`clean_taxon_names(reference_df$species)`) died on `NULL` and buried the
fetch's own correct diagnostic message; every early return now carries the
same columns a successful one does.

### A hand-drawn search polygon must persist, or every run has its own scope (found 2026-09-02)
The interactive `define_search_polygon()` gadget produces an ANALYST
DECISION, not a computed artifact: the polygon sets the scope of every
occurrence-derived quantity downstream (composition priors, the regional
back-off, the Good-Turing/Chao budget, which species exist at all). Treating
it like a recomputable cache means two runs of the same workflow silently
answer different questions. Found when a `RERUN_FROM_STEP <- 3` re-fetch
re-opened the gadget. A survey then found FOUR different behaviours across
five workflows: GreatLakes gated on `file.exists()` (correct);
MuguFishWorkflow gated it at step 3, so any step-3 rerun redrew it;
**MuguWilderFishWorkflow redrew it on EVERY run and never saved it**, so no
two runs shared a scope; both PtConception workflows read a hardcoded
absolute path to the 18S-prefixed file (stable, but an undocumented
cross-workflow dependency -- regenerating it rescopes both). Standardised:
every workflow now loads the saved polygon unless `REDRAW_BBOX <- TRUE`
(never invalidated by `RERUN_FROM_STEP`), backs up the old polygon before
replacing it, and logs the polygon's vertex count and lon/lat extent on
every run via `.bbox_report()` so each run's scope appears in its own log.
The general rule: anything a human draws, types, or curates is an input to
be versioned, not an intermediate to be regenerated.

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
| 2026-07-20 (Sonnet 5) | `filter_gbif_quality()` gains a 9th filter step (`exclude_equal_coords`/`exclude_near_zero`/`exclude_near_gbif_hq`, each default `TRUE`) | TaxaFetch | **Behavioral, not signature.** Calls `CoordinateCleaner::cc_equ()`/`cc_zero()`/`cc_gbif()` (identical lat/lon, near-(0,0), near GBIF's Copenhagen HQ) when that package is installed; skips with a message (not an error) otherwise, matching every other optional-column filter this function already has. Every existing in-repo caller (`TaxaExpect::build_priors()`, `TaxaExpect/inst/workflows/generate_priors_workflow.R`, `TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R`, `TaxaWizard/inst/graph/snippets/taxa_to_occ.R`) calls with no override and so now applies these checks automatically wherever `CoordinateCleaner` is installed in that environment -- pass all three as `FALSE` to restore the exact pre-2026-07-20 behavior. Deliberately does not hard-code that package's own buffer defaults (an attempt to do so hit real conflicting numbers across sources) -- calls the functions directly instead. `devtools::test()` 0 failures (481, up from 459), `devtools::check()` 0/0/0. See `TaxaFetch/CLAUDE.md`'s top session note. |
| 2026-07-20 (Sonnet 5) | `fetch_gbif_occurrences(geometry = NULL)` now issues an unrestricted global GBIF search | TaxaFetch | Additive, fully backward compatible -- `geometry` previously required a single WKT string (hard `stop()` on anything else); existing callers passing a real WKT string are unaffected. A real latent bug was fixed alongside it: `.gbif_checkpoint_path()`'s `nchar(geometry)` would have returned `integer(0)` for `NULL` geometry, breaking its `sprintf("%d", ...)` checkpoint-filename signature on the very first `geometry = NULL` call -- not reachable before this change since `geometry = NULL` was previously rejected at input validation. Added to support the new `check_geographic_outliers()` function, below. |
| 2026-07-20 (Sonnet 5) | `check_geographic_outliers()` added | TaxaFetch | New function, `R/check_geographic_outliers.R`. For species with few local (bbox-scoped) GBIF records (`min_local_n`, default `5L`), fetches that species' global distribution (`fetch_gbif_occurrences(geometry = NULL)`, row above) and flags local records that are geographic outliers against it via `CoordinateCleaner::cc_outl()` -- the generic fix for a real Mugu misidentification case (an African species with one errant citizen-science record in La Jolla), see `[[project_edge_case_error_taxa_design]]`. Adds `local_n`/`global_n_unique`/`outlier_status` columns; `outlier_status` is always one of `"not_tested_sufficient_local_data"`/`"insufficient_global_data"`/`"outlier"`/`"consistent"`, never a bare logical. Requires `CoordinateCleaner` (hard error if missing, no fallback exists). Wired into `MuguFishWorkflow.R`/`MuguWilderFishWorkflow.R` the same day -- see the next row for a real bug found on that first live run. See `TaxaFetch/CLAUDE.md`'s top session note for the full design record, including why `CoordinateCleaner` was adopted via `Suggests` rather than hand-rolled. |
| 2026-07-20, continued (Sonnet 5) | `check_geographic_outliers()`: `CoordinateCleaner::cc_outl()` now called once per species instead of once for the whole rare-species batch | TaxaFetch | **Behavioral bug fix, not a signature change.** Found on the row above's very first live run (wired into the real Mugu workflows the same day): `cc_outl()`'s `"distance"` method silently switches EVERY species in a single call to a coarser raster approximation whenever ANY ONE species in that call has >=10,000 records (confirmed directly from `cc_outl()`'s own source) -- a locally-rare species can still be globally common, so the real ~51-species/193,458-record Mugu batch had one common species silently degrade every other species' precision, clearing a real, obvious ~9,000km outlier (the exact motivating *Pseudotolithus epipercus* case -- it came back `"consistent"` instead of `"outlier"` on the first run). Two other hypotheses (a `gbifID` type mismatch between `download_gbif_occurrences()`'s `bit64::integer64` output and `fetch_gbif_occurrences()`'s character output; a species-crossing distance computation) were tested directly and refuted before finding the real cause. New regression test mocks `cc_outl()` directly to assert one call per species. `devtools::test()` 0 failures (483, up from 481), `devtools::check()` 0/0/0. **Any `check_geographic_outliers()` result computed before this fix is unreliable and should be recomputed** -- delete any cached `..._geo_outlier_check.rds` checkpoint before re-running. See `TaxaFetch/CLAUDE.md`'s top session note for the full diagnostic record. |
| 2026-07-20, continued yet further (Sonnet 5) | `fetch_gbif_occurrences()`'s checkpoint `remaining_keys` now correctly includes a chunk's own failed key on abort | TaxaFetch | **Behavioral bug fix, not a signature change.** Found via a real GBIF timeout during the user's own re-verification of the row above's fix. `global_pos` was previously advanced by a chunk's FULL size even when that chunk aborted partway through, so the checkpoint's `remaining_keys` (computed from that post-chunk position) silently excluded the specific key that failed -- and any others queued after it in the same chunk -- from ever being retried on resume, contradicting this function's own "never silently skip a key" design. Also produced a misleading `"Enable cache_dir for resumable fetches"` message on a real run where `cache_dir` genuinely was enabled and a real checkpoint had already been saved after the prior chunk. Fixed: the abort check now runs before `global_pos` advances past the aborting chunk; the whole aborting chunk (not just the failed key onward) is re-included in `remaining_keys` on resume, deliberately discarding any of that chunk's own partial pre-abort success to avoid duplicate rows. New regression test (5 keys, `chunk_size = 2`, 2nd key of the 2nd chunk mocked to fail) asserts the failed key is present in the saved checkpoint. `devtools::test()` 0 failures (487, up from 483), `devtools::check()` 0/0/0. See `TaxaFetch/CLAUDE.md`'s top session note for the full record. |
| 2026-07-23 (Sonnet 5) | `filter_gbif_quality()` gains a 10th/11th/12th check (`exclude_country_centroid`/`exclude_capital`/`exclude_institution`, each default `TRUE`) | TaxaFetch | **Behavioral, not signature.** Calls `CoordinateCleaner::cc_cen()`/`cc_cap()`/`cc_inst()` (near a country/province centroid, national capital, biodiversity institution) when installed; skips with a message otherwise, same convention as `cc_equ`/`cc_zero`/`cc_gbif`. All three resolve their `ref = NULL` default to bundled `countryref`/`institutions` data (no network call, confirmed via source). Every existing caller listed in the `cc_equ`/`cc_zero`/`cc_gbif` row above now also applies these three automatically; pass all three `FALSE` (alongside the earlier three) to restore pre-2026-07-20 behavior fully. Benchmarked at 122k rows: 1.37s, no performance concern. `devtools::test()` 0 failures (494, up from 487), `devtools::check()` 0/0/0. See `TaxaFetch/CLAUDE.md`'s top session note. |
| 2026-07-23, continued (Sonnet 5) | `filter_gbif_quality()` gains `attr(result, "removed_records")` | TaxaFetch | **Additive, fully backward compatible** -- the return value itself is unchanged (still just the cleaned data frame); this is purely a new attribute, not a second return value or signature change. Always present (a data frame, possibly zero rows, never `NULL`), one row per record removed by ANY of the nine filter steps, every original column preserved plus a new `filter_reason` column. Most steps get a single fixed reason string; the GBIF issue-code filter and the six `CoordinateCleaner` checks get per-row detail instead (the specific matched `bad_issues` code; every `CoordinateCleaner` check that flagged a given record, joined with `;` for a simultaneous multi-check hit). Internals fully rewritten to explicit keep-masks (no more `dplyr::filter()`) to support this -- incidentally fixed a real pre-existing bug (steps 7/8 never refreshed a stale count variable used only for the console message, found but left alone 2026-07-20). `devtools::test()` 0 failures (506, up from 494), `devtools::check()` 0/0/0. See `TaxaFetch/CLAUDE.md`'s top session note for the full record, including a real "split-string sprintf" bug caught in the first draft before shipping. |
| 2026-07-23, continued yet further (Sonnet 5) | `filter_gbif_quality()`: `exclude_institution` renamed `flag_institution`; institution-flagged records are RETAINED with 4 new columns, never moved to `removed_records` | TaxaFetch | **Behavioral default change AND signature change (rename).** No existing caller was passing `exclude_institution=` explicitly (all real in-repo callers use defaults), so the rename has no real fallout. Default `TRUE` unchanged, but the meaning flips: proximity to a biodiversity institution is no longer treated as an unambiguous data-entry error like the other five `CoordinateCleaner` checks -- it gets `institution_flag`/`institution_name`/`institution_type`/`institution_dist_m` columns on the retained data instead (via new internal `.nearest_institution()`, since `cc_inst(value="flagged")` only returns a boolean). Motivated by the user reviewing the real 29 flagged Mugu records directly and finding several likely-genuine field observations (live fish near a university botanical garden pond) mixed with likely-genuine errors -- field stations are often sited exactly where good habitat is, so this specific check needs a human decision, not a silent drop. The other five checks are unaffected and still auto-remove; they now run as their own step (9) before institution flagging (step 10), so a record failing both is removed and never reaches the flagging step. `devtools::test()` 0 failures (515, up from 506), `devtools::check()` 0/0/0. |
| 2026-07-23, continued yet further (Sonnet 5) | `TaxaHabitat::flag_institution_candidates()` added | TaxaHabitat | New function, `R/flag_institution_candidates.R`. Classification stage (pure, no interaction, no removal) for the `institution_flag` column above -- tiers flagged records "high"/"low"/"ambiguous" by crossing the matched institution's real `type` (verified via `CoordinateCleaner::institutions`, not guessed) against the record's own `kingdom`. Mirrors `flag_habitat_inconsistencies()`'s existing role ahead of an interactive review gadget. The gadget itself (`review_institution_flags()`, meant to mirror `review_spatial_flags()`) is scoped in detail but deliberately **not yet built** -- real time constraints raised mid-session; see `TaxaHabitat/CLAUDE.md`'s top session note and `[[project_geographic_outlier_check]]` for the exact resume point. A real bug (all-NA logical-index subsetting for a flagged record whose matched institution has no recorded type) was found and fixed before shipping -- caught by the console summary message itself printing wrong counts. `devtools::test()` 0 failures (158, up from 142), `devtools::check()` 0/0/0. |
| 2026-07-20 (Sonnet 5) | `score_consensus(rank_thresholds=)` default's fourth tier relabeled `order` → `phylum` | TaxaAssign | **Behavioral, not signature** -- numerically identical default (`85`), label-only fix. The user caught that the Session 147 default (`c(species=98, genus=95, family=90, order=85)`) mislabels its fourth tier: the literature this 85% value is corroborated by (Ransome et al. 2017 and others, compiled independently the same day in `ecosystem_docs/AQUARIUM_BENCHMARK_DESIGN.md`'s COI threshold table) treats 85% as a **phylum**-level cutoff, not order-level, and that same literature survey found no widely-cited genuine order-level COI threshold to substitute in its place -- so the fix is a relabel (`order=85` → `phylum=85`), not an added 5th tier. Verified before relabeling that this doesn't silently break the mechanism: `TaxaTools::detect_ranks()`'s standard rank ladder already includes `"phylum"` (`kingdom, phylum, class, order, family, genus, species`), and real production `match_df` data (confirmed on the bundled `TaxaID_test_BLAST.rds` fixture) carries a populated `phylum` column, so the auto-detected `rank_system` still reaches this tier exactly as `order` did. The two real workflow scripts' own `score_consensus()` calls (`TaxaAssign_bayesian_workflow.R`, `TaxaAssign_llm_workflow.R`) pass an explicit `rank_system = c("family", "genus", "species")` that excludes both `order` and `phylum` -- so for those two calls specifically, the fourth tier was already a no-op before this change and remains one after, unaffected either way. Propagated to `TaxaAssign/man/score_consensus.Rd` (regenerated), `TaxaWizard/inst/metadata/TaxaAssign.json`, `TaxaAssign_supplemental_methods.md`, and the `STATISTICAL_COMPONENT_CATALOG.md`/`STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`/`taxonomy_rank_review.md` reference docs; historical session notes describing the original Session 147 default are left as-is (a record of past state, not current documentation). `devtools::test()` unaffected (no test asserts on the tier name). See `TaxaAssign/CLAUDE.md`'s Function Inventory row for `score_consensus()`. |
| 2026-07-23 (Sonnet 5) | `read_speciesnet_output()` added | TaxaMatch | Additive, new exported function (`R/read_image_classifiers.R`). Ingests real SpeciesNet CLI (`google/cameratrapai`) `predictions_json` batch output -- label format (`uuid;class;order;family;genus;species;common_name`) verified directly against the shipped taxonomy file, not assumed. Treats the raw top-5 `classifications` block as the primary multi-candidate source rather than the ensemble's already-rolled-up `prediction` field, informed by Markoff & Galaktionovs 2025 (arXiv:2510.14594) confirming SpeciesNet's taxonomic rollup is a deliberate precision-over-recall design choice. Along the way, found that `read_wildlife_insights_output()` (existing function, same file) targets a JSON shape that matches neither the real Wildlife Insights platform (CSV bulk downloads, not JSON) nor the real SpeciesNet CLI (`predictions` is a list, not a dict) -- see next row. `devtools::check()` 0/0/1 (pre-existing environmental note) at the time this function was added. See `TaxaMatch/CLAUDE.md`'s top session note for the full record. |
| 2026-07-23 (Sonnet 5, continued) | `read_wildlife_insights_output()` removed entirely (not deprecated) | TaxaMatch | **Breaking**, but zero real callers found anywhere in the monorepo via grep (only its own tests, README examples, and TaxaWizard template snippets/prompts) -- same zero-caller-removal bar as `fetch_reference_sequences()`/`audit_barcode_coverage_ncbi()`/`expand_consensus_candidates()`. Its dict-keyed-by-filename JSON assumption matched neither real candidate source checked (real Wildlife Insights platform downloads are CSV, not JSON; real SpeciesNet CLI's `predictions` is a list, not a dict) -- a prior code review (`TaxaMatch/inst/taxamatch_review.Rmd`) had already flagged suspicion about this exact premise, never resolved until this session. Superseded by `read_speciesnet_output()` (row above). Dependents repointed: `TaxaMatch-package.R`, both READMEs, `TaxaWizard/inst/graph/workflow_graph.json` (2 edges), `.../snippets/image_to_match.R`, `.../snippets/image_refs_to_matrix.R`, `.../prompts/phase_classify.md`, `.../metadata/TaxaMatch.json`, `.../metadata/TaxaLikely.json`. `devtools::test()` TaxaMatch 494/494 (down from 508, 14 tests removed with the function), TaxaWizard 367/367 unaffected; `devtools::check()` TaxaMatch 0 errors/0 warnings/0 notes. See `TaxaMatch/CLAUDE.md`'s top session note for the full record, including a separately-flagged (not fixed) `data=`-vs-`files=` parameter-name drift found in TaxaWizard's metadata while repointing these snippets. |
| 2026-07-23 (Sonnet 5) | `fetch_inat_occurrences()` added | TaxaFetch | Additive, new exported function (`R/fetch_inat_occurrences.R`). Counts real local iNaturalist observation records (not a range-polygon test like `check_inat_range()`) via `/v1/observations`, with `captive`/`quality_grade` filters that can surface casual-grade cultivated/captive records GBIF-style indexing excludes. Non-GBIF occurrence source for `TaxaExpect::generate_domestic_food_priors()` (next row). Implements `ecosystem_docs/REENTRY_PROMPT_domestic_food_species_priors.md`. `devtools::test()` 0 failures (539, up from 506), `devtools::check()` 0/0/0. |
| 2026-07-23 (Sonnet 5, continued) | `generate_domestic_food_priors()` added | TaxaExpect | Additive, new exported function (`R/generate_domestic_food_priors.R`). Implements the reentry prompt's three-vector design: `domestic_animal_taxa`/`food_species_taxa` (fixed, pre-populated defaults) plus `candidate_plant_taxa` (no default list -- only produces a row when a live `fetch_inat_occurrences(quality_grade="casual")` check finds real local cultivated evidence, since the reentry prompt's own CSV-overlap finding showed the two candidate source files it considered are the same underlying list at two processing stages, not a genuine food-vs-ornamental split). Output rows carry a real `taxon_name` (unlike `generate_undetected_diversity()`'s anonymous proxies), a new `prior_source_type` categorical column, and `model_tier = "tier_domestic_food"`. Does not address cross-genus reference gaps (`Bison bison`/`Bos taurus`) -- see the reentry prompt's corrected `Homo sapiens` finding for why this fix's value is the categorical flag plus help for weaker matches, not sequence-level resolution. `devtools::test()` 0 failures (481, up from 445), `devtools::check()` 0/0/0. |
| 2026-07-23 (Sonnet 5, continued yet further) | `stack_occurrences(collapse_duplicate_occasions = TRUE)` added | TaxaFetch | **Behavioral default change, not just an addition.** Collapses rows sharing the same `taxon_col`/`date_col`/rounded-`lat_col`/`lon_col` combination -- catches repeat citizen-science reports of one detection occasion (e.g. many eBird checklists for one rare-bird-alert individual, many iNaturalist uploads from one bioblitz) across DIFFERENT records/platforms, which the existing `gbifID` dedup (Session 140) cannot touch since each is a genuinely distinct GBIF record. Default `TRUE` because `TaxaExpect::prepare_model_dataframe()` (verified directly before implementing, per the user's explicit request) counts raw records as both the binomial numerator (`n_species`) and shared effort denominator (`n_total_at_site`) -- uncollapsed repeat reports inflate a species' modeled relative detection frequency directly, and occupancy-style priors should be keyed on detection occasions, not report counts. Content-based match (not exact-ID); a row missing any key component is always kept; silent no-op when `taxon_col`/`date_col` aren't present, matching the `gbifID` step's own convention -- no existing test regressed, since no pre-existing fixture carries an `eventDate`/`year`/`month`/`day` column. Set `collapse_duplicate_occasions = FALSE` to restore the pre-2026-07-23 one-row-per-raw-report behavior. `devtools::test()` 0 failures (549, up from 539), `devtools::check()` 0/0/0. See `TaxaFetch/CLAUDE.md`'s top session note for the full record. |
| 2026-07-23 (Sonnet 5, same day, immediate follow-up) | `fetch_dataone_occurrences(gbif_snapshot_path=)` removed entirely | TaxaFetch | **Breaking, but zero real callers** (grepped the whole monorepo -- same "no external users" bar already used for `fetch_reference_sequences()`/`expand_consensus_candidates()`/`read_wildlife_insights_output()`). Prompted by the user asking, right after the row above shipped, whether it makes any existing dedup redundant: the `gbifID` step is NOT redundant (catches an exact-duplicate GBIF record with `NA` `scientificName`/`eventDate`, which the content-based step above deliberately never touches) but this DataONE-vs-GBIF-snapshot dedup (`.load_gbif_hashes()`/`.deduplicate_against_gbif()`, same key formula) IS -- and was actually less safe than the row above (it coalesced missing name/date/lat/lon to `""`/`0` before hashing, risking spurious matches on incomplete data, the opposite of the new step's design). `gbif_hashes` removed from 5 internal call sites (`.process_one_dataset()`/`.finalize_entity()`/`.attempt_odm_join()`); the two helper functions deleted; roxygen repointed at `stack_occurrences(collapse_duplicate_occasions=)`. `devtools::test()` 0 failures (553, up from 549), `devtools::check()` 0/0/0. See `TaxaFetch/CLAUDE.md`'s top session note for the full record. |
| 2026-07-23 (Sonnet 5, same day, yet another follow-up) | `dedupe_occurrences()` added; `stack_occurrences()` no longer removes any rows | TaxaFetch | **Breaking, real consequence for every existing caller.** Prompted by a user naming/design critique: "stack_occurrences" implies pure combination, so bundling dedup inside it risks a single-source caller skipping the call (and its dedup) entirely -- confirmed not hypothetical (the documented GBIF-only pipeline never calls `stack_occurrences()` at all) and not new to this session's own `collapse_duplicate_occasions` addition (the pre-existing Session 140 `gbifID` dedup has the identical single-frame blind spot). Both mechanisms moved (user's explicit choice, via `AskUserQuestion`) into new `dedupe_occurrences(data, ...)`, which takes a single frame (stacked or not) -- `stack_occurrences()` now only row-binds + adds `point_id`, row count always exactly the sum of inputs. **Because the pre-existing `gbifID` dedup moved too, every real caller of `stack_occurrences()` silently loses that protection unless updated** -- found via grep and fixed: `TaxaExpect::build_priors()` (real package code, `dedupe_occurrences()` now runs unconditionally, not just when `supplemental_occurrences` was stacked), plus 8 `inst/`/vignette files across `TaxaAssign`, `TaxaExpect`, and `TaxaFetch` (including the root `inst/TaxaID_Workflow_Template_TEST.R` and the Layer-1 teaching script's single-GBIF-source Variant A -- exactly the case this change targets). `devtools::test()` 0 failures (563, up from 553), `devtools::check()` 0 errors/0 warnings/0 notes. See `TaxaFetch/CLAUDE.md`'s top session note for the full record. |
| 2026-07-23 (Sonnet 5) | `train_likelihood_model()` gains `Support_Curves`; `evaluate_likelihoods()` gains `species_support`/`genus_support`/`family_support`/`own_rank_support`; `compute_rank_thresholds()` added | TaxaLikely | Additive, fully backward compatible -- no signature changes on either existing function; new columns/slot are simply absent-safe (`NA`/`NULL`) when not computable. Implements the `score_support_posthoc_and_rank_thresholds` reentry doc's Task 1 (the design decisions: package placement in TaxaLikely near `evaluate_likelihoods()`; EB-shrunk curves computed once by `train_likelihood_model()` and stored in `model_params$Support_Curves`, not recomputed per query; all three `*_support` values always populated where computable, plus an `own_rank_support` convenience column). New internal `.compute_rank_score_curves()` (`R/support_curves.R`) makes `diagnostics/score_floor_roc_sweep.R`'s genus-/family-equal-weighted, Empirical-Bayes-shrunk per-rank TPR/FPR curves real package machinery, shared by both consumers. `species_support`/`genus_support`/`family_support` are a model-independent, score-ONLY diagnostic (P(a real congener/confamilial/cross-family pair would score this high or higher) -- LOWER is stronger evidence), deliberately separate from `absolute_fit_pvalue` (which is model-based). `compute_rank_thresholds(seq_matrix, ...)` is the new exported, marker-agnostic Youden's-J threshold deriver `TaxaAssign::score_consensus()`'s new required-arg error message (next row) points at. `devtools::test()` 0 failures (463), `devtools::check()` 0/0/0. See `TaxaLikely/CLAUDE.md`'s top session note for the full record. |
| 2026-07-23 (Sonnet 5, continued) | `posterior_consensus()` gains `winner_species_support`/`winner_genus_support`/`winner_family_support`/`winner_own_rank_support` | TaxaAssign | Additive, fully backward compatible -- mirrors the existing `winner_absolute_fit_pvalue` pass-through pattern exactly (read from the winning row, `NA` when the source column is absent from `posterior_df`, present in both the main result path and `.empty_consensus_row()`'s NA-filled fallback). Passes through TaxaLikely's new `species_support`/`genus_support`/`family_support`/`own_rank_support` columns (row above) unchanged. `devtools::test()` 0 failures (256, up from 255), `devtools::check()` 0/0/0. |
| 2026-07-23 (Sonnet 5, continued further) | `add_posthoc_assessment()` gains `score_support_flag` + `own_rank_support_col`/`weak_score_support_threshold` params | TaxaFlag | Additive, fully backward compatible -- a genuinely SEPARATE new column, not folded into `posthoc_assessment`'s override chain the way `"unsupported_rank"` is. Deliberate design choice per the reentry doc's own cautionary precedent: the `trusted_rank` ladder-walk (built 2026-07-19, removed 2026-07-20 -- see `[[project_rank_trust_mechanism_removed]]`) showed what goes wrong when a mechanism recomputes/overrides an existing categorical judgment; `score_support_flag` stays a plain additive threshold on `winner_own_rank_support` (`"weak_score_support"` above `weak_score_support_threshold`, default `0.5`; `"adequate_score_support"` otherwise; `NA` when the source column is absent) that never interacts with `posthoc_assessment`. `devtools::test()` 0 failures (119, up from 112), `devtools::check()` 0 errors/0 warnings (1 pre-existing, unrelated warning + note in `build_review_covariates.R`, not touched this session). |
| 2026-07-23 (Sonnet 5, continued yet further) | `score_consensus(rank_thresholds=)` loses its default | TaxaAssign | **Breaking, intentionally.** `rank_thresholds` is now a required argument (no default, errors immediately if omitted) -- mirrors `join_priors(backbone_id=)`'s exact precedent (Session 143: same `missing()` + `cli::cli_abort()` pattern, same "no safe universal default" reasoning). The Session 147 GITA/Jonah Ventures default (`c(species=98, genus=95, family=90, phylum=85)`) is removed, not just changed, since this function has no way to know the marker or data type `score_col` was scored against. The error message points at two options: supply real thresholds directly, or derive marker-specific ones via the new `TaxaLikely::compute_rank_thresholds()` (row above). Passing `rank_thresholds = NULL` explicitly still means "disable rank capping" -- unchanged, since that's an explicit value, not an omission. Real call-site survey (from the reentry doc): both `TaxaAssign_llm_workflow.R` calls flagged as "would break" (`score_con_wilder`/`score_con_JV`) turned out to already pass `rank_thresholds = NULL` EXPLICITLY, so neither needed a code change -- only `vignettes/taxaid-ecosystem.Rmd`'s one bare `score_consensus(match_df)` call and ~20 test-file call sites (mostly unrelated to rank-threshold behavior, needed `rank_thresholds = NULL` added to keep exercising what they actually test) were updated. `devtools::test()` 0 failures (256), `devtools::check()` 0/0/0. See `TaxaAssign/CLAUDE.md`'s top session note for the full record. |
| 2026-07-23 (Sonnet 5, later same day) | `species_support`/`genus_support`/`family_support`/`own_rank_support` -> `species_confusion_risk`/`genus_confusion_risk`/`family_confusion_risk`/`own_rank_confusion_risk`; `model_params$Support_Curves` -> `Confusion_Risk_Curves` | TaxaLikely | **Breaking rename, no math changed.** The user noticed the original names inverted this ecosystem's own high=concern convention for risk-style metrics (e.g. `TaxaFlag::flag_contaminant()`'s `contaminant_score`) -- "support" implied higher=better while the values are one-sided tail probabilities where HIGHER means MORE confusable with a congener/confamilial/cross-family relative, i.e. WEAKER evidence. Taking the complement (`1 - value`) was considered and rejected (would invite the p-value fallacy, conflating `1-p` with a calibrated confidence). Internal `.lookup_support_value()` -> `.lookup_confusion_risk_value()` too. See `TaxaID/CLAUDE.md`'s top session note and `TaxaLikely/CLAUDE.md`'s matching note for the full record. |
| 2026-07-23 (Sonnet 5, later same day) | `posterior_consensus()`'s `winner_species_support`/`winner_genus_support`/`winner_family_support`/`winner_own_rank_support` -> `winner_species_confusion_risk`/`winner_genus_confusion_risk`/`winner_family_confusion_risk`/`winner_own_rank_confusion_risk` | TaxaAssign | **Breaking rename, no math changed** -- same reasoning and same session as the TaxaLikely row above; pure pass-through columns renamed to match their upstream source. |
| 2026-07-23 (Sonnet 5, later same day) | `add_posthoc_assessment()`'s `score_support_flag` -> `confusion_risk_flag`; `own_rank_support_col` -> `own_rank_confusion_risk_col`; `weak_score_support_threshold` -> `high_confusion_risk_threshold`; flag values `"weak_score_support"`/`"adequate_score_support"` -> `"high_confusion_risk"`/`"low_confusion_risk"` | TaxaFlag | **Breaking rename, no math changed** -- same reasoning and same session as the two rows above. |
| 2026-07-24 (Sonnet 5) | `flag_contaminant()`'s `contaminant_score`/`{contaminant_type}_risk`/`{contaminant_type}_reason` -> fixed-name `observation_validity`/`validity_flag`/`validity_reason`; `flag_handler()`'s `flag_handler`/`flag_handler_score`/`flag_handler_reason` -> the same three names | TaxaFlag | **Breaking rename + signature-adjacent change** (`contaminant_type` no longer changes output column names, only the type qualifier embedded in `validity_flag`'s value, e.g. `"invalid_lab_contaminant"`). Both functions now share identical column names -- verified safe since they operate on different data modalities (per-taxon eDNA vs. per-detection camera-trap) and no real workflow merges them. `report_flags()` gained a third, additive detection branch reading the type out of `validity_flag`'s values. See `TaxaFlag/CLAUDE.md`'s top session note for the full record, including the mid-design correction of the 2026-07-23 audit's "high=risk" mischaracterization of both metrics (actually high=good/genuine). `devtools::test()` 0 failures (123, up from 119), `devtools::check()` clean (1 pre-existing unrelated warning+note). |
| 2026-07-24, same day (Sonnet 5) | Both real PtConception workflows (`PtConceptionWorkflow_12S_single_site.R`, `PtConceptionWorkflow_18S_2_single_site.R`) updated for the row above | (workflow scripts, not a package) | Every real `lab_contaminant_risk`/`lab_contaminant_score` reference (Step 2 filter, Step 6/9 provenance joins, 12S's final `accurate_precise_consensus` filter) updated to `validity_flag`/`observation_validity`. `PtConceptionWorkflow_18S_2_single_site.R`'s pre-existing Session-101 cached-RDS name-migration block extended (not replaced) with a second branch forward-migrating old values to the new schema, so a pre-2026-07-24 cached `_contaminant_flags.rds` stays readable. Verified against both real cached checkpoints (12S 43/10300/3254, 18S 1/18693/2503 high/moderate/low, both still pre-2026-07-24 schema). Both files backed up first (`*.bak_pre_validity_schema`, not under git) and parse cleanly; not yet run end to end. |
| 2026-07-24 (Sonnet 5) | `convert_taxonomy_backbone()`'s not-found fallback value now cleaned via `clean_taxon_names()` | TaxaMatch | **Behavioral, not signature.** Previously only the target-backbone-matched path (`matched_name`/`target_<rank>`) was cleaned; a taxon not found in the target backbone passed through with its raw original value untouched. Found via a real compound hybrid-formula NCBI accession label (`"((Citrus unshiu x Citrus sinensis) x Citrus reticulata) x Citrus reticulata"`) surfacing unmodified in `match_obj$species` during the domestic/food-priors residual-count exercise on real 18S data. Does not change which names are sent to `verify_fn` or which rows count as "found" -- only the not-found fallback value's formatting. `devtools::test()` 0 failures (500, up from 496), `devtools::check()` 0/0/0. |
| 2026-07-24 (Sonnet 5, continued) | `fetch_inat_occurrences()` gains `inat_kingdom`; `generate_domestic_food_priors()` gains an iNaturalist kingdom cross-check | TaxaFetch, TaxaExpect | Additive. `fetch_inat_occurrences()`'s new `inat_kingdom` (via `.iconic_to_kingdom()`, same lookup `check_inat_range()` uses) lets a caller detect a possible cross-kingdom homonym -- iNaturalist resolves names against its own curated taxonomy, distinct from both NCBI and GBIF. `generate_domestic_food_priors()` now cross-checks it against a candidate's known kingdom (opt-in, requires a `kingdom` column in the `taxonomy` argument); on a mismatch, discards the local-evidence boost (`n_local -> NA`, `warning()`) without removing the candidate's fixed-list category. New output columns `inat_kingdom`/`inat_kingdom_mismatch`, always present. `devtools::test()` 0 failures (TaxaFetch 541/541 up from 539, TaxaExpect 495/495 up from 481), `devtools::check()` 0/0/0 both. |
| 2026-07-25 (Sonnet 5) | `verify_taxon_names()` gains `matched_rank`/`is_synonym`; `matched_name` now sourced from GNVerifier's `matchedCanonicalSimple`/`currentCanonicalSimple` instead of a local authority-stripping regex | TaxaTools | **Behavioral, not signature -- but a real output change for two classes of input.** (1) Any subspecies-rank match: previously silently truncated to a binomial by the old regex (confirmed: `"Delphinus delphis ponticus Barabash, 1935"` -> `"Delphinus delphis"`, dropping the subspecies epithet); now correctly preserved. (2) Any name whose best backbone match is a taxonomic synonym (`is_synonym = TRUE`): `matched_name` now reports the backbone's currently-accepted name instead of the synonym form (e.g. `"Inu"` -> `"Luciogobius"` under GBIF). New `matched_rank` reports the rank the match actually resolved at, independent of what rank the query implied. Verified backbone-general (not GBIF-specific) via a live 5-backbone comparison (Catalogue of Life/ITIS/NCBI/WoRMS/GBIF) before shipping -- see `TaxaTools/CLAUDE.md`'s top session note. `backbone_id = 4` never reaches this code path (`.verify_via_ncbi()` instead) and so never gets synonym resolution, but does get `matched_rank`. `devtools::test()` 0 failures (824, up from ~818), `devtools::check()` 0/0/0. |
| 2026-07-25 (Sonnet 5, continued) | `convert_taxonomy_backbone()` now corrects `taxon_name_rank` (not just `taxon_name`) when a row's own claimed rank has no matching target value | TaxaMatch | **Behavioral, not signature.** Closes the "Inu Inu" fabricated-pseudo-binomial bug: previously, when `taxon_name` fell back to a coarser resolved name (e.g. a genus-only match), `taxon_name_rank` kept its stale, now-wrong rank label -- a bare genus reported as if still species-level, which a downstream slash-name builder (`TaxaAssign::add_slash_taxon()`) then treated as a malformed binomial and duplicated into a fabricated name. Uses `TaxaTools::verify_taxon_names()`'s new `matched_rank` column (row above); silently skipped (not an error) for a `verify_fn` that predates it, e.g. one injected for offline testing -- confirmed via a dedicated backward-compatibility test. `devtools::test()` 0 failures (`test-convert_taxonomy_backbone.R` 43/43 up from 41, full suite 504/504), `devtools::check()` 0/0/0. |
| 2026-07-25 (Sonnet 5, later same day) | `fill_higher_ranks()`'s `genus` output now corrected to the backbone's resolved name for a genus-level synonym | TaxaTools | **Behavioral, not signature.** Companion fix to the two rows above, prompted by the user asking to double-check `fill_higher_ranks()` for the same issue. Previously `genus` was always the locally-extracted query string, even when the backbone flagged it as a synonym -- meaning it could disagree with `convert_taxonomy_backbone()`'s (now-corrected) output for the same taxon. Real consequence found: `TaxaAssign::join_priors()`'s `.expand_coarse_rank_rows()` exact-string-matches a likelihood-side coarse `taxon_name` against `expansion_taxonomy`'s `genus` column (built via `fill_higher_ranks()`) -- a disagreement here silently drops real occurrence-based coarse-rank species expansion for the affected taxon, falling back to the dark-diversity floor. `genus` is now corrected only when `matched_rank == "genus"` specifically (defensive against trusting a coarser-rank resolution as a genus substitution); silently skipped when `verify_fn`'s response lacks `matched_rank`. `devtools::test()` 0 failures (829, up from 824), `devtools::check()` 0/0/0. `escalate_taxonomic_rank()` was also checked and found to have no analogous issue -- no code change there. |
| 2026-07-25 (Sonnet 5, later still) | `convert_taxonomy_backbone()` now also clears rank columns finer than a row's corrected rank (e.g. `species` -> `NA` when demoted to genus) | TaxaMatch | **Behavioral, not signature -- closes a real regression found only by testing against production, not by inspection.** The `taxon_name_rank` fix (row above) worked in isolation, but the real `Mugu_Match_from_BLAST.R` script calls `TaxaTools::create_taxon_names()` a SECOND time immediately after `convert_taxonomy_backbone()` to re-derive `taxon_name` from rank columns -- and since the finer `species` column still held its stale, per-column-fallback-cleaned value (`"Inu"`), that second call applied "most specific non-NA rank wins" and silently reverted the whole fix back to the wrong species-level label. Confirmed live against the real accession (`LC765844`): `taxon_name`/`taxon_name_rank` were briefly correct right after `convert_taxonomy_backbone()` but wrong again by the time `match_12s.rds` was saved. Now every rank column finer than the corrected rank is cleared to `NA` on the same rows, so any re-derivation downstream -- this one or a future one -- can't resurrect the stale value. `genus` itself is untouched (it's AT the corrected rank, not finer). `devtools::test()` 0 failures (`test-convert_taxonomy_backbone.R` 47/47 up from 43, full suite 508/508), `devtools::check()` 0/0/0. Separately: diagnosing this surfaced a real, still-open library-path issue -- the user's live session (a different RStudio project, no project-level `.Rprofile`) kept resolving `TaxaMatch` to the system default library instead of `~/Library/R/4.0/library` even after `.rs.restartR()`; worked around via `devtools::load_all()` directly on the source, root cause not fully resolved. |
| 2026-07-28 (Sonnet 5) | `generate_domestic_food_priors()`: `known_cultivar_taxa` param added; `match_list_taxa`/`taxaexpect_priors` params added; `food_species_taxa` default extended 20 -> 449 species | TaxaExpect | **Additive (new params, `NULL`/default-preserving), plus a behavioral default change** (the larger `food_species_taxa` default checks more species when `match_list_taxa` is not supplied). Implements the match-list-gated architecture confirmed with the user 2026-07-24: `match_list_taxa` (taxa with real likelihoods this run) gates all four fixed/supplied channels to the intersection and drives an automatic open-discovery residual step (unreferenced match-list taxa, `phylum %in% c("Streptophyta","Tracheophyta")`, deliberately not pre-restricted to any known list) using the new `taxaexpect_priors` param to exclude already-modelled taxa. New `cultivar_evidence_source` output column (`"known_list"`/`"candidate_supplied"`/`"inat_confirmed"`) distinguishes the three ways a `prior_source_type = "domestic_plant"` row can arise. `match_list_taxa = NULL` (default) preserves the original 2026-07-23 unrestricted behavior exactly. `devtools::test()` 0 failures (536, up from 481), `devtools::check()` 0/0/0. |
| 2026-07-28, same day (Sonnet 5) | All four real production workflows (`PtConceptionWorkflow_12S_single_site.R`, `PtConceptionWorkflow_18S_2_single_site.R`, `MuguFishWorkflow.R`, `MuguWilderFishWorkflow.R`) rewired for the row above | (workflow scripts, not a package) | `match_list_taxa`/`taxonomy` now sourced from each script's own match object (`match_obj_restored` for 12S -- required relocating the call to after that object is finalized, since it didn't exist yet at the original Step-5 call site; `match_obj` for 18S_2; `match_taxonomy`/`esv_expanded` for the two Mugu scripts, both already available early, no relocation needed). The 18S_2 script's ad hoc `candidate_plant_taxa` sourcing (GBIF-occurrence-derived sampling-group restriction) is fully superseded by the open-discovery residual step and removed. All four parse cleanly; not yet run end to end (real GBIF/NCBI/iNat/LLM API calls, real checkpoints -- the user's call). |
| 2026-07-30 (Sonnet 5) | `compute_group_priors(taxaexpect_priors, taxonomy_map, rank_cols = c("genus","family"))` added; `posterior_consensus(group_priors = NULL)` added | TaxaAssign | New function + new optional param. `consensus_prior` (existing output column) redesigned from a candidate-scoped MAX to a real group-level SUM when `group_priors` is supplied -- a materially different, stronger statement (a single observation's own candidate set rarely contains every locally-modelled group member). The old candidate-scoped MAX fallback is REMOVED entirely (not kept as a default) -- `consensus_prior` is `NA_real_` when `group_priors` is `NULL` or has no matching row, a real behavior change for any caller that relied on the old fallback (no real caller did before this session). New `consensus_has_occurrence_record` output column is the dedicated presence signal downstream consumers should read -- `consensus_prior`'s own `NA`-ness cannot distinguish "checked, absent" from "`group_priors` never supplied." `devtools::test()` 615/615, `devtools::check()` 0/0/0. See `TaxaAssign/CLAUDE.md`'s top session note. |
| 2026-07-30 (Sonnet 5) | `add_posthoc_assessment()`: `posthoc_assessment`/`tiers`/`taxon_col`/`tier_col`/`finest_rank` removed entirely; `winner_prior_col`/`consensus_prior_col`(old)/`expected_prior_threshold` -> `winner_theta_col`/`winner_record_col`/`consensus_prior_col`(new)/`consensus_record_col`/`expected_theta_threshold` (no default, named-by-rank vector); `confusion_risk_flag` -> `primary_discrimination`/`consensus_discrimination` | TaxaFlag | **Breaking, intentionally -- supersedes the whole 2026-07-28 Axis 1 design**, not an incremental change. `expected_theta_threshold` has no safe universal default (mirrors `join_priors(backbone_id=)`'s precedent) -- callers must supply at least a `"species"` entry. Any workflow calling the pre-2026-07-30 signature will error, not silently degrade. All 5 real production workflows (2 Mugu + 3 PtConception) updated the same day. `devtools::test()` 240/240, `devtools::check()` 0 errors (1 pre-existing unrelated warning+note, untouched). See `TaxaFlag/CLAUDE.md`'s top session note. |
| 2026-07-30 (Sonnet 5) | `Mugu_Match_from_BLAST.R`/`Mugu_Match_from_Wilder.R`/all 5 real workflows: match-object `convert_taxonomy_backbone(target_backbone_id=)` GBIF -> NCBI; `join_priors(backbone_id=)` GBIF -> NCBI | (workflow scripts, not a package) | Backbone-architecture decision, not a package change -- NCBI adopted as the common working backbone for these vertebrate-focused eDNA workflows (see this file's own top session note for the full cost/dependability reasoning). Fixes a real, confirmed backbone-disagreement bug (`Urolophus halleri`/`Urobatis halleri`). Only `MuguFishWorkflow.R` verified via a real end-to-end re-run; the other 4 files have the identical fix applied but unverified this session. |
| 2026-08-01 (Sonnet 5) | `data` parameter renamed to `occurrence_data` in `assign_habitat_biological()`, `flag_habitat_inconsistencies()`, `flag_institution_candidates()`, `review_institution_flags()`, `review_spatial_flags()` | TaxaHabitat | **Breaking rename** (same fix as TaxaTools's own `df` -> `input_df`; `data` shadows base R's `data()`). All real named (`data = ...`) call sites across the monorepo updated, including `TaxaExpect::build_priors()` (real package code -- required a `TaxaExpect` reinstall) and `TaxaWizard/inst/metadata/TaxaHabitat.json`'s two entries. Positional-only calls unaffected. See `TaxaHabitat/CLAUDE.md`'s top session note and `TaxaHabitat/inst/taxahabitat_review_response.md` for the full record, including a real `parse_habitat_response.R` CSV-corruption bug fixed at the root cause and a full row-by-row rebuild of `.iucn_habitat_lookup` against the verified IUCN Habitats Classification Scheme v3.1 source (most of Marine Neritic was scrambled/fabricated; several other sections had real content errors). `devtools::test()` 220/220 (up from 158), `devtools::check()` 0/0/0. |
| 2026-08-02 (Sonnet 5) | `review_spatial_flags()`'s `confirm_habitat` handler: reassigning habitat from Likely/Unlikely no longer resets `spatial_flag` to `"questionable"` | TaxaHabitat | **Behavioral, not signature.** At the user's request -- the point now keeps its existing flag instead of being forced through a second Questionable-view round trip. Reassigning FROM Questionable is unchanged (still promotes to Likely). Any existing caller relying on the old auto-reset-to-Questionable behavior for a Likely/Unlikely reassignment will see a different result; the roxygen `@section Click behaviour` documents the new behavior. `devtools::test()` 220/220 unchanged, `devtools::check()` 0/0/0. Live-verified via real Chrome browser automation, not just `check()`/`test()` -- see `TaxaHabitat/CLAUDE.md`'s top session note and `[[project_review_spatial_flags_habitat_reassign_gap]]`. |
| 2026-08-02, same day (Sonnet 5) | `review_spatial_flags()`'s `output$map` renderer: fixed `Error in leaflet::addCircleMarkers: unused argument (occurrence_data = hab_sub)` | TaxaHabitat | **Real regression bug fix, not a signature change.** The row above from 2026-08-01 swept up an unrelated call into `leaflet::addCircleMarkers()` -- that function's own `data` parameter belongs to the `leaflet` package, not TaxaHabitat, and should never have been touched by that rename. Broke marker rendering in EVERY view of the gadget (a hard R error, not scale-dependent) until fixed (`occurrence_data = hab_sub` -> `data = hab_sub`). The other 4 functions touched by the same 2026-08-01 rename were checked for the identical mistake; none found. Any `review_spatial_flags()` call made against the 2026-08-01 install would have failed immediately on gadget launch -- this is the likely true explanation for the "several Questionable points" symptom looking newly worse on that day's re-test (the map wasn't drawing anything at all). `devtools::test()` 220/220, `devtools::check()` 0/0/0, live-verified via Chrome (map renders, markers clickable, correct color). |
| 2026-08-03 (Sonnet 5) | `blast_sequences()`: subject-length filter now checks `length` (aligned region), not `slen` (whole GenBank record length); `megablast = FALSE` param added (explicit); `max_hits_per_taxon = NULL` param added (requires `resolve_taxonomy = TRUE` on remote results) | TaxaMatch | **Real bug fix + additive params.** The `slen`-vs-`length` bug silently discarded real congener matches deposited as long mitogenomes -- found live debugging a real GreatLakes 12S ASV. `megablast` matches the prior implicit default byte-for-byte (tested, ruled out as the actual bug, kept for explicit-over-implicit). `max_hits_per_taxon` needed a new internal `.attach_taxonomy()` + `.filter_blast_hits(stage=, taxon_group_col=)` restructuring since remote BLAST XML never populates real per-hit taxids. `devtools::test()` 523/523, `devtools::check()` 0/0/0. See `TaxaMatch/CLAUDE.md`'s top session note. |
| 2026-08-03 (Sonnet 5) | `screen_spatial_formula()`'s gradient-covariate detection now reads `data`'s `scale_params` attribute instead of hardcoding `lat_r_s`/`lon_r_s` | TaxaExpect | **Behavioral, not signature.** Any covariate beyond the original two (e.g. a new `depth_m_s`) is now properly screened (shown in the VarCorr table, testable for removal via AIC) instead of being silently fit but invisible to this function's own model-selection machinery. Falls back to the old hardcoded pair when `scale_params` is absent (hand-built data/older callers) -- fully backward compatible, confirmed via a dedicated new test. `devtools::test()` 541/541 (up from 538), `devtools::check()` 0/0/0. See `TaxaExpect/CLAUDE.md`'s top session note and `[[project_depth_covariate_propagation]]`. |
| 2026-08-04 (Sonnet 5) | `compute_adaptive_sampling_groups(min_n=)` lost its `100` default, now required | TaxaExpect | **Breaking, but zero real callers** (confirmed via a grep across the whole monorepo and the wider `~/My Drive/Rscripts` tree -- this function has never been wired into any production workflow). No safe universal per-site record-count threshold exists across study systems, matching this ecosystem's established "no safe default" convention (`join_priors(backbone_id=)`, `score_consensus(rank_thresholds=)`). Part of TaxaExpect's first code-review response pass; see `TaxaExpect/CLAUDE.md`'s top session note and `TaxaExpect/inst/taxaexpect_review_response.md` for the full record (also: new `grid_size` attribute propagated through `create_sites_from_grid()`/`prepare_model_dataframe()`/`train_biodiversity_model()`/`generate_full_priors()`/`plot_theta_map_interactive()`; new `compute_moran_basis(coords=)` param). `devtools::test()` 555/555 (up from 538), `devtools::check()` 0/0/0. |
| 2026-08-07 (Sonnet 5) | `flag_contaminant(df=)`/`flag_handler(df=)`/`review_assignments(df=)`/`review_spatial_context(df=)` -> `input_df=` | TaxaFlag | **Breaking rename**, first TaxaFlag code review pass (`inst/taxaflag_review.Rmd`). `df` shadows `stats::df()`; matches the identical fix already made in `TaxaTools`/`TaxaHabitat`. Propagated to every real named-argument call site found via a full `~/My Drive/Rscripts` grep: this package's own tests/inst/vignette, `TaxaWizard`'s `consensus_to_flagged.R`/`consensus_to_reviewed.R` snippets + `metadata/TaxaFlag.json`, `TaxaID/inst/TaxaID_Workflow_Template_TEST.R`, and all 6 real external eDNA production workflow scripts (PtConception x4, SepulvedaMugu x2 -- outside this monorepo, not under git, backed up first as `*.bak_pre_input_df_rename`). Positional calls unaffected. Also fixed the same session: a real `flag_handler()` row-order bug (its internal `merge()` used `sort=TRUE`, silently re-sorting output by `group_col` whenever groups appeared out of alphabetical order in the input -- fixed with the same `.row_id`-then-resort pattern `review_assignments()` already used); a broken `\link{model_review_classification}` Rd cross-reference in `build_review_covariates.R` that had been the real cause of this package's long-standing, never-resolved `devtools::check()` warning; and a new `test-build_review_covariates.R` (that function's only exported-with-zero-tests gap). `devtools::test()` 415/415 (up from 382), `devtools::check()` 0 errors/0 warnings/0 notes (was 1 warning). See `TaxaFlag/CLAUDE.md`'s top session note and `inst/taxaflag_review.Rmd` for the full record. |
| 2026-08-08 (Sonnet 5) | `fetch_gbif_occurrences()`/`download_gbif_occurrences()`/`get_gbif_occurrences()`/`check_geographic_outliers()`/`fetch_occurrences_by_taxon()`: `year_range` default `"2000,2024"` -> `.gbif_default_year_range()` (`"2000"` through the current year, computed at call time) | TaxaFetch | **Behavioral, not signature**, first TaxaFetch human code review pass (`inst/taxafetch_review.Rmd`, reviewer Micah Wright). The old fixed-literal default was identical across all five functions and had already gone stale by the time of this review -- any caller relying on the default was silently excluding all 2025+ GBIF occurrence data with no warning. Any caller passing its own explicit `year_range` is unaffected; a caller relying on the default now gets more complete data, never less. Also fixed the same session, adjacent to this: `fetch_gbif_occurrences(year_range = NULL)` (a real, reachable path via `TaxaExpect::build_priors()`'s own `year_range = NULL` default) crashed inside `.gbif_checkpoint_path()` when `cache_dir` was enabled -- `gsub()` on `NULL` silently produced `character(0)`, propagating into a length-zero checkpoint path and an `"argument is of length zero"` error. See `TaxaFetch/CLAUDE.md`'s top session note and `inst/taxafetch_review_response.md` for the full record, including several real data-parsing bugs fixed the same session (PASTA coordinate/XML-field bugs, a newline-vs-PCRE-dot footgun recurrence, an NA-vs-NULL defaulting gap in the PDF pipeline). |
| 2026-08-08 (Sonnet 5) | `filter_gbif_quality()`'s `basisOfRecord` filter is now case/whitespace-insensitive | TaxaFetch | **Behavioral, not signature.** Previously exact `data$basisOfRecord %in% basis_keep`; now `toupper(trimws(...))` on both sides, matching the `occurrenceStatus` filter's own existing normalization (an inconsistency the review flagged). A no-op against real GBIF data (a strict, consistently upper-case Darwin Core controlled vocabulary); only changes outcomes for a non-GBIF-native `basisOfRecord` value differing from `basis_keep` only in case/whitespace, previously (incorrectly) dropped. |
| 2026-08-08 (Sonnet 5) | `read_crabs_output(file=)` -> `crabs_file=` | TaxaLikely | **Breaking rename**, first TaxaLikely human code review pass (`inst/taxalikely_review.Rmd`, reviewer Micah Wright). `file` shadows `base::file()`, matching this ecosystem's established `df`/`file`/`line`-shadowing fix convention. Propagated to the one real cross-package named-argument call site found via a full monorepo grep: `TaxaWizard/inst/graph/snippets/local_fasta_to_refs.R` (`file = {{input_var}}` -> `crabs_file = {{input_var}}`) and its `TaxaWizard/inst/metadata/TaxaLikely.json` entry; this package's own `README.md` example. All in-package test calls already used positional (unnamed) calling and needed no change. See `TaxaLikely/CLAUDE.md`'s top session note and `inst/taxalikely_review_response.md` for the full record. |
| 2026-08-08 (Sonnet 5) | `flag_reference_errors(singleton_match_threshold = 0.98)` added; `train_likelihood_model(singleton_match_threshold = 0.98)` added | TaxaLikely | **Additive, fully backward compatible** -- same default and comparison direction (`>`) as the prior hardcoded `0.98` literal, so no existing caller's behavior changes. The literal previously had an inline comment suggesting a caller "consider raising to 99% for ITS" with no actual way to do so; now a real parameter, threaded through `train_likelihood_model()` (which calls `flag_reference_errors()` internally) too. |
| 2026-08-08 (Sonnet 5) | `audit_barcode_coverage_gbif()` removed entirely | TaxaLikely | **Breaking, but zero real callers** -- confirmed via a full monorepo grep and `NAMESPACE`: never exported (`@noRd`), zero test coverage, zero real callers anywhere, a genuinely abandoned "DRAFT" function (matches this ecosystem's established zero-real-callers removal precedent, e.g. `fetch_reference_sequences()`/`audit_barcode_coverage_ncbi()`/`expand_consensus_candidates()`). Its GBIF-only species-enumeration code path (`.get_species_gbif()`, `use_gbif`/`version_tag` plumbing in the internal scaffold) removed with it; `rgbif` dropped from `DESCRIPTION` `Suggests` (now genuinely unused). Internal `.audit_barcode_coverage_new_()` renamed `.audit_barcode_coverage_impl()` (not user-facing). |
| 2026-08-11 (Sonnet 5) | `workflow_chat()`/`workflow_gadget()` removed entirely | TaxaWizard | **Breaking, but zero real callers, package never released** -- first human-authored TaxaWizard code review (Micah Wright) explicitly suggested removing both; confirmed via monorepo grep. Use `workflow_create(mode = "console"/"viewer")` directly. Also this session: real fix for a namespaced-call (`pkg::fn()`) crash bug in `R/shiny.R`'s generic-script parser (4 instances, `as.character(expr[[1L]])` silently returning length>1 for any `::`-call), `.extract_libraries()` now also matches `require()`, an empty-input confirm-prompt inconsistency fixed, and a real dead-feature bug (saved `workflow_context.json` defaults were loaded/offered but never reached the live LLM prompt) -- see `TaxaWizard/CLAUDE.md`'s top session note and `TaxaWizard/inst/taxawizard_review_response.md` for the full record. |
| 2026-08-20 (Sonnet 5) | `generate_domestic_food_priors()` output rows now carry `taxon_name_rank = "species"` | TaxaExpect | **Real bug fix, behavioral not signature.** Found live-testing the GreatLakes2023 workflow (a food-fish species added by the user), confirmed with real numbers before fixing: this column was previously unset on every emitted row, defaulting to `NA` via `bind_rows()` -- since `TaxaAssign::join_priors()`'s primary composite-key join requires an exact `(taxon_name, taxon_name_rank, grid_id, main_habitat)` match, every domestic-food prior row has been silently un-joinable since the function shipped (2026-07-23), for any real observation (which always carries a real, non-`NA` `taxon_name_rank`). Confirmed on real data: a real `Gadus morhua` domestic-food row (`alpha=5, beta=8775`, theta ~= 0.00057) never matched; the affected observation's applied prior came out theta ~= 0.000167 instead (~3.4x lower), the ordinary group-dark-diversity fallback. `main_habitat` is deliberately left `NA` (not stamped with a real value) -- see the paired `join_priors()` fix below for why. `devtools::test()` 586/586 (up from 580), `devtools::check()` 0/0/0. |
| 2026-08-20 (Sonnet 5) | `join_priors()` gains a habitat-agnostic named-species prior fallback tier | TaxaAssign | **Behavioral, not signature -- the other half of the fix above.** A `taxaexpect_priors` row with a real `taxon_name` but `main_habitat = NA` (by design -- e.g. a food/domestic species has no single correct habitat value, since its plausibility is governed by human food supply, not habitat suitability) previously could never match the primary composite-key join at all. New fallback tier re-matches any row whose primary join failed on `(taxon_name, taxon_name_rank, grid_id)` alone against `main_habitat = NA` rows -- ranked below a real per-habitat match, above the dark-diversity/global-floor fallback. When more than one habitat-agnostic row exists for the same key (e.g. two independent evidence sources naming the same species), the strongest (highest theta_mean) is used rather than an ambiguous many-to-many join. Emits a `cli::cli_inform()` count of rows rescued. Any existing caller whose `taxaexpect_priors` already contains `main_habitat = NA` named rows (in practice, only `generate_domestic_food_priors()` output) now gets a materially different, correct result instead of a silent no-op. `devtools::test()` 664/664 (up from 655, 1 pre-existing skip unchanged), `devtools::check()` 0/0/0. |
| 2026-08-26 (Fable 5) | `join_priors()`'s modelled-species floor promotion scoped by cause | TaxaAssign | **Behavioral, not signature -- a real results change for every workflow using evidence/domestic priors.** The Session-117 blanket promotion (`!is.na(alpha)` + below-singleton-mean -> promote to singleton parity) now (a) NEVER promotes evidence-derived rows (`undetected_type == "evidence_blend"`, `model_tier` `tier_undetected_evidence`/`tier_domestic_food` -- their sub-singleton theta is the graded design, and promotion silently erased every weight/distance/age gradation, the central finding of the 2026-08-26 GreatLakes upranking review); (b) promotes modelled rows only on a genuine habitat mismatch (`observed_in_habitat` explicitly `FALSE`, the rule's actual motivating case), never for a genuinely low in-habitat estimate; (c) retains the old blanket behavior when `taxaexpect_priors` has no `observed_in_habitat` column (older callers unaffected). Habitat-agnostic fallback rows now also carry `model_tier`/`undetected_type` provenance; coarse-rank expansion's `override_cols` gains `model_tier`/`observed_in_habitat`. Live-verified on real GreatLakes2023 data: promotion 3,326 -> 112 rows, species-resolved observations 33 -> 103. Any cached consensus/posterior checkpoint computed pre-fix is stale. `devtools::test()` 670/0, `devtools::check()` 0/0/0. See `ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md` (D1). |
| 2026-08-26 (Fable 5) | `apply_undetected_evidence()` no-singleton ceiling: floor-collapse no-op replaced by an anchor ladder | TaxaExpect | **Behavioral, not signature.** With zero `singleton_mirror` rows the blend ceiling previously collapsed onto the floor (every elevation a weight-independent no-op, warning only). Now descends: singleton mean -> minimum modelled theta (site-scoped preferred; evidence/domestic named rows excluded as anchors) -> `1/(median n_obs + 1)` -> only then the old warning fallback. Datasets WITH singletons are unchanged. `devtools::test()` 689/0, `devtools::check()` 0/0/0. See the reentry doc (D2). |
| 2026-08-26, continued (Fable 5) | `apply_undetected_evidence()`: `evidence$n_eff` retired -> optional `p_conc` (default 1); Beta concentration now moment-matched; new `prior_mix_w`/`prior_mix_theta_present`/`prior_mix_theta_absent`/`prior_mix_p_conc` output columns | TaxaExpect | **Breaking for evidence-table callers.** An `evidence` frame carrying `n_eff` without `p_conc` errors with migration guidance. `generate_invasive_watch_evidence(n_eff=)` -> `p_conc = 1` (signature change); `generate_regional_proximity_evidence()` loses `n_eff_base` (p_conc = exp(-age/age_half)). All 6 real production workflows' call sites updated same session (`INVASIVE_WATCH_N_EFF` -> `INVASIVE_WATCH_P_CONC`). Blend means unchanged byte-for-byte (verified on all 121 real GreatLakes rows); only the Beta concentration and new mixture columns differ. `devtools::test()` 694/0, `check()` 0/0/0. See the reentry doc (D3/D8). |
| 2026-08-26, continued (Fable 5) | `compute_posterior()` gains presence-draw sampling for `prior_mix_*` rows; `join_priors()` passes the columns through expansion; `update_prior_from_consensus()` clears the mixture on confirmation-raised rows | TaxaAssign | **Additive/behavioral.** Mixture rows draw `z ~ Bernoulli(prior_mix_w)` in simulation instead of being pinned at the mean by the `alpha <= 1` J-guard; `posterior_mean` integrates over presence states, `confidence_score` = fraction of presence states won. Point path unchanged. Non-mixture rows completely unaffected (regression-tested). `devtools::test()` 682/0, `check()` 0/0/0. Operative consensus column unchanged (`posterior_point_est`) pending the D8 verdict -- the three-way experiment found the choice second-order vs w calibration. |
| 2026-08-26, later still (Fable 5) | `generate_regional_proximity_evidence(w_scale = 1)` added | TaxaExpect | **Additive, backward compatible** (default 1 = prior behavior). `weight = w_scale * exp(-distance_km/d_half)`; `w_scale` = P(locally present) for a species with a record just outside the bbox and none inside. The default is documented as almost certainly too high for real studies; calibrate against a local checklist (GreatLakes2023: 0/110 zero-bbox candidates on the 53-species site checklist at any distance -> adopted 0.05, validated against held-out Lamar: species co-detections 74 -> 224, no_match 1/1081). GreatLakes workflow sets `w_scale = 0.05`; all 6 workflows' `INVASIVE_WATCH_WEIGHT` updated 0.6 -> 0.05 (0.6 violated the never-veto-an-observed-native ordering bound). `devtools::test()` 697/0, `check()` 0/0/0. |
| 2026-08-28 (Fable 5) | `update_prior_from_consensus()`: soft confirmation replaces the hard donor gate; `min_confirmation_confidence` REMOVED -> new `confirmation_discount = 0.25` | TaxaAssign | **Breaking signature + behavioral change** (D7). Support aggregates softly from every observation's posteriors (leave-one-out, power-prior-discounted, saturating; mixture rows update `prior_mix_w`); no thresholds anywhere -- continuity regression-tested. Propagated through `run_bayesian_pipeline()`/`run_llm_pipeline()`/`consensus_refinement`/`generate_report()` methods text/inst workflows/vignette. Held-out Lamar: soft beats hard on every axis (co-det 236->238, ours_only 120->97, uniq species 17->23, in-Lamar 12->18, precision 0.66->0.71). Citations verified live (Ibrahim & Chen 2000; Celeux & Govaert 1992; Dorazio & Erickson 2018). |
| 2026-08-28 (Fable 5) | `posterior_consensus(posterior_col)` default `"posterior_mean"` -> `"posterior_point_est"` | TaxaAssign | **Behavioral default change** (D8 drift fix): aligns the low-level default with `run_bayesian_pipeline()` and every production workflow. Rank by the MC mean by passing `"posterior_mean"` explicitly (with mixture priors that column integrates presence states). Test fixtures/examples updated to carry both columns. |
| 2026-08-28 (Fable 5) | `check_inat_range()` output gains `name_match`; `adjust_inat_range_priors(require_name_match = TRUE)` added | TaxaFetch, TaxaAssign | **Behavioral**: an in-range verdict resting on a fuzzy misresolution to a DIFFERENT species (real case: Gasterosteus gymnurus -> aculeatus) can no longer drive a prior elevation by default. `name_match` is derived at assembly time (cached rows get it too); pre-2026-08-28 `inat_range` tables elevate nothing until re-checked (guidance message). `adjust_inat_range_priors()` is marked superseded for the mixture pathway by `generate_inat_range_evidence()`. |
| 2026-08-28 (Fable 5) | `flag_watch_candidates()` added | TaxaFlag | New function (D4): likelihood-side watch-list surveillance -- flags observations where a watch species' raw score ties/beats the winner's best match; prior-free, purely informational, never edits consensus columns. Wired into the GreatLakes workflow (8i.5). |
| 2026-08-30/31 (Fable 5) | `estimate_kernel_priors()` + `calibrate_kernel_bandwidth()` added | TaxaExpect | New (additive), branch kernel-priors. Site-centered distance-kernel prior estimation (geo x covariate product kernel, Kish n_eff, concentration n_eff+m, weighted Good-Turing singletons) + leave-one-block-out bandwidth calibration. Output schema: `prior_branch` + `effective_records` + `observed_in_habitat=TRUE` (NO `model_tier` -- retirement in progress). Validated on GreatLakes (Lamar precision 0.748 -> 0.868). |
| 2026-08-31 (Fable 5) | `generate_undetected_diversity()`/`apply_undetected_evidence()`/`generate_domestic_food_priors()` accept `taxaexpect_kernel_priors` objects | TaxaExpect | Additive adapters; frozen rules on kernel ingredients. Undetected floor uses the RAW stratum record count while mirrors carry site-scale effective shares (two scales -- mapping both to n_eff inverts the floor/ceiling interval). Emitted undetected rows now also carry `prior_branch = "resident_undetected"`; domestic rows `"transport"`. |
| 2026-08-31 (Fable 5) | `join_priors()` promotion gated on `prior_branch`; `report_priors()` falls back to `prior_branch` | TaxaAssign, TaxaExpect | Behavioral, additive-safe: when `prior_branch` is present only `"resident_observed"` rows are promotion-eligible (subsumes the model_tier value checks once that column retires); new schema columns carried through coarse-rank expansion + habitat-agnostic fallback. Legacy tables without the column are unaffected. |
| 2026-08-31 (Fable 5) | `generate_domestic_food_priors()` kingdom cross-check normalizes backbone vocabularies | TaxaExpect | Behavioral bug fix (commit 2aa685a): NCBI "Metazoa"/"Viridiplantae" vs iNat "Animalia"/"Plantae" was treated as a cross-kingdom homonym, silently discarding every NCBI-taxonomy candidate's local-evidence boost since the check shipped. |
| 2026-08-28 (Fable 5) | `generate_inat_range_evidence()` + `fit_regional_presence_curve()` added; `apply_undetected_evidence()` prints the veto bound | TaxaExpect | Additive (D6/D5/D4): iNat as the third evidence generator through the shared applier (w = 0.8, name-gated); the generic distance-to-presence fitter (log-link binomial to `w_scale*exp(-d/d_half)`, zero-positive Jeffreys-bounds path first-class); every `apply_undetected_evidence()` call now prints the dataset-specific weight bound above which an unobserved species can veto a singleton-level native. |
| 2026-08-31 (Fable 5) | GLMM prior-fitting path deprecated, gently (B7): `build_priors()`/`optimize_grid_size()`/`prepare_model_dataframe()`/`add_pca_covariates()`/`compute_moran_basis()`/`screen_spatial_formula()`/`train_biodiversity_model()`/`train_biodiversity_model_by_group()`/`generate_full_priors()` | TaxaExpect | **Deprecation notice only, zero behavior change.** Each emits a once-per-session `rlang::inform()` (shared `.frequency_id` -- a full GLMM pipeline run prints one line, not nine) + a roxygen `@section Deprecated` pointing at `estimate_kernel_priors()`/`calibrate_kernel_bandwidth()`. Chosen over full archival because PtCon/Mugu workflows still run the GLMM path (PtCon kernel migration deferred while NCBI-throttled); archival (DECIPHER precedent) lands with that migration. `model_tier` doc-deprecated on all four emitters (kernel schema: `prior_branch` + `effective_records`). `devtools::test()` 773/0, `devtools::check()` 0/0/1 (pre-existing environmental timestamp note). NOT yet reinstalled -- see the session-end apply block. |
| 2026-08-31 (Fable 5) | `posterior_consensus()`: `winner_has_occurrence_record` + plausible-competitor mask read `prior_branch` when present | TaxaAssign | **Behavioral, not signature -- the posthoc Axis-1 recalibration for kernel tables.** Legacy reading (`!is.na(model_tier)`) was fully INVERTED on kernel output: kernel resident rows carry no `model_tier` (86 locally-evidenced species read FALSE) while evidence-blend/domestic legacy rows carry one (zero-local-record species read TRUE) -- real B8 run: 873/885 "unprecedented". New reading: `winner_has_occurrence_record = (prior_branch == "resident_observed")`; competitor plausibility = any non-`NA` `prior_branch` (named row on any branch); GLMM tables without `prior_branch` keep the exact legacy logic (regression-tested). Transport winners read FALSE by design -- `domestic_prior_caveat` carries their interpretation. Validated on the real GL fastpath: plausibility 2/10/873 -> 860/12/13 expected/unexpected/unprecedented (GLMM baseline 864/15/6); the 13 unprecedented are exactly the evidence-elevated zero-local-record winners (grass carp both name variants, Barbatula hispanica, Phoxinus phoxinus, Lythrurus ardens, Rhinichthys atratulus); consensus_taxon/consensus_rank byte-identical to B8. `devtools::test()` 700/0 (+5 new regression tests), `devtools::check()` 0/0/0, reinstalled. |
| 2026-08-31 (Fable 5) | `estimate_kernel_priors(lambda_latitude=)` + `calibrate_kernel_bandwidth(lambda_latitude_grid=)` added | TaxaExpect | Additive, backward compatible (NULL defaults = exact prior behavior, regression-tested to 1e-12). Opt-in climate-similarity product-kernel factor `exp(-111*||lat|-|site_lat||/lambda_latitude)` on the ABSOLUTE latitude difference (hemisphere-symmetric: a 42S temperate source is climatically ~0 deg from a 42N site). The calibration sweep always adds `Inf` (factor off) so the no-factor case competes on equal footing. Real-data verdict at GL: LOBO picks `lambda_latitude = Inf` (best 3.2138 vs finite-lambda runner-up 3.2155) -- within a single lake's ~2-degree span the factor earns nothing; its intended scale is the continental presence-curve work (unobserved-taxa redesign). 5 new tests; `devtools::test()` 782/0, `devtools::check()` 0/0/0, reinstalled. |
| 2026-08-31, later (Fable 5) | Curve pricing adopted on the GL kernel path: `apply_undetected_evidence(pricing="curve")`, `estimate_kernel_priors()` emits `f1`/`f2`/`chao_missing`/`theta_present`; NEW `generate_presence_curve_evidence()` + `generate_user_specified_evidence()` | TaxaExpect | Additive (blend mode regression-tested byte-identical; curve mode gates its own anchors so no `global_floor` row is required there). Design settled with the user in-session: theta = w*theta_present (mass/Chao = 2.04e-4 at GL; zero-record evidence caps share-if-present regardless of species identity), theta_absent = 0; one curve w = w_scale*exp(-min(d,1000)/(k*150)) prices named regionals (k=1), watch-listed invaders (k=2, log-space halfway lift at their OWN nearest-record distance), non-regional clamp (6.4e-5, human-vector tail; Jeffreys 0-of-221 guard); iNat 0.8 unchanged; budget AUDITED not enforced (sum(w) vs Chao in count units -- GL 6.67 vs 14.4). reserve/N floor REJECTED by pressure test (N not enumerable). GL VALIDATION (Lamar): co-detections 564->594, precision 0.853 (gate 0.748 PASS), 33 unique species (28/61), STRICTLY ADDITIVE +4/-0 species (E. americanus recovered). ADOPTED (user verdict): fastpath + full GL workflow both run curve pricing under USE_KERNEL_PRIORS (workflow 7a.7b-e restructured, backup .bak_pre_curve_pricing; legacy blend in the else). `devtools::test()` 818/0, `check()` 0/0/0, reinstalled. NEXT: PtCon fastpath analog for the near-invariance control (user verdict: next work item). |
| 2026-09-01 (Sonnet 5) | `evaluate_reference_accessions()` long-sequence/throttle robustness: new params `max_query_len`, `max_batch_bp`, `prioritize_uncached` (default `TRUE`), `retry_insufficient` (default `TRUE`); new `hierarchy_flag` value `"not_evaluated_oversized"`; `blast_sequences()`/`.blast_remote()` gain `max_batch_bp` | TaxaMatch | **Additive, backward compatible** except `prioritize_uncached`'s new default ordering (deliberately safe -- never changes which accessions get evaluated, only in what order). Implements `ecosystem_docs/REENTRY_PROMPT_eval_ref_accessions_long_sequence_robustness.md`: (1) feature-table-guided extraction fallback (new `.extract_feature_table_fallback()`, reuses `check_marker_mismatch()`'s fetch/matching internals) when primer trimming can't find a marker's primer sites on an over-length query; (2) a hard `max_query_len` submission cap -- a query still over-length after both rescue strategies is never BLASTed, gets the new `"not_evaluated_oversized"` verdict (TTL-retryable like `"insufficient_independent_evidence"`; downstream `remove_incongruent_references()`/`flag_incongruent_references()` never treat it as a flag); (3) length-aware BLAST batching (`max_batch_bp`, default `100000L` -- a batch closes on a cumulative-bp cap too, and one very long query rides alone rather than dooming a whole batch); (4) `prioritize_uncached`/`retry_insufficient` reorder/skip expired-retry evaluation so a budget-limited or purely-cache-served call doesn't grind against the NCBI CPU-budget throttle. `.EVAL_REF_ACC_VERSION` NOT bumped -- all 4 new params deliberately excluded from `params_key` (call mechanics/policy, not verdict-affecting). `devtools::test()` 950/0 (up from 886), `check()` 0/0/0, NOT yet reinstalled (live NCBI validation reserved for the user's next window -- see the reentry doc's own updated Status/re-run-instructions section). |
| 2026-09-03 (Opus 5) | `estimate_kernel_priors(sampling_group_col = NULL)` added; new `$budget` table | TaxaExpect | **Additive, backward compatible** -- `NULL` is the previous behaviour EXACTLY (verified against the real 529,091-record Mugu run: max \|delta\| = 0 across all 214 taxa for `theta_mean`/`alpha`/`beta`/`effective_records`, and every scalar reproduces). Restores the detection-process stratification the GLMM path enforced via `prepare_model_dataframe(sampling_group_col=)` (Session 149) and the kernel rewrite dropped. Composition AND the Good-Turing budget are shared-denominator quantities: pooling taxa detected by different processes dilutes a detectable taxon's share with records the assay could never amplify, and lets barely-sampled groups contribute singletons that inflate `f1` -- hence `chao_missing`, quadratically -- while barely moving `missing_mass`, deflating `theta_present` (measured 11x on a stark fixture; the user's own estimate was ~3x). A NO-OP on a taxonomically homogeneous pool by construction, which is why it cannot disturb the GreatLakes (376/376 Actinopteri) or Mugu (fish-only singletons) validations. When supplied, each group gets its own simplex and its own `$budget` row; with >1 group the pooled `f1`/`f2`/`chao_missing`/`theta_present` scalars are `NA` BY DESIGN (no single budget exists across detection processes) and `apply_undetected_evidence(pricing = "curve")` refuses with an actionable message rather than mispricing every group but one. Build the column with `compute_adaptive_sampling_groups()`. Also fixed: that function read `model_obj$f1` as `TRUE && NA`, which `if` rejects (the documented `is.logical(NA)` footgun). Full analysis + open decisions: `ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_scope.md`. `devtools::test()` 923/0, `check()` 0/0/0. |
| 2026-09-02 (Fable 5) | `resolve_barcode_marker()` added; every NCBI query builder now resolves `barcode_term` through it | TaxaTools (new fn); TaxaLikely, TaxaAssign (consumers) | **Behavioral bug fix, additive signature.** A registered primer-variant term (`"COI-Folmer"`, `"16S-Palumbi"`, `"rbcLa"`, `"cytb-Kocher"`, `"matK-Kim"`, `"trnL-Taberlet"`) is correct for primer/length resolution but is not indexed by NCBI, so a query built from it matched NOTHING -- silently, since an empty search result is legitimate. Live-confirmed: Leptocottus COI 0 hits (broken) vs 23 (fixed); Paralabrax 0 vs 46; Girella 0 vs 15. `fetch_ncbi_reference_sequences()` at least failed loudly a few lines downstream; the two SILENT consumers were worse -- `audit_barcode_coverage()` and `TaxaAssign::suggest_unreferenced_species()` reported every species as having no barcode, inflating `unreferenced` and feeding `apply_coverage_constraints()`/the unobserved-taxa machinery a fiction. MiFish terms deliberately NOT remapped (records really are annotated with that primer name); unrecognised terms pass through unchanged, so a custom term still searches as itself. Lengths/primers still resolve from the caller's own tighter term. Any cached `*_coverage*.rds` computed with a variant term is WRONG and must be deleted. `devtools::test()` TaxaTools 865/0, TaxaLikely 1024/0, TaxaAssign 707/0; `check()` 0/0/0 all. |
| 2026-09-02 (Fable 5) | `fetch_ncbi_reference_sequences()` empty returns now carry the successful return's columns | TaxaLikely | **Behavioral, not signature.** All three early returns (zero hits, nothing passed filters, empty FASTA) returned a bare `composite_id`/`sequence` frame, so a caller's ordinary next step (`clean_taxon_names(reference_df$species)`) failed with "`name_vec` must be a character vector" -- burying the function's own correct explanation of why the result was empty. New `.empty_reference_df()` carries the `rank_system` columns (and lat/lon/country when `include_location = TRUE`). |
| 2026-09-02 (Fable 5) | `plot_theta_surface(mask =)` accepts a WKT POLYGON string | TaxaExpect | **Additive, backward compatible.** The surface lattice is a RECTANGLE over the data extent, so for a coast-hugging search polygon it paints well inland -- correct by construction, surprising in practice. `mask` already took sf/matrix geometry, but every workflow holds its polygon as the WKT string `TaxaTools::define_search_polygon()` returns and passes to GBIF, so it could not be used without hand-conversion. Now `mask = bbox` clips the map to the exact geometry the records were fetched under. Uses `sf` when installed (handles holes/multipart); the dependency-free fallback refuses a multi-ring polygon rather than silently filling a hole. Wired into all 4 kernel-path workflows. |
| 2026-09-01 (Sonnet 5, branch theta-surface) | NEW `plot_theta_surface()` -- KDE prior-field map for the kernel-priors path (`ecosystem_docs/SPEC_plot_theta_surface.md`) | TaxaExpect | **Additive, capability restoration.** Evaluates `estimate_kernel_priors()`'s SAME estimator on an `n_grid` x `n_grid` lattice via binned FFT convolution (`stats::fft`, base R -- no new dependency) instead of at one site, so the map IS the prior field. Replaces `plot_theta_map_interactive()` for kernel priors (that function parses `Grid_<lat>_<lon>` ids into centroids and has nothing to draw for a single opaque kernel `site_id` -- unmodified, still correct for the deprecated-but-live GLMM/grid path). Site-identity invariant verified to ~1e-2 absolute (grid-quantization tolerance, tighter at finer `n_grid`; exact in the top-hat/large-lambda limit): evaluated at the site's own coordinates (the lattice is anchored so the site lands exactly on a node), the surface reproduces `estimate_kernel_priors()`'s `theta_mean` and `n_eff`, both with and without a `lambda_latitude` factor. FFT convolution validated against brute-force direct summation on a small fixture (diff ~1e-9, float noise only). Measured timing (this machine, base R `fft`, not the design work's separate 0.28s/512x512x1.25M-record figure -- see the spec's Status section for the gap): ~2.1s for a 512x512 surface from 1.25M records/1 taxon (~0.9s per additional taxon once the kernel is FFT'd once and reused via `.theta_surface_fft_convolve_batch()`). `covariate_at = NULL` (default) on a fit built with a covariate OMITS that factor and messages so, never implying a depth-conditioned field it doesn't show. `grDevices`/`graphics` added to Imports (new static-plot rendering path; `leaflet` interactive path reuses the existing Suggests, no new dependency). `devtools::test()` 866/0 (+37 new assertions), `check()` 0/0/0. Five production workflows' `if (!USE_KERNEL_PRIORS) plot_theta_map_interactive(...)` gates are candidates to switch to this function on their kernel branch -- listed in `TaxaExpect/CLAUDE.md`'s top note and the spec's Status section; NOT wired here (those workflows live outside this repo). |
| 2026-09-03 (Fable 5.1, branch local-corroboration) | `evaluate_reference_accessions()` cache version bumped to `"v5_amplicon_query"`; new `query_span = c("amplicon", "primer_inclusive")` (in `params_key`); new `local_corroboration`/`skip_locally_corroborated`; new `hierarchy_flag` value `"locally_corroborated"`; NEW `corroborate_references_locally()`, `match_driving_accessions()`, `migrate_reference_cache()`; `score_reference_labels()`/`refine_reference_verdicts()` gain `local_corroboration` and four always-present columns (`action_reason`, `corroboration_source`, `local_best_independent_pident`, `local_n_independent_conspecific`); `review_flagged_accessions()` gains `local_min_overlap` | TaxaMatch | **BREAKING FOR EXISTING CACHES, additive otherwise.** The screen now submits the primer-STRIPPED amplicon (169 bp for MiFish-U) instead of the primer-inclusive span (217 bp): a 169 bp amplicon-only conspecific deposit is out-scored by every full-length relative at >= 93% against the 217 bp query and never reaches NCBI's 100-hit list (live-confirmed on `KM057996`/`OQ846041`, `diagnostics/blast_coverage_blindspot_probe.R`), and `min_query_coverage = 80` would drop it anyway (169/217). Because that changes what BLAST can return, `params_key` changed and EVERY row cached before this is invalid. **Run `migrate_reference_cache(cache_dir)` on each real cache dir before the next screen** (PtCon `ptcon_ref_eval_cache`, the three GreatLakes `*_ref_eval_cache`): it backs the file up (`.bak_pre_v5_amplicon_query`), carries `"congruent"` rows forward (stripping primers only ADDS hits; it cannot withdraw a match already observed) and leaves incongruent/insufficient/oversized rows (PtCon 76, GreatLakes ~123) to re-BLAST under the new query. New params and the new flag value are additive: `"locally_corroborated"` is never a flag downstream (`remove_incongruent_references()`, `flag_incongruent_references()`, `verify_flagged_references()`, `refine_reference_verdicts()` all handled). A purely cache-served call now also carries the post-hoc `label_confidence`/`reference_action`/`listed_taxon_is_species` columns (the old early return omitted them). Implements `ecosystem_docs/REENTRY_PROMPT_local_corroboration_and_primer_stripped_screen.md`; see `TaxaMatch/CLAUDE.md`'s top note. |
| 2026-09-03 (Opus 5) | `kernel_budget_sensitivity()` added; `estimate_kernel_priors()` records column names in `$params` and prints `f1`/`f2`/`chao_missing`/`theta_present` in the ungrouped case; `apply_undetected_evidence(pricing="curve")` names the `f1`/`f2` behind its price | TaxaExpect | **Additive, backward compatible** -- no signature changes to existing functions, no computed value changes anywhere. Open decision #4 of `ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_scope.md`: `chao_missing = f1^2/(2 f2)` is hypersensitive to `f2` in single digits and nothing upstream constrains it (the bandwidth is calibrated on COMPOSITION prediction, which has no stake in singleton/doubleton counts), so a budget figure quoted without its `f2` and its radius sensitivity cannot be assessed by the reader. `kernel_budget_sensitivity(fit, occurrence_data, ...)` re-runs the estimator across counting radii (and optionally bandwidths) and returns per-group budget rows plus a `$summary` of the f1/f2/Chao ranges and the `theta_present` spread; `$reproduces_fit` is FALSE when the supplied data is not what the fit was computed from. Real 18S per-group radius sensitivity: 1.9x to 137x. Also corrected an overstated code comment -- `mass/Chao` is NOT below the singleton mean "by construction": it exceeds it whenever `f1 < 2*f2` (real case: PtCon 18S zooplankton, f1=3, f2=7, Chao=0.64). The veto bound itself was already computed, not assumed, so behaviour was correct. Also fixed, pre-existing and unrelated: `vignettes/building-priors.Rmd` was being tangled and sourced by R CMD check (an `opts_chunk$set(purl = FALSE)` in a setup chunk is not honoured by `knitr::purl()`), the sole cause of a standing check ERROR. `devtools::test()` 956/0, `devtools::check()` 0/0/0. |
| 2026-09-03 (Opus 5) | `plot_theta_surface()` renders its habitat + covariate conditions on the plot; a `sampling_group_col` fit is now REFUSED | TaxaExpect | **One breaking (zero real callers) change plus an additive display change.** (1) Breaking: passing a `kernel_fit` built with `estimate_kernel_priors(sampling_group_col=)` now errors. That argument computes `n_eff` and the regional back-off *within* each group; the surface has no such split and would have drawn the pooled ungrouped field while claiming the fit's identity — a silent failure of the site-identity invariant. Fit each group on its own record subset and map that fit (the shape `PtConceptionWorkflow_18S_2_single_site.R:823` already uses). No workflow passes it, so nothing breaks today. (2) Additive: the habitat stratum and covariate state are now drawn on the map itself (static `mtext` subtitle, leaflet `addControl` caption at bottomleft) and printed by `print()`, because a construction-time console message does not survive a re-print or a screenshot. The three covariate states are deliberately distinct — a fit that HAS a covariate but is drawn without it says `OMITTED (not a <col>-conditioned field)` affirmatively, since silence would read as "this model has no covariate", a different and false claim. `lambda_km`/`m` are deliberately kept OFF the plot (they set how smooth the surface is, not what it is a surface of) and stay in `print()`; a regression test asserts this. This was live, not hypothetical: `GreatLakes2023_ConsensusWorkflow.R:849` passes `covariate_at = SITE_DEPTH`, so that map was an unlabelled constant-depth cross-section. Selectors for depth/habitat were considered and NOT built — see `ecosystem_docs/SPEC_plot_theta_surface.md` for the rectangle-count ceiling and the lambda-calibration reason habitat must be a re-fit, not a toggle. |
| 2026-09-04 (Opus 5) | `add_slash_taxon()` irreducibility is now order-invariant; `review_assignments()` joins on the canonical candidate set | TaxaAssign, TaxaFlag | **Behavioral, not signature.** (1) `add_slash_taxon()` hashed the UNSORTED candidate vector when testing irreducibility. Candidate order is posterior order (what `primary_taxon` reads), so one biological unit arriving as `{A,B}` on one observation and `{B,A}` on another became two "distinct" sets of equal size sharing a taxon -- each marked the other reducible and every row of the unit went `FALSE`, leaving no irreducible instance. (2) `review_assignments()` then joined review results by the posterior-ordered display label (`review_assignments.R:400` carried the same "canonical because sets are sorted" assumption), so such a unit was an orphan: never scored, all plausibility columns `NA`, and silently dropped by the workflows' `filter(x != "unlikely")` export chains, which discard `NA`. Net effect at GreatLakes 2026-09-04: a **Lamar-confirmed grass carp detection** (5 ASVs, 7,453 reads; Lamar has it in 8 of the same year's samples) vanished from the output, along with *Moxostoma* and *Oncorhynchus* slash taxa. Fix sorts inside the signature only and adds a canonical join key -- display labels, `consensus_OTU` and `primary_taxon` are all unchanged, and one unit is now reviewed once instead of twice (one FEWER LLM call). Monotone: rows can only move `FALSE -> TRUE`, verified on the real run (538 -> 577 irreducible, 39 recovered, 0 lost). Regression tests assert the order-invariance the docstring always promised. Also relaxed, in all five workflows for consistency: `geographic_plausibility`/`scope_plausibility` export filters moved from `== "likely"` to `!= "unlikely"`, matching `habitat_plausibility` and MuguWilderFish's existing convention -- "possible" is the rating a range-edge invasive earns. GreatLakes final taxa 27 -> 38, none lost. `contamination_risk` is deliberately left inconsistent across sites (`!= "high"` vs `== "low"`) pending a separate decision. |
| 2026-09-04 (Opus 5) | `convert_taxonomy_backbone()` re-verifies names that `clean_taxon_names()` changed | TaxaMatch | **Behavioral, not signature.** NCBI carries taxon records for hybrid crosses, so a GenBank label like `"Ctenopharyngodon idellus x Elopichthys bambusa"` VERIFIES with score 1 and is only reduced to its maternal parent afterwards, at `matched_name_clean`. That parent binomial had never itself been looked up, so it kept the submitting author's spelling: `NC_025590` emitted `"Ctenopharyngodon idellus"` into GreatLakes while three direct references emitted the accepted `"Ctenopharyngodon idella"`, splitting one species into two competing candidates (posterior 0.5005/0.4945) and forcing the genus back-off that lost a Lamar-confirmed grass carp detection. Its two sibling hybrids resolved correctly only because their labels already used the accepted spelling. A second pass now re-queries ONLY names the cleaning actually changed and that were not in the first pass -- one small batched call when hybrid-formula labels are present, zero extra calls otherwise (regression-tested). Results are compared against the CLEANED match, so an authority-bearing return (`"Girella nigricans (Ayres, 1860)"`) is not mistaken for a rename, and are applied to the rank columns too so `taxon_name` and `species` cannot disagree about which spelling is in use. Live NCBI check: all three Ctenopharyngodon accessions now collapse to one taxon. TaxaMatch 1232 passed, 0 failed. |
| 2026-09-04 (Opus 5) | `review_assignments()` normalises the `"(unresolved candidates; ...)"` annotation the model echoes back | TaxaFlag | **Behavioral, not signature.** `.build_taxa_block()` renders an unresolved candidate set as `"- <label> (unresolved candidates; consensus rank: <rank>)"`, and the model echoes that whole decorated string back as `taxon_name`. The batch reconciliation's `.norm()` -- added 2026-07-14 for exactly this failure mode -- required the parenthetical to begin with `"rank:"`, so the unresolved form never normalised: every multi-candidate set was treated as OMITTED, filled with NA defaults, and then dropped without a word by the workflows' export filters. Singletons were unaffected because their `"(rank: ...)"` annotation WAS handled, which is precisely why the loss masqueraded as "coarse ranks are excluded on purpose". On GreatLakes 2026-09-04 this was 113 of 885 rows, every one a slash taxon; re-reviewing them recovers all 113, all of which pass the export filter, adding *Fundulus*, *Morone* and *Oncorhynchus* plus further observations of Centrarchidae, Lepomis, Leuciscidae and Notropis. The pattern now accepts both annotation forms. The run log said `"LLM omitted N taxa. Filling with NA defaults"` throughout -- that message is the signal to watch for. TaxaFlag 445 passed, 0 failed. |
| 2026-09-04 (Opus 5) | `review_assignments(cache_dir=)` added; new `taxaflag_clear_cache()` | TaxaFlag | **Additive, backward compatible** (`cache_dir = NULL` default keeps the old uncached behaviour). The review is a JUDGEMENT and an uncached one is not reproducible: two GreatLakes runs 50 minutes apart on identical input disagreed about *Pimephales vigilax* (`"possible"` then `"unlikely"`), so it appeared in one species list and not the other. One small `.rds` per reviewed taxon, keyed on everything that can move a verdict -- taxon label and rank, its attached pipeline/weight/spatial notes, `context`, `target_group`, `marker`, `data_type`, and the candidate-set path -- so a changed context is correctly a MISS rather than a stale hit. The full key is stored inside each file and verified on read, so a hash collision costs one re-asked taxon and can never return another taxon's verdict. Deliberately the file-per-key shape `TaxaTools::list_cache_files()`/`report_and_clear_cache()` are built for, so the new `taxaflag_clear_cache()` reports and prunes it exactly like `taxafetch_clear_cache()` / `taxalikely_clear_cache()` and it does not accumulate unmanaged. All five workflows now pass `cache_dir = file.path(OUT_DIR, paste0(OUT_PREFIX, "_review_assignments_cache"))`. TaxaFlag 456 passed, 0 failed. |
| 2026-09-04 (Opus 5) | New `hierarchy_flag` value `"not_evaluated_wrong_marker"`; `.extract_feature_table_fallback()` gains `attr(out, "decline_reason")` | TaxaMatch | **Additive, nothing invalidated** -- no `.EVAL_REF_ACC_VERSION` bump, no `params_key` change, every cached row stays valid. An over-length accession the feature-table fallback declined *because the record has annotated features and none is this marker* now reads `"not_evaluated_wrong_marker"` instead of `"not_evaluated_oversized"`. Cause vs symptom: "oversized" implies a size problem a caller could fix by raising `max_query_len`, and for a record carrying a different marker no length ever helps -- the accession does not belong in the screen's candidate set. A FAILED annotation fetch deliberately stays `"oversized"` ("we could not look it up" is not "it carries a different marker"). Real case: `HM561627` (*Lasiurus intermedius*), 2,657 bp, one feature (16S rRNA, 1061-2657) in a 12S screen -- 1 of 1 oversized accessions on the real 995-accession PtConception run. Downstream: 180-day TTL alongside the other not-evaluated flags, `reference_action = "untested"`, partner weight 1, never a flag in `remove_incongruent_references()`/`flag_incongruent_references()`/`verify_flagged_references()`; each verified by test, not assumed. `devtools::test()` 1256/0, `check()` 0/0/0. |
| 2026-09-04 (Opus 5) | MEASUREMENT, no code change: `congruent_evidence_exists_anywhere` (the hard removal veto) is truncated by `max_hits` | TaxaMatch | Not a change -- evidence for a decision the user still has to make. The veto that spares an accession from `reference_action == "remove"` is documented as walking the pool "not limited to `top_n`", but the pool is itself capped by `max_hits` (default 20), and 899 of 989 real PtCon accessions (91%) return AT that cap. New `diagnostics/veto_truncation_probe.R` re-ran the 15 veto-critical accessions at `max_hits = 100`: `congruent_evidence_exists_anywhere` flipped FALSE->TRUE for **8 of 15**, and `OQ846263` (*Rathbunella hypoplecta*) -- one of only two PtCon `"remove"` accessions -- became unremovable (`"inspect"`), halving the removal set again. `KM057967` (*Jordania zonope*) still removes, and both congruent controls are unchanged, so the probe is discriminating rather than flipping everything. 7 of 8 zero-partner `"insufficient"` rows resolved to `"congruent"`, so `max_hits` (not the independence filter) was starving them. Caveat: all 15 still return 99-100 hits, so 100 is also truncated. `max_hits` is in `params_key`, so raising the default would invalidate ~3,000 cached rows across PtCon + the three GreatLakes caches -- deliberately left as the user's call. Distinct from the closed widen-BLAST thread, which measured the MATCH path (0/22 at the cap) and says nothing about this function. |
| 2026-09-04 (Opus 5) | `label_confidence` is `NA` (and `reference_action` `"untested"`) when `n_independent_top_matches == 0` | TaxaMatch | **Behavioral, not signature; no cache invalidation** (derived post-hoc column). Such a row previously scored EXACTLY 0.500 -- `frac` falling back to its 0.5 default with no data and the identity margin `NA` -- landing in the `"caution"` band, so the screen asserted concern earned by an absence against a base rate of 931 congruent of 989 evaluated. Measured across four independent real caches (153 `insufficient` rows) the split is total with zero exceptions: all 98 zero-partner rows scored 0.500 and read `"caution"`; all 55 rows with >= 1 partner had corroborating evidence and read `"keep"`. The rule keys on the partner COUNT, not on `hierarchy_flag` -- a 1-2 partner row also reads `"insufficient_independent_evidence"` but does have evidence. Real effect: 98 rows move `caution` -> `untested` (PtCon 17, GL goal2 7, GL Plate1 24, GL pilot 50); PtCon's `caution` band drops 21 -> 4. `"untested"` correspondingly widens from "never submitted to BLAST" to "no usable evidence obtained". `devtools::test()` 1277/0, `check()` 0/0/0. |
| 2026-09-04 (Opus 5) | `verify_removal_candidates()` added | TaxaMatch | **Additive, new exported function.** The pre-removal audit: re-evaluates ONLY the accessions actioned `"remove"` at a wider `max_hits` (default 100) and reports which stop being removable (`spared`), plus `still_saturated` where the audit's own window was also at its cap. Zero NCBI calls when nothing would be removed. Compares its own `params_key` against the production evaluation's and warns, naming the differing fields, if anything other than `max_hits` differs -- forgetting to forward `barcode_term` otherwise yields a meaningless comparison. This is the chosen answer to the `max_hits` truncation finding: the default STAYS at 20 (it is in `params_key`, so raising it re-BLASTs ~3,000 rows across four caches, and truncation explains only ~35% of the `insufficient` population anyway), and the audit targets the one decision made destructively. |
| 2026-09-04 (Opus 5) | `.load_reference_accession_cache()` NA-fills a missing column that is on the new `.ADDITIVE_CACHE_COLUMNS` allowlist instead of discarding the whole file | TaxaMatch | **Behavioral, strictly less destructive; no signature change.** Previously ANY column mismatch discarded the entire cache, which is correct for a column a verdict depends on but meant every additive DIAGNOSTIC column cost a full re-BLAST of every cached row (~3,239 across four real caches) -- the same price this package refuses to pay for a `params_key` change, so in effect a diagnostic column could not be added at all. A column may join the allowlist ONLY if `NA` is a safe reading of it for a row computed before it existed; most fail that test (`congruent_evidence_exists_anywhere` NA-filled would make a row MORE removable, since `!(NA %in% TRUE)` is `TRUE`; `n_independent_top_matches` now drives the zero-partner rule). A missing column OFF the list still discards, unchanged. A test asserts every listed column genuinely does not move `label_confidence`/`reference_action`, so the claim cannot rot. Verified on all four real caches: nothing discarded. |
| 2026-09-04 (Opus 5) | Four additive diagnostic columns: `query_len_submitted`, `query_trim_path`, `n_excluded_same_batch`, `n_excluded_not_species_resolved`; `.trim_queries_to_amplicon()` gains `attr(out, "trimmed")` | TaxaMatch | **Additive; NO cache discarded and nothing re-BLASTed** (they ride the allowlist above and are `NA` on existing rows until an accession is re-evaluated). The screen's audit trail: what was actually submitted (`query_len_submitted`), which rescue produced it (`query_trim_path`: `"as_deposited"`/`"primer_match"`/`"feature_table"`), and why a BLAST hit did not become a voting partner. The two exclusion counts PARTITION the excluded hits, so `n_top_matches_available` minus both equals the survivors. Answers a question that had to be re-derived by hand repeatedly: a zero-partner accession previously read `n_independent_top_matches == 0` and nothing else, making "BLAST found nothing" indistinguishable from "BLAST returned a full slate and every hit was the accession's own submission batch". Deliberately per-accession rather than extra pair-cache rows, since the pair sidecar is what `refine_reference_verdicts()` votes over and disqualified partners must not risk being counted as voters. |
| 2026-09-04 (Opus 5) | `apply_undetected_evidence(pricing = "curve")` accepts a MULTI-GROUP kernel fit and prices per group; new `sampling_group`/`group_fallback`/`min_group_n_eff`/`min_group_f1`/`cap_at_singleton`; new `sampling_group`/`pricing_basis` output columns; `generate_undetected_diversity()` scales singleton mirrors by their own group's `n_eff` | TaxaExpect | **Additive + a behaviour change on a path that previously ERRORED.** Closes open decision #2 of the kernel budget/pricing re-entry doc: a multi-group fit used to be refused outright ("per-group curve pricing is not wired up yet"), and is now the supported path -- each evidence taxon is priced at its own sampling group's Good-Turing budget, justified by the 1859x per-group spread the 18S diagnostic measured. Group assignment is NEVER inferred from taxonomy (an unassigned taxon errors with guidance): the classification that built the occurrence pool's groups lives in the caller's workflow, and a wrong group mis-prices silently. Three guards, each of which fires on the real 10-group PtConception 18S fit -- support (`min_group_n_eff`/`min_group_f1`, which stops a 27-effective-record group pricing an unseen plant at 2.1% of its own community), a singleton cap (binds exactly when `f1 < 2*f2`, i.e. real zooplankton priced 4.7x ABOVE a species seen once; deliberately NOT the open `mass/f1` decision, which binds the other way), and a group-wise pooled-qualifying fallback that never re-pools records. **SINGLE-GROUP FITS ARE BYTE-IDENTICAL** -- verified old-vs-new on the real GreatLakes checkpoint at max \|delta\| = 0 on alpha/beta/theta_mean, so the Lamar-validated GL result does not move. Second real bug fixed alongside: `generate_undetected_diversity()`'s kernel adapter divided every singleton mirror by the POOLED `n_eff`, understating each group's mirrors by 1.86x (fishes) to 4295x (terrestrial arthropods) on a multi-group fit. `PtConceptionWorkflow_18S_2_single_site.R` wired (`WATCH_SAMPLING_GROUP <- "fishes"`, 1.26x the pooled price); domestic/food deliberately stays on the pooled fit. `devtools::test()` 1018/0, `devtools::check()` 0/0/0. |
| 2026-09-05 (Opus 5) | `download_gbif_occurrences()`: zip integrity verification + retry, self-healing cache hit, extraction warning promoted to error, `allow_prompts = FALSE` (NO blocking menus by default), `prompt_mb`, `cache_prompt_mb`, `keep_zip`; `check_geographic_outliers()`: `candidate_taxa`/`candidate_scope`/`verdict_cache`, routed through `get_gbif_occurrences()`; `taxafetch_clear_cache(zips_only=)` | TaxaFetch | **Mostly additive; two real behaviour changes.** (a) **No prompt blocks any more.** `utils::menu()` reads stdin, and RStudio queues a sourced script's remaining lines as console input -- on 2026-09-04 a cache prompt consumed ~600 lines of a live workflow as menu answers, silently swallowing them so they never executed (the GBIF download had already succeeded). `interactive()` cannot distinguish a human from the editor, so gating on it does not help. Every decision is now REPORTED with the command to act on it; pass `allow_prompts = TRUE` only when calling by hand. Same hazard this package already documented for `readline()` in `TaxaMatch::group_observations_by_bbox()`. (b) **`check_geographic_outliers()` can now be scoped to assignable taxa.** `candidate_taxa = NULL` keeps the old full sweep, so nothing breaks silently, but every workflow now passes it: a family-derived occurrence pool is ~20x wider than its species-level candidates (387 of 7,392 at PtCon 18S), and the unscoped per-key global fetch earned a GBIF rate-limit block at 360/829 keys. Real reduction 2,683 -> 591 rare species. Also: a truncated download is no longer cached as complete (127,733,417 of 130,577,434 declared bytes, which then failed on every re-run); the global fetch no longer inherits a `limit = 10000` cap that truncated the reference cloud by return order; verdicts are cached instead of the raw global cloud; and `keep_zip = FALSE` + `zips_only` address the fact that 38 zips held 17.0 GB against 52 MB for every other cache file combined. `devtools::test()` 737/2 (both pre-existing CoordinateCleaner environment failures). |
| 2026-09-06 (Sonnet 5) | `review_assignments()`: `habitat_plausibility`/`geographic_plausibility`/`scope_plausibility`/`contamination_risk` -> `llm_habitat_plausibility`/`llm_geographic_plausibility`/`llm_scope_plausibility`/`llm_contamination_risk`; new `consensus_plausibility_col`/`consensus_discrimination_col` params (defaults `"consensus_plausibility"`/`"consensus_discrimination"`); new `geographic_disagreement_basis` output column | TaxaFlag | **Breaking rename + additive.** All four renamed columns are independent LLM judgments, never derived from or gated by the pipeline's own values -- the old bare names read as if they might be pipeline output, which is what made a real surprising case (an LLM rating a taxon "likely" despite a ~6.5e-6 prior and both `unprecedented`+`indistinguishable` pipeline flags) hard to trace. The two new params gate a consensus-scope skepticism GUIDELINES bullet (LLM must cite specific evidence or default to "unlikely" for a flagged taxon); `geographic_disagreement_basis` is a deterministic, code-computed column (not derived from `review_comment`, which an LLM isn't guaranteed to populate) that fires whenever `llm_geographic_plausibility %in% c("likely","possible")` despite either ground (`"unprecedented"`/`"indistinguishable"`/`"unprecedented+indistinguishable"`, `NA` otherwise). The LLM's own JSON response schema is unchanged -- only the final output column names carry the prefix. `report_flags()`'s contaminant-detection regex updated to also match `llm_contamination_risk`; `review_spatial_context()`'s AI-review panel updated; all 7 real external eDNA workflow scripts (PtConception x4, Mugu x2, the shared Template) updated, backed up first (`*.bak_pre_llm_column_rename`). `devtools::test()` 456/456, `devtools::check()` 0/0/0, reinstalled. See `TaxaFlag/CLAUDE.md`'s own top session note. |
