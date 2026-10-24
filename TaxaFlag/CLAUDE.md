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
- `review_assignments()` asks the LLM for a PROBABILITY per judgement, not a category, and derives `llm_habitat_plausibility`, `llm_scope_plausibility`, `llm_contamination_risk`, `llm_geographic_plausibility` and `llm_geographic_plausibility_site` from it in code. Cuts: `unlikely < 0.10 <= possible < 0.70 <= likely`; contamination `low < 0.20 <= moderate < 0.70 <= high`. The probabilities are also returned, as `llm_p_*`. Everything downstream -- `screen_assignments()`, `report_flags()`, the workflow template -- consumes the same categorical columns as before.
- The cut is applied AFTER the cache, so a cache entry holds the probability and a changed cut re-reads it with no new LLM calls. The cuts are therefore NOT in the cache key.
- Habitat is living conditions only and scope is the kind of organism and its depth or zone only; whether the taxon occurs in the region is geography in both cases. `llm_p_transported` carries detectability separately from residency. The habitat and target-group wording comes from `context$habitat` and `target_group`, so no study is built in.
- `review_assignments(sites = , site_col = )` gives site-aware geography: a study sites block in the prompt, each taxon line told which sites it was detected at, and the model asked for its range LIMITS (`range_known`, `range_south_lat`, `range_north_lat`, `sites_outside_range`, `p_inside_range`, `p_outside_range`). The site probability is computed from them here, and the study-wide one is the MAXIMUM over the taxon's detected sites. Yields `llm_geographic_plausibility_site`, `llm_p_geographic_site` and `attr(, "geographic_by_site")`. Latitude limits suit a north-south study; an east-west or single-latitude study must use `sites_outside_range`, which works but is not measured.
- The review is shown DNA EVIDENCE and the study's own DESIGN, and no text derived from occurrence records. SHOWN by default: `best_identity_col` (the identity for EVERY taxon, not only a poor fit), `poor_absolute_fit_col`, `consensus_discrimination_col` (INDISTINGUISHABLE, a tail probability over match scores), `consensus_provenance` (the base "NO reference sequence" only), `winner_rank_expanded_col` (reworded sequence-only: "the sequence does not resolve this call to species"). NOT shown: `consensus_posterior_col`, `winner_prior_col`, `plausible_posteriors_col`, `dist_nearest_occupied_km_col`, `patch_diameter_km_col`, `beyond_buffer_col`, the three `inat_*`. READ BUT NOT SHOWN: `consensus_plausibility_col` -- UNPRECEDENTED still populates `geographic_disagreement_basis` and never enters the prompt, which is the read-vs-show split done for one note. Still open for 1.1: the same split for the rest, and the candidate-set `"pipeline call: X (rank)"` note, which NO argument gates.
- The note defaults needed NO cache-key bump on their own -- the notes are columns of `taxa_info` and every column enters the key, so dropping them is a miss by itself. Two prompt changes DID force bumps (v7 -> v8 -> v9), both for the same reason: the bracket guideline is assembled per BATCH, so a taxon whose own key cannot move still gets a different prompt when its neighbours lose their notes. The notes are columns of `taxa_info` and every column of it enters the key, so dropping them is a miss by itself. `test-review_assignments.R` pins that.
- The review cache key is `v10`, and `geo_sites_v5` when `sites` is supplied. `model_label` is REQUIRED with a `cache_dir` and a caller-written `llm_fn`: all that can be seen of such a closure is its source, and a wrapper written `function(p, ...) call_api(p, model = MODEL, ...)` deparses to the variable NAME, so switching models would silently serve the first one's verdicts. Same for `review_sample_identity()`.
- Batches are built from a sort of the taxon labels, not the input row order, so two runs with the same taxa left to ask ask the same batches.
- `review_assignments()` is advisory: its `llm_*` ratings are columns and it never
  removes a row. The flag-only reporting pattern (`llm_review_flag`, expert
  keep/exclude, `review_flag_stands`) lives in the TaxaWizard workflow template, not
  in this package.

## Conventions

- Native pipe `|>`, never `%>%`.
- `utils::globalVariables()` first line of any file using NSE column names.
- Internal helpers take a `.` prefix and `@noRd`. Put them ABOVE the documented
  function's roxygen block: a helper between a block and its function steals that
  block, which has shipped an exported function unexported before now.
- `dplyr::if_else()`, not `ifelse()`, wherever either branch could be length 1.
- Run `devtools::document()` after any roxygen change, and `devtools::check()` after
  any substantive edit.
