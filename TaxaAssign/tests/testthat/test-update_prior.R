# tests/testthat/test-update_prior.R
# Session 149: rewritten for the confirmation-quantile design (replaces the
# old fixed presence_multiplier). See update_prior_from_consensus.R's
# "Confirmation-quantile design" roxygen section for the full rationale.

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

# consensus_posterior default 0.9 for the confirming S1 row -- comfortably
# above the default min_confirmation_confidence (0.8) so "boost happens"
# tests exercise the intended path without also depending on the gate.
.make_consensus <- function(s1_posterior = 0.9) {
  tibble(
    observation_id       = c("S1", "S2"),
    consensus_taxon      = c("Sp_A", NA),
    consensus_rank       = c("species", NA),
    is_resolved          = c(TRUE, FALSE),
    consensus_posterior  = c(s1_posterior, NA),
    n_plausible          = c(1L, 2L)
  )
}

# ---- Basic functionality -----------------------------------------------------

test_that("update_prior_from_consensus returns data frame with expected columns", {
  result    <- .make_result()
  consensus <- .make_consensus()

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  expect_s3_class(out, "data.frame")
  expect_true("prior_updated" %in% names(out))
  expect_true(nrow(out) >= nrow(result))
})

test_that("update_prior_from_consensus boosts confirmed species in unresolved samples", {
  result    <- .make_result()
  consensus <- .make_consensus()

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)

  # Sp_A confirmed in S1 at posterior 0.9 (clears the default gate); should be
  # boosted (substituted, not multiplied) in S2 since 0.9 > the existing 0.5.
  s2_sp_a <- out |> filter(observation_id == "S2", taxon_name == "Sp_A")
  expect_true(nrow(s2_sp_a) == 1L)
  expect_true(s2_sp_a$prior_updated)
  expect_equal(s2_sp_a$prior_mean, 0.9)
})

test_that("update_prior_from_consensus handles case with no resolved species", {
  result    <- .make_result()
  consensus <- .make_consensus()
  consensus$is_resolved <- FALSE

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  expect_s3_class(out, "data.frame")
  # No species should be boosted — prior_updated may not exist or be all FALSE
  if ("prior_updated" %in% names(out)) {
    expect_true(all(!out$prior_updated))
  }
})

# ---- min_confirmation_confidence gate ----------------------------------------

test_that("a confirmation below min_confirmation_confidence is not used by default", {
  result    <- .make_result()
  consensus <- .make_consensus(s1_posterior = 0.6)  # resolved, but weakly so

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)

  # Default min_confirmation_confidence = 0.8; 0.6 doesn't clear it -> unchanged.
  expect_equal(nrow(out), nrow(result))
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_equal(s2_sp_a$prior_mean, 0.5)
})

test_that("min_confirmation_confidence = 0 disables the gate entirely", {
  result    <- .make_result()
  consensus <- .make_consensus(s1_posterior = 0.6)

  out <- update_prior_from_consensus(result, consensus, n_sims = 0,
                                     min_confirmation_confidence = 0)

  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_true(s2_sp_a$prior_updated)
  expect_equal(s2_sp_a$prior_mean, 0.6)
})

# ---- never-demote guard -------------------------------------------------------

test_that("never-demote: an existing prior above the confirmation quantile is left unchanged", {
  result    <- .make_result()
  result$prior_mean[result$observation_id == "S2" & result$taxon_name == "Sp_A"] <- 0.95
  consensus <- .make_consensus(s1_posterior = 0.9)  # would only raise to 0.9

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)

  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  # 0.9 < 0.95, so prior_mean must stay at 0.95 (not lowered)
  expect_equal(s2_sp_a$prior_mean, 0.95)
})

# ---- confirmation_quantile across multiple donors ----------------------------

test_that("confirmation_quantile combines multiple donor observations correctly", {
  result <- bind_rows(
    .make_result(),
    tibble(
      observation_id       = "S3",
      taxon_name           = "Sp_A",
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      score_likelihood     = 1.0,
      score_likelihood_mean = 1.0,
      score_likelihood_sd  = 0,
      prior_mean           = 0.4,
      prior_alpha          = 4,
      prior_beta           = 6,
      posterior_point_est  = 1.0,
      posterior_mean       = 1.0,
      posterior_sd         = 0,
      confidence_score     = 1.0,
      genus = "GenA", family = "FamA", species = "Sp_A"
    )
  )
  # Two donors confirming Sp_A: S1 at 0.90, S4 at 0.95 (S4 has no hypothesis
  # rows in `result` -- only its consensus counts as a donor). S3 needs its
  # own (unresolved) consensus row to be eligible for the boost at all.
  consensus <- bind_rows(
    .make_consensus(s1_posterior = 0.90),
    tibble(observation_id = "S3", consensus_taxon = NA, consensus_rank = NA,
           is_resolved = FALSE, consensus_posterior = NA, n_plausible = 1L),
    tibble(observation_id = "S4", consensus_taxon = "Sp_A", consensus_rank = "species",
           is_resolved = TRUE, consensus_posterior = 0.95, n_plausible = 1L)
  )

  expected_q90 <- stats::quantile(c(0.90, 0.95), probs = 0.9, names = FALSE)

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  s3_sp_a <- out[out$observation_id == "S3" & out$taxon_name == "Sp_A", ]
  expect_equal(s3_sp_a$prior_mean, expected_q90)
})

