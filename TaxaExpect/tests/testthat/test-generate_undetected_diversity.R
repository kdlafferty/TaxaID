# test-generate_undetected_diversity.R
# Tests for generate_undetected_diversity().
#
# Input:  biofreq_model object from train_biodiversity_model().
# Output: tibble of Tier 3 proxy priors with columns:
#   taxon_name, grid_id, habitat, alpha, beta, theta_mean, theta_sd,
#   n_obs, model_tier, undetected_type, source_taxon_name
#
# Two types of proxies:
#   1. singleton_mirror: one proxy per singleton species, inheriting its
#      habitat, grid_id, and theta_obs. taxon_name is always NA.
#   2. global_floor: always present regardless of singleton count.
#      Uses Beta(1, N_total - 1), or Jeffreys Beta(0.5, 0.5) when
#      N_total < jeffreys_threshold.

library(testthat)
library(dplyr)

# =============================================================================
# Mock biofreq_model builder
# =============================================================================
# Constructs a minimal object with the fields actually read by
# generate_undetected_diversity():
#   $N_total        -- integer
#   $singletons     -- dataframe with taxon_name, grid_id, <habitat_col>,
#                      n_species, n_total_at_site, theta_obs
#   $meta$habitat_col
#   $meta$taxon_col
# Must carry class "biofreq_model".
#
# Implementation note: tiers data.frame is built using length() of the
# pre-constructed species vectors -- NOT the n_tier* parameters directly --
# to ensure all vectors are guaranteed to have matching lengths even when
# any of the counts is 0.

.make_mock_model_obj <- function(n_tier1       = 3,
                                  n_tier2       = 2,
                                  n_singleton   = 4,
                                  N_total       = 200L,
                                  seed          = 42) {
  set.seed(seed)

  # Build species name vectors first; handle n = 0 explicitly
  tier1_sp     <- if (n_tier1    > 0) paste0("Tier1_",    seq_len(n_tier1))    else character(0)
  tier2_sp     <- if (n_tier2    > 0) paste0("Tier2_",    seq_len(n_tier2))    else character(0)
  singleton_sp <- if (n_singleton > 0) paste0("Singleton_", seq_len(n_singleton)) else character(0)

  all_sp <- c(tier1_sp, tier2_sp, singleton_sp)

  # Build tiers using length() of the pre-built vectors, not n_tier* variables,
  # so length always matches all_sp regardless of edge cases.
  tiers <- data.frame(
    taxon_name   = all_sp,
    tier         = c(rep("tier1", length(tier1_sp)),
                     rep("tier2", length(tier2_sp)),
                     rep("tier2", length(singleton_sp))),
    n_detections = c(rep(15L, length(tier1_sp)),
                     rep(3L,  length(tier2_sp)),
                     rep(1L,  length(singleton_sp))),
    stringsAsFactors = FALSE
  )

  # Singletons dataframe: one row per singleton, with theta_obs
  if (n_singleton > 0) {
    singletons <- data.frame(
      taxon_name       = singleton_sp,
      grid_id          = paste0("g", seq_len(n_singleton)),
      main_habitat     = rep("Kelp", n_singleton),
      n_species        = 1L,
      n_total_at_site  = 20L,
      theta_obs        = 1.0 / 20.0,
      total_detections = 1L,
      stringsAsFactors = FALSE
    )
  } else {
    singletons <- data.frame(
      taxon_name       = character(0),
      grid_id          = character(0),
      main_habitat     = character(0),
      n_species        = integer(0),
      n_total_at_site  = integer(0),
      theta_obs        = numeric(0),
      total_detections = integer(0),
      stringsAsFactors = FALSE
    )
  }

  obj <- list(
    models = list(tier1 = NULL, tier2 = NULL),
    tiers  = tiers,
    scale_params = list(
      lat_r = list(center = 35.0,   scale = 1.5),
      lon_r = list(center = -120.0, scale = 1.5)
    ),
    singletons           = singletons,
    N_total              = N_total,
    tier2_empirical      = data.frame(),
    convergence_warnings = character(0),
    meta = list(
      taxon_col         = "taxon_name",
      habitat_col       = "main_habitat",
      response          = "theta",
      min_obs_threshold = 5L,
      effort_threshold  = 10L,
      formula_tier1     = "cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)",
      formula_tier2     = "cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)",
      n_sites           = 20L,
      n_species_tier1   = length(tier1_sp),
      n_species_tier2   = length(tier2_sp)
    )
  )
  class(obj) <- "biofreq_model"
  obj
}

# =============================================================================
# Output structure
# =============================================================================

test_that("generate_undetected_diversity returns a dataframe", {
  mod <- .make_mock_model_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(is.data.frame(out))
})

test_that("output contains all documented columns", {
  mod      <- .make_mock_model_obj()
  out      <- generate_undetected_diversity(mod)
  required <- c("taxon_name", "grid_id", "main_habitat", "alpha", "beta",
                "theta_mean", "theta_sd", "n_obs", "model_tier",
                "undetected_type", "source_taxon_name")
  for (col in required) {
    expect_true(col %in% names(out), info = paste("Missing column:", col))
  }
})

# =============================================================================
# taxon_name is always NA (proxies have no taxonomic identity)
# =============================================================================

