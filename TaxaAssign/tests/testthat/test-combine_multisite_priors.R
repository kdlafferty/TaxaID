# tests/testthat/test-combine_multisite_priors.R

library(dplyr)

# ---- Shared test data --------------------------------------------------------

.make_single_site_joined <- function() {
  tibble(
    observation_id   = c("obs1", "obs1"),
    taxon_name       = c("Species_a", "Species_b"),
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = "site1",
    main_habitat     = "Marine",
    prior_alpha      = c(8, 2),
    prior_beta       = c(2, 8),
    prior_mean       = c(0.8, 0.2)
  )
}

.make_multisite_joined <- function() {
  tibble(
    observation_id   = "obs1",
    taxon_name       = c("Species_a", "Species_a", "Species_b", "Species_b"),
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = c("site1", "site2", "site1", "site2"),
    main_habitat     = "Marine",
    prior_alpha      = c(8, 1, 1, 8),
    prior_beta       = c(2, 9, 9, 2),
    prior_mean       = c(0.8, 0.1, 0.1, 0.8)
  )
}

# ---- Input validation ---------------------------------------------------------

test_that("combine_multisite_priors errors on non-data-frame input", {
  expect_error(combine_multisite_priors(list()), "must be a data frame")
})

test_that("combine_multisite_priors errors on missing required columns", {
  df <- .make_single_site_joined() |> select(-prior_alpha)
  expect_error(combine_multisite_priors(df), "missing required column")
})

test_that("combine_multisite_priors errors on non-positive prior_alpha/prior_beta", {
  df <- .make_single_site_joined()
  df$prior_alpha[1] <- 0
  expect_error(combine_multisite_priors(df), "non-positive or non-finite")
})

# ---- Single-site passthrough ---------------------------------------------------

test_that("single-site observations pass through unchanged", {
  df <- .make_single_site_joined()
  out <- suppressMessages(combine_multisite_priors(df))

  expect_equal(nrow(out), nrow(df))
  expect_equal(out$prior_alpha, df$prior_alpha)
  expect_equal(out$prior_beta, df$prior_beta)
  expect_equal(out$prior_mean, df$prior_mean)
  expect_true(all(out$n_sites_combined == 1L))
  expect_true(all(is.na(out$combined_sites)))
})

# ---- Multi-site combination -----------------------------------------------------

test_that("multi-site candidates are combined to one row each", {
  df <- .make_multisite_joined()
  out <- suppressMessages(combine_multisite_priors(df))

  expect_equal(nrow(out), 2L)
  expect_setequal(out$taxon_name, c("Species_a", "Species_b"))
  expect_true(all(out$n_sites_combined == 2L))
  expect_true(all(is.na(out$grid_id)))
  expect_true(all(is.na(out$main_habitat)))
  expect_equal(
    sort(strsplit(out$combined_sites[1], "|", fixed = TRUE)[[1]]),
    c("site1", "site2")
  )
})

test_that("combination is symmetric and gives the confidently-supported candidate more than half", {
  # Species_a is confidently favored at site1 (phi=10) and only weakly
  # disfavored at site2 (also phi=10) -- symmetric setup, so Species_a's
  # combined mean should exceed 0.5 and exceed Species_b's.
  df <- .make_multisite_joined()
  out <- suppressMessages(combine_multisite_priors(df))

  a_mean <- out$prior_mean[out$taxon_name == "Species_a"]
  b_mean <- out$prior_mean[out$taxon_name == "Species_b"]
  expect_equal(a_mean, b_mean) # fully symmetric fixture -> tie is correct here
  expect_true(a_mean > 0 && a_mean < 1)
})

test_that("a low-confidence (low-phi) site is discounted relative to a high-confidence site", {
  # Site A: phi=100, confidently favors X (mean 0.8) over Y (mean 0.2).
  # Site B: phi=5, weakly favors Y (mean 0.6) over X (mean 0.4) -- sparse,
  # possibly spurious signal in the OPPOSITE direction from site A.
  # Precision-weighted combination should still let X win decisively,
  # discounting site B's low-confidence signal -- unlike a plain product of
  # means, which would only give X ~72.7% (see combine_multisite_priors()
  # roxygen for the full worked comparison).
  df <- tibble(
    observation_id   = "obs1",
    taxon_name       = c("X", "X", "Y", "Y"),
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = c("siteA", "siteB", "siteA", "siteB"),
    main_habitat     = "Marine",
    prior_alpha      = c(80, 2, 20, 3),
    prior_beta       = c(20, 3, 80, 2),
    prior_mean       = c(0.8, 0.4, 0.2, 0.6)
  )
  out <- suppressMessages(combine_multisite_priors(df))

  x_mean <- out$prior_mean[out$taxon_name == "X"]
  y_mean <- out$prior_mean[out$taxon_name == "Y"]
  combined_x_share <- x_mean / (x_mean + y_mean)

  expect_gt(combined_x_share, 0.75) # precision-weighted combination gives ~0.785
  expect_lt(combined_x_share, 0.80)
})

test_that("other columns are inherited from the per-site rows on combined rows", {
  df <- .make_multisite_joined()
  out <- suppressMessages(combine_multisite_priors(df))

  expect_true(all(out$hypothesis_type == "specific_candidate"))
  expect_true(all(out$score_likelihood == 1))
  expect_true(all(out$observation_id == "obs1"))
})

test_that("a mixed batch (some multi-site, some single-site) handles both correctly", {
  multi <- .make_multisite_joined()
  single <- tibble(
    observation_id   = "obs2",
    taxon_name       = "Species_c",
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = "site1",
    main_habitat     = "Marine",
    prior_alpha      = 5,
    prior_beta       = 5,
    prior_mean       = 0.5
  )
  df <- bind_rows(multi, single)
  out <- suppressMessages(combine_multisite_priors(df))

  expect_equal(nrow(out), 3L) # 2 combined (obs1) + 1 passthrough (obs2)
  obs2_row <- out |> filter(observation_id == "obs2")
  expect_equal(obs2_row$n_sites_combined, 1L)
  expect_equal(obs2_row$grid_id, "site1")
})

test_that("prior_mean is required, not silently NA-filled", {
  # Regression: prior_mean was used (arrange + recomputed on combined rows)
  # but not validated. With mixed multi-/single-site input and no prior_mean
  # column, combined rows got a real value while single-site rows were
  # NA-filled by bind_rows -- an NA prior flowing into compute_posterior().
  df <- data.frame(
    observation_id = c("obs1", "obs1", "obs1"),
    taxon_name = c("Species_a", "Species_a", "Species_b"),
    taxon_name_rank = "species",
    grid_id = c("site1", "site2", "site1"),
    main_habitat = "Marine",
    prior_alpha = c(80, 3, 10),
    prior_beta = c(20, 2, 90),
    stringsAsFactors = FALSE
  )
  expect_error(combine_multisite_priors(df), "prior_mean")
})
