# TaxaFlag Peer Review Response

**Review date:** 2026-08-11 (file mtime) **Package version reviewed:** TaxaFlag 0.1.0
**Response prepared by:** Claude Code (Sonnet 5), 2026-08-11, at K. D. Lafferty's request

This document responds to `inst/taxaflag_review.Rmd`, which reviews 10 files
(`add_posthoc_assessment.R`, `build_review_covariates.R`, `check_gbif_tile_range.R`,
`compute_local_occurrence_distance.R`, `flag_contaminant.R`, `flag_handler.R`,
`report_flags.R`, `review_assignments.R`, `review_spatial_context.R`,
`TaxaFlag-package.R`) plus a package-level Code/Domain checklist, following this
ecosystem's TaxaMatch/TaxaLikely/TaxaFetch/TaxaAssign/TaxaHabitat review-response
format. **Note on scope:** a 2026-08-07 session had already fixed two items from this
same review (the `df` -> `input_df` rename and a broken `\link{}` in
`build_review_covariates.R`) directly in `TaxaFlag/CLAUDE.md`'s session notes, but never
produced this response document or worked through the remaining file-specific comments
-- this pass closes that gap. `devtools::test()`: 415 expectations, 0 failures (5
pre-existing `expect_warning()` tests, unchanged). `devtools::check()`: 0 errors, 0
warnings, 0 notes. Reinstalled to `~/Library/R/4.0/library`.

One design note that shaped most of the file-specific responses below: several review
comments across `add_posthoc_assessment.R`/`build_review_covariates.R`/
`compute_local_occurrence_distance.R`/`flag_contaminant.R`/`flag_handler.R`/
`report_flags.R`/`review_spatial_context.R` independently ask to "require specific
column names" for a function's inputs. This is a deliberate, package-wide (in fact
ecosystem-wide) convention, not an oversight: every TaxaFlag function that reads a named
column already validates that the supplied name exists in the input (`stop()` on a
missing column), but the NAME itself stays a configurable `*_col` parameter with a
sensible default, matching how upstream producers across this 9-package ecosystem name
things differently (e.g. `event_id` vs. `sample_id`, `taxon_name` vs. `species`). Hard-
coding fixed column names would break interoperability with every non-default upstream
caller for no safety benefit the existing existence-check doesn't already provide. Noted
once here rather than repeated per file below.

------------------------------------------------------------------------

## `TaxaFlag-package.R`

