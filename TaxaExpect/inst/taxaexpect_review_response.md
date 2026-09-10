# TaxaExpect Code + Domain Review Response

**Review date:** 2026-08-04 (file mtime) **Package version reviewed:** TaxaExpect 0.1.0
**Response prepared by:** Claude Code (Sonnet 5), 2026-08-04, at K. D. Lafferty's request

This document responds to `inst/taxaexpect_review.Rmd`, which reviews 18 files
(`add_pca_covariates.R`, `build_priors.R`, `compute_adaptive_sampling_groups.R`,
`compute_moran_basis.R`, `create_sites_from_grid.R`, `generate_domestic_food_priors.R`,
`generate_full_priors.R`, `generate_undetected_diversity.R`, `optimize_grid_size.R`,
`plot_theta_map_interactive.R`, `prepare_model_dataframe.R`, `recover_demoted_species.R`,
`report_priors.R`, `screen_spatial_formula.R`, `TaxaExpect-package.R`,
`train_biodiversity_model.R`, `train_biodiversity_model_by_group.R`, `utils_plot.R`) plus
a set of ecosystem-wide general comments. Several line-number references in the review no
longer match current line numbers -- this package has had substantial work land since the
review was likely drafted (see `TaxaExpect/CLAUDE.md`'s session history) -- every finding
below was re-verified against the current source before being fixed or declined, per this
project's own "verify before fixing" convention (see `feedback_verify_purpose_before_flagging`
in the memory system).

`devtools::document()` + `devtools::test()`: 555 expectations, 0 failures (up from 538).
`devtools::check()`: 0 errors, 0 warnings, 0 notes. Reinstalled to
`~/Library/R/4.0/library`. A short end-to-end smoke test of the new `grid_size`
propagation chain (`create_sites_from_grid()` -> `prepare_model_dataframe()` ->
`train_biodiversity_model()` -> `generate_full_priors()`) and
`compute_moran_basis(coords = ...)` was run against real synthetic data outside the test
suite to confirm the new attribute actually threads through in practice, not just in
isolated unit tests.

------------------------------------------------------------------------

## Cross-cutting fixes (touch more than one file)

- **`beta_mean`/`beta_sd` triplication** (flagged separately under both
  `generate_domestic_food_priors.R` and `generate_undetected_diversity.R`, and implied by
  the "lines 704-705... produced elsewhere" comment under `generate_full_priors.R`): a new
  `R/utils_internal.R` adds `.beta_mean()`/`.beta_sd()`, now the single implementation used
  by all three files (previously each had its own identical copy).
