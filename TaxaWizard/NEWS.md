# TaxaWizard 0.1.0

## 2026-09-18

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
