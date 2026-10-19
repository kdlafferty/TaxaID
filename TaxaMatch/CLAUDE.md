# CLAUDE.md -- TaxaMatch

Sequence and classifier input, BLAST search, match standardisation, and reference-accession screening.

Ecosystem-level context is in the repository root's CLAUDE.md, which is auto-loaded
from any package subdirectory.

## Development history

The narrative history of this package -- session notes, past decisions and the
reasoning behind them -- lives in the TaxaID_dev repository at
`ecosystem_docs/session_notes/TaxaMatch_CLAUDE_2026-10.md`. This file carries current
state only.

## Exported functions (30)

| Function | Purpose |
|---|---|
| `add_lowest_consistent_rank` | Add lowest consistent rank to a match object |
| `assign_spatial_group` | Manually Assign a Spatial Group to a Set of Observations |
| `blast_sequences` | BLAST Sequences Against NCBI or a Local Database |
| `build_site_table` | Build a Unified Long-Format Site Table |
| `check_marker_mismatch` | Cross-Check a Reference Accession's Own Annotated Gene/Product Against an Expected Marker |
| `convert_taxonomy_backbone` | Convert Match Object Taxonomy to a Target Backbone |
| `corroborate_references_locally` | Corroborate Reference Labels From the Local Reference Set, Without BLAST |
| `evaluate_reference_accessions` | Evaluate Reference-Accession Quality via Unrestricted BLAST Comparison |
| `filter_redundant_hypotheses` | Filter Redundant Higher-Rank Hypotheses |
| `filter_sequences` | Filter Sequences by Length and Abundance |
| `flag_incongruent_references` | Annotate a Match Object with Reference-Accession Quality, Without Removing Anything |
| `group_observations_by_bbox` | Group Observations by User-Drawn Bounding Boxes |
| `investigate_flagged_accession` | Deep-Dive Verification for a Single Flagged Reference Accession |
| `investigate_flagged_accessions` | Deep-Dive Verification for a Batch of Flagged Reference Accessions |
| `join_event_site_metadata` | Join Event-Level Detections to a Site Metadata Table |
| `match_driving_accessions` | Which Reference Accessions Ever Drive a Likelihood? |
| `read_animl_output` | Read Animl Camera Trap Results into a Match Object |
| `read_birdnet_output` | Read BirdNET-Analyzer Results into a Match Object |
| `read_inaturalist_cv_output` | Read iNaturalist Computer Vision API Results into a Match Object |
| `read_sequence_table` | Read Sequence Data into a Tidy ASV Table |
| `read_speciesnet_output` | Read SpeciesNet Batch Classification Results into a Match Object |
| `refine_reference_verdicts` | Re-run Reference Verdicts With Each Partner Weighted by Its Own Trustworthiness |
| `remove_incongruent_references` | Remove Confidently-Incongruent Reference Accessions from a Match Object |
| `report_match` | Generate a Report Section for Sequence Matching |
| `resolve_review_overrides` | Derive Removal Overrides from an LLM Second-Look Review |
| `review_flagged_accessions` | LLM Second-Look Review of Flagged Reference Accessions |
| `score_image_inat` | Score images using the iNaturalist Computer Vision API |
| `score_reference_labels` | Score Reference Labels: a Numeric Label Confidence and a Categorical Action |
| `standardize_match_data` | Standardize Raw Match Data to Canonical Match Object |
| `verify_removal_candidates` | Verify Removal Candidates Against a Wider Evidence Window |

## Current behaviour worth knowing

- No behaviour changed this cycle.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
