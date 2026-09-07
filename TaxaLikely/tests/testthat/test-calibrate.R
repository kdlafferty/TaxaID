# Tests for calibrate_coverage_filter() and coverage_threshold().
# Neither had any test coverage before this session -- this is their first
# regression coverage. Fixture mimics build_sequence_matrix() output: a
# ref_pairs data frame with id_x/id_y, paired species.x/species.y columns
# (H1 = same species, H2/H3 = different species), p_match, and coverage.

.make_ref_pairs <- function() {
  data.frame(
    id_x = c("A1", "A1", "A1", "A2", "A2", "A2", "B1", "B1", "B1"),
    id_y = c("A1", "A2", "B1", "A1", "A2", "B1", "A1", "A2", "B1"),
    species.x = c("Aa", "Aa", "Aa", "Aa", "Aa", "Aa", "Bb", "Bb", "Bb"),
    species.y = c("Aa", "Aa", "Bb", "Aa", "Aa", "Bb", "Aa", "Aa", "Bb"),
    p_match = c(1.00, 0.95, 0.70, 0.95, 1.00, 0.68, 0.70, 0.68, 1.00),
    coverage = c(1.00, 0.90, 0.40, 0.90, 1.00, 0.35, 0.40, 0.35, 1.00),
    stringsAsFactors = FALSE
  )
}

# ---- calibrate_coverage_filter() --------------------------------------------

test_that("calibrate_coverage_filter: returns one row per threshold with expected columns", {
  out <- calibrate_coverage_filter(.make_ref_pairs(),
    rank_system = "species",
    thresholds = c(0, 0.5, 0.9)
  )
  expect_equal(nrow(out), 3L)
  expect_true(all(c(
    "threshold", "n_queries", "breadth", "h1_pairs", "h2_pairs",
    "h1_retention", "h2_retention", "youden_j",
    "discrimination", "mean_h1_score"
  ) %in% names(out)))
})

test_that("calibrate_coverage_filter: breadth decreases as threshold rises", {
  out <- calibrate_coverage_filter(.make_ref_pairs(),
    rank_system = "species",
    thresholds = c(0, 0.5, 0.99)
  )
  expect_true(all(diff(out$breadth) <= 0))
})

test_that("calibrate_coverage_filter: youden_j is 0 at the no-filter baseline", {
  out <- calibrate_coverage_filter(.make_ref_pairs(),
    rank_system = "species",
    thresholds = 0
  )
  expect_equal(out$youden_j, 0, tolerance = 1e-9)
})

test_that("calibrate_coverage_filter: high threshold retains only high-coverage H1 pairs", {
  # At threshold 0.9, the five coverage>=0.9 rows survive (A1-A1, A1-A2,
  # A2-A1, A2-A2, B1-B1) -- all same-species (H1) pairs; every H2/H3
  # (cross-species) pair has coverage <= 0.40 and is filtered out.
  out <- calibrate_coverage_filter(.make_ref_pairs(),
    rank_system = "species",
    thresholds = 0.9
  )
  expect_equal(out$h1_pairs, 5L)
  expect_equal(out$h2_pairs, 0L)
  expect_equal(out$youden_j, 1.0, tolerance = 1e-9)
})

test_that("calibrate_coverage_filter: auto-detects finest rank when rank_system = NULL", {
  out <- calibrate_coverage_filter(.make_ref_pairs(), thresholds = 0)
  expect_false(is.na(out$youden_j))
})

test_that("calibrate_coverage_filter: missing rank columns gives NA H1/H2 metrics with a warning", {
  df <- .make_ref_pairs()
  df$species.x <- NULL
  df$species.y <- NULL
  expect_warning(
    out <- calibrate_coverage_filter(df, thresholds = 0),
    "could not be detected"
  )
  expect_true(is.na(out$youden_j))
})

test_that("calibrate_coverage_filter: categorical coverage message fires for few unique values", {
  expect_message(
    calibrate_coverage_filter(.make_ref_pairs(),
      rank_system = "species",
      thresholds = c(0, 0.5)
    ),
    "categorical"
  )
})

test_that("calibrate_coverage_filter: validates inputs", {
  expect_error(calibrate_coverage_filter(list()), "must be a data frame")
  expect_error(calibrate_coverage_filter(data.frame(x = 1)), "coverage.*column")
  expect_error(
    calibrate_coverage_filter(data.frame(coverage = 1, p_match = 1)),
    "id_x"
  )
  expect_error(
    calibrate_coverage_filter(.make_ref_pairs(), thresholds = c(NA, 0.5)),
    "thresholds"
  )
})

# ---- coverage_threshold() ---------------------------------------------------

test_that("coverage_threshold: returns the expected quantile for continuous coverage", {
  df <- data.frame(coverage = seq(0, 1, by = 0.01))
  out <- coverage_threshold(df, keep_frac = 0.90)
  expect_equal(out, stats::quantile(df$coverage, probs = 0.10, names = FALSE),
    tolerance = 1e-9
  )
})

test_that("coverage_threshold: snaps to the nearest grade for categorical coverage", {
  df <- data.frame(coverage = rep(c(1.0, 0.8, 0.5, 0.3, 0.1), each = 20L))
  expect_message(
    out <- coverage_threshold(df, keep_frac = 0.80),
    "Snapping"
  )
  expect_true(out %in% unique(df$coverage))
})

test_that("coverage_threshold: higher keep_frac gives a lower or equal threshold", {
  df <- data.frame(coverage = .make_ref_pairs()$coverage)
  t90 <- coverage_threshold(df, keep_frac = 0.90)
  t50 <- coverage_threshold(df, keep_frac = 0.50)
  expect_lte(t90, t50)
})

test_that("coverage_threshold: NA coverage values are ignored", {
  df <- data.frame(coverage = c(NA, 0.5, 0.6, 0.7, 0.8, 0.9))
  expect_no_error(coverage_threshold(df, keep_frac = 0.5))
})

test_that("coverage_threshold: validates inputs", {
  expect_error(coverage_threshold(list()), "must be a data frame")
  expect_error(coverage_threshold(data.frame(x = 1)), "coverage.*column")
  expect_error(
    coverage_threshold(data.frame(coverage = 1), keep_frac = 1.5),
    "\\(0, 1\\)"
  )
  expect_error(
    coverage_threshold(data.frame(coverage = NA_real_)),
    "no non-NA coverage"
  )
})
