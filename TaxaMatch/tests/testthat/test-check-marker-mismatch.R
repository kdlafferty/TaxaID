# ==============================================================================
# Tests for check_marker_mismatch() and its internal helpers
# (.resolve_marker_pattern(), .fetch_marker_annotation()).
#
# Fully offline: .fetch_marker_annotation() is mocked via
# local_mocked_bindings(), matching this package's established pattern.
# ==============================================================================

.resolve_marker_pattern_int <- function(...)
  get(".resolve_marker_pattern", envir = asNamespace("TaxaMatch"))(...)

# ------------------------------------------------------------------------------
# .resolve_marker_pattern()
# ------------------------------------------------------------------------------

test_that(".resolve_marker_pattern() resolves known marker synonyms", {
  p12s <- .resolve_marker_pattern_int("12S")
  expect_true(grepl(p12s, "12S ribosomal RNA", ignore.case = TRUE))
  expect_true(grepl(p12s, "s-rRNA", ignore.case = TRUE))
  expect_false(grepl(p12s, "16S ribosomal RNA", ignore.case = TRUE))

  # case/punctuation-insensitive key matching
  p12s_lower <- .resolve_marker_pattern_int("mifish-12s")
  expect_true(grepl(p12s_lower, "12S ribosomal RNA", ignore.case = TRUE))
})

test_that(".resolve_marker_pattern() falls back to a literal match for an unlisted marker", {
  p_unknown <- .resolve_marker_pattern_int("XYZ-marker")
  expect_true(grepl(p_unknown, "some XYZ-marker region", ignore.case = TRUE))
  expect_false(grepl(p_unknown, "an unrelated gene", ignore.case = TRUE))
})

# ------------------------------------------------------------------------------
# check_marker_mismatch() -- full offline integration
# ------------------------------------------------------------------------------

# AY850362-style fixture: a real accession annotated as 16S (gene="16S",
# product="16S ribosomal RNA") checked against an expected marker of "12S"
# -- the real motivating case (Question 2, item 4) this function exists to
# catch cheaply, before ever reaching investigate_flagged_accession()'s
# much more expensive deep dive.
.mock_fetch_marker_annotation <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
  fx <- data.frame(
    accession   = c("AY850362", "AY850362", "MZ605481", "NOANNOT111"),
    feature_key = c("rRNA", "gene", "rRNA", NA_character_),
    gene        = c(NA_character_, "16S", NA_character_, NA_character_),
    product     = c("16S ribosomal RNA", NA_character_, "12S ribosomal RNA", NA_character_),
    stringsAsFactors = FALSE
  )
  fx[fx$accession %in% accessions, , drop = FALSE]
}

test_that("check_marker_mismatch() detects a real marker mismatch (AY850362-style)", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("AY850362", "12S", verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_false(out$marker_match)
  expect_equal(out$annotated_products, "16S ribosomal RNA")
  expect_equal(out$annotated_genes, "16S")
})

test_that("check_marker_mismatch() confirms a real marker match", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("MZ605481", "12S", verbose = FALSE)
  expect_true(out$marker_match)
  expect_equal(out$annotated_products, "12S ribosomal RNA")
})

test_that("check_marker_mismatch() returns NA marker_match when the record has no relevant annotation", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("NOANNOT111", "12S", verbose = FALSE)
  expect_true(is.na(out$marker_match))
})

test_that("check_marker_mismatch() returns NA marker_match for an accession not found at all", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("GHOST999", "12S", verbose = FALSE)
  expect_true(is.na(out$marker_match))
  expect_true(is.na(out$annotated_genes))
  expect_true(is.na(out$annotated_products))
})

test_that("check_marker_mismatch() checks multiple accessions and dedupes input", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch(
    c("AY850362", "MZ605481", "AY850362"), "12S", verbose = FALSE
  )
  expect_equal(nrow(out), 2L)
  expect_setequal(out$accession, c("AY850362", "MZ605481"))
  expect_false(out$marker_match[out$accession == "AY850362"])
  expect_true(out$marker_match[out$accession == "MZ605481"])
})

test_that("check_marker_mismatch() validates inputs", {
  expect_error(check_marker_mismatch(123, "12S"), "character vector")
  expect_error(check_marker_mismatch(character(0L), "12S"), "non-empty")
  expect_error(check_marker_mismatch(c(NA, ""), "12S"), "No valid")
  expect_error(check_marker_mismatch("AY850362", NA_character_), "expected_marker")
  expect_error(check_marker_mismatch("AY850362", c("12S", "16S")), "expected_marker")
})
