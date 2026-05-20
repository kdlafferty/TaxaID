# TaxaID Ecosystem — Fragility Audit

**Prompt 2 of POLISHING_ROADMAP.md**
**Date:** 2026-04-13 (Session 56)
**Method:** 5 parallel agents scanned all exported functions and key internals across 7 packages

---

## Summary

| Package | High | Med | Low | Total |
|---------|------|-----|-----|-------|
| TaxaTools | 6 | 9 | 9 | 24 |
| TaxaMatch | 8 | 20 | 1 | 29 |
| TaxaLikely | 12 | 19 | 3 | 34 |
| TaxaFetch | 3 | 12 | 3 | 18 |
| TaxaHabitat | 2 | 5 | 0 | 7 |
| TaxaExpect | 2 | 3 | 0 | 5 |
| TaxaAssign | 4 | 8 | 0 | 12 |
| **Total** | **37** | **76** | **16** | **129** |

---

## Section 1: HIGH Severity Issues

These will crash or silently give wrong results. Fix before any user-facing release.

### 1.1 Missing input validation (will crash)

| # | Function | Package | File:Line | Description |
|---|----------|---------|-----------|-------------|
| 1 | `.prep_training_data()` | TaxaLikely | train.R:156 | No validation that taxonomy columns in `rank_system` exist after lowercasing. Error comes late (line 196) after partial processing. |
| 2 | `train_likelihood_model()` | TaxaLikely | train.R:350 | No check that `train_df` is non-empty after `.prep_training_data()`. If all sequences filtered, `nrow(h1_data) == 0` is the only catch. |
| 3 | `blast_sequences()` | TaxaMatch | blast.R:120-121 | No validation that `asv_id` and `sequence` columns are non-empty/non-NA. Empty sequences submitted to BLAST cause unhelpful API errors. |
| 4 | `read_sequence_table()` | TaxaMatch | sequence_input.R:298 | `.parse_semicolon_headers()` assumes `parts[[1L]]` exists without checking if headers is empty. Crashes on empty input. |
| 5 | `standardize_match_data()` | TaxaMatch | standardize_match_data.R:100-107 | Auto-detected rank columns are case-insensitive but then passed case-sensitively to `create_taxon_names()`. Mismatch breaks downstream. |
| 6 | `compute_posterior()` | TaxaAssign | compute_posterior.R:82-85 | `prior_alpha <= 0` or `prior_beta <= 0` validated but `rbeta()` produces NaN when shape params are exactly 0. Validation must precede sampling. |
| 7 | `create_taxon_names()` | TaxaTools | create_taxon_names.R:41-62 | No check for 0-row input dataframe. Returns silently with two NA-filled columns; downstream code expecting rows fails. |

### 1.2 External dependency failures (will hang or crash)

| # | Function | Package | File:Line | Description |
|---|----------|---------|-----------|-------------|
| 8 | `call_anthropic_api()` | TaxaTools | llm_api_utils.R:78-132 | No `req_timeout()` on httr2 request. Unresponsive API hangs indefinitely. |
| 9 | `call_gemini_api()` | TaxaTools | llm_api_utils.R:565-636 | Same: no timeout. Also no differentiated 429 rate-limit handling. |
| 10 | `call_openai_api()` | TaxaTools | llm_api_utils.R:696-760 | Same: no timeout. |
| 11 | `verify_taxon_names()` | TaxaTools | verify_taxon_names.R:140 | No null-check on `data$names` from Global Names API. Malformed response → `lapply(NULL, ...)` → silent empty result. |
| 12 | `fetch_gbif_occurrences()` | TaxaFetch | fetch_gbif_occurrences.R:90-174 | No timeout/retry on `rgbif::occ_data()`. Network failures halt pipeline. |
| 13 | `search_literature()` | TaxaFetch | literature_search.R:76-92 | OpenAlex API key check gives generic error; no guidance on obtaining key. |
| 14 | `fetch_reference_sequences()` | TaxaLikely | fetch.R:279 | Requires `rentrez` but only checks via tryCatch deep inside count loop. Should fail fast at function entry. |
| 15 | `.blast_remote()` | TaxaMatch | blast.R:301-313 | Failed BLAST batches silently skipped with warning. User doesn't know which batches were lost. |

