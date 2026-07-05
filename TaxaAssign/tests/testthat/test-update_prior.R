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

# ---- spatial_group_map: multi-member vs. single-observation spatial groups ---

test_that("spatial_group_map blocks the boost when the confirming observation is a singleton", {
  result    <- .make_result()
  consensus <- .make_consensus()

  # S1 (the resolved, confirming observation) is in its own single-observation
  # spatial group -- same "spatial_group_<n>" shape as any other group, just
  # with one member -- so it must not confirm anything for S2.
  spatial_group_map <- tibble(
    observation_id   = c("S1", "S2"),
    spatial_group_id = c("spatial_group_1", "spatial_group_2")
  )

  out <- update_prior_from_consensus(result, consensus, presence_multiplier = 5,
                                     n_sims = 0, spatial_group_map = spatial_group_map)

  # No spatial group has >= 2 members, so nothing is eligible; result unchanged.
  expect_equal(nrow(out), nrow(result))
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_equal(s2_sp_a$prior_mean, 0.5)
})

test_that("spatial_group_map allows the boost when S1 and S2 share a spatial group", {
  result    <- .make_result()
  consensus <- .make_consensus()

  spatial_group_map <- tibble(
    observation_id   = c("S1", "S2"),
    spatial_group_id = c("spatial_group_1", "spatial_group_1")
  )

  out <- update_prior_from_consensus(result, consensus, presence_multiplier = 5,
                                     n_sims = 0, spatial_group_map = spatial_group_map)

  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_true(nrow(s2_sp_a) == 1L)
  expect_true(s2_sp_a$prior_updated)
})

test_that("an unresolved observation in a single-observation spatial group is skipped even if another spatial group confirms the species", {
  result <- bind_rows(
    .make_result(),
    tibble(
      observation_id       = "S3",
      taxon_name           = c("Sp_A", "Sp_D"),
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      score_likelihood     = c(0.5, 0.5),
      score_likelihood_mean = c(0.5, 0.5),
      score_likelihood_sd  = c(0.05, 0.05),
      prior_mean           = c(0.5, 0.5),
      prior_alpha          = c(5, 5),
      prior_beta           = c(5, 5),
      posterior_point_est  = c(0.5, 0.5),
      posterior_mean       = c(0.5, 0.5),
      posterior_sd         = c(0.05, 0.05),
      confidence_score     = c(0.5, 0.5),
      genus                = c("GenA", "GenD"),
      family               = c("FamA", "FamD"),
      species              = c("Sp_A", "Sp_D")
    )
  )
  consensus <- bind_rows(
    .make_consensus(),
    tibble(observation_id = "S3", consensus_taxon = NA, consensus_rank = NA,
           is_resolved = FALSE, n_plausible = 2L)
  )

  # S1/S2 share a spatial group (confirms Sp_A); S3 is its own single-observation group.
  spatial_group_map <- tibble(
    observation_id   = c("S1", "S2", "S3"),
    spatial_group_id = c("spatial_group_1", "spatial_group_1", "spatial_group_2")
  )

  out <- update_prior_from_consensus(result, consensus, presence_multiplier = 5,
                                     n_sims = 0, spatial_group_map = spatial_group_map)

  s3_sp_a <- out[out$observation_id == "S3" & out$taxon_name == "Sp_A", ]
  expect_equal(s3_sp_a$prior_mean, 0.5)  # unchanged -- S3 is its own spatial group
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_true(s2_sp_a$prior_updated)     # unchanged behavior for the shared-group pair
})

test_that("spatial_group_map missing required columns errors", {
  result    <- .make_result()
  consensus <- .make_consensus()
  bad_map   <- tibble(observation_id = c("S1", "S2"))

  expect_error(
    update_prior_from_consensus(result, consensus, spatial_group_map = bad_map),
    "spatial_group_map missing required column"
  )
})
