# test-train_biodiversity_model.R
# Tests for train_biodiversity_model().
#
# Expects zero-filled output from prepare_model_dataframe():
#   one row per taxon x site-habitat with columns:
#   n_species, n_other, n_total_at_site, is_present,
#   habitat_observed_elsewhere, lat_r_s, lon_r_s
#   AND the scale_params attribute.
#
# Key behaviors tested:
#   - Returns a biofreq_model class list with the documented components
#   - Tier 1 vs Tier 2 assignment based on n_detections vs min_obs_threshold
#   - Tier values are strings "tier1" / "tier2"
#   - scale_params stored in $scale_params (not $scaling_params)
#   - Formulas stored in $meta$formula_tier1 and $meta$formula_tier2
#   - Models stored in $models$tier1 and $models$tier2

library(testthat)
library(dplyr)

# =============================================================================
# Synthetic data helpers
# =============================================================================

# Produces a zero-filled tibble as if returned by prepare_model_dataframe().
# n_common: species with many detections (Tier 1 candidates)
# n_rare:   species with few detections (Tier 2 candidates)
.make_train_data <- function(n_common = 3,
                              n_rare   = 2,
                              n_sites  = 20,
                              seed     = 42) {
  set.seed(seed)
  habitats <- c("Kelp", "Rocky", "Sandy")
  grids    <- paste0("g", seq_len(n_sites))
  lat_vals <- seq(33, 37, length.out = n_sites)
  lon_vals <- seq(-122, -118, length.out = n_sites)

  site_df <- data.frame(
    grid_id         = grids,
    lat_r           = lat_vals,
    lon_r           = lon_vals,
    lat_r_s         = as.numeric(scale(lat_vals)),
    lon_r_s         = as.numeric(scale(lon_vals)),
    main_habitat    = sample(habitats, n_sites, replace = TRUE),
    n_total_at_site = 15L,
    stringsAsFactors = FALSE
  )

  # Common: detected at many sites
  common_sp   <- paste0("Common_", LETTERS[seq_len(n_common)])
  common_rows <- lapply(common_sp, function(sp) {
    n_det <- rbinom(n_sites, size = 15L, prob = runif(1, 0.4, 0.7))
    dplyr::mutate(site_df,
      taxon_name               = sp,
      n_species                = n_det,
      n_other                  = 15L - n_det,
      is_present               = as.integer(n_det > 0),
      habitat_observed_elsewhere = TRUE
    )
  })

  # Rare: detected at 1-2 sites only
  rare_sp   <- paste0("Rare_", seq_len(n_rare))
  rare_rows <- lapply(rare_sp, function(sp) {
    n_det <- integer(n_sites)
    n_det[sample(n_sites, min(2L, n_sites))] <- sample(1:3, min(2L, n_sites),
                                                        replace = TRUE)
    dplyr::mutate(site_df,
      taxon_name               = sp,
      n_species                = n_det,
      n_other                  = 15L - n_det,
      is_present               = as.integer(n_det > 0),
      habitat_observed_elsewhere = TRUE
    )
  })

  df <- dplyr::bind_rows(common_rows, rare_rows)

  # Attach scale_params as required by train_biodiversity_model()
  attr(df, "scale_params") <- list(
    lat_r = list(center = mean(lat_vals), scale = sd(lat_vals)),
    lon_r = list(center = mean(lon_vals), scale = sd(lon_vals))
  )

  df
}

