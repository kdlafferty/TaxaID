# test-create_sites_from_grid.R
# Tests for create_sites_from_grid().
# Pure function -- no external dependencies or mocking required.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

.make_occ <- function() {
  data.frame(
    decimalLatitude  = c(34.12, 34.37, -33.7, 0.0,  89.9),
    decimalLongitude = c(-119.63, -120.14, 18.4, 0.0, -179.5),
    taxon_name       = paste0("Sp_", 1:5),
    stringsAsFactors = FALSE
  )
}

# =============================================================================
# Input validation
# =============================================================================

test_that("stops if data is not a data frame", {
  expect_error(
    create_sites_from_grid("not a df", grid_size = 0.5),
    regexp = "must be a dataframe"
  )
})

test_that("stops if lat_col is not found", {
  df <- data.frame(decimalLongitude = -120.0, stringsAsFactors = FALSE)
  expect_error(
    create_sites_from_grid(df, grid_size = 0.5),
    regexp = "decimalLatitude"
  )
})

test_that("stops if lon_col is not found", {
  df <- data.frame(decimalLatitude = 34.5, stringsAsFactors = FALSE)
  expect_error(
    create_sites_from_grid(df, grid_size = 0.5),
    regexp = "decimalLongitude"
  )
})

test_that("stops if custom lat_col is not found", {
  df <- data.frame(lat = 34.5, decimalLongitude = -120.0,
                   stringsAsFactors = FALSE)
  expect_error(
    create_sites_from_grid(df, grid_size = 0.5, lat_col = "latitude"),
    regexp = "latitude"
  )
})

test_that("stops if grid_size is zero", {
  expect_error(
    create_sites_from_grid(.make_occ(), grid_size = 0),
    regexp = "grid_size"
  )
})

test_that("stops if grid_size is negative", {
  expect_error(
    create_sites_from_grid(.make_occ(), grid_size = -0.5),
    regexp = "grid_size"
  )
})

test_that("stops if grid_size is NA", {
  expect_error(
    create_sites_from_grid(.make_occ(), grid_size = NA_real_),
    regexp = "grid_size"
  )
})

test_that("stops if grid_size is non-numeric", {
  expect_error(
    create_sites_from_grid(.make_occ(), grid_size = "0.5"),
    regexp = "grid_size"
  )
})

test_that("stops if grid_size is a vector of length > 1", {
  expect_error(
    create_sites_from_grid(.make_occ(), grid_size = c(0.5, 1.0)),
    regexp = "grid_size"
  )
})

test_that("warns if grid_size > 10 (likely in km, not degrees)", {
  expect_warning(
    create_sites_from_grid(.make_occ(), grid_size = 11),
    regexp = "unusually large"
  )
})

test_that("no warning for grid_size exactly equal to 10", {
  expect_no_warning(create_sites_from_grid(.make_occ(), grid_size = 10))
})

# =============================================================================
# Output structure
# =============================================================================

test_that("returns a data frame", {
  out <- create_sites_from_grid(.make_occ(), grid_size = 0.5)
  expect_true(is.data.frame(out))
})

test_that("same number of rows as input", {
  df  <- .make_occ()
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_equal(nrow(out), nrow(df))
})

test_that("adds lat_r, lon_r, and grid_id columns", {
  out <- create_sites_from_grid(.make_occ(), grid_size = 0.5)
  expect_true("lat_r"   %in% names(out))
  expect_true("lon_r"   %in% names(out))
  expect_true("grid_id" %in% names(out))
})

test_that("grid_id_raw intermediate column is NOT in output", {
  out <- create_sites_from_grid(.make_occ(), grid_size = 0.5)
  expect_false("grid_id_raw" %in% names(out))
})

test_that("all original columns are preserved", {
  df  <- .make_occ()
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_true(all(names(df) %in% names(out)))
})

test_that("row order is unchanged", {
  df  <- .make_occ()
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_equal(out$taxon_name, df$taxon_name)
})

# =============================================================================
# Snapping / rounding logic
# =============================================================================

