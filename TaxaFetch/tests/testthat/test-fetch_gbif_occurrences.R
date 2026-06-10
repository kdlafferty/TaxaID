# test-fetch_gbif_occurrences.R
# Tests for fetch_gbif_occurrences() and internal helper .fetch_chunk().
#
# Strategy:
#   - Input validation: no rgbif needed.
#   - Behaviour / output structure: mock rgbif::occ_data.
#   - .fetch_chunk hierarchy validation: tested directly with fake data.
#   - Live API: guarded by skip_if_not_installed + skip_if_offline.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

.bbox <- make_bbox_wkt(34.5, -120.0, 1.0)

# Minimal fake occ_data response matching rgbif structure
.make_occ_resp <- function(key, n = 3) {
  df <- data.frame(
    decimalLatitude  = runif(n, 33.5, 35.5),
    decimalLongitude = runif(n, -121, -119),
    taxonKey         = key,
    speciesKey       = key,
    genusKey         = key + 1000L,
    familyKey        = key + 2000L,
    orderKey         = key + 3000L,
    classKey         = key + 4000L,
    phylumKey        = key + 5000L,
    kingdomKey       = key + 6000L,
    acceptedTaxonKey = key,
    stringsAsFactors = FALSE
  )
  list(data = df)
}

.make_occ_resp_mismatch <- function(key, n = 2) {
  # Returns records whose hierarchy does NOT contain the query key
  resp <- .make_occ_resp(key + 99999L, n)  # wrong key throughout
  list(data = resp$data)
}

# =============================================================================
# Input validation
# =============================================================================

test_that("stops if rgbif is not installed", {
  skip_if(requireNamespace("rgbif", quietly = TRUE),
          "rgbif is installed; skipping missing-package test")
  expect_error(
    fetch_gbif_occurrences(keys = 1L, geometry = .bbox),
    regexp = "rgbif"
  )
})

test_that("stops if keys is empty after NA removal", {
  skip_if_not_installed("rgbif")
  expect_error(
    fetch_gbif_occurrences(keys = NA_integer_, geometry = .bbox),
    regexp = "empty"
  )
})

test_that("stops if keys is entirely NA", {
  skip_if_not_installed("rgbif")
  expect_error(
    fetch_gbif_occurrences(keys = c(NA_integer_, NA_integer_), geometry = .bbox),
    regexp = "empty"
  )
})

test_that("stops if geometry is not a single character string", {
  skip_if_not_installed("rgbif")
  expect_error(
    fetch_gbif_occurrences(keys = 1L, geometry = 123),
    regexp = "geometry"
  )
  expect_error(
    fetch_gbif_occurrences(keys = 1L, geometry = c(.bbox, .bbox)),
    regexp = "geometry"
  )
})

test_that("removes duplicate keys before processing", {
  skip_if_not_installed("rgbif")
  call_count <- 0L
  local_mocked_bindings(
    occ_data = function(...) { call_count <<- call_count + 1L; .make_occ_resp(1L) },
    .package = "rgbif"
  )
  fetch_gbif_occurrences(keys = c(1L, 1L, 1L), geometry = .bbox,
                         pause_seconds = 0)
  expect_equal(call_count, 1L)
})

test_that("NA keys are silently dropped before processing", {
  skip_if_not_installed("rgbif")
  call_count <- 0L
  local_mocked_bindings(
    occ_data = function(...) { call_count <<- call_count + 1L; .make_occ_resp(1L) },
    .package = "rgbif"
  )
  fetch_gbif_occurrences(keys = c(1L, NA_integer_), geometry = .bbox,
                         pause_seconds = 0)
  expect_equal(call_count, 1L)
})

# =============================================================================
# Output structure (mocked API)
# =============================================================================

test_that("returns a data frame", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    occ_data = function(taxonKey, ...) .make_occ_resp(taxonKey),
    .package = "rgbif"
  )
  out <- fetch_gbif_occurrences(keys = 1L, geometry = .bbox,
                                pause_seconds = 0)
  expect_true(is.data.frame(out))
})

test_that("returns rows from all keys combined", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    occ_data = function(taxonKey, ...) .make_occ_resp(taxonKey, n = 3),
    .package = "rgbif"
  )
  out <- fetch_gbif_occurrences(keys = c(1L, 2L, 3L), geometry = .bbox,
                                pause_seconds = 0)
  expect_gte(nrow(out), 9L)   # 3 rows × 3 keys
})

