# TaxaAssign Peer Review Response

**Review date:** 2026-08-07 (file mtime) **Package version reviewed:** TaxaAssign 0.1.0
**Response prepared by:** Claude Code (Sonnet 5), 2026-08-07, at K. D. Lafferty's request

This document responds to `inst/taxaassign_review.Rmd`, which reviews 20 files
(`adjust_inat_range_priors.R`, `assign_taxa_llm.R`, `build_context.R`,
`combine_multisite_priors.R`, `compute_posterior.R`, `consensus_refinement.R`,
`expand_unreferenced.R`, `generate_report.R`, `group_priors.R`, `join_priors.R`,
`posterior_consensus.R`, `report_assign.R`, `run_bayesian_pipeline.R`,
`run_llm_pipeline.R`, `score_consensus.R`, `site_utils.R`, `slash_taxon.R`,
`suggest_unreferenced_species.R`, `TaxaAssign-package.R`, `update_prior_from_consensus.R`)
plus general code/domain review checklist items. Every file was addressed in this pass.
`devtools::test()`: 655 expectations, 0 failures (up from 615 at the start of this
session; the increase is new regression/coverage tests, not previously-hidden failures).
`devtools::check()`: 0 errors, 0 warnings, 0 notes -- including every runnable
`@examples` block, several of which were rewritten this session specifically so
`R CMD check` actually exercises them instead of hiding behind `\dontrun{}`.
Reinstalled to `~/Library/R/4.0/library` and verified against the installed copy, not
just the source tree.

Two real bugs were found and fixed via direct empirical verification (not just
reasoning from the code) -- see "Real bugs found" below.

------------------------------------------------------------------------

## Added after the review

One new exported function since the review, `add_unreferenced_prior_mass()`
(`unreferenced_prior_mass.R`, tests in `test-unreferenced_prior_mass.R`). It gives the
generic unreferenced hypotheses (an unsequenced relative in the best candidate's genus
or family) the prior mass of the local species they stand for. That means species
recorded locally but lacking a reference sequence, added to the dark-diversity floor
`join_priors()` already assigns them. Without that mass, a posterior normalised over the
candidates cannot say that none of them is plausible at the site: an out-of-range
species with a prior of 1e-5 beats hypotheses carrying floors of 3e-6. 7 new internal
helper functions have also been added since (all in `site_utils.R`, `score_consensus.R`,
`kernel_branch.R`, and `posterior_consensus.R`).

------------------------------------------------------------------------

## Real bugs found and fixed

**`update_prior_from_consensus()` silently discarded upstream `report_params`.**
Its final `attr(out, "report_params") <- list(confirmation_quantile = ..., ...)`
*overwrote* (not merged with) whatever `report_params` the input `result` already
carried -- e.g. `assign_taxa_llm()`'s real `score_sharpness`/`unknown_lik_weight`/
`score_threshold`/`top_n`. Since `run_llm_pipeline()`'s `.run_consensus_and_report()`
*always* calls `update_prior_from_consensus()` before `generate_report()`, this meant
every real LLM-pipeline report's Methods text silently fell back to
`generate_report()`'s hardcoded defaults (e.g. "sharpness parameter = 0.1") instead of
whatever value was actually used, for every real run -- not a rare edge case. Confirmed
by constructing a `result` with `score_sharpness = 0.77` and tracing it through
`update_prior_from_consensus()`: the attribute came back missing that key entirely
before the fix, present and correct after. Fixed via `utils::modifyList()` (merge, not
overwrite); new regression test in `test-update_prior.R`.

**`.find_nearest_grid()`'s distance formula was not spherical-coordinate-correct.**
Plain Euclidean distance in `(lat, lon)` degree-space over-weights longitude
differences away from the equator (a degree of longitude is `cos(latitude)` times
shorter than a degree of latitude), so it could select the wrong "nearest" grid cell.
Confirmed with a constructed counterexample at 60N (see `test-site_utils.R`): the
naive formula and the fixed cosine-latitude-corrected (equirectangular) formula
disagree on which cell is nearer for exactly the case predicted. Fixed in
`site_utils.R`; also restructured so `.find_nearest_grid()` returns the distance it
already computed internally, so `.latlon_to_grid()` no longer recomputes the identical
calculation a second time just to decide whether to warn about a far-away match (this
closes the review's own separate "doesn't this just reproduce the effort from
`.find_nearest_grid`?" finding for the same code).

------------------------------------------------------------------------

## File-by-file responses

### `adjust_inat_range_priors.R`

**Fixed:**
- Added a runnable `@examples` block (previously none).
- `alpha / (alpha + beta)` (used twice in this file) factored into a shared
  `.beta_mean()` internal helper in `site_utils.R`.

**Considered and declined:** promoting `.beta_mean()` to a cross-package exported
utility in TaxaTools (the review's suggestion, per the general ranks/formulas
discussion below) -- TaxaAssign does not depend on TaxaExpect (which already has its
own internal `TaxaExpect:::.beta_mean()`), and the formula is a genuine one-liner used
in exactly two places in this package; the coordination cost of a new cross-package
exported utility wasn't judged worth it for this case specifically.

### `assign_taxa_llm.R`

**Fixed:**
- **Real, previously-undocumented gap:** the prompt always asks the LLM to commit to
  `range_status` ("geographic presence in this region") even when `context = NULL`
  (no region given at all) -- confirmed by tracing `.build_context_block()`/
  `.get_group_context()`, which silently produce an empty context block rather than
  refusing. Added a `cli_warn()` when `context` is `NULL`, plus a new `@details`
  "Context is optional but strongly recommended" section explaining why a
  context-less call's `range_status`/`prior_weight` should be read as weak evidence.
  Not made a hard requirement (a coarse `taxonomically_impossible` call can still be
  useful from genus/family alone with no location), matching the review's own
  observation that this needed a judgment call, not an obvious fix.
- `.merge_llm_priors()`'s defensive `prior_cols_to_drop`/`prior_df_clean` step
  (guarding against a `.x`/`.y` column collision on the `left_join`) removed --
  verified `.parse_taxa_response()`'s output schema is fixed (`taxon_name`,
  `range_status`, `habitat_fit`, `information_quality`, `prior_mean`,
  `prior_source`) and can never contain `hypothesis_type`/`taxon_name_rank` in
  either of its two return paths, so the guard was dead code. Directly answers the
  review's own question ("could this be a requirement for inputs...?") -- it already
  was, by construction; the code just didn't say so.
- `@examples` rewritten: the old block referenced `system.file("match_obj.rds",
  package = "TaxaMatch")`, which does not exist anywhere in the monorepo (confirmed
  via `find`). Replaced with a fully self-contained, runnable example using a stub
  `llm_fn` (no network call), matching the shape of this file's own test fixtures.
- The "Empirical sensitivity" `@details` block (a real parameter-sweep result)
  trimmed from ~40 lines to a ~10-line summary retaining the actionable findings --
  the review's own "consider whether this adds to the documentation for most users"
  point, applied.

**Already correct, no change needed:** none flagged as a false alarm in this file.

### `build_context.R`

**Fixed:**
- `@examples` rewritten as a fully runnable, offline example using a stub `llm_fn`
  that answers both prompt types this function sends (the habitat-weight CSV chunk
  prompt and the two-line synthesis prompt) -- previously referenced undefined
  `match_df`/`llm_fn` objects inside `\dontrun{}`.

