# TaxaTools Peer Review Response

**Review date:** 2026-06-27 **Package version reviewed:** TaxaTools 0.1.0 **Response prepared by:** K. D. Lafferty

This document responds to each comment in the TaxaTools code review. Changes were implemented across three phases and verified with `devtools::check()` (0 errors, 0 warnings, 0 notes; 680 tests passing).

------------------------------------------------------------------------

## Checklist Items

### Automated tests — "testthat.R fails to run"

**Root cause identified and fixed.** The reviewer ran tests using `testthat::test_dir()` on an installed package, which does not expose internal objects (those prefixed with `.`). Two test files accessed internal objects directly (`.registry_env`, `.get_registry`, `.resolve_model`) in ways that work with `devtools::test()` (which calls `load_all()`) but fail on an installed package.

**Fix:** All internal-object access in `test-model_registry.R` and `test-call_api.R` updated to use `get("<name>", envir = asNamespace("TaxaTools"))`, which works in both contexts.

The warning in `test-llm_utils.R` is a pre-existing, known issue unrelated to the reviewer's environment.

------------------------------------------------------------------------

## General Comments

### `azure` name collision with R color

**Fixed.** Provider renamed from `"azure"` to `"azure_openai"` and function from `call_azure_api()` to `call_azure_openai_api()` throughout the package ecosystem (TaxaTools: `R/call_api.R`, `R/llm_api_utils.R`, `R/model_registry.R`, `R/zzz.R`, `inst/model_tiers.json`, `tests/`; TaxaWizard: `R/zzz.R`, `R/shiny.R`).

### `df` parameter name

**Fixed.** Renamed `df` → `input_df` in all exported functions where it appeared as a parameter name: `rename_cols()`, `detect_ranks()`, `create_taxon_names()`, `find_taxonomy_conflicts()`, `to_faire()`, `change_backbone()`. (Note: `df` used as a local variable name within `@examples` sections is acceptable R convention and was left unchanged.) Associated tests updated to match the new error messages.

### Package scope (two distinct tasks: LLM + taxonomy)

**Noted, not actioned.** The packages are divided by purpose rather than by architecture. TaxaTools intentionally bundles both task families because the LLM provider functions are a shared dependency required by every other TaxaID package (TaxaFetch, TaxaHabitat, TaxaExpect, TaxaAssign, TaxaFlag). Splitting into two packages would create an additional dependency layer without clear user benefit at this stage.

### `ellmer` / tidyverse LLM package

**Noted, not actioned.** The `ellmer` package was considered. TaxaTools LLM functions predate its public availability and are built around the TaxaID-specific `llm_fn` dispatch pattern (which allows user-swappable providers as function arguments). Adopting `ellmer` would require redesigning this interface. The tradeoff may be worth revisiting.

### Security / LLM data sensitivity warning

**Fixed (Phase 3).** A `@details` "Data sensitivity" section was added to `call_api()` warning that cloud LLM providers transmit prompts to third-party servers and recommending `provider = "ollama"` for sensitive data. The same note was added to the `.onAttach()` startup messages for both the single-provider and multi-provider paths in `zzz.R`.

### Lintr for minor formatting

**Fixed (Phase 3).** `lintr::lint_package()` run on TaxaTools. A `.lintr` config was added setting `line_length_linter(120L)` (the default 80-char limit is stricter than CRAN requires and impractical for long string literals) and suppressing `indentation_linter` (off-by-one hanging-indent variations throughout). All substantive issues resolved: commented-out code blocks (25) rephrased; brace style (10) fixed in anonymous function bodies and `if/else` branches; spaces inside parentheses (3) and a single-quote string (1) fixed; internal helper `.extract_rank_from_classification` (34 chars) renamed to `.extract_classified_rank` (23 chars) to satisfy `object_length_linter`. 0 remaining issues in R/ source files.

### README.Rmd

**Fixed (Phase 3).** Debris files removed across all packages. `README.Rmd` templates deleted from TaxaMatch, TaxaAssign (package READMEs are hand-edited). Other debris: dev scripts, placeholder tests, prompt drafts, untracked data files, and template figures.

------------------------------------------------------------------------

## File-Specific Comments

### barcode_utils.R

**`resolve_barcode_lengths()` allows min \> max:** Fixed. Added validation that stops with an informative error when `min_len > max_len` (after coercion to integer).

**Unnamed return vector vs. documentation:** Fixed. `resolve_barcode_lengths()` now returns a named vector with names `"min_bp"` and `"max_bp"` at all return points (`stats::setNames()`). Tests updated to use `expect_named()` and `unname()` patterns, and `out[["min_bp"]]` / `out[["max_bp"]]` subscripting.

### call_api.R

**`switch()` coercion:** Fixed. Added `as.character()` to all three `switch()` expressions in `call_api.R`.

**Duplicated code across provider helpers:** Noted, not actioned. Each provider's request-building function has a distinct structure (different auth schemes, body formats, streaming options). A shared error/timeout handler could reduce some duplication but the marginal complexity vs. readability gain is low at this stage.

