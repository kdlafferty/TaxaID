# =============================================================================
# TaxaExpect end-to-end workflow
# =============================================================================
#
# INPUT:  occurrences_with_habitat -- output of TaxaFetch Habitat_assign_workflow.R
#         (loaded from TaxaFetch/inst/occurrences_with_habitat.rds, or in environment)
#
# OUTPUT: Two objects saved to TaxaExpect/inst/ for use in TaxaAssign:
#   taxaexpect_priors.rds  -- prior table (NCBI backbone); input to TaxaAssign Bayesian
#   model_fit.rds          -- fitted biofreq_model; needed for prediction at new sites
#
#   Model priors (GBIF)    --> change_backbone --> NCBI (id=4)  for TaxaAssign
#
# DEPENDENCIES:
#   TaxaTools, TaxaExpect, dplyr
#
# =============================================================================

library(TaxaTools)
library(TaxaExpect)
library(dplyr)


# =============================================================================
# 0.  USER INPUTS  -- edit this section only
# =============================================================================

moran_k      <- 5L     # number of Moran eigenvectors to compute
sd_threshold <- 0.20   # VarCorr SD threshold for screening random slopes
rank_system <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")

# Load upstream data (from TaxaFetch Habitat_assign_workflow.R)
occurrences_with_habitat <-
readRDS(file.choose())  # select occurrences_clean.rds from TaxaHabitat/inst/


# =============================================================================
# 1.  OPTIMISE GRID SIZE AND CREATE SITES
# =============================================================================

n_covariates <- 2L
message("\n--- Step 1: Optimising spatial grid ---")

grid_result <- optimize_grid_size(
  observation_data = occurrences_with_habitat,
  n_covariates     = n_covariates
)

message(sprintf("  Selected grid size: %.2f degrees.", grid_result$best_grid))
message(sprintf("  %s", grid_result$explanation))

occurrences_gridded <- create_sites_from_grid(
  occurrences_with_habitat,
  grid_size = grid_result$best_grid
)


# =============================================================================
# 2.  PREPARE MODEL DATAFRAME
# =============================================================================

message("\n--- Step 2: Preparing model dataframe ---")

model_data <- prepare_model_dataframe(occurrences_gridded)

message(sprintf("  Model dataframe: %d rows, %d species, %d sites.",
                nrow(model_data),
                dplyr::n_distinct(model_data$taxon_name),
                dplyr::n_distinct(model_data$grid_id)))


# =============================================================================
# 3.  COMPUTE MORAN SPATIAL BASIS
# =============================================================================
# Moran eigenvectors capture intermediate-scale spatial patchiness that linear
# lat/lon gradients miss. The full model starts with moran_k eigenvectors;
# Step 4 screens which (if any) are worth retaining.

message("\n--- Step 3: Computing Moran spatial basis ---")

basis <- compute_moran_basis(
  grid_ids = unique(model_data$grid_id),
  k        = moran_k
)
# basis has columns: grid_id, B1 ... B{moran_k}

model_data <- dplyr::left_join(model_data, basis, by = "grid_id")

message(sprintf("  %d Moran eigenvectors joined to model data.", moran_k))


# =============================================================================
# 4.  SELECT SPATIAL FORMULA AND TRAIN MODEL
# =============================================================================
# screen_spatial_formula() fits the full model, screens random slope terms
# by VarCorr SD, runs a small targeted AIC comparison, and returns the
# recommended parsimonious model.  model_fit flows into Steps 5+ unchanged.

message("\n--- Step 4: Selecting spatial formula and training model ---")

model_formula_full <- cbind(n_species, n_other) ~
  main_habitat +
  (1 | taxon_name) +
  diag(main_habitat | taxon_name) +
  (0 + B1 | taxon_name) +
  (0 + B2 | taxon_name) +
  (0 + B3 | taxon_name) +
  (0 + B4 | taxon_name) +
  (0 + B5 | taxon_name) +
  (0 + lat_r_s | taxon_name) +
  (0 + lon_r_s | taxon_name) +
  (1 | taxon_name:grid_id)

model_fit <- screen_spatial_formula(
  data          = model_data,
  formula_full  = model_formula_full,
  sd_threshold  = sd_threshold,
  delta_aic_max = 2.0,
  verbose       = TRUE
)

# Inspect the selection table if needed:
# model_fit$model_selection$aic_table
# model_fit$model_selection$recommended_formula
# model_fit$model_selection$sd_table

message(sprintf("  Tier assignment: %d Tier 1, %d Tier 2.",
                sum(model_fit$tiers$tier == "tier1"),
                sum(model_fit$tiers$tier == "tier2")))


