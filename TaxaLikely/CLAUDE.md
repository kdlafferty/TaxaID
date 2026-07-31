# CLAUDE.md -- TaxaLikely
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-30 (Sonnet 5 -- full code + domain review against `inst/Code and
# Domain Review 2.Rmd`, findings + fixes recorded in `inst/taxalikely_review.Rmd` (moved
# there from a monorepo-root DRAFT after this session's fixes, matching TaxaFetch's own
# `inst/taxafetch_review.Rmd` precedent). 9 low/low-medium findings, 0 vulnerabilities, 0
# domain-review findings -- all 9 fixed this session. Six were purely cosmetic (a drifted
# `.lintr` exclusion for `R/train.R`'s object-name lints, now `c(901, 936, 1076, 1092,
# 1100)`; 6 residual brace/semicolon/line-length lints; the local `df` variable renamed to
# `ref_seqs`/`seq_df`/`crabs_df` in `build_sequence.R`/`trim_to_amplicon.R`/`read_crabs.R`
# respectively, since it shadowed `stats::df()`). Two were real DRY refactors: `R/coverage.R`'s
# `.audit_one_genus_reverse()` had two near-duplicate ~25-line NCBI species-enumeration
# blocks, factored into a new `.ncbi_species_enumerate()` -- careful comparison found the
# two blocks were NOT byte-identical (the primary-source block warned on failure, the
# fallback block failed silently), preserved via a new `warn_on_error` parameter rather
# than silently picking one behavior; `R/fetch.R`'s four hand-rolled 3-attempt retry loops
# (`.fetch_summaries_batched()`/`.fetch_taxonomy_map()`/`.fetch_fasta_batched()`/
# `.fetch_locations_batched()`) were confirmed genuinely identical and factored into
# `.retry_fetch()` with no behavioral parameterization needed. One was a real, if
# currently-harmless, fragility fix: `R/interpret.R`'s `interpret_model()` had outer
# scalars `mu_score`/`mu_gap` sharing a name with `H1_Lookup`'s real per-species columns of
# the same name, relying on tidy-eval data-mask precedence inside a later `dplyr::mutate()`
# to resolve correctly -- renamed the outer scalars to `global_mu_score`/`global_mu_gap`,
# left `H1_Lookup`'s own columns (a real, ecosystem-wide name) untouched. `DESCRIPTION`
# gained `Depends: R (>= 4.1.0)` (a live `R CMD build` warning had been auto-detecting this
# from the package's own `|>`/`\(...)` usage in 7 files; confirmed gone after the fix).
# `inst/TaxaLikely_workflow.R`'s line 252 hardcoded personal path replaced with the same
# `system.file()`-based pattern already used a few lines above for the companion `.rds`.
# Two stale cached `.rds` files (`inst/real_matrix.rds`, `inst/real_likelihoods.rds`,
# already `.Rbuildignore`d, tied to that superseded workflow script) deleted after
# confirming via a whole-monorepo grep that nothing in TaxaLikely itself reads them (two
# references exist in TaxaAssign's own separate workflow scripts, flagged not touched).
# `devtools::test()` 925/925 (0 failures, 9 expected warnings, 1 environment skip --
# unchanged by this session, no test added or removed), `devtools::check()` 0 errors/0
# warnings/0 notes (down from the pre-fix `R CMD build` dependency warning),
# `lintr::lint_package()` 0 hits in `R/` (down from 12; 214 total package-wide, down from
# 226). Reinstalled to `~/Library/R/4.0/library`. See `inst/taxalikely_review.Rmd` for the
# full record.
# Previous update, 2026-07-28 (Opus 5 -- absolute_fit_pvalue REMOVED entirely, along with the
# internal .one_sided_fit_pvalue() helper it was built on. User decision after an audit
# they requested to avoid column creep; a revival memory was written FIRST at their
# explicit request -- see [[project_absolute_fit_pvalue_retired]] in the TaxaID memory
# system for the full justification, the measurements, and what would warrant bringing it
# back. Removed rather than deprecated, matching this package's own established
# zero-real-callers bar (fetch_reference_sequences(), audit_barcode_coverage_ncbi(),
# expand_consensus_candidates()).
#
# Four measurements on real Mugu data drove it: (1) ~78% redundant with the Axis 2
# discrimination signal -- cor(absolute_fit_pvalue, species_confusion_risk) = -0.883,
# R^2 = 0.78, computed against the POST-FIX confusion_risk, and the 3x3 tier cross-tab is
# near-diagonal with only ~19/792 rows off-pattern; (2) its ONLY consumer never fired --
# TaxaFlag::add_posthoc_assessment()'s "unsupported_rank" triggered on 0 of 606 real
# observations at the shipped 0.001 default, and is absent from real posthoc_assessment
# output entirely; (3) the proposed inconclusive < 0.05 tier held 2 of 792 rows; (4) severe
# unnormalised marker dependence -- median 12S 0.453 / 16S 0.462 / COI 0.032, fraction
# below 0.05 17% / 14% / 51%, so one fixed threshold means three different things.
#
# VERIFIED BEFORE REMOVING, not assumed: the p-value was purely informational and never
# gated anything. The TWO-SIDED `alpha` outlier gate (Session 121) is computed
# independently, not derived from it, and is completely unchanged -- so no likelihood
# value moves as a result of this removal. Also corrected a wrong conclusion I reached en
# route and should not be re-inherited: the saved *_lik_model_*.rds checkpoints have no
# Query_Calibration slot, which LOOKS like calibration never ran; it did --
# MuguWilderFishWorkflow.R:784 calls calibrate_query_noise() AFTER the model checkpoint is
# written. Do not infer calibration state from the saved model object. Separately, the old
# reentry doc's claim that COI "can never reach 0.70 (max 0.606)" is contradicted by real
# data (COI max 1.000, 24.6% of rows >= 0.70) -- treat it as unverified.
#
# Also this session: all 9 documentation-only vignettes across the ecosystem gained
# `purl = FALSE` alongside their existing `eval = FALSE`. R CMD check's "running R code
# from vignettes" step TANGLES via knitr::purl(), which honours purl=, not eval= -- so a
# vignette that never evaluates while knitting still executed during check and errored on
# objects its prose never defines. TaxaLikely's score-to-likelihood.Rmd was the one
# actively failing; the other 8 shared the same latent pattern.
# TaxaFlag/vignettes/quality-flagging.Rmd deliberately NOT changed -- it has no global
# eval = FALSE and genuinely evaluates, so a blanket purl = FALSE would have silently
# disabled a working vignette. TaxaLikely now passes a full check INCLUDING vignettes:
# 0 errors / 0 warnings / 1 note (the pre-existing environmental timestamp note).
# devtools::test() 925 pass / 0 fail (down from 932 -- the 7 removed are the retired
# column's own tests). Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-27 (Opus 5 -- two real fixes to R/support_curves.R's confusion-risk
# machinery, found while verifying the single most load-bearing unverified assumption in
# TaxaFlag/REENTRY_PROMPT_axis2_multifactor_diagnostic_redesign.md ("Dr = X", i.e. that
# confusion_risk is already a clean per-candidate-pair rate). It is NOT: .eb_shrink() returns
# w*rate + (1-w)*pooled_rate with w = n/(n+prior_weight), so the reported value is an
# Empirical-Bayes blend. Real 12S: median w = 0.69, min 0.17; on real rows 38 report nonzero
# risk where the genus's own data says exactly 0, 63 report <1 where raw is 1, and 7 cross the
# 0.5 flag threshold purely from shrinkage. This matters beyond bookkeeping -- w is a function
# of n (referenced congener count), which is exactly the reference-completeness quantity the
# reentry doc's planned `Ds` correction was going to inject separately, so `Ds` would have
# double-counted it. `Ds` was dropped on that basis (user-approved).
#
# FIX 1, Jeffreys floor: rate curves now carry BOTH the raw empirical proportion (rate/
# pooled_rate) and a Jeffreys-smoothed companion (rate_smooth/pooled_rate_smooth =
# (k + 1/2)/(n + 1), the Beta(1/2,1/2) reference prior -- already this ecosystem's own
# convention for the same problem, cf. TaxaExpect::generate_full_priors()'s jeffreys_fallback,
# Jeffreys 1946). Needed because a raw k = 0 reports an EXACT zero ("no congener could ever
# score this well"), which finite reference data cannot support -- and it is not a rare edge
# case: on real 12S every observed score at/above ~99.5% identity landed on a zero-valued grid
# point. Chosen over Laplace (k+1)/(n+2) and the rule of three because it is derived rather
# than picked, adds no tunable constant, is one line of arithmetic on values already computed,
# and is a continuous estimator defined on every row (the rule of three only exists at k = 0).
#
# FIX 2, interpolation: .lookup_confusion_risk_value() now interpolates linearly
# (stats::approx(rule = 2)) instead of snapping to the nearest grid threshold. The curves use a
# 1-percentage-point grid, but the congeneric FPR falls very steeply across the top point (real
# 12S: 0.279 at 99% to ~0 at 100%) and 45% of real observed scores sit at or above 99% -- so
# snapping reported the SAME confusion risk for a 99.5% match as for a literal 100% one, while
# separating 99.4% from 99.6% by the full height of that final step. An artifact of grid
# spacing, not a property of the evidence. This half needs no retraining -- it reads the same
# stored grid more faithfully. It also explains the reentry doc's puzzling "153/606 rows show
# an exact zero at species, genus AND family simultaneously, a perfect overlap": all three
# tiers' pooled curves hit 0 at threshold 100, so every row >= 99.5 zeroed at all three ranks
# at once. That was the cliff, not the structural coverage pattern the doc inferred.
#
# WHY THE RAW AND SMOOTHED COLUMNS ARE KEPT SEPARATE -- do not "simplify" this back into one.
# Replacing `rate` outright was implemented and tested first, and moved real production
# thresholds (12S genus 97->98, 16S genus 96->98, COI species 98->99), because (k+1/2)/(n+1)
# reweights groups by n/(n+1), partly undoing the deliberate genus-/family-equal weighting this
# file exists to apply. compute_rank_thresholds()'s Youden's J wants the argmax of the raw
# empirical ROC; the confusion-risk lookup wants a well-behaved probability estimate. Splitting
# the columns leaves all three markers' rank_thresholds bit-identical to their cached values
# (verified against the real Mugu seq_matrices) while still fixing the lookup -- important
# because those thresholds are wired into both real Mugu production workflows via
# TaxaAssign::score_consensus().
#
# Real effect (12S species tier, pooled): 99.4/99.5/99.6 went from 0.279/0.279/0.000 -- a cliff
# triggered by a 0.1-point score change -- to a smooth gradient; a literal 100% match now
# reports 0.0393 instead of an impossible exact 0. New tests/testthat/test-support-curves.R
# (46 assertions): this file had NO committed test coverage at all before, despite shipping
# 2026-07-23. devtools::test() 932 pass / 0 fail (up from ~886); devtools::check() 0 errors /
# 0 warnings / 0 notes with --ignore-vignettes. Reinstalled to ~/Library/R/4.0/library.
#
# CAVEAT: the Jeffreys half changes STORED curves, so it only takes effect on retrained models;
# the interpolation half applies immediately to existing ones. Every cached *_lik_model_*.rds /
# *_lik_result_*.rds still holds pre-fix confusion_risk values until the workflow re-runs
# train_likelihood_model() + evaluate_likelihoods(). Nothing was re-run this session.
#
# ALSO FOUND, PRE-EXISTING, NOT FIXED (flagged, untouched -- confirmed unmodified in git and
# unrelated to this work): vignettes/score-to-likelihood.Rmd fails R CMD check's
# "running R code from vignettes" step with "object 'reference_df' not found". The vignette
# sets eval = FALSE in opts_chunk$set, but check tangles and sources the code regardless.
# Previous update, 2026-07-23, later same day (Sonnet 5 -- renamed species_support/genus_support/
# family_support/own_rank_support -> *_confusion_risk (and model_params$Support_Curves ->
# Confusion_Risk_Curves) after the user noticed the original names inverted this ecosystem's
# high=concern convention for risk-style metrics. Pure rename, no math changed -- see
# TaxaID/CLAUDE.md's top session note for the full cross-package record (also covers the
# matching TaxaAssign/TaxaFlag renames and the same-session compute_rank_thresholds() rollout
# into both real Mugu workflows). The note below (same day, earlier) describes the original
# implementation and now uses the corrected names throughout.
# Previous update, 2026-07-23 (Sonnet 5 -- implements Task 1 of ecosystem_docs/REENTRY_PROMPT_
# score_support_posthoc_and_rank_thresholds.md (see TaxaID/CLAUDE.md's top session note for
# the full cross-package record). New R/support_curves.R: .compute_rank_score_curves()
# (internal) makes diagnostics/score_floor_roc_sweep.R's genus-/family-equal-weighted,
# Empirical-Bayes-shrunk per-rank TPR/FPR curves real package machinery, shared by two
# consumers rather than duplicated. train_likelihood_model() calls it once at training
# time and stores the result in a new model_params$Confusion_Risk_Curves slot (NULL-safe when
# rank_system has fewer than 2 levels) -- computed once, not recomputed per inference
# call, per the user's explicit design decision. evaluate_likelihoods() gains
# species_confusion_risk/genus_confusion_risk/family_confusion_risk/own_rank_confusion_risk output columns, reading
# Confusion_Risk_Curves: a model-independent, score-ONLY diagnostic (P(a real congener/
# confamilial/cross-family pair would score this high or higher), evaluated at each row's
# own genus/family and raw observed score) deliberately kept separate from the model-based
# absolute_fit_pvalue. LOWER values mean STRONGER evidence (a one-sided tail probability,
# not the usual higher-is-better "support" sense) -- documented explicitly in a new
# @section Confusion risk to head off the obvious misreading. All three *_support columns
# are populated for every row regardless of hypothesis_type (per the user's chosen
# design), with own_rank_confusion_risk as a convenience pointer at whichever matches that row's
# own resolved rank. New exported compute_rank_thresholds(seq_matrix, ...): a marker-
# agnostic per-rank Youden's J threshold deriver, reusing the identical curve machinery,
# built specifically to be what TaxaAssign::score_consensus()'s new required-rank_
# thresholds error message points at (see that package's own top session note). Verified
# on synthetic data before wiring into the real functions: a hand-built 2-family/2-genus/
# 3-species-per-genus fixture with clearly separated score bands (species ~97-99.5%,
# congeneric ~85-95%, confamilial ~60-80%, cross-family ~20-50%) recovered exactly the
# expected thresholds (species=95, genus=80, family=50) via compute_rank_thresholds(), and
# .lookup_support_value() gave 0.985 (weak evidence) at 90% for a congener-confusable
# genus vs. 0 (strong evidence) at 99% -- confirming the semantics work as designed before
# trusting them on real data. devtools::test() 0 failures (463), devtools::check() 0
# errors/0 warnings/0 notes. Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-20, continued (Sonnet 5 -- expand_consensus_candidates() removed
# entirely (deprecated since Session 99, -> unreferenced_candidates() + assign_scores()),
# same "no external users yet, don't keep an unneeded migration path" reasoning as the
# fetch_reference_sequences()/audit_barcode_coverage_ncbi() removal two entries below.
# Deleted R/expand_consensus.R (its only function, no shared internal helpers), tests/
# testthat/test-expand-consensus.R, and its own dedicated teaching workflow inst/workflows/
# expand_consensus_demo.R -- confirmed zero real callers anywhere in the monorepo or the
# two real external Mugu/PtConception production workflows first (the only monorepo hits
# were the function's own definition/tests/roxygen and an RStudio .Rproj.user session-cache
# file, not real code). Fixed one stale cross-reference in compute_likelihoods()'s own
# roxygen that named the now-deleted function. Also verified and updated
# inst/review_function_inputs.R for BOTH this removal and the separately-made
# evaluate_likelihoods() rank-trust simplification below (prompted by the user flagging
# that change directly) -- Section 6's evaluate_likelihoods() example already correctly
# showed only absolute_fit_pvalue (no trusted_rank/rank_trust_basis) by the time this
# session reached it; confirmed by live-running the whole file end to end, 0 errors.
# TaxaAssign/TaxaFlag's own downstream consumers checked directly (grep) and confirmed
# already consistent with the simplified evaluate_likelihoods() -- no stale references to
# the removed columns found in either package's live code. devtools::test() 0 failures,
# devtools::check() 0 errors/0 warnings/1 pre-existing environmental note. One .lintr
# exclusion line number corrected (drifted by +2 from the fetch.R edit two sessions back).
# Previous update, 2026-07-20 (Sonnet 5 -- removed the rank-trust ladder-walk mechanism
# entirely: evaluate_likelihoods() no longer has a min_rank_trust_pvalue param, and no
# longer produces trusted_rank/rank_trust_basis columns. absolute_fit_pvalue (the
# per-row, one-sided goodness-of-fit p-value each mechanism was built on) is unchanged
# and still computed unconditionally -- only the ladder-walk built on top of it (deciding
# a "trusted rank" by walking H1 -> H2 -> H3 coarser until one clears the threshold) is
# gone. Prompted directly by the user pressure-testing the two downstream consumers this
# same day: TaxaAssign::posterior_consensus()'s uprank_trust_pvalue and
# TaxaFlag::add_posthoc_assessment()'s "unsupported_rank" category. Live diagnostics
# against the user's own real 12S PtConception run found trusted_rank was computed for
# evaluate_likelihoods()'s own top-LIKELIHOOD hypothesis for a query -- which is NOT
# always the same hypothesis that wins the POSTERIOR once TaxaExpect priors are
# multiplied in downstream (a real occurrence-prior-favored referenced species can win
# the posterior while a generic unreferenced-congener placeholder briefly had the higher
# raw likelihood) -- confirmed as a genuine ~30% mismatch rate on that real dataset, and
# a second, independent cancellation problem where TaxaAssign::posterior_consensus()'s
# own species_reference downranking step could silently reverse an upranking that HAD
# fired correctly. The user's proposed fix, worked through together rather than assumed:
# since absolute_fit_pvalue is already correctly anchored to whichever row a downstream
# consumer treats as "the winner" (no re-derivation needed, no separate ladder-walk to go
# stale), both downstream consumers can read it directly instead of relying on the
# ladder-walk's output -- eliminating BOTH real bugs at once rather than patching either
# one. Verified before removing anything: absolute_fit_pvalue's own one-sided design
# (P(Z <= z), never penalizes a score better than the trained mean) was independently
# confirmed safe for perfect/near-ceiling matches by re-reading .one_sided_fit_pvalue()'s
# own roxygen and the code -- directly answering the user's own sharp question about
# whether this substitution could misfire on exactly the cases it's meant to protect.
# See TaxaAssign/CLAUDE.md's and TaxaFlag/CLAUDE.md's own same-day notes for the two
# downstream consumer changes, and [[project_rank_trust_mechanism_removed]] in the
# TaxaID memory system for the full investigation record (the diagnostic script, the
# exact mismatch numbers, and the worked Sardinops/Vulpes examples that surfaced this).
# `devtools::test()` clean (0 failures) throughout; `devtools::check()` 0 errors/0
# warnings/1 pre-existing environmental note. Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-19, continued yet further (Sonnet 5 -- removed two deprecated
# forwarding aliases entirely, prompted by the user questioning why a package with no
# external users yet needed review/test coverage for a rename migration path at all.
# fetch_reference_sequences() (-> fetch_ncbi_reference_sequences(), Session 136) and
# audit_barcode_coverage_ncbi() (-> audit_barcode_coverage(), Session 113) both deleted from
# R/fetch.R and R/coverage.R (roxygen + function body), along with their dedicated test
# coverage (test-audit-barcode-coverage-ncbi.R deleted entirely; test-fetch.R's two
# deprecated-alias tests removed) and their sections in inst/review_function_inputs.R.
# audit_barcode_coverage_ncbi() had zero real callers anywhere. fetch_reference_sequences()
# did have 4 real in-monorepo callers -- TaxaAssign/vignettes/taxaid-ecosystem.Rmd,
# TaxaLikely/vignettes/score-to-likelihood.Rmd, diagnostics/Barcode_similarity_matrix.R,
# diagnostics/sandpiper_12S_similarity.R -- all four updated to call
# fetch_ncbi_reference_sequences() directly before the alias was removed (confirmed with the
# user first, since two of the four sit outside this package). Checked the two real external
# production workflows too (MuguFishWorkflow.R, MuguWilderFishWorkflow.R, outside this
# monorepo): both already call the new name; only a stale code comment mentioned the old one,
# left as-is (harmless, not a real call). devtools::test() 0 failures, devtools::check() 0
# errors/0 warnings/1 pre-existing environmental note (clock verification, unrelated).
# expand_consensus_candidates() (a different kind of deprecation -- a superseded design
# pathway with its own dedicated teaching workflow, inst/workflows/expand_consensus_demo.R,
# not a simple rename) was deliberately NOT touched this pass -- flagged to the user as a
# separate decision, not bundled into this one.
# Previous update, 2026-07-19, continued further (Sonnet 5 -- review-prep catch-up pass, after
# discovering (via file-mtime + date-stamp grep, prompted directly by the user) that three
# other sessions had substantially reworked restore_suppressed_candidates() and evaluate_
# likelihoods() since the review-prep pass documented below. (1) Deleted .audit_barcode_
# coverage_legacy_() (R/coverage.R) -- confirmed genuinely unreachable ("retained for
# reference, not called" per its own header, zero references anywhere in R/tests/man/NAMESPACE
# outside its own definition) per the user's explicit request; removed the matching now-dead
# .lintr line-number exclusions. (2) Moved inst/referencegapsinflies.pdf -> TaxaID root's
# ecosystem_docs/referencegapsinflies.pdf (reference material for the reference-gap-modeling
# work already documented there, not code -- doesn't belong in the built package). (3) Grepped
# every exported function's current signature against review_function_inputs.R's assumptions;
# confirmed the ONLY two behavioral/signature changes since this file's own last update were
# restore_suppressed_candidates() (see the Session notes below for the full redesign) and
# evaluate_likelihoods()'s new min_rank_trust_pvalue param -- everything else unchanged.
# (4) Updated inst/review_function_inputs.R's own two examples: Section 10.2 now demonstrates
# the new no-op-without-evidence default AND a seq_matrix+model_params call showing real
# restoration_basis values ("both"/"plausible_prior", fixture reused verbatim from
# tests/testthat/test-score-collapse.R's .simple_model_params()); Section 6.1 now displays the
# new absolute_fit_pvalue/trusted_rank/rank_trust_basis columns (purely additive, the existing
# fixture already exercised them correctly, just wasn't showing them). Live-executed the whole
# file again after both edits -- confirmed both sections' output matches the redesign's
# documented behavior exactly (no-op returns 1 row; nigricans admitted via "both", laevifrons
# via "plausible_prior"). devtools::test()/check() reconfirmed clean after the coverage.R
# deletion. No functional code changes made to restore_suppressed_candidates()/evaluate_
# likelihoods() themselves this pass -- that work was already complete and validated (see the
# three "Previous update, 2026-07-19"/"2026-07-18, continued..." entries immediately below).
# Previous update, 2026-07-19, continued (Sonnet 5 -- real, unrelated NCBI-fetch bug found and
# fixed while live-testing restore_suppressed_candidates() against PtConceptionWorkflow_
# 18S_2_single_site.R's real, full ~1300-genus reference fetch (the first genuinely
# large-scale live fetch_ncbi_reference_sequences() run in this whole test-drive; every
# earlier validation used a pre-cached reference_df). Real error: "Error in rbind(deparse.
# level, ...) : numbers of columns of arguments do not match", crashing the ENTIRE fetch
# (discarding every already-completed genus's work) once one genus's real NCBI taxonomy XML
# resolved to a slightly different column set than another's -- a genuine, real-data risk
# with base rbind(), not a hypothetical one. This is the exact same failure class this
# codebase already found and fixed once for the BOLD fetch path (see fetch_bold_reference_
# sequences()'s own comment: "dplyr::bind_rows(), not rbind() -- BOLD's per-query TSV column
# set can... rbind() errors on mismatched column counts") -- that lesson had just never been
# applied to the NCBI path, which had no real-scale live testing to expose it until now.
# Fixed by replacing every do.call(rbind, ...) combining per-taxon/per-batch results with
# dplyr::bind_rows() across .fetch_summaries_batched(), .fetch_taxonomy_map(),
# .fetch_locations_batched(), and the main fetch_ncbi_reference_sequences() body's
# priority_combined/family_meta/combined_meta assembly -- 6 call sites total. Verified each
# site's downstream NULL/nrow==0 handling still works correctly with bind_rows()'s different
# empty-result semantics (returns a 0-row frame, not NULL) before changing it; .fetch_
# locations_batched()'s pre-declared empty-schema fallback updated from an is.null() check to
# nrow()==0 specifically because that one path relies on guaranteed column names even when
# empty. devtools::test() 0 failures (931, up from 910), devtools::check() 0/0/0, reinstalled.
# Not yet re-verified against the real full ~1300-genus fetch that found this (that run was
# interrupted by the crash) -- left for the user to retry.
# Previous update, 2026-07-19 (Sonnet 5 -- evaluate_likelihoods() gains the "rank-trust
# mechanism": min_rank_trust_pvalue param (default 0.001) + absolute_fit_pvalue/
# trusted_rank/rank_trust_basis output columns, grown out of a live design conversation
# with the user starting from ecosystem_docs/REENTRY_PROMPT_degraded_species_likelihood_
# thresholds.md. Answers a question score_likelihood structurally cannot: not "which
# hypothesis is relatively best" but "is the WINNING hypothesis's own absolute fit
# believable, or just the least-bad option among uniformly weak candidates" -- real,
# concrete PtConception 12S cases motivated this (Hylobatidae/Lemuridae-contamination
# rows winning at likelihood=1.0 despite every specific candidate scoring poorly in
# absolute terms). Entirely "free": reuses only already-trained H1_Lookup/H2/H2_Lookup/H3
# mu/sigma, no new model fit, no new pass over reference data -- walks the winning
# hypothesis's own rank coarser (species->genus->family) until one clears a ONE-SIDED
# score-only absolute-fit test, falling back to rank_system's own coarsest level once past
# H3 (no H4+ parameterization exists, regardless of rank_system's length). The one-sided
# design (vs. the existing, deliberately UNCHANGED two-sided `alpha` H1-zeroing gate) fixed
# a real bug found before shipping: a two-sided test wrongly flags a BETTER-than-typical
# match (e.g. literal 100% identity against a tightly-clustered/clonal-reference species) as
# equally suspicious as a worse-than-typical one -- confirmed concretely (two-sided
# p~=5.7e-07 vs one-sided p~=0.9999997 for the identical synthetic inputs) after the user
# specifically asked whether the 2-tailed nature could distrust a highly-likely-correct
# 100% match. Real-data validated on PtConMifishSchulte (13,442 real obs): the two real
# contamination-pattern edge cases from [[project_edge_case_error_taxa_design]] correctly
# cap at family across the ENTIRE threshold range tested (0.0001-0.5); the taxa whose
# likelihood is genuinely strong but occurrence-implausible (Ovis aries, Salmo salar, etc. --
# a different, deliberately out-of-scope prior-side problem) correctly do NOT get flagged,
# confirming the two problem classes stay separated; false-escalation rate on 132 real
# clean-match control observations is 0% up to threshold=0.2. Also found, incidentally: only
# 44% of real posterior-resolved-to-species observations sampled also win on raw likelihood
# alone -- the rest are resolved by the PRIOR, a real-data confirmation of the closed-world/
# Bayes-completeness concern this mechanism grew out of. Param renamed twice during design
# (rank_trust_alpha -> min_rank_trust_pvalue) before ever being used elsewhere -- final name
# only, no NAME_CHANGE_HISTORY.md entry needed. devtools::test() 0 failures (931, up from
# 910), devtools::check() 0/0/0, reinstalled to ~/Library/R/4.0/library. NOT yet wired into
# any production workflow -- see this file's own Function Inventory entry for the full
# validation record and the separate, already-abandoned Deliverable-2 (referenced-but-
# excluded-candidate rate) investigation this session also revisited and declined to rebuild.
# Previous update, 2026-07-19 (Sonnet 5 -- real second cost bug found and fixed in restore_
# suppressed_candidates(), this time by the user actually running the redesigned
# PtConceptionWorkflow_12S_single_site.R against the real, full 13,442-observation dataset
# (226 genera present, some -- Sebastes -- with 100+ reference species, seq_matrix ~3M rows)
# and reporting a run that was STILL GOING after 70+ minutes (confirmed via `ps`, genuinely
# CPU-bound, not hung). Root cause, confirmed by direct profiling against the real data: the
# "free" Levels 1-3 hierarchy (.resolve_hierarchy_score()) did a fresh id_x==/id_y %in%
# linear scan over the WHOLE seq_matrix for every single candidate species, every single
# call -- R's %in%/match() rebuilds its internal hash table over the right-hand side on
# EVERY call, it does not cache across repeated calls against the same unchanging
# seq_matrix. Under Purpose A's unconditional genus-wide sweep this scan runs once per
# candidate per observation with ZERO memoization (unlike Level 4's align_cache). Measured
# directly: one real Sebastes anchor against its 106 congeners took 19.06s (73.7% in
# `%in%`), and a SECOND, identical anchor (simulating a repeat observation) took 17.64s
# again -- confirming no caching benefit, and fully explaining the 70+-minute real run
# (Mugu's largest genus, Fundulus, only had 20 species and a ~1.36M-row seq_matrix, never
# exposing this -- the same class of bug Session 159 already fixed once for the OLD Tier 1
# mechanism, but that fix only cached the id-STRIPPING step, not the actual per-accession
# LOOKUP, which is what Purpose A's unconditional sweep newly exposed at scale).
#
# Fix: new .seq_matrix_partner_index()/.seq_matrix_lookup() in restore_hierarchy.R -- builds
# a real accession-indexed lookup of every seq_matrix pair ONCE per restore_suppressed_
# candidates() call (via split(), cached in align_cache like everything else here), so a
# subsequent lookup for any one accession is a single list access, not a linear scan.
# Levels 0-3 (.has_seq_matrix_presence(), Level 1 direct-accession, Level 2 species-pair,
# Level 3's raw genus-wide fallback) all rewired onto this index; Level 3's fallback
# double-counts each real pair (once from each side's own lookup) but this is exact, not
# approximate -- doubling a value multiset uniformly leaves its median unchanged (verified:
# median(c(x,x)) == median(x) for any x), confirmed empirically too (all 65 existing
# score-collapse tests pass unchanged after the rewrite, byte-for-byte same results).
#
# Verified directly against the real data that exposed the bug: the same Sebastes anchor
# that took 19.06s/17.64s now takes 1.55s (one-time index build, dominated by the already-
# cached id-stripping step) / 0.03s (repeat anchor -- ~590x faster). Full real-scale
# validation: the ENTIRE 13,442-observation PtConception 12S restore_suppressed_candidates()
# call, exact real production parameters (check_regional_overlap=TRUE, sequence_col=
# "sequence", candidate_species_filter=unique(taxaexpect_priors$taxon_name)), completed in
# **42.1 seconds** -- down from 70+ minutes (and still running when the user interrupted
# it), a >100x improvement, not an isolated microbenchmark result. 6,748 candidate rows
# added across 3,863 observations, 6,014 congeners recorded in regional_unreferenced across
# 1,430 observations -- real, substantial restoration activity confirmed, not a no-op that
# happens to also be fast. devtools::test() 0 failures (910, unchanged), devtools::check()
# 0/0/0, reinstalled to ~/Library/R/4.0/library. See
# [[project_restore_suppressed_candidates_implementation]] in the memory system for the
# full record, including how this was found (the user ran the actual updated
# PtConceptionWorkflow_12S_single_site.R for real, not a synthetic test -- the second time
# in two days a real end-to-end run surfaced a genuine performance bug no amount of
# synthetic/small-scale testing had exposed).
# Previous update, 2026-07-18, continued yet further (Sonnet 5 -- Level 4 cost-control redesign
# ("Option A + C") for restore_suppressed_candidates(), prompted directly by live-testing the
# redesign above against two real motivating cases the user asked to test-drive: Mugu
# Fundulus lima/parvipinnis and a newly-found PtConception Girella simplicidens/nigricans
# analog. Both real cases share the same structural trigger -- the ANCHOR species itself has
# zero seq_matrix presence (F. lima's only refs are out-of-range mitogenomes; Girella
# simplicidens/nigricans only have ~4000bp partial-mitogenome refs, never entered training) --
# which routes EVERY genus congener to Level 4's live alignment under Purpose A's prior-
# agnostic sweep, since the original compute-budget mechanism's ratio (R = P_anchor/P_candidate)
# is uncomputable whenever the anchor itself is occurrence-implausible (exactly the case this
# whole function exists to handle) and the original design skipped Level 4 for EVERY candidate
# in that case, including the one that matters. Measured real cost of the unrestricted default:
# restoring one marker's real Mugu 12S data took 275.8s (Fundulus's 20 species all live-aligned
# against F. lima's 16kb mitogenome); the documented pre-redesign baseline for the same data was
# 38s (candidate_species_filter-gated).
#
# Fix, per user design discussion ("Option A with C as a backstop"): (A) candidate_species_
# filter is restored as Level 4's own DEFAULT gate -- a candidate on the filter (or ANY
# candidate, when no filter is supplied at all) is always worth checking; a candidate NOT on
# the filter falls back to the original ratio test (still correctly handles a real-prior
# candidate a static filter happened to miss). This is a two-tier gate, not a replacement --
# Levels 1-3 (the free hierarchy) remain completely filter-independent, so Purpose A's
# genus-wide competitiveness detection is unaffected; only the one expensive step (Level 4) is
# gated. Internal function renamed .worth_tier2_budget() -> .worth_level4_check() (its role
# is broader than pure budget math now) and gains a candidate_species_filter param. (C) new
# max_level4_per_anchor param (default 10L, Inf disables), a hard backstop cap on distinct
# live-alignment attempts per anchor accession, independent of (A) -- insurance against a
# large/absent filter or a permissive ratio still admitting unbounded candidates. New internal
# .level4_attempt_allowed(), cache-keyed per anchor_accession in the same align_cache every
# other Level 4 mechanism already uses.
#
# Verified against BOTH real motivating cases, not just synthetic tests: Fundulus goes from
# ~19 live alignments per anchor down to 1 (F. parvipinnis, still correctly rejected on
# position grounds -- direct query-vs-reference alignment confirmed independently this session
# that OQ846298 genuinely doesn't cover this query's real hit window, 90% identity over only
# 10bp vs F. lima's 98.98% over the full 98bp read -- not a mechanism artifact); Girella goes
# from 8 wasted alignments down to 0, keeping the 1 that matters (G. nigricans, still correctly
# admitted at its real ~98% score, restoration_basis = "both"). Full real pipeline reproduction
# (restore -> calibrate_query_noise -> evaluate_likelihoods -> expand_unreferenced_hypotheses ->
# join_priors -> compute_posterior -> posterior_consensus, all 397 real 12S Mugu observations,
# real cached checkpoints, nothing written to production files): restore_suppressed_candidates()
# 275.8s -> 66.5s (~4.1x), full pipeline 6.02min -> 2.44min (~2.5x), F. parvipinnis still wins
# all 5 real target ASVs at 99.7-99.9% posterior (if anything stronger than both the unrestricted
# redesign's 99.5-99.9% and the original pre-redesign 98.6-99.6% baseline), n_plausible = 1
# throughout. See [[project_restore_suppressed_candidates_implementation]] in the memory system
# for the full record, including the Girella case's own numbers and the design-brainstorm
# options considered (a genus-wide Level 3 fallback loosening was proposed as an alternative,
# Option B, and set aside in favor of A+C after the user's explicit choice).
#
# devtools::test() 0 failures (910, up from 893), devtools::check() 0/0/0, reinstalled to
# ~/Library/R/4.0/library. Rolled out the same day to all four real production workflow scripts
# this redesign was validated against (outside this monorepo, not under git):
# MuguFishWorkflow.R, MuguWilderFishWorkflow.R (both gain model_params = lik_model too, enabling
# Purpose A there since lik_model is already trained before the restore call in both --
# PtConception's two scripts train lik_model AFTER restoration, so Purpose A stays unavailable
# there without a larger reordering not attempted this session), PtConceptionWorkflow_
# 12S_single_site.R, PtConceptionWorkflow_18S_2_single_site.R (all four: removed the now-invalid
# detected = detected argument, updated comments with the real cost numbers). NOT updated,
# flagged to the user rather than touched: PtConceptionWorkflow_12S_multi_site.R (a real, same-day-
# modified sibling) and three older/secondary files (PtConceptionWorkflow_12S_test_genus_fix.R,
# PtConception12S_regression_test.R, TaxaID_eDNA_Workflow_Template.R) all still call the old
# detected = detected signature and will error if run as-is.
# Previous update, 2026-07-18, continued further (Sonnet 5 -- implements
# ecosystem_docs/SPEC_restore_suppressed_candidates_redesign.md end to end: a ground-up redesign of
# restore_suppressed_candidates(), the first real code written against that design-discussion
# document (see [[project_edge_case_error_taxa_design]] in the TaxaID memory system for the full
# design-conversation record). Reframes the function's job from "restore candidates so more of them
# can individually win" to "detect whether the anchor's apparent win is real or an artifact of
# suppression," splitting admission into two purposes recorded in a new restoration_basis column:
# "competitive_score" (Purpose A -- prior-agnostic, tight score-only outlier test, same mechanism
# evaluate_likelihoods() already uses, needs model_params); "plausible_prior" (Purpose B -- wide
# build_sequence_matrix()-max_dist floor, gated by candidate_species_filter, which is re-scoped to
# Purpose B ONLY -- Purpose A now sweeps every genus congener for every observation regardless of
# the filter, closing the old "candidate_species_filter silently zeroes all restoration" red flag);
# "both" when a candidate clears both gates. New score-sourcing hierarchy (R/restore_hierarchy.R,
# .resolve_hierarchy_score()/.has_seq_matrix_presence()/.worth_tier2_budget()) replaces the old flat
# anchor_score - delta imputation: Level 0 precheck (does the anchor's SPECIES -- any of its own
# accessions, not just the one anchor accession -- have ANY seq_matrix presence at all?) routes
# straight to Level 4 when it fails; Levels 1-3 are free seq_matrix/model lookups (direct accession
# pair, any-accession species pair, genus-typical divergence via model_params$H2_Lookup$delta_shrunk
# preferred / raw genus-wide cross-species median as a no-model fallback); Level 4 is the only
# expensive step (live Tier 2 alignment via .check_regional_overlap(..., return_detail = TRUE), new
# opt-in mode returning a real percent-identity pid alongside the overlap verdict, read for free off
# the same pwalign alignment object the position check already builds -- default PID1, confirmed
# correct against the F. parvipinnis/F. lima case in the design doc). Every level aggregates by
# MEDIAN when multiple qualifying values exist, never max (an upward-biased order statistic) or a
# random pick. New opt-in compute-budget mechanism (taxaexpect_priors/grid_id_col/taxon_col/
# grid_col/theta_col/budget_ratio_cap, default 19, derived from posterior_consensus()'s
# min_posterior = 0.05) sizes Level 4 spend from the floor-vs-documented occurrence-prior ratio --
# NULL taxaexpect_priors (default) disables the gate entirely. A candidate a restored row can't be
# built for is recorded via attr(result, "regional_unreferenced") exactly as Session 159 already
# did, now with an additional basis column distinguishing "regional_reject" (Level 4 ran, found no
# overlap) from "no_reference_data" (no evidence could be gathered at all -- Level 0 failed and
# Level 4 also came back empty or was budget-skipped), closing the design doc's Q9. The no-score
# (Rule 3 / best_only) pathway is UNCHANGED -- there is no real score evidence to source Purpose A/B
# from, so it still restores every (optionally filtered) congener with the old flat synthetic gap.
#
# BREAKING, INTENTIONALLY (not a bug): the pre-redesign version restored EVERY same-genus congener
# unconditionally with a flat delta whenever a global suppression rule was detected (or unconditionally
# checked every observation under check_regional_overlap = TRUE); this version restores NOTHING for the
# scored pathway unless real evidence is supplied (seq_matrix for the free hierarchy levels, and/or
# check_regional_overlap = TRUE for Level 4) -- a bare call with neither is now correctly a no-op,
# closing red flags 1 and 2 (flat-delta imputation discarding real alignment evidence; a plausibility
# filter silently zeroing all restoration) from the design doc's Section 1. Also removed entirely:
# the `detected`/`perfect_threshold`/`purity_threshold`/`singleton_threshold` params -- every
# observation is now checked unconditionally (Purpose A is prior-agnostic and was designed
# specifically NOT to depend on a globally detected pipeline rule, closing red flag 4); detect_
# suppressed_candidates() itself is unchanged and still useful as a standalone diagnostic, just no
# longer consulted internally. New params: model_params (Purpose A's sigma source + Level 3's
# model-preferred estimate), alpha (Purpose A's outlier-test cutoff, default 0.001, reusing
# evaluate_likelihoods()'s own calibrated value), max_dist (Purpose B's floor, default 0.25, reusing
# build_sequence_matrix()'s own default), taxaexpect_priors/grid_id_col/taxon_col/grid_col/theta_col/
# budget_ratio_cap (the opt-in compute-budget mechanism). No production workflow (PtConception 12S/
# 18S_2, both Mugu scripts) has been updated to this new signature yet -- all four currently call
# check_regional_overlap = TRUE with candidate_species_filter set to a plausibility list, which under
# the new semantics restricts Purpose B only and no longer bounds Purpose A's sweep or Level 4's cost
# (that's now the compute-budget mechanism's job, opt-in via taxaexpect_priors, not wired into any
# workflow this session) -- rolling this out is a deliberate follow-on task, not attempted here (per
# the design doc's own Section 9, "Explicitly not started: implementation" -- now started, but the
# workflow rollout remains a separate step).
#
# Red flags 3 (Tier 2 lacked a percent-identity output) and the Purpose A/B redesign itself (closing
# 1, 2, 4) are resolved; red flag 5 (restored-row accession provenance always cites the first
# reference row for a species; multi-way ties pick one arbitrary anchor row for the regional-overlap
# check) remains explicitly open, as the design doc itself flagged it as deliberately deferred to a
# future session, not blocking. Generality beyond the spot-checked genera/datasets (item 7) is an
# ongoing caveat, not a one-shot resolution -- unchanged by this session.
#
# 16 new/rewritten test_that() blocks in test-score-collapse.R (62 total, up from 46) covering: the
# no-op-without-evidence behavior change, seq_matrix-hierarchy-sourced imputation (0-100 and 0-1
# scale) replacing the old delta-based assertions, median aggregation across multiple seq_matrix
# pairs for the same congener, restoration_basis values (plausible_prior/competitive_score/both) via
# a real model_params fixture, candidate_species_filter never gating Purpose A, Level 0 routing to
# Level 4 when a species has zero seq_matrix presence anywhere, the compute-budget mechanism's three
# real cases (R > cap, R <= cap, candidate absent from taxaexpect_priors entirely) plus its NULL-
# disables-the-gate default, and .check_regional_overlap(return_detail = TRUE)'s three return
# shapes (overlap + real pid; overlap = FALSE + pid = NA; overlap = NA + pid = NA). devtools::test()
# 0 failures (893, up from ~860), devtools::check() 0 errors / 0 warnings / 0 notes. Reinstalled to
# ~/Library/R/4.0/library. Not done this session: any production workflow rollout (see BREAKING note
# above); red flag 5; a systematic (not spot-check) generality pass across markers/genera.
# Previous update, 2026-07-18, continued (Sonnet 5 -- pre-code-review prep pass, following the
# TaxaFetch Session 131/148 checklist: (1) ASCII sweep (~460 non-ASCII chars across 22 R/ and
# tests/ files -- em-dash/en-dash/arrow/minus-sign, mechanically replaced; 4 math-symbol
# occurrences (sigma, proportional-to, squared, times) fixed by hand with ASCII equivalents).
# (2) Debris: deleted 2 superseded ad hoc inst/ scripts (test_session99.R -- fully superseded
# by existing testthat coverage; test_infer_exclude_predicted.R -- its 4-scenario fixture had
# no testthat equivalent, so ported into a new tests/testthat/test-infer-exclude-predicted.R
# instead of just deleting). Flagged, not removed (needs the user's OK): inst/
# referencegapsinflies.pdf (312KB, not referenced by any code/docs, not in .Rbuildignore --
# looks like personal reading material, not generated debris) and R/coverage.R's
# .audit_barcode_coverage_legacy_() (confirmed truly unreachable, "retained for reference, not
# called" per its own header -- a real deletion candidate, left in place this session). (3) Real
# test-coverage gap closed: grepped every exported name against tests/testthat/ and found SIX
# functions with zero coverage anywhere -- audit_barcode_coverage_ncbi(), audit_inat_coverage(),
# calibrate_coverage_filter(), coverage_threshold(), identify_confident_observations(),
# infer_exclude_predicted(). All six now have real regression tests (5 new test files, ~70
# new expectations total; audit_inat_coverage()/audit_barcode_coverage_ncbi() mocked offline
# via local_mocked_bindings() on .inat_species_info()/audit_barcode_coverage(), matching this
# package's existing .xc_recording_count() mocking convention). identify_confident_
# observations() and audit_inat_coverage() also gained their first @examples (both missing
# before this session). (4) Five real, small dead-code findings from a full lintr pass (new
# .lintr, line_length_linter(120) + indentation_linter/commented_code_linter disabled
# package-wide after confirming both are ~100% false positives here -- the former flags this
# package's own deliberate multi-arg-alignment house style across every file including
# brand-new ones, the latter flags the ecosystem's "# function_name()" file-header convention
# and deliberate commented-out workflow examples, not stale code): unused local variables
# `keep_cols` (compute_likelihoods.R), `agg_cols` (evaluate.R), `exp_types`
# (expand_unreferenced.R), `n_per_obs` (score_collapse.R), and a duplicate `existing_rank_cols`
# computation (unreferenced_candidates.R) -- all computed then never read again, removed.
# Plus ~20 long stop()/warning()/message() strings wrapped via paste0() and a handful of
# brace/comma/semicolon/quote style fixes in R/ (tests/inst/ left as-is -- same false-positive
# categories, lower value to chase in fixture code). `devtools::test()`: 0 failures (up from
# the prior session's count, +~70 new expectations across the 5 new test files).
# `devtools::check()`: 0 errors/0 warnings/0 notes throughout. (5) Main deliverable:
# `inst/review_function_inputs.R` added -- one runnable, REQUIRES-tagged section per each of
# the package's 38 exported functions (mirrors TaxaFetch/inst/review_function_inputs.R's
# format exactly), sourced cheapest-first from existing testthat fixtures reused verbatim,
# this package's own roxygen @examples, and new small synthetic inputs only where neither
# existed (Section 2's build_sequence_matrix() fixture was deliberately NOT hand-set -- a
# genuinely truncated sequence produces real, non-constant DECIPHER coverage values so
# Section 8's calibrate_coverage_filter()/coverage_threshold() have real signal to
# demonstrate, not a single repeated number). Live-executed the entire file top to bottom
# (not just written) -- found and fixed two real issues this way, not just by reading source:
# assign_scores(score_type = "probability") genuinely requires 0-1-scale input (unlike
# "similarity"/"similarity_softmax", which auto-detect any scale) and warned correctly when
# fed the reused 0-100-scale fixture, so that one demo now rescales first; and a live NCBI
# audit_reference_coverage() call hit one transient HTTP 502 mid-run, caught by that
# function's own tryCatch with no effect on the final (correct, non-NA) result -- documented
# in the file's own NON-DETERMINISM NOTE rather than treated as a bug. Every NETWORK section
# (NCBI via rentrez, BOLD v5, iNaturalist) needs no credentials and ran directly; the one
# NETWORK+AUTH section (Xeno-canto, fetch_xc_recording_locations()) is gated behind a
# RUN_XC_FETCH flag (default FALSE) since a reviewer is unlikely to have a personal
# XC_API_KEY. Not done this session: the security/algorithm review pass found no system()/
# eval()/parse()/unzip() calls and confirmed every external API host is a hardcoded literal
# (never built from externally-sourced metadata, unlike TaxaFetch's own DataONE SSRF finding)
# -- a quick, not exhaustive, pass; a full `/security-review` was not run.
# Previous update, 2026-07-18 (Fable -- answered the foundational train-vs-inference score-scale
# validity question in ecosystem_docs/REENTRY_PROMPT_train_likelihood_model_scoring_validity.md
# and shipped a level-aware calibration fix. Question: is a model whose H1 means are trained on
# build_sequence_matrix()'s DECIPHER reference-vs-reference MSA p_match valid to apply to query
# scores from a structurally different, undocumented external tool (PtConception 12S PercMatch)?
# Empirical answer on the real 13,442-obs 12S data (8,860-obs non-circular confident set, from
# identify_confident_observations()): the mismatch is REAL and, on this dataset, TOTAL. Per-species
# required offset regressed on trained mean has slope ~ -1 (robust b -> 0, R^2 ~ 0.87 among lookup
# species) -- real correct-species query scores collapse toward ~one identity level (~98.8%)
# regardless of what the reference MSA says that species' self-similarity is, so the per-species
# H1 LOCATION structure does not transfer to the external scoring scale at all. 5-fold CV: a single
# pooled inference mean (RMSE 0.0280) beats the current "DECIPHER per-species mean + one additive
# offset" (0.0304); per-species inference means add ~nothing (0.0278). So a single additive offset
# is patching per-species structure that isn't real on the inference scale. FIX: new opt-in
# `offset_form = c("constant","linear")` on calibrate_query_noise() (default "constant" =
# byte-identical to before, all pre-existing tests unchanged). "linear" remaps every H1 mean through
# a robustly-fit line intercept + slope*trained_mean (fit on per-species medians, weighted by obs
# count, evidence-range-clamped) instead of adding one constant -- a strict generalization
# (slope=1,intercept=offset == constant) that degrades to pooled-location when slope->0 (this data)
# and to constant-offset when slope->1 (structure transfers). Only H1 mean LOCATION is remapped; the
# H2/H3 congener-divergence deltas and gap feature -- the actual discriminators -- are untouched.
# Validated via the SHIPPED function on real 12S: linear gives slope=0.02, H1_Lookup mu_score sd
# 0.0095->0.0002 (collapse), H1 win rate 74.2%->76.3% (+2.1pts; 57 obs recovered unreferenced->correct
# specific_candidate vs 9 lost, on a 2500-obs check). CAVEATS built in + documented: confident set is
# selection-biased toward easy/abundant genera and by construction can't test congener DISCRIMINATION
# (one plausible species per confident genus), so "linear" stays opt-in with a min_calib_species guard
# (default 8L, falls back to "constant" with a warning) -- validate H1 win rate on your own data before
# enabling. Still ONE dataset/one external tool; the clean DECIPHER-vs-BLAST-on-same-pairs test the
# reentry doc's Q1 proposes remains not run. 5 new tests in test-calibrate_query_noise.R (default is
# constant/backward-compat; linear recovers constant under a constant gap; linear collapses under a
# constant-observed/no-transfer regime; too-few-species fallback). devtools::test() 0 failures (422
# tests), devtools::check() 0/0/0, installed to ~/Library/R/4.0/library. NOT wired into any production
# workflow (PtConceptionWorkflow_12S_single_site.R still calls calibrate_query_noise() with the default
# constant form) -- left for the user to opt in after validating. See [[project_train_inference_scale_validity]]
# in the TaxaID memory system for the full record.
# GENERALITY + MANUSCRIPT WRITE-UP (2026-07-18, same session, continued): ran the non-circular
# diagnostic on 4 more real datasets to test whether the "per-species DECIPHER means don't transfer"
# finding is a PercMatch/12S artifact. It is not: linear slope stayed far from 1 on every dataset with
# real per-species structure -- PtCon 12S (external) 0.02; Mugu WilderFish 12S/16S/COI, ALL BLAST-scored,
# -0.28/0.02/-0.21 -- and pooled beat per-species+offset in CV wherever there was enough data. The Mugu
# BLAST results are the clean DECIPHER-vs-BLAST comparison the reentry doc's Q1 asked for: BLAST doesn't
# preserve DECIPHER's per-species locations either, so the mismatch is a general property of using a
# different aligner at inference than at training, not specific to the unknown external tool. PtCon 18S
# has only 2 referenced species, so `linear` correctly FALLS BACK to `constant` (min_calib_species guard
# fires) -- the safe-fallback case working as designed. Then, at the user's request (they are a statistician,
# wary of unsupported methods + explicit "don't hallucinate references"), wrote a manuscript-quality
# description + defence into inst/TaxaLikely_supplemental_methods.md as new subsection 11A "Calibrating to
# the inference-time score scale" (~965 words, 3 display equations) under the existing Section 11 calibration
# discussion, plus 4 VERIFIED references (each confirmed by web search, DOIs fetched not guessed): May 2004
# Structure 12(5):737-8 + Raghava & Barton 2006 BMC Bioinformatics 7:415 (percent identity is operationally
# defined / method-dependent -- both protein-alignment papers, principle is general, stated honestly);
# Platt 1999 (Platt scaling -- ours is the linear-Gaussian analog, not logistic); Quinonero-Candela et al.
# 2009 Dataset Shift in ML, MIT Press (the train-vs-inference mismatch is a dataset/covariate shift). Core
# framing for the manuscript: affine calibration NESTS the constant offset (slope=1 special case), so the
# fitted slope is a reported DIAGNOSTIC not an assumption; slope~0 on real data means per-species reference
# means don't transfer; only the H1 LOCATION is remapped (gap + H2/H3 deltas, the discriminators, untouched);
# improvements minor but positive and never net-negative; components standard but the composition (affine
# recalibration of an open-set barcode likelihood model to the inference-time scorer, anchored on independent
# occurrence data) is to our knowledge novel. Also expanded calibrate_query_noise()'s roxygen @section with
# the generality result + precedent framing + a cross-ref to Section 11A, and added a Section 16 mapping line.
# devtools::document() clean.
# ADOPTED (2026-07-18, same session): user chose to adopt linear. Package DEFAULT flipped to
# offset_form = c("linear","constant") -- linear now default; constant kept as an opt-out (NOT hardcoded:
# it encodes a real analyst judgment the location-only confident set can't settle -- keep vs collapse
# per-species means for hard congener discrimination). Wired explicit offset_form into all 6 call sites:
# "linear" in PtConceptionWorkflow_12S_single_site.R / _12S_multi_site.R and Mugu{Fish,WilderFish}Workflow.R
# (BLAST/external, collapse confirmed); "constant" in PtConceptionWorkflow_18S_2_single_site.R (only 2
# referenced species -> affine unfittable, would just warn+fallback) and inst/TaxaID_Workflow_Template_TEST.R
# (tiny bundled fixture), each with an explanatory comment. Real edge-case bug found+fixed via the new
# default-is-linear test: exactly 1 confident species makes sd(sp_agg$exp) NA, so `if(!exp_varies)` in the
# fallback warning crashed -- fixed with isTRUE() (latent before: the linear branch never ran under the old
# constant default). 2 new tests (default is linear; default falls back to constant on thin data).
# devtools::test() 0 failures (423), devtools::check() 0/0/0, reinstalled to ~/Library/R/4.0/library. All 6
# workflow scripts parse cleanly. User still validating 12S posteriors -- adoption is in place, may revisit.
# Previous update, 2026-07-17 (Session 159, PtConception rollout -- Task 1 of
# ecosystem_docs/REENTRY_PROMPT_session159_regional_overlap_rollout.md. Wired
# check_regional_overlap=TRUE/sequence_col into both real PtConceptionWorkflow_12S/
# _18S_2_single_site.R scripts (outside this monorepo). Live-testing against the real
# cached 13,442-observation 12S checkpoint (pre-restoration match_obj/reference_df/
# seq_matrix/taxaexpect_priors/reads_long) confirmed the mechanism has a REAL effect,
# not a no-op -- 2,118 congener rows rejected on regional-overlap grounds across a
# random 2,000-observation sample, 33 restored as real overlapping congeners -- but also
# surfaced two more real .check_regional_overlap() performance bugs, found only by
# profiling real data with Rprof, not by review: (1) Tier 2b's query-vs-anchor
# alignment (deriving anchor_subject_range from query_sequence) depends only on
# (anchor_accession, query_sequence), never on which candidate is being checked, but
# restore_suppressed_candidates()'s vapply loop calls .check_regional_overlap() once
# PER CANDIDATE SPECIES for a given observation -- an observation with several
# congeners was redundantly re-running the identical alignment once per congener.
# Fixed with a new query::<anchor>::<query_sequence> align_cache key, same pattern as
# the existing (anchor,candidate) pair cache. (2) Far larger, found via Rprof after fix
# (1) barely moved the needle: Tier 1's "free" seq_matrix lookup re-stripped version
# suffixes off seq_matrix$id_x/id_y via sub() on EVERY SINGLE call -- with the real
# ~3,042,480-row seq_matrix this data uses, that alone was >90% of total wall time,
# an order of magnitude more than any real alignment cost. Fixed the same way: the
# stripped ids (and reference_df's stripped composite_id) are now cached under fixed
# keys in align_cache -- safe because align_cache is one environment per
# restore_suppressed_candidates() call, so reference_df/seq_matrix never change during
# its lifetime. Real, timed net effect: an anchor-clustered real 300-observation
# subset dropped from 84s to 6.8s (~12x); a real RANDOM (more representative)
# 2,000-observation subset ran in 153.5s, extrapolating to ~17 minutes for the full
# 13,442-observation dataset for this one function call alone (down from an estimated
# ~65 minutes pre-fix) -- not the full multi-hour production workflow, which includes
# many other expensive steps. 2 new regression tests added (test-score-collapse.R),
# each proving cache REUSE (not just population) by corrupting a pre-populated cached
# value under its exact key and confirming the corrupted value -- not a fresh
# recomputation -- drives the result. devtools::test() all passing (0 failures, same
# pre-existing warnings/skips), reinstalled to both the user (~/Library/R/4.0/library)
# and system R libraries. Both real workflow scripts parse cleanly
# (parse()-verified) but have NOT yet been run end-to-end in production (would
# overwrite real checkpoints and make real GBIF/NCBI/LLM API calls) -- left for the
# user to trigger. See [[project_regional_overlap_gap_modeling]] in the TaxaID memory
# system for the full record.
# Previous update, 2026-07-16 (Session 159, continued yet further -- three more real bugs found
# by actually running the fix against real Mugu data after telling the user it was done,
# each caught only because the user reported "still get Fundulus lima" and pushed for a
# real diagnosis rather than accepting a plausible-sounding fix. (1) restore_suppressed_
# candidates() never even reached its per-observation loop for real 12S BLAST data
# (score_range=8): detect_suppressed_candidates() correctly found NO global suppression
# pattern (real data is a genuine mix -- 240/401 true singletons, 161/401 real ties -- so
# no purity threshold clears its bar), so the function's original top-level gate
# (`if (!detected$rule_detected) return(match_obj)`) short-circuited before check_
# regional_overlap ever ran, for ANY observation, including ASV_300. Fixed: when
# check_regional_overlap = TRUE, target_obs = all_obs unconditionally, decoupled from the
# global rule verdict -- safe specifically because every addition is gated on real overlap
# evidence, not a fabricated score. (2) Once that gate was removed, a live run against the
# real 401-observation 12S dataset ran for 15+ minutes before being killed -- confirmed via
# `ps` it was genuinely CPU-bound, not stuck. Root cause: .check_regional_overlap()'s Tier 2
# alignment was recomputed once per OBSERVATION even when many observations shared the same
# anchor (401 observations reduced to only 71 distinct anchors; one anchor alone was reused
# 113 times). Fixed with a new align_cache environment (created once per restore_suppressed_
# candidates() call, threaded through every .check_regional_overlap() call), memoizing the
# (anchor, candidate) alignment result across the whole call -- the position-overlap decision
# itself stays a cheap per-observation comparison against the cached alignment. (3) Even with
# memoization, a real profiling pass found 2,361 distinct (anchor, candidate) pairs still
# needed genuine Tier 2 alignment (one real genus alone had 42 referenced congeners, each
# checked against every anchor sharing that genus) -- confirmed one real mitogenome-vs-
# mitogenome alignment alone takes ~2.7s, so total cost was still dominated by checking
# congeners with zero chance of being locally relevant. Fixed with a new candidate_species_
# filter param that restricts other_species to a caller-supplied plausibility list BEFORE any
# expensive work -- not a new judgment, just moving expand_unreferenced_hypotheses()'s own
# downstream taxaexpect_priors filter earlier so the expensive check never runs on a congener
# that gets discarded later anyway. Cut the real pair count to 416 (~6x) and real wall-clock
# time for one marker to 38 seconds (confirmed timed, not estimated). Wired into both Mugu
# workflows (candidate_species_filter = unique(taxaexpect_priors$taxon_name), already in
# scope at the restore_suppressed_candidates() call site in both). Full chain verified
# end-to-end against real saved data: ASV_300 now correctly carries TWO real hypotheses
# (Fundulus lima specific_candidate likelihood=1.0; Fundulus parvipinnis unreferenced_species
# likelihood=0.173) instead of F. lima alone with posterior=1.0 by default. devtools::test()
# 768/768 (up from 754), devtools::check() 0/0/0. Installed to BOTH the user library
# (~/Library/R/4.0/library) and the system library (/Library/Frameworks/.../Resources/
# library) this round, after discovering (mid-session) that the user's own RStudio session
# for the Mugu scripts -- which live outside the TaxaID project entirely -- may resolve
# either one depending on project/.Rprofile context, and a prior single-library reinstall
# had left a stale copy silently in play for a full ~2-hour production run. See the
# "continued once more"/"continued further" notes below for the earlier rounds in this same
# thread (search-term fix, keep_out_of_range, the regional-overlap mechanism itself, the
# size-bound fix, and the original named-species extension).
# Previous update, 2026-07-16 (Session 159, final entries -- two more fixes in the same
# real Mugu Fundulus lima/parvipinnis debugging thread. (1) fetch_ncbi_reference_
# sequences(keep_out_of_range = TRUE) had no upper size bound at all -- found via direct
# inspection of the real Mugu reference_df.rds (142MB, one genus pulling in a 111,213,091bp
# whole-genome/chromosome scaffold, not a mitogenome) after the user ran the real workflow
# and reported the outcome hadn't changed. Fixed with a new max_out_of_range_len = 200000L
# param (animal mitogenomes ~15-20kb, plant chloroplast genomes ~120-160kb, so 200kb keeps
# real organelle genomes while excluding genome/scaffold-scale sequences), folded into both
# length-filter locations and the cache key (which also didn't previously vary by
# keep_out_of_range at all -- a real staleness bug fixed the same session). (2) Diagnosed
# (via direct inspection of the real lik_result_12s.rds/consensus_final.rds) that the
# check_regional_overlap fix WAS working correctly -- F. parvipinnis was being correctly
# rejected/preserved per-observation exactly as designed -- but the real assignment outcome
# for ASV_300/328/329/354/433 still didn't change, because a regionally-rejected congener
# was simply OMITTED from the candidate set rather than becoming a real competing
# hypothesis, so F. lima won by default with posterior=1.0 whenever it was the only named
# species-level candidate left. This was exactly the "Current scope limit, not yet built"
# the prior Session 159 entries had already flagged. Built the extension:
# restore_suppressed_candidates() no longer silently drops a regionally-rejected congener --
# it now records it (observation_id/species/genus/family) and returns it via
# attr(result, "regional_unreferenced"). expand_unreferenced_hypotheses()'s unreferenced_df
# gained an optional observation_id column (NA/absent = applies to every observation
# sharing that genus/family, the original global behavior unchanged; a real observation_id
# restricts that row to just one observation) -- exactly the shape needed to let a
# GLOBALLY-referenced species (F. parvipinnis has a real NCBI accession, so it would never
# appear in a normal audit_barcode_coverage()-derived unreferenced_df) still compete as a
# named unreferenced_species hypothesis for the one specific query whose anchor doesn't
# overlap its reference, while remaining an ordinary specific_candidate everywhere else.
# Deliberately reuses expand_unreferenced_hypotheses()'s existing, already-tested
# expansion/suppression machinery rather than building a parallel mechanism -- the shared
# H2/H3 likelihood value it already copies onto every expanded species is reused unmodified.
# Wired into MuguFishWorkflow.R: .build_scored_likelihoods() captures
# attr(match_restored, "regional_unreferenced") immediately after restore_suppressed_
# candidates() runs (before the dplyr::left_join() reassignment that follows, which does
# not preserve custom attributes) and returns it; .run_round1() folds it into
# unreferenced_df, through the SAME taxaexpect_priors/inat_confirmed plausibility filter
# already applied to the global list, before calling expand_unreferenced_hypotheses().
# MuguWilderFishWorkflow.R was NOT wired the same way -- its own Step 8 header comment
# states no coverage audit or species-level unreferenced expansion happens there at all
# ("H2/H3 generic rows... serve as the unreferenced-species/genus hypotheses" directly,
# unexpanded), which appears to predate this session and looks stale (that workflow's
# restore_suppressed_candidates(check_regional_overlap = TRUE) call already requires and
# presumably has a real accession column, contradicting its own "no BLAST accessions"
# comment) -- flagged for the user to decide on, not changed unilaterally, since adding
# species-level expansion there is a real architecture change beyond this session's scope.
# devtools::test() 754/754 (up from 706), devtools::check() 0/0/0 throughout.
# Previous update, 2026-07-16 (Session 159 continued once more -- restore_suppressed_
# candidates()'s regional-overlap check gains Tier 2b, a query-vs-reference fallback for
# match objects with NO live BLAST step at all. Prompted directly by the user asking how
# the Mugu fix (Tier 2a, needs TaxaMatch::blast_sequences()'s subject_start/subject_end)
# applies to this ecosystem's PtConception 12S/18S workflows -- checked and confirmed those
# workflows build match_obj from an EXTERNALLY pre-computed match table (PercMatch/
# Accession columns from an outside wet-lab pipeline) that never runs through
# blast_sequences() at all, so no BLAST alignment coordinates exist anywhere for them.
# The ESV file itself also has no sequence column -- but the READ file (already loaded for
# contaminant detection in Step 2 of those workflows) does carry a real per-ESV sequence
# column, confirming the raw query DNA is available, just not currently wired to Step 7.
#
# New `sequence_col = NULL` param + new `query_sequence` param on the internal
# `.check_regional_overlap()`: when Tier 2a's coordinates aren't available for an
# observation but a raw query sequence is (via `sequence_col`), the anchor's own hit
# position is now derived ON THE FLY -- a local pairwise alignment of the query sequence
# against the anchor's own reference sequence (both already in memory, `reference_df`
# already has the anchor's sequence when `keep_out_of_range = TRUE` was used to fetch it;
# no NCBI call needed) -- then the SAME candidate-position-overlap logic as Tier 2a runs
# on the derived range. This is a genuinely more general mechanism than Tier 2a, not just a
# workaround: it doesn't depend on whether match_obj ever went through a live BLAST run.
# Tier 2a is still tried first when both are available (cheaper, no extra alignment needed
# to establish the anchor's own position); leaving `sequence_col = NULL` (the default)
# means only Tier 1/2a run, per the user's explicit request that Tier-1-only stays the safe
# default when neither input is supplied. Live-validated against the EXACT real Fundulus
# case with zero subject_start/subject_end supplied at all -- correctly derives the query's
# real position (515-613, matching the value independently confirmed via manual alignment
# in the earlier Tier 2a work) and correctly rejects F. parvipinnis, same verdict as Tier
# 2a produced with the coordinates supplied directly. 5 new tests (Tier 2b accept/reject/
# Tier-2a-preferred-when-both-available unit tests using the same synthetic two-region
# fixture, plus a `sequence_col`-driven `restore_suppressed_candidates()` integration test).
# `devtools::test()` 734/734 (up from 729), `devtools::check()` 0 errors/0 warnings (1
# pre-existing environmental NOTE, timestamp verification, unrelated).
#
# Real installation-path bug found and fixed the same session, separate from the code
# itself: `devtools::install()` run via a bare `Rscript` from inside a package's own
# subdirectory (not the TaxaID project root) had been silently landing in the SYSTEM
# DEFAULT R library, not `~/Library/R/4.0/library` (the path the user's real RStudio
# session actually uses, wired in only by the TaxaID project's own `.Rprofile`) -- meaning
# every earlier "reinstall" this session had NOT actually been visible to the user's live
# RStudio session at all. Confirmed and fixed by explicitly setting `.libPaths()` from
# `R_LIBS_USER` before calling `devtools::install()`; both TaxaLikely and TaxaMatch
# re-verified installed at the correct path via `find.package()` after. See `TaxaID/
# CLAUDE.md`'s Developer Environment table for the corrected, detailed record -- the
# previous documentation there was itself wrong about `Rscript` picking this up
# automatically, and has been corrected too. Always verify any Rscript-driven install with
# `find.package()` before trusting it landed in the right place.
# Previous update, same day (Session 159 continued further -- regional-overlap check for
# restore_suppressed_candidates(), closing out the real Fundulus (Mugu) misassignment
# investigation this session's earlier .build_search_term() fix (below) started. Root
# problem, precisely: restore_suppressed_candidates() adds every same-genus congener found
# in reference_df as a competing specific_candidate, assuming any same-genus reference is
# automatically a valid competitor -- wrong whenever the query's own real BLAST hit only
# overlaps a congener's reference (e.g. a complete mitogenome) at a genomic position a
# DIFFERENT congener's own reference sequence doesn't actually cover, even though that
# second congener has SOME reference elsewhere in the marker. Confirmed on real data: the
# real ASV's BLAST anchor (F. lima's mitogenome, NC_063692) hit at position 515-613; F.
# parvipinnis's own real, correctly-sized 12S reference (OQ846298, now recoverable via this
# session's earlier search-term fix) aligns to that SAME mitogenome at position 319-486 --
# genuinely non-overlapping, so F. parvipinnis was never really a competing hypothesis for
# this specific query, even though it IS validly referenced for other queries hitting the
# real MiFish window.
#
# Fix: new `check_regional_overlap` param on restore_suppressed_candidates() (default
# FALSE, fully backward compatible) skips restoring a congener unless there's real evidence
# its reference overlaps the SAME position the query's own anchor hit, not just that it has
# some reference somewhere. New internal `.check_regional_overlap()` (R/regional_overlap.R)
# implements this via two tiers, both entirely reference-vs-reference -- NEITHER needs the
# query's own raw DNA sequence, since transitivity (query aligns well to anchor, already
# established by BLAST; does candidate's reference overlap the SAME anchor position?)
# substitutes for it:
#   Tier 1 (free): a lookup against `seq_matrix` (already computed once per genus by
#     build_sequence_matrix() at TRAINING time, not per query) for an existing pairwise
#     `coverage` value between the anchor accession and the candidate's accessions. Safe to
#     treat "any overlap" as sufficient here (no position check needed) because
#     build_sequence_matrix() only ever includes properly-sized sequences -- never a whole
#     genome -- so a seq_matrix anchor can't have the "trivially contains every position"
#     problem below.
#   Tier 2 (fallback, only reached when the anchor itself isn't in seq_matrix -- e.g. it's a
#     mitogenome excluded from training): a fresh local pairwise alignment directly against
#     reference_df's own sequence content, no new NCBI fetch needed.
#
# Real design flaw found and fixed BEFORE landing, by testing the first Tier 2 draft
# against the actual motivating case rather than assuming it worked: an initial version
# checked only "does the candidate align anywhere in the anchor's full sequence," which is
# nearly always true once the anchor is a whole genome (it necessarily contains every
# sub-region of the gene, including the real MiFish window AND wherever this specific query
# happened to hit) -- confirmed directly: F. parvipinnis's OQ846298 DOES align well to F.
# lima's mitogenome (at 319-486), so the naive check wrongly returned TRUE for the exact
# case it needed to reject. Real fix required knowing WHERE within the anchor the query
# itself hit -- which nothing in the pipeline retained anywhere (see TaxaMatch/CLAUDE.md's
# same-session note: `Hsp_hit-from`/`Hsp_hit-to`, BLAST's own subject-side alignment
# coordinates, were computed by BLAST and then silently discarded by
# TaxaMatch::blast_sequences()'s XML parser). Tier 2 now REQUIRES
# `anchor_subject_range` (from match_obj's new `subject_start`/`subject_end` columns,
# TaxaMatch Session 159) and only accepts a candidate whose OWN fresh alignment against the
# anchor lands at a position overlapping that range -- verified against the exact real
# numbers (region [319,486] vs [515,613]) before writing a single test.
#
# New `keep_out_of_range`/`max_out_of_range_per_species` params on
# fetch_ncbi_reference_sequences() (this session's earlier work, see below) are what make
# Tier 2 possible at all for a mitogenome-anchored query without a separate on-demand NCBI
# fetch -- reference_df now retains a capped number of out-of-range sequences per species
# (new `in_barcode_range` diagnostic column) specifically so this check has real sequence
# content to align against, already in memory.
#
# Scope limit, explicit, not solved this session: a congener that fails the check is
# currently just OMITTED from restoration, not converted into a NAMED
# "unreferenced_species" hypothesis that evaluate_likelihoods() could still score via the
# borrowed-likelihood (H2) mechanism -- that would need generalizing H2's currently-generic,
# one-per-query anchoring to support multiple named unreferenced congeners per query, a
# separate, larger design question flagged for later.
#
# 13 new tests (test-score-collapse.R): .check_regional_overlap() unit tests using a
# synthetic two-region "genome" fixture (deterministic local-alignment behavior, no network
# dependency) covering both the accept and reject cases plus NA fallbacks; integration tests
# for restore_suppressed_candidates(check_regional_overlap = TRUE)'s validation errors,
# skip-on-no-overlap, restore-on-real-overlap, and confirmed-unaffected default (FALSE)
# behavior. `devtools::test()` 729/729 (up from 706 earlier this session), `devtools::check()`
# 0 errors/0 warnings/0 notes. Live-validated against the exact real Fundulus numbers
# (region overlap correctly rejects [319,486] vs [515,613], correctly accepts an overlapping
# range) before the unit tests were written, not just after.
# Previous update, same day (Session 159 continued -- .build_search_term()'s bare-marker-
# name search fixed for 12S/16S, found while debugging a real Mugu workflow misassignment
# (Fundulus parvipinnis vs F. lima). Root cause confirmed directly against live NCBI:
# barcode_term = "12S"/"16S" have no [GENE] field tag entry and no primer_to_locus entry,
# so they fell through to a bare "12S[All Fields]"/"16S[All Fields]" text search -- which
# is unreliable, since whether a real, correctly-annotated, correctly-sized reference
# sequence is found depends on incidental bibliographic metadata (does the record's OWN
# linked citation happen to contain the literal string "12S"?), not the sequence's actual
# content. Confirmed with a real pair: OQ846298 (F. parvipinnis, /product="small subunit
# ribosomal RNA", 168bp, real MiFish-primer-amplified) matched ZERO results for
# "12S[All Fields]" alone; a near-identical F. grandis record (OP537863, same /product
# text) WAS found, only because its own citation was titled "12S barcoding of Texas
# fishes" -- confirmed by comparing full GenBank flat files side by side, not guessed.
# Fixed: new marker_synonyms list ORs in "12S/16S ribosomal RNA"/"12S/16S rRNA"/"small/
# large subunit ribosomal RNA" (the standard, unambiguous SSU/LSU rRNA synonym convention
# for mitochondrial 12S/16S specifically) alongside the bare marker-name clause, live-
# verified to recover OQ846298 for F. parvipinnis. Deliberately NOT extended to 18S:
# "small subunit ribosomal RNA" is ambiguous between mitochondrial 12S and NUCLEAR 18S,
# so reusing it there would trade missed true positives for new false positives -- a
# different tradeoff needing its own design. COI/cytb/ITS/rbcL/matK/trnL untouched --
# already use the more precise [GENE] field-tag path, a different (and more reliable)
# mechanism than free-text [All Fields], not affected by this gap. 10 new regression
# tests (test-fetch.R): the synonym OR-clauses for 12S/16S, the deliberate 18S exclusion,
# and exact-string checks confirming COI/primer-name paths are unchanged.
# `devtools::test()` 706/706 unchanged pass count structure (was already 696 before this
# session's other fix; +10 here), `devtools::check()` 0 errors/0 warnings/0 notes.
# IMPORTANT OPERATIONAL NOTE: `fetch_ncbi_reference_sequences()`'s own `cache_dir` caches
# per-genus NCBI results keyed by taxon+barcode_term STRING+length+date -- NOT by the
# actual constructed search-query text -- so this fix does NOT take effect on a re-run
# until those cache files are cleared (barcode_term itself, e.g. "12S", never changes).
# Confirmed and cleared for the real Mugu case: 122 of 147 files under
# ~/My Drive/Rscripts/eDNA/SepulvedaMugu/cache_reference/ (75 for 12S, 47 for 16S; the 25
# COI files are unaffected and were left alone). Anyone else relying on a cached
# `fetch_ncbi_reference_sequences(barcode_term = "12S"/"16S", ...)` result from before
# this session needs the same cache-clearing step, or the fix will be silently bypassed.
# Previous update, same day (Session 158 continued -- correction to the same session's
# own note below: `calibrate_query_noise()`/`evidence_col`/`min_coverage` are NOT
# permanently guarded against `score_transform = "sqrt_mismatch"` models. That framing
# was wrong, found the moment the user tried to actually use it: testing
# `sqrt_mismatch` against the real production workflow
# (`PtConceptionWorkflow_12S_single_site.R`, which calls both `calibrate_query_noise()`
# and `evaluate_likelihoods(evidence_col=)`) immediately reproduced the exact symptom
# calibration is supposed to fix -- unreferenced Sardinops congeners at likelihood 1.0
# outscoring the correct referenced species -- because the guards below simply blocked
# calibration from running at all on a `sqrt_mismatch` model, not because the mechanism
# is unsafe on that scale. Re-derived via the delta method whether the guards' implicit
# premise (that `SE(transform(score)) propto 1/sqrt(N)` needs logit specifically) was
# ever true: it isn't -- for any transform `f`, `Var(f(p_hat)) ~= [f'(p)]^2 *
# Var(p_hat)`, and `Var(p_hat) ~ 1/N` regardless of `f`, so the `1/sqrt(N)` scaling
# holds for `sqrt_mismatch` too (confirmed numerically: the ratio of the two
# transforms' SE formulas is exactly constant across `N`). Fixed properly rather than
# just removed: `calibrate_query_noise()`'s one genuinely hardcoded logit line now uses
# `.transform_p()` (its verbose message uses the new `.untransform_p()` helper instead
# of a hardcoded `plogis()`); `evaluate_likelihoods()`'s `stop()` guard on
# `evidence_col`/`min_coverage` is removed and replaced with a comment recording the
# corrected reasoning (`min_coverage`'s coverage-sigma-inflation remains an
# unconditional widen either way -- a separate, pre-existing, already-documented
# limitation, unrelated to this correction). The two `test-evaluate.R` blocks
# asserting the old guards fire were rewritten to assert the mechanisms work with no
# error on a `sqrt_mismatch` model instead; `test-calibrate_query_noise.R` similarly
# rewritten from "guard fires" to "calibration works and produces scale-appropriate
# offsets for both scales" (including an exact numeric check of the `sqrt_mismatch`
# offset). `devtools::test()` 698/698 (up from 696), `devtools::check()` 0 errors/0
# warnings (1 pre-existing environmental note). Package reinstalled. See
# [[project_job2_unreferenced_relatives]]'s "Correction (2026-07-16)" section in the
# TaxaID memory system for the full record -- treat that section, and this note, as
# superseding the "deliberately NOT ported this session" language in the Session 158
# note immediately below wherever the two disagree.
# Previous update, 2026-07-15 (Session 158 -- "Job 2": modeling unreferenced-relative
# (H2/H3) likelihoods, the second of the two jobs identified in Session 155
# ([[project_bayesian_likelihood_calibration_2026_07]]) as separate design problems.
# Started from a real observation the user flagged in real posterior output: three
# named unreferenced Sardinops congeners all received the IDENTICAL likelihood
# (0.566) -- correct in principle (a query score can't discriminate between species
# with zero reference data), but the user's stated hunch was that the pooled H2/H3
# machinery itself should still behave sensibly: unreferenced species should track
# how well the REFERENCED relative matched (a surprisingly good/bad reference match
# should propagate), and a genus where species are hard to tell apart (small,
# consistent divergence) should differ systematically from one where they're easy to
# tell apart (larger, more variable divergence) -- with the LATTER, not the former,
# carrying more uncertainty.
#
# Two real, confirmed problems found by testing this intuition against real 12S
# congener data, both fixed:
#
# (1) H2's mean anchored on the population-wide H1_Global_Mu, not the specific
# referenced anchor species' own resolved mean -- so a species whose own trained
# mean sits above or below average never passed that information to its own
# unreferenced relatives' likelihood. Fixed: H2/H3 mean is now
# `used_mu1[best_i] - delta`, the anchor candidate's own resolved species mean
# (falls back to global mean when no species-specific entry exists, same as
# before). Small effect size in isolation (~4.5% on the motivating case) but
# directly addresses the user's stated intuition and costs nothing extra.
#
# (2) The bigger one: testing "should a tight genus's H2 differ from a loose
# genus's H2" against real congener data (Sardinops, tight, mean congener
# similarity 99.9%, real raw variance ~0; vs Symphurus, loose, mean 90.5%, real
# variance meaningfully larger) found the CURRENT model gets this qualitatively
# BACKWARDS: at the same real 99.4% match, logit gave Symphurus (loose) a HIGHER
# H2/H1 ratio (2.79) than Sardinops (tight, 2.80 -- indistinguishable), when the
# loose genus should show LOWER H2 competitiveness at a great match (congeners
# there don't normally score that high) and the tight genus should show HIGHER
# (its congeners routinely score just as well). Root-caused to the score
# transform itself, not the genus-shrinkage logic: on the RAW match-proportion
# scale, tight genera genuinely do show lower congener-score variance (Pearson
# r = -0.55 across 87 real genera, robust to controlling for sample size), but
# under logit this reverses sign (r = +0.47) because nearly all real barcode
# matches sit within a few points of 100% identity, exactly where logit's
# derivative (`1/(p(1-p))`) diverges fastest -- a small, real raw-scale
# imprecision near the ceiling gets mechanically inflated into a large logit-scale
# variance. Checked probit (worse, fastest-diverging of all) and complementary
# log-log (flattest in absolute terms but same wrong sign) before landing on
# `sqrt_mismatch` (`-sqrt(1-p)`, Anscombe's classical rare-event-count
# stabilizer -- real data lives in the "few mismatches out of many aligned
# bases" regime, for which square-root is the textbook transform): recovers the
# correct sign (r = -0.25, weaker than raw but correctly signed and monotonic
# across similarity quartiles) and, critically, reproduces the correct
# DIRECTION on real held-out cases -- Sardinops H2/H1 = 1.68 (competitive, as a
# tight genus should be) vs Symphurus H2/H1 = 0.65 (H1 clearly wins, as a loose
# genus should show), via the actual package functions, not just aggregate
# statistics.
#
# Implementation: new `score_transform` param on `train_likelihood_model()`
# (`"logit"` default, `"sqrt_mismatch"` new), stored in `model_params$Score_
# Transform` and read automatically by `evaluate_likelihoods()` -- H1/H2/H3 MUST
# share one transform, since they're compared via density ratios at one shared
# point (mixing transforms across hypotheses would need an explicit change-of-
# variables/Jacobian correction that was deliberately not built, in favor of
# moving H1's own core fitting onto the new scale too when `sqrt_mismatch` is
# selected -- a user design decision made explicitly, not assumed). New
# `H2_Lookup$var_shrunk` column: genus-specific H2 variance, shrunk toward a
# properly-sourced (congener-only, not the old cross-any-genus) pooled default
# with the identical `w = n/(n+prior_weight)` form already used for the delta.
# Several small "logit-unit" magic numbers (H1-H2 minimum separation, H2 variance
# floor, `min_observed_sigma`'s default, `max_gap_ceiling`'s default, the
# perfect-match anchor value, the noise floor) are now resolved per-transform via
# new shared helpers in `R/transform.R` rather than hardcoded. Satellite
# mechanisms that assume logit specifically (`calibrate_query_noise()`,
# `evidence_col`, `min_coverage`'s sigma inflation) now error clearly rather than
# silently misapply on a `sqrt_mismatch`-trained model -- deliberately NOT ported
# this session, flagged as explicit follow-up.
#
# A third, larger, unrelated bug was found and fixed along the way, at the
# user's explicit request to fix it before continuing: `train_likelihood_model()`'s
# per-species `shrunk_sigma` took an extra `sqrt()` of the already-shrunk variance
# before storing it in `H1_Lookup$sigma_score` -- a slot every downstream consumer
# (the species floor comparison against `H1_Sigma`, a true covariance matrix; the
# outlier chi-squared test; `dnorm(sd = sqrt(...))`; `dmvnorm(sigma = ...)`) treats
# as a variance, applying its own sqrt() (or using it directly as a covariance
# diagonal entry) on top. Net effect, confirmed by hand-reproducing the real
# training data: species-specific H1 candidates have been evaluated against the
# FOURTH root of the intended variance, not the square root -- systematically
# overconfident (too-narrow H1) for as long as this formula has existed, on BOTH
# transforms. Invisible on logit (shrunk variances ~1.5-2.5, where the extra sqrt
# is a "only" ~15-25% correction) until sqrt_mismatch's much smaller natural scale
# (~0.01-0.1) made the same bug a 3-6x distortion, impossible to miss once
# cross-checked against a hand computation. Fixed by removing the extra sqrt();
# `H1_Lookup$sigma_score` (and, automatically, `calibrate_query_noise()`'s own
# `calibrate_sigma` rescaling, which multiplies `sigma_score` by a proper variance
# ratio and was ALSO silently inheriting this unit mismatch) are now true
# variances throughout. All 681 pre-existing tests passed unchanged after this
# fix (none pinned an exact `sigma_score` value), and a new regression test
# hand-reproduces the corrected formula exactly against real training data.
#
# Verified at each stage, not just at the end: `devtools::test()` 696/696 (up from
# 670 at session start), `devtools::check()` 0 errors/0 warnings/0 notes
# throughout every intermediate commit-equivalent state. Real-data validation via
# the actual package functions (not the exploratory hand-reproduction scripts used
# to find and confirm the sign-reversal problem) on the real 12S PtConception
# `seq_matrix`: Sardinops/Symphurus H2/H1 ratios reproduce the expected direction
# under `sqrt_mismatch` and fail to discriminate under `logit`, both before and
# after the sigma fix (numbers changed, qualitative story held both times).
#
# Not done this session, explicitly flagged as follow-up: porting
# `calibrate_query_noise()`/`evidence_col`/`min_coverage` to `sqrt_mismatch`;
# re-deriving the outlier alpha test's specific threshold for the new scale
# (the FORM of the test is scale-invariant and needs no change, but `alpha =
# 0.001`'s own calibration was tuned on real logit-scale data, not re-validated
# here); rolling `score_transform = "sqrt_mismatch"` out to any production
# workflow (still opt-in, `"logit"` remains the default); H3's own sigma is
# still pooled, not genus-specific (would need family-level congener data,
# same limitation as before this session). See
# [[project_job2_unreferenced_relatives]] in the TaxaID memory system for the
# full empirical derivation and design-discussion record.
# Previous update, 2026-07-14 (Session 157 -- redesigned what score_likelihood_mean/
# score_likelihood_sd actually represent, prompted by the user stepping back from the
# evidence_col/depth work to ask a more fundamental question: what should the "error around"
# a likelihood estimate even mean, and does the current n_sims mechanism compute that?
# Traced the existing mechanism precisely: it resampled the QUERY'S OBSERVED score around the
# global H1 population dispersion (model_sd_score) -- answering "how sensitive is this
# density to where the query happens to land," not "how confidently do we know this
# candidate's trained mean." It also never touched evidence_vec at all, so score_likelihood_sd
# carried zero information about per-observation evidence quality regardless of the Session
# 155/156 mechanism. User's explicit framing: focus on a good likelihood estimate (mean +
# uncertainty) for referenced AND unreferenced candidates; don't chase per-query evidence
# quality unless it's justified and cheap; keep compute minimal.
#
# Redesign: score_likelihood_sd now represents uncertainty in the TRAINED MEAN itself, driven
# by how much reference data calibrated it -- Var(mean) ~= sigma^2/n, the standard
# uncertainty-in-an-estimated-mean result. `train_likelihood_model()` already computed
# `n_obs_species` (reference sequences per species) to do Empirical Bayes shrinkage, then
# discarded it before it reached `H1_Lookup` -- now retained. Each Monte Carlo draw perturbs
# the CANDIDATE'S TRAINED MEAN (not the observed score) by this uncertainty and evaluates the
# query's real, fixed observed point against it; H2/H3 get the identical treatment using
# `n_pairs` behind their genus-specific delta (already tracked in `H2_Lookup`) or the fully-
# pooled foreign-match count when no genus-specific delta exists (new `Stats$n_h2_pooled`) --
# so borrowed/unreferenced likelihoods correctly get MORE uncertainty than directly-observed
# ones, satisfying the user's third ask ("add variance for unreferenced taxa") for free.
# Mechanically this REDIRECTS the existing n_sims loop rather than adding to it -- same
# n_sims x n_candidates cost as before, just perturbing the right random variable -- and reuses
# `primary_evidence`'s already-resolved per-candidate sigma (species floor + evidence gate) as
# the basis, so the Session 155/156 evidence mechanism's contribution to uncertainty falls out
# automatically at zero extra cost, resolving the user's "should I care about evidence"
# question without building anything evidence-specific. Fully backward compatible: falls back
# to the exact previous (query-resampling) behavior when `model_params$H1_Lookup` lacks
# `n_obs_species` (i.e., any model trained before this change).
#
# No new output columns and no changes needed in TaxaAssign: `compute_posterior()` already
# consumes `score_likelihood_mean`/`score_likelihood_sd` for its own Beta-prior Monte Carlo, so
# a correctly-motivated likelihood uncertainty now flows straight into posterior uncertainty.
#
# Verified three ways before calling this done: (1) two synthetic regression tests confirm a
# poorly-referenced species (n=3) gets a larger sd than a well-referenced one (n=300) for
# identical observed data, and a genus-specific H2 delta backed by 2 congener pairs gets a
# larger sd than one backed by 500, both holding everything else fixed; (2) a third test
# confirms the legacy fallback still fires (non-zero sd from the old mechanism) when
# `n_obs_species` is absent; (3) real-data check: retrained on the real 12S seq_matrix
# (n_obs_species ranges 2-10, Stats$n_h1_pooled/n_h2_pooled = 2294), ran evaluate_likelihoods()
# on 300 real observations at n_sims=200 (11.2s -- extrapolates to ~8 min for the full 13,442,
# comparable to before), and confirmed the intended shape held: median H1 sd 0.075 vs. median
# H2/H3 sd 0.119 (unreferenced hypotheses genuinely wider), Sardinops still resolves cleanly.
# `devtools::test()` 674/674 (up from 670), `devtools::check()` 0/0/0.
#
# Deliberately NOT done, per the user's explicit steer: no separate evidence-specific
# uncertainty channel; no Student-t/heavier-tailed density family (the earlier, bigger reframe
# considered and set aside as unnecessary complexity for what was actually being asked); no
# change to score_likelihood_cov's identical, still-unaddressed pre-existing gap (it was never
# reflected in score_likelihood_mean/sd either, before or after this change -- out of scope,
# not touched). See TaxaID's memory system for the fuller design-discussion record.
#
# Live-testing correction, same day: the user ran the actual PtConceptionWorkflow_12S_single_
# site.R end to end and got a real result that contradicted the design intent --
# score_likelihood_sd came out large and roughly FLAT across H1/H2/H3 (medians 0.265 vs 0.241,
# H2/H3 NOT reliably wider), instead of the tighter/H2-H3-wider pattern the small 300-
# observation spot check above had shown. Root-caused to two real issues, both now fixed:
# (1) H1's naive sigma^2/n treated each species' mean as if estimated purely from its own
# n_obs_species observations, ignoring that the shrinkage estimator ALREADY blended it with the
# well-known global mean -- with real n_obs_species mostly 2-3 in this database, naive sigma^2/n
# gave implausibly large mean-SD (median ~0.76 logit units). Per the user's explicit direction
# ("shrinkage should reduce the uncertainty"), the formula is now shrinkage-consistent:
# Var(mean) = w^2 * sigma^2/n, where w = n/(n+prior_weight) is the SAME weight already used for
# the point estimate -- recovers the naive SE as n grows, correctly shrinks toward near-zero as
# n -> 0 (since at that limit the estimate IS almost entirely the well-known global mean).
# (2) The pooled-fallback case (a candidate/genus with NO local reference/congener data at all)
# was using the TRUE pooled training count (Stats$n_h1_pooled/n_h2_pooled, in the thousands) as
# its "n" -- meaning a genus with zero congener data looked MORE confidently known than one with
# substantial (but imperfect) local data, exactly backwards. Confirmed directly on real numbers:
# a genus with 1 congener pair had implied delta-SD 3.09; the POOLED FALLBACK (n=2294) had
# implied SD only 0.065 -- 47x too confident. Fixed: the fallback case now uses `prior_weight`
# (this codebase's own "equivalent sample size of the prior," already used identically for the
# shrinkage weight) instead of the true pooled count. New Stats$prior_weight field added
# (train_likelihood_model()'s own prior_weight argument, retained for this purpose;
# n_h1_pooled/n_h2_pooled kept as informational diagnostics only, no longer used as an
# uncertainty fallback). Re-verified on the same real 300-observation subsample after both
# fixes: H1 median sd 0.265 -> 0.064; H2/H3 median sd 0.241 -> 0.073 (meaningfully wider than
# H1 again, as intended). Confirmed a second time by the user on the FULL real 13,442-
# observation dataset (not just the 300-observation subsample), after a false alarm along the
# way (their live session had loaded the package before reinstall, and lik_model itself was
# stale/pre-fix -- retraining, not just restarting R, was required): H1 median sd 0.065 (mean
# 0.068), H2/H3 median sd 0.070 (mean 0.098, max 0.422 vs H1's 0.343) -- H2/H3 meaningfully
# wider than H1, especially in the tail, at full real scale. One existing synthetic test needed
# correcting alongside this (not a
# fixture bug from the formula change, a pre-existing structural blind spot in the test itself):
# a dominant winner (score 95 vs 80/60) wins every simulation regardless of how its mean is
# perturbed, so its normalized ratio is pinned at exactly 1.0 (sd=0) in every scenario --
# rewritten with a close two-candidate competition (90 vs 88) so the winner can actually flip
# between simulations, which is what exposes the underlying mean-uncertainty difference in the
# normalized output; verified stable in the same direction across 5 independent seeds before
# committing to one. `devtools::test()` 674/674, `devtools::check()` 0 errors/0 warnings (1
# pre-existing environmental NOTE, timestamp verification, unrelated).
# Previous update, 2026-07-14 (Session 156 -- evaluate_likelihoods()'s evidence_col sigma
# rescale (Session 155) is no longer unconditional: a closed-form crossover gate now
# decides, per candidate, whether the rescale can help before applying it, replacing the
# uncapped-then-capped-but-still-net-negative version from the prior session (27 helped,
# 2053 hurt on real 12S data even at the widen-only default -- see
# [[project_evidence_ratio_sigma_reentry]]). Root cause worked out algebraically rather
# than patched empirically: for a Gaussian, rescaling variance by a factor c changes
# log-density at z standard deviations from the mean by exactly
# -0.5*log(c) + 0.5*z^2*(1-1/c) -- because a Gaussian must integrate to 1, widening (c>1)
# necessarily lowers the peak while raising the tails, so it only pays off once z is large
# enough; verified numerically against a live dnorm() call before writing any production
# code (delta formula matched log(dnorm_wide/dnorm_orig) to machine precision). Since most
# low-evidence real observations are still close-to-mean, decent matches (small z), the
# prior unconditional version paid the peak-lowering cost almost everywhere for a benefit
# that only exists in the tail -- exactly the empirical pattern found. Fix: compute this
# delta directly (not a pre-solved z* comparison) and only apply the rescale when
# delta > 0 -- a single formula that correctly handles both the widen (evidence_ratio < 1)
# and, for free, the tighten (evidence_ratio > 1, reachable only via a non-default
# evidence_max_ratio) directions, since the earlier tighten path had no protection at all.
# For multi-candidate queries the gate uses the score-only marginal z (only sigma_score is
# ever rescaled; gap variance/covariance are untouched) -- deliberately consistent with the
# existing score-only Mahalanobis outlier test's own precedent (same documented reasoning:
# gap should inform relative weighting, not admissibility) rather than deriving a new,
# unvalidated 2D crossover. For singleton (1D) queries, where the density evaluated really
# is this exact univariate form, the gate is exact, not an approximation. Two new
# regression tests confirm the gate blocks the rescale for a near-mean low-evidence
# candidate and allows it for a far low-evidence candidate, using hand-verified z^2 vs z*^2
# arithmetic against the actual model fixture. `devtools::test()` 670/670 (up from 667),
# `devtools::check()` 0/0/0.
#
# Re-validated same session against the real 12S PtConception dataset (reconstructed
# match_obj_restored from the saved match_obj/reference_df checkpoints, real per-ESV read
# depth summed from reads_long, calibrate_query_noise(evidence_col=) run fresh to get an
# internally-consistent offset + reference_evidence baseline in one pass): **163 helped, 3
# hurt** across 24,857 real H1 rows (vs. the unconditional version's 27 helped/2053 hurt --
# a ~54:1 reversal). Mean H1 relative likelihood 0.8014 -> 0.8016 (flat-to-slightly-positive,
# vs. the old version's real regression 0.899 -> 0.884). H1 win rate unchanged at 77.5%
# (expected: only 166/24,857 rows moved at all, none enough to flip a winner already
# resolved by Session 155's mean fix). Sardinops still resolves correctly (1.0 both ways).
# Traced all 3 hurt cases directly rather than waving them off: each sits right at the
# gate's own decision boundary, where the documented score-only-marginal approximation (see
# evaluate_likelihoods()'s own @details) has its known, deliberate blind spot -- the marginal
# gate predicted a barely-positive delta (e.g. +0.0026 for one real case) while the TRUE
# joint bivariate density (accounting for the real score/gap covariance term the marginal
# ignores) actually decreased (log-delta -0.037), confirmed by direct `mvtnorm::dmvnorm`
# computation on the real mu/sigma/point. Bounded and small in practice: max swing across
# all 3 cases was 0.009 (under 1% of the score range). This is the cost of the approximation
# working as expected, not a new bug -- an exact 2D crossover would close it but was
# deliberately not attempted (bigger derivation for a correctness gain this real data shows
# is already tiny). `score_likelihood_evidence` is now empirically validated as a real net
# improvement on this dataset, not just theoretically safer. **Wired into
# `PtConceptionWorkflow_12S_single_site.R`** (outside this monorepo, not under git) as new
# Step 7a.6 (real per-ESV read depth summed from `reads_long`, joined onto
# `match_obj_restored` as `read_depth`) plus `evidence_col`/`evidence_max_ratio` added to the
# existing Step 7b.5/7c `calibrate_query_noise()`/`evaluate_likelihoods()` calls -- purely
# additive, produces `score_likelihood_evidence` as a parallel diagnostic column exactly like
# `score_likelihood_cov` already is. Deliberately NOT switched into what actually feeds
# `join_priors()`/`compute_posterior()` downstream (still `score_likelihood`/
# `score_likelihood_mean`) -- `score_likelihood_evidence` has no Monte Carlo variant, so
# routing it into the real posterior would mean either extending the n_sims simulation to
# cover it or dropping simulated uncertainty for the affected rows, a separate decision not
# made this session. Not yet live-run end to end through the full workflow (only validated
# via the isolated re-validation script above); not yet propagated to
# `PtConceptionWorkflow_12S_multi_site.R` or any other marker/workflow.
# Previous update, 2026-07-14 (Session 155 -- new calibrate_query_noise() (+ helper
# identify_confident_observations()) fixes a real, severe H1 calibration bug found while
# debugging PtConceptionWorkflow_12S_single_site.R: train_likelihood_model() estimates H1
# entirely from reference-vs-reference pairs (two clean NCBI accessions of the same
# species compared to each other), which cannot see technical query-side noise (PCR/
# sequencing/degradation/ASV-inference), so a genuinely correct match routinely scores
# below the trained H1 mean and loses to the unreferenced hypotheses. Confirmed universal
# on real 12S data: 46 of 47 species checked (98%) have their trained mu_score sitting
# 0.6-1.2 points above their own real production median match score. Root cause hunted
# carefully before fixing: same-individual/duplicate-accession contamination was tested
# and REJECTED (restricting to the true MiFish-U amplicon window, 130-210bp, made ties
# MORE common -- 80.6%, up from 39% unrestricted -- meaning short-barcode monomorphism is
# real biology, not an artifact; censoring it would remove real signal); anchor_perfect
# pseudo-data was tested and REJECTED (barely moves H1_Global_Mu, 99.961% -> 99.961%). The
# real driver: genuine query-side technical noise that reference-vs-reference data
# structurally cannot see, confirmed via TWO independent non-circular calibration sources
# (a universal MiFish-primer contaminant -- human DNA, unambiguous true species -- and 46
# real genera where TaxaExpect occurrence priors confirm exactly one locally-plausible
# species) both landing on the same ~98.8% real median, ~1.2 points below the trained
# mean. Marker-transferability explicitly checked and found NOT to hold: the identical
# method run on real 18S data (thin: only 3 genera/152 confident observations, treat
# cautiously) found the gap runs ~4.5 points/~74 mismatches vs 12S's ~1.2 points/~2
# mismatches -- neither a fixed percentage nor a fixed absolute mismatch count transfers
# between markers; this calibration must be re-run per marker/workflow, never reused.
# calibrate_query_noise() estimates one marker-wide additive offset (median residual
# across the confident set) and shifts H1_Global_Mu + every H1_Lookup$mu_score uniformly
# -- H2/H3 means are defined relative to H1's mean so they move automatically, no separate
# change needed. Live-validated end to end on the real 13,442-observation 12S dataset,
# wired into PtConceptionWorkflow_12S_single_site.R (outside this monorepo, not under git)
# as new Step 7b.5: mean H1 relative likelihood 0.140 -> 0.932, H1 win rate 1.0% -> 77.5%,
# unreferenced_genus's share of wins 92.9% -> 1.1%. The original motivating case
# (Sardinops sagax at 99.4% real match, previously losing to unreferenced_genus at raw
# likelihood 1.0 vs H1's 0.147) now resolves correctly, winning outright at 1.0.
# `devtools::test()` 667/667, `devtools::check()` clean.
#
# A matching sigma (variance) correction was attempted the same session and rejected
# after real-data testing: applying the identical MAD-based ratio to H1_Sigma and every
# H1_Lookup$sigma_score helped 0 of 13,442 real observations and hurt 4,878, in some cases
# (including the Sardinops case) zeroing the correct species' H1 likelihood to exactly 0.
# Root cause: the confident-observation set is selection-biased toward the *easiest*
# cases (abundant, well-sampled genera, clean high-depth reads) and understates true
# population-wide variability -- confirmed directly via a strong real correlation
# (cor(log(n_confident_obs_per_genus), sd_of_residuals) = -0.90 across 24 real genera).
# `calibrate_sigma` param added but defaults to FALSE (opt-in, documented negative
# result) -- see this function's own roxygen "Sigma correction" section for the full
# record, and TaxaID's memory system ([[project_bayesian_likelihood_calibration_2026_07]])
# for the complete investigative history including the two rejected root-cause hypotheses.
#
# Session 155 continued: real per-observation DNA read depth (from the workflow's
# `reads_long` table, aggregated per observation_id) confirmed the sigma problem's real
# fix direction -- NOT a flat population-wide correction, but a genuine per-observation
# quality covariate: cor(log(depth), |residual|) computed separately per genus (18 real
# genera, n>=50 each) is consistently negative (range -0.37 to -0.76, mean -0.567) --
# directly connects to and updates the existing [[project_quality_covariate_deferred]]
# memory (TaxaAssign's confirmation-quantile design, evaluate_likelihoods()'s own
# score_likelihood_cov, TaxaMatch's bbox_coverage all flagged there as needing exactly
# this kind of real per-observation signal). New evidence_col/evidence_max_ratio params
# added to both calibrate_query_noise() (computes reference_evidence, a global median
# baseline from the confident set, at calibration time) and evaluate_likelihoods() (reads
# that baseline at inference time -- deliberately decoupled so a single-observation
# evaluate_likelihoods() call needs no recalibration). Produces a new parallel
# score_likelihood_evidence output column (mirrors score_likelihood_cov's existing
# precedent: point-estimate only, no Monte Carlo variant). Deliberately kept SEPARATE from
# the existing coverage/min_coverage mechanism rather than overloading it, since coverage
# is documented as bounded (0,1] while evidence_ratio is symmetric/unbounded around 1.0.
# Two real problems found and one fixed via live-data testing, in sequence: (1) an
# uncapped, symmetric 1/sqrt(evidence_ratio) scaling crashed the Sardinops case to exactly
# 0 (735 real reads vs a baseline of 17 gave a ratio of 43.2, tightening sigma 6.6x enough
# to Mahalanobis-reject a real, correctly-identified match) -- fixed with
# evidence_max_ratio (default 1: never tighten sigma, only widen, mirroring
# score_likelihood_cov's own already-safe convention). (2) NOT fixed, genuinely open: even
# this safe, capped default is net slightly negative on the same real dataset (27 helped,
# 2053 hurt) -- widening a Gaussian's sigma always lowers its peak density, which only
# pays off for observations far from the mean, so uniformly widening every low-depth
# observation (most of which are still decent, close-to-mean matches) does more harm than
# good. The depth-noise correlation itself is real and validated; whether Gaussian
# sigma-modulation is even the right way to use it is not resolved. Four untried
# alternatives (borderline-only modulation, modulating the outlier-rejection alpha instead
# of sigma, a heavier-tailed H1 likelihood, or leaving the mechanism built-but-unused for
# now) recorded in [[project_evidence_ratio_sigma_reentry]] for whoever picks this up
# next. `devtools::test()` 667/667, `devtools::check()` clean throughout both rounds.
#
# Not done this session: Job 2 (modeling unreferenced-relative likelihoods -- H2/H3's own
# construction, as opposed to H1's calibration fixed here) not started at all. Rollout of
# calibrate_query_noise() beyond PtConceptionWorkflow_12S_single_site.R to any other real
# workflow (18S/18S_2/18S_phytoplankton single- and multi-site, Mugu, PtConception 12S
# multi-site, the TaxaID_Workflow_Template_TEST.R template) not yet done -- user explicitly
# asked to be reminded of this once tested here; still outstanding as of this writing.
# Previous update, 2026-07-11 (Session 151 continued once more -- ecosystem soundness-review
# item 13 (build_sequence_matrix()'s pairwise_distance_to_match) fixed: new opt-in
# barcode_term param auto-resolves min_seq_len/max_seq_len via
# TaxaTools::resolve_barcode_lengths() instead of the generic [100, 2000] default. This
# is the documented Paralabrax footgun (see Known Footguns below) made ergonomic: a
# broad NCBI fetch can return sequences describing a genomically different stretch of
# the same gene that still pass a length filter, silently mixing two amplicon windows
# into what looks like one self-consistent H1/H2 training set --
# diagnostics/sebastes_chromis_confirmation.R (the script that found this) already
# hand-implemented the fix by manually pre-filtering reference_df via
# TaxaTools::resolve_barcode_lengths() before calling this function; that pattern is now
# built in. Detected via missing(), not value comparison, so explicit min_seq_len/
# max_seq_len (even if numerically identical to the old defaults) always override the
# resolved range -- fully backward compatible, no existing caller's behavior changes
# unless barcode_term is newly supplied. Important nuance documented in the roxygen: a
# *specific registered primer variant* (e.g. "MiFishU", resolves to the literature-
# verified 130-210bp real PCR amplicon) gives a strong guarantee; a bare marker name
# (e.g. "12S", resolves to a much wider 100-600bp per-gene range) only guarantees
# "roughly the right marker," not amplicon-window comparability -- this fix closes the
# ergonomic gap, not the judgment-call gap. Wired into
# inst/workflows/sequence_likelihood_workflow.R (the one real workflow calling this
# function with no existing length safeguard); deliberately NOT wired into
# inst/TaxaID_Workflow_Template_TEST.R, which already made and documented its own wider
# max_len=1200L judgment call for real longer submissions -- applying the generic "12S"
# resolved range there would have silently excluded data that workflow's own team
# already decided to keep. Not attempted: making max_dist marker-aware (the review's
# smaller secondary suggestion) -- no established per-marker max_dist mapping exists
# anywhere in the ecosystem to draw from. 5 new offline tests. devtools::test() 667/667
# (up from 661), check() clean. See ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_
# REVIEW.md's item 13 for the full record.
# Previous update, same day (Session 151 continued once more -- ecosystem soundness-review
# item 12 (apply_coverage_constraints()'s completeness_penalty_weight) fixed:
# constraint_behavior default changed "zero" -> "relabel". The review flagged that the
# default hard-zeros the "unreferenced_species" hypothesis for any genus
# audit_barcode_coverage() calls "complete" -- treating an NCBI taxonomy-tree query result
# as certain ground truth, when it can under-enumerate a genus for reasons unrelated to
# true completeness (unindexed recent species, unresolved synonyms, missed renamings). A
# wrongly-"complete" genus then deterministically misassigns a genuinely novel detection,
# with the correct hypothesis permanently zeroed out. Investigating found the ecosystem had
# already half-adopted the fix: TaxaAssign::run_bayesian_pipeline() (the real production
# entry point) has defaulted to the non-destructive "relabel" mode since it was written --
# only this low-level function's own default still pointed at "zero", so any direct caller
# (three vignettes, one demo workflow script, the superseded monolithic workflow) got the
# unsafe default even though the flagship pipeline had already moved past it. Changed this
# function's default to match; added @section Census confidence explaining the reasoning.
# The one demo script that specifically narrates and counts zero-suppression
# (5_audit_coverage_workflow.R) and the superseded TaxaLikely_workflow.R both now request
# constraint_behavior = "zero" explicitly, preserving their teaching intent; the three
# vignettes were left to pick up the safer new default. Not attempted: a soft/
# confidence-scaled penalty_factor (the review's alternative suggestion) -- no data exists
# to quantify per-genus census confidence, and the default-mode fix alone already closes
# the H-priority risk (no more silent, irreversible destruction of likelihood mass by
# default). Two tests exercising "zero" mode's specific math now request it explicitly
# (matching item 11's tau=1 test-pinning pattern); new test confirms the new default is
# non-destructive. devtools::test() 661/661 (up from 658), check() clean. Also noticed, not
# fixed (pre-existing, out of scope): TaxaAssign/vignettes/taxaid-ecosystem.Rmd passes the
# whole audit_barcode_coverage() return list to apply_coverage_constraints() instead of the
# reshaped coverage$census every real call site uses -- a second instance of that file's
# already-known API drift (Session 150 flagged a separate stale-argument-count bug in the
# same file). See ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 12 for
# the full record.
# Previous update, same day (Session 151 continued yet further -- ecosystem soundness-review
# item 9 (train_likelihood_model()'s eb_bivariate_normal) closed out, docs-only, after the
# shrinkage-weight half of the finding turned out to be a false positive on verification.
# The review claimed the Empirical Bayes shrinkage weight (w = N/(N+prior_weight)) uses N =
# within-species PAIR count (O(k^2) for k reference sequences, correlated), inflating
# confidence in well-sampled species. Built a synthetic 5-sequence species and ran it
# through the real pipeline before touching any code: .prep_training_data() does generate
# all 20 ordered pairs internally, and a separate N_Obs diagnostic column does carry that
# pair count -- but group_by(id_x) |> slice_max(score_logit, n=1) (present since the
# package's initial commit) already collapses this to one row per SEQUENCE (its single best
# within-species match) before train_likelihood_model() ever computes the shrinkage N.
# Confirmed directly: N_Obs = 20 (pairs), but the actual n_obs_species used for shrinkage =
# 5 (sequences). N_Obs is dead code with respect to shrinkage -- grepped the whole package,
# never read again, and doesn't even survive into the returned model_params object. Fix
# (docs-only, kept N_Obs per the user's explicit choice rather than removing it -- costs
# nothing computationally, could be a future pair-density diagnostic): N_Obs's roxygen in
# .prep_training_data() now states plainly it's an unused pair-count diagnostic, not the
# shrinkage N; train_likelihood_model() gained a new @section Marker validation scope
# stating that Framing B (the continuous bivariate-normal form) is empirically validated
# for 12S/18S only and pointing at ecosystem_docs/../diagnostics/seq_matrix_score_distribution.R
# for any other marker (COI/16S/cytb/rbcL/matK/trnL, all now trainable via
# trim_to_amplicon()) -- this half of the original finding was real and remains open as a
# workflow caveat, not a code bug. devtools::test() 658/658 unchanged (docs-only), check()
# clean. See ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's item 9 for the full
# record, including the exact synthetic-fixture verification.
# Previous update, same day (Session 151 continued -- correct_training_bias()'s default tau
# changed 1.0 -> 0 (ecosystem-wide soundness-review item 11, the review's own "single
# clearest actionable bug"): every real calibration run against this function so far --
# image (Session 129) and acoustic, on both the original small pilot AND the later,
# properly-powered Session 133 re-test -- found tau ~= 0 optimal, contradicting the
# shipped tau = 1.0 default. Also fixed a stale docstring claim while in there: the
# function's own Details section still said "image and acoustic gave opposite answers"
# (tau~=0 vs tau~=1), which Session 133's larger acoustic re-test had already superseded
# (pooled acoustic is also tau~=0) without the docstring being updated to match. Tests
# that exercised tau=1's specific math now pass tau=1 explicitly rather than relying on
# the default; new test confirms the new default leaves scores unchanged.
# devtools::test() 658/658 (up from 656), check() clean. Not a claim that tau=0 is
# correct in general -- only the evidence-backed starting point given what has actually
# been measured; per-cluster heterogeneity (Session 133: 2/8 acoustic clusters still
# prefer high tau) means a single scalar default still won't fit every case. Previous
# update, same day (Session 151): per-genus H2 delta shrinkage, prompted by a
# manuscript peer-review pushback on the reference-gaps section: H2$delta (the logit shift
# used to model an unreferenced congener's likelihood) was a single value pooled across
# every genus in the training set, so a cryptic species complex (real divergence far below
# the pooled average) got the exact same shift as a loosely-differentiated genus, silently
# overstating confidence in the known-species hypothesis exactly where a taxonomist most
# needs the model to hedge. .prep_training_data() gains max_congener_score (best same-
# genus/different-species match, NA when the genus has no second referenced species --
# distinct from the existing max_foreign_score, which mixes in matches to unrelated
# genera); train_likelihood_model() uses it to estimate a genus-specific H2 delta,
# shrunk toward the pooled value via the identical Empirical Bayes w = n/(n+prior_weight)
# form already used for per-species H1 means, stored as a new H2_Lookup slot.
# evaluate_likelihoods() prefers H2_Lookup's genus-specific delta at inference time when
# the anchor candidate's genus has one (H3 keeps its "+2.0 taxonomic step" heuristic on
# top of whichever delta -- local or global -- H2 used), and marks every H2/H3 row with a
# new h2_delta_source diagnostic ("genus_specific" vs "global_fallback") so a
# "global_fallback" row -- including every genus with only one referenced species, where
# no local estimate is possible -- can be read with appropriate caution. Backward
# compatible: model_params objects trained before this change (no H2_Lookup slot) fall
# back to the pooled global delta exactly as before, unchanged. This fix only corrects the
# *magnitude* of the shift for the correct genus -- it does not address the separate,
# structural mimicry/convergence problem (H2/H3 only ever anchor on the best-scoring
# candidate's own genus; an unreferenced visual/acoustic mimic's true relatives may not be
# that genus at all), which has no statistical fix and is now documented as a load-bearing
# assumption -- "related taxa are more similar in the evidence trait than unrelated taxa
# are" -- with a new subsection in inst/TaxaLikely_supplemental_methods.md scoping it as
# much weaker for image/acoustic evidence than for DNA sequence identity, and recommending
# direct reference-database expansion (not modeling) for species with known/suspected
# unreferenced mimicry complexes. New tests confirm H2_Lookup construction on a real
# 2-genus fixture (a tight congener pair vs. a monotypic genus whose only foreign matches
# are cross-genus), confirm the monotypic genus is correctly excluded, and confirm
# .evaluate_one_query() actually prefers the genus-specific delta and raises H2's
# likelihood accordingly. devtools::test(): 656/656 (0 failures, up from 643; same 15
# pre-existing unrelated warnings, 1 pre-existing skip). devtools::check(): 0 errors,
# 0 warnings, 0 notes.
# Previous update, 2026-07-10 (Session 150 -- expand_unreferenced_hypotheses() moved here from
# TaxaAssign (package-placement fix, not a math change); see TaxaID/CLAUDE.md's Session 150
# note and this file's own Function Inventory entry above for the full record.
# devtools::test() 643/643 (0 failures), devtools::check() clean.)
# Previous update, 2026-07-06 (Session 142 -- trim_to_amplicon() now supports the real eDNA COI
# mini-barcode (Leray et al. 2013 mlCOIintF/Meyer 2003 dgHCO2198, "coi-leray"), resolving
# Session 141's flagged inosine blocker by pairing Leray's own inosine-free forward primer
# with an inosine-free reverse primer (Meyer 2003) instead of Geller et al. 2013's jgHCO2198 --
# no code changes needed here, same pattern as Session 141. See TaxaTools/CLAUDE.md's Session
# 142 note for the discriminatory-power literature review and full verification record.
# Session 141 -- trim_to_amplicon() now works out of the box for
# every mitochondrial/chloroplast marker in barcode_length_defaults (16S, COI, cytb, rbcL,
# matK, trnL), not just MiFish-12S -- TaxaTools::barcode_primer_defaults gained 6 more
# entries, each independently verified AND empirically tested against a real GenBank
# mitogenome/chloroplast genome. No code changes needed in this package -- trim_to_amplicon()
# was already generic over any barcode_term with a registered primer pair. See
# TaxaTools/CLAUDE.md's Session 141 note for the full verification record, including two real
# errors the empirical testing caught (a wrong cytb amplicon length, a matK forward/reverse
# mislabeling) that a literature-only check would have missed.
# Session 140 -- trim_to_amplicon() added: in-silico PCR
# amplicon extraction for over-length reference sequences (full mitogenomes, etc.) that
# would otherwise be excluded outright by build_sequence_matrix()'s length filter --
# implements ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md.
# Locates verified MiFish-U/E primer-binding sites (Biostrings::matchPattern(fixed =
# "subject"), both strands, mismatch-tolerant) and extracts just the amplicon; falls back
# gracefully per-sequence when a primer site can't be found or implies an implausible span.
# New TaxaTools::barcode_primer_defaults registry (MiFish-U/E only, verified against Miya
# et al. 2015 across three independent sources) + resolve_barcode_primers(). See Session
# 140 note below and TaxaTools/CLAUDE.md's own Session 140 note. Session 136 — fetch_reference_sequences() renamed to
# fetch_ncbi_reference_sequences() (old name kept as deprecated alias) now that a second
# live-API reference source exists: fetch_bold_reference_sequences(), built directly
# against BOLD's real v5 Data Portal API via httr2 (BOLD migrated off the old v3/v4 API
# the archived `bold` R package targets -- see Session 136 note below for the full
# investigation). subset_local_database() gained real PR2 support (.pr2_hierarchy, a
# fixed 9-level positional format, confirmed against real PR2 v5.1.1 data) and a MIDORI2
# license caveat. Session 135 — fetch_reference_sequences(include_location=)
# and a new fetch_xc_recording_locations() close two of the three location-metadata gaps
# flagged in ecosystem_docs/TODO_validation_benchmark.md's "Sourcing location data" section;
# see Session 135 note below. Session 133 — acoustic tau re-calibrated on a real 24-species/8-cluster/2487-window dataset; Session 128/129's tau≈1/tau≈3.6 for acoustic did NOT survive the larger sample, pooled result is tau≈0 matching image, though per-cluster results are heterogeneous; no current evidence for tau>0 as a default. Session 129 — assign_scores() score-scale bug found and fixed (unbounded scores like iNaturalist's combined_score no longer forced through a fixed 0-100 divisor); tau/score_sharpness jointly calibrated on 51 clean real photos; image resolved to tau≈0, superseding Session 128's confounded 5/6->4/6 number)

---

## Package Purpose
Converts match scores (DNA percent identity, image similarity, acoustic scores) into
likelihoods for taxonomic assignment. Takes a standardized match object (from TaxaMatch
or user-supplied) and produces per-hypothesis `score_likelihood`, `score_likelihood_mean`,
`score_likelihood_sd` columns required by TaxaAssign.

Also provides reference database quality tools:
- Detecting mislabeled reference sequences
- Auditing taxonomic completeness (identifying unreferenced taxa missing from the reference)

Part of the TaxaID ecosystem. Depends on TaxaTools for name cleaning and column standardization.

**Status: All functions written and passing devtools::check() (0 errors, 0 warnings, 0 notes).**
**Source refactored from: `~/Rscripts/eDNA/Bayesian  Workflow/Universal_Biological_Classifier_Working_2.R`**

---

## Dependency Chain

TaxaTools -> TaxaFetch -> TaxaHabitat -> TaxaExpect -> TaxaAssign / TaxaMatch -> **TaxaLikely** -> TaxaAssign

TaxaLikely depends on TaxaTools for:
- `create_taxon_names()` -- derives `taxon_name` + `taxon_name_rank` (used in evaluate.R for H2/H3 rows)

---

## Match Object Interface (Input)

The canonical match object produced by `standardize_match_data()` (TaxaMatch) or
supplied directly by the user. One row per `observation_id` x reference accession match.

| Column | Type | Required | Notes |
|---|---|---|---|
| `observation_id` | character | Yes | Unique query ID (e.g. ESVId, image hash, clip ID) |
| `score` | numeric | Yes | Raw match score (e.g. PercMatch 0-100, or similarity 0-1) |
| `taxon_name` | character | Yes | Best taxon label for this reference (from `create_taxon_names()`) |
| `taxon_name_rank` | character | Yes | Rank of `taxon_name` (e.g. "species", "genus") |
| taxonomy cols | character | Yes | e.g. `family`, `genus`, `species` -- must match `rank_system` |
| `testid` | character | No | Marker/barcode type (e.g. "MiFishU") -- retained, not modelled |
| `accession` | character | No | Reference accession -- retained, not modelled |

**Note:** Sample context (site, date, replicate) lives in a separate table and is joined
to likelihood output downstream -- it is NOT part of the match object.

---

## Likelihood Object Interface (Output -> TaxaAssign)

`evaluate_likelihoods()` returns a **named list** with two components:

**`$likelihoods`** -- one row per `observation_id` x taxon hypothesis; pass to
`filter_top_hypotheses()`, `apply_coverage_constraints()`, and
`TaxaAssign::compute_posterior()`.

| Column | Type | Description |
|---|---|---|
| `observation_id` | character | Query identifier |
| `taxon_name` | character | Hypothesized taxon (never NA) |
| `taxon_name_rank` | character | Rank of hypothesis |
| `hypothesis_type` | character | "specific_candidate", "unreferenced_species", "unreferenced_genus" |
| `score_likelihood` | numeric | Point estimate (deterministic) |
| `score_likelihood_mean` | numeric | Mean across Monte Carlo simulations |
| `score_likelihood_sd` | numeric | SD across simulations (0 if n_sims = 0) |
| `score_likelihood_cov` | numeric | Coverage-adjusted point estimate: H1 sigma inflated by `1/sqrt(coverage)`; equals `score_likelihood` when coverage absent or = 1 |
| `score_likelihood_evidence` | numeric | Evidence-adjusted point estimate (Session 155): H1 sigma scaled by `1/sqrt(evidence_ratio)` per candidate; equals `score_likelihood` when `evidence_col` absent or the model has no `reference_evidence` baseline. **Not validated as a net improvement even at the safe (widen-only) default** — see `TaxaLikely/CLAUDE.md`'s Session 155 note before relying on this column. |
| `h2_delta_source` | character | `unreferenced_species`/`unreferenced_genus` rows only (`NA` for `specific_candidate`): `"genus_specific"` when the anchor candidate's genus had an `H2_Lookup` entry, `"global_fallback"` when it used the pooled `H2$delta`/`H3$delta` instead (includes every genus with only one referenced species). |

**`$unresolved`** -- rows from the original `match_df` for any `observation_id` that
produced no usable likelihoods (e.g., all candidates matched only at a rank
coarser than `rank_system` specifies). Empty data frame if none. Re-run
`evaluate_likelihoods()` on `$unresolved` with a coarser `rank_system`.

TaxaAssign joins on `taxon_name` + `taxon_name_rank`. TaxaExpect provides priors
for `unreferenced_species` and `unreferenced_genus` rows (unreferenced species priors).

---

## Function Inventory

### Reference acquisition (build reference_df)

| Function | File | Status | Description |
|---|---|---|---|
| `fetch_ncbi_reference_sequences()` | `R/fetch.R` | Written | **Renamed from `fetch_reference_sequences()` (Session 136)** — old name kept as a deprecated forwarding alias (`.Deprecated()`, matches `audit_barcode_coverage_ncbi()`'s pattern); renamed because a second live-API reference source (BOLD) was planned and the old name didn't say NCBI anywhere. Search NCBI by taxon + barcode marker, resolve taxonomy via taxid bridge, filter/downsample, download FASTA → `reference_df`. Count-first estimation; resumable via `cache_dir` (default `tools::R_user_dir("TaxaLikely","cache")`). Cache key includes `min_len`, `max_len`, `max_date` so changed parameters auto-start fresh. Per-taxon tryCatch: NCBI rate-limit errors skip one taxon with warning instead of crashing the entire run. **Session 135**: `include_location = FALSE` param — when `TRUE`, fetches each accession's full GBSeq XML record (`.fetch_locations_batched()`) and adds `lat`/`lon`/`country` columns parsed from the `source` feature's `lat_lon`/`country` qualifiers (`.parse_lat_lon()`); a genuinely separate NCBI round trip from the ESummary/taxonomy-XML fetches this function already does, neither of which carries those qualifiers. **Session 159**: `keep_out_of_range = FALSE` param — when `TRUE`, out-of-range (e.g. mitogenome-length) sequences are retained (new `in_barcode_range` diagnostic column) instead of dropped, capped per species by `max_out_of_range_per_species` (default `2L`) so they never compete with in-range sequences for the `max_per_species`/`max_per_genus` training-set budget. `build_sequence_matrix()`'s own independent length filter still excludes them from training exactly as before. Exists so `restore_suppressed_candidates(check_regional_overlap = TRUE)` has real sequence content to check for regional overlap without a separate on-demand fetch when a query's own top hit is an over-length reference (see that function's own Session 159 note). Also fixed the same session: `.build_search_term()`'s bare `barcode_term = "12S"`/`"16S"` now ORs in "small/large subunit ribosomal RNA" synonyms -- see the top-of-file Session 159 note for the full real-data-confirmed root cause. **Session 159 (final entry)**: `keep_out_of_range = TRUE` had no upper size bound at all -- found via a real 111,213,091bp whole-genome scaffold in the real Mugu `reference_df.rds` (142MB). New `max_out_of_range_len = 200000L` param caps it (real mitogenomes/chloroplast genomes stay under this; genome/scaffold-scale sequences don't), folded into both length-filter locations and the cache key (which also didn't vary by `keep_out_of_range` at all before this fix -- a real staleness bug). |
| `fetch_bold_reference_sequences()` | `R/fetch.R` | Written | BOLD Systems reference-fetch analog. **Session 136**: talks directly to BOLD's real, live v5 Data Portal API (`portal.boldsystems.org/api`, confirmed via its own OpenAPI spec) via `httr2` -- does NOT wrap the `bold` R package, whose `bold_seqspec()`/`bold_identify()` target BOLD's now-permanently-retired v3/v4 API. 3-stage flow: `query/preprocessor` (resolve taxon → triplet) → `query` (submit → `query_id`) → `documents/{id}/download?format=tsv` (returns full result set, no pagination needed). No server-side marker/locus filter exists in BOLD's query API (only `tax`/`geo`/`ids`/`bin`/`recordsetcode` scopes) — `barcode_term` filters client-side on the returned `marker_code` column. Location (`coord`, bracketed `"[lat, lon]"` string, parsed by `.parse_bold_coord()`; `country/ocean`) comes free with every query, unlike NCBI which needs a separate round trip. Live-tested end to end (103 real sequences across 2 taxa, 84% real coordinate coverage). Internal helpers: `.bold_resolve_taxon()`, `.bold_submit_query()`, `.bold_fetch_documents()`, `.parse_bold_coord()`. |
| `read_crabs_output()` | `R/read_crabs.R` | Written | Read CRABS internal-format database (headerless 11-column TSV) → `reference_df`. Params: `rank_system` (NULL = auto-detect from populated columns), `max_n_bases`, `require_species` (uses `TaxaTools::is_valid_species_name()`), `dereplicate` (collapse exact-duplicate seqs within species). Complementary to `flag_reference_errors()`: CRABS handles bulk QC; TaxaLikely catches mislabeling CRABS cannot detect. |
| `trim_to_amplicon()` | `R/trim_to_amplicon.R` | Written | **Session 140.** In-silico PCR: locates forward/reverse primer-binding sites in over-length `reference_df` sequences (full mitogenomes, whole-genome scaffolds) and extracts just the amplicon, instead of `build_sequence_matrix()`'s length filter discarding the whole sequence -- the fix for a poorly-sampled species whose only GenBank record is over-length losing all reference representation. Standalone stage: `fetch_ncbi_reference_sequences()` → `trim_to_amplicon()` → `build_sequence_matrix()`. Sequences already within `[min_len, max_len]` are left untouched (most purpose-cut barcode submissions already have primers stripped at deposition, so attempting a match on them would often fail even though the sequence is fine). Primers resolved via `barcode_term` (`TaxaTools::resolve_barcode_primers()`) or supplied directly (`primer_fwd`/`primer_rev`) for any marker not yet in the registry. `Biostrings::matchPattern(fixed = "subject")` (both strands, via `reverseComplement()`) -- empirically confirmed `fixed = FALSE` produces spurious matches across long N-runs in draft sequences, while `fixed = "subject"` correctly treats subject ambiguity codes literally while still interpreting the primer's own IUPAC degeneracy. `max_mismatch_rate` (default `0.15`) tolerates real SNP variation at primer-binding sites. A matched pair implying a span outside `[min_len, max_len]` is rejected as an implausible pairing rather than accepted (guards against a spurious far-apart match producing a near-original-length "amplicon"). Per-sequence graceful fallback: unmatched/implausible sequences are left unchanged (still over-length) and flagged via `amplicon_trim_note`, so they fall through to `build_sequence_matrix()`'s existing length filter exactly as before -- this function only ever rescues sequences that would otherwise be lost, never removes ones that would otherwise be kept. Live-verified on a realistic simulated 16kb mitogenome containing an embedded real MiFish-U amplicon: correctly extracted a 172bp sequence (matching Miya et al. 2015's own reported mean amplicon length exactly) that would otherwise have been dropped outright. Deliberately narrow in scope -- not a CRABS reimplementation; primer registry is populated only for verified primer sets (currently MiFish-U/E), with an unregistered marker directed to supply primers directly or pre-trim with CRABS. Internal helper: `.extract_amplicon_one()`. **Session 141**: works out of the box for 6 more markers now that `barcode_primer_defaults` covers every mito/chloroplast marker in `barcode_length_defaults` (16S, COI, cytb, rbcL, matK, trnL) -- no code change needed here, since this function was already generic over any `barcode_term` with a registered pair. New tests confirm real, literature-verified COI-Folmer and rbcLa primer pairs correctly extract from an over-length synthetic sequence, plus a loop test covering all 6 new registry entries end-to-end. **Session 142**: now also supports `coi-leray` (the real mlCOIintF/dgHCO2198 eDNA mini-barcode) -- no code change needed, `barcode_term = "COI-Leray"` resolves through the same generic path. New test confirms correct extraction of a real, literature-verified Leray-fragment amplicon; bare `"COI"` now errors (ambiguous between `coi-folmer`/`coi-leray`) rather than guessing. |
| `read_reference_fasta()` | `R/fetch.R` | Written | Read local FASTA + taxonomy → `reference_df`. For CRUX, GenBank dumps, custom databases. `taxonomy` param accepts a data frame; new `taxonomy_file` param accepts a 2-column TSV (QIIME2/RESCRIPt/SILVA/MIDORI2 prefix-style `k__Kingdom;...` or positional `Kingdom;...`). Exactly one of `taxonomy` or `taxonomy_file` must be supplied (previously `taxonomy` was required). Internals: `.parse_taxonomy_tsv()`, `.parse_tax_string()`. |
| `subset_local_database()` | `R/subset_db.R` | Written | Filter a large local FASTA + taxonomy file (SILVA, MIDORI2, GTDB, Greengenes2, RDP, **PR2 — Session 136**) to a user-supplied taxon list. Parses taxonomy first → O(1) ID lookup via environment hash → streams FASTA in chunks; peak memory scales with matching sequences, not total database size. Supports `.gz`-compressed FASTA. Optional `max_n_bases` and `require_species` filters. Returns `reference_df`. Reuses `.parse_taxonomy_tsv()` internal. **Session 136**: added real PR2 support — PR2 uses a fixed 9-level positional taxonomy string (`domain;supergroup;division;subdivision;class;order;family;genus;species`, confirmed against a real downloaded v5.1.1 release, 240,201 records, 100% uniform) that doesn't match `.crabs_std_hierarchy`'s 7-level shape; `.parse_tax_string()` now dispatches on field count (9 → new `.pr2_hierarchy` constant) rather than bending the shared 7-level constant every other positional source relies on. Also confirmed and preserved (not stripped) PR2's `:plas` plastid-ancestry suffix. MIDORI2's license (reported CC-BY-NC in secondary sources, unconfirmed on the primary site) now flagged in `@details` as a possible conflict with this ecosystem's CC0/USGS policy. |

### Training (fit model on reference database)

| Function | File | Status | Description |
|---|---|---|---|
| `build_sequence_matrix()` | `R/build_sequence.R` | Written | Align DNA sequences (DECIPHER), compute pairwise distance matrix → pair format for `train_likelihood_model()`. Output includes `coverage` column. New params (Session 112): `filter_unnamed = TRUE` drops sequences with blank/NA finest-rank (species) label before alignment — removes spurious within-species pairs (blank == blank) that dominated 18S databases (69% of pairs); `max_seqs_per_taxon = NULL` randomly subsamples sequences per species before alignment to prevent heavily-sequenced taxa (e.g. Ovis aries) from dominating the within-species distribution. Both operate pre-alignment, reducing DECIPHER computation time. Renamed from `build_reference_matrix()` Session 88. **Session 151**: `barcode_term = NULL` param — when supplied and `min_seq_len`/`max_seq_len` are left at their defaults, auto-resolves the length window via `TaxaTools::resolve_barcode_lengths(barcode_term)` instead of the generic `[100, 2000]` default (explicit lengths always override). Closes the Paralabrax footgun (below) ergonomically — a specific registered primer variant (e.g. `"MiFishU"`) gives a real amplicon-window guarantee; a bare marker name (e.g. `"12S"`) does not. |
| `flag_reference_errors()` | `R/train.R` | Written | Flag mislabeled references |
| `compute_rank_thresholds()` | `R/support_curves.R` | Written | **2026-07-23.** Marker-agnostic per-rank Youden's J threshold deriver -- given a `build_sequence_matrix()`-style `seq_matrix` for YOUR marker/reference database, returns a `c(species=, genus=, family=)`-shaped named vector directly usable as `TaxaAssign::score_consensus(rank_thresholds=)`. Reuses the same genus-/family-equal-weighted, Empirical-Bayes-shrunk curve machinery `train_likelihood_model()` stores in `model_params$Confusion_Risk_Curves` (via the shared internal `.compute_rank_score_curves()`), so the two never drift apart. Built specifically because `score_consensus()`'s `rank_thresholds` lost its universal default the same session (see `TaxaAssign/CLAUDE.md`'s matching note) -- this is the "derive your own from real data" option its new error message points at. |
| `train_likelihood_model()` | `R/train.R` | Written | Full training pipeline -> `taxa_model_params` object; `anchor_perfect` param (default TRUE) injects synthetic perfect-match observations. Bivariate normal over `(score_logit, gap_logit)`. Coverage is a filter only — pass `min_coverage` to `evaluate_likelihoods()` at inference, not a model dimension. Empirical Bayes shrinkage weight `w = N/(N+prior_weight)` uses `N` = within-species SEQUENCE count (one row per sequence after `.prep_training_data()`'s `group_by(id_x) |> slice_max()` dedup), not raw pair count — confirmed empirically Session 151 after a soundness-review finding claimed otherwise (see that function's `N_Obs` doc note). **Session 151**: gained `@section Marker validation scope` — Framing B (this bivariate-normal form) is validated for 12S/18S only; run `diagnostics/seq_matrix_score_distribution.R` before trusting it on another marker. Also **Session 151**: `H2$delta` (the missing-species shift) is otherwise a single value pooled across every genus in the training set; where a genus has a real congener pair (`max_congener_score` from `.prep_training_data()`, distinct from the existing cross-any-genus `max_foreign_score`), a genus-specific delta is estimated and shrunk toward the pooled value via the same Empirical Bayes form as the per-species H1 means, stored in a new `H2_Lookup` slot. Genera with only one referenced species get no lookup row and fall back to the pooled delta unchanged. **Session 158**: new `score_transform` param (`"logit"` default, `"sqrt_mismatch"` new -- see this file's Session 158 note for the full derivation); `H2_Lookup` gains genus-specific `var_shrunk`; the pooled H2 delta/variance default now correctly sources from congener-only comparisons (was mixing in cross-any-genus data); fixed a real, pre-existing bug where `H1_Lookup$sigma_score` stored `sqrt(shrunk variance)` instead of the variance itself, understating every species-specific H1 candidate's true uncertainty since this formula was first written. **Session 157**: `H1_Lookup` gains `n_obs_species` (previously computed for shrinkage, then discarded); `Stats` gains `n_h1_pooled` (total sequences behind the global mean) and `n_h2_pooled` (foreign-match count behind the pooled global H2 delta) -- all three feed `evaluate_likelihoods()`'s redesigned Monte Carlo uncertainty (see that function's own Session 157 note). Purely additive; `model_params` objects trained before this change simply lack these fields and `evaluate_likelihoods()` falls back to its previous behavior. **2026-07-23**: gains a new `Confusion_Risk_Curves` slot (list, `NULL`-safe) -- genus-/family-equal-weighted, Empirical-Bayes-shrunk per-rank TPR/FPR curves computed once via the new internal `.compute_rank_score_curves()` (`R/support_curves.R`), read by `evaluate_likelihoods()`'s new `species_confusion_risk`/`genus_confusion_risk`/`family_confusion_risk` columns (see that function's own entry below) and by the new `compute_rank_thresholds()`. |

### Unified likelihood pipeline (new — Session 99)

| Function | File | Status | Description |
|---|---|---|---|
| `unreferenced_candidates()` | `R/unreferenced_candidates.R` | Written | Expand match_df with H2/H3/(H4) placeholder rows. Auto-detects `rank_system`. `include_unreferenced_family` param (default FALSE) adds H4 catch-all. Anchor = best-scoring taxon per observation. |
| `assign_scores()` | `R/assign_scores.R` | Written | Convert raw scores to `score_likelihood`. `score_type`: `"none"` (all rows = 1.0 uniform), `"direct"` (pass score column through unchanged; NA → 1.0; use after `restore_suppressed_candidates()` no-score path), `"probability"` (ratio-normalize H1; H2/H3 anchored at median same-genus/same-family H1 likelihood; H4 fixed at 0.05), `"similarity_softmax"` (exp-weighted, same H2/H3/H4 anchoring), `"similarity"` (adds `score_norm` only — pass to `model_likelihoods()`). **Single-H1 caveat**: for top-1 classifier output (one H1 row per observation), H2/H3 anchor = median(H1) = 1.0; score has no discriminating effect. Use multi-candidate output + `"probability"` to modulate likelihoods. **Session 129 fix**: `similarity`/`similarity_softmax` auto-detect score scale from the global max of `score_col` (no new parameter) — `max <= 100` keeps the original fixed 0-100/0-1 divisor (BLAST-style, unchanged); `max > 100` (unbounded scores, e.g. iNaturalist's `combined_score`) normalizes each observation against its own candidate range instead, since a fixed divisor was collapsing `score_likelihood` to near-uniform for that data type. `probability` was never affected (doesn't call `.normalize_scores()`). |
| `model_likelihoods()` | `R/compute_likelihoods.R` | Written | Apply bivariate-normal model to a `scored_df` from `assign_scores(score_type="similarity")`. Thin wrapper around `evaluate_likelihoods()`; adds `score_method = "bivariate_normal"`. |
| `compute_likelihoods()` | `R/compute_likelihoods.R` | Written | Orchestrating wrapper: `unreferenced_candidates()` → `assign_scores()` → `model_likelihoods()` (similarity only). Recommended high-level entry point. Returns `list($likelihoods, $unresolved)`. |

### Training-database bias correction (Session 125, revised Session 127)

| Function | File | Status | Description |
|---|---|---|---|
| `correct_training_bias()` | `R/correct_training_bias.R` | Written, wired, live-tested | Divides out an estimated training-count bias (`n_i`) from raw classifier scores before `unreferenced_candidates()`/`assign_scores()` run: `score_i / n_i^tau`. **Revised Session 127**: `tau` is now a single fixed global scalar (default `1.0`, user-tunable), not the Session 125 adaptive per-candidate `tau_i = n_i/(n_i+prior_weight)` — matches Menon et al. 2020's "logit adjustment" correction for long-tailed recognition (literature research found no support for a per-candidate adaptive exponent; the theoretically Fisher-consistent form applies one scalar uniformly). `prior_weight` parameter removed. Missing/zero counts still fall through to the uncorrected score (`tau_used = 0` for that row only) — a deliberate, documented deviation from strict logit adjustment, kept for the same practical reason as before (can't distinguish genuine rarity from a failed lookup). Overwrites `score_col` (default `"score_original"`) in place; preserves the pre-correction value in `score_uncorrected`; adds `n_used`, `tau_used` diagnostics. Pipeline placement: `raw scored_df → correct_training_bias() → unreferenced_candidates() → assign_scores()`. Unit-tested (27 expectations, synthetic fixture). **Wired into `image_acoustic_likelihood_workflow.R` Session 128** (both sections) and live-tested against real classifier output. **Resolved Session 129** (see that session's note below): the Session 128 image number was confounded by an unrelated `assign_scores()` bug; on clean, bug-fixed, 51-photo data, `tau ≈ 0` is optimal for image (correction should not be applied). **Session 133**: acoustic's Session 128/129 `tau ≈ 1`/`tau ≈ 3.6` result did NOT survive a properly powered re-test (24 species/8 confusable clusters/2487 real BirdNET detection windows, vs. the original 3-species/42-window pilot) — pooled acoustic optimum is now `tau ≈ 0` too, though per-cluster results are genuinely heterogeneous (5/8 clusters agree with `tau ≈ 0`; 2 clusters still prefer high `tau` even at ~150-170 windows each, unbracketed at the swept grid's edge). **No current real-data evidence supports `tau > 0` as a default for either data type.** **Session 151**: the package default was changed `1.0` -> `0` accordingly (ecosystem soundness-review item 11) — a caller who does nothing now gets no correction, matching every real result obtained so far, instead of a correction contradicted by every real result obtained so far. `tau` must still be calibrated per data type (and, per Session 133, possibly per taxon cluster) before being raised — see `TaxaLikely/inst/workflows/calibrate_training_bias_tau.R` and `ecosystem_docs/REENTRY_PROMPT_acoustic_tau_calibration_expanded.md` for full method detail. |

### Query-side calibration (Session 155)

| Function | File | Status | Description |
|---|---|---|---|
| `identify_confident_observations()` | `R/calibrate_query_noise.R` | Written, live-tested | Finds genera where `TaxaExpect` occurrence priors (`theta_mean`) confirm exactly one locally-plausible species, then returns the best-scoring row per `observation_id` for every real observation in one of those genera. Non-circular by construction — plausibility comes from independent occurrence/range data, not from the match scores or likelihood model being calibrated. |
| `calibrate_query_noise()` | `R/calibrate_query_noise.R` | Written, wired, live-tested | Fixes a real, severe H1 mean-calibration bug: `train_likelihood_model()`'s H1 params come entirely from reference-vs-reference pairs, which cannot see query-side technical noise, so genuinely correct matches routinely score below the trained mean and lose to H2/H3. Estimates one marker-wide additive offset (median residual across the confident-observation set) and shifts `H1_Global_Mu` + every `H1_Lookup$mu_score` uniformly; `H2`/`H3` move automatically since their means are defined relative to H1's. Live-validated on real 12S PtConception data: H1 win rate 1.0% → 77.5% (13,442 real observations). **Session 2026-07-18 (Fable):** new opt-in `offset_form = c("constant", "linear")` + `min_calib_species` (default `8L`). `"constant"` (default) = the single-additive-offset behavior above, byte-identical. `"linear"` remaps every H1 mean through a robustly-fit line `intercept + slope*trained_mean` (per-species medians, weighted, evidence-range-clamped) — a strict generalization for train-vs-inference scale gaps that aren't a pure location shift (found REAL and total on real 12S: DECIPHER per-species means don't transfer to the external `PercMatch` scale, robust slope→0, H1 win rate +2.1pts). Only H1 mean location is remapped; H2/H3 deltas + gap (the discriminators) untouched. Confident set can't test congener discrimination, so `"linear"` stays opt-in — validate H1 win rate before enabling; falls back to `"constant"` with a warning if `< min_calib_species` confident species. `$Query_Calibration` now also records `offset_form`/`slope`/`intercept`. See `[[project_train_inference_scale_validity]]`. **Do not reuse an offset across markers** — checked directly against real 18S data and found not to transfer as either a fixed percentage or fixed mismatch count. `calibrate_sigma` param (default `FALSE`) attempts an analogous variance correction — **tested and rejected**: helped 0/13,442 real observations, hurt 4,878, some to exactly 0 (confident-set selection bias toward easy/abundant genera understates true population variance). `evidence_col`/`evidence_max_ratio` (paired with the same params on `evaluate_likelihoods()`) is the follow-on per-observation attempt at the same variance problem — the Session 155 uncapped/capped versions were both tested and found net negative; **Session 156** replaced the unconditional rescale with a closed-form crossover gate (only rescales when doing so is provably non-decreasing for that candidate's density) — see `TaxaLikely/CLAUDE.md`'s Session 156 note and `[[project_evidence_ratio_sigma_reentry]]` for the derivation; not yet re-validated against the real 12S dataset the earlier versions were tested on. |

### Inference (apply model to query observations)

| Function | File | Status | Description |
|---|---|---|---|
| `evaluate_likelihoods()` | `R/evaluate.R` | Written | Apply model to all queries; outputs likelihood object. `verbose` param (default FALSE) logs species-specific param fallback. Output includes `score_likelihood_cov`: coverage-adjusted point estimate inflating H1 sigma by `1/sqrt(coverage)` per candidate taxon (binomial SE prior); equals `score_likelihood` when coverage column is absent or all 1. **Session 151**: prefers `model_params$H2_Lookup`'s genus-specific H2 delta over the pooled global one when the anchor candidate's genus has an entry (H3 keeps its `+2.0` step on top of whichever delta H2 used); output gains `h2_delta_source` (`"genus_specific"`/`"global_fallback"`) so callers can identify rows that used the cruder pooled approximation. Backward compatible with `model_params` objects trained before this change (no `H2_Lookup` slot -> always `"global_fallback"`). **Session 155**: new `evidence_col`/`evidence_max_ratio` params, paired with `calibrate_query_noise(evidence_col=)`'s `reference_evidence` baseline — scales H1 sigma by `1/sqrt(evidence_ratio)` per candidate (a real per-observation quality covariate, e.g. DNA read depth), producing a new parallel `score_likelihood_evidence` column (same precedent as `score_likelihood_cov` — point estimate only). Deliberately separate from `coverage`/`min_coverage` (bounded `(0,1]`) since `evidence_ratio` is symmetric/unbounded around 1.0. `evidence_max_ratio` (default `1`) caps the *tightening* direction only — found necessary live: an uncapped ratio crashed a real high-depth observation's H1 likelihood to exactly 0. **Session 156**: the rescale (either direction) is now additionally gated by an exact crossover condition on the candidate's own log-density (derived from the elementary fact that rescaling a Gaussian's variance by `c` changes its log-density at `z` SDs from the mean by `-0.5*log(c) + 0.5*z^2*(1-1/c)`) — only applied when that quantity is `> 0`. This replaces the Session 155 unconditional version, which was tested against real 12S data and found net negative even at the widen-only default (27 helped, 2053 hurt) because most low-evidence real observations are still close to their trained mean, where widening only lowers the peak with no compensating tail benefit. Re-validated against that same real dataset — see the Query-side calibration section above and `[[project_evidence_ratio_sigma_reentry]]` in TaxaID's memory system. **Session 157**: `score_likelihood_mean`/`score_likelihood_sd` (the Monte Carlo columns) are redesigned to represent uncertainty in the TRAINED MEAN (driven by `n_obs_species`/`n_pairs` -- how much reference data calibrated it), not a resampling of the observed query score around the population's overall spread (the previous, differently-motivated mechanism). H2/H3 get systematically wider uncertainty than H1, reflecting that they borrow rather than observe. Backward compatible (falls back to the previous mechanism when `model_params` lacks `n_obs_species`); no new output columns; `TaxaAssign::compute_posterior()` needs no changes since it already consumes these two columns. See this function's own Session 157 note for the full derivation and real-data validation. **Session 158**: reads `model_params$Score_Transform` automatically (no caller-supplied param); H2/H3's mean now anchors on the anchor candidate's own resolved species mean, not the population-wide global mean; uses genus-specific `H2_Lookup$var_shrunk` for H2's sigma when available; `evidence_col`/`min_coverage` now error immediately (not silently misapply) when combined with a `"sqrt_mismatch"`-trained model. See this file's Session 158 note for the full record. **2026-07-19 (Sonnet 5)**: new `min_rank_trust_pvalue` param (default `0.001`) + three new output columns (`absolute_fit_pvalue`, `trusted_rank`, `rank_trust_basis`) -- the "rank-trust mechanism", answering a different question than `score_likelihood` does: not "which hypothesis beats the others" but "is the WINNING hypothesis's own absolute fit believable, or is it just the least-bad option among uniformly weak candidates" (a real, structural blind spot of relative/Bayesian model comparison over a candidate set that isn't guaranteed exhaustive). Reuses only already-computed `H1_Lookup`/`H2`/`H2_Lookup`/`H3` mu/sigma -- no new model fit, no new pass over reference data. Walks from the winning hypothesis's own rank (species/genus/family) coarser until one clears `min_rank_trust_pvalue`'s own **one-sided** absolute-fit test (`P(Z<=z)`, `z=(x-mu)/sd`); falls back to `rank_system`'s own coarsest level with `rank_trust_basis="no_model_info"` once past H3 (no H4+ parameterization exists to test against, regardless of how many levels `rank_system` itself has). Deliberately one-sided, NOT a reuse of the existing (two-sided, unchanged) `alpha` H1-zeroing gate -- a two-sided test would wrongly flag a *better-than-typical* match (e.g. a literal 100% identity hit against a tightly-clustered/clonal-reference species) as equally suspicious as a worse-than-typical one; confirmed as a real, not hypothetical, bug during design (a synthetic case gave two-sided p~=5.7e-07, one-sided p~=0.9999997 for the identical inputs) and fixed before shipping. Real-data validated against PtConMifishSchulte (real PtConception 12S, 13,442 obs): the two real edge-case taxa from `[[project_edge_case_error_taxa_design]]` that best-fit-generic-family (Hylobatidae p=0.60, a Lemuridae/Vulpes contamination mess p=0.24) correctly cap at family across the ENTIRE `min_rank_trust_pvalue` sweep tested (0.0001-0.5); the taxa whose likelihood is genuinely strong but occurrence-implausible (Ovis aries, Cervus elaphus, Bison bison, Salmo salar, Sufflamen fraenatum, Fistularia commersonii -- a DIFFERENT, deliberately out-of-scope problem, see `[[project_edge_case_error_taxa_design]]`'s "prior-orphaned high-confidence match" pattern) correctly do NOT get flagged by this likelihood-only mechanism, confirming the two problems stay cleanly separated. False-escalation rate on 132 real raw-likelihood-driven H1-winning control observations: 0% up to `min_rank_trust_pvalue=0.2`, rising to only 1.5% at 0.4-0.5 (0.5 itself is a natural, provable breakdown point -- a one-sided p of exactly 0.5 means "sitting precisely at the trained mean," so alpha values approaching 0.5 start rejecting ~half of all genuinely normal matches by construction, not a "stricter" setting). Also surfaced a real, striking, unrelated finding along the way: only 44% (132/302) of real posterior-resolved-to-species PtConception observations sampled also win on RAW LIKELIHOOD alone -- for the rest, the PRIOR, not the likelihood, is what resolves the call to species level, a direct real-data confirmation of the closed-world/Bayes-completeness concern this whole mechanism grew out of. `devtools::test()` 0 failures (931, up from 910), `devtools::check()` 0/0/0, reinstalled to `~/Library/R/4.0/library`. Not yet wired into any production workflow. Session also investigated (not built, real dead end found first): extending `diagnostics/referenced_candidate_exclusion_rate*.R`'s already-abandoned "true species referenced but excluded from candidate set" rate estimate to Mugu's BLAST-scored data as a way around PtConception's external-scoring-tool noise problem -- blocked by Mugu's own match table lacking a `sequence` column (needed for real re-alignment) plus too few real observations (401) for a trustworthy rate; not pursued further. **REMOVED 2026-07-20**: `min_rank_trust_pvalue`/`trusted_rank`/`rank_trust_basis` are gone entirely -- `trusted_rank` was found unreliable on real data (computed for this function's own top-LIKELIHOOD hypothesis, not necessarily the hypothesis that wins the POSTERIOR downstream once priors are applied, a confirmed ~30% mismatch on a real 12S dataset). `absolute_fit_pvalue` itself (the per-row, one-sided p-value everything else was built on) is unchanged and still computed unconditionally; downstream consumers now read it directly instead of going through the ladder-walk. See this file's top session note and `[[project_rank_trust_mechanism_removed]]`. **2026-07-23**: gains `species_confusion_risk`/`genus_confusion_risk`/`family_confusion_risk`/`own_rank_confusion_risk` output columns -- a SECOND, model-independent, score-ONLY diagnostic alongside `absolute_fit_pvalue` (which is model-based), read from `model_params$Confusion_Risk_Curves`. Each is a one-sided tail probability (P(a real congener/confamilial/cross-family pair would score this high or higher) at that row's own genus/family) -- LOWER values mean STRONGER evidence, the opposite of the usual higher-is-better "support" sense, documented explicitly via a new `@section Confusion risk`. All three populated for every row regardless of `hypothesis_type`; `own_rank_confusion_risk` points at whichever matches that row's own resolved rank. `NA` when `Confusion_Risk_Curves` lacks the relevant tier or this row's own genus/family is unresolved. Purely informational, same contract as `absolute_fit_pvalue` -- never changes which hypothesis wins. See `TaxaAssign::posterior_consensus()`'s matching `winner_*_support` pass-through. |
| `filter_top_hypotheses()` | `R/evaluate.R` | Written | Keep finest-rank candidates per query |

### Reference coverage

| Function | File | Status | Description |
|---|---|---|---|
| `infer_exclude_predicted()` | `R/infer_predicted.R` | Written | Inspects accession column of a match object to infer whether the BLAST reference excluded computationally predicted (XR_/XM_) sequences. Returns `TRUE` (no XR_/XM_ found → exclude), `FALSE` (predicted accessions present → include), or `NA` (all custom/non-NCBI accessions → cannot determine). Auto-detects accession column; strips version suffixes; reports custom accession count. Feeds directly into `audit_barcode_coverage(exclude_predicted = infer_exclude_predicted(match_obj) \%\|\|\% TRUE)`. |
| `audit_barcode_coverage()` | `R/coverage.R` | Written | **Preferred for eDNA/barcode data.** Unreferenced = described species with NO barcode sequence (cannot appear as reference match). **Reverse-search implementation** (Session 113): one genus-level NCBI nuccore query + batched `elink` → taxonomy + batched `entrez_summary`; ~4 fixed API calls per genus regardless of species count (3.25× faster than per-species queries on 18S protist/algae genera). Species enumeration: NCBI taxonomy subtree (or user `species_list`). Census: `in_reference`, `has_seqs_not_in_ref`, `unreferenced`, `is_complete`. Params: `barcode_term` (vector ok), `max_date`, `min_len`, `max_len`, `species_list`, `max_nuccore` (default 5000), `cache_dir`. Checkpoint/resume: progress saved per genus; interrupted runs resume automatically. Hyphenated genera (e.g. *Pseudo-nitzschia*) handled via hyphen→space normalization in `.genus_taxid()`. `audit_barcode_coverage_ncbi()` is a deprecated alias. |
| `audit_reference_coverage()` | `R/coverage.R` | Written | Queries NCBI taxonomy tree (all described species). Use for non-barcode libraries (images, sounds) where barcode availability is irrelevant. |
| `audit_acoustic_coverage()` | `R/coverage.R` | Written | **Acoustic/image.** Which plausible species are absent from classifier's known list? Simple set-membership check — no NCBI API. `match_df` param annotates `in_match_data`. `xc_recordings = FALSE` param (Session 119, fixed to v3 Session 125): when TRUE, queries Xeno-canto v3 API (requires `XC_API_KEY` env var) for `n_recordings` per species (1s rate limit; NA on failure or missing key). Returns `list(census, unreferenced)` matching `audit_barcode_coverage()` format. |
| `audit_inat_coverage()` | `R/coverage.R` | Written | **iNaturalist image coverage audit** (Session 119). Given a species list (prior taxa), queries iNat taxa API for each species: returns `n_observations`, `cv_model_included` (n_obs >= `cv_threshold`, default 100L), `unreferenced` list. Optional `match_df` annotates `in_match_data`. Optional `api_token` (env `INAT_API_TOKEN`; 401 → stop). 0.3s rate limit. Returns `list(census, unreferenced)` with same structure as `audit_barcode_coverage()`. Internal helpers: `.inat_species_info()`, `.xc_recording_count()`. |
| `fetch_xc_recording_locations()` | `R/coverage.R` | Written | **Session 135.** Given one or more species names, returns per-recording `species`/`xc_id`/`lat`/`lon`/`country` from Xeno-canto v3 — the same API response `audit_acoustic_coverage(xc_recordings = TRUE)` already queries via `.xc_recording_count()`, but that function only ever read `numRecordings` off the body and discarded the `recordings` array's own `lat`/`lng`/`cnt` fields. Refactored the shared HTTP call into `.xc_recordings_raw()` (zero behavior change for `.xc_recording_count()`, confirmed by its own tests) and added `.xc_recording_locations()` as the per-recording extractor this function loops over (1s/species rate limit, matching `audit_acoustic_coverage()`'s own). `xc_id` is Xeno-canto's own catalog number, not a `TaxaMatch::build_site_table()`-ready `observation_id` — mapping it to a caller's BirdNET observation-id convention is left to the caller (harness-level concern, not attempted here). |
| `apply_coverage_constraints()` | `R/coverage.R` | Written | Suppress or relabel "unreferenced_species" for fully-sampled genera. **Session 151**: `constraint_behavior` default changed `"zero"` -> `"relabel"` (non-destructive) — matches `TaxaAssign::run_bayesian_pipeline()`'s own already-established default; `"zero"` mode (opt-in) treats `audit_barcode_coverage()`'s `is_complete` as certain ground truth, which it isn't (NCBI-query estimate). See `@section Census confidence`. |
| `expand_unreferenced_hypotheses()` | `R/expand_unreferenced.R` | Written | **Session 150: moved here from TaxaAssign.** Models likelihoods for named unreferenced species by copying/medianing the generic H2/H3 values (borrowed from referenced relatives), then expands genus/family placeholder rows into named species so they can join TaxaExpect priors directly. Still needs a TaxaExpect-derived `unreferenced_df` as input -- that's a data/workflow-ordering requirement only (build it, then call this function), not a package dependency, since this function never calls into TaxaExpect or TaxaAssign itself. `TaxaAssign::expand_unreferenced_hypotheses()` remains as a `.Deprecated()` forwarding wrapper. **Session 158 (2026-07-16 correction):** `score_likelihood_cov`/`score_likelihood_evidence`/`h2_delta_source` are now copied from the generic H2/H3 row onto every expanded named-species row when present (previously left `NA` along with genuinely row-specific extra columns like `constraint_applied` -- found live-testing the real `sqrt_mismatch` workflow run, where `h2_delta_source` showed `NA` on expanded rows in post-`join_priors()` output instead of `"genus_specific"`/`"global_fallback"`). **Session 159 (final entry):** `unreferenced_df` gains an optional `observation_id` column -- a row with `NA` (or the column absent entirely) applies to every observation sharing its genus/family, the original global-list behavior, unchanged; a row with a real `observation_id` applies only to that one observation. Lets `restore_suppressed_candidates(check_regional_overlap = TRUE)`'s rejected congeners (returned via `attr(result, "regional_unreferenced")`, same species/genus/family/observation_id shape) compete as named H2 hypotheses for the one query that rejected them, without being treated as globally unreferenced everywhere else. Fully backward compatible -- no existing caller's behavior changes. See `TaxaID/CLAUDE.md`'s Session 150 note for the full package-placement reasoning. |

