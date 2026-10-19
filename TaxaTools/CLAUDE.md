# CLAUDE.md -- TaxaTools

Shared taxonomic-name utilities and the LLM provider interface. Dependency of every other package.

Ecosystem-level context is in the repository root's CLAUDE.md, which is auto-loaded
from any package subdirectory.

## Development history

The narrative history of this package -- session notes, past decisions and the
reasoning behind them -- lives in the TaxaID_dev repository at
`ecosystem_docs/session_notes/TaxaTools_CLAUDE_2026-10.md`. This file carries current
state only.

## Exported functions (57)

| Function | Purpose |
|---|---|
| `%||%` | Null-coalescing operator |
| `assemble_report` | Assemble Multiple Report Sections into a Unified Report |
| `assign_sampling_group` | Assign Sampling Groups from Taxonomic Rank Columns |
| `barcode_length_defaults` | Default NCBI Nucleotide Length Ranges by Barcode Type |
| `barcode_primer_defaults` | Default PCR Primer Sequences by Barcode/Primer-Set Name |
| `build_report_context` | Build a Report Context Object |
| `cache_ok` | Is a cache file usable, given the inputs it derives from? |
| `call_anthropic_api` | Call the Anthropic API with a Single Prompt String |
| `call_api` | Call Any Configured LLM with a Single Prompt String |
| `call_azure_openai_api` | Call the Azure OpenAI API with a Single Prompt String |
| `call_gemini_api` | Call the Google Gemini API with a Single Prompt String |
| `call_ollama_api` | Call a Local Ollama Model with a Single Prompt String |
| `call_openai_api` | Call the OpenAI Chat Completions API with a Single Prompt String |
| `census_genus_species` | Census described species within genera (or higher ranks) via GBIF backbone |
| `change_backbone` | Translate Taxon Names Between Taxonomic Backbones |
| `check_lineage_agreement` | Check whether a returned lineage agrees with a declared one |
| `check_taxaid_manifest` | Check the Installed TaxaID Code Against a Recorded Manifest |
| `clean_taxon_names` | Extract and Clean Taxon Names from a Character Vector |
| `common_to_scientific` | Convert Common Names to Scientific Names |
| `create_taxon_names` | Create Most Specific Taxon Name Column |
| `default_sampling_scheme` | Default Sampling-Group Classification Scheme |
| `define_search_polygon` | Define a Search Polygon Interactively |
| `detect_ranks` | Detect Rank Columns Present in a Data Frame |
| `draft_methods_text` | Draft Methods Text from R Code |
| `draft_results_text` | Draft Results Text from R Objects |
| `escalate_taxonomic_rank` | Escalate a Taxon to the Next Coarser Rank |
| `extended_ranks` | Extended Rank Order Including Intermediate Ranks (Coarse to Fine) |
| `fetch_worms_attributes` | Fetch WoRMS Taxon Attributes by Name |
| `fill_higher_ranks` | Fill Higher Taxonomic Ranks from Local Data and Backbone APIs |
| `find_taxonomy_conflicts` | Find Taxonomic Conflicts in a Taxonomy Data Frame |
| `is_plausible_binomial` | Test Whether Strings Are Plausible Species Binomials |
| `list_cache_files` | List files in a directory matching cache-file patterns |
| `list_models` | List Current LLM Model Tier Assignments |
| `new_report_section` | Create a Report Section Object |
| `parse_classification_path` | Parse a Rank Value from a Pipe-Delimited Classification Path |
| `prompt_api` | Submit a Multi-Chunk LLM Prompt to Any Provider |
| `prompt_manual` | Submit a Prompt Manually via Any LLM Interface |
| `read_llm_response` | Read Saved LLM Response File(s) |
| `refresh_models` | Refresh LLM Model Discovery from Provider APIs |
| `register_provider` | Register a Custom OpenAI-Compatible LLM Provider |
| `rename_cols` | Rename Data Frame Columns to a Target Convention |
| `report_and_clear_cache` | Report and optionally delete a set of cache files |
| `reset_token_usage` | Reset the LLM Token Usage Ledger |
| `resolve_barcode_lengths` | Resolve Barcode Length Bounds from a Barcode Term |
| `resolve_barcode_marker` | Resolve a Primer-Variant Barcode Term to the Marker It Amplifies |
| `resolve_barcode_primers` | Resolve Primer Sequences from a Barcode/Primer-Set Term |
| `resolve_ncbi_taxid` | Resolve a taxon name to one disambiguated NCBI taxonomy id |
| `scientific_to_common` | Convert Scientific Names to Common Names |
| `set_model` | Pin a Specific Model Version for Reproducibility |
| `standard_ranks` | Standard Linnaean Rank Order (Coarse to Fine) |
| `taxaid_build_manifest` | Record Which TaxaID Code a Run Is Using |
| `taxaid_cache_report` | Report every TaxaID cache on this machine |
| `taxatools_clear_cache` | Report and clear the TaxaTools on-disk caches |
| `to_faire` | Export a TaxaID Data Frame in FAIRe Checklist Format |
| `token_usage` | Summarise LLM Token Usage for the Current Session |
| `verify_taxon_names` | Verify Taxon Names Against a Taxonomic Backbone |
| `write_taxaid_manifest` | Write a TaxaID Build Manifest |

## Current behaviour worth knowing

- `verify_taxon_names()` takes `input_rank` (the rank the caller means each name at) and `lineage` (a pipe-delimited ancestor string). A name is not a key: one string can match several unrelated NCBI nodes, so these two disambiguate, and an unresolved ambiguity goes to `decisions` or stops rather than being guessed.
- `fill_higher_ranks()` takes `input_rank` for the same reason and `fill_ranks` for which ranks to fill (`"family"` by default).
- `call_api()` takes `temperature`, defaulting to `NULL`, which sends no temperature field and keeps the provider's own default. Some current models reject the parameter outright, which is why the default sends nothing.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
