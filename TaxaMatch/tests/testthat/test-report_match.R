# test-report_match.R
# Tests for report_match()

test_that("report_match returns report_section with score stats", {
  df <- data.frame(
    observation_id = rep(paste0("S", 1:5), each = 2),
    score = c(99, 95, 98, 93, 100, 97, 96, 92, 99, 94),
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
    score = c(99, 95, 100, 90),
    stringsAsFactors = FALSE
  )

  sec <- report_match(df)
  # Top scores are 99, 100 -> median = 99.5
  expect_equal(sec$statistics$median_top_score, 99.5)
})

test_that("report_match detects eDNA data type from columns", {
  df <- data.frame(
    observation_id = "S1",
    score = 99,
    accession = "NC_123456",
    stringsAsFactors = FALSE
  )

  sec <- report_match(df, data_type = NULL)
  expect_true(grepl("Environmental DNA", sec$methods))
})

test_that("report_match uses explicit data_type", {
  df <- data.frame(observation_id = "S1", score = 99, stringsAsFactors = FALSE)

  sec <- report_match(df, data_type = "image")
  expect_true(grepl("image detections", sec$methods))
})

test_that("report_match detects marker from testid", {
  df <- data.frame(
    observation_id = c("S1", "S2"),
    score = c(99, 98),
    testid = c("MiFishU", "MiFishU"),
    stringsAsFactors = FALSE
  )

  sec <- report_match(df)
  expect_true(grepl("MiFishU", sec$methods))
  expect_equal(sec$params$marker, "MiFishU")
})

test_that("report_match reads report_params attribute", {
  df <- data.frame(observation_id = "S1", score = 99, stringsAsFactors = FALSE)
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
  df <- data.frame(observation_id = c("S1", "S2"), taxon_name = c("A", "B"),
                   stringsAsFactors = FALSE)

  sec <- report_match(df)
  expect_s3_class(sec, "report_section")
  expect_null(sec$statistics$median_top_score)
})
