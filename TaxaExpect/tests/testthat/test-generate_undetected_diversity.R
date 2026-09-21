# test-generate_undetected_diversity.R
# Tests for generate_undetected_diversity().
#
# Input:  taxaexpect_kernel_priors object from estimate_kernel_priors().
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
# Mock taxaexpect_kernel_priors builder
# =============================================================================
# Constructs a minimal object with the fields actually read by
# generate_undetected_diversity()'s kernel adapter:
#   $params$n_records_stratum -- the FLOOR's N_total
#   $params$site_id, $params$site_habitat
#   $n_eff                    -- the mirrors' shared effective-share denominator
#   $singletons               -- dataframe with taxon_name, effective_records
#   $budget                   -- NULL (single-group fit)

.make_mock_kernel_obj <- function(n_singleton = 4,
                                  N_total = 200L,
                                  n_eff = 20,
                                  site_id = "g1",
                                  site_habitat = "Kelp") {
  singleton_sp <- if (n_singleton > 0) paste0("Singleton_", seq_len(n_singleton)) else character(0)

  singletons <- data.frame(
    taxon_name        = singleton_sp,
    effective_records = rep(1, n_singleton),
    stringsAsFactors  = FALSE
  )

  structure(
    list(
      params = list(
        n_records_stratum = N_total,
        site_id = site_id,
        site_habitat = site_habitat
      ),
      n_eff = n_eff,
      singletons = singletons,
      budget = NULL
    ),
    class = "taxaexpect_kernel_priors"
  )
}

# =============================================================================
# Output structure
# =============================================================================

test_that("generate_undetected_diversity returns a dataframe", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(is.data.frame(out))
})

test_that("output contains all documented columns", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  required <- c(
    "taxon_name", "grid_id", "main_habitat", "alpha", "beta",
    "theta_mean", "theta_sd", "n_obs", "model_tier",
    "undetected_type", "source_taxon_name"
  )
  for (col in required) {
    expect_true(col %in% names(out), info = paste("Missing column:", col))
  }
})

# =============================================================================
# taxon_name is always NA (proxies have no taxonomic identity)
# =============================================================================

test_that("taxon_name is NA for all proxy rows", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(all(is.na(out$taxon_name)),
    info = "Proxy rows must have taxon_name = NA"
  )
})

# =============================================================================
# Global floor -- always present
# =============================================================================

test_that("at least one global_floor row is always present", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(any(out$undetected_type == "global_floor"),
    info = "Global floor must always be present"
  )
})

test_that("function returns at least 1 row even with no singletons", {
  mod <- .make_mock_kernel_obj(n_singleton = 0)
  out <- generate_undetected_diversity(mod)
  expect_gte(nrow(out), 1L,
    label = "At least global floor row expected"
  )
})

test_that("global floor grid_id and habitat are NA", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  floor_row <- out[out$undetected_type == "global_floor", ]
  expect_true(is.na(floor_row$grid_id[1]))
  expect_true(is.na(floor_row$main_habitat[1]))
})

# =============================================================================
# jeffreys_threshold controls global floor prior type (not species inclusion)
# =============================================================================

test_that("N_total >= jeffreys_threshold uses Beta(1, N_total - 1) for floor", {
  mod <- .make_mock_kernel_obj(N_total = 100L, n_singleton = 0)
  out <- generate_undetected_diversity(mod, jeffreys_threshold = 2L)
  floor_row <- out[out$undetected_type == "global_floor", ]
  expect_equal(floor_row$alpha, 1)
  expect_equal(floor_row$beta, 99)
})

test_that("N_total < jeffreys_threshold uses Jeffreys prior Beta(0.5, 0.5)", {
  mod <- .make_mock_kernel_obj(N_total = 1L, n_singleton = 0)
  out <- generate_undetected_diversity(mod, jeffreys_threshold = 2L)
  floor_row <- out[out$undetected_type == "global_floor", ]
  expect_equal(floor_row$alpha, 0.5)
  expect_equal(floor_row$beta, 0.5)
})

# =============================================================================
# Singleton mirrors
# =============================================================================

test_that("number of singleton mirrors equals number of valid singletons", {
  n_sing <- 4
  mod <- .make_mock_kernel_obj(n_singleton = n_sing)
  out <- generate_undetected_diversity(mod)
  mirrors <- out[out$undetected_type == "singleton_mirror", ]
  expect_equal(nrow(mirrors), n_sing)
})

test_that("total rows = n_singletons + 1 (global floor)", {
  n_sing <- 3
  mod <- .make_mock_kernel_obj(n_singleton = n_sing)
  out <- generate_undetected_diversity(mod)
  expect_equal(nrow(out), n_sing + 1L)
})

test_that("source_taxon_name is NA for global floor and populated for mirrors", {
  mod <- .make_mock_kernel_obj(n_singleton = 2)
  out <- generate_undetected_diversity(mod)
  floor <- out[out$undetected_type == "global_floor", ]
  mirrors <- out[out$undetected_type == "singleton_mirror", ]
  expect_true(is.na(floor$source_taxon_name))
  expect_true(all(!is.na(mirrors$source_taxon_name)))
})

# =============================================================================
# Prior properties
# =============================================================================

test_that("alpha and beta are strictly positive and finite", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(all(out$alpha > 0), info = "alpha must be > 0")
  expect_true(all(out$beta > 0), info = "beta must be > 0")
  expect_true(all(is.finite(out$alpha)))
  expect_true(all(is.finite(out$beta)))
})

test_that("theta_mean matches alpha / (alpha + beta)", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  computed <- out$alpha / (out$alpha + out$beta)
  expect_equal(out$theta_mean, computed, tolerance = 1e-9)
})

test_that("theta_mean is between 0 and 1 (exclusive)", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(all(out$theta_mean > 0 & out$theta_mean < 1))
})

test_that("model_tier is 'tier3_undetected' for all rows", {
  mod <- .make_mock_kernel_obj()
  out <- generate_undetected_diversity(mod)
  expect_true(all(out$model_tier == "tier3_undetected"))
})

# =============================================================================
# singleton_ess controls prior width
# =============================================================================

test_that("higher singleton_ess produces narrower priors (larger alpha + beta)", {
  mod <- .make_mock_kernel_obj(n_singleton = 5)
  out_low <- generate_undetected_diversity(mod, singleton_ess = 1L)
  out_high <- generate_undetected_diversity(mod, singleton_ess = 10L)
  ess_low <- sum(out_low$alpha + out_low$beta)
  ess_high <- sum(out_high$alpha + out_high$beta)
  expect_lt(ess_low, ess_high)
})

# =============================================================================
# Input validation
# =============================================================================

test_that("non-taxaexpect_kernel_priors input triggers informative error", {
  expect_error(
    generate_undetected_diversity(list(N_total = 100)),
    regexp = "taxaexpect_kernel_priors"
  )
})

test_that("N_total <= 0 triggers informative error", {
  mod <- .make_mock_kernel_obj()
  mod$params$n_records_stratum <- 0L
  expect_error(
    generate_undetected_diversity(mod),
    regexp = "N_total is zero"
  )
})
