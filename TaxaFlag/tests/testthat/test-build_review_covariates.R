# test-build_review_covariates.R
# Fully offline -- pure data-frame aggregation, no network calls.
# This function had zero test coverage before this pass (found during a
# code review against inst/Code and Domain Review 2.Rmd); every expected
# value below was verified against the real function output, not guessed.

library(testthat)

.make_reads <- function() {
  data.frame(
    ESVId    = c("ESV_1", "ESV_1", "ESV_1", "ESV_2", "ESV_2", "ESV_3"),
    sequence = c("ACGTACGT", "ACGTACGT", "ACGTACGT", "ACGT", "ACGT", "ACGTACGTAC"),
    event_id = c("s1", "s2", "blank1", "s1", "s2", "blank1"),
    n_reads  = c(100, 50, 2, 5, 0, 30),
    stringsAsFactors = FALSE
  )
}

.make_cls <- function() {
  data.frame(
    observation_id = c("ESV_1", "ESV_2", "ESV_3", "ESV_orphan"),
    primary_plausibility = c("expected", "unexpected", "expected", "unexpected"),
    stringsAsFactors = FALSE
  )
}

test_that("basic field-side aggregates and zero-fill are correct", {
  out <- suppressWarnings(build_review_covariates(
    .make_reads(), .make_cls(), control_samples = "blank1"
  ))

  expect_equal(nrow(out), 4L)
  expect_equal(out$observation_id, c("ESV_1", "ESV_2", "ESV_3", "ESV_orphan"))
  expect_equal(out$classification, c("expected", "unexpected", "expected", "unexpected"))

  esv1 <- out[out$observation_id == "ESV_1", ]
  expect_equal(esv1$min_reads, 50)
  expect_equal(esv1$max_reads, 100)
  expect_equal(esv1$total_reads, 150)
  expect_equal(esv1$n_samples_detected, 2L)
  expect_equal(esv1$prop_samples_detected, 1.0)
  expect_equal(esv1$seq_length, 8L)

  esv2 <- out[out$observation_id == "ESV_2", ]
  # s2 has n_reads = 0 for ESV_2 -- dropped before aggregation, so only s1 counts
  expect_equal(esv2$n_samples_detected, 1L)
  expect_equal(esv2$prop_samples_detected, 0.5)
})

test_that("a taxon detected only in a control sample gets zero-filled field counts, NA min/max, real seq_length", {
  out <- suppressWarnings(build_review_covariates(
    .make_reads(), .make_cls(), control_samples = "blank1"
  ))
  esv3 <- out[out$observation_id == "ESV_3", ]

  expect_equal(esv3$n_samples_detected, 0L)
  expect_equal(esv3$prop_samples_detected, 0)
  expect_equal(esv3$total_reads, 0)
  expect_true(is.na(esv3$min_reads))
  expect_true(is.na(esv3$max_reads))
  expect_true(is.na(esv3$quantile_reads))
  # seq_length is still real -- it comes from reads_df directly, control rows included
  expect_equal(esv3$seq_length, 10L)
})

test_that("a classification_df row entirely absent from reads_df warns and is zero/NA-filled", {
  expect_warning(
    out <- build_review_covariates(.make_reads(), .make_cls(), control_samples = "blank1"),
    "no matching rows in reads_df at all.*ESV_orphan"
  )
  orphan <- out[out$observation_id == "ESV_orphan", ]
  expect_equal(orphan$n_samples_detected, 0L)
  expect_equal(orphan$total_reads, 0)
  expect_true(is.na(orphan$min_reads))
  expect_true(is.na(orphan$seq_length))
})

test_that("no warning when control_samples is NULL and every taxon has some field data", {
  reads <- .make_reads()
  reads <- reads[reads$event_id != "blank1", ]
  cls <- data.frame(observation_id = c("ESV_1", "ESV_2"),
                     primary_plausibility = c("expected", "unexpected"),
                     stringsAsFactors = FALSE)
  expect_no_warning(build_review_covariates(reads, cls))
})

test_that("sequence_col = NULL omits seq_length entirely", {
  out <- suppressWarnings(build_review_covariates(
    .make_reads(), .make_cls(), control_samples = "blank1", sequence_col = NULL
  ))
  expect_false("seq_length" %in% names(out))
})

test_that("inconsistent sequence lengths within a taxon warn and use the first occurrence", {
  reads <- data.frame(
    ESVId = c("ESV_1", "ESV_1"), sequence = c("ACGTACGT", "AC"),
    event_id = c("s1", "s2"), n_reads = c(100, 50),
    stringsAsFactors = FALSE
  )
  cls <- data.frame(observation_id = "ESV_1", primary_plausibility = "expected",
                     stringsAsFactors = FALSE)
  expect_warning(
    out <- build_review_covariates(reads, cls),
    "more than one distinct sequence length.*ESV_1"
  )
  esv1 <- out[out$observation_id == "ESV_1", ]
  expect_equal(esv1$seq_length, 8L)  # first occurrence's length, not the second
})

