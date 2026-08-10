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
- The "Empirical sensitivity" `@details` block (Session 145's real parameter sweep)
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
  closes a real, already-documented production landmine (see this package's own
  `CLAUDE.md` 2026-07-30 note): `posterior_consensus()`'s `group_priors` lookup is
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