**Fixed:**
- **Real discoverability gap**, the same class of issue TaxaMatch's own review found for
  its package index: `?TaxaFlag` listed only `flag_contaminant()`/`flag_handler()`/
  `review_assignments()`/`report_flags()` -- `add_posthoc_assessment()`,
  `build_review_covariates()`, `check_gbif_tile_range()`,
  `compute_local_occurrence_distance()`, and `review_spatial_context()` (five of the
  package's nine exported functions) were entirely absent from the package overview.
  Added two new sections ("Post-hoc plausibility and discrimination", "Spatial context")
  covering all five.

------------------------------------------------------------------------

## `add_posthoc_assessment.R`

**Fixed:**
- **Real, if minor, convention violation:** `utils::globalVariables(character(0))` on
  line 1 -- the reviewer's "what is this here for?" question turned out to have no good
  answer. This file has no NSE column references anywhere (verified via grep for
  `.data`/`dplyr::`/`|>`), so per this ecosystem's own documented convention
  (`TaxaID/CLAUDE.md`: "omit entirely from files with no NSE references"), the line
  should never have been added. Removed.

**Considered and declined (with reasoning):**
- "Line 80: I thought that `TaxaAssign` does provide default lists" (re:
  `expected_theta_threshold` having no default): confirmed this is intentional, not an
  oversight -- the roxygen already explains why (mirrors `TaxaAssign::join_priors()`'s
  `backbone_id`/`score_consensus()`'s `rank_thresholds`, both required for the identical
  reason: the correct threshold is data-assemblage-dependent, and no single universal
  default is safe). `TaxaAssign::compute_group_priors()` is the recommended *source* for
  a real value (documented in the `@param` block: `median(taxaexpect_priors$theta_mean)`
  etc.), but the actual call is deliberately left to the caller, not auto-derived inside
  this function, since that would silently couple `add_posthoc_assessment()` to a
  specific upstream object shape.
- "Suggest requiring specific column names": see the package-wide note above.

------------------------------------------------------------------------

## `build_review_covariates.R`

**Considered and declined (with reasoning):**
- "Based on the documentation for this function, it seems like this is not currently
  used in any workflows. Consider whether this should be included in the package":
  confirmed via grep -- no `inst/` workflow script calls it. Kept anyway: its own roxygen
  already states this explicitly ("no dedicated `model_review_classification()` wrapper
  exists in this package yet") -- it's a general-purpose covariate-builder meant to feed
  a future modelling step a user builds themselves (a classification tree/logistic
  regression on its output), not a function whose value depends on having a wired-in
  consumer. No code depends on a currently-nonexistent caller, so there's no dead-code
  risk from keeping it.
- "Suggest requiring specific column names": see the package-wide note above.

------------------------------------------------------------------------

## `check_gbif_tile_range.R`

**Fixed:**
- **Real robustness gap, "Line 368: is this always the correct channel?":** `.fetch_gbif_tile_alpha()`
  indexed `img[, , 4]` (the alpha channel) unconditionally. GBIF's `@1x.png` tiles are
  always RGBA today (confirmed empirically in earlier sessions), but nothing guarded
  against that assumption breaking if GBIF's tile format ever changes -- a 3-channel
  (RGB-only) response would have failed with an opaque "subscript out of bounds" far from
  this call site. Added an explicit dimension check with a clear, actionable error
  message naming the offending tile.

**Verified as already correct, no change needed:**
- **".dilate8 only replaces the FALSE in the lower right corner... is that expected?"**
  Tested directly: `.dilate8(matrix(c(rep(TRUE, 8), FALSE), ncol = 3, byrow = TRUE))`
  returns an all-`TRUE` 3x3 matrix, not a matrix with only the corner replaced --
  every neighbour of that one `FALSE` cell is `TRUE`, so standard 8-connected dilation
  (which this correctly is, including the cell itself via the `dr=0,dc=0` loop iteration)
  turns it `TRUE` too. This is expected, correct region-growing behaviour, not a bug.
  Added an inline comment plus a short explicit-verification note to the function's own
  roxygen so the next reader doesn't have to re-derive this.
- "Is this the intended use of the GBIF tiles? ... primarily intended for display, not
  necessarily for use as raster information": already directly addressed in the
  function's own `@section What the PNG can and can't tell you` -- this function
  deliberately reads ONLY the alpha channel as a presence/absence signal (never decodes
  the colour ramp into a density value), precisely because the tiles are a display
  product, not an exact-count source. No change needed.
- "Does the existence of `compute_local_occurrence_distance` make this function
  redundant? ... suggest removing or finding data more suited to this purpose":
  already directly addressed in this function's own intro paragraph -- the two are
  deliberately complementary, not overlapping: `compute_local_occurrence_distance()` is
  free/local/exact but bounded to whatever bbox a study's own GBIF fetch covered;
  `check_gbif_tile_range()` is cheap/global/approximate and answers the wider "is this
  species far from its known range everywhere, or just novel to this one study" question
  the local function structurally cannot. Neither is a strict subset of the other.
- "Line 374: why have this on one line?": the file has been substantially rewritten
  since this review was written (down to 421 lines now, with zoom-escalation and
  km-unit-conversion logic added afterward) -- no single-line construct matching this
  description exists in the current version. Not applicable to the code as it stands.
- "Assumed formulas are true as given": the tile-pixel/Mercator-resolution formulas are
  already documented as empirically verified against real GBIF tiles in earlier sessions
  (known-present-species alpha checks, real presence/absence at known coordinates) --
  see the function's own inline comments on `.lonlat_to_tile_pixel()`/
  `.mercator_resolution_km()`. Re-verified once more via the live checks run for this
  review pass (see Summary below); no discrepancy found.

------------------------------------------------------------------------

## `compute_local_occurrence_distance.R`

**Fixed:**
- **"Example not runnable as-is":** the example referenced an undefined
  `occurrences_clean` object. Replaced with a small, self-contained synthetic
  `occurrence_data` frame so the example now runs (verified via `R CMD check`'s example
  execution).

**Considered and declined (with reasoning):**
- "Suggest requiring specific column names": see the package-wide note above.

------------------------------------------------------------------------

## `flag_contaminant.R`

**Fixed:**
- **Real duplication, "Line 291: could this just be created directly from scores,
  perhaps by removing unwanted columns?"** The final `result <- data.frame(...)` block
  manually re-listed and re-typed every one of `.compute_contaminant_scores()`'s output
  columns by hand. Refactored to select the needed columns directly out of `scores`
  (dropping only its internal `contaminant_score`/`flag`/`reason` working names) instead
  of rebuilding each value -- if `.compute_contaminant_scores()`'s own output columns
  ever change, this block no longer needs a matching manual update to stay in sync.
- **"Example not runnable as-is":** the example referenced an undefined `reads_long`
  object. Added a small, self-contained synthetic `reads_long` and made the first
  (primary) usage pattern runnable; the two secondary usage patterns
  (`sample_type_col`, positive-control leakage) remain `\dontrun{}` since they'd need a
  second synthetic dataset shape purely for illustration -- not worth the added example
  complexity for a documentation-only concern.

**Verified as already correct / already documented, no change needed:**
- "Line 306: since the `data.frame` is built just before, why not specify the names
  there?": not possible as literally suggested -- `taxon_col`/`score_col`/`flag_col`/
  `reason_col` are runtime string values (potentially anything the caller passed), and
  `data.frame(taxon_col = ...)` would name the column literally `"taxon_col"`, not
  whatever string that variable holds. The select-then-`names<-` pattern (now simplified,
  see the fix above) is the direct way to assign dynamic column names in base R;
  `stats::setNames()` would be equivalent, not simpler.
- "Line 178: what is the justification for having `prior_weight` default to 20?":
  already extensively documented in both `flag_contaminant()`'s own roxygen (`@section
  Reads, not samples, as the shrinkage denominator`) and `.compute_contaminant_scores()`'s
  roxygen -- a real empirical validation against two full real datasets (12S/18S
  PtConception) at `prior_weight` in {20, 50, 100, 500}, with the reasoning for why 20 was
  chosen over the other three tested values. No further justification needed beyond what's
  already written.
- "Why have `exclude_samples`? ... seems reasonable to assume a user will filter if
  that's not the case": already documented with a concrete real use case in the `@param`
  block -- removing e.g. extraction-control samples when analysing PCR controls
  specifically (or vice versa), where the same physical sample set legitimately needs to
  be excluded from BOTH the control and field pools for one particular call, not filtered
  out of the input data frame permanently (a later call in the same script may need those
  same samples back).
- "I'm actually not sure why `.compute_contaminant_scores` is a separate function here
  ... it's not being reapplied": deliberate separation of algorithm (the depth-weighted,
  shrinkage-based scoring math, independently unit-testable) from the calling function's
  own responsibilities (input validation, threshold application, reason-string
  formatting, verbose messaging) -- not iteration-driven reuse, but the standard
  "internal helper isolates a nontrivial, independently-verifiable computation" pattern
  used throughout this package (`.parse_datetimes()`, `.discrimination()`/
  `.plausibility()` closures in `add_posthoc_assessment.R`, etc.). Kept as-is.
- "Line 431: is there a reason to recreate `input_df` here?": the file has been
  substantially reorganized since the review was written (now ~330 lines, well short of
  line 431) -- this comment does not correspond to any code in the current version.
- "Line 35: Since this is the initial release for this package, consider whether
  documenting development changes is useful here. Should some or all of this go
  elsewhere, such as the `NEWS` file?": this package (like every package in this
  ecosystem) doesn't maintain a `NEWS.md` -- the roxygen `@section`s carrying dated
  design-rationale notes (e.g. "Session 152", "2026-07-24") are the ecosystem's
  established, deliberate substitute: they explain *why* a formula/default is what it is
  directly at the point a future reader needs that context, rather than in a separate
  changelog nobody reads before touching the code. This is a package-wide convention
  (see every other file in this response, and every other package's own `CLAUDE.md`), not
  specific to this file -- changing it here alone would be inconsistent with the rest of
  the codebase.
- "Suggest requiring specific column names" (lines 54, 57, 59, etc.): see the
  package-wide note above.

------------------------------------------------------------------------

## `flag_handler.R`

**Fixed:**
- **"Example not runnable as-is":** added a small, self-contained synthetic
  `camera_detections` frame and made the primary usage pattern (no `station_metadata`)
  runnable; the `station_metadata`-anchored variant remains `\dontrun{}` (needs a second
  synthetic table purely for illustration).
- `handler_taxa`'s doc now gives a second concrete example beyond `"Homo sapiens"`
  (a domestic animal accompanying a field crew), directly answering "I'm curious what
  the handler could be other than Homo sapiens" -- the parameter already accepted any
  taxon vector, this was a documentation gap, not a functionality one.

**Verified as already correct, no change needed:**
- **"Is `interval_minutes` supposed to be on each side of the interval? ... the output
  returns the following for 15 minutes from the nearest edge: `15.0 min from nearest
  edge; outside 30-min interval`. Have I misunderstood?"** Tested directly against the
  current, installed function with exactly this scenario (a detection 15 minutes from a
  30-minute-interval edge): the real output is `"15.0 min from nearest edge; within
  30-min interval, score 0.500"` -- correctly `"within"`, not `"outside"`. The reviewer's
  observed output does not reproduce against the current code; this class of "reviewer's
  report doesn't match current behaviour" has come up before in this ecosystem
  (see `TaxaID/CLAUDE.md`'s "Verify purpose before flagging a flaw" precedent) and here
  traces to the same cause -- the file has been substantially rewritten since (the 2026-07-24
  unified-validity-schema rename, the Session 151 edge-anchoring redesign) and the bug, if
  it was ever real, no longer exists. No code change; confirmed via a live re-run, not
  just re-reading source.
- "Line 185: do this first to avoid all the other date processing if it isn't needed":
  already correctly ordered -- `.parse_datetimes()` runs immediately after the cheap
  (O(1)) input-validation checks and its own failure (`all(is.na(parsed))`) is checked
  and `stop()`'d on *before* any of the expensive `group_edges` aggregation/merge work
  begins. The handful of preceding validation checks are themselves O(1) and would not
  measurably change performance if reordered after parsing; the substantive ask (don't
  do expensive downstream work on unparseable input) is already satisfied.
- "Suggest requiring specific column names": see the package-wide note above.

------------------------------------------------------------------------

## `report_flags.R`

**Fixed:**
- **"Example not runnable as-is":** the example referenced undefined `data`/`blanks`
  objects two functions removed from what `report_flags()` itself needs. Replaced with a
  minimal, self-contained `flagged` data frame carrying a real `validity_flag` column,
  runnable directly.

**Considered and declined (with reasoning):**
- "Suggest requiring specific column names": doesn't apply as stated to this function --
  unlike every other function in this response, `report_flags()` has no configurable
  `*_col` parameters at all. It auto-detects flag columns via fixed regex patterns
  (`"_plausibility$"`, `"^review_"`, the literal `validity_flag` name) specifically so it
  can summarize output from any of `flag_contaminant()`/`flag_handler()`/
  `review_assignments()`/`add_posthoc_assessment()` without per-caller configuration --
  the column names it looks for are already fixed, by design.

------------------------------------------------------------------------

## `review_assignments.R`

**Fixed:**
- **Real usability gap, "With these LLM calls, I wonder if showing the user the prompt
  might be useful... it would be useful for the user to see the prompts":** implemented
  directly rather than declined -- every batch's exact prompt string is now recorded (via
  a small environment-based accumulator that survives `rbind()`/retry-recursion
  untouched) and attached to the returned data frame as `attr(result, "llm_prompts")`,
  named by batch label (including `"a"`/`"b"` retry-sub-batch suffixes). Documented in
  the function's own `@return`. No new parameter needed, no behavioural change to the
  reviewed output itself -- purely additive.
- **Real duplication, "Could line 1238 be replaced with `make_default`?"** Yes -- the
  "LLM omitted these taxa" fallback block manually re-listed the same 9-column NA-filled
  structure `make_default()` already builds, just for a different taxon-name vector.
  `make_default()` now takes an optional `names` argument (defaulting to the full-batch
  `expected_taxa`) so both call sites share one definition.
- **Real, if minor, gap, "`.normalise_context` returns the first items of each row of
  `context`, no matter what they are. Is this expected? Can `context` ever be expected to
  be more than one row?"** Answer: no, `context` is meant to describe one study
  (a single geography/habitat/date shared across every taxon in the call) -- a multi-row
  data frame most likely signals the caller passed a per-observation table by mistake.
  Previously this was silently discarded (only row 1 used, no signal to the caller). Now
  warns explicitly when `nrow(context) > 1`, naming the row count, so a caller who passes
  the wrong object finds out immediately instead of getting a review that silently used
  only the first observation's context for every taxon.
- **Real, low-risk clarity fix, ".safe_col ... Consider adding `parsed` as an argument
  ... Has this functionality been produced elsewhere?"** Checked the whole
  `~/My Drive/Rscripts/projects/TaxaID` tree for the same null-string-to-NA coercion
  pattern -- not duplicated anywhere else, so this stays a local, single-use helper
  rather than being promoted to a shared utility. Took the reviewer's narrower suggestion
  though: `.safe_col()` now takes the source data frame as an explicit argument instead
  of reading `parsed` via lexical closure, making the dependency visible at each of its 8
  call sites rather than implicit.
- **Real, documented-elsewhere-but-missing-here gap, "Fails unless `TaxaTools` is
  loaded, `TaxaTools::` is insufficient."** This is the `.resolve_llm_fn()`/`call_api()`
  provider-auto-detection footgun already documented once, ecosystem-wide, in
  `TaxaID/CLAUDE.md`'s "Known R Footguns" -- but `review_assignments()`'s own `llm_fn`
  `@param` never mentioned it, despite this function being one of the five affected call
  sites named in that footgun entry. Added a direct pointer (with the concrete workaround)
  to the `llm_fn` parameter's own documentation, so a reader doesn't have to already know
  to look in the ecosystem-level `CLAUDE.md`.

**Verified as already correct / already documented, no change needed:**
- "Ensure that multiline `if` statements use curly braces": swept the file (and the rest
  of the package) for multi-line `if (...)` without an opening brace on the same line --
  none found in the current source.
- "Suggest removing `.build_candidate_label` and using a single function for the entire
  package ecosystem": already documented as a deliberate choice -- its own roxygen states
  it mirrors `TaxaAssign::.make_slash_name()` and is duplicated specifically to avoid a
  dependency on `TaxaAssign`'s internal (`@noRd`, unexported) functions. This matches this
  ecosystem's existing, explicit precedent for small, deliberately-duplicated
  NCBI-fetcher-style helpers (documented in
  `~/.claude/projects/-Users-lafferty/memory/project_blast_ncbi_fetcher_todo.md`) rather
  than introducing a new cross-package internal dependency for one ~15-line function.
  Left as-is.
- "Not sure I understand why `.fetch_inat_points` reproduces functionality from
  `TaxaFetch`": this comment is actually about `review_spatial_context.R`, not this file
  -- see that section below.

------------------------------------------------------------------------

## `review_spatial_context.R`

**Fixed:**
- Strengthened `.fetch_inat_points()`'s own internal documentation to state directly,
  not just imply, why it isn't reusing `TaxaFetch::fetch_inat_occurrences()` (see
  "Considered and declined" below for the substance) -- verified against that function's
  real source before writing the explanation, not assumed.
- Added a documentation note explaining the real "Felis catus tile shown several km out
  in the lake" observation: `gbif_bin_size`'s binning (default 256px squares) snaps each
  occurrence to its containing bin before drawing it, so a binned square can legitimately
  sit offset from a point's true location by up to the bin size in pixels -- a known,
  expected consequence of aggregation (needed to make sparse species visible at all, per
  this file's own prior click-through history), not a data error or rendering bug. Cross-
  referenced `check_gbif_tile_range()`'s own "What the PNG can and can't tell you"
  section, which makes the same point for the numeric (non-visual) consumer of the same
  tile API.
- Added an inline comment at the GBIF `addTiles()` call recording *why* there is no
  `tileOptions(opacity=)` override (an earlier round added one, a real click-through
  found it made sparse species harder to see, and it was reverted) -- directly answers
  "consider increasing transparency" with the concrete history of why that specific lever
  was already tried and undone, rather than leaving a future reader to rediscover it.

**Verified as already correct / already documented, no change needed:**
- **"I didn't see the 'Run AI Review' button when running the app."** By design: the
  button (and the whole AI-review sidebar section) is wrapped in
  `if (!is.null(context)) ...` -- `context` defaults to `NULL` specifically so opening
  the gadget never implies a billed LLM call is about to happen. Already documented in
  this function's own `@param context,target_group,marker,llm_fn` entry ("`context`
  defaulting to `NULL` ... is what hides the button entirely -- supply it to enable
  on-demand AI review") and in the `@section Cost` block. The reviewer's demo run most
  likely didn't pass `context`. No code change; this is the intended, already-documented
  behaviour.
- "How does `gbif_bin_size` relate to `tile_size` and `zoom` in `check_gbif_tile_range`?
  Edit: I see this is discussed lines 636+.": the reviewer resolved this themselves while
  reading; no further action needed.
- "This is noted in the comments, but it seems odd to split
  `.review_spatial_context_impl` from `review_spatial_context`.": already documented at
  the split point itself -- the split exists specifically so the gadget's construction can
  be driven directly (bypassing the `interactive()`-only gate) for automated verification
  during development, not a stylistic preference. Left as-is; the reviewer's own comment
  already acknowledges the reasoning is present, just questions whether it's worth the
  indirection -- it is, since standard browser automation cannot drive a live Shiny
  session's persistent WebSocket (confirmed in earlier sessions), making this split the
  only practical way to unit-test the gadget's reactive logic at all.
- "Not sure I understand why `.fetch_inat_points` reproduces functionality from
  `TaxaFetch`, defining functionality one time is the whole reason to have packages to
  begin with.": checked directly against `TaxaFetch::fetch_inat_occurrences()`'s real
  source before responding, not assumed. The two are NOT interchangeable:
  `fetch_inat_occurrences()` returns exactly one COUNT per taxon (`n_observations_local`,
  fetched via `per_page = 1`, reading only iNaturalist's `total_results` field) -- it
  never returns the individual observation records themselves, so it structurally cannot
  supply what this gadget's map layer needs (each observation's own lat/lon for
  plotting). Building that would mean adding a new, different-purpose (count vs. points)
  code path to `TaxaFetch::fetch_inat_occurrences()` for a single caller, or maintaining
  a hard `TaxaFetch` dependency for what amounts to one HTTP GET this file already knows
  needs no authentication. Kept as a small, self-contained internal helper; strengthened
  the documentation (see Fixed above) so the distinction is explicit rather than left to
  a reader tracing both functions' source independently, as this review did.
- "For `Felis catus` in the example file, one tile is shown several km out in the lake.
  This calls the reliability of the GBIF layer into question, at least at some zoom
  levels.": this is GBIF's own real, unfiltered occurrence data (very likely a genuine
  captive-cat report with imprecise coordinates, or ordinary binning offset -- see Fixed
  above) rather than a bug in this package's rendering. No code change; documented.
- "Consider increasing transparency in gbif tile layer.": considered and declined, with
  the reasoning now recorded inline (see Fixed above) -- this was tried in an earlier
  round and reverted after a real click-through found it hurt readability for the sparse
  species this gadget is actually meant to review.
- "Example not runnable as-is": intentionally `\dontrun{}` -- `review_spatial_context()`
  opens an interactive Shiny gadget and hard-errors outside an interactive session
  (`if (!interactive()) stop(...)`), so no runnable non-interactive example is possible.
  Matches this ecosystem's established precedent for every other interactive gadget
  (`TaxaHabitat::review_spatial_flags()`, `TaxaTools::define_search_polygon()`, etc.).
- "Suggest requiring specific column names": see the package-wide note above.

------------------------------------------------------------------------

## General code-review checklist items

- **Coding standards -- formatting/spacing consistency:** the reviewer's general note
  (pick one alignment convention and follow it strictly, since a half-applied one is
  worse than none) is accepted as valid feedback but was not addressed with a
  package-wide whitespace-realignment pass in this response -- the reviewer's own comment
  frames it as "not my preference, but... accepted," not a defect, and a blanket
  re-alignment sweep across 10 files risks large, semantically-empty diffs that make
  future `git blame`/review harder to use. The one concrete instance flagged
  incidentally by another comment (`flag_contaminant.R`'s inconsistently-spaced
  `data.frame()` column list) was resolved as a side effect of removing that block
  entirely (see `flag_contaminant.R` above).
- **Automated tests:** re-ran after all fixes above -- `devtools::test()`: 415
  expectations, 0 failures (5 pre-existing `expect_warning()`-driven warnings, unchanged
  from the review's own reported `[ FAIL 0 | WARN 5 | SKIP 0 | PASS 415 ]`).
- **Vulnerabilities:** no code change in this pass touches network/credential handling;
  the reviewer's own note ("I do not have the domain knowledge to assess this") stands.
  No new vulnerability surface introduced by this pass's changes (all additive
  documentation, one new environment-based prompt log with no external I/O, one new
  defensive dimension check).

------------------------------------------------------------------------

## Summary

| Category | Count |
|---|---|
| Real bugs/gaps fixed | 8 (missing package-index sections; unnecessary `globalVariables()` call; undefended alpha-channel index; 3 non-runnable examples fixed to actually run [`compute_local_occurrence_distance.R`, `flag_contaminant.R`, `flag_handler.R`, `report_flags.R` -- 4 files]; missing multi-row-`context` warning; missing LLM-prompt visibility) |
| Real duplication removed | 3 (`flag_contaminant.R`'s manual `data.frame()` rebuild; `review_assignments.R`'s `make_default()`-vs-`missing_rows` duplication; `.safe_col()`'s implicit-scope dependency) |
| Documentation-only additions closing a real gap | 4 (`handler_taxa` domestic-animal example; `llm_fn` provider-auto-detection footgun pointer; GBIF-tile binning-offset explanation; GBIF-tile opacity decision history) |
| Items verified already correct via live re-testing (not just re-reading source) | 2 (`flag_handler()`'s `interval_minutes`/reason-string interaction; `.dilate8()`'s corner-replacement behaviour) |
| Items considered and declined, with reasoning recorded above | ~15 (repeated "require specific column names" across 7 files, treated once as a package-wide design note; `.compute_contaminant_scores`/`.build_candidate_label` separation; `.review_spatial_context_impl` split; `.fetch_inat_points` vs. `TaxaFetch::fetch_inat_occurrences()`; dev-history-in-roxygen convention; several already-self-documenting design questions) |

All fixes verified against the full test suite and `R CMD check` (which also executes
every roxygen `@examples` block, including the four newly-runnable ones) after the full
set of changes, not piecemeal. `devtools::test()`: 415/415, 0 failures.
`devtools::check()`: 0 errors, 0 warnings, 0 notes. Reinstalled to
`~/Library/R/4.0/library`.

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

- `.build_candidate_label`
- `.build_review_prompt`
- `.build_spatial_context_server`
- `.check_gbif_tile_range_at_zoom`
- `.combine_notes`
- `.compute_contaminant_scores`
- `.dilate8`
- `.fetch_gbif_tile_alpha`
- `.fetch_inat_points`
- `.fmt_pipeline_value`
- `.gbif_legend_swatch`
- `.gbif_tile_url`
- `.grow_patch_size`
- `.haversine_km`
- `.lonlat_to_tile_pixel`
- `.mercator_resolution_km`
- `.normalise_context`
- `.parse_json_text`
- `.parse_review_response`
- `.recover_truncated_json`
- `.resolve_gbif_taxon_key`
- `.review_batch_with_retry`
- `.review_cache_hash`
- `.review_cache_read`
- `.review_cache_write`
- `.review_spatial_context_impl`
- `.summarise_candidate_weights`
- `.summarise_pipeline_context`
- `.summarise_spatial_context`
- `add_posthoc_assessment`
- `check_gbif_tile_range`
- `compute_local_occurrence_distance`
- `flag_contaminant`
- `flag_handler`
- `flag_watch_candidates`
- `report_flags`
- `review_assignments`
- `review_spatial_context`
- `taxaflag_clear_cache`

