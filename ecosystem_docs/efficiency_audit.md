# Efficiency Audit

**Prompt 7 — TaxaID Polishing Roadmap**
**Generated:** 2026-04-13 (Session 56)

---

## Overview

Scanned all 7 packages for substantial efficiency issues: memory, CPU, API
batching, unnecessary computation, and progress-bar coverage. Focus is on
changes that would noticeably improve user experience, not micro-optimizations.

---

## High-Impact Issues

### E1. Distance matrix expansion — `build_sequence_matrix()`

| | |
|---|---|
| **Function** | `build_sequence_matrix()` |
| **File** | `TaxaLikely/R/build.R:113` |
| **Impact** | **High** |

**Issue:** `as.data.frame(as.table(dist_m))` converts an N×N distance matrix to
an N² row data frame. For 5,000 reference sequences, this creates 25 million rows
(~600 MB for 3 numeric + 2 character columns). This is the single largest memory
consumer in the ecosystem.

**Suggested fix:** Filter the matrix before expanding:
```r
# Instead of: expand all → filter
# Current: dist_tbl <- as.data.frame(as.table(dist_m))
#          out <- dist_tbl |> filter(distance < max_dist)

# Better: extract only below-threshold pairs directly
idx <- which(dist_m < max_dist & row(dist_m) != col(dist_m), arr.ind = TRUE)
out <- data.frame(
  id_x     = rownames(dist_m)[idx[,1]],
  id_y     = colnames(dist_m)[idx[,2]],
  p_match  = 1 - dist_m[idx],
  stringsAsFactors = FALSE
)
```
This avoids creating the N² intermediate data frame entirely. Memory reduction:
~95%+ for typical datasets where `max_dist = 0.25` filters out most pairs.

---

### E2. MC simulation per-query loop — `.evaluate_one_query()`

| | |
|---|---|
| **Function** | `.evaluate_one_query()` |
| **File** | `TaxaLikely/R/evaluate.R:244-277` |
| **Impact** | **High** (with `n_sims > 0`) |

**Issue:** The Monte Carlo simulation loop runs `n_sims` iterations (default up
to 1000), each calling `stats::rnorm()` + a `vapply()` gap computation + a full
`.calc_likelihoods()` call + a row-by-row matching loop. This is repeated for
every `sample_id`.

For 1000 queries × 1000 sims = 1 million full likelihood recalculations.

**Suggested fixes (progressive):**
1. **Vectorize gap calculation** (line 248-253): The `vapply` computes `score[k] - max(score[-k])` for each k. Replace with vectorized: `gap <- score - pmax(sort(score, decreasing=TRUE)[2], -Inf)` (requires sorting once, not N subset operations).
2. **Pre-allocate cand matching** (line 260-272): The inner `for (r in seq_len(nrow(res_agg)))` loop with `which(cand$taxon_name == t_name)` can be replaced with pre-computed index mapping before the simulation loop.
3. **Consider matrix-based MC**: Generate all `n_sims` score vectors as a matrix, compute all gaps at once with matrix operations.

---

### E3. No progress bar — `evaluate_likelihoods()`

| | |
|---|---|
| **Function** | `evaluate_likelihoods()` |
| **File** | `TaxaLikely/R/evaluate.R:383-408` |
| **Impact** | **Medium** (UX) |

**Issue:** The per-query loop (`for (i in seq_along(query_groups))`) has no
progress indicator. With n_sims > 0 and hundreds of queries, this function can
run for minutes with no user feedback. Only a single `message()` at start.

**Suggested fix:** Add `cli::cli_progress_bar()`:
```r
pb <- cli::cli_progress_bar("Evaluating queries", total = length(query_groups))
for (i in seq_along(query_groups)) {
  cli::cli_progress_update(id = pb)
  ...
}
cli::cli_progress_done(id = pb)
```

---

### E4. No progress bar — `build_sequence_matrix()`

| | |
|---|---|
| **Function** | `build_sequence_matrix()` |
| **File** | `TaxaLikely/R/build.R:100-112` |
| **Impact** | **Medium** (UX) |

