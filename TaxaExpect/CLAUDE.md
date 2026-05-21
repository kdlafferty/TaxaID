# CLAUDE.md — TaxaExpect
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-05-19 (Session 77 — census_genera param in build_priors; GBIF genus census attribute)

---

## Package Purpose
Generates prior probability objects using occurrence and habitat data to estimate
detection probability (theta) for a taxon at a particular location. Provides tools
for spatial gridding, biodiversity modelling (binomial GLMM), and prior generation
for input to TaxaAssign.

Split note: data acquisition moved to TaxaFetch (Session 19); habitat assignment and
spatial QAQC moved to TaxaHabitat (Session 28). TaxaExpect retains gridding, modelling,
and prior generation only.

---

## Function Inventory

### Core pipeline

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `create_sites_from_grid()` | Snap lat/lon to grid cells; add `lat_r`, `lon_r`, `grid_id` | Complete | R/create_sites_from_grid.R |
| `prepare_model_dataframe()` | Aggregate occurrences to species × site-habitat counts; zero-fill; scale covariates | Complete | R/prepare_model_dataframe.R |
| `train_biodiversity_model()` | Fit Tier 1/2 binomial GLMM; return `biofreq_model` S3 object | Complete | R/train_biodiversity_model.R |
| `generate_undetected_diversity()` | Tier 3 proxy priors: singleton mirrors + global floor | Complete | R/generate_undetected_diversity.R |
| `generate_full_priors()` | Predict theta at all taxon × site × habitat; return Beta(alpha, beta) prior table | Complete | R/generate_full_priors.R |

### High-level wrapper

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `build_priors()` | End-to-end pipeline: GBIF fetch → habitat → grid → model → priors → backbone translation (~18 calls → 1). Params include `search_rank` (default "family"), `max_coord_uncertainty` (default 500m), `min_phi` (default 2), `census_genera` (default TRUE — GBIF genus census attached as attribute). | Complete | R/build_priors.R |

### Supporting functions

| Function | Purpose | Status | Source file |
|---|---|---|---|
| `optimize_grid_size()` | Score grid resolutions on coverage, quality, stability; return best size + fallback | Complete | R/optimize_grid_size.R |
| `compute_moran_basis()` | Build Moran Eigenvector Maps (MEM) for spatial autocorrelation covariates | Complete | R/compute_moran_basis.R |
| `screen_spatial_formula()` | Fit full spatial model, screen Moran/gradient slopes by VarCorr SD, select parsimonious formula by AIC | Complete | R/screen_spatial_formula.R |
| `plot_theta_map_interactive()` | Shiny gadget: Leaflet heatmap of `theta_mean` with occurrence point overlay | Complete | R/plot_theta_map_interactive.R |

### S3 methods

| Function | Purpose | Source file |
|---|---|---|
| `print.biofreq_model()` | Compact summary of tiers, formula, convergence | R/train_biodiversity_model.R |
| `summary.biofreq_model()` | print + tier assignments + habitat screening table | R/train_biodiversity_model.R |

---

## Function Signatures

### `create_sites_from_grid(data, grid_size, lat_col = "decimalLatitude", lon_col = "decimalLongitude")`
- Adds `lat_r`, `lon_r`, `grid_id` columns. `grid_id` format: `"Grid_{lat_r}_{lon_r}"` with `.` → `p`, `-` → `m`.
- `grid_size > 10` triggers a warning (likely km not degrees).
- **Strict rule:** `grid_id` encodes location only — never habitat.

### `prepare_model_dataframe(data, covariates = c("lat_r", "lon_r"), habitat_col = "main_habitat", cor_threshold = 0.7)`
- Requires: `grid_id`, `lat_r`, `lon_r`, `habitat_col`, `taxon_name`.
- Returns tibble with: `grid_id`, `lat_r`, `lon_r`, `<habitat_col>`, `taxon_name`, `n_species`, `n_total_at_site`, `n_other`, `is_present`, `observed_in_habitat`, `<cov>_s` columns.
- Attaches `scale_params` as attribute (list of center/scale per covariate) for use at prediction time.
- Warns on multicollinearity > `cor_threshold`; suggests `add_pca_covariates()`.

