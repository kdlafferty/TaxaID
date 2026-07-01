# CLAUDE.md — TaxaHabitat
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-01 (Session 123 — Layer-1 workflow script added: inst/workflows/assign_habitat_workflow.R)

---

## Package Purpose
Assigns habitat classifications to taxonomic occurrence records using LLM prompts
and performs spatial quality control. Receives occurrence data from TaxaFetch and
produces habitat-annotated, spatially screened records for input to TaxaExpect.
Part of the TaxaID ecosystem.

**Status: All functions passing devtools::check() (0 errors, 0 warnings, 0 notes).**

---

## Dependency Chain
TaxaTools → TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign/TaxaMatch

TaxaHabitat depends on TaxaTools for LLM provider functions
(`call_anthropic_api`, `call_gemini_api`, `call_openai_api`, `call_ollama_api`,
`prompt_api`, `prompt_manual`, `read_llm_response`).

---

## Function Inventory

| Function | File | Status | Description |
|---|---|---|---|
| `build_habitat_prompt()` | R/build_habitat_prompt.R | Complete | Build habitat assignment prompt object. `geographic_context` param (Session 46) adds geographic hint + `ecoregion_best_guess` column. |
| `parse_hierarchical_habitat_response()` | R/parse_habitat_response.R | Complete | Parse LLM CSV response into habitat weights table. Protects `ecoregion_best_guess` from numeric detection. |
| `assign_habitat_biological()` | R/assign_habitat_biological.R | Complete | Join habitat weights to occurrence data (per-point consensus) |
| `consensus_habitat()` | R/assign_habitat_biological.R | Complete | Assemblage-level consensus habitat from per-species weights; modal ecoregion extraction. Returns one-row data frame. (Session 46) |
| `flag_habitat_inconsistencies()` | R/flag_habitat_inconsistencies.R | Complete | Flag occurrences inconsistent with habitat |
| `review_spatial_flags()` | R/review_spatial_flags.R | Complete | Interactive Shiny review of spatial flags |
| (plot helpers) | R/utils_plot.R | Complete | Internal plotting utilities |
| `.detect_habitat_cols()` | R/assign_habitat_biological.R | Internal | Shared habitat column detection logic used by `assign_habitat_biological()` and `consensus_habitat()` |

---

## LLM Workflow

The full three-path habitat assignment workflow:
1. **Path 1 (API auto):** `build_habitat_prompt()` → `prompt_api()` [TaxaTools] → `parse_hierarchical_habitat_response()`
2. **Path 2 (manual):** `build_habitat_prompt()` → `prompt_manual()` [TaxaTools] → `read_llm_response()` [TaxaTools] → `parse_hierarchical_habitat_response()`
3. **Path 3 (inline):** build prompt manually → paste response as string → `parse_hierarchical_habitat_response()`

Provider functions (`call_anthropic_api`, `call_gemini_api`, etc.) live in TaxaTools.

---

## Key Design Notes
- `parse_hierarchical_habitat_response()` returns WIDE WEIGHTED output: one row
  per species, one numeric column per habitat in the scheme (0-1 weights), plus
  `Other_weight`, `habitat_best_guess`, and `Habitat` (argmax convenience column).
- The median-across-references approach for likelihood is intentional in TaxaMatch
  (not relevant here, but habitat weights follow a similar philosophy).
- `build_habitat_prompt()` supports both IUCN and custom habitat schemes.
  The `$habitat_cols` element of the returned prompt object drives column detection
  in `parse_hierarchical_habitat_response()`.
- `build_habitat_prompt(geographic_context = "Southern California")` adds a
  `GEOGRAPHIC CONTEXT:` block to the prompt and requests an `ecoregion_best_guess`
  column. The column is stored in the returned S3 object as `$geographic_context`.
- `consensus_habitat()` computes assemblage-level consensus from per-species habitat
  weights (equal-weight sum → argmax with threshold). Returns `main_habitat`,
  `ecoregion` (modal `ecoregion_best_guess`), and `habitat_best_guess` in a one-row
  data frame. `attr(result, "habitat_proportions")` has the full proportion vector.
- `%||%` is defined internally in `parse_habitat_response.R` and is available
  throughout the package namespace.

---

## Session 28 Notes (2026-03-26)
- Package created during TaxaFetch → TaxaTools/TaxaHabitat split
- All habitat files copied from TaxaFetch/R:
  - build_habitat_prompt.R, assign_habitat_biological.R,
    flag_habitat_inconsistencies.R, review_spatial_flags.R, utils_plot.R
