# test-check_geographic_outliers.R
# Tests for check_geographic_outliers().
#
# Strategy: mock rgbif::occ_data (same layer test-fetch_gbif_occurrences.R
# mocks at) so the real fetch_gbif_occurrences() and
# CoordinateCleaner::cc_outl() both run for real underneath -- genuine
# end-to-end coverage of this function's own logic, only the network
# boundary is faked.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

# Local (bbox-scoped) occurrences: species A is well-supported locally (10
# records, never checked); B/C/D are all rare (below the default
# min_local_n = 5) and exercise the three possible outcomes.
.make_local <- function() {
  data.frame(
    gbifID           = 1:14,
    species          = c(rep("Species A", 10), "Species B", "Species C",
                         "Species C", "Species D"),
    speciesKey       = c(rep(100L, 10), 200L, 300L, 300L, 400L),
    decimalLatitude  = c(runif(10, 33.5, 34.5), 34.4, 34.0, 34.1, 10.02),
    decimalLongitude = c(runif(10, -120.5, -119.5), -119.86, -120.0, -119.9, 10.03),
    stringsAsFactors = FALSE
  )
}

# Global response for species B (key 200): the local point (gbifID 11, near
# California) plus a real, well-separated cluster on another continent --
# the local point should come out flagged as an outlier.
.global_resp_outlier <- function() {
  df <- data.frame(
    gbifID           = c(11L, 101:108),
    species          = "Species B",
    speciesKey       = 200L,
    decimalLatitude  = c(34.4, 5.0, 5.05, 5.1, 5.15, 5.2, 5.25, 5.3, 5.35),
    decimalLongitude = c(-119.86, 5.0, 5.05, 5.1, 5.15, 5.2, 5.25, 5.3, 5.35),
    stringsAsFactors = FALSE
  )
  list(data = df)
}

# Global response for species C (key 300): only the 2 local records, no
# additional global data -- below min_occs, cannot be tested.
.global_resp_sparse <- function() {
  df <- data.frame(
    gbifID           = c(12L, 13L),
    species          = "Species C",
    speciesKey       = 300L,
    decimalLatitude  = c(34.0, 34.1),
    decimalLongitude = c(-120.0, -119.9),
    stringsAsFactors = FALSE
  )
  list(data = df)
}

# Global response for species D (key 400): the local point (gbifID 14) sits
# inside a tight global cluster -- should come out consistent, not flagged.
.global_resp_consistent <- function() {
  df <- data.frame(
    gbifID           = c(14L, 401:408),
    species          = "Species D",
    speciesKey       = 400L,
    decimalLatitude  = c(10.02, 10.0, 10.05, 10.1, 10.15, 10.2, 10.25, 10.3, 10.35),
    decimalLongitude = c(10.03, 10.0, 10.05, 10.1, 10.15, 10.2, 10.25, 10.3, 10.35),
    stringsAsFactors = FALSE
  )
  list(data = df)
}

.mock_occ_data <- function(taxonKey, ...) {
  switch(
    as.character(taxonKey),
    "200" = .global_resp_outlier(),
    "300" = .global_resp_sparse(),
    "400" = .global_resp_consistent(),
    list(data = NULL)
  )
}

# =============================================================================
# Dependency / input validation
# =============================================================================

test_that("stops if CoordinateCleaner is not installed", {
  skip_if(requireNamespace("CoordinateCleaner", quietly = TRUE),
          "CoordinateCleaner is installed; skipping missing-package test")
  expect_error(
    check_geographic_outliers(.make_local()),
    regexp = "CoordinateCleaner"
  )
})

test_that("stops if local_occurrences is not a data frame", {
  skip_if_not_installed("CoordinateCleaner")
  expect_error(
    check_geographic_outliers("not a df"),
    regexp = "data frame"
  )
})

test_that("stops if a required column is missing", {
  skip_if_not_installed("CoordinateCleaner")
  df <- .make_local()
  df$speciesKey <- NULL
  expect_error(
    check_geographic_outliers(df),
    regexp = "speciesKey"
  )
})

