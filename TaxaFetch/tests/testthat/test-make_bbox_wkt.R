# test-make_bbox_wkt.R
# Tests for make_bbox_wkt().
# Pure function -- no external dependencies, no mocking needed.

library(testthat)

# =============================================================================
# Return type and structure
# =============================================================================

test_that("returns a length-1 character string", {
  out <- make_bbox_wkt(34.5, -120.0, 1.0)
  expect_type(out, "character")
  expect_equal(length(out), 1L)
})

test_that("output starts with POLYGON ((", {
  out <- make_bbox_wkt(34.5, -120.0, 1.0)
  expect_true(startsWith(out, "POLYGON (("))
})

test_that("output ends with ))", {
  out <- make_bbox_wkt(34.5, -120.0, 1.0)
  expect_true(endsWith(out, "))"))
})

test_that("ring is closed: first and last vertex are identical", {
  out    <- make_bbox_wkt(34.5, -120.0, 1.0)
  coords <- gsub("POLYGON \\(\\(|\\)\\)", "", out)
  pairs  <- strsplit(trimws(coords), ",\\s*")[[1]]
  expect_equal(trimws(pairs[1]), trimws(pairs[length(pairs)]))
})

test_that("output contains exactly 5 vertex pairs (closed ring)", {
  out    <- make_bbox_wkt(34.5, -120.0, 1.0)
  coords <- gsub("POLYGON \\(\\(|\\)\\)", "", out)
  pairs  <- strsplit(trimws(coords), ",\\s*")[[1]]
  expect_equal(length(pairs), 5L)
})

# =============================================================================
# Correct bounding box values
# =============================================================================

test_that("box corners match lat +/- radius and lon +/- radius", {
  lat <- 34.5; lon <- -120.0; r <- 1.0
  out <- make_bbox_wkt(lat, lon, r)

  # Extract all numeric values from the WKT string
  nums <- as.numeric(regmatches(out, gregexpr("-?[0-9]+\\.?[0-9]*", out))[[1]])

  expect_true((lon - r) %in% nums)   # min_lon
  expect_true((lon + r) %in% nums)   # max_lon
  expect_true((lat - r) %in% nums)   # min_lat
  expect_true((lat + r) %in% nums)   # max_lat
})

test_that("WKT uses lon-lat order (X before Y)", {
  # For lat=0, lon=10, radius=1: min_lon=9, min_lat=-1
  # First coordinate pair in WKT should be "9 -1" (lon first)
  out   <- make_bbox_wkt(0, 10, 1)
  # First pair after "POLYGON ((" is min_lon min_lat
  first <- regmatches(out, regexpr("(?<=POLYGON \\(\\()[-0-9. ]+(?=,)",
                                   out, perl = TRUE))
  parts <- as.numeric(strsplit(trimws(first), "\\s+")[[1]])
  expect_equal(parts[1], 9)    # lon first
  expect_equal(parts[2], -1)   # lat second
})

test_that("fractional radius_deg produces correct decimal corners", {
  out  <- make_bbox_wkt(36.0, -121.5, 0.5)
  nums <- as.numeric(regmatches(out, gregexpr("-?[0-9]+\\.?[0-9]*", out))[[1]])
  expect_true(35.5  %in% nums)
  expect_true(36.5  %in% nums)
  expect_true(-122.0 %in% nums)
  expect_true(-121.0 %in% nums)
})

# =============================================================================
# Input validation -- type and length
# =============================================================================

test_that("stops on non-numeric lat", {
  expect_error(make_bbox_wkt("34.5", -120.0, 1.0), regexp = "'lat'")
})

test_that("stops on non-numeric lon", {
  expect_error(make_bbox_wkt(34.5, "-120.0", 1.0), regexp = "'lon'")
})

test_that("stops on non-numeric radius_deg", {
  expect_error(make_bbox_wkt(34.5, -120.0, "1"), regexp = "'radius_deg'")
})

test_that("stops on NA lat", {
  expect_error(make_bbox_wkt(NA_real_, -120.0, 1.0), regexp = "'lat'")
})

test_that("stops on NA lon", {
  expect_error(make_bbox_wkt(34.5, NA_real_, 1.0), regexp = "'lon'")
})

test_that("stops on NA radius_deg", {
  expect_error(make_bbox_wkt(34.5, -120.0, NA_real_), regexp = "'radius_deg'")
})

test_that("stops on vector lat", {
  expect_error(make_bbox_wkt(c(34.5, 35.0), -120.0, 1.0), regexp = "'lat'")
})

# =============================================================================
# Input validation -- range
# =============================================================================

test_that("stops on lat > 90", {
  expect_error(make_bbox_wkt(91, 0, 1), regexp = "\\[-90, 90\\]")
})

test_that("stops on lat < -90", {
  expect_error(make_bbox_wkt(-91, 0, 1), regexp = "\\[-90, 90\\]")
})

test_that("stops on lon > 180", {
  expect_error(make_bbox_wkt(0, 181, 1), regexp = "\\[-180, 180\\]")
})

test_that("stops on lon < -180", {
  expect_error(make_bbox_wkt(0, -181, 1), regexp = "\\[-180, 180\\]")
})

test_that("stops on radius_deg <= 0", {
  expect_error(make_bbox_wkt(34.5, -120.0, 0),    regexp = "positive")
  expect_error(make_bbox_wkt(34.5, -120.0, -0.5), regexp = "positive")
})

# =============================================================================
# Boundary clamping -- pole and antimeridian
# =============================================================================

test_that("stops when box extends beyond north pole", {
  expect_error(make_bbox_wkt(89, 0, 2), regexp = "poles")
})

test_that("stops when box extends beyond south pole", {
  expect_error(make_bbox_wkt(-89, 0, 2), regexp = "poles")
})

test_that("stops when box crosses antimeridian eastward", {
  expect_error(make_bbox_wkt(0, 179, 2), regexp = "antimeridian")
})

test_that("stops when box crosses antimeridian westward", {
  expect_error(make_bbox_wkt(0, -179, 2), regexp = "antimeridian")
})

test_that("does NOT stop when box exactly touches latitude boundary", {
  # lat=89, radius=1 -> max_lat=90 exactly -- should be allowed
  expect_no_error(make_bbox_wkt(89, 0, 1))
})