test_that("lat_r and lon_r are rounded to nearest grid multiple", {
  df <- data.frame(
    decimalLatitude  = 34.37,
    decimalLongitude = -119.63,
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_equal(out$lat_r, 34.5)
  expect_equal(out$lon_r, -119.5)
})

test_that("points within the same grid cell share the same grid_id", {
  df <- data.frame(
    decimalLatitude  = c(34.26, 34.49, 34.74),   # all round to 34.5 at 0.5 res
    decimalLongitude = c(-120.26, -120.3, -120.4), # all round to -120.5 at 0.5 res
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_equal(length(unique(out$grid_id)), 1L)
})

test_that("points in different grid cells have different grid_ids", {
  df <- data.frame(
    decimalLatitude  = c(34.1, 34.9),
    decimalLongitude = c(-120.0, -120.0),
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_equal(length(unique(out$grid_id)), 2L)
})

test_that("grid cell size of 1.0 rounds to nearest integer degree", {
  df <- data.frame(
    decimalLatitude  = c(34.4, 34.6),
    decimalLongitude = c(-120.0, -120.0),
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 1.0)
  expect_equal(out$lat_r[1], 34.0)
  expect_equal(out$lat_r[2], 35.0)
})

# =============================================================================
# grid_id encoding
# =============================================================================

test_that("grid_id starts with 'Grid_'", {
  out <- create_sites_from_grid(.make_occ(), grid_size = 0.5)
  expect_true(all(startsWith(out$grid_id, "Grid_")))
})

test_that("decimal points are replaced with 'p' in grid_id", {
  df <- data.frame(
    decimalLatitude  = 34.5,
    decimalLongitude = -119.5,
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_false(grepl("\\.", out$grid_id))
  expect_true(grepl("p", out$grid_id))
})

test_that("minus signs are replaced with 'm' in grid_id", {
  df <- data.frame(
    decimalLatitude  = 34.5,
    decimalLongitude = -119.5,
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_false(grepl("-", out$grid_id))
  expect_true(grepl("m", out$grid_id))
})

test_that("grid_id is correct for a known lat/lon pair", {
  # lat=34.5, lon=-119.5, grid_size=0.5
  # sprintf -> "Grid_34.5_-119.5"
  # replace - with m -> "Grid_34.5_m119.5"
  # replace . with p -> "Grid_34p5_m119p5"
  df <- data.frame(
    decimalLatitude  = 34.5,
    decimalLongitude = -119.5,
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_equal(out$grid_id, "Grid_34p5_m119p5")
})

test_that("grid_id is correct for whole-number coordinates", {
  # lat=34.0, lon=-120.0 -> "Grid_34p0_m120p0"
  df <- data.frame(
    decimalLatitude  = 34.3,
    decimalLongitude = -120.2,
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 1.0)
  expect_equal(out$grid_id, "Grid_34p0_m120p0")
})

test_that("grid_id is correct for positive longitude", {
  df <- data.frame(
    decimalLatitude  = -33.5,
    decimalLongitude = 18.5,
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_equal(out$grid_id, "Grid_m33p5_18p5")
})

test_that("grid_id contains no characters that break R formula syntax", {
  out <- create_sites_from_grid(.make_occ(), grid_size = 0.5)
  bad_chars <- grepl("[^A-Za-z0-9_]", out$grid_id)
  expect_false(any(bad_chars))
})

# =============================================================================
# Custom lat_col / lon_col
# =============================================================================

test_that("accepts custom lat_col and lon_col names", {
  df <- data.frame(
    lat = 34.37, lon = -119.63,
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5,
                                lat_col = "lat", lon_col = "lon")
  expect_equal(out$lat_r, 34.5)
  expect_equal(out$lon_r, -119.5)
})

# =============================================================================
# Edge cases
# =============================================================================

test_that("handles zero-coordinate (equator / prime meridian)", {
  df <- data.frame(
    decimalLatitude = 0.0, decimalLongitude = 0.0,
    stringsAsFactors = FALSE
  )
  out <- create_sites_from_grid(df, grid_size = 0.5)
  expect_equal(out$grid_id, "Grid_0p0_0p0")
})

test_that("works on single-row data frame", {
  df <- data.frame(
    decimalLatitude = 34.5, decimalLongitude = -120.0,
    stringsAsFactors = FALSE
  )
  expect_no_error(create_sites_from_grid(df, grid_size = 0.5))
})
