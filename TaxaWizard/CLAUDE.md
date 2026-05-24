# CLAUDE.md -- TaxaWizard (formerly TaxaWorkflow)
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-23 (Session 86 — no package changes; CC0 license Session 82)

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

**Session 68 (2026-05-05)**
- Package scaffold created with full directory structure
- R source files: api.R, metadata.R, engine.R, cli.R, shiny.R (placeholder), output.R, trial.R
- System prompt drafted in inst/prompts/system_prompt.md
- User-tested the chat interface; identified UX pain points:
  - Error feedback after script generation (solution: `workflow_fix()`)
  - Quoting issues pasting errors (solution: interactive readline mode)
  - Console competition between chat and script execution
- Implemented 6 UX improvements:
  1. `workflow_fix()` with interactive paste mode
  2. Auto-error-catch (`tryCatch`) in generated scripts
  3. Checkpoint/resume via per-step RDS caching
  4. `workflow_context.json` for session persistence
  5. `~/.taxawizard/corrections.json` for learning from mistakes
  6. Debug mode (subset to 20 rows for fast iteration)
- `workflow_gadget()` added for RStudio Viewer pane chat (separates chat from console)
- `context.R` added with save/load context + corrections system
- Metadata JSON audit: 13 wrong param names, 2 wrong defaults, 1 wrong package,
  many missing functions/required params. All 8 files corrected.
- Test file with 7 offline tests (JSON parsing, scaling estimation, trial subsetting)
- `devtools::check()`: 0 errors, 0 warnings, 0 notes (after cleanup)
- **Deferred**: Full Shiny app mode, package-level learning (auto-updating metadata from corrections)

**Session 69 (2026-05-06)**
- Graph-based workflow engine implemented to eliminate LLM hallucination
- New files:
  - `inst/graph/workflow_graph.json` -- 20 nodes, 22 edges defining full TaxaID workflow graph
  - `inst/graph/snippets/*.R` -- 22 code snippet files with `{{placeholder}}` params
  - `R/graph.R` -- graph loading, backward recursive path search, phase prompt builder
  - `inst/prompts/phase_classify.md` -- Phase 1 (~3.8K chars)
  - `inst/prompts/phase_path_select.md` -- Phase 2 (~6.5K chars)
  - `inst/prompts/phase_parameterize.md` -- Phase 3 (~5.9K chars)
  - `inst/prompts/phase_error_fix.md` -- Error fix (~3.5K chars, diagnostic-first)
  - `tests/testthat/test-graph.R` -- 140+ assertions
- Modified files:
  - `R/engine.R` -- three-phase architecture: `.detect_phase()` + `.build_phase_prompt()`
  - `R/cli.R` -- full JSON in history; `workflow_fix()` uses targeted error_fix prompt;
    `.parse_error_context()` extracts step/edge from error text
  - `.Rbuildignore` -- stale top-level files excluded
- Key algorithm: `.compute_paths()` backward recursive search handles multi-input edges
  (e.g., `match_to_consensus_bayes` needs 3 inputs from different branches). Cartesian
  product of sub-plans, deduplication, topological sort.
- Verification: `sequences -> consensus` yields 6 paths; `taxa -> priors` yields 2;
  all edges correctly sorted; `devtools::check()` 0/0/0; 168 tests passing
- **Deferred**: `workflow_gadget()` update for phase-aware UI; integration test with live
  LLM call; snippet audit against latest upstream function signatures

**Session 70 (2026-05-06, continued)**
- Live end-to-end testing of `workflow_chat()` → script generation → script execution
- **Snippet hardening** (8 bugs found and fixed during live testing):
  1. Debug subsetting: `head(match_df, 20)` → sample_id-based subsetting (first 20 sample_ids
     with all their match rows, not first 20 raw rows)
  2. Column casing: added rank column lowercasing loop after `detect_ranks()` in all 4
     consensus/taxa snippets (user data has `Family` not `family`)
  3. Hardcoded `consensus_taxon`/`consensus_rank` in `consensus_to_reviewed.R` and
     `consensus_to_flagged.R` snippets (LLM was guessing `taxon_name` — wrong for consensus output)
  4. Variable scoping: `function() {...}` → `quote({...})` + `eval(envir = parent.frame())`
     in generated scripts so step variables remain visible to later steps
  5. JSON parser: rewritten to try all top-level `{...}` blocks last-to-first (LLM thinking
     text before JSON was confusing the parser)
  6. Phase transition: `auto_message` pattern to skip `readline()` when path_select completes
  7. Status normalization: map LLM-invented statuses (`"confirmed"`, `"ready"`) to valid values
  8. Edge ID repair: `.repair_edge_ids()` substitutes valid paths when LLM invents edge names
