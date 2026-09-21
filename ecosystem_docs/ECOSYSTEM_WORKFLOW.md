# TaxaID Ecosystem — Workflow Guide
# Ordering, inputs, outputs, and save conventions across all packages

---

## Overview

The TaxaID ecosystem uses Bayes' Theorem to assign a consensus taxon to a sample -- a DNA sequence, sound, or image -- for which there are several competing hypothesized matches.
It can also clean taxonomic databases, reassign taxonomic backbones, generate species distribution priors, check the completeness of reference libraries, and translate match scores into probabilities.
The ecosystem does not calculate matches from a reference library; those are obtained elsewhere. The TaxaMatch package ingests a data frame with a `sample_id`, a match score, and one or more reference taxa that closely match the sample, and standardizes it for other packages to process.
The Bayesian part of TaxaID lives in TaxaAssign. It multiplies a likelihood -- how well a sample matches a reference -- by a prior expectation that the reference occurs at the sample location, to generate a posterior probability that the sample came from a particular taxon. Comparing among these posterior probabilities lets a user estimate confidence in the taxon or taxa hypothesized to have generated the sample. TaxaAssign also uses process of elimination to hypothesize unreferenced taxa (taxa missing from a reference database). It does this via two workflows, described below. Both can use an API account with a large language model, or operate through prompt generation for manual submission (an API is strongly recommended).

For the full multi-path pipeline diagram and function catalog, see the root [README.md](../README.md)'s "Pipeline Overview" and "Which Entry Point Do I Need?" sections. This document is the detailed, package-by-package walkthrough of the two most common complete paths: the fast LLM workflow and the thorough Bayesian workflow. `inst/TaxaID_Workflow_Template.R` at the repository root is a single-site template that runs the Bayesian path top to bottom with real function calls; it is generated from the same workflow graph this document describes, so its step order and argument names are the ground truth for that path.

## Fast and Simple LLM Workflow

The fastest workflow in TaxaAssign uses a large language model to estimate priors for a stated habitat, location, and taxonomic group. With a simple assumption about scores and an LLM-assisted check of the reference database's completeness, a consensus taxonomy can be generated with relatively little effort. It is suitable for exploration and for cases where reproducibility is not required or time is short.

| Workflow | Likelihoods source | Priors source | Habitat input | TaxaLikely objects needed |
|---|---|---|---|---|
| LLM | LLM-elicited scores, generated internally | LLM judgement | User enters manually (location + habitat label) | None |

`TaxaAssign::run_llm_pipeline()` is the recommended single-call entry point: it standardizes `match_df`, infers ecological context, elicits priors and likelihoods from an LLM, and returns a consensus data frame in one call. `TaxaAssign::assign_taxa_llm()` is the lower-level function it wraps, for callers who want to control each step separately -- see `TaxaAssign/inst/TaxaAssign_llm_workflow.R` for a worked, step-by-step version of the same path.

## LLM Pipeline Map

```
[Raw match data: eDNA / images / sounds]
         |
    ┌────▼───────────────────────────────┐
    │         Match data input           │
    │           TaxaMatch                │
    │   workflow_fastq_to_match.R        │
    │   → match_df                       │
    └────────────────────────────────────┘
                    |
    TaxaAssign::run_llm_pipeline()
    (habitat + location supplied manually;
     likelihoods and priors both LLM-elicited)
                    │
    TaxaAssign/inst/TaxaAssign_llm_workflow.R
                    │
              → consensus
```

---

## Thorough and Complex Statistical Workflow

The more accurate workflow in TaxaAssign makes more use of APIs, for downloading reference data and occurrence records.
It has two independent pipelines that both originate from TaxaMatch and converge at TaxaAssign:
- **Prior pipeline**: TaxaMatch → TaxaFetch → TaxaHabitat → TaxaExpect
- **Likelihood pipeline**: TaxaMatch → TaxaLikely

These pipelines are **fully independent** -- they can run in any order, or separately,
after TaxaMatch. Users who only need priors (e.g., species distribution mapping) or
only need likelihoods (e.g., reference quality auditing) need not run both.

Users can also start from an **existing species list** rather than TaxaMatch output.
Any vector of taxon names is a valid starting point for TaxaFetch or TaxaLikely.

