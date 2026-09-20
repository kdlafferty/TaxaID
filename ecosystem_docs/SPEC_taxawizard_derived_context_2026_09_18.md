# SPEC: TaxaWizard derived context, setup checks, and prompt pack
# Written 2026-09-18 (Fable 5.1). This is the P0 contract for work packages P1-P7.
# Decisions below were made by the user on 2026-09-18 and are not open.

## Why

TaxaWizard's knowledge of TaxaID lives in three hand-maintained layers that must be
edited together whenever a package changes: `inst/metadata/*.json` (94 function
signatures), `inst/graph/snippets/*.R` (31 snippets), and `inst/graph/workflow_graph.json`
(26 nodes, 33 edges). The system prompt also hard-codes signature facts in prose. The
metadata layer has drifted twice (see memory: project-taxawizard-metadata-drift) and the
GLMM -> kernel switch touched every layer plus tests. Installed packages already carry
every signature (`formals()`) and every argument description (`tools::Rd_db()`).

Principle for everything below: DERIVE, DON'T DECLARE. Hand-curate only workflow
topology (graph + snippets). Everything function-level is introspected from the
installed packages at runtime. Everything user-facing for LLMs is generated from the
same source, so the chat engine and the exportable prompt pack cannot disagree.

## Decisions (user, 2026-09-18)

1. `inst/metadata/` is DELETED. Data-flow types live only in the graph.
2. Snippets are KEPT and VALIDATED for now; removing them eventually is the direction.
   The Tier-B fallback (P2) is the path that makes removal possible later.
3. The setup checker lives in TaxaWizard (its conceptual home; already outside the
   dependency chain).
4. The prompt pack is BOTH generated on demand AND committed as a rendered copy at the
   repository root, refreshed by the same script that renders the READMEs, with a test
   that the two agree.
5. The existing chat interface is MODIFIED to consume the new structure (registry,
   setup report, pack templates). No new chat features.

## Constants

- `TAXAID_PACKAGES <- c("TaxaTools","TaxaFetch","TaxaHabitat","TaxaMatch","TaxaLikely",
  "TaxaExpect","TaxaAssign","TaxaFlag")` (dependency order). Define once in
  `R/registry.R`; nothing else hard-codes the list.
- All packages currently report version 0.1.0, so ANY cache must key on
  `packageDescription(p)$Built` as well as `packageVersion(p)`.
- New exports (collision-checked 2026-09-18 across all Taxa*/NAMESPACE and R/: none):
  `workflow_registry()`, `workflow_check()`, `sniff_input()`, `workflow_export_prompts()`.
- Branch: `taxawizard-derived-context`. Subagents work in their own worktree, do NOT
  install, do NOT commit; the coordinator merges and installs.
- Subagents run tests with `devtools::test()` from the package dir with
  `.libPaths(c("~/Library/R/4.0/library", .libPaths()))` so the installed TaxaID
  packages resolve. `devtools::check()` at the end of each package.
- Style: base R + jsonlite + httr2 only (DESCRIPTION Imports). Native pipe. No new
  Imports without a reason stated in the report.

---------------------------------------------------------------------------------------
## P1  Introspected registry replaces metadata JSON            (Sonnet, worktree)
---------------------------------------------------------------------------------------

### Deliverable: `R/registry.R`

```r
workflow_registry(packages = NULL, refresh = FALSE)
```
Returns a named list, one element per installed TaxaID package (skip, with a message,
any not installed). Element shape:

```r
list(
  package  = "TaxaExpect",
  version  = "0.1.0",
  built    = "<packageDescription()$Built>",
  functions = list(                     # one per export, alphabetical
    list(
      name        = "estimate_kernel_priors",
      title       = "<Rd \title>",
      description = "<Rd \description, first paragraph, plain text, <= 600 chars>",
      params      = list(               # in formals() order
        list(name = "occurrence_data", required = TRUE,  default = NULL, doc = "<Rd \arguments text>"),
        list(name = "lambda_km",       required = FALSE, default = "50", doc = "...")
      ),
      value       = "<Rd \value plain text, <= 400 chars, or NULL>"
    )
  )
)
```
- Source of truth: `getNamespaceExports(p)` for names; `formals()` for `required`
  (no default) and `default` (deparsed, one string); `tools::Rd_db(p)` for
  title/description/arguments/value, converted with `tools::Rd2txt()` and cleaned
  (strip underscore-bold markup and excess whitespace). Multiple exports can share
  one Rd (aliases): map via `\alias`.
- Exclude non-functions and internal helpers (names starting with `.`).
- Cache: `file.path(tools::R_user_dir("TaxaWizard", "cache"), "registry",
  sprintf("%s_%s_%s.rds", p, version, gsub("[^0-9]", "", built)))`.
  `refresh = TRUE` ignores the cache. Stale files for the same package are deleted
  when a new one is written.
