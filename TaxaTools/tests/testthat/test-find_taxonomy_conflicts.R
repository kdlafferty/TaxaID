# ==============================================================================
# test-find_taxonomy_conflicts.R
# Tests for find_taxonomy_conflicts()
# All tests are fully offline.
# ==============================================================================

# Helper: minimal clean taxonomy data frame (no conflicts)
.clean_df <- function() {
  data.frame(
    family  = c("Cottidae",  "Cottidae",   "Salmonidae"),
    genus   = c("Cottus",    "Enophrys",   "Salmo"),
    species = c("Cottus asper", "Enophrys bison", "Salmo salar"),
    stringsAsFactors = FALSE
  )
}

# Helper: data frame with a known genus-family conflict
.conflict_df <- function() {
  data.frame(
    family  = c("Cottidae",    "Scorpaenidae",    "Cottidae"),
    genus   = c("Cottus",      "Cottus",           "Enophrys"),
    species = c("Cottus asper", "Cottus rhotheus", "Enophrys bison"),
    stringsAsFactors = FALSE
  )
}

# --- Input validation ---------------------------------------------------------

test_that("errors on non-data-frame input", {
  expect_error(find_taxonomy_conflicts("not a df"),  "must be a data frame")
  expect_error(find_taxonomy_conflicts(list(a = 1)), "must be a data frame")
  expect_error(find_taxonomy_conflicts(42),          "must be a data frame")
})

# --- Clean data (no conflicts) ------------------------------------------------

test_that("returns 0-row data frame when no conflicts present", {
  result <- find_taxonomy_conflicts(.clean_df())
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 0L)
})

test_that("zero-row result has the correct column names", {
  result <- find_taxonomy_conflicts(.clean_df())
  expect_named(result,
    c("taxon_name", "taxon_rank", "parent_rank", "parent_values", "n_values"))
})

# --- Known conflict -----------------------------------------------------------

test_that("detects a genus assigned to two families", {
  result <- find_taxonomy_conflicts(.conflict_df())
  expect_true(nrow(result) >= 1L)
  expect_true("Cottus" %in% result$taxon_name)
})

test_that("conflict row has correct taxon_rank and parent_rank", {
  result <- find_taxonomy_conflicts(.conflict_df())
  cottus_row <- result[result$taxon_name == "Cottus", ]
  expect_equal(cottus_row$taxon_rank,  "genus")
  expect_equal(cottus_row$parent_rank, "family")
})

test_that("parent_values is semicolon-separated and sorted", {
  result <- find_taxonomy_conflicts(.conflict_df())
  cottus_row <- result[result$taxon_name == "Cottus", ]
  expect_equal(cottus_row$parent_values, "Cottidae; Scorpaenidae")
})

test_that("n_values equals the number of distinct parent values", {
  result <- find_taxonomy_conflicts(.conflict_df())
  cottus_row <- result[result$taxon_name == "Cottus", ]
  expect_equal(cottus_row$n_values, 2L)
})

# --- rank_system argument -----------------------------------------------------

test_that("accepts explicit rank_system and detects conflict", {
  result <- find_taxonomy_conflicts(
    .conflict_df(),
    rank_system = c("family", "genus", "species")
  )
  expect_true("Cottus" %in% result$taxon_name)
})

test_that("auto-detects rank columns when rank_system is NULL", {
  result <- find_taxonomy_conflicts(.conflict_df(), rank_system = NULL)
  expect_true(nrow(result) >= 1L)
})

test_that("messages and returns empty df when fewer than 2 rank columns detected", {
  df <- data.frame(species = c("Cottus asper", "Salmo salar"),
                   stringsAsFactors = FALSE)
  expect_message(
    result <- find_taxonomy_conflicts(df, rank_system = "species"),
    "fewer than 2"
  )
  expect_equal(nrow(result), 0L)
})

# --- NA handling --------------------------------------------------------------

test_that("rows with NA in either column are skipped, not treated as a conflict", {
  df <- data.frame(
    family  = c("Cottidae", NA,       "Cottidae"),
    genus   = c("Cottus",   "Cottus", "Enophrys"),
    stringsAsFactors = FALSE
  )
  result <- find_taxonomy_conflicts(df, rank_system = c("family", "genus"))
  expect_equal(nrow(result), 0L)
})

# --- Multi-level conflicts ----------------------------------------------------

test_that("detects conflict at species level (same species name, different genera)", {
  df <- data.frame(
    genus   = c("Cottus",  "Enophrys"),
    species = c("Cottus asper", "Cottus asper"),
    stringsAsFactors = FALSE
  )
  result <- find_taxonomy_conflicts(df, rank_system = c("genus", "species"))
  expect_true("Cottus asper" %in% result$taxon_name)
  expect_equal(result$taxon_rank[result$taxon_name == "Cottus asper"], "species")
})

# --- Output column types ------------------------------------------------------

test_that("output columns have correct types", {
  result <- find_taxonomy_conflicts(.conflict_df())
  expect_type(result$taxon_name,    "character")
  expect_type(result$taxon_rank,    "character")
  expect_type(result$parent_rank,   "character")
  expect_type(result$parent_values, "character")
  expect_type(result$n_values,      "integer")
})
