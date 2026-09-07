# Tests for dedupe_occurrences() -- split out of stack_occurrences() 2026-07-23
# so deduplication is its own explicit step, relevant with or without
# combining multiple sources.

test_that("dedupe_occurrences: requires a data frame", {
  expect_error(dedupe_occurrences(list(1, 2)), "must be a data frame")
})

test_that("dedupe_occurrences: duplicate gbifID rows are dropped, first kept", {
  df <- tibble::tibble(
    gbifID           = c("1", "2", "2", "3"),
    decimalLatitude  = c(34.40, 34.41, 34.41, 34.47),
    decimalLongitude = c(-120.41, -120.40, -120.40, -120.36)
  )
  expect_message(
    result <- dedupe_occurrences(df),
    "dropped 1 record"
  )
  expect_equal(nrow(result), 3L)
  expect_equal(sort(result$gbifID), c("1", "2", "3"))
})

test_that("dedupe_occurrences: NA gbifID rows are never deduped against each other", {
  df <- tibble::tibble(
    gbifID           = c(NA_character_, NA_character_, "5"),
    decimalLatitude  = c(34.0, 34.1, 34.2),
    decimalLongitude = c(-119.0, -119.1, -119.2)
  )
  result <- dedupe_occurrences(df)
  expect_equal(nrow(result), 3L)
})

test_that("dedupe_occurrences: no gbifID column -- that check is a silent no-op", {
  df <- tibble::tibble(
    occurrenceID     = c("A1", "A2"),
    decimalLatitude  = c(34.0, 34.1),
    decimalLongitude = c(-119.0, -119.1)
  )
  result <- dedupe_occurrences(df)
  expect_equal(nrow(result), 2L)
})

test_that("dedupe_occurrences: works directly on a single, unstacked source (the whole point of splitting it out of stack_occurrences)", {
  # e.g. one get_gbif_occurrences() call already containing duplicate
  # citizen-science reports of the same detection -- no stack_occurrences()
  # call involved at all.
  df <- tibble::tibble(
    occurrenceID     = c("ebird-1", "ebird-2"),
    scientificName   = c("Larus argentatus", "larus argentatus"),
    eventDate        = c("2026-06-01", "2026-06-01"),
    decimalLatitude  = c(34.4001, 34.4002),
    decimalLongitude = c(-119.8501, -119.8503)
  )
  expect_message(
    result <- dedupe_occurrences(df),
    "collapsed 1 record"
  )
  expect_equal(nrow(result), 1L)
  expect_equal(result$occurrenceID, "ebird-1")
})

test_that("dedupe_occurrences: collapses repeat reports of one detection occasion across combined sources", {
  df1 <- tibble::tibble(
    occurrenceID     = "ebird-1",
    scientificName   = "Larus argentatus",
    eventDate        = "2026-06-01",
    decimalLatitude  = 34.4001,
    decimalLongitude = -119.8501
  )
  df2 <- tibble::tibble(
    occurrenceID     = "ebird-2",
    scientificName   = "larus argentatus",  # case difference -- still matches
    eventDate        = "2026-06-01",
    decimalLatitude  = 34.4002,             # rounds to the same 3 d.p. cell
    decimalLongitude = -119.8503
  )
  combined <- stack_occurrences(df1, df2)
  expect_message(
    result <- dedupe_occurrences(combined),
    "collapsed 1 record"
  )
  expect_equal(nrow(result), 1L)
  expect_equal(result$occurrenceID, "ebird-1")
})

test_that("dedupe_occurrences: distinct dates/species/locations are never collapsed", {
  df <- tibble::tibble(
    occurrenceID     = c("A1", "A2", "A3"),
    scientificName   = c("Larus argentatus", "Larus argentatus", "Buteo jamaicensis"),
    eventDate        = c("2026-06-01", "2026-06-02", "2026-06-01"),
    decimalLatitude  = c(34.400, 34.400, 34.400),
    decimalLongitude = c(-119.850, -119.850, -119.850)
  )
  result <- dedupe_occurrences(df, collapse_duplicate_occasions = TRUE)
  expect_equal(nrow(result), 3L)
})

test_that("dedupe_occurrences: rows missing a key component are always kept", {
  df <- tibble::tibble(
    occurrenceID     = c("A1", "A2"),
    scientificName   = c("Larus argentatus", "Larus argentatus"),
    eventDate        = c("2026-06-01", NA_character_),  # A2 has no date
    decimalLatitude  = c(34.400, 34.400),
    decimalLongitude = c(-119.850, -119.850)
  )
  result <- dedupe_occurrences(df)
  expect_equal(nrow(result), 2L)
})

