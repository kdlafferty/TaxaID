# Redundancy Audit

**Prompt 6 — TaxaID Polishing Roadmap**
**Generated:** 2026-04-13 (Session 56)

---

## Overview

Scanned all 7 packages (R/ source files, inst/ workflow scripts, tests/) for
duplicate logic, near-duplicate functions, and dead code. Findings organized by
type, with consolidation recommendations and risk assessment.

---

## Cross-Package Duplicate Logic

These patterns are repeated identically or near-identically across package boundaries.
These are the highest-value consolidation targets because they create maintenance
burden when the shared pattern needs to change.

| # | Pattern | Locations | Type | Recommendation | Risk |
|---|---|---|---|---|---|
| D1 | `std_order` / `std_tax_cols` — standard 7 Linnaean ranks constant | `TaxaAssign/R/posterior_consensus.R:182`, `TaxaAssign/R/score_consensus.R:129`, `TaxaAssign/R/assign_taxa_llm.R:305`, `TaxaMatch/R/standardize_match_data.R:8-13` (extended) | Duplicate | Export `standard_ranks` from TaxaTools (already recommended in Prompt 5) | Low — pure data constant |
| D2 | `%||%` null-coalescing operator defined **6 times** with **2 different implementations** | `TaxaTools/R/llm_api_utils.R:503`, `TaxaFetch/R/dataone_standardize.R:1513`, `TaxaFetch/R/get_keys_from_context.R:189`, `TaxaFetch/inst/migrate_prompt_api.R:289`, `TaxaHabitat/R/parse_habitat_response.R:457`, `TaxaMatch/R/blast.R:825` | Duplicate (with variation) | Define once in TaxaTools; remove all other definitions. Note: TaxaMatch version checks `is.null(x)` only; others also check `length(x) > 0`. Standardize on the fuller version. | Low — but the inconsistent implementations could cause subtle bugs |
| D3 | `.is_valid_species_name()` — filter sp./cf./aff./uncultured/non-binomial | `TaxaLikely/R/coverage.R:76`, `TaxaAssign/R/suggest_unreferenced_species.R:99` | Duplicate | Move to TaxaTools as an exported utility; both packages already depend on TaxaTools | Low |
| D4 | `.barcode_length_defaults` + `.resolve_barcode_lengths()` — barcode marker → bp length lookup | `TaxaLikely/R/coverage.R:18-55`, `TaxaMatch/R/sequence_input.R:468-510`, `TaxaAssign/R/suggest_unreferenced_species.R:40-70` | Duplicate (3 copies) | Move to TaxaTools as exported `barcode_length_defaults` and `resolve_barcode_lengths()`. All 3 packages depend on TaxaTools. | Low — pure lookup logic |
| D5 | `.habitat_palette()` + `.he()` — habitat colour assignment + HTML escaping | `TaxaHabitat/R/utils_plot.R` (166 lines), `TaxaExpect/R/utils_plot.R` (84 lines) | Duplicate | TaxaExpect depends on TaxaHabitat. Move to TaxaHabitat only; TaxaExpect calls `TaxaHabitat:::.habitat_palette()` or export from TaxaHabitat. | Medium — cross-package internal calls are fragile; better to export |
| D6 | Exponential backoff retry pattern — 3-attempt retry with `Sys.sleep(attempt)` or `Sys.sleep(attempt * N)` | `TaxaMatch/R/blast.R` (3 locations: lines 367, 679, 791), `TaxaAssign/R/suggest_unreferenced_species.R:376`, `TaxaLikely/R/fetch.R` (3 locations: lines 74, 130, 158), `TaxaLikely/R/coverage.R:461` | Near-duplicate | Extract a shared `retry_with_backoff(fn, max_attempts, multiplier)` helper to TaxaTools. Not urgent — each instance is ~5 lines and context-specific error handling varies. | Medium — retry logic interacts with different APIs; abstraction may lose clarity |
| D7 | `tolower(names(df))` at function entry — case-normalize column names | 28+ locations across 6 packages | Duplicate pattern | Not worth extracting — it's a one-liner idiom. But consistency should be enforced: several functions (consensus, expand_unreferenced) are missing it. | None — one-liner |
| D8 | Genus derivation from species binomial `sub(" .*", "", x)` | `TaxaAssign/R/posterior_consensus.R:487`, `TaxaAssign/R/assign_taxa_llm.R:430,537` | Duplicate (within package) | Leave as-is — context-specific one-liner. A shared helper adds more complexity than it saves. | None |

