# CLAUDE.md — TaxaExpect
# Package-specific context. Ecosystem context is in TaxaID/CLAUDE.md (auto-loaded).
# Last updated: 2026-07-03 (habitat_col = NULL support added to optimize_grid_size()/prepare_model_dataframe()/train_biodiversity_model()/generate_undetected_diversity()/generate_full_priors() -- fixes a real Tier 2 fitting bug found testing a single-observation prior pipeline. SAME session, second bug found re-verifying the first fix: theta_epsilon's singleton-mirror auto-raise was clipping ALL tiers' predictions instead of just Tier 2, flattening real Tier 1 differentiation -- fixed by scoping the raised floor to Tier 2 only. See session notes below. Session 129 — screen_spatial_formula()/generate_full_priors() fixed to handle zero-Tier-1-species real data instead of crashing; non-ASCII em-dash in generate_undetected_diversity() fixed)

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
- Requires: `grid_id`, `lat_r`, `lon_r`, `habitat_col` (unless NULL), `taxon_name`.
- Returns tibble with: `grid_id`, `lat_r`, `lon_r`, `<habitat_col>`, `taxon_name`, `n_species`, `n_total_at_site`, `n_other`, `is_present`, `observed_in_habitat`, `<cov>_s` columns.
- Attaches `scale_params` as attribute (list of center/scale per covariate) for use at prediction time.
- Warns on multicollinearity > `cor_threshold`; call `add_pca_covariates()` on the result to fix.
- **`habitat_col = NULL`** (Session, 2026-07-03): opts out of habitat modeling entirely. No habitat
  column required in `data`, none in the output. Two-path design: if you have a habitat column, run
  `TaxaHabitat` and pass it here so habitat enters the model as a real predictor; if you don't, pass
  `NULL` rather than faking a single constant category (see `train_biodiversity_model()` below for
  why the fake-constant path is actively broken).

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
- **`habitat_col = NULL`** (Session, 2026-07-03): both Tier 1 and Tier 2 fit with no habitat term at
  all — Tier 2's formula becomes `cbind(n_species, n_other) ~ (1 | taxon_name)`. `data` must be the
  output of `prepare_model_dataframe(habitat_col = NULL)` (no habitat column). A formula with a
  `diag()` habitat term errors immediately if `habitat_col = NULL` (fail fast, not a silent
  misconfiguration). **Do not** work around a missing habitat classification by passing a single
  constant value through the real `habitat_col` argument — that previously broke Tier 2 fitting
  outright ("contrasts can be applied only to factors with 2 or more levels"), found 2026-07-03
  testing a single-observation prior pipeline that skipped `TaxaHabitat` to save cost. `habitat_col
  = NULL` is the only correct way to opt out.
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

### `generate_undetected_diversity(model_obj, taxonomy = NULL, jeffreys_threshold = 2L, singleton_ess = 2L)`
- Input: `biofreq_model` object.
- No habitat column on singleton-mirror/global-floor rows when `model_obj` was trained with
  `habitat_col = NULL`.
- **`taxonomy`** (Session 117): optional data frame with `taxon_name` + any subset of `{genus, family, order, class, phylum}` columns (e.g. `occurrences_std`). When supplied, taxonomy columns are joined onto singleton-mirror rows by `taxon_name` so that `join_priors()` hierarchical group priors can descend the taxonomy tree for singleton rows.
- Singleton mirrors: one proxy per singleton in training data; ESS controls diffuseness (`alpha = theta_obs * ESS`, `beta = (1 - theta_obs) * ESS`).
- Global floor: `Beta(1, N_total - 1)`; falls back to Jeffreys `Beta(0.5, 0.5)` when `N_total < jeffreys_threshold`.
- Returns tibble with `source_taxon_name` audit column linking each singleton mirror back to the observed species it was derived from. When `taxonomy` is supplied, also carries the joined taxonomy columns.

### `generate_full_priors(model_obj, new_sites, undetected = NULL, min_phi = 2, theta_epsilon = 1e-6)`
- `new_sites` must have: `grid_id`, `lat_r`, `lon_r`, `<habitat_col>` — unless `model_obj` was trained
  with `habitat_col = NULL`, in which case no habitat column is required or used, and the output has
  none either (`habitat_col` is read from `model_obj$meta$habitat_col`, not a direct argument here).
  Optionally `n_total_at_site` (for `effort_flag`).