# =============================================================================
# 5.  GENERATE PRIORS
# =============================================================================
# generate_full_priors() automatically:
#   - Reads model_fit$habitat_screening and adds indicator columns to new_sites
#   - Derives phi cap from taxon_name:grid_id variance (no user parameters needed)
#   - Applies BLUPs for in-sample grids; spatial surface for out-of-sample grids
# The old workflow steps (build_neighbor_graph, calibrate_prior_cap,
# compute_species_amplitude, update_theta_local) are retired -- all replaced
# by the taxon_name:grid_id random effect fitted in train_biodiversity_model().

message("\n--- Step 5: Generating priors ---")

priors_observed <- generate_full_priors(
  model_obj = model_fit,
  new_sites = model_data
)

priors_undetected <- generate_undetected_diversity(
  model_obj = model_fit
)

priors_combined <- dplyr::bind_rows(priors_observed, priors_undetected)

message(sprintf("  %d observed-species prior rows.", nrow(priors_observed)))
message(sprintf("  %d undetected-species prior rows.", nrow(priors_undetected)))

plot_theta_map_interactive(priors_combined, occurrences_with_habitat,tile = "OpenStreetMap")


# =============================================================================
# 6.  TRANSLATE PRIORS TO NCBI BACKBONE
# =============================================================================
# TaxaAssign uses NCBI (backbone_id = 4). GBIF backbone names are translated
# here so downstream joins work without further backbone conversion.

message("\n--- Step 6: Translating priors to NCBI backbone ---")

gbif_taxa_unique <- unique(priors_combined$taxon_name)

ncbi_lookup <- verify_taxon_names(gbif_taxa_unique, backbone_id = 4) |>
  change_backbone(
    input_col          = "user_supplied_name",
    old_backbone_label = "gbif_name",
    new_backbone_label = "ncbi_name"
  )

taxaexpect_priors <- priors_combined |>
  dplyr::left_join(ncbi_lookup, by = c("taxon_name" = "gbif_name")) |>
  dplyr::select(!taxon_name) |>
  create_taxon_names(rank_system = rank_system)

n_translated <- sum(!is.na(taxaexpect_priors$taxon_name))
message(sprintf("  %d of %d prior rows have an NCBI name.",
                n_translated, nrow(taxaexpect_priors)))

# =============================================================================
# 7.  SAVE OUTPUTS FOR TaxaAssign
# =============================================================================

message("\n--- Step 7: Saving outputs ---")
saveRDS(taxaexpect_priors, file.choose(new = TRUE))  # choose where to save taxaexpect_priors.rds
saveRDS(model_fit, file.choose(new = TRUE))  # choose where to save model_fit.rds
message("Saved all_occurrences.")
message("\n--- Done. Next step: TaxaAssign/inst/TaxaAssign_bayesian_workflow.R ---")


# =============================================================================
# WRAPPER ALTERNATIVE: build_priors()
# =============================================================================
# Replaces Sections 1-7 above with a single call. Requires TaxaFetch,
# TaxaHabitat, and TaxaTools (all in Suggests). Uses the same underlying
# functions but handles gridding, model training, prior generation, and
# backbone translation internally.
#
# The step-by-step workflow above gives full control over each stage;
# the wrapper is for the common single-site case where defaults suffice.
match_obj  <- readRDS(file.choose())  # select your match data file (.rds)
match_obj  <-match_obj[1:20,]
higher_taxa_to_search <- unique(match_obj$family)
higher_taxa_to_search <- higher_taxa_to_search[!is.na(higher_taxa_to_search)]

bp_result <- build_priors(
  taxa               = data.frame(family = higher_taxa_to_search),
  lat                = 34.1,                     # site latitude
  lon                = -119.1,                   # site longitude
  search_radius_deg  = 2,                        # GBIF search radius
  habitat_scheme     = NULL,                     # NULL = 3-category default
  llm_fn             = TaxaTools::call_anthropic_api,
  geographic_context = "Southern California estuary",
  moran_k            = 5L,
  sd_threshold       = 0.20,
  rank_system        = c("kingdom", "phylum", "class", "order",
                         "family", "genus", "species"),
  target_backbone_id = 4L,                       # NCBI
  checkpoint_dir     = tempdir(),                # saves intermediates
  verbose            = TRUE
)

# Equivalent outputs:
taxaexpect_priors <- bp_result$priors
model_fit         <- bp_result$model
occurrences       <- bp_result$occurrences
grid_result       <- bp_result$grid_result

