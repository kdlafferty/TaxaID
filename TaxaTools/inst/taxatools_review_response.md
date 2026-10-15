# TaxaTools Peer Review Response

**Review date:** 2026-06-27 **Package version reviewed:** TaxaTools 0.1.0 **Response prepared by:** K. D. Lafferty

This document responds to each comment in the TaxaTools code review. Changes were implemented across three phases and verified with `devtools::check()` (0 errors, 0 warnings, 0 notes; 680 tests passing).

------------------------------------------------------------------------

## Added after the review

| Function | File | Purpose | Tests |
|---|---|---|---|
| `assign_sampling_group()` | `R/sampling_group.R` | Assign Sampling Groups from Taxonomic Rank Columns | test-sampling_group.R |
| `cache_ok()` | `R/cache_utils.R` | Is a cache file usable, given the inputs it derives from? | test-cache_utils.R |
| `check_lineage_agreement()` | `R/ncbi_homonyms.R` | Check Whether a Returned Lineage Agrees With a Declared One | test-ncbi_homonyms.R |
| `check_taxaid_manifest()` | `R/build_manifest.R` | Check the Installed TaxaID Code Against a Recorded Manifest | test-build_manifest.R |
| `default_sampling_scheme()` | `R/sampling_group.R` | Default Sampling-Group Classification Scheme | test-sampling_group.R |
| `define_search_polygon()` | `R/define_search_polygon.R` | Define a Search Polygon Interactively | test-define_search_polygon.R |
| `escalate_taxonomic_rank()` | `R/escalate_taxonomic_rank.R` | Escalate a Taxon to the Next Coarser Rank | test-escalate_taxonomic_rank.R |
| `fetch_worms_attributes()` | `R/worms_attributes.R` | Fetch WoRMS Taxon Attributes by Name | test-worms_attributes.R |
| `list_cache_files()` | `R/cache_utils.R` | List files in a directory matching cache-file patterns | test-cache_utils.R |
| `report_and_clear_cache()` | `R/cache_utils.R` | Report and optionally delete a set of cache files | test-cache_utils.R |
| `resolve_barcode_marker()` | `R/barcode_utils.R` | Resolve a Primer-Variant Barcode Term to the Marker It Amplifies | test-barcode_utils.R |
| `resolve_barcode_primers()` | `R/barcode_utils.R` | Resolve Primer Sequences from a Barcode/Primer-Set Term | test-barcode_utils.R |
| `resolve_ncbi_taxid()` | `R/ncbi_homonyms.R` | Resolve a Taxon Name to One Disambiguated NCBI Taxonomy Id | test-ncbi_homonyms.R |
| `taxaid_build_manifest()` | `R/build_manifest.R` | Record Which TaxaID Code a Run Is Using | test-build_manifest.R |
| `taxaid_cache_report()` | `R/cache_utils.R` | Report every TaxaID cache on this machine | test-cache_utils.R |
| `taxatools_clear_cache()` | `R/common_names.R` | Report and clear the TaxaTools on-disk caches | test-common-names.R, test-worms_attributes.R |
| `write_taxaid_manifest()` | `R/build_manifest.R` | Write a TaxaID Build Manifest | test-build_manifest.R |

28 new internal helper functions have also been added since the review (mostly in
`worms_attributes.R`'s WoRMS-API internals and `common_names.R`'s cache internals; 3 in
`ncbi_homonyms.R`). `ncbi_homonyms.R` also carries one internal, unexported data object,
`.known_ncbi_homonyms` -- a confirmed-case fixture for `test-ncbi_homonyms.R` and the
worked examples in `resolve_ncbi_taxid()`'s own roxygen, deliberately not exported (see
that object's own roxygen for why a hand-curated list should not stand in for the
resolver itself).

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

## Behavior changes to already-reviewed functions