# ---- prior_alpha/prior_beta consistency (Session 149 latent-bug fix) --------

test_that("prior_alpha/prior_beta are recomputed consistently with a boosted prior_mean", {
  result    <- .make_result()
  consensus <- .make_consensus(s1_posterior = 0.9)

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  phi <- 5 + 5  # original prior_alpha + prior_beta for this row
  expect_equal(s2_sp_a$prior_alpha, 0.9 * phi)
  expect_equal(s2_sp_a$prior_beta,  0.1 * phi)
  # Mean implied by the recomputed Beta matches the boosted prior_mean exactly
  expect_equal(s2_sp_a$prior_alpha / (s2_sp_a$prior_alpha + s2_sp_a$prior_beta),
               s2_sp_a$prior_mean)
})

test_that("a confirmation_quantile of exactly 1.0 does not produce a zero prior_beta", {
  # consensus_posterior = 1.0 is a real, common value -- any unambiguously
  # resolved single-candidate donor observation produces it. Before the
  # boundary clamp, new_beta = (1 - 1) * phi = 0, which compute_posterior()
  # rejects (Session 152 bug, found live in PtConceptionWorkflow_12S.R).
  result    <- .make_result()
  consensus <- .make_consensus(s1_posterior = 1.0)

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  expect_equal(s2_sp_a$prior_mean, 1.0)
  expect_true(is.finite(s2_sp_a$prior_alpha) && s2_sp_a$prior_alpha > 0)
  expect_true(is.finite(s2_sp_a$prior_beta)  && s2_sp_a$prior_beta  > 0)

  # compute_posterior() must accept the recomputed Beta shape without erroring,
  # including on the Monte Carlo path (n_sims > 0), which is what the real
  # failure surfaced on.
  expect_no_error(update_prior_from_consensus(result, consensus, n_sims = 100))
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

  out <- update_prior_from_consensus(result, consensus, n_sims = 0,
                                     spatial_group_map = spatial_group_map)

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

  out <- update_prior_from_consensus(result, consensus, n_sims = 0,
                                     spatial_group_map = spatial_group_map)

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
           is_resolved = FALSE, consensus_posterior = NA, n_plausible = 2L)
  )

  # S1/S2 share a spatial group (confirms Sp_A); S3 is its own single-observation group.
  spatial_group_map <- tibble(
    observation_id   = c("S1", "S2", "S3"),
    spatial_group_id = c("spatial_group_1", "spatial_group_1", "spatial_group_2")
  )

  out <- update_prior_from_consensus(result, consensus, n_sims = 0,
                                     spatial_group_map = spatial_group_map)

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

# ---- Input validation ---------------------------------------------------------

test_that("consensus missing consensus_posterior errors", {
  result    <- .make_result()
  consensus <- .make_consensus()
  consensus$consensus_posterior <- NULL

  expect_error(
    update_prior_from_consensus(result, consensus),
    "consensus_posterior"
  )
})

test_that("confirmation_quantile must be in (0, 1]", {
  result    <- .make_result()
  consensus <- .make_consensus()

  expect_error(
    update_prior_from_consensus(result, consensus, confirmation_quantile = 0),
    "confirmation_quantile"
  )
  expect_error(
    update_prior_from_consensus(result, consensus, confirmation_quantile = 1.5),
    "confirmation_quantile"
  )
})

test_that("min_confirmation_confidence must be in [0, 1]", {
  result    <- .make_result()
  consensus <- .make_consensus()

  expect_error(
    update_prior_from_consensus(result, consensus, min_confirmation_confidence = -0.1),
    "min_confirmation_confidence"
  )
  expect_error(
    update_prior_from_consensus(result, consensus, min_confirmation_confidence = 1.1),
    "min_confirmation_confidence"
  )
})

# ==============================================================================
# Rescaling onto the occurrence scale + confirmed_without_occurrence_record
# (2026-07-30, Task 0b/0c)
# ==============================================================================
# S1 confirms Sp_A (has a real theta_mean/occurrence record); S3 confirms
# Sp_D (theta_mean NA everywhere -- no occurrence record at all, e.g. the
# real Oncorhynchus mykiss case). S2 is unresolved and carries both as
# candidates, so both boost paths are exercised side by side.