---

## Dead Code

| # | Item | Location | Type | Recommendation | Risk |
|---|---|---|---|---|---|
| X1 | `combine_occurrence_sources()` — entire file (230+ lines) | `TaxaFetch/R/combine_occurrence_sources.R` | Dead function | Superseded by `rename_cols()` + `stack_occurrences()` per name change log (Session 19). Still referenced in comments/roxygen in 3 other files. **Delete file; update stale references.** | Low — no callers; update @seealso links |
| X2 | `TaxaFetch_workflow copy.R` | `TaxaFetch/inst/TaxaFetch_workflow copy.R` | Dead file | Stale backup copy with space in filename. Delete. | None |
| X3 | `migrate_prompt_api.R` | `TaxaFetch/inst/migrate_prompt_api.R` | Dead file | Session 26 migration script. Migration is long complete. Also contains its own `%||%` definition. Delete. | None |
| X4 | `globalVariables(character(0))` in 22 files | Multiple packages | Dead code | Files with no NSE references don't need this line. Convention says "omit entirely from files with no NSE references." Remove from all 22 files. | None — no functional impact |
| X5 | `TaxaLikely_workflow.R` (monolithic) | `TaxaLikely/inst/TaxaLikely_workflow.R` | Dead file | Superseded by 5 workflow scripts in `inst/workflows/` (Session 50). Retained for reference per CLAUDE.md but should be deleted now that the split is stable. | Low |
| X6 | `habitat_scheme_workflow.R` | `TaxaFetch/inst/habitat_scheme_workflow.R` | Potentially dead | Habitat functions moved to TaxaHabitat (Session 28). Check if this workflow has been migrated. | Medium — verify before deleting |

---

## Near-Duplicate Functions

| # | Functions | Locations | Differences | Recommendation | Risk |
|---|---|---|---|---|---|
| N1 | `audit_barcode_coverage()` vs `audit_reference_coverage()` | `TaxaLikely/R/coverage.R` | Both query NCBI for taxonomic completeness. Barcode version adds per-species nucleotide count queries and barcode-specific filtering. Reference version is simpler (taxonomy tree only). | Keep both — they serve distinct use cases (barcode vs non-barcode). The shared NCBI taxonomy query logic could be extracted into a shared internal helper, but the gain is modest. | N/A |
| N2 | `draft_methods_text()` vs `draft_results_text()` | `TaxaTools/R/draft_text.R` | Both build LLM prompts with context injection. Methods reads R code; Results reads R objects. Shared prompt scaffolding (context injection, audience param, LLM caution instructions) is already in the same file. | No change needed — the shared scaffolding is already co-located. | N/A |
| N3 | `call_anthropic_api()` / `call_gemini_api()` / `call_openai_api()` / `call_ollama_api()` | `TaxaTools/R/llm_api_utils.R` | Four parallel implementations with identical structure but different API endpoints, auth headers, and response parsing. `max_tokens = 3000L` hardcoded in all 4. | These are necessarily separate (different APIs). The shared `max_tokens` default could be a module-level constant. Not urgent. | N/A |
| N4 | `posterior_consensus()` vs `score_consensus()` | `TaxaAssign/R/posterior_consensus.R`, `TaxaAssign/R/score_consensus.R` | Both compute LCA-based consensus taxonomy. Posterior version uses posterior probabilities + cumulative threshold; score version uses raw scores + gap + rank thresholds. Both define `std_order` locally. | Keep both — fundamentally different algorithms. Consolidate shared `std_order` via D1 above. The internal `.find_lca()` could potentially be shared, but the implementations differ enough that the coupling cost outweighs the benefit. | N/A |

