.toy_scored_df <- function() {
  data.frame(
    observation_id = c("obs1", "obs1", "obs2"),
    taxon_name = c("Turdus migratorius", "Turdus merula", "Limosa fedoa"),
    score_original = c(0.9, 0.85, 0.6),
    n_observations = c(500000, 20, 300),
    stringsAsFactors = FALSE
  )
}

test_that("correct_training_bias: high-n species corrected down relative to low-n (tau = 1)", {
  df <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations", tau = 1)

  # Turdus migratorius (n = 500000) should be corrected down more than
  # Turdus merula (n = 20) -- ratio should shrink toward favoring the rarer species.
  ratio_before <- df$score_original[1] / df$score_original[2]
  ratio_after <- out$score_original[1] / out$score_original[2]
  expect_true(ratio_after < ratio_before)
})

test_that("correct_training_bias: score_uncorrected preserves original values", {
  df <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations", tau = 1)
  expect_equal(out$score_uncorrected, df$score_original)
})

test_that("correct_training_bias: n_used and tau_used are added (tau = 1)", {
  df <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations", tau = 1)
  expect_true(all(c("n_used", "tau_used") %in% names(out)))
  expect_equal(out$n_used, df$n_observations)
  # Every valid-count row gets exactly tau_used = 1, not a continuous
  # per-candidate value (that was the Session 125 adaptive design this
  # revision replaces).
  expect_true(all(out$tau_used == 1))
})

test_that("correct_training_bias: tau = 1 divides score by n exactly", {
  df <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations", tau = 1)
  expect_equal(out$score_original, df$score_original / df$n_observations)
})

test_that("correct_training_bias: default tau = 0 leaves scores unchanged (Session 151)", {
  # Every real calibration run against this function (image, and acoustic on
  # a properly powered re-test) found tau ~= 0 optimal -- the default
  # changed from 1.0 to 0 accordingly, so a caller who does nothing gets no
  # correction rather than one contradicted by every real result so far.
  df <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations")
  expect_equal(out$score_original, df$score_original)
  expect_true(all(out$tau_used == 0))
})

test_that("correct_training_bias: NA count falls through to uncorrected score", {
  df <- .toy_scored_df()
  df$n_observations[3] <- NA_real_
  out <- correct_training_bias(df, count_col = "n_observations", tau = 1)
  expect_equal(out$score_original[3], df$score_original[3])
  expect_equal(out$tau_used[3], 0)
})

test_that("correct_training_bias: zero count falls through to uncorrected score", {
  df <- .toy_scored_df()
  df$n_observations[3] <- 0
  out <- correct_training_bias(df, count_col = "n_observations", tau = 1)
  expect_equal(out$score_original[3], df$score_original[3])
  expect_equal(out$tau_used[3], 0)
})

test_that("correct_training_bias: all-NA counts leave every score unchanged", {
  df <- .toy_scored_df()
  df$n_observations <- NA_real_
  out <- correct_training_bias(df, count_col = "n_observations", tau = 1)
  expect_equal(out$score_original, df$score_original)
  expect_true(all(out$tau_used == 0))
})

test_that("correct_training_bias: missing count_col warns and leaves scores unchanged", {
  df <- .toy_scored_df()
  df$n_observations <- NULL
  expect_warning(
    out <- correct_training_bias(df, count_col = "n_observations"),
    "not found"
  )
  expect_equal(out$score_original, .toy_scored_df()$score_original)
  expect_true(all(is.na(out$n_used)))
})

test_that("correct_training_bias: tau = 0 disables correction entirely", {
  df <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations", tau = 0)
  expect_equal(out$score_original, df$score_original)
  expect_true(all(out$tau_used == 0))
})

test_that("correct_training_bias: tau above 1 applies stronger correction than tau = 1", {
  df <- .toy_scored_df()
  out_tau1 <- correct_training_bias(df, count_col = "n_observations", tau = 1)
  out_tau2 <- correct_training_bias(df, count_col = "n_observations", tau = 2.6)
  # Larger tau -> the high-n candidate is pushed down further still.
  expect_true(out_tau2$score_original[1] < out_tau1$score_original[1])
})

test_that("correct_training_bias: tau is applied uniformly across candidates (not adaptive)", {
  df <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations", tau = 0.5)
  # Both valid-count candidates in obs1 get the SAME tau_used regardless of
  # how different their own n is -- the key behavioral change from the
  # Session 125 adaptive-per-candidate design.
  expect_equal(out$tau_used[1], out$tau_used[2])
  expect_equal(out$tau_used[1], 0.5)
})

test_that("correct_training_bias: errors on non-data-frame input", {
  expect_error(correct_training_bias(list(a = 1), count_col = "n"), "data frame")
})

test_that("correct_training_bias: errors on missing score_col", {
  df <- .toy_scored_df()
  expect_error(
    correct_training_bias(df, count_col = "n_observations", score_col = "nope"),
    "not found"
  )
})

test_that("correct_training_bias: errors on non-numeric score_col", {
  df <- .toy_scored_df()
  df$score_original <- as.character(df$score_original)
  expect_error(
    correct_training_bias(df, count_col = "n_observations"),
    "numeric"
  )
})

test_that("correct_training_bias: errors on negative counts", {
  df <- .toy_scored_df()
  df$n_observations[1] <- -5
  expect_error(
    correct_training_bias(df, count_col = "n_observations"),
    "negative"
  )
})

test_that("correct_training_bias: errors on invalid tau", {
  df <- .toy_scored_df()
  expect_error(
    correct_training_bias(df, count_col = "n_observations", tau = -1),
    "non-negative"
  )
  expect_error(
    correct_training_bias(df, count_col = "n_observations", tau = c(1, 2)),
    "non-negative"
  )
  expect_error(
    correct_training_bias(df, count_col = "n_observations", tau = NA_real_),
    "non-negative"
  )
})
