# test-report_flags.R
# Tests for report_flags()

test_that("report_flags detects contaminant flags", {
  df <- data.frame(
    observation_id = paste0("S", 1:5),
    flag_lab = c("likely", "likely", "unlikely", "possible", "likely"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaFlag")
  expect_equal(sec$section, "flags")
  expect_true("contamination" %in% sec$params$flag_types)
  expect_equal(sec$statistics$n_total, 5L)
  expect_equal(sec$statistics$n_flagged, 2L)  # "unlikely" + "possible"
})

test_that("report_flags detects handler flags", {
  df <- data.frame(
    observation_id = paste0("S", 1:4),
    flag_handler = c("likely", "unlikely", "likely", "likely"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_true("handler artifacts" %in% sec$params$flag_types)
})

test_that("report_flags detects multiple flag types", {
  df <- data.frame(
    observation_id = paste0("S", 1:3),
    flag_lab = c("likely", "unlikely", "likely"),
    flag_handler = c("likely", "likely", "possible"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_equal(sec$statistics$flag_types_detected, 2L)
  expect_true("contamination" %in% sec$params$flag_types)
  expect_true("handler artifacts" %in% sec$params$flag_types)
})

test_that("report_flags reports zero flags correctly", {
  df <- data.frame(
    observation_id = paste0("S", 1:5),
    flag_lab = rep("likely", 5),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_equal(sec$statistics$n_flagged, 0L)
  expect_true(grepl("none were flagged", sec$results))
})

test_that("report_flags detects review columns", {
  df <- data.frame(
    observation_id = paste0("S", 1:3),
    review_confidence = c("high", "low", "medium"),
    review_comment = c("OK", "Suspect", "Fine"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_true("expert review" %in% sec$params$flag_types)
})

test_that("report_flags handles data with no flag columns", {
  df <- data.frame(
    observation_id = paste0("S", 1:3),
    taxon = c("A", "B", "C"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_equal(sec$statistics$flag_types_detected, 0L)
  expect_true(grepl("No quality flags", sec$methods))
})

test_that("report_flags errors on empty data", {
  expect_error(report_flags(data.frame()))
  expect_error(report_flags(NULL))
})

test_that("report_flags percentage is correct", {
  df <- data.frame(
    observation_id = paste0("S", 1:10),
    flag_field = c(rep("unlikely", 3), rep("likely", 7)),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  # 3 out of 10 = 30%
  expect_equal(sec$statistics$n_flagged, 3L)
  expect_true(grepl("30\\.0%", sec$results))
})
