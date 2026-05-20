# Taxonomy Rank Generalization Review

**Prompt 5 — TaxaID Polishing Roadmap**
**Generated:** 2026-04-13 (Session 56)

---

## Overview

Taxonomic hierarchy handling is a cross-cutting concern in TaxaID. Every package
touches rank columns, and fragility in rank assumptions is one of the most likely
sources of user-facing failures. This review covers three tasks:

1. **Fragility scan**: where code breaks if the backbone or available ranks change
2. **Generalization opportunities**: where rank-specific logic could be broadened
3. **GITA pattern assessment**: whether the `f_generalize_taxonomy_ranks` approach
   should be promoted to TaxaTools

---

## Conventions to Enforce

These conventions are stated in the roadmap and should be consistently documented
and validated across the ecosystem:

| Convention | Status |
|---|---|
| Subspecies not used (make apparent to users) | Partially enforced — `standardize_match_data()` includes subspecific ranks in `.standard_match_ranks` but no other function uses them. No warning emitted if subspecific columns are present. |
| Species and genus always present | Not enforced — most functions silently proceed with whatever columns exist. `evaluate_likelihoods()` will fail cryptically if genus is absent. |
| Rank names always lowercase | Enforced in `.prep_training_data()` (`tolower(names(raw_df))`), `standardize_match_data()`, and `create_taxon_names()`. Not enforced in consensus functions or `expand_unreferenced_hypotheses()`. |
| Ranks ordered coarse to fine | Enforced by convention (`rank_system` parameter docs). `.generalize_ranks()` relies on this order. |
| `taxon_name` + `taxon_name_rank` are canonical | Consistently used across TaxaLikely, TaxaAssign, and TaxaMatch. |

---

## Task 1: Fragility Scan

### 1.1 Repeated `std_order` definitions

**Problem:** The standard rank ordering `c("kingdom", "phylum", "class", "order",
"family", "genus", "species")` is defined independently in at least 4 locations:

| File | Line | Variable name |
|---|---|---|
| `TaxaAssign/R/posterior_consensus.R` | 182 | `std_order` |
| `TaxaAssign/R/score_consensus.R` | 129 | `std_order` |
| `TaxaAssign/R/assign_taxa_llm.R` | 305 | `std_tax_cols` |
| `TaxaMatch/R/standardize_match_data.R` | 8-13 | `.standard_match_ranks` (extended) |

Each definition is slightly different. `standardize_match_data.R` includes 21 ranks
(domain through form). The TaxaAssign definitions use the 7 major Linnaean ranks.
If a new rank needs to be added (e.g., "infraclass" for some backbones), every
definition must be found and updated.

**Recommendation:** Define a single canonical rank order in TaxaTools as an
exported constant (e.g., `standard_ranks`) with both major and extended versions.
All downstream packages reference `TaxaTools::standard_ranks` instead of defining
their own.

**Priority:** High — this is the single highest-value fix for rank fragility.

### 1.2 Hard-coded rank column names in BLAST taxonomy resolution

**Problem:** `TaxaMatch/R/blast.R:728-738` builds a data frame with exactly 7
hard-coded rank columns:

```r
data.frame(
  taxid   = taxid,
  kingdom = lineage[["kingdom"]] %||% NA_character_,
  phylum  = lineage[["phylum"]]  %||% NA_character_,
  class   = lineage[["class"]]   %||% NA_character_,
  order   = lineage[["order"]]   %||% NA_character_,
  family  = lineage[["family"]]  %||% NA_character_,
  genus   = lineage[["genus"]]   %||% NA_character_,
  species = ...,
  stringsAsFactors = FALSE
)
```

If the NCBI lineage includes ranks not in this list (e.g., "subphylum",
"superorder"), they are silently dropped. If a backbone omits one of these 7
(e.g., GBIF omits "class" for some fish taxa), the column will be all-NA.

**Fragility:** Low-to-medium. The 7 Linnaean ranks are almost always present in
NCBI. But the hard-coded `data.frame()` means adding a rank requires editing
internal code.