### `train_biodiversity_model(data, formula, taxon_col = "taxon_name", habitat_col = "main_habitat", response = c("theta", "psi"), min_obs_threshold = 5L, effort_threshold = 10L, min_positive_rows = 50L, full_data = NULL)`
- **Tier 1** (>= `min_obs_threshold` detections): full user-supplied formula with habitat screening.
- **Tier 2** (< threshold): auto intercept-only formula `cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)`.
- `diag(main_habitat | taxon_name)` in user formula is a placeholder — rewritten to indicator-based slopes per supported habitat.
- Returns `biofreq_model` S3 object (see below).
- **Recommended formula:**
  ```
  cbind(n_species, n_other) ~
    main_habitat +
    (1 | taxon_name) +
    diag(main_habitat | taxon_name) +
    (0 + lat_r_s | taxon_name) +
    (0 + lon_r_s | taxon_name) +
    (1 | taxon_name:grid_id)
  ```

### `generate_undetected_diversity(model_obj, jeffreys_threshold = 2L, singleton_ess = 2L)`
- Input: `biofreq_model` object.
- Singleton mirrors: one proxy per singleton in training data; ESS controls diffuseness (`alpha = theta_obs * ESS`, `beta = (1 - theta_obs) * ESS`).
- Global floor: `Beta(1, N_total - 1)`; falls back to Jeffreys `Beta(0.5, 0.5)` when `N_total < jeffreys_threshold`.
- Returns tibble with `source_taxon_name` audit column (not passed to TaxaAssign).

### `generate_full_priors(model_obj, new_sites, undetected = NULL, min_phi = 2, theta_epsilon = 1e-6)`
- `new_sites` must have: `grid_id`, `lat_r`, `lon_r`, `<habitat_col>`. Optionally `n_total_at_site` (for `effort_flag`).
- Covariates scaled using training `scale_params` (not re-scaled from `new_sites`).
- Alpha/beta via moment-matching; phi capped at `1 / grid_var` (Tier 1 `taxon_name:grid_id` variance).
- **`min_phi`** (default 2): phi floor. When the phi cap is very low (high grid variance), prevents modelled priors from becoming so diffuse that MC posterior simulation is unstable and modelled priors become less informative than dark-diversity fallbacks. Matches `singleton_ess` default in `generate_undetected_diversity()`.
- Jeffreys fallback `Beta(0.5, 0.5)` when phi <= 0; flagged in `jeffreys_fallback` column.
- Appends `undetected` rows if supplied.

### `optimize_grid_size(observation_data, n_covariates, protected_habitat = NULL, min_s_threshold = 5, min_N_threshold = 10, min_distinct_locs = 20, min_locs_per_habitat = 3, min_grid = 0.1, max_grid = 1.0, step_grid = 0.05, lat_col = "decimalLatitude", lon_col = "decimalLongitude", species_col = "taxon_name", habitat_col = "main_habitat", weights = c(resolution = 0.4, quality = 0.4, stability = 0.2))`
- Returns named list: `$summary_table`, `$best_grid` (pass to `create_sites_from_grid`), `$explanation`, `$fallback_level` (`"none"`, `"A"`, `"B"`, `"C"`).
- Three fallback levels when no resolution meets `min_distinct_locs`.

### `screen_spatial_formula(data, formula_full, sd_threshold = 0.20, delta_aic_max = 2.0, verbose = TRUE, ...)`
- Runs after `compute_moran_basis()` + `prepare_model_dataframe()`, before `train_biodiversity_model()` for final fit.
- Two-stage: VarCorr pre-screen (flags near-zero SD slopes) → AIC comparison of up to 4 candidate models.
- Returns a `biofreq_model` object (the recommended model) with `$model_selection` appended.
- `$model_selection` contains: `aic_table`, `recommended_formula`, `flagged_terms`, `sd_table`.
- `...` passed to `train_biodiversity_model()` (e.g. `effort_threshold`, `min_obs_threshold`).

### `compute_moran_basis(grid_ids, k = 10L, distance_threshold = NULL, min_neighbours = 1L)`
- Returns data frame: `grid_id`, `B1`, `B2`, ..., `Bk` (MEM columns, largest eigenvalue first).
- `distance_threshold = NULL` auto-inferred as 1.5× minimum coordinate spacing.
- Join result to model data before calling `prepare_model_dataframe()`.