| Workflow | Likelihoods source | Priors source | Habitat input | TaxaExpect objects needed |
|---|---|---|---|---|
| Bayesian | `real_likelihoods` from `TaxaLikely::evaluate_likelihoods()` | `TaxaExpect::estimate_kernel_priors()` output, joined via `TaxaAssign::join_priors()` | Via `site` (see below) | `priors` (a kernel-priors data frame) |

---

## Full Pipeline Map

```
[Raw match data: eDNA / images / sounds]
         |
    ┌────▼────────────────────────────────┐
    │         Match data input            │
    │           TaxaMatch                 │
    │   workflow_fastq_to_match.R         │
    │   → match_df                        │
    └────┬────────────────────────────────┘
         |
    ┌────┴───────────────────────┬──────────────────────────────────┐
    │                            │                                  │
    │   PRIOR PIPELINE           │   LIKELIHOOD PIPELINE            │
    │                            │                                  │
    │  TaxaFetch                 │  TaxaLikely                      │
    │  (any combination):        │  inst/workflows/1_fetch_...R     │
    │  - GBIF_workflow.R         │  → 4_score_to_likelihood_...R    │
    │  - Dataone_workflow.R      │  → real_likelihoods              │
    │  - pdf_workflow*.R         │                                  │
    │  joined by:                │                                  │
    │  Merge_sources_workflow.R  │                                  │
    │  → occurrence_data         │                                  │
    │         |                  │                                  │
    │  TaxaHabitat                │                                 │
    │  assign_habitat_workflow.R │                                  │
    │  → std_occurrences         │                                  │
    │         |                  │                                  │
    │  TaxaExpect (kernel path)  │                                  │
    │  calibrate_kernel_bandwidth│                                  │
    │  → estimate_kernel_priors  │                                  │
    │  → generate_undetected_... │                                  │
    │  → priors                  │                                  │
    └────────────┬───────────────┘
                 │                         │
                 └──────────┬───────────────┘
                            │
                       TaxaAssign
                ──────────┴──────────┐
                            │
                    Bayesian workflow
                    TaxaAssign_bayesian_workflow.R
                    (join_priors → compute_posterior
                     → posterior_consensus)
```

---

## Workflow Reference

### STEP 0 — TaxaMatch

**Script:** `TaxaMatch/inst/workflow_fastq_to_match.R`

**Inputs:** Raw match file, or a sequence table/FASTA to BLAST; column names for sample ID and match score

**Key functions:**
- `read_sequence_table()`, `filter_sequences()` -- ingest and quality-filter raw sequences before matching
- `blast_sequences()` -- BLAST search (remote or local)
- `standardize_match_data()` -- standardises columns, detects taxonomy ranks
- `TaxaTools::clean_taxon_names()` -- strips authors, subspecies, brackets
- `filter_redundant_hypotheses()` -- drops higher-rank rows superseded by finer-rank rows within the same lineage and sample
- `evaluate_reference_accessions()` / `flag_incongruent_references()` / `review_flagged_accessions()` / `resolve_review_overrides()` / `remove_incongruent_references()` -- optional pre-training reference-accession screen: checks whether independent GenBank evidence agrees taxonomically with each reference accession a hypothesis rests on, gives borderline flags an LLM second look, and only removes rows on a separate, explicit opt-in

**Outputs:**

| Object | Description | Recommended path |
|---|---|---|
| `match_df` | One row per `sample_id`/`observation_id` × reference; standardised columns | `TaxaMatch/inst/match_obj.rds` |

**Key columns:** `observation_id`, `score_original`, `taxon_name`, `taxon_name_rank`, `family`, `genus`, `species`, `accession`

Non-DNA match data (camera-trap or acoustic classifier output) enters the same way via `TaxaMatch::read_animl_output()`, `read_inaturalist_cv_output()`, `read_speciesnet_output()`, or `read_birdnet_output()` -- see `TaxaMatch/inst/workflow_image_acoustic.R`.

---

### PRIOR PIPELINE -- Data Acquisition (TaxaFetch)

Run **any combination** of the acquisition workflows below. Each takes a vector
of taxon names (from `match_df`/`taxa` or user-supplied). Acquisition order does not matter.
Join all results with `Merge_sources_workflow.R` before proceeding.

#### GBIF acquisition
**Scripts:** `TaxaFetch/inst/Define_search_workflow.R` → `TaxaFetch/inst/GBIF_workflow.R`

The Define script translates NCBI backbone names to the GBIF backbone and identifies the
higher-rank groups to query (e.g., all families in the sample). The GBIF script then
fetches and quality-filters occurrence records.

