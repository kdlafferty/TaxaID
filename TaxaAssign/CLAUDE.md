# CLAUDE.md -- TaxaAssign

Posterior probability for a taxonomic assignment from a likelihood and a prior, and consensus over hypotheses.

Ecosystem-level context is in the repository root's CLAUDE.md, which is auto-loaded
from any package subdirectory.

## Development history

The narrative history of this package -- session notes, past decisions and the
reasoning behind them -- lives in the TaxaID_dev repository at
`ecosystem_docs/session_notes/TaxaAssign_CLAUDE_2026-10.md`. This file carries current
state only.

## Exported functions (14)

| Function | Purpose |
|---|---|
| `add_slash_taxon` | Add Slash Taxon Name and Irreducibility Flag to a Consensus Dataframe |
| `add_unreferenced_prior_mass` | Add the prior mass of unreferenced local relatives to generic hypotheses |
| `adjust_inat_range_priors` | Elevate priors for iNaturalist range-supported unobserved taxa |
| `assign_taxa_llm` | Assign Taxa Using an LLM-Approximated Bayesian Pipeline |
| `build_context` | Build Site Context from Taxon Names |
| `combine_multisite_priors` | Combine Per-Site Priors for Multi-Site Observations |
| `compute_group_priors` | Aggregate occurrence-model shares to genus/family level |
| `compute_posterior` | Compute Bayesian Posterior Probabilities |
| `generate_report` | Generate Publication-Ready Report from TaxaAssign Output |
| `join_priors` | Join Likelihoods to TaxaExpect Priors |
| `posterior_consensus` | Derive Consensus Taxonomy from a Posterior Dataframe |
| `report_assign` | Generate a Report Section for Taxonomic Assignment |
| `score_consensus` | Derive Consensus Taxonomy from Raw Match Scores |
| `update_prior_from_consensus` | Update Priors from Consensus Assignments and Recompute Posteriors |

## Current behaviour worth knowing

- `posterior_consensus(pool_tail = )` defaults to `FALSE`, dropping hypotheses below `min_posterior` and measuring `cumulative_threshold` against what remains. `TRUE` gathers them into one tail block measured against the total named mass. Pooled rows carry `pooled_n`, `pooled_mass` and `pooled_taxa`, with the row set in the `"pooled_rows"` attribute.
- `add_unreferenced_prior_mass(named_rows = )` defaults to `FALSE`, folding a ring row's recorded unreferenced local species into that row's prior. `TRUE` emits one species-rank row each instead, so such a species can be reported by name rather than as anonymous mass.
- `consensus_method = "credible_node"` with `robust_prior_s = 0` and `cross_phylum_eps = 0` is the weighted LCA (node summing). The PACKAGE default remains `"lca"`; the canonical workflow template sets the weighted form explicitly.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
