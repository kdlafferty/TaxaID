# TaxaWizard 0.1.0

## 2026-09-18

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
