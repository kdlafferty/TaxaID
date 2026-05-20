# test-filter_gbif_quality.R
# Tests for filter_gbif_quality() and internal helper .count_decimal_places().
# Pure function -- no external dependencies or mocking required.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

# Minimal valid GBIF-like data frame covering all filter columns
.make_gbif <- function(n = 6) {
  data.frame(
    decimalLatitude              = c(34.12, 35.678, NA,    33.0,  36.111, 34.5),
    decimalLongitude             = c(-120.1, -119.5, -118.0, -121.0, -122.0, -120.0),
    basisOfRecord                = c("HUMAN_OBSERVATION", "FOSSIL_SPECIMEN",
                                     "HUMAN_OBSERVATION", "MACHINE_OBSERVATION",
                                     "UNKNOWN", "PRESERVED_SPECIMEN"),
    issues                       = c(NA, "COORDINATE_OUT_OF_RANGE", NA,
                                     "COUNTRY_COORDINATE_MISMATCH",
                                     NA, NA),
    coordinateUncertaintyInMeters = c(100, 300, NA, 600, 1000, 50),
    samplingProtocol             = c("net tow", "eDNA water sample", "trawl",
                                     "visual survey", "metabarcoding", "trap"),
    stringsAsFactors = FALSE
  )
}

# Minimal frame with coords only (for testing optional-column skipping)
.make_coords_only <- function(n = 4) {
  data.frame(
    decimalLatitude  = c(34.5, 35.1, NA, 33.9),
    decimalLongitude = c(-120.0, -119.5, -118.0, -121.0),
    stringsAsFactors = FALSE
  )
}

# =============================================================================
# Input validation
# =============================================================================

test_that("stops if data is not a data frame", {
  expect_error(filter_gbif_quality("not a df"), regexp = "data frame")
})

test_that("stops if decimalLatitude is missing", {
  df <- .make_gbif()
  df$decimalLatitude <- NULL
  expect_error(filter_gbif_quality(df), regexp = "decimalLatitude")
})

test_that("stops if decimalLongitude is missing", {
  df <- .make_gbif()
  df$decimalLongitude <- NULL
  expect_error(filter_gbif_quality(df), regexp = "decimalLongitude")
})

test_that("returns empty data frame unchanged when input is empty", {
  empty <- .make_gbif()[0, ]
  out   <- filter_gbif_quality(empty)
  expect_equal(nrow(out), 0L)
})

# =============================================================================
# Filter 1: coordinate completeness
# =============================================================================

test_that("removes records with NA decimalLatitude", {
  df  <- .make_gbif()
  n_na <- sum(is.na(df$decimalLatitude))
  out <- filter_gbif_quality(df, basis_keep = unique(df$basisOfRecord),
                              exclude_edna = FALSE,
                              bad_issues   = character(0),
                              max_coord_uncertainty = Inf)
  expect_equal(nrow(out), nrow(df) - n_na)
})