**Key functions:** `TaxaTools::verify_taxon_names()`, `TaxaTools::change_backbone()`, `get_keys_from_context()`,
`make_bbox_wkt()` or `define_search_polygon()`, `fetch_gbif_occurrences()` (or, for larger pulls, `download_gbif_occurrences()`), `filter_gbif_quality()`, `dedupe_occurrences()`

**Outputs:** `occurrences` (or `gbif_occurrences` before merging with other sources)

#### DataOne acquisition
**Script:** `TaxaFetch/inst/Dataone_workflow.R`

**Outputs:** DataOne occurrence records (standardised via `stack_occurrences()`)

#### PDF / literature acquisition
**Script:** `TaxaFetch/inst/pdf_workflow_test_v4.R`

See also: `TaxaFetch/inst/PDF_PIPELINE_DATAONE_PARALLEL.md` for a combined DataOne + PDF approach.

**Outputs:** Literature-extracted occurrence records

#### Merging sources
**Script:** `TaxaFetch/inst/Merge_sources_workflow.R`

**Inputs:** Any combination of the above acquisition outputs

**Key functions:** `TaxaTools::create_taxon_names()`, `TaxaTools::verify_taxon_names()`, `rename_cols()`, `stack_occurrences()`

**Outputs:**

| Object | Description | Recommended path |
|---|---|---|
| `occurrence_data` | Combined, standardised occurrences; one `point_id` per lat/lon | `TaxaFetch/inst/occurrence_data.rds` |

**Key columns:** `point_id`, `decimalLatitude`, `decimalLongitude`, `taxon_name`,
`taxon_name_rank`, `datasource`, `eventDate`

---

### PRIOR PIPELINE -- Habitat Assignment (TaxaHabitat, via TaxaFetch)

**Script:** `TaxaHabitat/inst/workflows/assign_habitat_workflow.R`

**Inputs:** `occurrence_data`

**Key functions:**
- `flag_institution_candidates()` -- tiers occurrence records flagged near a biodiversity institution (`institution_flag`, set by `TaxaFetch::filter_gbif_quality()`) into "high"/"low"/"ambiguous" suspicion for review; field stations and marine labs are often sited exactly where good habitat is, so these are never auto-removed
- `build_habitat_lookup()` -- the recommended, cached one-call path to a species × habitat weight table: it wraps `build_habitat_prompt()` → an LLM call → `parse_hierarchical_habitat_response()`, serving a taxon already classified under the same scheme from `cache_dir` instead of re-asking. An uncached verdict can flip between runs, moving a species' records in or out of a site's habitat stratum and its kernel prior by orders of magnitude; force fresh verdicts with `taxahabitat_clear_cache(<cache_dir>)`.
- `assign_habitat_biological()` -- applies the habitat lookup's weights to occurrence records, producing the `main_habitat` column, at a given `threshold`
- `flag_habitat_inconsistencies()`, `review_spatial_flags()`, `save_spatial_review_decisions()`, `apply_spatial_review_decisions()` -- spatial QAQC and its reviewed-decision cache
- `resolve_habitat_by_geography()` -- resolves a habitat verdict from geography alone when biological consensus is unavailable
- `consensus_habitat()` -- combines multiple habitat-scheme votes into one consensus label

**Habitat terminology:**
- `habitat_lookup` contains **species-level** habitat weights: a species' affinity score
  for each habitat category. This is a property of the species, not the location.
- `main_habitat`, produced by `assign_habitat_biological()`, is the **site-level** habitat: the
  dominant habitat at a specific occurrence point, derived from species composition
  at that location. The same column name, `main_habitat`, carries this site-level meaning
  everywhere downstream -- in `std_occurrences`, in `TaxaExpect`'s priors table, and in the
  `site` argument to `TaxaAssign::join_priors()`.
- These are distinct concepts: a species' own habitat affinity is never a location's habitat.

**Outputs:**

| Object | Description | Recommended path |
|---|---|---|
| `habitat_lookup` | Species × habitat weight table (LLM output, parsed) | `TaxaHabitat/inst/habitat_lookup.rds` |
| `std_occurrences` | `occurrence_data` + `main_habitat` column | `TaxaFetch/inst/std_occurrences.rds` |

---

### PRIOR PIPELINE -- Prior Generation (TaxaExpect, kernel path)

**Inputs:** `std_occurrences` (habitat-labelled occurrence records; no gridding step needed)

