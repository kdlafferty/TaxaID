# tests/testthat/test-join_priors.R

library(dplyr)

# ---- Shared test data --------------------------------------------------------

.make_likelihoods <- function() {
  tibble(
    observation_id            = rep("ESV_001", 3),
    taxon_name           = c("Fundulus parvipinnis", "Fundulus lima", "Fundulidae"),
    taxon_name_rank      = c("species", "species", "family"),
    hypothesis_type      = c("specific_candidate", "specific_candidate", "unreferenced_genus"),
    likelihood_point_est = c(0.8, 0.3, 0.1),
    likelihood_mean      = c(0.8, 0.3, 0.1),
    likelihood_sd        = c(0.05, 0.04, 0.02),
    genus                = c("Fundulus", "Fundulus", NA),
    family               = c("Fundulidae", "Fundulidae", "Fundulidae"),
    species              = c("Fundulus parvipinnis", "Fundulus lima", NA)
  )
}

.make_priors <- function() {
  tibble(
    taxon_name      = c("Fundulus parvipinnis", "Fundulus lima", "undetected_placeholder"),
    taxon_name_rank = c("species", "species", "species"),
    grid_id         = "Grid_34p1_m119p1",
    main_habitat    = "Estuarine Bay",
    alpha           = c(5, 2, 0.5),
    beta            = c(5, 8, 9.5),
    undetected_type = c(NA, NA, "tier3")
  )
}

# ---- Input validation --------------------------------------------------------

test_that("join_priors errors on non-data-frame likelihoods", {
  expect_error(
    join_priors(list(), .make_priors(),
                site = list(grid_id = "G", main_habitat = "H")),
    "must be a data frame"
  )
})

test_that("join_priors errors on missing columns in likelihoods", {
  lik <- .make_likelihoods() |> select(-taxon_name)
  expect_error(
    join_priors(lik, .make_priors(),
                site = list(grid_id = "Grid_34p1_m119p1",
                            main_habitat = "Estuarine Bay")),
    "missing required column"
  )
})

test_that("join_priors errors on missing site elements", {
  expect_error(
    join_priors(.make_likelihoods(), .make_priors(),
                site = list(grid_id = "G")),
    "missing element"
  )
})

# ---- Single-site mode -------------------------------------------------------

test_that("join_priors works in single-site mode", {
  lik <- .make_likelihoods()
  pri <- .make_priors()
  site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine Bay")

  out <- suppressMessages(join_priors(lik, pri, site = site))

  expect_s3_class(out, "data.frame")
  expect_true(all(c("prior_mean", "prior_alpha", "prior_beta") %in% names(out)))
  # All rows should have non-NA prior_mean
  expect_true(all(!is.na(out$prior_mean)))
})

# ---- Multi-site mode --------------------------------------------------------

test_that("join_priors works in multi-site mode", {
  lik <- .make_likelihoods()
  pri <- .make_priors()
  site_df <- data.frame(
    observation_id    = "ESV_001",
    grid_id      = "Grid_34p1_m119p1",
    main_habitat = "Estuarine Bay",
    stringsAsFactors = FALSE
  )

  out <- suppressMessages(join_priors(lik, pri, site = site_df))
  expect_s3_class(out, "data.frame")
  expect_true(all(c("prior_mean", "prior_alpha", "prior_beta") %in% names(out)))
})
