# test-fetch_occurrences_by_taxon.R
# Tests for fetch_occurrences_by_taxon().
#
# Strategy: get_gbif_occurrences() is mocked throughout (this function's own
# logic is the geometry union / call-grouping step, not the GBIF call itself,
# which is already covered by test-get_gbif_occurrences.R). Mock records each
# call's args so grouping behaviour can be asserted directly.

library(testthat)

.box_a <- make_bbox_wkt(lat = 34.40, lon = -120.41, radius_deg = 0.05)
.box_b <- make_bbox_wkt(lat = 34.47, lon = -120.36, radius_deg = 0.05) # overlaps .box_a
.box_c <- make_bbox_wkt(lat = 10.00, lon = 10.00, radius_deg = 0.05) # disjoint from both

.mock_recording_fetch <- function(calls_env) {
  function(keys, geometry, year_range = "2000,2024", limit = NULL, ...) {
    calls_env$n <- calls_env$n + 1L
    calls_env$calls[[calls_env$n]] <- list(keys = keys, geometry = geometry)
    tibble::tibble(
      gbifID   = paste0("g", calls_env$n, "_", seq_along(keys)),
      taxonKey = keys
    )
  }
}

# =============================================================================
# Input validation
# =============================================================================

test_that("stops on non-data-frame input", {
  expect_error(
    fetch_occurrences_by_taxon(list(taxon_key = 1L, geometry = .box_a)),
    regexp = "data frame"
  )
})

test_that("stops when required columns are missing", {
  expect_error(
    fetch_occurrences_by_taxon(data.frame(taxon_key = 1L)),
    regexp = "missing required column"
  )
  expect_error(
    fetch_occurrences_by_taxon(data.frame(geometry = .box_a)),
    regexp = "missing required column"
  )
})

test_that("stops on invalid combine_shared_geometry", {
  expect_error(
    fetch_occurrences_by_taxon(
      data.frame(taxon_key = 1L, geometry = .box_a),
      combine_shared_geometry = "yes"
    ),
    regexp = "combine_shared_geometry"
  )
})

test_that("stops when no valid rows remain after cleaning", {
  expect_error(
    fetch_occurrences_by_taxon(data.frame(taxon_key = NA_integer_, geometry = NA_character_)),
    regexp = "no valid"
  )
})

# =============================================================================
# Grouping behaviour (mocked get_gbif_occurrences)
# =============================================================================

test_that("same taxon at overlapping sites -> exactly one query, unioned geometry", {
  calls <- new.env()
  calls$n <- 0L
  calls$calls <- list()
  local_mocked_bindings(
    get_gbif_occurrences = .mock_recording_fetch(calls),
    .package = "TaxaFetch"
  )

  map <- data.frame(
    taxon_key = c(100L, 100L),
    geometry  = c(.box_a, .box_b)
  )

  out <- fetch_occurrences_by_taxon(map)

  expect_equal(calls$n, 1L)
  expect_equal(calls$calls[[1]]$keys, 100L)
  # unioned geometry differs from either individual box (it's the dissolved pair)
  expect_false(calls$calls[[1]]$geometry %in% c(.box_a, .box_b))
  expect_equal(nrow(out), 1L)
})

test_that("different taxa, same geometry -> combined into one call by default", {
  calls <- new.env()
  calls$n <- 0L
  calls$calls <- list()
  local_mocked_bindings(
    get_gbif_occurrences = .mock_recording_fetch(calls),
    .package = "TaxaFetch"
  )

  map <- data.frame(
    taxon_key = c(100L, 200L),
    geometry  = c(.box_a, .box_a)
  )

  out <- fetch_occurrences_by_taxon(map)

  expect_equal(calls$n, 1L)
  expect_setequal(calls$calls[[1]]$keys, c(100L, 200L))
  expect_equal(nrow(out), 2L)
})

test_that("combine_shared_geometry = FALSE issues one call per taxon key even with shared geometry", {
  calls <- new.env()
  calls$n <- 0L
  calls$calls <- list()
  local_mocked_bindings(
    get_gbif_occurrences = .mock_recording_fetch(calls),
    .package = "TaxaFetch"
  )

  map <- data.frame(
    taxon_key = c(100L, 200L),
    geometry  = c(.box_a, .box_a)
  )

  out <- fetch_occurrences_by_taxon(map, combine_shared_geometry = FALSE)

  expect_equal(calls$n, 2L)
  expect_setequal(vapply(calls$calls, function(x) x$keys, integer(1)), c(100L, 200L))
})

test_that("different taxa, disjoint geometry -> separate queries, no wasted union", {
  calls <- new.env()
  calls$n <- 0L
  calls$calls <- list()
  local_mocked_bindings(
    get_gbif_occurrences = .mock_recording_fetch(calls),
    .package = "TaxaFetch"
  )

  map <- data.frame(
    taxon_key = c(100L, 200L),
    geometry  = c(.box_a, .box_c)
  )

  out <- fetch_occurrences_by_taxon(map)

  expect_equal(calls$n, 2L)
  queried_keys <- vapply(calls$calls, function(x) x$keys, integer(1))
  expect_setequal(queried_keys, c(100L, 200L))
})

test_that("duplicate rows are dropped before unioning (no error, single query)", {
  calls <- new.env()
  calls$n <- 0L
  calls$calls <- list()
  local_mocked_bindings(
    get_gbif_occurrences = .mock_recording_fetch(calls),
    .package = "TaxaFetch"
  )

  map <- data.frame(
    taxon_key = c(100L, 100L, 100L),
    geometry  = c(.box_a, .box_a, .box_a)
  )

  out <- fetch_occurrences_by_taxon(map)

  expect_equal(calls$n, 1L)
  expect_equal(calls$calls[[1]]$geometry, .box_a)
})

test_that("NA taxon_key / geometry rows are dropped, not passed to get_gbif_occurrences", {
  calls <- new.env()
  calls$n <- 0L
  calls$calls <- list()
  local_mocked_bindings(
    get_gbif_occurrences = .mock_recording_fetch(calls),
    .package = "TaxaFetch"
  )

  map <- data.frame(
    taxon_key = c(100L, NA_integer_),
    geometry  = c(.box_a, .box_b)
  )

  out <- fetch_occurrences_by_taxon(map)

  expect_equal(calls$n, 1L)
  expect_equal(calls$calls[[1]]$keys, 100L)
})

test_that("year_range and limit are forwarded to get_gbif_occurrences", {
  captured <- new.env()
  local_mocked_bindings(
    get_gbif_occurrences = function(keys, geometry, year_range = "2000,2024",
                                    limit = NULL, ...) {
      captured$year_range <- year_range
      captured$limit <- limit
      tibble::tibble(gbifID = "g1", taxonKey = keys[1])
    },
    .package = "TaxaFetch"
  )

  fetch_occurrences_by_taxon(
    data.frame(taxon_key = 100L, geometry = .box_a),
    year_range = "1990,2020",
    limit = 500L
  )

  expect_equal(captured$year_range, "1990,2020")
  expect_equal(captured$limit, 500L)
})
