# test-get_keys_from_context.R
# Tests for get_keys_from_context() and its internal helper .process_gbif_row().
#
# Strategy:
#   - Input validation tests: no rgbif needed, mock the requireNamespace check.
#   - Logic tests (rank selection, NO_DATA, case-insensitivity, ERROR path):
#     mock rgbif::name_backbone via testthat::local_mocked_bindings().
#   - Live API integration tests: skip_if_not_installed + skip_if_offline.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

.hierarchy_full <- data.frame(
  kingdom = "Animalia",
  phylum  = "Chordata",
  class   = "Actinopterygii",
  order   = "Scorpaeniformes",
  family  = "Sebastidae",
  genus   = "Sebastes",
  species = "Sebastes mystinus",
  stringsAsFactors = FALSE
)

.hierarchy_genus_only <- data.frame(
  kingdom = "Animalia",
  genus   = "Sebastes",
  stringsAsFactors = FALSE
)

.hierarchy_no_ranks <- data.frame(
  common_name = "Blue rockfish",
  notes       = "test",
  stringsAsFactors = FALSE
)

.hierarchy_mixed_case <- data.frame(
  Kingdom = "Animalia",
  SPECIES = "Engraulis mordax",
  stringsAsFactors = FALSE
)

.hierarchy_blank_species <- data.frame(
  genus   = "Sebastes",
  species = "",
  stringsAsFactors = FALSE
)

.hierarchy_na_species <- data.frame(
  genus   = "Sebastes",
  species = NA_character_,
  stringsAsFactors = FALSE
)

.mock_backbone_exact <- function(...) {
  list(usageKey = 12345L, matchType = "EXACT", rank = "SPECIES")
}

.mock_backbone_none <- function(...) {
  list(usageKey = NULL, matchType = "NONE", rank = NULL)
}

# =============================================================================
# Input validation -- no API needed
# =============================================================================

test_that("stops if hierarchy_df is not a dataframe", {
  expect_error(
    get_keys_from_context("not a df"),
    regexp = "must be a dataframe"
  )
})

test_that("stops if hierarchy_df has zero rows", {
  empty <- .hierarchy_full[0, ]
  expect_error(
    get_keys_from_context(empty),
    regexp = "zero rows"
  )
})

test_that("stops if no recognised rank columns are present", {
  expect_error(
    get_keys_from_context(.hierarchy_no_ranks),
    regexp = "no rank columns"
  )
})

test_that("stops if rgbif is not installed", {
  skip_if(requireNamespace("rgbif", quietly = TRUE),
          "rgbif is installed; skipping missing-package test")
  expect_error(
    get_keys_from_context(.hierarchy_full),
    regexp = "rgbif"
  )
})

# =============================================================================
# Output structure (mocked API)
# =============================================================================

test_that("appends exactly usageKey, matchType, gbif_rank columns", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    name_backbone = .mock_backbone_exact,
    .package = "rgbif"
  )
  out <- get_keys_from_context(.hierarchy_full)
  expect_true(all(c("usageKey", "matchType", "gbif_rank") %in% names(out)))
})

test_that("output has same number of rows as input", {
  skip_if_not_installed("rgbif")
  df <- rbind(.hierarchy_full, .hierarchy_full)
  local_mocked_bindings(
    name_backbone = .mock_backbone_exact,
    .package = "rgbif"
  )
  out <- get_keys_from_context(df)
  expect_equal(nrow(out), nrow(df))
})

test_that("original columns are preserved in output", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    name_backbone = .mock_backbone_exact,
    .package = "rgbif"
  )
  out <- get_keys_from_context(.hierarchy_full)
  expect_true(all(names(.hierarchy_full) %in% names(out)))
})

test_that("usageKey is integer type", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    name_backbone = .mock_backbone_exact,
    .package = "rgbif"
  )
  out <- get_keys_from_context(.hierarchy_full)
  expect_type(out$usageKey, "integer")
})

test_that("matchType is character type", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    name_backbone = .mock_backbone_exact,
    .package = "rgbif"
  )
  out <- get_keys_from_context(.hierarchy_full)
  expect_type(out$matchType, "character")
})

# =============================================================================
# Rank selection logic (via .process_gbif_row directly)
# =============================================================================

test_that("selects species as target when present", {
  skip_if_not_installed("rgbif")
  called_with <- list()
  local_mocked_bindings(
    name_backbone = function(...) {
      called_with <<- list(...)
      .mock_backbone_exact()
    },
    .package = "rgbif"
  )
  TaxaFetch:::.process_gbif_row(.hierarchy_full, valid_ranks = c(
    "kingdom","phylum","class","order","family","genus","species"))
  # name should be the species value, rank = SPECIES
  expect_equal(called_with$name, "Sebastes mystinus")
  expect_equal(called_with$rank, "SPECIES")
})