### 1.3 Silent wrong results (most dangerous)

| # | Function | Package | File:Line | Description |
|---|----------|---------|-----------|-------------|
| 16 | `prompt_api()` | TaxaTools | llm_api_utils.R:208-272 | Partial chunk failures: 3 of 5 chunks fail → returns 2 results. Downstream parser may misalign chunks to taxa, producing wrong habitat assignments. |
| 17 | `assign_taxa_llm()` | TaxaAssign | assign_taxa_llm.R:427-442 | When ALL priors are NA, `global_min <- min(..., na.rm=TRUE)` is `-Inf`, breaking posterior calculation. |
| 18 | `posterior_consensus()` | TaxaAssign | posterior_consensus.R | Empty hypothesis set after `min_posterior` filter → returns NA without warning why consensus is missing. |
| 19 | `assign_taxa_llm()` | TaxaAssign | assign_taxa_llm.R:377-386 | LLM API failure silently falls back to uniform priors. No `prior_source` column tracks whether priors are real or fallback. |
| 20 | `prepare_model_dataframe()` | TaxaExpect | prepare_model_dataframe.R:206 | Zero-SD covariate → division by 0 → NaN propagates through model. |
| 21 | `generate_full_priors()` | TaxaExpect | generate_full_priors.R:213-214 | Unbounded phi when theta→0/1. Cap can fail if `max_phi` is NULL. |
| 22 | `filter_top_hypotheses()` | TaxaLikely | evaluate.R:470 | Unknown `taxon_name_rank` values → NA rank score → silently dropped from results. |
| 23 | `filter_top_hypotheses()` | TaxaLikely | evaluate.R:485-488 | If all specific_candidate rows filtered, function silently returns only H2/H3 rows. |
| 24 | `.evaluate_one_query()` | TaxaLikely | evaluate.R:97 | Zero candidates after summarise → empty `cand` → downstream code expects nrow >= 1. |
| 25 | `.evaluate_one_query()` | TaxaLikely | evaluate.R:50 | Single candidate triggers 1D mode with artificial max gap. Can inflate H2/H3 relative to H1. No warning. |
| 26 | `train_likelihood_model()` | TaxaLikely | train.R:434-437 | `stats::cov()` on < 3 rows → non-positive-definite matrix or NaN. No tryCatch fallback. |
| 27 | `read_sequence_table()` | TaxaMatch | sequence_input.R:263-266 | Malformed `;size=abc` in FASTA header → `as.integer()` silently coerces to NA. |
| 28 | `filter_redundant_hypotheses()` | TaxaMatch | standardize_match_data.R:252-254 | NA in `sample_id` → `NA == NA` is `NA` (not TRUE) → logic errors in redundancy detection. |
| 29 | `.parse_blast_xml()` | TaxaMatch | blast.R:461, 480 | Hit with no HSPs → silent skip. No warning about data loss. |
| 30 | `flag_habitat_inconsistencies()` | TaxaHabitat | flag_habitat_inconsistencies.R:144-150 | Requires 7 optional packages; fails late instead of checking upfront. |
| 31 | `flag_habitat_inconsistencies()` | TaxaHabitat | flag_habitat_inconsistencies.R:126-138 | Hard-codes freshwater detection from IUCN L1 name strings. Custom habitat schemes don't match. |
| 32 | `.prep_training_data()` | TaxaLikely | train.R:263-264 | Singletons identified via `id_x == id_y` self-matches. If matrix lacks self-matches, zero singletons found silently. |
| 33 | `assign_habitat_biological()` | TaxaHabitat | assign_habitat_biological.R:118-200 | Case-sensitive column matching for `point_id_col` and `taxon_col`. No existence check. |
| 34 | `.blast_poll()` | TaxaMatch | blast.R:383-436 | First poll waits 15s unconditionally. Up to 600s total with no clear timeout message. |
| 35 | `.read_esv_dataframe()` | TaxaMatch | sequence_input.R:160-164 | User-specified `abundance_cols` partially missing → silently falls back to auto-detect instead of erroring. |
| 36 | `.normalize_scores()` | TaxaLikely | normalize.R:20 | All-NA input → `max(-Inf)` → sets all values to `1-epsilon`. Should return all-NA. |
| 37 | `.evaluate_one_query()` | TaxaLikely | evaluate.R:164-165 | `which.max()` on all-zero vector returns `integer(0)`. Downstream code at line 195 uses fallback but doesn't validate result. |