**Issue:** Alignment (`DECIPHER::AlignSeqs`) and distance computation
(`DECIPHER::DistanceMatrix`) can take minutes on large reference sets. Only
static `message()` calls ("Aligning sequences...") — no progress indication.

**Suggested fix:** DECIPHER functions have their own `verbose` option, currently
set to `FALSE`. Consider setting `verbose = TRUE` for user-facing calls, or
add timing info:
```r
t0 <- proc.time()[["elapsed"]]
aligned <- DECIPHER::AlignSeqs(dna, processors = NULL, verbose = FALSE)
cli::cli_inform("Alignment complete ({round(proc.time()[['elapsed']] - t0, 1)}s)")
```

---

### E5. Sequential NCBI API calls — coverage/fetch functions

| | |
|---|---|
| **Functions** | `audit_barcode_coverage()`, `fetch_reference_sequences()` |
| **Files** | `TaxaLikely/R/coverage.R`, `TaxaLikely/R/fetch.R` |
| **Impact** | **Medium** |

**Issue:** NCBI Entrez API calls are made sequentially with `Sys.sleep()` delays
between each. For `audit_barcode_coverage()`, each species gets its own
per-species nucleotide count query. For 200 species across 10 genera, that's 200
sequential HTTP requests with 1-3 second delays = 5-10 minutes minimum.

**Constraint:** NCBI rate limit (3 requests/second without API key, 10/second
with key). Parallelism is capped by this.

**Suggested fix:** These functions already use exponential backoff and `retmax=0`
(efficient). The main improvement would be:
1. **Batch queries**: NCBI `esearch` supports multiple terms with OR. Query
   multiple species in one call where possible.
2. **NCBI API key awareness**: Check for `NCBI_API_KEY` env var and adjust
   rate accordingly (3→10 req/s).

---

## Medium-Impact Issues

### E6. Repeated taxonomy lookup per sample — `posterior_consensus()`

| | |
|---|---|
| **Function** | `posterior_consensus()` |
| **File** | `TaxaAssign/R/posterior_consensus.R:191-240` |
| **Impact** | **Medium** |

**Issue:** When `lookup_missing_taxonomy = TRUE`, the function calls
`TaxaTools::verify_taxon_names()` for unreferenced taxa. This makes API calls
to the Global Names Verifier. If many samples share the same unreferenced taxa,
the lookup is done once for all unique names (good), but the function could
still be called redundantly across workflow reruns.

**Suggested fix:** This is already reasonably efficient (deduplicates names
before API call). Document that users should cache the result via `saveRDS()`.

---

### E7. `group_split` + `map_dfr` in `compute_posterior()`

| | |
|---|---|
| **Function** | `compute_posterior()` |
| **File** | `TaxaAssign/R/compute_posterior.R:127-129` |
| **Impact** | **Low-Medium** |

**Issue:** `dplyr::group_split(.data$sample_id) |> purrr::map_dfr(...)` creates
a list of data frames per sample, processes each, then row-binds. For thousands
of samples, the overhead of splitting/binding is noticeable.

**Suggested fix:** The MC simulation inside is already vectorized (matrix
operations). The split is needed because normalization is per-sample. This is
acceptable unless profiling shows it's a bottleneck. A grouped `dplyr::mutate()`
could replace it for the point-estimate path.

---

### E8. BLAST polling interval

| | |
|---|---|
| **Function** | `blast_sequences()` |
| **File** | `TaxaMatch/R/blast.R:367` |
| **Impact** | **Low-Medium** |

**Issue:** BLAST result polling uses `Sys.sleep(attempt * 5)` — starts at 5
seconds, increases linearly. For fast queries this is fine, but for slow queries
the user waits with minimal feedback.

**Suggested fix:** Already has messages during polling. Could add estimated
remaining time based on NCBI's `ThereAreHits` and `Status` indicators.

---

### E11. Row-wise `apply()` for GBIF key validation