- screen_spatial_formula.R moved to TaxaExpect (Session 29, 2026-03-27) --
  belongs with biodiversity modelling, not habitat assignment
- parse_habitat_response.R: habitat parser extracted from TaxaFetch/R/llm_api_utils.R
- LLM provider functions moved to TaxaTools/R/llm_api_utils.R
- TODO: ~~Run devtools::document() and devtools::check() on this package~~ — completed Session 46
- TODO: ~~Update @importFrom tags in habitat files to use TaxaTools:: for LLM functions~~ — completed Session 46

**Session 37 (2026-03-30)**
- `Main_Habitat` column → `main_habitat` (snake_case consistency; 145 occurrences across 20 files).
- `ctx$habitat` → `ctx$main_habitat` recognised context field in TaxaAssign.

**Session 46 (2026-04-03)**
- `geographic_context` param added to `build_habitat_prompt()`: optional geographic hint;
  adds `GEOGRAPHIC CONTEXT:` block to prompt and requests `ecoregion_best_guess` column.
- `consensus_habitat()` added to `R/assign_habitat_biological.R`: assemblage-level consensus
  from per-species weights; modal ecoregion extraction. `.detect_habitat_cols()` internal
  shared with `assign_habitat_biological()`.
- `ecoregion_best_guess` protected from numeric detection in `parse_hierarchical_habitat_response()`.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 57 (2026-04-15)**
- Duplicate `%||%` definition removed from `R/parse_habitat_response.R`; now imported from
  TaxaTools via `@importFrom TaxaTools %||%`.
- Empty `utils::globalVariables(character(0))` removed.

**Session 59 (2026-04-17)**
- `test-assign_habitat_biological.R` added (new test file, expanded coverage).
- Vignette added. `knitr` + `rmarkdown` added to Suggests; `VignetteBuilder: knitr` in DESCRIPTION.
- `.Rbuildignore` updated (`.Rhistory`, `.DS_Store`).
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 65 (2026-05-02)**
- `report_habitat()` added: generates `report_section` summarizing habitat assignment
  (scheme, n_taxa, dominant habitat). For `TaxaTools::assemble_report()`.

**Session 66 (2026-05-03)**
- Dead code cleanup; stale `@seealso` refs updated.

**Session 67 (2026-05-04)**
- `llm_fn` default in `build_habitat_prompt()` updated to
  `getOption("TaxaID.llm_fn", call_anthropic_api)`.

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` ecosystem rename: TaxaHabitat does not use this column;
  no source changes required.

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 81 (2026-05-21)**
- Methods sections added to README: habitat weights, site assignment, spatial QAQC.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- `llm_fn` defaults updated across all LLM-calling functions to
  `getOption("TaxaID.llm_fn", call_anthropic_api)`.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaHabitat-specific code changes. Session 85: README expanded with spatial QAQC
  paragraph (user edit committed). Ecosystem: `call_api()` dispatcher (TaxaTools), WERC
  review integration.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/assign_habitat_workflow.R` added — teaching-oriented, fully namespaced,
  continues directly from TaxaFetch's tutorial checkpoint. Two classification steps on the
  SAME mechanism: Step A (always runs) standard habitat classification via
  `build_habitat_prompt()` → `TaxaTools::prompt_api()` → `parse_hierarchical_habitat_response()`
  → `assign_habitat_biological()`; Step B (optional, `NEEDS_SAMPLING_GROUP` toggle) reuses the
  identical chain with a sampling-group scheme instead of a habitat scheme — confirmed to need
  **zero package changes** (weight-matrix math is scheme-agnostic; `realm = NA` is a valid
  scheme value; see `ecosystem_docs/LAYER1_WORKFLOWS.md` for the full generalization
  investigation). Spatial QAQC tail (`flag_habitat_inconsistencies()`) preserved;
  `review_spatial_flags()` documented as interactive-only, not run via `source()`.
- Live-tested with a real Anthropic LLM call and real GEBCO bathymetry download. One real bug
  fixed: Step B's `assign_habitat_biological()` call would have silently overwritten Step A's
  `main_habitat` column if run on the same object (the function unconditionally drops
  pre-existing `main_habitat`/`habitat_best_guess` from its `data` argument) — fixed by running
  Step B against the original `all_occurrences` independently and joining only its renamed
  output columns back on. Full record in `ecosystem_docs/LAYER1_WORKFLOWS.md`.
