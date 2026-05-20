# TaxaWizard Testing — Reentry Prompt

## Context
TaxaWizard is the conversational workflow designer for the TaxaID ecosystem. It uses a graph-based 3-phase engine (classify → path select → parameterize) to generate .R scripts from user descriptions. Session 73 fixed 5 snippets to clean species names before `create_taxon_names()`.

## What has been tested
- **Session 70:** Bayesian pipeline (match_df → priors → consensus) via viewer/browser modes. Found and fixed 8 snippet bugs (rank casing, consensus column names, debug subsetting, variable scoping, JSON parsing).
- **Session 73:** Bayesian pipeline end-to-end with real eDNA data. Found issues with: subspecies/hybrid names in match data (fixed via snippet cleaning), `finest_rank` scoping in `fetch_reference_sequences()` (fixed), habitat mismatch priors (fixed via min_phi + dark floor).

## What needs testing
1. **LLM pipeline path** (`match_df → consensus` via `run_llm_pipeline()`): Has this path been tested with `workflow_create()`? Does the generated script correctly set up `llm_fn`, handle `build_context()`, and pass parameters?

2. **Score-only path** (`match_df → consensus` via `score_consensus()`): Simplest path. Does the snippet produce a working script with correct `rank_thresholds`?

3. **Sequences → consensus** (full pipeline from DADA2/FASTA): Tests `seq_to_match` snippet + downstream. Requires BLAST — may need `blast_method = "remote"` guidance.

4. **Taxa → priors** (occurrence-based prior building): Tests `taxa_to_occ` → `occ_to_std` → `std_to_dist` → `dist_to_priors` path and the `taxa_to_priors_wrapper` shortcut. New parameters from Session 73 (`search_rank`, `max_coord_uncertainty`, `min_phi`) should be exposed.

5. **Reference QC paths**: `taxa → reference_df → reference_matrix → clean_refs` and `taxa → reference_df → reference_matrix → model_params`. Tests TaxaLikely snippets.

6. **Post-consensus paths**: `consensus → reviewed` (TaxaFlag `review_assignments()`), `consensus → flagged` (contaminant/handler flagging).

7. **Error recovery**: Run a generated script, introduce an error, test `workflow_fix()`.

8. **Edge cases**:
   - User starts with `occurrences` (already has GBIF data)
   - User starts with `consensus_df` (already has IDs, wants review)
   - User asks for something outside the graph (should get helpful "not possible" message)

## How to test
```r
library(TaxaWizard)
workflow_create()  # launches browser mode by default
```

Describe a workflow goal in natural language. Verify:
- Phase 1: Correct input/output type classification
- Phase 2: Sensible path recommendation with tradeoffs explained
- Phase 3: Correct parameter questions, then valid .R script generated
- Generated script: Sources and runs without errors (may need real data or checkpoint files)

## Known issues from Session 73
- `species_reference` parameter not automatically passed to `posterior_consensus()` in any snippet — genus-level monotypic assignments won't be downranked unless user adds it manually.
- Habitat mismatch can still cause modelled species to get dark-floor priors (by design, but users may find it surprising). The `min_phi` and dark floor fixes are in the installed packages but not yet documented in TaxaWizard's parameterize prompt.
