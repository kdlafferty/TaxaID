# CLAUDE.md -- TaxaFlag
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-27 (Session 89 — review_assignments data_type param)

---

## Package Purpose
Identifies and flags anomalous detections in taxonomic assignment results.
Correct identifications can still be ecologically meaningless due to:
- **Lab contamination** -- human DNA, reagent contaminants, index hopping
- **Field contamination** -- airborne DNA, handler artifacts during collection
- **Allochthonous detections** -- DNA/images/sounds transported from elsewhere
  (e.g., marine fish DNA carried by cormorant into freshwater stream)
- **Taxonomic scope violations** -- taxa outside the study's target group
  (e.g., plant DNA in a fish eDNA survey)

Operates on consensus data frames from TaxaAssign (or any data frame with
a taxon column). Appends categorical flag columns for user-driven filtering.

**Cross-modality:** Functions work for eDNA sequences, camera trap images,
and acoustic detections. Modality-specific logic lives in prompt text and
parameter defaults, not function signatures.

**Status: All core functions implemented and passing devtools::check() (0 errors, 0 warnings).**

---

## Dependency Chain

TaxaAssign -> **TaxaFlag** (post-assignment quality control)

TaxaFlag depends on:
- dplyr, jsonlite, stats (Imports)
- TaxaTools (Imports -- LLM provider functions for review_assignments, report_flags)

---

## Flag Column Convention

Data-driven flaggers (`flag_contaminant`, `flag_handler`) add a triplet:
- `flag_{type}` -- character: "likely" (valid detection) / "possible" (uncertain) / "unlikely" (probable artifact)
- `flag_{type}_score` -- numeric: interpretable ratio or confidence (0-1)
- `flag_{type}_reason` -- character: plain-English explanation

Consistent with TaxaHabitat's `spatial_flag` / `spatial_flag_reason` pattern.

`review_assignments()` adds 8 structured LLM assessment columns (see below).

---

## Function Inventory

| Function | File | Status | Description |
|----------|------|--------|-------------|
| `.compute_contaminant_scores()` | `R/flag_contaminant.R` | Written | Internal: proportion-based control comparison algorithm |
| `flag_contaminant()` | `R/flag_contaminant.R` | Written | Compare read proportions between field samples and controls; `contaminant_type` param selects lab vs field vs positive control |
| `flag_handler()` | `R/flag_handler.R` | Written | Temporal proximity to start/end of sampling period; placeholder for camera trap handler artifacts |
| `.parse_datetimes()` | `R/flag_handler.R` | Written | Internal: auto-detect datetime format |
| `review_assignments()` | `R/review_assignments.R` | Written | LLM expert review: habitat, geography, scope, contaminant, alternatives. Default `taxa_per_call = 15` to avoid response truncation. `data_type` param ("eDNA"/"acoustic"/"image") switches contaminant guidance in LLM prompt. |
| `.normalise_context()` | `R/review_assignments.R` | Written | Internal: normalise build_context() or named list to standard fields |
| `.build_review_prompt()` | `R/review_assignments.R` | Written | Internal: construct structured LLM prompt |
| `.parse_review_response()` | `R/review_assignments.R` | Written | Internal: parse + validate LLM JSON response; multi-strategy parser with truncated JSON recovery |
| `.recover_truncated_json()` | `R/review_assignments.R` | Written | Internal: salvage complete JSON objects from truncated LLM response |

**Dropped (Session 62):** `flag_allochthonous()` and `flag_taxonomic_scope()` -- absorbed
into `review_assignments()`. One LLM call covers habitat, geography, scope, contaminant
screening, and alternative suggestions more efficiently than separate functions.

**Dropped (Session 63):** `combine_flags()` and `flag_detections()` -- users should
filter on individual flag columns directly. A wrapper that guesses parameters is more
frustrating than helpful; workflow scripts are more transparent.

---

## flag_contaminant() Design

**Input:** Long-format data frame (one row per sample x taxon) with read counts.
**Output:** Per-taxon summary (one row per taxon), sorted by score.

