.toy_scored_df <- function() {
  data.frame(
    observation_id = c("obs1", "obs1", "obs2"),
    taxon_name      = c("Turdus migratorius", "Turdus merula", "Limosa fedoa"),
    score_original  = c(0.9, 0.85, 0.6),
    n_observations  = c(500000, 20, 300),
    stringsAsFactors = FALSE
  )
}

test_that("correct_training_bias: high-n species corrected down relative to low-n", {
  df  <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations")

  # Turdus migratorius (n = 500000) should be corrected down more than
  # Turdus merula (n = 20) -- ratio should shrink toward favoring the rarer species.
  ratio_before <- df$score_original[1] / df$score_original[2]
  ratio_after  <- out$score_original[1] / out$score_original[2]
  expect_true(ratio_after < ratio_before)
})

test_that("correct_training_bias: score_uncorrected preserves original values", {
  df  <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations")
  expect_equal(out$score_uncorrected, df$score_original)
})

test_that("correct_training_bias: n_used and tau_used are added", {
  df  <- .toy_scored_df()
  out <- correct_training_bias(df, count_col = "n_observations")
  expect_true(all(c("n_used", "tau_used") %in% names(out)))
  expect_equal(out$n_used, df$n_observations)
  expect_true(all(out$tau_used >= 0 & out$tau_used <= 1))
})

test_that("correct_training_bias: NA count falls through to uncorrected score", {
  df <- .toy_scored_df()
  df$n_observations[3] <- NA_real_
  out <- correct_training_bias(df, count_col = "n_observations")
  expect_equal(out$score_original[3], df$score_original[3])
  expect_equal(out$tau_used[3], 0)
})

test_that("correct_training_bias: zero count falls through to uncorrected score", {
  df <- .toy_scored_df()
  df$n_observations[3] <- 0
  out <- correct_training_bias(df, count_col = "n_observations")
  expect_equal(out$score_original[3], df$score_original[3])
  expect_equal(out$tau_used[3], 0)
})

test_that("correct_training_bias: all-NA counts leave every score unchanged", {
  df <- .toy_scored_df()
  df$n_observations <- NA_real_
  out <- correct_training_bias(df, count_col = "n_observations")
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

test_that("correct_training_bias: default prior_weight is median of counts", {
  df  <- .toy_scored_df()
  out_default <- correct_training_bias(df, count_col = "n_observations")
  out_manual  <- correct_training_bias(df, count_col = "n_observations",
                                        prior_weight = stats::median(df$n_observations))
  expect_equal(out_default$score_original, out_manual$score_original)
})

test_that("correct_training_bias: explicit prior_weight overrides the default", {
  df  <- .toy_scored_df()
  out_small_k <- correct_training_bias(df, count_col = "n_observations", prior_weight = 1)
  out_big_k   <- correct_training_bias(df, count_col = "n_observations", prior_weight = 1e6)
  # Larger prior_weight = less trust in n -> tau closer to 0 -> less correction
  expect_true(out_big_k$tau_used[1] < out_small_k$tau_used[1])
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

test_that("correct_training_bias: errors on invalid prior_weight", {
  df <- .toy_scored_df()
  expect_error(
    correct_training_bias(df, count_col = "n_observations", prior_weight = -1),
    "positive"
  )
  expect_error(
    correct_training_bias(df, count_col = "n_observations", prior_weight = c(1, 2)),
    "positive"
  )
})
