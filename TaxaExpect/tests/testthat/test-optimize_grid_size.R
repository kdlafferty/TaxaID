# test-optimize_grid_size.R
# Tests for optimize_grid_size(), .score_one_resolution(), and .safe_normalise().
#
# Strategy:
#   - Use small min_grid/max_grid/step_grid ranges (e.g. 0.5–1.0 in 0.5 steps)
#     to keep the grid search fast in CI.
#   - Loosen quality thresholds (min_s=1, min_N=1) and set min_distinct_locs
#     to small values so modest synthetic fixtures are sufficient.
#   - Test each fallback path with progressively sparser fixtures.
#   - Test internal helpers directly via TaxaExpect:::.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

# Dense fixture: 5x5 lat/lon grid × 2 habitats × 5 species × 5 obs each.
# At grid_size=0.5 this resolves to 25 distinct locations, easily passing
# min_distinct_locs=5 with default-like thresholds.
.make_dense_obs <- function() {
  lats  <- seq(34.0, 36.0, by = 0.5)  # 5 distinct latitudes
  lons  <- seq(-121.0, -119.0, by = 0.5)  # 5 distinct longitudes
  habs  <- c("Rocky_Reef", "Kelp_Forest")
  specs <- paste0("Sp_", 1:5)

  rows <- do.call(rbind, lapply(lats, function(la) {
    do.call(rbind, lapply(lons, function(lo) {
      do.call(rbind, lapply(habs, function(h) {
        do.call(rbind, lapply(specs, function(sp) {
          data.frame(
            decimalLatitude  = la + runif(2, -0.05, 0.05),
            decimalLongitude = lo + runif(2, -0.05, 0.05),
            taxon_name       = sp,
            main_habitat     = h,
            stringsAsFactors = FALSE
          )
        }))
      }))
    }))
  }))
  rows
}

# Sparse fixture: only 4 distinct lat/lon pairs, 2 habitats, enough obs per
# cell to pass per-cell thresholds but not enough locations for min_distinct_locs.
.make_sparse_obs <- function() {
  lats <- c(34.0, 34.5, 35.0, 35.5)
  lons <- c(-120.0, -120.0, -120.0, -120.0)
  do.call(rbind, mapply(function(la, lo) {
    data.frame(
      decimalLatitude  = la + runif(15, -0.1, 0.1),
      decimalLongitude = lo + runif(15, -0.1, 0.1),
      taxon_name       = rep(paste0("Sp_", 1:5), 3),
      main_habitat     = rep(c("Rocky_Reef", "Kelp_Forest", "Sand"), 5),
      stringsAsFactors = FALSE
    )
  }, lats, lons, SIMPLIFY = FALSE))
}

# Single-point fixture: forces Fallback C
.make_single_point_obs <- function() {
  data.frame(
    decimalLatitude  = rep(34.5, 20),
    decimalLongitude = rep(-120.0, 20),
    taxon_name       = paste0("Sp_", rep(1:5, 4)),
    main_habitat     = rep("Rocky_Reef", 20),
    stringsAsFactors = FALSE
  )
}

# Shared loose thresholds used throughout to avoid needing huge datasets
.loose <- list(
  min_s_threshold      = 1L,
  min_N_threshold      = 1L,
  min_locs_per_habitat = 1L,
  min_grid             = 0.5,
  max_grid             = 1.0,
  step_grid            = 0.5
)

# =============================================================================
# Input validation
# =============================================================================

test_that("stops if weights do not sum to 1", {
  expect_error(
    optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                       weights = c(resolution = 0.5, quality = 0.5, stability = 0.5)),
    regexp = "sum to 1"
  )
})

test_that("stops if weights missing required names", {
  expect_error(
    optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                       weights = c(a = 0.5, b = 0.3, c = 0.2)),
    regexp = "resolution.*quality.*stability"
  )
})

test_that("stops if required columns are missing", {
  df <- .make_dense_obs()
  df$taxon_name <- NULL
  expect_error(
    optimize_grid_size(df, n_covariates = 2),
    regexp = "taxon_name"
  )
})

test_that("stops if all rows are NA in required columns", {
  df <- .make_dense_obs()
  df$taxon_name <- NA_character_
  expect_error(
    optimize_grid_size(df, n_covariates = 2,
                       species_col = "taxon_name"),
    regexp = "no rows remain"
  )
})

test_that("warns if protected_habitat not found in data", {
  expect_warning(
    optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                       protected_habitat    = "Nonexistent_Habitat",
                       min_distinct_locs    = .loose$min_distinct_locs,
                       min_s_threshold      = .loose$min_s_threshold,
                       min_N_threshold      = .loose$min_N_threshold,
                       min_locs_per_habitat = .loose$min_locs_per_habitat,
                       min_grid             = .loose$min_grid,
                       max_grid             = .loose$max_grid,
                       step_grid            = .loose$step_grid),
    regexp = "not found"
  )
})