**Key parameters:**
- `event_col` -- column identifying L1 collection events (default `"event_id"`)
- `control_samples` -- character vector of event IDs that are controls (blanks or positive controls)
- `sample_type_col` / `control_types` -- alternative: identify controls via a column
- `exclude_samples` -- remove samples from both control and field calculations
- `contaminant_type` -- controls output column names (`flag_{contaminant_type}`)
- `score_thresholds` -- numeric(2), default `c(0.5, 0.9)`

**Algorithm:** `.compute_contaminant_scores()`:
1. Compute within-sample proportions: `prop = n_reads / sum(n_reads)` per sample
2. Per taxon: `mean_prop_field`, `mean_prop_control`, `n_controls_present`
3. Score: `mean_prop_field / (mean_prop_field + mean_prop_control)` -- range [0, 1]
4. Taxa absent from controls -> score = 1.0

---

## flag_handler() Design

**Input:** Data frame with a datetime column and optionally a grouping column.
**Output:** Input data frame with 3 columns appended (per-row flags).

**Key parameters:**
- `datetime_col` -- auto-parsed via `.parse_datetimes()`
- `group_col` -- min/max computed per group (e.g., camera station)
- `interval_minutes` -- flag window from edges
- `handler_taxa` -- optional whitelist (e.g., "Homo sapiens")

**Score:** `min(minutes_to_start, minutes_to_end) / interval_minutes`, clamped [0, 1].

---

## review_assignments() Output Columns

| Column | Type | Values | What it captures |
|--------|------|--------|-----------------|
| `review_habitat` | character | expected / occasional / unlikely | Does this taxon live in this habitat? |
| `review_geography` | character | expected / occasional / unlikely | Is this taxon found in this region? |
| `review_scope` | character | in_scope / marginal / out_of_scope | Target group match (only if `target_group` supplied) |
| `review_contaminant` | character | unlikely / possible / likely | Common lab/field contaminant? |
| `review_alternatives` | character | comma-separated | Plausible alternatives at same rank (when taxon is implausible) |
| `review_lower_hypotheses` | character | comma-separated | Finer-rank taxa expected here (when consensus is coarse-ranked) |
| `review_confidence` | character | high / moderate / low | LLM's overall confidence |
| `review_comment` | character | free text | Anything structured fields don't capture |

**Key distinction:**
- `review_alternatives` = "you might have the wrong taxon" (implausible taxon, plausible relative)
- `review_lower_hypotheses` = "you have the right group, could narrow it down" (coarse consensus, likely species)

**Context input:** Accepts either `build_context()` output (data frame with `ecoregion`, `main_habitat`) or a simple named list (`list(geography = ..., habitat = ...)`).

---

## Workflow Scripts

| File | Purpose |
|------|---------|
| `inst/contaminant_workflow.R` | End-to-end: wide CSV -> pivot -> 3 flag_contaminant() calls (extraction, PCR, positive control) -> combined summary |
| `inst/review_assignments_workflow.R` | LLM review with test consensus data for Palmyra Atoll |

---

## Session Notes

**Session 60 (2026-04-28)**
- Package scaffold created (DESCRIPTION, NAMESPACE, CLAUDE.md, CITATION, tests, etc.)
- Design plan finalized: 6 exported functions + 2 internal helpers
- Key decisions: single `flag_contaminant()` with `contaminant_type` param;
  consensus_df must have `n_reads` pre-joined; `flag_allochthonous()` reuses
  TaxaAssign `build_context()` output

**Session 62 (2026-04-30)**
- `review_assignments()` designed: LLM expert review producing 8 structured columns
- `flag_allochthonous()` and `flag_taxonomic_scope()` dropped -- absorbed into
  `review_assignments()` for efficiency (one LLM call covers all dimensions)
- `review_alternatives` vs `review_lower_hypotheses` distinction clarified:
  alternatives = wrong taxon, plausible relative; lower = right group, finer resolution
- Implementation order: data-driven flaggers first (baseline for LLM validation),
  then `review_assignments()`, then wrapper

**Session 63 (2026-04-30)**
- `flag_contaminant()` + `.compute_contaminant_scores()` implemented and tested (17 tests)
  - `blank_samples` renamed to `control_samples` (supports positive controls)
  - Returns per-taxon summary, not joined to input