- Covariates scaled using training `scale_params` (not re-scaled from `new_sites`).
- Alpha/beta via moment-matching; phi capped at `1 / grid_var` (Tier 1 `taxon_name:grid_id` variance).
- **`min_phi`** (default 2): phi floor. When the phi cap is very low (high grid variance), prevents modelled priors from becoming so diffuse that MC posterior simulation is unstable and modelled priors become less informative than dark-diversity fallbacks. Matches `singleton_ess` default in `generate_undetected_diversity()`.
- **`theta_epsilon` auto-raise (Session 108):** When `undetected` is supplied and contains singleton-mirror rows, `theta_epsilon` is automatically raised to `mean(alpha/(alpha+beta))` across those rows if that value exceeds the default `1e-6`. This data-derived floor ensures Tier 2 sparse species (detected at least once in the system) always receive priors above the dark-diversity floor computed in `join_priors()`. Root cause fixed: a Tier 2 singleton with predicted theta ≈ 1e-6 was being promoted to dark_mean by `join_priors()`, producing priors identical to undetected species (e.g. `Syngnathus auliscus` vs `S. caribbaeus`). With the raise: `singleton_mirror_floor > dark_mean` (because dark_mean averages singleton mirrors + global floor, which is lower), so Tier 2 priors survive the promotion check unchanged.
- Jeffreys fallback `Beta(0.5, 0.5)` when phi <= 0; flagged in `jeffreys_fallback` column.
- Appends `undetected` rows if supplied. Singleton-mirror rows in `undetected` carry `source_taxon_name` (Session 117); this column is preserved in the output and used by `join_priors(singleton_taxonomy=)` to re-join taxonomy for hierarchical group priors.

### `optimize_grid_size(observation_data, n_covariates, protected_habitat = NULL, min_s_threshold = 5, min_N_threshold = 10, min_distinct_locs = 20, min_locs_per_habitat = 3, min_grid = 0.1, max_grid = 1.0, step_grid = 0.05, lat_col = "decimalLatitude", lon_col = "decimalLongitude", species_col = "taxon_name", habitat_col = "main_habitat", weights = c(resolution = 0.4, quality = 0.4, stability = 0.2))`
- Returns named list: `$summary_table`, `$best_grid` (pass to `create_sites_from_grid`), `$explanation`, `$fallback_level` (`"none"`, `"A"`, `"B"`, `"C"`).
- Three fallback levels when no resolution meets `min_distinct_locs`.
- **`habitat_col = NULL`** (Session, 2026-07-03): resolutions scored on location count alone, no
  per-habitat stratification. Errors if `protected_habitat` is also supplied (incompatible). Uses an
  internal placeholder category to reuse the existing grouping/counting logic unchanged -- safe here
  specifically because this function never fits a model (unlike `train_biodiversity_model()`, where a
  placeholder instead of real `NULL` would still crash Tier 2).

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

**Session 123 (2026-07-01): Layer-1 workflow script**
- `inst/workflows/generate_priors_workflow.R` added — the modelling step is genuinely
  data-hungry (`optimize_grid_size()`'s real minimum-data thresholds; a binomial GLMM needs
  co-occurring species to estimate relative abundance), so DEBUG_MODE cannot use a sub-minute
  toy example the way TaxaFetch's/TaxaHabitat's scripts do. It tries TaxaHabitat's checkpoint
  first (with a species-breadth pre-flight check, not just a location-count one), and falls
  back to a wider live GBIF fetch (family Gadidae) when the upstream data is too narrow.
- Live-tested end to end (real GBIF fetch, real glmmTMB fit) as part of a 5-package chain.
  Six real bugs found and fixed by actually running it (none caught by reading alone) —
  hardcoded `compute_moran_basis()` k crashing on sparse grids; a `paste0()` zero-length-vector
  quirk silently building a formula term for a nonexistent column; `screen_spatial_formula()`'s
  `recommended_formula` being a character string, not a formula object (needs `as.formula()`);
  and more. Full list in `ecosystem_docs/LAYER1_WORKFLOWS.md` — read that before touching this
  script again, several of these are exactly the kind of thing that would silently recur.

**Session 129 (2026-07-03): screen_spatial_formula()/generate_full_priors() fixes for zero-Tier-1-species real data**

Both surfaced running `TaxaAssign::camera_trap_posterior_workflow.R`'s real GBIF-prior
pipeline on a small/sparse real dataset (all species below `min_obs_threshold`, so
`train_biodiversity_model()` legitimately produces `models$tier1 = NULL` by design).

- `screen_spatial_formula()` called `glmmTMB::VarCorr(model_full$models$tier1)`
  unconditionally at its VarCorr pre-screen step, crashing (`no applicable method for
  'VarCorr' applied to an object of class 'NULL'`) whenever this happened. Fixed with an
  early-return guard — same "nothing to screen, return the fitted model as-is" pattern
  the function already used for formulas with no screenable spatial terms.