- Internal helpers: `.compress_registry(registry)` produces the text injected at
  `{{FUNCTION_REGISTRY}}` in the system prompt. Format, one line per function:
  `- pkg::fn(a, b = 50, c = NULL) | <title>`. NO type column (types are gone).
  `.registry_docs(registry, functions)` produces the PARAM_DOCS block for a set of
  function names (used by `.extract_param_docs()`), listing each param with
  required/default and the Rd argument text.

### Removals and rewires
- Delete `inst/metadata/` and `R/metadata.R` (`.load_metadata`, `.compress_metadata`).
- Delete `diagnostics/taxawizard_metadata_audit.R` (nothing left to audit).
- Every `.load_metadata()` call site (create.R x2, engine.R, graph.R x3) uses
  `workflow_registry()`. `.extract_param_docs()` in graph.R reads registry entries.
- `workflow_engine(metadata = )` becomes `workflow_engine(registry = )`; accept
  `metadata` with a `lifecycle::deprecate_warn()` (lifecycle is in Suggests; guard with
  `requireNamespace`, else plain `warning()`).
- `inst/prompts/system_prompt.md`: delete every sentence that enumerates a specific
  function's parameters or package (the "Common mistakes to avoid" list, the
  "Package attribution" list, the `habitat_scheme`/`context`/`llm_fn` type notes).
  Keep the generic rules. Add one rule: "The FUNCTION REGISTRY below is generated from
  the installed packages at run time and is the ONLY authority on function names,
  packages, and parameter names." `llm_fn` guidance is allowed ONLY in generic form:
  "arguments named `llm_fn` take a function such as `TaxaTools::call_api`".
- `inst/prompts/phase_parameterize.md`: same rule; check its teaching example uses only
  names present in the registry (test it).
- Tests: replace `test-metadata-covers-workflow-functions.R` with
  `test-registry.R`: (a) registry non-empty for every installed package; (b) every
  function named in any snippet or in any edge's `functions` array has a registry
  entry (this is the structural guard, now against live truth); (c) `.compress_registry`
  output contains no line for a name that is not an export; (d) cache round-trip.
  Update `test-graph.R`/`test-engine.R` wherever they build or pass metadata.
