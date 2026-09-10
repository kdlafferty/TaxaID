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

test_that("dominant pct survives an all-NA habitat column (2026-09-01 real crash)", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(0.9, 1.0),
    Freshwater = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
  sec <- report_habitat(df)
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_equal(sec$statistics$dominant_pct, 95)
  expect_true(grepl("mean weight 95%", sec$results, fixed = TRUE))
})

test_that("no crash when EVERY habitat column is entirely NA (2026-09-07 code review)", {
  df <- data.frame(
    scientificName = c("Sp A", "Sp B"),
    Marine = c(NA_real_, NA_real_),
    Freshwater = c(NA_real_, NA_real_),
    stringsAsFactors = FALSE
  )
  sec <- report_habitat(df)
  expect_null(sec$statistics$dominant_habitat)
  expect_null(sec$statistics$dominant_pct)
  expect_false(grepl("Dominant habitat", sec$results, fixed = TRUE))
})

test_that("occurrence-level habitat data is summarised from main_habitat, not coordinates (2026-09-07 bug)", {
  # Reproduces the real shape that produced "under the decimalLatitude/
  # decimalLongitude scheme" and "Dominant habitat: decimalLatitude (mean
  # weight 3519%)" in both a real 18S and a real GreatLakes generated report:
  # occurrence-level data (taxon_name, not scientificName; decimalLatitude/
  # decimalLongitude as the only other numeric columns) with a categorical
  # main_habitat winner per row, no numeric habitat-weight columns at all.
  df <- data.frame(
    taxon_name       = c("Sp A", "Sp A", "Sp B", "Sp C", "Sp C"),
    decimalLatitude  = c(34.1, 34.2, 35.0, 34.5, 34.6),
    decimalLongitude = c(-119.8, -119.7, -120.1, -119.9, -119.9),
    main_habitat     = c("Marine", "Marine", "Estuarine", "Marine", NA_character_),
    habitat_best_guess = c(NA_character_, NA_character_, NA_character_, NA_character_, "unclear"),
    stringsAsFactors = FALSE
  )

  sec <- report_habitat(df)
  # 3 unique taxa, not 5 raw rows.
  expect_equal(sec$statistics$n_taxa, 3L)
  # Real categories (Marine/Estuarine), never the coordinate column names.
  expect_equal(sec$statistics$n_habitat_cols, 2L)
  expect_equal(sec$params$habitat_scheme, "Marine/Estuarine")
  expect_false(grepl("decimalLat|decimalLon", sec$methods))
  # Dominant = most common category among ASSIGNED (non-NA) rows: Marine, 3/4.
  expect_equal(sec$statistics$dominant_habitat, "Marine")
  expect_equal(sec$statistics$dominant_pct, 75)
  expect_true(grepl("Marine \\(75% of assigned records\\)", sec$results))
})

test_that("main_habitat branch: n_habitat_cols and dominant_habitat are NULL/0 when every row is NA", {
  df <- data.frame(
    taxon_name   = c("Sp A", "Sp B"),
    main_habitat = c(NA_character_, NA_character_),
    stringsAsFactors = FALSE
  )
  sec <- report_habitat(df)
  expect_equal(sec$statistics$n_habitat_cols, 0L)
  expect_null(sec$statistics$dominant_habitat)
  expect_null(sec$params$habitat_scheme)
})
