# CLAUDE.md -- TaxaWizard (formerly TaxaWorkflow)
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-24, continued (Sonnet 5 -- graph EXPANSION, direct follow-up to the
# metadata-drift sync pass below: the user asked for the 5 flagged-but-not-fixed capabilities
# to actually be wired into workflow_graph.json as new nodes/edges, not just documented as a
# gap. New node: site_table (per-observation spatial_group_id table). New edges:
# match_to_site_table (match_df -> site_table, build_site_table()+group_observations_by_bbox());
# taxa_to_occ_checked (taxa -> occurrences alternative with check_geographic_outliers());
# dist_to_priors_by_group (distributions -> priors alternative, train_biodiversity_model_by_group()
# for sampling_group_col-style detection-PROCESS grouping -- deliberately renamed from an
# initial "dist_to_priors_multisite" draft after realizing mid-implementation that
# sampling_group_col (detection-method grouping, e.g. fish vs birds vs phytoplankton) and
# site_table's spatial_group_id (physical-site grouping) are two INDEPENDENT axes, not the
# same mechanism -- conflating them would have produced a working-looking but conceptually
# wrong edge); lik_prior_to_post_multisite (likelihoods+priors+site_table -> posteriors,
# join_priors()'s multi-site data-frame `site` path + combine_multisite_priors() +
# compute_posterior() -- the specific combine_multisite_priors() wiring the user named
# directly). Existing edges extended in place (snippet + functions list, no topology change):
# dist_to_priors and dist_to_priors_by_group both gain an optional generate_domestic_food_priors()
# step (domestic/commensal-animal + food-species priors, gated by a boolean placeholder);
# occ_to_std gains a flag_institution_candidates() classification step (gated on
# institution_flag being present -- silently skipped otherwise); taxa_to_priors_wrapper and
# match_to_consensus_bayes both gain a description caveat that neither wrapper covers
# domestic-food-priors / multi-site combination (build_priors()/run_bayesian_pipeline() were
# checked directly and confirmed NOT to call generate_domestic_food_priors()/
# combine_multisite_priors() internally). A real, substantial pre-existing metadata-drift bug
# was found and fixed along the way (not part of the plan, found while writing correct docs
# for the new multi-site join_priors() call): metadata/TaxaAssign.json's join_priors entry
# still described a completely different, non-existent signature
# (likelihoods_df/priors_df/grid_id/main_habitat as flat top-level required args) -- the real
# function takes likelihoods/taxaexpect_priors/site (site being a list OR a multi-site data
# frame, with grid_id/main_habitat living INSIDE it) -- rewritten to match reality. New
# metadata entries added: TaxaMatch.json (build_site_table, group_observations_by_bbox,
# assign_spatial_group, join_event_site_metadata), TaxaExpect.json (prepare_model_dataframe,
# train_biodiversity_model_by_group, generate_domestic_food_priors -- prepare_model_dataframe
# had NO entry at all before this session despite being called in the pre-existing
# dist_to_priors edge, a separate pre-existing gap left as-is beyond adding this one),
# TaxaAssign.json (combine_multisite_priors), TaxaFetch.json (check_geographic_outliers),
# TaxaHabitat.json (flag_institution_candidates). Live path-computation smoke test confirmed
# every new node/edge is actually reachable (e.g. `sequences -> posteriors` now yields 30
# paths, up from 6, spanning both the single-site and multi-site lik_prior_to_post variants
# and both priors-building strategies) -- not just JSON-valid but graph-reachable. One
# pre-existing test (test-graph.R's "multi-input edges produce full Bayesian path") needed a
# one-line update to recognize dist_to_priors_by_group as a valid priors source alongside the
# two it already knew about -- a legitimate consequence of a genuinely new alternative path,
# not a design flaw. devtools::test() 0 failures (855, up from 367 -- the jump is expected
# combinatorial growth in path-enumeration tests, not new test files), devtools::check()
# 0 errors/0 warnings/0 notes. Also corrected the Workflow Graph section's long-stale
# "20 nodes / 22 edges" claim (dated to Session 69's original build, never updated through
# many later additions) to the current true count (28 nodes / 38 edges / 34 snippets).
# Previous update, 2026-07-24 (Sonnet 5 -- metadata-drift assessment + sync pass, prompted by the
# user asking how well TaxaWizard understands the many recent ecosystem changes. Cross-checked
# workflow_graph.json/snippets/inst/metadata/*.json against every package's real current
# exports (NAMESPACE) and the ecosystem CLAUDE.md's Recent Breaking Changes table. Found and
# fixed: (1) BROKEN -- workflow_graph.json's reference_df node + taxa_to_refs edge, and
# metadata/TaxaLikely.json, still named the fully-removed fetch_reference_sequences()
# (deleted 2026-07-19, see TaxaID/CLAUDE.md) instead of fetch_ncbi_reference_sequences();
# taxa_to_refs.R's own snippet CODE was already correct (called the right function), so
# generated scripts using this path were fine -- only the graph/metadata registry was stale.
# (2) BROKEN, silent-wrong-answer risk -- consensus_to_flagged.R's snippet and
# metadata/TaxaFlag.json's flag_contaminant()/flag_handler() entries still assumed the
# pre-2026-07-24 {contaminant_type}_risk/_score/_reason and handler_risk/_score/_reason column
# names; TaxaFlag::flag_contaminant()/flag_handler() were renamed to a fixed
# observation_validity/validity_flag/validity_reason schema THE SAME DAY (see TaxaFlag/
# CLAUDE.md's top session note) -- contaminant_type now only changes the qualifier embedded in
# validity_flag's VALUE, not any column name. A script generated from the old snippet would
# have silently reported "0 high-risk contaminants" always (paste0(contaminant_type, "_risk")
# resolves to a column that no longer exists, so the sum() over it is always 0) rather than
# erroring -- fixed the snippet to read validity_flag directly. add_posthoc_assessment()'s
# metadata entry was also substantially behind (missing domestic_taxa/domestic_prior_source,
# absolute_fit_pvalue_col/weak_evidence_pvalue -> unsupported_rank, own_rank_confusion_risk_col/
# high_confusion_risk_threshold -> confusion_risk_flag, all added across the 2026-07-19 through
# 2026-07-23 sessions) -- updated to the current signature. (3) Real correctness gap, not
# breaking -- TaxaFetch::stack_occurrences() stopped deduplicating entirely on 2026-07-23
# (dedupe_occurrences() split out); taxa_to_occ.R's snippet (the one live caller of
# filter_gbif_quality() in this package) had no dedup step at all even before that split.
# TaxaFetch's own CLAUDE.md now says explicitly "call dedupe_occurrences() even for a single
# GBIF source" -- added that call to the snippet + the taxa_to_occ edge's function list + a new
# metadata/TaxaFetch.json entry for dedupe_occurrences(). Also refreshed metadata/TaxaFetch.json's
# filter_gbif_quality()/stack_occurrences() entries, both badly stale (wrong max_coord_uncertainty
# default, no mention of removed_records attr, flag_institution, or any CoordinateCleaner checks).
# NOT done this session, flagged as open follow-up work instead of attempted blind: several real
# functions/capabilities added since roughly Session 134-140 have NO graph representation at
# all -- TaxaAssign::combine_multisite_priors() (required after join_priors() for the multi-site
# "site" data-frame path, added Session 138, still entirely missing from the graph), the
# site-table/spatial-grouping toolchain (TaxaMatch::build_site_table()/group_observations_by_bbox()/
# join_event_site_metadata()/assign_spatial_group()), TaxaFetch::check_geographic_outliers(),
# TaxaFetch::fetch_inat_occurrences() + TaxaExpect::generate_domestic_food_priors() (the whole
# domestic/food-species-priors path, added 2026-07-23), and TaxaHabitat::flag_institution_candidates().
# These aren't drift (nothing in the graph claims to cover them) -- they're capabilities the
# conversational workflow builder simply can't route to yet, which needs new graph nodes/edges (a
# design decision, not a sync fix) -- scoped but not attempted this session. The *_support ->
# *_confusion_risk rename (2026-07-23) and the new winner_*_confusion_risk/winner_absolute_fit_pvalue
# pass-through output columns (TaxaAssign::posterior_consensus()) were checked and found to have
# NEVER been referenced anywhere in TaxaWizard's metadata (correctly -- optional/additive output
# columns, not required inputs), so there was nothing to rename; skipped adding them as a
# low-value completeness pass. devtools::test() 0 failures (367/367, unchanged -- no test asserts
# on these specific snippet/metadata contents), devtools::check() run to confirm no regressions.
# Previous update, 2026-07-23, continued (Sonnet 5 -- metadata/TaxaAssign.json's score_consensus
# entry updated for TaxaAssign::score_consensus(rank_thresholds=)'s new required-arg behavior
# (no default, errors if omitted -- see TaxaAssign/CLAUDE.md's matching note): the
# rank_thresholds input flipped "required": false/"default": "c(species=98,...)" ->
# "required": true, description rewritten to point at either supplying real thresholds or
# deriving marker-specific ones via the new TaxaLikely::compute_rank_thresholds(), or passing
# NULL explicitly to disable rank capping. inst/graph/snippets/match_to_consensus_score.R
# needed no change -- it already always forwards a templated {{rank_thresholds}} value the
# Phase 3 parameterize step fills in, so making the metadata entry required simply means the
# interview always asks for it now rather than silently accepting an omission. Validated
# inst/metadata/TaxaAssign.json still parses (jsonlite::fromJSON) after the edit.
# devtools::test() 0 failures (70), devtools::check() 0/0/0.
# Previous update, 2026-07-23 (Sonnet 5 -- repointed from TaxaMatch's removed
# read_wildlife_insights_output() to the new read_speciesnet_output() (see
# TaxaMatch/CLAUDE.md's 2026-07-23 note): workflow_graph.json's two "wildlife_insights"
# function-list entries (image_to_match, image_refs_to_matrix edges) -> "speciesnet";
# both edges' snippet files (image_to_match.R, image_refs_to_matrix.R) gained a
# "speciesnet" switch branch calling TaxaMatch::read_speciesnet_output() in place of
# the removed "wildlife_insights" branch; metadata/TaxaMatch.json's function entry
# replaced wholesale with read_speciesnet_output()'s real signature;
# metadata/TaxaLikely.json's build_image_reference() input description updated; and
# prompts/phase_classify.md's input-type guidance re-worded. Found, but deliberately
# NOT fixed (out of scope, flagged for the existing metadata-drift audit item instead):
# every read_*() entry in metadata/TaxaMatch.json lists its first input as `"name":
# "data"`, but the real functions (read_animl_output()/read_birdnet_output()/
# read_inaturalist_cv_output()) all take `files` as their first argument -- `data`
# isn't even a valid formal, so a script generated from these snippets' pre-existing
# "animl"/"inaturalist_cv" branches would error with "unused argument" if run. The
# new "speciesnet" branch added this session correctly uses `files =` (matching
# read_speciesnet_output()'s real signature); the three pre-existing branches were
# left as-is. See [[project_taxawizard_metadata_drift]] in the memory system.
# devtools::test() 367/367 unaffected. Previous update, 2026-06-08 (Session 104 —
# TaxaFlag metadata updated: add_posthoc_assessment added; stale column names fixed)

---

## Package Purpose

Conversational workflow designer for the TaxaID ecosystem. Interviews the user
about their data, goals, and parameters via an LLM-powered chat interface, then
generates a self-contained .R script, .md methods text, or Shiny application.

Sits outside the TaxaID dependency chain -- depends on all TaxaID packages
(via metadata), but no TaxaID package depends on it.

**Status: Graph-based engine implemented. 0 errors, 0 warnings, 0 notes on devtools::check().
Metadata JSONs fully audited. 259 tests passing.**

---

## Architecture

### Graph-Based Three-Phase Engine (Session 69)

The engine eliminates LLM hallucination of function names, parameter names, and
variable threading by encoding the valid workflow graph as structured data and
reducing the LLM's role to three constrained tasks.

**Phase 1 -- Classify** (~3.8K token prompt):
LLM sees only node descriptions. Identifies `input_type` and `output_type` from
user's description. No function details exposed.

**Phase 2 -- Path Select** (~6.5K token prompt):
R computes all valid paths via `.compute_paths()` (backward recursive search
with multi-input edge support). LLM sees numbered path options with step labels
and time estimates. Recommends a path and confirms with user.

**Phase 3 -- Parameterize** (~5.9K token prompt):
R loads pre-validated code snippets for the selected path. LLM sees ONLY those
snippets + their parameter docs. Fills in `{{placeholder}}` values from user
input. Cannot invent function calls or parameter names.

**Error Fix** (~3.5K token prompt):
Diagnostic-first flow. `.parse_error_context()` extracts step number and edge
from error text. Full parameter docs for the failing function injected. LLM
instructed to ask for `str()`/`names()` diagnostics before attempting fix.

Phase detection is stateless -- determined from the last assistant message's
JSON (stored as full structured response in history).

### Workflow Graph

`inst/graph/workflow_graph.json` defines (2026-07-24 count, corrected from a long-stale
"20 nodes / 22 edges" claim dating to Session 69's original build):
- **28 nodes**: 10 inputs, 12 intermediates, 6 outputs
- **38 edges**: each maps to specific TaxaID functions + a code snippet file
- **Wrapper edges**: `build_priors()`, `run_llm_pipeline()`, `run_bayesian_pipeline()`
  flagged with `"wrapper": true`

`inst/graph/snippets/*.R` -- 34 code snippet files with `{{placeholder}}` params
extracted from real battle-tested workflow scripts.

Path computation handles multi-input edges (e.g., `match_to_consensus_bayes`
requires `match_df + model_params + priors`) via backward recursive search with
Cartesian product combination. Results are topologically sorted.

Example: `sequences -> consensus` yields 6 paths (score-only, LLM wrapper,
full Bayesian manual, full Bayesian wrapper, stepwise Bayesian manual/wrapper).

### Stateless Engine
`workflow_engine(history, metadata) -> JSON` is the core. Phase detection from
history, phase-specific prompt assembly, LLM call, response parsing. No state
between calls.

### User Interface: `workflow_create()`
Single entry point with `mode` parameter:
- **`"auto"`** (default): browser if shiny available, else console
- **`"browser"`**: standalone browser window via `shiny::browserViewer()`
- **`"viewer"`**: RStudio Viewer pane via `shiny::paneViewer()`
- **`"console"`**: `readline()` loop in R console (no shiny dependency)

Deprecated wrappers `workflow_chat()` and `workflow_gadget()` still exported
(thin wrappers that print deprecation notice and call `workflow_create()`).

### Script-to-App Conversion: `workflow_app()`
Takes any R script and converts it to a standalone Shiny `app.R` with file upload
widgets, parameter controls, progress bar, log panel, results table, and CSV/RDS
download buttons. No TaxaWizard dependency at runtime -- the app is fully standalone.

Two paths:
- **TaxaWizard scripts**: auto-detected via `# --- User Parameters ---` markers;
  parses parameter section (10 widget types) and step blocks via regex + brace counting.
- **Generic R scripts**: via `annotate_script()` -- guided annotation identifies
  parameters (top-level literal assignments) and steps (comment-separated code blocks).
  Self-guided mode (3 readline questions) or LLM-guided mode (1 confirmation).

The `annotate` parameter controls behavior: `"auto"` (default) tries TaxaWizard
parsing first, then falls back to interactive annotation. `"self"`/`"llm"` force
a specific mode. `"none"` errors on non-TaxaWizard scripts.

### Triple-Mode Output
A single interview produces one or more outputs:
- `.R` script (self-contained workflow with checkpoint/resume + debug mode)
- `.md` methods text (publication-ready)
- Shiny app (interactive dashboard via `workflow_app()`)

### Error Feedback Loop
`workflow_fix()` resumes the conversation after a script error:
1. User runs generated script, hits error
2. Calls `workflow_fix()` (no args = interactive paste mode, avoids quoting issues)
3. `.parse_error_context()` extracts step number + edge from error text + saved DAG
4. Engine uses `phase_error_fix.md` prompt with full param docs for failing function
5. Diagnostic-first: LLM asks for `str()`/`names()` before attempting speculative fix
6. In auto mode, LLM is instructed to be conservative (only fix confident errors)
7. Correction saved to `~/.taxawizard/corrections.json` for future sessions

### Generated Script Features
- **Checkpoint/resume**: each step cached as `.workflow_checkpoints/step_NN.rds`; skipped on re-run
- **Auto-error-catch**: `tryCatch()` wrapping with auto `workflow_fix()` call on failure
- **Debug mode**: `debug_mode <- TRUE` subsets to first 20 `observation_id`s (not raw rows) for fast iteration
- **Scope-safe steps**: uses `quote({...})` + `eval(envir = parent.frame())` so variables created in one step are visible to later steps

### Context Persistence
- `workflow_context.json` saved alongside generated script; next `workflow_create()` session
  uses previous parameters as defaults
- `~/.taxawizard/corrections.json` accumulates error/fix pairs (max 50); injected into
  system prompt as "KNOWN ISSUES" to prevent repeat mistakes

### Trial Mode
Generated scripts can include a trial-mode subset for performance estimation.
Metadata includes per-function `scaling` and `scaling_note` fields.

---

## Function Inventory

### Exported

| Function | Purpose | Source file |
|---|---|---|
| `workflow_create()` | Main entry point: interview + script generation (mode = auto/browser/viewer/console) | R/create.R |
| `workflow_engine()` | Stateless core: history + metadata -> JSON response | R/engine.R |
| `workflow_fix()` | Resume conversation after script error | R/cli.R |
| `workflow_app()` | Convert any R script to standalone Shiny app (auto/self/llm/none annotation) | R/shiny.R |
| `annotate_script()` | Guided annotation of generic R scripts for Shiny conversion (self/llm modes) | R/shiny.R |
| `workflow_chat()` | **Deprecated** wrapper -> `workflow_create(mode = "console")` | R/cli.R |
| `workflow_gadget()` | **Deprecated** wrapper → `workflow_create(mode = "viewer")` | R/gadget.R |

### Internal helpers -- Graph engine (R/graph.R)

| Function | Purpose |
|---|---|
| `.load_graph()` | Parse workflow_graph.json; cache in namespace env |
| `.compute_paths()` | Backward recursive search for all valid paths between input/output types |
| `.describe_paths()` | Human-readable path descriptions for Phase 2 prompt |
| `.get_path_context()` | Load snippets + param docs for a selected path (Phase 3) |
| `.build_phase_prompt()` | Assemble phase-specific system prompt from template + graph context |
| `.describe_node_types()` | Format input/output node list for Phase 1 prompt |
| `.list_node_types()` | Return input/output node IDs |
| `.cartesian_plans()` | Cartesian product of sub-path plans for multi-input edges |
| `.topo_sort_edges()` | Topologically sort edge set for dependency-correct execution order |
| `.extract_param_docs()` | Pull parameter docs from metadata for path functions |
| `.build_adjacency()` | Forward adjacency list from edges |
| `.graph_cache()` / `.graph_env` | Mutable cache for loaded graph |

### Internal helpers -- Engine (R/engine.R)

| Function | Purpose |
|---|---|
| `.detect_phase()` | Determine current phase from conversation history (stateless) |
| `.last_assistant_state()` | Parse last assistant message JSON for phase fields |
| `.last_message_by_role()` | Find last user or assistant message |
| `.looks_like_error()` | Pattern-match error text to trigger error_fix phase |
| `.load_system_prompt()` | Legacy monolithic prompt builder (kept for backward compat) |

### Internal helpers -- API + metadata

| Function | Purpose | Source file |
|---|---|---|
| `.call_llm()` | httr2 wrapper for Anthropic API | R/api.R |
| `.parse_engine_response()` | Extract + validate JSON from LLM response | R/api.R |
| `%\|\|%` | Null-coalescing operator | R/api.R |
| `.load_metadata()` | Load per-package JSON from inst/metadata/ | R/metadata.R |
| `.compress_metadata()` | Convert metadata to token-efficient prompt text | R/metadata.R |

### Internal helpers -- Output + CLI

| Function | Purpose | Source file |
|---|---|---|
| `.generate_outputs()` | Dispatch to script/markdown/app generators | R/output.R |
| `.generate_script()` | DAG -> .R file (with checkpoint, error-catch, debug) | R/output.R |
| `.find_existing_script()` | Find today's script for continuation mode | R/output.R |
| `.append_to_script()` | Append new DAG steps to existing script (step renumbering, dedup) | R/output.R |
| `.generate_markdown()` | DAG -> .md file | R/output.R |
| `.generate_app()` | DAG -> app.R (placeholder) | R/output.R |
| `.save_session()` / `.load_session()` | Temp RDS for conversation state (workflow_fix) | R/cli.R |
| `.parse_error_context()` | Extract step number + edge ID from error text + saved DAG | R/cli.R |
| `.history_has_prior_dag()` | Detect continuation mode from conversation history | R/engine.R |
| `.save_context()` / `.load_context()` | workflow_context.json persistence | R/context.R |
| `.format_context_for_prompt()` | Inject saved context into system prompt | R/context.R |
| `.corrections_path()` | `~/.taxawizard/corrections.json` path | R/context.R |
| `.load_corrections()` / `.save_correction()` | Per-user error/fix accumulation | R/context.R |
| `.format_corrections_for_prompt()` | Inject known issues into system prompt | R/context.R |
| `.subset_for_trial()` | Subset input data for trial mode | R/trial.R |
| `.estimate_scaling()` | Predict full-run time from trial timing | R/trial.R |

---

## Metadata Schema

Per-package JSON files in `inst/metadata/`. Each file contains:

```json
{
  "package": "PackageName",
  "description": "One-line package description",
  "functions": [
    {
      "name": "function_name",
      "description": "What it does",
      "inputs": [
        {"name": "arg", "type": "type_name", "required": true, "default": "value", "description": "..."}
      ],
      "output": {"type": "type_name", "description": "..."},
      "scaling": "linear | quadratic | api_limited",
      "scaling_note": "Human-readable timing estimate"
    }
  ]
}
```

Type names create the compatibility matrix: a function that outputs `match_df`
feeds into any function that accepts `match_df` as input.

**CRITICAL**: Parameter names in metadata must exactly match actual function signatures.
A full audit was performed Session 68 against all 8 packages. If function signatures
change upstream, metadata must be updated here.

---

## Dependencies

| Package | Role | In |
|---|---|---|
| httr2 | Anthropic API calls | Imports |
| jsonlite | JSON parse/write for metadata + engine responses | Imports |
| shiny | Gadget + Shiny chat UI | Suggests |

No TaxaID packages in Imports or Suggests -- the metadata JSON files are the
interface, not runtime dependencies.

---

## Key Design Decisions

### Graph-constrained LLM (Session 69)
The LLM never invents function sequences. Valid paths are computed in R from the
workflow graph. The LLM only: (1) classifies user intent, (2) selects from
precomputed paths, (3) fills in parameter values for pre-validated code snippets.
This eliminates the root cause of hallucinated parameter names, wrong function
sequences, and variable threading errors.

### Phase-specific prompts
Each phase gets a minimal, targeted prompt (~4-7K tokens) instead of the old
monolithic prompt (~15K+ tokens with full registry). Phase 1 sees only node
descriptions. Phase 3 sees only the selected path's snippets + param docs.
Dramatically reduces the LLM's opportunity to hallucinate.

### Backward recursive path search
`.compute_paths()` uses backward search from the output node, recursively finding
all ways to produce each required input. Handles multi-input edges (e.g.,
`match_to_consensus_bayes` needing `match_df + model_params + priors`) via
Cartesian product of sub-plans. Results are deduplicated and topologically sorted.

### Full JSON in history
Assistant messages store the full structured JSON response (not just `$message`
text). This enables stateless phase detection from history alone -- no external
state object needed between calls.

### Diagnostic-first error handling
`workflow_fix()` now builds a targeted `error_fix` prompt with full parameter
docs for just the failing function. The prompt instructs the LLM to request
`str()` and `names()` diagnostics before attempting a fix. In auto mode, the
LLM is told to be conservative (only fix confident errors like wrong parameter
names).

### Compressed metadata registry (legacy, still used in error_fix)
One flat table of function signatures. Full details injected only for functions
in the selected path. Keeps token budget manageable.

### LLM model for the engine
Default: `claude-sonnet-4-6`. Configurable via `model` param. Sonnet is faster
and cheaper for the interview loop; the code comes from pre-validated snippets,
not the LLM. Opus can be specified for complex parameterization tasks.

### Wrappers first
Phase 2 recommends wrapper paths when available. Individual functions exposed
only when customization is needed. User confirms that standard defaults are
acceptable before wrapper path is selected.

### Named arguments always
System prompt requires `function(arg_name = value)` style -- never positional.
This prevents parameter ordering bugs (e.g., `site_description` landing in `date`).

### Interactive paste for workflow_fix()
Calling `workflow_fix()` with no args opens readline() prompt where users paste
error text directly. Avoids R quoting/escaping issues with error messages that
contain quotes, backslashes, etc.

---

## Session Notes

Sessions 68–80 archived in ecosystem_docs/session_notes/TaxaWizard_sessions.md.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaWizard-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.

**Session 89 (2026-05-27)**
- `phase_classify.md`: `match_df` input type description now mentions BirdNET acoustic detections and image classifier results alongside BLAST output — "multiple scored candidates per sample" is the common pattern.
- `phase_parameterize.md`: `barcode_term` bullet explicitly marked as DNA/eDNA only; new `rank_system` bullet for acoustic/image: BirdNET typically uses `c("genus","species")`; image classifiers use whatever taxonomy columns are returned.

**Session 104 (2026-06-08): TaxaFlag metadata update**
- `TaxaFlag.json` updated: `add_posthoc_assessment()` added; `flag_contaminant` column names corrected to Session 101 vocabulary (`{type}_risk`/`{type}_score`/`{type}_reason`); `event_col` default fixed from `"observation_id"` → `"event_id"`; `review_assignments` `taxa_per_call` default corrected from 30 → 15; `data_type` param added.
- No workflow graph changes: `add_posthoc_assessment()` is a post-hoc annotation step (not a pipeline transformation), so it is not added as a graph edge.
