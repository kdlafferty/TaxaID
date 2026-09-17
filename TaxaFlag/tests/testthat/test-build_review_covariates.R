# test-build_review_covariates.R
# Fully offline -- pure data-frame aggregation, no network calls.
# This function had zero test coverage before this pass (found during a
# code review against inst/Code and Domain Review 2.Rmd); every expected
# value below was verified against the real function output, not guessed.

library(testthat)

.make_reads <- function() {
  data.frame(
    ESVId = c("ESV_1", "ESV_1", "ESV_1", "ESV_2", "ESV_2", "ESV_3"),
    sequence = c("ACGTACGT", "ACGTACGT", "ACGTACGT", "ACGT", "ACGT", "ACGTACGTAC"),
    event_id = c("s1", "s2", "blank1", "s1", "s2", "blank1"),
    n_reads = c(100, 50, 2, 5, 0, 30),
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
    .make_reads(), .make_cls(),
    control_samples = "blank1"
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
    .make_reads(), .make_cls(),
    control_samples = "blank1"
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
  cls <- data.frame(
    observation_id = c("ESV_1", "ESV_2"),
    primary_plausibility = c("expected", "unexpected"),
    stringsAsFactors = FALSE
  )
  expect_no_warning(build_review_covariates(reads, cls))
})

test_that("sequence_col = NULL omits seq_length entirely", {
  out <- suppressWarnings(build_review_covariates(
    .make_reads(), .make_cls(),
    control_samples = "blank1", sequence_col = NULL
  ))
  expect_false("seq_length" %in% names(out))
})

test_that("inconsistent sequence lengths within a taxon warn and use the first occurrence", {
  reads <- data.frame(
    ESVId = c("ESV_1", "ESV_1"), sequence = c("ACGTACGT", "AC"),
    event_id = c("s1", "s2"), n_reads = c(100, 50),
    stringsAsFactors = FALSE
  )
  cls <- data.frame(
    observation_id = "ESV_1", primary_plausibility = "expected",
    stringsAsFactors = FALSE
  )
  expect_warning(
    out <- build_review_covariates(reads, cls),
    "more than one distinct sequence length.*ESV_1"
  )
  esv1 <- out[out$observation_id == "ESV_1", ]
  expect_equal(esv1$seq_length, 8L) # first occurrence's length, not the second
})

