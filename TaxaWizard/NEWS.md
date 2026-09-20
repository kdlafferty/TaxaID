# TaxaWizard 0.1.0

## 2026-09-19 / 2026-09-20

* Generated scripts no longer replay a stale result when you edit a parameter.
  Each step now stores a signature beside its checkpoint -- a digest of the
  step's own code plus the values of the parameters that step actually reads --
  and a checkpoint is reused only when that signature still matches. A step
  whose inputs changed also clears every later checkpoint, since those were
  computed from its old output. Previously the cache was keyed on the step
  NUMBER alone, so editing a parameter and re-running printed the old answer
  under the new parameters with no warning, and the outer existence check also
  short-circuited `TaxaFetch`'s content-addressed GBIF cache before it could
  notice the query had changed. `.append_to_script()` widens the new
  `.workflow_params` list the same way it widens Step 0.
* `sniff_input()` now runs on paths containing spaces. `.detect_paths_in_text()`
  matched only whitespace-free tokens, so an unquoted path through a folder
  such as `My Drive` was never inspected and `{{SNIFF_RESULT}}` silently
  degraded to "nothing was inspected". Detection now also anchors on a
  data-file extension and allows interior spaces, and trims trailing sentence
  punctuation; `file.exists()` still adjudicates, so prose is not mistaken for
  a path.
* An edge id invented by the LLM no longer reaches a generated script's Step 0.
  `.generate_script()` and `.widen_step0_edges()` filter through
  `.keep_known_edges()`, which warns rather than dropping silently and falls
  back to `edges = NULL` when every id is dropped -- an empty `c()` would check
  nothing while looking like a pass.
* `inst/graph/snippets/dist_to_priors_by_group.R` calibrated the kernel
  bandwidth on POOLED occurrences and then passed `sampling_group_col` to a
  per-group `estimate_kernel_priors()`, so lambda was fitted on one pooled
  composition and handed to a per-group estimate. Both calls now receive the
  same `sampling_group_col`. Both kernel snippets also widen `lambda_grid` to
  `c(1, 2, 5, 10, 25, 50, 100)` -- the previous `c(25, 50, 100, 200)` could not
  represent the 10 km optimum production measured -- and now report the
  kernel's margin over the `regional` and `nearest_block` references, so a
  reader can see whether the kernel beats not having one.
* The prompt pack's equality test no longer compares the pack's own generation
  DATE bytewise, which made it fail every day on the clock alone. The stamp is
  normalised out of the comparison and asserted separately to still be present.

## 2026-09-18

* The workflow interview now consumes the setup checker. `workflow_create()`
  runs `workflow_check()` before the conversation starts and shows you anything
  missing; the classify prompt receives that report (`{{SETUP_STATUS}}`) and, for
  any path in your message that exists on disk, a `sniff_input()` result
  (`{{SNIFF_RESULT}}`); the parameterize prompt receives
  `workflow_check(edges = <selected path>)` (`{{PATH_REQUIREMENTS}}`) so the
  assistant can tell you what to set up in the same reply as the workflow. Only
  rows needing attention are rendered, and key rows report set/unset, never a
  value.
* Appending to an existing generated script now widens that script's Step 0
  `workflow_check(edges = ...)` call to the union of the old and new edges,
  rather than leaving it stale or writing a second check block
  (`.widen_step0_edges()`).
* Fixed: `.pack_render_task()` skipped the bracketed-placeholder map for the
  classify phase, so a newly added classify placeholder shipped as a raw
  `{{TOKEN}}` in the exported pack.
* Fixed: registry text varied with the global `useFancyQuotes` option, which
  meant an ambient setting could decide whether the pack's byte-for-byte
  equality test passed. Pinned off while rendering Rd; `REGISTRY_SCHEMA` is
  now 3.
* `R/registry.R` parses Rd `\arguments` structurally (new internal
  `.rd_arguments()` / `.rd_text()`) instead of re-parsing `tools::Rd2txt()`
  output. `Rd2txt()` right-aligns argument terms into a column, and the
  previous parser treated a leading-whitespace chunk as a continuation of
  the item above it, so every term narrower than the widest one lost its
  documentation and had its text appended to its neighbour's. Across the
  eight installed packages this affected 318 of 1387 parameters (no doc at
  all) plus 233 survivors carrying a lost neighbour's text; argument doc
  coverage is now 1387/1387. New `REGISTRY_SCHEMA` constant is part of the
  registry cache file name, so a future parsing change invalidates caches
  that the package version and `Built` date alone would not.