**`show_tokens` enhancement:** The `show_tokens` message now includes provider and model (e.g., `"Tokens used [anthropic / claude-sonnet-4-6] — input: 312, output: 87"`).

### census_genus_species.R

**Lines 92–96 `as.integer()` coercion:** The `backbone_id` parameter is coerced to `as.integer()` at the point of use in `verify_taxon_names.R`. The census function uses it only for comparison; the coercion in `verify_taxon_names()` is the canonical location.

**Lines 106–108 filtering for specific terms:** The term-filtering logic at those lines is intentionally broad; restricting to specific terms would require enumeration of all valid GBIF kingdom/phylum tokens, which is outside the intended scope of this function.

**Multiline if-statement style (lines 152–158 and 337–341):** Fixed. Assignments moved inside braces for both `status_val` and `name_col` if/else blocks.

### change_backbone.R

**Rename suggestion (lines 18–20):** Noted. The function does reshape and relabel rather than call a backbone directly, but the name `change_backbone` accurately describes its role in the workflow (changing which backbone's taxonomy is active).

**Column name specificity (lines 57–58):** The `input_col` parameter already accepts any column name. Restricting to specific names would reduce flexibility for users with non-standard verify output.

**0-row input as warning vs. error (lines 133–138):** Noted. The current warning is intentional — returning an empty data frame allows pipe-based workflows to continue gracefully when upstream steps produce no results.

**Piping complexity (lines 156–191):** Noted. The pipeline is intentionally concise; inline comments at each step explain what each mutation does. Author preference for commenting to help with debugging in V1.

### clean_taxon_names.R

**Lowercase genus names returned as NA:** Intentional. `clean_taxon_names()` is a downstream-of-verify cleaning step, not a validator. Names that do not follow sentence-case binomial convention are treated as unusable for backbone API queries. The function documentation explicitly notes this.

**"P." retained (lines 83–86):** Intentional. Two-character strings like `"P."` are retained because the minimum-length filter is set conservatively. Users who need to exclude genus abbreviations should filter on `is_valid_species_name()` after cleaning.

### common_names.R

**LLM accuracy for `common_to_scientific()`:** The `verify = TRUE` parameter (default) passes LLM-returned scientific names through `verify_taxon_names()` against the selected backbone. Since multiple common names are possible for the same Latin binomial, there is acceptable variation in this output. Furthermore, the purpose of this function is to help non-experts understand what kinds of organisms they are dealing with rather than settle on a preferred common name. I.e., this confirms the names exist as valid taxa but does not confirm that they match the user's common-name intent (as the reviewer notes). This limitation is documented in the function's `@details` section.

**File naming convention:** Noted. The file contains both `common_to_scientific()` and `scientific_to_common()`, so a single-function name for the file would be misleading. No change.

**Multiline if-statement style (lines 144–145):** Fixed. `context_block` assignment moved inside braces.

**`scientific_to_common()` — consider removing:** Retained. `scientific_to_common()` is used by downstream packages (TaxaHabitat, TaxaWizard) to generate human-readable labels for reports and Shiny outputs.

**`use_llm` default in `scientific_to_common()`:** Fixed. Changed from `TRUE` to `FALSE`.

### create_taxon_names.R

**`df` parameter name:** Fixed (see general comment above).

**Empty data frame return on 0-row input (lines 59–63):** Intentional. Returning an empty data frame preserves the pipe-able interface — callers do not need to check for NULL before continuing.

### draft_text.R

**`df` parameter name:** Fixed (see general comment above).

**Clinical trial examples (lines 102–109):** Noted. The examples in that section are from `build_report_context()`, which is intentionally domain-agnostic. Taxonomy-specific examples appear in the `@examples` section.

**Code comments treated skeptically by LLM (line 239):** Noted. `draft_methods_text()` reads both code and comments because method-section language often relies on the intent captured in comments rather than the mechanics in the code. The behavior is documented.

**`generate_report()` co-location (lines 11, 88):** The `generate_report()` function lives in TaxaWizard, which depends on TaxaTools. Placing it here would create a circular dependency.

### fill_higher_ranks.R

**`parse_classification_path()` wrapping `.extract_rank_from_classification()`:** The thin exported wrapper exists to provide a stable public API to an internal helper, allowing users to call it without `:::`. The internal function signature may change; the wrapper's signature remains stable.

**`df` parameter name:** Fixed (see general comment above).

### find_taxonomy_conflicts.R

**Single-line if / curly braces:** Fixed in Phase 1. All single-line `if` statements now use braces.

**`df` parameter name:** Fixed (see general comment above).

### is_valid_species_name.R

**Returns TRUE for "Test all day":** Accurate observation. The function tests structural plausibility, not biological validity. It is intended to be applied to a vector of scientific names, some of which might depart from convention (i.e., it is not intended to be applied to generic text). The documentation is explicit: "Returns FALSE for names that are structurally implausible."

**Renamed (Phase 3).** `is_valid_species_name()` renamed to `is_plausible_binomial()` throughout the ecosystem (13 files across TaxaTools, TaxaLikely, TaxaAssign; test file renamed). The new name better describes the function's intent as a plausibility heuristic rather than a strict validator.

### llm_api_utils.R

**"Backward compatibility" comment (lines 27–28):** Fixed. Comment updated to: "Wrappers are retained for named-provider access and as `llm_fn` arguments."

**"STEP 2 PATH 1/3" section headers (lines 106, 268, 386):** Fixed. Opaque internal step labels removed; sections now have plain descriptive headers.

### model_registry.R

**Code duplication in fetch-models functions (lines 177–194):** Noted. The duplication is minor (two similar conditional blocks). Wrapping into a helper is deferred.

**"GitHub" reference (line 595):** Fixed. Replaced with "repository".

### rank_utils.R

**`rank_system` parameter utility:** `rank_system` allows users to supply custom or extended rank lists (e.g., `extended_ranks`) instead of relying on `standard_ranks`. This is used by `TaxaMatch::standardize_match_data()` which works with NCBI/GBIF columns that include intermediate ranks not in `standard_ranks`. The parameter is necessary.

### rename_cols.R

**Why not just use `dplyr::rename()`?** `rename_cols()` provides two features not in `dplyr::rename()`: (1) automatic DarwinCore pattern matching when `col_map = NULL`, and (2) the `strict` parameter for workflow-level control over missing-key behavior. Users who know their column names can use `dplyr::rename()` directly; `rename_cols()` is aimed at batch-processing of heterogeneous input data frames.

**`.dwc_patterns` should be local to the function:** Fixed. The constant is now defined as a local variable inside `rename_cols()`.

### report_section.R

**Line 15 reference:** Fixed (Phase 3). Session reference comment removed.

**`print.report_section` vs. `print_report_section`:** `print.report_section` is an S3 method dispatch convention — R requires the name `print.<class>` for `print()` to dispatch to it automatically. This is correct R idiom, not a style violation.

**`assemble_report()` returns string, not .md file (line 159):** Fixed (Phase 3). `@return` updated to explicitly state "A length-1 character string" and a `\preformatted{}` block shows the `writeLines()` usage. `@examples` updated to use `writeLines(full_report, "methods_report.md")`.

### to_faire.R

**Column name validation (lines 110–118):** The rename map only applies to columns that are present; absent columns are silently skipped. This is intentional — TaxaID output objects vary in column composition across pipeline stages (`taxaRaw` vs. `taxaFinal`). Adding strict validation would break pipe-based workflows where not all columns are always present.

**`specificEpithet` assumes species is second word (line 158):** The assumption is correct for all valid binomials (genus + epithet). Uninomials (genus-only entries) are handled explicitly — when no space is present, `NA` is returned.

**`df` parameter name:** Fixed (see general comment above).

**Single-line if braces:** Fixed.

### token_usage.R

**Date format reliability (line 137):** `Sys.time()` is converted with `format(..., "%Y-%m-%d %H:%M:%S")`, which is locale-independent ISO 8601 format. This is reliable across platforms.

### verify_taxon_names.R

**`is.integer` vs. `is.numeric` for `backbone_id` (line 80):** `is.numeric` is intentional — users commonly pass integer literals like `11` or `4` which R parses as doubles. `is.integer(11)` returns FALSE. The coercion to `as.integer()` happens inside the function; the entry-point check uses `is.numeric` to accept both `11` and `11L`.

**`verified` default FALSE (line 196):** Intentional. `verified = FALSE` is the safe default for rows where the API did not return a result, to prevent unverified names from being silently treated as confirmed.

**Conditional success message:** Fixed. The "0 had no match; 0 were unverified" text no longer appears on successful runs. The message now reports only counts that are \> 0.

### zzz.R

**Lines 71 and 75–76 — two Azure messages:** The line 71 message is the general startup message for any provider (`"TaxaID: Using azure_openai as LLM provider."`). Lines 75–76 (now fixed) appended an Azure-specific DOI network note. They are separate because the DOI note only applies to Azure. The comment in the code now makes this clearer.

**Multiline if-statement style (lines 75–78):** Fixed. `doi_note` assignment moved inside braces.

------------------------------------------------------------------------

## Previously Deferred Items — All Completed (Phase 3)

All items from the original deferred list were completed in the pre-release cleanup pass (Phase 3, 2026-06-27). `devtools::check()` confirmed 0 errors, 0 warnings, 0 notes.

| Item | Resolution |
|---|---|
| General LLM data-sensitivity warning | Fixed: `@details` added to `call_api()`; NOTE added to `.onAttach()` startup messages |
| `is_valid_species_name()` rename | Fixed: renamed to `is_plausible_binomial()` across 13 files |
| `assemble_report()` documentation clarification | Fixed: `@return` and `@examples` updated |
| `report_section.R` line 15 cleanup | Fixed: session comment removed |
| Lintr sweep | Fixed: `.lintr` config added; all substantive issues resolved (25 commented-code, 10 brace, 4 other) |
| README and repo file cleanup | Fixed: debris deleted across all packages |