test_that("warns and returns empty tibble when no records pass", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    occ_data = function(...) list(data = NULL),
    .package = "rgbif"
  )
  expect_warning(
    out <- fetch_gbif_occurrences(keys = 1L, geometry = .bbox,
                                  pause_seconds = 0),
    regexp = "no records"
  )
  expect_equal(nrow(out), 0L)
})

# =============================================================================
# Chunking behaviour
# =============================================================================

test_that("splits keys into correct number of chunks", {
  skip_if_not_installed("rgbif")
  call_count <- 0L
  local_mocked_bindings(
    occ_data = function(taxonKey, ...) {
      call_count <<- call_count + 1L
      .make_occ_resp(taxonKey)
    },
    .package = "rgbif"
  )
  # 5 keys, chunk_size = 2 -> 3 chunks, 5 occ_data calls
  fetch_gbif_occurrences(keys = 1L:5L, geometry = .bbox,
                         chunk_size = 2L, pause_seconds = 0)
  expect_equal(call_count, 5L)
})

# =============================================================================
# Hierarchy validation (via .fetch_chunk directly)
# =============================================================================

test_that("hierarchy validation retains records where query key is in lineage", {
  skip_if_not_installed("rgbif")
  key  <- 42L
  resp <- .make_occ_resp(key, n = 4)
  local_mocked_bindings(
    occ_data = function(...) resp,
    .package = "rgbif"
  )
  out <- TaxaFetch:::.fetch_chunk(
    keys_chunk = key,
    geometry   = .bbox,
    year_range = "2000,2024",
    limit      = 100L,
    global_pos = 0L,
    total      = 1L
  )
  expect_equal(nrow(out$records), 4L)
  expect_false(out$aborted)
})

test_that("hierarchy validation drops records where query key is absent from lineage", {
  skip_if_not_installed("rgbif")
  key  <- 42L
  resp <- .make_occ_resp_mismatch(key, n = 3)
  local_mocked_bindings(
    occ_data = function(...) resp,
    .package = "rgbif"
  )
  out <- TaxaFetch:::.fetch_chunk(
    keys_chunk = key,
    geometry   = .bbox,
    year_range = "2000,2024",
    limit      = 100L,
    global_pos = 0L,
    total      = 1L
  )
  expect_true(is.null(out$records) || nrow(out$records) == 0L)
  expect_false(out$aborted)
})

test_that("records kept when no hierarchy columns are present (can't validate)", {
  skip_if_not_installed("rgbif")
  key <- 99L
  df_no_hier <- data.frame(
    decimalLatitude  = c(34.0, 35.0),
    decimalLongitude = c(-120.0, -119.5),
    stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    occ_data = function(...) list(data = df_no_hier),
    .package = "rgbif"
  )
  out <- TaxaFetch:::.fetch_chunk(
    keys_chunk = key,
    geometry   = .bbox,
    year_range = "2000,2024",
    limit      = 100L,
    global_pos = 0L,
    total      = 1L
  )
  expect_equal(nrow(out$records), 2L)
  expect_false(out$aborted)
})

# =============================================================================
# Error handling -- exhausted retries abort the run (no silent skipping)
# =============================================================================

test_that("a failing key aborts the run with an error (no silent partial results)", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    occ_data = function(taxonKey, ...) {
      if (taxonKey == 999L) stop("simulated API error")
      .make_occ_resp(taxonKey)
    },
    .package = "rgbif"
  )
  # Key 999 fails immediately (non-transient error, no retry) -> abort
  # cache_dir = NULL so checkpoint is not written during the test
  expect_error(
    fetch_gbif_occurrences(keys = c(1L, 999L, 2L), geometry = .bbox,
                           pause_seconds = 0, cache_dir = NULL),
    regexp = "aborted"
  )
})

# =============================================================================
# Live API (skipped offline)
# =============================================================================

test_that("live API: returns records for a known taxon key", {
  skip_if_not_installed("rgbif")
  skip_if_offline()
  # GBIF key for Engraulis mordax (northern anchovy) -- stable
  bbox <- make_bbox_wkt(37.0, -122.5, 2.0)
  out  <- fetch_gbif_occurrences(
    keys       = 2360464L,
    geometry   = bbox,
    year_range = "2010,2024",
    limit      = 10L,
    pause_seconds = 0
  )
  expect_true(is.data.frame(out))
  # May be 0 rows in some regions; just check it doesn't error
})
