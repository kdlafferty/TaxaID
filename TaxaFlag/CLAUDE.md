# CLAUDE.md -- TaxaFlag
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-30 (Sonnet 5 -- add_posthoc_assessment()'s Axis 1 rebuilt around
# theta_mean instead of prior_mean, closing out the 2026-07-28 design's two real weaknesses
# found live-testing against production Mugu data. (1) prior_mean can be substantially
# inflated by TaxaAssign::update_prior_from_consensus()'s cross-observation confirmation
# boost, which has no gate on occurrence-record presence -- measured on real Mugu data,
# EVERY row with prior_mean >= 0.5 was a boosted row, so an "expected" call built on
# prior_mean meant "confirmed elsewhere in this dataset", not "expected here on occurrence
# grounds". theta_mean (TaxaExpect::prepare_model_dataframe()'s raw occurrence-model share)
# is immune to that boost by construction. (2) A single absolute threshold (the previous
# design's fixed 0.5) is a unit mismatch on the theta_mean scale (a share of local records,
# not a presence probability) AND biased across ranks -- a genus/family-level consensus_prior
# (now a SUM over group members, see TaxaAssign/CLAUDE.md's matching note) is mechanically
# larger than any one species' own share just from summing more terms (confirmed: 27/28 real
# Mugu families cleared the species-level median purely by having more members). Fixed:
# winner_prior_col/winner_record_col/consensus_prior_col/expected_prior_threshold=0.5 (the
# 2026-07-28 design) replaced by winner_theta_col/winner_record_col/consensus_prior_col/
# consensus_record_col (new)/expected_theta_threshold (no default, now a NAMED VECTOR keyed
# by rank -- "species" required, genus/family optional; a rank absent from the vector gets
# "not_modeled" rather than an unsafe cross-rank comparison). consensus_record_col
# (default "consensus_has_occurrence_record") reads TaxaAssign::posterior_consensus()'s new
# dedicated presence column directly instead of inferring presence from consensus_prior's
# own NA-ness -- closes a real production bug (100% of 616 real Mugu rows read
# "unprecedented" the moment group_priors was first wired into posterior_consensus(), since
# consensus_prior's NA had started meaning "group_priors never supplied" as well as "checked,
# absent", and the old inference couldn't tell them apart). Also retired posthoc_assessment
# and its supporting params (tiers/taxon_col/tier_col/finest_rank) entirely -- there is no
# replacement for the 3x2 tier-times-likelihood table itself, since primary_plausibility
# (occurrence side, now theta-based) and primary_discrimination (evidence side, Axis 2)
# already answer the same two questions without collapsing them into one column or gating
# either on rank; the retired design's "vague_rank" category had short-circuited 109/616
# real Mugu observations (17.7%) into never being assessed at all. Real end-to-end
# verification via MuguFishWorkflow.R (not just the test suite): after TaxaAssign's own
# group_priors wiring + a full real backbone-architecture fix (see TaxaID/CLAUDE.md's
# 2026-07-30 note), final consensus_plausibility distribution: 519 expected / 93 unexpected /
# 4 unprecedented (the 4 being genus-level taxa already flagged as genuinely suspect in
# earlier project investigation, not a further bug). Fixtures in
# test-add_posthoc_assessment.R updated to carry consensus_has_occurrence_record explicitly.
# devtools::test() 240/240 (0 failures), devtools::check() 0 errors, with the pre-existing
# build_review_covariates.R warning + .data note unchanged. Reinstalled and verified via a
# direct smoke test (not just the reinstall command's exit status -- see TaxaAssign/CLAUDE.md's
# matching note for why a stale-install bug this exact session made that distinction matter).
# See [[project_axis1_consensus_prior_group_priors]] in the TaxaID memory system for the full
# debugging record.
# Previous update, 2026-07-28, later (Opus 5 -- add_posthoc_assessment() gains Axis 1:
# primary_plausibility and consensus_plausibility, each one of "expected"/"unexpected"/
# "unprecedented"/"not_modeled". Four new params (winner_prior_col, winner_record_col,
# consensus_prior_col, expected_prior_threshold = 0.5), all with defaults matching
# TaxaAssign::posterior_consensus()'s real column names and silently skipped (NA output,
# no error) when absent -- this function's established optional-upstream-output
# convention.
#
# "unprecedented" is driven by RECORD PRESENCE, never by a low prior value -- see
# TaxaAssign/CLAUDE.md's same-day note for the real-data evidence (a never-reported taxon
# and a genuine singleton can carry the identical floor prior while meaning opposite
# things, so no threshold on the value can separate them).
#
# The 0.5 break was chosen over a fitted cutoff because it does two jobs at once: it is
# directly interpretable (the taxon is at least as likely present as absent) AND it falls
# in a genuinely empty region of the real prior distribution -- nothing between 0.0865 and
# 0.966, an 11x gap. Same reasoning as Axis 2's 0.05/0.5 breaks.
#
# Reported ALONGSIDE the other columns, never gating them -- which is the specific defect
# "vague_rank" has. Measured on the real 616-observation Mugu dataset: 109 observations
# get "vague_rank" from posthoc_assessment and are therefore left unassessed entirely
# (it short-circuits every non-species rank); Axis 1 classifies all 109 (78 expected,
# 22 unexpected, 9 unprecedented). That is the original ASV_379/Chaenogobius bug this
# whole redesign exists to fix, now demonstrably closed.
#
# Anchor validation -- Axis 1 reproduces the user's own domain judgment unprompted: both
# taxa they independently called genuinely suspect (ASV_379 Chaenogobius, ASV_30
# Prosopium) come out "unprecedented", as do ASV_371 Salmonidae (their read: a food item,
# not a wild population) and ASV_382 Sciaenidae (their read: all candidates implausible);
# the CA-native tidewater-goby-bearing ASV_463 Gobiidae comes out "expected".
#
# Primary and consensus scopes disagree on only 3/616 real observations (vs Axis 2's
# 23/606) -- reported as two columns per the user's explicit requirement that both axes
# carry primary_taxon and consensus_taxon versions. 10 new tests (239 total, up from 222),
# including the two that pin the design: a no-record taxon with a HIGH prior must be
# unprecedented, and a singleton at the floor must NOT be. Full real pipeline
# (posterior_consensus -> add_posthoc_assessment, 616 obs) runs in 1.5 s.
# devtools::test() 239 pass / 0 fail; devtools::check() 0 errors, with the pre-existing
# build_review_covariates.R warning + .data note unchanged. Reinstalled.
# Previous update, 2026-07-28 (Opus 5 -- add_posthoc_assessment() loses the
# "unsupported_rank" category and both params that drove it (absolute_fit_pvalue_col,
# weak_evidence_pvalue), following TaxaLikely's removal of the underlying
# absolute_fit_pvalue column. Decisive evidence: the category fired on 0 of 606 real Mugu
# observations at its shipped 0.001 default and is absent from real posthoc_assessment
# output entirely -- it has never once classified a real row. See
# [[project_absolute_fit_pvalue_retired]] for the full audit (written before the removal,
# at the user's request, to keep revival possible).
#
# confusion_risk_flag is UNTOUCHED and still present. One test
# ("confusion_risk_flag never overrides posthoc_assessment") was rewritten rather than
# deleted -- it had been asserting non-interference by pinning the OTHER column to
# "unsupported_rank"; it now demonstrates the same property directly, by confirming that
# changing the confusion risk leaves posthoc_assessment identical.
#
# Also: REENTRY_PROMPT_*.md added to .Rbuildignore (they were tripping R CMD check's
# top-level-files note). vignettes/quality-flagging.Rmd deliberately NOT given the
# purl = FALSE fix applied to the other 9 ecosystem vignettes -- it has no global
# eval = FALSE and genuinely evaluates. devtools::test() 222 pass / 0 fail;
# devtools::check() 0 errors, with the pre-existing build_review_covariates.R
# warning + .data note unchanged (confirmed untouched). Reinstalled.
# Previous update, 2026-07-24, later still (Sonnet 5 -- review_assignments() wired up to
# TaxaAssign::posterior_consensus()/add_slash_taxon() columns that postdate when this
# function was originally written, prompted by the user asking to tabulate which newer
# consensus columns weren't being taken into account. Four new params, all additive/
# backward-compatible (non-NULL defaults matching the real producer column names,
# silently skipped -- not an error -- when that column is absent from df, matching
# add_posthoc_assessment()'s own established convention for this kind of optional
# pass-through column): consensus_posterior_col ("consensus_posterior"), winner_prior_col
# ("winner_prior"), winner_rank_expanded_col ("winner_rank_expanded"),
# plausible_posteriors_col ("plausible_posteriors"). When present, a compact "[...]"
# annotation is appended to each taxon's line in the LLM prompt: median pipeline
# posterior/occurrence prior across every row sharing that taxon/candidate-set label (so
# the LLM's ecological plausibility judgment can be checked against the pipeline's own
# statistical confidence), a note when the winning call came from join_priors()'s
# coarse-rank expansion with no real sequence discrimination, and -- for multi-candidate
# slash/plus labels -- each candidate's own averaged posterior weight (so review_comment
# can speak to the specific weaker member instead of the undifferentiated group). New
# GUIDELINES bullet tells the LLM what the bracket means and how to use it (flag
# disagreement, don't defer to it). Deliberately did NOT wire in consensus_reason/
# is_resolved/n_plausible/winner_likelihood(_cov)/winner_absolute_fit_pvalue/the four
# winner_*_confusion_risk columns/taxon_changed -- either redundant with what
# add_posthoc_assessment() already does numerically, or judged not worth the added prompt
# tokens for this function's specific (ecological plausibility, not statistical
# confidence) job. Separately, fixed a real label-drift risk found during the same
# discussion: the candidate-set path's label builder (.build_candidate_label(), a
# documented duplicate of add_slash_taxon()'s .make_slash_name()) had no equivalent of
# add_slash_taxon()'s downranked-row NA-clearing logic, so the two could produce DIFFERENT
# labels for the same row once species_reference downranking was in play. Now prefers
# df$consensus_OTU (add_slash_taxon()'s own already-computed, already-correct label) when
# present, falling back to the independent rebuild only when absent -- closing the drift
# without adding a hard TaxaAssign package dependency. Both new helpers
# (.summarise_pipeline_context()/.summarise_candidate_weights()) group via split() (O(n))
# rather than a per-label linear scan, to stay cheap on large datasets. Verified with an
# offline mocked-llm_fn smoke test (median aggregation, rank-expanded flag, and candidate
# weights all confirmed correct against hand-computed expected values) in addition to the
# full test suite. devtools::test() 232/232 (0 failures, unchanged from before -- no
# existing test's df carries these new columns, so backward compatibility is exercised by
# the existing suite passing unchanged), devtools::check() 0 errors/0 warnings (1
# pre-existing, unrelated warning+note in build_review_covariates.R, confirmed untouched
# via git diff). Not yet wired into any real production workflow -- both real PtConception
# review_assignments() calls would need to be updated to pass a consensus_df carrying
# these columns (currently upstream of add_slash_taxon() in at least one of the two
# workflows; not verified this session) before the new context would actually appear in a
# live LLM call.
# Previous update, 2026-07-24, later same day (Sonnet 5 -- the unified validity schema below
# (observation_validity/validity_flag/validity_reason) wired into both real PtConception
# production workflows (PtConceptionWorkflow_12S_single_site.R,
# PtConceptionWorkflow_18S_2_single_site.R -- outside this monorepo, not under git, at
# ~/My Drive/Rscripts/eDNA/PtConception/), backed up first as *.bak_pre_validity_schema.
# Every real lab_contaminant_risk/lab_contaminant_score reference at each file's Step 2
# filter, Step 6/9 provenance joins, and (12S only) the final accurate_precise_consensus
# filter updated to validity_flag == "invalid_lab_contaminant" / observation_validity;
# deliberately left untouched: contamination_risk/spatial_flag/*_plausibility (unrelated
# columns from review_assignments()/flag_habitat_inconsistencies(), confirmed by tracing
# each column's real source before editing, not by name similarity alone). 18S_2's own
# pre-existing Session 101 name-migration block (upgrading a cached RDS's old
# flag_lab_contaminant naming forward) was EXTENDED, not replaced, with a second branch
# migrating lab_contaminant_risk/score/reason values forward to the new schema
# ("high"/"moderate"/"low" -> "invalid_lab_contaminant"/"questionable_lab_contaminant"/
# "valid") -- verified against both real cached *_contaminant_flags.rds checkpoints (12S:
# 43/10300/3254 high/moderate/low; 18S: 1/18693/2503), which are themselves still on the
# pre-2026-07-24 schema, confirming the migration path is genuinely exercised, not
# speculative. Also confirmed the freshly-installed flag_contaminant() itself now emits
# the new schema directly (live-tested against a small synthetic case) -- an initial
# verification attempt without explicitly setting R_LIBS_USER showed the OLD schema,
# which was the documented bare-Rscript library footgun, not a real regression; resolved
# by setting .libPaths() explicitly per that footgun's known fix. Both workflow files
# parse cleanly (parse() check); not yet run end to end (would trigger live GBIF/NCBI/LLM
# calls) -- left for the user to trigger.
# Previous update, 2026-07-24 (Sonnet 5 -- flag_contaminant()/flag_handler() redesigned around a
# unified observation_validity/validity_flag/validity_reason schema, closing out the polarity
# audit's two flagged-but-deferred names (contaminant_score, flag_handler_score) from
# 2026-07-23. Real correction found mid-design: both were mischaracterized in the original
# audit as "high=more risk" (matching contaminant_risk-style naming) -- verified directly
# against source and actually HIGH=GOOD/genuine, LOW=likely contaminant or handler artifact
# (contaminant_score's own roxygen: "Taxa with a higher rate in controls than field samples
# receive low scores"). Renaming them to a "_risk" suffix would have been a backwards, actively
# WRONG fix, not merely a missed opportunity -- caught by reading the real case_when()/
# threshold logic before touching any file, not by trusting the prior day's audit conclusion.
# Final schema (both functions now share it, matching add_posthoc_assessment()'s existing
# "one column, type-qualified values" precedent rather than inventing a new pattern):
# observation_validity (numeric 0-1, high=good, was contaminant_score/flag_handler_score);
# validity_flag (character: "valid"/"questionable_{type}"/"invalid_{type}", was
# {contaminant_type}_risk's high/moderate/low and flag_handler's likely/possible/unlikely);
# validity_reason (was {contaminant_type}_reason/flag_handler_reason). contaminant_type's
# column-NAME-parameterization (e.g. lab_contaminant_risk vs positive_control_risk, letting two
# calls coexist on the same taxa) is gone -- verified first that neither real PtConception
# workflow uses that multi-call pattern -- the type now lives in validity_flag's VALUE instead
# (e.g. "invalid_lab_contaminant"), matching flag_handler()'s fixed-name convention. Kept the
# existing 3-tier severity (not collapsed to binary) per explicit user direction, so no
# information is lost relative to the old high/moderate/low or likely/possible/unlikely scales.
# report_flags() gained a THIRD auto-detection branch (validity_flag-based, additive to the two
# pre-existing naming eras it already supported) since column names alone no longer identify
# which check produced a flag -- reads the type qualifier out of the VALUE instead. Also fixed
# a real citation error in add_posthoc_assessment()'s own confusion_risk_flag docs (written
# 2026-07-23), which had cited contaminant_score as a "high=concern" precedent -- backwards,
# now corrected. devtools::test() 0 failures (123, up from 119 -- 4 new report_flags() tests for
# the new detection branch), devtools::check() 0 errors/0 warnings (1 pre-existing, unrelated
# warning+note in build_review_covariates.R, untouched). Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-23, later same day (Sonnet 5 -- renamed add_posthoc_assessment()'s
# score_support_flag -> confusion_risk_flag (+ own_rank_support_col -> own_rank_confusion_risk_col,
# weak_score_support_threshold -> high_confusion_risk_threshold, and the two flag values
# "weak_score_support"/"adequate_score_support" -> "high_confusion_risk"/"low_confusion_risk"),
# matching the same-day TaxaLikely/TaxaAssign renames -- see TaxaID/CLAUDE.md's top session
# note for the full cross-package record. Pure rename, no math changed; 7 tests renamed in
# place (not new), same 119 total. The note below (same day, earlier) describes the original
# implementation and now uses the corrected names throughout.
# Previous update, 2026-07-23 (Sonnet 5 -- add_posthoc_assessment() gains a new, deliberately
# SEPARATE confusion_risk_flag column (own_rank_confusion_risk_col default "winner_own_rank_confusion_risk",
# high_confusion_risk_threshold default 0.5) implementing Task 1's TaxaFlag wiring from
# ecosystem_docs/REENTRY_PROMPT_score_support_posthoc_and_rank_thresholds.md (full
# cross-package record in TaxaID/CLAUDE.md's top session note). Reads
# TaxaAssign::posterior_consensus()'s new winner_own_rank_confusion_risk pass-through (itself sourced
# from TaxaLikely::evaluate_likelihoods()'s new species_confusion_risk/genus_confusion_risk/family_confusion_risk --
# a model-independent, score-ONLY diagnostic where LOWER values mean STRONGER evidence).
# Deliberately kept as its OWN new column rather than folded into posthoc_assessment's existing
# override chain the way "unsupported_rank" is -- the explicit design rationale, documented in
# a new @section Confusion-risk flag, is the trusted_rank ladder-walk's own cautionary precedent
# (built 2026-07-19, removed 2026-07-20 after a real ~30% mismatch + a downranking-cancellation
# bug, see [[project_rank_trust_mechanism_removed]]): a mechanism that recomputes/overrides an
# existing categorical judgment is exactly the shape that broke there, so confusion_risk_flag
# stays a plain additive threshold that never interacts with posthoc_assessment. 7 new tests
# added to test-add_posthoc_assessment.R (119 total, up from 112) covering the NA-when-absent
# case, above/below-threshold classification, NA-propagation, custom column name, non-
# interaction with posthoc_assessment, and both new input-validation errors. devtools::test()
# 0 failures (119), devtools::check() 0 errors/0 warnings (1 pre-existing, unrelated warning +
# note in build_review_covariates.R, confirmed untouched this session via git diff).
# Reinstalled to ~/Library/R/4.0/library.
# Previous update, 2026-07-20 (Sonnet 5 -- add_posthoc_assessment()'s "unsupported_rank"
# category (added the day before, see the Session 2026-07-19 note directly below)
# redesigned: `trusted_rank_col` (default `"winner_trusted_rank"`, comparing rank ORDER
# against `consensus_rank_col`) replaced by `absolute_fit_pvalue_col` (default
# `"winner_absolute_fit_pvalue"`) + a new `weak_evidence_pvalue` threshold (default
# `0.001`), comparing the p-value DIRECTLY rather than going through a rank comparison at
# all. Same trigger position (Step 4, still overrides any of the 3x2-table categories
# including "sensible"), same category name, much simpler logic -- no `.std_rank_order`
# constant needed anymore (deleted). Prompted by the user pressure-testing yesterday's
# `winner_trusted_rank`/`uprank_trust_pvalue` mechanism against their own real 12S run:
# a live diagnostic confirmed `winner_trusted_rank` was computed upstream
# (`TaxaLikely::evaluate_likelihoods()`) for that FUNCTION's own top-LIKELIHOOD
# hypothesis, not necessarily the same hypothesis that wins the POSTERIOR reported by
# `TaxaAssign::posterior_consensus()` here -- a confirmed ~30% mismatch on real data,
# meaning `"unsupported_rank"` could fire (or fail to fire) based on the wrong
# candidate's fit. `winner_absolute_fit_pvalue` doesn't have this problem: it is always
# read directly off whichever row `posterior_consensus()` itself treated as the winner,
# with no intermediate ladder-walk to go stale. `TaxaLikely::evaluate_likelihoods()`'s
# entire `min_rank_trust_pvalue`/`trusted_rank`/`rank_trust_basis` mechanism was removed
# the same day (see `TaxaLikely/CLAUDE.md`'s own top note) -- `absolute_fit_pvalue`
# itself is unchanged and still computed unconditionally, only the ladder-walk built on
# top of it is gone. Before implementing, independently re-confirmed
# `absolute_fit_pvalue`'s one-sided design is safe for perfect/near-ceiling matches
# (never penalizes a score better than the trained mean) -- directly answering the
# user's own question about whether this substitution could misfire on exactly the
# cases it's meant to catch. `devtools::test()` 208/208 (0 failures), `devtools::check()`
# clean except the pre-existing, unrelated `build_review_covariates.R`
# warning/note (confirmed via a fresh `check()` mentioning neither
# `add_posthoc_assessment` nor this file). Reinstalled to `~/Library/R/4.0/library`.
# See [[project_rank_trust_mechanism_removed]] in the TaxaID memory system for the full
# investigation record. `add_posthoc_assessment()`'s `"unsupported_rank"` category is
# the intended end state here, not an interim step -- it already says "the evidence may
# be too weak to be confident at the reported rank," which is all that was wanted; no
# further work to suggest a specific replacement rank is planned (confirmed with the
# user, who found an earlier draft of this note over-scoped).
# Previous update, 2026-07-19 (Sonnet 5 -- add_posthoc_assessment() gains a new
# "unsupported_rank" category (Step 4, overrides any of the existing 3x2-table
# categories including "sensible") + new trusted_rank_col param (default
# "winner_trusted_rank", silently skipped when absent from consensus_df -- optional
# upstream output, not required input). Consumes TaxaAssign::posterior_consensus()'s new
# winner_trusted_rank pass-through (see TaxaAssign/CLAUDE.md), itself sourced from
# TaxaLikely::evaluate_likelihoods()'s new rank-trust mechanism (TaxaLikely/CLAUDE.md).
# Real motivation, not hypothetical: winner_likelihood_col is ratio-normalised WITHIN one
# observation (best hypothesis always exactly 1.0 by construction) -- it can read as
# strong evidence even when every candidate fit poorly in absolute terms, simply because
# nothing competitive existed to normalise against (the real motivating case: a
# contamination-pattern detection where every specific candidate species scores poorly
# in absolute terms but the weakest-of-a-bad-lot still "wins" the relative comparison
# outright, landing "sensible" under the old 3x2 logic alone if its prior tier happened
# to be favorable). trusted_rank_col answers a genuinely different, absolute question
# (does this call's own fit to its trained distribution actually hold up at the rank
# being reported), and a mismatch overrides whatever the tier x likelihood table said.
# Purely informational/additive -- never changes consensus_taxon/consensus_rank itself
# (that's TaxaAssign::posterior_consensus()'s own separate, opt-in uprank_trust_pvalue
# mechanism); backward compatible, zero behavior change for any consensus_df lacking the
# new column. REAL BUG found and fixed the same session via a full real 13,442-observation
# PtConception run (not caught by synthetic tests, which all used same-rank-family
# fixtures): the first version used plain string inequality (trusted != consensus_rank),
# which flagged 4,776 real rows -- but 48% (2,275) had trusted_rank FINER than
# consensus_rank, meaning disagreement-based LCA logic had already coarsened the call
# beyond what absolute fit alone requires (not "unsupported" at all, if anything more
# conservative than necessary). Fixed with a new .std_rank_order canonical coarse-to-fine
# constant (mirrors evaluate_likelihoods()'s own auto-detection list) so the mismatch only
# fires when trusted_rank is COARSER than consensus_rank; corrected real count: 2,501/
# 13,442 (18.6%). New regression test reproduces the exact real failure mode. 9 new tests
# total in test-add_posthoc_assessment.R (42 total). devtools::test() 206/206 (0 failures,
# up from 197), devtools::check(): 1 pre-existing warning + 1 pre-existing note in an
# unrelated file (build_review_covariates.R, last touched 2026-07-14, not part of this
# change) -- confirmed via git diff this session touched only add_posthoc_assessment.R/
# .Rd/its test file. Reinstalled to ~/Library/R/4.0/library. Wired into
# PtConceptionWorkflow_12S_single_site.R's add_posthoc_assessment() call
# (trusted_rank_col = "winner_trusted_rank"). See TaxaAssign/CLAUDE.md's and
# TaxaLikely/CLAUDE.md's own session notes for the paired posterior_consensus()
# uprank_trust_pvalue wiring and the full real-data validation record, including the real
# problem this combination caught: 8 real observations confidently called
# Urocyon cinereoargenteus/Canis lupaster (terrestrial canids) at species level in this
# marine 12S survey, absolute_fit_pvalue ~ 0.002-0.004.
# Previous update, 2026-07-11 (Session 152 -- flag_contaminant()'s shrinkage denominator
# changed from SAMPLE count to READ count (n_reads_total = taxon_field_reads +
# taxon_control_reads, replacing n_field_present + n_controls_present), and
# prior_weight's default changed 2 -> 20 to match the new read-equivalent units.
# Session 151's own shrinkage design (0.5 target, applied to the already
# depth-weighted field_rate/control_rate ratio) was correct -- the flaw, found by
# live-testing the Template and both real PtConception workflows
# (ecosystem_docs/REENTRY_PROMPT_session151_debug_template_and_12S_18S.md), was that
# shrinking by SAMPLE count conflated a 2-read detection with a 500,000-read detection
# whenever both happened to come from exactly one sample -- capping BOTH at the same
# distance from 0.5 regardless of actual evidence strength. Concretely: with the
# Session 151 default (prior_weight=2, samples), no taxon detected in 1-8 total samples
# could ever reach "low" risk even with overwhelming read support, and the median real
# taxon in both real PtConception datasets is detected in exactly 1 field sample -- so
# 97% (12S) / 88% (18S) of taxa were capped at "moderate" purely as a sample-count
# artifact, not because the evidence was actually ambiguous.
# Two literature-informed alternatives (decontam's presence/absence prevalence test via
# a hypergeometric test; a depth-weighted binomial-exact test) were prototyped first and
# REJECTED after live-testing against real data: both are one-sided tests where
# "0 control reads" trivially gives p=1 regardless of total evidence, so both degenerate
# almost exactly back to the pre-151 hard-1.0 problem (verified: median score 1.0 on
# both real datasets, undoing Session 151's whole point). A third alternative (Beta-
# Binomial shrinkage toward the study's own depth-based background rate p0) was also
# rejected: it requires anchoring to p0 explicitly and does NOT transfer across studies
# with very different control:field depth ratios -- confirmed directly: it worked
# reasonably on 12S (p0=0.00059) but missed the known real contaminant entirely on 18S
# (p0 rounds to 0, only 1 control/54 field samples) at every prior strength tested.
# Read-count-based shrinkage in the EXISTING depth-normalized rate space needed no new
# anchor point (0.5 remains correct there) and was validated empirically at
# prior_weight in {20, 50, 100, 500}: 100% of known "high"-risk taxa recovered with
# ZERO false positives at every value, on BOTH real datasets, while far more
# well-supported clean taxa correctly reach "low" instead of being capped at
# "moderate" (12S: 330 -> 3263 "low"; 18S: 2503 -> 4140 "low", at the chosen
# prior_weight=20). New `n_reads_total` output column exposes the quantity that now
# drives shrinkage (n_field_present/n_controls_present/n_controls_total remain,
# informational only, unchanged in meaning). Reason string now reports the read count
# used for shrinkage alongside the existing sample-count context. Fully backward
# compatible in shape (no new required params, same column set plus one addition);
# NOT backward compatible in behavior (same as Session 151's own change) -- every
# existing caller relying on the implicit default gets different scores/tiers.
# devtools::test() 185/185 passing (0 failures, 2 pre-existing unrelated warnings in
# review_assignments tests), including a new dedicated test constructing two taxa with
# IDENTICAL sample-count evidence but very different read counts to confirm they now
# score differently, plus rewritten TaxonA/sample_type_col tests reflecting the new
# exact score values. devtools::check() 0 errors/0 warnings/0 notes. See
# ecosystem_docs/REENTRY_PROMPT_session151_debug_template_and_12S_18S.md for the full
# investigative record (the decontam-literature comparison, all three rejected
# prototypes, and the real-data validation) and this file's own flag_contaminant()
# Design section below for the current mechanism.
# Previous update, same day (Session 151, once more -- ecosystem soundness-review item 16
# (flag_handler()'s edge_proximity_score), the LAST of the review's 16 H-priority items,
# fixed: new optional station_metadata param anchors group edges on real per-station
# deploy/retrieve timestamps instead of the detection data's own min/max. The core flaw:
# without real deployment metadata, the very first and last GENUINE wildlife detection at
# a station is always exactly at the data-derived edge and scores maximally suspect,
# purely as an artifact of how "edge" is defined -- not because a handler was ever
# present. station_metadata mirrors the "external attribute lookup table keyed by a
# sample/event identifier" pattern already established in this ecosystem
# (TaxaMatch::join_event_site_metadata(), the BLANKS_MARCH/BLANKS_AUG convention): one row
# per group_col value with deploy_time/retrieve_time (column names configurable via
# deploy_col/retrieve_col). A group present in the data but missing from
# station_metadata (or with an unparseable timestamp) falls back to the data-derived
# min/max for that group only, with an explicit warning() naming it -- a real weakening
# of that group's flag, not a silent one. New edge_anchor_source output column records,
# per row, whether "station_metadata" or "detection_data_fallback" was used. Fully
# additive/backward compatible: station_metadata defaults NULL, and all 36 pre-existing
# tests pass completely unchanged. The vignette (quality-flagging.Rmd) -- still this
# function's only real call site anywhere in the monorepo -- updated to demonstrate the
# new param. 12 new tests. devtools::test() 181/181 (up from 169), devtools::check()
# clean. This closes out the full 16-item H-priority soundness-review walk-through: 16 of
# 16 addressed (fixed/mitigated/reclassified/flagged-by-design -- see
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md for the final per-item status;
# "addressed" does not mean every caveat is resolved, several items remain CONDITIONAL
# with explicitly documented open gaps).
# Previous update, same day (Session 151 -- ecosystem soundness-review item 15
# (flag_contaminant()'s contaminant_score) fixed: depth-weighted rates + Empirical Bayes
# shrinkage replace the old unweighted-mean-of-proportions formula with its hard 0.0/1.0
# edge cases. field_rate/control_rate now = sum(taxon reads in group)/sum(total reads in
# that group) -- a proportion from 500,000 reads counts far more than one from 50, fixing
# "read-depth-unweighted." The raw ratio field_rate/(field_rate+control_rate) is then
# shrunk toward 0.5 with weight n_present/(n_present+prior_weight) (default prior_weight=2,
# n_present = total samples across both groups where the taxon was detected) -- a taxon
# absent from controls no longer gets an automatic exact 1.0 when only a couple of controls
# exist. Design bug found and fixed mid-implementation, not just in code review: an earlier
# version shrunk field_rate/control_rate individually toward the taxon's own pooled
# (field+control) rate, which let a taxon's large field read volume leak into its
# control-side prior, systematically understating genuinely clean taxa's scores whenever
# field sequencing depth dominated control depth (the common real case: many field samples,
# few small blanks) -- caught only by running the actual test suite against the mock data
# and seeing TaxonA (a clean, field-only taxon) score "moderate" instead of "low." Fixed by
# shrinking the FINAL ratio toward 0.5 by sample-count replication instead, which keeps the
# two groups' magnitudes fully independent. Also fixed: roxygen no longer calls the score a
# "probability" -- explicit new prose states it's a ranked screening statistic. New
# mean_prop_field/mean_prop_control (unweighted, informational only) vs. field_rate/
# control_rate (depth-weighted, drives the score) distinction throughout docs/reason
# strings. New prior_weight param (default 2, 0 disables shrinkage). Tests updated: two
# tests asserting exact 1.0/0.0 for absent-from-one-side taxa now assert the shrunk,
# non-exact values instead (matching item 11/12's "tests exercising old exact math now pin
# that value explicitly" pattern); new tests cover prior_weight=0 (exact un-shrunk
# boundary), prior_weight sensitivity, and input validation. devtools::test() 169/169,
# devtools::check() clean. See ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's
# item 15 for the full record.
# Previous update, 2026-07-10 (Session 149 -- add_posthoc_assessment() gains domestic_taxa/
# domestic_prior_source params, implementing the deferred domestic-species-floor design note
# ([[project_taxaflag_domestic_species_floor_note]] in project memory) at the user's direction
# during the ecosystem statistical soundness review walk-through. A strong-likelihood call to a
# user-specified domestic/synanthropic taxon that lands in tier2/tier3_undetected purely because
# GBIF/iNat under-index captive organisms is now re-labelled "domestic_prior_caveat" instead of
# "unexpected"/"unprecedented", so a reviewer sees "trust the ID, question the rarity" rather
# than a generic low-plausibility flag. domestic_taxa defaults to NULL (feature off, matching
# flag_handler()'s handler_taxa convention -- no built-in species list, since "domestic" is
# study-system-specific). domestic_prior_source = "wild" (default) vs "augmented" gives an
# explicit opt-out for pipelines that already augment occurrence data with known local domestic
# presence (the companion prior-side fix: TaxaExpect::generate_undetected_diversity() and
# TaxaAssign::join_priors() both gained a documentation-only note recommending exactly that
# augmentation, rather than TaxaID inventing a fix on the prior side). Backward compatible
# (new params both optional, no behavior change when domestic_taxa is not supplied). 7 new
# tests added to test-add_posthoc_assessment.R (33 test_that blocks total in that file);
# devtools::test() 159/159 passing, 0 failures; devtools::check() 0 errors/0 warnings/1
# pre-existing NOTE (clock-check artifact, same as
# other packages). See this file's own Session 149 note below for the full record, and
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md for the review row this resolves.

---

## Package Purpose
Identifies and flags anomalous detections in taxonomic assignment results.
Correct identifications can still be ecologically meaningless due to:
- **Lab contamination** -- human DNA, reagent contaminants, index hopping
- **Field contamination** -- airborne DNA, handler artifacts during collection
- **Allochthonous detections** -- DNA/images/sounds transported from elsewhere
  (e.g., marine fish DNA carried by cormorant into freshwater stream)
- **Taxonomic scope violations** -- taxa outside the study's target group
  (e.g., plant DNA in a fish eDNA survey)

Operates on consensus data frames from TaxaAssign (or any data frame with
a taxon column). Appends categorical flag columns for user-driven filtering.

**Cross-modality:** Functions work for eDNA sequences, camera trap images,
and acoustic detections. Modality-specific logic lives in prompt text and
parameter defaults, not function signatures.

**Status: All core functions implemented and passing devtools::check() (0 errors, 0 warnings).**

---

## Dependency Chain

TaxaAssign -> **TaxaFlag** (post-assignment quality control)

TaxaFlag depends on:
- dplyr, jsonlite, stats (Imports)
- TaxaTools (Imports -- LLM provider functions for review_assignments, report_flags)

---

## Flag Column Convention

**Vocabulary design:** All columns use a consistent direction — higher value = worse for the taxon's credibility as a real detection.

**Data-driven risk columns** (`flag_contaminant`, `flag_handler`) add a triplet:
- `{type}_risk` -- character: `"high"` (probable artifact) / `"moderate"` (uncertain) / `"low"` (likely genuine)
- `{type}_score` -- numeric: interpretable ratio or confidence (0–1; higher = more likely genuine)
- `{type}_reason` -- character: plain-English explanation

**LLM plausibility columns** (`review_assignments`):
- `habitat_plausibility`, `geographic_plausibility`, `scope_plausibility` -- `"likely"` / `"possible"` / `"unlikely"` (higher = more plausible genuine detection)
- `contamination_risk` -- `"high"` / `"moderate"` / `"low"` (higher = more contamination risk)

Note: `{type}_score` (numeric) is NOT the same direction as `{type}_risk` (character). Score near 1.0 = low risk (real detection); score near 0.0 = high risk (contaminant). This asymmetry is intentional: scores are intermediate outputs for threshold-tuning; risk labels are the user-facing result. (`flag_contaminant()`'s score no longer reaches an exact 0.0/1.0 since Session 151's shrinkage fix -- see below.)

`review_assignments()` adds 8 structured LLM assessment columns (see below).

---

## Function Inventory

| Function | File | Status | Description |
|----------|------|--------|-------------|
| `.compute_contaminant_scores()` | `R/flag_contaminant.R` | Written | Internal: proportion-based control comparison algorithm |
| `flag_contaminant()` | `R/flag_contaminant.R` | Written | Compare read proportions between field samples and controls; `contaminant_type` param selects lab vs field vs positive control. **Session 151**: depth-weighted rates + Empirical Bayes shrinkage replace the old unweighted-mean/hard-0-1 formula; score documented as a ranked screening statistic, not a probability. **Session 152**: shrinkage denominator changed from sample count to read count (`prior_weight`, default `20`, now read-equivalent units) -- see "flag_contaminant() Design" below. **2026-07-24**: output columns renamed to the unified schema -- `observation_validity` (was `{contaminant_type}_score`, high=good, unchanged direction/math), `validity_flag` (was `{contaminant_type}_risk`; values now `"valid"`/`"questionable_{contaminant_type}"`/`"invalid_{contaminant_type}"`, was `"low"`/`"moderate"`/`"high"`), `validity_reason` (was `{contaminant_type}_reason`). Column NAMES no longer vary by `contaminant_type` -- the type now lives in `validity_flag`'s value instead. |
| `flag_handler()` | `R/flag_handler.R` | Written | Temporal proximity to start/end of sampling period; placeholder for camera trap handler artifacts. **Session 151**: optional `station_metadata` param anchors edges on real deploy/retrieve timestamps instead of the data's own min/max (opt-in, backward compatible; see "flag_handler() Design" below). **2026-07-24**: output columns renamed to the same unified schema as `flag_contaminant()` -- `observation_validity` (was `flag_handler_score`, high=good, unchanged direction/math), `validity_flag` (was `flag_handler`; values now `"valid"`/`"questionable_handling"`/`"invalid_handling"`, was `"likely"`/`"possible"`/`"unlikely"`), `validity_reason` (was `flag_handler_reason`). `edge_anchor_source` unchanged. |
| `.parse_datetimes()` | `R/flag_handler.R` | Written | Internal: auto-detect datetime format |
| `review_assignments()` | `R/review_assignments.R` | Written | LLM expert review: habitat, geography, scope, contaminant, alternatives. Default `taxa_per_call = 15` to avoid response truncation. `data_type` param ("eDNA"/"acoustic"/"image") switches contaminant guidance in LLM prompt. **2026-07-24**: gains `consensus_posterior_col`/`winner_prior_col`/`winner_rank_expanded_col`/`plausible_posteriors_col` (all optional, silently skipped when absent) -- when present, appends a compact pipeline-confidence/occurrence-prior/rank-expanded/candidate-weight annotation to each taxon's LLM prompt line, so the LLM's ecological judgment can be checked against the pipeline's own statistics. Also now prefers `df$consensus_OTU` (from `TaxaAssign::add_slash_taxon()`) for candidate-set labels when present, instead of always rebuilding independently -- closes a label-drift risk on downranked rows. |
| `.normalise_context()` | `R/review_assignments.R` | Written | Internal: normalise build_context() or named list to standard fields |
| `.build_review_prompt()` | `R/review_assignments.R` | Written | Internal: construct structured LLM prompt |
| `.parse_review_response()` | `R/review_assignments.R` | Written | Internal: parse + validate LLM JSON response; multi-strategy parser with truncated JSON recovery |
| `.recover_truncated_json()` | `R/review_assignments.R` | Written | Internal: salvage complete JSON objects from truncated LLM response |

| `add_posthoc_assessment()` | `R/add_posthoc_assessment.R` | Written | **Redesigned 2026-07-30, superseding everything below this row from Session 149 onward.** The old single-column `posthoc_assessment` (9 categories, `tiers`/`taxon_col`/`tier_col`/`finest_rank` params, including `"vague_rank"` and `"unsupported_rank"`) is entirely retired -- see this file's top session note. Now appends FIVE columns implementing two independent, orthogonal axes, reported for `primary_taxon` and `consensus_taxon` separately, neither gating the other: **Axis 1** (`primary_plausibility`/`consensus_plausibility`, "how expected is this taxon here?") -- `"expected"`/`"unexpected"`/`"unprecedented"`/`"not_modeled"`, driven by `winner_theta_col` (default `"winner_theta_mean"`) + `winner_record_col` (default `"winner_has_occurrence_record"`) at primary scope, `consensus_prior_col` (default `"consensus_prior"`) + `consensus_record_col` (default `"consensus_has_occurrence_record"`, 2026-07-30 new) at consensus scope, compared against `expected_theta_threshold` -- a REQUIRED named vector keyed by rank (`"species"` mandatory, `genus`/`family` optional; a rank absent from the vector gets `"not_modeled"`). `"unprecedented"` is driven by record presence (the `*_record_col`), never by a low threshold value -- a never-reported taxon and a genuine singleton can share the same numeric floor while meaning opposite things. **Axis 2** (`primary_discrimination`/`consensus_discrimination`, "could the evidence tell this taxon apart from a plausible relative?") -- `"discriminating"`/`"weak"`/`"indistinguishable"`/`"not_modeled"`, driven by `primary_confusion_risk_col`/`consensus_confusion_risk_col` against `discriminating_threshold`/`indistinguishable_threshold` (default 0.05/0.5) -- this is the direct successor to the old `confusion_risk_flag` column (now two rank-scoped columns instead of one). `domestic_prior_caveat` (logical) is unchanged in purpose (Session 149) but now reads `primary_plausibility` instead of the retired tier lookup. See this file's top session note for the full real-data verification record. |

**Dropped (Session 62):** `flag_allochthonous()` and `flag_taxonomic_scope()` -- absorbed
into `review_assignments()`. One LLM call covers habitat, geography, scope, contaminant
screening, and alternative suggestions more efficiently than separate functions.

**Dropped (Session 63):** `combine_flags()` and `flag_detections()` -- users should
filter on individual flag columns directly. A wrapper that guesses parameters is more
frustrating than helpful; workflow scripts are more transparent.

---

## flag_contaminant() Design

**Input:** Long-format data frame (one row per sample x taxon) with read counts.
**Output:** Per-taxon summary (one row per taxon), sorted by score.

**Key parameters:**
- `event_col` -- column identifying L1 collection events (default `"event_id"`)
- `control_samples` -- character vector of event IDs that are controls (blanks or positive controls)
- `sample_type_col` / `control_types` -- alternative: identify controls via a column
- `exclude_samples` -- remove samples from both control and field calculations
- `contaminant_type` -- controls output column names (`{contaminant_type}_risk`, `{contaminant_type}_score`, `{contaminant_type}_reason`)
- `score_thresholds` -- numeric(2), default `c(0.5, 0.9)`
- `prior_weight` -- numeric, default `20` (**Session 152**; read-equivalent units --
  previously sample-equivalent units, default `2`, through Session 151). Shrinkage
  strength for the final ratio toward 0.5; `0` disables shrinkage.

**Algorithm:** `.compute_contaminant_scores()` (**Session 152** -- see that function's
roxygen "Depth-weighting and shrinkage" and "Reads, not samples, as the shrinkage
denominator" sections for the full real-data motivation, including three rejected
alternatives):
1. Depth-weighted rate per group: `field_rate`/`control_rate` = `sum(taxon reads in group) /
   sum(total reads across samples in that group)` -- a proportion from 500,000 reads now
   counts far more than one from 50. (The old unweighted per-sample-proportion mean is
   still computed as `mean_prop_field`/`mean_prop_control` for reference, but no longer
   drives the score.)
2. Raw ratio: `field_rate / (field_rate + control_rate)`.
3. Shrunk toward 0.5 (maximally uncertain) with weight `n_reads_total / (n_reads_total +
   prior_weight)`, where `n_reads_total` = total READS (field + control combined) for
   that taxon -- same Empirical Bayes form used throughout this ecosystem (e.g.
   `TaxaLikely::train_likelihood_model()`'s per-species shrinkage), but measured in
   reads, not samples (**Session 152** -- Session 151 used sample count
   `n_field_present + n_controls_present`, which conflated a 2-read detection with a
   500,000-read detection whenever both came from one sample; see the CLAUDE.md session
   note above for the real-data evidence and the three alternatives tried and rejected
   before landing here). Applied to the FINAL ratio, not to `field_rate`/`control_rate`
   individually toward a shared reference rate -- an earlier design shrunk each rate
   toward the taxon's own pooled (field+control) rate, which let a taxon's own (usually
   much larger) field read volume leak into its control-side prior and systematically
   understated genuinely clean taxa's scores whenever field depth dominated control
   depth. Caught by actually running the test suite, not by review alone.
4. Taxa absent from controls no longer get an automatic exact 1.0 -- with little total
   read support, real absence is still real evidence, but shrinkage keeps the score
   below 1.0 in proportion to how little total evidence supports it. A taxon with
   substantial read support (even from a single sample) converges close to its raw ratio.
Score is documented as a ranked screening statistic, not a calibrated probability
(the roxygen previously called it one). New `n_reads_total` output column (Session 152)
exposes the read count that now drives shrinkage; `n_field_present`/`n_controls_present`/
`n_controls_total` remain, informational only.

---

## flag_handler() Design

**Input:** Data frame with a datetime column and optionally a grouping column.
**Output:** Input data frame with 4 columns appended (per-row flags; **Session 151** adds
`edge_anchor_source`).

**Key parameters:**
- `datetime_col` -- auto-parsed via `.parse_datetimes()`
- `group_col` -- min/max computed per group (e.g., camera station)
- `interval_minutes` -- flag window from edges
- `handler_taxa` -- optional whitelist (e.g., "Homo sapiens")
- `station_metadata` / `deploy_col` / `retrieve_col` -- **Session 151**, ecosystem
  soundness-review item 16. Optional data frame, one row per `group_col` value, with real
  deploy/retrieve timestamps -- the same "external attribute lookup table keyed by a
  sample/event identifier" pattern already used elsewhere in this ecosystem (e.g.
  `TaxaMatch::join_event_site_metadata()`, the `BLANKS_MARCH`/`BLANKS_AUG` convention).
  When supplied, anchors group edges on the REAL deployment window instead of the
  data's own detection min/max -- fixes the core flaw the review flagged: without this,
  the very first and last genuine wildlife detection at a station is always scored
  maximally suspect, purely because the edge is defined by the data itself, not because a
  handler was ever actually present. A group missing from `station_metadata` (or with an
  unparseable timestamp) falls back to the data-derived min/max for that group only, with
  a `warning()` naming it. Fully backward compatible -- default `NULL`, no behavior change
  for existing callers; every existing test (36) passes unchanged.

**Score:** `min(minutes_to_start, minutes_to_end) / interval_minutes`, clamped [0, 1],
computed against `group_min`/`group_max` -- real deploy/retrieve times when
`station_metadata` covers that group, data-derived min/max otherwise (see
`edge_anchor_source`).

**Still genuinely unfixed (Session 151, honestly recorded, not solved):** when
`station_metadata` is NOT supplied (still the default, and the only mode any real caller
has ever used -- see below), `handler_taxa` remains the sole real protection, exactly as
before this session; the structural bias itself is only fixed when a user actually has and
supplies a real deployment log. No live caller in the monorepo does yet -- `flag_handler()`
still has only one real call site anywhere: `vignettes/quality-flagging.Rmd`'s own example
(now updated to demonstrate `station_metadata`, Session 151). This was the lowest-priority
of the review's 16 H-priority items for exactly this reason (its own row: "no live caller
found yet, which is the only thing keeping this from being worse").

---

## review_assignments() Output Columns

| Column | Type | Values | What it captures |
|--------|------|--------|-----------------|
| `habitat_plausibility` | character | likely / possible / unlikely | Does this taxon live in this habitat? |
| `geographic_plausibility` | character | likely / possible / unlikely | Is this taxon found in this region? |
| `scope_plausibility` | character | likely / possible / unlikely | Target group match (only if `target_group` supplied) |
| `contamination_risk` | character | low / moderate / high | Common lab/field contaminant? |
| `review_alternatives` | character | comma-separated | Plausible alternatives at same rank (when taxon is implausible) |
| `review_lower_hypotheses` | character | comma-separated | Finer-rank taxa expected here (when consensus is coarse-ranked) |
| `review_confidence` | character | high / moderate / low | LLM's overall confidence |
| `review_comment` | character | free text | Anything structured fields don't capture |

**Key distinction:**
- `review_alternatives` = "you might have the wrong taxon" (implausible taxon, plausible relative)
- `review_lower_hypotheses` = "you have the right group, could narrow it down" (coarse consensus, likely species)

**Context input:** Accepts either `build_context()` output (data frame with `ecoregion`, `main_habitat`) or a simple named list (`list(geography = ..., habitat = ...)`).

---

## Workflow Scripts

| File | Purpose |
|------|---------|
| `inst/contaminant_workflow.R` | End-to-end: wide CSV -> pivot -> 3 flag_contaminant() calls (extraction, PCR, positive control) -> combined summary |
| `inst/review_assignments_workflow.R` | LLM review with test consensus data for Palmyra Atoll |

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-flag_contaminant.R | `flag_contaminant()` | Fully offline; covers all risk levels, custom thresholds, positive controls; uses Session 101 vocabulary (low/moderate/high) |
| test-flag_handler.R | `flag_handler()` | Fully offline; covers edge scoring, handler_taxa filtering |
| test-review_assignments.R | `review_assignments()` | LLM mocked; covers all 8 output columns, partial response recovery, Session 101 column names/values |
| test-report_flags.R | `report_flags()` | Fully offline |
| test-add_posthoc_assessment.R | `add_posthoc_assessment()` | Rewritten 2026-07-30 for the Axis 1/Axis 2 redesign (62 tests) -- the old `posthoc_assessment`-category tests are gone with the column. Covers: Axis 1 expected/unexpected/unprecedented/not_modeled at both scopes, the load-bearing "no-record-but-high-theta is unprecedented" vs "singleton-at-floor is not" pin, rank-relative `expected_theta_threshold` (species-only vs species+genus+family), `consensus_has_occurrence_record`-driven consensus scope (incl. the regression test for the real 100%-unprecedented production bug), Axis 2 discriminating/weak/indistinguishable/not_modeled at both scopes, `domestic_prior_caveat`, NA-when-columns-absent, input validation. |

---

## Session Notes

**Session 149 (2026-07-10): add_posthoc_assessment() domestic-species caveat**

Third item on the ecosystem statistical soundness review's H-priority walk-through
(`ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`) was
`TaxaAssign::join_priors()`'s dark-diversity floor treating domestic/synanthropic species
as exchangeable with genuinely unmodelled wild species -- the deferred design note from
[[project_taxaflag_domestic_species_floor_note]] (single-observation-pipeline work,
2026-07-03), never implemented. The user resolved where this belongs across two
functions rather than one: (1) priors -- a user who knows their study includes domestic
species should augment their occurrence data before training, and TaxaID's job is just
to document that clearly (a note is sufficient; not a code fix); (2) likelihoods --
iNaturalist image recognition and NCBI BLAST already handle domestic-species
classification fine, so the likelihood side needs no change; (3) the one thing worth
building is a small, narrow flag in TaxaFlag for the specific *contrast* -- a strong
likelihood for a domestic species next to a low prior, when that prior came from an
unaugmented wild-species database.

**Implementation:** `add_posthoc_assessment()` gains two new optional params:
- `domestic_taxa = NULL` -- character vector of taxon names the caller considers
  domestic/synanthropic for their study system. No built-in default list (matches
  `flag_handler()`'s `handler_taxa = NULL` convention) -- what counts as "domestic" is
  study-system-specific, so a curated list baked into the package would be either
  incomplete or presumptuous.
- `domestic_prior_source = c("wild", "augmented")` -- default `"wild"`. When a row's
  `consensus_taxon` is in `domestic_taxa` AND its likelihood is above
  `likelihood_threshold` AND it landed in the tier2/tier3_undetected branch (which would
  otherwise emit `"unexpected"`/`"unprecedented"`), the assessment is re-labelled
  `"domestic_prior_caveat"` instead -- signalling "trust the ID, question the rarity"
  rather than a generic low-plausibility flag. Passing `domestic_prior_source =
  "augmented"` disables this entirely, for pipelines that already incorporated known
  local domestic presence into their priors (the low tier is then genuinely
  informative, not a database artifact).

Deliberately narrow: only fires on the strong-likelihood + low-tier combination (a
low-likelihood domestic-species call stays `"suspect"`, correctly -- the caveat is about
the *prior*, not the identification), never invents or elevates a prior itself, and is
opt-in (`NULL` default, zero behavior change for existing callers).

**Companion prior-side documentation fix** (no code change, per the user's steer that a
note is sufficient there): `TaxaExpect::generate_undetected_diversity()` gained a new
`@section Domestic/synanthropic species` explaining the root cause (GBIF/iNat under-index
captive organisms) at the actual point where the floor value is computed, and recommending
occurrence-data augmentation before training as the fix; `TaxaAssign::join_priors()`'s
"Dark diversity fallback" section cross-references it. Both are pure roxygen additions --
`devtools::test()` unchanged (TaxaExpect 383/383, TaxaAssign 544/544), `devtools::check()`
clean on both.

7 new tests added to `test-add_posthoc_assessment.R` covering: default-off behavior,
tier2 and tier3_undetected re-labelling, the low-likelihood non-re-labelling case, no
effect on non-domestic taxa, the `"augmented"` opt-out, and input validation.
`devtools::test()`: 159/159 passing, 0 failures. `devtools::check()`: 0 errors, 0
warnings, 1 pre-existing NOTE (clock-check artifact, unrelated).

Sessions 60–74 archived in ecosystem_docs/session_notes/TaxaFlag_sessions.md.

**Session 79 (2026-05-20)**
- `sample_col` param → `event_col` in `flag_contaminant()` (this param identifies L1 collection
  events, not L2 observations; default changed from `"sample_id"` to `"event_id"`)
- `sample_id` → `observation_id` in all L2 references across R source, tests, vignettes, inst/, README
- `event_col` documented in CLAUDE.md flag_contaminant() design section
- 126 tests passing (2 warnings — pre-existing)

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- TaxaTools moved from Suggests to Imports (used unconditionally by `report_flags()` and
  as default in `review_assignments()`).

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaFlag-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration. See TaxaID/CLAUDE.md for full log.

**Session 86 (2026-05-23)**
- `review_assignments()`: `llm_fn` fallback updated from `TaxaTools::call_anthropic_api` to
  `TaxaTools::call_api`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`.

**Session 89 (2026-05-27)**
- `review_assignments()`: `data_type` param added (`"eDNA"` default / `"acoustic"` / `"image"`). Controls contaminant guidance text in the LLM prompt: eDNA (common lab contaminants: Homo sapiens, Bos taurus, etc.), acoustic (human vocalizations + handler noise near recording equipment), image (handler presence during camera setup/teardown). Also switches the JSON example `comment` value to match the data type. Implemented in `.build_review_prompt()` via `switch(data_type, ...)`.

**Session 101 (2026-06-06): Unified flag vocabulary**
- Renamed `review_assignments()` output columns: `review_habitat` → `habitat_plausibility`, `review_geography` → `geographic_plausibility`, `review_scope` → `scope_plausibility`, `review_contaminant` → `contamination_risk`.
- Updated values: plausibility columns use `"likely"/"possible"/"unlikely"` (positive = plausible genuine detection); `contamination_risk` uses `"low"/"moderate"/"high"` (positive = more risk).
- Renamed `flag_contaminant()` output columns: `flag_{type}` → `{type}_risk`, `flag_{type}_score` → `{type}_score`, `flag_{type}_reason` → `{type}_reason`. Values changed: `"likely"` → `"low"`, `"possible"` → `"moderate"`, `"unlikely"` → `"high"` (direction flipped — old "likely" meant real detection; new "low" risk means real detection; both mean same thing).
- Updated Flag Column Convention in CLAUDE.md; updated workflows, tests, and prompts throughout.

**Session 104 (2026-06-08): add_posthoc_assessment() + NA-rank bug fix**
- `add_posthoc_assessment()` added: single categorical column `posthoc_assessment` combining tier × likelihood into 7 categories (`sensible`, `limited_evidence`, `unexpected`, `suspect`, `unprecedented`, `vague_rank`, `modeled`). Replaces rejected `flag_prior_mismatch()` design.
- Bug fix: `vague_rank` mask was `!is.na(rank) & rank != finest_rank`; NA rank fell through to active path, getting treated as tier2 → "suspect". Fixed to `is.na(rank) | rank != finest_rank` so NA-rank rows correctly receive "vague_rank".
- `flag_prior_mismatch.R` and associated man/tests deleted.
- PtConceptionWorkflow_12S.R and _18S.R updated to use `add_posthoc_assessment()`.

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/flag_detections_workflow.R` added — the FINAL package in the tutorial
  chain (TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign → TaxaFlag). Unlike the four
  upstream scripts, both live steps run on 100% real continuity data with no synthetic
  bootstrapping: `review_assignments()` reviews TaxaAssign's real `taxaassign_consensus`
  (irreducible candidate sets via `plausible_taxa_col`), and `add_posthoc_assessment()` uses
  the real `taxaexpect_priors` directly as `tiers` (it only needs `taxon_name` + `model_tier`,
  both already present). `flag_contaminant()` is documented with its full signature and
  algorithm but not run live — it needs lab read-count data (sample × taxon, with blanks) that
  a GBIF-occurrence-based tutorial chain has no honest way to fabricate.
- Live-tested with a real Anthropic LLM call as part of a full 5-package chain (0 errors,
  sensible output — see `ecosystem_docs/LAYER1_WORKFLOWS.md`). One real bug fixed:
  `review_assignments(irreducible_only = TRUE)` hard-errors if zero rows qualify as
  irreducible, which is the *expected* outcome (not bad luck) for TaxaAssign's small
  synthetic species pool — fixed with an adaptive fallback to `irreducible_only = FALSE`.
- Also surfaced (and documented in `TaxaID/CLAUDE.md`'s Known R Footguns): `review_assignments()`
  shares the same `.resolve_llm_fn()` default-degrades-silently issue as TaxaAssign's LLM
  pathway — must pass `llm_fn` explicitly under this ecosystem's fully-namespaced calling style.
