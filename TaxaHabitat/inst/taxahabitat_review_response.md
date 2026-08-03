# TaxaHabitat Peer Review Response

**Review date:** 2026-08-01 **Package version reviewed:** TaxaHabitat 0.1.0 **Response prepared by:** K. D. Lafferty

This document responds to each comment in the TaxaHabitat code review (`inst/taxahabitat_review.Rmd`).
The review's own line-number references had drifted from the current source (the codebase has
been edited since the review was written, including an earlier 2026-07-28 review-prep pass
against a different, no-longer-present review document, `inst/Code and Domain Review 2.Rmd` --
see `TaxaHabitat/CLAUDE.md`). Every comment below was re-verified against the current source
before being accepted or rejected, not answered from the review's own stale line numbers.

------------------------------------------------------------------------

## Checklist Items

### Automated tests -- "some functions do not have tests"

**Partially fixed.** `parse_hierarchical_habitat_response()` had zero test coverage at all
(the review's own flagged bug lived here, untested) -- a new `tests/testthat/test-parse_habitat_response.R`
adds 33 tests, including a direct reproduction of the comma-corruption bug (see below).
`flag_habitat_inconsistencies()` gains its first tests too (`test-flag_habitat_inconsistencies.R`,
4 tests) covering the input-validation path that runs before any network call -- every other
code path in that function requires live Natural Earth + NOAA GEBCO downloads and has no offline
path at all, matching this ecosystem's own established precedent for genuinely network-bound
functions (e.g. `TaxaTools::verify_taxon_names()`/`census_genus_species()`, "online tests skipped
offline"). `review_spatial_flags()`/`review_institution_flags()` remain untested by design --
interactive Shiny/leaflet gadgets requiring a live session aren't unit-tested anywhere in this
ecosystem (an explicit, repeated precedent -- see `TaxaHabitat/CLAUDE.md`'s session notes).

### R (>= 4.1.0) dependency warning

**Fixed.** `DESCRIPTION` now declares `Depends: R (>= 4.1.0)` explicitly, matching the exact
pattern already used in `TaxaTools/DESCRIPTION` and `TaxaLikely/DESCRIPTION`. This was previously
only an auto-detected `R CMD build` warning (from `|>`/`\(...)` usage in `review_institution_flags.R`/
`review_spatial_flags.R`); it's now a stated, correct constraint.

### `adehabitatMA` S3-method-overwrite warning

**Investigated, confirmed transitive, documented (not a direct dependency, nothing to remove).**
Grepped `R/` for `adehabitatMA` -- zero hits. `DESCRIPTION`'s own Imports/Suggests do not list it
either. Traced the real source: `marmap` (a genuine, actively-used direct Import here, via
`flag_habitat_inconsistencies()`'s `getNOAA.bathy()`/`as.raster()` calls) lists `adehabitatMA` in
its own Suggests (confirmed via `packageDescription("marmap")`), and loading `marmap` triggers
`adehabitatMA`'s S3-method registration. This is exactly the reviewer's own hypothesis, now
confirmed rather than left as a guess. No action needed -- `marmap` is genuinely used and its own
transitive dependency choice isn't something this package controls.

### `data` is an existing R function -- rename throughout

**Fixed.** This is the same fix TaxaTools already made for its own `df` parameter (see that
package's response doc). Renamed the `data` parameter to `occurrence_data` in all five affected
exported functions: `assign_habitat_biological()`, `flag_habitat_inconsistencies()`,
`flag_institution_candidates()`, `review_institution_flags()`, `review_spatial_flags()` --
picked because all five operate on occurrence-level data specifically, not a generic table.
Every internal reference to the bound variable was renamed too (not just the formal parameter),
since these functions use `data` as their actual working variable throughout their bodies, not
just as an entry-point name. `data.frame(...)`/`is.data.frame(...)` calls were left untouched
(a careful regex excluded them). Local variables named `data` inside `consensus_habitat()`/
`.detect_habitat_cols()` (which take `habitats_df`, never `data`) were correctly left alone.

Grepped the **whole monorepo** for real named (`data = ...`) call sites and updated every one
found: `TaxaHabitat/tests/testthat/test-assign_habitat_biological.R` (5 sites),
`TaxaHabitat/vignettes/habitat-assignment.Rmd`, `TaxaHabitat/inst/Habitat_workflow.R`,
`TaxaHabitat/inst/workflows/assign_habitat_workflow.R` (2 sites, plus a prose comment referencing
the old name), `TaxaAssign/inst/workflows/camera_trap_posterior_workflow.R`,
`TaxaExpect/R/build_priors.R` (real package code, not a workflow script -- this one required a
`TaxaExpect` reinstall too), `inst/TaxaID_Workflow_Template_TEST.R`, and
`TaxaWizard/inst/graph/snippets/occ_to_std.R`. `TaxaWizard/inst/metadata/TaxaHabitat.json`'s two
`"name": "data"` input entries (for `assign_habitat_biological`/`flag_institution_candidates`)
were also updated to `"name": "occurrence_data"` -- per `TaxaWizard/CLAUDE.md`'s own explicit
rule that metadata parameter names must exactly match real function signatures. Positional-only
calls (e.g. `assign_habitat_biological(occurrences, habitats)` in
`TaxaAssign/vignettes/taxaid-ecosystem.Rmd`/`TaxaExpect/vignettes/building-priors.Rmd`) needed no
change. See `TaxaID/CLAUDE.md`'s Recent Breaking Changes table for this row.

### British spelling ("colour" not "color")

**Investigated, left as-is (not user-facing).** Every "colour"/"colours"/"colouring" occurrence
found (`review_spatial_flags.R`, `utils_plot.R`) is in roxygen prose or inline `#` comments --
never in an actual `message()`/`warning()`/`stop()` string shown at runtime, never in an exported
column name, and never in a user-facing UI label. The actual parameter name is `colors` (American
spelling, consistent with the ecosystem) throughout; only the prose describing it occasionally
says "colours." Per the task's own guidance (fix genuinely user-facing output; don't sweep-rename
internal prose), this was left alone. `flag_habitat_inconsistencies.R`'s "metres"/"kilometres" in
`@param`/`@return` prose is the same category and was also left alone -- the actual column names
(`elevation_m`, `dist_to_coast_km`, `coast_buffer_m`, etc.) already use unit abbreviations, not
spelled-out British/American forms, so there's no real inconsistency in anything a user actually
sees in their data. `flag_institution_candidates.R`'s "Research_centre" is a **different case**,
addressed separately below -- not a spelling choice this package made at all.

### `parse_habitat_response` has "an bug" -- the comma-corruption bug

**Fixed, at the root cause.** See the detailed writeup under `parse_habitat_response.R` below.

------------------------------------------------------------------------

## General Comments

### Non-exported helper functions printed in error messages

**Noted, not actioned.** Every function in this package (and, checked, throughout this
ecosystem) prefixes its own `stop()`/`warning()`/`message()` text with the function's own name,
including internal `.`-prefixed helpers -- a deliberate, consistent convention that makes error
tracebacks legible when a helper several calls deep raises the actual problem. A user isn't meant
to call `.validate_habitat_scheme()` directly, but seeing its name in the error text still
correctly identifies where validation failed, which is more useful for debugging than a generic
message would be. `.collapse_to_model_habitats()`, the other function this comment named, is now
removed entirely (see below), so this concern is moot for that specific function.

------------------------------------------------------------------------

## File-Specific Comments

### assign_habitat_biological.R

- **`data` existing R function:** Fixed -- see Checklist Items above (renamed to `occurrence_data`).

- **Require `habitat_cols` to be a standard format, or at least warn when all numeric columns
  are used:** Fixed, the warning half. `.detect_habitat_cols()` now emits a `message()` naming
  every auto-detected habitat column whenever `habitat_cols = NULL`, so a user always sees
  exactly which columns were treated as habitat weights. Requiring a single fixed format was
  **not** added -- the auto-detect path (any numeric column not otherwise reserved) already
  supports both the wide-weighted `parse_hierarchical_habitat_response()` output and hand-built
  scheme dataframes with arbitrary category names; forcing one fixed naming convention would
  break that flexibility for no functional gain now that the new message makes the auto-detected
  set visible.

- **If `weight_by_abundance` needs a documentation warning about sampling bias often enough,
  consider removing it:** Noted, not actioned. There is no runtime `warning()` here -- only
  `@param` prose explaining why `FALSE` is the recommended default. The parameter itself remains
  legitimate: a caller with properly effort-corrected abundance data (not raw record counts) has
  a real use for `TRUE`. The default already steers users toward the safer choice; removing the
  option would reduce flexibility without fixing anything.

- **Example not runnable, suggest real `occurrence_data`/`hab_weights`:** Fixed. The example now
  builds small, concrete `occurrence_data`/`hab_weights` data frames inline and runs
  `assign_habitat_biological()` on them directly (no longer wrapped in `\dontrun{}` except for
  the one line that pipes through `dplyr::filter()`, kept as an illustrative-only snippet since
  `dplyr` isn't a hard dependency of the example itself).

- **Line ~192 (`n_covered == 0`): should this prompt an early return?** Clarified, not changed.
  It effectively already does: a few lines later, `if (nrow(joined) == 0)` catches exactly this
  case (no species matched) and returns early with `main_habitat = NA` for every row. The warning
  at `n_covered == 0` and the early return at `nrow(joined) == 0` are two views of the same
  condition; no functional gap exists.

- **Is `.detect_habitat_cols()` really needed?** Noted, not actioned. It's a genuine DRY helper
  shared by `assign_habitat_biological()` and `consensus_habitat()` -- both need identical
  `Other_weight` renaming + habitat-column auto-detection logic. Removing it would mean
  duplicating that logic in both functions.

- **Consider simplifying with a pivot->summarize->filter `dplyr` pipeline or `colSums`:** Noted,
  not actioned. The current implementation already computes exactly this (per-point weighted sums
  via `aggregate()` + a normalized weight matrix, equivalent to a pivot-summarize) using base R.
  A `dplyr` rewrite would not change behavior, and this function has real, passing test coverage
  against the current implementation -- not worth the churn/regression risk for a pure style
  preference.

- **`consensus_habitat` has a good runnable example:** Acknowledged, no action needed.

### build_habitat_prompt.R

- **`.collapse_to_model_habitats` unused:** Confirmed and **deleted**. Grepped the whole monorepo
  (source, tests, workflows, vignettes) -- the only real references were the function's own body
  and its own roxygen. Its doc comment said it was "Called by `assign_habitat_llm()` when
  hierarchical = TRUE" -- `assign_habitat_llm()` was itself deleted from this ecosystem back on
  2026-02-27 (`TaxaExpect/CLAUDE.md`'s renaming log), long before this package existed in its
  current form. This was confirmed dead code from a removed pipeline, not a live but
  under-referenced utility -- deleted entirely (~220 lines), per this ecosystem's own convention
  of removing confirmed-dead code.

- **`.iucn_habitat_lookup`: 1.3/3.3 mislabeled "Subalpine"; "the pattern goes on, double check the
  whole table":** Confirmed and **fully rebuilt**. Fetched the real IUCN Habitats Classification
  Scheme v3.1 source document directly (not from memory) and audited every one of the table's 104
  rows against it. The reviewer's specific finding was correct and, as suspected, far from
  isolated:
  - Both Forest 1.3 and Shrubland 3.3 were "Subalpine" and should be "Subantarctic"/"Boreal"
    respectively -- **and Shrubland's whole 3.1-3.3 order was wrong**: the real scheme uses
    Subarctic/Subantarctic/Boreal for Shrubland, a genuinely different order from Forest's
    Boreal/Subarctic/Subantarctic (verified directly against the source; not an assumption).
  - Grassland 4.3 was "Subalpine/Alpine", should be "Subantarctic".
  - **Marine Neritic (9.x) was almost entirely scrambled** relative to the real 9.1-9.10 codes,
    with three entries outright fabricated: "Subtidal Cave and Overhangs", "Pelagic
    (Supercolumnar)" (not real IUCN terminology), and "Seamounts and Knolls" at 9.9 (Seamount is
    real, but it's code 11.5, under Marine Deep Ocean Floor, not Marine Neritic at all).
  - **Marine Deep Ocean Floor** was missing "Seamount" (real 11.5) entirely, had "Seamounts and
    Knolls (bathyal)" in place of the real 11.3 "Abyssal Mountain/Hills", and had the Hadal zone's
    depth threshold wrong (">4000m" instead of the real ">6000m").
  - **Marine Intertidal 12.4** ("Mud Shoreline and Intertidal Mud Flats") had been changed to
    "Mud Flats and Salt Flats" -- introducing a "Salt Flats" concept not part of this real
    category.
  - **Marine Coastal/Supralittoral** -- the L1 name itself was wrong; the real IUCN term is
    "Marine - Coastal/Supratidal". Renamed throughout (the lookup table, `.realm_to_l1`'s marine
    list, `.l1_to_realm()`'s marine list, and doc references).
  - **Wetlands (Inland)** had a fabricated 19th entry ("Ephemeral Saline/Brackish/Alkaline
    Lakes", not in the real 18-entry scheme) and a fabricated 5.18 ("Rocky Freshwater Rivers
    (rapids, falls)") in place of the real "Karst and Other Subterranean Inland Aquatic Systems".
  - **Artificial - Aquatic** had three fabricated entries (15.10-15.12: "Marine and Freshwater
    (flooded mines)", "Marine - Littoral (Tidal) Areas", "Marinas, Harbours, Jetties") and was
    missing the real 15.13 ("Mari/Brackish-culture Ponds") entirely.
  - **Rocky Areas (inland)** and **Introduced Vegetation** are both **L1-only** in the real
    scheme -- no numbered L2 subcategories exist for either (the real document lists "inland
    cliffs, mountain peaks, talus, feldmark" only as prose *examples*, not codified categories).
    Both had two fabricated L2 rows each ("Inland Cliffs and Outcrops"/"Scree and Talus";
    "Planted Forest (monocultures)"/"Other Managed/Introduced Vegetation").
  - **"Other" and "Unknown"** similarly have no real L2 subcategory (`"No type specified"` in the
    source), but the table gave each a fabricated pseudo-code ("17.0"/"18.0").
  - Caves and Subterranean Habitats' two entries were close but incomplete ("Caves"/"Other
    Subterranean Habitats" -> corrected to "Dry Caves"/"Other Dry Subterranean Habitats", the
    real 7.1/7.2 names).

  The table was rebuilt row-by-row against the verified source (104 rows total, up from the
  original's differently-miscounted set), restructured so the four genuinely L1-only groups
  (Rocky Areas (inland), Introduced Vegetation, Other, Unknown) now correctly have
  `l2_code = l2_name = NA` instead of a fabricated pseudo-L2 row -- matching how every other
  L1-only row in this package's own scheme objects (e.g. `build_iucn_scheme()`'s own output) is
  already represented. Fixing that surfaced one more real bug: `build_iucn_scheme()`'s
  `all_l2_in_scope <- unique(lookup$l2_name)` would otherwise have picked up the new `NA` values
  and let `l2 = "all"` silently pull in duplicate L1-only rows for those four groups -- fixed by
  excluding `NA` from that specific lookup, with the reasoning documented inline. Two roxygen
  examples referencing the old (now-corrected) "Rocky Subtidal" name, and a stale "31 L2
  categories"/"18 L1 groups" example comment, were updated to match. L1-name capitalization/word
  order differences from the official document that don't change what the category actually
  means (e.g. this table's "Wetlands (inland)" vs. the official "5. Wetlands (Inland)") were
  deliberately left alone -- fixing those would cascade into `.realm_to_l1`, `.l1_to_realm()`,
  and every doc reference for no scientific-accuracy gain, unlike the content errors above.

  New tests (`test-build_habitat_prompt.R`) verify the corrected Shrubland order, Marine Neritic's
  real categories (and absence of the fabricated ones), Seamount's presence, and the two L1-only
  groups' lack of fabricated L2 rows -- all exercised through the public `build_iucn_scheme()` API.

- **Line ~221 (original numbering): what is the resolution of the cells?** Moot -- this question
  was about `.collapse_to_model_habitats()`'s `grid_col`/`min_cells` grid-cell-count concept,
  which no longer exists (see the dead-code removal above).

- **Document `.collapse_to_model_habitats()`'s arguments:** Moot, same removal.

- **Line 884 (original numbering): logic after the OR in `.is_iucn_scheme` makes `identical()`
  redundant:** Confirmed and **fixed** -- and it turned out to be a real, currently-shipping bug,
  not just redundant code. `.is_iucn_scheme(scheme)` was `identical(scheme, .iucn_habitat_lookup)
  || (all(c("l1_code","l2_code","l1_name","l2_name") %in% names(scheme)) && any(grepl(...)))`.
  Every scheme that ever reaches this function has already passed through
  `.validate_habitat_scheme()`, which subsets to exactly `c("l1_name","l2_code","l2_name","realm")`
  and never preserves `l1_code` -- so **neither disjunct could ever be true** for a real,
  validated scheme (`identical()` compares against a structurally different raw table; the
  `l1_code` membership check always fails since validated schemes never have that column).
  Confirmed live: `flag_habitat_inconsistencies()`'s `.realm()` IUCN-lookup fallback branch (the
  one place `.is_iucn_scheme()` is actually still called after the dead-code removal above) was
  therefore silently unreachable for every real IUCN-derived scheme. Fixed by keeping only the
  actually-functional check (`l2_code`/`l1_name`/`l2_name` present + IUCN-style numeric `l2_code`
  pattern), which is now the only part that was ever really doing the work.

- **Line 279 (original numbering): can `.is_iucn_scheme` be called once and referenced later?**
  Moot -- that call site was inside `.collapse_to_model_habitats()`, now removed.

- **Line 300 (original numbering): where do column names come from? Consider requiring specific
  names, applies to all column names:** Noted, not actioned. Every function that needs a specific
  column already exposes it as a parameter (`taxon_col`, `habitat_col`, `point_id_col`, `lat_col`,
  `lon_col`, etc.) with a sensible default rather than a hardcoded name -- this *is* the "require
  specific names" mechanism, just made configurable. Real occurrence data in this ecosystem comes
  from multiple sources (GBIF DarwinCore exports, camera-trap CSVs, LLM-generated tables) with
  genuinely different native column names; hardcoding one convention would reduce
  interoperability without a correctness benefit.

- **Lines 513-521 (original numbering): add `TaxaTools::` prefix to functions not exported by
  this package:** Fixed. A `\preformatted{}` pipeline block in `build_habitat_prompt()`'s own docs
  called `prompt_manual(prompt)` and `read_llm_response(...)` unprefixed; both now read
  `TaxaTools::prompt_manual(...)`/`TaxaTools::read_llm_response(...)`.

- **Line 595 (original numbering): why not require no duplicate L2 names?** Clarified, already
  true. `.validate_habitat_scheme()` already does exactly this: `stop()`s on any duplicate
  non-`NA` `l2_name` value. No change needed.

- **Suggest running `.validate_habitat_scheme()` right after the default scheme is created, since
  it fails fast:** Fixed. Moved the `.validate_habitat_scheme()` call to immediately after the
  `NULL`/`"IUCN_L1"` shortcut resolution, before any `taxon_list` deduplication/messaging work --
  a malformed custom scheme now fails before the function does unrelated work first.

- **Lines 614-629 (original numbering): rows are just using L1 when L2 is missing -- why not
  `ifelse(is.na(l2), l1, l2)`?** Confirmed as a **real, reproducible bug**, and fixed exactly as
  suggested. For a mixed-scale scheme (both L1-only fallback rows and L2 rows in one object, e.g.
  from `build_iucn_scheme(realm = "terrestrial", l2 = "Temperate")`), the "HABITAT CLASSES" prompt
  block printed the literal habitat name from `scheme$l2_name` for every row -- which is `NA` for
  the L1-only rows, so the LLM prompt read `"NA  [Forest]"`, `"NA  [Savanna]"`, etc. for every
  single-level fallback category. Live-reproduced before fixing (see below) and fixed with exactly
  the reviewer's suggested `ifelse(is.na(l2_name), l1_name, l2_name)` pattern; the underlying
  `habitat_cols` (the actual output-column list requested from the LLM) was already correct --
  only this human-readable display block had the bug. New test confirms no literal `"NA"` appears
  in the generated prompt and that the L1-only rows now correctly show their group name.

- **`.build_single_prompt`: collapse all the ecosystem's prompt-builder functions into one
  `TaxaTools::build_llm_prompt()`:** Noted, not actioned. A real, plausible architectural idea,
  but it spans every prompt-building function across multiple packages (this package,
  `TaxaAssign`'s LLM workflow, `TaxaFlag::review_assignments()`, etc.) -- a genuine cross-package
  redesign well beyond this package's own review scope.

- **Use `example_habitat_scheme` in `build_habitat_prompt()`'s examples, or use
  `build_iucn_scheme()` and remove `example_habitat_scheme` entirely:** Partially done. The
  example now demonstrates both the default scheme and a custom scheme built from
  `example_habitat_scheme`. Removing `example_habitat_scheme` was **rejected**: it and
  `build_iucn_scheme()` serve genuinely different purposes -- `example_habitat_scheme` is a
  minimal, exported *template* for a user building their own non-IUCN scheme (e.g. a local,
  ecologically-tailored classification), while `build_iucn_scheme()` generates schemes derived
  from the IUCN standard specifically. A user who wants a custom scheme needs something to copy
  and edit; that's what `example_habitat_scheme` is for.

- **Does `.l1_to_realm()` only work for certain aquatic habitats? Consider expanding:** Confirmed
  and fixed -- directly related to the realm bug below. `.l1_to_realm()` previously only
  recognised marine and freshwater L1 group names, returning `NA` for every terrestrial group
  (Forest, Savanna, Shrubland, Grassland, Rocky Areas (inland), Caves and Subterranean Habitats,
  Desert, Introduced Vegetation) and for Artificial - Terrestrial. Expanded to also map all of
  those to `"terrestrial"` (a real, unambiguous answer). Artificial - Aquatic, Other, and Unknown
  are deliberately left `NA` -- Artificial - Aquatic genuinely spans both marine (e.g. Mariculture
  Cages) and freshwater (e.g. Ponds) use cases and can't be resolved from the L1 name alone, and
  Other/Unknown have no real-world realm at all; `flag_habitat_inconsistencies()`'s own `.realm()`
  fallback already defaults anything unmatched to `"terrestrial"`, so this remaining `NA` doesn't
  silently misclassify anything.

- **`build_iucn_scheme`: add the "specifics can be included" detail for `l1`/`l2` earlier in the
  docs, it's there but you have to dig:** Noted, not actioned. The information is present and
  accurate; reordering roxygen sections for prominence is a low-value cosmetic change relative to
  the substantive fixes in this pass.

- **`build_iucn_scheme(realm = "terrestrial", l2 = "Temperate")` has odd behavior -- duplicate L1
  rows where L2 is NA, and `realm` is NA despite being explicitly supplied:** Both investigated
  and resolved differently. The duplicate-L1-fallback-rows behavior is **intentional, documented
  mixed-scale semantics** (`l1` defaults to `"all"`, so supplying `l2` without also setting
  `l1 = "none"` deliberately returns both the L1 fallback rows for every group in the realm AND
  the specific L2 rows requested) -- a new `@details` "A common surprise" section now spells this
  out explicitly with the reviewer's own exact example, and points at `l1 = "none"` for anyone who
  only wants the L2 rows. The `realm = NA` half, however, **was a real bug**: `.l1_to_realm()`
  (called for every row regardless of whether the caller had already told the function which
  realm it wanted) returned `NA` for terrestrial/artificial groups, so `build_iucn_scheme(realm =
  "terrestrial", ...)`'s own output showed `realm = NA` on every row despite the caller explicitly
  requesting `"terrestrial"`. Fixed: when `realm` is supplied, every row in that call's output
  uses the caller's own known realm value directly (every row is guaranteed to be in that realm by
  construction, since realm-filtering happens before row selection) rather than going through
  `.l1_to_realm()`'s incomplete per-L1-group guess. New tests confirm `realm = "terrestrial"`/
  `"artificial"`/`"marine"` calls all produce a non-`NA`, correctly-valued `realm` column, and that
  `realm = NULL` calls still correctly vary realm per L1 group.

- **`build_scheme_prompt("pinus contorta", realm = "terrestrial")`'s OUTPUT FORMAT lists all
  realms even though the prompt is scoped to one:** Confirmed and fixed. The `realm` output-column
  instruction line unconditionally said "one of: marine, freshwater, terrestrial, or NA if
  mixed" even when `realm` was already fixed by the caller. It now reads `always "<realm>" (all
  species in this list are in the <realm> realm)` whenever `realm` is supplied, and keeps the
  original all-three-option wording only when `realm = NULL`.

- **Print methods harder to parse than raw `data.frame` output:** Noted, not actioned. The custom
  `print.habitat_prompt`/`print.scheme_prompt`/`build_iucn_scheme()` summaries are a deliberate
  design choice to avoid dumping unwieldy nested structures (e.g. `$prompts` holds full multi-KB
  prompt strings) to the console. Users who want the raw structure can already use `str()` or
  access `$scheme`/`$habitat_cols` directly -- this matches standard R S3 practice.

- **Not all examples are runnable:** Addressed where it's cheap and where a network call isn't
  required (`build_habitat_prompt()`'s own example now runs directly, no `\dontrun{}`, per the
  point above); left as `\dontrun{}` for functions whose real work genuinely requires a live LLM
  call or network access (`build_scheme_prompt()`, `parse_scheme_response()`) -- matching this
  ecosystem's own established convention for LLM-calling examples.

- **Suggest updating `prompt_anthropic_api` to `prompt_api` in examples:** Fixed. All 6
  occurrences replaced with `TaxaTools::prompt_api(...)`.

- **Line 1587 (original numbering): is it possible for a comma to exist in lines that aren't
  data?** Investigated, left as a documented, low-severity edge case, not fixed. This is
  `parse_scheme_response()`'s preamble/postamble-trimming heuristic (`is_data <- grepl(",", ...)
  | seq_along(lines) == 1`), a different code path from the confirmed comma bug below. Yes, a
  stray prose sentence containing a comma (e.g. "Note: categories are approximate, adjust as
  needed.") could in principle be misclassified as a data line. The LLM is already explicitly
  instructed to return "ONLY a raw CSV block... no preamble or postamble," which minimizes real
  exposure, and a full robust preamble/postamble parser rewrite is a larger undertaking than this
  review's scope warrants for a defensive fallback path.

- **Line 1623 (original numbering): `min_habitats` defaults to 2 -- consider requiring it be
  specified:** Noted, not actioned (the reviewer themselves flagged this as low-priority). `2` is
  a sensible floor -- a "scheme" of exactly one category is degenerate -- and the function already
  validates `min_habitats >= 1`. Not worth an API friction increase for a soft concern.

### flag_habitat_inconsistencies.R

- **Line 11 (original numbering): is this actually the most common error, or the most common for
  existing users?** Fixed. Reworded to "In this project's real usage so far, the most common
  error..." with an explicit note that this reflects the datasets used to date, not a universal
  claim about GBIF data quality.

- **Line 15 (original numbering): why not return a joinable dataframe instead of duplicating
  columns?** Noted, not actioned. This is intentional: the function's own doc explains the
  augmented, row-count-preserving shape exists specifically so the result can be passed directly
  to `review_spatial_flags()`, which needs the flag columns present on every occurrence row, not a
  separate lookup table keyed by location. A joinable-table return would require every caller
  (including that gadget) to do the join themselves.

- **British spelling ("metres"):** See Checklist Items above -- prose-only, left as-is.

- **No tests:** Fixed, partially. New `test-flag_habitat_inconsistencies.R` covers the real,
  offline-testable input-validation path (missing/custom-named required columns). Every other
  code path requires live network access (Natural Earth polygons, NOAA GEBCO bathymetry) with no
  offline substitute -- matching this ecosystem's own precedent for genuinely network-bound
  functions.

- **`data` existing R function:** Fixed -- see Checklist Items above.

- **Consider requiring specific column names in `occurrence_data`:** Noted, not actioned -- same
  reasoning as the analogous `build_habitat_prompt.R` comment above (parameterized `lat_col`/
  `lon_col`/`habitat_col` already serve this role).

- **Example not runnable:** Fixed. The example now uses the reviewer's own tested minimal case
  (`decimalLatitude = 40.823875, decimalLongitude = -124.193872, main_habitat = "Marine"`) inline,
  still inside `\dontrun{}` since it genuinely requires live network access.

- **Suggest explicitly requiring `rnaturalearthdata` as a dependency:** Fixed. The function's own
  runtime `requireNamespace()` check already required it; `DESCRIPTION` did not declare it
  anywhere. Added to `Suggests`.

- **`rnaturalearthhires` isn't on CRAN -- show how to install it:** Fixed, and this was a real,
  actionable gap: the old error message told the user to `install.packages(c(..., "rnaturalearthhires", ...))`,
  which fails for that one package specifically. The missing-package error now gives
  `rnaturalearthhires` its own correct install line
  (`install.packages("rnaturalearthhires", repos = "https://ropensci.r-universe.dev")`) separate
  from the CRAN-only `install.packages()` line for everything else.

- **Lines 190-200 (original numbering): could `st_as_sfc(st_bbox(st_buffer(pts_unique,
  distance)))` replace the coastal-buffer logic? Should distance be tunable?** Investigated,
  rejected as a substitution (not equivalent), and the tunability already exists. The suggested
  one-liner buffers each *point* into a box -- a materially different (and less correct)
  computation from what's needed here, which is "is this point within X of the actual *coastline
  geometry*." The current code correctly buffers the coastline polyline itself and tests polygon
  containment. The buffer distance is already fully tunable via the existing `coast_buffer_m`
  parameter.

- **Could the spatial reference data be preprocessed and shipped with the package?** Noted, not
  actioned. Natural Earth's `scale = "large"` polygons plus NOAA GEBCO bathymetry would add a very
  large amount of data to the package, far beyond normal CRAN package-size norms -- fetching live
  is the correct tradeoff here, matching this package's existing design.

- **Messages still print even with `suppressWarnings()`:** Clarified, not a bug. This is correct,
  standard R behavior -- `suppressWarnings()` only ever suppresses warning-class conditions, never
  `message()`-class output, regardless of what package emits them. This function's own `verbose`
  parameter (default `TRUE`) is the actual, documented mechanism for controlling its messages;
  `verbose = FALSE` is the fix, not a change to how R's condition system works.

- **`marmap::getNOAA.bathy` fails without wifi (works on cellular... or vice versa), "not
  necessarily a package issue":** Noted, not actioned -- the reviewer's own framing already
  correctly identifies this as outside this package's control (a third-party network client's
  behavior on a specific network path).

### flag_institution_candidates.R

- **Either `TaxaFetch::filter_gbif_quality()` changed since review, or this function references
  an outdated version:** Confirmed current, not outdated. Read `TaxaFetch::filter_gbif_quality()`'s
  actual current source directly: it produces exactly `institution_flag`, `institution_name`,
  `institution_type`, `institution_dist_m`, `institution_lon`, `institution_lat` when
  `flag_institution = TRUE` (its default) -- precisely the columns `flag_institution_candidates()`
  and `review_institution_flags()` both expect. The interface is current; the review was likely
  written against an earlier snapshot.

- **Should this function live in TaxaFetch instead?** Restated from the existing documented
  rationale (this exact question was worked through when the function was built, 2026-07-23 --
  see `TaxaHabitat/CLAUDE.md`'s session note for that date): TaxaHabitat, not TaxaFetch, because
  it sits in the same pipeline lane as the GBIF reference-occurrence data it classifies, and
  "archived specimen vs. wild observation" is fundamentally a habitat-context question, mirroring
  `flag_habitat_inconsistencies()`'s own classify-then-review role in this same package.

- **More British spellings: `Research_centre`:** Investigated and confirmed this is **not this
  package's spelling choice at all** -- it's a literal value from `CoordinateCleaner::institutions$type`,
  the external package this classification is built against (confirmed directly by loading that
  data: `sort(unique(institutions$type))` returns `"Botanic_garden" "Herbarium" "Museum"
  "Research_centre" "University" "Zoo"`). Renaming it in our own docs/rules would break the string
  match against the real external vocabulary this function joins against. Left as-is.

- **`data` existing R function:** Fixed -- see Checklist Items above.

### parse_habitat_response.R

- **The comma-in-`habitat_best_guess` bug ("This seems like a true bug"):** **Confirmed and fixed
  at the root cause**, not just worked around. Root-caused precisely: when the LLM writes an
  unquoted, literal comma inside `habitat_best_guess` free text (a real, reproduced case:
  `"Continental shelf demersal (30-200 m), including deeper muddy/sandy bottoms..."`), that data
  row ends up with one more comma-separated field than the header. `utils::read.csv()`
  (`read.table()`'s own documented behavior for exactly this header/data field-count mismatch)
  then treats the *first* field as an implicit row name rather than a data column -- every value
  shifts one column left, `taxon_name` reads as a numeric habitat weight, `Other_weight` reads as
  the first half of the free-text description, and the true taxon name silently becomes the
  (invisible) row name instead of the `taxon_name` column. Exactly the symptom the reviewer's own
  pasted repro showed.

  Fixed two ways, matching the review's own "true bug" framing seriously:
  1. **Preventive, at the LLM prompt (`build_habitat_prompt.R`):** the OUTPUT FORMAT rules now
     explicitly instruct the LLM to wrap any `habitat_best_guess`/`ecoregion_best_guess` value
     containing a comma in double quotes, standard CSV convention.
  2. **Corrective, at parse time (new `.repair_unquoted_commas()`):** since LLMs don't reliably
     follow formatting instructions, the parser now detects (via a quote-aware
     `utils::count.fields()` check, so an *already correctly quoted* field is never touched) any
     data row that genuinely overflows the header's field count, merges the overflow field(s)
     back into `habitat_best_guess` (and `ecoregion_best_guess`, when present, using the last
     overflow-span field for it since it's the shorter/less comma-prone of the two), and re-quotes
     the merged value before handing the row to `utils::read.csv()`. This fixes both already-
     malformed historical responses and any future LLM that ignores the new prompt instruction.

  New `tests/testthat/test-parse_habitat_response.R` (33 tests total) directly reproduces the
  exact reported scenario (a `habitat_best_guess` value containing a comma) and confirms
  `taxon_name`, row names, `Other_weight`, and `habitat_best_guess` all parse correctly -- plus
  the ecoregion-present variant, the already-correctly-quoted case (confirmed *not* double-quoted
  by the repair step), and general coverage of `parse_hierarchical_habitat_response()` overall
  (fences/preamble/postamble stripping, duplicate-header stripping, missing/extra habitat
  columns, weight-sum warnings, the `Habitat` argmax column, `ecoregion_best_guess`).

- **What's the difference between `.validate_habitat_scheme_local`/`.validate_habitat_scheme` and
  `.is_two_level_local`/`.is_two_level`? Are both needed? Why is cross-file dependency an issue?**
  Investigated. Note first: the earlier 2026-07-28 review-prep session already found and fixed a
  *related but distinct* bug here -- a stale, buggy duplicate `.is_two_level()` definition that
  used to live in this file (missing an empty-string guard `.is_two_level()` in
  `build_habitat_prompt.R` already had) -- that duplicate was deleted, and this file's own
  `.is_two_level_local()` (correctly named and scoped to this file's own bare-dataframe legacy
  path) was left in place deliberately. Re-examined independently this session: `.validate_habitat_scheme_local()`/
  `.is_two_level_local()` exist specifically for the one legacy code path in
  `parse_hierarchical_habitat_response()` that accepts a *bare dataframe* as `habitat_scheme`
  (not a `habitat_prompt` object) -- their own header comments say so explicitly ("kept local to
  avoid cross-file dependency in this helper path"). The duplication is real but narrow (two
  small functions, ~15 lines combined) and the cross-file-dependency concern is legitimate: this
  file would otherwise need `build_habitat_prompt.R`'s internal (`.`-prefixed, `@noRd`) functions
  to be loaded in a specific order, which R packages don't guarantee without an explicit
  `Collate:` field this package doesn't use (and the 2026-07-28 session's own bug is a direct,
  concrete demonstration of what goes wrong when two files silently drift on a shared internal
  name). Kept as-is -- the duplication is small, intentional, and the alternative (a `Collate:`-
  ordered shared helper) trades a minor DRY violation for a real ordering fragility this package
  has already been bitten by once.

- **Line 454 (original numbering): `%||%` not created here, but avoids duplication:**
  Acknowledged, no action needed -- correctly observed as already handled (imported from
  `TaxaTools`, not locally redefined).

- **`parse_hierarchical_habitat_response` has no tests:** Fixed -- see above (33 new tests).

- **Should lines 158-166 (original numbering) be inside `.strip_and_extract_csv()`?** Noted, not
  actioned. A reasonable code-organization preference (folding the duplicate-header-stripping
  step into the fence-stripping helper), but purely stylistic -- the current three-step structure
  (extract -> dedupe headers -> repair commas) is functionally correct and each step is easy to
  reason about independently; not worth the churn given everything else already changed in this
  file this pass.

### report_habitat.R

- **Example not runnable as-is:** Noted, not actioned. The example is already inside
  `\dontrun{}` and depends on a full LLM habitat-assignment pipeline having already run
  (`llm_output` is illustrative, matching this ecosystem's convention for examples that need a
  live LLM call).

- **Consider adding a known-habitat-scheme option, probably as the default:** Noted, not actioned
  -- out of scope for this review pass; the function already auto-detects the 3-category/IUCN_L1
  scheme from column names, which covers the common cases without requiring a new parameter.

### review_institution_flags.R

- **Example not runnable as-is:** Noted, not actioned -- requires a live `TaxaFetch::filter_gbif_quality()`
  network call; already `\dontrun{}`, matching this ecosystem's convention.

- **No tests, but that might be reasonable:** Confirmed reasonable, matching this ecosystem's own
  explicit precedent (interactive Shiny/leaflet gadgets requiring a live session aren't unit-
  tested anywhere in this ecosystem -- see `review_spatial_flags()`'s own documented history).

- **`data` existing R function:** Fixed -- see Checklist Items above.

- **Line 145 (original numbering): seems like this could be a simple filter operation:** Clarified,
  not a functional issue. The point-table construction there already *is* a filter -- base-R
  bracket subsetting on a logical index (`flagged_idx <- which(is_flagged)`, then `data[[col]][flagged_idx]`)
  is functionally identical to `dplyr::filter()`/`subset()`, just written in the base-R style this
  whole file already uses consistently. No behavior change made.

### review_spatial_flags.R

- **British spelling ("colour"):** See Checklist Items above -- prose-only, left as-is.

- **`data` existing R function:** Fixed -- see Checklist Items above.

- **Should manual habitat entry (the "Other" text box) be free text or constrained to specific
  values?** Noted, not actioned -- intentional. Free text is needed precisely because a reviewer
  using this gadget is often *correcting* a genuinely wrong or scheme-incomplete original
  classification, so the value being entered may not already exist in the scheme. It isn't
  unconstrained after entry, though: `.register_new_habitat()` immediately folds any newly typed
  value into the same controlled palette/level system every other habitat value uses, so it
  becomes a normal, selectable choice for the rest of the session.

- **Line 742 (original numbering): `hist` shadows `stats::hist()`, consider `flag_hist`:** Fixed,
  using the reviewer's own suggested name. Renamed the local undo-history variable `hist` ->
  `flag_hist` everywhere in the file (12 occurrences), matching this ecosystem's own established
  precedent for base-R-shadowing local variable names (the 2026-07-28 session's `det`/`t` ->
  `hab_cols_info`/`type` fix in `assign_habitat_biological.R`/`flag_institution_candidates.R`).
  `history()`, the unrelated `reactiveVal` accessor, was correctly left untouched.

- **The bulk flag drawing option doesn't seem to be working:** **Investigated thoroughly, no new
  bug found, reported honestly rather than guessed at.** This exact complaint (a rectangle drawn
  in the gadget's default "Flag" action mode appearing to do nothing) was already investigated
  across 6 rounds in an earlier session (see `TaxaHabitat/CLAUDE.md`'s top session note and the
  `project_review_spatial_flags_habitat_reassign_gap` memory record): several real bugs were
  found and fixed then (a view-membership bug, an `input$` race condition, an NA-habitat drop, and
  -- directly relevant here -- an unstable per-view auto-zoom bug whose fix is the `full_bounds`
  computation still present at the top of this file's server function). The specific "draws a
  rectangle, nothing happens" symptom was never conclusively reproduced on a freshly restarted,
  correctly reinstalled session, even at 6x the scale that originally failed -- the leading theory
  from that investigation is that the earlier failing tests ran against a stale, pre-fix build (a
  documented footgun in this project: `devtools::install()` output looks identical whether or not
  anything actually changed). Debug `message()` calls
  (`"[review_spatial_flags DEBUG] ..."`) were deliberately left in the rectangle-select handler as
  a safety net from that session, per the user's own choice at the time.

  Re-read the entire rectangle-select code path fresh for this review, specifically to find an
  independent bug rather than trust the prior conclusion: the coordinate-ring extraction (GeoJSON
  Polygon `coordinates[[1]]`, correctly lon-then-lat indexed), the view/flag/habitat-visibility
  filtering (`pts$point_id %in% names(fl)[fl == view_lc] & pts$habitat %in% vis_hab & ...`), and
  the post-flag marker-removal/toolbar-reset logic all read as internally consistent and
  structurally mirror the single-click path (which the reviewer implicitly confirms works, since
  only "bulk" drawing was flagged). One initially-promising lead -- an asymmetry where
  `.reset_draw_toolbar()` is called immediately after a bulk Flag action but not immediately after
  drawing a rectangle in Reassign-Habitat mode -- turned out **not** to be a bug on closer reading:
  the toolbar reset in Reassign-Habitat mode is correctly deferred until `confirm_habitat` fires
  (line ~1051), since the reviewer needs the drawn rectangle to stay visible while picking a target
  habitat from the sidebar first.

  **Honest conclusion: no new, independently reproducible bug was found via careful static reading
  this session, consistent with the prior session's own inability to reproduce it on a fresh
  session.** The debug logging remains in place. If this recurs, the printed `[review_spatial_flags
  DEBUG]` console output (box coordinates and `in_box_ids` length) will show directly whether the
  rectangle's bounds or the view/habitat filters are the actual point of failure -- please try a
  fresh reinstall + restart first (see the reinstall instructions below), since that's the one
  variable the prior investigation could never fully rule out.

### TaxaHabitat-package.R

- **Reviewed, no comments:** No action needed.

### utils_plot.R

- **Line 4 (original numbering): `.he` is also used by `review_institution_flags`:** Verified,
  not a real ambiguity risk. `.he()` is defined exactly once, only in this file (confirmed via
  grep across `R/`), and is *called* (not redefined) by both `review_institution_flags.R` and
  `review_spatial_flags.R`. A single package-namespace-scoped internal helper reused by multiple
  files is ordinary R scoping, not a collision -- a real collision would require a second
  definition of the same name, which doesn't exist. Fixed the file's own stale header comment,
  which only listed `review_spatial_flags()` as a user and didn't mention
  `review_institution_flags()` at all (added later), to name both, with a short note explaining
  why this isn't a collision.

### zzz_imports.R

- **Line 5 (original numbering): consider adding `call_api`:** Investigated and addressed
  differently than suggested. `call_anthropic_api` was imported here but confirmed **never
  actually called anywhere in this package** as a bare (unqualified) symbol -- this package's
  functions never call an LLM provider directly; `build_habitat_prompt()` only builds prompt
  strings, and every real LLM call in this package's own docs/examples is namespace-qualified
  (`TaxaTools::prompt_api()`, etc.). Removed the dead `call_anthropic_api` import rather than
  adding a new, equally-unused `call_api` one, matching this ecosystem's own established
  precedent for removing confirmed-dead imports (the 2026-07-28 session's `rlang` import removal
  in `assign_habitat_biological.R`).

------------------------------------------------------------------------

## Test and Check Results

`devtools::document()`: clean, no errors.

`devtools::test()`: **220/220 passing (0 failures, 0 warnings, 0 skips)**, up from the review's
own reported 158/158 -- the increase is real new coverage (33 new tests in
`test-parse_habitat_response.R`, 4 new in `test-flag_habitat_inconsistencies.R`, 25 new in
`test-build_habitat_prompt.R` for the `build_iucn_scheme()`/`.is_iucn_scheme()`/prompt fixes), not
inflation of an existing file.

`devtools::check()`: **0 errors, 0 warnings, 0 notes** (includes examples, vignettes, and the
`R (>= 4.1.0)` dependency now correctly stated rather than auto-detected as a warning).

Reinstalled via `ecosystem_docs/install_all.R` (multiple packages touched: `TaxaHabitat` itself,
`TaxaExpect` for the real `R/build_priors.R` call-site fix, `TaxaWizard` for the metadata/snippet
updates). Verified post-install: `find.package("TaxaHabitat")` ->
`/Users/lafferty/Library/R/4.0/library/TaxaHabitat` (the correct user library, not the system
default).

------------------------------------------------------------------------

## Not Resolved / Open Items

- **`review_spatial_flags()`'s "bulk flag drawing doesn't seem to be working"** -- see the
  file-specific writeup above. No new bug found via careful static re-reading; matches a prior
  session's own inability to reproduce the same symptom on a fresh session. Debug logging remains
  in place as a safety net. Genuinely open, not fabricated as fixed.
- **`parse_scheme_response()`'s preamble/postamble comma-detection heuristic** (a different,
  lower-severity edge case from the confirmed `habitat_best_guess` bug) -- documented as a known,
  low-probability limitation rather than fixed, given the LLM is already explicitly instructed to
  avoid preamble/postamble text entirely.

------------------------------------------------------------------------

## To apply these changes

```r
.rs.restartR()
source("~/My Drive/Rscripts/projects/TaxaID/ecosystem_docs/install_all.R")
.rs.restartR()
```