**Already correct, no change needed:**
- The "odd warning running with misspelled `taxon_names`" the review flagged
  (`parse_hierarchical_habitat_response: 1 taxon/taxa missing from response:
  Sequoia sempivirens`) *already* names the specific missing taxon exactly as the
  review's own suggested improvement asks -- this is `TaxaHabitat::
  parse_hierarchical_habitat_response()`'s message, not this file's, and it already
  does what was asked.

**Considered and declined:**
- Moving this function to TaxaHabitat -- it exists specifically to build the
  `context` argument `assign_taxa_llm()` (TaxaAssign) needs, using TaxaHabitat's
  primitives as building blocks; this is the same convenience-wrapper pattern as
  `compute_group_priors()` and other TaxaAssign functions that call into other
  packages' lower-level tools.
- Consolidating prompt-building into one dispatch function parameterized by
  `prompt_type` (a suggestion the review raises for multiple files/packages) -- a
  legitimate cross-cutting idea, but a package-wide redesign out of scope for a
  single-file review response; each prompt has different structure/rules, and a
  dispatch function would trade a DRY win for reduced per-prompt readability.

### `combine_multisite_priors.R`

**Fixed:**
- `@examples` rewritten to be fully runnable (directly-constructed `data.frame`
  instead of undefined `likelihoods`/`site_df` objects), with the network-requiring
  full-pipeline version kept as a separate `\dontrun{}` illustration.
- Session-number reference removed from an error message
  ("`join_priors` output (TaxaAssign >= Session 138, whose...)" ->
  "`join_priors` output -- its final `distinct` call is...").

**Already correct, no change needed:** `main_habitat` (and `grid_id`) being set to
`NA` on combined multi-site rows is intentional, documented behavior (the combined row
no longer corresponds to a single site) -- confirmed against the function's own
`@return` docs, which already state this explicitly.

### `compute_posterior.R`

**Fixed:**
- `@examples` rewritten as a fully self-contained, runnable example (previously
  `\dontrun{}` referencing an undefined `likelihood_w_prior`).
- `rtruncnorm_at_zero()`'s `sigma` parameter renamed `stdev` -- `stats::sigma()` is a
  real generic (residual-SD extractor for fitted models); harmless in practice (the
  function body never calls the generic), but the collision-avoidance discipline this
  codebase already applies to `mean`/`sd` parameter names (this exact function was
  previously renamed from `mean`/`sd` for the identical reason) extends cleanly to
  `sigma` too.
- New `@details` documenting (a) why the truncated-normal *mean* necessarily differs
  from `mu` when `sigma` is large relative to `mu` -- confirmed numerically
  (`mu = 0.001, sigma = 2` gives a truncated mean of ~1.60, matching the closed-form
  truncated-normal expectation formula) -- this is the correct, intended behavior of
  switching from a clamp to true truncation, not a bug, but worth documenting since a
  future reader could easily mistake it for one (exactly what the review's own
  self-flagged uncertainty suggests happened here); (b) why a truncated Normal is used
  as an *approximation* at this interface boundary rather than sampling from
  whatever true generative distribution produced the score (this function only
  receives already-summarized `score_likelihood_mean`/`score_likelihood_sd`, not the
  underlying model or raw scores -- it cannot know whether they came from
  `TaxaLikely::train_likelihood_model()`'s logit/sqrt-mismatch-transformed Normal or
  from `assign_taxa_llm()`'s LLM-derived proxy).
- Documented why `prior_alpha`/`prior_beta` are optional rather than required
  (the review's "why not always require and sample from Beta" question) --
  `assign_taxa_llm(prior_phi = NULL)` is the one real, deliberate use of the
  fixed-prior path; every other real caller (`join_priors()`-derived TaxaExpect
  priors) always supplies both.

### `consensus_refinement.R`

**Fixed:** expanded the previously minimal header comment into a full description of
what `.run_consensus_and_report()` does, why it's shared between the two pipeline
wrappers, and what each parameter means (pointing at the two callers' own roxygen
rather than duplicating it, to avoid the two copies drifting apart). Also threaded a
new explicit `workflow` argument through (see `generate_report.R` below) so this
function's own callers no longer rely on column-presence guessing.

**Acknowledged, no change:** this function is only indirectly tested (via
`run_bayesian_pipeline()`/`run_llm_pipeline()`'s own test suites) -- matches the
existing convention in this package for internal orchestration helpers with no
independently meaningful unit-level contract; not changed.

### `expand_unreferenced.R`

**Removed entirely** (not just deprecated further), per the review's explicit
suggestion and matching this ecosystem's own established precedent for unreleased
code with zero real external dependents (`fetch_reference_sequences()`,
`audit_barcode_coverage_ncbi()`, `expand_consensus_candidates()`,
`read_wildlife_insights_output()` were all removed the same way in earlier sessions).
Confirmed via a monorepo-wide grep (including the real external eDNA workflow scripts
outside this repo) that no caller uses the *qualified* `TaxaAssign::
expand_unreferenced_hypotheses()` name -- every real caller uses the bare, unqualified
name, which will now resolve directly to `TaxaLikely::expand_unreferenced_hypotheses()`
via the normal search path (since `library(TaxaLikely)` is always loaded in those
scripts) with no behavior change, just one fewer deprecation-warning hop. Deleted the
source file, its dedicated test file, and its `NAMESPACE`/man-page entries;
cross-references in `join_priors.R`, `TaxaAssign-package.R`, and `README.md` updated
to point at `TaxaLikely::expand_unreferenced_hypotheses()` directly.

### `generate_report.R`

**Fixed:**
- New `workflow = NULL` parameter (values `"bayesian"`/`"llm"`) lets a caller override
  the auto-detected workflow used to select Methods-text wording, instead of always
  inferring it from column presence (`range_status`/`habitat_fit`/
  `information_quality` all present -> `"llm"`). Default `NULL` preserves the old
  auto-detection behavior exactly (non-breaking). `run_bayesian_pipeline()`/
  `run_llm_pipeline()` (via `.run_consensus_and_report()`) now pass this explicitly,
  since each pipeline wrapper knows definitively which workflow it is and has no
  reason to let the report-builder guess.
- `.build_citation_text()` tightened and given an explanatory comment answering the
  review's specific question ("under what circumstances would this error?") --
  confirmed `utils::citation("TaxaAssign")` does not error under normal use (tested
  under both an installed package and `devtools::load_all()`); the `tryCatch`/fallback
  is kept as a defense specifically against a future `inst/CITATION` edit introducing a
  syntax error or dropping below 2 entries, not because the current call is fragile.
- `@examples` rewritten as a fully self-contained, runnable example (`llm_fn = NULL`
  uses the template-based Results section, so no network call is needed).

### `group_priors.R`

**Fixed:**
- **Default `rank_cols` changed from `c("genus", "family")` to
  `c("species", "genus", "family")`**, with `"species"` auto-derived as `taxon_col`'s
  own identity when `taxonomy_map` has no explicit `species` column. This directly
  closes a real, already-documented production landmine:
  `posterior_consensus()`'s `group_priors` lookup is
  keyed on `(lca$rank, lca$taxon)`, and most real consensus calls resolve at species
  rank, but the old default produced zero `rank == "species"` rows -- so every
  species-level `consensus_taxon` found nothing in `group_priors`, and
  `consensus_has_occurrence_record` read `FALSE` (not `NA`) purely from this gap
  (confirmed in production: 504 of 616 real Mugu observations misread
  "unprecedented"). The fix that shipped at the time was a manual workflow-level
  shim (`taxonomy_map$species <- taxonomy_map$taxon_name`, still present verbatim in
  the real `MuguFishWorkflow.R`) rather than a package default change, on the
  reasoning that it was "trivially expressible via the existing mechanism." The
  review's own independent "should `rank_cols` have a default?" question is exactly
  the signal that this reasoning under-valued discoverability: a fresh reviewer with
  no access to the session history flagged the same landmine on sight. Purely
  additive (never removes existing genus/family rows); an explicit `"species"` column
  in `taxonomy_map`, or omitting `"species"` from `rank_cols`, both still work as
  overrides. 3 new regression tests.
- Removed a cross-package reference to `TaxaFlag/REENTRY_PROMPT_axes_wrapup.md` (an
  internal planning doc, not part of any shipped package) from exported roxygen --
  directly answers the review's "how is TaxaFlag relevant here?" confusion. The
  underlying math derivation was already stated inline in the same section, so
  nothing substantive was lost.
- Early-return branch given `{ }` braces for readability, matching the style used
  elsewhere in the same function.

### `join_priors.R`

**Fixed:**
- **Real, previously-undocumented usability gap:** `site = list(main_habitat = "...")`
  alone (no `lat`/`lon`/`grid_id`) now auto-fills coordinates from
  `attr(taxaexpect_priors, "search_center")` when present (set by
  `TaxaExpect::build_priors()`) instead of hard-erroring and forcing the caller to
  retype coordinates that are already known. `main_habitat` itself is still never
  auto-filled or guessed. Directly answers the review's "suggest requiring
  coordinates since they are known" -- the coordinates are now used automatically
  rather than required to be retyped. 2 new regression tests.
- `rank_system`/`.split_mean_cap()`/several other items -- see the shared "Rank-order
  validation" and "Repeated formula consolidation" notes below, both implemented
  in this file (and shared with `posterior_consensus.R`/`score_consensus.R`).
- `template_keep_cols` (a dead variable, computed once and never referenced again --
  confirmed via grep across the whole function body) removed. Directly confirms the
  review's suspicion.
- The `for (i in needs_fill) { donor_lookup[donor_lookup[[anchor_col]] == anchor_val, ] }`
  per-row taxonomy-propagation loop replaced with a vectorized `match()`-based lookup
  (one hash lookup per rank level instead of a linear scan per row) -- directly
  answers "could a merge be used effectively here?"; same semantics, verified against
  the existing test suite.
- The unexplained shorthand "dark floor" comment expanded to "the dark-diversity
  fallback... assigns it a floor prior downstream" -- answers "dark floor?".
- `backbone_id`'s error messages and `@param` docs, which pointed at
  `TaxaID/CLAUDE.md` (an internal development doc, not shipped with the package --
  an end user installing TaxaAssign standalone has no access to it), now point at
  `TaxaTools::verify_taxon_names()`'s own `backbone_id` docs and
  `https://verifier.globalnames.org/` directly. Directly answers "this file is not
  in this package, if it is important it should be documented within the package."
  (The same fix was applied to the identical pattern in `posterior_consensus.R`,
  `run_bayesian_pipeline.R`, and `run_llm_pipeline.R`.)
- `@examples` rewritten as a fully self-contained, runnable example.

**Verified, not a real duplication:** the review's "this is the same function as used
in TaxaExpect, could it be defined once?" comment (re: `.compute_dark_diversity_groups()`)
does not hold up on inspection -- `TaxaExpect::generate_undetected_diversity()` has no
equivalent recursive hierarchical-grouping helper (confirmed via grep: it's the only
function defined in that file); it produces flat singleton-mirror/global-floor rows,
structurally different from this file's phylum -> genus recursive descent. No shared
logic exists to consolidate.

**Considered and declined:**
- Requiring one specific `site` format instead of accepting several -- the multiple
  accepted formats mirror real, different upstream states a caller may already be in
  (already has a `grid_id` from a prior `create_sites_from_grid()` call vs. only has
  raw coordinates), matching `.resolve_site()`'s own equally-flexible design (see
  `site_utils.R` below). Note: this investigation surfaced that `join_priors()` and
  `.resolve_site()` are two **independently implemented, overlapping** site-resolution
  code paths within this same package (`join_priors()` doesn't call
  `.resolve_site()` at all, despite `.resolve_site()` existing and being used by
  `run_bayesian_pipeline()`) -- a real, confirmed duplication, flagged here rather
  than unified in this pass, since consolidating two independently-evolved public
  argument-handling paths (one of which -- `join_priors()`'s -- also has a bare-
  grid_id-string shortcut and the new search_center auto-fill above that the other
  lacks) is a higher-risk refactor than this review-response pass should take on
  unilaterally.
