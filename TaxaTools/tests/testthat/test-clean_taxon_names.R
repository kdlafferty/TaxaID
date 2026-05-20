# tests/testthat/test-clean_taxon_names.R
#
# Tests for clean_taxon_names()
# All tests are offline — no API calls.
#
# Design: clean_taxon_names() preserves input length. Invalid names become NA.
# Callers add unique() or na.omit() as needed.

# ==============================================================================
# Input validation
# ==============================================================================

test_that("rejects non-character input", {
  expect_error(clean_taxon_names(123),      "`name_vec` must be a character vector")
  expect_error(clean_taxon_names(TRUE),     "`name_vec` must be a character vector")
  expect_error(clean_taxon_names(list("Homo sapiens")), "`name_vec` must be a character vector")
})

# ==============================================================================
# Length preservation
# ==============================================================================

test_that("output length matches input length", {
  input <- c("Homo sapiens", "mus musculus", NA, "sp.", "Canis lupus sp.")
  out <- clean_taxon_names(input)
  expect_equal(length(out), length(input))
})

# ==============================================================================
# NA and empty handling
# ==============================================================================

test_that("NA inputs become NA in output", {
  out <- clean_taxon_names(c("Homo sapiens", NA))
  expect_equal(out, c("Homo sapiens", NA))
})

test_that("string 'NA' and '<NA>' become NA", {
  out <- clean_taxon_names(c("Homo sapiens", "NA", "<NA>"))
  expect_equal(out, c("Homo sapiens", NA, NA))
})

test_that("all-NA input returns NA vector of same length", {
  out <- clean_taxon_names(c(NA_character_, NA_character_))
  expect_equal(out, c(NA_character_, NA_character_))
})

test_that("empty character vector returns empty character vector", {
  out <- clean_taxon_names(character(0))
  expect_equal(out, character(0))
})

# ==============================================================================
# Case filtering
# ==============================================================================

test_that("names not starting with capital become NA", {
  out <- clean_taxon_names(c("Homo sapiens", "mus musculus", "unknown"))
  expect_equal(out, c("Homo sapiens", NA, NA))
})

# ==============================================================================
# Whitespace normalisation
# ==============================================================================

test_that("trims leading and trailing whitespace", {
  out <- clean_taxon_names(c("  Homo sapiens  "))
  expect_equal(out, "Homo sapiens")
})

test_that("collapses internal whitespace", {
  out <- clean_taxon_names(c("Homo  sapiens"))
  expect_equal(out, "Homo sapiens")
})

# ==============================================================================
# Abbreviation handling
# ==============================================================================

test_that("trims 'sp.' to genus-only", {
  out <- clean_taxon_names(c("Canis sp."))
  expect_equal(out, "Canis")
})

test_that("trims 'spp.' to genus-only", {
  out <- clean_taxon_names(c("Canis spp."))
  expect_equal(out, "Canis")
})

test_that("trims 'spp' (no dot) to genus-only", {
  out <- clean_taxon_names(c("Canis spp"))
  expect_equal(out, "Canis")
})

test_that("trims 'species' to genus-only", {
  out <- clean_taxon_names(c("Canis species"))
  expect_equal(out, "Canis")
})

test_that("trims 'unknown' epithet to genus-only", {
  out <- clean_taxon_names(c("Canis unknown"))
  expect_equal(out, "Canis")
})

test_that("bare abbreviation-only name retains genus", {
  # Starts with capital so passes case filter; no epithet — genus retained.
  out <- clean_taxon_names(c("Sp."))
  expect_equal(out, "Sp.")
})

test_that("valid two-word name is not truncated to genus", {
  out <- clean_taxon_names(c("Homo sapiens"))
  expect_equal(out, "Homo sapiens")
})

# ==============================================================================
# Bracket artefact removal
# ==============================================================================

test_that("strips square brackets around genus", {
  out <- clean_taxon_names(c("[Bacillus] subtilis"))
  expect_equal(out, "Bacillus subtilis")
})

test_that("strips parentheses from names", {
  out <- clean_taxon_names(c("Bacillus (subtilis)"))
  # Epithet is retained but parens removed; re-squished
  expect_false(grepl("[()]", out))
})

# ==============================================================================
# Duplicates are preserved (caller's responsibility to deduplicate)
# ==============================================================================

test_that("duplicates are preserved in output", {
  out <- clean_taxon_names(c("Homo sapiens", "Homo sapiens", "Homo sapiens"))
  expect_equal(length(out), 3L)
  expect_equal(out, c("Homo sapiens", "Homo sapiens", "Homo sapiens"))
})

# ==============================================================================
# Author string trimming
# ==============================================================================

test_that("drops author string (third+ token)", {
  # "Linnaeus" is the third token — should be discarded
  out <- clean_taxon_names(c("Homo sapiens Linnaeus"))
  expect_equal(out, "Homo sapiens")
})

# ==============================================================================
# Custom remove_abbr
# ==============================================================================

test_that("custom remove_abbr replaces defaults", {
  # "mycustom" is not in the default list — would be kept normally
  # but passing it explicitly should cause it to be stripped
  out <- clean_taxon_names(c("Canis mycustom"), remove_abbr = c("mycustom"))
  expect_equal(out, "Canis")
})

# ==============================================================================
# Mixed input — integration
# ==============================================================================

test_that("handles a realistic mixed vector correctly", {
  input <- c(
    "Homo sapiens",
    "mus musculus",        # lowercase — NA
    NA,                    # NA — NA
    "sp.",                 # no capital — NA
    "Canis lupus sp.",     # "sp." is third token (author position) -> "Canis lupus"
    "Homo sapiens",        # duplicate — preserved
    "[Bacillus] subtilis"  # bracket artefact removed
  )
  out <- clean_taxon_names(input)
  expect_equal(length(out), length(input))
  expect_equal(out[1], "Homo sapiens")
  expect_true(is.na(out[2]))
  expect_true(is.na(out[3]))
  expect_true(is.na(out[4]))
  expect_equal(out[5], "Canis lupus")
  expect_equal(out[6], "Homo sapiens")
  expect_equal(out[7], "Bacillus subtilis")
})