test_that("contaminant_df joins in requested columns and warns on unmatched rows", {
  reads <- data.frame(
    ESVId = c("ESV_1", "ESV_1", "ESV_2"), sequence = c("ACGTACGT", "ACGTACGT", "ACGT"),
    event_id = c("s1", "s2", "s1"), n_reads = c(100, 50, 5),
    stringsAsFactors = FALSE
  )
  cls <- data.frame(
    observation_id = c("ESV_1", "ESV_2"),
    primary_plausibility = c("expected", "unexpected"),
    stringsAsFactors = FALSE
  )
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
  cls <- data.frame(
    observation_id = "ESV_1", primary_plausibility = "expected",
    stringsAsFactors = FALSE
  )
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
  cls <- data.frame(
    observation_id = "ESV_1", primary_plausibility = "expected",
    stringsAsFactors = FALSE
  )
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
      classification_col = "nonexistent_col"
    ),
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

# ---------------------------------------------------------------------------
# site_col: within-site replicate detection frequency
# ---------------------------------------------------------------------------
# Site A has a 4-replicate roster (a1-a4) and site B a 2-replicate roster
# (b1, b2). blank1 sits at site A but is a control, so it must never enter
# A's roster -- if it did, A's denominator would be 5 and ESV_1's best-site
# frequency would read 0.8 instead of 1.
.make_site_reads <- function() {
  data.frame(
    ESVId = c(rep("ESV_1", 5), rep("ESV_2", 2), "ESV_3", rep("ESV_4", 6)),
    sequence = c(rep("ACGTACGT", 5), rep("ACGT", 2), "AACC", rep("TTTT", 6)),
    event_id = c(
      "a1", "a2", "a3", "a4", "b1", "b1", "b2", "blank1",
      "a1", "a2", "a3", "a4", "b1", "b2"
    ),
    site_id = c("A", "A", "A", "A", "B", "B", "B", "A", "A", "A", "A", "A", "B", "B"),
    n_reads = c(100, 50, 40, 30, 20, 10, 10, 5, 9, 9, 9, 9, 9, 9),
    stringsAsFactors = FALSE
  )
}

.make_site_cls <- function() {
  data.frame(
    observation_id = c("ESV_1", "ESV_2", "ESV_3", "ESV_4"),
    primary_plausibility = c("expected", "expected", "unexpected", "expected"),
    stringsAsFactors = FALSE
  )
}

test_that("site_col = NULL leaves the output completely unchanged", {
  reads <- .make_site_reads()
  cls <- .make_site_cls()
  base <- build_review_covariates(reads, cls, control_samples = "blank1")
  with_site <- build_review_covariates(reads, cls,
    site_col = "site_id", control_samples = "blank1"
  )

  expect_false(any(c(
    "n_sites_detected", "prop_sites_detected", "max_site_detection_freq",
    "mean_site_detection_freq", "n_replicates_at_max_site"
  ) %in% names(base)))
  # the site columns are purely additive: every pre-existing column is identical
  expect_identical(base, with_site[, names(base)])
})

test_that("within-site detection frequency uses the full replicate roster", {
  out <- build_review_covariates(
    .make_site_reads(), .make_site_cls(),
    site_col = "site_id", control_samples = "blank1"
  )
  g <- function(id, col) out[[col]][out$observation_id == id]

  # ESV_1: 4/4 at A, 1/2 at B
  expect_equal(g("ESV_1", "n_sites_detected"), 2L)
  expect_equal(g("ESV_1", "prop_sites_detected"), 1)
  expect_equal(g("ESV_1", "max_site_detection_freq"), 1)
  expect_equal(g("ESV_1", "mean_site_detection_freq"), 0.75)
  expect_equal(g("ESV_1", "n_replicates_at_max_site"), 4L)

  # ESV_2: 2/2 at B, absent from A. Same best-site frequency as ESV_1, on a
  # roster half the size -- the case n_replicates_at_max_site exists for.
  expect_equal(g("ESV_2", "n_sites_detected"), 1L)
  expect_equal(g("ESV_2", "prop_sites_detected"), 0.5)
  expect_equal(g("ESV_2", "max_site_detection_freq"), 1)
  expect_equal(g("ESV_2", "n_replicates_at_max_site"), 2L)

  # the pooled view cannot distinguish these two: ESV_1 is in 5/6 samples,
  # but "5/6" says nothing about it saturating one site and half-filling another
  expect_equal(g("ESV_1", "prop_samples_detected"), 5 / 6)
})

test_that("a frequency tie reports the larger replicate roster, not the first site name", {
  out <- build_review_covariates(
    .make_site_reads(), .make_site_cls(),
    site_col = "site_id", control_samples = "blank1"
  )
  # ESV_4 is 4/4 at A and 2/2 at B -- tied at 1.0. Site "A" also happens to
  # sort first, so assert on a case where the two rules disagree instead.
  reads <- .make_site_reads()
  reads$site_id[reads$site_id == "A"] <- "Zed"
  out2 <- build_review_covariates(
    reads, .make_site_cls(),
    site_col = "site_id", control_samples = "blank1"
  )
  expect_equal(
    out$n_replicates_at_max_site[out$observation_id == "ESV_4"], 4L
  )
  expect_equal(
    out2$n_replicates_at_max_site[out2$observation_id == "ESV_4"], 4L
  )
})

test_that("observations with no field detections get zeros for counts and NA where undefined", {
  out <- build_review_covariates(
    .make_site_reads(), .make_site_cls(),
    site_col = "site_id", control_samples = "blank1"
  )
  i <- which(out$observation_id == "ESV_3") # blank-only

  expect_equal(out$n_sites_detected[i], 0L)
  expect_equal(out$prop_sites_detected[i], 0)
  expect_equal(out$max_site_detection_freq[i], 0)
  expect_true(is.na(out$mean_site_detection_freq[i]))
  expect_true(is.na(out$n_replicates_at_max_site[i]))
})

test_that("rows with a missing site are dropped from site covariates only, with a warning", {
  reads <- .make_site_reads()
  reads$site_id[reads$event_id == "b2"] <- NA

  expect_warning(
    out <- build_review_covariates(
      reads, .make_site_cls(),
      site_col = "site_id", control_samples = "blank1"
    ),
    "missing 'site_id' value"
  )
  # B's roster is now b1 alone, so ESV_2 reads 1/1 there ...
  expect_equal(out$n_replicates_at_max_site[out$observation_id == "ESV_2"], 1L)
  # ... but the non-site covariates still see both of its samples
  expect_equal(out$n_samples_detected[out$observation_id == "ESV_2"], 2L)
})

test_that("site_col validates against reads_df", {
  expect_error(
    build_review_covariates(.make_site_reads(), .make_site_cls(), site_col = "nope"),
    "column 'nope' not found in reads_df"
  )
  expect_error(
    build_review_covariates(.make_site_reads(), .make_site_cls(), site_col = c("a", "b")),
    "'site_col' must be a single column name or NULL"
  )
})