### `plot_theta_map_interactive(priors, occurrences, occurrence_habitat_col = "main_habitat", tile = "Esri.OceanBasemap", theta_col = "theta_mean", grid_opacity = 0.7, point_radius = 4, point_color = "#ff6600")`
- Returns `NULL` invisibly. For exploration only.
- `occurrences = NULL` suppresses occurrence points.
- `occurrence_habitat_col = NULL` disables habitat colouring on points.

---

## `biofreq_model` S3 Object

Named list, class `"biofreq_model"`:

| Slot | Type | Contents |
|---|---|---|
| `$models$tier1` | glmmTMB / NULL | Fitted Tier 1 model |
| `$models$tier2` | glmmTMB / NULL | Fitted Tier 2 model |
| `$tiers` | tibble | `taxon_name`, `tier` ("tier1"/"tier2"), `n_detections` |
| `$scale_params` | named list | Per-covariate `$center` and `$scale` |
| `$singletons` | data frame | Species seen exactly once (for Tier 3) |
| `$N_total` | integer | Sum of `n_total_at_site` across effort-passing cells |
| `$tier2_empirical` | data frame | Empirical theta mean/SD fallback for Tier 2 |
| `$habitat_screening` | list | `$supported`, `$sparse`, `$indicators`, `$min_positive_rows`, `$summary`, `$formula_used` |
| `$convergence_warnings` | character vector | Captured glmmTMB warnings |
| `$meta` | named list | `taxon_col`, `habitat_col`, `response`, thresholds, formulas, `n_sites`, `n_species_tier1`, `n_species_tier2` |

---

## Prior Object (output of `generate_full_priors()`)

Tibble, one row per taxon × site × habitat (plus Tier 3 proxies):

| Column | Type | Description |
|---|---|---|
| `taxon_name` | character | Taxon identifier (NA for undetected proxies) |
| `grid_id` | character | Spatial cell identifier |
| `main_habitat` | character | Site-level habitat category (column name follows `habitat_col` param set during training; default `"main_habitat"`) |
| `alpha` | numeric | Beta prior alpha parameter |
| `beta` | numeric | Beta prior beta parameter |
| `theta_mean` | numeric | `alpha / (alpha + beta)` |
| `theta_sd` | numeric | SD of Beta(alpha, beta) |
| `n_obs` | integer | `n_total_at_site` if supplied in `new_sites`, else NA |
| `model_tier` | character | `"tier1"`, `"tier2"`, or `"tier3_undetected"` |
| `effort_flag` | logical | TRUE if N < `effort_threshold`; NA if N not supplied |
| `observed_in_habitat` | logical | TRUE if taxon ever recorded in this habitat in training data |
| `extrapolation_warning` | logical | TRUE if any covariate |z| > 3 at this site |
| `undetected_type` | character | NA (modelled); `"singleton_mirror"`; `"global_floor"` |
| `jeffreys_fallback` | logical | TRUE if Jeffreys Beta(0.5, 0.5) used (variance too large) |

---

## Typical Workflow

```r
# 1. Grid occurrences (from TaxaFetch + TaxaHabitat)
sites  <- create_sites_from_grid(occurrences, grid_size = 0.5)

# 2. Optional: check grid resolution
opt    <- optimize_grid_size(occurrences, n_covariates = 3)
sites  <- create_sites_from_grid(occurrences, grid_size = opt$best_grid)

# 3. Optional: Moran basis for spatial autocorrelation
basis  <- compute_moran_basis(unique(sites$grid_id), k = 10L)
sites  <- dplyr::left_join(sites, basis, by = "grid_id")

# 4. Prepare model data
mdf    <- prepare_model_dataframe(sites, habitat_col = "main_habitat")

# 5. Optional: screen spatial formula for parsimony
full_formula <- cbind(n_species, n_other) ~
  main_habitat + (1 | taxon_name) +
  (0 + B1 | taxon_name) + (0 + B2 | taxon_name) + (0 + B3 | taxon_name) +
  (0 + lat_r_s | taxon_name) + (0 + lon_r_s | taxon_name) +
  (1 | taxon_name:grid_id)
screened <- screen_spatial_formula(mdf, full_formula, effort_threshold = 10L)
# screened$model_selection$recommended_formula is the parsimonious formula

# 6. Fit model (or use screened directly)
formula <- cbind(n_species, n_other) ~
  main_habitat + (1 | taxon_name) +
  diag(main_habitat | taxon_name) +
  (0 + lat_r_s | taxon_name) + (0 + lon_r_s | taxon_name) +
  (1 | taxon_name:grid_id)
mod     <- train_biodiversity_model(mdf, formula)

# 6. Undetected diversity priors
undet   <- generate_undetected_diversity(mod)

# 7. Generate prior table
priors  <- generate_full_priors(mod, new_sites = sites, undetected = undet)

# 8. Explore
plot_theta_map_interactive(priors, occurrences)
```

