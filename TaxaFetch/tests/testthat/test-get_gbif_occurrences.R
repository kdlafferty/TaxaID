# test-get_gbif_occurrences.R
# Tests for get_gbif_occurrences().
#
# Strategy:
#   - Input validation (keys, key_threshold, rank_filter, columns): no network needed.
#   - Download-path column handling: exercised end to end via a pre-populated cache
#     hit (synthetic SIMPLE_CSV zip + matching meta.rds), same technique as
#     test-download_gbif_occurrences.R. Covers the wrapper's own select_cols_dl
#     translation ("issues" -> "issue" for the SIMPLE_CSV-native argument) and
#     column standardization/rank_filter -- this is the wrapper's own logic, not
#     just a passthrough to download_gbif_occurrences(), and previously had no
#     test coverage at all (a gap flagged in the Session 131 pre-review pass).

library(testthat)

skip_if_not_installed("rgbif")
skip_if_not_installed("zip")

# =============================================================================
# Input validation (no network)
# =============================================================================

test_that("stops if no valid keys supplied", {
  expect_error(
    get_gbif_occurrences(keys = NA_integer_, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))"),
    regexp = "no valid 'keys'"
  )
})

test_that("stops on invalid key_threshold", {
  expect_error(
    get_gbif_occurrences(
      keys = 1L, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))", key_threshold = -1
    ),
    regexp = "key_threshold"
  )
})

test_that("stops on invalid rank_filter", {
  expect_error(
    get_gbif_occurrences(
      keys = 1L, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))", rank_filter = c("a", "b")
    ),
    regexp = "rank_filter"
  )
})

test_that("stops on invalid columns", {
  expect_error(
    get_gbif_occurrences(
      keys = 1L, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))", columns = 42
    ),
    regexp = "columns"
  )
})

# =============================================================================
# Download-path column handling (cache-hit, no network)
# =============================================================================

.make_fake_gbif_zip <- function(dir) {
  csv_name <- "0000000-000000000000000.csv"
  writeLines(
    c(
      paste(c("gbifID", "datasetKey", "license", "taxonKey", "speciesKey",
              "kingdom", "phylum", "class", "order", "family", "genus", "species",
              "infraspecificEpithet", "taxonRank", "scientificName",
              "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
              "countryCode", "stateProvince", "year", "month", "day",
              "basisOfRecord", "issue", "occurrenceStatus"),
            collapse = "\t"),
      paste(c("1", "d1", "CC0", "100", "100",
              "Animalia", "Chordata", "Actinopterygii", "Gadiformes", "Gadidae",
              "Gadus", "Gadus morhua", "", "SPECIES", "Gadus morhua L.",
              "60.0", "2.0", "100",
              "NO", "", "2020", "1", "1",
              "HUMAN_OBSERVATION", "", "PRESENT"),
            collapse = "\t")
    ),
    file.path(dir, csv_name)
  )
  zip_path <- file.path(dir, "0000000-000000000000000.zip")
  zip::zip(zip_path, csv_name, root = dir)
  zip_path
}

test_that("download path standardizes columns and reports 'issues', not 'issue'", {
  cache_dir <- tempfile("gbif_test_")
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)
  zip_path <- .make_fake_gbif_zip(cache_dir)

  keys       <- 100L
  geometry   <- "POLYGON((0 0,0 1,1 1,1 0,0 0))"
  year_range <- "2000,2024"

  meta_path <- TaxaFetch:::.gbif_dl_meta_path(cache_dir, keys, geometry, year_range)
  saveRDS(
    list(dl_key = "0000000-000000000000000", zip_path = zip_path, timestamp = Sys.time()),
    meta_path
  )

  out <- get_gbif_occurrences(
    keys          = keys,
    geometry      = geometry,
    year_range    = year_range,
    key_threshold = 1L,
    cache_dir     = cache_dir,
    gbif_user     = "u", gbif_pwd = "p", gbif_email = "e@example.com"
  )

  expect_true("issues" %in% names(out))
  expect_false("issue" %in% names(out))
  expect_setequal(names(out), TaxaFetch:::.gbif_standard_columns())
  expect_equal(nrow(out), 1L)
})

test_that("rank_filter drops non-species records on the download path", {
  cache_dir <- tempfile("gbif_test_")
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)
  zip_path <- .make_fake_gbif_zip(cache_dir)

  keys       <- 200L
  geometry   <- "POLYGON((0 0,0 1,1 1,1 0,0 0))"
  year_range <- "2000,2024"

  meta_path <- TaxaFetch:::.gbif_dl_meta_path(cache_dir, keys, geometry, year_range)
  saveRDS(
    list(dl_key = "0000000-000000000000000", zip_path = zip_path, timestamp = Sys.time()),
    meta_path
  )

  out <- get_gbif_occurrences(
    keys          = keys,
    geometry      = geometry,
    year_range    = year_range,
    key_threshold = 1L,
    rank_filter   = "genus",
    cache_dir     = cache_dir,
    gbif_user     = "u", gbif_pwd = "p", gbif_email = "e@example.com"
  )

  expect_equal(nrow(out), 0L)
})