test_that("removes records with NA decimalLongitude", {
  df <- data.frame(
    decimalLatitude  = c(34.5, 35.0),
    decimalLongitude = c(NA,   -120.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE, bad_issues = character(0),
                              max_coord_uncertainty = Inf)
  expect_equal(nrow(out), 1L)
})

# =============================================================================
# Filter 2: basis of record
# =============================================================================

test_that("retains only records in basis_keep", {
  df  <- .make_gbif()
  df  <- df[!is.na(df$decimalLatitude), ]   # remove NA coord row first
  out <- filter_gbif_quality(df,
                              basis_keep   = c("HUMAN_OBSERVATION"),
                              exclude_edna = FALSE,
                              bad_issues   = character(0),
                              max_coord_uncertainty = Inf)
  expect_true(all(out$basisOfRecord == "HUMAN_OBSERVATION"))
})

test_that("skips basis filter with message when basisOfRecord column absent", {
  df  <- .make_coords_only()
  expect_message(
    out <- filter_gbif_quality(df, exclude_edna = FALSE,
                               bad_issues = character(0),
                               max_coord_uncertainty = Inf),
    regexp = "basisOfRecord.*skipping"
  )
  expect_equal(nrow(out), sum(!is.na(df$decimalLatitude)))
})

# =============================================================================
# Filter 3: GBIF issue codes
# =============================================================================

test_that("removes records containing any bad issue code", {
  df <- data.frame(
    decimalLatitude  = c(34.5, 35.0, 36.0),
    decimalLongitude = c(-120.0, -119.0, -118.0),
    issues           = c("COORDINATE_OUT_OF_RANGE", NA,
                         "COUNTRY_COORDINATE_MISMATCH"),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE,
                              max_coord_uncertainty = Inf,
                              bad_issues = c("COORDINATE_OUT_OF_RANGE",
                                             "COUNTRY_COORDINATE_MISMATCH"))
  expect_equal(nrow(out), 1L)
  expect_true(is.na(out$issues))
})

test_that("retains records with NA issues (no flag is not a bad flag)", {
  df <- data.frame(
    decimalLatitude  = c(34.5, 35.0),
    decimalLongitude = c(-120.0, -119.0),
    issues           = c(NA, "COORDINATE_OUT_OF_RANGE"),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE,
                              max_coord_uncertainty = Inf,
                              bad_issues = "COORDINATE_OUT_OF_RANGE")
  expect_equal(nrow(out), 1L)
  expect_true(is.na(out$issues))
})

test_that("skips issue filter when issues column absent", {
  df <- .make_coords_only()
  expect_message(
    filter_gbif_quality(df, exclude_edna = FALSE, bad_issues = "ZERO_COORDINATE",
                        max_coord_uncertainty = Inf),
    regexp = "issues.*skipping"
  )
})

test_that("skips issue filter when bad_issues is empty", {
  df <- data.frame(
    decimalLatitude  = 34.5,
    decimalLongitude = -120.0,
    issues           = "COORDINATE_OUT_OF_RANGE",
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE,
                              bad_issues   = character(0),
                              max_coord_uncertainty = Inf)
  expect_equal(nrow(out), 1L)
})

# =============================================================================
# Filter 4: coordinate uncertainty
# =============================================================================

test_that("removes records with uncertainty above threshold", {
  df <- data.frame(
    decimalLatitude               = c(34.5, 35.0, 36.0),
    decimalLongitude              = c(-120.0, -119.0, -118.0),
    coordinateUncertaintyInMeters = c(100, 600, 1000),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE, bad_issues = character(0),
                              max_coord_uncertainty = 500)
  expect_equal(nrow(out), 1L)
  expect_equal(out$coordinateUncertaintyInMeters, 100)
})

test_that("retains records with NA uncertainty (unknown != large)", {
  df <- data.frame(
    decimalLatitude               = c(34.5, 35.0),
    decimalLongitude              = c(-120.0, -119.0),
    coordinateUncertaintyInMeters = c(NA, 1000),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE, bad_issues = character(0),
                              max_coord_uncertainty = 500)
  expect_equal(nrow(out), 1L)
  expect_true(is.na(out$coordinateUncertaintyInMeters))
})

test_that("Inf max_coord_uncertainty disables the filter", {
  df <- data.frame(
    decimalLatitude               = c(34.5, 35.0),
    decimalLongitude              = c(-120.0, -119.0),
    coordinateUncertaintyInMeters = c(50000, 99999),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE, bad_issues = character(0),
                              max_coord_uncertainty = Inf)
  expect_equal(nrow(out), 2L)
})

test_that("skips uncertainty filter with message when column absent", {
  df <- .make_coords_only()
  expect_message(
    filter_gbif_quality(df, exclude_edna = FALSE, bad_issues = character(0),
                        max_coord_uncertainty = 500),
    regexp = "coordinateUncertaintyInMeters.*skipping"
  )
})

# =============================================================================
# Filter 5: coordinate decimal-place precision
# =============================================================================

test_that("removes records where both coords have fewer decimal places than threshold", {
  df <- data.frame(
    decimalLatitude  = c(34.0,   34.12,  35.0),   # 0dp, 2dp, 0dp
    decimalLongitude = c(-120.0, -119.5, -118.56), # 0dp, 1dp, 2dp
    stringsAsFactors = FALSE
  )
  # require >= 2 dp in at least one coord
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE, bad_issues = character(0),
                              max_coord_uncertainty = Inf,
                              max_coord_decimal_places = 2L)
  # row 1: lat=0dp, lon=0dp -> removed
  # row 2: lat=2dp -> kept
  # row 3: lon=2dp -> kept
  expect_equal(nrow(out), 2L)
})

