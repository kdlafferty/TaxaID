# CLAUDE.md -- TaxaFlag
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-11 (Session 151, once more -- ecosystem soundness-review item 16
# (flag_handler()'s edge_proximity_score), the LAST of the review's 16 H-priority items,
# fixed: new optional station_metadata param anchors group edges on real per-station
# deploy/retrieve timestamps instead of the detection data's own min/max. The core flaw:
# without real deployment metadata, the very first and last GENUINE wildlife detection at
# a station is always exactly at the data-derived edge and scores maximally suspect,
# purely as an artifact of how "edge" is defined -- not because a handler was ever
# present. station_metadata mirrors the "external attribute lookup table keyed by a
# sample/event identifier" pattern already established in this ecosystem
# (TaxaMatch::join_event_site_metadata(), the BLANKS_MARCH/BLANKS_AUG convention): one row
# per group_col value with deploy_time/retrieve_time (column names configurable via
# deploy_col/retrieve_col). A group present in the data but missing from
# station_metadata (or with an unparseable timestamp) falls back to the data-derived
# min/max for that group only, with an explicit warning() naming it -- a real weakening
# of that group's flag, not a silent one. New edge_anchor_source output column records,
# per row, whether "station_metadata" or "detection_data_fallback" was used. Fully
# additive/backward compatible: station_metadata defaults NULL, and all 36 pre-existing
# tests pass completely unchanged. The vignette (quality-flagging.Rmd) -- still this
# function's only real call site anywhere in the monorepo -- updated to demonstrate the
# new param. 12 new tests. devtools::test() 181/181 (up from 169), devtools::check()
# clean. This closes out the full 16-item H-priority soundness-review walk-through: 16 of
# 16 addressed (fixed/mitigated/reclassified/flagged-by-design -- see
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md for the final per-item status;
# "addressed" does not mean every caveat is resolved, several items remain CONDITIONAL
# with explicitly documented open gaps).
# Previous update, same day (Session 151 -- ecosystem soundness-review item 15
# (flag_contaminant()'s contaminant_score) fixed: depth-weighted rates + Empirical Bayes
# shrinkage replace the old unweighted-mean-of-proportions formula with its hard 0.0/1.0
# edge cases. field_rate/control_rate now = sum(taxon reads in group)/sum(total reads in
# that group) -- a proportion from 500,000 reads counts far more than one from 50, fixing
# "read-depth-unweighted." The raw ratio field_rate/(field_rate+control_rate) is then
# shrunk toward 0.5 with weight n_present/(n_present+prior_weight) (default prior_weight=2,
# n_present = total samples across both groups where the taxon was detected) -- a taxon
# absent from controls no longer gets an automatic exact 1.0 when only a couple of controls
# exist. Design bug found and fixed mid-implementation, not just in code review: an earlier
# version shrunk field_rate/control_rate individually toward the taxon's own pooled
# (field+control) rate, which let a taxon's large field read volume leak into its
# control-side prior, systematically understating genuinely clean taxa's scores whenever
# field sequencing depth dominated control depth (the common real case: many field samples,
# few small blanks) -- caught only by running the actual test suite against the mock data
# and seeing TaxonA (a clean, field-only taxon) score "moderate" instead of "low." Fixed by
# shrinking the FINAL ratio toward 0.5 by sample-count replication instead, which keeps the
# two groups' magnitudes fully independent. Also fixed: roxygen no longer calls the score a
# "probability" -- explicit new prose states it's a ranked screening statistic. New
# mean_prop_field/mean_prop_control (unweighted, informational only) vs. field_rate/
# control_rate (depth-weighted, drives the score) distinction throughout docs/reason
# strings. New prior_weight param (default 2, 0 disables shrinkage). Tests updated: two
# tests asserting exact 1.0/0.0 for absent-from-one-side taxa now assert the shrunk,
# non-exact values instead (matching item 11/12's "tests exercising old exact math now pin
# that value explicitly" pattern); new tests cover prior_weight=0 (exact un-shrunk
# boundary), prior_weight sensitivity, and input validation. devtools::test() 169/169,
# devtools::check() clean. See ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md's
# item 15 for the full record.
# Previous update, 2026-07-10 (Session 149 -- add_posthoc_assessment() gains domestic_taxa/
# domestic_prior_source params, implementing the deferred domestic-species-floor design note
# ([[project_taxaflag_domestic_species_floor_note]] in project memory) at the user's direction
# during the ecosystem statistical soundness review walk-through. A strong-likelihood call to a
# user-specified domestic/synanthropic taxon that lands in tier2/tier3_undetected purely because
# GBIF/iNat under-index captive organisms is now re-labelled "domestic_prior_caveat" instead of
# "unexpected"/"unprecedented", so a reviewer sees "trust the ID, question the rarity" rather
# than a generic low-plausibility flag. domestic_taxa defaults to NULL (feature off, matching
# flag_handler()'s handler_taxa convention -- no built-in species list, since "domestic" is
# study-system-specific). domestic_prior_source = "wild" (default) vs "augmented" gives an
# explicit opt-out for pipelines that already augment occurrence data with known local domestic
# presence (the companion prior-side fix: TaxaExpect::generate_undetected_diversity() and
# TaxaAssign::join_priors() both gained a documentation-only note recommending exactly that
# augmentation, rather than TaxaID inventing a fix on the prior side). Backward compatible
# (new params both optional, no behavior change when domestic_taxa is not supplied). 7 new
# tests added to test-add_posthoc_assessment.R (33 test_that blocks total in that file);
# devtools::test() 159/159 passing, 0 failures; devtools::check() 0 errors/0 warnings/1
# pre-existing NOTE (clock-check artifact, same as
# other packages). See this file's own Session 149 note below for the full record, and
# ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md for the review row this resolves.

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

Note: `{type}_score` (numeric) is NOT the same direction as `{type}_risk` (character). Score near 1.0 = low risk (real detection); score near 0.0 = high risk (contaminant). This asymmetry is intentional: scores are intermediate outputs for threshold-tuning; risk labels are the user-facing result. (`flag_contaminant()`'s score no longer reaches an exact 0.0/1.0 since Session 151's shrinkage fix -- see below.)

`review_assignments()` adds 8 structured LLM assessment columns (see below).

---

## Function Inventory

| Function | File | Status | Description |
|----------|------|--------|-------------|
| `.compute_contaminant_scores()` | `R/flag_contaminant.R` | Written | Internal: proportion-based control comparison algorithm |
| `flag_contaminant()` | `R/flag_contaminant.R` | Written | Compare read proportions between field samples and controls; `contaminant_type` param selects lab vs field vs positive control. **Session 151**: depth-weighted rates + Empirical Bayes shrinkage (`prior_weight`, default `2`) replace the old unweighted-mean/hard-0-1 formula; score documented as a ranked screening statistic, not a probability. |
| `flag_handler()` | `R/flag_handler.R` | Written | Temporal proximity to start/end of sampling period; placeholder for camera trap handler artifacts. **Session 151**: optional `station_metadata` param anchors edges on real deploy/retrieve timestamps instead of the data's own min/max (opt-in, backward compatible; see "flag_handler() Design" below). |
| `.parse_datetimes()` | `R/flag_handler.R` | Written | Internal: auto-detect datetime format |
| `review_assignments()` | `R/review_assignments.R` | Written | LLM expert review: habitat, geography, scope, contaminant, alternatives. Default `taxa_per_call = 15` to avoid response truncation. `data_type` param ("eDNA"/"acoustic"/"image") switches contaminant guidance in LLM prompt. |
| `.normalise_context()` | `R/review_assignments.R` | Written | Internal: normalise build_context() or named list to standard fields |
| `.build_review_prompt()` | `R/review_assignments.R` | Written | Internal: construct structured LLM prompt |
| `.parse_review_response()` | `R/review_assignments.R` | Written | Internal: parse + validate LLM JSON response; multi-strategy parser with truncated JSON recovery |
| `.recover_truncated_json()` | `R/review_assignments.R` | Written | Internal: salvage complete JSON objects from truncated LLM response |

| `add_posthoc_assessment()` | `R/add_posthoc_assessment.R` | Written | Single-column `posthoc_assessment` summary combining sequence-match evidence (`winner_likelihood`) and prior establishment tier. Eight categories: `"sensible"`, `"limited_evidence"`, `"unexpected"`, `"unprecedented"`, `"suspect"`, `"vague_rank"`, `"modeled"`, and (Session 149) `"domestic_prior_caveat"` -- a strong-likelihood call to a user-specified `domestic_taxa` name that landed in tier2/tier3 purely from GBIF/iNat's under-indexing of captive organisms, not genuine rarity. Requires `tiers` data frame (from `priors_combined`). Threshold: `winner_likelihood >= 0.5` = sequence-supported. `domestic_taxa = NULL` (default, feature off) / `domestic_prior_source = "wild"` (default) vs `"augmented"` (opt-out when priors already account for domestic species). |

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
- `prior_weight` -- numeric, default `2` (**Session 151**). Shrinkage strength for the
  final ratio toward 0.5; `0` disables shrinkage.

**Algorithm:** `.compute_contaminant_scores()` (**Session 151**, ecosystem soundness-review
item 15 -- see that function's roxygen "Depth-weighting and shrinkage" section for the full
real-data motivation and the design bug found and fixed mid-implementation):
1. Depth-weighted rate per group: `field_rate`/`control_rate` = `sum(taxon reads in group) /
   sum(total reads across samples in that group)` -- a proportion from 500,000 reads now
   counts far more than one from 50. (The old unweighted per-sample-proportion mean is
   still computed as `mean_prop_field`/`mean_prop_control` for reference, but no longer
   drives the score.)
2. Raw ratio: `field_rate / (field_rate + control_rate)`.
3. Shrunk toward 0.5 (maximally uncertain) with weight `n_present / (n_present +
   prior_weight)`, where `n_present` = total samples (field + control combined) in which
   the taxon was detected -- same Empirical Bayes form used throughout this ecosystem
   (e.g. `TaxaLikely::train_likelihood_model()`'s per-species shrinkage). Applied to the
   FINAL ratio, not to `field_rate`/`control_rate` individually toward a shared reference
   rate -- an earlier design shrunk each rate toward the taxon's own pooled (field+control)
   rate, which let a taxon's own (usually much larger) field read volume leak into its
   control-side prior and systematically understated genuinely clean taxa's scores whenever
   field depth dominated control depth. Caught by actually running the test suite, not by
   review alone.
4. Taxa absent from controls no longer get an automatic exact 1.0 -- with few controls,
   real absence is still real evidence, but shrinkage keeps the score below 1.0 in
   proportion to how little total replication supports it.
Score is documented as a ranked screening statistic, not a calibrated probability
(the roxygen previously called it one).

---

## flag_handler() Design

**Input:** Data frame with a datetime column and optionally a grouping column.
**Output:** Input data frame with 4 columns appended (per-row flags; **Session 151** adds
`edge_anchor_source`).

**Key parameters:**
- `datetime_col` -- auto-parsed via `.parse_datetimes()`
- `group_col` -- min/max computed per group (e.g., camera station)
- `interval_minutes` -- flag window from edges
- `handler_taxa` -- optional whitelist (e.g., "Homo sapiens")
- `station_metadata` / `deploy_col` / `retrieve_col` -- **Session 151**, ecosystem
  soundness-review item 16. Optional data frame, one row per `group_col` value, with real
  deploy/retrieve timestamps -- the same "external attribute lookup table keyed by a
  sample/event identifier" pattern already used elsewhere in this ecosystem (e.g.
  `TaxaMatch::join_event_site_metadata()`, the `BLANKS_MARCH`/`BLANKS_AUG` convention).
  When supplied, anchors group edges on the REAL deployment window instead of the
  data's own detection min/max -- fixes the core flaw the review flagged: without this,
  the very first and last genuine wildlife detection at a station is always scored
  maximally suspect, purely because the edge is defined by the data itself, not because a
  handler was ever actually present. A group missing from `station_metadata` (or with an
  unparseable timestamp) falls back to the data-derived min/max for that group only, with
  a `warning()` naming it. Fully backward compatible -- default `NULL`, no behavior change
  for existing callers; every existing test (36) passes unchanged.

**Score:** `min(minutes_to_start, minutes_to_end) / interval_minutes`, clamped [0, 1],
computed against `group_min`/`group_max` -- real deploy/retrieve times when
`station_metadata` covers that group, data-derived min/max otherwise (see
`edge_anchor_source`).

**Still genuinely unfixed (Session 151, honestly recorded, not solved):** when
`station_metadata` is NOT supplied (still the default, and the only mode any real caller
has ever used -- see below), `handler_taxa` remains the sole real protection, exactly as
before this session; the structural bias itself is only fixed when a user actually has and
supplies a real deployment log. No live caller in the monorepo does yet -- `flag_handler()`
still has only one real call site anywhere: `vignettes/quality-flagging.Rmd`'s own example
(now updated to demonstrate `station_metadata`, Session 151). This was the lowest-priority
of the review's 16 H-priority items for exactly this reason (its own row: "no live caller
found yet, which is the only thing keeping this from being worse").

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

## Test Coverage

| File | Functions covered | Notes |
|---|---|---|
| test-flag_contaminant.R | `flag_contaminant()` | Fully offline; covers all risk levels, custom thresholds, positive controls; uses Session 101 vocabulary (low/moderate/high) |
| test-flag_handler.R | `flag_handler()` | Fully offline; covers edge scoring, handler_taxa filtering |
| test-review_assignments.R | `review_assignments()` | LLM mocked; covers all 8 output columns, partial response recovery, Session 101 column names/values |
| test-report_flags.R | `report_flags()` | Fully offline |
| test-add_posthoc_assessment.R | `add_posthoc_assessment()` | Fully offline; 33 tests; covers all 8 categories (incl. Session 149's `domestic_prior_caveat`), tier3, boundary threshold, custom columns, NA handling, validation; includes NA-rank bug fix (NA rank → vague_rank) |

---

## Session Notes

**Session 149 (2026-07-10): add_posthoc_assessment() domestic-species caveat**

Third item on the ecosystem statistical soundness review's H-priority walk-through
(`ecosystem_docs/STATISTICAL_COMPONENT_SOUNDNESS_REVIEW.md`) was
`TaxaAssign::join_priors()`'s dark-diversity floor treating domestic/synanthropic species
as exchangeable with genuinely unmodelled wild species -- the deferred design note from
[[project_taxaflag_domestic_species_floor_note]] (single-observation-pipeline work,
2026-07-03), never implemented. The user resolved where this belongs across two
functions rather than one: (1) priors -- a user who knows their study includes domestic
species should augment their occurrence data before training, and TaxaID's job is just
to document that clearly (a note is sufficient; not a code fix); (2) likelihoods --
iNaturalist image recognition and NCBI BLAST already handle domestic-species
classification fine, so the likelihood side needs no change; (3) the one thing worth
building is a small, narrow flag in TaxaFlag for the specific *contrast* -- a strong
likelihood for a domestic species next to a low prior, when that prior came from an
unaugmented wild-species database.

**Implementation:** `add_posthoc_assessment()` gains two new optional params:
- `domestic_taxa = NULL` -- character vector of taxon names the caller considers
  domestic/synanthropic for their study system. No built-in default list (matches
  `flag_handler()`'s `handler_taxa = NULL` convention) -- what counts as "domestic" is
  study-system-specific, so a curated list baked into the package would be either
  incomplete or presumptuous.
- `domestic_prior_source = c("wild", "augmented")` -- default `"wild"`. When a row's
  `consensus_taxon` is in `domestic_taxa` AND its likelihood is above
  `likelihood_threshold` AND it landed in the tier2/tier3_undetected branch (which would
  otherwise emit `"unexpected"`/`"unprecedented"`), the assessment is re-labelled
  `"domestic_prior_caveat"` instead -- signalling "trust the ID, question the rarity"
  rather than a generic low-plausibility flag. Passing `domestic_prior_source =
  "augmented"` disables this entirely, for pipelines that already incorporated known
  local domestic presence into their priors (the low tier is then genuinely
  informative, not a database artifact).

Deliberately narrow: only fires on the strong-likelihood + low-tier combination (a
low-likelihood domestic-species call stays `"suspect"`, correctly -- the caveat is about
the *prior*, not the identification), never invents or elevates a prior itself, and is
opt-in (`NULL` default, zero behavior change for existing callers).

**Companion prior-side documentation fix** (no code change, per the user's steer that a
note is sufficient there): `TaxaExpect::generate_undetected_diversity()` gained a new
`@section Domestic/synanthropic species` explaining the root cause (GBIF/iNat under-index
captive organisms) at the actual point where the floor value is computed, and recommending
occurrence-data augmentation before training as the fix; `TaxaAssign::join_priors()`'s
"Dark diversity fallback" section cross-references it. Both are pure roxygen additions --
`devtools::test()` unchanged (TaxaExpect 383/383, TaxaAssign 544/544), `devtools::check()`
clean on both.

7 new tests added to `test-add_posthoc_assessment.R` covering: default-off behavior,
tier2 and tier3_undetected re-labelling, the low-likelihood non-re-labelling case, no
effect on non-domestic taxa, the `"augmented"` opt-out, and input validation.
`devtools::test()`: 159/159 passing, 0 failures. `devtools::check()`: 0 errors, 0
warnings, 1 pre-existing NOTE (clock-check artifact, unrelated).

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

**Session 104 (2026-06-08): add_posthoc_assessment() + NA-rank bug fix**
- `add_posthoc_assessment()` added: single categorical column `posthoc_assessment` combining tier × likelihood into 7 categories (`sensible`, `limited_evidence`, `unexpected`, `suspect`, `unprecedented`, `vague_rank`, `modeled`). Replaces rejected `flag_prior_mismatch()` design.
- Bug fix: `vague_rank` mask was `!is.na(rank) & rank != finest_rank`; NA rank fell through to active path, getting treated as tier2 → "suspect". Fixed to `is.na(rank) | rank != finest_rank` so NA-rank rows correctly receive "vague_rank".
- `flag_prior_mismatch.R` and associated man/tests deleted.
- PtConceptionWorkflow_12S.R and _18S.R updated to use `add_posthoc_assessment()`.

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/flag_detections_workflow.R` added — the FINAL package in the tutorial
  chain (TaxaFetch → TaxaHabitat → TaxaExpect → TaxaAssign → TaxaFlag). Unlike the four
  upstream scripts, both live steps run on 100% real continuity data with no synthetic
  bootstrapping: `review_assignments()` reviews TaxaAssign's real `taxaassign_consensus`
  (irreducible candidate sets via `plausible_taxa_col`), and `add_posthoc_assessment()` uses
  the real `taxaexpect_priors` directly as `tiers` (it only needs `taxon_name` + `model_tier`,
  both already present). `flag_contaminant()` is documented with its full signature and
  algorithm but not run live — it needs lab read-count data (sample × taxon, with blanks) that
  a GBIF-occurrence-based tutorial chain has no honest way to fabricate.
- Live-tested with a real Anthropic LLM call as part of a full 5-package chain (0 errors,
  sensible output — see `ecosystem_docs/LAYER1_WORKFLOWS.md`). One real bug fixed:
  `review_assignments(irreducible_only = TRUE)` hard-errors if zero rows qualify as
  irreducible, which is the *expected* outcome (not bad luck) for TaxaAssign's small
  synthetic species pool — fixed with an adaptive fallback to `irreducible_only = FALSE`.
- Also surfaced (and documented in `TaxaID/CLAUDE.md`'s Known R Footguns): `review_assignments()`
  shares the same `.resolve_llm_fn()` default-degrades-silently issue as TaxaAssign's LLM
  pathway — must pass `llm_fn` explicitly under this ecosystem's fully-namespaced calling style.