test_that("accepts custom column names", {
  df <- .make_dense_obs()
  names(df)[names(df) == "decimalLatitude"]  <- "lat"
  names(df)[names(df) == "decimalLongitude"] <- "lon"
  names(df)[names(df) == "taxon_name"]          <- "taxon"
  names(df)[names(df) == "main_habitat"]     <- "habitat"
  expect_no_error(
    optimize_grid_size(df, n_covariates = 2,
                       lat_col     = "lat",
                       lon_col     = "lon",
                       species_col = "taxon",
                       habitat_col = "habitat",
                       min_distinct_locs    = 3L,
                       min_s_threshold      = .loose$min_s_threshold,
                       min_N_threshold      = .loose$min_N_threshold,
                       min_locs_per_habitat = .loose$min_locs_per_habitat,
                       min_grid             = .loose$min_grid,
                       max_grid             = .loose$max_grid,
                       step_grid            = .loose$step_grid)
  )
})

# =============================================================================
# Output structure (all paths)
# =============================================================================

test_that("always returns a list with four named elements", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  expect_named(out, c("summary_table", "best_grid", "explanation", "fallback_level"))
})

test_that("best_grid is always a single positive numeric", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  expect_true(is.numeric(out$best_grid))
  expect_equal(length(out$best_grid), 1L)
  expect_gt(out$best_grid, 0)
})

test_that("explanation is always a non-empty character string", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  expect_type(out$explanation, "character")
  expect_true(nzchar(out$explanation))
})

test_that("fallback_level is one of 'none', 'A', 'B', 'C'", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  expect_true(out$fallback_level %in% c("none", "A", "B", "C"))
})

# =============================================================================
# Optimal path (fallback_level = "none")
# =============================================================================

test_that("optimal path: fallback_level is 'none'", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  expect_equal(out$fallback_level, "none")
})

test_that("optimal path: summary_table is a non-empty data frame", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  expect_true(is.data.frame(out$summary_table))
  expect_gt(nrow(out$summary_table), 0L)
})

test_that("optimal path: summary_table has required columns", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  expected_cols <- c("grid_size", "suitability_score", "n_distinct_locs",
                     "cv_N", "n_samples", "median_N", "median_S", "n_habitats_kept")
  expect_true(all(expected_cols %in% names(out$summary_table)))
})

test_that("optimal path: summary_table is sorted by descending suitability_score", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  scores <- out$summary_table$suitability_score
  expect_true(all(diff(scores) <= 0))
})

test_that("optimal path: best_grid matches top row of summary_table", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  expect_equal(out$best_grid, out$summary_table$grid_size[1])
})