TaxaExpect prices each species' prior as its kernel-weighted share of legitimate detections at the sampling site, directly from occurrence records: each record is weighted by its own distance from the site, so there is no intermediate grid cell to bin records into. Bandwidth is chosen by leave-one-block-out composition prediction rather than a formula. See `TaxaExpect/README.md`'s Quick Start and Key Functions sections for the full statistical description.

**Steps:**

| Step | Function | Output object | Notes |
|---|---|---|---|
| 1 | `calibrate_kernel_bandwidth()` | `kernel_cal` | Chooses `lambda_km` (and the regional back-off `m`) by leave-one-block-out prediction. `kernel_cal$results["regional", ]` and `["nearest_block", ]` are reference rows -- compare `kernel_cal$best$weighted_logloss` against them to confirm the kernel actually beats a flat regional average before trusting it. `lambda_grid` should span a wide enough range that an interior optimum is possible in both directions. |
| 2 | `estimate_kernel_priors()` | `kernel_priors_fit` | Site-centered kernel weighting of habitat-stratified occurrence records. `site_id` (default `"Site_<lat>_<lon>"`) is stamped onto the output's `grid_id` column, kept under that name for join compatibility with `TaxaAssign::join_priors()`; the value itself is opaque. |
| 3 | `generate_undetected_diversity()` | `priors_undetected` | Good-Turing/Chao-based dark-diversity floor: singleton-mirror priors for neighborhood singletons, plus a global floor for the rest. |
| 4 | `dplyr::bind_rows()` | `priors` | Combines resident (`kernel_estimated`) and undetected (`resident_undetected`) rows. |
| 5 (optional) | `generate_domestic_food_priors()` | `domestic_priors`, added to `priors` | Named domestic/commensal-animal and food-species priors (`transport` branch) -- GBIF/occurrence data structurally under-counts these species. Priced on a pooled fit regardless of `sampling_group_col`, since a domestic/food species is not scoped to one detection process. |
| 6 (optional) | `generate_regional_proximity_evidence()`, `generate_presence_curve_evidence()`, `generate_invasive_watch_evidence()`, `generate_inat_range_evidence()`, `generate_user_specified_evidence()`, each conditioned by `condition_evidence_on_habitat()` and folded in via `apply_undetected_evidence(pricing = "curve")` | evidence-blended rows added to `priors` | Elevates the dark-diversity floor for a zero-record candidate with a real regional GBIF record just outside the site, a named invasive/watch-listed species, a verified iNaturalist range, or a user-supplied weight, instead of leaving every such candidate at one flat clamp. `condition_evidence_on_habitat()` multiplies each evidence weight by the taxon's weight for the site habitat from the same `habitat_lookup` the resident priors use, so evidence obeys the same habitat stratification. |
| 7 | `TaxaTools::verify_taxon_names()` + `TaxaMatch::convert_taxonomy_backbone()` | `priors` (backbone-converted) | Verifies taxon names and converts to the backbone `TaxaAssign::join_priors()` will be called with. |

**Grouping by detection process:** when `std_occurrences` spans more than one detection process with different sampling effort (e.g. one pooled marker covering fish, birds, and phytoplankton via different methods), pass the same `sampling_group_col` to both `calibrate_kernel_bandwidth()` and `estimate_kernel_priors()`. Composition and the Good-Turing budget are then computed *within* each group instead of pooled -- pooling incomparable effort silently dilutes a detectable taxon's share and inflates a barely-sampled group's singleton counts. `kernel_priors_fit$by_group` and `$budget` carry the per-group detail; with more than one group the pooled scalars (`f1`, `f2`, `theta_present`, etc.) are `NA` by design, and `$budget` is authoritative. This grouping is a no-op for a taxonomically homogeneous pool and is orthogonal to grouping by physical site (`TaxaMatch::build_site_table()`, see the TaxaAssign section below).

**Diagnostics:** `plot_theta_surface(kernel_fit, occurrence_data, taxon)` renders a continuous prior-field map for one taxon, evaluated from `kernel_priors_fit` itself (not the flattened `priors` table). `kernel_budget_sensitivity()` reports how the Good-Turing budget moves across counting-radius/bandwidth choices. `report_priors()` builds the priors section for `TaxaTools::assemble_report()`. `fit_regional_presence_curve()` recalibrates the presence-distance curve's `w_scale`/`d_half` from a local species checklist, in place of the package default used by `generate_presence_curve_evidence()`.

