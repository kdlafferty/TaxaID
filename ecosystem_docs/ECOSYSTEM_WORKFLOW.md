# TaxaID Ecosystem — Workflow Guide
# Ordering, inputs, outputs, and save conventions across all packages
# Last updated: 2026-04-01

---

## Overview

The TaxaID ecosystem uses Baye's Theorem to assign a consensus taxon to a sample such as DNA sequence, sound or image for which there are several competing hypothesized matches.
It can also clean taxonomic databases, reassign taxonomic backbones, generate species distributions models, check the completeness of reference libraries, and translate match scores into probabilities.
The package currently does not calculate matches from a reference library. These are obtained elsewhere. Thus, the TaxaMatch package uploads a dataframe that contains a sample_id, a match score, and one or more reference taxa that closely match the sample. It then does some data standarization needed for other packages to process the data. 
The Bayesian part of TaxaID is in the TaxaAssign package. This packages uses Baye's Theorem to multiply a likelihood that matches a sample to a reference by a prior expectation that the reference occurs at the sample location to generate a posterior probability that the sample was from a particular taxon. By comparing among these posterior probabilities, a user can estimate confidence in the various taxon or taxa hypothesized to have generated the sample. Notably, TaxaAssign also uses the process of elimination to hypothesize unreferenced taxa (taxa missing from a reference database). TaxaAssign does this with two separate worflows. Both approaches can use an api account with a large language model or can be operated through prompt generation (api strongly suggested).

## Fast and simple LLM Workflow
The fastest workflow in TaxaAssign is to use a large language model to estimate priors for a stated habitat, location and taxonomic group. Then, with some simple assumptions about scores, and an exploration of the reference database for completeness (using an api), a consensus taxonomy can be generated with relatively little effort. It is almost always going to outperform other available consensus algorithms and is suitable for exploration and when reproducibility is not needed or time is short. 
| Workflow | Likelihoods source | Priors source | Habitat input | TaxaLikely objects needed |
|---|---|---|---|---|
| LLM | TaxaLikely functions (called internally) | LLM judgement | User enters manually (location + habitat label) | None — TaxaLikely must be installed, not pre-run |

## LLM Pipeline Map

```
[Raw match data: eDNA / images / sounds]
         |
    ┌────▼───────────────────────────────┐
    │         Match data input           │
    │           TaxaMatch                │
    │   workflow_standardize.R           │
    │   → match_obj.rds                  │
    └────────────────────────────────────┘
                    |
    TaxaAssign (using functions from TaxaLikely)
                    │
    TaxaAssign_llm_workflow.R
```

---

## THOROUGH AND COMPLEX STATISTICAL WORKFLOW
The more accurate workflow in TaxaAssign requires more use of api for downloading data from various sources. Notably, reference databases, and species distribution information. 
It has two independent pipelines that both originate from TaxaMatch
and converge at TaxaAssign:
- **Prior pipeline**: TaxaMatch → TaxaFetch → TaxaHabitat → TaxaExpect
- **Likelihood pipeline**: TaxaMatch → TaxaLikely

These pipelines are **fully independent** — they can run in any order, or separately,
after TaxaMatch. Users who only need priors (e.g., species distribution mapping) or
only need likelihoods (e.g., reference quality auditing) need not run both.

Users can also start from an **existing species list** rather than TaxaMatch output.
Any vector of taxon names is a valid starting point for TaxaFetch or TaxaLikely.

| Workflow | Likelihoods source | Priors source | Habitat input | TaxaLikely objects needed |
|---|---|---|---|---|
| Bayesian | Pre-computed `real_likelihoods` | TaxaExpect priors | Via `sample_meta` (see below) | `real_model.rds`, `real_likelihoods.rds` |

---

## Full Pipeline Map

```
[Raw match data: eDNA / images / sounds]
         |
    ┌────▼────────────────────────────────┐
    │         Match data input            │
    │           TaxaMatch                 │
    │   workflow_standardize.R            │
    │   → match_obj.rds                   │
    └────┬────────────────────────────────┘
         |
    ┌────┴───────────────────────┬──────────────────────────────────┐
    │                            │                                  │
    │   PRIOR PIPELINE           │   LIKELIHOOD PIPELINE            │
    │                            │                                  │
    │  TaxaFetch                 │  TaxaLikely                      │
    │  (any combination):        │  TaxaLikely_workflow.R           │
    │  - GBIF_workflow.R         │  → real_matrix.rds  (cached)     │
    │  - Dataone_workflow.R      │  → real_model.rds               │
    │  - pdf_workflow*.R         │  → real_likelihoods.rds          │
    │  joined by:                │                                  │
    │  Merge_sources_workflow.R  │                                  │
    │  → occurrence_data         │                                  │
    │         |                  │                                  │
    │  TaxaHabitat               │                                  │
    │  Habitat_assign_workflow.R │                                  │
    │  → occurrences_with_habitat│                                  │
    │         |                  │                                  │
    │  TaxaExpect                │                                  │
    │  TaxaExpect_workflow.R     │                                  │
    │  → taxaexpect_priors.rds   │                                  │
    └────────────┬───────────────┘
                 │                         │
                 └──────────┬───────────────┘
                            │
                       TaxaAssign
                ──────────┴──────────┐
                            │          
                    Bayesian workflow
                    TaxaAssign_bayesian_workflow.R
```

