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

# Same fixture shape, but named after a caller-supplied dl_key -- used to
# mock rgbif::occ_download_get()'s real behavior (writing "<dl_key>.zip"
# into the destination directory) for the overwrite/orphan-cleanup tests.
.make_fake_gbif_zip_named <- function(dir, dl_key) {
  csv_name <- paste0(dl_key, ".csv")
  writeLines(
    c(
      paste(c("gbifID", "taxonKey", "speciesKey", "kingdom", "phylum",
              "class", "order", "family", "genus", "species",
              "decimalLatitude", "decimalLongitude", "basisOfRecord",
              "issue", "occurrenceStatus", "year", "month", "day"),
            collapse = "\t"),
      paste(c("2", "100", "100", "Animalia", "Chordata", "Actinopterygii",
              "Gadiformes", "Gadidae", "Gadus", "Gadus morhua",
              "61.0", "3.0", "HUMAN_OBSERVATION", "", "PRESENT",
              "2021", "1", "1"),
            collapse = "\t")
    ),
    file.path(dir, csv_name)
  )
  zip_path <- file.path(dir, paste0(dl_key, ".zip"))
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

# =============================================================================
# overwrite = TRUE: orphan cleanup + cache summary (2026-09-03)
# =============================================================================

test_that("overwrite = TRUE in a non-interactive session removes the old cached zip after a fresh download", {
  cache_dir <- tempfile("gbif_test_")
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)

  old_zip <- .make_fake_gbif_zip(cache_dir)
  keys       <- 100L
  geometry   <- "POLYGON((0 0,0 1,1 1,1 0,0 0))"
  year_range <- "2000,2024"
  meta_path  <- TaxaFetch:::.gbif_dl_meta_path(cache_dir, keys, geometry, year_range)
  saveRDS(
    list(dl_key = "0000000-000000000000000", zip_path = old_zip, timestamp = Sys.time() - 86400),
    meta_path
  )
  expect_true(file.exists(old_zip))

  new_dl_key <- "1111111-999999999999999"
  testthat::local_mocked_bindings(
    occ_download      = function(...) new_dl_key,
    occ_download_wait = function(...) invisible(NULL),
    occ_download_get  = function(key, path, overwrite = TRUE) {
      .make_fake_gbif_zip_named(path, key)
      invisible(NULL)
    },
    .package = "rgbif"
  )

  out <- download_gbif_occurrences(
    keys = keys, geometry = geometry, year_range = year_range,
    cache_dir = cache_dir, overwrite = TRUE,
    gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
  )

  expect_false(file.exists(old_zip))
  new_zip <- file.path(cache_dir, paste0(new_dl_key, ".zip"))
  expect_true(file.exists(new_zip))
  meta <- readRDS(meta_path)
  expect_equal(meta$dl_key, new_dl_key)
  expect_equal(attr(out, "download_key"), new_dl_key)
})

# The interactive confirmation prompt itself (`interactive()` + `utils::menu()`)
# is not covered by an automated test: `interactive()` is a .Primitive, not an
# ordinary closure, so it cannot be reliably intercepted by
# testthat::local_mocked_bindings() the way an ordinary base/utils function can
# -- confirmed directly (a mocked TRUE return silently had no effect on the
# real call path). The non-interactive orphan-cleanup path above already
# covers the actual bug fix (the old zip is never left behind); the prompt's
# own UI behavior (showing the cached zip's date/size, honoring both menu
# choices) is exercised by hand per this feature's plan verification step --
# run the same `overwrite = TRUE` repeat call from a real interactive R
# console and confirm both choices behave as documented in `@param overwrite`.

test_that("download_gbif_occurrences reports the total cache size after a run", {
  cache_dir <- tempfile("gbif_test_")
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)
  zip_path <- .make_fake_gbif_zip(cache_dir)

  keys       <- 100L
  geometry   <- "POLYGON((0 0,0 1,1 1,1 0,0 0))"
  year_range <- "2000,2024"
  meta_path  <- TaxaFetch:::.gbif_dl_meta_path(cache_dir, keys, geometry, year_range)
  saveRDS(
    list(dl_key = "0000000-000000000000000", zip_path = zip_path, timestamp = Sys.time()),
    meta_path
  )

  expect_message(
    download_gbif_occurrences(
      keys = keys, geometry = geometry, year_range = year_range,
      cache_dir = cache_dir, overwrite = FALSE,
      gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
    ),
    "TaxaFetch cache: 2 file"
  )
})