# All-rare dataset: every species has <= 2 detections
.make_all_rare_data <- function(n_sites = 10, seed = 7) {
  set.seed(seed)
  lat_vals <- seq(33, 36, length.out = n_sites)
  lon_vals <- seq(-122, -119, length.out = n_sites)

  site_df <- data.frame(
    grid_id         = paste0("g", seq_len(n_sites)),
    lat_r           = lat_vals,
    lon_r           = lon_vals,
    lat_r_s         = as.numeric(scale(lat_vals)),
    lon_r_s         = as.numeric(scale(lon_vals)),
    main_habitat    = sample(c("Kelp", "Rocky"), n_sites, replace = TRUE),
    n_total_at_site = 10L,
    stringsAsFactors = FALSE
  )

  sp_rows <- lapply(paste0("Sp_", 1:3), function(sp) {
    n_det <- integer(n_sites)
    n_det[1] <- 1L
    dplyr::mutate(site_df,
      taxon_name               = sp,
      n_species                = n_det,
      n_other                  = 10L - n_det,
      is_present               = as.integer(n_det > 0),
      habitat_observed_elsewhere = TRUE
    )
  })

  df <- dplyr::bind_rows(sp_rows)
  attr(df, "scale_params") <- list(
    lat_r = list(center = mean(lat_vals), scale = sd(lat_vals)),
    lon_r = list(center = mean(lon_vals), scale = sd(lon_vals))
  )
  df
}

# Default simple formula for tests -- intercept-only tier1, compatible with
# small synthetic datasets (avoid convergence failures in CI).
.simple_formula <- function() {
  cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)
}

# =============================================================================
# Return structure
# =============================================================================

test_that("train_biodiversity_model returns a biofreq_model object", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data()
  mod  <- train_biodiversity_model(data, formula = .simple_formula())
  expect_s3_class(mod, "biofreq_model")
  expect_true(is.list(mod))
})

test_that("output contains expected top-level components", {
  skip_if_not_installed("glmmTMB")
  data     <- .make_train_data()
  mod      <- train_biodiversity_model(data, formula = .simple_formula())
  required <- c("models", "tiers", "scale_params", "singletons",
                "N_total", "tier2_empirical", "convergence_warnings", "meta")
  for (nm in required) {
    expect_true(nm %in% names(mod), info = paste("Missing component:", nm))
  }
})

test_that("$models is a list with $tier1 and $tier2 slots", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data()
  mod  <- train_biodiversity_model(data, formula = .simple_formula())
  expect_true(is.list(mod$models))
  expect_true("tier1" %in% names(mod$models))
  expect_true("tier2" %in% names(mod$models))
})

test_that("$meta contains formula_tier1 and formula_tier2 as character strings", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data()
  mod  <- train_biodiversity_model(data, formula = .simple_formula())
  expect_true(!is.null(mod$meta$formula_tier1))
  expect_true(!is.null(mod$meta$formula_tier2))
  expect_type(mod$meta$formula_tier1, "character")
  expect_type(mod$meta$formula_tier2, "character")
})

# =============================================================================
# Tier assignments
# =============================================================================

test_that("$tiers is a dataframe with taxon_name, tier, n_detections", {
  skip_if_not_installed("glmmTMB")
  data  <- .make_train_data()
  mod   <- train_biodiversity_model(data, formula = .simple_formula())
  tiers <- mod$tiers
  expect_true(is.data.frame(tiers))
  expect_true("taxon_name"   %in% names(tiers))
  expect_true("tier"         %in% names(tiers))
  expect_true("n_detections" %in% names(tiers))
})

test_that("every training species has a tier assignment", {
  skip_if_not_installed("glmmTMB")
  data     <- .make_train_data()
  mod      <- train_biodiversity_model(data, formula = .simple_formula())
  all_sp   <- unique(data$taxon_name)
  tiers_sp <- mod$tiers$taxon_name
  expect_setequal(all_sp, tiers_sp)
})

test_that("tier values are strings 'tier1' and/or 'tier2'", {
  skip_if_not_installed("glmmTMB")
  data  <- .make_train_data()
  mod   <- train_biodiversity_model(data, formula = .simple_formula())
  tiers <- mod$tiers$tier
  expect_true(all(tiers %in% c("tier1", "tier2")))
})

