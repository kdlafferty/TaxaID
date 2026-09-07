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

  # Soft design (2026-08-28): support for Sp_A = S1's 0.8 + S2's own 0.5;
  # leave-one-out mass for S2 = 0.8; discounted m = 0.25*0.8 = 0.2;
  # saturation s = 0.2/1.2 = 1/6; target = support-weighted 0.9-quantile of
  # {0.5 (w 0.5), 0.8 (w 0.8)} = 0.8; new = 0.5 + (0.8-0.5)*(1/6) = 0.55.
  s2_sp_a <- out |> filter(observation_id == "S2", taxon_name == "Sp_A")
  expect_true(nrow(s2_sp_a) == 1L)
  expect_true(s2_sp_a$prior_updated)
  expect_equal(s2_sp_a$prior_mean, 0.55, tolerance = 1e-8)
})

test_that("report_params from the input `result` survive the call, merged with this function's own (real bug, code review 2026-08)", {
  result    <- .make_result()
  attr(result, "report_params") <- list(score_sharpness = 0.77, top_n = 4L)
  consensus <- .make_consensus()

  out <- update_prior_from_consensus(result, consensus, n_sims = 0,
                                      confirmation_quantile = 0.85)
  rp <- attr(out, "report_params")

  # Previously this attribute was overwritten wholesale, silently discarding
  # score_sharpness/top_n (and anything else the caller had attached) --
  # generate_report()'s LLM Methods text would then fall back to a
  # hardcoded default instead of the value actually used.
  expect_equal(rp$score_sharpness, 0.77)
  expect_equal(rp$top_n, 4L)
  expect_equal(rp$confirmation_quantile, 0.85)
})

test_that("soft update still operates when no observation is resolved", {
  # Old (hard-gate) behavior: no resolved donors -> nothing boosted. Soft
  # design (2026-08-28): support flows from posteriors regardless of
  # resolution status, so cross-observation evidence still applies.
  result    <- .make_result()
  consensus <- .make_consensus()
  consensus$is_resolved <- FALSE

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  expect_s3_class(out, "data.frame")
  # S1's Sp_A gets S2's 0.5 support: m = 0.125, s = 1/9, target 0.8 ->
  # 0.5 + 0.3/9; S2's Sp_A gets S1's 0.8: 0.55 as elsewhere.
  s1_sp_a <- out$prior_mean[out$observation_id == "S1" & out$taxon_name == "Sp_A"]
  expect_equal(s1_sp_a, 0.5 + 0.3 * (0.125 / 1.125), tolerance = 1e-8)
})

# ---- Soft design: no confirmation gate, continuous everywhere ----------------

test_that("consensus confidence no longer gates the update (soft design, 2026-08-28)", {
  result    <- .make_result()
  consensus <- .make_consensus(s1_posterior = 0.6)  # weakly resolved donor

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)

  # Support now comes from the posteriors table itself, not the consensus
  # confidence, so the outcome is identical to the 0.9-confidence case: 0.55.
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_true(s2_sp_a$prior_updated)
  expect_equal(s2_sp_a$prior_mean, 0.55, tolerance = 1e-8)
})

test_that("confirmation_discount = 0 disables the update entirely", {
  result    <- .make_result()
  consensus <- .make_consensus()

  out <- update_prior_from_consensus(result, consensus, n_sims = 0,
                                     confirmation_discount = 0)
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_equal(s2_sp_a$prior_mean, 0.5)
})

