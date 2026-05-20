# test-generate_full_priors.R
# Tests for generate_full_priors().
#
# Structure:
#   - Input validation (no model needed)
#   - Integration tests (require glmmTMB; use minimal synthetic pipeline)
#
# generate_full_priors() wraps a fitted glmmTMB model, so integration tests
# build a minimal biofreq_model via train_biodiversity_model() on tiny data.

library(testthat)
library(dplyr)

# =============================================================================
# Minimal synthetic pipeline helpers
# (mirrors the approach in test-train_biodiversity_model.R)
# =============================================================================

.make_sites <- function(n_sites = 10, habitats = c("Rocky", "Sandy")) {
  set.seed(42)
  expand.grid(
    grid_id      = paste0("Grid_", seq_len(n_sites), "p0_m120p0"),
    main_habitat = habitats,
    stringsAsFactors = FALSE
  ) |>
    dplyr::mutate(
      lat_r          = runif(dplyr::n(), 33, 38),
      lon_r          = runif(dplyr::n(), -122, -117),
      n_total_at_site = sample(20:50, dplyr::n(), replace = TRUE)
    )
}

.make_model_data <- function(n_sites     = 10,
                              n_common    = 3,
                              n_rare      = 2,
                              habitats    = c("Rocky", "Sandy")) {
  set.seed(7)
  sites    <- .make_sites(n_sites, habitats)
  taxa_t1  <- paste0("Species_", seq_len(n_common))
  taxa_t2  <- paste0("Rare_",    seq_len(n_rare))
  all_taxa <- c(taxa_t1, taxa_t2)

  tidyr::crossing(
    dplyr::tibble(taxon_name = all_taxa),
    sites
  ) |>
    dplyr::mutate(
      n_species = ifelse(taxon_name %in% taxa_t1,
                         sample(0:8, dplyr::n(), replace = TRUE),
                         sample(0:2, dplyr::n(), replace = TRUE)),
      n_other   = n_total_at_site - n_species,
      is_present = as.integer(n_species > 0),
      lat_r_s   = as.numeric(scale(lat_r)),
      lon_r_s   = as.numeric(scale(lon_r)),
      main_habitat = factor(main_habitat)
    ) |>
    structure(
      scale_params = list(
        lat_r = list(center = mean(sites$lat_r), scale = sd(sites$lat_r)),
        lon_r = list(center = mean(sites$lon_r), scale = sd(sites$lon_r))
      )
    )
}

.fit_minimal_model <- function() {
  skip_if_not_installed("glmmTMB")
  data <- .make_model_data()
  train_biodiversity_model(
    data              = data,
    formula           = cbind(n_species, n_other) ~
      main_habitat + (1 | taxon_name) + (1 | taxon_name:grid_id),
    min_obs_threshold = 3L,
    effort_threshold  = 5L,
    min_positive_rows = 1L
  )
}

.make_new_sites <- function(n = 5) {
  set.seed(99)
  data.frame(
    grid_id         = paste0("Grid_", seq_len(n), "p0_m121p0"),
    main_habitat    = rep(c("Rocky", "Sandy"), length.out = n),
    lat_r           = runif(n, 34, 37),
    lon_r           = runif(n, -121, -118),
    n_total_at_site = sample(20:40, n, replace = TRUE),
    stringsAsFactors = FALSE
  )
}

# =============================================================================
# Input validation (no model needed)
# =============================================================================

test_that("stops if model_obj is not a biofreq_model", {
  expect_error(
    generate_full_priors(list(), new_sites = data.frame()),
    regexp = "biofreq_model"
  )
})

test_that("stops if new_sites missing required columns", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  expect_error(
    generate_full_priors(mod, new_sites = data.frame(lat_r = 1)),
    regexp = "missing columns"
  )
})

# =============================================================================
# Output structure
# =============================================================================

test_that("returns a data frame", {
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  sites <- .make_new_sites()
  out   <- generate_full_priors(mod, new_sites = sites)
  expect_true(is.data.frame(out))
})

test_that("output contains all documented columns", {
  skip_if_not_installed("glmmTMB")
  mod      <- .fit_minimal_model()
  sites    <- .make_new_sites()
  out      <- generate_full_priors(mod, new_sites = sites)
  required <- c("taxon_name", "grid_id", "main_habitat", "alpha", "beta",
                "theta_mean", "theta_sd", "n_obs", "model_tier",
                "effort_flag", "habitat_observed_elsewhere",
                "extrapolation_warning", "undetected_type")
  for (col in required) {
    expect_true(col %in% names(out), info = paste("Missing column:", col))
  }
})

test_that("model_tier values are valid", {
  skip_if_not_installed("glmmTMB")
  mod  <- .fit_minimal_model()
  out  <- generate_full_priors(mod, new_sites = .make_new_sites())
  valid_tiers <- c("tier1", "tier2", "tier3_undetected")
  expect_true(all(out$model_tier %in% valid_tiers))
})

test_that("alpha and beta are positive numeric", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expect_true(all(out$alpha > 0))
  expect_true(all(out$beta  > 0))
})

test_that("theta_mean is in (0, 1)", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expect_true(all(out$theta_mean > 0 & out$theta_mean < 1))
})

test_that("theta_mean equals alpha / (alpha + beta)", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expected <- out$alpha / (out$alpha + out$beta)
  expect_equal(out$theta_mean, expected, tolerance = 1e-6)
})

# =============================================================================
# Effort flag
# =============================================================================

test_that("effort_flag is NA when n_total_at_site is absent from new_sites", {
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  sites <- .make_new_sites()
  sites$n_total_at_site <- NULL
  out   <- generate_full_priors(mod, new_sites = sites)
  expect_true(all(is.na(out$effort_flag)))
})

test_that("effort_flag is logical when n_total_at_site is present", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expect_type(out$effort_flag, "logical")
})

# =============================================================================
# Undetected rows
# =============================================================================

test_that("undetected rows are appended when undetected is supplied", {
  skip_if_not_installed("glmmTMB")
  mod      <- .fit_minimal_model()
  sites    <- .make_new_sites()
  undet    <- generate_undetected_diversity(mod)
  out_with <- generate_full_priors(mod, new_sites = sites, undetected = undet)
  out_base <- generate_full_priors(mod, new_sites = sites, undetected = NULL)
  expect_gt(nrow(out_with), nrow(out_base))
})

test_that("undetected rows have taxon_name = NA", {
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  undet <- generate_undetected_diversity(mod)
  out   <- generate_full_priors(mod, new_sites = .make_new_sites(),
                                undetected = undet)
  undet_rows <- out[out$model_tier == "tier3_undetected", ]
  if (nrow(undet_rows) > 0) {
    expect_true(all(is.na(undet_rows$taxon_name)))
  }
})

# =============================================================================
# Extrapolation flag
# =============================================================================

test_that("extrapolation_warning is logical", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expect_type(out$extrapolation_warning, "logical")
})

# =============================================================================
# undetected_type column
# =============================================================================

test_that("undetected_type is NA for modelled rows", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  modelled <- out[!is.na(out$taxon_name), ]
  expect_true(all(is.na(modelled$undetected_type)))
})
