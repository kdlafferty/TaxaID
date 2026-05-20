# Tests for read_biotime_study()
# Run with devtools::test() from the TaxaFetch project root.

# ── shared helper ─────────────────────────────────────────────────────────────

#' Write a minimal BioTime per-study CSV to a temp file and return its path.
#' @param filename  Name for the temp file (used to test study_id inference).
#' @param include_zeros   Add one row with ABUNDANCE = 0 and BIOMAS = 0.
#' @param include_na_coords  Add one row with NA lat/lon.
#' @param omit_biomas  Write file without the BIOMAS column.
#' @param omit_sample_desc  Write file without the SAMPLE_DESC column.
#' @noRd
.bt_tmp <- function(filename         = "raw_data_595.csv",
                    include_zeros    = FALSE,
                    include_na_coords = FALSE,
                    omit_biomas      = FALSE,
                    omit_sample_desc = FALSE) {

  df <- data.frame(
    ABUNDANCE   = c(1, 2, 10, 4),
    BIOMAS      = c(NA, NA, 5.2, NA),
    valid_name  = c("Alloclinus holderi", "Gobiiformes sp",
                    "Alloclinus holderi", "Coryphopterus nicholsii"),
    SAMPLE_DESC = c("2008_11_5_SB-AP", "2008_11_6_SB-CAT",
                    "2004_9_30_SC-PB", "2003_8_7_SC-YB"),
    LATITUDE    = c(33.48, 33.46, 34.03, 33.98),
    LONGITUDE   = c(-119.02, -119.03, -119.70, -119.56),
    DAY         = c(5L, 6L, 30L, 7L),
    MONTH       = c(11L, 11L, 9L, 8L),
    YEAR        = c(2008L, 2008L, 2004L, 2003L),
    stringsAsFactors = FALSE
  )

  if (include_zeros) {
    zero_row            <- df[1L, ]
    zero_row$ABUNDANCE  <- 0
    zero_row$BIOMAS     <- 0
    df <- rbind(df, zero_row)
  }

  if (include_na_coords) {
    na_row           <- df[1L, ]
    na_row$LATITUDE  <- NA_real_
    na_row$LONGITUDE <- NA_real_
    df <- rbind(df, na_row)
  }

  if (omit_biomas)      df$BIOMAS      <- NULL
  if (omit_sample_desc) df$SAMPLE_DESC <- NULL

  tmp <- file.path(tempdir(), filename)
  utils::write.csv(df, tmp, row.names = FALSE)
  tmp
}


# ── input validation ──────────────────────────────────────────────────────────

test_that("read_biotime_study() errors when file not found", {
  expect_error(
    read_biotime_study("/no/such/file.csv"),
    regexp = "File not found"
  )
})

test_that("read_biotime_study() error message includes download instructions", {
  err <- tryCatch(
    read_biotime_study("/no/such/file.csv"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "biotime.st-andrews.ac.uk")
  expect_match(err, "Register")
  expect_match(err, "Download data")
})

test_that("read_biotime_study() rejects non-string local_path", {
  expect_error(read_biotime_study(123L),       regexp = "single character string")
  expect_error(read_biotime_study(c("a","b")), regexp = "single character string")
})

test_that("read_biotime_study() rejects bad verbose", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  expect_error(read_biotime_study(tmp, verbose = "yes"), regexp = "TRUE or FALSE")
  expect_error(read_biotime_study(tmp, verbose = NA),    regexp = "TRUE or FALSE")
})

test_that("read_biotime_study() errors when required columns are missing", {
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(data.frame(x = 1:3), tmp, row.names = FALSE)
  on.exit(unlink(tmp))
  expect_error(read_biotime_study(tmp, verbose = FALSE), regexp = "missing expected columns")
})

test_that("read_biotime_study() errors in non-interactive session when local_path is NULL", {
  # R CMD check always runs non-interactively
  expect_error(
    read_biotime_study(local_path = NULL),
    regexp = "not running interactively"
  )
})


# ── study_id inference ────────────────────────────────────────────────────────

test_that("read_biotime_study() infers study_id from standard filename", {
  tmp <- .bt_tmp(filename = "raw_data_595.csv")
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_true(all(result$datasetID == "biotime:595"))
})

test_that("read_biotime_study() uses explicit study_id over filename inference", {
  tmp <- .bt_tmp(filename = "raw_data_595.csv")
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, study_id = 999L, verbose = FALSE)
  expect_true(all(result$datasetID == "biotime:999"))
})

test_that("read_biotime_study() warns and uses 'unknown' when study_id cannot be inferred", {
  tmp <- .bt_tmp(filename = "mydata.csv")
  on.exit(unlink(tmp))
  expect_warning(
    result <- read_biotime_study(tmp, verbose = FALSE),
    regexp = "Could not infer study_id"
  )
  expect_true(all(result$datasetID == "biotime:unknown"))
})

test_that("read_biotime_study() accepts string study_id", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, study_id = "595", verbose = FALSE)
  expect_true(all(result$datasetID == "biotime:595"))
})