- The response ceiling (`max_tokens`) on `call_api()` and the provider
  wrappers rises from 3000 to 16000. A reasoning model spends part of its
  budget thinking before it writes, so a ceiling sized for the visible answer
  returned a response carrying no text at all, which took out every LLM path
  in the ecosystem (habitat assignment, assignment review, the LLM prior, the
  unreferenced-species suggester, report drafting and script annotation). The
  ceiling is a cap and not an allocation, so the larger default costs nothing
  for a short answer.

Not new functions (see "Added after the review" near the top for those) -- new behavior
on functions this document already covers above.

- `list_cache_files(recursive = FALSE)` -- new argument, so a nested store can
  be seen. It now also drops directories, which the previous code would have
  handed to `file.remove()`.
- `scientific_to_common()` caches `llm_parsed` per row, so a name the model
  omits is no longer cached as "no common name" for every subsequent run.
- `verify_taxon_names()` gains an optional `decisions` parameter (only meaningful for
  `backbone_id = 4`, the NCBI direct bypass; warns "unused" if supplied for any other
  backbone). `.verify_via_ncbi()`'s batched name search used to silently pick whichever
  NCBI node its own ESummary record happened to process last for a name shared by more
  than one taxonomy node (confirmed live: `"Vertebrata"[Scientific Name]` genuinely
  returns both a red-algal genus and the vertebrate clade) -- such a name is now
  reported as an unresolved ambiguity, never guessed, resolved only via `decisions` (a
  `data.frame(name, taxid)` or a path to an `.rds` holding one; `taxid = NA` is an
  explicit, recorded skip), one interactive prompt covering every ambiguous name in the
  call, or a non-interactive `stop()` naming exactly how to supply the missing
  decisions. `escalate_taxonomic_rank()`, `fill_higher_ranks()`, and
  `assign_sampling_group(harmonise = TRUE)` each gain the identical parameter,
  forwarded verbatim to whichever of their own internal `verify_taxon_names()` calls
  targets backbone_id 4 -- none grows a prompt or resolution mechanism of its own. No
  new exports: the two new helpers this needed
  (`.save_ncbi_homonym_decisions()`/`.apply_ncbi_homonym_decisions()`) stay internal in
  `R/ncbi_homonyms.R`, next to `resolve_ncbi_taxid()`/`check_lineage_agreement()`.
- `barcode_primer_defaults` gains `"18s-v9"` (1389F/1510R, Amaral-Zettler et al. 2009),
  with a matching `barcode_length_defaults` window and an `18s-v9` to `18S` entry in
  `resolve_barcode_marker()`, so one term serves both primer trimming and the NCBI
  search. Verified in silico against three real 18S genes, every stripped product
  ending in the same 3' sequence carried by real 18S environmental sequences.
- `resolve_barcode_primers()` refuses to resolve a bare `"18S"`, `"ITS"` or `"ITS2"`
  by prefix once a region of that marker is registered, and the error names the
  registered regions. Registering one region of a marker whose studies target
  several would otherwise have made the bare term silently resolve to whichever
  region happened to be registered, so an 18S V4 study's references would have been
  trimmed with V9 primers without a word. A bare term already errored before this
  change, and every caller in the ecosystem wraps the call, so the amplicon paths
  that leave an unregistered marker untrimmed behave exactly as before; only the
  message is different, and more specific.
- `verify_taxon_names()` gains `cache_dir` (default `NULL`, unchanged behaviour)
  and `cache_ttl_days` (default 365). A per-name cache so a re-run reproduces
  instead of depending on whether the service answered. Only answered names
  (`verified = TRUE`, matched or not) are written; a failed lookup is never
  cached and is asked again. The key is the name plus `backbone_id`,
  `fallback_backbone_id` and `decisions` by content (a decisions file by its
  contents); `batch_size`/`timeout_sec` are excluded. `taxatools_clear_cache()`
  now also covers `_verified_name.rds`. Tests: test-verify_taxon_names_cache.R.

### 2026-10-02: clean_taxon_names() -- subgenus, cf./aff., hybrid formulae

