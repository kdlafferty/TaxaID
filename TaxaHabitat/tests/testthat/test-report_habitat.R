# test-report_habitat.R
# Tests for report_habitat()

test_that("report_habitat returns valid report_section", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B", "Sp C"),
    Marine = c(0.9, 0.8, 1.0),
    Freshwater = c(0.1, 0.2, 0.0),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaHabitat")
  expect_equal(sec$section, "habitat")
  expect_equal(sec$statistics$n_taxa, 3L)
})

test_that("report_habitat detects 3-category scheme", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(0.9, 1.0),
    Freshwater = c(0.1, 0.0),
    Terrestrial = c(0.0, 0.0),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_equal(sec$params$habitat_scheme, "3-category")
  expect_true(grepl("3-category", sec$methods))
})

test_that("report_habitat identifies dominant habitat", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(0.9, 1.0),
    Freshwater = c(0.1, 0.0),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_true(grepl("Marine", sec$results))
})

test_that("report_habitat respects custom taxon_col", {
  df <- data.frame(
    taxon_name = c("Sp A", "Sp B", "Sp C"),
    Marine = c(0.9, 0.8, 1.0),
    Freshwater = c(0.1, 0.2, 0.0),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df, taxon_col = "taxon_name")
  expect_equal(sec$statistics$n_taxa, 3L)
})

test_that("report_habitat excludes known non-habitat columns", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(0.9, 1.0),
    Freshwater = c(0.1, 0.0),
    habitat_best_guess = c("Marine", "Marine"),
    main_habitat = c("Marine", "Marine"),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  # Should only have 2 habitat columns (Marine, Freshwater), not 4
  expect_equal(sec$statistics$n_habitat_cols, 2L)
})

test_that("report_habitat reads report_params attribute", {
  df <- data.frame(
    scientificName = "Sp A",
    Marine = 1.0,
    stringsAsFactors = FALSE
  )
  attr(df, "report_params") <- list(geographic_context = "tropical Pacific")

  sec <- report_habitat(df)
  expect_equal(sec$params$geographic_context, "tropical Pacific")
})

test_that("report_habitat errors on empty data", {
  expect_error(report_habitat(data.frame()))
  expect_error(report_habitat(NULL))
})
