# test-fit_regional_presence_curve.R
# D5: per-dataset distance-to-presence calibration for regional-proximity weights.

library(testthat)

test_that("recovers known w_scale/d_half from synthetic data", {
  set.seed(42)
  n <- 4000
  d <- runif(n, 0, 1000)
  p <- 0.4 * exp(-d / 200)
  df <- data.frame(present = runif(n) < p, distance_km = d)
  fitted <- suppressMessages(fit_regional_presence_curve(df))
  expect_true(fitted$identifiable)
  expect_equal(fitted$w_scale, 0.4, tolerance = 0.15)
  expect_equal(fitted$d_half, 200, tolerance = 0.25 * 200)
})

test_that("zero positives returns bounds, not a curve (the GreatLakes case)", {
  df <- data.frame(present = rep(FALSE, 110),
                   distance_km = seq(12, 990, length.out = 110))
  expect_message(fitted <- fit_regional_presence_curve(df), "not identifiable")
  expect_false(fitted$identifiable)
  expect_true(is.na(fitted$w_scale))
  expect_true("pooled" %in% fitted$bin_table$bin)
  pooled_ub <- fitted$bin_table$jeffreys_ub_95[fitted$bin_table$bin == "pooled"]
  expect_equal(pooled_ub, qbeta(0.975, 0.5, 110.5), tolerance = 1e-8)
  expect_lt(pooled_ub, 0.04)  # the real dataset's ~0.027-scale bound
})

test_that("an increasing (wrong-direction) relationship is refused, with bounds", {
  set.seed(7)
  d <- runif(500, 0, 1000)
  p <- 0.01 + 0.3 * d / 1000  # presence INCREASES with distance -- nonsense fit
  df <- data.frame(present = runif(500) < p, distance_km = d)
  fitted <- suppressMessages(fit_regional_presence_curve(df))
  expect_false(fitted$identifiable)
})

test_that("input validation", {
  expect_error(fit_regional_presence_curve(data.frame(x = 1)), "presence_df")
  expect_error(fit_regional_presence_curve(
    data.frame(present = 1, distance_km = 10)), "logical")
})
