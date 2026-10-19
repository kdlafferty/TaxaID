# CLAUDE.md -- TaxaLikely

Turning match scores into likelihoods with a hierarchical Bayesian model, plus reference-coverage auditing.

Ecosystem-level context is in the repository root's CLAUDE.md, which is auto-loaded
from any package subdirectory.

## Development history

The narrative history of this package -- session notes, past decisions and the
reasoning behind them -- lives in the TaxaID_dev repository at
`ecosystem_docs/session_notes/TaxaLikely_CLAUDE_2026-10.md`. This file carries current
state only.

## Exported functions (33)

| Function | Purpose |
|---|---|
| `annotate_reference_support` | Annotate Calls With How Much Reference Data Stood Behind Them |
| `apply_coverage_constraints` | Apply taxonomic completeness constraints to likelihood results |
| `assign_scores` | Assign score_likelihood values to a hypotheses data frame |
| `audit_acoustic_coverage` | Audit Acoustic Reference Coverage for a Species List |
| `audit_barcode_coverage` | Identify unreferenced species for barcode-based taxonomic assignment |
| `audit_inat_coverage` | Audit iNaturalist Reference Coverage for a Species List |
| `audit_reference_coverage` | Audit reference database taxonomic completeness via NCBI taxonomy |
| `build_sequence_matrix` | Build a pairwise match-score matrix from reference sequences |
| `calibrate_query_noise` | Calibrate a trained likelihood model to real query-vs-reference behavior |
| `check_cross_genus_sampling_noise` | How Much Does the Random Cross-Genus Draw Move the Estimate? |
| `compute_rank_thresholds` | Derive marker-specific rank_thresholds via per-rank Youden's J |
| `detect_suppressed_candidates` | Detect pipeline rules that suppress candidate rows in a match object |
| `estimate_sequence_matrix_size` | Predict the memory a sequence matrix will need, for a grid of caps |
| `evaluate_likelihoods` | Convert match scores to likelihoods for all queries |
| `expand_unreferenced_hypotheses` | Expand unreferenced hypotheses from genus/family level to named species |
| `fetch_bold_reference_sequences` | Fetch reference sequences from BOLD Systems for model building |
| `fetch_ncbi_reference_sequences` | Fetch reference sequences from NCBI for model building |
| `fetch_xc_recording_locations` | Fetch per-recording locations from Xeno-canto for one or more species |
| `filter_top_hypotheses` | Keep only the finest-rank specific candidates per query |
| `infer_exclude_predicted` | Infer whether predicted sequences were excluded from the BLAST reference |
| `interpret_model` | Summarise a trained likelihood model |
| `match_reference_region` | Trim reference sequences to the region the study's ESVs cover |
| `read_crabs_output` | Read a CRABS-formatted reference database |
| `read_reference_fasta` | Read a local FASTA file into a reference data frame |
| `report_likelihood` | Generate a Report Section for Likelihood Estimation |
| `restore_suppressed_candidates` | Restore candidates suppressed by upstream pipeline rules |
| `subset_local_database` | Subset a Large Local Reference Database by Taxon |
| `suggest_unreferenced_species` | Suggest Unreferenced Species Using an LLM |
| `taxalikely_clear_cache` | Report and clear TaxaLikely's on-disk cache |
| `train_likelihood_model` | Train the hierarchical likelihood model on reference-vs-reference scores |
| `trim_to_amplicon` | Extract the amplicon region from over-length reference sequences (in-silico PCR) |
| `unreferenced_candidates` | Add unreferenced taxon placeholder rows to a match object |
| `write_reference_fasta` | Write a Reference Data Frame to FASTA Format |

## Current behaviour worth knowing

- An unreferenced species is named on its OWN genus's ring where this unit has one, rather than on a borrowed family ring. A genus that is referenced but has no ring here is withheld instead of being given someone else's; only a genus with no references at all falls back to the family ring.
- Each unit carries `best_identity`, `best_identity_rank` and `poor_absolute_fit`. These answer a different question from the likelihood ratio: the ratio says which hypothesis fits best relative to the others, `poor_absolute_fit` says the winner sits poorly against its own trained distribution. A unit can win decisively and still be flagged.
- `apply_coverage_constraints()` defaults to `constraint_behavior = "relabel"`, which sets a marker and leaves likelihoods unchanged; `TaxaAssign::compute_posterior()` is what moves the placeholder's posterior onto the genus's referenced species.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