---

## Section 2: MEDIUM Severity Issues

Confusing error messages, undocumented edge cases, or fragile-but-usually-works patterns.

### 2.1 Edge cases (26 issues)

| # | Function | Package | Description |
|---|----------|---------|-------------|
| 1 | `change_backbone()` | TaxaTools | `strsplit(NA, "\\|")` returns list with NA, not empty list. Guard checks `length == 0` which won't catch NA. |
| 2 | `change_backbone()` | TaxaTools | 0-row dataframe passed through silently. |
| 3 | `verify_taxon_names()` | TaxaTools | Deduplicates input but never maps results back to original positions. Output length != input length. |
| 4 | `create_taxon_names()` | TaxaTools | Duplicate column names after `tolower()` (e.g., "Kingdom" and "kingdom") → undefined matching. |
| 5 | `.combine_chunk_responses()` | TaxaTools | All chunks NULL → returns `character(0)` not `""`. Length-0 vs length-1 distinction breaks callers. |
| 6 | `filter_sequences()` | TaxaMatch | Unrecognized `barcode_term` defaults to 100-2000 bp with only a `message()`, not `warning()`. |
| 7 | `read_sequence_table()` | TaxaMatch | `.join_taxonomy()` failure → returns input unchanged with warning. User may not notice taxonomy is missing. |
| 8 | `read_sequence_table()` | TaxaMatch | `.parse_semicolon_headers()` — inconsistent field count across headers not detected. |
| 9 | `.filter_blast_hits()` | TaxaMatch | `merge()` with tied max scores per query → row duplication. |
| 10 | `.parse_blast_xml()` | TaxaMatch | Division by zero when `align_len` or `qlen` is 0 in percent calculations. |
| 11 | `filter_redundant_hypotheses()` | TaxaMatch | `unlist()` on single-column subset vs multi-column gives different named/unnamed vectors. |
| 12 | `train_likelihood_model()` | TaxaLikely | `quantile()` on all-NA `real_pos_gaps` → anchor_gap becomes NA → passed to `rep()`. |
| 13 | `.evaluate_one_query()` | TaxaLikely | Species-specific params unavailable → silently falls back to global. No verbose mode. |
| 14 | `evaluate_likelihoods()` | TaxaLikely | All `sample_id` values NA → `group_split()` returns one group with NA. Confusing downstream. |
| 15 | `fetch_reference_sequences()` | TaxaLikely | All count queries fail → `sum(NA, na.rm=TRUE) = 0` → returns empty df silently. "No hits" indistinguishable from "errors". |
| 16 | `fetch_reference_sequences()` | TaxaLikely | Per-filter-step counts not reported. User can't tell which filter dropped their sequences. |
| 17 | `read_reference_fasta()` | TaxaLikely | 0-byte FASTA or headers-only → empty df silently until late check. |
| 18 | `audit_barcode_coverage()` | TaxaLikely | API failure → count=NA → treated as unreferenced. Conservative but could misclassify on transient errors. |
| 19 | `compute_moran_basis()` | TaxaExpect | Zero row-sum in neighbor matrix → NaN in row-standardized W. |
| 20 | `optimize_grid_size()` | TaxaExpect | `sd(N) / mean(N)` when mean is 0 → NaN. |
| 21 | `generate_undetected_diversity()` | TaxaExpect | Boundary theta (0 or 1) skipped silently → inconsistent output count. |
| 22 | `compute_posterior()` | TaxaAssign | All-zero likelihoods in a simulation column → uniform fallback without warning. |
| 23 | `join_priors()` | TaxaAssign | `alpha + beta = 0` → prior_mean = NaN from division by zero. |
| 24 | `posterior_consensus()` | TaxaAssign | Single hypothesis after threshold → ambiguous: strong consensus or data sparsity? No `n_plausible` indicator. |
| 25 | `score_consensus()` | TaxaAssign | Non-numeric `score` column not caught before filtering operations. |
| 26 | `generate_report()` | TaxaAssign | `median()` on all-NA or empty `top_score` → NA without warning. |

