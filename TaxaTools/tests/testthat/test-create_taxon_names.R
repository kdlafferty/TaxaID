# tests/testthat/test-create_taxon_names.R
#
# Tests for create_taxon_names()
# All tests are offline -- no API calls.

# ==============================================================================
# Input validation
# ==============================================================================

test_that("rejects non-data-frame input", {
  expect_error(
    create_taxon_names(list(kingdom = "Animalia"), "kingdom"),
    "`input_df` must be a data frame"
  )
  expect_error(
    create_taxon_names("not a df", "kingdom"),
    "`input_df` must be a data frame"
  )
})

test_that("rejects empty rank_system", {
  df <- data.frame(kingdom = "Animalia")
  expect_error(
    create_taxon_names(df, character(0)),
    "`rank_system` must be a non-empty character vector"
  )
})

test_that("rejects non-character rank_system", {
  df <- data.frame(kingdom = "Animalia")
  expect_error(
    create_taxon_names(df, 1:3),
    "`rank_system` must be a non-empty character vector"
  )
})

test_that("stops when a rank column is missing from df", {
  df <- data.frame(kingdom = "Animalia")
  expect_error(
    create_taxon_names(df, c("kingdom", "phylum")),
    "Column\\(s\\) not found"
  )
})

# ==============================================================================
# Basic resolution -- most specific wins
# ==============================================================================

test_that("returns species when all ranks present", {
  df <- data.frame(kingdom = "Animalia", genus = "Homo", species = "Homo sapiens")
  out <- create_taxon_names(df, c("kingdom", "genus", "species"))
  expect_equal(out$taxon_name, "Homo sapiens")
  expect_equal(out$taxon_name_rank, "species")
})

test_that("falls back to genus when species is NA", {
  df <- data.frame(kingdom = "Animalia", genus = "Homo", species = NA_character_)
  out <- create_taxon_names(df, c("kingdom", "genus", "species"))
  expect_equal(out$taxon_name, "Homo")
  expect_equal(out$taxon_name_rank, "genus")
})

test_that("falls back to kingdom when all finer ranks are NA", {
  df <- data.frame(kingdom = "Animalia", genus = NA_character_, species = NA_character_)
  out <- create_taxon_names(df, c("kingdom", "genus", "species"))
  expect_equal(out$taxon_name, "Animalia")
  expect_equal(out$taxon_name_rank, "kingdom")
})

test_that("returns NA when all ranks are NA", {
  df <- data.frame(kingdom = NA_character_, genus = NA_character_)
  out <- create_taxon_names(df, c("kingdom", "genus"))
  expect_true(is.na(out$taxon_name))
  expect_true(is.na(out$taxon_name_rank))
})

# ==============================================================================
# Empty string treated as NA
# ==============================================================================

test_that("treats empty string as NA and falls back", {
  df <- data.frame(genus = "Homo", species = "")
  out <- create_taxon_names(df, c("genus", "species"))
  expect_equal(out$taxon_name, "Homo")
  expect_equal(out$taxon_name_rank, "genus")
})

# ==============================================================================
# Case-insensitive column matching
# ==============================================================================

test_that("matches rank columns case-insensitively", {
  df <- data.frame(Kingdom = "Animalia", Genus = "Homo", Species = "Homo sapiens")
  # rank_system supplied in lowercase -- should still match
  out <- create_taxon_names(df, c("kingdom", "genus", "species"))
  expect_equal(out$taxon_name, "Homo sapiens")
  expect_equal(out$taxon_name_rank, "species")
})

test_that("rank label in output is always lowercase", {
  df <- data.frame(Kingdom = "Animalia", Genus = NA_character_)
  out <- create_taxon_names(df, c("kingdom", "genus"))
  expect_equal(out$taxon_name_rank, "kingdom")
})

# ==============================================================================
# Multi-row data frames
# ==============================================================================

test_that("resolves correctly across multiple rows", {
  df <- data.frame(
    genus   = c("Homo", "Canis", NA),
    species = c("Homo sapiens", NA, NA)
  )
  out <- create_taxon_names(df, c("genus", "species"))

  expect_equal(out$taxon_name, c("Homo sapiens", "Canis", NA))
  expect_equal(out$taxon_name_rank, c("species", "genus", NA))
})

# ==============================================================================
# Output structure
# ==============================================================================

test_that("appends taxon_name and taxon_name_rank without dropping other columns", {
  df <- data.frame(
    id = 1:2, genus = c("Homo", "Canis"),
    species = c("Homo sapiens", NA)
  )
  out <- create_taxon_names(df, c("genus", "species"))

  expect_true("id" %in% names(out))
  expect_true("genus" %in% names(out))
  expect_true("species" %in% names(out))
  expect_true("taxon_name" %in% names(out))
  expect_true("taxon_name_rank" %in% names(out))
})

test_that("returns a data frame", {
  df <- data.frame(genus = "Homo", species = "Homo sapiens")
  out <- create_taxon_names(df, c("genus", "species"))
  expect_s3_class(out, "data.frame")
})

test_that("row count is unchanged", {
  df <- data.frame(genus = c("Homo", "Canis", "Felis"))
  out <- create_taxon_names(df, "genus")
  expect_equal(nrow(out), 3L)
})

# ==============================================================================
# Full Linnaean rank vector
# ==============================================================================

test_that("works with a full seven-rank vector", {
  df <- data.frame(
    kingdom = "Animalia",
    phylum  = "Chordata",
    class   = "Mammalia",
    order   = "Primates",
    family  = "Hominidae",
    genus   = "Homo",
    species = "Homo sapiens"
  )
  ranks <- c("kingdom", "phylum", "class", "order", "family", "genus", "species")
  out <- create_taxon_names(df, ranks)
  expect_equal(out$taxon_name, "Homo sapiens")
  expect_equal(out$taxon_name_rank, "species")
})

# ---- a blank rank value is absent, not a name -------------------------------
# `na_if(x, "")` matched "" exactly, so a whitespace-only cell survived as a
# value and the most-specific-wins walk reported it as the finest present rank.
# Whitespace in a spreadsheet cell is invisible; this project has already lost
# real rows to a trailing space in a join key.

test_that("a whitespace-only rank value is treated as absent", {
  d <- data.frame(
    family = rep("Gobiidae", 3L),
    genus = c("Gobius", "", "   "),
    species = c("Gobius niger", "", ""),
    stringsAsFactors = FALSE
  )
  out <- create_taxon_names(d, c("family", "genus", "species"))
  expect_equal(out$taxon_name, c("Gobius niger", "Gobiidae", "Gobiidae"))
  expect_equal(out$taxon_name_rank, c("species", "family", "family"))
})

test_that("a tab- or newline-only rank value is also absent", {
  d <- data.frame(
    family = rep("Gobiidae", 2L), genus = c("\t", "\n"),
    species = c(NA_character_, NA_character_), stringsAsFactors = FALSE
  )
  out <- create_taxon_names(d, c("family", "genus", "species"))
  expect_equal(out$taxon_name_rank, c("family", "family"))
})

test_that("a non-blank rank value is left exactly as supplied, padding included", {
  # Deliberately NOT trimmed: trimming a real value would change taxon_name
  # and every join keyed on it. Only BLANK values are rewritten.
  d <- data.frame(
    family = "Gobiidae", genus = " Gobius ", species = NA_character_,
    stringsAsFactors = FALSE
  )
  out <- create_taxon_names(d, c("family", "genus", "species"))
  expect_equal(out$taxon_name, " Gobius ")
  expect_equal(out$taxon_name_rank, "genus")
  expect_equal(out$genus, " Gobius ") # the input column is untouched
})