Spec decided by package review at the maintainer's request (clean subspecies and strain labels).
Three changes, each with a test that fails on the previous code:
- A1 BUG FIX. A parenthesised subgenus became a fake binomial: bracket stripping turned
  "Allodia (Brachycampta) sp. TTMDI642-10" into "Allodia Brachycampta". The subgenus is now
  dropped before brackets are stripped: that name gives "Allodia" with `collapsed_to_genus = TRUE`,
  and "Allodia (Brachycampta) lugens" gives the species "Allodia lugens".
- A2. A LEADING "cf."/"aff." ("cf. Laternula", "aff. Cyrtona sp. 1") returned NA because of the
  capital-letter filter. Qualified names now return the genus whether the qualifier leads or
  follows the genus; the new attribute `name_qualifier` ("cf." / "aff.") keeps a qualified genus
  distinguishable from an asserted one.
- A3. A hybrid formula returned its first parent as if it were the organism. Congeneric parents
  now give the genus; intergeneric parents give NA ("Carassius auratus red var. x Megalobrama
  amblycephala", which `strip_modifiers` documentation cites, is now NA), including nested
  formulae and modifier-prefixed ones (modifier stripping now runs first, so a prefix cannot slip
  a formula past the rule). A named nothospecies ("Mentha x piperita") is not a formula and is
  unchanged. The first-parent reading was relied on by TaxaMatch's maternal-parent proxy; that
  reading now lives in TaxaMatch behind a marker gate (see TaxaMatch's entry of this date),
  because a generic cleaner must not call one parent the organism: wrong for a nuclear marker.
New attribute `clean_reason` ("subgenus_dropped", "qualifier", "hybrid_congeneric",
"hybrid_intergeneric", else NA). Tests comparing cleaned vectors with
`ignore_attr = "collapsed_to_genus"` now ignore all three attributes (33 TaxaTools, 3 TaxaExpect).
A fourth test pins existing behaviour on real CalIntertidal labels ("Chone magna CMC01" ->
"Chone magna"; "Corallina sp. 4frondescens", "Melobesia sp. 2BC" -> genus); it passes on the old
code too. Those strain labels reached species calls (COI 698 of 5,918, 18S 175 of 1,562) because
the workflow never called this function on the match rows' `species`, not because it mis-cleaned.
Name-keyed caches will re-resolve the changed names on first run: slower, not wrong. In
CalIntertidal these are `gbif_rank_lookup.rds` and the sampling-group harmonise caches.

### 2026-10-03: a skipped item in a long loop is announced as it happens

`warning()` is DEFERRED to the end of the run under `Rscript`, so a failure
inside a long loop that CATCHES the error, SKIPS the item and continues is
invisible until the script exits -- the run looks healthy and quietly returns a
smaller result. A real audit nearly read a silent log as a clean bill of health
across 22,080 NCBI lookups for exactly this reason. Each such site now also
`message()`s. The `warning()` calls are unchanged, so anything programmatic that
depends on them is unaffected; and a caller's `suppressWarnings()` no longer
hides the operator-facing line, which was a second silent-failure route.

One site: `.ncbi_batch_summary()`, per batch of 100 taxids. This is the site a
lineage audit hit -- it warned correctly and the operator saw nothing for the
duration of the run. Test in `test-verify_taxon_names.R` mocks
`rentrez::entrez_summary` to fail and asserts both the message and the warning.

NOT changed: failure paths that warn at call time with the user present (input
validation), and single-shot failures that abort rather than continue. The
maintainer's condition was that this must not produce thousands of repeat lines,
so the choice of sites is deliberate -- see the volume note where it applies.

### 2026-10-08: `fill_higher_ranks(ranks=, record_source=)` -- fill a rank the primary backbone leaves silent

K. Lafferty approved both pieces of new public surface, relayed by the package-review coordinator
("1) approve (a)"): a `ranks` argument and a source-recording output column.

**The problem.** GBIF's backbone carries no class at all for the ray-finned fishes -- its
Actinopterygii/Actinopteri node is not an accepted backbone class, a gap already documented in
`sampling_group.R`. A genus-level query returns `kingdom|phylum|order|family|genus` with no class
entry, so `class` arrives `NA` and a consensus keyed on class lands at phylum Chordata. NCBI supplies
`Actinopteri`.

**The rule.** A rank is filled only where the source above it in the chain said NOTHING: local
sources, then the primary backbone, then the fallback, each touching only cells still `NA`. A value
the primary supplied is never replaced by the fallback's. This is the opposite emphasis from
`cross_phylum_eps`, where the backbone WINS over a disagreeing input, and the two are consistent
because they answer different questions -- there two sources disagree and the backbone is trusted,
here one source is silent and another is asked. Nothing in this function adjudicates a disagreement.
Both sections are in the Rd.

**Backward compatibility is exact.** `ranks` defaults to `"family"` and `record_source` to `FALSE`,
and the default call is `identical()` to the previous version's output on the same input, with the
same three columns. `record_source` is off by default for a specific reason:
`TaxaAssign::join_priors()` joins EVERY non-`taxon_name` column of its `expansion_taxonomy` argument
onto the priors table, so a source column left on by default would travel into the posteriors. The Rd
says so and says to drop the columns before that call.

**Two defects found by measurement, both fixed here.**

- *A homonym could have been filled.* A bare genus name is not a key: GBIF carries a polychaete worm
  genus `Corallina` (`Animalia|Annelida|Polychaeta|...`) beside the red algal genus NCBI resolves
  (`Rhodophyta|Florideophyceae|...`), and BOTH match at genus rank, so `matched_rank` cannot separate
  them. A fallback value is now accepted only if its lineage does not contradict the primary's at
  `phylum` (or `division`), and a rejected genus warns by name. Coarser and finer ranks are
  deliberately not compared, each because a first attempt failed: the backbones use different
  vocabulary for the same kingdom ("Metazoa" against "Animalia"), and they disagree routinely on
  intermediate ranks for the same organism (NCBI puts Girella in Centrarchiformes, GBIF in
  Perciformes). Both produced false contradictions that rejected a correct class for every fish
  tried. The check cannot protect against a wrong PRIMARY, which is authoritative by construction --
  querying with GBIF primary resolves `Corallina` to `Polychaeta` with nothing to compare against --
  and the Rd says that plainly.
- *One ambiguous name aborted the whole batch.* `verify_taxon_names()` refuses to guess between NCBI
  homonyms and errors for the CALL, not the name. Measured: 7 ambiguous genera (Apogon, Coris,
  Liparis, Microstoma, Decodon, Hirundichthys, Appendicularia -- fish names that are also plant or
  tunicate genera) cost all 374 resolvable genera in the same request, and every class came back
  `NA`. The batch is now retried name by name on failure, keeping the resolvable ones and reporting
  the rest. This does NOT add homonym-resolution logic: an ambiguous name is reported and left
  unfilled, as the `decisions` contract requires.

Also: one lineage query per BACKBONE rather than per rank, since a single classification path answers
every requested rank at once.

**Before/after on the CalIntertidal G5+G6 run.** 316 observations call phylum Chordata in the current
final (12S 132, 18S 53, COI 131 -- measured here, not carried over). 301 of them carry
`consensus_limit = "backbone"`, which is the code already reporting that a finer rank value is
missing. Filling class for their candidate rows (619 of 631 named taxa resolved, 617 from NCBI, 603 of
them `Actinopteri`; 26,062 of 35,020 rows filled) and recomputing with production's own
`consensus_settings`: **99 observations change, every one Chordata/phylum -> Actinopteri/class, and 0
new species calls.** `consensus_limit = "backbone"` falls 301 -> 83. The 217 that stay at phylum now
do so with limit `"threshold"` rather than `"backbone"` -- the call is still coarse, but for the
honest reason that the mass is spread rather than because a rank was missing. The subset was validated
first: under the installed pre-change build it reproduces all 316 as Chordata at phylum.

12 taxa remain unresolved and are reported by warning (the Apogon group above). Suite 1,295 pass / 0
fail / 19 skip; `rcmdcheck --as-cran` 0 errors / 0 warnings / 1 pre-existing note.

### 2026-10-15: a failed lookup is never cached as an answer (verify_taxon_names, assign_sampling_group, fill_higher_ranks)

During a network outage (the machine slept, 2026-10-14 20:41-20:44 HST) a Mugu run's
`posterior_consensus(taxonomy_cache_dir =)` wrote cache entries for *Notropis* and
*Atherinops* -- both valid NCBI genera -- as `verified = TRUE`, `matched = FALSE`,
`matched_name = NA`, and would have served that non-answer as a definitive non-match on
every later run. The cache writer in `verify_taxon_names()` was correct: it stores only rows
with `verified = TRUE`. The NCBI path (`.verify_via_ncbi()`, `backbone_id = 4`) was not: a
search batch that failed all three attempts, a failed `[All Names]` synonym fallback and a
failed lineage fetch all reached Step 3 as `verified = TRUE` / `matched_name = NA`, the same
shape as a genuine non-match. The GlobalNames path has always returned `verified = FALSE` on
failure, which is why the CalIntertidal cache (5,169 GlobalNames entries) carried no poison.

Fix. The NCBI path now tracks the names it could not ask about (a failed search batch's
names, a failed synonym check's name, the taxids of a failed lineage batch) and reports them
with `verified = FALSE`; the summary line counts them separately from "no match". Every cache
entry written from now on carries an `answered = TRUE` marker. An entry from before the
marker existed is served only if it holds a matched name (a failure never produces one, on
either path, since a name is assigned only from a fetched lineage or an API record); an
unmarked entry without a name is treated as a miss, asked once more and rewritten with the
marker. Measured one-time cost on the three validation caches: CalIntertidal 132 unmarked
nameless entries (GlobalNames: 100 names re-asked in 0.6 s), Mugu 0 (its 89 entries all
matched), Great Lakes 0 live (the 66 poisoned entries had been moved to a quarantine folder
by hand), so no pre-warm step was needed.

`assign_sampling_group(harmonise = TRUE)` had the same shape one level up: its cache was
built from `change_backbone(keep_unmatched = TRUE)` with no filter on `verified`, so a
GlobalNames batch that failed was stored as an unmatched name. Rows with `verified = FALSE`
are now dropped before the cache is built, with a warning naming them (they are left
unharmonised this run and asked again next run); the saved cache carries
`attr(, "answered_only")`, and a cache lacking it has its lineage-less rows treated as misses
while its lineage-bearing rows are kept, the same rule as the `matched_rank` check already
applied to caches written before the rank-agreement gate.

`fill_higher_ranks(character(0))` used to stop with "taxon_names must be a non-empty
character vector". An empty input is a legitimate upstream outcome (a coverage audit that
finds no unreferenced species for a marker) and was killing a Mugu Round-1 loop on its
emptiest marker. It now returns the documented zero-row table with the usual columns
(`taxon_name`, `genus`, each requested rank and, with `record_source = TRUE`, each
`<rank>_source`) and says so in a message; a non-character input still stops.

Tests: three mocked-rentrez failure cases (search batch, lineage fetch, synonym fallback;
the last also through `verify_taxon_names(cache_dir =)`, asserting the failed name is not
written and is asked again while its answered siblings are cached with the marker), two
cache-marker cases (an unmarked nameless entry is re-asked and rewritten; an unmarked named
entry is served), two harmonise cases (a failed row is warned about and never cached; an
unmarked cache's lineage-less row is re-resolved while its lineage-bearing row is kept), and
the empty `fill_higher_ranks()` input.
