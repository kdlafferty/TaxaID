# CLAUDE.md -- TaxaExpect

Occurrence and habitat data into an expected-occurrence prior (theta) for a taxon at a place.

Ecosystem-level context is in the repository root's CLAUDE.md, which is auto-loaded
from any package subdirectory.

## Development history

The narrative history of this package -- session notes, past decisions and the
reasoning behind them -- lives in the TaxaID_dev repository at
`ecosystem_docs/session_notes/TaxaExpect_CLAUDE_2026-10.md`. This file carries current
state only.

## Exported functions (17)

| Function | Purpose |
|---|---|
| `apply_undetected_evidence` | Elevate the dark-diversity floor prior for species with external occurrence-plausibility evidenc |
| `calibrate_kernel_bandwidth` | Calibrate kernel bandwidths by leave-one-block-out composition prediction |
| `condition_evidence_on_habitat` | Condition Presence Evidence on the Site Habitat |
| `estimate_kernel_priors` | Estimate site priors by distance-kernel weighting of occurrence records |
| `estimate_kernel_priors_from_counts` | Estimate site priors from GBIF band counts (no record download) |
| `fit_regional_presence_curve` | Fit a distance-to-presence curve for regional-proximity weights |
| `generate_domestic_food_priors` | Generate priors for domestic, commensal, and food-associated species |
| `generate_inat_range_evidence` | Evidence rows for species inside their iNaturalist range polygon |
| `generate_invasive_watch_evidence` | Evidence rows for a user-supplied invasive/nonindigenous watch list |
| `generate_presence_curve_evidence` | Price unobserved candidates on the presence-distance curve |
| `generate_regional_proximity_evidence` | Evidence rows for species with a real GBIF record just outside the study bbox |
| `generate_uncertain_habitat_evidence` | Presence Evidence From Records Whose Habitat Could Not Be Resolved |
| `generate_undetected_diversity` | Generate Priors for Undetected Species |
| `generate_user_specified_evidence` | User-specified presence evidence for species of special concern |
| `kernel_budget_sensitivity` | Sensitivity of a kernel Good-Turing budget to its counting radius |
| `plot_theta_surface` | Evaluate the kernel-prior estimator on a spatial lattice (KDE prior field) |
| `report_priors` | Generate a Report Section for Prior Estimation |

## Current behaviour worth knowing

- Habitat-uncertain records carry their own weights rather than being dropped or treated as certain.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
