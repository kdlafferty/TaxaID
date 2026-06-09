# CLAUDE.md -- TaxaWizard (formerly TaxaWorkflow)
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-06-08 (Session 104 — TaxaFlag metadata updated: add_posthoc_assessment added; stale column names fixed)

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

`inst/graph/workflow_graph.json` defines:
- **20 nodes**: 6 inputs, 9 intermediates, 5 outputs
- **22 edges**: each maps to specific TaxaID functions + a code snippet file
- **Wrapper edges**: `build_priors()`, `run_llm_pipeline()`, `run_bayesian_pipeline()`
  flagged with `"wrapper": true`

`inst/graph/snippets/*.R` -- 22 code snippet files with `{{placeholder}}` params
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