### 2.2 Input validation gaps (16 issues)

| # | Function | Package | Description |
|---|----------|---------|-------------|
| 1 | `draft_results_text()` | TaxaTools | All `...` objects NULL not caught. Empty dots creates malformed prompt. |
| 2 | `.resolve_code_input()` | TaxaTools | `readLines()` without tryCatch on unreadable files. |
| 3 | `rename_cols()` | TaxaTools | Column index from pattern matching could contain duplicates or out-of-bounds. |
| 4 | `filter_sequences()` | TaxaMatch | `sequence` column exists but contains NA → `nchar()` fails. |
| 5 | `build_reference_matrix()` | TaxaLikely | No check that rank_system is non-empty before processing. Lowercased rank columns not validated for existence. |
| 6 | `flag_reference_errors()` | TaxaLikely | No explicit check that `species.x` and `species.y` exist in `raw_df`. |
| 7 | `apply_coverage_constraints()` | TaxaLikely | `census_result` column names not validated helpfully; error message is generic. |
| 8 | `interpret_model()` | TaxaLikely | Assumes `H1_Global_Mu` has named elements. Manually constructed model breaks. |
| 9 | `stack_occurrences()` | TaxaFetch | Single data.frame in list — `is.data.frame()` logic ambiguous. |
| 10 | `get_keys_from_context()` | TaxaFetch | Column name case-insensitivity relies on `tolower()` but missing columns silently return 0 matches. |
| 11 | `search_dataone()` | TaxaFetch | Non-numeric bbox element passes through to API causing 500. |
| 12 | `build_taxon_screen_prompt()` | TaxaFetch | Missing text columns (title, abstract, keywords) silently become empty prompts. |
| 13 | `parse_hierarchical_habitat_response()` | TaxaHabitat | Duplicates and NAs in `taxon_list` not checked. |
| 14 | `build_habitat_prompt()` | TaxaHabitat | Duplicate catalog IDs cause silent row duplication. |
| 15 | `expand_unreferenced_hypotheses()` | TaxaAssign | Case-sensitive genus/family matching. |
| 16 | `update_prior_from_consensus()` | TaxaAssign | `merge()` without explicit `by =` key; column name mismatch → silent duplication. |

### 2.3 Silent failures (10 issues)

| # | Function | Package | Description |
|---|----------|---------|-------------|
| 1 | `read_llm_response()` | TaxaTools | Missing files skipped with warning; `chunks[i]` left as uninitialized `NA_character_`. |
| 2 | `call_ollama_api()` | TaxaTools | Model-not-found regex may miss non-standard error formats. Wrong suggestion given. |
| 3 | `blast_sequences()` | TaxaMatch | No BLAST hits → returns `.empty_blast_result()` (0 rows). Caller may not check. |
| 4 | `.resolve_taxonomy()` | TaxaMatch | All taxonomy batches fail → empty df returned. Looks like "no matches" not "API failure". |
| 5 | `.resolve_taxonomy_from_accessions()` | TaxaMatch | Returns NULL instead of empty df when no matches. Inconsistent return type. |
| 6 | `evaluate_likelihoods()` | TaxaLikely | Failed queries counted but not reported at end. User can't tell how many queries lost. |
| 7 | `evaluate_likelihoods()` | TaxaLikely | NA taxon_name warning doesn't list which sample_ids are affected. |
| 8 | `assign_habitat_biological()` | TaxaHabitat | Species not in lookup silently ignored. No coverage stats returned. |
| 9 | `plot_theta_map_interactive()` | TaxaExpect | Unparseable grid_id dropped with warning. Map shows blank areas without explanation. |
| 10 | `build_context()` | TaxaAssign | LLM synthesis failure → mechanical consensus fallback. No attribute tracks which method used. |

