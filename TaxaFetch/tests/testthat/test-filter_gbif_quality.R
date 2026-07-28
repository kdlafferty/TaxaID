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

test_that("does NOT remove records with only generic 'bulk sample'/'water sample' wording", {
  # A plankton tow or water-quality collection note can legitimately say
  # "water sample"/"bulk sample" with no eDNA/metabarcoding content at all --
  # these must not be excluded as presence data (see filter_gbif_quality.R's
  # eDNA-filter comment for the rationale).
  df <- data.frame(
    decimalLatitude  = c(34.5, 35.0),
    decimalLongitude = c(-120.0, -119.0),
    samplingProtocol = c("bulk sample, plankton net tow", "grab water sample"),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0),
                              bad_issues = character(0),
                              max_coord_uncertainty = Inf,
                              exclude_edna = TRUE)
  expect_equal(nrow(out), 2L)
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
# Filter 9: CoordinateCleaner checks (equal coords / near-zero / near GBIF HQ)
# =============================================================================

test_that("skips CoordinateCleaner checks with message when package not installed", {
  skip_if(requireNamespace("CoordinateCleaner", quietly = TRUE),
          "CoordinateCleaner is installed; skipping missing-package test")
  df <- .make_coords_only()
  expect_message(
    filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                        bad_issues = character(0), max_coord_uncertainty = Inf),
    regexp = "CoordinateCleaner.*not installed"
  )
})

