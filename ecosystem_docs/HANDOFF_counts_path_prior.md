# HANDOFF: the counts path for site priors

Read this before installing TaxaFetch or TaxaExpect from branch `gbif-facet-priors`, before reviewing it, before updating TaxaWizard, and before editing any workflow's Step 3 or Step 5. It says what changed, what the user decided, and what each consumer still has to do. Written by the "count based priors" session.

## What it is

The kernel prior (`TaxaExpect::estimate_kernel_priors()`) needs every GBIF record in the search polygon: a download, `filter_gbif_quality()`, habitat assignment per location and spatial review. That cost grows with the number of records, roughly 4 minutes and 4 GB of RAM per million, plus GBIF's download queue.

The **counts path** asks GBIF's search API for per-species record COUNTS (`limit=0&facet=speciesKey`) in concentric distance bands around the site, clipped to the same polygon, and fits the **same estimator**, producing the **same object**. Its cost grows with the number of species not yet in the name cache, not with records. It needs no GBIF account.

Vocabulary for users and docs is **records path** vs **counts path**. "facet" is only the GBIF API parameter; keep it out of user-facing text.

## User decisions

1. **Habitat for the GBIF counts defaults to `habitat_filter = "none"`**; `"taxon_threshold"` is optional. Counts have no locations, so the records path's per-location habitat labels cannot be reproduced.
   - PtConception 18S, against the record-level Marine stratum: "none" lost 0 of 377 species with prior >= 1e-4; "taxon_threshold" lost 50 (coastal plants whose records sit at points labelled Marine).
   - Do NOT build a "flag only" variant (`observed_in_habitat = FALSE`): `join_priors()` PROMOTES those rows to singleton parity.
2. **Names** (collision-checked across the monorepo):

   | Name | Package | Status |
   |---|---|---|
   | `fetch_gbif_occurrence_counts()` | TaxaFetch | new |
   | `plan_gbif_fetch()` | TaxaFetch | new |
   | `estimate_kernel_priors_from_counts()` | TaxaExpect | new |
   | `fetch_inat_occurrence_counts()` | TaxaFetch | RENAME of `fetch_inat_occurrences()`: it always returned counts, never records. Separate commit `9a05644`, droppable. |

3. **Non-GBIF data (e.g. Littler) is a separate step.** Read and standardise it as now, habitat-assign it per record, and pass it as `extra_occurrences`. It is fitted at its true coordinates in the same composition. Check that a source is not also published to GBIF, or it is counted twice.

## Results that justify it (PtConception 18S)

| Comparison | Missing (prior >= 1e-4) | Within 10x | Within ~3x | Spearman |
|---|---|---|---|---|
| Counts path vs GBIF-only kernel (R2) | 0 / 377 | 95% | 91% | 0.97 |
| Counts path, GBIF only, vs production | 53 / 415 | 77% | 67% | 0.64 |
| **Counts path + Littler vs production** | **0 / 415** | **94.9%** | **89.6%** | **0.94** |

Production also uses a depth kernel, which the counts path cannot.

Cold fetch took 89 s (2,389 one-time name lookups); later fetches take 4 s. `plan_gbif_fetch()` predicted 1,718,477 records against 1,717,250 actual. At five-kingdom scale (40M records) it recommends counts, since the records path would need about 161 GB of RAM.

Scripts and results: `eDNA/PtConception/diagnostics/fast_prior_2026_09_25/`.

## Branches (nothing merged)

- **TaxaID `gbif-facet-priors`**, from main `e9d000e`:

  | Commit | Change |
  |---|---|
  | `ae68573` | `estimate_kernel_priors(count_col=)`: a row of count n equals n one-record rows (tested to equality) |
  | `b332068` | counts path, first version |
  | `89756d4` | agreed names, `habitat_filter`, `extra_occurrences` |
  | `9a05644` | the iNat rename |
  | `d91f19c` | README rows |

- **eDNA `template-counts-path`**, from `e621fd6`, commit `149c212`: the template gets `OCCURRENCE_PATH` ("records" or "counts"), `COUNTS_LAMBDA_KM` and `COUNTS_HABITAT_FILTER`.
  - `plan_gbif_fetch()` prints a recommendation in Step 3 and never switches the path.
  - In counts mode: no calibration, no theta map, and Littler goes through Step 4.
  - Every downstream reader of `occurrences_clean`/`all_occurrences` has a counts branch.
  - The priors carry `attr(, "occurrence_path")`, and `session_meta` records the path.
  - The template's own Steps 3-5 were RUN in counts mode on PtCon 18S + Littler through a harness and reproduced the scores above.
  - Production workflows are untouched.

The worktrees lived in that session's scratchpad. Recreate with `git worktree add <dir> gbif-facet-priors`; never switch branches in the shared checkout.