- `generate_full_priors()` then failed downstream with "no predictions generated": when
  `models$tier2` is also `NULL` (Tier 2 GLMM failed to fit, e.g. a single-level habitat
  factor), `predict_tier()` returns `NULL` for every candidate, even though
  `train_biodiversity_model()`'s own docs promise "Tier 2 species will fall back to
  empirical means" — nothing downstream ever consumed `$tier2_empirical` to actually do
  that. Added `predict_tier_empirical()`, using the same moment-matching helper the GLMM
  path already uses; wired in as the fallback specifically when `models$tier2` is `NULL`.
  Not spatially resolved (no GLMM to interpolate from), and only covers species x habitat
  combinations with at least one positive training detection — species with zero
  detections still correctly fall through to `generate_undetected_diversity()`'s
  dark-diversity handling, unchanged.

Both verified against synthetic reproductions of the exact failure conditions, and
against the full TaxaExpect test suite (386 expectations, 0 failures, both before and
after). Separately, `devtools::check()` found a pre-existing non-ASCII em-dash in
`generate_undetected_diversity()`'s warning text (unrelated to the above, same fix
pattern as TaxaAssign's Session 122 ASCII cleanup) — fixed, `check()` now 0/0/0.

**Session (2026-07-03): habitat_col = NULL support -- fixes a real Tier 2 fitting bug found designing a single-observation prior pipeline**

Found while testing whether TaxaExpect's community-level prior pipeline could be run on
a *narrow*, candidate-only occurrence fetch as a stand-in for a full regional model (part
of `single-observation-pipeline` branch design work, not yet merged). Skipping
`TaxaHabitat` (to avoid the LLM cost for a small ad hoc species list) and hardcoding
`main_habitat` to one constant value broke `train_biodiversity_model()`'s Tier 2 fit
outright: `Error: contrasts can be applied only to factors with 2 or more levels`. Root
cause: Tier 2's formula was hardcoded inside the function
(`cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)`, `habitat_col` not
nullable) with no way for a caller to opt out — asymmetric with Tier 1, whose formula is
built by the *calling script* and already had an `if (n_habitat_levels >= 2L)` guard, but
that guard lived outside the package and only ever covered Tier 1.

