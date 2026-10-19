# CLAUDE.md -- TaxaHabitat

Habitat assignment via LLM, and spatial QA/QC of occurrence records.

Ecosystem-level context is in the repository root's CLAUDE.md, which is auto-loaded
from any package subdirectory.

## Development history

The narrative history of this package -- session notes, past decisions and the
reasoning behind them -- lives in the TaxaID_dev repository at
`ecosystem_docs/session_notes/TaxaHabitat_CLAUDE_2026-10.md`. This file carries current
state only.

## Exported functions (15)

| Function | Purpose |
|---|---|
| `apply_spatial_review_decisions` | Apply saved spatial-flag decisions before (or instead of) the gadget |
| `assign_habitat_biological` | Assign Habitat to Points Using Biological Consensus |
| `build_habitat_lookup` | Build a per-taxon habitat lookup with an on-disk cache |
| `build_habitat_prompt` | Build a Habitat Assignment Prompt |
| `consensus_habitat` | Compute Assemblage-Level Consensus Habitat |
| `example_habitat_scheme` | Example Custom Habitat Scheme |
| `flag_habitat_inconsistencies` | Flag Spatially Inconsistent Habitat Assignments |
| `flag_institution_candidates` | Tier Institution-Proximity Flags by Suspicion |
| `parse_hierarchical_habitat_response` | Parse a Weighted Habitat Response from an LLM |
| `report_habitat` | Generate a Report Section for Habitat Assignment |
| `resolve_habitat_by_geography` | Resolve Unassigned Habitats From Point Geography |
| `review_institution_flags` | Review Institution-Proximity Flags Interactively |
| `review_spatial_flags` | Review and Correct Spatial Flags Interactively |
| `save_spatial_review_decisions` | Save a reviewer's spatial-flag decisions |
| `taxahabitat_clear_cache` | Report and clear TaxaHabitat's on-disk habitat-verdict cache |

## Current behaviour worth knowing

- `build_habitat_lookup()` takes `compound_rule`. A taxon the scheme places in more than one habitat gets its weight from its parts: `"sum"` (the default, capped at 1) treats them as alternatives a record could fall in, `"max"` takes the strongest part. A scheme that does not split a habitat has nothing to combine and the two agree.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