| | |
|---|---|
| **Function** | `.fetch_chunk()` |
| **File** | `TaxaFetch/R/fetch_gbif_occurrences.R:229-231` |
| **Impact** | **Medium** |

**Issue:** `apply(df[present_cols], 1, function(row) key %in% as.integer(row))`
processes every row individually. For 5,000 records × 9 hierarchy columns, this
is 45,000 per-element comparisons via apply.

**Suggested fix:** Vectorized matrix operation:
```r
m <- as.matrix(df[present_cols])
key_found <- rowSums(m == key, na.rm = TRUE) > 0
```

---

### E12. `crossing()` before filtering — `generate_full_priors()`

| | |
|---|---|
| **Function** | `predict_tier()` (internal) |
| **File** | `TaxaExpect/R/generate_full_priors.R:308` |
| **Impact** | **Medium** |

**Issue:** `tidyr::crossing()` creates all taxon × site combinations, then drops
rows with NA values. For 1000 sites × 500 taxa = 500K rows created before
filtering.

**Suggested fix:** Filter sites before crossing to reduce the intermediate size.

---

### E13. Sequential LLM chunk submission — `prompt_api()`

| | |
|---|---|
| **Function** | `prompt_api()` |
| **File** | `TaxaTools/R/llm_api_utils.R:235-258` |
| **Impact** | **Medium** |

**Issue:** LLM prompt chunks submitted one-at-a-time with `Sys.sleep()` between
each. For habitat prompts with 1000 species split into 5 chunks × 5s per API
call = 25 seconds. Most LLM APIs support concurrent requests.

**Suggested fix:** Not urgent — LLM calls are inherently slow. But documenting
that users with `future` installed could parallelize chunks would help power users.

---

### E14. XML parsing per-hit loop — `.parse_blast_xml()`

| | |
|---|---|
| **Function** | `.parse_blast_xml()` |
| **File** | `TaxaMatch/R/blast.R:536-567` |
| **Impact** | **Medium** |

**Issue:** For each BLAST hit, 15+ individual `xml2::xml_find_first()` +
`xml2::xml_text()` calls. With 1000 hits per query, that's 15,000 XPath
evaluations. Batch extraction with `xml_find_all()` on the document root would
be faster.

**Suggested fix:** Extract all hit fields at once:
```r
accessions <- xml2::xml_text(xml2::xml_find_all(doc, ".//Hit/Hit_accession"))
```

---

### E15. Missing progress bars — TaxaFetch DataONE + TaxaExpect

| | |
|---|---|
| **Functions** | `fetch_dataone_occurrences()`, `train_biodiversity_model()`, `generate_full_priors()` |
| **Files** | `TaxaFetch/R/dataone_standardize.R`, `TaxaExpect/R/train_biodiversity_model.R`, `TaxaExpect/R/generate_full_priors.R` |
| **Impact** | **Medium** (UX) |

**Issue:** `fetch_dataone_occurrences()` processes ~20 datasets × 3s each = 60s
with no progress feedback. `train_biodiversity_model()` fits glmmTMB models
(10-60s) with no progress. `generate_full_priors()` predicts on thousands of
taxon × site combinations with no feedback.

---

### E16. Early exit for sparse lme4 hierarchy — `train_likelihood_model()`

| | |
|---|---|
| **Function** | `train_likelihood_model()` |
| **File** | `TaxaLikely/R/train.R:446-468` |
| **Impact** | **Low-Medium** |

**Issue:** Fits two `lme4::lmer()` models (5-30s each) even when data are too
sparse (< 10 species). Both fail silently and fall back to global mean.

**Suggested fix:** Add early exit: `if (n_species < 10) use_hierarchy <- FALSE`

---

## Low-Impact Issues

### E9. Unnecessary columns carried through `assign_taxa_llm()`

| | |
|---|---|
| **Function** | `assign_taxa_llm()` |
| **File** | `TaxaAssign/R/assign_taxa_llm.R` |
| **Impact** | **Low** |

