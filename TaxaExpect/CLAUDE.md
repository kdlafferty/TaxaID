# CLAUDE.md — TaxaExpect
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-06-13 (Session 108 — generate_full_priors theta_epsilon auto-raise from singleton mirrors)

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
| `add_pca_covariates()` | Replace correlated `_s` covariate columns with orthogonal PCA scores; returns same structure as `prepare_model_dataframe()` output; stores `pca_rotation` attribute for prediction-time use | Complete | R/add_pca_covariates.R |
| `apply_pca_transform()` | Apply stored PCA rotation to scaled new-site data before `generate_full_priors()` | Complete | R/add_pca_covariates.R |
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
- Warns on multicollinearity > `cor_threshold`; call `add_pca_covariates()` on the result to fix.

### `add_pca_covariates(model_df, cor_threshold = 0.7, prefix = "PC")`
- Input: output of `prepare_model_dataframe()` (must have `_s` columns and `scale_params` attribute).
- Finds all `_s` column pairs with `|r| > cor_threshold`; applies PCA to all involved columns.
- Replaces involved `_s` columns with `<prefix>N_s` PC score columns (orthogonal by construction).
- Returns the same tibble structure suitable for `train_biodiversity_model()`.
- Attributes on output: `scale_params` (unchanged, original covariate entries); `pca_rotation` (list: `source_cols`, `pc_cols`, `rotation`, `center`, `prefix`).
- Returns input unchanged (with message) if no pairs exceed threshold.

### `apply_pca_transform(new_sites, pca_rotation)`
- Input: scaled new-site data frame (has `pca_rotation$source_cols` columns) + `pca_rotation` from `add_pca_covariates()` output attribute or `model_obj$pca_rotation`.
- Subtracts training center, applies rotation, replaces source columns with PC columns.
- Use before `generate_full_priors()` when model was trained with PCA covariates.

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
- **`theta_epsilon` auto-raise (Session 108):** When `undetected` is supplied and contains singleton-mirror rows, `theta_epsilon` is automatically raised to `mean(alpha/(alpha+beta))` across those rows if that value exceeds the default `1e-6`. This data-derived floor ensures Tier 2 sparse species (detected at least once in the system) always receive priors above the dark-diversity floor computed in `join_priors()`. Root cause fixed: a Tier 2 singleton with predicted theta ≈ 1e-6 was being promoted to dark_mean by `join_priors()`, producing priors identical to undetected species (e.g. `Syngnathus auliscus` vs `S. caribbaeus`). With the raise: `singleton_mirror_floor > dark_mean` (because dark_mean averages singleton mirrors + global floor, which is lower), so Tier 2 priors survive the promotion check unchanged.
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
- `add_pca_covariates()` and `apply_pca_transform()` implemented in Session 106 (see Supporting functions above)
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

**Session 79 (2026-05-20)**
- `sample_id` → `observation_id` ecosystem rename: TaxaExpect does not use this column
  directly; no source changes required.

**Session 80 (2026-05-20)**
- GitHub public monorepo created at github.com/kdlafferty/TaxaID; no package-specific changes.

**Session 81 (2026-05-21)**
- `habitat_observed_elsewhere` column → `observed_in_habitat` (43 occurrences across 9 files).
  TRUE = species recorded in this habitat type during training; FALSE = habitat extrapolation.
- `moran_k = 0` support added to `build_priors()`: skips Moran eigenvector computation entirely.
  Default remains 5. Useful for non-spatial data or debugging.
- `inst/TaxaExpect_supplemental_methods.md` renamed from `inst/methods_background.md`.

**Session 82 (2026-05-21)**
- License changed MIT → CC0 per USGS policy. DESCRIPTION updated; per-package LICENSE stub removed.
- `llm_fn` defaults updated to `getOption("TaxaID.llm_fn", call_anthropic_api)` in `build_priors()`.
- `leaflet`, `shiny`, `miniUI` moved from Imports to Suggests (only used in
  `plot_theta_map_interactive()` which already had `requireNamespace()` guards).

**Sessions 83–85 (2026-05-21 to 2026-05-23)**
- No TaxaExpect-specific changes. Ecosystem: `call_api()` generic dispatcher (TaxaTools),
  WERC review integration. See TaxaID/CLAUDE.md for full log.

**Session 86 (2026-05-23)**
- `build_priors()`: `llm_fn` fallback updated from `TaxaTools::call_anthropic_api` to
  `TaxaTools::call_api`. Clears TODO from Sessions 82/85.
- `DISCLAIMER.md` + `LICENSE.md` deleted from package root (centralised at TaxaID/ root).
- Disclaimer section removed from `README.md`.

Sessions 28, 29, 62, 73 archived in ecosystem_docs/session_notes/TaxaExpect_sessions.md.