---

## Within-Package Patterns

| # | Pattern | Package | Details | Action |
|---|---|---|---|---|
| W1 | NCBI exponential backoff in fetch.R (3 identical blocks) | TaxaLikely | `.fetch_summaries_batched()`, `.fetch_taxonomy_map()`, `.fetch_fasta_batched()` all have identical retry loops | Could extract `.ncbi_retry(fn)` but gain is minimal for 3 internal uses |
| W2 | Column validation `miss <- setdiff(required, names(df)); if (length(miss)) stop(...)` | All packages | Appears ~20+ times ecosystem-wide | One-liner idiom; not worth a shared function |
| W3 | `if (!is.logical(x) \|\| length(x) != 1L \|\| is.na(x)) stop(...)` pattern | Multiple | Logical parameter validation | Idiom; leave as-is |
| W4 | LLM context block building (ctx fields → formatted string) | TaxaAssign | 4 locations: `.build_plausible_prompt()`, `.build_family_prompt()`, `.build_taxa_prompt()`, `.build_synthesis_prompt()` — ~85% identical logic for context field extraction and formatting | Extract `.build_context_block(ctx)` internal helper; medium value |
| W5 | JSON array extraction from LLM responses (`sub("(?s).*?(\\[...\\]).*", ...)`) | TaxaAssign | 3 locations: `.parse_plausible_response()`, `.parse_family_response()`, `.parse_taxa_response()` | Extract `.extract_json_array(response)` trivial helper; low value |
| W6 | Genus extraction `sub(" .*", "", x)` | TaxaAssign | 8 instances across 4 files (posterior_consensus, assign_taxa_llm, suggest_unreferenced_species) | Could extract `.extract_genus()` but one-liner idiom; low value |
| W7 | `.find_lca()` + `.extract_rank_values()` defined in posterior_consensus.R but reused by score_consensus.R | TaxaAssign | Cross-file internal dependency acknowledged in comments. Works but fragile. | Move to a shared `R/internal_helpers.R` if refactoring; low priority |

---

## Summary

### Consolidation Priority

| Priority | Item | Impact | Effort |
|---|---|---|---|
| **High** | D1: `standard_ranks` constant to TaxaTools | Eliminates 4+ independent definitions; enables Prompt 5 fixes | 30 min |
| **High** | D2: `%||%` — single definition in TaxaTools | Eliminates 6 definitions with 2 inconsistent implementations | 30 min |
| **High** | D4: barcode length defaults to TaxaTools | Eliminates 3 identical copies across 3 packages | 30 min |
| **High** | X1: Delete `combine_occurrence_sources.R` | 230 lines of dead code + stale references | 15 min |
| **Medium** | D3: `.is_valid_species_name()` to TaxaTools | Eliminates 2 copies; useful standalone utility | 20 min |
| **Medium** | D5: `utils_plot.R` — consolidate to TaxaHabitat | Eliminates 84-line copy in TaxaExpect | 20 min |
| **Medium** | X4: Remove 22 empty `globalVariables(character(0))` | Cleans up dead convention noise | 15 min |
| **Low** | X2-X3, X5-X6: Delete stale inst/ files | ~4 dead files; verify X6 first | 15 min |
| **Low** | D6: Shared retry helper | 7+ copies of backoff pattern; but each is context-specific | 1 hr |
| **Skip** | N1-N4: Near-duplicate functions | All serve distinct purposes; consolidation would increase coupling | — |
| **Skip** | W1-W3: Within-package idioms | Too small to justify extraction | — |

### Totals

- **8 cross-package duplicate patterns** (6 actionable, 2 skip)
- **6 dead code items** (all actionable)
- **4 near-duplicate function pairs** (all skip — distinct purposes)
- **7 within-package patterns** (2 medium value, 5 low/skip)

Estimated total consolidation effort: **3-4 hours** for all high + medium items.