- **`workflow_create()` merge**: combined `workflow_chat()` + `workflow_gadget()` into single
  entry point with `mode` parameter (auto/browser/viewer/console)
  - Default `mode = "auto"` → browser if shiny available, console otherwise
  - `workflow_chat()` and `workflow_gadget()` retained as deprecated thin wrappers
  - Default model changed from `claude-opus-4-6` to `claude-sonnet-4-6`
- **`workflow_app()` repurposed**: now takes a generated .R script path and will convert it
  to a standalone Shiny app (placeholder implementation; build after script path is stable)
- **Viewer/browser modes**:
  - `dialogViewer` → `paneViewer` (viewer mode) + `browserViewer` (browser mode)
  - Fixed scroll: replaced `uiOutput`/`renderUI` with static `#chat-log` div + custom
    `Shiny.addCustomMessageHandler('update_chat', ...)` for direct innerHTML injection
  - Absolute positioning for chat-log inside flex-growing frame gives real pixel height
  - User guidance messages on mode selection
- **Prompt improvements**:
  - `phase_parameterize.md`: "CRITICAL FORMAT REQUIREMENT" (JSON only), "DAG Generation"
    rules 7-9 (never empty dag with complete status), score scale rules, rank_system rules
  - `phase_path_select.md`: "Use EXACT edge IDs", "Do NOT write R code"
  - Edge IDs now shown per step + as JSON array in `.describe_paths()`
- **`devtools::check()`: 0 errors, 0 warnings, 0 notes**
- **Deferred**: `workflow_app()` full implementation (script-to-Shiny converter);
  test Bayesian and score-consensus paths; test `consensus_df` input type paths;
  end-to-end `workflow_fix()` test with new engine

**Session 71 (2026-05-07)**
- Package renamed TaxaWorkflow → TaxaWizard
- Phase classify prompt: added CRITICAL DISAMBIGUATION section
- UI: "Thinking..." indicator with pulse animation; exit guidance messages

**Session 74 (2026-05-15)**
- **Script continuation/append mode**: when user extends a workflow in the same session,
  new steps are appended to the existing script rather than overwriting it.
  - `.find_existing_script()`: matches only `taxaid_workflow_YYYYMMDD.R` from today
    (avoids appending to week-old unrelated scripts)
  - `.append_to_script()`: finds highest step number, inserts before "Workflow complete"
    footer, adds only new library() calls, deduplicates parameters, updates `total_steps`
  - `.history_has_prior_dag()`: scans conversation history for completed DAGs to detect
    continuation mode; `is_continuation` flag propagated to parameterize prompt
  - Continuation prompt tells LLM that input data is already available as a variable
    from the prior script — do not add a file-loading step
- **Chat UI improvements** (Shiny viewer/browser modes):
  - CSS flex layout with `margin-top: auto` on inner wrapper anchors messages near input
    (eliminates large gap between chat text and text box)
  - Enter-to-send via JS `keydown` handler on `#user_input` (Shift+Enter for newline)
  - `innerHTML` operations target `#chat-log-inner` wrapper for correct scroll behavior
- **3 match-input snippets fixed**: `match_to_consensus_score.R`, `match_to_consensus_llm.R`,
  `match_to_consensus_bayes.R` now include `sample_id`/`score` column rename block
  (ESVId→sample_id, PercMatch→score) before calling consensus functions
- **Deferred**: full test of Bayesian pipeline path