test_that("optimal path: suitability_scores are in [0, 1]", {
  out <- optimize_grid_size(.make_dense_obs(), n_covariates = 2,
                             min_distinct_locs    = 3L,
                             min_s_threshold      = .loose$min_s_threshold,
                             min_N_threshold      = .loose$min_N_threshold,
                             min_locs_per_habitat = .loose$min_locs_per_habitat,
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  scores <- out$summary_table$suitability_score
  expect_true(all(scores >= 0 & scores <= 1, na.rm = TRUE))
})

# =============================================================================
# Fallback C (single-cell, fully pooled)
# =============================================================================

test_that("fallback C: triggered when data are too sparse for any multi-cell grid", {
  expect_warning(
    out <- optimize_grid_size(.make_single_point_obs(), n_covariates = 2,
                               min_distinct_locs    = 20L,
                               min_s_threshold      = 1L,
                               min_N_threshold      = 1L,
                               min_locs_per_habitat = 1L,
                               min_grid             = 0.1,
                               max_grid             = 0.5,
                               step_grid            = 0.1),
    regexp = "Fallback C"
  )
  expect_equal(out$fallback_level, "C")
})

test_that("fallback C: summary_table is an empty tibble", {
  suppressWarnings(
    out <- optimize_grid_size(.make_single_point_obs(), n_covariates = 2,
                               min_distinct_locs    = 20L,
                               min_s_threshold      = 1L,
                               min_N_threshold      = 1L,
                               min_locs_per_habitat = 1L,
                               min_grid             = 0.1,
                               max_grid             = 0.5,
                               step_grid            = 0.1)
  )
  expect_equal(nrow(out$summary_table), 0L)
})

test_that("fallback C: best_grid is positive and larger than max_grid", {
  suppressWarnings(
    out <- optimize_grid_size(.make_single_point_obs(), n_covariates = 2,
                               min_distinct_locs    = 20L,
                               min_s_threshold      = 1L,
                               min_N_threshold      = 1L,
                               min_locs_per_habitat = 1L,
                               min_grid             = 0.1,
                               max_grid             = 0.5,
                               step_grid            = 0.1)
  )
  expect_gt(out$best_grid, 0)
})

# =============================================================================
# Protected habitat
# =============================================================================

test_that("protected habitat is retained even when below min_locs_per_habitat", {
  # Use dense obs with one rare habitat artificially added
  df <- .make_dense_obs()
  # Add just 2 observations of a rare habitat (would normally be dropped)
  df <- rbind(df, data.frame(
    decimalLatitude  = c(34.0, 34.0),
    decimalLongitude = c(-120.0, -120.0),
    taxon_name       = c("Sp_1", "Sp_2"),
    main_habitat     = "Rare_Habitat",
    stringsAsFactors = FALSE
  ))
  out <- optimize_grid_size(df, n_covariates = 2,
                             protected_habitat    = "Rare_Habitat",
                             min_distinct_locs    = 3L,
                             min_s_threshold      = 1L,
                             min_N_threshold      = 1L,
                             min_locs_per_habitat = 5L,  # would drop Rare_Habitat
                             min_grid             = .loose$min_grid,
                             max_grid             = .loose$max_grid,
                             step_grid            = .loose$step_grid)
  # n_habitats_kept should include Rare_Habitat in at least one resolution row
  expect_true(any(out$summary_table$n_habitats_kept >= 3L))
})

# =============================================================================
# .safe_normalise
# =============================================================================

test_that(".safe_normalise maps a range to [0, 1]", {
  x   <- c(1, 2, 3, 4, 5)
  out <- TaxaExpect:::.safe_normalise(x)
  expect_equal(out[1], 0)
  expect_equal(out[5], 1)
  expect_true(all(out >= 0 & out <= 1))
})

test_that(".safe_normalise returns 0s when all values are equal (max == min)", {
  out <- TaxaExpect:::.safe_normalise(c(5, 5, 5))
  expect_true(all(out == 0))
})

test_that(".safe_normalise treats Inf as NA and still normalises finite values", {
  out <- TaxaExpect:::.safe_normalise(c(1, 2, Inf))
  expect_true(is.na(out[3]))
  expect_equal(out[1], 0)
  expect_equal(out[2], 1)
})

test_that(".safe_normalise returns all NA when all values are non-finite", {
  out <- TaxaExpect:::.safe_normalise(c(NA, Inf, -Inf))
  expect_true(all(is.na(out)))
})

# =============================================================================
# .score_one_resolution
# =============================================================================

test_that(".score_one_resolution returns NULL when no cells pass quality thresholds", {
  df <- data.frame(
    decimalLatitude  = c(34.5),
    decimalLongitude = c(-120.0),
    taxon_name       = c("Sp_1"),
    main_habitat     = c("Rocky_Reef"),
    stringsAsFactors = FALSE
  )
  out <- TaxaExpect:::.score_one_resolution(
    res                  = 0.5,
    df_clean             = df,
    lat_col              = "decimalLatitude",
    lon_col              = "decimalLongitude",
    species_col          = "taxon_name",
    habitat_col          = "main_habitat",
    min_s_threshold      = 5L,   # 1 species -- will fail
    min_N_threshold      = 10L,  # 1 obs -- will fail
    min_distinct_locs    = 20L,
    min_locs_per_habitat = 3L,
    protected_habitat    = NULL
  )
  expect_null(out)
})

test_that(".score_one_resolution returns a one-row tibble with correct columns", {
  df <- .make_dense_obs()
  out <- TaxaExpect:::.score_one_resolution(
    res                  = 0.5,
    df_clean             = df,
    lat_col              = "decimalLatitude",
    lon_col              = "decimalLongitude",
    species_col          = "taxon_name",
    habitat_col          = "main_habitat",
    min_s_threshold      = 1L,
    min_N_threshold      = 1L,
    min_distinct_locs    = 3L,
    min_locs_per_habitat = 1L,
    protected_habitat    = NULL
  )
  expect_false(is.null(out))
  expect_equal(nrow(out), 1L)
  expected_cols <- c("grid_size", "n_samples", "n_distinct_locs",
                     "n_habitats_kept", "median_S", "median_N",
                     "cv_N", "max_habitat_locs", "passed")
  expect_true(all(expected_cols %in% names(out)))
})

test_that(".score_one_resolution: passed = TRUE when n_distinct_locs >= min_distinct_locs", {
  df <- .make_dense_obs()
  out <- TaxaExpect:::.score_one_resolution(
    res                  = 0.5,
    df_clean             = df,
    lat_col              = "decimalLatitude",
    lon_col              = "decimalLongitude",
    species_col          = "taxon_name",
    habitat_col          = "main_habitat",
    min_s_threshold      = 1L,
    min_N_threshold      = 1L,
    min_distinct_locs    = 3L,
    min_locs_per_habitat = 1L,
    protected_habitat    = NULL
  )
  expect_true(out$passed)
  expect_gte(out$n_distinct_locs, 3L)
})

test_that(".score_one_resolution: grid_size column equals the res argument", {
  df <- .make_dense_obs()
  out <- TaxaExpect:::.score_one_resolution(
    res                  = 0.5,
    df_clean             = df,
    lat_col              = "decimalLatitude",
    lon_col              = "decimalLongitude",
    species_col          = "taxon_name",
    habitat_col          = "main_habitat",
    min_s_threshold      = 1L,
    min_N_threshold      = 1L,
    min_distinct_locs    = 3L,
    min_locs_per_habitat = 1L,
    protected_habitat    = NULL
  )
  expect_equal(out$grid_size, 0.5)
})