---

## Workflow Reference

### STEP 0 — TaxaMatch

**Script:** `TaxaMatch/inst/workflow_standardize.R`

**Inputs:** Raw match file (CSV); column names for sample ID and match score

**Key functions:**
- `standardize_match_data()` — standardises columns, detects taxonomy ranks
- `TaxaTools::clean_taxon_names()` — strips authors, subspecies, brackets
- `filter_redundant_hypotheses()` — drops higher-rank rows superseded by finer-rank rows within the same lineage and sample

**Outputs:**

| Object | Description | Saved to |
|---|---|---|
| `match_obj` | One row per `sample_id` × reference; standardised columns | `TaxaMatch/inst/match_obj.rds` ✓ |

**Key columns:** `sample_id`, `score`, `taxon_name`, `taxon_name_rank`, `family`, `genus`, `species`, `accession`

---

### PRIOR PIPELINE — Data Acquisition (TaxaFetch)

Run **any combination** of the three acquisition workflows below. Each takes a vector
of taxon names (from `match_obj` or user-supplied). Acquisition order does not matter.
Join all results with `Merge_sources_workflow.R` before proceeding.

#### GBIF acquisition
**Scripts:** `TaxaFetch/inst/Define_search_workflow.R` → `TaxaFetch/inst/GBIF_workflow.R`

The Define script translates NCBI backbone names → GBIF backbone and identifies the
higher-rank groups to query (e.g., all families in the sample). The GBIF script then
fetches and quality-filters occurrence records.

**Key functions:** `verify_taxon_names()`, `change_backbone()`, `get_keys_from_context()`,
`make_bbox_wkt()`, `fetch_gbif_occurrences()`, `filter_gbif_quality()`

**Outputs:** `gbif_occurrences`

#### DataOne acquisition
**Script:** `TaxaFetch/inst/Dataone_workflow.R`

**Outputs:** DataOne occurrence records (standardised via `dataone_standardize()`)

#### PDF / literature acquisition
**Script:** `TaxaFetch/inst/pdf_workflow*.R`

See also: `TaxaFetch/inst/PDF_PIPELINE_DATAONE_PARALLEL.md` for parallel DataOne + PDF approach.

**Outputs:** Literature-extracted occurrence records

#### Merging sources
**Script:** `TaxaFetch/inst/Merge_sources_workflow.R`

**Inputs:** Any combination of the above acquisition outputs

**Key functions:** `create_taxon_names()`, `verify_taxon_names()`, `rename_cols()`, `stack_occurrences()`

**Outputs:**

| Object | Description | Saved to |
|---|---|---|
| `occurrence_data` | Combined, standardised occurrences; one `point_id` per lat/lon | *(add `saveRDS`)* |

**Key columns:** `point_id`, `decimalLatitude`, `decimalLongitude`, `taxon_name`,
`taxon_name_rank`, `datasource`, `eventDate`

---

### PRIOR PIPELINE — Habitat Assignment (TaxaHabitat, via TaxaFetch)

**Script:** `TaxaFetch/inst/Habitat_assign_workflow.R`

**Inputs:** `occurrence_data`

**Key functions:**
- `build_habitat_prompt()` — constructs LLM prompt for habitat assignment
- `prompt_api()` — submits prompt (or `prompt_manual()` for manual submission)
- `parse_hierarchical_habitat_response()` — parses LLM JSON → species × habitat weight table
- `assign_habitat_biological()` — applies weights to occurrence records → `main_habitat` column
- `flag_habitat_inconsistencies()`, `review_spatial_flags()` — spatial QAQC

**Note on habitat terminology:**
- `habitat_lookup` contains **species-level** habitat weights: a species' affinity score
  for each habitat category. This is a property of the species, not the location.
- `main_habitat` in `occurrences_with_habitat` is the **site-level** habitat: the
  dominant habitat at a specific occurrence point, derived from species composition
  at that location using `assign_habitat_biological()`.
- These are distinct concepts — both terms are now used consistently throughout the ecosystem.

**Outputs:**

| Object | Description | Saved to |
|---|---|---|
| `habitat_lookup` | Species × habitat weight table (LLM output, parsed) | *(add `saveRDS`)* |
| `occurrences_with_habitat` | `occurrence_data` + `main_habitat` column | *(add `saveRDS`)* |