- README.md "Key Functions" table gains `workflow_registry()`. NEWS.md entry.
  TaxaWizard/CLAUDE.md gets a top note (the user's convention: what, why, verified how).

### Acceptance
`devtools::test()` 0 failures; `devtools::check()` 0 errors/0 warnings; the compressed
registry for all 8 packages renders and is under ~60 KB; `grep -rn "load_metadata\|inst/metadata" TaxaWizard/` returns nothing.

---------------------------------------------------------------------------------------
## P2  Snippet validator + Tier-B fallback                (Sonnet, worktree, after P1)
---------------------------------------------------------------------------------------

- `R/validate.R`: `.validate_snippets(graph, registry)` returns a data.frame
  (edge_id, function, problem) with problems `not_exported` and `stale_argument`.
  Port the logic of `diagnostics/workflow_checks/check_stale_arguments.R` (AST walk,
  named args vs formals) to snippets; placeholders `{{x}}` are replaced with `x` before
  parsing. Test asserts zero problems (this is the in-package drift test).
- Engine fallback: when an edge in the selected path fails validation at run time,
  `.get_path_context()` substitutes for that edge's snippet a generated block:
  the edge's label/description, the live registry entries (full docs) for that edge's
  package(s), and the instruction "No validated snippet exists for this step. Write it
  from the documentation above, use named arguments only, and mark the step
  `validated: false`." Generated scripts print a WARNING banner above unvalidated
  steps. `.describe_paths()` labels such paths "(one or more unvalidated steps)".

---------------------------------------------------------------------------------------
## P3  Setup checker, edge requirements, input sniffer         (Sonnet, worktree)
---------------------------------------------------------------------------------------

### `R/setup.R`

```r
workflow_check(edges = NULL, verbose = TRUE)   # -> data.frame, class "taxaid_check"
```
Columns: `component`, `category` (one of `r`, `package`, `key`, `network`, `cache`,
`binary`), `status` (`ok`, `missing`, `warn`, `skip`), `detail`, `fix`.
`print.taxaid_check()` renders a compact table with the fix text for non-ok rows.
Machine-readable is the point: the engine injects it into prompts, the generated
script's Step 0 stops on it.

Checks (all no-network unless category is `network`):
- `r`: R >= 4.1; interactive vs Rscript (affects provider auto-detect; see README
  Troubleshooting).
- `package`: each of TAXAID_PACKAGES installed + `Built` date; `Biostrings`/`DECIPHER`
  (Bioconductor, needed by TaxaLikely reference-matrix building and TaxaMatch);
  `rBLAST` optional (local BLAST); `shiny` optional.
- `key`: from `inst/setup/requirements.json` (below). Report set/unset only, never the
  value. Detect whether the key is in `~/.Renviron` vs only the session (the README's
  documented footgun) and say so in `fix`.
- `binary`: `blastn` on PATH via `Sys.which()` (optional; only needed for local BLAST).
- `cache`: each package's `tools::R_user_dir(p, "cache")` existence, writability, size
  (use `TaxaTools::taxaid_cache_report()` if available, else `list.files` + `file.size`).
- `network`: one cheap HEAD/GET each to GBIF, NCBI eutils, and the configured LLM
  provider, 5 s timeout, `status = "skip"` when `getOption("TaxaWizard.offline")` is
  TRUE or no network. Use httr2 (already an Import).

`edges = c("seq_to_match", ...)` restricts the report to the union of those edges'
`requires` plus the `r` and `package` categories.

### `inst/setup/requirements.json`
One table, hand-kept but small:
```json
{
  "keys": [
    {"id": "key:ANTHROPIC_API_KEY", "env": "ANTHROPIC_API_KEY", "purpose": "LLM provider (any ONE of the LLM keys suffices)",
     "group": "llm", "fix": "usethis::edit_r_environ(); add ANTHROPIC_API_KEY=...; restart R",
     "docs": "TaxaTools vignette api-setup"},
    ...GEMINI_API_KEY, OPENAI_API_KEY, AZURE_OPENAI_API_KEY (group llm),
    ...ENTREZ_KEY (alias NCBI_API_KEY), GBIF_USER/GBIF_PWD/GBIF_EMAIL (group gbif),
    ...INAT_API_TOKEN, OPENALEX_API_KEY, XC_API_KEY
  ],
  "packages": [{"id": "pkg:Biostrings", "install": "BiocManager::install(\"Biostrings\")"}, ...],
  "binaries": [{"id": "bin:blastn", "install": "https://blast.ncbi.nlm.nih.gov/ ... or use method = \"remote\""}],
  "network": [{"id": "net:gbif", "url": "https://api.gbif.org/v1/"}, {"id": "net:ncbi", "url": "https://eutils.ncbi.nlm.nih.gov/"}, {"id": "net:llm", "url": null}]
}
```
A `group` means "any one of these satisfies the requirement" (`key:llm`, `key:gbif`).
Source material: `TaxaTools/vignettes/api-setup.Rmd`, README.md sections "API Keys"
and "Troubleshooting", `TaxaWizard/R/zzz.R`, `grep -rn 'Sys.getenv' Taxa*/R`.

### Graph: `requires` per edge
Add `"requires": ["key:llm", "net:ncbi", "pkg:Biostrings", ...]` to every edge in
`inst/graph/workflow_graph.json`, derived by reading each edge's snippet and the
functions it calls (which env vars / packages / network they touch). Empty array when
nothing is needed. Test: every token in any `requires` is defined in requirements.json;
every edge has the field.

### `sniff_input(path)`
Returns `list(node_id, confidence = c("high","medium","low"), evidence = "<string>")`
where `node_id` is one of the graph's input node ids (see `.list_node_types()`), or
`NA` with evidence explaining why. Signatures: FASTA (`>` first char); `.rds` whose
object is a matrix with DNA-string column names -> `sequences` (DADA2 seqtab); CSV
with BirdNET headers -> `birdnet_detections`; Animl / SpeciesNet JSON (`predictions`)
/ iNaturalist CV JSON -> `image_classifier_output`; CRABS TSV or FASTA + taxonomy
TSV sibling -> `local_fasta`; CSV with lat/lon-like columns -> `occurrences`; CSV with
a score-like column and taxon/rank columns -> `match_df`; CSV/txt with a single
name column -> `taxa`; CSV with one taxon per row and no score -> `consensus_df`.
Reuse the exact header signatures the `TaxaMatch::read_*()` functions expect (read
their source; do not guess). Reads at most the first 50 lines / 1 MB. Never errors on
an unreadable file; returns NA with evidence.

### Generated script Step 0
`R/output.R` `.generate_script()`: emit, before step 1,
```r
# Step 0: setup check (generated by TaxaWizard)
.setup <- TaxaWizard::workflow_check(edges = c("<edge ids of this dag>"), verbose = TRUE)
if (any(.setup$status == "missing")) stop("Setup incomplete -- see the fix column above.")
```
Only when the dag carries edge ids (it does after the graph engine; the legacy
free-form dag may not -- fall back to `edges = NULL`).

### Do NOT (in P3)
Do not wire the check into the engine prompts; that is P6, to avoid editing engine.R /
graph.R concurrently with P1. Do put the placeholder names in the spec so P6 can:
`{{SETUP_STATUS}}` (classify prompt), `{{PATH_REQUIREMENTS}}` (parameterize prompt),
`{{SNIFF_RESULT}}` (classify prompt, when the user names a path).

### Acceptance
`workflow_check()` runs on this machine and prints; `workflow_check(edges = "seq_to_match")`
shows NCBI/BLAST rows and not GBIF rows; `sniff_input()` on
`diagnostics/fast_workflows/` fixtures and on a FASTA classifies correctly (tests with
tiny in-test fixtures written to tempdir; no network in tests). Tests/check clean.
README, NEWS, CLAUDE.md top note.

---------------------------------------------------------------------------------------
## P4  Prompt pack generator                          (Sonnet, worktree, after P1+P3)
---------------------------------------------------------------------------------------

```r
workflow_export_prompts(dir = "taxaid_prompts", overwrite = FALSE)
```
Writes:
```
taxaid_prompts/
  START_HERE.md              # P5, hand-written, copied from inst/prompts/pack/
  CLAUDE.md                  # 3 lines: "Read START_HERE.md first." (agentic tools)
  AGENTS.md                  # same text (Codex/Cursor convention)
  CONTEXT_TaxaID.md          # generated ecosystem digest
  CONTEXT_<Package>.md x8    # generated per package
  SETUP_REPORT.md            # rendered workflow_check() output for THIS machine
  tasks/classify.md          # phase templates with {{NODE_TYPES}} etc. filled
  tasks/path_select.md       # (PATH_OPTIONS left as an instruction to compute from CONTEXT_TaxaID)
  tasks/parameterize.md
  tasks/error_fix.md
  tasks/handoff_template.md  # from P5
```
- `CONTEXT_TaxaID.md`: packages table (name, one-line purpose from DESCRIPTION Title,
  version, built); node types (from `.describe_node_types()`); the graph as a text
  adjacency list (edge id, from -> to, label, requires); the two/three canonical
  pipelines (from the system prompt's "Pipeline Awareness"); wrappers; setup
  requirements summary. Target <= 400 lines.
- `CONTEXT_<Package>.md`: DESCRIPTION Title/Description; then every export as
  `### fn(sig)` + title + description + params table; then the package README's
  Quick Start section if a `## Quick Start` heading exists. Generated from
  `workflow_registry()` -- no hand text.
- The committed copy lives at `TaxaID/llm_prompts/` (repo root). Add a step to
  `ecosystem_docs/render_readmes.R` (or wherever the README render pipeline is; verify)
  that regenerates it. Test: `workflow_export_prompts(tempdir())` equals the committed
  copy except `SETUP_REPORT.md` (machine-specific; committed copy holds a placeholder).

---------------------------------------------------------------------------------------
## P5  START_HERE.md and handoff template                       (coordinator)
---------------------------------------------------------------------------------------
Hand-written in `inst/prompts/pack/`. Interview lists (data type, desired output, file
locations, installed state, interface kind); interface branch (file-capable agent vs
paste-only chat); routing rules to CONTEXT files; when to split into multiple chats
(prior pipeline vs likelihood pipeline are independent); handoff note template.

---------------------------------------------------------------------------------------
## P6  Engine consumes the new structure                (Sonnet, after P1-P5 merged)
---------------------------------------------------------------------------------------
- `workflow_create()` runs `workflow_check()` first; the report is injected at
  `{{SETUP_STATUS}}` in the classify prompt; after path selection the engine runs
  `workflow_check(edges = selected)` and injects `{{PATH_REQUIREMENTS}}` into the
  parameterize prompt so the LLM tells the user what to set up before generating.
- When the user's message contains a path that exists on disk, `sniff_input()` runs and
  `{{SNIFF_RESULT}}` is injected into the classify prompt.
- Phase templates are read from ONE place (`inst/prompts/`), and the pack's `tasks/`
  are rendered from the same files (P4 already does this; P6 verifies no duplication).
- Docs: README rewrite for the new entry points; NEWS; CLAUDE.md note.

---------------------------------------------------------------------------------------
## P7  Dry runs                                                     (coordinator + Sonnet)
---------------------------------------------------------------------------------------
(a) `workflow_create(mode = "console")` scripted against the fast fixtures for the
score-only path and one Bayesian path; the generated script runs.
(b) The pack pasted cold into a plain chat model (Haiku or Sonnet via TaxaTools::call_api)
with a scripted "naive user" transcript; judge whether it reaches a correct plan and
asks for the right files. Record results in TaxaWizard/CLAUDE.md.
