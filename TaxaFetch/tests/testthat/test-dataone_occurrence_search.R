# test-dataone_occurrence_search.R
# Tests for dataone_occurrence_search.R internals. All pure -- no network calls.
#
# Covers:
#   .parse_coordinates_field()  raw coordinates text -> bbox list
#   .parse_pasta_response()     PASTA Solr XML -> tibble (spatialCoverage path)
#   .bbox_overlaps()            bbox intersection test
#
# Added 2026-08 (human review, taxafetch_review.Rmd): a real, previously
# uncaught bug -- coordinates_raw was NA for every real PASTA record because
# the real XML nests coordinates under <spatialCoverage>, not directly under
# <document>, and the real coordinate text is a Solr "ENVELOPE(minX, maxX,
# maxY, minY)" string, a format this file's parser never recognized at all.

library(testthat)

# =============================================================================
# .parse_coordinates_field() -- ENVELOPE format (the confirmed real format)
# =============================================================================

test_that("parses a real ENVELOPE() coordinates string (degenerate point box)", {
  # Real example from live PASTA data (human review, 2026-08): SBC LTER
  # Kelp Forest Community Dynamics Fish abundance dataset.
  raw <- "ENVELOPE(-119.7445915, -119.7445915, 34.400275, 34.400275)"
  pb <- TaxaFetch:::.parse_coordinates_field(raw)
  expect_false(is.null(pb))
  expect_equal(pb$west,  -119.7445915)
  expect_equal(pb$east,  -119.7445915)
  expect_equal(pb$north, 34.400275)
  expect_equal(pb$south, 34.400275)
})

test_that("parses a non-degenerate ENVELOPE() string with correct N/S/E/W order", {
  # west=-121.0, east=-118.5, north=35.0, south=33.5 -- ENVELOPE order is
  # minX, maxX, maxY, minY, i.e. west, east, north, south.
  raw <- "ENVELOPE(-121.0, -118.5, 35.0, 33.5)"
  pb <- TaxaFetch:::.parse_coordinates_field(raw)
  expect_equal(pb$west,  -121.0)
  expect_equal(pb$east,  -118.5)
  expect_equal(pb$north, 35.0)
  expect_equal(pb$south, 33.5)
})

test_that("ENVELOPE parsing is case-insensitive and tolerates extra whitespace", {
  raw <- "envelope( -121.0 ,  -118.5,35.0 ,33.5 )"
  pb <- TaxaFetch:::.parse_coordinates_field(raw)
  expect_equal(pb$west,  -121.0)
  expect_equal(pb$north, 35.0)
})

test_that("legacy key:value format (N:/S:/E:/W:) still parses correctly", {
  raw <- "N:35.0 S:33.5 E:-118.5 W:-121.0"
  pb <- TaxaFetch:::.parse_coordinates_field(raw)
  expect_equal(pb$north, 35.0)
  expect_equal(pb$south, 33.5)
  expect_equal(pb$east,  -118.5)
  expect_equal(pb$west,  -121.0)
})

test_that("bare 4-number fallback uses corrected WESN order (west,east,north,south)", {
  # No ENVELOPE keyword, no N:/S:/E:/W: tokens -- falls to the numeric-token
  # heuristic. Before the fix, this branch mislabeled nums[3]/nums[4] as
  # south/north (swapped relative to the confirmed real order).
  raw <- "-121.0 -118.5 35.0 33.5"
  pb <- TaxaFetch:::.parse_coordinates_field(raw)
  expect_equal(pb$west,  -121.0)
  expect_equal(pb$east,  -118.5)
  expect_equal(pb$north, 35.0)
  expect_equal(pb$south, 33.5)
})

test_that("unparseable coordinates text returns NULL (fail open)", {
  expect_null(TaxaFetch:::.parse_coordinates_field("not a coordinate string"))
  expect_null(TaxaFetch:::.parse_coordinates_field(NA_character_))
  expect_null(TaxaFetch:::.parse_coordinates_field(""))
})

# =============================================================================
# .parse_pasta_response() -- real spatialCoverage/coordinates XML structure
# =============================================================================

test_that(".parse_pasta_response() extracts coordinates nested under spatialCoverage", {
  raw_xml <- paste0(
    "<resultset>",
    "<document>",
    "<packageid>knb-lter-sbc.17.18</packageid>",
    "<title>SBC LTER: Reef: Kelp Forest Community Dynamics</title>",
    "<spatialCoverage>",
    "<coordinates>ENVELOPE(-119.7445915, -119.7445915, 34.400275, 34.400275)</coordinates>",
    "</spatialCoverage>",
    "</document>",
    "</resultset>"
  )
  docs <- TaxaFetch:::.parse_pasta_response(raw_xml)
  expect_false(is.null(docs))
  expect_equal(nrow(docs), 1L)
  expect_false(is.na(docs$coordinates_raw[[1L]]))
  expect_equal(
    docs$coordinates_raw[[1L]],
    "ENVELOPE(-119.7445915, -119.7445915, 34.400275, 34.400275)"
  )
})

test_that(".parse_pasta_response() still handles the legacy flat <coordinates> shape", {
  raw_xml <- paste0(
    "<resultset>",
    "<document>",
    "<packageid>knb-lter-sbc.99.1</packageid>",
    "<coordinates>N:35.0 S:33.5 E:-118.5 W:-121.0</coordinates>",
    "</document>",
    "</resultset>"
  )
  docs <- TaxaFetch:::.parse_pasta_response(raw_xml)
  expect_equal(docs$coordinates_raw[[1L]], "N:35.0 S:33.5 E:-118.5 W:-121.0")
})

test_that(".parse_pasta_response() returns NA coordinates_raw when neither shape is present", {
  raw_xml <- paste0(
    "<resultset>",
    "<document>",
    "<packageid>knb-lter-sbc.5.1</packageid>",
    "</document>",
    "</resultset>"
  )
  docs <- TaxaFetch:::.parse_pasta_response(raw_xml)
  expect_true(is.na(docs$coordinates_raw[[1L]]))
})

# =============================================================================
# .bbox_overlaps()
# =============================================================================

test_that(".bbox_overlaps() detects overlap and non-overlap correctly", {
  query <- list(west = -120, east = -119, south = 34, north = 35)
  overlapping <- list(west = -119.7, east = -119.7, north = 34.4, south = 34.4)
  non_overlapping <- list(west = 10, east = 11, north = 50, south = 49)
  expect_true(TaxaFetch:::.bbox_overlaps(overlapping, query))
  expect_false(TaxaFetch:::.bbox_overlaps(non_overlapping, query))
})
