# Tests for fetch_reference_recordings() and internal helpers
#
# Offline tests: validate inputs and internal helpers with no network access.
# Online tests: guarded by skip_if_offline(); hit the real Xeno-canto API.

# ==============================================================================
# Input validation (offline)
# ==============================================================================

test_that("fetch_reference_recordings() errors on non-character species", {
  expect_error(fetch_reference_recordings(123), "non-empty character vector")
})

test_that("fetch_reference_recordings() errors on empty species vector", {
  expect_error(fetch_reference_recordings(character(0)),
               "non-empty character vector")
})

test_that("fetch_reference_recordings() errors on invalid quality grade", {
  expect_error(fetch_reference_recordings("Turdus migratorius", quality = "Z"),
               "invalid quality grade")
})

test_that("fetch_reference_recordings() errors on invalid max_per_species", {
  expect_error(
    fetch_reference_recordings("Turdus migratorius", max_per_species = 0L),
    "positive integer"
  )
})

test_that("fetch_reference_recordings() quality grades are case-insensitive", {
  # Should not error — "a" should be normalized to "A"
  skip_if_offline()
  skip_if_not_installed("httr2")
  skip_if(nchar(Sys.getenv("XC_API_KEY")) == 0L, "XC_API_KEY not set")
  result <- fetch_reference_recordings("Turdus migratorius",
                                       quality = "a",
                                       max_per_species = 1L,
                                       verbose = FALSE)
  expect_true(nrow(result) >= 0L)  # just checking no error thrown
})

# ==============================================================================
# .parse_xc_duration() (offline)
# ==============================================================================

test_that(".parse_xc_duration() parses m:ss format", {
  expect_equal(TaxaLikely:::.parse_xc_duration("1:35"), 95)
  expect_equal(TaxaLikely:::.parse_xc_duration("0:45"), 45)
  expect_equal(TaxaLikely:::.parse_xc_duration("10:00"), 600)
})

test_that(".parse_xc_duration() handles NA and empty string", {
  expect_true(is.na(TaxaLikely:::.parse_xc_duration(NA_character_)))
  expect_true(is.na(TaxaLikely:::.parse_xc_duration("")))
})

test_that(".parse_xc_duration() handles seconds-only string", {
  expect_equal(TaxaLikely:::.parse_xc_duration("45"), 45)
})

# ==============================================================================
# .xc_standardize_cols() (offline)
# ==============================================================================

test_that(".xc_standardize_cols() renames API fields and builds species column", {
  raw <- data.frame(
    id  = "123456",
    gen = "Turdus",
    sp  = "migratorius",
    en  = "American Robin",
    cnt = "United States",
    q   = "A",
    lic = "//creativecommons.org/licenses/by-nc-sa/4.0/",
    file = "https://xeno-canto.org/123456/download",
    length = "0:35",
    also = I(list(character(0))),
    stringsAsFactors = FALSE
  )

  out <- TaxaLikely:::.xc_standardize_cols(raw)

  expect_true("recording_id" %in% names(out))
  expect_true("species"      %in% names(out))
  expect_true("common_name"  %in% names(out))
  expect_true("quality"      %in% names(out))
  expect_true("duration_s"   %in% names(out))
  expect_false("sp"          %in% names(out))
  expect_equal(out$recording_id, "XC123456")
  expect_equal(out$species, "Turdus migratorius")
  expect_equal(out$duration_s, 35)
  expect_equal(out$common_name, "American Robin")
})

# ==============================================================================
# API key validation (offline)
# ==============================================================================

test_that("fetch_reference_recordings() errors when api_key is empty", {
  expect_error(
    fetch_reference_recordings("Turdus migratorius", api_key = ""),
    "API key"
  )
})

# ==============================================================================
# Online tests (require network + httr2 + XC_API_KEY)
# ==============================================================================

test_that("fetch_reference_recordings() returns expected columns for a real query", {
  skip_if_offline()
  skip_if_not_installed("httr2")
  skip_if(nchar(Sys.getenv("XC_API_KEY")) == 0L, "XC_API_KEY not set")

  result <- fetch_reference_recordings(
    species         = "Turdus migratorius",
    quality         = "A",
    max_per_species = 5L,
    verbose         = FALSE
  )

  expect_s3_class(result, "data.frame")
  expect_true(nrow(result) > 0L)
  expected_cols <- c("recording_id", "species", "genus", "common_name",
                     "quality", "file_url", "duration_s", "local_path")
  expect_true(all(expected_cols %in% names(result)))
  expect_true(all(result$quality == "A"))
  expect_true(all(startsWith(result$recording_id, "XC")))
  expect_equal(attr(result, "xc_query"), "Turdus migratorius")
})

test_that("fetch_reference_recordings() respects max_per_species cap", {
  skip_if_offline()
  skip_if_not_installed("httr2")
  skip_if(nchar(Sys.getenv("XC_API_KEY")) == 0L, "XC_API_KEY not set")

  result <- fetch_reference_recordings(
    species         = "Turdus migratorius",
    quality         = c("A", "B"),
    max_per_species = 3L,
    verbose         = FALSE
  )

  expect_true(nrow(result) <= 3L)
})

test_that("fetch_reference_recordings() handles species with no recordings gracefully", {
  skip_if_offline()
  skip_if_not_installed("httr2")
  skip_if(nchar(Sys.getenv("XC_API_KEY")) == 0L, "XC_API_KEY not set")

  # A clearly non-existent species name
  result <- fetch_reference_recordings(
    species  = "Imaginus nonexistentus",
    verbose  = FALSE
  )

  expect_true(nrow(result) == 0L)
})
