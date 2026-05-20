# tests/testthat/test-consensus_habitat.R

test_that("consensus_habitat returns correct main_habitat for clear majority", {
  hab <- data.frame(
    taxon_name     = c("Species A", "Species B", "Species C"),
    Marine         = c(1.0, 0.8, 0.9),
    Freshwater     = c(0.0, 0.2, 0.0),
    Terrestrial    = c(0.0, 0.0, 0.1),
    Other_weight   = c(0.0, 0.0, 0.0),
    habitat_best_guess = c("", "", ""),
    stringsAsFactors = FALSE
  )
  result <- consensus_habitat(hab)
  expect_equal(result$main_habitat, "Marine")
  expect_true(is.na(result$ecoregion))
  expect_true(is.na(result$habitat_best_guess))
})

test_that("consensus_habitat returns NA when no habitat meets threshold", {
  hab <- data.frame(
    taxon_name     = c("Sp A", "Sp B", "Sp C", "Sp D"),
    Marine         = c(0.25, 0.25, 0.25, 0.25),
    Freshwater     = c(0.25, 0.25, 0.25, 0.25),
    Terrestrial    = c(0.25, 0.25, 0.25, 0.25),
    Other_weight   = c(0.25, 0.25, 0.25, 0.25),
    habitat_best_guess = c("", "", "", ""),
    stringsAsFactors = FALSE
  )
  result <- consensus_habitat(hab, threshold = 0.5)
  expect_true(is.na(result$main_habitat))
})

test_that("consensus_habitat extracts modal ecoregion_best_guess", {
  hab <- data.frame(
    taxon_name            = c("Sp A", "Sp B", "Sp C"),
    Marine                = c(1.0, 1.0, 1.0),
    Other_weight          = c(0.0, 0.0, 0.0),
    habitat_best_guess    = c("", "", ""),
    ecoregion_best_guess  = c("Southern California Bight",
                               "Southern California Bight",
                               "Central California"),
    stringsAsFactors = FALSE
  )
  result <- consensus_habitat(hab)
  expect_equal(result$ecoregion, "Southern California Bight")
})

test_that("consensus_habitat works without ecoregion_best_guess column", {
  hab <- data.frame(
    taxon_name     = c("Sp A", "Sp B"),
    Marine         = c(0.8, 0.7),
    Freshwater     = c(0.2, 0.3),
    Other_weight   = c(0.0, 0.0),
    habitat_best_guess = c("", ""),
    stringsAsFactors = FALSE
  )
  result <- consensus_habitat(hab)
  expect_true(is.na(result$ecoregion))
  expect_equal(result$main_habitat, "Marine")
})

test_that("consensus_habitat attaches habitat_proportions attribute", {
  hab <- data.frame(
    taxon_name     = c("Sp A", "Sp B"),
    Marine         = c(1.0, 0.0),
    Freshwater     = c(0.0, 1.0),
    Other_weight   = c(0.0, 0.0),
    habitat_best_guess = c("", ""),
    stringsAsFactors = FALSE
  )
  result <- consensus_habitat(hab)
  props <- attr(result, "habitat_proportions")
  expect_true(!is.null(props))
  expect_equal(sum(props), 1.0)
})

test_that("consensus_habitat populates habitat_best_guess when Other wins", {
  hab <- data.frame(
    taxon_name     = c("Sp A", "Sp B"),
    Marine         = c(0.0, 0.0),
    Other_weight   = c(1.0, 1.0),
    habitat_best_guess = c("deep-sea vent", "hydrothermal"),
    stringsAsFactors = FALSE
  )
  result <- consensus_habitat(hab)
  expect_equal(result$main_habitat, "Other")
  expect_true(grepl("deep-sea vent", result$habitat_best_guess))
  expect_true(grepl("hydrothermal", result$habitat_best_guess))
})

test_that("consensus_habitat de-duplicates taxa", {
  hab <- data.frame(
    taxon_name     = c("Sp A", "Sp A", "Sp B"),
    Marine         = c(1.0, 1.0, 0.0),
    Freshwater     = c(0.0, 0.0, 1.0),
    Other_weight   = c(0.0, 0.0, 0.0),
    habitat_best_guess = c("", "", ""),
    stringsAsFactors = FALSE
  )
  result <- consensus_habitat(hab)
  # With de-dup: Marine=1.0, Freshwater=1.0 -> 50/50
  # threshold 0.3 -> whichever is first alphabetically in max.col
  props <- attr(result, "habitat_proportions")
  expect_equal(unname(props["Marine"]), 0.5)
  expect_equal(unname(props["Freshwater"]), 0.5)
})
