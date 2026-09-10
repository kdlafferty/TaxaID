# CLAUDE.md -- TaxaWizard (formerly TaxaWorkflow)
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-09-09, later (Sonnet 5 -- graph updates from TaxaExpect's archival of
# the remaining 8 members of the GLMM grid/prior-fitting chain (`build_priors()`,
# `optimize_grid_size()`, `prepare_model_dataframe()`, `add_pca_covariates()`/
# `apply_pca_transform()`, `compute_moran_basis()`, `screen_spatial_formula()`,
# `train_biodiversity_model()`, `generate_full_priors()`, plus `plot_theta_map_
# interactive()` as a 9th item) -- see TaxaExpect/CLAUDE.md's own 2026-09-09-later top
# note for the full archival record; this note covers only this package's own side.
#
# Three edges/snippets DELETED outright (not rewritten): `std_to_dist`, `dist_to_priors`,
# `taxa_to_priors_wrapper` -- all three were 100% composed of calls into the now-archived
# chain, and unlike the earlier `train_biodiversity_model_by_group()` retirement (which had
# a direct one-call kernel-path replacement to rewrite the snippet onto), there is no
# kernel-path equivalent for "grid the occurrences" or "one wrapper call, taxa in, priors
# out" -- the kernel path never grids at all, and no kernel-path wrapper was ever built to
# replace `build_priors()`'s single-call convenience. This orphaned the `distributions`
# intermediate node (its only other edge, `dist_to_priors_by_group`, is itself kernel-path
# and doesn't consume a gridded object -- see below), so it was removed from `workflow_
# graph.json` too.
#
# REAL, PRE-EXISTING BUG found and fixed while investigating whether `distributions` was
# genuinely orphaned: `dist_to_priors_by_group`'s own `from: ["distributions"]` was stale,
# left over from its 2026-09-09-earlier rewrite (see the entry directly below) to call
# `estimate_kernel_priors(sampling_group_col=)` -- that rewrite changed the snippet's
# CODE to work directly on `std_occurrences` (exactly like its sibling `std_to_priors_
# kernel`, no grid ever built or consumed) but never updated the edge's own `from` field to
# match, leaving the graph topology claiming a dependency the snippet's real content
# doesn't have. Fixed the same session (`from` -> `["std_occurrences"]`), closing a real
# graph-correctness gap the earlier session introduced, not just cleanup incidental to this
# one.
#
# `priors_to_map` simplified to save-only: its old interactive-map step called the now-
# archived `plot_theta_map_interactive()`. Cannot simply be repointed at `plot_theta_
# surface()` instead -- that function needs the full `kernel_fit` object (not just the
# flattened priors table this generic, priors-only edge has access to), which is exactly
# why `plot_theta_surface()` was ALREADY wired inline inside `std_to_priors_kernel.R`/
# `dist_to_priors_by_group.R` rather than here, back when it was first added (2026-09-07).
# `metadata/TaxaExpect.json` lost its `build_priors`/`optimize_grid_size`/`prepare_model_
# dataframe` entries entirely; every remaining entry's description corrected to stop
# describing the archived functions in the present tense (they're gone, not "replaced" by
# something competing with them). `metadata/TaxaAssign.json`/`TaxaFetch.json` and
# `prompts/phase_parameterize.md`'s parameter-type teaching example (previously walked the
# LLM through `build_priors(taxa=...)` specifically) updated -- the teaching point about
# rank-encoded data.frame columns now uses `get_keys_from_context()` (the real, still-live
# `taxa -> occurrences` step) as its example instead.
#
# `tests/testthat/test-graph.R`: two real fixes, not tolerance widening. The `taxa ->
# priors (wrapper and manual)` test's whole premise (a wrapper path must exist) is now
# false -- rewritten to `taxa -> priors (manual, multi-hop)`, asserting the real remaining
# path (`taxa -> occurrences -> std_occurrences -> priors` via `taxa_to_occ` -> `occ_to_
# std` -> `std_to_priors_kernel`/`dist_to_priors_by_group`) exists and that NO path uses a
# wrapper. The "multi-input edges produce full Bayesian path" test's `has_priors` check
# dropped the two now-deleted edge IDs, keeping only the two real kernel-path ones.
# `devtools::test()` 908 -> 633 is the SAME documented, non-regressive effect this file's
# own history already records twice for the identical reason (2026-08-09: 855 -> 655) --
# fewer real edges means fewer enumerable combinatorial paths, and several tests iterate
# one assertion per computed path; confirmed `FAIL 0` before and after the edit, not just a
# smaller number. `devtools::check()` 0 errors / 0 warnings / 1 note (the standing "future
# file timestamps" environmental note, unchanged). Reinstalled (its `inst/` files --
# snippets/metadata/graph JSON -- are bundled at install time, not just read from source).
#
# Previous update, 2026-09-09 (Sonnet 5 -- `dist_to_priors_by_group` edge (distributions ->
# priors, grouped by sampling/detection process) rewritten, following TaxaExpect's
# retirement of `train_biodiversity_model_by_group()` (zero real callers ecosystem-wide,
# archived to `TaxaExpect/archive_glmm_by_group/` -- see `TaxaExpect/CLAUDE.md`'s own
# 2026-09-09 top note for the full record). The old snippet called the now-archived
# function directly -- would have hard-errored on generation. New pattern: a single
# `TaxaExpect::estimate_kernel_priors(sampling_group_col=)` call handles every sampling
# group at once (composition AND Good-Turing budget computed within each group, no
# per-group model-fitting loop needed, unlike the retired GLMM wrapper), followed by
# `generate_undetected_diversity()` for the unseen-taxa floor -- mirrors the
# `std_to_priors_kernel.R` snippet's own house style (already built from the real
# production kernel-priors path). Domestic/food priors deliberately still computed from a
# separate POOLED `estimate_kernel_priors()` call, not the grouped one -- a domestic/food
# species isn't scoped to one detection process, matching the real
# `PtConceptionWorkflow_18S_2_single_site.R` convention. `functions`/`description`/
# `time_estimate` on the edge itself updated in `workflow_graph.json` (topology --
# `id`/`from`/`to`/`snippet` filename -- left unchanged, matching this project's own
# in-place-update precedent for a rewritten-not-relocated edge). `metadata/TaxaExpect.json`'s
# now-stale `train_biodiversity_model_by_group` entry removed; `prepare_model_dataframe`'s
# output description and `generate_domestic_food_priors`'s `model_obj` input description
# both repointed away from it; `estimate_kernel_priors`'s own metadata entry gained a
# `sampling_group_col` parameter it had been missing since that parameter shipped
# 2026-09-03 (found opportunistically while touching this file, not part of the original
# ask -- a real, separate metadata gap the new snippet's own usage would otherwise have
# perpetuated). `tests/testthat/test-graph.R`'s only reference to this edge checks edge-ID
# membership in a computed path, not snippet content, so needed no change (confirmed via
# grep, not assumed). `devtools::test()` 908/908 unchanged, `devtools::check()` clean,
# reinstalled (its `inst/` files -- snippets/metadata/graph JSON -- are bundled at install
# time, not just read from the source tree the way `devtools::test()`'s own `load_all()`
# does).
# Previous update, 2026-09-08 (Sonnet 5 -- `matrix_to_clean` edge (reference_matrix ->
# clean_refs) rewritten, following TaxaLikely's retirement of `flag_reference_errors()`/
# `remove_flagged_references()` (see TaxaLikely/CLAUDE.md's own top note for the full
# ecosystem-level record). The old snippet called both retired functions -- would have
# hard-errored on generation. New pattern: `TaxaMatch::corroborate_references_locally()`
# (free local check) -> `TaxaMatch::evaluate_reference_accessions(local_corroboration=,
# skip_locally_corroborated=TRUE)` (BLAST only what the free check can't resolve; its own
# output already carries a `reference_action` verdict via an automatic internal
# `score_reference_labels()` call, so no separate call is needed) -> filter `reference_df`
# to exclude accessions actioned `"remove"`. Edge's `from` widened to `[reference_matrix,
# reference_df]` (both now genuinely needed) and `packages` changed TaxaLikely -> TaxaMatch.
# `metadata/TaxaLikely.json`'s stale `flag_reference_errors`/`remove_flagged_references`
# entries removed; `train_likelihood_model`/`build_site_reference`/`read_crabs_output`
# descriptions updated to stop citing them. `metadata/TaxaMatch.json`'s
# `evaluate_reference_accessions` entry (already present from an earlier metadata pass)
# gained the `barcode_term`/`local_corroboration`/`skip_locally_corroborated` inputs and
# `reference_action` output it was missing -- needed by this new snippet, previously
# undocumented since nothing had called for them yet. `clean_refs` remains a genuine
# terminal graph node (nothing downstream consumes it -- confirmed pre-existing, not
# something this change introduced) -- a real, standalone deliverable ("give me a cleaned
# reference database"), not wired back into `matrix_to_model`. `devtools::test()`/`check()`
# re-verified clean. `TaxaWizard:::.compute_paths()` confirms real reachability post-edit:
# `reference_df -> clean_refs` (1 path) and `taxa -> clean_refs` (3 paths) both resolve --
# `reference_matrix -> clean_refs` alone correctly finds 0, since the edge's widened `from`
# now genuinely needs BOTH inputs and `reference_df` isn't derivable starting only from
# `reference_matrix` (it's the coarser, earlier object `reference_matrix` is built from).
# Previous update, 2026-09-07, later (Sonnet 5 -- closes out the metadata resync's item 3:
# new graph node/edge design for the 3 wholly-missing mechanisms flagged in
# ecosystem_docs/REENTRY_PROMPT_taxawizard_metadata_resync.md.
#
# (1) Kernel-based prior estimator (TaxaExpect::calibrate_kernel_bandwidth()/
# estimate_kernel_priors()/generate_undetected_diversity(), 2026-08-30/31 redesign) --
# a genuinely different estimator from the GLMM/grid path (dist_to_priors.R), not an
# add-on step, per this file's own established rule for when a new alternative edge is
# warranted vs. a gated extension. New edge std_to_priors_kernel (std_occurrences ->
# priors, new snippet std_to_priors_kernel.R) -- deliberately sourced from
# std_occurrences, NOT distributions: the kernel path needs no gridding/
# create_sites_from_grid() step at all (each record is weighted by its own distance
# from the site instead of being binned into a grid cell), confirmed directly against
# estimate_kernel_priors()'s real formals (occurrence_data, not gridded distributions)
# before designing, not assumed from the function name. Snippet built from the real
# production kernel-priors path (GreatLakes2023_ConsensusWorkflow.R /
# PtConceptionWorkflow_18S_2_single_site.R), same "extract from a real battle-tested
# workflow" convention every other snippet already follows. Optional domestic/food
# priors block preserved (same as dist_to_priors.R). apply_undetected_evidence()
# (regional-proximity/invasive-watch/iNat evidence elevation) is metadata-only, no
# graph edge -- it needs a real evidence table from a caller-specific generator
# (a watch list, a search radius, etc.), no one-size default exists, matching
# dist_to_priors.R's own scope (which doesn't wire the full evidence-mixture system
# either, only the simpler domestic-priors add-on).
#
# (2) The 5 newer BLAST reference-quality-screening functions built since the
# 2026-08-09 partial wiring (which only wired evaluate_reference_accessions() +
# flag_incongruent_references()). Investigated each one's real scope before deciding
# where it belongs, rather than uniformly extending one edge: corroborate_references_
# locally()/match_driving_accessions() need seq_matrix/reference_df, which don't exist
# until AFTER the DECIPHER alignment step (refs_to_matrix.R) -- later in the pipeline
# than seq_to_match.R's own scope -- so both are metadata-only (documented, available
# to wire in directly for a caller past that point in the pipeline) rather than forced
# into a scope that doesn't have the objects they need. review_flagged_accessions()/
# resolve_review_overrides() DO fit seq_to_match.R's existing gated screening block
# (they only need evaluate_reference_accessions()'s own output, already computed
# there) -- added as a nested optional sub-step, with an explicit further-gated
# remove_incongruent_references() call for the harder opt-in (never silently escalates
# from "flag" to "remove"). verify_removal_candidates() is metadata-only, matching the
# established investigate_flagged_accession(s)()/check_marker_mismatch() precedent for
# on-demand human-audit tools (not a mechanical pipeline step). score_reference_labels()
# is NOT given its own entry at all -- it's already called automatically inside
# evaluate_reference_accessions() itself, so no caller ever invokes it directly.
# Found and fixed a real, separate metadata gap while here: remove_incongruent_
# references()'s existing entry (added well before this session) was missing
# override_accessions/gate entirely -- both real, optional formals that predate this
# session's own work, just never caught by the audit script (which only flags a
# MISSING metadata entry for a REQUIRED real param, never an optional one).
#
# (3) plot_theta_surface() (2026-09-01) -- checked directly rather than assumed to
# fit the established "interactive gadget, no graph representation" precedent
# (review_spatial_flags()/review_institution_flags()/review_spatial_context()): its
# real default is interactive=FALSE, a genuine static, scriptable plot, not a Shiny
# gadget with no non-interactive path at all -- so it does NOT fit that precedent and
# gets a real metadata entry. Wired as an optional step inside std_to_priors_kernel.R
# itself (not the generic priors_to_map.R edge) since it needs the kernel_fit object
# directly, not just the flattened priors table -- an object that only exists inside
# the kernel path's own scope.
#
# One pre-existing test needed updating (test-graph.R's "multi-input edges produce
# full Bayesian path", exactly the same class of update the 2026-07-24 session already
# made once for dist_to_priors_by_group): its has_priors check enumerated a fixed list
# of recognized priors-building edges, and some Bayesian paths now legitimately use the
# new kernel edge instead of the two it already knew about.
#
# Verified via TaxaWizard:::.compute_paths(): std_occurrences -> priors now returns 3
# paths (the 2 existing GLMM routes + the new direct kernel edge, confirmed reachable
# as its own single-edge path, not buried inside a longer chain).
# devtools::test() 908/908 (up from 735), devtools::check() 0/0/0, reinstalled.
#
# Previous update, 2026-09-07 (Sonnet 5 -- metadata resync, per
# ecosystem_docs/REENTRY_PROMPT_taxawizard_metadata_resync.md (written 2026-09-05,
# deliberately deferred until both its own stated blockers -- the live 18S PtConception
# run settling, and the critical fix-review pass -- resolved). Re-ran the existing
# structural auditor (diagnostics/taxawizard_metadata_audit.R) against freshly
# reinstalled packages: 44 findings, down to 30 after fixing every genuine one. Same
# triage discipline as the 2026-08-09 audit this builds on (documented below) --
# confirmed several apparent "findings" are actually the auditor's own display bug
# (a JSON array default gets correctly parsed and matches the real vector exactly, but
# the auditor's sprintf() call silently vectorizes over it, printing one spurious line
# per array element -- convert_taxonomy_backbone's rank_system and
# compute_group_priors's rank_cols were both already fully correct, just displayed this
# way) and confirmed several more are the deliberate match.arg()-style single-value
# representation (train_biodiversity_model_by_group's response,
# evaluate_reference_accessions's method, add_posthoc_assessment's
# domestic_prior_source -- metadata correctly shows the practical resolved default, a
# real vector default would only ever mean "pick one of these", not "use all of these").
#
# 13 genuine fixes: 2 real param-NAME drift (TaxaFetch::dedupe_occurrences data ->
# occurrence_data; TaxaMatch::read_sequence_table data -> input_data -- both real
# renames, but positional in every real snippet call so neither was actually broken,
# Tier 2 severity); TaxaFetch::check_geographic_outliers's year_range and
# TaxaTools::call_anthropic_api's model both had stale hardcoded literals where the real
# function now resolves the value dynamically at call time (year range to the current
# year; model via the model registry) -- both updated to null with a description
# explaining the dynamic resolution; 9 stale VALUE drifts across TaxaHabitat (taxon_col
# species->taxon_name), TaxaExpect (optimize_grid_size's species_col same fix;
# build_priors's rank_system was missing 4 coarser ranks entirely, search_radius_deg was
# actively wrong -- metadata said 5, real default is 2, meaning the interview was
# silently overriding the true default with a different value rather than describing
# it), TaxaLikely (read_crabs_output's dereplicate was the OPPOSITE boolean;
# flag_reference_errors/train_likelihood_model's mislabel_threshold was off by 150x --
# 3 vs the real 0.02, evidently stale from before this parameter's scale was reworked;
# evaluate_likelihoods's n_sims 100 vs the real default 0), and TaxaAssign
# (posterior_consensus's cumulative_threshold/min_posterior both drifted from their
# real 0.9/0.05 defaults). standardize_match_data's `data` REQUIRED_MISMATCH finding
# (real formal now has a NULL default enabling an interactive file.choose() fallback)
# deliberately left as `required: true` in metadata -- same judgment call the 2026-08-09
# audit already made and documented below: NULL would hang/error in a non-interactive
# wizard-generated script, so treating it as required is the operationally correct
# choice for this package's use case even though it diverges from bare R semantics.
#
# Verified via `TaxaWizard:::.compute_paths()`: sequences -> consensus 32 paths,
# distributions -> prior_map 2 paths, birdnet_detections -> consensus 32 paths -- all
# match the 2026-08-09 note's own documented counts exactly, confirming no topology
# regression. `devtools::test()` 735/735, `devtools::check()` 0/0/0, reinstalled.
#
# NOT done this pass: the reentry doc's own item 3, the three wholly-missing mechanisms
# (kernel-based prior estimator; the 5 newer BLAST reference-quality-screening functions
# built since the 2026-08-09 partial wiring; plot_theta_surface()) -- these need new
# graph node/edge DESIGN, not a metadata sync, and are a genuinely separate, larger task
# from what this session's pass covered. See the reentry doc's own updated status.
#
# Previous update, 2026-08-11 (Sonnet 5 -- TaxaWizard's first human-authored code review
# (Micah Wright, replacing the prior Claude-authored inst/taxawizard_review.Rmd entirely --
# see inst/taxawizard_review_response.md and this file's Function Inventory below for the
# full record). The review's own reported test crash ("Error in if (fn_name ==
# \"data.frame\") ... condition has length > 1") traced to a real, previously-undiscovered
# bug class in R/shiny.R's generic-script parser: as.character(expr[[1L]]) returns a
# length-3 vector for ANY namespaced pkg::fn() call (not a scalar), so `fn == "x"`-style
# checks throw the moment a real script -- i.e. nearly any script in this ecosystem, which
# writes package::function() throughout by convention -- is parsed. Fixed via a new shared
# .call_fn_name() scalar-unwrapping helper, applied at FOUR separate call sites
# (.is_library_call/.is_source_call/.is_literal_value, matching the review's own report,
# plus .is_simple_assignment and .last_assignment_var, found only by writing a reproducing
# regression test and then grepping for the same pattern once the first fix revealed there
# was more than one instance). Also fixed: .extract_libraries() never matched require(),
# only library(); a genuine empty-input-handling inconsistency in shiny.R (one y/n prompt
# defaulted Enter to "cancel", a different one to "proceed" -- unified via new
# .confirm_yes()); workflow_chat()/workflow_gadget() removed entirely (not just deprecated
# -- package has never been released, zero real callers confirmed via monorepo grep,
# reviewer's own explicit suggestion); create.R's quit-check narrowed to the literal word
# "quit" (was also "exit"/"q", risking an accidental early exit on a short reply); a
# genuinely dead feature found investigating the review's context.R question -- saved
# workflow_context.json defaults were loaded and offered to the user ("Use previous session
# defaults?") but never actually reached the LLM prompt anywhere, since
# .format_context_for_prompt()'s only caller was the legacy monolithic prompt builder the
# Session 69 graph-engine redesign superseded -- fixed by wiring it into
# .build_phase_prompt()'s classify branch for a session's first turn; a real cross-session-
# append risk in .find_existing_script() (two unrelated workflow_create() calls in one
# output_dir on the same day would silently merge into one script) -- fixed with a
# known_script_path parameter making same-session continuation deterministic and a new
# cross_session_append flag the console/viewer loops now warn on; DESCRIPTION now declares
# Depends: R (>= 4.1.0) explicitly (silences the R CMD build auto-detected-dependency
# warning the review quoted); workflow_app() gained a genuinely runnable @examples block
# (no LLM call/interactive session needed to convert an already-marked script) --
# workflow_create()/workflow_fix()/workflow_engine()/annotate_script() remain \dontrun{}
# for functions that inherently need one or the other. workflow_create() gained an explicit
# LLM-cost @details section plus a session-start console/viewer message, per the review's
# domain-review comment about accidental API spend. `devtools::test()` 721/721 (0 failures,
# up from 696), `devtools::check()` 0/0/0, reinstalled and verified at
# ~/Library/R/4.0/library. See inst/taxawizard_review_response.md for the complete
# file-by-file record, including several items investigated and confirmed intentional
# rather than fixed (TaxaTools duplication in api.R/zzz.R, tempdir() session-scoping in
# cli.R, the USGS release-governance question) -- with reasoning recorded for each.
# Previous update, 2026-08-09, continued yet again (Sonnet 5 -- TaxaWizard's first full code +
# domain review against inst/Code and Domain Review 2.Rmd, findings + fixes recorded in new
# inst/taxawizard_review.Rmd (matches TaxaFetch/TaxaLikely/TaxaMatch/TaxaFlag's own
# combined-review convention -- every other package already had one; this was the last gap).
# Real fixes: (1) SECURITY -- .param_assembly_line()'s function_ref branch in every
# workflow_app()-generated app.R called eval(parse(text = input$param_llm_fn)) with no
# server-side validation; the selectInput() widget constrains the UI, but Shiny's
# client/server protocol lets a browser client set arbitrary input$ values via
# Shiny.setInputValue() regardless of widget choices, and workflow_app()'s own docs
# describe generated apps as meant to be "shared with collaborators" -- a real, if narrow,
# RCE vector in any deployed app. Fixed with a new shared .llm_provider_choices() (used by
# both the widget builder and a new server-side allow-list check emitted before every
# eval(parse(...)) call), verified by a new test that a tampered input value is rejected
# before eval() runs. (2) .save_session() (R/cli.R) persists api_key/llm_fn (often a
# closure capturing a provider key) to a plaintext RDS in tempdir() for workflow_fix() to
# resume later -- now chmod'd 0600 immediately after saveRDS() so the secret is
# owner-readable only. (3) .generate_app() was a hardcoded non-functional placeholder
# ("Full implementation forthcoming") even though a complete app generator
# (workflow_app()/.build_app_code()) already existed in the same package -- any interview
# response with "app" in dag$outputs (a value the legacy system_prompt.md schema still
# documents as valid, though the live phase_parameterize.md prompt steers the LLM toward
# a separate workflow_app() follow-up call instead) would have silently produced a broken
# stub. Now delegates to workflow_app(script_path=, launch=FALSE) when a sibling script
# exists in the same response. (4) workflow_engine()/.call_llm()'s model default
# ("claude-opus-4-6") didn't match workflow_create()/workflow_chat()/workflow_gadget()'s
# ("claude-sonnet-4-6") -- this file's own "Key Design Decisions" section documents Sonnet
# as the intended engine default; a caller using workflow_engine() directly (the natural
# entry point for scripting) silently got the wrong one. Aligned both to sonnet. (5) `df`
# (shadows stats::df()) renamed to `input_df` in .subset_for_trial() (R/trial.R,
# internal-only) -- the last function in the ecosystem still carrying this exact pattern.
# (6) lifecycle::badge("deprecated") is used in R/cli.R's and R/gadget.R's roxygen
# (confirmed live-evaluated at devtools::document() time by inspecting the built .Rd
# files' expanded badge markup) but `lifecycle` was declared nowhere in DESCRIPTION --
# added to Suggests. (7) Two dead sub() calls immediately shadowed by an identical gsub()
# removed from .build_phase_prompt()'s path_select branch (R/graph.R). (8) Three orphaned,
# unreferenced *.rds prior tables (~120KB, real TaxaExpect-style output from an unrelated
# manual test session, confirmed via a full-package grep) and a stray tests/.DS_Store
# removed from inst/ -- a package with no data dependencies of its own shouldn't ship
# unrelated species-specific fixtures in every install. Test coverage: added
# tests/testthat/test-output.R (.generate_script()/.append_to_script()/.generate_markdown()/
# .generate_outputs() -- the actual script-generation logic behind this package's core
# deliverable, previously entirely untested) plus two .parse_engine_response() tests for
# the previously-uncovered "Approach 3" brace-matching JSON-recovery fallback and three new
# tests in test-shiny.R for the eval() allow-list fix. Also new inst/
# taxawizard_reviewer_demo.R -- a runnable companion script demonstrating every exported
# function (workflow_create/workflow_engine/workflow_fix/workflow_app/annotate_script/the
# two deprecated wrappers) against a real Azure OpenAI (DOI) backend via an explicit llm_fn
# closure, plus an offline-only section (graph path computation, response parsing) needing
# no API key at all. `devtools::test()` 696/696 (0 failures, up from 655),
# `devtools::check()` 0 errors/0 warnings/0 notes (unchanged, was already clean),
# reinstalled and verified at ~/Library/R/4.0/library. See inst/taxawizard_review.Rmd for
# the full write-up, including several items checked and found NOT to be problems (the
# Shiny chat gadget's HTML escaping, path-handling quote-escaping, .call_llm()'s
# TaxaTools-optional design).
# Previous update, 2026-08-09, continued (Sonnet 5 -- closes out the three "wholly missing
# capability" gaps the same-day metadata-drift audit left open, at the user's explicit request
# ("let's add those open issues"). Two were real graph-worthy DAG additions; one turned out to
# be a documentation-only decision once actually investigated, not a gap at all.
#
# (1) BLAST-based reference-quality screening (TaxaMatch::evaluate_reference_accessions()/
# flag_incongruent_references(), 2026-08-07/08's recommended pre-training screen). Considered
# and REJECTED a self-loop design (match_df + accession_evaluation -> match_df, as its own new
# node/edge) after checking `.compute_paths()`'s actual backward-search implementation
# (R/graph.R): its cycle-prevention (`visited_targets`) unconditionally blocks a node from
# being re-derived while already being derived, so a `match_df -> match_df` edge would NEVER
# appear in any computed path -- the exact same permanently-unreachable failure mode as the
# dead acoustic/image edges removed earlier the same day. Wired instead as an optional gated
# step INSIDE the existing `seq_to_match.R` snippet (the sequences -> match_df edge, the only
# one BLAST-derived accessions are relevant to -- not acoustic/image match_df, which have no
# GenBank accession at all), exactly matching this codebase's own established precedent for
# this situation (`generate_domestic_food_priors()`'s addition to `dist_to_priors.R`,
# `flag_institution_candidates()`'s addition to `occ_to_std.R`, both 2026-07-24: "existing
# edges extended in place, no topology change"). Gated on a new `{{screen_reference_accessions}}`
# boolean; `flag_incongruent_references()` (annotate, not remove) used as the wired default,
# matching the ecosystem's own explicit recommendation -- `remove_incongruent_references()`
# metadata'd but not snippet-wired, matching that same recommendation's "deliberate opt-in,
# not default" framing. `investigate_flagged_accession(s)()`/`check_marker_mismatch()` are
# genuinely investigative single-accession follow-up tools (a human decides which flagged
# accessions to dig into) rather than mechanical pipeline steps -- metadata'd only, matching
# the existing `calibrate_coverage_filter()`/`coverage_threshold()` precedent for diagnostic
# helpers with no graph edge. Also fixed a real, separate, stale value found while touching
# this exact file: `seq_to_match.R` hardcoded `blast_sequences(score_range = 2)`, the OLD
# default the 2026-08-08 breaking-change table's own evidence shows silently drops a query's
# true species from BLAST output 57% of the time when a confusable congener scores higher --
# updated to the current default (`8`).
#
# (2) `TaxaAssign::compute_group_priors()` + `posterior_consensus(group_priors=)` (2026-07-30,
# the fix for the real Mugu 504/616 false-positive regression). Same "extend the existing edge
# in place" pattern -- added as an optional gated step inside `post_to_consensus.R` (the
# `posteriors -> consensus` edge), computing `group_priors` once and threading it into both of
# that snippet's existing `posterior_consensus()` calls (the initial pass and the empirical-
# Bayes-refined final pass). Gated on `{{include_group_priors}}`, needs
# `{{taxaexpect_priors_var}}` + `{{taxonomy_map_var}}` (e.g. `occurrences_clean`) as directly-
# supplied placeholders, mirroring `lik_prior_to_post.R`'s existing `{{lat}}`/`{{lon}}`/
# `{{main_habitat}}` convention rather than inventing a new cross-edge variable-threading
# mechanism. Verified directly against real formals (`compute_group_priors()`'s 5 formals,
# `posterior_consensus()` does have `group_priors`) and a live smoke test with realistic
# priors/taxonomy_map fixtures before trusting the wiring.
#
# (3) `TaxaFlag::review_spatial_context()` (2026-08-06/07) -- checked directly rather than
# assumed: it's a `miniUI`/`leaflet` Shiny GADGET (opens a live interactive browser session),
# not a script-callable function. Confirmed via the graph's own existing precedent that this
# whole CLASS of function has zero graph AND zero metadata representation anywhere already --
# `TaxaHabitat::review_spatial_flags()`/`review_institution_flags()` (both real, both used in
# production, both genuinely Shiny gadgets) have never had a graph edge or metadata entry
# either, while `TaxaFlag::review_assignments()` (an LLM-driven, non-interactive, plain
# script-callable review function -- confirmed via its own real formals, no Shiny anywhere)
# IS graph-wired (`consensus_to_reviewed`). This is a real, consistent, working distinction
# already baked into the design (interactive gadgets don't fit a generated-script DAG; batch
# review functions do) -- not a gap that was missed, just never written down as a decision
# anywhere. Documenting it here so a future audit doesn't re-flag it as one: `workflow_app()`
# (TaxaWizard's own script-to-Shiny-app converter, R/shiny.R) is the intended path from a
# TaxaWizard-generated script to something with review-gadget-style interactivity, not a graph
# edge to a specific gadget function.
#
# Verified: `TaxaWizard:::.compute_paths()` re-run post-edit -- `sequences -> consensus` still
# 32 paths (edge count unchanged, since both additions were snippet-internal, not new
# topology), `distributions -> prior_map` still 2 paths. `devtools::test()` 655/655 unchanged
# (no test asserts on gated-optional-step snippet content), `devtools::check()` 0/0/0.
# Previous update, 2026-08-09 (Sonnet 5 -- metadata-drift audit + Tier-1 fix pass, prompted by the
# user asking for a full sensitivity/staleness assessment (how sensitive is the engine to
# function details, when was metadata last synced, what's emerged since, what's the update
# strategy). Verdict: metadata/*.json's last full sync was 2026-07-24; four of eight files
# (TaxaAssign/TaxaExpect/TaxaFetch/TaxaMatch) hadn't been touched since. Built a reusable
# structural auditor (formals()-vs-metadata diff against the real installed packages, not
# just grep) -- TaxaID/diagnostics/taxawizard_metadata_audit.R, run standalone
# (`Rscript diagnostics/taxawizard_metadata_audit.R` from the TaxaID root) any time a package
# signature changes, to catch this class of drift going forward without a full manual re-audit
# -- surfacing 95 findings, ~70 after noise filtering (mostly `5L` vs `5` default-literal
# formatting, flagged separately as DEFAULT_MISMATCH and not treated as real drift). Fixed the "Tier 1" subset (graph-wired,
# confirmed broken, would fail or silently misbehave on first real generated-script run):
# (1) The single worst finding -- `taxa_to_acoustic_matrix`/`image_refs_to_matrix` edges (plus
# their `acoustic_matrix_to_model`/`image_matrix_to_model` consumers) called
# TaxaLikely::fetch_reference_recordings()/build_acoustic_reference()/build_image_reference(),
# none of which have existed since **Session 99 (2026-06-02)** -- confirmed via `git log -S`
# that the ecosystem's own ecosystem-level `2820c07` commit deliberately removed them in favor
# of the no-score pathway (`unreferenced_candidates()` + `assign_scores(score_type=)`), and the
# real replacement edges (`birdnet_to_match`, `image_to_match`) already existed correctly in
# the graph the whole time. This drift had been live for over two months, not weeks. Deleted
# the 4 dead edges + 2 orphaned nodes (`acoustic_matrix`/`image_matrix`) + 2 dead snippet files;
# 28 nodes/38 edges -> 26 nodes/34 edges. (2) `TaxaTools::create_taxon_names()` called with
# `df = {{var}}` (real formal: `input_df`) in FIVE separate snippets
# (match_to_consensus_llm/bayes/score.R, model_match_to_lik.R, match_to_taxa.R) -- every one
# would have errored "unused argument" on first real use; all fixed. (3)
# `TaxaMatch::read_animl_output()`/`read_inaturalist_cv_output()`/`read_birdnet_output()`
# called with `data = ` (real formal: `files`) in `image_to_match.R`/`birdnet_to_match.R` --
# confirms [[project_taxawizard_metadata_drift]]'s pre-existing memory finding was STILL live
# 17 days after being flagged; fixed both snippets + metadata (also corrected read_animl_
# output's stale FilePath/PredictedValue/Confidence defaults to the real FileName/prediction/
# confidence). (4) `dist_to_priors_by_group.R` called `TaxaTools::change_backbone(df,
# target_backbone_id=)` -- that function is a different, unrelated relabeling helper requiring
# pre-existing matched_name/classification_path columns; the real target was always
# `TaxaMatch::convert_taxonomy_backbone()` (the function documented extensively throughout
# TaxaID/CLAUDE.md's NCBI-backbone-adoption history), which had NO metadata entry anywhere in
# TaxaWizard despite being production-critical -- fixed the snippet and added a full, correct
# metadata entry; removed the wrong `change_backbone` entry from TaxaTools.json entirely (it
# was never a real fit for what any snippet needed). (5) `get_keys_from_context()`'s metadata
# invented `taxon_names`/`backbone_id` params that don't exist -- real signature is a single
# `hierarchy_df` (full-taxonomy-context lookup, not a name+backbone pair); the two calling
# snippets (`taxa_to_occ.R`/`taxa_to_occ_checked.R`) were already calling it correctly
# (positional), only the metadata was wrong -- fixed metadata only. (6)
# `TaxaLikely::flag_reference_errors()`'s metadata `rank_system` param isn't real; its new
# `singleton_match_threshold` (added the day before this audit, 2026-08-08) was completely
# absent -- fixed. (7) `filter_top_hypotheses()`'s metadata said `likelihoods_df`, real formal
# is `likelihood_df` (singular) -- fixed (snippet call was positional, so only metadata broke).
# Verified via `TaxaWizard:::.compute_paths()` directly (not just JSON validity) that real
# multi-step paths still resolve post-edit: `sequences -> consensus` 32 paths,
# `birdnet_detections -> consensus` 32 paths, `image_classifier_output -> consensus` 32 paths,
# `distributions -> prior_map` 2 paths. `devtools::test()` 655/655 (down from the 2026-07-24
# note's 855 -- expected, matching combinatorial-growth logic in reverse: fewer real edges,
# fewer enumerable paths, not a regression), `devtools::check()` 0/0/0.
# Same-day follow-up (Tier 2): fixed the remaining metadata-only entries too (no snippet calls
# these directly, so no script-breaking risk, but each would have produced a wrong/incomplete
# interview or a garbage error-fix suggestion). `TaxaFlag::add_posthoc_assessment()` was the
# worst of these -- metadata still described the pre-2026-07-30 signature entirely (`tiers`/
# `taxon_col`/`tier_col`/`finest_rank`, none of which exist post-redesign; the real required
# `expected_theta_threshold` was absent) -- fully rewritten against the real 15-param Axis-1/
# Axis-2 signature and roxygen. Also fixed: `make_bbox_wkt()` (lon_min/lon_max/lat_min/lat_max
# -> lat/lon/radius_deg), `search_literature()` (taxon_names/geographic_terms -> taxon_scope/
# geo_scope/bbox/... the real 9-param OpenAlex signature), `write_reference_fasta()`
# (fasta_path -> file), `calibrate_coverage_filter()`/`coverage_threshold()` (raw_df ->
# ref_pairs, descriptions' build_acoustic_reference() references removed), `generate_report()`
# (`result` flipped required=false -> true, matching the real no-default formal),
# `find_taxonomy_conflicts()` (df -> input_df), `read_reference_fasta()` (`rank_system` flipped
# optional -> required) and `build_sequence_matrix()` (`rank_system` flipped required ->
# optional, matching its real `NULL` default). A second pass over the audit's own output
# (re-run after the Tier-1 fixes, to catch what changed) surfaced 3 more structural findings
# not in the original Tier-1/Tier-2 scoping message -- fixed rather than left as a known gap
# since the tooling was already loaded: `TaxaHabitat::build_habitat_prompt()`/
# `parse_hierarchical_habitat_response()` (both had entirely invented param names --
# `taxon_names`/`response`/`habitat_prompt` -- vs. the real `taxon_list`/`raw_text`/
# `habitat_scheme` etc.) and `TaxaLikely::audit_acoustic_coverage()` (`taxa`/
# `classifier_species` -> the real `plausible_species`/`reference_species`). Left
# deliberately unfixed: `TaxaMatch::standardize_match_data()`'s `data` param is flagged
# `REQUIRED_MISMATCH` (real formal has a `NULL` default, so mechanically "optional") but
# `data = NULL` opens `file.choose()` interactively or errors non-interactively -- for
# TaxaWizard's always-non-interactive generated-script context, `required: true` is the
# correct design choice even though it diverges from bare R semantics, so left as-is rather
# than "fixed" into something worse.
#
# Verified via `TaxaTools::create_taxon_names(input_df=)` against the real bundled
# `TaxaID_test_BLAST.rds` fixture (6 unique taxa resolved, no error) and
# `TaxaMatch::read_animl_output()`/`read_inaturalist_cv_output()`/`read_birdnet_output()`
# called with `files=` against small synthetic fixtures matching each real reader's expected
# format (all three accepted the argument with no "unused argument" error -- one had 0 rows
# from an intentionally-imperfect JSON fixture, not a fix problem).
# `TaxaMatch::convert_taxonomy_backbone()`'s own existing test suite (`devtools::test(filter=
# "convert_taxonomy_backbone")`) confirmed passing, ruling out any regression from the new
# metadata entry describing it. Final audit re-run: 95 -> 44 -> 35 findings, ALL remaining
# ones DEFAULT_MISMATCH noise (`5L` vs `5` literal-formatting, or a `match.arg()`-style vector
# default represented as its first element) except the one deliberate `standardize_match_data`
# case above. `devtools::test()` 655/655 (down from 2026-07-24's 855 -- expected, fewer real
# edges means fewer enumerable paths, not a regression), `devtools::check()` 0/0/0.
#
# Wholly missing capabilities (no graph representation at all, not drift since nothing
# claims to cover them) still open, unchanged from the 2026-07-24 note plus everything the
# ecosystem has shipped since: the entire BLAST-based reference-quality screening toolchain
# (TaxaMatch::evaluate_reference_accessions()/flag_incongruent_references()/
# investigate_flagged_accession(s)()/check_marker_mismatch(), 2026-08-07/08, now the
# recommended pre-training screen per the same day's ecosystem audit),
# TaxaAssign::compute_group_priors()/posterior_consensus(group_priors=) (2026-07-30, the fix
# for the real Mugu 504/616 false-positive regression), TaxaFlag::review_spatial_context()
# (2026-08-06/07, plausibly deliberate given add_posthoc_assessment()'s precedent, but never
# recorded as such the way that one was).
# Previous update, 2026-07-24, continued (Sonnet 5 -- graph EXPANSION, direct follow-up to the
# metadata-drift sync pass below: the user asked for the 5 flagged-but-not-fixed capabilities
# to actually be wired into workflow_graph.json as new nodes/edges, not just documented as a
# gap. New node: site_table (per-observation spatial_group_id table). New edges:
# match_to_site_table (match_df -> site_table, build_site_table()+group_observations_by_bbox());
# taxa_to_occ_checked (taxa -> occurrences alternative with check_geographic_outliers());
# dist_to_priors_by_group (distributions -> priors alternative, train_biodiversity_model_by_group()
# for sampling_group_col-style detection-PROCESS grouping -- deliberately renamed from an
# initial "dist_to_priors_multisite" draft after realizing mid-implementation that
# sampling_group_col (detection-method grouping, e.g. fish vs birds vs phytoplankton) and
# site_table's spatial_group_id (physical-site grouping) are two INDEPENDENT axes, not the
# same mechanism -- conflating them would have produced a working-looking but conceptually
# wrong edge); lik_prior_to_post_multisite (likelihoods+priors+site_table -> posteriors,
# join_priors()'s multi-site data-frame `site` path + combine_multisite_priors() +
# compute_posterior() -- the specific combine_multisite_priors() wiring the user named
# directly). Existing edges extended in place (snippet + functions list, no topology change):
# dist_to_priors and dist_to_priors_by_group both gain an optional generate_domestic_food_priors()
# step (domestic/commensal-animal + food-species priors, gated by a boolean placeholder);
# occ_to_std gains a flag_institution_candidates() classification step (gated on
# institution_flag being present -- silently skipped otherwise); taxa_to_priors_wrapper and
# match_to_consensus_bayes both gain a description caveat that neither wrapper covers
# domestic-food-priors / multi-site combination (build_priors()/run_bayesian_pipeline() were
# checked directly and confirmed NOT to call generate_domestic_food_priors()/
# combine_multisite_priors() internally). A real, substantial pre-existing metadata-drift bug
# was found and fixed along the way (not part of the plan, found while writing correct docs
# for the new multi-site join_priors() call): metadata/TaxaAssign.json's join_priors entry
# still described a completely different, non-existent signature
# (likelihoods_df/priors_df/grid_id/main_habitat as flat top-level required args) -- the real
# function takes likelihoods/taxaexpect_priors/site (site being a list OR a multi-site data
# frame, with grid_id/main_habitat living INSIDE it) -- rewritten to match reality. New
# metadata entries added: TaxaMatch.json (build_site_table, group_observations_by_bbox,
# assign_spatial_group, join_event_site_metadata), TaxaExpect.json (prepare_model_dataframe,
# train_biodiversity_model_by_group, generate_domestic_food_priors -- prepare_model_dataframe
# had NO entry at all before this session despite being called in the pre-existing
# dist_to_priors edge, a separate pre-existing gap left as-is beyond adding this one),
# TaxaAssign.json (combine_multisite_priors), TaxaFetch.json (check_geographic_outliers),
# TaxaHabitat.json (flag_institution_candidates). Live path-computation smoke test confirmed
# every new node/edge is actually reachable (e.g. `sequences -> posteriors` now yields 30
# paths, up from 6, spanning both the single-site and multi-site lik_prior_to_post variants
# and both priors-building strategies) -- not just JSON-valid but graph-reachable. One
# pre-existing test (test-graph.R's "multi-input edges produce full Bayesian path") needed a
# one-line update to recognize dist_to_priors_by_group as a valid priors source alongside the
# two it already knew about -- a legitimate consequence of a genuinely new alternative path,
# not a design flaw. devtools::test() 0 failures (855, up from 367 -- the jump is expected
# combinatorial growth in path-enumeration tests, not new test files), devtools::check()
# 0 errors/0 warnings/0 notes. Also corrected the Workflow Graph section's long-stale
# "20 nodes / 22 edges" claim (dated to Session 69's original build, never updated through
# many later additions) to the current true count (28 nodes / 38 edges / 34 snippets).
# Previous update, 2026-07-24 (Sonnet 5 -- metadata-drift assessment + sync pass, prompted by the
# user asking how well TaxaWizard understands the many recent ecosystem changes. Cross-checked
# workflow_graph.json/snippets/inst/metadata/*.json against every package's real current
# exports (NAMESPACE) and the ecosystem CLAUDE.md's Recent Breaking Changes table. Found and
# fixed: (1) BROKEN -- workflow_graph.json's reference_df node + taxa_to_refs edge, and
# metadata/TaxaLikely.json, still named the fully-removed fetch_reference_sequences()
# (deleted 2026-07-19, see TaxaID/CLAUDE.md) instead of fetch_ncbi_reference_sequences();
# taxa_to_refs.R's own snippet CODE was already correct (called the right function), so
# generated scripts using this path were fine -- only the graph/metadata registry was stale.
# (2) BROKEN, silent-wrong-answer risk -- consensus_to_flagged.R's snippet and
# metadata/TaxaFlag.json's flag_contaminant()/flag_handler() entries still assumed the
# pre-2026-07-24 {contaminant_type}_risk/_score/_reason and handler_risk/_score/_reason column
# names; TaxaFlag::flag_contaminant()/flag_handler() were renamed to a fixed
# observation_validity/validity_flag/validity_reason schema THE SAME DAY (see TaxaFlag/
# CLAUDE.md's top session note) -- contaminant_type now only changes the qualifier embedded in
# validity_flag's VALUE, not any column name. A script generated from the old snippet would
# have silently reported "0 high-risk contaminants" always (paste0(contaminant_type, "_risk")
# resolves to a column that no longer exists, so the sum() over it is always 0) rather than
# erroring -- fixed the snippet to read validity_flag directly. add_posthoc_assessment()'s
# metadata entry was also substantially behind (missing domestic_taxa/domestic_prior_source,
# absolute_fit_pvalue_col/weak_evidence_pvalue -> unsupported_rank, own_rank_confusion_risk_col/
# high_confusion_risk_threshold -> confusion_risk_flag, all added across the 2026-07-19 through
# 2026-07-23 sessions) -- updated to the current signature. (3) Real correctness gap, not
# breaking -- TaxaFetch::stack_occurrences() stopped deduplicating entirely on 2026-07-23
# (dedupe_occurrences() split out); taxa_to_occ.R's snippet (the one live caller of
# filter_gbif_quality() in this package) had no dedup step at all even before that split.
# TaxaFetch's own CLAUDE.md now says explicitly "call dedupe_occurrences() even for a single
# GBIF source" -- added that call to the snippet + the taxa_to_occ edge's function list + a new
# metadata/TaxaFetch.json entry for dedupe_occurrences(). Also refreshed metadata/TaxaFetch.json's
# filter_gbif_quality()/stack_occurrences() entries, both badly stale (wrong max_coord_uncertainty
# default, no mention of removed_records attr, flag_institution, or any CoordinateCleaner checks).
# NOT done this session, flagged as open follow-up work instead of attempted blind: several real
# functions/capabilities added since roughly Session 134-140 have NO graph representation at
# all -- TaxaAssign::combine_multisite_priors() (required after join_priors() for the multi-site
# "site" data-frame path, added Session 138, still entirely missing from the graph), the
# site-table/spatial-grouping toolchain (TaxaMatch::build_site_table()/group_observations_by_bbox()/
# join_event_site_metadata()/assign_spatial_group()), TaxaFetch::check_geographic_outliers(),
# TaxaFetch::fetch_inat_occurrences() + TaxaExpect::generate_domestic_food_priors() (the whole
# domestic/food-species-priors path, added 2026-07-23), and TaxaHabitat::flag_institution_candidates().
# These aren't drift (nothing in the graph claims to cover them) -- they're capabilities the
# conversational workflow builder simply can't route to yet, which needs new graph nodes/edges (a
# design decision, not a sync fix) -- scoped but not attempted this session. The *_support ->
# *_confusion_risk rename (2026-07-23) and the new winner_*_confusion_risk/winner_absolute_fit_pvalue
# pass-through output columns (TaxaAssign::posterior_consensus()) were checked and found to have
# NEVER been referenced anywhere in TaxaWizard's metadata (correctly -- optional/additive output
# columns, not required inputs), so there was nothing to rename; skipped adding them as a
# low-value completeness pass. devtools::test() 0 failures (367/367, unchanged -- no test asserts
# on these specific snippet/metadata contents), devtools::check() run to confirm no regressions.
# Previous update, 2026-07-23, continued (Sonnet 5 -- metadata/TaxaAssign.json's score_consensus
# entry updated for TaxaAssign::score_consensus(rank_thresholds=)'s new required-arg behavior
# (no default, errors if omitted -- see TaxaAssign/CLAUDE.md's matching note): the
# rank_thresholds input flipped "required": false/"default": "c(species=98,...)" ->
# "required": true, description rewritten to point at either supplying real thresholds or
# deriving marker-specific ones via the new TaxaLikely::compute_rank_thresholds(), or passing
# NULL explicitly to disable rank capping. inst/graph/snippets/match_to_consensus_score.R
# needed no change -- it already always forwards a templated {{rank_thresholds}} value the
# Phase 3 parameterize step fills in, so making the metadata entry required simply means the
# interview always asks for it now rather than silently accepting an omission. Validated
# inst/metadata/TaxaAssign.json still parses (jsonlite::fromJSON) after the edit.
# devtools::test() 0 failures (70), devtools::check() 0/0/0.
# Previous update, 2026-07-23 (Sonnet 5 -- repointed from TaxaMatch's removed
# read_wildlife_insights_output() to the new read_speciesnet_output() (see
# TaxaMatch/CLAUDE.md's 2026-07-23 note): workflow_graph.json's two "wildlife_insights"
# function-list entries (image_to_match, image_refs_to_matrix edges) -> "speciesnet";
# both edges' snippet files (image_to_match.R, image_refs_to_matrix.R) gained a
# "speciesnet" switch branch calling TaxaMatch::read_speciesnet_output() in place of
# the removed "wildlife_insights" branch; metadata/TaxaMatch.json's function entry
# replaced wholesale with read_speciesnet_output()'s real signature;
# metadata/TaxaLikely.json's build_image_reference() input description updated; and
# prompts/phase_classify.md's input-type guidance re-worded. Found, but deliberately
# NOT fixed (out of scope, flagged for the existing metadata-drift audit item instead):
# every read_*() entry in metadata/TaxaMatch.json lists its first input as `"name":
# "data"`, but the real functions (read_animl_output()/read_birdnet_output()/
# read_inaturalist_cv_output()) all take `files` as their first argument -- `data`
# isn't even a valid formal, so a script generated from these snippets' pre-existing
# "animl"/"inaturalist_cv" branches would error with "unused argument" if run. The
# new "speciesnet" branch added this session correctly uses `files =` (matching
# read_speciesnet_output()'s real signature); the three pre-existing branches were
# left as-is. See [[project_taxawizard_metadata_drift]] in the memory system.
# devtools::test() 367/367 unaffected. Previous update, 2026-06-08 (Session 104 —
# TaxaFlag metadata updated: add_posthoc_assessment added; stale column names fixed)

---

## Package Purpose

Conversational workflow designer for the TaxaID ecosystem. Interviews the user
about their data, goals, and parameters via an LLM-powered chat interface, then
generates a self-contained .R script, .md methods text, or Shiny application.

Sits outside the TaxaID dependency chain -- depends on all TaxaID packages
(via metadata), but no TaxaID package depends on it.

**Status: Graph-based engine implemented. 0 errors, 0 warnings, 0 notes on devtools::check().
Metadata JSONs fully audited. First full code + domain review complete (2026-08-09, see
inst/taxawizard_review.Rmd); first human-authored review response complete (2026-08-11, see
inst/taxawizard_review_response.md). 721 tests passing.**

---

## Architecture

### Graph-Based Three-Phase Engine (Session 69)

The engine eliminates LLM hallucination of function names, parameter names, and
variable threading by encoding the valid workflow graph as structured data and
reducing the LLM's role to three constrained tasks.

**Phase 1 -- Classify** (~3.8K token prompt):
LLM sees only node descriptions. Identifies `input_type` and `output_type` from
user's description. No function details exposed.

**Phase 2 -- Path Select** (~6.5K token prompt):
R computes all valid paths via `.compute_paths()` (backward recursive search
with multi-input edge support). LLM sees numbered path options with step labels
and time estimates. Recommends a path and confirms with user.

**Phase 3 -- Parameterize** (~5.9K token prompt):
R loads pre-validated code snippets for the selected path. LLM sees ONLY those
snippets + their parameter docs. Fills in `{{placeholder}}` values from user
input. Cannot invent function calls or parameter names.

**Error Fix** (~3.5K token prompt):
Diagnostic-first flow. `.parse_error_context()` extracts step number and edge
from error text. Full parameter docs for the failing function injected. LLM
instructed to ask for `str()`/`names()` diagnostics before attempting fix.

Phase detection is stateless -- determined from the last assistant message's
JSON (stored as full structured response in history).

### Workflow Graph

`inst/graph/workflow_graph.json` defines (2026-08-09 count, after the metadata-drift audit
below removed the dead acoustic/image reference-matrix subgraph -- down from 2026-07-24's
28 nodes / 38 edges):
- **26 nodes**: 10 inputs, 10 intermediates, 6 outputs
- **34 edges**: each maps to specific TaxaID functions + a code snippet file
- **Wrapper edges**: `build_priors()`, `run_llm_pipeline()`, `run_bayesian_pipeline()`
  flagged with `"wrapper": true`

`inst/graph/snippets/*.R` -- 32 code snippet files with `{{placeholder}}` params
extracted from real battle-tested workflow scripts.

Path computation handles multi-input edges (e.g., `match_to_consensus_bayes`
requires `match_df + model_params + priors`) via backward recursive search with
Cartesian product combination. Results are topologically sorted.

Example: `sequences -> consensus` yields 6 paths (score-only, LLM wrapper,
full Bayesian manual, full Bayesian wrapper, stepwise Bayesian manual/wrapper).

### Stateless Engine
`workflow_engine(history, metadata) -> JSON` is the core. Phase detection from
history, phase-specific prompt assembly, LLM call, response parsing. No state
between calls.

### User Interface: `workflow_create()`
Single entry point with `mode` parameter:
- **`"auto"`** (default): browser if shiny available, else console
- **`"browser"`**: standalone browser window via `shiny::browserViewer()`
- **`"viewer"`**: RStudio Viewer pane via `shiny::paneViewer()`
- **`"console"`**: `readline()` loop in R console (no shiny dependency)

`workflow_chat()`/`workflow_gadget()` (formerly deprecated thin wrappers) were removed
entirely 2026-08-11 (code review response, zero real callers, package never released --
see this file's own top session note). Use `workflow_create(mode = "console"/"viewer")`.

### Script-to-App Conversion: `workflow_app()`
Takes any R script and converts it to a standalone Shiny `app.R` with file upload
widgets, parameter controls, progress bar, log panel, results table, and CSV/RDS
download buttons. No TaxaWizard dependency at runtime -- the app is fully standalone.

Two paths:
- **TaxaWizard scripts**: auto-detected via `# --- User Parameters ---` markers;
  parses parameter section (10 widget types) and step blocks via regex + brace counting.
- **Generic R scripts**: via `annotate_script()` -- guided annotation identifies
  parameters (top-level literal assignments) and steps (comment-separated code blocks).
  Self-guided mode (3 readline questions) or LLM-guided mode (1 confirmation).

The `annotate` parameter controls behavior: `"auto"` (default) tries TaxaWizard
parsing first, then falls back to interactive annotation. `"self"`/`"llm"` force
a specific mode. `"none"` errors on non-TaxaWizard scripts.

### Triple-Mode Output
A single interview produces one or more outputs:
- `.R` script (self-contained workflow with checkpoint/resume + debug mode)
- `.md` methods text (publication-ready)
- Shiny app (interactive dashboard via `workflow_app()`)

### Error Feedback Loop
`workflow_fix()` resumes the conversation after a script error:
1. User runs generated script, hits error
2. Calls `workflow_fix()` (no args = interactive paste mode, avoids quoting issues)
3. `.parse_error_context()` extracts step number + edge from error text + saved DAG
4. Engine uses `phase_error_fix.md` prompt with full param docs for failing function
5. Diagnostic-first: LLM asks for `str()`/`names()` before attempting speculative fix
6. In auto mode, LLM is instructed to be conservative (only fix confident errors)
7. Correction saved to `~/.taxawizard/corrections.json` for future sessions

### Generated Script Features
- **Checkpoint/resume**: each step cached as `.workflow_checkpoints/step_NN.rds`; skipped on re-run
- **Auto-error-catch**: `tryCatch()` wrapping with auto `workflow_fix()` call on failure
- **Debug mode**: `debug_mode <- TRUE` subsets to first 20 `observation_id`s (not raw rows) for fast iteration
- **Scope-safe steps**: uses `quote({...})` + `eval(envir = parent.frame())` so variables created in one step are visible to later steps

### Context Persistence
- `workflow_context.json` saved alongside generated script; next `workflow_create()` session
  uses previous parameters as defaults
- `~/.taxawizard/corrections.json` accumulates error/fix pairs (max 50); injected into
  system prompt as "KNOWN ISSUES" to prevent repeat mistakes

### Trial Mode
Generated scripts can include a trial-mode subset for performance estimation.
Metadata includes per-function `scaling` and `scaling_note` fields.

---

## Function Inventory

### Exported

| Function | Purpose | Source file |
|---|---|---|
| `workflow_create()` | Main entry point: interview + script generation (mode = auto/browser/viewer/console) | R/create.R |
| `workflow_engine()` | Stateless core: history + metadata -> JSON response | R/engine.R |
| `workflow_fix()` | Resume conversation after script error | R/cli.R |
| `workflow_app()` | Convert any R script to standalone Shiny app (auto/self/llm/none annotation) | R/shiny.R |
| `annotate_script()` | Guided annotation of generic R scripts for Shiny conversion (self/llm modes) | R/shiny.R |

### Internal helpers -- Graph engine (R/graph.R)

| Function | Purpose |
|---|---|
| `.load_graph()` | Parse workflow_graph.json; cache in namespace env |
| `.compute_paths()` | Backward recursive search for all valid paths between input/output types |
| `.describe_paths()` | Human-readable path descriptions for Phase 2 prompt |
| `.get_path_context()` | Load snippets + param docs for a selected path (Phase 3) |
| `.build_phase_prompt()` | Assemble phase-specific system prompt from template + graph context |
| `.describe_node_types()` | Format input/output node list for Phase 1 prompt |
| `.list_node_types()` | Return input/output node IDs |
| `.cartesian_plans()` | Cartesian product of sub-path plans for multi-input edges |
| `.topo_sort_edges()` | Topologically sort edge set for dependency-correct execution order |
| `.extract_param_docs()` | Pull parameter docs from metadata for path functions |
| `.build_adjacency()` | Forward adjacency list from edges |
| `.graph_cache()` / `.graph_env` | Mutable cache for loaded graph |

### Internal helpers -- Engine (R/engine.R)

| Function | Purpose |
|---|---|
| `.detect_phase()` | Determine current phase from conversation history (stateless) |
| `.last_assistant_state()` | Parse last assistant message JSON for phase fields |
| `.last_message_by_role()` | Find last user or assistant message |
| `.looks_like_error()` | Pattern-match error text to trigger error_fix phase |
| `.load_system_prompt()` | Legacy monolithic prompt builder (kept for backward compat) |

### Internal helpers -- API + metadata

| Function | Purpose | Source file |
|---|---|---|
| `.call_llm()` | httr2 wrapper for Anthropic API | R/api.R |
| `.parse_engine_response()` | Extract + validate JSON from LLM response | R/api.R |
| `%\|\|%` | Null-coalescing operator | R/api.R |
| `.load_metadata()` | Load per-package JSON from inst/metadata/ | R/metadata.R |
| `.compress_metadata()` | Convert metadata to token-efficient prompt text | R/metadata.R |

### Internal helpers -- Output + CLI

| Function | Purpose | Source file |
|---|---|---|
| `.generate_outputs()` | Dispatch to script/markdown/app generators | R/output.R |
| `.generate_script()` | DAG -> .R file (with checkpoint, error-catch, debug) | R/output.R |
| `.find_existing_script()` | Find today's script for continuation mode | R/output.R |
| `.append_to_script()` | Append new DAG steps to existing script (step renumbering, dedup) | R/output.R |
| `.generate_markdown()` | DAG -> .md file | R/output.R |
| `.generate_app()` | **Fixed 2026-08-09** (was a non-functional placeholder despite `workflow_app()` already existing in-package) -- now delegates to `workflow_app(script_path=, launch=FALSE)` when a sibling script was generated in the same response; falls back to a minimal placeholder pointing at `workflow_app()` directly only when no script exists to convert (e.g. "app" requested without "script") or `shiny` is unavailable. | R/output.R |
| `.save_session()` / `.load_session()` | Temp RDS for conversation state (workflow_fix) | R/cli.R |
| `.parse_error_context()` | Extract step number + edge ID from error text + saved DAG | R/cli.R |
| `.history_has_prior_dag()` | Detect continuation mode from conversation history | R/engine.R |
| `.save_context()` / `.load_context()` | workflow_context.json persistence | R/context.R |
| `.format_context_for_prompt()` | Inject saved context into system prompt | R/context.R |
| `.corrections_path()` | `~/.taxawizard/corrections.json` path | R/context.R |
| `.load_corrections()` / `.save_correction()` | Per-user error/fix accumulation | R/context.R |
| `.format_corrections_for_prompt()` | Inject known issues into system prompt | R/context.R |
| `.subset_for_trial()` | Subset input data for trial mode | R/trial.R |
| `.estimate_scaling()` | Predict full-run time from trial timing | R/trial.R |

---

## Metadata Schema

Per-package JSON files in `inst/metadata/`. Each file contains:

```json
{
  "package": "PackageName",
  "description": "One-line package description",
  "functions": [
    {
      "name": "function_name",
      "description": "What it does",
      "inputs": [
        {"name": "arg", "type": "type_name", "required": true, "default": "value", "description": "..."}
      ],
      "output": {"type": "type_name", "description": "..."},
      "scaling": "linear | quadratic | api_limited",
      "scaling_note": "Human-readable timing estimate"
    }
  ]
}
```

Type names create the compatibility matrix: a function that outputs `match_df`
feeds into any function that accepts `match_df` as input.

**CRITICAL**: Parameter names in metadata must exactly match actual function signatures.
A full audit was performed Session 68 against all 8 packages. If function signatures
change upstream, metadata must be updated here.

---

## Dependencies

| Package | Role | In |
|---|---|---|
| httr2 | Anthropic API calls | Imports |
| jsonlite | JSON parse/write for metadata + engine responses | Imports |
| shiny | Gadget + Shiny chat UI | Suggests |

No TaxaID packages in Imports or Suggests -- the metadata JSON files are the
interface, not runtime dependencies.

---

## Key Design Decisions

### Graph-constrained LLM (Session 69)
The LLM never invents function sequences. Valid paths are computed in R from the
workflow graph. The LLM only: (1) classifies user intent, (2) selects from
precomputed paths, (3) fills in parameter values for pre-validated code snippets.
This eliminates the root cause of hallucinated parameter names, wrong function
sequences, and variable threading errors.

### Phase-specific prompts
Each phase gets a minimal, targeted prompt (~4-7K tokens) instead of the old
monolithic prompt (~15K+ tokens with full registry). Phase 1 sees only node
descriptions. Phase 3 sees only the selected path's snippets + param docs.
Dramatically reduces the LLM's opportunity to hallucinate.

### Backward recursive path search
`.compute_paths()` uses backward search from the output node, recursively finding
all ways to produce each required input. Handles multi-input edges (e.g.,
`match_to_consensus_bayes` needing `match_df + model_params + priors`) via
Cartesian product of sub-plans. Results are deduplicated and topologically sorted.

### Full JSON in history
Assistant messages store the full structured JSON response (not just `$message`
text). This enables stateless phase detection from history alone -- no external
state object needed between calls.

### Diagnostic-first error handling
`workflow_fix()` now builds a targeted `error_fix` prompt with full parameter
docs for just the failing function. The prompt instructs the LLM to request
`str()` and `names()` diagnostics before attempting a fix. In auto mode, the
LLM is told to be conservative (only fix confident errors like wrong parameter
names).

### Compressed metadata registry (legacy, still used in error_fix)
One flat table of function signatures. Full details injected only for functions
in the selected path. Keeps token budget manageable.

### LLM model for the engine
Default: `claude-sonnet-4-6`. Configurable via `model` param. Sonnet is faster
and cheaper for the interview loop; the code comes from pre-validated snippets,
not the LLM. Opus can be specified for complex parameterization tasks.

### Wrappers first
Phase 2 recommends wrapper paths when available. Individual functions exposed
only when customization is needed. User confirms that standard defaults are
acceptable before wrapper path is selected.

### Named arguments always
System prompt requires `function(arg_name = value)` style -- never positional.
This prevents parameter ordering bugs (e.g., `site_description` landing in `date`).

### Interactive paste for workflow_fix()
Calling `workflow_fix()` with no args opens readline() prompt where users paste
error text directly. Avoids R quoting/escaping issues with error messages that
contain quotes, backslashes, etc.

---

## Session Notes

Sessions 68–80 archived in ecosystem_docs/session_notes/TaxaWizard_sessions.md.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaWizard-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.

**Session 89 (2026-05-27)**
- `phase_classify.md`: `match_df` input type description now mentions BirdNET acoustic detections and image classifier results alongside BLAST output — "multiple scored candidates per sample" is the common pattern.
- `phase_parameterize.md`: `barcode_term` bullet explicitly marked as DNA/eDNA only; new `rank_system` bullet for acoustic/image: BirdNET typically uses `c("genus","species")`; image classifiers use whatever taxonomy columns are returned.

**Session 104 (2026-06-08): TaxaFlag metadata update**
- `TaxaFlag.json` updated: `add_posthoc_assessment()` added; `flag_contaminant` column names corrected to Session 101 vocabulary (`{type}_risk`/`{type}_score`/`{type}_reason`); `event_col` default fixed from `"observation_id"` → `"event_id"`; `review_assignments` `taxa_per_call` default corrected from 30 → 15; `data_type` param added.
- No workflow graph changes: `add_posthoc_assessment()` is a post-hoc annotation step (not a pipeline transformation), so it is not added as a graph edge.
