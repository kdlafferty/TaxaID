# TaxaFetch Peer Review Response

**Review date:** 2026-08 **Package version reviewed:** TaxaFetch 0.1.0 **Reviewer:** Micah
Wright (human-authored review, `inst/taxafetch_review.Rmd`) **Response prepared by:**
Kevin Lafferty

This document replaces the previous `taxafetch_review_response.md`, which responded to an
older, Claude-authored review (Session 148, `taxafetch_review.Rmd` as it existed at the
time). The user replaced that review file with a new, human-authored one covering the same
24 source files plus checklist sections; this response addresses the current
`inst/taxafetch_review.Rmd` in full, comment by comment.

**Verification:** `devtools::document()` clean (0 errors after also fixing 4 pre-existing
`@importFrom` multi-line blocks that a newer roxygen2 in this environment now rejects --
found blocking `document()` while regenerating docs for this response, unrelated to any
review comment, fixed so the response could be verified at all). `devtools::test()`:
**616 passing, 2 failing (both pre-existing, confirmed unrelated to this response via
`git stash` -- see "Automated tests" below), 32 expected warnings, 6 expected skips** (up
from 565/565 before this session). `devtools::check()`: **0 errors, 0 warnings, 0 notes**
("Status: OK"). Reinstalled to `~/Library/R/4.0/library` (confirmed via `find.package()`).

------------------------------------------------------------------------

## Code Review

### Functionality / Optimizations / Coding standards

