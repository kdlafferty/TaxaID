# tests/testthat/test-update_prior.R

library(dplyr)

# ---- Shared test data --------------------------------------------------------

.make_result <- function() {
  bind_rows(
    tibble(
      observation_id            = "S1",
      taxon_name           = c("Sp_A", "Sp_B"),
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      score_likelihood = c(0.8, 0.2),
      score_likelihood_mean      = c(0.8, 0.2),
      score_likelihood_sd        = c(0.05, 0.05),
      prior_mean           = c(0.5, 0.5),
      prior_alpha          = c(5, 5),
      prior_beta           = c(5, 5),
      posterior_point_est  = c(0.8, 0.2),
      posterior_mean       = c(0.8, 0.2),
      posterior_sd         = c(0.05, 0.05),
      confidence_score     = c(0.9, 0.1),
      genus                = c("GenA", "GenB"),
      family               = c("FamA", "FamB"),
      species              = c("Sp_A", "Sp_B")
    ),
    tibble(
      observation_id            = "S2",
      taxon_name           = c("Sp_A", "Sp_C"),
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      score_likelihood = c(0.5, 0.5),
      score_likelihood_mean      = c(0.5, 0.5),
      score_likelihood_sd        = c(0.05, 0.05),
      prior_mean           = c(0.5, 0.5),
      prior_alpha          = c(5, 5),
      prior_beta           = c(5, 5),
      posterior_point_est  = c(0.5, 0.5),
      posterior_mean       = c(0.5, 0.5),
      posterior_sd         = c(0.05, 0.05),
      confidence_score     = c(0.5, 0.5),
      genus                = c("GenA", "GenC"),
      family               = c("FamA", "FamC"),
      species              = c("Sp_A", "Sp_C")
    )
  )
}

.make_consensus <- function() {
  tibble(
    observation_id       = c("S1", "S2"),
    consensus_taxon = c("Sp_A", NA),
    consensus_rank  = c("species", NA),
    is_resolved     = c(TRUE, FALSE),
    n_plausible     = c(1L, 2L)
  )
}

# ---- Basic functionality -----------------------------------------------------

test_that("update_prior_from_consensus returns data frame with expected columns", {
  result    <- .make_result()
  consensus <- .make_consensus()

  out <- update_prior_from_consensus(result, consensus,
                                     presence_multiplier = 5, n_sims = 0)
  expect_s3_class(out, "data.frame")
  expect_true("prior_updated" %in% names(out))
  expect_true(nrow(out) >= nrow(result))
})

test_that("update_prior_from_consensus boosts confirmed species in unresolved samples", {
  result    <- .make_result()
  consensus <- .make_consensus()

  out <- update_prior_from_consensus(result, consensus,
                                     presence_multiplier = 5, n_sims = 0)

  # Sp_A confirmed in S1, should get boosted prior in S2
  s2_sp_a <- out |> filter(observation_id == "S2", taxon_name == "Sp_A")
  expect_true(nrow(s2_sp_a) == 1L)
  expect_true(s2_sp_a$prior_updated)
})

test_that("update_prior_from_consensus handles case with no resolved species", {
  result    <- .make_result()
  consensus <- .make_consensus()
  consensus$is_resolved <- FALSE

  out <- update_prior_from_consensus(result, consensus,
                                     presence_multiplier = 5, n_sims = 0)
  expect_s3_class(out, "data.frame")
  # No species should be boosted — prior_updated may not exist or be all FALSE
  if ("prior_updated" %in% names(out)) {
    expect_true(all(!out$prior_updated))
  }
})