test_that("dedupe_occurrences: falls back to year/month/day when eventDate is absent (GBIF standard columns)", {
  df <- tibble::tibble(
    occurrenceID     = c("gbif-1", "gbif-2"),
    scientificName   = c("Larus argentatus", "Larus argentatus"),
    year = c(2026, 2026), month = c(6, 6), day = c(1, 1),
    decimalLatitude  = c(34.400, 34.400),
    decimalLongitude = c(-119.850, -119.850)
  )
  expect_message(
    result <- dedupe_occurrences(df),
    "collapsed 1 record"
  )
  expect_equal(nrow(result), 1L)
})

test_that("dedupe_occurrences: an incomplete year/month/day triple is never collapsed", {
  # Regression: sprintf() renders NA as the literal text "NA", so an unknown
  # day used to build a complete-LOOKING key ("2026-06-NA") that passed the
  # key-completeness test -- collapsing two genuinely separate reports whose
  # date is only known to the month, exactly the drop-on-incomplete-information
  # this function documents it never does.
  df <- tibble::tibble(
    occurrenceID     = c("gbif-1", "gbif-2"),
    scientificName   = c("Larus argentatus", "Larus argentatus"),
    year = c(2026, 2026), month = c(6, 6), day = c(NA, NA),
    decimalLatitude  = c(34.400, 34.400),
    decimalLongitude = c(-119.850, -119.850)
  )
  result <- dedupe_occurrences(df)
  expect_equal(nrow(result), 2L)

  # Same, with the whole triple missing.
  df$year  <- c(NA, NA)
  df$month <- c(NA, NA)
  expect_equal(nrow(dedupe_occurrences(df)), 2L)
})

test_that("dedupe_occurrences: collapse_duplicate_occasions = FALSE preserves every raw report", {
  df <- tibble::tibble(
    occurrenceID     = c("ebird-1", "ebird-2"),
    scientificName   = c("Larus argentatus", "Larus argentatus"),
    eventDate        = c("2026-06-01", "2026-06-01"),
    decimalLatitude  = c(34.400, 34.400),
    decimalLongitude = c(-119.850, -119.850)
  )
  result <- dedupe_occurrences(df, collapse_duplicate_occasions = FALSE)
  expect_equal(nrow(result), 2L)
})

test_that("dedupe_occurrences: missing taxon_col/date_col is a silent no-op (no rows dropped)", {
  df <- tibble::tibble(
    occurrenceID     = c("A1", "A2"),
    decimalLatitude  = c(34.400, 34.400),
    decimalLongitude = c(-119.850, -119.850)
  )
  result <- dedupe_occurrences(df)
  expect_equal(nrow(result), 2L)
})

test_that("dedupe_occurrences: custom taxon_col/date_col are respected", {
  df <- tibble::tibble(
    occurrenceID     = c("A1", "A2"),
    species          = c("Larus argentatus", "Larus argentatus"),
    obs_date         = c("2026-06-01", "2026-06-01"),
    decimalLatitude  = c(34.400, 34.400),
    decimalLongitude = c(-119.850, -119.850)
  )
  result <- dedupe_occurrences(df, taxon_col = "species", date_col = "obs_date")
  expect_equal(nrow(result), 1L)
})

test_that("dedupe_occurrences: custom lat_col/lon_col are respected", {
  df <- tibble::tibble(
    occurrenceID   = c("A1", "A2"),
    scientificName = c("Larus argentatus", "Larus argentatus"),
    eventDate      = c("2026-06-01", "2026-06-01"),
    lat            = c(34.400, 34.400),
    lon            = c(-119.850, -119.850)
  )
  result <- dedupe_occurrences(df, lat_col = "lat", lon_col = "lon")
  expect_equal(nrow(result), 1L)
})

test_that("dedupe_occurrences: refreshes report_params attribute when present", {
  df <- tibble::tibble(
    occurrenceID     = c("ebird-1", "ebird-2"),
    scientificName   = c("Larus argentatus", "Larus argentatus"),
    eventDate        = c("2026-06-01", "2026-06-01"),
    decimalLatitude  = c(34.400, 34.400),
    decimalLongitude = c(-119.850, -119.850)
  )
  attr(df, "report_params") <- list(n_records = 2L, n_sources = 1L)

  result <- dedupe_occurrences(df)
  rp <- attr(result, "report_params")
  expect_equal(rp$n_records, 1L)
  expect_equal(rp$n_duplicates_removed, 1L)
})

test_that("dedupe_occurrences: no report_params attribute -- output has none either", {
  df <- tibble::tibble(
    occurrenceID     = "A1",
    decimalLatitude  = 34.0,
    decimalLongitude = -119.0
  )
  result <- dedupe_occurrences(df)
  expect_null(attr(result, "report_params"))
})

test_that("dedupe_occurrences: returns a tibble", {
  df <- tibble::tibble(
    occurrenceID     = "A1",
    decimalLatitude  = 34.0,
    decimalLongitude = -119.0
  )
  result <- dedupe_occurrences(df)
  expect_s3_class(result, "tbl_df")
})
