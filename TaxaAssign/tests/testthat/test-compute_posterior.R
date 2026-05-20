# tests/testthat/test-compute_posterior.R
# Updated 2026-04-04: prior_alpha/prior_beta (Beta-distributed priors)
# replaces prior_sd (Normal-distributed priors).

library(dplyr)

# ---------------------------------------------------------------------------
# Shared test data — Beta-distributed priors
# ---------------------------------------------------------------------------

make_test_df <- function() {
  dplyr::bind_rows(

    # Sample A: clear winner (high phi = tight priors)
    dplyr::tibble(
      observation_id            = "Sample_A",
      taxon_name           = c("Gadus morhua", "Gadus chalcogrammus", "Gadus"),
      hypothesis_type      = c("specific_candidate", "specific_candidate",
                               "unreferenced_species"),
      likelihood_point_est = c(0.85, 0.30, 0.10),
      likelihood_mean      = c(0.83, 0.31, 0.10),
      likelihood_sd        = c(0.05, 0.04, 0.02),
      prior_mean           = c(0.60, 0.30, 0.10),
      prior_alpha          = c(30.0, 15.0, 5.0),
      prior_beta           = c(20.0, 35.0, 45.0)
    ),

    # Sample B: two strong candidates (ambiguous, moderate phi)
    dplyr::tibble(
      observation_id            = "Sample_B",
      taxon_name           = c("Salmo salar", "Salmo trutta", "Salmo"),
      hypothesis_type      = c("specific_candidate", "specific_candidate",
                               "unreferenced_species"),
      likelihood_point_est = c(0.70, 0.65, 0.10),
      likelihood_mean      = c(0.68, 0.64, 0.10),
      likelihood_sd        = c(0.08, 0.08, 0.02),
      prior_mean           = c(0.50, 0.40, 0.10),
      prior_alpha          = c(5.0, 4.0, 1.0),
      prior_beta           = c(5.0, 6.0, 9.0)
    ),

    # Sample C: 5 hypotheses (mixed phi)
    dplyr::tibble(
      observation_id            = "Sample_C",
      taxon_name           = c("Thunnus thynnus", "Thunnus albacares",
                               "Thunnus obesus", "Thunnus", "Scombridae"),
      hypothesis_type      = c(rep("specific_candidate", 3),
                               "unreferenced_species", "unreferenced_genus"),
      likelihood_point_est = c(0.90, 0.40, 0.20, 0.05, 0.02),
      likelihood_mean      = c(0.88, 0.41, 0.21, 0.05, 0.02),
      likelihood_sd        = c(0.06, 0.05, 0.04, 0.01, 0.01),
      prior_mean           = c(0.50, 0.25, 0.15, 0.07, 0.03),
      prior_alpha          = c(25.0, 12.5, 7.5, 3.5, 1.5),
      prior_beta           = c(25.0, 37.5, 42.5, 46.5, 48.5)
    )
  )
}

# ---------------------------------------------------------------------------
# Test 1: Output shape, sums-to-1, output columns present (Beta priors)
# ---------------------------------------------------------------------------

test_that("compute_posterior returns correct structure with Beta priors", {
  df     <- make_test_df()
  result <- compute_posterior(df, n_sims = 500L)

  # Output columns present
  expect_true(all(c("posterior_point_est", "posterior_mean",
                    "posterior_sd", "confidence_score") %in% names(result)))

  # Pass-through columns unchanged
  expect_true(all(c("taxon_name", "hypothesis_type") %in% names(result)))

  # Same number of rows as input
  expect_equal(nrow(result), nrow(df))

  # Posteriors sum to 1 within each observation_id (point estimate)
  sums_pt <- result |>
    dplyr::group_by(observation_id) |>
    dplyr::summarise(s = sum(posterior_point_est), .groups = "drop")
  expect_true(all(abs(sums_pt$s - 1) < 1e-9))

  # Posteriors sum to 1 within each observation_id (mean)
  sums_mn <- result |>
    dplyr::group_by(observation_id) |>
    dplyr::summarise(s = sum(posterior_mean), .groups = "drop")
  expect_true(all(abs(sums_mn$s - 1) < 1e-6))

  # Posteriors are non-negative
  expect_true(all(result$posterior_point_est >= 0))
  expect_true(all(result$posterior_mean      >= 0))

  # confidence_score in [0, 1]
  expect_true(all(result$confidence_score >= 0 & result$confidence_score <= 1))
})

