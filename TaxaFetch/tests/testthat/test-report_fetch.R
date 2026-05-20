# test-report_fetch.R
# Tests for report_fetch()

test_that("report_fetch returns report_section with basic data", {
  occ <- data.frame(
    scientificName = c("Species A", "Species B", "Species A"),
    decimalLatitude = c(34.0, 34.1, 34.2),
    decimalLongitude = c(-119.0, -119.1, -119.2),
    stringsAsFactors = FALSE
  )

  sec <- report_fetch(occ)
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaFetch")
  expect_equal(sec$section, "fetch")
  expect_equal(sec$statistics$n_records, 3L)
  expect_equal(sec$statistics$n_taxa, 2L)
})

test_that("report_fetch extracts citations from bibliographicCitation", {
  occ <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    decimalLatitude = c(34, 35),
    decimalLongitude = c(-119, -120),
    bibliographicCitation = c("GBIF Download", "BioTIME Study"),
    stringsAsFactors = FALSE
  )

  sec <- report_fetch(occ)
  expect_equal(length(sec$citations), 2)
  expect_true("GBIF Download" %in% sec$citations)
  expect_true("BioTIME Study" %in% sec$citations)
})

test_that("report_fetch detects sources from datasetID prefix", {
  occ <- data.frame(
    scientificName = c("Sp A", "Sp B", "Sp C"),
    decimalLatitude = c(34, 34.1, 34.2),
    decimalLongitude = c(-119, -119.1, -119.2),
    datasetID = c("gbif:12345", "biotime:42", "doi:10.123/abc"),
    stringsAsFactors = FALSE
  )

  sec <- report_fetch(occ)
  expect_true(grepl("GBIF", sec$methods))
  expect_true(grepl("BioTime", sec$methods))
  expect_true(grepl("DataONE", sec$methods))
})

test_that("report_fetch includes study_area in methods", {
  occ <- data.frame(
    scientificName = "Sp A",
    decimalLatitude = 34,
    decimalLongitude = -119,
    stringsAsFactors = FALSE
  )

  sec <- report_fetch(occ, study_area = "Santa Barbara Channel")
  expect_true(grepl("Santa Barbara Channel", sec$methods))
})

test_that("report_fetch includes year range when available", {
  occ <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    decimalLatitude = c(34, 35),
    decimalLongitude = c(-119, -120),
    year = c(2010, 2022),
    stringsAsFactors = FALSE
  )

  sec <- report_fetch(occ)
  expect_true(grepl("2010-2022", sec$methods))
  expect_equal(sec$params$year_range, "2010-2022")
})

test_that("report_fetch includes bbox when no study_area", {
  occ <- data.frame(
    scientificName = "Sp A",
    decimalLatitude = c(33.5, 35.0),
    decimalLongitude = c(-120.0, -118.5),
    stringsAsFactors = FALSE
  )

  sec <- report_fetch(occ)
  expect_true(grepl("lat \\[33\\.50, 35\\.00\\]", sec$methods))
  expect_false(is.null(sec$params$bbox))
})

test_that("report_fetch errors on empty or non-df input", {
  expect_error(report_fetch(data.frame()))
  expect_error(report_fetch(NULL))
  expect_error(report_fetch("not a df"))
})

test_that("report_fetch reads report_params attribute", {
  occ <- data.frame(
    scientificName = "Sp A",
    decimalLatitude = 34,
    decimalLongitude = -119,
    stringsAsFactors = FALSE
  )
  attr(occ, "report_params") <- list(custom_param = "value")

  sec <- report_fetch(occ)
  expect_equal(sec$params$custom_param, "value")
})
