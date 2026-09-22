# Fast test workflows

A full workflow run takes hours: thousands of observations and live NCBI,
GBIF and LLM calls. This directory holds small fixtures cut from real
production checkpoints, and short scripts that chain the same functions the
production workflows call, so a code change can be exercised in seconds. The
fixtures are real data, not synthetic, so they carry the edge cases that
matter (incongruent hierarchies, wide candidate sets, insufficient evidence,
downranking cases).

These scripts exercise code paths. Their numbers are not results.

## Files

| File | What it is |
|---|---|
| `build_fast_fixture.R` | General-purpose subsetter. Given a match-shaped or posterior-shaped checkpoint (one row per `observation_id` x candidate), it keeps every observation touching a flagged value in a chosen set of columns (`reference_action`, `hierarchy_flag`, `validity_flag` by default, skipped when absent), a stratified random baseline, and any observations you name. |
| `ptcon12s_fast_match_obj.rds` | Point Conception 12S match object: 374 observations, 1,259 rows. Companion model: `ptcon12s_fast_lik_model_calibrated.rds`. No priors checkpoint; the smoke test uses a flat placeholder prior and says so. |
| `run_fast_smoketest.R` | `evaluate_likelihoods()` -> `compute_posterior()` -> `posterior_consensus()` -> `add_slash_taxon()` on the Point Conception 12S fixture. About 3 seconds. |
| `greatlakes_fast_match_obj.rds` | Great Lakes 12S match object: 257 observations, 4,592 rows, including 78 *Perca flavescens* observations. Companion model: `greatlakes_fast_lik_model_calibrated.rds`. Flat placeholder prior, so the perch share posterior mass with congeners as expected. |
| `run_greatlakes_fast_smoketest.R` | Same chain on the Great Lakes fixture. About 6 seconds. |
| `mugu12s_fast_posterior_df.rds` | Mugu 12S `compute_posterior()` output with real kernel priors: 75 observations, 546 rows. |
| `run_mugu_fast_smoketest.R` | `posterior_consensus()` -> `add_slash_taxon()` on the Mugu fixture. Under a second. Every *Fundulus* observation resolves to *F. parvipinnis*. |
| `ptcon18s_fast_match_obj.rds` | Point Conception 18S match object, 200 observations. Companions: `ptcon18s_fast_lik_model_calibrated.rds` and `ptcon18s_fast_taxaexpect_priors.rds`, the real single-site kernel priors (`grid_id` `"Site_34.40_-120.40"`). |
| `run_ptcon18s_fast_smoketest.R` | The full chain with a real `join_priors()` step: `evaluate_likelihoods()` -> `join_priors()` -> `compute_posterior()` -> `posterior_consensus()` -> `add_slash_taxon()`. About 30 seconds. `join_priors()` may look up taxonomy for unmatched names, the one network call in this directory. |
| `ptcon12s_r2_fast_match_obj.rds` | A second, later Point Conception 12S run, curated around eleven known downranking cases. Companions: `ptcon12s_r2_fast_lik_model_calibrated.rds` and `ptcon12s_r2_fast_taxaexpect_priors.rds` (the whole priors table, 783 rows: 258 named-evidence and 37 anonymous `resident_undetected` rows, 479 `kernel_estimated`, 9 `transport`). Do not mix these with the `ptcon12s_fast_*` files; they are different runs. |
| `run_review_fixes_fast_check.R` | Exercises specific consensus and downranking options (`species_reference`, `downrank_requires_candidate`) against the 18S and 12S run-2 fixtures and prints before/after counts. A scoped check, not a smoke test: it reconstructs only the first stages of the pipeline, so cases that enter through `restore_suppressed_candidates()` or `expand_unreferenced_hypotheses()` in production do not reach a downrank event here. |

## Building a fixture

Run `build_fast_fixture.R` against a checkpoint that no workflow is currently
writing. Check the source file's modification time first; treat anything
touched in the last 30 minutes as live. Never point `output_path` at a
directory a running workflow reads from or writes to. A fixture needs
rebuilding only when the upstream checkpoint changes shape or content enough
to stop being representative, for example after a change to a column contract
such as the `prior_branch` labels.

## Known behaviour these fixtures expose

- `posterior_consensus()` cannot detect `rank_system` from an input with no
  taxonomy-rank columns (such as `evaluate_likelihoods()`'s own output, which
  carries only `taxon_name` and `taxon_name_rank`). Pass `rank_system`
  explicitly, as the smoke tests do.
- `add_slash_taxon()` warns when genus-only names reach its slash-name
  formatter. On the Point Conception 12S fixture about 30 do, regardless of
  the prior used.
