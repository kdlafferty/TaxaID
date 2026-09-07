# tests/testthat/test-flag_institution_candidates.R
# Pure classification logic -- no network calls, no CoordinateCleaner
# dependency (this function only reads columns TaxaFetch::filter_gbif_quality()
# already computed, it doesn't call CoordinateCleaner itself).

.make_flagged <- function() {
  data.frame(
    species = c("Plant A", "Fish A", "Mammal A", "Bird A", "Fish B", "Fish C"),
    kingdom = c("Plantae", "Animalia", "Animalia", "Animalia", "Animalia", "Animalia"),
    institution_flag = c(TRUE, TRUE, TRUE, TRUE, TRUE, FALSE),
    institution_type = c("Herbarium", "Botanic_garden", "Zoo", "University", NA, NA),
    institution_name = c(
      "Some Herbarium", "UCLA Botanical Garden", "Some Zoo",
      "Some University", NA, NA
    ),
    institution_dist_m = c(5, 20, 15, 60, NA, NA),
    stringsAsFactors = FALSE
  )
}

test_that("stops if required columns are missing", {
  df <- .make_flagged()
  df$institution_flag <- NULL
  expect_error(flag_institution_candidates(df), regexp = "institution_flag")
})

test_that("stops if kingdom column is missing", {
  df <- .make_flagged()
  df$kingdom <- NULL
  expect_error(flag_institution_candidates(df), regexp = "kingdom")
})

test_that("non-flagged records get NA, never a real tier", {
  out <- flag_institution_candidates(.make_flagged())
  expect_true(is.na(out$institution_suspicion[out$species == "Fish C"]))
})

test_that("Herbarium + Plantae is high suspicion", {
  out <- flag_institution_candidates(.make_flagged())
  expect_equal(out$institution_suspicion[out$species == "Plant A"], "high")
})

test_that("Botanic_garden + Animalia is low suspicion (the motivating fish-in-a-garden-pond case)", {
  out <- flag_institution_candidates(.make_flagged())
  expect_equal(out$institution_suspicion[out$species == "Fish A"], "low")
})

test_that("Zoo + Animalia is high suspicion", {
  out <- flag_institution_candidates(.make_flagged())
  expect_equal(out$institution_suspicion[out$species == "Mammal A"], "high")
})

test_that("University (not in default rules) is ambiguous regardless of kingdom", {
  out <- flag_institution_candidates(.make_flagged())
  expect_equal(out$institution_suspicion[out$species == "Bird A"], "ambiguous")
})

test_that("no flagged records at all produces a message and an all-NA column", {
  df <- .make_flagged()
  df$institution_flag <- FALSE
  expect_message(out <- flag_institution_candidates(df), regexp = "no flagged records")
  expect_true(all(is.na(out$institution_suspicion)))
})

test_that("a flagged record with NA institution_type falls through to ambiguous, not NA", {
  # Regression test: real CoordinateCleaner::institutions matches can have a
  # NA type (e.g. some real Scripps Institution of Oceanography matches do).
  # suspicion_rules$institution_type == NA produces an all-NA logical index,
  # which subsets to NA rather than zero, without the is.na(t) guard.
  df <- data.frame(
    species = "Mystery fish",
    kingdom = "Animalia",
    institution_flag = TRUE,
    institution_type = NA_character_,
    institution_name = "Some Institution With No Recorded Type",
    institution_dist_m = 40,
    stringsAsFactors = FALSE
  )
  out <- flag_institution_candidates(df)
  expect_equal(out$institution_suspicion, "ambiguous")
  expect_false(is.na(out$institution_suspicion))
})

test_that("custom suspicion_rules override the defaults", {
  df <- .make_flagged()
  custom_rules <- data.frame(
    institution_type = "University",
    kingdom = NA,
    suspicion = "high",
    stringsAsFactors = FALSE
  )
  out <- flag_institution_candidates(df, suspicion_rules = custom_rules)
  expect_equal(out$institution_suspicion[out$species == "Bird A"], "high")
  # Herbarium is no longer in the (fully replaced) rules table -> falls back to ambiguous
  expect_equal(out$institution_suspicion[out$species == "Plant A"], "ambiguous")
})

test_that("row count and column set are otherwise unchanged", {
  df <- .make_flagged()
  out <- flag_institution_candidates(df)
  expect_equal(nrow(out), nrow(df))
  expect_true(all(names(df) %in% names(out)))
  expect_equal(setdiff(names(out), names(df)), "institution_suspicion")
})