test_that("the update is continuous in the support (no cliff at any threshold)", {
  # Sweep S1's posterior support for Sp_A across the old 0.8 hard gate: the
  # boosted prior must move smoothly, with no jump anywhere.
  news <- vapply(c(0.70, 0.78, 0.80, 0.82, 0.90), function(p1) {
    result <- .make_result()
    result$posterior_point_est[result$observation_id == "S1" &
                                 result$taxon_name == "Sp_A"] <- p1
    out <- suppressMessages(update_prior_from_consensus(result, .make_consensus(), n_sims = 0))
    out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  }, numeric(1))
  expect_true(all(diff(news) > 0))          # monotone in support
  expect_true(max(abs(diff(news))) < 0.05)  # and smooth -- no gate-sized jumps
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

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  s3_sp_a <- out[out$observation_id == "S3" & out$taxon_name == "Sp_A", ]

  # Soft design: support for Sp_A across the posteriors table = S1 0.8 +
  # S2 0.5 + S3 1.0; leave-one-out mass for S3 = 1.3; m = 0.25*1.3 = 0.325;
  # s = 0.325/1.325; target = support-weighted 0.9-quantile of
  # {0.5, 0.8, 1.0} (weights = values) = 1.0; new = 0.4 + 0.6*s.
  s_sat <- 0.325 / 1.325
  expect_equal(s3_sp_a$prior_mean, 0.4 + 0.6 * s_sat, tolerance = 1e-8)

  # A consensus-only donor (S4 has no rows in `result`) contributes nothing
  # under the soft design -- support is sourced from the posteriors table.
  out2 <- update_prior_from_consensus(result,
    consensus[consensus$observation_id != "S4", ], n_sims = 0)
  expect_equal(
    out2$prior_mean[out2$observation_id == "S3" & out2$taxon_name == "Sp_A"],
    s3_sp_a$prior_mean, tolerance = 1e-12
  )
})

# ---- prior_alpha/prior_beta consistency (Session 149 latent-bug fix) --------

test_that("prior_alpha/prior_beta are recomputed consistently with a boosted prior_mean", {
  result    <- .make_result()
  consensus <- .make_consensus(s1_posterior = 0.9)

  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  phi <- 5 + 5  # original prior_alpha + prior_beta for this row
  expect_equal(s2_sp_a$prior_alpha, 0.55 * phi, tolerance = 1e-8)
  expect_equal(s2_sp_a$prior_beta,  0.45 * phi, tolerance = 1e-8)
  # Mean implied by the recomputed Beta matches the boosted prior_mean exactly
  expect_equal(s2_sp_a$prior_alpha / (s2_sp_a$prior_alpha + s2_sp_a$prior_beta),
               s2_sp_a$prior_mean)
})