# ---------------------------------------------------------------------------
# Test 2: Beta priors produce non-zero posterior_sd
# ---------------------------------------------------------------------------

test_that("Beta priors propagate uncertainty into posterior_sd", {
  df     <- make_test_df()
  result <- compute_posterior(df, n_sims = 1000L)

  # With Beta priors + likelihood SD, posterior_sd should be > 0
  expect_true(all(result$posterior_sd > 0))
})

# ---------------------------------------------------------------------------
# Test 3: No alpha/beta — priors treated as fixed, no prior uncertainty
# ---------------------------------------------------------------------------

test_that("compute_posterior with no alpha/beta treats priors as fixed", {
  df     <- make_test_df() |> dplyr::select(-prior_alpha, -prior_beta)

  # Also set likelihood_sd to 0 so there's no uncertainty at all
  df$likelihood_sd <- 0
  result <- suppressMessages(compute_posterior(df, n_sims = 1000L))

  expect_true(all(abs(result$posterior_mean - result$posterior_point_est) < 1e-10))
  expect_true(all(result$posterior_sd == 0))
})

# ---------------------------------------------------------------------------
# Test 4: No alpha/beta but nonzero likelihood_sd — MC still runs for likelihoods
# ---------------------------------------------------------------------------

test_that("MC runs for likelihood uncertainty even without Beta priors", {
  df <- make_test_df() |> dplyr::select(-prior_alpha, -prior_beta)
  result <- suppressMessages(compute_posterior(df, n_sims = 500L))

  # posterior_sd should be > 0 from likelihood uncertainty alone
  expect_true(any(result$posterior_sd > 0))
})

# ---------------------------------------------------------------------------
# Test 5: n_sims = 0 — point estimate path only; posterior_sd = 0
# ---------------------------------------------------------------------------

test_that("compute_posterior with n_sims = 0 uses point estimate path only", {
  df     <- make_test_df()
  result <- compute_posterior(df, n_sims = 0L)

  expect_true(all(abs(result$posterior_mean - result$posterior_point_est) < 1e-10))
  expect_true(all(result$posterior_sd == 0))

  # confidence_score: 1 for top hypothesis per sample, 0 otherwise
  top_flags <- result |>
    dplyr::group_by(observation_id) |>
    dplyr::mutate(is_top = posterior_mean == max(posterior_mean)) |>
    dplyr::ungroup()
  expect_true(all(top_flags$confidence_score[top_flags$is_top]  == 1))
  expect_true(all(top_flags$confidence_score[!top_flags$is_top] == 0))
})

# ---------------------------------------------------------------------------
# Test 6: Missing required columns — informative error
# ---------------------------------------------------------------------------

test_that("compute_posterior errors informatively on missing required columns", {
  df_bad <- make_test_df() |> dplyr::select(-likelihood_sd, -prior_mean)

  expect_error(compute_posterior(df_bad), regexp = "likelihood_sd|prior_mean")
})

# ---------------------------------------------------------------------------
# Test 7: NA values in likelihood_sd — replaced with 0, warning emitted
# ---------------------------------------------------------------------------

test_that("compute_posterior replaces NA likelihood_sd with 0 and warns", {
  df        <- make_test_df()
  df$likelihood_sd[c(1L, 4L)] <- NA

  expect_warning(
    result <- compute_posterior(df, n_sims = 0L),
    regexp = "NA"
  )
  expect_false(anyNA(result$likelihood_sd))
})

# ---------------------------------------------------------------------------
# Test 8: Single-hypothesis sample — posterior = 1
# ---------------------------------------------------------------------------