**Recommendation:** Build the data frame dynamically from a rank constant:
```r
ranks <- TaxaTools::standard_ranks  # or a local copy
row <- stats::setNames(
  lapply(ranks, function(r) lineage[[r]] %||% NA_character_),
  ranks
)
```

### 1.3 `expand_unreferenced_hypotheses()` requires exactly species/genus/family

**Problem:** `TaxaAssign/R/expand_unreferenced.R:85` hard-codes:
```r
needed_unref <- c("species", "genus", "family")
```

This means the unreferenced species expansion works only with the three finest
Linnaean ranks. If a user's data includes "order" but not "family" (unlikely but
possible with some marine invertebrate backbones), expansion fails.

**Fragility:** Low — the species/genus/family triad is near-universal for the
use cases TaxaID targets (eDNA, camera traps, acoustic monitoring).

**Recommendation:** Add a code comment explaining this is intentional (unreferenced
species detection is inherently genus/family-level), and improve the error message
to say *why* these columns are needed.

### 1.4 Genus derivation from species binomial

**Problem:** Multiple files derive genus from species using `sub(" .*", "", x)`:

| File | Line | Context |
|---|---|---|
| `TaxaAssign/R/posterior_consensus.R` | 430 | `.extract_rank_values()` |
| `TaxaTools/R/create_taxon_names.R` | — | Splits binomial for rank detection |

This is the standard biological convention (genus is the first word of a binomial).
It breaks only for:
- Subspecies trinomials (genus is still the first word — still works)
- Hybrid formulas (e.g., "Genus species × Genus species") — extremely rare in
  reference databases

**Fragility:** Very low. This is a well-motivated biological heuristic.

**Recommendation:** No change needed. Add a brief comment where used:
`# Genus = first word of binomial (standard taxonomic convention)`

### 1.5 Missing-backbone column silent failures

**Problem:** When `rank_system = NULL`, several functions auto-detect rank columns
by intersecting `std_order` with `names(df)`. If the intersection is empty (user's
columns are named differently, e.g., "Class" instead of "class"), they fall back to
`c("family", "genus", "species")` — which may also be absent.

| Function | Behavior on empty detection |
|---|---|
| `posterior_consensus()` | Falls back to `c("family", "genus", "species")` |
| `score_consensus()` | Falls back to `c("family", "genus", "species")` |
| `assign_taxa_llm()` | Uses `std_tax_cols` intersection — could be empty |

**Fragility:** Medium. The fallback is reasonable for most users, but the failure
mode is silent — no warning that auto-detection found nothing.

**Recommendation:** Emit a `cli::cli_warn()` when auto-detection falls back:
```r
if (length(detected) == 0) {
  cli::cli_warn("No standard rank columns detected; falling back to family/genus/species.")
  rank_system_eff <- c("family", "genus", "species")
}
```

### 1.6 Coverage functions require "species" column by name

**Problem:** `TaxaLikely/R/coverage.R` functions (`audit_barcode_coverage`,
`audit_reference_coverage`) require a column literally named "species" in the
reference data. They use it to extract species lists for NCBI queries.

**Fragility:** Low — the "species" column is a universal convention in taxonomy
data. But if the user has "Species" (title case) or "scientificName" (DarwinCore),
the function fails without explanation.

**Recommendation:** Add `tolower()` on column names at function entry (same pattern
as `.prep_training_data()`).

### 1.7 `fetch_reference_sequences()` species/genus downsampling logic

**Problem:** `TaxaLikely/R/fetch.R:440-455` has genus-specific and species-specific
downsampling logic that references "genus" and "species" columns by name. This is
inherent to the function's purpose (fetching sequences *per species* from NCBI)
and cannot be meaningfully generalized.

**Fragility:** None — this is conceptually genus/species-specific by design.

**Recommendation:** No change needed.

---

## Task 2: Generalization Opportunities

### 2.1 Rank-aware LCA (Lowest Common Ancestor) algorithm

