# TaxaExpect Session Notes Archive
# Sessions 28–73. Current sessions live in TaxaExpect/CLAUDE.md.

**Session 28 (2026-03-26)**
- Full function inventory completed; all 8 exported functions documented with exact signatures
- Prior object canonical columns confirmed from `generate_full_priors()` source
- `biofreq_model` S3 structure documented from `train_biodiversity_model()` source
- ⚠️ DESCRIPTION likely has stale Imports post-split (sf, terra, marmap, rnaturalearth* may not
  be directly needed); run `devtools::check()` before next submission
- ⚠️ Malformed test filename: `test-generate_undetected_diversity.Rscreen_spatial_formula.R`
  needs investigation
- ⚠️ NAMESPACE may still export functions moved to TaxaHabitat; run `devtools::document()` first

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

**Session 62 (2026-04-30)**
- `build_priors()`: habitat scheme messaging added at Stage 2. Prints scheme label
  (e.g., "3-category (Marine / Freshwater / Terrestrial)") and how to change it
  (`habitat_scheme = 'IUCN_L1'` or custom data frame). Scheme label resolved from
  NULL/string/data.frame input.
- `build_priors()`: `attr(output, "habitat_scheme")` attached to return list for
  downstream functions to inspect.
- `devtools::check()`: 0 errors, 0 warnings, 1 note (benign timestamp)

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
