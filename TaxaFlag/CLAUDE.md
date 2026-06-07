# CLAUDE.md -- TaxaFlag
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-06-06 (Session 101 — unified flag vocabulary; column renames)

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

**Vocabulary design:** All columns use a consistent direction — higher value = worse for the taxon's credibility as a real detection.

**Data-driven risk columns** (`flag_contaminant`, `flag_handler`) add a triplet:
- `{type}_risk` -- character: `"high"` (probable artifact) / `"moderate"` (uncertain) / `"low"` (likely genuine)
- `{type}_score` -- numeric: interpretable ratio or confidence (0–1; higher = more likely genuine)
- `{type}_reason` -- character: plain-English explanation

**LLM plausibility columns** (`review_assignments`):
- `habitat_plausibility`, `geographic_plausibility`, `scope_plausibility` -- `"likely"` / `"possible"` / `"unlikely"` (higher = more plausible genuine detection)
- `contamination_risk` -- `"high"` / `"moderate"` / `"low"` (higher = more contamination risk)

Note: `{type}_score` (numeric) is NOT the same direction as `{type}_risk` (character). Score 1.0 = low risk (real detection); score 0.0 = high risk (contaminant). This asymmetry is intentional: scores are intermediate outputs for threshold-tuning; risk labels are the user-facing result.

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
- `contaminant_type` -- controls output column names (`{contaminant_type}_risk`, `{contaminant_type}_score`, `{contaminant_type}_reason`)
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
| `habitat_plausibility` | character | likely / possible / unlikely | Does this taxon live in this habitat? |
| `geographic_plausibility` | character | likely / possible / unlikely | Is this taxon found in this region? |
| `scope_plausibility` | character | likely / possible / unlikely | Target group match (only if `target_group` supplied) |
| `contamination_risk` | character | low / moderate / high | Common lab/field contaminant? |
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

Sessions 60–74 archived in ecosystem_docs/session_notes/TaxaFlag_sessions.md.

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

**Session 101 (2026-06-06): Unified flag vocabulary**
- Renamed `review_assignments()` output columns: `review_habitat` → `habitat_plausibility`, `review_geography` → `geographic_plausibility`, `review_scope` → `scope_plausibility`, `review_contaminant` → `contamination_risk`.
- Updated values: plausibility columns use `"likely"/"possible"/"unlikely"` (positive = plausible genuine detection); `contamination_risk` uses `"low"/"moderate"/"high"` (positive = more risk).
- Renamed `flag_contaminant()` output columns: `flag_{type}` → `{type}_risk`, `flag_{type}_score` → `{type}_score`, `flag_{type}_reason` → `{type}_reason`. Values changed: `"likely"` → `"low"`, `"possible"` → `"moderate"`, `"unlikely"` → `"high"` (direction flipped — old "likely" meant real detection; new "low" risk means real detection; both mean same thing).
- Updated Flag Column Convention in CLAUDE.md; updated workflows, tests, and prompts throughout.
