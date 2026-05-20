# test-prepare_model_dataframe.R
# Tests for prepare_model_dataframe().
#
# Input structure (from create_sites_from_grid() + habitat assignment):
#   One row per individual occurrence event with columns:
#   taxon_name, grid_id, lat_r, lon_r, main_habitat, plus optional covariates.
#   The function counts rows to derive n_species and n_total_at_site.
#
# Output: zero-filled species x site-habitat tibble with:
#   n_species, n_other, n_total_at_site, is_present,
#   habitat_observed_elsewhere, <covariate>_s, scale_params attribute.
#
# Key design choices tested:
#   - Scaled suffix is _s (not _scaled)
#   - Attribute name is "scale_params" (not "scaling_params")
#   - Correlated covariates are WARNED about, not dropped
#   - Warning text matches "correlated above"

library(testthat)
library(dplyr)

# =============================================================================
# Synthetic data helpers
# =============================================================================

# Generates raw occurrence rows (one row per individual observation).
# lat and lon are assigned from a lookup that is NOT perfectly correlated
# (lon follows a non-monotone sequence relative to lat) so the default
# covariates c("lat_r", "lon_r") do not trigger the correlation warning.
.make_model_input <- function(n_species        = 3,
                               n_sites          = 4,
                               n_total_per_site = 10,
                               seed             = 42) {
  set.seed(seed)
  species  <- paste0("Species_", LETTERS[seq_len(n_species)])
  habitats <- c("Kelp", "Rocky", "Sandy", "Pelagic")

  # lon_r is non-monotone relative to lat_r to avoid r = ±1 correlation
  site_meta <- data.frame(
    grid_id      = paste0("grid_", seq_len(n_sites)),
    lat_r        = seq(34.0, 37.0, length.out = n_sites),
    lon_r        = c(-120.5, -118.2, -121.0, -119.3)[seq_len(n_sites)],
    main_habitat = habitats[seq_len(n_sites)],
    stringsAsFactors = FALSE
  )

  do.call(rbind, lapply(seq_len(n_sites), function(i) {
    data.frame(
      grid_id      = site_meta$grid_id[i],
      lat_r        = site_meta$lat_r[i],
      lon_r        = site_meta$lon_r[i],
      main_habitat = site_meta$main_habitat[i],
      taxon_name   = sample(species, n_total_per_site, replace = TRUE),
      stringsAsFactors = FALSE
    )
  }))
}

# Minimal dataset with GUARANTEED zero-filled rows: Species_A and Species_C
# each absent from exactly one site. Species_B appears everywhere.
.make_guaranteed_absence_input <- function() {
  data.frame(
    grid_id      = c("g1","g1","g2","g2","g2"),
    lat_r        = c(34, 34, 35, 35, 35),
    lon_r        = c(-120, -120, -118, -118, -118),
    main_habitat = c("Kelp","Kelp","Rocky","Rocky","Rocky"),
    taxon_name   = c("Sp_A","Sp_B","Sp_B","Sp_C","Sp_C"),
    stringsAsFactors = FALSE
  )
  # After zero-fill: 3 species x 2 sites = 6 rows
  # Sp_A at g2 = 0, Sp_C at g1 = 0
}

# Occurrence rows with an extra continuous covariate (depth) at each site.
.make_model_input_with_depth <- function(n_species        = 3,
                                          n_sites          = 4,
                                          n_total_per_site = 10,
                                          seed             = 42) {
  base <- .make_model_input(n_species, n_sites, n_total_per_site, seed)
  depth_lookup <- setNames(c(45, 80, 120, 200)[seq_len(n_sites)],
                           paste0("grid_", seq_len(n_sites)))
  base$depth <- depth_lookup[base$grid_id]
  base
}