test_that("falls back to genus when species is absent", {
  skip_if_not_installed("rgbif")
  called_with <- list()
  local_mocked_bindings(
    name_backbone = function(...) {
      called_with <<- list(...)
      .mock_backbone_exact()
    },
    .package = "rgbif"
  )
  TaxaFetch:::.process_gbif_row(.hierarchy_genus_only, valid_ranks = c(
    "kingdom","phylum","class","order","family","genus","species"))
  expect_equal(called_with$name, "Sebastes")
  expect_equal(called_with$rank, "GENUS")
})

test_that("column names are matched case-insensitively", {
  skip_if_not_installed("rgbif")
  called_with <- list()
  local_mocked_bindings(
    name_backbone = function(...) {
      called_with <<- list(...)
      .mock_backbone_exact()
    },
    .package = "rgbif"
  )
  TaxaFetch:::.process_gbif_row(.hierarchy_mixed_case, valid_ranks = c(
    "kingdom","phylum","class","order","family","genus","species"))
  expect_equal(called_with$name, "Engraulis mordax")
  expect_equal(called_with$rank, "SPECIES")
})

test_that("higher-rank context is passed to API (target rank stripped from context)", {
  skip_if_not_installed("rgbif")
  called_with <- list()
  local_mocked_bindings(
    name_backbone = function(...) {
      called_with <<- list(...)
      .mock_backbone_exact()
    },
    .package = "rgbif"
  )
  TaxaFetch:::.process_gbif_row(.hierarchy_full, valid_ranks = c(
    "kingdom","phylum","class","order","family","genus","species"))
  # kingdom should be passed as context
  expect_equal(called_with$kingdom, "Animalia")
  # species itself should NOT be in context (removed as target)
  expect_null(called_with$species)
})

# =============================================================================
# NO_DATA path (all rank values blank or NA)
# =============================================================================

test_that("returns NO_DATA when species is blank", {
  valid_ranks <- c("kingdom","phylum","class","order","family","genus","species")
  out <- TaxaFetch:::.process_gbif_row(.hierarchy_blank_species,
                                         valid_ranks = valid_ranks)
  # blank species -> falls back to genus; no API call needed to test:
  # but if only blank species provided and genus also absent -> NO_DATA
  no_rank_row <- data.frame(species = "", stringsAsFactors = FALSE)
  out2 <- TaxaFetch:::.process_gbif_row(no_rank_row, valid_ranks = valid_ranks)
  expect_equal(out2$matchType, "NO_DATA")
  expect_true(is.na(out2$usageKey))
})

test_that("returns NO_DATA when all rank values are NA", {
  na_row <- data.frame(genus = NA_character_, species = NA_character_,
                       stringsAsFactors = FALSE)
  valid_ranks <- c("kingdom","phylum","class","order","family","genus","species")
  out <- TaxaFetch:::.process_gbif_row(na_row, valid_ranks = valid_ranks)
  expect_equal(out$matchType, "NO_DATA")
  expect_true(is.na(out$usageKey))
})

# =============================================================================
# NONE match from API
# =============================================================================

test_that("matchType is NONE and usageKey is NA when API returns no match", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    name_backbone = .mock_backbone_none,
    .package = "rgbif"
  )
  out <- get_keys_from_context(.hierarchy_full)
  expect_equal(out$matchType, "NONE")
  expect_true(is.na(out$usageKey))
})

# =============================================================================
# ERROR path -- API failure produces warning, not stop
# =============================================================================

test_that("API failure returns ERROR matchType with a warning (does not stop)", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    name_backbone = function(...) stop("simulated network error"),
    .package = "rgbif"
  )
  expect_warning(
    out <- get_keys_from_context(.hierarchy_full),
    regexp = "API call failed"
  )
  expect_equal(out$matchType, "ERROR")
  expect_true(is.na(out$usageKey))
})

test_that("one failed row does not prevent other rows from resolving", {
  skip_if_not_installed("rgbif")
  call_count <- 0L
  local_mocked_bindings(
    name_backbone = function(...) {
      call_count <<- call_count + 1L
      if (call_count == 1L) stop("simulated error on row 1")
      .mock_backbone_exact()
    },
    .package = "rgbif"
  )
  df <- rbind(.hierarchy_full, .hierarchy_full)
  expect_warning(out <- get_keys_from_context(df))
  expect_equal(nrow(out), 2L)
  expect_equal(out$matchType[1], "ERROR")
  expect_equal(out$matchType[2], "EXACT")
})

# =============================================================================
# Live API integration (skipped offline)
# =============================================================================

test_that("live API: returns EXACT match for a well-known species", {
  skip_if_not_installed("rgbif")
  skip_if_offline()
  out <- get_keys_from_context(data.frame(
    kingdom = "Animalia", species = "Homo sapiens",
    stringsAsFactors = FALSE
  ))
  expect_equal(out$matchType, "EXACT")
  expect_false(is.na(out$usageKey))
})
