# TaxaFetch Peer Review Response

**Review date:** 2026-07-09 **Package version reviewed:** TaxaFetch 0.1.0 **Response prepared by:** K. D. Lafferty

This document responds to `inst/taxafetch_review.Rmd`. That review was conducted and fixed
in a single pass (Session 148), with two design decisions made by K. D. Lafferty before
implementation -- this document records those decisions and confirms, on re-verification,
that all fixes are present and unchanged in the current codebase. No code changes were made
in the course of preparing this response; the package had not been touched since the review
session (`git log` shows no commits to TaxaFetch between the review commit and this
response). Re-verified: `devtools::check()` 0 errors, 0 warnings, 0 notes; `devtools::test()`
459 expectations, 0 failures (2 expected skips, 6 expected warnings from tests deliberately
checking warning messages); `lintr::lint_dir("R")` 0 issues.

------------------------------------------------------------------------

## Code Review

### Functionality / Optimizations / Coding standards

**No changes needed / fixed.** Confirmed as reported: consistent organization across all 24
files; `fetch_occurrences_by_taxon()` documents its own GBIF WKT-complexity scaling
limitation rather than leaving it undiscovered. Two doc-accuracy gaps fixed and verified
present: `get_gbif_occurrences()`'s `@param rank_filter` now states the
`SUBSPECIES`/`VARIETY`/`FORM`-exclusion behavior (`R/get_gbif_occurrences.R`); the
`"LOOKUP_RECOVERED"` `matchType` value is documented in `get_keys_from_context()`'s enum and
review-advice list (`R/get_keys_from_context.R`).

### Automated tests

**Confirmed.** `devtools::test()`: 459 expectations, 0 failures, 0 errors (re-verified this
session).

### Vulnerabilities

**SSRF via third-party EML metadata (Medium-High, fixed).** *Decision (K. D. Lafferty): add
a host allowlist.* Confirmed present: `.pasta_trusted_hosts` / `.is_trusted_pasta_url()`
(`R/dataone_standardize.R:486-496`), restricting requests to `pasta.lternet.edu` and
`pasta.edirepository.org`. Both call sites (`.download_data_table()` in
`dataone_standardize.R`, `.preview_one_entity()` in `dataone_preview.R`) skip untrusted URLs
with a clear reason rather than requesting them. 6 tests covering accepted/rejected hosts
(including a cloud metadata-endpoint address and `localhost`), non-`https` schemes, and
unparseable input confirmed present and passing (`test-dataone_standardize.R`,
`test-dataone_preview.R`).

**Zip-slip (Low, hardened defensively).** Confirmed present: `.read_gbif_zip()`
(`R/download_gbif_occurrences.R:535`) rejects absolute paths and `..` traversal segments
before extraction.

Everything else the review checked and found not exploitable (command injection, XXE,
unsafe deserialization, path traversal, PDF magic-byte validation) required no changes and
was not re-tested this session -- no code in those areas has changed since the review.

------------------------------------------------------------------------

## Domain Review

### Scientific Rigor

**Homonym misresolution in `get_keys_from_context()`'s `HIGHERRANK` recovery path
(Medium-High, fixed).** *Decision (K. D. Lafferty): filter `name_lookup()` hits by kingdom
before voting.* Confirmed present: `.recover_higherrank()` accepts a `context` parameter and
narrows `rgbif::name_lookup()` hits to the matching kingdom before the majority vote,
falling back to the previous unfiltered behavior when no kingdom context is available
(`R/get_keys_from_context.R`, called with `context = rank_values` at line 208). 3 tests using
a synthetic mixed-kingdom fixture confirmed present and passing.

**BioTime `occurrenceStatus` conflated missing data with confirmed absence (Medium,
fixed).** Confirmed present: `read_biotime_study()` (`R/biotime_fetch.R:237`) sets
`occurrenceStatus` to `NA` when neither `ABUNDANCE` nor `BIOMAS` parses to a number,
`"absent"` only for an explicit valid zero. Verbose-mode row-count message confirmed present
(line 247). 3 tests confirmed present and passing.

**eDNA-exclusion pattern was overly broad (Low-Medium, fixed).** Confirmed present:
`filter_gbif_quality()`'s `edna_pattern` (`R/filter_gbif_quality.R:265`) is narrowed to
`edna`/`environmental dna`/`metabarcod`; the generic `"bulk sample"`/`"water sample"`
phrases were removed, with an inline comment explaining why. 1 test confirmed present and
passing.

### Outputs

**`make_bbox_wkt()`'s km-conversion reference was latitude-dependent but undisclosed (Low,
doc fix).** Confirmed present: `@param radius_deg` (`R/make_bbox_wkt.R:17-20`) states the
`cos(latitude)` caveat with concrete examples (about 78 km at 45 degrees, about 39 km at 70
degrees).

**`get_gbif_occurrences()`'s `rank_filter` default silently excludes subspecies-level
records (Low, doc fix, behavior unchanged).** Confirmed present (see Coding standards
above). No behavioral change was made, per the review's own assessment that the existing
default is plausibly intentional.

### Algorithms

**No changes needed.** No code in the algorithms the review examined
(`fetch_occurrences_by_taxon()`'s geometry union/combine, `stack_occurrences()`'s `gbifID`
dedup, `check_inat_range()`'s point-in-polygon logic, the DataONE screening prompts, the
other six `filter_gbif_quality()` filters) has changed since the review.

------------------------------------------------------------------------

## File-specific comments

All file-level changes listed in `taxafetch_review.Rmd`'s "File specific comments" section
were re-checked directly against the current source and confirmed present, unmodified since
the review commit:

- `R/dataone_standardize.R` -- SSRF allowlist + `.recover_higherrank()` context-passing.
- `R/dataone_preview.R` -- host-allowlist guard on the HEAD/stream calls.
- `R/get_keys_from_context.R` -- `matchType` enum/advice + `LOOKUP_RECOVERED` summary count.
- `R/biotime_fetch.R` -- NA-vs-absent `occurrenceStatus` derivation and roxygen.
- `R/filter_gbif_quality.R` -- narrowed `edna_pattern`.
- `R/make_bbox_wkt.R` -- latitude-dependent caveat.
- `R/get_gbif_occurrences.R` -- `rank_filter` subspecies caveat.
- `R/download_gbif_occurrences.R` -- zip-slip entry-path check.
- `.lintr` -- `dataone_preview.R:544` `object_usage_linter` exclusion present.
- Test files `test-dataone_standardize.R`, `test-dataone_preview.R`,
  `test-get_keys_from_context.R`, `test-biotime_fetch.R`, `test-filter_gbif_quality.R` all
  present with the counts the review reports.

No package code has changed since the review session (confirmed via `git log`), so nothing
needed to be reapplied or reconciled with newer work.

------------------------------------------------------------------------