* New (internal) `.validate_snippets()` in `R/validate.R`: AST-walks every
  `inst/graph/snippets/*.R` template against the installed TaxaID packages
  and reports `not_exported` (a `Pkg::fn()` call where `fn` is not exported
  by `Pkg`), `stale_argument` (a named argument absent from the installed
  function's real formals, skipped for functions taking `...`),
  `parse_error` (a snippet that does not parse once its `{{placeholder}}`
  tokens are substituted), or `unknown_bare_call` (a bare call that resolves
  to neither base/utils/stats nor a TaxaID export -- reported at warn
  severity, not a drift failure). New `test-validate.R` asserts zero
  `not_exported`/`stale_argument`/`parse_error` across every real snippet --
  found and fixed one real drift: `dist_to_priors_by_group.R` called
  `TaxaTools::verify_taxon_names(priors, taxon_col = "taxon_name")`, a
  signature that no longer exists (real formals are `name_list`,
  `backbone_id`, ...); it also discarded `priors` by reassigning it to the
  verification result. Fixed to call with `name_list`/`backbone_id` and no
  longer clobber `priors`.
* Tier-B fallback: `.get_path_context()` now runs `.validate_snippets()`
  over the selected path's edges and substitutes, for any edge whose
  snippet fails validation, a generated block (the edge's label/description
  plus full registry documentation for that edge's `functions` and every
  export of its `packages`) ending in the instruction to write the step
  from that documentation, named arguments only, and mark it
  `validated: false`. `.describe_paths()` appends
  "(one or more unvalidated steps)" to a path header when any of its edges
  would trigger the fallback. The DAG step schema (`phase_parameterize.md`)
  gains an optional `validated` boolean (default `true`); `.generate_script()`
  (fresh scripts and `.append_to_script()` extensions) prints
  `# WARNING: this step was generated without a validated snippet; review
  before running` directly above any step with `validated: false`.
* `inst/metadata/*.json` (94 hand-maintained function-signature entries) and
  `R/metadata.R` deleted. New `R/registry.R` / `workflow_registry()`
  introspects the installed TaxaID packages at runtime (`getNamespaceExports()`
  / `formals()` / `tools::Rd_db()`), cached under
  `tools::R_user_dir("TaxaWizard", "cache")` keyed on package version AND
  `packageDescription()$Built`. Every consumer (`workflow_engine()`,
  `.build_phase_prompt()`, `.get_path_context()`, `.extract_param_docs()`,
  `workflow_create()`) now reads the registry instead of the old JSON.
* `workflow_engine(metadata = )` renamed to `workflow_engine(registry = )`;
  `metadata` still accepted with a deprecation warning.
* `inst/prompts/system_prompt.md` and `phase_parameterize.md`: removed every
  sentence that hard-coded a specific function's parameter names or package
  (these are now sourced solely from the generated FUNCTION
  REGISTRY / PARAMETER DOCUMENTATION blocks, so they cannot drift out of
  sync with the installed packages the way hand-typed prompt text could).
* `diagnostics/taxawizard_metadata_audit.R` deleted (nothing left to audit).
* New `tests/testthat/test-registry.R` replaces
  `test-metadata-covers-workflow-functions.R`.

* New `workflow_check(edges = NULL, verbose = TRUE)`: reports R version,
  the 8 TaxaID packages (+ Bioconductor `Biostrings`/`DECIPHER`, optional
  `rBLAST`/`shiny`), each package's on-disk cache, and -- narrowed to a set
  of workflow-graph edge ids when supplied -- the API keys, network
  services, and binaries those steps need. Returns a `"taxaid_check"`
  data.frame (`component`, `category`, `status`, `detail`, `fix`) with a
  `print.taxaid_check()` method. Key checks report set/unset only, and
  whether a set key was found in `~/.Renviron` vs the session only (the
  README's documented restart footgun) -- a key's value is never printed,
  logged, or returned. `options(TaxaWizard.offline = TRUE)` skips the
  live network checks.
* New `inst/setup/requirements.json`: the hand-kept table backing
  `workflow_check()` -- every API key (`ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,
  `OPENAI_API_KEY`, `AZURE_OPENAI_API_KEY`, `ENTREZ_KEY`/`NCBI_API_KEY`,
  `GBIF_USER`/`GBIF_PWD`/`GBIF_EMAIL`, `INAT_API_TOKEN`, `OPENALEX_API_KEY`,
  `XC_API_KEY`, `XAI_API_KEY`), Bioconductor/optional package, binary
  (`blastn`), and network target the ecosystem uses, each tagged `"missing"`
  (blocking) or `"warn"` (recommended). `ENTREZ_KEY` and `GBIF_USER`/`PWD`/
  `EMAIL` are `"warn"`: NCBI and GBIF search both work without them, just
  slower/search-only.
* Every edge in `inst/graph/workflow_graph.json` (33 edges) now carries a
  `requires` array of requirement tokens (`key:...`, `net:...`, `pkg:...`,
  `bin:...`), derived from reading each edge's snippet and the real
  functions/env vars it touches -- e.g. `seq_to_match` requires NCBI/BLAST,
  `taxa_to_occ` requires GBIF, `refs_to_matrix` requires Bioconductor;
  purely offline edges (`match_to_taxa`, `matrix_to_model`,
  `match_to_consensus_score`, ...) require nothing.
* New `sniff_input(path)`: guesses which `workflow_graph.json` input node a
  file looks like (FASTA, a DADA2 seqtab `.rds`, BirdNET/Animl/
  iNaturalist-CV/SpeciesNet output, a CRABS or FASTA+taxonomy reference
  database, an occurrence/match/taxon/consensus table) from the real header
  signatures the `TaxaMatch`/`TaxaLikely` `read_*()` functions expect.
  Reads at most 50 lines / 1 MB; never errors on an unreadable file (returns
  `node_id = NA` with an explanatory `evidence` string instead).
* Generated scripts (`.generate_script()`) now emit a "Step 0" setup check
  before Step 1: `TaxaWizard::workflow_check(edges = c(<the dag's own edge
  ids>))`, `stop()`-ing with a pointer to the fix column if any row is
  `"missing"`. Falls back to `edges = NULL` when a step's `edge_id` is
  absent (the legacy free-form DAG shape).
* New `R/pack.R` / `workflow_export_prompts(dir = "taxaid_prompts",
  overwrite = FALSE, placeholder_setup_report = FALSE)`: exports a
  self-contained "prompt pack" any LLM can be pointed at -- an agentic coding
  tool that reads files and runs R directly, or a plain chat window where the
  user pastes files back and forth -- to design a TaxaID workflow with no
  TaxaWizard install or engine API key needed. `START_HERE.md` and
  `tasks/handoff_template.md` are copied verbatim from
  `inst/prompts/pack/` (hand-written, P5); `CLAUDE.md`/`AGENTS.md` are three
  lines pointing an agentic tool at `START_HERE.md`; `CONTEXT_TaxaID.md`
  (<= 400 lines) and one `CONTEXT_<Package>.md` per TaxaID package are
  generated from `workflow_registry()`, the workflow graph, and
  `inst/setup/requirements.json` -- packages table, node types, the graph as
  a text adjacency list, the canonical pipelines (read live from
  `system_prompt.md`'s "Pipeline Awareness" section, never pasted), every
  exported function's signature/docs/params table, and each package's
  README Quick Start section when the source repo is reachable;
  `SETUP_REPORT.md` is `workflow_check()`'s report for the generating
  machine (or a placeholder); `tasks/classify.md`/`path_select.md`/
  `parameterize.md`/`error_fix.md` are the `inst/prompts/phase_*.md`
  templates with statically-resolvable placeholders filled and every
  conversation-dependent placeholder replaced by a bracketed instruction,
  with the JSON-only response-format requirement stripped (a chat LLM
  answers in prose). The rendered copy is committed at the repository root,
  `llm_prompts/` (`placeholder_setup_report = TRUE`), refreshed by
  `ecosystem_docs/readmes/render_readmes.R`'s new final step; new
  `tests/testthat/test-pack.R` asserts the two agree byte-for-byte.

## 2026-09-13

* `.extract_param_docs()` now reads the metadata `inputs` key -- previously
  every function rendered as "(no params)".

## 2026-09-09

* GLMM-path edges `std_to_dist`, `dist_to_priors`, `taxa_to_priors_wrapper`
  deleted; `dist_to_priors_by_group` repointed to `estimate_kernel_priors()`.

## 2026-09-08

* `matrix_to_clean` rewritten around
  `TaxaMatch::corroborate_references_locally()`/`evaluate_reference_accessions()`.

## 2026-09-07

* Metadata resynced against current signatures (1b1af81).
* New `std_to_priors_kernel` edge and reference-screening snippets (4aff5a1).
* Generated files may contain backslashes; app allow-list hardened (1ba54d8).