**Current state:** `.find_lca()` in `posterior_consensus.R` walks up the rank
hierarchy to find the first rank where all candidates agree. It already works with
any set of ranks present in the data — it is rank-general.

**Assessment:** No generalization needed. Well-designed.

### 2.2 `filter_redundant_hypotheses()` — already generalized

**Current state:** `TaxaMatch/R/filter_redundant.R` accepts `rank_system` parameter
and works with any ordered set of ranks. Default is `c("kingdom", "phylum", "class",
"order", "family", "genus", "species")`.

**Assessment:** No generalization needed. Good design.

### 2.3 `rank_thresholds` in `score_consensus()` — partially generalized

**Current state:** Default `rank_thresholds = c(species = 98, genus = 95,
family = 90, order = 85)`. These are named by rank, so the function works with
any rank system. However, only 4 ranks have defaults.

**Assessment:** The defaults are conventional for DNA barcoding. Users working with
coarser ranks (phylum, class) would need to supply their own thresholds, which is
already possible via the parameter.

**Recommendation:** Document in roxygen that the default thresholds cover 4 ranks;
users can extend for additional ranks.

### 2.4 Score normalization — fully general

**Current state:** `.normalize_scores()` auto-detects 0-100 vs 0-1 scale and
normalizes. No rank dependency.

**Assessment:** No change needed.

### 2.5 `create_taxon_names()` — already generalized

**Current state:** Accepts `rank_system` parameter; picks the most-specific non-NA
rank per row. Works with any ordered set of rank column names.

**Assessment:** The core function for rank-aware column handling. Well-designed.

### 2.6 Opportunity: `change_backbone()` rank parsing

**Current state:** `TaxaTools/R/change_backbone.R` parses pipe-delimited
classification paths and ranks from `verify_taxon_names()` output. It creates wide
columns from whatever rank names appear in the data.

**Assessment:** Already general — it does not assume specific rank names.

---

## Task 3: GITA Generalization Pattern Assessment

### 3.1 The GITA pattern

The original source (`inst/GITA functions_24.R`) defines two functions:

**`f_generalize_taxonomy_ranks(df, taxonomy_ranks)`** — renames user-facing rank
columns (e.g., "family", "genus", "species") to generic codes
(`taxonomy_code_a`, `taxonomy_code_b`, `taxonomy_code_c`, ...) where `code_a` is
the finest rank. This allows all downstream functions to reference `taxonomy_code_a`
regardless of whether it represents species, genus, or subspecies.

**`f_ungeneralize_taxonomy_ranks(df, taxonomy_ranks)`** — reverses the mapping,
restoring original rank names.

### 3.2 Current TaxaID adoption

TaxaLikely already implements this pattern as `.generalize_ranks()` in `R/train.R`:

```r
.generalize_ranks <- function(df_sub, ranks) {
  present   <- intersect(ranks, names(df_sub))
  if (length(present) == 0L) return(df_sub)
  codes     <- paste0("rank_code_", letters[seq_along(present)])
  rename_map <- stats::setNames(rev(present), codes)
  dplyr::rename(df_sub, !!rename_map)
}
```

This is used *only* inside `.prep_training_data()` for model training. The
corresponding "ungeneralize" function was identified as dead code and dropped.

### 3.3 Should this pattern be promoted to TaxaTools?

**Arguments for:**
- Centralizes rank abstraction — any function can work on `rank_code_a` without
  knowing whether it represents "species" or "subspecies"
- Eliminates the need for `std_order` definitions in every file
- Makes it straightforward to add new ranks without changing internal logic
- The GITA source used this successfully across dozens of functions

**Arguments against:**
- Adds cognitive overhead — users must understand the code_a/code_b mapping
- Most TaxaID functions already work by intersecting `rank_system` with column names,
  achieving the same flexibility without renaming
- The ungeneralize step is error-prone if the original `rank_system` is not preserved
- Only one function (`.prep_training_data`) currently uses it — limited proven need
- The pattern solves a problem that `rank_system` parameter + `intersect()` already
  solves at the interface level

