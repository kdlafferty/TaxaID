# TaxaLikely Peer Review Response

**Review date:** 2026-07-30 **Package version reviewed:** TaxaLikely 0.1.0 **Response prepared by:** K. D. Lafferty

This document responds to each comment in the TaxaLikely code and domain review
(`inst/taxalikely_review.Rmd`). Unlike the TaxaTools review, this review was conducted by
Claude Code itself (using the ecosystem's standard `Code and Domain Review 2.Rmd` template)
and all 9 findings were fixed in the same session the review was written, following the
`TaxaFetch/inst/taxafetch_review.Rmd` precedent of combining findings and fixes into one
document rather than a separate response. This file exists as a companion index in the
TaxaTools/TaxaHabitat response-document format, since no standalone response document had
been written for this package. **No new edits were made to produce this document** — it
summarizes and cross-references `inst/taxalikely_review.Rmd`'s own record, and the current
source tree (2026-08-01) was spot-checked against that record's claims before writing this
(see Verification section below): all 9 fixes are still present, unchanged since 2026-07-30.

------------------------------------------------------------------------

## Checklist Items

### Automated tests

**Confirmed passing.** `devtools::test()`: 925 expectations, 0 failures, 0 errors, 9
expected warnings (8 from `assign_scores(score_type = "none")` tests deliberately
triggering a warning; 1 environmental S4-dispatch warning from `pwalign`/`Biostrings`),
1 environment-dependent skip.

### Vulnerabilities

**None found.** Checked SSRF (all external hosts hardcoded or reached only via path segment
on a fixed host, unlike TaxaFetch's earlier DataONE finding), unsafe deserialization (every
`readRDS()` reads only files this package's own functions wrote), command injection,
zip-slip (n/a, no archive extraction), XXE (NCBI XML parsed via `xml2::read_xml()`, no
external entity resolution by default), credentials (all via env vars/explicit params, none
hardcoded), and path traversal (cache filenames sanitized; local-file-reading functions
reading a caller-supplied path directly is expected behavior for that function's purpose,
not a vulnerability).

------------------------------------------------------------------------

## Findings and Responses

### 1. `.lintr`'s `R/train.R` `object_name_linter` exclusion line numbers had drifted

**Fixed.** Updated to the real current hit lines. Re-verified a second time after finding 2's
own edit shifted the lines again (`.lintr` now reads `c(901, 936, 1076, 1092, 1100)`).

### 2. Six residual cosmetic lints in `R/` (4 brace_linter, 1 semicolon_linter, 1 line_length_linter)

**Fixed.** `R/evaluate.R:632,641,650,651` and `R/support_curves.R:256` — braces added to
both branches of each `if`/`else`, matching each file's own established convention (checked
first, not applied by rote). `R/support_curves.R:335` — a semicolon-joined two-statement
line split into two lines. `R/train.R:714` — a 143-character `sprintf()` string wrapped via
`paste0()`, matching this package's existing convention for long diagnostic strings.

### 3. `df` used as a local variable name, shadowing `stats::df()`

**Fixed.** Renamed per-file to reflect what each variable actually holds, not a mechanical
find/replace: `ref_seqs` (`R/build_sequence.R`), `seq_df` (`R/trim_to_amplicon.R`),
`crabs_df` (`R/read_crabs.R`). Confirmed each was function-local and unreferenced by any
test before renaming, and that the substitution never matched inside the unrelated
`reference_df` parameter name.

### 4. Duplicated ~25-line NCBI species-enumeration block (`R/coverage.R`)

**Fixed.** Extracted into a new shared helper, `.ncbi_species_enumerate()`. The two original
blocks were read carefully before merging (per the task's own caution) and found NOT
byte-identical: the primary-source call warns on failure, the fallback call fails silently
(avoiding a doubled warning for a lookup the caller already knows was unproductive). This
real asymmetry was preserved via a new `warn_on_error` parameter rather than silently
picking one behavior for both call sites.

### 5. Four duplicated retry-loop implementations (`R/fetch.R`)

**Fixed.** Extracted into a new shared helper, `.retry_fetch()`. Unlike finding 4, the four
loops were confirmed genuinely identical in attempt count, backoff, and error handling
before merging, so no behavioral parameterization was needed.

### 6. `interpret_model()`'s reused `mu_score`/`mu_gap` names created a fragile scoping dependency

**Fixed.** The two outer scalars were renamed to `global_mu_score`/`global_mu_gap`
throughout the "Hypothesis baselines"/"Global H1 profile" sections. Per the task's explicit
instruction, `H1_Lookup`'s own `mu_score`/`mu_gap` columns (a real, ecosystem-wide column
pair used elsewhere and consumed by other functions) were **not** renamed — this was a
scoping-clarity fix at the one call site relying on shadow precedence, not a schema change.

### 7. No `Depends: R (>= 4.1.0)` in `DESCRIPTION` despite `|>`/`\(...)` usage

**Fixed.** Field added; confirmed the `R CMD build` auto-detection warning no longer
appears and `R CMD check`'s own status remains 0/0/0.

### 8. `inst/TaxaLikely_workflow.R` (superseded, "retained for reference") hardcoded a personal absolute path

**Fixed.** Line 252 now uses the same `system.file()`-based pattern already used a few lines
above for the companion `.rds` file.

### 9. Two stale cached `.rds` files in `inst/` tied to the superseded workflow script

**Deleted.** `inst/real_matrix.rds` (9.5 KB) and `inst/real_likelihoods.rds` (972 KB) —
confirmed via a whole-monorepo grep that no `R/`, `tests/`, or other TaxaLikely file reads
either path before deleting. Two references in *other* packages' own workflow scripts
(`TaxaAssign/inst/TaxaAssign_bayesian_workflow.R`, `TaxaAssign/inst/Wrapper_full_workflow.R`)
were flagged, not touched — outside TaxaLikely and outside anything `devtools::check()`/
`test()` exercises. Regenerating them requires re-running `inst/TaxaLikely_workflow.R`'s
Stage B end to end (network + DECIPHER access) — left for the author.

------------------------------------------------------------------------

## Domain Review

**No new findings.** Scientific rigor, output comparability, and algorithm consistency were
all re-confirmed against this package's already-extensive session history (the
`sqrt_mismatch` transform choice, the `H1_Lookup$sigma_score` squaring bug, per-genus H2
shrinkage, the evidence-ratio crossover gate, the Jeffreys-smoothing fix for
`Confusion_Risk_Curves`) rather than re-litigated. None of the 9 fixes above touch any
statistical/domain logic — all are cosmetic, refactoring, packaging, or debris-cleanup, with
confirmed identical behavior (finding 4's `warn_on_error` split is the one preserved,
parameterized behavioral difference, not a new one).

------------------------------------------------------------------------

## Verification (this document, 2026-08-01)

Spot-checked the current source tree against every finding above before writing this
document, since the packages have been edited since the review was performed:

- `DESCRIPTION` still has `Depends: R (>= 4.1.0)`.
- `.lintr` still has the corrected `R/train.R` exclusion line numbers.
- `R/interpret.R` still uses `global_mu_score`/`global_mu_gap`.
- `R/coverage.R` still has `.ncbi_species_enumerate()`, called from both sites.
- `R/fetch.R` still has `.retry_fetch()`.
- `R/build_sequence.R`/`R/trim_to_amplicon.R`/`R/read_crabs.R` still use
  `ref_seqs`/`seq_df`/`crabs_df`.
- `inst/real_matrix.rds`/`inst/real_likelihoods.rds` remain deleted.

All 9 fixes are intact and unchanged since the 2026-07-30 review session. `TaxaLikely/
CLAUDE.md`'s own session history confirms no further edits to this package occurred between
the review and this verification.

------------------------------------------------------------------------