---

## Key Design Notes
- `grid_id` encodes **location only** — habitat is never part of the identifier
- `observed_in_habitat` is computed from positive detections only, before zero-filling
- **Phi cap + floor:** `generate_full_priors()` caps phi at `1 / grid_var` (the model's own estimate of grid-level uncertainty) and floors at `min_phi` (default 2). The cap prevents overconfidence; the floor prevents MC instability when grid variance is high.
- **`search_rank`** in `build_priors()`: controls what taxonomic rank GBIF queries are made at (default "family"). Species-level names are still verified against GBIF backbone first to resolve cross-backbone disagreements (e.g. Girellidae→Kyphosidae), then collapsed to unique families for querying.
- **`max_coord_uncertainty`** in `build_priors()`: passed to `filter_gbif_quality()` (default 500m). Endangered species often have intentionally degraded coordinates (~28km); a species purge warning is emitted when taxa lose ≥80% or 100% of records.
- **`search_center` attribute:** `build_priors()` attaches `attr(out, "search_center") <- list(lat, lon)` to both the return list and the `$priors` data frame. Used by `TaxaAssign::join_priors()` as the default site when `site = NULL`.
- `add_pca_covariates()` is referenced in warnings but **not yet implemented** in this package
- `assign_habitat_to_points()` and `assign_habitat_biological()` are now in **TaxaHabitat**, not TaxaExpect

---

## `spatial_flag` Values (historical; spatial QAQC now in TaxaHabitat)
| Value | Meaning |
|---|---|
| `"likely"` | Spatially credible (was `"ok"` before Session 22) |
| `"questionable"` | Needs review (was `"suspect"`) |
| `"unlikely"` | Probable error (was `"likely_error"`) |

---

## Test Coverage

⚠️ Test coverage is incomplete. Known issue: `test-generate_undetected_diversity.Rscreen_spatial_formula.R`
is a malformed filename in `tests/testthat/` — investigate and rename before running `devtools::check()`.

---

## Key Dependencies

| Package | Used for |
|---|---|
| glmmTMB | Binomial GLMM fitting (Tier 1 and Tier 2 models) |
| dplyr | Data manipulation throughout |
| tidyr | `complete()` for zero-filling, `crossing()` for prediction grid |
| rlang | NSE (`sym`, `:=`) |
| stats | `predict()`, `plogis()`, `binomial()`, `as.formula()` |
| shiny / miniUI | `plot_theta_map_interactive()` gadget |
| leaflet / leaflet.extras | Interactive map rendering |
| stringr | `grid_id` string manipulation in `create_sites_from_grid()` |
| tibble | `tibble()` in `generate_undetected_diversity()` |

---

## Renaming Log

| Old Name | New Name | Date | Notes |
|---|---|---|---|
| `integrate_local_sources` | `combine_occurrence_sources` | 2026-02-27 | — |
| `make_hierarchical_habitat_prompt` | `build_habitat_prompt` | 2026-02-27 | Moved to TaxaFetch, then TaxaHabitat |
| `call_anthropic_api` | `prompt_api` | 2026-02-27 | Moved to TaxaFetch, then TaxaTools |
| `submit_manual` | `prompt_manual` | 2026-02-27 | Moved to TaxaFetch, then TaxaTools |
| `make_habitat_prompt` | *(deleted)* | 2026-02-27 | Flat pipeline removed |
| `assign_habitat_llm` | *(deleted)* | 2026-02-27 | — |
| `parse_habitat_response` | *(deleted)* | 2026-02-27 | — |
| `build_neighbor_graph` | *(deleted)* | 2026-03-01 | Superseded |
| `compute_species_amplitude` | *(deleted)* | 2026-03-01 | Superseded |
| `update_theta_local` | *(deleted)* | 2026-03-01 | Superseded |
| `calibrate_prior_cap` | *(deleted)* | 2026-03-01 | Superseded |
| `combine_occurrence_sources` | *(retired)* | 2026-03-13 | Replaced by `rename_cols()` + `stack_occurrences()` |
| habitat/spatial functions | Moved to TaxaHabitat | 2026-03-26 | Session 28 |

---

## Session Notes

**Session 77 (2026-05-19)**
- `build_priors()`: added `census_genera` parameter (default TRUE). After Stage 1
  (`create_taxon_names()`), extracts unique `genusKey` values from GBIF occurrence
  data and calls `TaxaTools::census_genus_species()` to enumerate described species
  per genus. Census attached as `attr(output, "gbif_genus_census")` on both the
  return list and `$priors` data frame.
- No additional GBIF API calls for key resolution — `genusKey` is free in occurrence records.
- Census enables three-tier H2 phantom suppression in `TaxaAssign::run_bayesian_pipeline()`.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 73 (2026-05-14)**
- `generate_full_priors()`: added `min_phi` parameter (default 2). Phi floor applied after
  phi cap in `moment_match()`. Prevents modelled priors from becoming so diffuse that MC
  posterior simulation is unstable. Messaging updated: warns when phi cap < min_phi.
- `build_priors()`: added `search_rank` parameter (default "family"). `.translate_to_gbif()`
  verifies species against GBIF backbone, then collapses to unique values at `search_rank`
  for GBIF occurrence queries. Fixes missing unreferenced species (e.g. F. parvipinnis).
- `build_priors()`: added `max_coord_uncertainty` parameter (default 500m), passed to
  `filter_gbif_quality()`. Species purge warnings emitted when taxa lose ≥80% or 100%
  of records after quality filtering (e.g. endangered species with degraded coordinates).
- `build_priors()`: added `min_phi` parameter, passed to `generate_full_priors()`.
- `build_priors()`: attaches `search_center` attribute (lat/lon) to both the return list
  and `$priors` data frame, enabling `TaxaAssign::join_priors()` to default to the build
  location when `site = NULL`.
- `.translate_to_gbif()`: fixed silent early return caused by `change_backbone()` renaming
  `input_col` ("user_supplied_name") to "source_name". Removed stale column name check.
- `devtools::check()`: 0 errors, 0 warnings, 0 notes.

**Session 62 (2026-04-30)**
- `build_priors()`: habitat scheme messaging added at Stage 2. Prints scheme label
  (e.g., "3-category (Marine / Freshwater / Terrestrial)") and how to change it
  (`habitat_scheme = 'IUCN_L1'` or custom data frame). Scheme label resolved from
  NULL/string/data.frame input.
- `build_priors()`: `attr(output, "habitat_scheme")` attached to return list for
  downstream functions to inspect.
- `devtools::check()`: 0 errors, 0 warnings, 1 note (benign timestamp)

**Session 29 (2026-03-27)**
- `screen_spatial_formula()` moved from TaxaHabitat to TaxaExpect
  - Belongs with biodiversity modelling pipeline, not habitat assignment
  - `utils::globalVariables("train_biodiversity_model")` removed (same package now)
  - `@seealso` updated to use `\link{}` for `train_biodiversity_model` and `compute_moran_basis`
  - `glmmTMB` removed from TaxaHabitat DESCRIPTION Imports
  - Test file restored as `test-screen_spatial_formula.R`
- `utils_plot.R` added (`.he`, `.habitat_palette` helpers for `plot_theta_map_interactive`)
- Stale Imports removed from DESCRIPTION (TaxaFetch, TaxaTools, httr2, sf, terra, etc.)
- `.Rbuildignore` updated; Rd cross-ref warnings fixed; `@importFrom stats cor` added

**Session 28 (2026-03-26)**
- Full function inventory completed; all 8 exported functions documented with exact signatures
- Prior object canonical columns confirmed from `generate_full_priors()` source
- `biofreq_model` S3 structure documented from `train_biodiversity_model()` source
- ⚠️ DESCRIPTION likely has stale Imports post-split (sf, terra, marmap, rnaturalearth* may not
  be directly needed); run `devtools::check()` before next submission
- ⚠️ Malformed test filename: `test-generate_undetected_diversity.Rscreen_spatial_formula.R`
  needs investigation
- ⚠️ NAMESPACE may still export functions moved to TaxaHabitat; run `devtools::document()` first
