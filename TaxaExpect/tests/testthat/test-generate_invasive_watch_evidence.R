# test-generate_invasive_watch_evidence.R
# Tests for generate_invasive_watch_evidence(). Fully offline -- no live
# queries at all (unlike the earlier NAS-API-based design).

library(testthat)

# =============================================================================
# Input validation
# =============================================================================

test_that("stops on empty invasive_taxa", {
  expect_error(
    generate_invasive_watch_evidence(character(0), weight = 0.5, p_conc = 4),
    regexp = "invasive_taxa"
  )
})

test_that("stops when weight is out of [0,1]", {
  expect_error(
    generate_invasive_watch_evidence("Gymnocephalus cernua", weight = 1.2, p_conc = 4),
    regexp = "weight"
  )
})

test_that("stops when p_conc is non-positive", {
  expect_error(
    generate_invasive_watch_evidence("Gymnocephalus cernua", weight = 0.5, p_conc = -1),
    regexp = "p_conc"
  )
})

# =============================================================================
# Output shape
# =============================================================================

test_that("returns one row per taxon with the documented schema", {
  out <- generate_invasive_watch_evidence(
    c("Gymnocephalus cernua", "Neogobius melanostomus"), weight = 0.6, p_conc = 4
  )
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 2L)
  expect_named(out, c("taxon_name", "weight", "p_conc", "source"))
  expect_true(all(out$weight == 0.6))
  expect_true(all(out$p_conc == 4))
  expect_true(all(out$source == "invasive_watch"))
})

test_that("duplicate taxon names collapse to one row", {
  out <- generate_invasive_watch_evidence(
    c("Gymnocephalus cernua", "Gymnocephalus cernua"), weight = 0.5, p_conc = 4
  )
  expect_equal(nrow(out), 1L)
})

# =============================================================================
# match_list_taxa gating
# =============================================================================

test_that("match_list_taxa restricts output to the intersection", {
  out <- generate_invasive_watch_evidence(
    c("Gymnocephalus cernua", "Neogobius melanostomus"), weight = 0.5, p_conc = 4,
    match_list_taxa = "Gymnocephalus cernua"
  )
  expect_equal(out$taxon_name, "Gymnocephalus cernua")
})

test_that("no overlap with match_list_taxa returns an empty tibble with correct columns", {
  out <- generate_invasive_watch_evidence(
    "Gymnocephalus cernua", weight = 0.5, p_conc = 4,
    match_list_taxa = "Some other species"
  )
  expect_equal(nrow(out), 0L)
  expect_named(out, c("taxon_name", "weight", "p_conc", "source"))
})

test_that("NULL match_list_taxa (default) does not restrict", {
  out <- generate_invasive_watch_evidence(
    c("Gymnocephalus cernua", "Neogobius melanostomus"), weight = 0.5, p_conc = 4
  )
  expect_equal(nrow(out), 2L)
})

# =============================================================================
# Repeated calls for tiering (documented pattern, not built-in)
# =============================================================================

test_that("two calls with different weights can be bound into one evidence table", {
  strong <- generate_invasive_watch_evidence("Gymnocephalus cernua", weight = 0.8, p_conc = 6)
  weak   <- generate_invasive_watch_evidence("Alburnus alburnus",    weight = 0.2, p_conc = 2)
  combined <- dplyr::bind_rows(strong, weak)
  expect_equal(nrow(combined), 2L)
  expect_equal(combined$weight, c(0.8, 0.2))
})
