# Refactor: Unified Likelihood Pipeline
# Designed: Session 99 (2026-06-02)
# Status: PLANNED — not yet implemented

---

## Motivation

The current pipeline has two separate entry points for likelihood computation:
- `evaluate_likelihoods()` — eDNA/similarity scores, requires trained model
- `expand_consensus_candidates()` — no-score or single-candidate pathways

These diverge structurally, use inconsistent column names, and cannot accommodate
neural net probability scores (softmax outputs summing to 1). The goal is a single,
modular pipeline that handles all data types from TaxaMatch with consistent
column naming and auditable score transformations.

---

## Decisions Made in Session 99

### Score column naming convention
All score columns use `score_X` prefix. **This is a breaking change from current names.**

| New name | Old name | Description |
|---|---|---|
| `score_original` | `score` | Raw score from classifier/aligner — never modified |
| `score_norm` | *(new)* | Normalized to 0–1 |
| `score_softmax` | *(new)* | Exponential-weighted, ratio-normalized (LLM pathway only) |
| `score_likelihood` | `likelihood_point_est` | Point estimate — always the column TaxaAssign reads |
| `score_likelihood_mean` | `likelihood_mean` | Monte Carlo mean |
| `score_likelihood_sd` | `likelihood_sd` | Monte Carlo SD |
| `score_method` | *(new)* | Character column: method used to produce `score_likelihood` |

`score_method` values: `"bivariate_normal"`, `"softmax"`, `"probability"`, `"none"`.
Stored as a **plain column** (not attribute, not list wrapper) so it survives joins.

### New three-function pipeline (TaxaLikely)

```
unreferenced_candidates(match_df, rank_system)
  → assign_scores(hypotheses_df, score_type, ...)
    → model_likelihoods(scored_df, model_params, ...)   [similarity pathway only]
```

Wrapper: `compute_likelihoods(match_df, score_type, model_params = NULL, ...)` calls all three.

**Naming rationale:** `model_likelihoods()` (not `assign_likelihoods()`) distinguishes the
bivariate normal modeling step from the simpler score-assignment step. `compute_likelihoods()`
is the orchestrating wrapper that routes through the appropriate steps. The three function names
now reflect three distinct operations: generate structure → assign scores → fit model.

### score_type vocabulary
| Value | Description |
|---|---|
| `"none"` | No score column — uniform likelihoods (score_likelihood = 1.0 for all) |
| `"probability"` | Neural net softmax outputs summing to ≤ 1 — used directly as ratios |
| `"similarity"` | DNA/image similarity scores — routes to bivariate normal model (requires model_params) |
| `"similarity_softmax"` | Similarity scores without a trained model — exponential weighting (LLM shortcut pathway) |

### Normalization: ratio normalization throughout
All `score_likelihood` values are **likelihood ratios** (÷ max), NOT probabilities (÷ sum).
- H1 rows normalized first; H2/H3 added after — H1 values unaffected by number of unreferenced rows
- Neural net probabilities converted to ratios (÷ max) before adding H2/H3
- TaxaAssign normalizes posteriors — absolute likelihood scale does not matter

### H2/H3 anchor: max vs. median by pathway
- **Bivariate normal pathway** (`"similarity"`): anchor at **best (max)** median-aggregated score.
  Delta shift corrects downward; max + delta is appropriate.
- **Softmax pathway** (`"similarity_softmax"`): anchor at **median** exp-score of referenced congeners.
  No delta correction; median is more conservative and prevents unreferenced taxa from
  competing equally with the best referenced match.
- Document both as intentional, not inconsistent.

