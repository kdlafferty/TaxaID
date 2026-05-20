# CLAUDE.md — TaxaTools
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-19 (Session 77 — census_genus_species for GBIF backbone species enumeration)

---

## Package Purpose
Shared helper functions for working with taxonomic name lists AND LLM API providers.
Dependency of all other TaxaID packages. Can also be used standalone for cleaning and
standardizing taxon name lists, resolving synonyms, and querying taxonomic hierarchies.

---

## Function Inventory

### Taxonomy functions

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `verify_taxon_names()` | Verify names against a taxonomic backbone via Global Names Verifier API; batched; returns `user_supplied_name`, `matched_name`, `classification_path`, `classification_ranks`, `score`, `verified` | Complete | R/verify_taxon_names.R |
| `create_taxon_names()` | Add `taxon_name` and `taxon_name_rank` columns from separate rank columns; case-insensitive column matching; most-specific non-NA rank wins | Complete | R/create_taxon_names.R |
| `clean_taxon_names()` | Normalise, deduplicate, and filter a character vector of taxon names; removes NA, non-capital-initial, abbreviations, bracket artefacts | Complete | R/clean_taxon_names.R |
| `change_backbone()` | Post-process `verify_taxon_names()` output; rename source/translated name columns; parse pipe-delimited classification into wide rank columns | Complete | R/change_backbone.R |
| `rename_cols()` | Rename data frame columns using an explicit `col_map` or built-in case-insensitive regex patterns for common DarwinCore alternatives; `strict` arg controls missing-key behaviour | Complete | R/rename_cols.R |
| `find_taxonomy_conflicts()` | Detect higher-rank inconsistencies in taxonomy data frames; returns `taxon_name`, `taxon_rank`, `parent_rank`, `parent_values`, `n_values` | Complete | R/find_taxonomy_conflicts.R |
| `is_valid_species_name()` | Filter out "sp.", "cf.", "aff.", uncultured, environmental, and non-binomial names; vectorised logical return | Complete | R/is_valid_species_name.R |
| `format_dwc()` | Apply per-column DarwinCore formatting rules | Planned | — |
| `validate_dwc()` | Read-only QC after formatting | Planned | — |
| `dwc_map()` | Compare input column names against full DarwinCore term list; propose `col_map` via fuzzy matching or LLM API | Planned | — |

### Rank and barcode utilities (Sessions 56-57)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `standard_ranks` | Character vector: `c("kingdom","phylum","class","order","family","genus","species")` | Complete | R/rank_utils.R |
| `extended_ranks` | Character vector: standard + subspecies, variety, form | Complete | R/rank_utils.R |
| `detect_ranks()` | Auto-detect which rank columns exist in a data frame; returns coarse-to-fine character vector | Complete | R/rank_utils.R |
| `barcode_length_defaults` | Named list of 12 barcode markers → `list(min, max)` bp ranges | Complete | R/barcode_utils.R |
| `resolve_barcode_lengths()` | Resolve min/max bp from `barcode_term` vector; takes union across multiple terms; user overrides | Complete | R/barcode_utils.R |

### LLM provider functions (moved from TaxaFetch, Session 28)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `call_anthropic_api()` | Submit one prompt string to Anthropic Claude | Complete | R/llm_api_utils.R |
| `call_gemini_api()` | Submit one prompt string to Google Gemini (free tier available) | Complete | R/llm_api_utils.R |
| `call_openai_api()` | Submit one prompt string to OpenAI ChatGPT | Complete | R/llm_api_utils.R |
| `call_ollama_api()` | Submit one prompt string to a local Ollama model (no API key) | Complete | R/llm_api_utils.R |
| `prompt_api()` | Multi-chunk llm_prompt dispatcher; llm_fn param selects provider | Complete | R/llm_api_utils.R |
| `prompt_manual()` | Write prompt files for manual web interface submission | Complete | R/llm_api_utils.R |
| `read_llm_response()` | Read and concatenate saved LLM response files | Complete | R/llm_api_utils.R |
| `%||%` | Null-coalescing operator; exported for use by downstream packages via `@importFrom` | Complete | R/llm_api_utils.R |

### GBIF backbone census (Session 77)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `census_genus_species()` | Enumerate described species per genus (or higher rank) via GBIF backbone `name_usage(children)`. `match_species` param computes reference completeness: "complete" / "singleton_missing" / "incomplete". Higher-rank recursion (family → genera → species). `rgbif` in Suggests. | Complete | R/census_genus_species.R |

### LLM text generation functions (Session 55)

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `build_report_context()` | Domain-agnostic S3 context object with verified facts for grounding LLM output | Complete | R/draft_text.R |
| `draft_methods_text()` | Read R code and draft Methods section via LLM; context-aware; audience param | Complete | R/draft_text.R |
| `draft_results_text()` | Read R objects and draft Results section via LLM; context-aware; audience param | Complete | R/draft_text.R |

---

## Typical Workflow

```r
rename_cols()           # align column names to DarwinCore
  → create_taxon_names()   # derive best taxon name per row
  → clean_taxon_names()    # deduplicate & clean for API
  → verify_taxon_names()   # check against backbone via API
  → change_backbone()      # reshape into wide taxonomy table
```

---

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-verify_taxon_names.R | `verify_taxon_names()` | Offline validation + online API tests (skipped offline) |
| test-create_taxon_names.R | `create_taxon_names()` | Fully offline |
| test-clean_taxon_names.R | `clean_taxon_names()` | Fully offline |
| test-change_backbone.R | `change_backbone()` | Fully offline; uses mock verified tibbles |
| test-rename_cols.R | `rename_cols()` | Fully offline |