---

### PRIOR PIPELINE — Modelling and Prior Generation (TaxaExpect)

**Script:** `TaxaExpect/inst/TaxaExpect_workflow.R`

**Inputs:** `occurrences_with_habitat`

**Steps:**

| Step | Function | Output object | Notes |
|---|---|---|---|
| 1 | `optimize_grid_size()` | `grid_result` | Scores candidate resolutions; returns `$best_grid` |
| 2 | `create_sites_from_grid()` | `occurrences_gridded` | Adds `grid_id`, `lat_r`, `lon_r` |
| 3 | `prepare_model_dataframe()` | `model_data` | Species × site counts, zero-filled, covariates scaled |
| 4 | `compute_moran_basis()` | `basis` | Moran eigenvectors; joined to `model_data` |
| 5 | `screen_spatial_formula()` | `model_fit` | Selects parsimonious formula; returns `biofreq_model` |
| 6 | `generate_full_priors()` | `priors_observed` | Beta(alpha, beta) per taxon × grid_id |
| 7 | `generate_undetected_diversity()` | `priors_undetected` | Tier 3 proxies (singletons + global floor) |
| 8 | `bind_rows()` | `priors_combined` | All tiers combined |
| 9 | `verify_taxon_names()` + `change_backbone()` | `taxaexpect_priors` | NCBI backbone; ready for TaxaAssign |

**Outputs:**

| Object | Description | Saved to |
|---|---|---|
| `model_fit` | Fitted `biofreq_model`; needed to predict at new sites | *(add `saveRDS` → `TaxaExpect/inst/model_fit.rds`)* |
| `grid_size` | Best grid resolution from `optimize_grid_size()` | *(embed in `model_fit` or save separately)* |
| `taxaexpect_priors` | Prior table; NCBI backbone; input to TaxaAssign Bayesian | *(add `saveRDS` → `TaxaExpect/inst/taxaexpect_priors.rds`)* |

**Key columns in `taxaexpect_priors`:** `taxon_name`, `taxon_name_rank`, `grid_id`,
`alpha`, `beta`, `theta_mean`, `theta_sd`, `model_tier`, `undetected_type`

---

### LIKELIHOOD PIPELINE (TaxaLikely)

**Script:** `TaxaLikely/inst/TaxaLikely_workflow.R`

**Inputs:** `match_obj` (from TaxaMatch, or any conforming data frame)

**Stages:**

| Stage | Functions | Output | Saved to |
|---|---|---|---|
| A | Toy data — verify functions run | (no save needed) | — |
| B1 | `build_sequence_matrix()` | `real_matrix` | `TaxaLikely/inst/real_matrix.rds` ✓ |
| B2 | `train_likelihood_model()` | `real_model` | *(add `saveRDS` → `TaxaLikely/inst/real_model.rds`)* |
| B3 | `evaluate_likelihoods()` | `real_likelihoods` | `TaxaLikely/inst/real_likelihoods.rds` ✓ |
| C | `audit_barcode_coverage()` | `coverage` | *(optional; not passed to TaxaAssign directly)* |

**Note:** `real_likelihoods` is `lik_result$likelihoods` before `filter_top_hypotheses()`.
The Bayesian workflow applies `filter_top_hypotheses()` as its first step.

**Outputs needed by TaxaAssign:**

| Object | Description | Saved to |
|---|---|---|
| `real_model` | Trained `taxa_model_params`; needed to re-evaluate at new queries | `TaxaLikely/inst/real_model.rds` *(TODO)* |
| `real_likelihoods` | Raw evaluated likelihoods | `TaxaLikely/inst/real_likelihoods.rds` ✓ |

---

### CONVERGENCE — TaxaAssign

#### Option A: LLM workflow
**Script:** `TaxaAssign/inst/TaxaAssign_llm_workflow.R`

Does **not** require TaxaLikely or TaxaExpect objects. The LLM generates both
likelihood judgements and prior context internally from the match data.

**User must supply manually:**
- A location (coordinates or descriptive)
- A habitat label for the sampling site

**Required inputs:**
- `match_obj` — provides species candidates and match scores

#### Option B: Bayesian workflow
**Script:** `TaxaAssign/inst/TaxaAssign_bayesian_workflow.R`

Combines TaxaLikely likelihoods with TaxaExpect priors. The user does **not** enter
habitat manually — habitat context is embedded in `taxaexpect_priors` via `grid_id`.

**Required inputs:**

| Object | Source | Role |
|---|---|---|
| `match_obj` | TaxaMatch | Species list for unreferenced hypothesis expansion |
| `real_likelihoods` (+ `real_model`) | TaxaLikely | Per-hypothesis likelihoods |
| `taxaexpect_priors` | TaxaExpect | Per-taxon × grid_id prior probabilities |
| `sample_meta` | User-supplied (see below) | Maps `sample_id` → `grid_id` |