**Outputs:**

| Object | Description | Recommended path |
|---|---|---|
| `kernel_priors_fit` | Fitted `taxaexpect_kernel_priors` object; needed to derive undetected/evidence rows or re-plot the prior field at this site | `TaxaExpect/inst/kernel_priors_fit.rds` |
| `priors` | Prior table; backbone-converted; input to TaxaAssign's Bayesian workflow | `TaxaExpect/inst/priors.rds` |

Neither the workflow template nor the package saves these to disk automatically -- add a `saveRDS()` call at whichever checkpoint you want to persist.

**Key columns in `priors`:** `taxon_name`, `taxon_name_rank`, `grid_id`, `main_habitat`,
`alpha`, `beta`, `theta_mean`, `theta_sd`, `prior_branch`, `effective_records`, `undetected_type`, `model_tier`.
`prior_branch` records which generator produced a row (`kernel_estimated`, `resident_undetected`, `evidence_blend`, `transport`); it makes no claim about how much evidence stands behind the row -- `effective_records` does.

---

### LIKELIHOOD PIPELINE (TaxaLikely)

**Inputs:** `match_df` (from TaxaMatch, or any conforming data frame)

**Stages:**

| Stage | Script | Functions | Output |
|---|---|---|---|
| 1 | `TaxaLikely/inst/workflows/1_fetch_references_workflow.R` | `fetch_ncbi_reference_sequences()` -- searches NCBI by family (not individual species) so the model has within-species variation and between-species distances; species present in `match_df` are prioritized so they are always fully represented under a download budget | `reference_df` |
| 2 (optional) | `TaxaLikely/inst/workflows/2_flag_errors_workflow.R` | Reference-accession screening (see the TaxaMatch step above) | flagged `reference_df` |
| 3 | `TaxaLikely/inst/workflows/3_train_model_workflow.R` | `build_sequence_matrix()` → `train_likelihood_model()` -- fits per-species score distributions with empirical Bayes shrinkage | `reference_matrix`, `model_params` |
| 4 | `TaxaLikely/inst/workflows/4_score_to_likelihood_workflow.R` | `evaluate_likelihoods()` → `filter_top_hypotheses()` -- computes H1/H2/H3 likelihoods per sample × taxon | `likelihoods` (from `lik_result$likelihoods`) |
| 5 (optional) | `TaxaLikely/inst/workflows/5_audit_coverage_workflow.R` | `audit_barcode_coverage()` -- audits reference-database coverage for the taxa in `match_df` | `coverage` (not passed to TaxaAssign directly) |
| 6 (non-DNA alternative) | `TaxaLikely/inst/workflows/6_no_score_pathway_workflow.R` | `unreferenced_candidates()` + `assign_scores(score_type = "none")` -- for expert/morphological IDs with no match scores at all | `likelihoods` |

Non-DNA match data (image/acoustic classifier output) skips training and goes straight to `assign_scores()` -- see `TaxaLikely/inst/workflows/image_acoustic_likelihood_workflow.R`.

**Outputs needed by TaxaAssign:**

| Object | Description | Recommended path |
|---|---|---|
| `model_params` | Trained `taxa_model_params`; needed to re-evaluate at new queries | `TaxaLikely/inst/model_params.rds` |
| `likelihoods` | Evaluated, top-filtered likelihoods | `TaxaLikely/inst/real_likelihoods.rds` |

---

### CONVERGENCE -- TaxaAssign

#### Option A: LLM workflow
**Script:** `TaxaAssign/inst/TaxaAssign_llm_workflow.R`; recommended entry point `TaxaAssign::run_llm_pipeline()`.

Does **not** require TaxaLikely or TaxaExpect objects. The LLM generates both
likelihood judgements and prior context internally from the match data.

**User must supply manually:**
- A location (coordinates or descriptive)
- A habitat label for the sampling site

**Required inputs:**
- `match_df` -- provides species candidates and match scores

#### Option B: Bayesian workflow
**Script:** `TaxaAssign/inst/TaxaAssign_bayesian_workflow.R`

Combines TaxaLikely likelihoods with TaxaExpect priors via `TaxaAssign::join_priors()`.

**Required inputs:**