Confirmed with the user this was a known recurring pain point ("I have encountered this
problem with the habitat model before"), and agreed on a two-path design: if you have a
habitat column, run `TaxaHabitat` and supply it so habitat enters the model as a real
predictor; if you don't, pass `habitat_col = NULL` and skip habitat entirely, rather than
faking a single hardcoded category.

**Changes**, all four touching `habitat_col`:
- `prepare_model_dataframe(habitat_col = NULL)`: uses a single internal placeholder
  column so existing aggregation logic runs unchanged, then drops it from the final
  output entirely (no habitat column at all) instead of exposing it.
- `train_biodiversity_model(habitat_col = NULL)`: the real fix. Tier 2's formula omits
  the habitat term entirely (`cbind(n_species, n_other) ~ (1 | taxon_name)`) instead of
  hardcoding one. `N_total`, singleton identification, and `tier2_empirical` all branch
  on `is.null(habitat_col)` rather than assuming a habitat column exists. A formula with
  a `diag()` habitat term now errors immediately and specifically
  (`"habitat_col = NULL was supplied"`) if `habitat_col = NULL`, checked right after
  formula validation so it fires before the generic "column not found" error would.
- `generate_undetected_diversity()`: singleton-mirror/global-floor rows skip adding a
  habitat column when `model_obj$meta$habitat_col` is `NULL` (two direct
  `df[[habitat_col]] <-` assignments would otherwise error on a NULL subscript). The
  `taxonomy` join (genus/family/order/class/phylum hierarchy) is unaffected.
- `generate_full_priors()`: the most deeply embedded — `observed_combos` lookup,
  `predict_tier()`/`predict_tier_empirical()`'s site-column vectors, and both final
  `select()` calls all read `habitat_col` from `model_obj$meta$habitat_col` and now
  branch throughout. `predict_tier_empirical()`'s join to prediction sites becomes a
  cross join (`tidyr::crossing()`) rather than a keyed join when there is no habitat
  column to join on, since `tier2_empirical` then carries one row per taxon with no
  location dimension at all.

9 new tests across all four functions' test files, covering the specific regression
(Tier 2 must fit successfully with no habitat term, not error), the `diag()`-term/NULL
conflict error, and end-to-end `generate_full_priors()` output with no habitat column.
Full suite: `devtools::test()` reports 378 passing, 0 failing. `devtools::check()`:
0 errors, 0 warnings, 0 notes.

**Not done**: no ecosystem workflow script was changed to actually use
`habitat_col = NULL` yet (this was a package-level fix, not a workflow rewrite); the
`single-observation-pipeline` branch design work that surfaced this is still in progress
and unmerged.

**Second, unrelated bug found and fixed the same session while re-verifying the fix above against real data**: user asked, correctly, why priors for six real bobcat-photo candidates (*Canis latrans*, *Felis catus*, *Lynx rufus*, *Procyon lotor*, *Puma concolor*, *Urocyon cinereoargenteus*) all came out as the exact same `theta_mean` (0.0530) despite wildly different real detection counts (*Canis latrans*: 688 total detections, 6 at the focal grid cell alone; *Urocyon cinereoargenteus*: 27 total, 0 at that cell). Confirmed via `ranef()` that the fitted model itself had real, well-differentiated per-species random intercepts (+2.55 to -0.59 logit units) -- so the bug was downstream, in `generate_full_priors()`, not in model fitting. Isolated by manually replicating `predict_tier()`'s exact internal steps outside the function (correctly differentiated) versus calling the real exported function (flattened) -- the only difference was `theta_epsilon`'s singleton-mirror-derived auto-raise (Session 108), confirmed by testing with `undetected = NULL` (bypasses the raise entirely): predictions became correctly differentiated and matched hand-computed values almost exactly.

Root cause: the auto-raised `theta_epsilon` floor (here, 0.053 -- the mean singleton-mirror detection rate) was applied as a hard clip (`moment_match()`'s `m <- pmax(pmin(m, 1-epsilon), epsilon)`) to **every** tier's predictions, not just Tier 2 (the only tier it was ever meant to protect, per its own original design rationale -- preventing Tier 2 from being conflated with the dark-diversity floor in `join_priors()`). With a broadened, realistic candidate pool (21 real species, the point of the single-observation-pipeline broadening work), many genuinely low-but-differentiated Tier 1 probabilities fell below 0.053 and all collapsed to that identical floor value -- invisible with a small, well-separated candidate list (which is why this was never caught before), very visible and wrong with a more realistic one.

Fix: split into `theta_epsilon` (base, applied to Tier 1 predictions as supplied -- default `1e-6`) and `theta_epsilon_floor` (the auto-raised value, applied only to Tier 2's GLMM predictions and to `predict_tier_empirical()`'s fallback). `predict_tier()`/`predict_tier_empirical()` now take an explicit `epsilon` argument instead of closing over one shared variable. New regression test asserts Tier 1 output is byte-identical whether or not `undetected` is supplied (the thing that triggers the raise) -- directly encodes the invariant the bug violated. Full suite: 379 passing (up one), `devtools::check()`: 0/0/0.

Re-verified end-to-end against the real bobcat-photo data with both fixes applied together: Tier 2 fits (first fix), and priors are now genuinely differentiated in the correct rank order matching raw detection counts (*Canis latrans* highest at 0.0077, *Urocyon cinereoargenteus* lowest at 0.00089).

**Third change, same session, before committing**: user asked to assess whether `optimize_grid_size()` (which also requires `habitat_col` unconditionally, discovered while re-verifying the above) should get the same `habitat_col = NULL` treatment, or whether a placeholder constant habitat value upstream would be simpler. Traced `.score_one_resolution()`'s internals to answer precisely: this function never fits a statistical model, only groups/counts, so a constant placeholder would *not* trigger the Tier-2-style crash here -- but that same placeholder, if passed through by name to `train_biodiversity_model()`, would still trigger it there, meaning a placeholder-based approach requires two different "no habitat" conventions in one pipeline (real placeholder for grid sizing, genuine `NULL` for model fitting). Decided against that: extended `habitat_col = NULL` to `optimize_grid_size()` too, for one consistent convention across all three functions.

Implementation: `no_habitat <- is.null(habitat_col)`; errors clearly if `protected_habitat` is supplied with `habitat_col = NULL` (incompatible); otherwise injects a single internal placeholder category (safe here specifically because no model is fit) so `.score_one_resolution()`'s grouping/counting logic runs unchanged, with `min_locs_per_habitat` becoming redundant with (not contradictory to) `min_distinct_locs`. 4 new tests (basic run, `protected_habitat` conflict error, and an equivalence check that a single real habitat category scores identically to `habitat_col = NULL`). Full suite: 383 passing, `devtools::check()`: 0/0/0.

Final end-to-end re-verification with all three fixes chained together, no workarounds: `optimize_grid_size(habitat_col = NULL)` -> `create_sites_from_grid()` -> `prepare_model_dataframe(habitat_col = NULL)` -> `train_biodiversity_model(habitat_col = NULL)` -> `generate_undetected_diversity()` -> `generate_full_priors()`, against the real bobcat-photo data. Confirmed Tier 2 fits and priors are genuinely differentiated in the correct rank order.

Sessions 28, 29, 62, 73 archived in ecosystem_docs/session_notes/TaxaExpect_sessions.md.