.make_result_theta <- function() {
  bind_rows(
    tibble(
      observation_id      = "S1",
      taxon_name           = c("Sp_A", "Sp_B"),
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      score_likelihood     = c(0.8, 0.2),
      score_likelihood_mean = c(0.8, 0.2),
      score_likelihood_sd   = c(0.05, 0.05),
      prior_mean           = c(0.5, 0.5),
      theta_mean           = c(0.05, 0.01),
      prior_alpha          = c(5, 5),
      prior_beta           = c(5, 5),
      posterior_point_est  = c(0.95, 0.05),
      posterior_mean       = c(0.95, 0.05),
      posterior_sd         = c(0.02, 0.02),
      confidence_score     = c(0.95, 0.05)
    ),
    tibble(
      observation_id      = "S2",
      taxon_name           = c("Sp_A", "Sp_D"),
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      score_likelihood     = c(0.5, 0.5),
      score_likelihood_mean = c(0.5, 0.5),
      score_likelihood_sd   = c(0.05, 0.05),
      prior_mean           = c(0.001, 0.0005),
      theta_mean           = c(0.05, NA_real_),
      prior_alpha          = c(5, 5),
      prior_beta           = c(5, 5),
      posterior_point_est  = c(0.5, 0.5),
      posterior_mean       = c(0.5, 0.5),
      posterior_sd         = c(0.05, 0.05),
      confidence_score     = c(0.5, 0.5)
    ),
    tibble(
      observation_id      = "S3",
      taxon_name           = c("Sp_D", "Sp_E"),
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      score_likelihood     = c(0.95, 0.05),
      score_likelihood_mean = c(0.95, 0.05),
      score_likelihood_sd   = c(0.02, 0.02),
      prior_mean           = c(0.0005, 0.5),
      theta_mean           = c(NA_real_, 0.02),
      prior_alpha          = c(5, 5),
      prior_beta           = c(5, 5),
      posterior_point_est  = c(0.95, 0.05),
      posterior_mean       = c(0.95, 0.05),
      posterior_sd         = c(0.02, 0.02),
      confidence_score     = c(0.95, 0.05)
    )
  )
}

.make_consensus_theta <- function() {
  tibble(
    observation_id       = c("S1", "S2", "S3"),
    consensus_taxon      = c("Sp_A", NA, "Sp_D"),
    consensus_rank       = c("species", NA, "species"),
    is_resolved          = c(TRUE, FALSE, TRUE),
    consensus_posterior  = c(0.95, NA, 0.95),
    n_plausible          = c(1L, 2L, 1L)
  )
}

test_that("boost is rescaled onto the occurrence-scale ceiling, not used directly", {
  result    <- .make_result_theta()
  consensus <- .make_consensus_theta()
  theta_ceiling <- max(result$theta_mean, na.rm = TRUE)   # 0.05
  expect_equal(theta_ceiling, 0.05)

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]

  # q = 0.95 (the sole S1 donor's consensus_posterior); expected = q * ceiling
  expect_equal(sp_a_s2, 0.95 * theta_ceiling, tolerance = 1e-8)
  # and NOT the raw, unscaled quantile value (the pre-fix behavior)
  expect_false(isTRUE(all.equal(sp_a_s2, 0.95)))
})

test_that("confirmed_without_occurrence_record flags a boosted taxon with NA theta_mean", {
  result    <- .make_result_theta()
  consensus <- .make_consensus_theta()
  out <- update_prior_from_consensus(result, consensus, n_sims = 0)

  sp_d_s2 <- out[out$observation_id == "S2" & out$taxon_name == "Sp_D", ]
  sp_a_s2 <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  expect_true("confirmed_without_occurrence_record" %in% names(out))
  expect_true(sp_d_s2$confirmed_without_occurrence_record)
  expect_false(sp_a_s2$confirmed_without_occurrence_record)
  # boosting is NOT suppressed for the no-record taxon -- it still gets raised
  expect_gt(sp_d_s2$prior_mean, 0.0005)
})

test_that("confirmed_without_occurrence_record defaults FALSE for resolved/unboosted rows", {
  result    <- .make_result_theta()
  consensus <- .make_consensus_theta()
  out <- update_prior_from_consensus(result, consensus, n_sims = 0)

  resolved <- out[out$observation_id %in% c("S1", "S3"), ]
  expect_true(all(!resolved$confirmed_without_occurrence_record))
})

test_that("falls back to unscaled substitution when result has no theta_mean column", {
  result    <- .make_result()      # no theta_mean column
  consensus <- .make_consensus()
  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  expect_false("theta_mean" %in% names(result))
  # existing behavior: raw quantile substituted directly (0.9 default s1_posterior)
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  expect_equal(sp_a_s2, 0.9, tolerance = 1e-8)
})

test_that("never-demote still holds under rescaling", {
  result    <- .make_result_theta()
  result$prior_mean[result$observation_id == "S2" & result$taxon_name == "Sp_A"] <- 0.9
  consensus <- .make_consensus_theta()
  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  expect_equal(sp_a_s2, 0.9)   # already well above q*ceiling (0.0475) -- untouched
})