## Installs, libraries, restarts

- The branch packages are installed ONLY in `~/.R_libs_counts_branch` (use it with `R_LIBS=~/.R_libs_counts_branch`). The main library is untouched.
- **When merged, install TaxaFetch and TaxaExpect TOGETHER, TaxaFetch first.** Branch TaxaExpect's `generate_domestic_food_priors()` calls `TaxaFetch::fetch_inat_occurrence_counts()`, which the old TaxaFetch does not export. Branch TaxaExpect with old TaxaFetch breaks that function at run time.
- Never reinstall under a live R process that has either package loaded. Restart those sessions afterwards.
- TaxaFlag changed in comments/roxygen only (the rename); re-document, no behaviour change.

## Tests

- New tests: `test-fetch_gbif_occurrence_counts.R` (7, GBIF mocked), `test-estimate_kernel_priors_from_counts.R` (12), and 2 `count_col` tests in `test-estimate_kernel_priors.R`.
- Full suites passed before the renames: TaxaFetch 455, TaxaExpect 289, 0 failures.
- Re-run both full suites plus TaxaFlag on the final branch before merge; that has not been done yet.
- Workflow checkers on the edited template: dead calls clean (run `check_dead_calls.sh` from the TaxaID_dev root, where the `archive_*` dirs are). `check_stale_arguments.R` flags only `build_sequence_matrix(pair_retention=)`, which predates this work and comes from the unmerged pair-retention branch.

## For the package review workflow

- Four exports added or renamed during the release freeze (with user approval), plus one argument (`count_col`) on a reviewed function.
- "Added after the review" rows and a behaviour-change line are already in `TaxaFetch/inst/taxafetch_review_response.md` and `TaxaExpect/inst/taxaexpect_review_response.md`.
- Still to do: the 9-pass pre-review checklist, `devtools::check()`, and a decision on whether the iNat rename should wait until after 1.0.

## For TaxaWizard (its memory goes stale; nothing there is changed yet)

- `inst/graph/workflow_graph.json` needs a counts-path edge beside `std_to_priors_kernel`. It must go from the taxon/site inputs to `priors` without the `std_occurrences` node. Functions: `plan_gbif_fetch`, `fetch_gbif_occurrence_counts`, `estimate_kernel_priors_from_counts`, `generate_undetected_diversity`, plus the evidence functions the kernel edge lists. It needs a snippet, and its description must state what counts cannot do: record-level habitat, covariate kernel, bandwidth calibration, spatial review.
- `inst/prompts/phase_parameterize.md` needs the path choice as a user decision, with `plan_gbif_fetch()`'s recommendation rule. Records path when the analysis needs record-level habitat, a covariate, calibration, spatial review or merged local data and it fits in memory; otherwise counts. Also the habitat default ("none") and that `COUNTS_LAMBDA_KM` must come from an earlier calibration.
- `inst/setup/requirements.json` needs a note that the counts path needs no GBIF credentials.
- The rename touches `fetch_inat_occurrences` wherever the graph/snippets mention it. There were none at the time of writing; re-grep.

## Who calls the renamed iNat function

A full search found NO direct caller of `fetch_inat_occurrences()` outside the packages. It covered `.R`, `.Rmd`, `.qmd`, `.md` and `.json` under My Drive, Google Drive, Dropbox, Documents and Desktop, every branch of both repos, and other sessions' worktrees.

Seven workflow files and one vignette call it INDIRECTLY, through `TaxaExpect::generate_domestic_food_priors()`:

- `inst/TaxaID_Workflow_Template.R`
- `eDNA/PtConception/TaxaID_eDNA_Workflow_Template.R`
- the PtCon 12S and 18S single-site workflows
- `MuguFishWorkflow.R`
- `CaliforniaIntertidalWorkflow_multi_marker.R`
- TaxaID_dev's `PtCon12S_b2_workflow.R`
- `TaxaExpect/vignettes/building-priors.Rmd`

`generate_domestic_food_priors()`'s arguments did not change (one internal call line did), so none of these need editing. They break only if TaxaExpect is installed without the matching TaxaFetch. Historical records under TaxaID_dev/screen_records keep the old name on purpose.
- After install, regenerate `llm_prompts/CONTEXT_*.md` (built from installed packages by `TaxaWizard/R/pack.R`).

## Open

1. GreatLakes Lamar end-to-end precision benchmark in counts mode (the freshwater habitat test). Next step; waiting for heavy R sessions to finish.
2. CalIntertidal session offered its COI kernel prior for a kernel-vs-counts comparison (the user's call).
3. Not built: clipping the polygon to a habitat area (would need a better coastline than Natural Earth, which omits Anacapa and Santa Barbara Island); per-sampling-group count queries.