- `flag_handler()` + `.parse_datetimes()` implemented and tested (16 tests)
  - Placeholder function for camera trap handler artifacts
  - Auto-parses datetime formats; per-group min/max; linear scoring
- `review_assignments()` + `.build_review_prompt()` + `.parse_review_response()` +
  `.normalise_context()` implemented and tested (14 tests)
  - Accepts build_context() or named list for context
  - Batched LLM calls; graceful fallback on failure
  - Tested against real Palmyra Atoll data via workflow script
- `combine_flags()` dropped -- users should weight flags themselves
- `flag_detections()` dropped -- wrapper that guesses parameters is unhelpful
- Quality audit: removed unused `rlang` import; replaced `%||%` with inline
  null check; removed `VignetteBuilder` (no vignette yet); updated DESCRIPTION
  text; fixed non-ASCII em-dashes in prompt text
- devtools::check(): 0 errors, 0 warnings, 1 note (timestamp)

**Session 66 (2026-05-03)**
- `stop()` missing `sprintf()` in `review_assignments()` fixed
- TaxaTools moved from Suggests to Imports (used unconditionally)
- Vignette parameter names corrected (`data→df`, `count_col→reads_col`, `window_minutes→interval_minutes`)

**Session 74 (2026-05-15)**
- `review_assignments()` truncation fix: `taxa_per_call` default reduced from 30 to 15.
  With 8 JSON fields per taxon, 30 taxa generate ~10K char responses that exceed
  `call_anthropic_api()`'s 3000 `max_tokens` default, causing mid-JSON truncation.
  15 taxa stays well within limits (~1500-2250 tokens).
- `.recover_truncated_json()` added: when truncation occurs, walks backward through
  `}` positions to find the last complete JSON object, closes the array, and parses
  the recoverable portion. Recovered taxa get real reviews; only omitted taxa get NA defaults.
- `.parse_review_response()` multi-strategy parser: (1) strip markdown fences (lazy `.*?`
  regex), (2) direct parse, (3) bracket extraction, (4) truncated recovery.
- Fence-stripping regex fixed: greedy `(?s).*``` ` matched the LAST triple-backtick
  (consuming the entire response); corrected to lazy `(?s).*?``` ` to match the FIRST.
  Same PCRE footgun documented in ecosystem CLAUDE.md Session 33.
- TaxaWizard script continuation mode: `.find_existing_script()` scoped to today's date
  only; `.append_to_script()` inserts new steps before footer; handles both `total_steps`
  variable and hardcoded step counts. `is_continuation` flag propagated to parameterize prompt.
- TaxaWizard UI: CSS flex layout anchors messages near input box; Enter-to-send via JS keydown handler.
- 3 match-input snippets (`match_to_consensus_score/llm/bayes`) gain `sample_id`/`score` column rename block.

**Session 79 (2026-05-20)**
- `sample_col` param → `event_col` in `flag_contaminant()` (this param identifies L1 collection
  events, not L2 observations; default changed from `"sample_id"` to `"event_id"`)
- `sample_id` → `observation_id` in all L2 references across R source, tests, vignettes, inst/, README
- `event_col` documented in CLAUDE.md flag_contaminant() design section
- 126 tests passing (2 warnings — pre-existing)

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- TaxaTools moved from Suggests to Imports (used unconditionally by `report_flags()` and
  as default in `review_assignments()`).

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaFlag-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration. See TaxaID/CLAUDE.md for full log.

**Session 86 (2026-05-23)**
- `review_assignments()`: `llm_fn` fallback updated from `TaxaTools::call_anthropic_api` to
  `TaxaTools::call_api`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`.

**Session 89 (2026-05-27)**
- `review_assignments()`: `data_type` param added (`"eDNA"` default / `"acoustic"` / `"image"`). Controls contaminant guidance text in the LLM prompt: eDNA (common lab contaminants: Homo sapiens, Bos taurus, etc.), acoustic (human vocalizations + handler noise near recording equipment), image (handler presence during camera setup/teardown). Also switches the JSON example `comment` value to match the data type. Implemented in `.build_review_prompt()` via `switch(data_type, ...)`.