**Issue:** The full match data frame (all columns) is carried through the LLM
prompt building and likelihood computation, even though only `sample_id`,
`score`, `taxon_name`, `taxon_name_rank`, and taxonomy columns are used.

**Suggested fix:** Select only needed columns early. Minor memory savings.

---

### E10. `compute_moran_basis()` full distance matrix

| | |
|---|---|
| **Function** | `compute_moran_basis()` |
| **File** | `TaxaExpect/R/compute_moran_basis.R:164` |
| **Impact** | **Low** |

**Issue:** `as.matrix(stats::dist(coords))` creates a full N×N distance matrix
for spatial coordinates. For typical grid sizes (< 500 cells), this is fine.
Could become an issue with very fine grids.

**Suggested fix:** No change needed for current use cases. Add a check:
```r
if (nrow(coords) > 5000) cli::cli_warn("Large grid ({nrow(coords)} cells) ...")
```

---

## Progress Bar Coverage Summary

| Function | Package | Typical duration | Has progress bar? | Recommendation |
|---|---|---|---|---|
| `build_sequence_matrix()` | TaxaLikely | 30s - 10min | No (messages only) | **Add timing info** |
| `evaluate_likelihoods()` | TaxaLikely | 5s - 5min | **No** | **Add progress bar** |
| `train_likelihood_model()` | TaxaLikely | 1-10s | No (fast enough) | OK as-is |
| `fetch_reference_sequences()` | TaxaLikely | 1-30min | Messages per batch | Consider progress bar for download phase |
| `audit_barcode_coverage()` | TaxaLikely | 5-30min | No | **Add progress bar** (per-genus) |
| `verify_taxon_names()` | TaxaTools | 2-30s | Messages per batch | OK as-is (batched with messages) |
| `blast_sequences()` | TaxaMatch | 30s - 10min | Messages during poll | OK as-is |
| `assign_taxa_llm()` | TaxaAssign | 30s - 5min | **Yes** | Good |
| `suggest_unreferenced_species()` | TaxaAssign | 1-10min | **Yes** (3 bars) | Good |
| `compute_posterior()` | TaxaAssign | < 5s | No (fast enough) | OK as-is |
| `posterior_consensus()` | TaxaAssign | < 2s | No (fast enough) | OK as-is |
| `train_biodiversity_model()` | TaxaExpect | 5-60s | Messages only | **Add progress bar** |
| `generate_full_priors()` | TaxaExpect | 5-30s | No | **Add progress bar** |
| `fetch_dataone_occurrences()` | TaxaFetch | 20-60s | No | **Add progress bar** |

**Functions needing progress bars:** `evaluate_likelihoods()`, `audit_barcode_coverage()`, `fetch_dataone_occurrences()`, `train_biodiversity_model()`, `generate_full_priors()`
**Functions needing timing info:** `build_sequence_matrix()`

---

## Priority Summary

| Priority | Item | Impact | Effort |
|---|---|---|---|
| **High** | E1: Distance matrix expansion | Memory ~95% reduction | 30 min |
| **High** | E2: MC simulation vectorization | CPU ~5-10× speedup | 1-2 hrs |
| **Medium** | E3: Progress bar for `evaluate_likelihoods()` | UX | 15 min |
| **Medium** | E4: Timing info for `build_sequence_matrix()` | UX | 10 min |
| **Medium** | E5: NCBI API batching | API time ~2-5× reduction | 1-2 hrs |
| **Medium** | E11: Row-wise apply in GBIF fetch | CPU | 20 min |
| **Medium** | E12: crossing() before filtering | Memory | 20 min |
| **Medium** | E14: XML batch parsing in BLAST | CPU | 30 min |
| **Medium** | E15: Progress bars (DataONE, TaxaExpect) | UX | 30 min |
| **Low-Med** | E13: Sequential LLM chunks | Wall-clock time | Document only |
| **Low-Med** | E16: lmer early exit | CPU 10-60s savings | 10 min |
| **Low** | E6-E10: Various minor | Minimal | 1 hr total |

**Estimated total effort for High + Medium items: 6-7 hours.**