### 2.4 Type coercion and column assumptions (8 issues)

| # | Function | Package | Description |
|---|----------|---------|-------------|
| 1 | `standardize_match_data()` | TaxaMatch | Identity rename logic relies on vector order via `setNames()`. |
| 2 | `blast_sequences()` | TaxaMatch | Merge with duplicate column names → `.x`/`.y` suffixes silently created. |
| 3 | `.blast_remote()` | TaxaMatch | `asv_id` with newline or `>` character breaks FASTA format. |
| 4 | `.parse_blast_xml()` | TaxaMatch | Empty XML node text → `as.numeric("")` → NA silently. |
| 5 | `build_reference_matrix()` | TaxaLikely | `as.data.frame()` on distance matrix may have NaN/Inf values not checked. |
| 6 | `apply_coverage_constraints()` | TaxaLikely | `tolower()` on non-character columns silently coerces. |
| 7 | `combine_occurrence_sources()` | TaxaFetch | `suppressWarnings(as.numeric())` silently coerces unparseable coords to NA. |
| 8 | `filter_gbif_quality()` | TaxaFetch | eDNA keyword filter pastes numeric columns into strings for grepl. |

---

## Section 3: LOW Severity Issues (16 total)

Cosmetic, unlikely edge cases, or minor usability improvements. Listed for completeness.

- `clean_taxon_names()`: Silent type coercion of non-character input (TaxaTools)
- `clean_taxon_names()`: `nchar(NA)` returns NA in ifelse comparison (TaxaTools)
- `build_report_context()`: Unnamed list elements accepted but print method assumes names (TaxaTools)
- `draft_methods_text()`: Code truncation happens without warning (TaxaTools)
- `.resolve_code_input()`: File path detection fragile with `\n` in path (TaxaTools)
- `.summarize_data_frame()`: All-NA character column → `"NA (0)"` in LLM prompt (TaxaTools)
- `.summarize_character()`: Zero-length character vector → misleading output (TaxaTools)
- `flag_reference_errors()`: Empty result set (all clean) returned without message (TaxaLikely)
- `.normalize_scores()`: `(x-lo)/(hi-lo)` can produce NaN if bounds are NA (TaxaLikely)
- `filter_sequences()`: Unreachable variable reference when `do_length=FALSE` (TaxaMatch)
- `make_bbox_wkt()`: Floating-point rounding for very small radius_deg (TaxaFetch)
- `combine_occurrence_sources()`: NA coordinates → `point_id = "NA_NA"` (TaxaFetch)
- `screen_eml_columns()`: Hardcoded `pause_seconds` even when not needed (TaxaFetch)
- `filter_gbif_quality()`: Decimal place cap at 10 (TaxaFetch)
- `call_anthropic_api_pdf()`: Token estimates inaccurate if many PDF pages fail (TaxaFetch)
- `read_biotime_study()`: Non-interactive mode error message unhelpful (TaxaFetch)

---

## Section 4: Prioritized Fix Plan

### Priority 1 — Will crash or silently corrupt results (fix immediately)

**Pattern A: Add timeouts to all LLM provider calls** (3 functions, 1 fix pattern)
- Add `httr2::req_timeout(seconds = 120)` to `call_anthropic_api()`, `call_gemini_api()`, `call_openai_api()`
- Estimated effort: 10 minutes

**Pattern B: Validate required columns exist before processing** (6 functions)
- `.prep_training_data()`: check rank_system columns exist after lowercasing
- `blast_sequences()`: check asv_id and sequence are non-empty/non-NA
- `standardize_match_data()`: ensure auto-detected ranks match column case
- `flag_reference_errors()`: check species.x and species.y exist
- `assign_habitat_biological()`: check point_id_col and taxon_col exist
- `create_taxon_names()`: warn on 0-row input
- Estimated effort: 30 minutes