test_that("common species (many detections) are assigned 'tier1'", {
  skip_if_not_installed("glmmTMB")
  data   <- .make_train_data(n_common = 3, n_rare = 0)
  mod    <- train_biodiversity_model(data,
                                     formula          = .simple_formula(),
                                     min_obs_threshold = 5L)
  tiers  <- mod$tiers
  common <- tiers$tier[grepl("^Common_", tiers$taxon_name)]
  expect_true(all(common == "tier1"))
})

test_that("rare species fall to 'tier2' when below min_obs_threshold", {
  skip_if_not_installed("glmmTMB")
  data  <- .make_all_rare_data()
  mod   <- train_biodiversity_model(data,
                                    formula          = .simple_formula(),
                                    min_obs_threshold = 5L)
  tiers <- mod$tiers
  expect_true(all(tiers$tier == "tier2"))
})

test_that("raising min_obs_threshold moves species from tier1 to tier2", {
  skip_if_not_installed("glmmTMB")
  data  <- .make_train_data(n_common = 3, n_rare = 2)
  mod1  <- train_biodiversity_model(data,
                                    formula          = .simple_formula(),
                                    min_obs_threshold = 2L)
  mod2  <- train_biodiversity_model(data,
                                    formula          = .simple_formula(),
                                    min_obs_threshold = 50L)
  n_t1_low  <- sum(mod1$tiers$tier == "tier1")
  n_t1_high <- sum(mod2$tiers$tier == "tier1")
  expect_gte(n_t1_low, n_t1_high)
})

# =============================================================================
# scale_params
# =============================================================================

test_that("$scale_params is a list with center and scale entries", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data()
  mod  <- train_biodiversity_model(data, formula = .simple_formula())
  sp   <- mod$scale_params
  expect_true(is.list(sp))
  expect_true(any(grepl("lat_r|lon_r", names(sp))))
  # Each entry should have $center and $scale
  first <- sp[[1]]
  expect_true(!is.null(first$center))
  expect_true(!is.null(first$scale))
})

# =============================================================================
# N_total and singletons
# =============================================================================

test_that("$N_total is a positive integer", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data()
  mod  <- train_biodiversity_model(data, formula = .simple_formula())
  expect_true(mod$N_total > 0)
})

test_that("$singletons is a dataframe", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data()
  mod  <- train_biodiversity_model(data, formula = .simple_formula())
  expect_true(is.data.frame(mod$singletons))
})

# =============================================================================
# Effort threshold
# =============================================================================

test_that("effort_threshold below all site totals excludes no data", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data(n_sites = 20)
  expect_no_error(
    train_biodiversity_model(data,
                             formula          = .simple_formula(),
                             effort_threshold = 5L)
  )
})

# =============================================================================
# Model objects
# =============================================================================

test_that("$models$tier1 is a glmmTMB object when Tier 1 species exist", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data(n_common = 3)
  mod  <- train_biodiversity_model(data,
                                   formula          = .simple_formula(),
                                   min_obs_threshold = 5L)
  expect_s3_class(mod$models$tier1, "glmmTMB")
})

test_that("response = 'psi' runs without error", {
  skip_if_not_installed("glmmTMB")
  data <- .make_train_data()
  expect_no_error(
    train_biodiversity_model(
      data,
      formula   = cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name),
      response  = "psi"
    )
  )
})

# =============================================================================
# Input validation
# =============================================================================

test_that("formula is required and must be a formula object", {
  data <- .make_train_data()
  expect_error(train_biodiversity_model(data),
               info = "formula argument is required")
  expect_error(
    train_biodiversity_model(data, formula = "n_species ~ 1"),
    regexp = "formula.*formula object"
  )
})

test_that("LHS must be cbind() for response = 'theta'", {
  data <- .make_train_data()
  expect_error(
    train_biodiversity_model(data, formula = n_species ~ main_habitat,
                             response = "theta"),
    regexp = "cbind"
  )
})

test_that("missing required columns trigger informative error", {
  data <- .make_train_data()
  data$n_species <- NULL
  expect_error(
    train_biodiversity_model(data, formula = .simple_formula()),
    regexp = "missing required columns"
  )
})