# Occurrence rows with two near-perfectly correlated covariates for testing
# the multicollinearity warning. lat and corr_with_lat are intentionally
# highly correlated (distinct from the main .make_model_input helper).
.make_correlated_input <- function(n_total = 80, seed = 99) {
  set.seed(seed)
  n_sites  <- 10
  lat_vals <- seq(33, 38, length.out = n_sites)
  site_meta <- data.frame(
    grid_id       = paste0("g", seq_len(n_sites)),
    lat_r         = lat_vals,
    lon_r         = c(-120, -118, -121, -119, -117, -122, -118.5, -120.5, -119.5, -121.5),
    corr_with_lat = lat_vals + rnorm(n_sites, 0, 0.01),  # near-perfect correlation
    main_habitat  = sample(c("Kelp", "Rocky"), n_sites, replace = TRUE),
    stringsAsFactors = FALSE
  )
  rows_per_site <- ceiling(n_total / n_sites)
  do.call(rbind, lapply(seq_len(n_sites), function(i) {
    data.frame(
      grid_id       = site_meta$grid_id[i],
      lat_r         = site_meta$lat_r[i],
      lon_r         = site_meta$lon_r[i],
      corr_with_lat = site_meta$corr_with_lat[i],
      main_habitat  = site_meta$main_habitat[i],
      taxon_name    = sample(paste0("Sp_", 1:3), rows_per_site, replace = TRUE),
      stringsAsFactors = FALSE
    )
  }))
}

# =============================================================================
# Output structure
# =============================================================================

test_that("prepare_model_dataframe returns a dataframe", {
  input <- .make_model_input()
  out   <- prepare_model_dataframe(input)
  expect_true(is.data.frame(out))
})

test_that("output contains required columns", {
  input    <- .make_model_input()
  out      <- prepare_model_dataframe(input)
  required <- c("taxon_name", "grid_id", "main_habitat",
                "n_species", "n_total_at_site", "n_other",
                "is_present", "habitat_observed_elsewhere")
  for (col in required) {
    expect_true(col %in% names(out), info = paste("Missing column:", col))
  }
})

# =============================================================================
# Zero-filling
# =============================================================================

test_that("zero-fill creates one row per species x site combination", {
  # Use the guaranteed-absence dataset (deterministic, no randomness)
  input <- .make_guaranteed_absence_input()
  out   <- prepare_model_dataframe(input)
  n_sp  <- dplyr::n_distinct(out$taxon_name)
  n_si  <- dplyr::n_distinct(out$grid_id)
  expect_equal(nrow(out), n_sp * n_si)
})

test_that("zero-filled rows have n_species = 0", {
  # Guaranteed-absence input ensures zero-filled rows exist
  input <- .make_guaranteed_absence_input()
  out   <- prepare_model_dataframe(input)
  expect_true(any(out$n_species == 0),
              info = "Expected zero-filled rows (species absent at some sites)")
  expect_true(all(out$n_species >= 0))
})

test_that("n_total_at_site is positive and consistent within a site", {
  input <- .make_model_input()
  out   <- prepare_model_dataframe(input)
  expect_true(all(out$n_total_at_site > 0))
  site_totals <- out |>
    dplyr::group_by(grid_id) |>
    dplyr::summarise(n_unique = dplyr::n_distinct(n_total_at_site),
                     .groups = "drop")
  expect_true(all(site_totals$n_unique == 1L),
              info = "n_total_at_site should be constant within a site")
})

test_that("n_other equals n_total_at_site minus n_species", {
  input <- .make_model_input()
  out   <- prepare_model_dataframe(input)
  expect_equal(out$n_other, out$n_total_at_site - out$n_species)
})

test_that("is_present is 1 where n_species > 0 and 0 otherwise", {
  input <- .make_model_input()
  out   <- prepare_model_dataframe(input)
  expect_equal(out$is_present, as.integer(out$n_species > 0))
})

# =============================================================================
# Covariate scaling
# =============================================================================

test_that("default scaled columns use _s suffix (not _scaled)", {
  input <- .make_model_input()
  out   <- prepare_model_dataframe(input, covariates = c("lat_r", "lon_r"))
  expect_true("lat_r_s" %in% names(out), info = "Expected lat_r_s")
  expect_true("lon_r_s" %in% names(out), info = "Expected lon_r_s")
  expect_false("lat_r_scaled" %in% names(out),
               info = "Suffix is _s not _scaled")
})

test_that("scaled columns have mean ~0 at site level", {
  # Mean-zero check is robust even when z-scoring over repeated rows
  input      <- .make_model_input(n_total_per_site = 15, seed = 1)
  out        <- prepare_model_dataframe(input, covariates = c("lat_r", "lon_r"))
  lat_scaled <- unique(out[, c("grid_id", "lat_r_s")])$lat_r_s
  expect_lt(abs(mean(lat_scaled)), 0.1, label = "mean of lat_r_s ~0")
})