**Pattern C: Guard against division by zero / degenerate numerics** (5 functions)
- `prepare_model_dataframe()`: check SD > 0 before scaling
- `train_likelihood_model()`: tryCatch on `stats::cov()`, fallback to `diag(2)`
- `generate_full_priors()`: validate max_phi is finite
- `assign_taxa_llm()`: check `is.finite(global_min)` before fill
- `.normalize_scores()`: handle all-NA input explicitly
- Estimated effort: 20 minutes

**Pattern D: Fix silent-wrong-result cases** (4 functions)
- `prompt_api()`: error (not warn) on partial chunk failure, OR return chunk indices
- `verify_taxon_names()`: null-check on `data$names`
- `filter_top_hypotheses()`: validate all `taxon_name_rank` values are in `rank_system`
- `posterior_consensus()`: warn when all hypotheses excluded by threshold
- Estimated effort: 20 minutes

### Priority 2 — Edge cases and confusing errors (fix before beta release)

**Pattern E: Handle 0-row and single-row edge cases** (8 functions)
- Add `if (nrow(df) == 0L)` guards with informative warnings/returns
- Functions: `change_backbone`, `.evaluate_one_query`, `evaluate_likelihoods`, `filter_redundant_hypotheses` (NA sample_id), `read_reference_fasta`, `blast_sequences` (no hits), `compute_posterior` (all-zero likelihoods), `join_priors` (alpha+beta=0)
- Estimated effort: 45 minutes

**Pattern F: Distinguish API errors from empty results** (4 functions)
- `fetch_reference_sequences()`: separate "no sequences found" from "NCBI API failed"
- `audit_barcode_coverage()`: separate count=0 from count=NA in census
- `.resolve_taxonomy()` / `.resolve_taxonomy_from_accessions()`: return empty df (not NULL) on failure
- `fetch_gbif_occurrences()`: add retry/timeout
- Estimated effort: 30 minutes

**Pattern G: Improve error messages** (6 functions)
- `search_literature()`: include key acquisition URL in error
- `fetch_reference_sequences()`: check rentrez at function entry
- `flag_habitat_inconsistencies()`: check all 7 optional packages upfront
- `apply_coverage_constraints()`: include expected column format in error
- `build_taxon_screen_prompt()`: require at least one text column
- `.blast_remote()`: track and report failed batch indices
- Estimated effort: 20 minutes

### Priority 3 — Nice-to-have robustness (fix when convenient)

- Add `prior_source` column to `assign_taxa_llm()` output
- Add `n_plausible` column to `posterior_consensus()` output
- Add coverage stats return to `assign_habitat_biological()`
- Sanitize `asv_id` before FASTA formatting
- Track method used in `build_context()` via attribute
- Improve LLM partial-failure diagnostics across ecosystem

---

## Section 5: Cross-Cutting Patterns

Several fragility patterns recur across packages:

1. **No timeout on HTTP requests** — affects all LLM providers (TaxaTools), GBIF (TaxaFetch), NCBI (TaxaLikely), BLAST (TaxaMatch). A single `req_timeout()` pattern would fix all.

2. **Division by zero / degenerate numerics** — affects statistical functions in TaxaExpect, TaxaLikely, and TaxaAssign. Pattern: always check denominator > 0 or use `tryCatch` with informative fallback.

3. **Silent empty results vs API failures** — affects NCBI queries (TaxaLikely), BLAST (TaxaMatch), GBIF (TaxaFetch). Pattern: return a list with `$result` and `$errors` or attach failure metadata as attributes.

4. **Column existence not validated early** — affects column-name-driven functions across all packages. Pattern: validate all expected columns at function entry, before any processing.

5. **0-row data frames silently pass through** — affects most pipeline functions. Pattern: add `if (nrow(df) == 0L) { warning(...); return(df) }` guard at entry.