# =============================================================================
# Behaviour (mocked GBIF)
# =============================================================================

test_that("species clearing min_local_n are never tested", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("rgbif")
  local_mocked_bindings(occ_data = .mock_occ_data, .package = "rgbif")

  out <- check_geographic_outliers(.make_local(), cache_dir = NULL)
  a_rows <- out[out$species == "Species A", ]

  expect_true(all(a_rows$outlier_status == "not_tested_sufficient_local_data"))
  expect_true(all(is.na(a_rows$global_n_unique)))
})

test_that("a locally-isolated record is flagged as an outlier against its global range", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("rgbif")
  local_mocked_bindings(occ_data = .mock_occ_data, .package = "rgbif")

  out <- check_geographic_outliers(.make_local(), cache_dir = NULL)
  b_row <- out[out$gbifID == 11L, ]

  expect_equal(b_row$outlier_status, "outlier")
  expect_gte(b_row$global_n_unique, 7L)
})

test_that("a species with too little global data is reported as untested, not passed", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("rgbif")
  local_mocked_bindings(occ_data = .mock_occ_data, .package = "rgbif")

  out <- check_geographic_outliers(.make_local(), cache_dir = NULL)
  c_rows <- out[out$species == "Species C", ]

  expect_true(all(c_rows$outlier_status == "insufficient_global_data"))
  expect_true(all(c_rows$global_n_unique < 7L))
})

test_that("a record within its global cluster is consistent, not flagged", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("rgbif")
  local_mocked_bindings(occ_data = .mock_occ_data, .package = "rgbif")

  out <- check_geographic_outliers(.make_local(), cache_dir = NULL)
  d_row <- out[out$gbifID == 14L, ]

  expect_equal(d_row$outlier_status, "consistent")
  expect_gte(d_row$global_n_unique, 7L)
})

test_that("every species clearing min_local_n short-circuits with a message", {
  skip_if_not_installed("CoordinateCleaner")
  df <- .make_local()
  expect_message(
    out <- check_geographic_outliers(df, min_local_n = 1L, cache_dir = NULL),
    regexp = "nothing to check"
  )
  expect_true(all(out$outlier_status == "not_tested_sufficient_local_data"))
})

test_that("cc_outl() is called once per species, not once for the whole batch", {
  # Regression test for a real production bug (2026-07-20, Mugu data):
  # CoordinateCleaner::cc_outl()'s "distance" method silently switches EVERY
  # species in a single call to a coarser raster approximation whenever ANY
  # ONE species in that call has >=10,000 records -- a locally-rare species
  # can still be globally common, so batching every rare species into one
  # cc_outl() call let one common species degrade every other species'
  # precision, clearing a real ~9,000km outlier. This asserts the fix (one
  # cc_outl() call per species) directly, rather than trying to synthesize
  # a 10,000+ row fixture to reproduce the raster branch itself.
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("rgbif")
  local_mocked_bindings(occ_data = .mock_occ_data, .package = "rgbif")

  call_species <- list()
  local_mocked_bindings(
    cc_outl = function(x, species, ...) {
      call_species[[length(call_species) + 1]] <<- unique(x[[species]])
      rep(TRUE, nrow(x))
    },
    .package = "CoordinateCleaner"
  )

  check_geographic_outliers(.make_local(), cache_dir = NULL)

  expect_true(all(lengths(call_species) == 1L))
  expect_setequal(unlist(call_species), c("Species B", "Species C", "Species D"))
})

test_that("output preserves row count and adds exactly the documented columns", {
  skip_if_not_installed("CoordinateCleaner")
  skip_if_not_installed("rgbif")
  local_mocked_bindings(occ_data = .mock_occ_data, .package = "rgbif")

  local <- .make_local()
  out   <- check_geographic_outliers(local, cache_dir = NULL)

  expect_equal(nrow(out), nrow(local))
  expect_true(all(c("local_n", "global_n_unique", "outlier_status") %in% names(out)))
})