**Assessment:** The generalize/ungeneralize pattern is valuable **within** functions
that need to manipulate rank columns generically (like model training, where you need
`code_a` to always mean "finest rank"). But it should NOT be the primary rank-handling
strategy across the ecosystem. The `rank_system` parameter pattern already used by
most functions is simpler, more transparent to users, and achieves the same goal.

### 3.4 Recommendation

**Do not promote `generalize_ranks()` to TaxaTools as an exported function.**

Instead, implement two simpler TaxaTools exports that address the root fragility:

1. **`standard_ranks`** — exported character vector constant:
   ```r
   #' Standard Linnaean rank order (coarse to fine)
   #' @export
   standard_ranks <- c("kingdom", "phylum", "class", "order",
                        "family", "genus", "species")
   ```

2. **`extended_ranks`** — exported character vector with intermediate ranks:
   ```r
   #' Extended rank order including intermediate ranks (coarse to fine)
   #' @export
   extended_ranks <- c("domain", "kingdom", "subkingdom", "phylum", "subphylum",
                        "superclass", "class", "subclass", "superorder", "order",
                        "suborder", "superfamily", "family", "subfamily", "tribe",
                        "genus", "subgenus", "species")
   ```

3. **`detect_ranks(df, rank_system = NULL)`** — detect rank columns in a data frame:
   ```r
   #' Detect rank columns present in a data frame
   #'
   #' If rank_system is NULL, intersects column names with standard_ranks.
   #' Warns when falling back to family/genus/species.
   #' @export
   detect_ranks <- function(df, rank_system = NULL) { ... }
   ```

This trio replaces the 4+ independent `std_order` definitions, provides a consistent
auto-detection mechanism, and avoids the cognitive overhead of generalize/ungeneralize.

The existing `.generalize_ranks()` in TaxaLikely's `.prep_training_data()` should
remain as-is — it is well-suited for internal model training where generic column
names are genuinely needed.

---

## Summary of Findings

### Fragility issues (7 found)

| # | Issue | Severity | Fix complexity |
|---|---|---|---|
| 1.1 | Repeated `std_order` definitions | High | Low — extract to TaxaTools constant |
| 1.2 | Hard-coded rank columns in BLAST taxonomy | Medium | Low — build dynamically |
| 1.3 | `expand_unreferenced_hypotheses` requires species/genus/family | Low | Trivial — improve error message |
| 1.4 | Genus derivation from binomial | Very low | None — add comment only |
| 1.5 | Silent fallback on empty rank detection | Medium | Low — add warning |
| 1.6 | Coverage functions require "species" column | Low | Low — add `tolower()` |
| 1.7 | Fetch downsampling references genus/species | None | None — by design |

### Generalization opportunities

Most functions are already well-generalized via the `rank_system` parameter pattern.
No major generalization gaps found. Minor documentation improvements recommended for
`rank_thresholds` defaults.

### GITA pattern verdict

**Do not promote.** The `rank_system` + `intersect()` pattern already used across the
ecosystem is simpler and achieves the same goal. Instead, centralize the rank constant
and auto-detection logic in TaxaTools.

---

## Recommended Implementation (Prompt 10+)

1. **TaxaTools:** Export `standard_ranks`, `extended_ranks`, and `detect_ranks()`
2. **TaxaAssign:** Replace all `std_order` / `std_tax_cols` definitions with
   `TaxaTools::standard_ranks`
3. **TaxaMatch:** Replace `.standard_match_ranks` with `TaxaTools::extended_ranks`
4. **TaxaMatch:** Build BLAST taxonomy data frame dynamically from rank constant
5. **TaxaAssign/TaxaLikely:** Add `tolower(names(df))` at entry to functions that
   don't already have it
6. **TaxaAssign:** Add `cli::cli_warn()` for empty rank auto-detection fallback
7. **TaxaAssign:** Improve `expand_unreferenced_hypotheses()` error message

Estimated effort: 1-2 sessions (mechanical changes once the TaxaTools constants exist).