test_that("OR logic: keeps record if EITHER coordinate meets threshold", {
  df <- data.frame(
    decimalLatitude  = c(34.123),   # 3 dp
    decimalLongitude = c(-120.0),   # 0 dp
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE, bad_issues = character(0),
                              max_coord_uncertainty = Inf,
                              max_coord_decimal_places = 3L)
  expect_equal(nrow(out), 1L)
})

test_that("NULL max_coord_decimal_places disables the filter", {
  df <- data.frame(
    decimalLatitude  = c(34.0, 35.0),
    decimalLongitude = c(-120.0, -119.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              exclude_edna = FALSE, bad_issues = character(0),
                              max_coord_uncertainty = Inf,
                              max_coord_decimal_places = NULL)
  expect_equal(nrow(out), 2L)
})

test_that("stops on invalid max_coord_decimal_places", {
  df <- .make_coords_only()
  expect_error(
    filter_gbif_quality(df, max_coord_decimal_places = 0L),
    regexp = "max_coord_decimal_places"
  )
  expect_error(
    filter_gbif_quality(df, max_coord_decimal_places = -1L),
    regexp = "max_coord_decimal_places"
  )
})

# =============================================================================
# Filter 6: eDNA / metabarcoding
# =============================================================================

test_that("removes records with eDNA keywords in samplingProtocol", {
  df <- data.frame(
    decimalLatitude  = c(34.5, 35.0),
    decimalLongitude = c(-120.0, -119.0),
    samplingProtocol = c("eDNA water sample", "net tow"),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              bad_issues = character(0),
                              max_coord_uncertainty = Inf,
                              exclude_edna = TRUE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$samplingProtocol, "net tow")
})

test_that("removes records with metabarcoding keyword (case-insensitive)", {
  df <- data.frame(
    decimalLatitude   = c(34.5, 35.0),
    decimalLongitude  = c(-120.0, -119.0),
    occurrenceRemarks = c("Metabarcoding survey", "visual census"),
    stringsAsFactors  = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              bad_issues = character(0),
                              max_coord_uncertainty = Inf,
                              exclude_edna = TRUE)
  expect_equal(nrow(out), 1L)
})

test_that("exclude_edna = FALSE skips eDNA filter entirely", {
  df <- data.frame(
    decimalLatitude  = c(34.5, 35.0),
    decimalLongitude = c(-120.0, -119.0),
    samplingProtocol = c("eDNA water sample", "bulk sample"),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              bad_issues = character(0),
                              max_coord_uncertainty = Inf,
                              exclude_edna = FALSE)
  expect_equal(nrow(out), 2L)
})

test_that("skips eDNA filter with message when no detectable columns present", {
  df <- .make_coords_only()
  expect_message(
    filter_gbif_quality(df, exclude_edna = TRUE, bad_issues = character(0),
                        max_coord_uncertainty = Inf),
    regexp = "eDNA.*skipping"
  )
})

# =============================================================================
# Output structure
# =============================================================================

test_that("column structure is unchanged after filtering", {
  df  <- .make_gbif()
  out <- filter_gbif_quality(df)
  expect_equal(names(out), names(df))
})

test_that("returns a data frame", {
  out <- filter_gbif_quality(.make_gbif())
  expect_true(is.data.frame(out))
})

# =============================================================================
# .count_decimal_places
# =============================================================================

test_that(".count_decimal_places returns 0 for whole numbers", {
  expect_equal(TaxaFetch:::.count_decimal_places(c(34.0, -120.0, 0.0)),
               c(0L, 0L, 0L))
})

test_that(".count_decimal_places counts correctly for typical coordinates", {
  expect_equal(TaxaFetch:::.count_decimal_places(c(34.1, 34.12, 34.123)),
               c(1L, 2L, 3L))
})

test_that(".count_decimal_places returns 0 for NA and Inf", {
  expect_equal(TaxaFetch:::.count_decimal_places(c(NA_real_, Inf, -Inf)),
               c(0L, 0L, 0L))
})

test_that(".count_decimal_places handles negative coordinates", {
  expect_equal(TaxaFetch:::.count_decimal_places(-119.75), 2L)
})

test_that(".count_decimal_places caps at 10", {
  # A value with more than 10 dp returns 10
  expect_lte(TaxaFetch:::.count_decimal_places(1.12345678901), 10L)
})