test_that("even maximal support keeps the prior strictly inside (0, 1) with a valid Beta", {
  # Under the hard design, a donor at consensus_posterior = 1.0 could
  # substitute exactly 1.0 and (pre-clamp) produce prior_beta = 0, which
  # compute_posterior() rejects (Session 152 bug). The soft saturation can
  # never reach the target exactly, and the boundary clamp guards the Beta
  # derivation regardless.
  result <- .make_result()
  result$posterior_point_est[result$observation_id == "S1" &
                               result$taxon_name == "Sp_A"] <- 1.0
  out <- suppressMessages(update_prior_from_consensus(result, .make_consensus(), n_sims = 0))
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  # mass = 1.0 (S1) ; m = 0.25 ; s = 0.2 ; target = 1.0 ; new = 0.5 + 0.5*0.2
  expect_equal(s2_sp_a$prior_mean, 0.6, tolerance = 1e-8)
  expect_true(s2_sp_a$prior_mean < 1)
  expect_true(is.finite(s2_sp_a$prior_alpha) && s2_sp_a$prior_alpha > 0)
  expect_true(is.finite(s2_sp_a$prior_beta)  && s2_sp_a$prior_beta  > 0)
  expect_no_error(update_prior_from_consensus(result, .make_consensus(), n_sims = 100))
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

test_that("confirmation_discount must be in [0, 1]", {
  result    <- .make_result()
  consensus <- .make_consensus()

  expect_error(
    update_prior_from_consensus(result, consensus, confirmation_discount = -0.1),
    "confirmation_discount"
  )
  expect_error(
    update_prior_from_consensus(result, consensus, confirmation_discount = 1.1),
    "confirmation_discount"
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

  # Soft design: support for Sp_A = S1 0.95 + S2 0.5; leave-one-out mass for
  # S2 = 0.95; m = 0.25*0.95; s = m/(1+m); target = support-weighted
  # 0.9-quantile of {0.5, 0.95} = 0.95, rescaled onto the ceiling ->
  # candidate = 0.95 * 0.05; new = old + (candidate - old) * s.
  m <- 0.25 * 0.95; s_sat <- m / (1 + m)
  expected <- 0.001 + (0.95 * theta_ceiling - 0.001) * s_sat
  expect_equal(sp_a_s2, expected, tolerance = 1e-8)
  # and NOT the raw, unscaled target (the pre-2026-07-30 behavior)
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
  # no occurrence scale: the support-weighted target (0.8) is used directly;
  # soft move: 0.5 + (0.8 - 0.5) * (1/6) = 0.55
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  expect_equal(sp_a_s2, 0.55, tolerance = 1e-8)
})

test_that("never-demote still holds under rescaling", {
  result    <- .make_result_theta()
  result$prior_mean[result$observation_id == "S2" & result$taxon_name == "Sp_A"] <- 0.9
  consensus <- .make_consensus_theta()
  out <- update_prior_from_consensus(result, consensus, n_sims = 0)
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  expect_equal(sp_a_s2, 0.9)   # already well above q*ceiling (0.0475) -- untouched
})

test_that("a presence-mixture row has prior_mix_w updated (not cleared) by soft support", {
  res <- .make_result()
  mixify <- res$observation_id == "S2" & res$taxon_name == "Sp_A"
  res$prior_mean[mixify]  <- 1e-4 + (0.02 - 1e-4) * 0.5   # blend at w = 0.5
  res$prior_alpha[mixify] <- 0.02
  res$prior_beta[mixify]  <- 1.98
  res$prior_mix_w             <- ifelse(mixify, 0.5, NA_real_)
  res$prior_mix_theta_present <- ifelse(mixify, 0.02, NA_real_)
  res$prior_mix_theta_absent  <- ifelse(mixify, 1e-4, NA_real_)
  res$prior_mix_p_conc        <- ifelse(mixify, 1, NA_real_)

  out <- suppressMessages(suppressWarnings(
    update_prior_from_consensus(res, .make_consensus(), n_sims = 50)
  ))
  boosted <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  # leave-one-out mass = S1's 0.8; m = 0.25*0.8 = 0.2;
  # w1 = (1*0.5 + 0.2)/(1 + 0.2) = 0.5833...; theta1 = blend at w1
  w1 <- (1 * 0.5 + 0.2) / 1.2
  th1 <- 1e-4 + (0.02 - 1e-4) * w1
  expect_equal(boosted$prior_mix_w, w1, tolerance = 1e-8)
  expect_equal(boosted$prior_mean, th1, tolerance = 1e-8)
  expect_equal(boosted$prior_mix_p_conc, 1.2, tolerance = 1e-8)
  # Beta summary re-moment-matched to the updated mixture
  expect_equal(boosted$prior_alpha / (boosted$prior_alpha + boosted$prior_beta),
               th1, tolerance = 1e-6)
  # never demoted; resolved rows untouched
  expect_gt(boosted$prior_mix_w, 0.5)
  s1 <- out[out$observation_id == "S1", ]
  expect_true(all(is.na(s1$prior_mix_w)))
})

test_that("mixture re-moment-match includes prior_mix_var_present/_absent when supplied (2026-09-05, finding A4)", {
  # Same fixture as above, but with real (non-zero) within-state variance at
  # the present/absent anchors -- as a real blend-mode
  # apply_undetected_evidence() row now carries. Reproducing v_mix WITHOUT
  # these two terms (the pre-fix formula) would give a smaller v_mix and
  # therefore a LARGER n_eff/alpha+beta (over-concentrated) than reproducing
  # it WITH them -- confirm the fix actually uses the supplied variances by
  # comparing against that pre-fix formula computed by hand.
  res <- .make_result()
  mixify <- res$observation_id == "S2" & res$taxon_name == "Sp_A"
  res$prior_mean[mixify]  <- 1e-4 + (0.02 - 1e-4) * 0.5
  res$prior_alpha[mixify] <- 0.02
  res$prior_beta[mixify]  <- 1.98
  res$prior_mix_w             <- ifelse(mixify, 0.5, NA_real_)
  res$prior_mix_theta_present <- ifelse(mixify, 0.02, NA_real_)
  res$prior_mix_theta_absent  <- ifelse(mixify, 1e-4, NA_real_)
  res$prior_mix_p_conc        <- ifelse(mixify, 1, NA_real_)
  res$prior_mix_var_present   <- ifelse(mixify, 5e-5, NA_real_)
  res$prior_mix_var_absent    <- ifelse(mixify, 2e-6, NA_real_)

  out <- suppressMessages(suppressWarnings(
    update_prior_from_consensus(res, .make_consensus(), n_sims = 50)
  ))
  boosted <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  w1  <- (1 * 0.5 + 0.2) / 1.2
  th1 <- 1e-4 + (0.02 - 1e-4) * w1
  v_mix_with_var    <- w1 * (1 - w1) * (0.02 - 1e-4)^2 + w1 * 5e-5 + (1 - w1) * 2e-6
  v_mix_without_var <- w1 * (1 - w1) * (0.02 - 1e-4)^2
  ne_with_var    <- max(th1 * (1 - th1) / v_mix_with_var - 1, 1e-3)
  ne_without_var <- max(th1 * (1 - th1) / v_mix_without_var - 1, 1e-3)
  expect_false(isTRUE(all.equal(ne_with_var, ne_without_var)))  # sanity: fixture actually discriminates

  observed_phi <- boosted$prior_alpha + boosted$prior_beta
  expect_equal(observed_phi, ne_with_var, tolerance = 1e-6)
  expect_false(isTRUE(all.equal(observed_phi, ne_without_var, tolerance = 1e-6)))
})

test_that("mixture w-update is capped at prior_mix_veto_bound, never exceeds it (2026-09-05, finding B2)", {
  res <- .make_result()
  mixify <- res$observation_id == "S2" & res$taxon_name == "Sp_A"
  res$prior_mean[mixify]  <- 1e-4 + (0.02 - 1e-4) * 0.5
  res$prior_alpha[mixify] <- 0.02
  res$prior_beta[mixify]  <- 1.98
  res$prior_mix_w             <- ifelse(mixify, 0.5, NA_real_)
  res$prior_mix_theta_present <- ifelse(mixify, 0.02, NA_real_)
  res$prior_mix_theta_absent  <- ifelse(mixify, 1e-4, NA_real_)
  res$prior_mix_p_conc        <- ifelse(mixify, 1, NA_real_)
  # Uncapped update would reach w1 = (1*0.5 + 0.2)/1.2 = 0.5833... -- set the
  # bound below that so the cap is guaranteed to bind.
  res$prior_mix_veto_bound <- ifelse(mixify, 0.52, NA_real_)

  out <- suppressMessages(suppressWarnings(
    update_prior_from_consensus(res, .make_consensus(), n_sims = 50)
  ))
  boosted <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_equal(boosted$prior_mix_w, 0.52, tolerance = 1e-8)
  expect_equal(boosted$prior_mean,
               1e-4 + (0.02 - 1e-4) * 0.52, tolerance = 1e-8)

  msgs <- capture_messages(suppressWarnings(
    update_prior_from_consensus(res, .make_consensus(), n_sims = 50)
  ))
  expect_true(any(grepl("veto bound", msgs, ignore.case = TRUE)))
})

test_that("mixture w-update is NOT capped when prior_mix_veto_bound is NA or the column is absent", {
  res <- .make_result()
  mixify <- res$observation_id == "S2" & res$taxon_name == "Sp_A"
  res$prior_mean[mixify]  <- 1e-4 + (0.02 - 1e-4) * 0.5
  res$prior_alpha[mixify] <- 0.02
  res$prior_beta[mixify]  <- 1.98
  res$prior_mix_w             <- ifelse(mixify, 0.5, NA_real_)
  res$prior_mix_theta_present <- ifelse(mixify, 0.02, NA_real_)
  res$prior_mix_theta_absent  <- ifelse(mixify, 1e-4, NA_real_)
  res$prior_mix_p_conc        <- ifelse(mixify, 1, NA_real_)
  # No prior_mix_veto_bound column at all -- backward compatible, uncapped.

  out <- suppressMessages(suppressWarnings(
    update_prior_from_consensus(res, .make_consensus(), n_sims = 50)
  ))
  boosted <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  w1 <- (1 * 0.5 + 0.2) / 1.2
  expect_equal(boosted$prior_mix_w, w1, tolerance = 1e-8)
})