# ── DwC column contract ───────────────────────────────────────────────────────

test_that("read_biotime_study() returns expected DwC columns", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expected <- c("scientificName", "decimalLatitude", "decimalLongitude",
                "year", "month", "day",
                "occurrenceStatus", "organismQuantity", "organismQuantityType",
                "eventID", "datasetID", "basisOfRecord", "biotime_biomass")
  expect_true(all(expected %in% names(result)))
})

test_that("read_biotime_study() renames valid_name to scientificName", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_true("scientificName" %in% names(result))
  expect_false("valid_name" %in% names(result))
})

test_that("read_biotime_study() renames BIOMAS to biotime_biomass", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_true("biotime_biomass" %in% names(result))
  expect_false("BIOMAS" %in% names(result))
})

test_that("read_biotime_study() sets biotime_biomass to NA when BIOMAS column is absent", {
  tmp <- .bt_tmp(omit_biomas = TRUE)
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_true("biotime_biomass" %in% names(result))
  expect_true(all(is.na(result$biotime_biomass)))
})

test_that("read_biotime_study() renames SAMPLE_DESC to eventID", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_true("eventID" %in% names(result))
  expect_false("SAMPLE_DESC" %in% names(result))
})

test_that("read_biotime_study() works when SAMPLE_DESC column is absent", {
  tmp <- .bt_tmp(omit_sample_desc = TRUE)
  on.exit(unlink(tmp))
  expect_no_error(result <- read_biotime_study(tmp, verbose = FALSE))
  expect_false("eventID" %in% names(result))   # absent in source → not added
})


# ── type coercion ─────────────────────────────────────────────────────────────

test_that("read_biotime_study() coerces decimalLatitude and decimalLongitude to numeric", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_type(result$decimalLatitude,  "double")
  expect_type(result$decimalLongitude, "double")
})

test_that("read_biotime_study() coerces year, month, day to integer", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_type(result$year,  "integer")
  expect_type(result$month, "integer")
  expect_type(result$day,   "integer")
})

test_that("read_biotime_study() coerces organismQuantity to numeric", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_type(result$organismQuantity, "double")
})

test_that("read_biotime_study() coerces biotime_biomass to numeric", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_type(result$biotime_biomass, "double")
})


# ── derived columns ───────────────────────────────────────────────────────────

test_that("read_biotime_study() sets organismQuantityType to 'abundance'", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_true(all(result$organismQuantityType == "abundance"))
})

test_that("read_biotime_study() sets basisOfRecord to 'HumanObservation'", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_true(all(result$basisOfRecord == "HumanObservation"))
})

test_that("read_biotime_study() sets occurrenceStatus to 'present' when ABUNDANCE > 0", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  present <- result[!is.na(result$organismQuantity) & result$organismQuantity > 0, ]
  expect_true(all(present$occurrenceStatus == "present"))
})

test_that("read_biotime_study() sets occurrenceStatus to 'present' when BIOMAS > 0 even if ABUNDANCE is NA", {
  df <- data.frame(
    ABUNDANCE   = NA_real_,
    BIOMAS      = 3.5,
    valid_name  = "Gadus morhua",
    SAMPLE_DESC = "s1",
    LATITUDE    = 50.0,
    LONGITUDE   = -10.0,
    DAY = 1L, MONTH = 6L, YEAR = 2010L,
    stringsAsFactors = FALSE
  )
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(df, tmp, row.names = FALSE)
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, study_id = 1L, verbose = FALSE)
  expect_equal(result$occurrenceStatus, "present")
})

test_that("read_biotime_study() sets occurrenceStatus to 'absent' when ABUNDANCE == 0 and BIOMAS == 0", {
  tmp <- .bt_tmp(include_zeros = TRUE)
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  zero_rows <- result[!is.na(result$organismQuantity) &
                        result$organismQuantity == 0 &
                        !is.na(result$biotime_biomass) &
                        result$biotime_biomass == 0, ]
  if (nrow(zero_rows) > 0L) {
    expect_true(all(zero_rows$occurrenceStatus == "absent"))
  }
})


# ── coordinate handling ───────────────────────────────────────────────────────

test_that("read_biotime_study() drops rows with missing coordinates", {
  tmp <- .bt_tmp(include_na_coords = TRUE)
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_false(any(is.na(result$decimalLatitude)))
  expect_false(any(is.na(result$decimalLongitude)))
})


# ── return type ───────────────────────────────────────────────────────────────

test_that("read_biotime_study() returns a tibble", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result <- read_biotime_study(tmp, verbose = FALSE)
  expect_s3_class(result, "tbl_df")
})

test_that("read_biotime_study() output is compatible with stack_occurrences()", {
  tmp <- .bt_tmp()
  on.exit(unlink(tmp))
  result  <- read_biotime_study(tmp, verbose = FALSE)
  stacked <- stack_occurrences(result)
  expect_true("point_id" %in% names(stacked))
  expect_equal(nrow(stacked), nrow(result))
})
