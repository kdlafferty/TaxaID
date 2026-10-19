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

- An unreferenced species is named only on its OWN genus's ring. A species whose genus
  has no ring here is NEVER named from a family ring: it is listed in
  `attr(result, "unreferenced_withheld")` with `reason` either
  `"genus_referenced_unmatched"` (the genus has references for this marker that did
  not match the read) or `"no_own_genus_ring"` (it has none), and the generic family
  row still stands for it.
- Each unit carries `best_identity` (the best raw match identity among its
  `specific_candidate` rows, percent scale), `best_identity_rank` (the finest rank whose
  marker-specific Youden's-J threshold it reaches) and `poor_absolute_fit` (TRUE when it
  reaches none). They are a FLAG ONLY and never change a likelihood or which hypothesis
  wins: `score_likelihood` is normalised to the unit maximum, so an 86% identity match
  can score 0.998 when it is the best of a bad set. A unit can win decisively and still
  be flagged.
- `apply_coverage_constraints()` defaults to `constraint_behavior = "relabel"`, which
  relabels the row `unresolved_species` and leaves likelihoods unchanged;
  `TaxaAssign::compute_posterior()` then moves that row's posterior onto the genus's
  referenced species, pro rata by their posteriors.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