test_that("contaminant_df joins in requested columns and warns on unmatched rows", {
  reads <- data.frame(
    ESVId = c("ESV_1", "ESV_1", "ESV_2"), sequence = c("ACGTACGT", "ACGTACGT", "ACGT"),
    event_id = c("s1", "s2", "s1"), n_reads = c(100, 50, 5),
    stringsAsFactors = FALSE
  )
  cls <- data.frame(observation_id = c("ESV_1", "ESV_2"),
                     primary_plausibility = c("expected", "unexpected"),
                     stringsAsFactors = FALSE)
  contam <- data.frame(ESVId = "ESV_1", control_rate = 0.01, stringsAsFactors = FALSE)

  expect_warning(
    out <- build_review_covariates(reads, cls, contaminant_df = contam),
    "no matching rows in contaminant_df.*ESV_2"
  )
  expect_true("control_rate" %in% names(out))
  expect_equal(out$control_rate[out$observation_id == "ESV_1"], 0.01)
  expect_true(is.na(out$control_rate[out$observation_id == "ESV_2"]))
})

test_that("extra_covariate_cols are passed through unchanged from classification_df", {
  reads <- data.frame(
    ESVId = c("ESV_1", "ESV_2"), sequence = c("ACGTACGT", "ACGT"),
    event_id = c("s1", "s1"), n_reads = c(100, 5),
    stringsAsFactors = FALSE
  )
  cls <- data.frame(
    observation_id = c("ESV_1", "ESV_2"),
    primary_plausibility = c("expected", "unexpected"),
    winner_likelihood = c(0.9, 0.5),
    stringsAsFactors = FALSE
  )
  out <- build_review_covariates(reads, cls, extra_covariate_cols = "winner_likelihood")
  expect_equal(out$winner_likelihood, c(0.9, 0.5))
})

test_that("read_quantile = 1 reproduces max_reads", {
  reads <- data.frame(
    ESVId = rep("ESV_1", 4), sequence = rep("ACGT", 4),
    event_id = c("s1", "s2", "s3", "s4"), n_reads = c(10, 40, 20, 90),
    stringsAsFactors = FALSE
  )
  cls <- data.frame(observation_id = "ESV_1", primary_plausibility = "expected",
                     stringsAsFactors = FALSE)
  out <- build_review_covariates(reads, cls, read_quantile = 1)
  expect_equal(out$quantile_reads, out$max_reads)
  expect_equal(out$max_reads, 90)
})

test_that("rows with n_reads = 0 are excluded before aggregation", {
  reads <- data.frame(
    ESVId = c("ESV_1", "ESV_1"), sequence = c("ACGT", "ACGT"),
    event_id = c("s1", "s2"), n_reads = c(0, 25),
    stringsAsFactors = FALSE
  )
  cls <- data.frame(observation_id = "ESV_1", primary_plausibility = "expected",
                     stringsAsFactors = FALSE)
  out <- build_review_covariates(reads, cls)
  expect_equal(out$n_samples_detected, 1L)
  expect_equal(out$total_reads, 25)
})

# ===========================================================================
# Input validation
# ===========================================================================

test_that("errors when reads_df is not a data frame", {
  expect_error(
    build_review_covariates(list(), .make_cls()),
    "'reads_df' must be a data frame"
  )
})

test_that("errors when classification_df is not a data frame", {
  expect_error(
    build_review_covariates(.make_reads(), list()),
    "'classification_df' must be a data frame"
  )
})

test_that("errors when a required reads_df column is missing", {
  reads <- .make_reads()
  reads$n_reads <- NULL
  expect_error(
    build_review_covariates(reads, .make_cls()),
    "'n_reads' not found in reads_df"
  )
})

test_that("errors when classification_col is missing from classification_df", {
  expect_error(
    build_review_covariates(.make_reads(), .make_cls(),
                             classification_col = "nonexistent_col"),
    "'nonexistent_col' not found in classification_df"
  )
})

test_that("errors when sequence_col is supplied but missing from reads_df", {
  expect_error(
    build_review_covariates(.make_reads(), .make_cls(), sequence_col = "nope"),
    "'nope' not found in reads_df"
  )
})

test_that("errors when contaminant_df is supplied but not a data frame", {
  expect_error(
    build_review_covariates(.make_reads(), .make_cls(), contaminant_df = list()),
    "'contaminant_df' must be a data frame or NULL"
  )
})

test_that("errors when read_quantile is out of (0, 1]", {
  expect_error(
    build_review_covariates(.make_reads(), .make_cls(), read_quantile = 0),
    "'read_quantile' must be a single number in \\(0, 1\\]"
  )
  expect_error(
    build_review_covariates(.make_reads(), .make_cls(), read_quantile = 1.5),
    "'read_quantile' must be a single number in \\(0, 1\\]"
  )
})
