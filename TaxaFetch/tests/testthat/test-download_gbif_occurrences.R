# test-download_gbif_occurrences.R
# Tests for download_gbif_occurrences().
#
# Strategy:
#   - Input validation (credentials, keys, geometry, year_range): no network needed.
#   - issue -> issues rename: exercised end to end via a pre-populated cache hit
#     (synthetic SIMPLE_CSV zip + matching meta.rds), so no rgbif/network calls
#     are made. Regression test for a Session 129/131 finding: a prior session
#     incorrectly claimed this rename was never implemented; it was, and always
#     had been -- this test pins the behavior down so that claim can't silently
#     recur.

library(testthat)

skip_if_not_installed("rgbif")
skip_if_not_installed("zip")

# =============================================================================
# Fixtures
# =============================================================================

# Build a minimal SIMPLE_CSV-shaped zip: tab-delimited, "issue" column
# (singular, matching GBIF's real SIMPLE_CSV export), inside a zip whose
# member file name does not itself contain "occurrence" (exercises the
# fallback file-detection branch in .read_gbif_zip() as a side effect).
# Uses zip::zip()'s `root` argument to store a relative entry name without
# a setwd() dance, and to avoid depending on an external `zip` binary.
.make_fake_gbif_zip <- function(dir) {
  csv_name <- "0000000-000000000000000.csv"
  writeLines(
    c(
      paste(c("gbifID", "taxonKey", "speciesKey", "kingdom", "phylum",
              "class", "order", "family", "genus", "species",
              "decimalLatitude", "decimalLongitude", "basisOfRecord",
              "issue", "occurrenceStatus", "year", "month", "day"),
            collapse = "\t"),
      paste(c("1", "100", "100", "Animalia", "Chordata", "Actinopterygii",
              "Gadiformes", "Gadidae", "Gadus", "Gadus morhua",
              "60.0", "2.0", "HUMAN_OBSERVATION", "", "PRESENT",
              "2020", "1", "1"),
            collapse = "\t")
    ),
    file.path(dir, csv_name)
  )
  zip_path <- file.path(dir, "0000000-000000000000000.zip")
  zip::zip(zip_path, csv_name, root = dir)
  zip_path
}

# =============================================================================
# Input validation (no network)
# =============================================================================

test_that("stops with informative message when GBIF credentials are missing", {
  expect_error(
    download_gbif_occurrences(
      keys = 1L, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))",
      gbif_user = "", gbif_pwd = "", gbif_email = ""
    ),
    regexp = "missing GBIF credentials"
  )
})

test_that("stops if keys is empty after NA removal", {
  expect_error(
    download_gbif_occurrences(
      keys = NA_integer_, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))",
      gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
    ),
    regexp = "empty"
  )
})

test_that("stops on malformed year_range", {
  expect_error(
    download_gbif_occurrences(
      keys = 1L, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))",
      year_range = "not-a-range",
      gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
    ),
    regexp = "year_range"
  )
})

# =============================================================================
# issue -> issues rename (cache-hit path, no network)
# =============================================================================

test_that("renames SIMPLE_CSV's 'issue' column to 'issues' on import", {
  cache_dir <- tempfile("gbif_test_")
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)
  zip_path  <- .make_fake_gbif_zip(cache_dir)

  keys       <- 100L
  geometry   <- "POLYGON((0 0,0 1,1 1,1 0,0 0))"
  year_range <- "2000,2024"

  meta_path <- TaxaFetch:::.gbif_dl_meta_path(cache_dir, keys, geometry, year_range)
  saveRDS(
    list(dl_key = "0000000-000000000000000", zip_path = zip_path, timestamp = Sys.time()),
    meta_path
  )

  out <- download_gbif_occurrences(
    keys       = keys,
    geometry   = geometry,
    year_range = year_range,
    cache_dir  = cache_dir,
    overwrite  = FALSE,
    gbif_user  = "u", gbif_pwd = "p", gbif_email = "e@example.com"
  )

  expect_true("issues" %in% names(out))
  expect_false("issue" %in% names(out))
})