test_that("removes records with identical lat/lon (cc_equ)", {
  skip_if_not_installed("CoordinateCleaner")
  df <- data.frame(
    decimalLatitude  = c(34.5, 10.0, 35.0),
    decimalLongitude = c(-120.0, 10.0, -119.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_near_zero = FALSE, exclude_near_gbif_hq = FALSE)
  expect_equal(nrow(out), 2L)
  expect_false(any(out$decimalLatitude == out$decimalLongitude))
})

test_that("removes records near (0,0) (cc_zero)", {
  skip_if_not_installed("CoordinateCleaner")
  df <- data.frame(
    decimalLatitude  = c(34.5, 0.01, 35.0),
    decimalLongitude = c(-120.0, 0.02, -119.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_gbif_hq = FALSE)
  expect_equal(nrow(out), 2L)
})

test_that("exclude_equal_coords/near_zero/near_gbif_hq = FALSE skips all three checks", {
  skip_if_not_installed("CoordinateCleaner")
  df <- data.frame(
    decimalLatitude  = c(10.0, 0.01),
    decimalLongitude = c(10.0, 0.02),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE,
                              exclude_country_centroid = FALSE, exclude_capital = FALSE,
                              flag_institution = FALSE)
  expect_equal(nrow(out), 2L)
})

test_that("removes a record at a real country centroid (cc_cen)", {
  skip_if_not_installed("CoordinateCleaner")
  ref <- CoordinateCleaner::countryref[CoordinateCleaner::countryref$type == "country", ]
  ref <- ref[!is.na(ref$centroid.lon) & !is.na(ref$centroid.lat), ][1, ]
  df <- data.frame(
    decimalLatitude  = c(ref$centroid.lat, 34.5),
    decimalLongitude = c(ref$centroid.lon, -120.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_capital = FALSE,
                              flag_institution = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$decimalLongitude, -120.0)
})

test_that("removes a record at a real national capital (cc_cap)", {
  skip_if_not_installed("CoordinateCleaner")
  ref <- CoordinateCleaner::countryref[!is.na(CoordinateCleaner::countryref$capital.lon) &
                                       !is.na(CoordinateCleaner::countryref$capital.lat), ][1, ]
  df <- data.frame(
    decimalLatitude  = c(ref$capital.lat, 34.5),
    decimalLongitude = c(ref$capital.lon, -120.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              flag_institution = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$decimalLongitude, -120.0)
})

test_that("flags (does NOT remove) a record near a real biodiversity institution (cc_inst)", {
  skip_if_not_installed("CoordinateCleaner")
  ref <- CoordinateCleaner::institutions[!is.na(CoordinateCleaner::institutions$decimalLongitude) &
                                         !is.na(CoordinateCleaner::institutions$decimalLatitude), ][1, ]
  df <- data.frame(
    decimalLatitude  = c(ref$decimalLatitude, 34.5),
    decimalLongitude = c(ref$decimalLongitude, -120.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE)
  # Both rows retained -- institution proximity never removes anything
  expect_equal(nrow(out), 2L)
  expect_equal(out$institution_flag, c(TRUE, FALSE))
  expect_equal(out$institution_name[1], ref$name)
  expect_equal(out$institution_type[1], ref$type)
  expect_true(out$institution_dist_m[1] < 100)
  expect_equal(out$institution_lon[1], ref$decimalLongitude)
  expect_equal(out$institution_lat[1], ref$decimalLatitude)
  expect_true(is.na(out$institution_name[2]))
  expect_true(is.na(out$institution_lon[2]))
  expect_true(is.na(out$institution_lat[2]))
})

test_that("flag_institution = FALSE skips institution flagging entirely", {
  skip_if_not_installed("CoordinateCleaner")
  ref <- CoordinateCleaner::institutions[!is.na(CoordinateCleaner::institutions$decimalLongitude) &
                                         !is.na(CoordinateCleaner::institutions$decimalLatitude), ][1, ]
  df <- data.frame(
    decimalLatitude  = c(ref$decimalLatitude, 34.5),
    decimalLongitude = c(ref$decimalLongitude, -120.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE, flag_institution = FALSE)
  expect_equal(nrow(out), 2L)
  expect_false("institution_flag" %in% names(out))
})

test_that("exclude_country_centroid/capital = FALSE skips those two checks", {
  skip_if_not_installed("CoordinateCleaner")
  ref <- CoordinateCleaner::countryref[CoordinateCleaner::countryref$type == "country", ]
  ref <- ref[!is.na(ref$centroid.lon) & !is.na(ref$centroid.lat), ][1, ]
  df <- data.frame(
    decimalLatitude  = c(ref$centroid.lat, 34.5),
    decimalLongitude = c(ref$centroid.lon, -120.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE, flag_institution = FALSE)
  expect_equal(nrow(out), 2L)
})

test_that("a record near both a removal-check trigger and an institution is removed, not flagged", {
  # Step 9 (removal) runs before step 10 (institution flagging) -- a record
  # that fails a removal check never reaches the institution step at all.
  skip_if_not_installed("CoordinateCleaner")
  df <- data.frame(
    decimalLatitude  = c(0.01, 34.5),
    decimalLongitude = c(0.01, -120.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE)
  expect_equal(nrow(out), 1L)
  removed <- attr(out, "removed_records")
  expect_equal(nrow(removed), 1L)
})

# =============================================================================
# removed_records attribute
# =============================================================================

test_that("removed_records is present with 0 rows when nothing is removed", {
  df <- data.frame(
    decimalLatitude  = c(34.5, 35.0),
    decimalLongitude = c(-120.0, -119.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE, flag_institution = FALSE)
  removed <- attr(out, "removed_records")
  expect_false(is.null(removed))
  expect_equal(nrow(removed), 0L)
  expect_true("filter_reason" %in% names(removed))
})

test_that("removed_records captures rows dropped for missing coordinates", {
  df <- data.frame(
    decimalLatitude  = c(34.5, NA),
    decimalLongitude = c(-120.0, -119.0),
    gbifID           = c("1", "2"),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE, flag_institution = FALSE)
  removed <- attr(out, "removed_records")
  expect_equal(nrow(removed), 1L)
  expect_equal(removed$gbifID, "2")
  expect_equal(removed$filter_reason, "missing_coordinates")
})

test_that("removed_records reports the specific matched GBIF issue code", {
  df <- data.frame(
    decimalLatitude  = c(34.5, 35.0),
    decimalLongitude = c(-120.0, -119.0),
    issues           = c(NA, "SOME_OTHER_CODE;COORDINATE_OUT_OF_RANGE"),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              max_coord_uncertainty = Inf,
                              bad_issues = c("COORDINATE_OUT_OF_RANGE", "ZERO_COORDINATE"),
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE, flag_institution = FALSE)
  removed <- attr(out, "removed_records")
  expect_equal(nrow(removed), 1L)
  expect_equal(removed$filter_reason, "flagged_issue_code:COORDINATE_OUT_OF_RANGE")
})

test_that("removed_records joins multiple simultaneous CoordinateCleaner reasons with ';'", {
  skip_if_not_installed("CoordinateCleaner")
  # (0.01, 0.01) is simultaneously an equal-coordinate record AND near (0,0)
  df <- data.frame(
    decimalLatitude  = c(0.01, 34.5),
    decimalLongitude = c(0.01, -120.0),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE, flag_institution = FALSE)
  removed <- attr(out, "removed_records")
  expect_equal(nrow(removed), 1L)
  reasons <- strsplit(removed$filter_reason, ";")[[1]]
  expect_setequal(reasons, c("equal_coordinates", "near_zero"))
})

test_that("removed_records preserves original columns (e.g. for reporting back to GBIF)", {
  df <- data.frame(
    decimalLatitude  = c(34.5, NA),
    decimalLongitude = c(-120.0, -119.0),
    gbifID           = c("1", "2"),
    datasetKey       = c("dsA", "dsB"),
    stringsAsFactors = FALSE
  )
  out <- filter_gbif_quality(df, basis_keep = character(0), exclude_edna = FALSE,
                              bad_issues = character(0), max_coord_uncertainty = Inf,
                              exclude_equal_coords = FALSE, exclude_near_zero = FALSE,
                              exclude_near_gbif_hq = FALSE, exclude_country_centroid = FALSE,
                              exclude_capital = FALSE, flag_institution = FALSE)
  removed <- attr(out, "removed_records")
  expect_true(all(c("gbifID", "datasetKey") %in% names(removed)))
  expect_equal(removed$datasetKey, "dsB")
})

# =============================================================================
# Output structure
# =============================================================================

test_that("original columns are preserved after filtering (institution columns added, not substituted)", {
  df  <- .make_gbif()
  out <- filter_gbif_quality(df)
  expect_true(all(names(df) %in% names(out)))
})

test_that("column structure is unchanged when flag_institution = FALSE", {
  df  <- .make_gbif()
  out <- filter_gbif_quality(df, flag_institution = FALSE)
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