**`sample_meta`** is NOT generated by any TaxaID workflow. The user builds it from their
experimental design (where samples were collected and what habitat was present).
TaxaAssign uses it to attach spatial and habitat context to each likelihood row before
joining to `taxaexpect_priors`.

Required columns: `sample_id`, `grid_id`, `main_habitat`

```r
# grid_id must use the SAME grid_size as the TaxaExpect model:
#   sample_locations <- create_sites_from_grid(
#     sample_lat_lon_df,            # user data: sample_id + decimalLatitude + decimalLongitude
#     grid_size = grid_result$best_grid   # saved from TaxaExpect workflow
#   )
#   sample_meta <- sample_locations |>
#     dplyr::select(sample_id, grid_id) |>
#     dplyr::left_join(sample_habitat_notes, by = "sample_id")  # adds main_habitat
#   # main_habitat can come from field notes or TaxaHabitat applied to sample locations
```

**Join sequence in TaxaAssign (Section 5):**
1. `likelihoods |> left_join(sample_meta, by = "sample_id")` — adds `grid_id` + `main_habitat` to every likelihood row
2. `|> left_join(taxaexpect_priors, by = c("taxon_name", "grid_id", "main_habitat"))` — attaches prior parameters

**Pipeline sections:**

| Section | Action |
|---|---|
| 1 | Load likelihoods; apply `filter_top_hypotheses()` |
| 2 | Load `taxaexpect_priors`; extract species list |
| 3 | Identify unreferenced species; expand H2/H3 rows via `expand_unreferenced_hypotheses()` |
| 4 | Apply coverage constraints: `apply_coverage_constraints()` |
| 5 | Join likelihoods to priors on `taxon_name` + `grid_id` + `main_habitat` (via `sample_meta`) |
| 6 | `compute_posterior()` |
| 7 | `consensus_taxonomy()` — see `TaxaAssign_consensus_workflow.R` for full details |

---

## Recommended Save Paths (all packages)

| Object | Package | Path |
|---|---|---|
| `match_obj` | TaxaMatch | `TaxaMatch/inst/match_obj.rds` |
| `occurrence_data` | TaxaFetch | `TaxaFetch/inst/occurrence_data.rds` *(TODO)* |
| `occurrences_with_habitat` | TaxaHabitat | `TaxaFetch/inst/occurrences_with_habitat.rds` *(TODO)* |
| `real_matrix` | TaxaLikely | `TaxaLikely/inst/real_matrix.rds` |
| `real_model` | TaxaLikely | `TaxaLikely/inst/real_model.rds` *(TODO)* |
| `real_likelihoods` | TaxaLikely | `TaxaLikely/inst/real_likelihoods.rds` |
| `model_fit` | TaxaExpect | `TaxaExpect/inst/model_fit.rds` *(TODO)* |
| `taxaexpect_priors` | TaxaExpect | `TaxaExpect/inst/taxaexpect_priors.rds` *(TODO)* |

---

## Open Design Issues

### `habitat` vs `main_habitat` — RESOLVED

Two distinct concepts existed under overlapping names:
- **Species-level**: habitat affinity weights in `habitat_lookup` — a property of the species (TaxaHabitat)
- **Site-level**: `main_habitat` — dominant habitat at an occurrence point or grid cell

`generate_full_priors()` and `generate_undetected_diversity()` were previously hardcoding
the output column as `habitat` regardless of `habitat_col`. Fixed: both functions now
respect `habitat_col` on output (default `"main_habitat"`). The Bayesian workflow join
updated accordingly. `main_habitat` is now consistent throughout TaxaHabitat → TaxaExpect → TaxaAssign.

### ⚠️ TaxaExpect workflow Section 7 (legacy code)

Section 7 of `TaxaExpect_workflow.R` references `taxamatch_output` (the raw TaxaMatch
object) and attempts to join likelihoods. This predates the TaxaLikely split and should
be removed. TaxaExpect does not use likelihoods — that join happens in TaxaAssign.

### ⚠️ `sample_meta` not generated by any workflow

The Bayesian workflow needs `sample_id → grid_id` mapping. No existing script builds this.
The grid_id must use the same `grid_size` as the TaxaExpect model. The `grid_size` should
be stored in `model_fit$meta` (verify this is implemented) or saved separately alongside
`taxaexpect_priors`.

### Prior join dimension — RESOLVED

`taxaexpect_priors` is indexed by `taxon_name × grid_id × main_habitat`. The Bayesian
workflow joins on all three dimensions. `sample_meta` supplies `grid_id` and `main_habitat`
per `sample_id`, so the join is fully determined. The join sequence is documented above
under Option B.