**Testing rules:** All tests use small inline data. No external files. No API calls except
the online group in test-verify_taxon_names.R (guarded by `skip_if_offline()`).

---

## Key Dependencies

| Package | Used for |
|---|---|
| httr | Global Names Verifier API requests |
| httr2 | LLM provider API calls (Anthropic, Gemini, OpenAI, Ollama) |
| jsonlite | JSON encoding for API body |
| dplyr | Tibble construction, data manipulation |
| tidyr | `unnest_wider()` in `change_backbone()` |
| purrr | `map2()` in `change_backbone()` |
| stringr | String cleaning in `clean_taxon_names()` |
| rlang | NSE (`:=`, `sym()`) in `change_backbone()` |
| stats | `setNames()` in `change_backbone()` |

---

## Design Notes
- All functions are general-purpose — no assumptions about TaxaMatch/TaxaExpect input formats
- Argument names must be consistent and intuitive (these are the most-called internal functions)
- `verify_taxon_names()` is slow for large lists — always run on a deduplicated vector, save result, load in downstream scripts
- `clean_taxon_names()` strips brackets BEFORE the capital-letter filter (bug fix Session 27)


## Renaming Log

| Old Name | New Name | Date | Notes |
|---|---|---|---|
| `f_spellcheck_sci_names` | `verify_sci_names` | 2026-02-18 | — |
| `verify_sci_names` | `verify_taxon_names` | 2026-03-26 | Consistency with package naming |
| `create_taxon_name` | `create_taxon_names` | 2026-03-26 | Plural for consistency |

---

## Session Notes

**Session 27 (2026-03-26)**
- Tests written for `clean_taxon_names`, `create_taxon_names`, `change_backbone` — all pass
- Bug fixed in `clean_taxon_names`: bracket stripping (`[Bacillus] subtilis`) now happens
  before the capital-letter filter; previously bracketed names were silently dropped
- `NA_character_` required (not `NA`) when testing character-vector functions
- CLAUDE.md restructured: ecosystem context moved to `TaxaID/CLAUDE.md`; this file is package-specific

**Session 28 (2026-03-26)**
- LLM provider functions moved from TaxaFetch → TaxaTools/R/llm_api_utils.R
  (`call_anthropic_api`, `call_gemini_api`, `call_openai_api`, `call_ollama_api`,
  `prompt_api`, `prompt_manual`, `read_llm_response`)
- TaxaHabitat package created; habitat assignment functions moved from TaxaFetch
- `httr2` added to DESCRIPTION Imports
- TODO: Run `devtools::document()` and `devtools::check()` on TaxaTools

  # Lafferty removed "unique(cleaned)" from last line of clean_taxon_names!!! 29 March 2026

**Session 52 (2026-04-09)**
- `clean_taxon_names()` output now length-preserving (invalid → NA, duplicates kept)
- `attr(result, "model")` added to all 4 LLM provider returns
- `inst/CITATION` created

**Session 55 (2026-04-12)**
- `build_report_context()`, `draft_methods_text()`, `draft_results_text()` added to R/draft_text.R
- General-purpose LLM text generation: read code → methods prose, read R objects → results prose
- `build_report_context()` creates domain-agnostic S3 `report_context` object with verified facts
- Methods prompt includes statistics bleed guard (statistics shown for accuracy only, not to be reported)
- Both prompts include LLM caution instructions (flag LLM-derived data, stochastic output caveat)
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 57 (2026-04-15) — Prompts 14-16**
- `R/rank_utils.R` created: exports `standard_ranks`, `extended_ranks`, `detect_ranks()`
  (Prompt 14). Replaces inline rank definitions across downstream packages.
- `R/find_taxonomy_conflicts.R` created: exports `find_taxonomy_conflicts()` (Prompt 15, GITA G8).
  Detects higher-rank inconsistencies; returns conflict data frame.
- `R/is_valid_species_name.R` created: exports `is_valid_species_name()` (Prompt 16, D3).
  Consolidated from internal copies in TaxaLikely + TaxaAssign.
- `R/barcode_utils.R` created: exports `barcode_length_defaults` + `resolve_barcode_lengths()`
  (Prompt 16, D4). Consolidated from 3 internal copies across TaxaLikely, TaxaMatch, TaxaAssign.
- `%||%` in `R/llm_api_utils.R` upgraded from `@noRd` to `@export` with `@name null-coalesce`
  (Prompt 16, D2). Downstream packages import via `@importFrom TaxaTools %||%`.
- Empty `utils::globalVariables(character(0))` removed from files with no NSE references.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes

**Session 77 (2026-05-19)**
- `R/census_genus_species.R` created: exports `census_genus_species()`.
  Queries GBIF backbone via `rgbif::name_usage(key, data="children")` to enumerate
  all described species within each genus. `match_species` param computes per-genus
  completeness (complete / singleton_missing / incomplete). Higher-rank recursion
  (family → genera → species) via `.census_higher_rank()` and `.fetch_children_genera()`.
- `rgbif` added to Suggests in DESCRIPTION.
- Character key coercion: `name_backbone()` returns character usageKeys; the function
  now accepts and coerces character vectors to numeric.
- 41 tests in `test-census_genus_species.R` (all mocked GBIF responses for offline testing).
- `devtools::check()`: 0 errors, 0 warnings, 0 notes
