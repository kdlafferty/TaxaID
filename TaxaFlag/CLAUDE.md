# CLAUDE.md -- TaxaFlag

Flagging anomalous detections: contamination, transport, taxonomic scope, handler artefacts, and expert review.

Ecosystem-level context is in the repository root's CLAUDE.md, which is auto-loaded
from any package subdirectory.

## Development history

The narrative history of this package -- session notes, past decisions and the
reasoning behind them -- lives in the TaxaID_dev repository at
`ecosystem_docs/session_notes/TaxaFlag_CLAUDE_2026-10.md`. This file carries current
state only.

## Exported functions (17)

| Function | Purpose |
|---|---|
| `add_posthoc_assessment` | Add post-hoc plausibility and discrimination assessments to a consensus data frame |
| `check_gbif_tile_range` | Spatial-isolation signal for a taxon from GBIF's occurrence-density map tiles |
| `classify_sample_identity` | Gate Samples on Whether They Look Like Their Label |
| `compute_local_occurrence_distance` | Distance from a query point to the nearest already-fetched GBIF occurrence |
| `flag_backbone_conflicts` | Flag Taxa Whose Backbone Placement Disagrees With Itself |
| `flag_contaminant` | Flag Potential Contaminants by Comparison to Control Samples |
| `flag_failed_libraries` | Flag Sequencing Libraries and Runs That Failed |
| `flag_handler` | Flag Detections Near Start or End of a Sampling Period |
| `flag_hopped_detections` | Flag Detections Explained by Read Spillover Between Samples on a Run |
| `flag_watch_candidates` | Flag observations where a watch-list species outscores the consensus winner |
| `report_flags` | Generate a Report Section for Quality Flagging |
| `review_assignments` | LLM Expert Review of Taxonomic Assignments |
| `review_sample_identity` | LLM Advice on Samples That Do Not Look Like Their Label |
| `review_spatial_context` | Interactive Spatial Review of Consensus Taxa |
| `screen_assignments` | Screen reviewed assignments for identity and presence problems |
| `taxaflag_clear_cache` | Report and clear TaxaFlag's on-disk caches |
| `validate_controls` | Validate That Control Samples Actually Look Like Controls |

## Current behaviour worth knowing

- `screen_assignments()` is the post-hoc identity/presence screen. It FLAGS ONLY and never drops a row. Identity is match plus geography (rules I1-I4); presence is habitat and scope. It emits `suggested_action` and an information-only `isolated_geography_unlikely`.
- `screen_assignments()` carries `attr(, "rule_counts")`: a fixed nine-row table, `n_rows = 0` for a rule evaluated that fired on nothing and `NA` with `evaluated = FALSE` for one that could not be evaluated. So "did not fire" and "was not evaluated" are distinguishable. It is an attribute, so a dplyr verb drops it -- read it off the call.
- `relative_score_gap` defaults to 0.25. That is a chosen value, not a calibrated one, and the roxygen says so; the fired count exists so a dataset where it bites announces itself.
- `review_assignments(sites = , site_col = )` gives site-aware geography: a study sites block in the prompt and a parsed per-taxon range rule, yielding `llm_geographic_plausibility_site` and `attr(, "geographic_by_site")`. With `sites = NULL` the prompt, the cache key and the output columns are byte-identical to a call without the argument, so existing caches are not orphaned.
- The review is advisory: it writes `llm_review_flag` and never removes a row.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
