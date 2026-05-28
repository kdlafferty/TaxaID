# TaxaWizard Session Notes Archive
# Sessions 68–80. Current sessions live in TaxaWizard/CLAUDE.md.

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
