# tests/testthat/test-verify_taxon_names.R
#
# Tests for verify_taxon_names()
#
# Tests are split into two groups:
#   1. Offline — test input validation without hitting the internet
#   2. Online  — test real API behavior (skipped on CRAN and CI if no internet)
#
# To run manually: devtools::test()

# ── Offline tests: input validation ─────────────────────────────────────────

test_that("rejects non-character input", {
  expect_error(verify_taxon_names(123, backbone_id = 4),
               "`name_list` must be a non-empty character vector")
})

test_that("rejects empty character vector", {
  expect_error(verify_taxon_names(character(0), backbone_id = 4),
               "`name_list` must be a non-empty character vector")
})

test_that("rejects missing or non-scalar backbone_id", {
  expect_error(verify_taxon_names("Homo sapiens", backbone_id = c(4, 9)),
               "`backbone_id` must be a single integer")
  expect_error(verify_taxon_names("Homo sapiens", backbone_id = "ncbi"),
               "`backbone_id` must be a single integer")
})

# ── Online tests: real API behavior ─────────────────────────────────────────
# These tests require internet access and are skipped otherwise.

test_that("returns correct structure for valid names", {
  skip_if_offline()

  result <- verify_taxon_names(
    name_list   = c("Homo sapiens", "Mus musculus"),
    backbone_id = 4
  )

  # Output is a data frame / tibble
  expect_s3_class(result, "data.frame")

  # Correct number of rows
  expect_equal(nrow(result), 2)

  # All expected columns present
  expect_named(result,
               c("user_supplied_name", "matched_name",
                 "classification_path", "classification_ranks",
                 "score", "verified"),
               ignore.order = FALSE)

  # All rows reached the API
  expect_true(all(result$verified))

  # Score is numeric
  expect_type(result$score, "double")
})

test_that("exact matches return score of 1", {
  skip_if_offline()

  result <- verify_taxon_names("Homo sapiens", backbone_id = 4)
  expect_equal(result$score, 1)
})

test_that("unrecognized name returns NA matched_name with verified = TRUE", {
  skip_if_offline()

  result <- verify_taxon_names("Xyzzy fakeii", backbone_id = 4)
  expect_true(result$verified)
  expect_true(is.na(result$matched_name))
})

test_that("duplicates are deduplicated for API but output preserves input length", {
  skip_if_offline()

  result <- verify_taxon_names(
    c("Homo sapiens", "Homo sapiens", "Homo sapiens"),
    backbone_id = 4
  )
  # Output has same length as input; duplicates get identical results
  expect_equal(nrow(result), 3)
  expect_equal(result$matched_name[1], result$matched_name[2])
  expect_equal(result$matched_name[2], result$matched_name[3])
})

test_that("whitespace in names is trimmed", {
  skip_if_offline()

  result <- verify_taxon_names("  Homo sapiens  ", backbone_id = 4)
  expect_equal(result$user_supplied_name, "Homo sapiens")
})