- **`tax_rank_cols`/taxonomic rank vector duplication** (flagged under both
  `generate_domestic_food_priors.R` and `generate_undetected_diversity.R`, and the general
  "a variety of taxonomic rank objects are created here, and throughout the package
  ecosystem" comment): `R/utils_internal.R` adds `.dark_diversity_rank_cols`, now shared by
  both files. This is a narrower, package-internal fix, not the ecosystem-wide unification
  the general comment gestures at -- see "Declined" below for why the broader version is
  out of scope here.
- **Duplicate `grid_id`-string parser** (`compute_moran_basis.R`'s own comment: "I think a
  function to parse grid_id is also defined in `compute_moran_basis.R`, define once and
  reference" -- correctly anticipating that `plot_theta_map_interactive.R` had a second,
  differently-implemented copy): `R/utils_internal.R` adds `.parse_grid_id_coords()` (the
  more robust of the two originals -- vectorised via `sub()`, which preserves `NA`/length
  rather than silently dropping unmatched elements the way `regmatches(regexpr(...))`
  would). Both files now call it; the two local copies (`.parse_grid_id_basis()` in
  `compute_moran_basis.R`, `.parse_grid_id()` in `plot_theta_map_interactive.R`) are
  deleted.
- **"Why parse `grid_id` when coordinates are known?"** (asked under both
  `compute_moran_basis.R` and `plot_theta_map_interactive.R`): partially fixed, partially
  declined -- see each file's own section below. `compute_moran_basis()` gained a `coords`
  parameter so a caller who already has real `lat_r`/`lon_r` can skip string-parsing
  entirely; `plot_theta_map_interactive()` still parses `grid_id` (declined to change, see
  its own section) but now also reads a recorded `grid_size` attribute instead of
  inferring the cell half-width, addressing the closely related "Isn't the grid resolution
  also knowable? Suggest recording somehow and reading actual value" comment. A new
  `grid_size` attribute, set by `create_sites_from_grid()`, is threaded through
  `prepare_model_dataframe()` -> `train_biodiversity_model()` (`$meta$grid_size`) ->
  `generate_full_priors()` (output attribute) -- purely additive, `NULL`-safe at every
  hop, confirmed working end to end via a live smoke test (see above).
- **Session/date references in user-facing roxygen** ("much of the comments contain
  narrative describing earlier versions and the development process... suggest removing
  this as it is the first release"): cleaned from every `@section`/`@details` header that
  is purely a version-history label (`generate_undetected_diversity.R`,
  `prepare_model_dataframe.R`, `train_biodiversity_model.R`,
  `train_biodiversity_model_by_group.R`) -- 6 headers changed, e.g. `@section Multi-group
  data is refused (Session 149):` -> `@section Multi-group data is refused:`. Three dated
  references were deliberately **left in place** (`generate_full_priors.R:59`,
  `prepare_model_dataframe.R:73`, `train_biodiversity_model.R:268`, all `2026-07-03`):
  each names the date a specific real bug (not a refactor or rename) was found and fixed,
  which is exactly the kind of thing a future user hitting a related edge case would want
  to know actually happened, not narrative for its own sake -- these pass the review's own
  stated test ("unless they are directly relevant to future users"). Top-of-file plain
  `#` dev-log comments (e.g. `screen_spatial_formula.R`'s 2-line renaming log,
  `train_biodiversity_model_by_group.R`'s file-header paragraph) were left alone --
  lower-visibility than roxygen (never rendered by `?function`), and match this
  ecosystem's existing convention of keeping a brief top-of-file history in several other
  packages.
- **"Weird spaces" (`build_priors.R:217, 660, 729`)**: these turned out to be two related
  but distinct artifacts, found by re-reading the current file rather than trusting the
  stale line numbers: (1) one comment line with a single leading space instead of two
  (`" # may come from any backbone..."`), and (2) three separate places where a stray
  blank line splits one comment sentence into two disconnected-looking fragments (e.g.
  `"...should be a" / <blank> / "no-op for NCBI backbone."`). All four fixed. A
  package-wide sweep (`R/*.R`) for the same two patterns found no further instances --
  every other blank-line-before-`#'` hit was a legitimate section-divider (a plain `#`
  banner comment followed by a blank line, then a real roxygen block), not the same bug.
- **`is.integer()` simplification (`compute_moran_basis.R`)**: declined. The current check
  (`k != round(k)`) accepts the ordinary, idiomatic `k = 10` (a double); `is.integer(10)`
  is `FALSE` in R, so switching to it would reject the most common way a user actually
  types this argument and force `k = 10L` -- a real regression in usability for a cosmetic
  simplification. `k <- as.integer(k)` immediately below already coerces to a true integer
  once validated.

------------------------------------------------------------------------

## General comments (not file-specific)

- **British spellings ("centre", "colour")**: not changed. Confirmed via `grep` this is a
  consistent, deliberate style choice across the whole TaxaID ecosystem (e.g. `"Centre
  coordinates"` in `build_priors.R`'s own docs, `.habitat_palette()`'s British spelling in
  `utils_plot.R`, matching equivalents in TaxaFetch/TaxaHabitat), not an accident isolated
  to this package.
- **Replace objects named `data` with more informative names**: partially applies here.
  Five exported functions use `data` as their first parameter
  (`compute_adaptive_sampling_groups()`, `create_sites_from_grid()`,
  `prepare_model_dataframe()`, `screen_spatial_formula()`, `train_biodiversity_model()`).
  **Declined**, matching the identical decision already made and documented in
  `TaxaMatch/inst/taxamatch_review_response.md` for `standardize_match_data()`'s own
  `data` parameter: this is common, idiomatic R convention (`lm(data =)`,
  `ggplot(data =)`, `glmmTMB::glmmTMB(data =)` -- the exact modelling function this
  package wraps), not a local mistake. The blast radius here is also real and larger than
  TaxaHabitat's own equivalent `data` -> `occurrence_data` rename (2026-08-01, see
  `TaxaID/CLAUDE.md`'s Recent Breaking Changes table): a grep across the whole
  `~/My Drive/Rscripts` tree (not just this monorepo) found ~20 named `data = ` call
  sites for these five functions, spanning multiple real, currently-running production
  eDNA workflow scripts outside this monorepo (`PtConceptionWorkflow_12S_single_site.R`,
  `PtConceptionWorkflow_18S_2_single_site.R`, several older/historical
  `Prior_Workflow*.R`/`main.workflow.R` scripts whose current status could not be
  confirmed) plus a `TaxaWizard` code-generation snippet. Renaming would require touching
  every one of those, several without a reliable way to verify they are still in active
  use -- a scope decision for a dedicated session with the user's sign-off, not a
  unilateral call inside this review pass. Local variables named `data` inside function
  bodies (not parameters) were left alone for the same reason `cov`/`.he()` were handled
  differently -- see below.
- **Consider combining these packages into one**: declined -- this is a standing ecosystem
  architecture decision, already made and documented (see `TaxaID/CLAUDE.md`'s package
  split history: TaxaFetch split from TaxaExpect Session 19, TaxaHabitat split Session 28,
  TaxaMatch/TaxaLikely split Session 30, TaxaFlag added Session 60). Revisiting it is a
  cross-package decision for the user, not something to change inside a single-package
  review response.
- **`rnaturalearthdata`/`rnaturalearthhires` should be explicit dependencies**: verified
  directly -- TaxaExpect itself has **zero** references to `rnaturalearth`/
  `rnaturalearthdata`/`rnaturalearthhires` anywhere in its own source. This finding
  applies to `TaxaHabitat`, not this package; confirmed TaxaHabitat's own `DESCRIPTION`
  already lists both (`rnaturalearthdata`, `rnaturalearthhires`) in Suggests. No action
  needed in TaxaExpect.
- **`formula` is an existing R function**: declined. `formula` is used as a parameter name
  in `train_biodiversity_model_by_group()` and (via `formula_full`) `screen_spatial_formula()`.
  This is standard, idiomatic R practice for exactly this domain -- `stats::lm(formula,
  data)`, `stats::glm(formula, data)`, and `glmmTMB::glmmTMB(formula, data)` (the modelling
  engine this package wraps directly) all use the identical parameter name. Unlike `data`
  (which shadows a function users commonly call standalone, `utils::data()`), no realistic
  confusion exists here.
- **Identifying an unprecedented invasion may be a weakness of this package/ecosystem**:
  acknowledged, no code change -- this is a domain-scope observation about what the
  Bayesian framework can and cannot detect (a truly novel arrival has no prior support
  anywhere in the pipeline by construction), not a bug. Recorded here for visibility;
  matches the reviewer's own framing that this is a known, considered limitation rather
  than an oversight.

------------------------------------------------------------------------

## File-specific responses

### `add_pca_covariates.R`

**Fixed:**
- Both `add_pca_covariates()` and `apply_pca_transform()` gained real, fast, self-contained
  `@examples` (small synthetic correlated covariates, `set.seed()`'d) instead of a
  `\dontrun{}` block referencing objects (`gridded_data`, `model_obj`) that don't exist in
  the example's own scope. The original `\dontrun{}` block illustrating the full
  `prepare_model_dataframe()` -> `add_pca_covariates()` -> `train_biodiversity_model()`
  chain is kept alongside, for context.

**Already correct, no change needed:**
- "Lines 88-92: how much of this is reproduced from `prepare_model_dataframe`?" -- checked
  directly: lines 88-92 are the `anyNA(pca_mat)` diagnostic-`stop()` block. No equivalent
  logic exists anywhere in `prepare_model_dataframe.R` (that function tolerates `NA` via
  `na.rm = TRUE` in its own mean/SD calculations rather than erroring). This appears to be
  a stale line-number reference from an earlier draft of this file; no duplication found.

### `build_priors.R`

**Fixed:**
- `llm_fn`'s roxygen default was stale (`TaxaTools::call_anthropic_api`) while the actual
  code default is `getOption("TaxaID.llm_fn", TaxaTools::call_api)` -- the reviewer's own
  question ("Doesn't `llm_fn` actually default to whatever the env variable is now?") was
  correct; only the documentation was wrong. Fixed to describe the real default.
- `habitat_scheme[[1]]` (used only for a status message) read whichever column happened to
  be first in a custom `habitat_scheme` data frame, rather than the specific column
  `TaxaHabitat::build_habitat_prompt()`'s own validator (`.validate_habitat_scheme()`)
  actually requires (`l1_name`) -- confirmed by reading that validator directly. Fixed to
  read `l1_name` when present, falling back to the first column only for a shape that
  predates that requirement.
- "Weird spaces" -- see Cross-cutting fixes above.

**Already correct, no change needed:**
- "What happens if `gbif_rank` isn't in the keys `data.frame`?" -- traced directly:
  `good_match` is computed unconditionally *before* the `if ("gbif_rank" %in%
  names(keys))` block, and the Layer-2 fallback's own `queried_rank <- if
  (exists("input_ranks")) ... else NA_character_` guard correctly no-ops that entire
  branch when the column (and therefore `input_ranks`) was never created. Both paths
  degrade safely; no fix needed.
- "Line 440: this seems like it should be 2 of 7, as no other steps have substeps" (the
  GBIF genus census stage, printed as `"[1b/7]"`) -- this is intentional, not a
  miscount: the `"1b"` label is deliberately a sub-step of Stage 1 (it runs on Stage 1's
  own output, before Stage 2 begins), and keeping the total denominator at a stable "of 7"
  across the whole function is the point of the letter suffix, rather than inflating the
  total to 8 for one optional, skippable step (`census_genera = FALSE` skips it entirely).
  Left unchanged.

**Considered and declined (with reasoning):**
- **`lat`/`lon`/`search_radius_deg` -> single `bbox` parameter**: declined. The
  center+radius form is simpler for the common case, is what `TaxaFetch::make_bbox_wkt()`
  itself takes, and `lat`/`lon` are independently needed downstream (`search_center`
  attribute for `TaxaAssign::join_priors()`'s default site, real-time messaging). A raw
  WKT bbox parameter would need callers to hand-write polygons for the common centered-
  search case without removing the need for `lat`/`lon` elsewhere in the function.
- **`year_range` as a plain length-2 integer vector, removing the coercion at line ~190**:
  the numeric-vector form is already accepted (`if (!is.null(year_range) &&
  is.numeric(year_range)) year_range <- paste(as.integer(year_range), collapse = ",")`) --
  this already works today: `year_range = c(2015, 2025)` is valid input. The coercion
  itself can't be removed, though, since `TaxaFetch::fetch_gbif_occurrences()` requires
  GBIF's own comma-joined string format downstream; this line is the necessary bridge
  between a user-friendly input and that requirement, not incidental cruft.
- **`checkpoint_dir` as an explicit argument to the internal `.save()` closure**: declined.
  `.save()` closes over `checkpoint_dir` the same way the adjacent `.msg()` closure closes
  over `verbose` -- consistent, idiomatic use of closures for two small internal helpers
  scoped to one function, not worth threading an extra parameter through every one of the
  8 call sites for no behavioral change.
- **Line 71 (rename option for `supplemental_occurrences`'s required columns)**: the
  current signature has no rename-mapping parameter at all -- `supplemental_occurrences`
  already requires exact column names (or pre-renaming via
  `TaxaTools::rename_cols()` before the call), matching the reviewer's own suggested
  direction. Appears to describe an earlier version of this function; no change needed.
- **Collapsing the ecosystem's various taxonomic-rank-vector objects into one**: see
  Cross-cutting fixes above (a narrower, package-internal version was implemented instead)
  and General comments above (the full ecosystem-wide version is out of scope for a
  single-package pass).
- **`TaxaHabitat::assign_habitat_biological()`'s "0 site(s) assigned 'Other'" message**:
  this is a real, valid finding, but it lives in `TaxaHabitat/R/assign_habitat_biological.R`
  (lines 376-377), not in this package -- `build_priors.R` only calls it. Flagging here for
  a future TaxaHabitat-scoped pass rather than editing a sibling package as a side effect
  of this review.
- **The `prepare_model_dataframe()` correlation warning firing "frequently" for
  `lat_r`/`lon_r`**: acknowledged as a real, expected pattern (species distributions
  routinely correlate with both axes at once) rather than a bug -- `add_pca_covariates()`
  already exists specifically to handle it, and is cross-referenced from
  `prepare_model_dataframe()`'s own warning message. No further change made here.
- **Example not runnable**: left `\dontrun{}` -- `build_priors()` makes live GBIF and LLM
  API calls and fits a real spatial GLMM; there is no way to make this both runnable in
  `R CMD check` and meaningful without either bundling example data (out of scope for this
  pass) or mocking away the entire point of the function.

### `compute_adaptive_sampling_groups.R`

**Fixed:**
- `min_n` lost its `100` default and is now a required argument -- matches this ecosystem's
  established "no safe universal default" convention (e.g. `TaxaAssign::join_priors(
  backbone_id = )`, `TaxaAssign::score_consensus(rank_thresholds = )`): a viable per-site
  record count varies by orders of magnitude across study designs, and the function's own
  docs already called `100` "a placeholder... adjust to your system's actual effort
  scale." Omitting it now errors immediately with guidance, rather than silently applying
  a value that is very likely wrong for a given caller. Verified zero real callers exist
  anywhere in the monorepo or the wider `~/My Drive/Rscripts` tree (this function has never
  been wired into a production workflow, per its own docs), so this is zero-risk.
  Parameter order left unchanged (`min_n` stays 3rd) to avoid an unnecessary second,
  unrelated signature change.
- Gained a real, fast, non-`\dontrun{}` `@examples` block.

**Addendum, 2026-09-09 (dated, does not rewrite the answer above):** archived to
`archive_glmm_prior_pipeline/`, alongside `create_sites_from_grid()` (see that
function's own section below). Confirmed via a fresh grep across the whole monorepo:
still zero real callers anywhere -- the "never been wired into a production workflow"
observation recorded above at review time remained true right up to archival. See
`TaxaExpect/CLAUDE.md`'s 2026-09-09 (later) session note for the full record.

**Addendum, 2026-09-09, later still (dated, does not rewrite the answers above):** the
archival above is REVERSED -- this function is restored to `R/` and live again, moved
back out of `archive_glmm_prior_pipeline/`. Not a re-litigation of the "zero real
callers" finding above (still true) but a real, different consideration found while
reviewing `TaxaExpect/README.md`: `estimate_kernel_priors(sampling_group_col = NULL)`
has no guard at all against silently pooling data from genuinely incompatible detection
processes (e.g. phytoplankton cell counts + bird point counts) -- confirmed directly in
`R/estimate_kernel_priors.R`. The now-archived GLMM path had a hard `stop()` for this
exact hazard (`train_biodiversity_model()`'s `sampling_group` multi-value check); the
kernel path has no equivalent, and this is a real safety regression, not a hypothetical
one. Auto-detecting the mixing was explicitly rejected (this codebase's established
precedent, see `generate_invasive_watch_evidence()`'s own roxygen, is to never guess a
domain classification a wrong guess could silently mis-price) -- the fix is making
`sampling_group_col` unmissable in the docs and keeping a real tool available to
discharge that responsibility, which is exactly what this function is. Also, TaxaID is
headed for a USGS software release and an MEE manuscript -- an external user adopting
this package won't have the domain depth the person who hand-built the real 18S
workflow's 11-way classification did, which the original archival's "never actually
needed" reasoning implicitly assumed. See `TaxaExpect/CLAUDE.md`'s later 2026-09-09
session note for the full record.

**Addendum, 2026-09-09, final (dated, does not rewrite the answers above):** the
restoration directly above is REVERSED, this time final -- this function is archived
again, moved back to `archive_glmm_prior_pipeline/`. The restoration's own reasoning
was tested against real evidence, not just re-argued, and refuted: run live against a
real, full-scale, hand-built 9-group expert classification on the actual PtConception
18S occurrence checkpoint (1,375,345 rows), `compute_adaptive_sampling_groups(min_n =
100)` produced 37-58 automatic groups at three grid sizes against the expert's 10 --
splitting the single largest real group (`macroinvertebrates`, 1.27M records, all
genuinely detected by the same eDNA marker) into 28-39 separate automatic groups purely
because each order individually clears the per-site record floor on its own. The
algorithm also collapsed two taxa the expert had deliberately kept separate --
`parasites` (n=9) and `terrestrial_arthropods` (n=3), almost certainly a real marine
target vs. likely airborne contamination -- into one `phylum:Arthropoda` group, purely
because neither cleared `min_n` even at the phylum ceiling. This is exactly the
"combining taxa collected by incommensurable methods" failure the whole `sampling_group`
mechanism exists to prevent, produced automatically by the tool meant to help avoid it.
Separately, `estimate_kernel_priors(sampling_group_col=)` was run directly on the real,
UNMERGED 9-group expert classification (no merge step at all) and succeeded with zero
errors for every group, including the tiniest (`terrestrial_arthropods`, n_taxa=1;
`parasites`, n_taxa=3) -- refuting the premise that a sample-size-adequate merge step was
ever necessary before calling the estimator. See `TaxaExpect/CLAUDE.md`'s final
2026-09-09 session note for the full evidence record (Findings 1-5).

### `compute_moran_basis.R`

**Fixed:**
- New `coords` parameter: a data frame with real `grid_id`/`lat`/`lon` can now be supplied
  directly, used in place of string-parsing `grid_ids`' own encoding (falling back to
  parsing only for any `grid_id` missing from `coords`). Directly answers "why use
  `.parse_grid_id_basis` when lat/lon coordinates are known?" -- when a caller has
  `prepare_model_dataframe()`'s own `lat_r`/`lon_r` columns on hand, they no longer have
  to round-trip through the string encoding at all. Backward compatible: `coords = NULL`
  (the default) preserves the original string-parsing behavior exactly.
- Duplicate parser (`.parse_grid_id_basis()`) removed in favor of the shared
  `.parse_grid_id_coords()` -- see Cross-cutting fixes above.
- Gained a real, fast, non-`\dontrun{}` `@examples` block (a small synthetic 4x4 grid),
  plus a `\dontrun{}` block demonstrating the new `coords` parameter in real usage.

**Declined:** `is.integer()` simplification for the `k` validity check -- see Cross-cutting
fixes above.

### `create_sites_from_grid.R`

**Fixed:**
- `@examples` fixed using the reviewer's own tested code
  (`data.frame(decimalLatitude = runif(10, 34, 36), decimalLongitude = runif(10, -119,
  -118))`) -- verbatim, since the reviewer had already confirmed it works.
- `grid_id_raw` intermediate column removed entirely: the two `stringr::str_replace_all()`
  calls (`"-"` -> `"m"`, then `"."` -> `"p"`) operate on disjoint characters and can be
  chained directly on `sprintf()`'s output within one `mutate()`, with no need to hold the
  pre-replacement string in its own column and drop it afterward. Confirmed the existing
  `"grid_id_raw intermediate column is NOT in output"` test still passes unchanged (it
  never existed to begin with now, rather than being created-then-dropped).
- New `grid_size` attribute recorded on the output -- the seed of the cross-cutting
  `grid_size` propagation chain described above, closing the "isn't the grid resolution
  also knowable?" question raised under `plot_theta_map_interactive.R`.

**Declined:** requiring fixed `lat_col`/`lon_col` names instead of configurable
parameters -- see `optimize_grid_size.R`'s matching section below for the shared
reasoning (this decision was made once and applies identically to both files).

**Addendum, 2026-09-09 (dated, does not rewrite the answer above):** archived to
`archive_glmm_prior_pipeline/`, alongside `compute_adaptive_sampling_groups.R`. This
function was deliberately kept live at the time of the main 2026-09-09 GLMM-chain
archival, on the strength of its own roxygen's claim of one remaining independent
purpose (spatial binning feeding `compute_adaptive_sampling_groups()`'s per-site
effort measurement, ahead of `estimate_kernel_priors(sampling_group_col=)`). That
justification was re-examined directly, later the same day, at the user's explicit
prompt: a fresh grep confirmed zero calls in any of the 6 real production workflows,
and the scenario it would justify keeping this pair for (taxonomic breadth too large
to hand-classify into detection-process sampling groups) has never actually
materialized in any real dataset this ecosystem has handled, including the
taxonomically broadest one (PtConception 18S, ~10-11 groups, successfully
hand-classified). The one remaining real caller,
`diagnostics/kernel_budget_18S_sampling_groups.R`, is a frozen, dated one-time
analysis script and was left untouched, per this project's own convention for such
scripts. See `TaxaExpect/CLAUDE.md`'s 2026-09-09 (later) session note for the full
record.

**Addendum, 2026-09-09, later still (dated, does not rewrite the answers above):** the
archival above is REVERSED -- this function is restored to `R/` and live again, moved
back out of `archive_glmm_prior_pipeline/`, alongside `compute_adaptive_sampling_
groups()` (see that function's own addendum above). Real reason, not a re-litigation:
a safety gap found reviewing `TaxaExpect/README.md` -- `estimate_kernel_priors(
sampling_group_col = NULL)` silently pools incompatible detection processes with no
guard, unlike the archived GLMM path's hard `stop()` for the same hazard. Auto-detection
was rejected as out of character for this codebase (never guess a domain
classification); the fix is an unmissable doc warning plus a real tool a user can reach
for -- this function is that tool. Also weighed: TaxaID is headed for a USGS/MEE
publication, and an external adopter won't have this project's own hand-built-11-way-
classification domain depth, a genuinely different consideration from what was weighed
at archival time. See `TaxaExpect/CLAUDE.md`'s later 2026-09-09 session note for the
full record.

**Addendum, 2026-09-09, final (dated, does not rewrite the answers above):** the
restoration directly above is REVERSED, this time final -- this function is archived
again, moved back to `archive_glmm_prior_pipeline/`, alongside `compute_adaptive_
sampling_groups()` (see that function's own final addendum above for the full evidence
record). In short: real, full-scale testing against a hand-built 9-group expert
classification on the actual PtConception 18S occurrence checkpoint confirmed
`compute_adaptive_sampling_groups()` (the function this file's own spatial-binning
purpose exists to feed) answers the wrong question -- record-count adequacy, not shared
detection process -- and can fragment or falsely conflate real groups. It also confirmed
`estimate_kernel_priors()` needs no pre-merged, sample-size-adequate groups at all (it
fits cleanly on the real unmerged classification down to a single-taxon group), so the
spatial-binning purpose this function was kept alive for was never actually load-bearing.
See `TaxaExpect/CLAUDE.md`'s final 2026-09-09 session note for the full record.

### `generate_domestic_food_priors.R`

**Fixed:**
- `beta_mean`/`beta_sd` and `tax_rank_cols` de-duplicated -- see Cross-cutting fixes above.
- `radius_km`'s roxygen now states "in kilometers" explicitly rather than relying on the
  parameter name alone.
- Added an explicit note to the `.default_food_species_taxa`/`.default_known_cultivar_taxa`
  `@section Provenance` block stating plainly that the five Wikipedia food-plant list URLs
  were not retained from the original web-search session and cannot be reconstructed with
  confidence now, rather than fabricating citations. The reviewer's underlying ask (cite
  the actual source pages) could not be honestly satisfied after the fact; this makes the
  gap explicit instead of silently leaving it unaddressed.

**Considered and declined (with reasoning):**
- **Example not runnable**: left `\dontrun{}` -- requires a real `biofreq_model` and live
  `TaxaFetch::fetch_inat_occurrences()` calls (a real external API), which cannot be made
  both deterministic and meaningful in a package example.

### `generate_full_priors.R`

**Fixed:**
- `cov` (an existing R function, `stats::cov()`) renamed to `covariate` throughout the
  scaling loop.
- `beta_mean_fn`/`beta_sd_fn` (local, file-scoped duplicates) replaced by the shared
  `.beta_mean()`/`.beta_sd()` -- see Cross-cutting fixes above; this closes the "lines
  704-705... produced elsewhere, make a single function and reference" finding directly
  (those were exactly this pair).
- `predict_tier()`/`predict_tier_empirical()`'s identical `effort_flag`/`n_obs` assignment
  block (present verbatim in both) factored into one shared local helper
  (`.assign_effort_flag()`) -- a real, bounded DRY win extracted from the larger
  `predict_tier`/`predict_tier_empirical` duplication finding below.
- New `grid_size` output attribute -- see Cross-cutting fixes above.

**Considered and declined (with reasoning):**
- **Fully merging `predict_tier()` and `predict_tier_empirical()`**: the shared
  effort-flag logic was extracted (above), but the rest was left separate. The two
  functions build their prediction grids from genuinely different sources (a
  `crossing()` + `predict.glmmTMB()` call needing habitat indicators/Moran columns/
  factor-level restoration, vs. a plain join against a pre-computed empirical-means table
  with a completely different join key set) -- forcing them into one function would need a
  large branching parameter surface for a marginal line-count win, the same reasoning
  already applied to a structurally similar case in
  `TaxaMatch/inst/taxamatch_review_response.md` (`read_image_classifiers.R`'s three
  reader functions, "considered and declined").
- **`dplyr::if_else()` instead of base `ifelse()`** (lines ~400-403): declined --
  `dplyr::if_else()` is used consistently throughout this file and the rest of the
  package specifically for its stricter type-checking (it errors on a type mismatch
  rather than silently coercing), matching this codebase's own native-pipe/dplyr-first
  convention; no `missing` argument is needed here since both branches are already
  same-type numeric vectors.
- **Example not runnable**: left `\dontrun{}` -- needs a real fitted `biofreq_model`.

### `generate_undetected_diversity.R`

**Fixed:**
- `beta_mean`/`beta_sd` and `tax_rank_cols` de-duplicated -- see Cross-cutting fixes above.
- Session/date references removed from 4 roxygen `@section` headers -- see Cross-cutting
  fixes above.

**Already correct, no change needed:**
- "Line 291 and onward: The global floor row has `NA` for `grid_id` in `result`. Is this
  expected?" -- yes: the global floor prior is not tied to any specific location (it is a
  single effort-based prior computed from `N_total` across the whole dataset), and its own
  `@return` documentation already states this explicitly (`grid_id`: "... or NA for the
  global floor"). Confirmed intentional, not an oversight.

**Considered and declined (with reasoning):**
- **"Should this reference `generate_domestic_food_priors`?"**: the two functions are
  already cross-referenced in both directions via `@seealso` and each other's roxygen
  `@section` text (`generate_undetected_diversity()`'s own "Domestic/synanthropic species"
  section points at `generate_domestic_food_priors()` by name). No further linkage added.
- **"Line 58: if this is referencing an issue on the github repo, it's not clear what that
  is"**: could not be reproduced against the current file -- no GitHub issue reference
  exists anywhere in this file's current text (the line-number references throughout this
  review predate substantial rewrites; see this document's header). No change made absent
  a reproducible target.

### `optimize_grid_size.R`

**Fixed:**
- `@examples` corrected -- the original example passed `grid_sizes = c(0.05, 0.10, 0.25)`
  and `min_species = 5`, **neither of which is a real parameter of this function**
  (the actual parameters are `min_grid`/`max_grid`/`step_grid` and `min_s_threshold`). This
  was a genuine documentation bug (an example that would error if run), not just a style
  preference -- fixed to use the function's real parameter names.
- `tidyr::drop_na()`'s silent row-dropping now surfaces a `message()` naming how many rows
  (and what fraction) were dropped and why. Used `message()`, not `warning()`, matching
  this function's own established convention of `message()` for expected/informational
  data-cleaning steps and `warning()` reserved for conditions that trigger a fallback path
  (e.g. the three grid-size fallback levels below it in the same function).
- `.score_one_resolution()`'s argument count reduced from 10 to 5: the four column-name
  arguments (`lat_col`/`lon_col`/`species_col`/`habitat_col`) are now bundled into one
  `site_cols` list, and the four threshold arguments into one `thresholds` list. Purely
  internal (`.score_one_resolution()` is `@noRd`, not exported), so this is zero-risk to
  any external caller; the 4 direct unit tests exercising it (`TaxaExpect:::.score_one_
  resolution(...)`) were updated to the new call shape.

**Considered and declined (with reasoning):**
- **Requiring fixed `lat_col`/`lon_col`/`species_col`/`habitat_col` names instead of
  configurable parameters** (raised for both this file and `create_sites_from_grid.R`):
  declined for both. Real occurrence data doesn't always arrive in Darwin Core's
  `decimalLatitude`/`decimalLongitude` convention (camera-trap exports, acoustic
  detections, and hand-entered datasets commonly use other names), and this ecosystem's
  established mechanism for standardizing column names is `TaxaTools::rename_cols()`,
  called *before* handing data to a TaxaExpect function -- not requiring every downstream
  function to hard-code one naming convention. The configurable-parameter design already
  defaults to the Darwin Core names, so nothing changes for the common case; it just
  doesn't force a rename for the uncommon one.
- **Example not runnable**: kept `\dontrun{}` even after fixing the parameter-name bug
  above -- a genuinely useful example needs realistic multi-species, multi-site occurrence
  data for the grid search to converge on an instructive (non-fallback) answer; a tiny
  synthetic fixture would mostly just demonstrate the fallback-warning path, which isn't
  the didactic point of this function.

### `plot_theta_map_interactive.R`

**Fixed:**
- **Real documentation bug**: the `@return` doc referenced `plot_theta_map()` ("use
  `plot_theta_map()` when you need a static exportable figure") -- confirmed via a
  monorepo-wide grep that **no such function exists anywhere in this codebase**. The
  reviewer's own search had already established this ("I searched the project and I
  couldn't find"). Fixed to describe a real alternative (plotting `priors` directly with
  a general-purpose plotting package) instead of pointing at a function that was never
  built.
- Duplicate `.parse_grid_id()` helper removed in favor of the shared
  `.parse_grid_id_coords()` -- see Cross-cutting fixes above.
- Grid cell half-width now prefers the real recorded `grid_size` attribute (propagated
  from `create_sites_from_grid()`) over inferring it from centroid spacing, when present
  -- directly answers "Isn't the grid resolution also knowable? Suggest recording somehow
  and reading actual value." Falls back to the original inference logic for `priors`
  objects that predate this attribute (e.g. hand-built, or produced before this session).
- New `tests/testthat/test-plot_theta_map_interactive.R`: 6 tests covering the now-shared
  `.parse_grid_id_coords()` and the pure `.truncate_label()` helper, directly addressing
  "No tests for this function, but that makes sense for shiny apps. Testing helpers would
  be good." -- mirrors the precedent already set by
  `TaxaTools::define_search_polygon()`'s own `.pts_to_wkt()`/`.wkt_to_pts()` tests (pure
  helpers tested without a live gadget session; the gadget itself remains untested, same
  as before).

**Considered and declined (with reasoning):**
- **Parsing `grid_id` at all, when coordinates might be known**: declined to remove
  entirely, unlike `compute_moran_basis()` above. `priors` objects (this function's input)
  are typically standalone artifacts -- saved to disk, reloaded in a later session,
  potentially on a different machine -- that don't carry a separate sites table alongside
  them; `grid_id`'s own string encoding is the self-contained record of where each cell
  is. Adding real `lat_r`/`lon_r` columns to `generate_full_priors()`'s own output was
  considered as a further step (it already has them internally, before the final
  `output_cols` selection drops them) but scoped out of this pass: propagating them
  correctly through `generate_undetected_diversity()`'s singleton-mirror/global-floor rows
  and `generate_domestic_food_priors()`'s single-query rows (neither of which has a
  natural multi-cell `lat_r`/`lon_r` the same way) would be a real, separate design
  question, not a one-line addition. The `grid_size`-attribute fix above addresses the
  more actionable, narrower half of the original comment (resolution) without that
  larger scope.
- **No example data / didn't run this function**: acknowledged -- this remains genuinely
  hard to address in a package example, since the function both requires `interactive()`
  to be `TRUE` (so it can never execute inside `R CMD check` regardless of data
  availability) and is a Shiny gadget with no batch-mode return value to assert against.
  The new helper-function tests (above) are the practical substitute.

### `prepare_model_dataframe.R`

**Fixed:**
- The internal `.run_one_group` closure -- previously nested inside
  `prepare_model_dataframe()` with its ~140-line body left at the *same* indentation level
  as the outer function, rather than indented one level deeper the way a nested function's
  body normally would be -- extracted to a proper top-level `.prepare_one_group(data,
  covariates, habitat_col)` helper with explicit parameters (no closure capture) and
  correct indentation throughout. Directly addresses "Indenting code for `.run_one_group`
  or putting outside main function would make it easier to read." Called identically from
  both the single-group and per-group-split code paths.
- The same function's aggregation logic (site totals, species counts, the zero-fill
  `tidyr::complete()` step) rewritten from deeply nested function calls
  (`dplyr::mutate(dplyr::left_join(tidyr::complete(dplyr::summarise(dplyr::group_by(
  dplyr::filter(...))))))`) to a native-pipe chain, matching this project's own stated
  coding convention (`CLAUDE.md`: "Native pipe `|>` throughout") and directly addressing
  "These functions tend to use nesting instead of pipes... inconsistent with other
  functions in the package."
- Gained a real, fast, non-`\dontrun{}` `@examples` block for the base case (a
  `\dontrun{}` block remains for the `sampling_group_col` grouped case, which needs a
  larger fixture to be illustrative).
- Session/date references removed from 2 roxygen `@section` headers -- see Cross-cutting
  fixes above.
- Now propagates the `grid_size` attribute (when present on its input) through to its own
  output, in both the single-group and grouped-output paths -- see Cross-cutting fixes
  above.

**Considered and declined (with reasoning):**
- **Change `habitat_col` to a logical flag + require specific column names, matching
  `lat`/`lon`'s treatment**: declined, with the strongest reasoning of any item in this
  review response. `habitat_col`'s current `character-or-NULL` design is not incidental --
  it is the direct, deliberate fix for a real, previously-shipped bug (documented at
  length in this function's own `@details`, in `train_biodiversity_model()`'s `@details`,
  and in `TaxaExpect/CLAUDE.md`'s session history for 2026-07-03): passing a single
  hardcoded placeholder habitat value used to break `train_biodiversity_model()`'s Tier 2
  fit outright ("contrasts can be applied only to factors with 2 or more levels"). The
  `NULL`-means-opt-out convention was specifically chosen, and then propagated
  consistently to `optimize_grid_size()`, `train_biodiversity_model()`,
  `generate_undetected_diversity()`, and `generate_full_priors()`, precisely so a caller
  without a real habitat classification has one obviously-correct way to say so rather
  than being tempted back toward the broken placeholder pattern. A logical flag would
  still need a follow-up "and what's the column named" answer, i.e. it doesn't remove the
  configurability question, it just adds a second parameter to express the same thing this
  design already expresses in one.
- **"Is having `train_biodiversity_model_by_group` worth having?"**: see that function's
  own section below (the identical question is asked there too).

**Addendum, 2026-09-09:** `prepare_model_dataframe()` itself, along with the rest of the
GLMM grid/prior-fitting chain, was archived this session (source + tests moved intact to
`archive_glmm_prior_pipeline/`) once every real production workflow finished migrating to
the kernel-priors path (`estimate_kernel_priors()`). The `habitat_col` design defense
above remains an accurate record of why that choice was made at the time and is not being
revisited or overturned -- it is simply no longer live code. The kernel path's own
`estimate_kernel_priors()` takes a required `site_habitat` argument instead (no `NULL`-
means-opt-out convention, since the kernel estimator has no equivalent GLMM-contrasts
failure mode to guard against). See `TaxaExpect/CLAUDE.md`'s 2026-09-09 top session note
and `ecosystem_docs/NAME_CHANGE_HISTORY.md` for the full archival record.

### `recover_demoted_species.R`

Not flagged with any file-specific comments in the review (only marked "reviewed"). No
changes made.

### `report_priors.R`

Not flagged with any file-specific comments in the review (only marked "reviewed"). No
changes made.

### `screen_spatial_formula.R`

**Fixed:**
- `moran_present`/`spatial_present` renamed to `moran_terms`/`spatial_terms` throughout --
  both hold **character vectors of term names**, not logicals, and the `_present` suffix
  reads as boolean. Directly implements the reviewer's own suggested fix ("If the names
  are what is needed suggest renaming to something like `moran_names` or something").
  Purely internal local variables, zero external impact.
- `aic_vals[!na_aic] - min(valid_aic)` simplified to `valid_aic - min(valid_aic)` --
  `valid_aic <- aic_vals[!na_aic]` is computed on the immediately preceding line; the
  original re-subset the same values a second time instead of reusing the variable it had
  just created for exactly this purpose.
- New `@details` paragraph explaining what "Tier 1" means in this function's own
  documentation (previously only defined in `train_biodiversity_model()`'s docs, which a
  reader of `?screen_spatial_formula` alone wouldn't necessarily have open) -- answers
  "what is Tier 1, exactly?"

**Considered and declined (with reasoning):**
- **Renaming the function** ("it makes it seem like it's doing something to the formula
  specifically... perhaps this should be...?"): declined. The function genuinely does
  screen and select among candidate spatial formulas by VarCorr SD and AIC -- the current
  name accurately describes its behavior. It is also already referenced by name in
  `TaxaID/CLAUDE.md`'s Recent Breaking Changes table (as recently as the 2026-08-03
  `depth_m_s` generalization fix) and throughout this package's own documentation;
  renaming a function this freshly and heavily cross-referenced for a subjective naming
  preference, with no correctness benefit, was judged not worth the churn.
- **Separating model training and selection into two functions**: declined. The combined
  design (fit + screen + select, returning one ready-to-use recommended model) is
  deliberate and matches this ecosystem's broader convention of returning directly-usable
  objects rather than intermediate artifacts a caller must manually recombine (e.g.
  `TaxaAssign::posterior_consensus()`). Splitting it would mean every one of this
  function's real call sites (`build_priors.R`, `inst/TaxaExpect_workflow.R`, 2 real
  `inst/workflows/` scripts, and 3 real external PtConception production workflow scripts)
  would need to orchestrate two calls instead of one, for a code-organization preference
  rather than a fixed defect.
- **Example not runnable**: left `\dontrun{}` -- needs a real fitted `model_df` with Moran
  basis columns already joined.

### `TaxaExpect-package.R`

Not flagged with any file-specific comments in the review. No changes made.

### `train_biodiversity_model.R`

**Fixed:**
- New `grid_size` slot added to `$meta` (from `attr(data, "grid_size")`) -- the other end
  of the cross-cutting `grid_size` propagation chain described above. `@return`
  documentation updated to describe it.
- Session/date reference removed from one roxygen `@section` header -- see Cross-cutting
  fixes above.

**Already correct, no change needed:**
- "Tier 1 is not explained until line 117" -- checked against the current file: Tier 1 is
  defined in the very first `\describe{}` block of the function's own `@description`,
  immediately after the opening paragraph. This may have been true of an earlier version
  of the file; not reproducible now.
- "Line 359: what if they use a different column name? Column name control is loose at
  times" (the hardcoded literal `"sampling_group"` string in the multi-group-refusal
  check) -- verified this is correct, not loose: `"sampling_group"` is not a
  user-configurable input column name here, it is the **fixed output column name**
  `prepare_model_dataframe(sampling_group_col = ...)` always writes internally,
  regardless of what the caller's own input column was called (that configurable name is
  `sampling_group_col`, a completely different thing). Hardcoding the literal output name
  of an internal contract between two functions in the same package is correct;
  "column name control is loose" would be a fair criticism if this were reading a
  user-supplied name, but it isn't.

**Considered and declined (with reasoning):**
- **Example not runnable**: left `\dontrun{}` -- needs `prepare_model_dataframe()`'s
  output and fits a real glmmTMB model.

### `train_biodiversity_model_by_group.R`

**Fixed:**
- Session/date reference removed from one roxygen `@section` header -- see Cross-cutting
  fixes above.

**Considered and declined (with reasoning):**
- **"Isn't this just iterating over existing functions? Could this replace
  `train_biodiversity_model.R` with a `groups` argument?"**: declined, for two concrete
  reasons already documented in this function's own roxygen (`@section Groups that fail to
  fit are dropped, not fatal`) but worth restating directly: (1)
  `train_biodiversity_model()` *deliberately refuses* multi-group data as a safety check
  (see that function's own `@section Multi-group data is refused`) specifically so a
  careless caller cannot silently pool incommensurable detection processes into one shared
  effort denominator -- folding grouping into that same function via a `groups=` argument
  would mean the function doing the refusing is also the function doing the thing it
  refuses, undermining the safety check's own point. (2) This wrapper does real,
  non-trivial work beyond iteration: per-group `tryCatch()` isolation (one group's fitting
  failure -- a real, observed failure mode with unevenly-sized real broad-marker data --
  does not take down every other group's result), and independent per-group covariate
  re-scaling via `prepare_model_dataframe()` (each group needs its own center/scale, not a
  shared one computed across groups then split). A `groups=` argument on
  `train_biodiversity_model()` would need to absorb both of these to be equivalent, at
  which point it would just be this function under a different name.
- **Example not runnable**: left `\dontrun{}` -- needs real occurrence data spanning
  multiple sampling groups.

**Addendum, 2026-09-09:** the question this section opens with -- "Is having
`train_biodiversity_model_by_group` worth having?" -- was answered concretely this
session, not just argued through in the abstract. A full usage audit (bulk grep across
every real production workflow and every cross-package/same-package R call, plus a
targeted follow-up specifically checking whether `PtConceptionWorkflow_18S_2_single_site.R`
-- the exact "broad-marker data spanning multiple detection processes" scenario this
function's own roxygen called its "recommended entry point" for -- actually calls it)
found **zero real callers anywhere**, including in that one workflow: it hand-rolls its
own per-group loop (`prepare_model_dataframe(sampling_group_col=)` then a manual loop
calling `screen_spatial_formula()`/`train_biodiversity_model()` per group with its own
`tryCatch()`), which turns out to be a strict superset of what this function did (it adds
AIC-based formula screening this function had no equivalent for). So the two reasons given
above for keeping this function separate from `train_biodiversity_model()` were sound
architecture, but the function itself was built, never adopted, and its own target use case
evolved past it before anyone ever called it. Archived (source + tests moved intact,
DECIPHER-module retirement precedent) rather than deleted -- it remains fully functional
GLMM-path infrastructure, just not live; later the same day, the rest of the GLMM chain
was archived too and this function's own archive location was consolidated into that same
directory, `archive_glmm_prior_pipeline/` (the original, separate `archive_glmm_by_group/`
no longer exists). Superseded by `estimate_kernel_priors(sampling_group_col=)` (added
2026-09-03) on the kernel path, which restores per-group/multi-detection-process
stratification without needing a separate orchestrating wrapper. See
`TaxaExpect/CLAUDE.md`'s 2026-09-09 top session notes and `ecosystem_docs/NAME_CHANGE_
HISTORY.md` for the full record.

### `utils_plot.R`

**Considered and declined (cross-package, flagged for a future session):**
- **`.he()` (HTML-escaping helper) is also defined in TaxaHabitat -- "could this be
  defined once and referenced (i.e. in TaxaTools)?"**: a real, valid finding, but moving it
  requires (a) adding it to `TaxaTools` as a new exported-or-internal utility, (b)
  updating `TaxaHabitat` to remove its own copy and depend on the new one, and (c) updating
  this package the same way -- a genuinely cross-package change, not something to do
  unilaterally as a side effect of a TaxaExpect-scoped review response (the same
  reasoning already applied to the `data`-parameter-rename and package-combination
  questions above). Flagged here for a future dedicated pass, most naturally alongside the
  next TaxaTools/TaxaHabitat work.

------------------------------------------------------------------------

## Summary

| Category | Count |
|---|---|
| Real bugs fixed (broken example referencing non-existent parameters/functions; fragile `habitat_scheme[[1]]` column selection; stale `llm_fn` doc default) | 3 |
| DRY consolidations (new `R/utils_internal.R`: `.beta_mean()`/`.beta_sd()`, `.dark_diversity_rank_cols`, `.parse_grid_id_coords()`; plus `.assign_effort_flag()`, `.prepare_one_group()`) | 5 shared helpers, spanning 7 files |
| New capability (`grid_size` recorded + propagated across 4 functions; `compute_moran_basis(coords = )`) | 2 |
| Readability/naming fixes (`.run_one_group` extraction + pipe conversion, `moran_terms`/`spatial_terms` rename, `cov` -> `covariate`, `.score_one_resolution()` argument bundling, redundant `aic_vals[!na_aic]` simplification, "weird spaces") | 6 |
| Breaking signature change (`compute_adaptive_sampling_groups(min_n = )` now required) | 1, zero real callers affected |
| Examples fixed to be runnable/correct | 6 (`add_pca_covariates`/`apply_pca_transform`, `create_sites_from_grid`, `optimize_grid_size`, `compute_moran_basis`, `compute_adaptive_sampling_groups`, `prepare_model_dataframe`) |
| New tests | 6 (`.parse_grid_id_coords()`/`.truncate_label()`) + 5 (updated `.score_one_resolution()` call shape) + 2 (`compute_adaptive_sampling_groups()` `min_n` validation) |
| Items explicitly declined, with reasoning recorded above | ~20 |
| Cross-package findings flagged, not fixed here | 2 (`TaxaHabitat`'s "0 site(s) assigned 'Other'" message; `.he()` duplicated in TaxaHabitat) |

`devtools::test()`: 555 expectations, 0 failures (up from 538). `devtools::check()`: 0
errors, 0 warnings, 0 notes. Reinstalled to `~/Library/R/4.0/library`.

------------------------------------------------------------------------

------------------------------------------------------------------------

## Functions added or modified since this review (through 2026-09-07)

The functions below were added or modified after this review's own date
(above), in response to client requests and/or fixes identified during
testing against real production data, consistent with USGS code review
policy. Each was individually code-reviewed against the same checklist
used above (functionality, coding standards, vulnerabilities, and -- where
applicable -- domain/scientific reasonableness) as part of this software
release.

- `.beta_mean`
- `.beta_sd`
- `.empty_undetected_evidence_result`
- `.glmm_deprecation_notice`
- `.parse_grid_id_coords`
- `.prepare_one_group`
- `.resolve_evidence_groups`
- `.resolve_gbif_taxon_key`
- `.resolve_gbif_taxon_keys_batch`
- `.resolve_group_prices`
- `.score_one_resolution`
- `.theta_surface_accumulate`
- `.theta_surface_apply_mask`
- `.theta_surface_axis`
- `.theta_surface_bbox`
- `.theta_surface_bin_index`
- `.theta_surface_condition_label`
- `.theta_surface_downsample`
- `.theta_surface_downsample_matrix`
- `.theta_surface_engine`
- `.theta_surface_fft_convolve`
- `.theta_surface_fft_convolve_batch`
- `.theta_surface_in_polygon`
- `.theta_surface_kernel`
- `.theta_surface_plot_leaflet`
- `.theta_surface_plot_static`
- `.theta_surface_raster`
- `.theta_surface_wkt_to_polys`
- `.translate_to_gbif`
- `add_pca_covariates`
- `apply_undetected_evidence`
- `build_priors`
- `calibrate_kernel_bandwidth`
- `compute_adaptive_sampling_groups`
- `compute_moran_basis`
- `create_sites_from_grid`
- `estimate_kernel_priors`
- `fit_regional_presence_curve`
- `generate_domestic_food_priors`
- `generate_full_priors`
- `generate_inat_range_evidence`
- `generate_invasive_watch_evidence`
- `generate_presence_curve_evidence`
- `generate_regional_proximity_evidence`
- `generate_undetected_diversity`
- `generate_user_specified_evidence`
- `kernel_budget_sensitivity`
- `optimize_grid_size`
- `plot_theta_map_interactive`
- `plot_theta_surface`
- `prepare_model_dataframe`
- `print.taxaexpect_kernel_budget_sensitivity`
- `print.taxaexpect_kernel_priors`
- `print.taxaexpect_theta_surface`
- `report_priors`
- `rewrite_habitat_formula`
- `screen_spatial_formula`
- `train_biodiversity_model`
- `train_biodiversity_model_by_group`