| Object | Source | Role |
|---|---|---|
| `match_df` / `taxa` | TaxaMatch | Species list for unreferenced-hypothesis expansion and taxonomy fallback |
| `likelihoods` (+ `model_params`) | TaxaLikely | Per-hypothesis likelihoods |
| `priors` | TaxaExpect | Per-taxon × `grid_id` × `main_habitat` prior parameters |
| `site` | User-supplied (see below) | Tells `join_priors()` which site/habitat each likelihood row belongs to |

**The `site` argument** is what `join_priors()` uses to attach spatial and habitat context to
each likelihood row before joining to `priors`. `main_habitat` is always required -- the
function never guesses which habitat the observations came from. For a single-site study it
is a named list:

```r
site_spec <- list(lat = SITE_LAT, lon = SITE_LON, main_habitat = SITE_HABITAT)
```

which auto-resolves to the nearest `grid_id` in `priors` (or `list(grid_id = "...",
main_habitat = "...")` directly, if known). For a study spanning multiple sites, `site` is
instead a data frame with one row per `observation_id` (`observation_id`, `lat`, `lon`,
`main_habitat`, or `grid_id` in place of `lat`/`lon`) -- built by joining
`TaxaMatch::build_site_table()`'s output to a per-site habitat lookup, one row per
`spatial_group_id`. `TaxaAssign::combine_multisite_priors()` then combines any duplicate
`(observation_id, taxon_name)` rows produced by an observation detected at more than one
site, via precision-weighted logit combination, before `compute_posterior()`.

**Join sequence in `join_priors()`:**
1. Resolve `site` to one `grid_id` + `main_habitat` per `observation_id` (nearest-site resolution for a named-list `site`, direct lookup for a data-frame `site`).
2. Join `likelihoods` to `priors` on `taxon_name` (or, via `expansion_taxonomy`, an expanded set of species under a coarser-rank likelihood row) × `grid_id` × `main_habitat`, attaching `prior_mean`, `prior_alpha`, `prior_beta`.

**Pipeline sections:**

| Section | Action |
|---|---|
| 1 | Load likelihoods; apply `TaxaLikely::filter_top_hypotheses()` |
| 2 | Load `priors`; extract species list |
| 3 | Identify unreferenced species; expand H2/H3 rows via `TaxaLikely::expand_unreferenced_hypotheses()` |
| 4 | Apply coverage constraints: `TaxaLikely::apply_coverage_constraints()` |
| 5 | `TaxaAssign::join_priors()` -- see above |
| 6 | `TaxaAssign::compute_posterior()` |
| 7 | `TaxaAssign::posterior_consensus()`, optionally refined by `update_prior_from_consensus()` + a second `posterior_consensus()` call (empirical Bayes), then `add_slash_taxon()` |

Both options converge on the same consensus schema and can be passed to `TaxaFlag::review_assignments()` for LLM expert review (habitat fit, geographic plausibility, contaminant risk, alternatives) -- see `TaxaFlag/inst/review_assignments_workflow.R`.

---

## Recommended Save Paths (all packages)

Neither the generated workflow template nor the individual package scripts save these
checkpoint objects to disk by default -- add a `saveRDS()` call yourself at whichever step
you want to persist. Point `CACHE_ROOT`/`cache_dir` arguments at a durable, project-local
directory rather than `tempdir()` for a real run; see the root README's "Caching and
resources" section for the separate, query-level caches (GBIF downloads, NCBI fetches, LLM
verdicts) that most of these steps also use.

| Object | Package | Recommended path |
|---|---|---|
| `match_df` | TaxaMatch | `TaxaMatch/inst/match_obj.rds` |
| `occurrence_data` | TaxaFetch | `TaxaFetch/inst/occurrence_data.rds` |
| `habitat_lookup` | TaxaHabitat | `TaxaHabitat/inst/habitat_lookup.rds` |
| `std_occurrences` | TaxaHabitat | `TaxaFetch/inst/std_occurrences.rds` |
| `reference_matrix` | TaxaLikely | `TaxaLikely/inst/real_matrix.rds` |
| `model_params` | TaxaLikely | `TaxaLikely/inst/model_params.rds` |
| `likelihoods` | TaxaLikely | `TaxaLikely/inst/real_likelihoods.rds` |
| `kernel_priors_fit` | TaxaExpect | `TaxaExpect/inst/kernel_priors_fit.rds` |
| `priors` | TaxaExpect | `TaxaExpect/inst/priors.rds` |
| `consensus` / `reviewed` | TaxaAssign / TaxaFlag | project-specific output directory |