test_that("compute_posterior assigns posterior = 1 when only one hypothesis", {
  df <- dplyr::tibble(
    observation_id            = "Solo",
    taxon_name           = "Gadus morhua",
    hypothesis_type      = "specific_candidate",
    likelihood_point_est = 0.75,
    likelihood_mean      = 0.75,
    likelihood_sd        = 0.0,
    prior_mean           = 0.5
  )
  result <- suppressMessages(compute_posterior(df, n_sims = 0L))

  expect_equal(result$posterior_point_est, 1)
  expect_equal(result$posterior_mean,      1)
})

# ---------------------------------------------------------------------------
# Test 9: Output sorted — observation_id ascending, posterior_mean descending
# ---------------------------------------------------------------------------

test_that("compute_posterior output is sorted by observation_id asc then posterior_mean desc", {
  result <- compute_posterior(make_test_df(), n_sims = 0L)

  sorted_check <- result |>
    dplyr::group_by(observation_id) |>
    dplyr::summarise(
      is_desc = all(diff(posterior_mean) <= 0),
      .groups = "drop"
    )
  expect_true(all(sorted_check$is_desc))
  expect_equal(result$observation_id, sort(result$observation_id))
})

# ---------------------------------------------------------------------------
# Test 10: Only one of prior_alpha/prior_beta — error
# ---------------------------------------------------------------------------

test_that("compute_posterior errors when only one of alpha/beta is present", {
  df_alpha_only <- make_test_df() |> dplyr::select(-prior_beta)
  expect_error(compute_posterior(df_alpha_only), regexp = "prior_alpha.*prior_beta")

  df_beta_only <- make_test_df() |> dplyr::select(-prior_alpha)
  expect_error(compute_posterior(df_beta_only), regexp = "prior_alpha.*prior_beta")
})

# ---------------------------------------------------------------------------
# Test 11: Invalid alpha/beta values — error
# ---------------------------------------------------------------------------

test_that("compute_posterior errors on non-positive alpha/beta", {
  df <- make_test_df()
  df$prior_alpha[1] <- 0
  expect_error(compute_posterior(df), regexp = "non-positive")

  df2 <- make_test_df()
  df2$prior_beta[2] <- -1
  expect_error(compute_posterior(df2), regexp = "non-positive")
})

# ---------------------------------------------------------------------------
# Test 12: High phi (tight priors) vs low phi (diffuse priors)
# ---------------------------------------------------------------------------

test_that("higher phi produces lower posterior_sd than lower phi", {
  # Tight priors: phi = 100
  df_tight <- dplyr::tibble(
    observation_id            = rep("S1", 2),
    taxon_name           = c("Sp_A", "Sp_B"),
    hypothesis_type      = "specific_candidate",
    likelihood_point_est = c(0.6, 0.4),
    likelihood_mean      = c(0.6, 0.4),
    likelihood_sd        = c(0.05, 0.05),
    prior_mean           = c(0.7, 0.3),
    prior_alpha          = c(70, 30),
    prior_beta           = c(30, 70)
  )

  # Diffuse priors: phi = 3
  df_diffuse <- dplyr::tibble(
    observation_id            = rep("S1", 2),
    taxon_name           = c("Sp_A", "Sp_B"),
    hypothesis_type      = "specific_candidate",
    likelihood_point_est = c(0.6, 0.4),
    likelihood_mean      = c(0.6, 0.4),
    likelihood_sd        = c(0.05, 0.05),
    prior_mean           = c(0.7, 0.3),
    prior_alpha          = c(2.1, 0.9),
    prior_beta           = c(0.9, 2.1)
  )

  set.seed(42)
  res_tight   <- compute_posterior(df_tight,   n_sims = 2000L)
  set.seed(42)
  res_diffuse <- compute_posterior(df_diffuse, n_sims = 2000L)

  # Tight priors should give smaller posterior SD
  mean_sd_tight   <- mean(res_tight$posterior_sd)
  mean_sd_diffuse <- mean(res_diffuse$posterior_sd)
  expect_true(mean_sd_tight < mean_sd_diffuse)
})