**Session 75 (2026-05-18)**
- **`workflow_app()` fully implemented and debugged** — reads a generated .R script, parses
  parameters and steps, writes a standalone Shiny `app.R` with interactive widgets.
  - `.parse_workflow_script(lines)` — master parser: `$libraries`, `$params`, `$steps`
  - `.extract_libraries(lines)` — regex; drops TaxaWizard/TaxaWorkflow/base
  - `.extract_params(lines)` — finds User/Extension parameter sections; skips infrastructure params
  - `.classify_param(name, value_expr)` — 10 widget types: file_input, file_output, logical,
    numeric, named_numeric, numeric_range, data_frame, function_ref, null_param, character
  - `.extract_steps(lines)` — brace-counting parser for both `quote({})` and `function(){}` styles
  - `.build_app_code(parsed)` — orchestrates full app.R generation
  - `.widget_code()`, `.param_assembly_line()`, `.app_ui()`, `.app_server()` — code generators
- **Shiny app fixes** (4 bugs found during live testing):
  - Log panel: raw `tags$pre(id=...)` → `textOutput()` (wasn't a Shiny output binding)
  - `.run_step` scoping: injected into `env` via `assign()` (env has `parent = globalenv()`,
    can't see app-scope functions)
  - List columns: `renderTable` crashes on list-type columns; added `vapply(toString)` coercion
  - File upload validation: modal dialog blocks Run if no file uploaded; `.failed` flag halts
    on first error; `.log()` writes step-by-step messages to log panel
- **Known parameter labels**: `.widget_code()` has a 20-entry lookup mapping common TaxaWizard
  parameter names (min_score, geographic_hint, date, marker, etc.) to descriptive widget labels
  with examples
- **Prompt rule 22** added to `phase_parameterize.md`: step code must reference parameter
  variable names (`min_score = min_score`), never hardcode literals (`min_score = 97`).
  Ensures Shiny widget changes actually affect the computation. Verified with new script.
- **Stale `app.R` deleted** from package root (was causing R CMD check NOTE and shiny::runApp conflict)
- 48 tests passing; `devtools::check()` 0/0/0

**Session 76 (2026-05-18)**
- **`annotate_script()` for generic R scripts** -- any R script can now be converted to
  a Shiny app, not just TaxaWizard-generated workflows:
  - `.segment_script(lines)` -- pure R parsing using `parse(text=, keep.source=TRUE)` for
    expression boundaries. Identifies: libraries, parameter candidates (top-level literal
    assignments before first non-assignment expression), step candidates (remaining code
    grouped by comment headers or blank-line gaps).
  - `annotate_script(script_path, mode)` -- exported. Self-guided mode: 3 readline questions
    (select params, confirm/merge steps, confirm build). LLM-guided mode: sends script to
    LLM via `inst/prompts/annotate_script.md` template, user confirms with one question.
  - `workflow_app()` gains `annotate` param: `"auto"` (default, try TaxaWizard first then ask),
    `"self"`, `"llm"`, `"none"` (backward compat). Also gains `llm_fn` param for LLM mode.
  - Internal helpers: `.is_library_call()`, `.is_source_call()`, `.is_simple_assignment()`,
    `.is_literal_value()`, `.group_into_steps()`, `.extract_header_text()`,
    `.describe_code_block()`, `.last_assignment_var()`, `.annotate_self()`, `.annotate_llm()`,
    `.parse_annotation_response()`, `.parse_number_list()`, `.merge_steps_by_groups()`
  - Header pattern broadened to catch `# Step N: ...` style single-# comments
  - Step merging: user can combine steps (e.g., "1,2; 3; 4,5") during self-guided annotation
- 83 tests passing; `devtools::check()` 0/0/0

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` rename in all snippets, metadata JSON, prompts, R source, tests
- `sample_id_col` → `observation_id_col` in `seq_to_match.R` snippet and `TaxaMatch.json` metadata
- Debug subsetting in `R/output.R` and `R/trial.R` updated to use `observation_id`

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaWizard-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools), WERC
  review integration.

**Session 86 (2026-05-23)**
- No code changes. `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at
  TaxaID/ root). Disclaimer section removed from `README.md`.