- `taxaexpect_priors` carrying real `lat`/`lon` columns instead of `grid_id` strings
  being re-parsed (the review's suggestion, matching a pattern TaxaExpect's own
  `compute_moran_basis(coords=)` already uses for the identical concern) -- confirmed
  real: `TaxaExpect::generate_full_priors()`'s documented output has no `lat_r`/`lon_r`
  columns, so `taxaexpect_priors` genuinely never carries real coordinates today.
  Building TaxaAssign-side support for a column that never exists in real data would
  be speculative dead code; the actual fix belongs upstream, in TaxaExpect
  (propagating `lat_r`/`lon_r` through to `generate_full_priors()`'s final output,
  mirroring that package's own `coords=` precedent) -- flagged as a future
  cross-package task, not attempted here.

### `posterior_consensus.R`

**Fixed:**
- `@examples` rewritten as a fully self-contained, runnable example.
- The "Empirical sensitivity" `@details` block trimmed (same treatment as
  `assign_taxa_llm.R` above) -- answers "consider whether this adds to the
  documentation for most users."
- 8 repeated `x <- if ("col" %in% names(winner_row)) winner_row$col[[1L]] else
  NA_real_` blocks (`winner_prior`, `winner_likelihood`, `winner_likelihood_cov`,
  `winner_theta_mean`, and the 4 `winner_*_confusion_risk` columns) consolidated into
  a new `.row_col_or()` helper -- addresses both the readability point ("if this used
  [a clearer] format...") and the "reproduced in several places" pattern, with a
  cleaner fix than reformatting each occurrence individually.
- `winner_taxon`'s equivalent `if ("taxon_name" %in% names(winner_row)) ... else NA`
  guard removed -- `taxon_name` is a *required* column (checked at this function's own
  input validation), unlike the genuinely-optional `winner_*` pass-throughs above, so
  the guard was unreachable defensive code; simplified with a comment explaining why.
- `rank_vals_all`/`in_lca` (previously bare single-line `if/else`) converted to the
  same `{ } else { }` block-brace style as the adjacent `consensus_posterior`
  assignment three lines below -- directly answers "inconsistent curly brace use...
  suggest using them in all locations."
- Added a comment at `.extract_rank_values()`'s species-derivation branch (the
  review's "are these always species, or could this be a genus-only attribute?"
  question) explaining that this trusts `taxon_name_rank == "species"` to mean
  `taxon_name` really is a full binomial, that this contract is enforced *upstream*
  (`TaxaMatch::convert_taxonomy_backbone()`'s "Inu Inu" fix), and that re-validating it
  at every downstream rank-derivation site would be extensive and duplicative rather
  than fixing the actual source.

**Also fixed:** the `rank_system`/rank-order validation and `backbone_id` doc-location
fixes shared with `join_priors.R` above (see those two shared sections).

### `report_assign.R`

**Fixed:**
- New `workflow = NULL` parameter, mirroring `generate_report()`'s identical fix
  above -- directly answers "suggest requiring workflow be specified instead of
  guessing based on column names."
- Removed a stray Session-number reference and normalized inconsistent header
  spacing (the "weird spaces" comment).
- `@examples` rewritten as a fully self-contained, runnable example.

**Considered and declined:** moving this function to TaxaTools -- it constructs a
`TaxaTools::new_report_section()` object specific to *this package's own*
`posterior_consensus()`/`score_consensus()` output shapes, matching the same
per-package `report_*()` -> `TaxaTools::assemble_report()` pattern used elsewhere in
this ecosystem (e.g. TaxaExpect's own `report_priors()`).

### `run_bayesian_pipeline.R` / `run_llm_pipeline.R`

**Fixed:**
- `@examples` given an explanatory comment (kept inside `\dontrun{}`, since both
  pipelines genuinely require real upstream objects -- a fitted TaxaLikely model, real
  TaxaExpect priors, and/or real LLM calls -- that cannot be honestly synthesized
  inline) pointing at `vignette("taxonomic-assignment", package = "TaxaAssign")` for a
  complete runnable version, and (for `run_llm_pipeline()`) at
  `assign_taxa_llm()`'s own now-fully-offline `@examples` for a demonstration of the
  underlying LLM-prior mechanism without needing a real API key.
- `backbone_id`'s error messages' `TaxaID/CLAUDE.md` reference fixed (see the shared
  note under `join_priors.R`).
- Threaded the new `workflow` argument through to `generate_report()` (see
  `consensus_refinement.R` above).

**Considered and declined:** making TaxaTools a hard `Imports` dependency instead of
`Suggests` (`run_llm_pipeline()`'s own comment: "doesn't all the LLM stuff require
TaxaTools?") -- `run_bayesian_pipeline()` and every purely score-based function in this
package (`score_consensus()`, etc.) work with no LLM/TaxaTools involvement at all, and
every LLM-touching function already gives a clear, actionable error/warning
(`.resolve_llm_fn()`, strengthened this session -- see `site_utils.R` below) when
TaxaTools is absent, rather than crashing at install time for users who don't need it.
This is the same soft-dependency architecture TaxaAssign already uses consistently
(e.g. `build_context()`'s `requireNamespace("TaxaHabitat")` guard).

**Acknowledged, not changed:** "this seems bigger than this package somehow -
dependent on all or many of the others" -- accurate, and by design: this is the
high-level orchestrating wrapper this package's own docs describe as combining
TaxaLikely likelihoods with TaxaExpect priors into one call. "Examples in tests are
all designed to fail at some point so couldn't test all functionality" -- not
investigated further in this pass; flagged for a future session if deeper test-design
review is wanted.

### `score_consensus.R`

**Fixed:**
- Step 1 (min-score filter) and Step 2 (gap filter) previously reassigned `chunk`
  between steps and re-read `scores` from the already-filtered object; rewritten to
  combine both steps into one logical mask (`keep1`, then `keep2 <- keep1 & ...`) and
  subset `chunk` exactly once, at the end -- directly answers "why reassign to
  `chunk`? ... keep working with the same vector."
- `unique_taxa <- !duplicated(chunk$taxon_name); taxa_unique <- chunk[unique_taxa, ]`
  inlined to `taxa_unique <- chunk[!duplicated(chunk$taxon_name), ]` (used exactly
  once) -- directly answers "this object doesn't need to be named."
- `.cap_rank_by_threshold()`'s `for (rk in threshold_ranks) { if (top_score >=
  threshold) { ...; break } }` loop vectorized into one `which(meets_threshold)[1L]`
  call -- directly answers "could this be a vectorized filter?"
- `@examples` rewritten as a fully self-contained, runnable example.
- Rank-order validation (see shared note below).

**Considered and declined:** requiring `score_col` to be on a single, specified 0-1 or
0-100 scale instead of auto-detecting and rescaling `rank_thresholds` -- this function
already deliberately follows the exact same `if (max(x) > 1) treat-as-percent`
convention used identically in three other places in this ecosystem
(`TaxaLikely::.normalize_scores()`, `assign_scores()`,
`restore_suppressed_candidates()$delta`). Requiring an explicit scale here alone would
create a new inconsistency with the rest of the ecosystem rather than fix a real one;
the shared risk profile (a percent-identity score with an unusually low max could in
principle misfire the same way in all four places) is a pre-existing, already-accepted
tradeoff, not something unique to this function.

### `site_utils.R`

**Fixed:**
- **`.find_nearest_grid()`'s spherical-distance bug** -- see "Real bugs found" above.
- **`.resolve_llm_fn()`'s silent-degradation footgun made loud.** This is the exact,
  previously-documented (`TaxaID/CLAUDE.md`'s "Known R Footguns") issue the review
  independently rediscovered by hands-on testing ("`TaxaTools::call_api` usually
  results in an error, often package must be loaded"): `TaxaTools`'s provider
  auto-detection only fires via `library(TaxaTools)`, never via a bare `TaxaTools::`
  reference, so a fully-namespaced caller could previously fall through to a
  degraded/uniform LLM result with *no visible signal at all*. Added a `cli_warn()`
  at exactly the point this becomes likely (falling back to bare `TaxaTools::call_api`
  with no auto-detected provider), naming the cause and both workarounds directly.
- `.latlon_to_grid()` now gives a clear, specific error ("No prior rows with a
  non-NA `main_habitat` exist at the nearest grid cell...") when the resolved grid
  cell has zero usable prior rows, instead of falling through to a confusing
  "Available habitats at X: " message with nothing listed after the colon -- answers
  the "what happens if `grid_rows` has no values?" question with a real, verified fix
  rather than just an answer.
- New dedicated `test-site_utils.R` (32 tests) covering every internal helper in this
  file -- directly answers "not sure any of these functions are directly tested" /
  "example data not available so I didn't run directly." Includes a constructed
  counterexample specifically demonstrating the spherical-distance fix.

**Verified, not a real issue:** the review's suspicion that `.latlon_to_grid()` wastes
effort on grid-parsing before checking `main_habitat` for `NULL` -- traced directly:
the nearest-grid computation is *needed* to build the informative error message (which
grid was resolved, what habitats are available there), so this work is not wasted even
in the NULL-`main_habitat` case; it's what makes that error actionable instead of
generic.

**Considered and declined:** unifying `.resolve_site()` with `join_priors()`'s own,
separately-implemented site-resolution logic -- see the "Considered and declined" note
under `join_priors.R` above; this is real, confirmed duplication, flagged but not
resolved in this pass given the risk of unifying two independently-evolved public
argument-handling paths.

### `slash_taxon.R`

**Fixed:**
- **Real robustness gap, closed defensively:** `posterior_consensus()`'s
  `plausible_posteriors` list-column is a *named* vector (keyed by taxon name, not
  just positionally aligned with `plausible_taxa`) -- confirmed by reading its
  construction (`stats::setNames(plausible[[posterior_col]], plausible$taxon_name)`).
  `add_slash_taxon()` was discarding that self-describing structure and indexing
  `raw_posts[[i]]` *positionally* instead, meaning the two list-columns' order had to
  stay in sync by convention alone, exactly the risk the review's "is there any way
  the order of the list columns could get corrupted?" question raised. Switched to
  name-based lookup (`post_vec[x]`) when `post_vec` has names, falling back to the old
  positional indexing for older/hand-built input with no names -- fully backward
  compatible, and now robust to positional desync rather than merely hoping it never
  happens.
- **Real defensive gap, made visible:** added a runtime check (when TaxaTools is
  available) warning when any taxon name in `plausible_taxa` fails
  `TaxaTools::is_plausible_binomial()` -- the exact failure mode this function's own
  `@note` already documents as capable of corrupting `.make_slash_name()`'s
  space-split logic ("Thunnus aff.", "Canis sp. Russia/33500"). Previously this was
  prevention-by-documentation only; now it's also detected at the point it would
  actually cause corruption, not just documented as a risk to avoid upstream.
- `@examples` rewritten as a fully self-contained, runnable example.

**Considered and declined:** renaming `add_slash_taxon()` (the review's suggestion,
since it does more than build slash names) -- it's an already-exported, real-workflow-
referenced function name (used across multiple production `PtConceptionWorkflow_*.R`/
`MuguFishWorkflow.R` scripts per this package's own `CLAUDE.md`); renaming would be a
breaking change with real external impact for a naming preference, and the function's
scope (slash-name building *plus* `irreducible_consensus`/`consensus_OTU`/
`primary_taxon`) is genuinely broader than "a wrapper for `.make_slash_name()`" alone,
so a narrower name wouldn't actually fit better.

**Verified, not a real gap:** `.build_plausible_prompt()`'s `ex1`/`ex2` special-casing
(1 vs 2+ genera) -- this builds a static 1-2-row *illustrative format example* for the
LLM prompt, not an iteration over all genera; using more than 2 examples wouldn't add
value and would only bloat the prompt. (This finding is actually in
`suggest_unreferenced_species.R`, not `slash_taxon.R` -- see below; noted here since
it's the same code shape as this file's own list-column question.)

### `suggest_unreferenced_species.R`

**Fixed:**
- **Real defensive gap, LLM-response parsing:** `.parse_plausible_response()` took
  `as.character(item$genus)[[1L]]` unconditionally, silently keeping only the first
  value if the LLM ever returned a genus *array* instead of the expected scalar
  string -- any `plausible_species` in that malformed item would then be silently
  misattributed. Now checks `length(g_vec) != 1L`, warns naming the malformed item,
  and skips it rather than guessing which genus it belongs to. Directly answers "line
  146: probably safer to iterate instead of selecting the first element."
- **Real, separate defensive gap in the same failure class:** the family-lookup step
  (`fam[[1L]]` from `match_df$family` for a given genus) silently kept the first
  family value seen even when `match_df` genuinely disagreed (a genus mapping to more
  than one distinct family -- a real data-quality issue this would otherwise mask).
  Now uses the most frequent value and warns when there's disagreement, pointing at
  `TaxaTools::find_taxonomy_conflicts()` (a function that already exists in this
  ecosystem for exactly this class of check) for further inspection.
- `@examples` for both `suggest_unreferenced_species()` and
  `print.unreferenced_species_result()` rewritten -- the former replaced the
  nonexistent `system.file("match_obj.rds", package = "TaxaMatch")` reference
  (confirmed via `find` across the whole monorepo: this file does not exist) with a
  self-built `match_df` matching this file's own test fixture shape; the latter now
  builds a synthetic `unreferenced_species_result` object directly so it needs no LLM
  call at all.

**Verified, not a real gap:** `.build_plausible_prompt()`'s `genera[[1L]]`/`genera[[2L]]`
example-building (the review's "could this just iterate over genera, which would
allow any length?") -- this builds a static 1-2-row format *example* to illustrate the
expected JSON shape to the LLM, not a real iteration over the genus list being
processed; more than 2 illustrative rows would add prompt length without adding
information.

**Acknowledged, addressed at the shared-mechanism level:** "I had to explicitly load
TaxaTools to run" is the exact `.resolve_llm_fn()` footgun fixed in `site_utils.R`
above (this function calls `.resolve_llm_fn()` too, so it inherits that fix directly).
The real "Unreferenced species detected: 0" run against `make_spg_match_df()` the
review reported is expected, not a bug: that test fixture's stub LLM (`stub_plausible_llm`
in the test file) deliberately returns species already present in the reference set, so
zero *new* unreferenced species is the correct output for that specific input, not a
sign the function found nothing when it should have found something.

### `TaxaAssign-package.R`

**Fixed:** updated the "Unreferenced species" `@section` to point at
`TaxaLikely::expand_unreferenced_hypotheses()` directly instead of the now-removed
`expand_unreferenced_hypotheses()` deprecation-forwarding entry.

### `update_prior_from_consensus.R`

**Fixed:** the real `report_params`-overwrite bug -- see "Real bugs found" above.

------------------------------------------------------------------------

## Cross-cutting themes addressed once, shared across files

**Rank-order validation.** The review raised, in several files independently
(`join_priors.R`, `posterior_consensus.R`, `score_consensus.R`, and the general
opening comments), that every rank-aware function in this ecosystem infers
coarsest/finest rank from a user-supplied `rank_system` vector's *position*, trusting
it's already ordered coarse-to-fine with no verification -- and suggested a single,
immutable, ecosystem-wide rank-ordering mechanism (acknowledging this "might require a
custom S4 class"). A full redesign of that scope is out of bounds for a single-package
review response. Implemented instead: a new `.check_rank_system_order()` helper
(`site_utils.R`) that warns when a user-supplied `rank_system` disagrees in relative
order with `TaxaTools::standard_ranks` for any rank names the two share -- catching the
exact bug class (an accidentally reversed or misordered hand-typed vector) without
requiring a new immutable-object redesign. Wired into `join_priors()`,
`posterior_consensus()`, and `score_consensus()` (the three functions in this package
whose `rank_system` argument is consumed positionally).

**Repeated formula consolidation.** `join_priors.R`'s hierarchical dark-diversity
grouping recomputed `min(mass / n, 1 - 1e-9)` in five separate places (the review's
"line 327... reproduced in some form multiple times"); consolidated into one
`.split_mean_cap()` helper.

**Internal cross-references to files outside the shipped package.** Several error
messages and `@param` docs pointed at `TaxaID/CLAUDE.md` (an internal
development-session log, not part of any installed package) or `TaxaFlag/
REENTRY_PROMPT_axes_wrapup.md` (an internal planning doc) for information a real
end-user installing TaxaAssign standalone cannot actually reach. All such references
found via grep (`join_priors.R`, `posterior_consensus.R`, `run_bayesian_pipeline.R`,
`run_llm_pipeline.R`, `group_priors.R`) were replaced with either the actual content
inline or a pointer to `TaxaTools::verify_taxon_names()`'s own documentation and
`https://verifier.globalnames.org/`, both of which ship with (or are reachable from)
the installed package.

------------------------------------------------------------------------

## Summary

| Category | Count |
|---|---|
| Real bugs found and fixed (confirmed via direct empirical verification) | 2 (`update_prior_from_consensus()`'s `report_params` overwrite; `.find_nearest_grid()`'s non-spherical distance) |
| Real defensive/robustness gaps closed (not correctness bugs in current data, but confirmed-reachable failure modes) | 4 (`assign_taxa_llm()`'s malformed-JSON genus-array guard's sibling in `suggest_unreferenced_species.R`, the family-disagreement guard, `add_slash_taxon()`'s name-vs-position lookup, `add_slash_taxon()`'s non-binomial detection) |
| Real, previously-undocumented usability gaps closed | 2 (`join_priors()`'s coordinate auto-fill; `.resolve_llm_fn()`'s silent-degradation warning, independently rediscovering an already-known but under-visible footgun) |
| `@examples` blocks rewritten from broken/`\dontrun{}`-hidden to genuinely runnable (verified by `devtools::check()`) | 13 |
| Dead code removed | 2 (`template_keep_cols`, `expand_unreferenced.R` entire file) |
| New dedicated test files | 1 (`test-site_utils.R`, 32 tests, 0 prior coverage) |
| New regression tests elsewhere | 6 |
| Items verified and found NOT to be real issues (documented, not silently dismissed) | 5 |
| Items explicitly considered and declined, with reasoning recorded above | 9 |

All fixes verified against the full test suite and `R CMD check` (0 errors/0
warnings/0 notes, including every non-`\dontrun{}` example actually executing) after
every file, not just once at the end. Reinstalled to `~/Library/R/4.0/library` and
confirmed the installed copy reflects the final source (not just that the reinstall
command exited cleanly -- this package's own session history flagged that distinction
as having caused a real problem once before).

------------------------------------------------------------------------

## Behavior changes to already-reviewed functions

Not new functions (see "Added after the review" above for those) -- new arguments and
behavior on functions this document already covers above.

- `compute_group_priors(exclude_named_evidence = TRUE)` excludes rows carrying a named
  evidence source from the group-level plausibility denominator.
- `posterior_consensus(downrank_requires_candidate = TRUE)` refuses to narrow a
  consensus to a taxon that is not in the observation's own candidate set.
- `combine_multisite_priors()` guards against differing presence-mixture parameters
  across a group's site rows, blanking them with a warning that names the affected
  candidates rather than silently picking one.
- `assign_taxa_llm()` normalises the LLM's prior weights once per observation. It
  used to normalise each batch of `taxa_per_call` taxa by its own sum, so an
  observation whose candidates fell in different batches compared them on different
  scales, and a lone implausible taxon in a small final batch could win. A batch
  whose call fails takes the median weight of the group's other batches.
- `assign_taxa_llm()` gives each taxon in the prompt its higher lineage (the ranks
  above genus in `match_df`), so the model can tell homonyms apart. Unreferenced
  species borrow a referenced congener's lineage. The survey block reads
  "independent of this detection method" rather than "independent of DNA".
- `assign_taxa_llm()` records `n_known_absent` in its `report_params`.
- `generate_report()`'s Methods text for the LLM workflow says the LLM elicited the
  priors and that likelihoods came from an uncalibrated weighting of match scores;
  it used to say the LLM approximated both. The range categories match the prompt,
  and the known-absent sentence appears only when `known_absent` was supplied.
- `run_llm_pipeline()` passes `context_source = "llm"` to `generate_report()` when
  it built the context itself, unless `report_params` sets it.
- `build_context()` returns a `geographic_hint` column, which `assign_taxa_llm()`
  shows the model as "Location".
- `assign_taxa_llm()` accepts `range_status = "transported"` for taxa with no wild
  population that are present because people bring or keep them, with its own
  `prior_weight_guide$transported` band (default `c(0.03, 0.15)`). A guide supplied
  without the band gets the default.
- `assign_taxa_llm(cache_dir = NULL)` caches LLM prior responses, one file per call,
  keyed on the full prompt and what can be known about the model before the call.
  Incomplete answers are never cached. `run_llm_pipeline()` forwards it.
- `run_llm_pipeline(data_type)` has no default and must be stated when the function
  detects unreferenced species itself. It used to pass `"eDNA"` unconditionally.
  Detection inside the wrapper runs only for `"eDNA"`; image and acoustic data need
  `suggest_unreferenced_species()` with its `reference_species` list. The value also
  reaches `generate_report()` unless `report_params` sets it.
- `assign_taxa_llm()` gives a taxon the LLM left out of its answer the smallest prior
  among the taxa it did answer for. The unknown hypothesis's placeholder 0 used to be
  counted in that minimum, so an omitted taxon got prior 0 and was eliminated, or,
  with `prior_phi` set, `compute_posterior()` aborted the run.
- `posterior_consensus()` gains an output column `unreferenced_taxonomy_lookup`
  (`"matched"`, `"not_found"`, `"lookup_failed"`, or `NA` when nothing needed
  looking up) and an argument `taxonomy_cache_dir` passed to
  `TaxaTools::verify_taxon_names(cache_dir =)`. A failed lookup previously left
  the label blank exactly like a genuine non-match, and a re-run could label
  the same observation differently (seen on CalIntertidal 12S_ESV_178200). A
  failure now also prints a message as it happens. Requires the TaxaTools
  build carrying `verify_taxon_names(cache_dir =)`. Tests:
  test-posterior_consensus.R.
- `posterior_consensus()` passes `taxonomy_cache_dir` to
  `TaxaTools::verify_taxon_names()` only when a cache directory was actually
  supplied. Passing it unconditionally would make the call fail against a
  TaxaTools that predates the argument, and the failure would arrive as
  `lookup_failed` on every row, which reads as a service outage rather than as
  a version mismatch. A test asserts the argument is absent on the default
  path.
- `update_prior_from_consensus(detections, group_cols = "sample_id", marker_col)`
  pools confirmation evidence within groups. Species mass, the leave-one-out
  subtraction, the confirmation target and the occurrence ceiling are computed per
  group, and an observation in k groups receives the mean of its k per-group gains.
  `spatial_group_map` is read as `detections` with `group_cols = "spatial_group_id"`.
  Before this, the map only decided which observations were eligible; every
  quantity after that was study-wide, so a detection at one site raised priors at
  every other site. With `detections = NULL` the whole result is one group, and
  the call is refused when `result` carries multi-site combined priors. Tests
  cover isolation, within-group donation, cross-marker grouping, a hand-computed
  multi-group value, per-group leave-one-out and a composite key.

- `join_priors()` no longer lets `TaxaMatch::filter_redundant_hypotheses()` delete
  unreferenced hypotheses. That filter removes a coarser row when a finer row of the same
  lineage exists, so it deleted the generic unsequenced-congener row ("Sardinops",
  genus) and unsequenced-genus row ("Clupeidae", family) whenever a species candidate of
  that genus was present. Those rows compete with the candidate; they are not coarser
  labels for it. The filter still runs, with the unreferenced rows still able to
  supersede coarser specific candidates, and any unreferenced row it removed is then
  restored. Measured on the CalIntertidal 12S Government Point join: 9,132 H2 and
  9,278 H3 rows went in, and 106 and 103 came out. Round-1 posteriors carried a generic
  row for 2.0% (12S), 39.4% (18S) and 16.3% (COI) of observations. This is post-Step-7,
  so no likelihood checkpoint is invalidated. Tests: test-join_priors.R (the new test
  fails on the previous code).

- Blank rank values are treated as missing when a table enters `join_priors()`,
  `posterior_consensus()`, `score_consensus()`, `compute_group_priors()`,
  `combine_multisite_priors()` and `add_unreferenced_prior_mass()` (internal
  `.blank_ranks_to_na()`). Reference taxonomies store an absent genus or species as `""` as
  well as `NA`; every rank reader tested `is.na()`, so `""` passed as a taxon. In
  `join_priors()` the genus-to-family fill joined every `genus == ""` row to every family
  with a `""` genus at the site, multiplying generic rows. Measured in the CalIntertidal
  three-arm run: 12S 72, 18S 45 and COI 474 groups of identical rows, 100% with a blank
  genus. `posterior_consensus()` then reported a plausible set of such rows as "unanimous"
  at species with an empty taxon name (18 COI calls). Tests: test-join_priors.R,
  test-posterior_consensus.R (both fail on the previous code).
- `join_priors()` fills family from genus only for genus names that map to a single
  family. A genus name is not a key: homonyms and reassigned genera (Porella, Eisenia,
  Mastophora, Dilophus, Halopteris, Prosorhochmus) carry two families, and the join on the
  bare name gave every row of such a genus one copy per family. After the blank-rank fix,
  80 over-counted rows at CalIntertidal were all of this kind; 27 genera in the match
  objects have more than one family. Ambiguous genera are named in a message. Tests:
  test-join_priors.R (fails on the previous code).
- `combine_multisite_priors()` counts each site once. Identical repeats of one
  (observation, candidate, site) row are dropped before combining, with a message
  giving the count; repeats that disagree stop the call. Combining k copies of one site
  had divided the logit variance by k and multiplied `n_sites_combined` by k. Measured
  on the saved CalIntertidal Round 1: 527 rows in 518 observations had
  `n_sites_combined` above their true site count (18S up to 22x, COI median 90x, up to
  154x), 177 of them consensus winners. Tests: test-combine_multisite_priors.R (both fail
  on the previous code).
- `add_unreferenced_prior_mass()` returns `attr(, "unreferenced_scope_members")`, the
  species behind each added mass, so each mass can be traced to its members. That list
  found the next defect: prior tables carry rows for records identified only to genus or
  family ("Cottidae", "Icelinus") under `taxon_name_rank` "species", and they were summed
  as if they were unreferenced species. At CalIntertidal Government Point the Cottidae
  scope held 1.46e-3, 74% of it from the family row itself, against 3.8e-4 from the six
  real unreferenced cottids. Only binomials are now summed; the excluded rows are counted
  in `n_coarse_prior_rows_excluded`. Tests: test-unreferenced_prior_mass.R.

- `posterior_consensus(pool_tail = FALSE)` is a new argument; the default keeps the
  existing rule. With `pool_tail = TRUE`, the hypotheses below `min_posterior` form one
  tail block: the hypotheses above the floor are added until they hold
  `cumulative_threshold` of the TOTAL named mass, and when they fall short the whole
  block joins the plausible set and the consensus is the LCA of everything in it. Under
  the default rule a hypothesis at 0.13 beside twenty at 0.02-0.03 is the whole
  plausible set and is reported as a species. Measured on the saved CalIntertidal Round
  1: 41 of 16,849 species calls had `consensus_posterior` below 0.2. On one CalIntertidal
  subset, pooling moved species calls from 544 to 475, clearing all 17 low-posterior 18S
  calls but also 52 calls at 0.5-0.9. That is why it is opt-in. New output columns
  `tail_mass` (always reported) and `tail_pooled`. Tests: test-posterior_consensus.R
  (the tail tests use `pool_tail = TRUE`; one asserts the default is unchanged).

- A cross-package `::` call inside a test resolves to whatever build of the sibling
  package is loaded at that moment, so a test can pass against the INSTALLED sibling while
  appearing to check the source. `test-integration.R` asserted TaxaLikely's expansion rule
  through `TaxaLikely::expand_unreferenced_hypotheses()`: it passed alone (installed main
  build) and failed after TaxaLikely's own tests had loaded the source, as it would have in
  CI, which installs siblings from the checkout. The fix is structural: each rule is
  asserted only in the package that owns it, and the integration test checks the hand-off
  between the packages, which holds whichever build is loaded. Separately, every test that
  exercises a Monte Carlo path now sets its own seed (19 tests), and each package's test
  run is also seeded in `setup-seed.R`, so neither prior session state nor a new test
  added later can shift another test's random stream.

- `assign_taxa_llm()`'s prompt builder no longer lets a missing `lineage` column
  collapse a vector. `ifelse()` returns the length of its TEST, so a length-1
  `lineage` made the `ifelse()` below it length 1 regardless of how many taxa
  there were. Here that was harmless, because `sprintf()` recycles a length-1
  argument and every row correctly received `""`. It is fixed because the LENGTH
  depended on whether the column existed, which is the shape that did bite
  elsewhere in the ecosystem, where the collapsed vector was indexed per row and
  every row read `NA`.

### posterior_consensus(): likelihood-only consensus and prior_decided (added after the review)

A species call can rest on the occurrence prior rather than on the sequence: when
several candidates match equally well, the prior picks among them and the posterior
can still read ~1.0. New `likelihood_consensus = TRUE` re-runs the same consensus rule
on the likelihoods alone (uniform priors, no downranking) and adds
`likelihood_consensus_taxon`/`_rank`, `prior_role` ("agrees", "narrowed", "broadened",
"changed") and `prior_decided` (narrowed or changed). No existing column changes
(tested: identical output with the pass on or off, apart from the four new columns).
On real CalIntertidal Round 1 posteriors, prior-decided species calls: 12S 2,144 of
9,347 (22.9%), COI 1,909 of 5,835 (32.7%), 18S 568 of 1,478 (38.4%) -- many at
posterior ~1.0, e.g. Oligocottus snyderi where the sequence supports only Oligocottus.
Re-running the saved 09-27 Round 1 posteriors on current main reproduces the
saved calls at 0.995 (COI), 0.997 (12S) and 0.976 (18S): the first real-data
measure of what the fixes merged since then changed. The second pass roughly doubles consensus time (67 s for 13,735 12S observations).
Six tests.

### 2026-10-01: posterior_consensus() reports likelihood_support; the support rule was removed

`likelihood_support` is the share the sequence evidence alone gives the reported taxon
(named candidates' priors flattened, generic unsequenced-relative rows at their own
priors). A short-lived option, `min_likelihood_support`, moved any call below a support
threshold up its lineage. It was removed before release, on the maintainer's reasoning:
in a clade with one local species the prior legitimately concentrates the posterior on
that species -- whether the species is referenced but the marker cannot separate it from
non-local congeners, or unreferenced with no local competitors. A rule that moved such
calls up was suppressing a right answer, not catching a wrong one. On three-arm data it
would have removed every 18S species call (83 -> 0) for that reason. Prior-chosen calls
go wrong when the prior itself is wrong (a local relative present but unrecorded); that is
addressed through the prior for unrecorded relatives, not a reporting threshold.
`likelihood_support` remains as a column so a reader can see how much of a call rests on
the prior. The binary `prior_decided` flag was dropped: it read TRUE for nearly every
species call (83/83 on 18S) and so carried no information.

### 2026-10-01: dark diversity is a shared per-clade budget (changes numbers for every caller)

The dark-diversity prior for named candidates with no occurrence record is now a budget shared
within each clade, not a per-candidate allowance. Per clade X (phylum .. genus): f1 singletons,
D = their mean share (one missing species' share if present), K unrecorded candidates, W weight
already priced by evidence generators. The expected number of missing species is shrunk toward
the parent clade, N* = (f1 + kappa * Nhat) / (1 + kappa), kappa = 1, Nhat = the parent's N*
apportioned by the clade's share of the parent's candidates. Each candidate gets
min(1, (N* - W) / K) * D: the clade's unseen mass shared among its candidates and never more than
one species' share (so 4 missing species across 10 candidates gives 0.4 * D each). The remainder
-- missing species no candidate accounts for -- goes to the unsequenced-relative ring rows (genus
N* - K - W; a coarser clade N* minus its child clades'), so nothing is counted twice. BUG FIX:
candidates took their taxonomy from the occurrence taxonomy, where unrecorded candidates are
absent by definition, so most fell to the global floor; they now take their ranks from their own
rows. This function had no tests; it now has six.

### 2026-10-01: add_unreferenced_prior_mass(named_rows) -- opt-in, default FALSE

New argument, default FALSE (no change for existing callers). TRUE adds one row per recorded
local species without a reference, carrying the likelihood of the unsequenced-relative ring
whose scope contains it and its own occurrence prior; the ring row keeps only the unrecorded
part. The total prior per scope is the same as the default summing mode. It lets a local
unreferenced species be reported by name when the prior concentrates on it (counterfactual case
C-1: an unreferenced, locally common species with no local congeners was called at species in
88-92% of cases with named rows, 0% without). Referenced local species that were not search
hits get no row: missing the hit window is evidence of a worse match.

### 2026-10-01: posterior_consensus(robust_prior_s = 1) -- robust credible node, default ON

The maintainer's decision: on by default, `robust_prior_s = 0` turns it off, to be revisited if
an evaluation says so. Active with consensus_method = "credible_node". Because the occurrence
prior is estimated from finitely many records, a node is reported only if its posterior stays at
or above cumulative_threshold across an imprecise-Dirichlet neighbourhood of the prior:
eps = s / (N + s), N = the median alpha + beta of the observation's kernel-estimated rows, with
the worst case putting eps on the best-fitting hypothesis outside the node (Berger & Berliner
1986; Walley 1996). Calls the sequence decides are unaffected; a call resting on the prior is kept
only if it would survive s further records of a better-matching taxon. Reported as
robust_lower_posterior. Asymmetric-loss rules, prior-data conflict thresholds, prior tempering
and a higher threshold were evaluated and rejected: none separates a prior-decided error from a
legitimate one-local-species call, and the last two broke that case. Known-truth counterfactual,
corrected likelihood model, s = 1 vs off: F6 (rare species vs a close, 136x commoner congener)
wrong 12S 70 -> 35%, 18S 95 -> 71%; T3 (unrecorded species vs a common congener) wrong 11 -> 3%,
36 -> 7%; cost on the legitimate case C-1, species calls 89 -> 80%, 85 -> 78%. The margin scales
with the records behind the prior, so sparsely recorded sites coarsen most.

### 2026-10-02: credible node on per-row (rank, name) ancestry; consensus_limit

Spec from the workflow peer and package review, under the maintainer's sequencing (generic
missing-rank rule and rank ceiling first, backbone decision after). `.credible_node()` now takes
every row of the observation: each named row adds its posterior to the (rank, name) nodes its own
lineage carries, a row with no value at a rank joins no node there but stays in the
denominator, no rank is imputed, and rows with no `taxon_name` count in the denominator only
(their rank columns are not trusted as a position). Under `"credible_node"` the denominator is
now always every row; `unnamed_in_threshold` governs `"lca"` only (with its default TRUE the
result was already the same). The plain and robust rules share one implementation. Most of the
ancestry behaviour was already true of the per-rank aggregation; the new tests pin it,
including a ragged case (row A has order without class, row B class without order: neither node
borrows the other's mass). New column `consensus_limit` says why a call is coarser than the
finest rank: "backbone" (at a finer rank, rows resolved to that rank or finer but with no value
there would have let a node reach the threshold that does not reach it alone), "robust_prior"
(the plain rule would have called finer), "threshold" (mass spread across named alternatives).
A hypothesis named at a coarser rank (a ring row) lacks finer ranks by design and does not count
as a lineage gap. `rank_system` may run to phylum and kingdom when those columns exist.

### 2026-10-02: robust_prior_s takes N from the site's records, never from pseudo-counts

DEFECT FIX. `robust_prior_s` sets eps = s / (N + s) with N the occurrence prior's record
concentration. N was the median alpha + beta of the observation's kernel-estimated rows and, when
the observation had none, of ALL its rows. On current main those rows are floor and per-clade
dark-diversity priors, whose alpha + beta are pseudo-counts (dark diversity: 2 x the clade's
missing-species count), so N was a few units and eps ~ 0.05-0.3, coarsening nearly every call in
an observation whose candidates are all unrecorded locally: 3,572 of 5,616 18S and 6,608 of 13,029
COI CalIntertidal observations have no kernel-estimated candidate. (The workflow peer's
measurement used the 2026-09-27 priors, whose non-kernel rows carried large concentrations, so it
did not show this.) `join_priors()` now stamps `prior_site_records`, the site x habitat's median
kernel alpha + beta (CalIntertidal: 26 sites, median 137,000), on every row; the robust check uses
it, else the observation's kernel rows, and with neither it is not applied (plain credible node).
The test fails 3 of 4 checks on the previous code.

Also corrected: the documentation said a call must survive one more record "of a better-matching
taxon". The bound's worst case is the best-fitting taxon OUTSIDE the node, which may fit worse.
Measured on the 09-27 posteriors, of calls the rule coarsened the outside taxon fit worse in 156 of
179 (18S) and 456 of 561 (COI), and the plain share was 0.90-0.95 in 111 and 385: the rule
coarsens marginal calls whose candidates carry priors worth only a few records, where one record
moves the prior noticeably. That is the imprecise-Dirichlet model's own behaviour, not an
aggregation artefact, and it is the evaluation the maintainer asked to see before keeping the
default.

### 2026-10-02: combine_multisite_priors sums prior_site_records

Found by the workflow peer: at ESV grain a combined row inherited one site's `prior_site_records`,
so the robust check would use an arbitrary site's record count. The combined prior pools the
sites' precision (its concentration is at least the sum of theirs), so the record count behind it
is now the sum over the combined sites. The rule is derived from an invariant the function already
guarantees, `phi_combined >= sum(phi_i)`, so the robust check sees the same evidence base the
combined prior itself claims and cannot drift out of step with it as a chosen constant could. (The
test fails on the previous code, which returned the first site's 1,000 instead of 4,000.)

The join_priors test for `prior_site_records` first asserted `all(out$prior_site_records == 1000)`,
which is TRUE on old code (absent column: `all(logical(0))`), the third vacuous assertion found in
this screen. Rewritten as a presence check plus `expect_equal()` on the values, it fails on the old
code and also caught a real defect: the column carried tapply()'s `dim` attribute, now stripped.
Named case checked (18S_ESV_140800, Antithamnionella spirographidis, posterior 0.993, no call under
robust_prior_s = 1): it is NOT this defect. The best-matching reference is Gelidium sesquipedale
(likelihood 1.26x the winner's, floor prior), the winner's 0.993 comes from a ~1,800x prior, and
at San Juanico (262 records) that prior is worth ~1.5 records; one more record of Gelidium flips
it. No call (on family/genus/species) is the intended robust outcome, under the site's N and the
kernel rows' N alike.

### 2026-10-02: a placeholder rank value can never form a credible node (test only)

`posterior_consensus()` normalises placeholder rank values to `NA` on entry via
`.blank_ranks_to_na()`, which matches `^unk_<word>$`, `^incertae[ _]sedis`,
`^unclassified` and `^unknown` case-insensitively. That normaliser has its own
tests; what had no test was the CONSEQUENCE in the consensus rule, which is what
a reader actually depends on: two candidates from different phyla that share only
a placeholder class must not be pooled into a node named for the placeholder,
because that would report a non-taxon as the consensus and sum the posterior mass
of unrelated taxa. Reachable on real data -- NCBI leaves some fish orders
*incertae sedis* -- once phylum/class ranks are supplied in `rank_system`.

Added to `test-placeholder_ranks.R`: six placeholder spellings must each give
`consensus_taxon = NA` with `consensus_limit = "backbone"`, plus a CONTROL with a
real shared class (`Mammalia`) that must form that node, so the test
distinguishes "placeholder suppressed" from "no node could form here". Verified
sensitive rather than assumed: with `.is_placeholder_rank()` stubbed to return
FALSE, the file goes from 35 passing / 0 failing to 12 passing / 23 failing.

No code changed. Raised because a grep of `posterior_consensus.R` alone found no
placeholder handling and I concluded there was none -- the handling is in a helper
that file calls on its first line of work. Checking the file was a proxy for
checking the behaviour; feeding the case in and reading the output was the real
check, and it is now a test.

### 2026-10-02: rings at any rank; lineage_conflict; credible_node threshold > 0.5; rank order

Maintainer's decisions (review of the rank-ancestry work, items 1a-1c, and the ring cap):
- Ring types are recognised by one rule, `unreferenced_<rank>` at any standard rank, with the
  ring's scope one rank coarser (internal `.is_unreferenced_type()`, `.unreferenced_ring_rank()`),
  replacing four fixed lists in `add_unreferenced_prior_mass()`, `join_priors()` (twice) and
  `posterior_consensus()`. `add_unreferenced_prior_mass()`'s default `unreferenced_types` gains
  `"unreferenced_class"`. A phylum ring row now takes the recorded unreferenced species of other
  classes of its phylum (tested; fails on the previous code).
- `lineage_conflict` (new column, reported only): names the observation's own rows use with two
  different lineages. The credible node identifies a taxon by (rank, name); a homonym or a taxon
  labelled two ways would pool, and consensus cannot tell which. Measured on the 2026-09-27
  posteriors: 18S 33 observations, COI 22 (genuine homonyms such as Porella and Lunularia,
  bryozoan vs liverwort; and inconsistent labels such as Alcyonacea vs Malacalcyonacea). The fix
  belongs to the inputs (one lineage per name, or a taxon key); the workflow peer has been told.
- `consensus_method = "credible_node"` requires `cumulative_threshold > 0.5`: two disjoint nodes
  can both hold half the mass, and at 0.5 the call depended on row order (measured: the same rows
  reversed gave a different species). The default 0.9 is unaffected; `"lca"` is unchanged.
- Rank masking (a row never reports a rank finer than its own) orders ranks by the standard
  ladder with the caller's non-standard ranks inserted (internal `.rank_order()`), so a row named
  at e.g. subgenus no longer counts toward the species its anchor carries.

### 2026-10-03: consensus_limit gains "rank_not_supplied"

Maintainer's approval (relayed by the peer coordinator; scope as proposed). A rank in
`rank_system` that no row of `posterior_df` carries (the column absent, or empty throughout after
placeholder normalisation) used to stamp any call held coarse by it as "backbone", the same stamp
as a rank missing from SOME lineages (e.g. GBIF has no class for ray-finned fishes). The two now
differ: such a rank is "rank_not_supplied", decided at dataset level, with one entry `message()`
naming it; "backbone" is kept for ranks the input supplies but these rows' lineages lack. Calls
are unchanged; only the label. Motivating case: on the 2026-09-27 CalIntertidal 18S objects, which
had no usable class column, 4,203 no-calls were stamped "backbone" (benchmark session's count).
Internal to posterior_consensus(); no new export, argument or column. Test covers absent / missing
from these lineages / supplied (the absent case fails on the previous code). Package review's
placeholder test now adds a second observation carrying a real class, so its "backbone"
expectation still describes a supplied-but-missing rank; a single-observation, all-placeholder
input is now "rank_not_supplied", asserted alongside.

### 2026-10-05: update_prior_from_consensus memory (exact; no method change)

Approved under the maintainer's standing instruction for exact memory fixes (relayed by the peer
coordinator). CalIntertidal attempt 6 was killed at 19.04 GB in Section 8 inside this function: the
soft-confirmation step made whole-table copies of `result` (~4.7M posterior rows at ESV x site),
including two base `merge()` calls on full-width tables just to add `consensus_taxon_v1` /
`consensus_rank_v1`. There is no observation x species matrix. Changes:
- The support pool takes the three columns it uses (observation_id, taxon_name, posterior),
  not a full-width copy of `result`.
- The resolved / unresolved rows are built by `.merge_rows_with()`: `merge()` runs on a NARROW
  (observation_id, row index) table, whose row permutation and y columns are the same as merging
  the full rows (merge's ordering depends only on the key and the row order of x), and the
  full-width rows are taken once in merge's own layout (key column first, x's other columns in
  order, then y's columns; compact row names). It falls back to `merge()` itself for a
  non-data.frame `result` (a tibble) or a y column name `result` already has (merge would
  suffix it).
Evidence: `.merge_rows_with()` is `expect_identical` to `merge()` on shuffled rows with several
rows per observation, unmatched observations and mixed column types (character, logical with
NA, factor, Date), for full, partial and empty row sets; with NA KEYS (merge() pairs NA with NA)
and with keys repeated on BOTH sides (the cartesian block, ordered by the pairing of match indices;
the expansion is asserted) -- both raised by package review; a test asserts the narrow path is
the one taken; both fallbacks are tested. Scope of the claim: identity holds between the two paths
on one machine; merge()'s character-key order follows the locale identically in both, so this
does not address cross-machine reproducibility of merge() itself. The whole function, old (main 6c83ced) vs new, on a
synthetic 6-site fixture (400 observations, 1,603 rows, ties, 620 priors raised, a site without
theta_mean exercising the ceiling fallback, shuffled rows, n_sims = 50 under one seed):
identical() TRUE.
Real data (2026-10-06, after the CalIntertidal rerun; machine otherwise idle): CalIntertidalWorkflow's
saved Section 8 inputs (cache_lik/section8_update_inputs.rds: 4,738,140 posterior rows x 62 columns,
49,352 observations; group_cols = "Site", marker_col = "marker", n_sims = 1000). Comparison on a
WHOLE-SITE subset, because the update is group-local per Site: a random row sample would cut groups in
half and could mask a divergence or manufacture one, whereas whole Sites are a valid smaller instance
(the one cross-group quantity, the theta_mean ceiling fallback, is computed on the same subset by both
versions; no Site in the input falls back). Subset: 8 Sites (Government Point, the largest, 19,942
observations; plus the 7 smallest), 2,133,087 rows, 25,143 observations; seed 42 (set.seed before the
call, same in both). Old = main 6c83ced, new = this branch, each alone in its own process:
identical(old, new) TRUE on the full output (1,702,418 rows prior_updated).
Cost on that subset: wall 3,322 s -> 334 s; CPU (user) 449 s -> 317 s; R heap max 7.91 -> 6.78 GB;
peak footprint 7.77 -> 6.21 GB; maximum resident set 8.61 -> 8.67 GB. The old version's wall time
was ~7x its CPU time (memory pressure), so the speed gain is mostly avoided waiting, not computation.
HONEST LIMIT: the memory saving is modest (~1.1-1.6 GB at 2.1M rows), and the new version on the FULL
4.74M-row input still exceeded a 12 GB tree cap within ~100 s (aborted at 13.0 GB). Another consumer
in this function, not touched here, dominates at full scale; it needs profiling before a further
fix. This branch is exact and strictly cheaper, but it does not by itself make the full CalIntertidal
input fit; the workflow's per-Site calls remain necessary.

### 2026-10-06: update_prior_from_consensus soft confirmation uses referenced candidates only

Maintainer's decision (relayed by the peer coordinator; "referenced species with sequence support").
Rows whose `hypothesis_type` is an unreferenced-relative type (`.is_unreferenced_type()`: ring rows
and the named rows of recorded unreferenced species) are excluded on BOTH sides of the soft
confirmation: their posterior no longer counts as cross-observation support (donors), and their
priors are no longer raised (receivers). Such rows carry a ring likelihood but no sequence match of
their own, and their support at one observation comes from the same rows at the others, so the
old behaviour was circular. Diagnosed on CalIntertidal (2026-10-06): ring priors rose from the
dark-diversity floor (3.5e-6) to ~0.05 across a Site and turned honest no-calls into confident
wrong-phylum calls. Tests (both fail on main 8cc0c36; the control passes there): an
unreferenced-relative row is not raised although a donor confirms its species; an
unreferenced-relative row's posterior does not confirm a species elsewhere.
Real data, before (main 8cc0c36) vs after (this branch), on the whole-Site CalIntertidal subset used
for the upfc-memory check (2,133,087 rows, 25,143 observations, 8 Sites incl. Government Point,
seed 42, n_sims 1000): rows raised 1,552,495 -> 58,300; unreferenced-relative rows raised 1,493,171 ->
0; referenced candidates raised 59,324 -> 58,300; prior mass on unreferenced-relative rows per
observation, median 0.104 (83% of the observation's prior) -> 0.00244 (23%), p90 1.01 -> 0.083.
Example 18S_ESV_026656 (a sequence ~77% from every reference): before, a ring prior raised from
3.5e-6 to 0.0998 took posterior 0.87; after, the ring stays at the floor and the consensus is a
no-call limited by threshold.

### 2026-10-06: posterior_consensus per-observation chunks by a row-index split (exact)

Approved under the maintainer's instruction for exact memory/time fixes (relayed by the peer
coordinator). Two changes, both identical by construction:
- The main loop took each observation's rows as `posterior_df[posterior_df$observation_id == sid, ]`,
  scanning every row once per observation (O(N x observations)). The row indices are now split once
  (`split(seq_len(n), factor(observation_id, levels = observation_ids))`, original row order kept)
  and each chunk is `posterior_df[row_idx[[i]], ]`: the same rows, in the same order, with the same
  row names. NA observation ids keep the original path, where `==` selects differently.
- The likelihood-consensus pass (`.add_prior_role()`) did `split(posterior_df, observation_id)`,
  holding a full-width second copy of the table as one data frame per observation.
  `split.data.frame()` is `lapply(split(seq_len(n), f), function(i) x[i, , drop = FALSE])`, so it now
  keeps the index split and takes each chunk when used: the same objects without the copy.
Tests: interleaving observations' rows (each observation's own row order kept, interleaving
asserted) gives the same per-observation output as grouped rows; an NA observation id still runs.
Real data (CalIntertidal whole-Site subset of the saved Section 8 inputs; credible_node,
phylum..species): old (main 8cc0c36) vs new on the 7 small Sites (494,266 rows, 5,201 observations):
identical() TRUE on the full output (1,129 species calls); old 54 s / 1.43 GB tree peak, new 47 s /
1.08 GB. Full subset (2,133,087 rows, 25,143 observations, 8 Sites incl. Government Point): identical() TRUE
again (7,295 species calls). Cost, old -> new: process wall 367 -> 227 s and CPU 343 -> 219 s (a
compute gain, not avoided paging; the machine was idle); R heap max 3.10 -> 2.07 GB; maximum
resident set 3.85 -> 2.30 GB. The O(N x observations) scan grows faster than N, so the gain
should be larger at the full CalIntertidal scale (6.15M rows, 49,262 observations), where Round 2's
consensus took ~2 h at ~14 GB; that full-scale before/after was not run here.

### 2026-10-07: update_prior_from_consensus receiver guards (likelihood node, occurrence record)

Approved by the maintainer (2026-10-07, relayed by the peer coordinator: "go ahead and implement C1 + G3, and
G1"); the argument's name and its transitional status follow package review.
Problem (measured on the 2026-10-07 CalIntertidal run): Round 2 raised one referenced row's prior from the
floor by three to four orders of magnitude toward a support-weighted quantile of OTHER observations' posteriors
(scaled to the group's occurrence ceiling). Of 176 reviewed new confident species calls, 174 winners had been
raised, with Round 1 posteriors of median 0.03-0.15; 131 had no occurrence record. The support came largely
from sibling sequence variants of one organism matching a reference at a mediocre identity. Once item b
stopped the circular ring boosts, the raised referenced row stood alone. A raise could also OVERTURN the
sequence: a rare recorded brown alga (likelihood 0.016) beat a red-alga match (likelihood 1.0) once its prior
was raised about 300-fold.
Change (receivers only; donor support unchanged): (G3) only rows inside their observation's likelihood-only
credible node (consensus$likelihood_consensus_taxon at likelihood_consensus_rank, i.e. Round 1's, matched
with the same .extract_rank_values the node was built with) are raised; an observation with no node has no
row raised. (G1) a row with no occurrence record (theta_mean NA) is never raised; the old "flag, don't
suppress" behaviour is reversed and confirmed_without_occurrence_record is kept for compatibility (always
FALSE when theta_mean is present). A message counts the rows each guard held back.
API: require_support_columns = TRUE stops, naming the missing column and where it comes from, when consensus
lacks likelihood_consensus_taxon/_rank or result lacks theta_mean. FALSE is a TRANSITIONAL shim for callers
not yet migrated, not a supported mode; it raises without the guards and says the results are not comparable
to a guarded run.
In-package callers: the shared pipeline helper (.run_consensus_and_report) passes FALSE for the LLM workflow
only (its priors are not occurrence-based, so there is no theta_mean) and TRUE for the Bayesian workflow;
inst/ workflows, vignettes and the example are updated.
OUT-OF-PACKAGE callers to migrate (for their owners; they stop until they supply the columns or pass FALSE):
the generic template TaxaID/inst/TaxaID_Workflow_Template.R (line 786); TaxaWizard
inst/graph/snippets/post_to_consensus.R (line 64); eDNA/PtConception (TaxaID_eDNA_Workflow_Template.R,
PtConceptionWorkflow_12S_multi_site_FAST.R, PtConception12S_regression_test.R); diagnostics scripts in
TaxaID_dev. (TaxaFlag add_posthoc_assessment, TaxaExpect apply_undetected_evidence and TaxaMatch
group_observations_by_bbox only mention the function in comments.) CalIntertidal supplies both columns.
Tests: the Dictyota case (outside the node: not raised; raised with the guards off and when the node contains
it); an observation with no node (nothing raised); the Aplanochytrium case (unrecorded inside the node: not
raised; a recorded sibling is); the occurrence-record test rewritten; the stop names the missing column; the
pipeline helper runs the LLM workflow without theta_mean and requires it for the Bayesian one. The
mechanics tests run with the guards off through a local wrapper (their fixtures carry neither column); one
arithmetic test runs the guarded default path with both columns and checks the same occurrence-scale value
and Beta shape as the shim path. The four guard tests fail on main 01feb65.
Real data (r2g_before_after.R, TaxaID_dev diagnostics): today's saved Section 8 update input (6,120,500
rows), the update run one Site at a time (the update is Site-local; the full input does not fit in memory)
with n_sims = 0 (calls use posterior_point_est, which does not depend on the simulations), then the
workflow's Section 8c consensus. BASELINE IS PRODUCTION: main 01feb65's code reproduces the stored Round 2
priors and point posteriors exactly (max difference 0 over all 6,120,500 rows), so the comparison below is
against what the run actually produced, not a re-derivation. With the guards, 1,291,613 rows change in
17,126 observations. Of the 184 flagged new confident species calls, 159 are touched and 148 change: back to
the 2026-10-06 call 35, no call 33, coarser (phylum 21, class 12, order 3, family 5, genus 39); 11 unchanged.
HEADLINE: across the changed observations, species calls 2,241 -> 810 (1,545 withheld), with 114 new species
calls and 35 species -> other species. Those 35 are NOT a broad effect: 34 are ONE congeneric pair,
Acrochaetium humile -> A. catenulatum (the unrecorded humile is no longer raised; the recorded catenulatum
wins), plus one other (Artedius lateralis -> A. harringtoni). The built code
matches the earlier measurement on 17,124 of 17,126 calls. The 2 that differ, plus 35 observations changed
only in the measurement, come from the built code testing node membership with .extract_rank_values (the
helper the node is built with, which derives genus/species from the binomial) where the measurement read
raw columns.

### 2026-10-07: G4 -- a prior boost must not overturn the likelihood ordering

Approved by the maintainer (2026-10-07, relayed by the peer coordinator: "OK. let's do G4."). This is a principle of its
own, separate from the occurrence-record and likelihood-node guards: a prior boost must not overturn the
likelihood ordering.
Problem (tonight's run, with the likelihood-node and occurrence-record guards installed and holding, 0 violations): 70
COI Acrochaetium catenulatum calls at posterior 0.96-0.99 whose winner scored below A. humile (median 86.6 vs
91.4). In COI_ESV_194374, catenulatum's likelihood was 0.0046 against humile's 0.20 (44-fold lower). Site-level
support from other ESVs that really are catenulatum raised its rare-but-recorded prior about 160,000-fold
inside a CLASS-level likelihood node, so the node guard could not see the inversion. The same mechanism also
worked the other way: a weaker recorded congener raised alongside the better-scoring species split the mass
and held that species at genus (Gibbonsia montereyensis, Citharichthys spp., Aglaophenia struthionides).
Change (under require_support_columns, alongside the two guards): a row is raised only if its score_likelihood is
at least that of every other REFERENCED candidate in its observation, ties allowed. Unreferenced rows are not
in the comparison. An NA-likelihood comparator is left out; an NA-likelihood receiver is never raised (package
review). The message counts the rows held back. No constant.
Tests: the Acrochaetium inversion is blocked (raised with the guards off); a tie is allowed; of two supported
congeners only the better-likelihood one is raised (both with the guards off); a higher-likelihood
unreferenced row does not block; NA comparator and NA receiver. Two existing guard tests now use ties so they
still isolate the node and record guards. The inversion, splitting and NA-receiver tests fail on main's code.
Real data (g4_before_after.R; tonight's update input, 6,134,732 rows, run one Site at a time, n_sims = 0, then
the Section 8c consensus). BASELINE IS PRODUCTION: main's update code reproduces tonight's stored Round 2 priors
and point posteriors exactly (max difference 0 over every row). NA likelihood: 0 of 224,354 referenced rows,
so the NA rules are untested on this dataset but specified and unit-tested. G4 removes 26,752 raises; 570,284
rows change in 10,399 observations.
Error side: all 70 Acrochaetium catenulatum calls that scored below the runner-up become class calls. Of the
258 confident species calls whose winner scored more than 1 point below the runner-up, every 18S one but 1 and
all 143 COI ones that G4 touches change (8 COI untouched); in 12S only 19 of 73 change, because 52 are not
touched: their winner leads on calibrated likelihood although it trails on raw score. 23 calls move to another
species, all to a better-scoring SIBLING (Xiphister atropurpureus -> X. mucosus x11, Clinocottus recalvus -> C.
globiceps x6, Syngnathus californiensis -> S. exilis x5, Artedius x1).
Species calls in the changed observations: 1,739 -> 4,466 (607 withheld, 3,334 new). Most new calls are the
best-scoring recorded species once a weaker congener's raise no longer splits the mass. Whole dataset,
species calls per marker (12S / 18S / COI): 10-06 before item b 10,541 / 364 / 3,819; 10-07 am after item b
12,238 / 1,079 / 4,670; 10-07 pm with C1 and the node and record guards 12,143 / 356 / 4,108; pm with G4
15,015 / 265 / 4,054. The built code matches the earlier measurement on all 10,399 observations both touch;
90 further observations touched only by the measurement have no call change.