### H2/H3 single-anchor convention (preserved)
One H2 row (unreferenced species in best candidate's genus) and one H3 row
(unreferenced genus in best candidate's family) per query. Queries with near-tied
genera are expected to route through the consensus/upranking pathway. See Known
Footguns in TaxaLikely CLAUDE.md.

### hypothesis_type vocabulary (extended)
| Value | Meaning |
|---|---|
| `"specific_candidate"` | Referenced taxon with a match |
| `"unreferenced_species"` | Genus represented in reference, species not |
| `"unreferenced_genus"` | Family represented, genus not |
| `"unreferenced_family"` | Family not represented — replaces `unknown_species` in assign_taxa_llm |

### Functions removed
- `expand_consensus_candidates()` — replaced by `unreferenced_candidates()` + `assign_scores()`

### TaxaMatch
- `standardize_match_data()` output renames `score` → `score_original`
- All internal references updated simultaneously

### TaxaAssign
- `compute_posterior()` reads `score_likelihood`, `score_likelihood_mean`, `score_likelihood_sd`
- `assign_taxa_llm()` rewritten to accept `scored_hypotheses_df` (output of `assign_scores()`)
  rather than raw `match_df`; internal `.score_to_likelihood()` removed (replaced by pipeline)

### Finalized function signatures

```r
unreferenced_candidates(
  match_df,
  rank_system                  = NULL,    # auto-detect if NULL
  include_unreferenced_family  = FALSE    # see guidance below
)

assign_scores(
  hypotheses_df,
  score_type,                             # "none", "probability", "similarity_softmax", "similarity"
  score_col                    = "score_original",
  score_sharpness              = 0.1      # similarity_softmax only
)

model_likelihoods(                        # bivariate normal modeling step; similarity pathway only
  scored_df,
  model_params,
  rank_system          = NULL,
  ratio_threshold      = 0.01,
  min_match_threshold  = 0.50,
  n_sims               = 0L,
  min_coverage         = NULL,
  verbose              = FALSE
)

compute_likelihoods(                      # orchestrating wrapper
  match_df,
  score_type,
  model_params   = NULL,
  rank_system    = NULL,
  ...
)
```

**assign_scores() validation:** should warn when score_type appears inconsistent with data:
- `score_type = "none"` but `score_original` is non-NA → warn user that scores exist but are being ignored
- `score_type = "probability"` but scores per observation do not sum to ~1 (tolerance ±0.05) → warn
- `score_type = "probability"` but any score > 1 → warn (likely on wrong scale)
- `score_type = "similarity"` or `"similarity_softmax"` but `score_original` is all-NA → stop with error
- `score_type = "similarity"` but `score_original` values all ≤ 1 → inform user that scores appear to
  be on 0–1 scale (auto-normalization will treat as already normalized)

**assign_scores() contract for downstream steps:**
- `"none"`, `"probability"`, `"similarity_softmax"`: writes `score_likelihood` + `score_method` — pipeline
  is complete, ready for TaxaAssign
- `"similarity"`: writes `score_norm` only, does NOT write `score_likelihood` — `model_likelihoods()`
  is required to complete the pipeline

### Decision 2: referenced-not-returned recovery (deferred)
The bobcat/ocelot case — referenced species that "lost" classifier competition and were
not returned as candidates deserve likelihood = residual (1 - sum(returned scores)) — cannot
be implemented without a reference_taxa list. Deferred to future enhancement.

**Future hook:** after joining with TaxaExpect, any taxon with a prior but no corresponding
`score_likelihood` row could be detected and assigned residual likelihood at that join step.
TaxaAssign is the natural location for this logic since it sees both the likelihood df and
the prior df simultaneously. Add a `fill_residual_referenced` parameter to the relevant
TaxaAssign join function when implementing.

### Decision 3: include_unreferenced_family guidance
`include_unreferenced_family = FALSE` (default). Set to `TRUE` when:
- Using the LLM shortcut pathway (`assign_taxa_llm()`) **without** TaxaExpect priors — the
  catch-all prevents posteriors over-concentrating on the candidate set when the full prior
  community is not modeled
- The reference database has known family-level gaps and you want an explicit "something else"
  hypothesis to absorb residual posterior mass
- Do NOT set to `TRUE` when using the full TaxaExpect pipeline — TaxaExpect priors already
  distribute mass across the broader community including unrepresented families; adding
  `unreferenced_family` would double-count that mass

`assign_taxa_llm()` calls `unreferenced_candidates(include_unreferenced_family = TRUE)` internally.

---

## Files to Change (by package)

### TaxaMatch
| File | Change |
|---|---|
| `R/standardize.R` (or equivalent) | Rename output column `score` → `score_original` |
| Tests | Update column name references |
| Workflows / README | Update column name references |
| CLAUDE.md | Update match object interface table |

### TaxaLikely
| File | Change |
|---|---|
| `R/evaluate.R` | Rename output columns; refactor `.evaluate_one_query()` internals into `assign_likelihoods()`; `evaluate_likelihoods()` becomes a wrapper or is deprecated |
| `R/expand_consensus.R` | Delete — replaced by new functions |
| `R/unreferenced_candidates.R` | **New file** — `unreferenced_candidates()` |
| `R/assign_scores.R` | **New file** — `assign_scores()` |
| `R/model_likelihoods.R` | **New file** (or merged into evaluate.R) — `model_likelihoods()` |
| `R/compute_likelihoods.R` | **New file** — wrapper `compute_likelihoods()` |
| `R/coverage.R` | Check for `likelihood_point_est` / `likelihood_mean` / `likelihood_sd` references |
| `R/clean.R` | Check for score column references |
| `R/report_likelihood.R` | Update for new column names; add `score_method` interpretation |
| `man/` | Regenerate all affected .Rd files |
| `tests/` | Update all tests for new column names and new functions |
| `inst/workflows/` | Update all six workflow scripts |
| `inst/TaxaLikely_supplemental_methods.md` | Update if column names appear |
| `CLAUDE.md` | Update function inventory, column interface tables, session notes |
| `NAMESPACE` | Update exports (add new, remove expand_consensus_candidates) |

### TaxaAssign
| File | Change |
|---|---|
| `R/compute_posterior.R` | Read `score_likelihood` / `score_likelihood_mean` / `score_likelihood_sd` |
| `R/assign_taxa_llm.R` | Major rewrite: accept `scored_hypotheses_df`; remove `.score_to_likelihood()`; update `unknown_species` → `unreferenced_family`; update column names |
| `R/expand_unreferenced.R` | Check for likelihood column references |
| `R/posterior_consensus.R` | Check for likelihood column references |
| `R/score_consensus.R` | Check for likelihood column references |
| `man/` | Regenerate affected .Rd files |
| `tests/` | Update all tests |
| `inst/workflows/` | Update workflow scripts |
| `CLAUDE.md` | Update interface tables and session notes |

---

## Implementation Order (dependency-aware)

### Phase 1 — Column rename foundation (no logic changes)
Goal: rename columns throughout without changing any computational logic.
Test: `devtools::check()` passes on all affected packages after each step.

1. **TaxaMatch**: rename `score` → `score_original` in output
   - Run `devtools::check()` on TaxaMatch
2. **TaxaLikely**: rename `likelihood_point_est` / `likelihood_mean` / `likelihood_sd`
   → `score_likelihood` / `score_likelihood_mean` / `score_likelihood_sd` throughout
   - Update `evaluate_likelihoods()`, `filter_top_hypotheses()`, `apply_coverage_constraints()`,
     `expand_consensus_candidates()`, `report_likelihood()`, all tests, all workflows
   - Run `devtools::check()` on TaxaLikely
   - Run `devtools::install()` on TaxaLikely
3. **TaxaAssign**: update `compute_posterior()` and `assign_taxa_llm()` for new column names
   - Run `devtools::check()` on TaxaAssign

**Sensitivity**: grep all R files in each package for `likelihood_point_est`, `likelihood_mean`,
`likelihood_sd`, and bare `score` (as a column name reference, e.g., `$score`, `"score"`,
`[[\"score\"]]`) before starting. Log any missed occurrences.

### Phase 2 — New TaxaLikely functions
Goal: implement the three-function pipeline. Resolve open decisions first.

1. Finalize function signatures for `unreferenced_candidates()`, `assign_scores()`,
   `assign_likelihoods()`, `compute_likelihoods()`
2. Write `unreferenced_candidates()` — structural, no model required
3. Write `assign_scores()` — handles all score_type values; writes `score_likelihood`
   and `score_method`
4. Write `assign_likelihoods()` — refactored bivariate normal from `.evaluate_one_query()`
5. Write `compute_likelihoods()` wrapper
6. Deprecate or remove `expand_consensus_candidates()`
7. Update `evaluate_likelihoods()` to delegate to new internals (or deprecate)
8. Run `devtools::check()` on TaxaLikely

### Phase 3 — TaxaAssign integration
1. Rewrite `assign_taxa_llm()` to accept `scored_hypotheses_df`
2. Replace `unknown_species` with `unreferenced_family` throughout
3. Add `score_method` column threading through `assign_taxa_llm()` and `compute_posterior()`
4. Run `devtools::check()` on TaxaAssign

### Phase 4 — Documentation and workflows
1. Update all workflow scripts (TaxaLikely inst/workflows/, TaxaAssign inst/workflows/)
2. Update CLAUDE.md files (TaxaLikely, TaxaAssign, TaxaMatch, ecosystem CLAUDE.md)
3. Update NAME_CHANGE_HISTORY.md
4. Run full `devtools::check()` on all packages
5. Run `devtools::install()` on all packages in dependency order

---

## Sensitive Areas / Likely Breakage Points

| Risk | Location | Mitigation |
|---|---|---|
| `score` column referenced by name in match object consumers | TaxaLikely evaluate.R, expand_consensus.R; TaxaAssign assign_taxa_llm.R | Grep before Phase 1 |
| `likelihood_point_est` referenced in coverage.R, clean.R, report_likelihood.R | TaxaLikely | Grep before Phase 1 |
| `filter_top_hypotheses()` — check if it uses likelihood columns | TaxaLikely evaluate.R | Read before Phase 1 |
| `apply_coverage_constraints()` — uses hypothesis_type and taxon_name | TaxaLikely coverage.R | Check for likelihood column refs |
| `expand_unreferenced_hypotheses()` — lives in TaxaAssign | TaxaAssign | Check for likelihood column refs |
| `posterior_consensus()` / `score_consensus()` | TaxaAssign | Check for likelihood column refs |
| Tests that create mock likelihood data frames with old column names | All packages | Update in Phase 1 |
| Workflow scripts that reference column names by string | inst/workflows/ | Update in Phase 4 |

---

## Grep Commands to Run Before Phase 1

```r
# In TaxaLikely project root:
grep -r "likelihood_point_est\|likelihood_mean\|likelihood_sd" R/ tests/ inst/
grep -r '"score"' R/ tests/ inst/
grep -r '\$score\b' R/ tests/ inst/

# In TaxaAssign project root:
grep -r "likelihood_point_est\|likelihood_mean\|likelihood_sd" R/ tests/ inst/
grep -r '"score"' R/ tests/ inst/

# In TaxaMatch project root:
grep -r '"score"' R/ tests/ inst/
grep -r '\$score\b' R/ tests/ inst/
```

---

## NAME_CHANGE_HISTORY entries to add (Session 99)

| Old name | New name | Package | Notes |
|---|---|---|---|
| `score` | `score_original` | TaxaMatch | Match object output column |
| `likelihood_point_est` | `score_likelihood` | TaxaLikely, TaxaAssign | Likelihood ratio point estimate |
| `likelihood_mean` | `score_likelihood_mean` | TaxaLikely, TaxaAssign | Monte Carlo mean |
| `likelihood_sd` | `score_likelihood_sd` | TaxaLikely, TaxaAssign | Monte Carlo SD |
| `expand_consensus_candidates()` | `unreferenced_candidates()` + `assign_scores()` + `model_likelihoods()` | TaxaLikely | Split into pipeline steps |
| `assign_likelihoods()` | `model_likelihoods()` | TaxaLikely | Renamed to clarify bivariate normal modeling step |
| `unknown_species` (hypothesis_type) | `"unreferenced_family"` | TaxaAssign | Standardized vocabulary |
| `evaluate_likelihoods()` | `compute_likelihoods()` | TaxaLikely | Old function deprecated or becomes wrapper |
