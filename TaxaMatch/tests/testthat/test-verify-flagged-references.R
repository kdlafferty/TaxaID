# verify_flagged_references() -- fully offline via a mocked
# evaluate_reference_accessions(), matching this file's sibling tests'
# established local_mocked_bindings(.package = "TaxaMatch") convention.

.mock_qc <- function(accessions, flags) {
  data.frame(
    accession = accessions,
    hierarchy_flag = flags,
    stringsAsFactors = FALSE
  )
}

test_that("verify_flagged_references: accepts a flag_reference_errors()-style data frame", {
  errors <- data.frame(
    id_x = c("A1", "A2", "A3"),
    error_type = c("likely_mislabeled", "likely_mislabeled", "unverified_singleton_high_match"),
    stringsAsFactors = FALSE
  )
  mock_qc <- .mock_qc(c("A1", "A2"), c("congruent", "incongruent"))
  local_mocked_bindings(
    evaluate_reference_accessions = function(accessions, ...) mock_qc,
    .package = "TaxaMatch"
  )

  result <- verify_flagged_references(errors)
  expect_equal(result$verified_clean, "A1")
  expect_equal(nrow(result$evaluation), 2L)
})

test_that("verify_flagged_references: error_types restricts which rows are screened", {
  errors <- data.frame(
    id_x = c("A1", "A2"),
    error_type = c("likely_mislabeled", "unverified_singleton_high_match"),
    stringsAsFactors = FALSE
  )
  captured <- NULL
  local_mocked_bindings(
    evaluate_reference_accessions = function(accessions, ...) {
      captured <<- accessions
      .mock_qc(accessions, "congruent")
    },
    .package = "TaxaMatch"
  )

  verify_flagged_references(errors)
  expect_equal(captured, "A1")

  verify_flagged_references(errors,
    error_types = c("likely_mislabeled", "unverified_singleton_high_match")
  )
  expect_setequal(captured, c("A1", "A2"))
})

test_that("verify_flagged_references: accepts a plain character vector of accessions", {
  local_mocked_bindings(
    evaluate_reference_accessions = function(accessions, ...) .mock_qc(accessions, "congruent"),
    .package = "TaxaMatch"
  )
  result <- verify_flagged_references(c("X1", "X2", "X1"))
  expect_equal(sort(result$verified_clean), c("X1", "X2"))
})

test_that("verify_flagged_references: trust_insufficient_evidence controls whether that verdict counts as verified", {
  mock_qc <- .mock_qc(c("A1", "A2"), c("congruent", "insufficient_independent_evidence"))
  local_mocked_bindings(
    evaluate_reference_accessions = function(accessions, ...) mock_qc,
    .package = "TaxaMatch"
  )

  result_default <- verify_flagged_references(c("A1", "A2"))
  expect_equal(result_default$verified_clean, "A1")

  result_trusting <- verify_flagged_references(c("A1", "A2"),
    trust_insufficient_evidence = TRUE
  )
  expect_setequal(result_trusting$verified_clean, c("A1", "A2"))
})

test_that("verify_flagged_references: incongruent accessions are never verified_clean", {
  mock_qc <- .mock_qc(
    c("A1", "A2", "A3"),
    c("congruent", "incongruent", "insufficient_independent_evidence")
  )
  local_mocked_bindings(
    evaluate_reference_accessions = function(accessions, ...) mock_qc,
    .package = "TaxaMatch"
  )
  result <- verify_flagged_references(c("A1", "A2", "A3"),
    trust_insufficient_evidence = TRUE
  )
  expect_false("A2" %in% result$verified_clean)
})

test_that("verify_flagged_references: no matching accessions makes no NCBI call", {
  errors <- data.frame(
    id_x = "A1", error_type = "unverified_singleton_high_match",
    stringsAsFactors = FALSE
  )
  called <- FALSE
  local_mocked_bindings(
    evaluate_reference_accessions = function(accessions, ...) {
      called <<- TRUE
      .mock_qc(accessions, "congruent")
    },
    .package = "TaxaMatch"
  )
  result <- verify_flagged_references(errors) # default error_types = "likely_mislabeled"
  expect_false(called)
  expect_equal(result$verified_clean, character(0L))
  expect_null(result$evaluation)
})

test_that("verify_flagged_references: input validation", {
  expect_error(verify_flagged_references(data.frame(x = 1)), "missing required columns")
  expect_error(verify_flagged_references(123), "flagged must be a data frame")
})