test_that("scaled columns have sd close to 1 at site level", {
  # z-scoring is performed over all rows (n_species x n_sites), so the
  # sd of unique site-level scaled values may slightly exceed 1.
  # Tolerance of 0.2 accommodates this.
  input      <- .make_model_input(n_total_per_site = 15, seed = 1)
  out        <- prepare_model_dataframe(input, covariates = c("lat_r", "lon_r"))
  lat_scaled <- unique(out[, c("grid_id", "lat_r_s")])$lat_r_s
  expect_lt(abs(sd(lat_scaled) - 1), 0.2, label = "sd of lat_r_s approximately 1")
})

test_that("additional covariate is scaled with _s suffix", {
  input <- .make_model_input_with_depth()
  out   <- prepare_model_dataframe(input,
                                    covariates = c("lat_r", "lon_r", "depth"))
  expect_true("depth_s" %in% names(out), info = "Expected depth_s")
})

test_that("scale_params attribute is stored on output with correct structure", {
  input <- .make_model_input()
  out   <- prepare_model_dataframe(input, covariates = c("lat_r", "lon_r"))
  sp    <- attr(out, "scale_params")
  expect_false(is.null(sp),       info = "scale_params attribute missing")
  expect_true(is.list(sp))
  expect_true("lat_r" %in% names(sp))
  expect_true("lon_r" %in% names(sp))
  expect_false(is.null(sp$lat_r$center))
  expect_false(is.null(sp$lat_r$scale))
  expect_false(is.null(sp$lon_r$center))
  expect_false(is.null(sp$lon_r$scale))
})

# =============================================================================
# Correlated covariate warning
# =============================================================================

test_that("correlated covariates trigger a 'correlated above' warning", {
  input <- .make_correlated_input()
  expect_warning(
    prepare_model_dataframe(
      input,
      covariates    = c("lat_r", "corr_with_lat"),
      cor_threshold = 0.7
    ),
    regexp = "correlated above",
    ignore.case = FALSE
  )
})

test_that("correlated covariates are warned about but NOT dropped from output", {
  input <- .make_correlated_input()
  out   <- suppressWarnings(
    prepare_model_dataframe(
      input,
      covariates    = c("lat_r", "corr_with_lat"),
      cor_threshold = 0.7
    )
  )
  # prepare_model_dataframe warns but retains the column (user decides what to do)
  expect_true("corr_with_lat_s" %in% names(out),
              info = "Correlated column should still appear in output (only warned, not dropped)")
})

test_that("lat_r and lon_r in default input do not trigger correlation warning", {
  # The default helper uses non-monotone lon values to avoid r = +/-1
  input <- .make_model_input()
  expect_no_warning(
    prepare_model_dataframe(input, covariates = c("lat_r", "lon_r"))
  )
})

# =============================================================================
# habitat_observed_elsewhere flag
# =============================================================================

test_that("habitat_observed_elsewhere is logical", {
  input <- .make_model_input()
  out   <- prepare_model_dataframe(input)
  expect_type(out$habitat_observed_elsewhere, "logical")
})

test_that("rows with detections have habitat_observed_elsewhere = TRUE", {
  input        <- .make_model_input(n_total_per_site = 20)
  out          <- prepare_model_dataframe(input)
  present_rows <- out[out$n_species > 0, ]
  expect_true(all(present_rows$habitat_observed_elsewhere),
              info = "Detected rows must have habitat_observed_elsewhere = TRUE")
})

# =============================================================================
# Habitat column handling
# =============================================================================

test_that("main_habitat values are preserved from input", {
  input   <- .make_model_input()
  out     <- prepare_model_dataframe(input)
  in_hab  <- sort(unique(input$main_habitat))
  out_hab <- sort(unique(as.character(out$main_habitat)))
  expect_equal(out_hab, in_hab)
})

test_that("custom habitat_col parameter is respected", {
  input <- .make_model_input()
  input <- dplyr::rename(input, Biome = main_habitat)
  out   <- prepare_model_dataframe(input, habitat_col = "Biome")
  expect_true("Biome" %in% names(out))
  expect_false("main_habitat" %in% names(out))
})

# =============================================================================
# Input validation
# =============================================================================

test_that("missing required column triggers informative error", {
  input <- .make_model_input()
  input$taxon_name <- NULL
  expect_error(prepare_model_dataframe(input),
               regexp = "missing required columns")
})

test_that("missing covariate column triggers informative error", {
  input <- .make_model_input()
  expect_error(
    prepare_model_dataframe(input, covariates = c("lat_r", "depth")),
    regexp = "covariate columns not found"
  )
})