test_that("taxon_name is NA for all proxy rows", {
  mod <- .make_mock_model_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(all(is.na(out$taxon_name)),
              info = "Proxy rows must have taxon_name = NA")
})

# =============================================================================
# Global floor -- always present
# =============================================================================

test_that("at least one global_floor row is always present", {
  mod <- .make_mock_model_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(any(out$undetected_type == "global_floor"),
              info = "Global floor must always be present")
})

test_that("function returns at least 1 row even with no singletons", {
  mod <- .make_mock_model_obj(n_singleton = 0)
  out <- generate_undetected_diversity(mod)
  expect_gte(nrow(out), 1L,
             label = "At least global floor row expected")
})

test_that("global floor grid_id and habitat are NA", {
  mod       <- .make_mock_model_obj()
  out       <- generate_undetected_diversity(mod)
  floor_row <- out[out$undetected_type == "global_floor", ]
  expect_true(is.na(floor_row$grid_id[1]))
  expect_true(is.na(floor_row$main_habitat[1]))
})

# =============================================================================
# jeffreys_threshold controls global floor prior type (not species inclusion)
# =============================================================================

test_that("N_total >= jeffreys_threshold uses Beta(1, N_total - 1) for floor", {
  mod       <- .make_mock_model_obj(N_total = 100L, n_singleton = 0)
  out       <- generate_undetected_diversity(mod, jeffreys_threshold = 2L)
  floor_row <- out[out$undetected_type == "global_floor", ]
  expect_equal(floor_row$alpha, 1)
  expect_equal(floor_row$beta,  99)
})

test_that("N_total < jeffreys_threshold uses Jeffreys prior Beta(0.5, 0.5)", {
  mod       <- .make_mock_model_obj(N_total = 1L, n_singleton = 0)
  out       <- generate_undetected_diversity(mod, jeffreys_threshold = 2L)
  floor_row <- out[out$undetected_type == "global_floor", ]
  expect_equal(floor_row$alpha, 0.5)
  expect_equal(floor_row$beta,  0.5)
})

# =============================================================================
# Singleton mirrors
# =============================================================================

test_that("number of singleton mirrors equals number of valid singletons", {
  n_sing  <- 4
  mod     <- .make_mock_model_obj(n_singleton = n_sing)
  out     <- generate_undetected_diversity(mod)
  mirrors <- out[out$undetected_type == "singleton_mirror", ]
  expect_equal(nrow(mirrors), n_sing)
})

test_that("total rows = n_singletons + 1 (global floor)", {
  n_sing <- 3
  mod    <- .make_mock_model_obj(n_singleton = n_sing)
  out    <- generate_undetected_diversity(mod)
  expect_equal(nrow(out), n_sing + 1L)
})

test_that("source_taxon_name is NA for global floor and populated for mirrors", {
  mod     <- .make_mock_model_obj(n_singleton = 2)
  out     <- generate_undetected_diversity(mod)
  floor   <- out[out$undetected_type == "global_floor", ]
  mirrors <- out[out$undetected_type == "singleton_mirror", ]
  expect_true(is.na(floor$source_taxon_name))
  expect_true(all(!is.na(mirrors$source_taxon_name)))
})

# =============================================================================
# Prior properties
# =============================================================================

test_that("alpha and beta are strictly positive and finite", {
  mod <- .make_mock_model_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(all(out$alpha > 0),      info = "alpha must be > 0")
  expect_true(all(out$beta  > 0),      info = "beta must be > 0")
  expect_true(all(is.finite(out$alpha)))
  expect_true(all(is.finite(out$beta)))
})

test_that("theta_mean matches alpha / (alpha + beta)", {
  mod <- .make_mock_model_obj()
  out <- generate_undetected_diversity(mod)
  computed <- out$alpha / (out$alpha + out$beta)
  expect_equal(out$theta_mean, computed, tolerance = 1e-9)
})

test_that("theta_mean is between 0 and 1 (exclusive)", {
  mod <- .make_mock_model_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(all(out$theta_mean > 0 & out$theta_mean < 1))
})

test_that("model_tier is 'tier3_undetected' for all rows", {
  mod <- .make_mock_model_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(all(out$model_tier == "tier3_undetected"))
})

# =============================================================================
# singleton_ess controls prior width
# =============================================================================

test_that("higher singleton_ess produces narrower priors (larger alpha + beta)", {
  mod      <- .make_mock_model_obj(n_singleton = 5)
  out_low  <- generate_undetected_diversity(mod, singleton_ess = 1L)
  out_high <- generate_undetected_diversity(mod, singleton_ess = 10L)
  ess_low  <- sum(out_low$alpha  + out_low$beta)
  ess_high <- sum(out_high$alpha + out_high$beta)
  expect_lt(ess_low, ess_high)
})

# =============================================================================
# Input validation
# =============================================================================

test_that("non-biofreq_model input triggers informative error", {
  expect_error(
    generate_undetected_diversity(list(N_total = 100)),
    regexp = "biofreq_model"
  )
})

test_that("N_total <= 0 triggers informative error", {
  mod         <- .make_mock_model_obj()
  mod$N_total <- 0L
  expect_error(
    generate_undetected_diversity(mod),
    regexp = "N_total is zero"
  )
})