### Coverage quality calibration

| Function | File | Status | Description |
|---|---|---|---|
| `calibrate_coverage_filter()` | `R/calibrate.R` | Written | Sweep a grid of coverage thresholds over `build_sequence_matrix()` output; return per-threshold breadth + H1/H2 discrimination metrics. Key columns: `breadth`, `h1_retention`, `h2_retention`, `youden_j` (primary — maximised at Pareto-optimal threshold), `discrimination` (ratio form), `mean_h1_score`. Detects categorical coverage (≤10 unique values) and messages that J will be near-flat. Auto-detects finest rank from `.x`/`.y` column pairs via `.detect_finest_rank_col()`. |
| `coverage_threshold()` | `R/calibrate.R` | Written | Quantile-based shortcut: returns the coverage value at the `(1 − keep_frac)` quantile so that `keep_frac` of pairs are retained (default 0.95). For categorical coverage, snaps to the nearest unique value with a message showing the achieved retention fraction. |

### No-score (prior-only) pathway

Use `unreferenced_candidates()` + `assign_scores()` (score_type = "none" or
"probability"). `expand_consensus_candidates()` -- deprecated since Session
99 -- was removed entirely 2026-07-20 (see this file's top session note).

### Score-collapse detection and restoration

| Function | File | Status | Description |
|---|---|---|---|
| `detect_suppressed_candidates()` | `R/score_collapse.R` | Written | Diagnose which pipeline suppression rule(s) are active. Three rules: `"perfect_only"` (purity_threshold fraction of qualifying obs have only scores ≥ perfect_threshold); `"max_score_ties"` (multi-row obs all show uniform score); `"best_only"` (singleton_threshold fraction of obs have exactly 1 row). `purity_threshold` (default 0.99) and `perfect_threshold` (default 100) user-settable. Returns list: rule_detected, rules, individual logicals, diagnostic counts, example_observations. |
| `restore_suppressed_candidates()` | `R/score_collapse.R` (+ `R/restore_hierarchy.R`) | Written | **Redesigned 2026-07-18** (`ecosystem_docs/SPEC_restore_suppressed_candidates_redesign.md`, see this file's own top session note for the full record) -- appends same-genus congeners from `reference_df` as `hypothesis_type = "suppressed_candidate"` rows, admitted under Purpose A (`restoration_basis = "competitive_score"`, prior-agnostic score-only outlier test, needs `model_params`) and/or Purpose B (`"plausible_prior"`, wide `max_dist` floor, gated by `candidate_species_filter`) -- every observation is checked unconditionally now, not gated by a detected pipeline rule. Score imputation sources from a cheap-to-expensive hierarchy (`R/restore_hierarchy.R`'s `.resolve_hierarchy_score()`/`.worth_level4_check()`), median-aggregated, not the old flat `anchor_score - delta`; `delta` now only affects the unchanged no-score (Rule 3) synthetic-score pathway. **Level 4 cost control, revised 2026-07-18 (Option A+C, see this file's own top session note):** `candidate_species_filter` is Level 4's own default gate again (falls back to the `taxaexpect_priors` ratio only for a candidate not on it); new `max_level4_per_anchor` param (default `10L`) is an independent hard backstop cap. Real, measured result on both motivating cases: Fundulus 275.8s -> 66.5s, Girella 7.0s -> 2.4s, correctness preserved (if anything strengthened) in both. No-score path: creates synthetic `score_original` column (H1 = 1.0, restored = 1.0 − delta/100); pass to `assign_scores(score_type = "direct")`. Returns match_obj with `is_restored`/`restoration_basis` columns. `detected`/`perfect_threshold`/`purity_threshold`/`singleton_threshold` params removed (no longer consulted -- `detect_suppressed_candidates()` itself is unchanged and still useful standalone). **BREAKING**: the scored pathway is now a no-op without real evidence (`seq_matrix` and/or `check_regional_overlap = TRUE`) -- see the top session note. The `.check_regional_overlap()`-based mechanics below (Tiers 1/2a/2b, `align_cache`, `candidate_species_filter`'s original performance-filter role) are historical -- **Session 159**: new opt-in `check_regional_overlap = FALSE` param -- when `TRUE`, a same-genus congener is only restored if there's real evidence its own reference overlaps the SAME genomic position as the observation's top-hit ("anchor") reference, not just that it has some reference somewhere in `reference_df`. Uses new internal `.check_regional_overlap()`, three ways to reach a verdict (Tier 1 the safe default, free `seq_matrix` lookup; Tier 2a, needs `subject_start`/`subject_end` from a live BLAST run; Tier 2b, new `sequence_col` param, derives the anchor's hit position on the fly from a raw query sequence when NO live BLAST step exists at all, e.g. this ecosystem's PtConception 12S/18S workflows -- see that helper's own header comment and this file's Session 159 notes for the full mechanism, including a real design flaw found and fixed before landing). Fully backward compatible; default `FALSE`/`sequence_col = NULL` behaves identically to before this feature existed. **Session 159 (final entry):** a congener rejected by `check_regional_overlap` is no longer just dropped -- it's now recorded (`observation_id`/`species`/`genus`/`family`, one row per rejection) and returned via `attr(result, "regional_unreferenced")` (`NULL` if nothing was ever rejected). Feed this straight into `expand_unreferenced_hypotheses()`'s `unreferenced_df` (its new `observation_id`-scoping, same session) to let a globally-referenced-but-regionally-rejected species still compete as a named `unreferenced_species` hypothesis for the one query that rejected it. Closes the real "outcome didn't change" gap the earlier Session 159 entries left open. **Session 159 (continued yet further):** three real bugs found live-testing against actual Mugu data. (1) The `check_regional_overlap` per-observation loop now runs for every observation when `check_regional_overlap = TRUE`, regardless of `detect_suppressed_candidates()`'s global verdict -- real BLAST data with a wide `score_range` is often a genuine mix of true singletons and real ties, so no global purity threshold fires even though individual singletons are exactly what this mechanism exists to help; safe because every addition is still evidence-gated. (2) New `align_cache` internal mechanism (an environment, created once per call) memoizes `.check_regional_overlap()`'s expensive per-`(anchor, candidate)` alignment across observations sharing an anchor -- fixes a real 15+-minute run (401 real observations, only 71 distinct anchors, one reused 113 times). (3) New `candidate_species_filter = NULL` param restricts which same-genus congeners get checked at all, before any expensive work -- without it, a genus with many globally-referenced species (real data: 42 in one genus) forces alignment against every one regardless of local relevance; passing `unique(taxaexpect_priors$taxon_name)` cut a real 2,361-pair run to 416 pairs and 38 seconds (timed, not estimated). `devtools::test()` 768/768 (up from 754), `devtools::check()` 0/0/0. **Session 159 (PtConception rollout, 2026-07-17):** two more real `.check_regional_overlap()` perf bugs found profiling real PtConception 12S data, both fixed via `align_cache` (same mechanism, new fixed/scoped keys, no signature change): Tier 2b's query-vs-anchor alignment was recomputed once per candidate species instead of once per (anchor, query_sequence); Tier 1's `seq_matrix` id-stripping `sub()` call was recomputed on every single call against the full `seq_matrix` (real data: ~3M rows) instead of once. The second was by far the larger cost (>90% of wall time in profiling). Real timed result: 84s → 6.8s on a 300-obs anchor-clustered subset; ~65min → ~17min extrapolated for the full 13,442-observation dataset. |

**Motivation:** When BLAST uses a 100-percent rule (drop all sub-perfect hits when a perfect match exists), referenced congeners are silently suppressed. `evaluate_likelihoods()` sees only one H1 candidate (singleton mode — gap uninformative) and generates only generic `unreferenced_species` H2/H3 rows. `restore_suppressed_candidates()` replaces those generic placeholders with real referenced alternatives, enabling full bivariate-normal evaluation. See *Girella simplicidens* case (Session 101/103).

### Match object cleaning and export

| Function | File | Status | Description |
|---|---|---|---|
| `remove_flagged_references()` | `R/clean.R` | Written | Remove mislabeled accessions from match_df using `flag_reference_errors()` output. Handles version suffix stripping. `remove_unverified_singletons` param (default FALSE). |
| `write_reference_fasta()` | `R/write_fasta.R` | Written | Export `reference_df` to FASTA + optional companion taxonomy TSV. FASTA header: `>{composite_id} {rank vals}` (NA ranks omitted). TSV is positional format compatible with `read_reference_fasta(taxonomy_file=)`. `rank_system` auto-detected when NULL. |
| `build_site_reference()` | `R/build_site_reference.R` | Written | High-level site-specific reference builder (DNA only). taxa list → `fetch_reference_sequences()` → optional `flag_reference_errors()` → `audit_barcode_coverage()` → `write_reference_fasta()`. Returns `list($reference_df, $errors, $census, $unreferenced)`. `output_dir` param writes `reference.fasta` + `reference_taxonomy.tsv`. |

### Diagnostics

| Function | File | Status | Description |
|---|---|---|---|
| `interpret_model()` | `R/interpret.R` | Written | Summarise trained model: expected match %, gap, per-species profiles |

### Reporting

| Function | File | Status | Description |
|---|---|---|---|
| `report_likelihood()` | `R/report_likelihood.R` | Written | Generate `report_section` summarizing model training (n_species, AIC, anchoring, mislabel detection). For `assemble_report()`. |

### Internal helpers (not exported)

| Function | File | Description |
|---|---|---|
| `.normalize_scores()` | `R/normalize.R` | Normalise raw scores to (0,1); clip for logit |
| `.prep_training_data()` | `R/train.R` | Logit-transform, compute within-species pairs + gap |
| `.evaluate_one_query()` | `R/evaluate.R` | Per-query H1/H2/H3 likelihood calculation |
| `.detect_finest_rank_col()` | `R/calibrate.R` | Auto-detect finest rank from paired `.x`/`.y` columns using `TaxaTools::standard_ranks`; used by `calibrate_coverage_filter()` |
| `.build_search_term()` | `R/fetch.R` | Construct NCBI nucleotide search query from taxon + barcode_term + dates |
| `.fetch_summaries_batched()` | `R/fetch.R` | Batched NCBI summary retrieval (accession, taxid, length); exponential backoff |
| `.fetch_taxonomy_map()` | `R/fetch.R` | Batched NCBI taxonomy XML → full lineage lookup table |
| `.fetch_fasta_batched()` | `R/fetch.R` | Batched FASTA download from NCBI nucleotide |
| `.parse_fasta_text()` | `R/fetch.R` | Parse FASTA text into data.frame(composite_id, sequence) |
| `.parse_taxonomy_tsv()` | `R/fetch.R` | Parse 2-column taxonomy TSV (QIIME2/RESCRIPt/SILVA/MIDORI2) → data frame for `read_reference_fasta(taxonomy_file=)`. Skips header rows; calls `.parse_tax_string()` on unique strings only (efficient for large files). |
| `.parse_tax_string()` | `R/fetch.R` | Parse one semicolon-delimited taxonomy string; auto-detects prefix-style (`k__`, `d__`, etc.) vs positional format; maps to user-supplied `rank_system`. |
| `.crabs_std_hierarchy` | `R/fetch.R` | Character constant: standard 7-level CRABS/NCBI rank order used for positional taxonomy-string parsing. |
| `.resolve_hierarchy_score()` | `R/restore_hierarchy.R` | **2026-07-18.** Section 3a's score-sourcing hierarchy for `restore_suppressed_candidates()` -- Levels 1-3 (direct accession pair / any-accession species pair / genus-typical divergence), median-aggregated; returns unresolved when the Level 0 precheck fails, signalling the caller to try Level 4. |
| `.has_seq_matrix_presence()` | `R/restore_hierarchy.R` | Level 0 precheck -- does a SPECIES (any of its own reference accessions) appear anywhere in `seq_matrix` at all. Species-level, not accession-level (a species' non-anchor accessions can still rescue Level 2). |
| `.worth_level4_check()` | `R/restore_hierarchy.R` | **Renamed from `.worth_tier2_budget()`, 2026-07-18 (Option A cost-control redesign).** Level 4's own gate, two-tier: `TRUE` when `candidate_species_filter` is `NULL` or the candidate is on it (restored from the pre-redesign design, specifically for this one expensive step); otherwise falls back to the floor-vs-documented occurrence-prior ratio in `taxaexpect_priors` (`<= budget_ratio_cap`). Fixes a real gap the ratio-only version had: both real motivating anchors (`F. lima`, `Girella simplicidens`) are themselves absent from `taxaexpect_priors`, making the ratio uncomputable and the old version skip Level 4 for every candidate including the one that matters. |
| `.level4_attempt_allowed()` | `R/restore_hierarchy.R` | **New, 2026-07-18 (Option C backstop).** Hard cap (`max_level4_per_anchor`, default `10L`, `Inf` disables) on distinct candidates getting a live Level 4 alignment per anchor accession, independent of `.worth_level4_check()`. Cache-keyed per `anchor_accession` in the shared `align_cache`. |
| `.seq_matrix_partner_index()` / `.seq_matrix_lookup()` | `R/restore_hierarchy.R` | **New, 2026-07-19.** Real accession-indexed lookup of every `seq_matrix` pair, built once per call via `split()` and cached in `align_cache`, replacing Levels 0-3's old per-candidate linear `%in%` scan over the whole `seq_matrix` (R's `match()`/`%in%` rebuilds its hash table on every call, it doesn't cache across calls against an unchanging table). Found necessary live-testing the real 13,442-obs PtConception dataset (~590x faster on a repeated real `Sebastes` anchor; full dataset 70+min -> 42.1s). |
| `.build_restored_row()` | `R/score_collapse.R` | Shared row-builder for `restore_suppressed_candidates()`'s scored and no-score pathways -- copies rank columns from the reference row, rebuilds `taxon_name`, sets the imputed score/`hypothesis_type`/`restoration_basis`, and the `RESTORED_<accession>` provenance. |

---

## Workflow Scripts

Six self-contained workflow scripts in `inst/workflows/`, replacing the old
monolithic `inst/TaxaLikely_workflow.R` (retained for reference but superseded).

| # | File | Purpose | Key functions |
|---|---|---|---|
| 1 | `1_fetch_references_workflow.R` | Build `reference_df` from NCBI or local FASTA | `fetch_reference_sequences()`, `read_reference_fasta()` |
| 2 | `2_flag_errors_workflow.R` | Find mislabeled references; explore/tabulate/report | `build_sequence_matrix()` → `flag_reference_errors()` |
| 3 | `3_train_model_workflow.R` | Train likelihood model from DNA reference matrix | `build_sequence_matrix()` → `train_likelihood_model()` → `interpret_model()` |
| 4 | `4_score_to_likelihood_workflow.R` | Convert match scores to likelihoods for TaxaAssign | `evaluate_likelihoods()` → `filter_top_hypotheses()` |
| 5 | `5_audit_coverage_workflow.R` | Audit reference completeness; constrain likelihoods | `infer_exclude_predicted()` → `audit_barcode_coverage()` / `audit_reference_coverage()` → `apply_coverage_constraints()` |
| 6 | `6_no_score_pathway_workflow.R` | No-score pathway: build uniform likelihoods from consensus assignments | `unreferenced_candidates()` → `assign_scores(score_type = "none")` |

**Layer-1 (Session 124-126), separate naming convention (`ecosystem_docs/LAYER1_WORKFLOWS.md`):**

| File | Purpose | Key functions |
|---|---|---|
| `image_acoustic_likelihood_workflow.R` | Image + acoustic score-to-likelihood, TWO independent live sections (not a DEBUG_MODE variant switch — both real, both run in the same tutorial session): Section 1 consumes TaxaMatch's real iNat CV checkpoint (`score_type = "similarity_softmax"`, unbounded raw score); Section 2 consumes TaxaMatch's real BirdNET checkpoint (`score_type = "probability"`, already 0-1 bounded). **Session 128:** both sections now open with `correct_training_bias()` (Section 2 first joins real Xeno-canto `n_recordings` via `audit_acoustic_coverage(xc_recordings = TRUE)`), plus a before/after honesty-check comparing corrected vs. uncorrected top-1 accuracy | `correct_training_bias()` → `unreferenced_candidates()` → `assign_scores()` |
| `sequence_likelihood_workflow.R` (Session 126) | Sequence/BLAST score-to-likelihood — the ONE Layer-1 data type needing the actual bivariate-normal self-vs-non-self model (no pre-trained classifier to calibrate). Consumes TaxaMatch's real `blast_sequences_workflow.R` checkpoint (5 real PtConception 12S queries) as the query side; fetches a real NCBI reference database live (6 genera / 3 fish families) as the training side. | `fetch_reference_sequences()` → `build_sequence_matrix()` → `calibrate_coverage_filter()` → `train_likelihood_model()` → `remove_flagged_references()` → `evaluate_likelihoods()` → `filter_top_hypotheses()` |

Workflows 2 and 3 share `build_sequence_matrix()` — build once, reuse.
Acoustic and image data use `unreferenced_candidates()` + `assign_scores()` (no training
step — classifiers are pre-trained; TaxaLikely acts as a post-classifier calibration layer).
Workflow 4 includes a one-liner to remove flagged errors from the match object
before evaluating likelihoods (no dedicated function needed).

### Other inst/ files

| File | Purpose |
|---|---|
| `inst/plot_likelihood_landscape.R` | Standalone two-panel visualization of H1/H2 density surfaces with example points (A/B/U). For presentations and manuscripts; not an exported function. |
| `inst/TaxaLikely_supplemental_methods.md` | Statistical methods background document adapted from early design docs; 10 sections covering the generative Bayesian framework, feature engineering, hypotheses, anchoring, and visualization. Future manuscript seed. |

---

## `model_params` Object (class `"taxa_model_params"`)

Output of `train_likelihood_model()`.

| Slot | Type | Description |
|---|---|---|
| `H1_Lookup` | data.frame | Per-species `lookup_key`, `rank`, `mu_score`, `mu_gap`, `sigma_score` (shrunk) |
| `H1_Global_Mu` | named numeric | Global fallback mean: `c(score_logit, gap_logit)`. |
| `H1_Sigma` | matrix | 2×2 global covariance over `(score_logit, gap_logit)`. |
| `H2` | list | Missing-species params: `delta` (logit offset from H1 mean, pooled across all genera), `sigma` (2×2). |
| `H3` | list | Missing-genus params: `delta`, `sigma` (2×2). |
| `H2_Lookup` | data.frame or `NULL` | **Session 151.** Per-genus H2 delta: `genus`, `n_pairs`, `delta_shrunk`. `NULL` when no genus in the training set had a real congener pair (or `rank_system` has no genus-level rank). Genera absent from this table simply weren't estimable locally and use `H2$delta` unchanged. |
| `Stats` | list | Diagnostics: `AIC_Score`, `n_species`, `n_singletons`, `n_anchors`. |
| `reference_errors` | data.frame | Output of `flag_reference_errors()` (mislabeled + singleton flags). Use with `remove_flagged_references()` to clean match objects. Auto-used by `run_bayesian_pipeline()`. |

---

## Critical Design Decisions (Session 31)

### rank_system convention
**Always coarse-to-fine** (e.g., `c("family", "genus", "species")`).
The last element (finest rank) maps to `rank_code_a` internally.
This matches the order of taxonomy columns in the match object.

### p_match scale
`build_sequence_matrix()` outputs `p_match = 1 - distance` where distance is
from DECIPHER (0-1 scale). All downstream functions (`flag_reference_errors()`,
`.prep_training_data()`) expect **p_match on 0-1 scale**.
The `score` column in the match object (input to `evaluate_likelihoods()`) can
be on either 0-1 or 0-100 scale -- `.normalize_scores()` auto-detects.

### H2/H3 sigma slots
`H2$sigma` and `H3$sigma` are **2×2 matrices** matching `H1_Sigma`. Dimnames:
`c("score_logit", "gap_logit")`.

### H2/H3 filtering
H2 and H3 hypotheses CAN be filtered out by `ratio_threshold` when scores
are high (the missing-taxon distribution is far from the observed scores).
This is correct behavior -- TaxaAssign treats absent rows as likelihood = 0.
Use `ratio_threshold = 0` to always retain all three hypothesis types.

### Rank generalization
`f_generalize_taxonomy_ranks()` from UBC is implemented inline in
`.prep_training_data()` as `.generalize_ranks()`. Not exported.
`f_ungeneralize_taxonomy_ranks()` from UBC is **dead code** -- never
used in the original source. Dropped entirely.

### TaxaTools::create_taxon_names() usage
Called inside `.evaluate_one_query()` to derive `taxon_name` + `taxon_name_rank`
for H2/H3 rows (where finest rank(s) are set to NA before calling).
Must be installed; it is in Imports.

---

## Test Coverage

All tests are fully offline (no NCBI, no DECIPHER, no external files) except `test-build.R`
which is skipped when DECIPHER/Biostrings are not installed.

| File | Functions covered | Notes |
|---|---|---|
| test-assign-scores.R | `assign_scores()` | Covers all score_type values including `"direct"`, H2/H3 anchoring, H4 behavior, single-H1 caveat |
| test-build.R | `build_sequence_matrix()` | Skipped when DECIPHER not installed (Bioconductor Suggests) |
| test-build-site-reference.R | `build_site_reference()` | Offline via `local_mocked_bindings()`; 17 tests + 1 skip (DECIPHER present) |
| test-clean.R | `remove_flagged_references()` | Fully offline |
| test-compute-likelihoods.R | `compute_likelihoods()`, `model_likelihoods()` | Fully offline with minimal model_params fixture |
| test-coverage.R | `audit_reference_coverage()`, `audit_acoustic_coverage()`, `apply_coverage_constraints()`, `calibrate_coverage_filter()`, `coverage_threshold()` | Fully offline |
| test-evaluate.R | `evaluate_likelihoods()`, `filter_top_hypotheses()` | Fully offline |
| test-fetch.R | `read_reference_fasta()`, `.parse_taxonomy_tsv()`, `.parse_tax_string()` | Fully offline; NCBI fetch tests skipped |
| test-interpret.R | `interpret_model()` | Fully offline with minimal model_params fixture |
| test-normalize.R | `.normalize_scores()` | Fully offline |
| test-read-crabs.R | `read_crabs_output()`, `read_reference_fasta(taxonomy_file=)` | Fully offline; 16 + 7 tests |
| test-report_likelihood.R | `report_likelihood()` | Fully offline |
| test-subset-local-database.R | `subset_local_database()` | Fully offline; 25 tests; gz FASTA, pre-parsed taxonomy df, filters |
| test-train.R | `train_likelihood_model()`, `flag_reference_errors()` | Fully offline |
| test-unreferenced-candidates.R | `unreferenced_candidates()` | Fully offline |
| test-write-fasta.R | `write_reference_fasta()` | Fully offline |
| test-score-collapse.R | `detect_suppressed_candidates()`, `restore_suppressed_candidates()`, `.check_regional_overlap()` | 65 test_that blocks (up from 46, 2026-07-18 redesign + Option A/C cost-control revision); fully offline; covers all 3 detect rules, no-score path, check_regional_overlap (Tiers 1/2a/2b), `align_cache` memoization, `.check_regional_overlap(return_detail = TRUE)`'s pid output, the score-sourcing hierarchy (seq_matrix-based imputation, median aggregation, Level 0 routing to Level 4), Purpose A/B admission (`restoration_basis` values via a real `model_params` fixture), the `.worth_level4_check()` two-tier gate (`candidate_species_filter` default, ratio fallback for a candidate not on it), the `.level4_attempt_allowed()` per-anchor cap (`max_level4_per_anchor`), the `regional_unreferenced` attribute's `basis` column (`regional_reject` vs `no_reference_data`), and the no-evidence no-op behavior change |
| test-expand_unreferenced.R | `expand_unreferenced_hypotheses()` | 20 test_that blocks; fully offline; covers H2/H3 expansion, species-level suppression, genus-rank suppression, extra-column passthrough, and the Session 159 `observation_id`-scoped unreferenced_df extension |

---

## Statistical Design Notes

- **Score metric:** any raw match score; normalised to (0,1) then logit-transformed
- **Gap metric:** best-match logit score minus second-best logit score -- key discriminator
- **H1 (Known Species):** bivariate normal over `(score_logit, gap_logit)`.
  Species-specific score + gap means with Empirical Bayes shrinkage toward global mean.
- **H2 (Missing Species):** H1 distribution shifted left by `H2$delta` on score axis.
- **H3 (Missing Genus):** shifted further left by `H3$delta` = `H2$delta + 2.0`
- **Singleton queries:** 1D normal (score only) when only one candidate exists (gap uninformative).
- **Pseudo-data anchoring:** `anchor_perfect = TRUE` (default) injects synthetic
  perfect-match rows (score = logit(1-ε), gap = 95th percentile of real positive gaps)
  into training data. Prevents the "perfection penalty". Count = max(5, 10% of data).
- **Shrinkage:** `w = N / (N + prior_weight)`; per-species score variance + gap mean shrunk
  toward global. Default `prior_weight = 10.0`.
- **Per-species sigma floor (Session 121):** At inference, `use_sigma[1,1]` is floored at
  `global_sigma[1,1]` before evaluating H1 density. Species-specific sigma can be
  artificially tight for well-sampled species whose NCBI reference sequences are
  near-identical clones; tight sigma causes the Mahalanobis distance to balloon for
  realistic eDNA query scores, driving H1 likelihood near zero. The floor ensures the
  per-species distribution is never narrower than the global empirical distribution.
  Applied in `.evaluate_one_query()` after loading `sp_var` from `H1_Lookup`.
- **Score-only outlier filter, `alpha = 0.001` (Session 121):** Before computing H1
  density, `.evaluate_one_query()` tests whether the query score is consistent with the
  H1 species distribution via a univariate chi-squared test (df = 1, **score only**,
  not 2D bivariate). If `p_val < alpha`, H1 likelihood = 0. Gap excluded from this test:
  a small gap (confusable congener present) lowers the bivariate density correctly without
  spuriously rejecting the H1 candidate. Including gap in the outlier check rejected
  legitimate H1s in species-rich families (Leptocottus at 99% dropped because
  Agonomalus at 99% gave a tiny gap, inflating 2D chi-sq past threshold). Default alpha
  changed from `1e-6` → `0.001` (~3.3 sigma). Cyprinidae at 91–93% (>4 sigma from
  H1 mean, p < 0.001) drop; coastal species at 99% (~2.7 sigma, p ≈ 0.006) retained.
- **Monte Carlo:** n_sims perturbations of score_logit → `score_likelihood_mean` + `score_likelihood_sd`.
- **Median-across-references:** `evaluate_likelihoods()` takes the **median** score
  per taxon_name across multiple reference accessions before likelihood calculation.
- **Coverage filter (not a model dimension):** pass `min_coverage` to `evaluate_likelihoods()`
  to pre-filter candidates below an alignment/detection quality threshold. Use
  `calibrate_coverage_filter()` on the training matrix to find the Pareto-optimal threshold.

---

## Known Footguns

### trim_to_amplicon() rescued 0/107 over-length real Sebastes 12S sequences -- RESOLVED: not a trimming bug, but exposes that build_sequence_matrix()'s default length filter is too permissive for cross-source comparability (found + resolved manuscript-support session, 2026-07-07)
Live-fetched 238 real `Sebastes` (rockfish) 12S sequences from NCBI (`fetch_ncbi_reference_sequences(taxa = "Sebastes", barcode_term = "12S", max_per_species = 20L)`) while confirming a BayesianID_perspective manuscript claim outside this package (see `diagnostics/sebastes_chromis_confirmation.R`). 107 of 238 exceeded `max_len` (210bp) and were passed through `trim_to_amplicon(barcode_term = "MiFishU")` -- **0 of 107 were successfully trimmed**. The same 0%-rescue result then recurred on a second, unrelated genus (`Paralabrax`, kelp bass/sand bass): all 22 fetched sequences were ~415-600bp and 0/22 trimmed.

**Root cause, confirmed empirically (not a `trim_to_amplicon()` bug):** manually searched a real over-length `Paralabrax` sequence for both MiFish primers, both strands, allowing up to 6 mismatches (`Biostrings::matchPattern(..., max.mismatch = 6, fixed = "subject")`) -- **zero hits in any of the 4 combinations**. NCBI's `"12S"` free-text search term matches any GenBank record describing the 12S rRNA gene, not just MiFish-primer amplicons -- many real records (older Kocher-primer studies, broader mitochondrial fragments, etc.) cover a genomically different stretch of the same gene that never overlaps the MiFish binding sites at all. A 0% rescue rate is therefore correct behavior for these particular records, not a defect in the trimming logic. `trim_to_amplicon()`'s own synthetic test fixtures (Sessions 140-142) all embed a matchable primer site by construction, so this "real record has no primer site to find" case was never exercised until now.

**The more consequential, broadly-actionable finding:** `build_sequence_matrix()`'s default `min_seq_len = 100L, max_seq_len = 2000L` is wide enough that it does **not** filter out these off-target, non-MiFish-window sequences -- they pass straight into alignment and pairwise-distance calculation alongside genuine short MiFish-amplicon sequences. For `Sebastes`, this went unnoticed at first because DECIPHER's alignment coincidentally produced high divergence (and thus exclusion via the `distance < 0.25` pair-retention step) for most such cross-window pairs -- but for `Paralabrax`, ALL fetched sequences were off-target long fragments, so the *entire* resulting seq_matrix was built from a different genomic window than intended, silently invalidating a same-species vs. congeneric %-match comparison that looked superficially normal (non-empty, plausible-looking output). This would not have been caught without an independent, methodologically-motivated reason to compare two genera against each other and notice the numbers looked inconsistent.

**How to apply:** when reference sequences are fetched by a broad NCBI text search term (e.g. `barcode_term = "12S"`) rather than sourced from a curated amplicon-only database, do not trust `build_sequence_matrix()`'s default length filter to guarantee amplicon-window comparability across taxa/sources -- it only guards against absurdly short/long sequences, not "same region as every other sequence in this matrix." Explicitly filter `reference_df` to the registered amplicon length range first (`TaxaTools::resolve_barcode_lengths("MiFishU")` gives `130-210`bp for MiFish-U/E) before calling `build_sequence_matrix()`, especially when comparing results *across* separately-fetched taxon sets rather than just running one self-contained pipeline. See `diagnostics/sebastes_chromis_confirmation.R` for the corrected pattern.

**UPDATE (Session 151, ecosystem soundness-review item 13):** the manual pre-filter above is now built into `build_sequence_matrix()` itself via a new `barcode_term` param -- `build_sequence_matrix(reference_df, ..., barcode_term = "MiFishU")` auto-resolves and applies the same length window (explicit `min_seq_len`/`max_seq_len` still override). The nuance from this footgun still applies to the new parameter, not just the old manual pattern: pass a *specific registered primer variant* (`"MiFishU"`), not just a bare marker name (`"12S"`, which resolves to a much wider 100-600bp range) -- only the specific-variant term gives the real amplicon-window guarantee this footgun is about.

### .xc_recording_count() required v2 -> v3 migration (found Session 124, FIXED Session 125)
`.xc_recording_count()` (`R/coverage.R`), used by
`audit_acoustic_coverage(xc_recordings = TRUE)`, called the dead
`https://xeno-canto.org/api/2/recordings` endpoint (404 unconditionally as of
Session 124's Xeno-canto migration). Because it checked `resp_status(resp) != 200L`
and returned `NA_integer_` on any non-200, the failure was **silent** -- the same
"silently degrades instead of erroring" pattern as the `.resolve_llm_fn()` footgun in
`TaxaID/CLAUDE.md`. Fixed Session 125: switched to
`https://xeno-canto.org/api/3/recordings`, added a required `key` query param read from
the `XC_API_KEY` environment variable (register at xeno-canto.org/explore/api; set via
`~/.Renviron`), and rewrote the query from v2's free-text to v3's tag-based syntax
(`gen:{genus} sp:{species} type:call`). If `XC_API_KEY` is unset, the function now warns
explicitly and returns `NA_integer_` (no longer silent). Live-verified against 4 real
species (`Turdus migratorius`, `Setophaga petechia`, `Limosa fedoa`,
`Selasphorus calliope`) via both `.xc_recording_count()` directly and
`audit_acoustic_coverage(xc_recordings = TRUE)` end-to-end -- all returned real,
non-NA counts.

### TaxaTools::create_taxon_names() must be installed
`evaluate_likelihoods()` calls `TaxaTools::create_taxon_names()`. If TaxaTools
is not installed (e.g., in test environments), tests that call `evaluate_likelihoods()`
will fail. Guard with `skip_if_not_installed("TaxaTools")`.

### build_sequence_matrix() needs DECIPHER + Biostrings (Suggests)
These are Bioconductor packages. Install with `BiocManager::install("DECIPHER")`.
They are in Suggests, not Imports -- not loaded at package startup.
The function checks for them at runtime.

### lme4 hierarchy fitting with small data
`train_likelihood_model(use_hierarchy = TRUE)` requires enough taxonomic levels
(>= 2 rank columns in training data) and sufficient variance across ranks for
lme4 to converge. Falls back gracefully to global mean with a message.

### Single H2/H3 anchor — non-best genera get no unreferenced hypothesis
`.evaluate_one_query()` generates exactly one H2 row (unreferenced species in the
best candidate's genus) and one H3 row (unreferenced genus in the best candidate's
family), both anchored at the single globally best-scoring candidate. This is
intentional: when one genus clearly dominates, its unreferenced congeners are the
relevant alternative hypotheses, and the gap feature already signals ambiguity when
genera are nearly tied. The implicit assumption is that near-tied multi-genus
observations are routed through the consensus/upranking pathway (uniform likelihoods)
rather than `evaluate_likelihoods()`. Known limitation: near-tied multi-genus queries
that bypass upranking will not receive unreferenced hypotheses for the non-best genus.

### expand_unreferenced_hypotheses() workflow order
`expand_unreferenced_hypotheses()` must run **before** `apply_coverage_constraints()`.
Coverage constraints operate on `hypothesis_type` and `taxon_name`; if constraints are
applied first (zeroing the generic H2 row), expansion will produce named rows with
non-zero likelihoods that bypass the constraint. Correct order:
`evaluate_likelihoods()` → `filter_top_hypotheses()` → `expand_unreferenced_hypotheses()`
→ `apply_coverage_constraints()`.

---

## Session Notes

**Session 142 (2026-07-06): trim_to_amplicon() now supports the real eDNA COI mini-barcode (coi-leray)**

Direct same-day follow-on to Session 141, which explicitly flagged the Leray et al.
(2013) mini-barcode (mlCOIintF/jgHCO2198, the actual ~313bp fragment most real COI
metabarcoding studies use -- not `coi-folmer`'s full-length ~710bp Sanger-era product)
as unimplemented, blocked by Geller et al. (2013)'s `jgHCO2198` reverse primer using
inosine (dITP), a base analog `Biostrings::DNAString` has no representation for. The
user asked to learn more about the mini-barcode's discriminatory-power tradeoffs before
deciding whether to invest in solving that.

**No code change needed in this package again** -- all the work was in
`TaxaTools::barcode_primer_defaults` gaining a `coi-leray` entry (pairs Leray's own
inosine-free forward primer with Meyer (2003)'s inosine-free degenerate reverse primer
`dgHCO2198` instead of Geller's, a real published pairing, not an invented workaround --
see `TaxaTools/CLAUDE.md`'s own Session 142 note for the full verification record and
the discriminatory-power literature summary). `trim_to_amplicon(barcode_term =
"COI-Leray")` resolves through the same already-generic path as every other marker.

New test confirms `trim_to_amplicon()` correctly extracts a real, literature-verified
Leray-fragment amplicon from a synthetic over-length sequence (same fixture pattern as
the Session 141 markers); one existing test that had assumed bare `"COI"` resolved
uniquely (updated to `"COI-Folmer"` explicitly, since `"COI"` alone is now ambiguous
between `coi-folmer` and `coi-leray` -- confirmed by a new test that this errors rather
than silently picking one). `devtools::test()` (58/58 in `test-trim-to-amplicon.R`;
full suite 609 passing, up from 605, 0 failures, same 15 pre-existing unrelated
warnings) + `devtools::check()` (0 errors, 0 warnings, 0 notes) all clean.

**Still not implemented**: the more-degenerate "Leray-XT" mlCOIintF variant (partially
mitigates, but doesn't eliminate, the primer-mismatch-driven non-amplification in
certain marine zooplankton taxa noted in the discriminatory-power review); any
vertebrate-tolerant COI primer pair (Folmer's own known limitation, noted Session 141,
remains unaddressed); wiring `trim_to_amplicon()` into any production workflow script.

**Session 141 (2026-07-06): trim_to_amplicon() now covers every mito/chloroplast marker, not just MiFish-12S**

Same-day follow-on to Session 140. The user asked two things directly: (1) is
primer-based trimming actually worth it for 12S, or better to just drop over-length
sequences? (2) work through the rest of the mitochondrial and chloroplast markers in
`TaxaTools::barcode_length_defaults` (nuclear genes -- 18S, ITS, ITS2 -- explicitly
excluded per the user's own instruction, since none of them has one canonical primer
pair to verify the way every mito/chloroplast marker does).

**Opinion on 12S**: yes, practical -- the fallback is always exactly today's
length-exclusion behavior (this function can only rescue sequences that would
otherwise be lost, never discard ones that would otherwise be kept), the primer
specificity plus length-plausibility gate make a spurious accept astronomically
unlikely, and the problem is already observed on real data (Session 139's "No H1
pairs found" bug).

**No code changes needed in this package.** `trim_to_amplicon()` was already fully
generic over `barcode_term` -- all the new-marker work happened in
`TaxaTools::barcode_primer_defaults`, which gained 6 new entries (16S, COI, cytb,
rbcL, matK, trnL), each verified against 2-3 independent literature sources AND
empirically tested with `Biostrings::matchPattern()` against a real GenBank
mitogenome or chloroplast genome fetched live via NCBI eutils -- not just trusted from
citation text. This caught two real errors a literature-only check would have missed
(a wrong cytb amplicon length repeated by two secondary sources -- corrected from a
mistaken 309bp to the empirically-measured 358bp -- and a genuine forward/reverse
mislabeling in an otherwise-authoritative matK primer table, resolved by testing both
orientations directly against real chloroplast DNA). Full verification record is in
`TaxaTools/CLAUDE.md`'s own Session 141 note.

Added 21 new offline tests here confirming the *consuming* side works correctly with
the newly-registered primers: real COI-Folmer and rbcLa pairs each correctly extract
from a synthetic over-length sequence built around them, plus a loop test exercising
all 6 new registry entries end-to-end through `trim_to_amplicon()` itself (not just
through the registry lookup, which `TaxaTools`'s own tests already cover). One
existing test's example marker changed from `"COI"` (now registered, so no longer a
valid "unregistered marker" example) to `"ITS2"`.

`devtools::test()` (54/54 in `test-trim-to-amplicon.R`; full suite 605 passing, up
from 588, 0 failures, same 15 pre-existing unrelated warnings) + `devtools::check()`
(0 errors, 0 warnings, 0 notes) all clean.

**Still deliberately unimplemented**: 18S/ITS/ITS2 primer entries (no canonical pair
to verify); wiring `trim_to_amplicon()` into any production workflow script (still
the case from Session 140); the Geller et al. (2013) jgLCO1490/jgHCO2198 redesigned
COI primers, which use inosine (`I`) -- not a standard IUPAC symbol
`Biostrings::DNAString` supports, so they can't be implemented with the current
algorithm without a lossy `N`-substitution approximation that wasn't attempted this
session; and the Leray et al. (2013) mlCOIintF/jgHCO2198 mini-barcode ("Leray
fragment"), the actual eDNA-relevant COI marker, blocked by the same inosine issue on
its reverse primer.

**Session 140 (2026-07-06): trim_to_amplicon() -- in-silico PCR amplicon extraction, implements the Session 139 reentry design doc**

Implements `ecosystem_docs/REENTRY_PROMPT_session139_insilico_pcr_amplicon_trimming.md`
in full. That doc deliberately stopped short of recommending answers to its own open
design questions (package placement, primer scope, naming) -- resolved with the user at
the start of this session before writing any code:

- **Package placement** (design question 4): user pushed back on the doc's own
  TaxaLikely recommendation, asking for the TaxaMatch/TaxaFetch alternatives to be
  argued through rather than assumed. Worked through it explicitly: TaxaFetch only ever
  handles *occurrence* data (GBIF/DataONE), never reference sequences, so it doesn't
  fit despite the name. TaxaMatch has the raw-sequence/`Biostrings` tooling but is
  strictly query-side (`TaxaMatch → TaxaLikely`, one direction) -- putting a
  reference-database-shaping function there would either reverse that dependency
  direction or split one pipeline stage across a package boundary. TaxaLikely already
  owns the entire reference-fetch/reference-QC pipeline this slots into
  (`fetch_ncbi_reference_sequences()`, `read_reference_fasta()`,
  `build_sequence_matrix()`, `audit_barcode_coverage()`) with no new cross-package
  dependency either way. User confirmed TaxaLikely on that reasoning.
- **Primer scope** (design question 1): user's own framing was that the package should
  stay generic to marker type, populate the registry only where the "long submission
  contaminates the short-barcode training set" problem is real and a primer pair can be
  verified, and have a fallback plan (point users at CRABS pre-trimming, and confirm a
  length-based exclusion filter already exists) if broader coverage turns out to be too
  much work. Landed on: `trim_to_amplicon()` itself is fully generic (any primer pair
  via `primer_fwd`/`primer_rev` works, registry lookup via `barcode_term` is a
  convenience, not a requirement); the registry itself is populated only with MiFish-U/E
  (12S) this session -- the only marker with real production use in this ecosystem
  (confirmed by grep: every real `barcode_term` ever passed by a live workflow is
  `"MiFishU"`) and a single, well-established, verifiable primer pair. Confirmed the
  fallback length filter already exists and needed no new work:
  `build_sequence_matrix()`'s existing `min_seq_len`/`max_seq_len` step (`R/build_sequence.R`,
  "LENGTH FILTER" section) already excludes anything `trim_to_amplicon()` can't rescue,
  exactly as before this session -- this function only ever adds sequences that would
  otherwise be lost, never removes ones that would otherwise be kept. 18S was
  deliberately NOT given a registry entry: unlike MiFish, there is no single canonical
  18S primer pair (the existing `barcode_length_defaults` comment already flags "varies
  widely by primer set") -- inventing one would be exactly the unverified-citation risk
  the reentry doc warned against. 18S callers must supply `primer_fwd`/`primer_rev`
  directly from their own wet-lab protocol, or pre-trim with CRABS.
- **Naming** (design question 4b): `trim_to_amplicon()` / `barcode_primer_defaults`,
  user's direct choice over the doc's `extract_amplicon()` alternative.

**Primer sequences verified, not trusted from memory.** Per the reentry doc's explicit
instruction ("citing real primer papers... is real work, not a placeholder task"), used
live web search to cross-check the MiFish-U/E sequences against Miya et al. (2015)'s own
primary text plus two independent secondary sources (a university core-facility protocol
page, a GitHub pipeline's README) before adding them to
`TaxaTools::barcode_primer_defaults` -- all three agreed verbatim:
MiFish-U-F `GTCGGTAAAACTCGTGCCAGC` / MiFish-U-R `CATAGTGGGGTATCTAATCCCAGTTTG`
(amplicon 163-185bp); MiFish-E-F `GTTGGTAAATCTCGTGCCAGC` / MiFish-E-R
`CATAGTGGGGTATCTAATCCTAGTTTG` (amplicon 170-185bp). New
`TaxaTools::resolve_barcode_primers()` deliberately does *not* mirror
`resolve_barcode_lengths()`'s substring-prefix convenience matching for a bare
`"mifish"` -- U and E have genuinely different primer sequences, so an ambiguous term
errors with guidance instead of silently picking one (see `TaxaTools/CLAUDE.md`'s own
Session 140 note).

**Algorithm choices empirically verified via real `Biostrings` calls before being
written into the function**, not assumed from documentation alone: confirmed
`Biostrings::matchPattern(fixed = FALSE)` produces spurious matches across long
N-runs (ambiguity codes in the *subject* matching every primer base for free), and that
`fixed = "subject"` (the reentry doc's own suggested value) correctly avoids this while
still letting a degenerate primer base match a literal subject base -- reproduced both
behaviors directly in a throwaway script before committing to the design. Also
empirically confirmed the both-strand search (via `Biostrings::reverseComplement()`)
correctly recovers a primer pair when a sequence was deposited on the opposite strand,
and that `max.mismatch` tolerates a real single-base substitution at a primer-binding
site. `Biostrings::start()`/`end()` must be called via explicit `::` (a bare `start()`
resolves to base R's own S3 generic and silently returns wrong values for an
`XStringViews` object) -- caught by testing this directly rather than assuming.

**Implausible-span guard**: an extracted "amplicon" is only accepted if its span falls
within `[min_len, max_len]` (from `barcode_length_defaults` via `barcode_term`, or
supplied directly) -- without this, a spurious far-apart primer pairing inside a large
sequence could produce a near-original-length "amplicon" that passes through
undetected. Caught by an early test failure during development (a deliberately
long-interior synthetic fixture) before it could reach real data.

37 new offline tests (`test-trim-to-amplicon.R`), all using real, verified MiFish-U
primer sequences embedded in synthetic flanking contexts rather than fabricated
primers -- covers: already-short sequences left untouched; correct extraction on the
sense strand; correct extraction when the sequence was deposited on the antisense
strand; single-base-mismatch tolerance and its rejection at `max_mismatch_rate = 0`;
graceful fallback when a primer is genuinely absent; the implausible-span rejection;
explicit `primer_fwd`/`primer_rev` bypassing the registry; mixed-outcome multi-row
input; and non-IUPAC (protein-looking) sequences flagged rather than crashing. Plus 8
new offline tests for `TaxaTools::resolve_barcode_primers()`
(`test-barcode_utils.R`) covering exact/case/separator-insensitive matching, the
MiFish-U vs. MiFish-E distinction, the deliberate ambiguous-bare-term error, and input
validation.

Live-verified end to end against a realistic simulated 16kb mitogenome (random-sequence
flanks, not a repeated motif, to avoid an artificially easy case) containing a real
embedded MiFish-U amplicon: correctly extracted exactly 172bp -- matching Miya et al.
2015's own reported mean MiFish-U amplicon length -- while a co-occurring
already-short, already-primer-trimmed barcode submission (the common real deposition
convention) was correctly left untouched. This is the exact scenario that broke
`train_likelihood_model()` in Session 139 ("No H1 pairs found"), now rescuable instead
of being discarded outright.

`devtools::document()` + `devtools::test()` (TaxaTools: 77/77 in `test-barcode_utils.R`,
full suite unaffected; TaxaLikely: 37/37 in `test-trim-to-amplicon.R`, full suite 588
passing / 0 failures / 15 pre-existing unrelated warnings) + `devtools::check()` on both
packages (0 errors, 0 warnings, 0 notes) all clean.

**Not done / deliberately deferred**: no other marker besides MiFish-U/E was added to
`barcode_primer_defaults` -- 18S in particular was explicitly ruled out this session (no
single canonical primer set exists to verify); `trim_to_amplicon()` is not wired into
any of the four production `PtConceptionWorkflow_*`/`MuguFishWorkflow.R` scripts or the
Layer-1 `sequence_likelihood_workflow.R` -- those still use the length-exclusion-only
fix from Session 139's sibling GBIF reentry doc. BLAST-alignment-coordinate trimming
(the reentry doc's "ruled out as a shortcut" alternative) remains unimplemented and
unrevisited.

**Session 136 (2026-07-05): fetch_reference_sequences() renamed; real PR2 support added; BOLD wrapper work blocked by a live outage**

Follow-on from Session 135's `ecosystem_docs/EXTERNAL_DATA_SOURCES.md` work: reviewing
that table with the user identified BOLD Systems and PR2 as worth real engineering
investment (Macaulay Library explicitly dropped as too access-gated/legally risky).

**Rename**: `fetch_reference_sequences()` → `fetch_ncbi_reference_sequences()`. The old
name didn't say NCBI anywhere, which stopped being safe once a second live-API
reference source (BOLD) was on the table. Old name kept as a pure forwarding deprecated
alias (`.Deprecated()`, `@rdname` folding into the same Rd page), mirroring
`audit_barcode_coverage_ncbi()`'s existing pattern exactly. All internal call sites
updated to the new name directly: `build_site_reference()`, both `1_fetch_references_workflow.R`
and `sequence_likelihood_workflow.R`, `README.md`, and (cross-package)
`TaxaWizard`'s `taxa_to_refs.R`/`taxa_to_site_refs.R` snippets. The
`test-build-site-reference.R` mock bindings were also updated to target the new name —
missing this would have made the mocks silently stop intercepting, since
`local_mocked_bindings()` replaces by exact name.

**Real PR2 support** (`subset_local_database()`/`.parse_tax_string()`): downloaded a real
PR2 v5.1.1 release file (`pr2_version_5.1.1_SSU_mothur.tax.gz`, 240,201 records — the
smallest real release asset, not the multi-GB FASTA) to check PR2's actual taxonomy
string format directly rather than assume compatibility, per the plan's explicit
"verify before writing code" instruction. Confirmed PR2 uses a **fixed, always-9-level
positional format** (`domain;supergroup;division;subdivision;class;order;family;genus;species`,
100% uniform across all 240,201 records, no prefix codes) that does not match
`.crabs_std_hierarchy`'s 7-level kingdom-first shape either in count or rank names.
Added `.pr2_hierarchy` as its own constant and made `.parse_tax_string()`'s positional
branch dispatch on field count (exactly 9 → PR2; otherwise → the existing 7-level
constant) — a real, verified structural signal, not a heuristic guess. Two additional
real quirks found and deliberately preserved rather than "cleaned": plastid-derived
sequences suffix every taxonomic level with `:plas` (e.g. `Eukaryota:plas`) — collapsing
this would erase a real, scientifically meaningful ancestry distinction, so it's kept
as-is in the parsed value; and PR2's `species`-level values are underscore-joined and
often unresolved placeholder labels (e.g. `Rozellomycota_XXX_sp.`) rather than clean
binomials, left for callers to post-process if needed. Live-verified `.parse_tax_string()`
against the real 9-level, `:plas`-tagged, 7-level (MIDORI2), and prefix-style (SILVA/GTDB)
cases side by side to confirm no regression. 4 new offline tests added to
`test-subset-local-database.R` using the real downloaded strings verbatim (not
fabricated), all passing (37/37 in that file, 0 regressions).

**MIDORI2 license caveat**: added to `subset_local_database()`'s `@section Supported
database formats` — MIDORI2's license is reported as CC-BY-NC in secondary sources
(unconfirmed on the primary site, per `EXTERNAL_DATA_SOURCES.md`'s MIDORI2 row),
potentially in tension with this ecosystem's CC0/USGS public-domain policy. Flagged as
needing resolution before redistributing any cached MIDORI2-derived data. Documentation
only, no code change.

**BOLD: not an outage — a full API migration. Real API found, `fetch_bold_reference_sequences()`
built and shipped.** First diagnosis this session (see below) was wrong in framing, not
in observation: installed `bold` (ropensci/bold, archived from CRAN 2024-08-26) via
`remotes::install_github()` to live-verify its output before writing any reshape code,
per this session's "verify, don't guess" discipline, and both `bold_seqspec()` (returns
an HTML "BOLD Public Offline" page) and `bold_identify()` (crashes on non-XML content)
failed live. When the user reported BOLD's website looked up and asked to recheck,
further digging found the real cause: **BOLD migrated to an entirely new "v5" API in
2024; the old v3/v4 endpoints the `bold` package targets are permanently retired, not
temporarily down.** Found and fully live-tested the real replacement: BOLD's v5 Data
Portal API (`portal.boldsystems.org/api`), documented by its own public OpenAPI spec
(`portal.boldsystems.org/openapi.json`). Confirmed the complete 3-stage flow live
end-to-end (`query/preprocessor` → `query` → `documents/{id}/download`), and pulled the
real field list directly from live records rather than secondhand docs.

**Built `fetch_bold_reference_sequences()` directly against this API via `httr2`** (see
Function Inventory above) — no `bold` package dependency needed at all, sidestepping the
whole archived-from-CRAN dependency question. Live end-to-end test (`Fundulus` +
`Danaus plexippus`): 103 real sequences, 38 species, 84% real coordinate coverage
(87/103) — notably better location coverage than NCBI/GenBank typically has. Found and
fixed one real bug this way: different taxa return different column sets from BOLD's
TSV export, so combining needed `dplyr::bind_rows()`, not `rbind()` (which errors on
mismatched columns).

**Query/ID-engine side (`identify_bold_sequences()`, TaxaMatch) — investigated,
no public API found, not built.** Pulled BOLD's complete OpenAPI paths list (20
endpoints, all reference/query-by-known-criteria) and confirmed no
identification/sequence-matching endpoint exists anywhere in it. BOLD's "Barcode ID"
tool now lives at `id.boldsystems.org` and every page checked describes only a
web-form (paste/upload sequence, click Identify), no documented REST endpoint. This may
be a real, permanent capability gap under BOLD v5, not an oversight — see
`project_bold_v5_migration_resolved` memory for the full record and how to re-check if
BOLD ever publishes one.

`devtools::document()` + `devtools::test()` (551 passing, 0 regressions) +
`devtools::check()` (0 errors/warnings/notes) all clean for the rename, PR2, and BOLD
reference-fetch work.

**Session 135 (2026-07-05): GenBank + Xeno-canto location extraction — closes two of three gaps in `ecosystem_docs/TODO_validation_benchmark.md`'s "Sourcing location data" section**

Scoped narrowly to the location-metadata plumbing itself, not the leave-one-out
benchmark harness (still gated behind the user's 2026-07-04 directive — confirmed
explicitly out of scope this session before starting).

**GenBank side** (`R/fetch.R`): confirmed directly that neither
`.fetch_summaries_batched()` (ESummary: `acc`/`title`/`taxid`/`slen`/`organism`) nor
`.fetch_taxonomy_map()` (taxonomy DB: lineage only) ever retrieves a record that can
carry `/lat_lon` or `/country` — those live only in the full GenBank nucleotide record's
`source` feature qualifiers. Added `.parse_lat_lon()` (pure INSDC `lat_lon` string
parser, e.g. `"36.789 N 121.947 W"` → signed decimal `c(lat=, lon=)`; degrades to
`NA`/`NA` on anything unparseable rather than erroring, since GenBank free-text is
inconsistent) and `.fetch_locations_batched()` (batched `rentrez::entrez_fetch(db =
"nucleotide", rettype = "gb", retmode = "xml")`, passing accessions directly as `id` —
the same convention `.fetch_fasta_batched()` already uses successfully, so no separate
search→summary round trip is needed). `fetch_reference_sequences(include_location =
FALSE)` — new opt-in trailing param; when `TRUE`, joins `lat`/`lon`/`country` onto the
final `reference_df` by `composite_id`.

**Xeno-canto side** (`R/coverage.R`): `.xc_recording_count()` was already performing the
exact HTTP request whose response body contains a `recordings` array with `lat`/`lng`
per recording — it just read `numRecordings` and threw the rest away. Extracted the
shared HTTP call into `.xc_recordings_raw()` and rewrote `.xc_recording_count()` to call
it (zero behavior change, confirmed by keeping its call sites' existing tests passing
unmodified plus a new direct test). Added `.xc_recording_locations()` (per-recording
`species`/`xc_id`/`lat`/`lon`/`country` — XC's `lat`/`lng`/`cnt` fields are already plain
decimal-degree/text strings, no DMS parsing needed unlike GenBank) and exported
`fetch_xc_recording_locations()` as the public entry point (1s/species rate limit,
matching `audit_acoustic_coverage()`'s own). `xc_id` is XC's own catalog number, not a
`build_site_table()`-ready `observation_id` — deliberately left for the caller to map to
their own BirdNET observation-id convention.

BOLD's equivalent location fields remain unchecked (separate TBD, no BOLD integration
exists anywhere in the ecosystem) and wiring either of the above into an actual
`TaxaMatch::build_site_table()` `site_df` call is left for benchmark-harness time, once
a real caller exists — both explicitly out of scope this session.

New tests: `.parse_lat_lon()` (6 cases, `test-fetch.R`), `.fetch_locations_batched()`
empty-input typing (`test-fetch.R`), `.xc_recording_count()`/`.xc_recording_locations()`/
`fetch_xc_recording_locations()` via `local_mocked_bindings()` on `.xc_recordings_raw()`
(`test-coverage.R`), matching the offline-mock convention already used in
`test-build-site-reference.R`. No live NCBI/Xeno-canto network calls added to the test
suite. `devtools::document()` + `devtools::test()` (512 expectations, 0 failures, 15
pre-existing unrelated warnings) + `devtools::check()` (0 errors, 0 warnings, 0 notes)
all clean.

**Session 133 (2026-07-03): acoustic tau re-calibrated on a broad, multi-cluster real dataset — Session 128/129's tau≈1 for acoustic does NOT hold; pooled result is tau≈0, matching image, but per-cluster results are genuinely heterogeneous**

Session 129's acoustic number (`tau ≈ 1` helps, later re-confirmed by log-loss at
`tau ≈ 3.6`) rested on 3 species, all one genus (*Calidris*), 9 recordings, 42 detection
windows — flagged by the user as too thin an evidence base to trust as a general
default. This session redid the calibration on a deliberately-designed, real,
much larger dataset: **8 confusable clusters, 24 species, 191 real Xeno-canto
recordings, real BirdNET-Analyzer runs, 2487 detection windows** (up from 42). Full
design rationale, live Xeno-canto recon, species list, and reproducible method detail
are in `ecosystem_docs/REENTRY_PROMPT_acoustic_tau_calibration_expanded.md` (now marked
complete) — this note summarizes the result.

**Design, briefly:** clusters chosen from real, live-verified Xeno-canto `n_recordings`
counts, not guessed — an initial assumption that confusable congener pairs would show
orders-of-magnitude count contrast was wrong; real confusable pairs mostly span only
2-7x. One genuine outlier was found and included (*Phylloscopus collybita* vs.
*ibericus*, ~19x — a species pair only recently split, still essentially inseparable by
song). A low-confusability control cluster (*Turdus migratorius* vs. *Megascops asio*)
was included specifically to test whether `tau` does damage where there's nothing to
correct. The original 3 Calidris species were folded back in at the same sampling depth
as everything else, so this result supersedes rather than discards Session 128/129's
pilot.

**Pooled result: `tau ≈ 0` is optimal — log-loss and accuracy both get monotonically
worse from `tau = 0` (log-loss 4.4136, 71% accuracy, 1771/2487) through `tau = 6`
(log-loss 4.6200, 68%).** This reverses Session 129's acoustic finding and now agrees
with image's own `tau ≈ 0` result — the "image and acoustic need opposite corrections"
conclusion from Session 129 does not survive a properly powered sample.

**Per-cluster breakdown (new diagnostic, not run in any prior session) shows this is
not uniform, though:** 5 of 8 clusters (Catharus, Control, Empidonax, Melospiza,
Chiffchaff — collectively ~1900 of 2487 windows) independently favor `tau` at or near 0,
which is why the pooled fit does too. But **Calidris (152 windows) and Woodpecker
(172 windows) both still prefer high `tau` (5.0 and 6.0 respectively) even at this much
larger scale**, and both optima are pinned at the swept grid's edge (`tau = 6`),
meaning their true optima are still unbracketed. Accipiter also "prefers" `tau = 6`, but
that cluster's accuracy is poor (41%) regardless of `tau` (59% complete-miss rate — the
true species frequently isn't even among BirdNET's candidates at all, a coverage
problem no amount of re-weighting fixes), so its tau=6 result is not treated as
meaningful signal, just noise on a bad cluster. **Practical conclusion: a single global
`tau` does not fit this data well — it behaves as if it should be cluster/taxon-specific
rather than one ecosystem-wide scalar.** That's a new open design question, not resolved
this session.

**True=rare vs. true=common balance check (new diagnostic):** among 211 windows where
the top-2 candidates' `n_recordings` differed by ≥1.5x, the TRUE species was the more
*common* candidate 44% of the time (93/211) vs. the rarer candidate only 18% of the time
(37/211) — the remainder (38%) matched neither top-2 candidate. This directly explains
why a large `tau` loses on the pooled fit: favoring the rarer candidate is wrong more
often than it's right in this broader, more representative sample — the opposite of
what the narrow Calidris pilot implied. This was exactly the design concern flagged
before data collection (an all-true=rare sample would make large `tau` trivially win by
construction); good to have it checked and refuted rather than assumed away.

**One real, confirmed bug found and fixed while building the dataset:** Xeno-canto
tags Hairy Woodpecker as `Leuconotopicus villosus` (its older genus), but BirdNET's own
internal taxonomy calls it `Dryobates villosus` and never once output the XC-tag name —
confirmed directly (0/8 Hairy Woodpecker files matched `Leuconotopicus villosus`; 126
rows matched `Dryobates villosus`). Every Hairy Woodpecker window was silently
registering as a complete miss even where BirdNET correctly identified the bird. Fixed
by correcting the true-species label to match BirdNET's own taxonomy (not by re-fetching
audio — the XC tag is still the correct thing to query by; only the ground-truth label
used for scoring needed to change). Woodpecker's accuracy went from 22% to 88% after the
fix. Checked all other 23 species for the same failure mode (does BirdNET ever output
that species' own name for its own recordings, at all) — none had it; this looks like a
one-off Xeno-canto/BirdNET taxonomy divergence for this specific species, not a
systemic issue. Worth checking for any future species added to this kind of design,
though — it's the second live taxonomy-tag mismatch found on Xeno-canto data this
session (the other, `Dryobates villosus` returning 0 hits on Xeno-canto's own search
API, was caught during species selection, before any data was pulled).

**Net effect on the package:** **there is currently no real-data evidence supporting
`tau > 0` as a general default for either data type (image or acoustic).** The
package's own default remains `tau = 1.0` (Menon et al. 2020's theoretical
Fisher-consistent value) — this session's result doesn't prove `tau = 1.0` is wrong in
principle, only that it hasn't been empirically supported yet on any real dataset built
so far, image or acoustic. Whether `correct_training_bias()` should ship with a
different default, or a per-context `tau`, remains an open decision — not changed this
session (would need to touch multiple files/tests; flagging for a deliberate choice
rather than making it unilaterally here).

Not done: bracketing Calidris/Woodpecker's true per-cluster optima (grid capped at
`tau = 6`, both still climbing); wiring any of this into
`TaxaAssign::camera_trap_posterior_workflow.R` (still uses the old `tau = 1.0` default);
whether `.xc_recording_count()`'s `type:call`-only restriction is even the right
training-representation proxy (flagged, not investigated).

**Session 129 (2026-07-03): assign_scores() score-scale bug found and fixed; tau/score_sharpness jointly calibrated on clean data — image result resolved, superseding Session 128's number**

Expanded the Session 128 image photo set from 6 to 52 real photos (8 species, 3 new:
raccoon, California ground squirrel, Virginia opossum) to get past a small-n result.
Two real, previously-hidden bugs surfaced while doing this, both now fixed:

1. **iNaturalist returns off-scope candidates** (plants, birds) that a mammal-only camera-
   trap study can never actually be. `TaxaMatch::score_image_workflow.R` now filters to
   `iconic_taxon_name == "Mammalia"` right after scoring, before any downstream step can
   assign the impossible candidates probability mass. Real examples removed: *Baccharis
   pilularis* ("coyote brush", a plant) for coyote.JPG, *Megascops kennicottii* (a screech
   owl) for rabbit.JPG — the second of these is the exact taxon Session 128's flip report
   named, meaning that specific result was already partly a scope-filter artifact, not a
   pure `tau` effect.

2. **`assign_scores()`'s `similarity_softmax` path collapsed to near-uniform likelihoods**,
   independent of `tau` entirely. `.normalize_scores()` forced iNaturalist's unbounded
   `combined_score` (real data reaches ~3000) through a fixed 0-100 divisor meant for
   BLAST-style percent-identity scores; every candidate in every photo ended up with
   `score_likelihood` within ~0.1% of 1.0 regardless of which one iNat actually favored.
   Confirmed directly: a tau-only sweep on 51 scope-filtered photos showed log-loss
   essentially FLAT across the entire `tau` range (2.4624 to 2.4638, 0.05% relative) while
   accuracy swung 22 points non-monotonically — the two metrics disagreeing that sharply
   was the tell that something other than `tau` was driving accuracy, and a per-photo
   probability trace confirmed it (every candidate ~0.999-1.000, an almost perfectly
   uniform distribution).

**Fix** (`R/assign_scores.R`): score scale is now auto-detected once per call from the
global max of `score_col` across all `specific_candidate` rows — no new caller-facing
parameter, so every data type (existing and future) is handled without per-type
configuration. `max <= 100` (BLAST/percent-identity): unchanged fixed-divisor behavior,
confirmed byte-for-byte identical via the full existing test suite (497 expectations, 0
failures) and a targeted synthetic check. `max > 100` (iNaturalist `combined_score`, or
any other genuinely unbounded score): each observation is normalized against its own
candidate range instead, restoring real discrimination (synthetic check: spread went from
~0.001 to ~0.095 between best and worst candidate).

**Joint (tau, score_sharpness) calibration on clean data** (`TaxaLikely/inst/workflows/
calibrate_training_bias_tau.R`, extended from a tau-only sweep after finding
`score_sharpness = 0.1`'s default is also poorly matched to this data type — a 2D grid,
72 combinations, log-loss-minimizing, refined with `stats::optim()`): on the 51 real,
scope-filtered, correctly-scaled photos, log-loss and accuracy now AGREE and are both
monotonic in `tau` — log-loss rises and accuracy falls steadily from `tau = 0` (82%
top-1) to `tau = 1` (63%) and beyond. **Resolved: for the image pathway,
`tau ≈ 0` is optimal — the correction should not be applied.** Optimal `score_sharpness`
(5-15) is also far from the package default (0.1). Continuous optimum: `tau = 0.085`,
`score_sharpness = 15.24`.

**Acoustic is unaffected by bug #2** — BirdNET confidence uses `score_type =
"probability"` (already 0-1 bounded), which never calls `.normalize_scores()` at all, only
`similarity`/`similarity_softmax` do. Session 128's acoustic result (37/42 -> 39/42,
correction helps at `tau = 1`) is expected to still hold, but has not yet been
re-validated with the same log-loss calibration procedure used for image — do that before
fully trusting it, since it was only ever an accuracy-based first look.
**Update, Session 133: this expectation did NOT hold** — re-validated on a much larger,
multi-cluster real dataset (2487 windows vs. 42); pooled acoustic optimum is `tau ≈ 0`,
same as image. See Session 133's note below for the full result, including real
per-cluster heterogeneity this 3-species pilot had no way to detect.

**The practical conclusion is not "`tau = 0` is the right default"** — both `correct_
training_bias()`'s own roxygen and this note now say so explicitly: `tau` (and, for
`similarity_softmax`, `score_sharpness`) must be calibrated per data type. Image and
acoustic gave opposite answers (`tau ≈ 0` vs `tau ≈ 1`) from the identical function with
identical defaults on real data — that is itself the strongest evidence yet that a shared
default across data types was never going to be safe.

`devtools::document()`: clean, no signature changes (auto-detection, not a new
parameter). Full TaxaLikely test suite: 497 expectations, 0 failures, 0 errors both
before and after the `assign_scores()` fix.

**Not done**: acoustic re-validation with log-loss (see above — **done Session 133**, see
that note above for the result); wiring the calibrated `(tau, score_sharpness)` into
`TaxaAssign::camera_trap_posterior_workflow.R`'s actual posterior computation (currently
still uses the old `tau = 1.0` default there — still not done as of Session 133).

**Session 128 (2026-07-02): correct_training_bias() wired into the image/acoustic Layer-1 workflow and live-tested — mixed first result**

The two-sessions-overdue wiring from `ecosystem_docs/REENTRY_PROMPT_session127...`, item 1.
`correct_training_bias()` (Session 125, revised Session 127) had never been run against
real classifier output before this session — only a synthetic 3-row fixture.

**Image section** (`image_acoustic_likelihood_workflow.R` Section 1): inserted
`correct_training_bias(count_col = "n_observations")` right after loading TaxaMatch's
checkpoint, before `unreferenced_candidates()` (the reentry note's file reference —
`score_image_workflow.R` — was slightly off; the actual `unreferenced_candidates()` call
site is here, in this script, not TaxaMatch's). `score_image_inat()`'s output already
carries `n_observations` per candidate, so no extra API call was needed.

**Acoustic section** (Section 2): first built the join Session 125's reentry prompt
flagged as never built — `audit_acoustic_coverage(xc_recordings = TRUE)` queried live
against the 9 unique species in the real BirdNET match object (Xeno-canto v3, ~9s), and
its `n_recordings` census column was left-joined onto the match object by `species`
before calling `correct_training_bias(count_col = "n_recordings")`.

**Grounding-truth check (first look, not a calibration — both sets are small):** re-ran
each section's pipeline twice — once with the corrected score, once substituting
`score_uncorrected` back in — to isolate the correction's effect on the winning
candidate, holding everything else constant. Real, live result at `tau = 1.0`:

- **Image** (6 real camera-trap photos): correction changed 2/6 winners; top-1 accuracy
  **fell** from 5/6 (83%) to 4/6 (67%). One flip was wrong-to-wrong (coyote.JPG, already
  a known miss — see Session 124's note); the other turned a correct call wrong: *Sylvilagus
  bachmani* (brush rabbit) got reassigned to *Megascops kennicottii* (a screech owl) once
  bias-corrected. `n_observations` spans 352 to 153,730 across this tiny candidate set —
  a very large range to correct with only 6 photos of signal.
- **Acoustic** (42 real BirdNET detection windows, 3 confusable Calidris sandpipers):
  correction changed 2/42 winners; top-1 accuracy **rose** from 37/42 (88%) to 39/42
  (93%). Both flips were wrong-to-right (one *Calidris mauri* window previously misassigned
  to Killdeer, one *Calidris pusilla* window previously misassigned to Dunlin, both
  corrected to the true species). `n_recordings` (Xeno-canto) spans 44 to 417 — a much
  narrower range than the image path's `n_observations`.

**Interpretation, held loosely:** the correction helped on the data type with narrower
count spread and hurt on the one with wider spread, which is at least directionally
consistent with the "First real-data look" caveat added to `correct_training_bias()`'s
own roxygen this session — but n=6 and n=42 are both far too small to conclude anything
about `tau` itself, and the one harmful image flip is a real, concrete warning sign, not
noise to explain away. **`tau` was NOT changed from the default `1.0`** on the strength of
this alone. Recorded in the function's own "Open caveat" `@details` section (per the
Session 127 reentry prompt's explicit instruction to update that section once a real
check had actually been run) and here, for whoever runs the next real dataset through
this pipeline to compare against.

`devtools::check()` on `TaxaLikely`: 0 errors, 0 warnings, 1 pre-existing note (timestamp
verification, environmental). No R/ source changes besides the roxygen addition to
`correct_training_bias()` — the wiring itself is entirely in
`inst/workflows/image_acoustic_likelihood_workflow.R`.

**Not done**: `tau` was not retuned; the Stage 3 reentry items (real head-data testing,
function-promotion check, Layer-2 wrapper decisions, Drive cleanup check) are unchanged
from Session 127; `TaxaID/CLAUDE.md`'s stale "Planned" label for TaxaAssign was not
touched this session (out of scope — user chose this item specifically over that one).

**Session 127 (2026-07-02): correct_training_bias() revised — logit adjustment (Menon et al. 2020) replaces adaptive per-candidate shrinkage**

Prompted by the user questioning the Session 125 design before it was ever wired into a
real workflow: "it seems like rare taxa would always win over common ones." Worked
through the math live — with `prior_weight = median(n)`, `tau_i = n_i/(n_i+prior_weight)`
behaves almost like a step function pivoting at the candidate set's median count (e.g.
divisor ≈1.02× at n=10, ≈40,300× at n=50,000, ≈487,000× at n=500,000 for
`prior_weight≈1000`). Since real classifier scores are bounded and can't differ by
anything close to that many orders of magnitude, this meant: whenever two candidates
straddle the local median by much, the lower-n one wins essentially by construction,
correct or not — confirming the user's suspicion quantitatively rather than just
intuitively.

Rather than hand-tune the existing formula, ran a 105-agent deep-research literature
review (long-tailed recognition / class-imbalance correction literature) before making
any code change, per the user's own instinct that "this is a well-studied field." Key
findings, all adversarially verified:
- **Menon et al. 2020, "Long-Tail Learning via Logit Adjustment"** (ICLR 2021,
  arXiv:2007.07314) — the standard theoretically-grounded correction: subtract
  `tau * log(pi_i)` from class `i`'s logit (`pi_i` = training-set class frequency),
  equivalent to dividing the raw score by `pi_i^tau`. Critically, `tau` is a **single
  global scalar**, not a per-class adaptive value — the opposite direction from the
  Session 125 design. Fisher-consistent for the balanced/class-uniform error at
  `tau = 1`, derived directly from Bayes' rule; explicitly endorsed for **post-hoc**
  application to an already-trained model (no retraining needed) when label frequencies
  are known — directly matches this package's use case (correcting pretrained
  third-party classifiers, iNaturalist CV / BirdNET).
- The user's "diminishing returns from more data" intuition (their own guess was
  sqrt(n)) does have a real literature analog — **Cui et al. 2019's "effective number
  of samples"**, `(1-beta^n)/(1-beta)` — but it reweights *training loss*, not a frozen
  model's inference-time posterior; structurally the wrong tool for this package's
  post-hoc-only use case (verified against the official implementation).
- No source survived adversarial verification for a direct sqrt(n)/log(n) posterior
  correction; a candidate paper's log-based "Quantity Factor" claim was explicitly
  refuted on reverification.
- Open gap, confirmed by the research (not resolved by it): Menon's Fisher-consistency
  guarantee formally assumes `pi_i` is an accurate estimate of the classifier's *actual*
  training frequency. This package's `n_i` is a noisy **external proxy** (public
  database counts, not the classifier's real internal training counts) — no paper
  directly studies robustness to that gap. `tau` is kept user-tunable, not hardcoded,
  for this reason.

**Mathematical reconciliation**: Menon's `pi_i^tau` uses relative frequency
(`n_i / N_total`), but `N_total` (total training count across all classes) is the same
constant for every candidate being compared within one observation — it cancels out of
any ratio/ranking comparison within a query's candidate set. So dividing by raw `n_i^tau`
instead of `pi_i^tau` is exactly proportionally equivalent here; no need to know or
estimate `N_total`, which this package has no way to obtain for a third-party classifier
anyway. This let the revision keep `correct_training_bias()`'s existing `score / n^tau`
structure and just change what `tau` means (fixed global scalar, default `1.0`) rather
than rewriting the formula shape from scratch.

**Kept from Session 125, deliberately**: NA/zero counts still fall through to the
uncorrected score rather than applying `tau` — pure logit adjustment has no answer for
an unknown `pi_i`, and treating a failed lookup as "no correction" remains the
conservative, defensible default (can't tell a genuinely rare species from a lookup
failure from the count alone).

Test suite fully rewritten to match the new signature: removed the `prior_weight`-default
and `prior_weight`-override tests, added `tau = 0` (disables correction),
`tau` uniformity-across-candidates (the core behavioral change from Session 125), and
`tau > 1` (stronger-than-theoretical correction, matching Menon et al.'s own CIFAR-10-LT
tuned optimum of 2.6) tests. 27 expectations, all passing. `devtools::document()` +
`devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Still not done**: wiring into `image_acoustic_likelihood_workflow.R` or any other
Layer-1 script, and validation against real classifier output — see
`ecosystem_docs/REENTRY_PROMPT_session127...`.

**Session 126 (2026-07-01): Sequence/BLAST Layer-1 workflow — Stage 2 of REENTRY_PROMPT_session124**

`inst/workflows/sequence_likelihood_workflow.R` added — the second script in the
sequence/BLAST mini-chain (TaxaMatch's `blast_sequences_workflow.R`, added the same
session, is the first). This is the architecturally different one among the three
Layer-1 data types: it actually trains the bivariate-normal self-vs-non-self model
(`build_sequence_matrix()` → `train_likelihood_model()`) rather than calibrating a
pre-trained classifier's output like the image/acoustic pathway.

Reference database: live NCBI fetch (`fetch_reference_sequences()`, `max_per_species =
5L`) for 6 real genera spanning 3 fish families (Cottidae, Embiotocidae, Clinidae) —
matching the same real PtConception study system as TaxaMatch's query-side script, not
a separate invented example. Query side reuses TaxaMatch's checkpoint directly (5 real
12S sequences).

Live-tested end to end (both scripts chained in one session, real NCBI calls
throughout), 0 errors after one bug fix (below): 5/5 (100%) top-likelihood accuracy —
`evaluate_likelihoods()`'s winning `specific_candidate` hypothesis matched the true
species for every query, including one genuinely interesting edge case:
`fetch_reference_sequences()`'s genus-level NCBI search for *Rhacochilus* returned 0
sequences (a real query-construction gap — BLAST's own `nt` search independently found
a 100%-identity *Rhacochilus toxotes* record that the narrower reference-fetch query
missed), so that species has no species-specific H1 parameters in the trained model at
all. It still won correctly at inference time via the model's global-mean fallback —
real confirmation that the fallback path (documented in Statistical Design Notes) works
as intended, not a bug. `fetch_reference_sequences()`'s query-construction gap itself
was not fixed this session (out of scope for the workflow-script task; a candidate for
a future investigation if it recurs on other genera).

**Bug found and fixed (by actually running the two-script chain, not by static
review):** the honesty check in this script needs a `true_species` column carried
through on TaxaMatch's checkpoint object, re-joined from it after `evaluate_likelihoods()`
(whose output schema doesn't pass arbitrary columns through). `blast_sequences_workflow.R`'s
own Output block already documented this column as present — but the column was only
ever computed into a local copy inside that script's own honesty-check block, never
actually attached to `taxamatch_blast_match_obj` itself. First run of the two-script
chain failed with `"undefined columns selected"` on the re-join. Fixed in
`TaxaMatch/inst/workflows/blast_sequences_workflow.R` by attaching
`taxamatch_blast_match_obj$true_species <- TRUE_SPECIES[taxamatch_blast_match_obj$observation_id]`
right after `standardize_match_data()`, matching the pattern `score_image_workflow.R`
already uses. Second run: 0 errors.

Other real behavior observed (not bugs): `calibrate_coverage_filter()` reported
near-flat Youden's J (5 unique coverage values on this small reference set) — the
already-documented categorical-coverage message fired as designed; fell back to
`coverage_threshold()`'s quantile shortcut as this script's own coverage-calibration
step anticipates. `train_likelihood_model()` skipped `lme4` hierarchy fitting (only 5
species trained, need ≥10) and warned about singleton references lacking self-matches
(7 of the fetched species had only 1 sequence) — both are the already-documented
graceful-fallback paths (Known Footguns), not new issues.

**Session 125 (2026-07-01): .xc_recording_count() v2 → v3 migration (Stage 1 of REENTRY_PROMPT_session124)**

Fixed the dead-endpoint footgun flagged Session 124. `.xc_recording_count()` (`R/coverage.R`)
switched from `https://xeno-canto.org/api/2/recordings` (404 unconditionally) to
`https://xeno-canto.org/api/3/recordings`, added a required `key` query param read from
`Sys.getenv("XC_API_KEY")`, and rewrote the query from v2 free-text to v3 tag-based syntax
(`gen:{genus} sp:{species} type:call`). Missing-key case now warns explicitly instead of
silently returning `NA` (matching the fix pattern used for `.resolve_llm_fn()` in
`TaxaID/CLAUDE.md`). Response body parsing (`numRecordings` field) unchanged — v3 kept the
same field name as v2.

Live-verified with a real, freshly-registered `XC_API_KEY` (confirmed with the user before
use, per the reentry note's key-provenance caution): `.xc_recording_count("Turdus migratorius")`
→ 430; `audit_acoustic_coverage(xc_recordings = TRUE)` end-to-end on 4 species (2 in-reference,
2 unreferenced) → all 4 returned real non-NA counts (430, 118, 78, 19). `devtools::check()`:
0 errors, 0 warnings, 0 notes.

Stage 1's second item (training-database bias correction) picked up the same session —
see below.

**Session 125 continued: `correct_training_bias()` — training-database bias correction**

Design discussion with the user first (not started from a ticket, per the reentry note's
explicit instruction): confirmed the statistical justification — a classifier trained by
standard cross-entropy estimates a Bayes posterior, so raw score_i ∝ L(obs|species_i) × n_i,
and dividing each candidate's score by its own n_i (rather than pairwise `R = n_i/n_j`
corrections, which don't scale past 2 candidates) corrects every pairwise ratio
simultaneously. Landed on an **adaptive** shrinkage exponent rather than a fixed one:
`tau_i = n_i / (n_i + prior_weight)`, the same functional form already used in
`train_likelihood_model()`'s per-species shrinkage (`w = N/(N+prior_weight)`) — justified
because `n_i` (a public-database count) is only a noisy proxy for the classifier's actual
internal training count, least trustworthy exactly where `n_i` is small. `prior_weight`
defaults to `median(n, na.rm = TRUE)` (self-normalizing to whatever scale the count data
has, rather than an arbitrary constant). A useful side effect: treating a missing/failed
count lookup as `n_i = 0` makes `tau_i = 0` automatically (`n^0 = 1`, no correction) — so
NA handling falls out of the same formula with no special-case branch, rather than having
to decide whether a given NA reflects genuine rarity or a lookup error.

`correct_training_bias()` added (`R/correct_training_bias.R`): overwrites `score_col`
(default `"score_original"`, matching `assign_scores()`'s own default) in place with the
corrected value, so no downstream call site needs to change; preserves the pre-correction
value under `score_uncorrected`; adds `n_used`/`tau_used` diagnostics. Confirmed via
`TaxaMatch::score_image_workflow.R`'s real output contract that the working column really
is named `score_original` (not `score`) by the point this would run — the design
conversation's placeholder name was corrected before implementation.

22 offline unit tests (`test-correct-training-bias.R`), all passing: correction direction
(favors low-n over high-n candidates), NA/zero-count fallthrough, all-NA-counts case,
missing-count_col warning, default-vs-explicit `prior_weight`, and input validation.
`devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Not done yet**: not wired into the Layer-1 `image_acoustic_likelihood_workflow.R` /
`score_image_workflow.R` / `score_acoustic_workflow.R` scripts, and not validated against
real classifier output (only a synthetic 3-row fixture so far) — the acoustic side also
still needs the `n_recordings` join from `audit_acoustic_coverage(xc_recordings = TRUE)`
onto the match object by taxon, which nothing does yet. See the reentry prompt for the
concrete next steps.

**Session 124 (2026-07-01): Layer-1 image/acoustic likelihood workflow**

`inst/workflows/image_acoustic_likelihood_workflow.R` added — consumes TaxaMatch's real
iNat CV (image) and BirdNET (acoustic) checkpoints from `score_image_workflow.R` /
`score_acoustic_workflow.R`, via the same `unreferenced_candidates()` + `assign_scores()`
pathway this file's docs already noted is identical for both data types. Live-tested,
0 errors: image section 5/6 (83%) correct on real camera-trap photos (5 mammal species,
4 families); acoustic section 37/42 (88%) correct on real BirdNET output for 3
confusable Calidris sandpipers. See `TaxaMatch/CLAUDE.md`'s Session 124 note for the
full real-data provenance and bugs found while building the TaxaMatch side.

Confirmed live: `assign_scores(score_type = "similarity_softmax")` (image, unbounded
`combined_score`) and `score_type = "probability"` (acoustic, already 0-1 bounded
BirdNET confidence) both ratio-normalize by the winning candidate's own score — the
winner's `score_likelihood` is therefore always exactly 1.0 by construction; the
meaningful comparison across observations is which taxon won, not the likelihood
magnitude. Not a bug, but non-obvious enough to be worth stating plainly here.

Also found (not fixed, out of scope for this task): `.xc_recording_count()` calls a
dead Xeno-canto v2 endpoint — see the new Known Footguns entry above.

**Session 123 (2026-07-01): audit_barcode_coverage() "Common mistake" doc fix (no logic change)**

No function behavior changed — this was a workflow-usage bug, not a package defect.
Root cause confirmed empirically against real Mugu cached data (`match_obj`/`reference_df`/
`coverage` RDS files): *Mustelus mosis* was both an H1 BLAST `specific_candidate`
(accession NC_077464, a complete 16755bp mitogenome, 174bp aligned region, 98.28% identity)
and reported "unreferenced" by `audit_barcode_coverage()`. Cause: three real workflows
(`PtConceptionWorkflow_12S.R`, `PtConceptionWorkflow_18S_2.R`, `MuguFishWorkflow.R`) all
passed the length-curated `reference_df` (built for `build_sequence_matrix()`, which
correctly excludes full mitogenomes from the alignment training set) as
`audit_barcode_coverage()`'s `match_df` skip-list argument, instead of the actual match
object. A species whose only NCBI record is a long sequence is therefore absent from the
skip-list and fails the barcode-length-restricted reverse search, even though BLAST
(unconstrained by length) already matched it correctly. `run_bayesian_pipeline()` was
already unaffected — it builds its skip-list from its own `match_df` parameter (the real
match object), never from a training `reference_df`.

Added a `@param match_df` clarification plus a "Common mistake" `@details` subsection to
`audit_barcode_coverage()` (`R/coverage.R`) documenting the exact mechanism with this case
as a worked example, so it does not recur a fourth time. All three real workflows updated
to pass `match_obj`/`match_obj_restored` instead of `reference_df`; each workflow's
diagnostic NOTE (checking for species in both the match object and
`coverage$unreferenced`) kept as a post-fix sanity check rather than removed.
`devtools::check()`: 0 errors, 0 warnings.

Sessions 30–94 archived in `ecosystem_docs/session_notes/TaxaLikely_sessions.md`.

**Session 100 (2026-06-03/04): Trivariate revert; coverage sigma-inflation (score_likelihood_cov)**

Trivariate coverage model (rejected): explored making coverage a third dimension of the
bivariate normal, but premise validation on `build_sequence_matrix()` output showed H1
(within-species) training pairs are nearly all coverage ≈ 1 (mean 0.991, var 0.002) while
H2 cross-species pairs are much more variable (mean 0.908, var 0.041). Because there is
no within-H1 coverage variation, the model cannot estimate a coverage–score relationship.
Trivariate approach reverted; coverage remains a hard filter only via `min_coverage`.

New: `score_likelihood_cov` column added to `evaluate_likelihoods()` output. Applies a
post-hoc sigma inflation at inference time using a prior (binomial SE argument):
σ_eff = σ / sqrt(coverage). Only the [1,1] element of H1_Sigma is inflated; H2/H3 sigmas
are global fixed parameters and are not modified. Key behavior: for scores near the H1
mean (good within-species matches), widening sigma lowers the peak density → negative
delta (primary intended effect — penalises good matches observed at low coverage). For
scores far below the H1 mean (cross-species matches), widening sigma fattens the left
tail → positive delta (secondary, low-relevance effect). Crossover at exactly ±1 sigma
from the H1 mean. Column added as a parallel output only (non-breaking); `score_likelihood`
is unchanged and remains the default for TaxaAssign unless the user switches.

Other changes this session: Workflow 3 fully rewritten (removed stale trivariate
references; added coverage-by-hypothesis-type diagnostic; added demo of
score_likelihood_cov using within-species pairs with coverage < 0.99). README updated
with `score_likelihood_cov` in the Quick Start output and a Statistical Design bullet
explaining the formula, direction of effect, and why coverage is not a model dimension.
`train.R` minor cleanup (roxygen, h2_sigma_mat moved outside conditional).

**Session 105 (2026-06-10): fetch_reference_sequences() cache key fix + audit_barcode_coverage() checkpoint/resume**

`fetch_reference_sequences()`:
- `cache_dir` default changed from `tempdir()` to `tools::R_user_dir("TaxaLikely", "cache")`
  for cross-session persistence.
- Per-taxon cache keys now include `eff_min_len`, `eff_max_len`, and `max_date` in the
  filename. Previously changing these parameters returned stale cached data. Both the
  priority-species key (`priority_{name}_{bc}_l{min}_{max}_d{date}_meta.rds`) and
  the broader-taxa key (`{name}_{bc}_l{min}_{max}_d{date}_meta.rds`) updated.

`audit_barcode_coverage()`:
- `cache_dir` param added (default `tools::R_user_dir("TaxaLikely", "cache")`; NULL disables).
- `.coverage_checkpoint_path()` internal helper: deterministic path from genera count/nchar-sum,
  barcode_term, len_range, max_date, target_rank. Changed parameters auto-start fresh.
- Checkpoint (named list of completed genus records) saved after each genus — both the
  early-exit (no species found) and normal completion paths.
- On resume, already-completed genera are loaded from checkpoint and skipped.
- Checkpoint deleted on clean completion.

**Session 119 (2026-06-24): audit_inat_coverage() + audit_acoustic_coverage(xc_recordings)**

`audit_inat_coverage()` added to `R/coverage.R`:
- New exported function. Given a `species_list` (prior taxa not in match data), queries the
  iNaturalist taxa API (`GET https://api.inaturalist.org/v1/taxa?q={name}&rank=species&per_page=1`)
  for each species. Returns `list(census, unreferenced)` with same structure as
  `audit_barcode_coverage()`.
- Census columns: `species`, `taxon_id`, `matched_name`, `n_observations`, `in_inat`,
  `cv_model_included` (n_obs >= `cv_threshold`, default 100L), `unreferenced`, `in_match_data`.
- Optional `match_df` param annotates `in_match_data`. Optional `api_token` (env
  `INAT_API_TOKEN`); 401 → stop with token refresh message.
- 0.3s `Sys.sleep()` rate limit per species. `verbose = FALSE` param for progress messages.
- Internal helper `.inat_species_info()` wraps `httr2` request; returns list with `taxon_id`,
  `matched_name`, `rank`, `n_observations`, `found`.

`audit_acoustic_coverage()` enhanced:
- New `xc_recordings = FALSE` param. When TRUE, queries Xeno-canto v2 API
  (`GET https://xeno-canto.org/api/2/recordings?query={name}`) per species; adds `n_recordings`
  column to census (NA when FALSE). 1s `Sys.sleep()` rate limit per species.
- Internal helper `.xc_recording_count()` wraps `httr2` request; parses `numRecordings`
  string → integer; returns `NA_integer_` on any failure.

`httr2` moved from Suggests to Imports in `DESCRIPTION` to support the new API-calling
coverage audit functions.

`devtools::check()`: 0 errors, 0 warnings, 1 pre-existing note (stale top-level .rds file).

**Session 121 (2026-06-26): Per-species sigma floor + Mahalanobis alpha 1e-6 → 0.001**

Two inference improvements in `.evaluate_one_query()` / `evaluate_likelihoods()`:

Per-species sigma floor: `use_sigma[1,1]` now floored at `global_sigma[1,1]` before
H1 density evaluation. Fixes species with artificially tight reference distributions
(near-identical NCBI clones) silently dropping below `ratio_threshold`.

Mahalanobis alpha default changed from `1e-6` to `0.001`: The chi-squared outlier
check (2 df) now rejects H1 candidates at p < 0.001 rather than p < 1e-6. Motivation:
`1e-6` admitted freshwater Cyprinidae (91–93% identity in a marine sample; p ≈ 0.00026)
as spurious H1 rows. `0.001` drops them (0.00026 < 0.001) while retaining legitimate
borderline H1 hits (e.g. Leptocottus armatus at 99%; p ≈ 0.009 > 0.001). Unlike
`ratio_threshold`, this check is H1-intrinsic — it asks only whether the query is
consistent with H1's own distribution, independent of H2/H3 densities. `ratio_threshold`
default left at `0.01` in function signatures for backwards compatibility; workflows
that use `ratio_threshold = 0` rely solely on this alpha check.

449 tests pass; 0 failures.

