# test-report_match.R
# Tests for report_match()

test_that("report_match returns report_section with score stats", {
  df <- data.frame(
    observation_id = rep(paste0("S", 1:5), each = 2),
    score_original = c(99, 95, 98, 93, 100, 97, 96, 92, 99, 94),
    taxon_name = rep(c("Sp A", "Sp B"), 5),
    stringsAsFactors = FALSE
  )

  sec <- report_match(df)
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaMatch")
  expect_equal(sec$section, "match")
  expect_equal(sec$statistics$n_samples, 5L)
  expect_equal(sec$statistics$n_taxa, 2L)
  expect_false(is.null(sec$statistics$median_top_score))
})

test_that("report_match computes top score per sample", {
  df <- data.frame(
    observation_id = c("S1", "S1", "S2", "S2"),
    score_original = c(99, 95, 100, 90),
    stringsAsFactors = FALSE
  )

  sec <- report_match(df)
  # Top scores are 99, 100 -> median = 99.5
  expect_equal(sec$statistics$median_top_score, 99.5)
})

test_that("report_match detects eDNA data type from columns", {
  df <- data.frame(
    observation_id = "S1",
    score_original = 99,
    accession = "NC_123456",
    stringsAsFactors = FALSE
  )

  sec <- report_match(df, data_type = NULL)
  expect_true(grepl("Environmental DNA", sec$methods))
})

test_that("report_match uses explicit data_type", {
  df <- data.frame(observation_id = "S1", score_original = 99, stringsAsFactors = FALSE)

  sec <- report_match(df, data_type = "image")
  expect_true(grepl("image detections", sec$methods))
})

test_that("report_match detects marker from testid", {
  df <- data.frame(
    observation_id = c("S1", "S2"),
    score_original = c(99, 98),
    testid = c("MiFishU", "MiFishU"),
    stringsAsFactors = FALSE
  )

  sec <- report_match(df)
  expect_true(grepl("MiFishU", sec$methods))
  expect_equal(sec$params$marker, "MiFishU")
})

test_that("report_match reads report_params attribute", {
  df <- data.frame(observation_id = "S1", score_original = 99, stringsAsFactors = FALSE)
  attr(df, "report_params") <- list(
    method = "local BLAST", database = "custom_db", min_score = 95
  )

  sec <- report_match(df)
  expect_true(grepl("local BLAST", sec$methods))
  expect_true(grepl("custom_db", sec$methods))
  expect_true(grepl("95%", sec$methods))
})

test_that("report_match errors on empty input", {
  expect_error(report_match(data.frame()))
  expect_error(report_match(NULL))
})

test_that("report_match handles missing score column gracefully", {
  df <- data.frame(
    observation_id = c("S1", "S2"), taxon_name = c("A", "B"),
    stringsAsFactors = FALSE
  )

  sec <- report_match(df)
  expect_s3_class(sec, "report_section")
  expect_null(sec$statistics$median_top_score)
})

# ==============================================================================
# Search provenance and an unrecorded method
# ==============================================================================

test_that("report_match does not claim BLAST for a match object that records no method", {
  # An imported hit list (vsearch, a classifier export) carries no
  # report_params. Naming BLAST here would put a tool into a published methods
  # section on no evidence -- and, below, cite a paper for a search that may
  # have no connection to it.
  df <- data.frame(observation_id = "S1", score_original = 99, stringsAsFactors = FALSE)
  expect_null(attr(df, "report_params"))

  sec <- report_match(df)
  expect_false(grepl("BLAST", sec$methods, fixed = TRUE))
  expect_true(grepl("not recorded", sec$methods, fixed = TRUE))
  expect_true(grepl("not recorded", sec$params$method, fixed = TRUE))
})

test_that("report_match omits the BLAST citation when no method is recorded", {
  df <- data.frame(observation_id = "S1", score_original = 99, stringsAsFactors = FALSE)
  sec <- report_match(df)
  expect_false(any(grepl("BLAST", unlist(sec$citations), fixed = TRUE)))
})

test_that("report_match still cites BLAST when the match object records it", {
  df <- data.frame(observation_id = "S1", score_original = 99, stringsAsFactors = FALSE)
  attr(df, "report_params") <- list(method = "local BLAST", database = "nt")
  sec <- report_match(df)
  expect_true(any(grepl("BLAST", unlist(sec$citations), fixed = TRUE)))
})

test_that("report_match prints every provenance field the match object records", {
  df <- data.frame(observation_id = "S1", score_original = 99, stringsAsFactors = FALSE)
  attr(df, "report_params") <- list(
    method = "local BLAST", database = "core_nt", min_score = 90,
    blast_version = "2.14.0+",
    db_build_dates = "Jan 5, 2026",
    search_started = as.POSIXct("2026-10-29 09:00:00", tz = "UTC"),
    search_finished = as.POSIXct("2026-10-29 09:10:00", tz = "UTC")
  )

  sec <- report_match(df)
  expect_true(grepl("2.14.0+", sec$methods, fixed = TRUE))
  expect_true(grepl("Jan 5, 2026", sec$methods, fixed = TRUE))
  expect_true(grepl("2026-10-29", sec$methods, fixed = TRUE))
})

test_that("report_match prints no provenance sentence for an NA field", {
  # NA means "this search could not record it". Printing "NA" into a methods
  # section would be worse than the gap it fills.
  df <- data.frame(observation_id = "S1", score_original = 99, stringsAsFactors = FALSE)
  attr(df, "report_params") <- list(
    method = "local BLAST", database = "core_nt",
    blast_version = NA_character_,
    db_build_dates = NA_character_,
    search_started = as.POSIXct(NA),
    search_finished = as.POSIXct(NA)
  )

  sec <- report_match(df)
  expect_false(grepl("NA", sec$methods, fixed = TRUE))
  expect_false(grepl("Search tool version", sec$methods, fixed = TRUE))
  expect_false(grepl("Search run", sec$methods, fixed = TRUE))
})

test_that("report_match reports the remote database the server named", {
  df <- data.frame(observation_id = "S1", score_original = 99, stringsAsFactors = FALSE)
  attr(df, "report_params") <- list(
    method = "remote BLAST", database = "nt",
    database_reported = "nt v5 2026-10-01"
  )
  sec <- report_match(df)
  expect_true(grepl("nt v5 2026-10-01", sec$methods, fixed = TRUE))
})