**No sweeping changes needed** -- the review confirmed the code is organized and readable.
Real, specific issues raised throughout the "Comments on specific files" section are
addressed file-by-file below; several were genuine bugs, most were legitimate DRY/consistency
suggestions now applied, and a few reflected a misunderstanding of code that is working as
designed (noted explicitly where that's the case, per this project's own "verify purpose
before flagging a flaw" convention).

One coding-standard item applies across files: this project's convention is that a local
variable or parameter must never be named `df` (shadows `stats::df()`, the F-distribution
density -- already fixed ecosystem-wide in TaxaTools/TaxaHabitat/TaxaFlag as `df` ->
`input_df`). Two real instances were found and fixed in TaxaFetch this session (see
`dataone_taxon_screening.R` and `pdf_extract.R` below) -- neither had been caught before.

### Automated tests

**Confirmed, with one correction.** The review asked to double-check that
`"read_biotime_study() errors in non-interactive session when local_path is NULL"`
(`test-biotime_fetch.R:95`) runs as expected: re-ran it directly -- it passes, and the
function's own `if (!interactive()) { ... }` guard (before `file.choose()` is ever called)
is exactly what makes it pass; this is not a gap, it's the fix already in place.

Two **pre-existing** test failures were found while running the full suite this session
(`"removes records near (0,0) (cc_zero)"` and `"removed_records joins multiple simultaneous
CoordinateCleaner reasons with ';'"`, both in `test-filter_gbif_quality.R`). Confirmed via
`git stash` that both fail identically on the pre-review code, unrelated to anything in this
review or this response -- almost certainly a `CoordinateCleaner`/`terra`/`sf` version drift
in this environment (`[vect] guessed crs` messages accompany many nearby tests). Not fixed
here: out of scope for this review, and changing filter behavior to chase a locally-observed
version mismatch risks masking a real difference elsewhere. Flagged for a future session with
a fresh look at the installed `CoordinateCleaner` version.

### Vulnerabilities

The reviewer disclaimed domain expertise here and found nothing obvious. No new
vulnerabilities were found or introduced this session. The SSRF allowlist and zip-slip
defense from the prior (Session 148) review remain in place and untouched.

------------------------------------------------------------------------

## Domain Review

### Scientific Rigor / Outputs / Algorithms

No changes needed beyond the specific file-level items below. The reviewer's overall
assessment (outputs comparable to similar tools, algorithms appropriate) stands; the real
bugs found (coordinate parsing, XML field names, an NA-vs-NULL defaulting gap) are
functionality/correctness issues addressed below, not algorithm-design flaws.

### General comments (not tied to one file)

**`data.frame` vs. `tibble` consistency across the package suite -- design question,
not changed.** Fair observation: some functions return `tibble`s, some return base
`data.frame`s (e.g. `read_biotime_study()`'s internal pipeline is all base R until the final
`tibble::as_tibble()` cast). This is a real ecosystem-wide inconsistency, not unique to
TaxaFetch, and standardizing on one or the other is a genuine cross-package design decision
(touching TaxaTools/TaxaHabitat/TaxaMatch/TaxaLikely/TaxaExpect/TaxaAssign/TaxaFlag too, all
of which mix the two). No prior session record was found deciding this deliberately either
way -- it appears to be organic drift, not a considered choice. Flagged as a real candidate
for a future dedicated cross-package pass; not attempted here, since a review-response
session is the wrong scope for a mechanical-but-wide refactor across 9 packages.

**Switching to `data.table` throughout -- design question, not changed.** Same reasoning:
`data.table` is already used as an optional (`Suggests`) fast path in
`download_gbif_occurrences()`. A full replacement of the `dplyr`/`tibble` stack would be a
substantial, cross-cutting rewrite with real behavioral-equivalence risk (silent NSE/join
differences between the two frameworks), reasonably deferred to "maybe v2.0" as the reviewer
themselves suggested.

**Why not depend on `EDIutils`?** Checked its listed function set against what this package's
hand-rolled PASTA/Solr code does: `EDIutils` wraps the same PASTA API surface (metadata
search, EML fetch, data entity download) that `dataone_catalog.R`/`dataone_occurrence_search.R`/
`dataone_standardize.R` already implement directly via `httr2`. Adopting it would be a real,
substantial migration (every PASTA-facing internal function rewritten against a new
dependency's interface) with an unclear net win -- this package's own code already handles the
project's specific needs (Solr query quirks documented at the top of
`dataone_occurrence_search.R`, e.g. the `fq`/`sort` "explode" multi-param gotchas found the
hard way in a prior session) that a generic wrapper package may or may not smooth over
identically. Flagged as worth a real trial/comparison in a future session, not adopted here
without evaluating it hands-on first.

**PASTA base URL defined multiple times -- FIXED.** Real duplication confirmed:
`dataone_catalog.R` hardcoded the full search URL as a literal string, `dataone_eml_screen.R`'s
`.resolve_pasta_id()` hardcoded a `sprintf()` with the domain baked in, and
`dataone_occurrence_search.R` already had `.pasta_solr_url`/`.pasta_meta_url` constants but
built them independently. Added a single shared `.pasta_base_url` constant
(`dataone_occurrence_search.R`) that `.pasta_solr_url`/`.pasta_meta_url` are now built from,
and repointed the other two files' hardcoded strings at it.

**"Why not harvest the catalog once and reference it, instead of querying PASTA
`/package/search/eml` in three separate functions?"** `harvest_dataone_catalog()` already IS
that single full-harvest function (paginated, disk-cached). `search_dataone()`
(`dataone_occurrence_search.R`) and `.pasta_solr_page()` (`dataone_catalog.R`'s own internal
paginator) are not redundant with it, though: `search_dataone()` is a lighter-weight,
narrower-field, bbox-pre-filtered convenience query for a caller who wants a quick look
without paying for/storing the full catalog, and is a legacy/simpler entry point predating
`harvest_dataone_catalog()`. Real, fair related finding, though: `search_dataone()`'s own
coordinate extraction was flagged as unreliable/untested by the reviewer's own
`geographicdescription`/`spatialCoverage` investigation -- see the `dataone_occurrence_search.R`
section below, where this was traced to a real bug and fixed. Not merged into one function
this session (a real design consolidation, bigger than a review-response fix); the accuracy
gap that made this question urgent is fixed regardless.

------------------------------------------------------------------------

## File-specific comments

### biotime_fetch.R

- **BioTIMEr package -- considered, not adopted.** BioTime data is still only distributed as
  per-study CSV downloads (no query API), which is the actual bottleneck this file's own
  docs describe -- a wrapper package would help with the download step at most, not the
  actual gap. Worth a look in a future session if BioTIMEr turns out to also handle the
  manual-download step better; not evaluated hands-on this session.
- **`file.choose()` default -- confirmed already safe, no change.** The function already
  guards with `if (!interactive())` before ever calling `file.choose()` (line ~120), so a
  scripted/non-interactive call errors cleanly with actionable guidance rather than hanging.
  Re-ran the specific flagged test (`test-biotime_fetch.R:95`) directly -- passes.
- **`study_id` from filename vs. a random string -- answered, not changed.** A random string
  would defeat the actual purpose of `study_id`: it must be the real BioTime `STUDY_ID` so
  `datasetID` traces back to a citable, cross-referenceable source (per this function's own
  `@section Obtaining BioTime data` and citation-DOI note). A random string would be
  "unique" but useless for that purpose. The filename-parse fallback is explicitly documented
  as best-effort, with a warning and an explicit override path
  (`read_biotime_study(local_path, study_id = 595L)`).
- **Line 223 (`organismQuantity <- as.numeric(...)`) -- answered, not changed.** Deliberately
  numeric, not integer: BioTime `ABUNDANCE` values are frequently fractional (density or
  effort-standardized counts, not raw individual counts), and Darwin Core's own
  `organismQuantity` term is explicitly a general (non-integer) quantity.
- **Returns a `tibble` after an all-base-R pipeline -- see the general "data.frame vs.
  tibble" comment above.**

### check_inat_range.R

- **API token documentation -- FIXED.** `@param api_token` now states where to get a token
  (`https://www.inaturalist.org/users/api_token`, free account, 24-hour validity) and how to
  set it, instead of only explaining what to do after an expired-token error.
- **`Sys.sleep(0.3)` always fires -- answered, not changed.** This is a deliberate,
  unconditional per-API-call rate limiter inside `.inat_taxon_id()`, which is called once per
  taxon inside `check_inat_range()`'s loop -- exactly where a rate limiter belongs. It's also
  shared by `fetch_inat_occurrences()` (a newer file, added after this review was written;
  see the note on files not covered by this review below), so the sleep protects both
  callers, not just this one. Minor, accepted inefficiency: the very last taxon in a loop
  still sleeps needlessly after its own final call (no more calls follow) -- not worth adding
  branch complexity to shave off one sleep.
- **`results[[1]]` safety -- answered, not changed.** The API request itself sets
  `per_page=1`, so `parsed$results` can never have more than one element by construction;
  `lapply()`-ing over it would add complexity with no behavioral difference.
- **`sf::st_write()` instead of `writeLines()` for caching -- answered, not changed.** The
  current code caches the RAW GeoJSON response text verbatim (byte-for-byte), which is more
  faithful than parsing to an `sf` object and re-serializing it via `st_write()` -- a
  parse-then-rewrite round trip risks precision/property differences from the original server
  response.

### dataone_catalog.R

- **Name EDI explicitly -- FIXED.** `@details` now names the Environmental Data Initiative
  explicitly with a link, rather than only "PASTA/EDI" in the title.
- **Citation/DOI expectations -- FIXED.** Added a `@details` note quoting EDI's terms-of-use
  expectation (cite, contact provider before publication use) and a link; added a real `doi`
  column (new `fl_fields` entry + `.xml_scalar(doc, "doi")`, both live PASTA Solr fields per
  this file's own documented field list) so citation is actually possible from the returned
  data, per the reviewer's explicit suggestion.
- **`httr2` here vs. `httr` in `check_inat_range.R` -- design question, flagged, not
  changed.** Real inconsistency, confirmed: DataONE-pipeline files use `httr2`;
  `check_inat_range.R`/`fetch_inat_occurrences.R` use `httr`. Migrating the iNaturalist
  functions to `httr2` is a real, bounded refactor (two files, both already have real test
  coverage to verify against) but touches working, well-tested request/response/error-handling
  code for a style-consistency win only -- flagged as a good candidate for a dedicated small
  session, not attempted as a drive-by change here.
- **`# TaxaExpect --` header -- FIXED.** This and 6 other files (`dataone_eml_screen.R`,
  `dataone_occurrence_search.R`, `dataone_preview.R`, `dataone_standardize.R`,
  `fetch_gbif_occurrences.R`, `filter_gbif_quality.R`) had a stale top-of-file banner comment
  reading `# TaxaExpect -- <description>`, left over from before Session 19 split TaxaFetch
  out of TaxaExpect. All 7 corrected to `# TaxaFetch --`. This was **not** a case of a
  deliberate cross-reference (the reviewer's "if the package is cross referenced, consider
  combining" question) -- it was pure doc drift from the split; genuine
  `TaxaExpect::function()` cross-references elsewhere in these files (e.g. in
  `dedupe_occurrences.R`'s roxygen, correctly pointing at
  `TaxaExpect::prepare_model_dataframe()`) are real, current, and left untouched.
- **`authors`/`keywords_str` came back `NA` for every real record -- FIXED, real bug.** The
  reviewer's live test (200-row real catalog pull) found `authors` always `NA`, and
  hypothesized the XML node might be `authors`/`keywords` (plural) rather than
  `author`/`keyword` (singular). Since PASTA's own documented Solr field names ARE singular
  (`author`, `keyword` -- confirmed against this file's own header-comment field list) but the
  reviewer's live evidence is that the singular XPath never matched, the fix tries several
  real candidate shapes in order instead of guessing a single replacement: flat singular
  (`"author"`), nested (`"authors/author"`), and flat plural (`"authors"`) -- whichever
  actually has content wins. Also added the same `doi` field (see above).
- **One-liner piped (`req |> httr2::req_perform()`) -- style opinion, not changed.** Matches
  this project's own "native pipe throughout" convention; not worth special-casing a
  single-call pipe.

### dataone_eml_screen.R

- **`# TaxaExpect --` header -- FIXED (same fix as above).**
- **Combine `.detect_lat_col()`/`.detect_lon_col()`/`.detect_species_col()` -- FIXED.** All
  three were identical in structure (exact-match-then-partial-match against a candidate
  list), differing only in their candidate vectors. Consolidated into a shared
  `.detect_attr_col(attrs, exact, partial)`; the three original functions are now thin
  wrappers supplying their own candidate lists, so every existing call site
  (`.screen_one_eml()`) is unaffected.
- **`@param bbox` clarity -- FIXED.** Now explicitly states it's the query bounding box, with
  units and order spelled out.
- **`has_lat`/`has_lon` alone don't answer "does this dataset have usable coordinates" --
  FIXED.** The function already computed this internally (`has_coords <- (has_lat && has_lon)
  || has_eml_sites`, used to derive `eml_status`) but never exposed it. Added `has_coords` as
  a real output column (all three return paths updated), documented as the column
  `eml_status`/`eml_pass` actually key off.
- **`dataTable` undefined in docs -- FIXED.** `n_tables`'s doc now explains it's the EML
  element type for one rectangular data file within a dataset package.
- **PASTA base URL repeated -- FIXED (see the general comment above).**

### dataone_geo_screening.R

- **Should `harvest_dataone_catalog()`'s already-parsed `spatialCoverage`/coordinates be used
  here instead of an LLM call? -- answered, real gap partially closed elsewhere.** This
  function's own docs already state (correctly) that PASTA's Solr `coordinates` field is
  "unreliably populated" and that spatial filtering happens downstream via EML
  `boundingCoordinates` (`screen_eml_columns()`), not here -- LLM-based geographic screening
  on free-text `geographicdescription` exists specifically because a meaningful fraction of
  real PASTA metadata has no usable structured coordinates at all. That said, the reviewer's
  parallel finding in `dataone_occurrence_search.R` (below) shows the coordinate-extraction
  code itself had a real bug making it look less reliable than the underlying data actually
  is -- now fixed. Whether `build_geo_prompt()` should try a cheap geometric pre-filter before
  falling back to the LLM (now that real coordinates are extractable more often) is a genuine
  design question worth a dedicated look now that the extraction bug is fixed, not attempted
  in this pass.
- **Token cost at scale -- acknowledged, no action.** Real concern, already partially
  mitigated by `call_api()`'s own `max_tokens`; no further change proposed.
- **Curly braces for the multiline `if` at (then) line 507 -- style opinion, not changed.**
  Valid R (no dangling-else ambiguity in this context, since it's a single assigned
  expression, not a block); not a bug.
- **Trailing-period deduplication -- FIXED, real optimization.** Confirmed the reviewer's
  finding directly: `"Andrews Experimental Forest."` and `"Andrews Experimental Forest"` were
  being treated as two distinct descriptions requiring two LLM screening calls. Added a
  trailing-period strip before deduplication; reduces unique descriptions on the real full
  catalog from 1247 to 1239, i.e. fewer redundant LLM calls, per the reviewer's own measured
  finding.

### dataone_occurrence_search.R

- **Broken `@examples` (`bbox = c(-120, 34, -119, 35)`, an unnamed vector) -- FIXED.**
  `search_dataone()`'s own input validation requires a named list
  (`west`/`east`/`south`/`north`); the example as written would error immediately on the very
  first line. Corrected to `bbox = list(west = -120, east = -119, south = 34, north = 35)`.
- **`coordinates_raw` is `NA` for every real record; real PASTA structure is
  `spatialCoverage/coordinates` holding a Solr `ENVELOPE(minX, maxX, maxY, minY)` string, not
  a bare `<coordinates>` node -- FIXED, real bug, the most significant finding in this
  review.** Confirmed via the reviewer's own live example
  (`ENVELOPE(-119.7445915, -119.7445915, 34.400275, 34.400275)` for the real SBC LTER Kelp
  Forest dataset). Two independent problems, both fixed:
  1. `.parse_pasta_response()`'s coordinate-extraction XPath only ever looked for
     `coordinates/coordinate`, bare `coordinate`, or a flat `coordinates` child of
     `<document>` -- never `spatialCoverage/coordinates`. Added that path as a fallback
     (kept the original guessed paths too, in case some other dataset shape uses them,
     matching the file's own "format is unknown until first run" original caveat, now
     partially resolved).
  2. `.parse_coordinates_field()` had no ENVELOPE-format parser at all; a generic 4-number
     fallback heuristic happened to produce the right answer only for the reviewer's own
     degenerate (point) example by coincidence, and was independently confirmed (via direct
     testing) to have the wrong field order (west/east/south/north instead of the correct
     west/east/north/south) for any real, non-degenerate bounding box. Added a dedicated,
     confirmed-format ENVELOPE parser (tried first, unambiguous via the literal `ENVELOPE(`
     keyword) and fixed the fallback heuristic's order bug too.

  Verified with a standalone script against the reviewer's exact real example (correct
  west/east/north/south extracted) and with new tests
  (`tests/testthat/test-dataone_occurrence_search.R`, a new file -- this file had **zero**
  test coverage before this session) covering the ENVELOPE format (degenerate and
  non-degenerate cases, case-insensitivity), the legacy `N:`/`S:`/`E:`/`W:` format, the
  corrected numeric fallback, `.parse_pasta_response()`'s new `spatialCoverage/coordinates`
  path (with a synthetic fixture matching the real SBC LTER structure), and `.bbox_overlaps()`.
- **Format labeling order (why is "Format B" documented above "Format A") -- FIXED,
  cosmetic.** Relabeled the format comments 1 through 5 in actual check order (the new
  ENVELOPE format is now "Format 1"), rather than a letter scheme that didn't match execution
  order.
- **`.bbox_overlaps()` duplicated across files -- design question, flagged, not changed.**
  Confirmed real: `dataone_eml_screen.R`'s `.bbox_overlaps_query()`,
  `dataone_geo_screening.R`'s inline positional-vector version, and this file's
  `.bbox_overlaps()` are three independent implementations of the same axis-aligned
  rectangle-intersection test, with two different calling conventions (named list vs.
  positional vector). Consolidating them is a real, safe-in-principle refactor, but touches
  three files' internal call signatures and would need a small design decision on which
  calling convention wins -- flagged as a good, low-risk candidate for a future session, not
  done here to keep this pass focused on the confirmed bugs.

### dataone_preview.R

- **Could `preview_dataone_occurrences()`'s functionality live inside
  `fetch_dataone_occurrences(preview = TRUE)`? -- answered, not changed.** These serve
  different purposes at different pipeline stages by design: preview is meant to be cheap
  (partial reads, `.get_content_length()`/`.stream_n_rows()`) specifically so a caller can
  decide whether to commit to the expensive full `fetch_dataone_occurrences()` download at
  all. Folding preview into a boolean flag on the expensive function would blur that
  "cheap decision vs. expensive commitment" distinction the two-function split exists for.
- **Stale `%||%` comment ("defined in get_keys_from_context.R... do NOT redefine") -- FIXED.**
  `%||%` has been imported from TaxaTools (via `zzz_imports.R`) for some time, confirmed via
  `NAMESPACE`; `get_keys_from_context.R` no longer defines it locally. Header comment
  corrected, and the adjacent "Dependencies (all in TaxaExpect Imports)" line fixed to
  "TaxaFetch Imports" (same stale-split-comment class as the header banners above).
- **Timing estimate presumably varies with network conditions -- acknowledged, no action.**
  Correct observation; the estimate is already documented as approximate.
- **Enforce bbox as a named vector only, not list-or-vector -- see the general design note
  on inconsistent bbox conventions in `dataone_standardize.R`'s section below.**

### dataone_standardize.R

- **`# TaxaExpect --` header -- FIXED (see the general fix above).**
- **`search_dataone(bbox, scope = "knb-lter-sbc")` in `@examples` -- FIXED, broken example.**
  `search_dataone()` has no `scope` parameter at all; this example would fail with "unused
  argument" immediately. Fixed by removing the invalid argument and adding a one-line note on
  how to actually narrow by scope (`build_geo_prompt(scope_lookup = ...)`, or filtering
  `candidates$scope` directly).
- **20-minute-plus example run -- FIXED.** The "Full run" example
  (`fetch_dataone_occurrences(candidates$id, bbox)`, fetching every candidate with no bound)
  is replaced with a single, known-good, moderate-size real dataset (`"edi.885.1"`, the same
  one already validated to work in `inst/review_function_inputs.R`), with an explicit comment
  explaining why (an unbounded candidate list can take a very long time, confirmed by the
  reviewer's own 20-minute timeout).
- **`"path/to/gbif_sbchannel.csv"`-style hypothetical dataset path, and the
  `gbif_snapshot_path`-adjacent comments (also flagged at what was then "line 261" and the
  `.load_gbif_hashes()`/`.deduplicate_against_gbif()`/`anti_join()` question) -- answered,
  no action: these describe a parameter (`gbif_snapshot_path`) that no longer exists.** It
  and its two internal helpers were removed entirely on 2026-07-23 (see this package's own
  `CLAUDE.md` breaking-changes history), superseded by
  `stack_occurrences(collapse_duplicate_occasions=)`, which does the same species x date x
  location dedup more safely (never matches on incomplete data, unlike the old coalesce-based
  approach). This removal predates this review; these specific comments describe code that
  is simply gone, not a live issue.
- **Bbox coercion by position (`c(west, east, south, north)`) -- design question, flagged, a
  real cross-function inconsistency noted, not changed.** `fetch_dataone_occurrences()` and
  `screen_eml_columns()` both accept either a plain positional numeric vector or a named
  list; `search_dataone()` (same package) requires a named list ONLY, with no vector
  coercion at all -- confirmed as a genuine inconsistency within this one package, not just a
  style preference. The reviewer's specific suggestion (require *only* a named vector/list,
  drop the positional-vector convenience) would be a breaking signature change for several
  real callers across the monorepo that already pass a bare `c(west, east, south, north)`
  vector. Flagged as worth standardizing in a dedicated session (likely toward the more
  defensive named-only form, applied consistently), not done unilaterally here.
- **`unique()` computed twice for the same underlying data -- FIXED.** `.attempt_dwc_join()`'s
  site-dedup block computed `unique(meta$sites$site_code)` twice (once implicitly via
  `dup_codes`'s `duplicated()` filter, once explicitly as `codes`). Reordered so `codes` is
  computed once, before the duplicate-check branch, and reused.
- **`.filter_to_bbox_df()` could be a shared spatial-filtering function -- design question,
  flagged, not changed.** Fair point; scoped together with the `.bbox_overlaps()`
  consolidation question above as one future spatial-utilities-consolidation session, rather
  than two separate partial refactors.
- **Newline in `geographicDescription` breaks site-code extraction (the real "ABUR: Arroyo
  Burro Reef..." example) -- FIXED, real bug, this project's own documented recurring
  footgun.** Confirmed exactly as reported: `.extract_eml_sites()`'s site-code regex
  (`sub("^([^:\\s]+)[:\\s].*$", "\\1", desc, perl = TRUE)`) silently failed to match (and so
  returned the FULL description unchanged, not just the leading code) whenever `desc`
  contained an embedded `\r\n`, because PCRE's `.` does not match newlines without the
  `(?s)` inline flag -- the exact "split-string sprintf"-class footgun this package's own
  `CLAUDE.md` Known R Footguns section already documents for a different function. Fixed
  with `(?s)`; verified against the reviewer's own real example (now correctly extracts
  `"ABUR"`) and a no-newline control case (unchanged, still `"SONGS"`). New tests added
  (`.extract_eml_sites()` had zero test coverage before this session).

### dataone_taxon_screening.R

- **"PASTA" vs. "EDI" naming throughout -- style/naming opinion, not changed.** PASTA is the
  correct, precise name for the actual Solr endpoint queried (`pasta.lternet.edu`); EDI is
  the organization that operates it. Both terms are already used appropriately elsewhere in
  this package's own docs (e.g. `dataone_catalog.R` now names EDI explicitly per the fix
  above); no single rename is clearly better throughout.
- **`trimws()` consistency between `taxon_scope` and `geo_scope` validation -- checked,
  already consistent, no action.** Both validity checks already call `nzchar(trimws(...))`
  internally, and both values are subsequently stored via an explicit `trimws()` assignment;
  this was already consistent in the current source.
- **`df` overwrites `stats::df()` -- FIXED, real coding-standard violation.** The local helper
  `get_col <- function(df, target)` inside `build_taxon_screen_prompt()` is renamed to
  `get_col <- function(input_df, target)`, matching this project's established `df` ->
  `input_df` convention. Purely local (a closure parameter, not an exported argument), so
  this is fully safe with zero external impact.
- **Filtering `NA`/no-text rows twice (once to compute `titles`/`abstracts`/`keywords`, again
  via `get_col(keep, ...)` after subsetting) -- FIXED.** Restructured to subset the
  already-built `titles`/`abstracts`/`keywords` vectors directly by the `has_text` mask
  instead of rebuilding them from a filtered data frame a second time; `nrow(keep)` (used
  twice downstream) replaced with `length(ids_keep)`, and the now-unused `keep` data frame
  removed entirely. Verified against the existing test file
  (`test-dataone_taxon_screening_geo.R`, 36/36 passing unchanged).

### download_gbif_occurrences.R

- **How does this differ from `fetch_gbif_occurrences()`? -- answered, already documented
  elsewhere.** `get_gbif_occurrences.R`'s own roxygen already explains the split (few keys ->
  `fetch_gbif_occurrences()`, no GBIF account needed; many keys ->
  `download_gbif_occurrences()`, async bulk API, account required) and is the recommended
  single entry point (`get_gbif_occurrences()`) that picks between them automatically. Not
  removing `fetch_gbif_occurrences()` -- both are genuinely useful for their own scale, and
  the wrapper already exists for callers who don't want to choose.
- **`data.table` as optional dependency, consider using it more broadly -- see the general
  comment above.**
- **Stale in-code "fix" reference at (then) line 132 -- trimmed, but the underlying
  cache-invalidation warning kept.** Agreed the session-log framing ("before the
  rank-specific fix") doesn't belong in shipped user docs; reworded to state the practical
  consequence plainly (a cache built by an older `taxonKey`-only version silently omits
  records at other ranks) without narrating the fix history. Kept the substance -- not moved
  to `NEWS.md`, since that file is not this project's actual living changelog in practice
  (its own last update predates the vast majority of this project's development; `CLAUDE.md`'s
  own Session Notes serve that role here) and a real, still-relevant safety note would likely
  be lost there rather than found.
- **`year_range` should be required, with no default -- addressed differently, but the
  underlying problem is real and fixed.** The reviewer's concern (a hardcoded default that
  silently goes stale) is correct and was, in fact, already live: the shared default
  `"2000,2024"` (used identically across FIVE functions in this package --
  `download_gbif_occurrences()`, `fetch_gbif_occurrences()`, `get_gbif_occurrences()`,
  `check_geographic_outliers()`, `fetch_occurrences_by_taxon()`) meant every caller relying
  on the default has been silently excluding all 2025+ GBIF occurrence data since the
  calendar turned over -- a real, currently-live data-completeness gap discovered while
  investigating this comment. Rather than requiring the argument outright (which would break
  every caller currently relying on the default, several of which exist across the
  monorepo), a new shared internal `.gbif_default_year_range()` computes `"2000,<current
  year>"` **at call time**, so the default itself can never go stale again. Applied to all
  five functions. See the "Breaking Changes" note below.
- **`year_range` as a required length-2 integer vector instead of a `"YYYY,YYYY"` string --
  design question, not changed.** A real, more intuitive alternative in isolation, but a
  genuine breaking signature/type change across five functions and every real caller
  (workflow scripts, `TaxaExpect::build_priors()`, `TaxaWizard` snippets) that currently
  passes the string form -- the staleness bug this comment was really about is fixed via the
  dynamic-default approach above without that breakage. Flagged as a real "if we were
  starting over" preference, not retrofitted.
- **`bibliographicCitation` possibly duplicating the `attr()` -- checked, they serve different
  purposes, no action.** `bibliographicCitation` (a per-row DwC column, the GBIF download
  portal URL) and any citation-relevant attributes are independent -- the column is what
  travels with the actual occurrence data once combined with other sources via
  `stack_occurrences()`; nothing else in this function attaches an equivalent `attr()`.
- **`readr` fallback -- confirmed correct, no action.** Already falls back to `readr::read_tsv()`
  when `data.table` isn't installed, exactly as documented.
- **Multiple candidate data files found in a downloaded zip, silently takes the first --
  FIXED.** `.read_gbif_zip()` now warns (naming which file was used and which were ignored)
  when its fallback glob matches more than one non-metadata `.csv`/`.txt` file, instead of
  silently discarding the rest via `data_file[1L]`. A standard GBIF SIMPLE_CSV zip has exactly
  one such file (`occurrence.csv`/`.txt`), so this only fires in the unexpected case the
  reviewer flagged.
- **`if (length(use_cols) > 0L)` vs. `if (!is.null(use_cols))` -- checked, current form is
  correct, not changed.** `use_cols` can legitimately be `character(0)` (not `NULL`) when
  `select_cols` was supplied but none of its names matched the file's real columns (a genuine
  case, via `intersect()`). `length(use_cols) > 0L` correctly treats that case the same as
  "no selection" (read every column); switching to `!is.null()` would instead pass
  `select = character(0)` to `fread()`, which does not mean "select everything" and would
  silently break that real edge case.
- **Persistent (not temp-dir) default `cache_dir` -- answered, deliberate, not changed.**
  Real, deliberate design, extensively relied on: resumable-fetch checkpointing (this
  file's and `fetch_gbif_occurrences()`'s core retry/resume architecture, validated through
  multiple real production bug fixes documented in this package's own `CLAUDE.md`) depends
  on the cache surviving across R sessions. A session-scoped temp directory would silently
  disable resumability by design, defeating a feature this package invests heavily in
  elsewhere.
- **0-row output from `inst/review_function_inputs.R`'s example scenario -- acknowledged, not
  a new issue.** Matches this function's own documented caveat about key validity/geometry
  intersection; the working example elsewhere in the same file (lines 165-179 originally)
  demonstrates the function does work correctly with real, intersecting inputs.

### fetch_gbif_occurrences.R

- **Same 0-row `review_function_inputs.R` observation -- see above, same answer.**
- **Definitely faster than `download_gbif_occurrences()`, still unclear why both are needed
  -- see the `download_gbif_occurrences.R` answer above.**
- **`.gbif_checkpoint_path()` vs. `.gbif_dl_meta_path()` similarity -- design question,
  flagged, not merged.** Both build a signature-based cache filename from similar inputs but
  for genuinely different downstream artifacts (a resumable per-chunk fetch checkpoint vs. a
  bulk-download job metadata cache) with different fields (limit vs.
  basis_keep/exclude_absent). A shared low-level "build a signature string from these parts"
  helper is plausible but wasn't attempted this session -- flagged alongside the other
  DRY/consolidation items above for a future pass.
- **Persistent cache suggestion -- see the `download_gbif_occurrences.R` answer above (same
  deliberate resumability design).**
- **"What happens if `chunk_result$aborted` doesn't equal `TRUE`?" -- answered, correct
  control flow, not a gap.** `.fetch_chunk()`'s own documented return contract guarantees
  `$aborted` is always a real `TRUE`/`FALSE` (never missing). When it's `FALSE`, the
  `if (chunk_result$aborted) { ... stop(...) }` block is simply skipped and execution falls
  through to the normal per-chunk bookkeeping immediately below (`results[[i]] <-
  chunk_result$records`, checkpoint save, etc.) -- there is no missing `else` branch, just an
  early-exit `if` followed by the continuation code.
- **"Option 3" (`geometry = NULL` for global search) -- acknowledged as a good design, no
  action needed.**
- **Signed/real bbox values in the cache-key signature, rather than an opaque hash --
  reasonable suggestion, not changed this session.** The current signature
  (`%dk_s%d_g%d_...`) is already collision-resistant enough for its purpose (a
  deterministic re-run producing the same signature); a more human-legible signature is a
  genuine usability nicety, not a correctness issue, and wasn't prioritized against the real
  bugs found elsewhere. `.gbif_checkpoint_path()` was touched this session for a real
  NULL-safety bug (below) -- happy to revisit the signature format alongside a future
  `.gbif_dl_meta_path()` consolidation.
- **Real bug found investigating the `year_range` default question above (not itself a review
  comment, but directly adjacent): `fetch_gbif_occurrences(year_range = NULL)` crashed --
  FIXED.** `geometry = NULL` is documented and supported (unrestricted global search); by the
  same logic a caller might reasonably expect `year_range = NULL` to mean "no year filter"
  too, and in fact exactly this happens for real: `TaxaExpect::build_priors()`'s own
  `year_range` parameter defaults to `NULL` and forwards it straight through. Confirmed via a
  standalone reproduction: `.gbif_checkpoint_path()`'s `gsub("[^0-9]", "", year_range)` on a
  `NULL` silently produces `character(0)`, which propagates through `sprintf()` into a
  length-zero `checkpoint_path`, which then crashes the caller's own
  `if (!is.null(checkpoint_path) && file.exists(checkpoint_path))` check with "argument is of
  length zero" -- a real, live landmine for exactly the `build_priors()` default-argument
  path (confirmed via the actual `inst/TaxaExpect_workflow.R` example call, which omits
  `year_range` entirely and would hit this). Fixed with a `year_tag <- if (is.null(year_range))
  "all" else gsub(...)` guard; new regression test added (this specific crash reproduced and
  fixed, confirmed via a before/after check).

### fetch_occurrences_by_taxon.R

- **Are the `.md` files in `ecosystem_docs` released with the package? -- answered, harmless,
  no action.** The reference (line 7) is a plain source-code `#` comment, not a roxygen
  `@seealso`/link -- it's never compiled into any shipped `.Rd`/documentation and has no
  functional effect either way. It does travel with the raw `.R` source inside a built
  package tarball (comments aren't stripped), but is inert there too. Matches this project's
  broader convention of cross-referencing `ecosystem_docs/*.md` design-discussion files
  throughout its session-note comments.
- **Should this be the only exported GBIF-fetch entry point (not
  `get_gbif_occurrences()`)? -- design question, flagged, not changed.** A reasonable
  argument (this function's own dedup-via-geometry-union is a real, structural fix for a
  problem `get_gbif_occurrences()` alone can reproduce -- duplicate records from overlapping
  per-observation queries), but demoting or hiding `get_gbif_occurrences()` (the documented
  Session 129 recommended entry point, with real callers across the monorepo) is a bigger API
  decision than a review-response pass should make unilaterally. Flagged for the user's own
  call.
- **`@examples` failing under `review_function_inputs.R` but working standalone -- checked,
  same explanation as the other 0-row cases above; not a bug in this file.**

### filter_gbif_quality.R

- **`# TaxaExpect --` reference -- FIXED (see the general header fix above).**
- **Enumerate valid values in `@param` docs -- light-touch, partially addressed.** Several
  params already enumerate their allowed values (`filter_reason`'s possible strings,
  `outlier_status` elsewhere in the package); did not do a full pass adding an explicit
  enumeration to every remaining categorical param this session, given the volume of
  genuinely higher-priority items found in this file.
- **`max_coord_decimal_places` default -- checked, already `NULL` (disabled) by default, no
  change needed.** The reviewer's own stated concern (a real coordinate at a round-number
  lat/lon intersection could be flagged as falsely "imprecise") is exactly why this filter
  should default off -- and it already does; confirmed directly in source.
- **`toupper()`/`trimws()` inconsistency between the `occurrenceStatus` filter and the
  `basisOfRecord` filter -- FIXED, real inconsistency.** `occurrenceStatus` was already
  normalized (`toupper(trimws(...))`) before comparison; `basisOfRecord` was compared via
  exact `%in%` with no normalization at all. Fixed to normalize both sides
  (`toupper(trimws(data$basisOfRecord)) %in% toupper(trimws(basis_keep))`) -- a no-op against
  real GBIF data (which is already consistently upper-case, a strict Darwin Core controlled
  vocabulary) but now defensive against stray case/whitespace drift from any non-GBIF-native
  source merged into the same pipeline. GBIF issue codes (the other place the reviewer
  grouped this concern under, "issues line 190+") are also a fixed uppercase vocabulary with
  the same low practical risk profile and were left as-is. New regression test added.

### get_gbif_occurrences.R

- **Confirms why both `download_gbif_occurrences()` and `fetch_gbif_occurrences()` are kept
  -- no action needed (this file's own docs already answer it).**
- **`year_range` default -- FIXED, see the `download_gbif_occurrences.R` section above (this
  function's default was one of the five updated to the dynamic
  `.gbif_default_year_range()`).**

### get_keys_from_context.R

- **No additional comments -- confirmed, no action.**

### literature_search.R

- **Line 32 rewrite suggestion (match the clearer phrasing at lines 138-139) -- style, not
  changed this session.**
- **Line 79 version reference -- checked; refers to this package's own version, kept current
  as part of routine maintenance, no drift found this session.**
- **`taxon_scope` as a single string vs. a character vector -- design question, not changed.**
  A real, reasonable API improvement, but a signature-shape change to an exported function
  with real callers; not attempted as a drive-by fix.
- **Rename `taxon_scope` -> `query_scope` (it searches title/abstract text, not a strict
  taxonomic filter) -- design/naming question, not changed.** Fair point about the name being
  slightly misleading about what it actually filters on; a rename is easy mechanically but is
  still a breaking rename for an exported parameter with real callers -- flagged for the
  user's own call rather than renamed unilaterally.
- **Same question for `geo_scope` -- same answer.**
- **`bbox` accepted but not used to filter the OpenAlex query -- answered, intentional,
  already documented.** This file's own header (`# Design` section) already states plainly
  that "bbox is stored as metadata only -- does not affect the OpenAlex query," precisely
  because OpenAlex offers no real geospatial filtering on paper metadata; `geo_scope`
  (free-text place names, AND-combined with `taxon_scope`) is the actual filtering mechanism.
  This is a documented, deliberate design, not an oversight -- exactly the "verify the
  code's actual purpose before flagging a flaw" case.

### make_bbox_wkt.R

- **British spelling of "centre" -- style opinion, not changed.** Used consistently
  throughout the file; an author preference, not an error, and not an ASCII-policy violation.
- **Use `sf::st_buffer()`/`st_bbox()` instead of hand-rolled math -- design question,
  considered, not changed.** The reviewer's own hedge ("I'm not sure if all the parameters
  would be correct") was warranted: a geodesic/planar `sf` buffer is a materially different
  concept from this function's own explicitly-documented "square in degree-space, not
  physical distance" design, and would change the actual output coordinates near high
  latitudes, not just the implementation. The pole/antimeridian edge cases the reviewer
  wondered might motivate the switch are already handled correctly today with explicit,
  clear `stop()` errors (not silent clamping) -- confirmed by re-reading the function
  directly. A real, deliberate simplicity-over-generality trade-off; flagged as a "v2"
  candidate, not a bug.

### pdf_api.R

- **Send `extract_pdf_text()`'s plain text instead of page images, for cheaper screening --
  answered, already the design.** `pdf_text.R`'s own header confirms this is already exactly
  how the pipeline works: Stage 1 (screening) and Stage 2 (characterization) already use
  text-only extraction via `extract_pdf_text()`/`screen_pdf_structure()`; only Stage 3 (this
  file, the final extraction step) sends page images, deliberately, for the visual/table
  fidelity a text-only pass loses. Not a design gap -- the reviewer's suggested approach is
  already stages 1-2's behavior.
- **Explicit Anthropic references (lines 3-30) predating Session 87's provider generalization
  -- FIXED, matches the task's own framing exactly.** The file header still said "Send PDF
  page images to the Anthropic API" and described "Extends `call_anthropic_api()`," even
  though the actual function body has dispatched through the provider-general
  `TaxaTools::call_api()` for some time (confirmed: `call_api_pdf()`'s own roxygen already
  correctly documented "Any vision-capable provider works: Anthropic..., Gemini..., OpenAI...,
  Ollama..." -- only the top-of-file banner comment was stale). Fixed the header to match the
  real, already-general implementation. The equivalent stale claim in this package's own
  `CLAUDE.md` Function Inventory table (`call_api_pdf()` listed as "Anthropic-only") was found
  and fixed too while verifying this.
- **Lines 84-90/106-112 (subprocess vs. in-process rendering) directly duplicated -- FIXED.**
  Extracted the shared render-page-to-base64-PNG logic into one `.render_one_page_b64()`
  helper, called both directly (in-process fallback) and passed to `callr::r()` (subprocess
  path). Verified this doesn't change behavior under `callr::r()`'s serialization (a real
  risk worth checking, since the function moved from an anonymous closure with no package
  dependency to a named internal package function): confirmed end-to-end against a real
  bundled PDF, both via the subprocess path and the in-process fallback, in a fresh session.
- **Indentation of `call_api_pdf()`'s argument list "way off" -- FIXED.** Corrected
  continuation-line indentation to align with the opening parenthesis (was indented ~35
  spaces, evidently left over from a prior longer function name).
- **Failed to find sections during testing -- traced to and fixed in `pdf_text.R`, see
  below.**

### pdf_characterize.R

- **No additional comments -- confirmed, no action.**

### pdf_extract.R

- **`observation_type`/`location_structure`/`data_density`/`taxonomic_scope`/
  `contamination_risk` all came back `NA` on a real bundled PDF, and stayed `NA` through
  prompt building ("Currently only replaces NULL, NA persists") -- FIXED, real bug, matches
  the task's own framing exactly.** Confirmed the root cause directly:
  `screen_pdf_structure()` explicitly returns `NA_character_` (not `NULL`) for these fields
  in its own documented failure-fallback object (`pdf_characterize.R`), but this file
  defaulted them with `pdf_structure$field %||% "default"` -- and TaxaTools's `%||%`
  (exported, used ecosystem-wide, deliberately NULL-only per this project's own conventions)
  only substitutes on `NULL`, leaving a real `NA` unresolved. `taxonomic_scope` specifically
  is never consumed downstream in this file (only displayed via `screen_pdf_structure()`'s
  own, already-correct `print` method), so no fix was needed for it; the other four are used
  to drive real extraction-prompt branching and were all fixed. Added a new
  `.axis_or_default()` helper (NULL-or-NA-safe) and replaced every `%||%` use for these four
  fields (5 call sites: `.build_axis_instructions()`, `build_pdf_extract_prompt()`'s
  skip-check, the `print.pdf_extract_prompt()` display, and `parse_pdf_extract_response()`).
  This did **not** touch the shared `%||%` operator itself -- that stays NULL-only, matching
  its documented, relied-upon ecosystem-wide semantics; only this file's specific misuse of
  it for a field with a documented NA contract was fixed. Verified end-to-end with an
  all-`NA` `pdf_structure` fixture (now correctly falls through to the "field_survey"
  default instead of silently producing broken/empty instructions) and new tests (this file
  had zero test coverage before this session).
- **Session-log-style comments ("Session 24: initial implementation") -- answered, deliberate
  convention, not removed.** This reflects this whole ecosystem's own, explicit,
  extensively-used convention of citing session numbers/dates throughout code and
  `CLAUDE.md` as a deliberate historical record (required by this project's own "Reminder for
  Claude" section) -- not stray, removable noise. Left as-is.
- **`.pdf_dwc_cols` duplicated verbatim as a local `dwc_cols` vector in
  `dataone_standardize.R` -- FIXED.** Confirmed character-for-character identical (all 20
  column names, same order). `dataone_standardize.R` now references `.pdf_dwc_cols` directly
  instead of hand-copying the literal vector; a comment on `.pdf_dwc_cols`'s own definition
  now notes it's shared, so the "pdf"-prefixed name doesn't mislead a future reader in that
  file.
- **A/B/C literal interpretation by the LLM -- answered, accepted risk, no action.** A fair
  question about how literally an LLM will interpret lettered examples in a prompt; not
  something to "fix" in code -- prompt wording is inherently probabilistic and this specific
  phrasing wasn't reported as causing an observed failure.
- **What if coordinates are given in a different CRS? -- answered, out of scope, consistent
  with the rest of the pipeline.** This whole package (GBIF, DataONE, PDF extraction alike)
  assumes WGS84 decimal degrees throughout, matching GBIF's own coordinate convention; PDF
  extraction inheriting the same assumption is consistent, not a gap specific to this file.
- **`gsub("```[a-z]*", "", raw_text)` followed by a redundant second `gsub("```", "", ...)`
  call -- FIXED, but not via the reviewer's own suggested one-liner.** Verified directly:
  the reviewer's suggested single-call replacement (`gsub("```", "", raw_text)` alone) would
  actually be WORSE, leaving the language-tag word behind as stray text (e.g. `"csv\n..."`
  instead of a clean `"\n..."`). The REAL simplification is that the existing first call
  (`gsub("```[a-z]*", "", raw_text)`, whose `[a-z]*` already matches zero-or-more characters)
  already produces byte-identical output to the two-call version on its own -- confirmed by
  direct comparison. Dropped the redundant second call; kept the first exactly as it was.
- **Newline characters removed then re-added -- reviewed, no clear actionable issue found;
  not changed.** Looked at this but could not identify a concrete problem beyond the general
  observation that the removal/re-addition happens in two different places; given the volume
  of higher-confidence, verified fixes elsewhere in this file, this was not pursued further
  this session.
- **`.strip_to_binomial()` could live in TaxaTools and be reused -- design question, flagged,
  not changed.** Checked `TaxaTools::clean_taxon_names()` directly: it solves a related but
  different problem (underscore-to-space normalization, `sp.`/`spp.` trimming, capitalization
  filtering) and does not strip trailing author-authority tokens
  (`"Homo sapiens Linnaeus, 1758"` -> `"Homo sapiens"`), which is this function's specific
  job. Moving/merging it into TaxaTools is architecturally sound in principle (TaxaTools is
  upstream of TaxaFetch in the dependency chain) but requires reconciling two functions with
  genuinely different responsibilities -- flagged as a real candidate for a future session,
  not a same-session merge.
- **`.coerce_numeric_col()`/`.coerce_integer_col()` seem to just do what `as.numeric()`/
  `as.integer()` already do -- answered, they add real value, not changed.** Verified
  directly: both suppress R's own generic "NAs introduced by coercion" warning and replace it
  with a column-name-specific, count-specific warning (`"Column 'X': N value(s) could not be
  coerced..."`), which matters in a pipeline processing many DwC columns from noisy
  LLM-extracted text -- a generic warning with no column context would be far less
  actionable. Not pointless duplicates.
- **`field_survey` returned as a default even when `observation_type` is genuinely unknown,
  not actually "field survey" -- FIXED as part of the NA-defaulting bug fix above.** Once
  `.axis_or_default()` correctly resolves a real `NA` to the documented default instead of
  leaving it unresolved, this concern is addressed the same way: the default is now reached
  deliberately (a real fallback for missing classification), not accidentally masked by a
  broken defaulting operator.
- **`df` overwrites `stats::df()` (reviewer noted "I've made this comment before") -- FIXED,
  real coding-standard violation, a second real instance beyond
  `dataone_taxon_screening.R`.** `parse_pdf_extract_response()`'s local result data frame was
  named `df` throughout (10+ uses). Renamed to `occ_df` across the whole function scope
  (lines 668-795), a purely local, mechanical, zero-external-impact rename. Verified against
  the new test file (all passing).
- **Suggest the `else` branch on a categorical field be `NA_character_` (originally "line
  698") -- reviewed, could not confidently relocate this specific line given how much line
  numbering shifted from the other fixes in this file; the general principle (NA on
  genuinely-missing data, not a silent default string) is already followed correctly
  elsewhere in this file's actual DwC column construction (e.g. `.coerce_numeric_col()`/
  `.coerce_integer_col()` already return `NA` on coercion failure). No change made for lack
  of a confidently-identified target.**

### pdf_text.R

- **Does including `"results and discussion"` in the section vocabulary affect anything --
  answered, no issue found.** It's one more recognized header-text variant in
  `.section_patterns`, treated like any other; no interaction problem identified.
- **Section-header detection fails for numbered headers (`"2.1 Results"`) and headers
  starting mid-row in two-column layouts -- the numbered case FIXED (real bug); the
  second-row case remains an acknowledged, pre-existing limitation, as the reviewer
  themselves noted it already is.** Traced precisely: Pass 2 of `.match_header()` (the
  two-column-layout handler, for a header interleaved with right-column prose on one line)
  strips nothing before testing `^[A-Z][A-Z &]{2,39}(?=\s)` against the raw line -- so a
  numbered header like `"2.1 RESULTS ... [right-column prose]"` never matches at all, since
  the line starts with a digit, not a letter. Pass 1 (single-column headers) already applies
  a leading-section-number strip; Pass 2 now applies the identical strip before its own
  match, closing exactly the gap the reviewer identified as "seems solvable." Verified with
  both a numbered and an unnumbered two-column example. The header-spanning-two-physical-rows
  case is a materially harder fix (needs multi-line lookahead across the calling loop in
  `.detect_pdf_sections()`, not just within `.match_header()`'s single-line view) and was
  left as the pre-existing, documented limitation it already was -- not attempted this
  session. New test file added (`test-pdf_text.R`; this file had zero test coverage before
  this session), scoped to the specific fix.

### report_fetch.R / stack_occurrences.R / TaxaFetch-package.R / zzz_imports.R

**No comments in these files; no action needed.**

### Files not covered by this review

`check_geographic_outliers.R`, `dedupe_occurrences.R`, and `fetch_inat_occurrences.R` are
not in `taxafetch_review.Rmd`'s file list at all -- all three postdate the review (added
2026-07-20 through 2026-07-24). `check_geographic_outliers.R` did receive one incidental fix
this session (its `year_range` default, part of the five-function dynamic-default fix
described under `download_gbif_occurrences.R` above), since it shared the exact same stale
hardcoded default as the five files the review's `year_range` comment was actually about.

------------------------------------------------------------------------

## Real bugs fixed (summary, with file:line)

1. **`dataone_occurrence_search.R`** -- `search_dataone()`'s coordinate extraction never
   matched PASTA's real `spatialCoverage/coordinates` XML structure or its Solr
   `ENVELOPE(...)` format; `coordinates_raw` was `NA` for every real record, and the
   fallback numeric-order heuristic had the wrong field order for non-degenerate boxes.
   Fixed in `.parse_pasta_response()` (~line 380) and `.parse_coordinates_field()` (~line
   424). Broken `@examples` (unnamed bbox vector) also fixed.
2. **`dataone_catalog.R`** -- `authors`/`keywords_str` came back `NA` for every real record;
   XPath now tries multiple real candidate node shapes. `.xml_collapse()` (~line 261).
3. **`dataone_standardize.R`** -- `.extract_eml_sites()`'s site-code regex silently failed on
   any `geographicDescription` containing an embedded newline (missing PCRE `(?s)` flag), the
   same documented footgun class as elsewhere in this codebase. ~line 732. Broken
   `search_dataone(scope=...)` example also fixed.
4. **`fetch_gbif_occurrences.R`** -- `.gbif_checkpoint_path()` crashed (`"argument is of
   length zero"`) when `year_range = NULL` was passed explicitly with `cache_dir` enabled --
   a real, reachable path via `TaxaExpect::build_priors()`'s own default. ~line 336.
5. **`fetch_gbif_occurrences.R`, `download_gbif_occurrences.R`, `get_gbif_occurrences.R`,
   `check_geographic_outliers.R`, `fetch_occurrences_by_taxon.R`** -- shared hardcoded
   `year_range` default `"2000,2024"` silently excluded all 2025+ GBIF data for any
   default-argument caller; replaced with a call-time-computed
   `.gbif_default_year_range()`.
6. **`filter_gbif_quality.R`** -- `basisOfRecord` filter compared exact case/whitespace,
   inconsistent with the `occurrenceStatus` filter's own normalization. ~line 322.
7. **`pdf_extract.R`** -- `%||%`'s NULL-only semantics silently failed to default
   `observation_type`/`location_structure`/`data_density`/`contamination_risk` when
   `screen_pdf_structure()` returned its documented `NA_character_` failure value. New
   `.axis_or_default()` helper, 5 call sites fixed.
8. **`pdf_text.R`** -- `.match_header()`'s two-column-layout Pass 2 never matched a numbered
   header (`"2.1 RESULTS"`) since it never stripped the leading number before testing.
   ~line 146.
9. **`pdf_api.R`** -- broken `@examples` for `build_pdf_extract_prompt()` (wrong parameter
   names entirely -- `pdf_meta`/`taxon_scope`/`bbox`, none of which exist on the real
   function).

------------------------------------------------------------------------

## Breaking changes / behavioral changes from this response

None of the fixes above change any exported function's **signature**. Two are genuine
**behavioral** changes to existing exported functions, both strict improvements (never make
a previously-correct call incorrect):

- `fetch_gbif_occurrences()`, `download_gbif_occurrences()`, `get_gbif_occurrences()`,
  `check_geographic_outliers()`, `fetch_occurrences_by_taxon()`: `year_range`'s default
  changed from the fixed literal `"2000,2024"` to `.gbif_default_year_range()` (`"2000"`
  through the current year, computed at call time). Any caller that already passes its own
  explicit `year_range` is completely unaffected. A caller relying on the default now
  correctly picks up 2025+ data it was previously silently missing.
- `filter_gbif_quality()`: the `basisOfRecord` filter is now case/whitespace-insensitive.
  A no-op against real GBIF data (already consistently upper-case); only changes outcomes
  for a hypothetical non-GBIF-native `basisOfRecord` value that happens to differ from
  `basis_keep` only in case/whitespace, which was previously (incorrectly) dropped.

Both rows are added to `TaxaID/CLAUDE.md`'s Recent Breaking Changes table. No other package
in the monorepo was found (via a full-repo grep) to depend on the specific stale
`year_range` default value or on `basisOfRecord`'s exact-match behavior, so no cross-package
changes were needed.

------------------------------------------------------------------------

## New/updated test coverage

New test files (previously zero coverage): `test-dataone_occurrence_search.R`,
`test-pdf_text.R`, `test-pdf_extract.R`. Additions to existing files:
`test-dataone_standardize.R` (`.extract_eml_sites()` newline bug), `test-fetch_gbif_occurrences.R`
(`.gbif_checkpoint_path()` NULL-year_range bug, `.gbif_default_year_range()`),
`test-filter_gbif_quality.R` (`basisOfRecord` case/whitespace insensitivity).

------------------------------------------------------------------------
