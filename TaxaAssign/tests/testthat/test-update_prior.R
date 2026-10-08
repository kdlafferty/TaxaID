# tests/testthat/test-update_prior.R
# Session 149: rewritten for the confirmation-quantile design (replaces the
# old fixed presence_multiplier). See update_prior_from_consensus.R's
# "Confirmation-quantile design" roxygen section for the full rationale.

library(dplyr)

# ---- Shared test data --------------------------------------------------------

# The tests above the receiver-guard section exercise the raise mechanics
# themselves, so they run with the guards off (their fixtures carry no
# likelihood-only consensus and mostly no theta_mean). The guards are tested
# in their own section below and in the occurrence-record test.
.upf <- function(...) update_prior_from_consensus(..., require_support_columns = FALSE)
# the guarded (production) path. The fixtures' consensus is hand-built, so it carries the settings
# posterior_consensus() would attach (attr "consensus_settings"), which the species guard reuses.
.CARGS <- list(cumulative_threshold = 0.9, min_posterior = 0.05)
.with_settings <- function(consensus, settings = .CARGS) {
  attr(consensus, "consensus_settings") <- settings
  consensus
}
.upg <- function(result, consensus, ..., settings = .CARGS) {
  update_prior_from_consensus(result, .with_settings(consensus, settings), ...)
}
# isolates the earlier guards (G1/G3/G4) and the raise arithmetic: no likelihood margin (G5; the
# internal constant mocked to 0), and the species guard's (G6) consensus stubbed to call no species,
# so it has nothing to undo
.upg0 <- function(..., likelihood_margin_z = 0) {
  stub <- function() data.frame(observation_id = unique(posterior_df$observation_id), consensus_rank = NA_character_)
  formals(stub) <- formals(posterior_consensus) # keeps the settings validation meaningful
  testthat::local_mocked_bindings(posterior_consensus = stub, .ROUND2_LIKELIHOOD_MARGIN_Z = likelihood_margin_z)
  .upg(...)
}

.make_result <- function() {
  bind_rows(
    tibble(
      observation_id = "S1",
      taxon_name = c("Sp_A", "Sp_B"),
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      score_likelihood = c(0.8, 0.2),
      score_likelihood_mean = c(0.8, 0.2),
      score_likelihood_sd = c(0.05, 0.05),
      prior_mean = c(0.5, 0.5),
      prior_alpha = c(5, 5),
      prior_beta = c(5, 5),
      posterior_point_est = c(0.8, 0.2),
      posterior_mean = c(0.8, 0.2),
      posterior_sd = c(0.05, 0.05),
      confidence_score = c(0.9, 0.1),
      genus = c("GenA", "GenB"),
      family = c("FamA", "FamB"),
      species = c("Sp_A", "Sp_B")
    ),
    tibble(
      observation_id = "S2",
      taxon_name = c("Sp_A", "Sp_C"),
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      score_likelihood = c(0.5, 0.5),
      score_likelihood_mean = c(0.5, 0.5),
      score_likelihood_sd = c(0.05, 0.05),
      prior_mean = c(0.5, 0.5),
      prior_alpha = c(5, 5),
      prior_beta = c(5, 5),
      posterior_point_est = c(0.5, 0.5),
      posterior_mean = c(0.5, 0.5),
      posterior_sd = c(0.05, 0.05),
      confidence_score = c(0.5, 0.5),
      genus = c("GenA", "GenC"),
      family = c("FamA", "FamC"),
      species = c("Sp_A", "Sp_C")
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
  result <- .make_result()
  consensus <- .make_consensus()

  out <- .upf(result, consensus, n_sims = 0)
  expect_s3_class(out, "data.frame")
  expect_true("prior_updated" %in% names(out))
  expect_true(nrow(out) >= nrow(result))
})

test_that("update_prior_from_consensus boosts confirmed species in unresolved samples", {
  result <- .make_result()
  consensus <- .make_consensus()

  out <- .upf(result, consensus, n_sims = 0)

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
  result <- .make_result()
  attr(result, "report_params") <- list(score_sharpness = 0.77, top_n = 4L)
  consensus <- .make_consensus()

  out <- .upf(result, consensus,
    n_sims = 0,
    confirmation_quantile = 0.85
  )
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
  result <- .make_result()
  consensus <- .make_consensus()
  consensus$is_resolved <- FALSE

  out <- .upf(result, consensus, n_sims = 0)
  expect_s3_class(out, "data.frame")
  # S1's Sp_A gets S2's 0.5 support: m = 0.125, s = 1/9, target 0.8 ->
  # 0.5 + 0.3/9; S2's Sp_A gets S1's 0.8: 0.55 as elsewhere.
  s1_sp_a <- out$prior_mean[out$observation_id == "S1" & out$taxon_name == "Sp_A"]
  expect_equal(s1_sp_a, 0.5 + 0.3 * (0.125 / 1.125), tolerance = 1e-8)
})

# ---- Soft design: no confirmation gate, continuous everywhere ----------------

test_that("consensus confidence no longer gates the update (soft design, 2026-08-28)", {
  result <- .make_result()
  consensus <- .make_consensus(s1_posterior = 0.6) # weakly resolved donor

  out <- .upf(result, consensus, n_sims = 0)

  # Support now comes from the posteriors table itself, not the consensus
  # confidence, so the outcome is identical to the 0.9-confidence case: 0.55.
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_true(s2_sp_a$prior_updated)
  expect_equal(s2_sp_a$prior_mean, 0.55, tolerance = 1e-8)
})

test_that("confirmation_discount = 0 disables the update entirely", {
  result <- .make_result()
  consensus <- .make_consensus()

  out <- .upf(result, consensus,
    n_sims = 0,
    confirmation_discount = 0
  )
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
    out <- suppressMessages(.upf(result, .make_consensus(), n_sims = 0))
    out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  }, numeric(1))
  expect_true(all(diff(news) > 0)) # monotone in support
  expect_true(max(abs(diff(news))) < 0.05) # and smooth -- no gate-sized jumps
})

# ---- never-demote guard -------------------------------------------------------

test_that("never-demote: an existing prior above the confirmation quantile is left unchanged", {
  result <- .make_result()
  result$prior_mean[result$observation_id == "S2" & result$taxon_name == "Sp_A"] <- 0.95
  consensus <- .make_consensus(s1_posterior = 0.9) # would only raise to 0.9

  out <- .upf(result, consensus, n_sims = 0)

  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  # 0.9 < 0.95, so prior_mean must stay at 0.95 (not lowered)
  expect_equal(s2_sp_a$prior_mean, 0.95)
})

# ---- confirmation_quantile across multiple donors ----------------------------

test_that("confirmation_quantile combines multiple donor observations correctly", {
  result <- bind_rows(
    .make_result(),
    tibble(
      observation_id = "S3",
      taxon_name = "Sp_A",
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      score_likelihood = 1.0,
      score_likelihood_mean = 1.0,
      score_likelihood_sd = 0,
      prior_mean = 0.4,
      prior_alpha = 4,
      prior_beta = 6,
      posterior_point_est = 1.0,
      posterior_mean = 1.0,
      posterior_sd = 0,
      confidence_score = 1.0,
      genus = "GenA", family = "FamA", species = "Sp_A"
    )
  )
  # Two donors confirming Sp_A: S1 at 0.90, S4 at 0.95 (S4 has no hypothesis
  # rows in `result` -- only its consensus counts as a donor). S3 needs its
  # own (unresolved) consensus row to be eligible for the boost at all.
  consensus <- bind_rows(
    .make_consensus(s1_posterior = 0.90),
    tibble(
      observation_id = "S3", consensus_taxon = NA, consensus_rank = NA,
      is_resolved = FALSE, consensus_posterior = NA, n_plausible = 1L
    ),
    tibble(
      observation_id = "S4", consensus_taxon = "Sp_A", consensus_rank = "species",
      is_resolved = TRUE, consensus_posterior = 0.95, n_plausible = 1L
    )
  )

  out <- .upf(result, consensus, n_sims = 0)
  s3_sp_a <- out[out$observation_id == "S3" & out$taxon_name == "Sp_A", ]

  # Soft design: support for Sp_A across the posteriors table = S1 0.8 +
  # S2 0.5 + S3 1.0; leave-one-out mass for S3 = 1.3; m = 0.25*1.3 = 0.325;
  # s = 0.325/1.325; target = support-weighted 0.9-quantile of
  # {0.5, 0.8, 1.0} (weights = values) = 1.0; new = 0.4 + 0.6*s.
  s_sat <- 0.325 / 1.325
  expect_equal(s3_sp_a$prior_mean, 0.4 + 0.6 * s_sat, tolerance = 1e-8)

  # A consensus-only donor (S4 has no rows in `result`) contributes nothing
  # under the soft design -- support is sourced from the posteriors table.
  out2 <- .upf(result,
    consensus[consensus$observation_id != "S4", ],
    n_sims = 0
  )
  expect_equal(
    out2$prior_mean[out2$observation_id == "S3" & out2$taxon_name == "Sp_A"],
    s3_sp_a$prior_mean,
    tolerance = 1e-12
  )
})

# ---- prior_alpha/prior_beta consistency (Session 149 latent-bug fix) --------

test_that("prior_alpha/prior_beta are recomputed consistently with a boosted prior_mean", {
  result <- .make_result()
  consensus <- .make_consensus(s1_posterior = 0.9)

  out <- .upf(result, consensus, n_sims = 0)
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  phi <- 5 + 5 # original prior_alpha + prior_beta for this row
  expect_equal(s2_sp_a$prior_alpha, 0.55 * phi, tolerance = 1e-8)
  expect_equal(s2_sp_a$prior_beta, 0.45 * phi, tolerance = 1e-8)
  # Mean implied by the recomputed Beta matches the boosted prior_mean exactly
  expect_equal(
    s2_sp_a$prior_alpha / (s2_sp_a$prior_alpha + s2_sp_a$prior_beta),
    s2_sp_a$prior_mean
  )
})

test_that("even maximal support keeps the prior strictly inside (0, 1) with a valid Beta", {
  set.seed(1) # simulation path: seeded here so other tests cannot shift its stream
  # Under the hard design, a donor at consensus_posterior = 1.0 could
  # substitute exactly 1.0 and (pre-clamp) produce prior_beta = 0, which
  # compute_posterior() rejects (Session 152 bug). The soft saturation can
  # never reach the target exactly, and the boundary clamp guards the Beta
  # derivation regardless.
  result <- .make_result()
  result$posterior_point_est[result$observation_id == "S1" &
    result$taxon_name == "Sp_A"] <- 1.0
  out <- suppressMessages(.upf(result, .make_consensus(), n_sims = 0))
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  # mass = 1.0 (S1) ; m = 0.25 ; s = 0.2 ; target = 1.0 ; new = 0.5 + 0.5*0.2
  expect_equal(s2_sp_a$prior_mean, 0.6, tolerance = 1e-8)
  expect_true(s2_sp_a$prior_mean < 1)
  expect_true(is.finite(s2_sp_a$prior_alpha) && s2_sp_a$prior_alpha > 0)
  expect_true(is.finite(s2_sp_a$prior_beta) && s2_sp_a$prior_beta > 0)
  expect_no_error(.upf(result, .make_consensus(), n_sims = 100))
})

# ---- spatial_group_map: multi-member vs. single-observation spatial groups ---

test_that("spatial_group_map blocks the boost when the confirming observation is a singleton", {
  result <- .make_result()
  consensus <- .make_consensus()

  # S1 (the resolved, confirming observation) is in its own single-observation
  # spatial group -- same "spatial_group_<n>" shape as any other group, just
  # with one member -- so it must not confirm anything for S2.
  spatial_group_map <- tibble(
    observation_id   = c("S1", "S2"),
    spatial_group_id = c("spatial_group_1", "spatial_group_2")
  )

  out <- .upf(result, consensus,
    n_sims = 0,
    spatial_group_map = spatial_group_map
  )

  # No spatial group has >= 2 members, so nothing is eligible; result unchanged.
  expect_equal(nrow(out), nrow(result))
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_equal(s2_sp_a$prior_mean, 0.5)
})

test_that("spatial_group_map allows the boost when S1 and S2 share a spatial group", {
  result <- .make_result()
  consensus <- .make_consensus()

  spatial_group_map <- tibble(
    observation_id   = c("S1", "S2"),
    spatial_group_id = c("spatial_group_1", "spatial_group_1")
  )

  out <- .upf(result, consensus,
    n_sims = 0,
    spatial_group_map = spatial_group_map
  )

  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_true(nrow(s2_sp_a) == 1L)
  expect_true(s2_sp_a$prior_updated)
})

test_that("an unresolved observation in a single-observation spatial group is skipped even if another spatial group confirms the species", {
  result <- bind_rows(
    .make_result(),
    tibble(
      observation_id = "S3",
      taxon_name = c("Sp_A", "Sp_D"),
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      score_likelihood = c(0.5, 0.5),
      score_likelihood_mean = c(0.5, 0.5),
      score_likelihood_sd = c(0.05, 0.05),
      prior_mean = c(0.5, 0.5),
      prior_alpha = c(5, 5),
      prior_beta = c(5, 5),
      posterior_point_est = c(0.5, 0.5),
      posterior_mean = c(0.5, 0.5),
      posterior_sd = c(0.05, 0.05),
      confidence_score = c(0.5, 0.5),
      genus = c("GenA", "GenD"),
      family = c("FamA", "FamD"),
      species = c("Sp_A", "Sp_D")
    )
  )
  consensus <- bind_rows(
    .make_consensus(),
    tibble(
      observation_id = "S3", consensus_taxon = NA, consensus_rank = NA,
      is_resolved = FALSE, consensus_posterior = NA, n_plausible = 2L
    )
  )

  # S1/S2 share a spatial group (confirms Sp_A); S3 is its own single-observation group.
  spatial_group_map <- tibble(
    observation_id   = c("S1", "S2", "S3"),
    spatial_group_id = c("spatial_group_1", "spatial_group_1", "spatial_group_2")
  )

  out <- .upf(result, consensus,
    n_sims = 0,
    spatial_group_map = spatial_group_map
  )

  s3_sp_a <- out[out$observation_id == "S3" & out$taxon_name == "Sp_A", ]
  expect_equal(s3_sp_a$prior_mean, 0.5) # unchanged -- S3 is its own spatial group
  s2_sp_a <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_true(s2_sp_a$prior_updated) # unchanged behavior for the shared-group pair
})

test_that("spatial_group_map missing required columns errors", {
  result <- .make_result()
  consensus <- .make_consensus()
  bad_map <- tibble(observation_id = c("S1", "S2"))

  expect_error(
    .upf(result, consensus, spatial_group_map = bad_map),
    "spatial_group_map missing required column"
  )
})

# ---- Input validation ---------------------------------------------------------

test_that("consensus missing consensus_posterior errors", {
  result <- .make_result()
  consensus <- .make_consensus()
  consensus$consensus_posterior <- NULL

  expect_error(
    .upf(result, consensus),
    "consensus_posterior"
  )
})

test_that("confirmation_quantile must be in (0, 1]", {
  result <- .make_result()
  consensus <- .make_consensus()

  expect_error(
    .upf(result, consensus, confirmation_quantile = 0),
    "confirmation_quantile"
  )
  expect_error(
    .upf(result, consensus, confirmation_quantile = 1.5),
    "confirmation_quantile"
  )
})

test_that("confirmation_discount must be in [0, 1]", {
  result <- .make_result()
  consensus <- .make_consensus()

  expect_error(
    .upf(result, consensus, confirmation_discount = -0.1),
    "confirmation_discount"
  )
  expect_error(
    .upf(result, consensus, confirmation_discount = 1.1),
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
      observation_id = "S1",
      taxon_name = c("Sp_A", "Sp_B"),
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      score_likelihood = c(0.8, 0.2),
      score_likelihood_mean = c(0.8, 0.2),
      score_likelihood_sd = c(0.05, 0.05),
      prior_mean = c(0.5, 0.5),
      theta_mean = c(0.05, 0.01),
      prior_alpha = c(5, 5),
      prior_beta = c(5, 5),
      posterior_point_est = c(0.95, 0.05),
      posterior_mean = c(0.95, 0.05),
      posterior_sd = c(0.02, 0.02),
      confidence_score = c(0.95, 0.05)
    ),
    tibble(
      observation_id = "S2",
      taxon_name = c("Sp_A", "Sp_D"),
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      score_likelihood = c(0.5, 0.5),
      score_likelihood_mean = c(0.5, 0.5),
      score_likelihood_sd = c(0.05, 0.05),
      prior_mean = c(0.001, 0.0005),
      theta_mean = c(0.05, NA_real_),
      prior_alpha = c(5, 5),
      prior_beta = c(5, 5),
      posterior_point_est = c(0.5, 0.5),
      posterior_mean = c(0.5, 0.5),
      posterior_sd = c(0.05, 0.05),
      confidence_score = c(0.5, 0.5)
    ),
    tibble(
      observation_id = "S3",
      taxon_name = c("Sp_D", "Sp_E"),
      taxon_name_rank = "species",
      hypothesis_type = "specific_candidate",
      score_likelihood = c(0.95, 0.05),
      score_likelihood_mean = c(0.95, 0.05),
      score_likelihood_sd = c(0.02, 0.02),
      prior_mean = c(0.0005, 0.5),
      theta_mean = c(NA_real_, 0.02),
      prior_alpha = c(5, 5),
      prior_beta = c(5, 5),
      posterior_point_est = c(0.95, 0.05),
      posterior_mean = c(0.95, 0.05),
      posterior_sd = c(0.02, 0.02),
      confidence_score = c(0.95, 0.05)
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
  result <- .make_result_theta()
  consensus <- .make_consensus_theta()
  theta_ceiling <- max(result$theta_mean, na.rm = TRUE) # 0.05
  expect_equal(theta_ceiling, 0.05)

  out <- .upf(result, consensus, n_sims = 0)
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]

  # Soft design: support for Sp_A = S1 0.95 + S2 0.5; leave-one-out mass for
  # S2 = 0.95; m = 0.25*0.95; s = m/(1+m); target = support-weighted
  # 0.9-quantile of {0.5, 0.95} = 0.95, rescaled onto the ceiling ->
  # candidate = 0.95 * 0.05; new = old + (candidate - old) * s.
  m <- 0.25 * 0.95
  s_sat <- m / (1 + m)
  expected <- 0.001 + (0.95 * theta_ceiling - 0.001) * s_sat
  expect_equal(sp_a_s2, expected, tolerance = 1e-8)
  # and NOT the raw, unscaled target (the pre-2026-07-30 behavior)
  expect_false(isTRUE(all.equal(sp_a_s2, 0.95)))
})

test_that("the raise arithmetic is the same on the guarded (default) path", {
  # The mechanics tests above run through the guards-off shim (.upf); this one
  # runs the production configuration: both support columns supplied, guards
  # ON. Every candidate shares one likelihood node, so only Sp_D (theta NA) is
  # held back, and Sp_A's raise must be the occurrence-scale value exactly.
  result <- .make_result_theta()
  result$phylum <- "P1"
  consensus <- .make_consensus_theta()
  consensus$likelihood_consensus_taxon <- "P1"
  consensus$likelihood_consensus_rank <- "phylum"
  out <- suppressMessages(.upg0(result, consensus, n_sims = 0))
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  m <- 0.25 * 0.95
  expect_equal(sp_a_s2, 0.001 + (0.95 * 0.05 - 0.001) * m / (1 + m), tolerance = 1e-8)
  shim <- .upf(result, consensus, n_sims = 0)
  expect_equal(sp_a_s2, shim$prior_mean[shim$observation_id == "S2" & shim$taxon_name == "Sp_A"])
  # alpha/beta follow the new mean with the concentration preserved, as on the shim path
  r <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_equal(r$prior_alpha + r$prior_beta, 10)
  expect_equal(r$prior_alpha / (r$prior_alpha + r$prior_beta), sp_a_s2)
})

test_that("a supported row with no occurrence record (theta_mean NA) is never raised", {
  # 2026-10-07 (maintainer, error-first): previously raised and only flagged.
  result <- .make_result_theta()
  result$phylum <- "P1" # one node holds every candidate, so only the record guard decides
  consensus <- .make_consensus_theta()
  consensus$likelihood_consensus_taxon <- "P1"
  consensus$likelihood_consensus_rank <- "phylum"
  out <- suppressMessages(.upg0(result, consensus, n_sims = 0))
  sp_d_s2 <- out[out$observation_id == "S2" & out$taxon_name == "Sp_D", ]
  sp_a_s2 <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  # Sp_D has support (S3 resolves it at 0.95) but no record: kept at its prior
  expect_equal(sp_d_s2$prior_mean, 0.0005)
  expect_false(sp_d_s2$confirmed_without_occurrence_record)
  # control: Sp_A in the SAME observation has a record and IS raised
  expect_gt(sp_a_s2$prior_mean, 0.001)
  expect_false(sp_a_s2$confirmed_without_occurrence_record)
  expect_true("confirmed_without_occurrence_record" %in% names(out))
  # the message counts the row the guard held back
  expect_message(.upg0(result, consensus, n_sims = 0),
    "1 not raised because they have no occurrence record")
})

test_that("confirmed_without_occurrence_record defaults FALSE for resolved/unboosted rows", {
  result <- .make_result_theta()
  consensus <- .make_consensus_theta()
  out <- .upf(result, consensus, n_sims = 0)

  resolved <- out[out$observation_id %in% c("S1", "S3"), ]
  expect_true(all(!resolved$confirmed_without_occurrence_record))
})

test_that("falls back to unscaled substitution when result has no theta_mean column", {
  result <- .make_result() # no theta_mean column
  consensus <- .make_consensus()
  out <- .upf(result, consensus, n_sims = 0)
  expect_false("theta_mean" %in% names(result))
  # no occurrence scale: the support-weighted target (0.8) is used directly;
  # soft move: 0.5 + (0.8 - 0.5) * (1/6) = 0.55
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  expect_equal(sp_a_s2, 0.55, tolerance = 1e-8)
})

test_that("never-demote still holds under rescaling", {
  result <- .make_result_theta()
  result$prior_mean[result$observation_id == "S2" & result$taxon_name == "Sp_A"] <- 0.9
  consensus <- .make_consensus_theta()
  out <- .upf(result, consensus, n_sims = 0)
  sp_a_s2 <- out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"]
  expect_equal(sp_a_s2, 0.9) # already well above q*ceiling (0.0475) -- untouched
})

test_that("a presence-mixture row has prior_mix_w updated (not cleared) by soft support", {
  set.seed(1) # simulation path: seeded here so other tests cannot shift its stream
  res <- .make_result()
  mixify <- res$observation_id == "S2" & res$taxon_name == "Sp_A"
  res$prior_mean[mixify] <- 1e-4 + (0.02 - 1e-4) * 0.5 # blend at w = 0.5
  res$prior_alpha[mixify] <- 0.02
  res$prior_beta[mixify] <- 1.98
  res$prior_mix_w <- ifelse(mixify, 0.5, NA_real_)
  res$prior_mix_theta_present <- ifelse(mixify, 0.02, NA_real_)
  res$prior_mix_theta_absent <- ifelse(mixify, 1e-4, NA_real_)
  res$prior_mix_p_conc <- ifelse(mixify, 1, NA_real_)

  out <- suppressMessages(suppressWarnings(
    .upf(res, .make_consensus(), n_sims = 50)
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
    th1,
    tolerance = 1e-6
  )
  # never demoted; resolved rows untouched
  expect_gt(boosted$prior_mix_w, 0.5)
  s1 <- out[out$observation_id == "S1", ]
  expect_true(all(is.na(s1$prior_mix_w)))
})

test_that("mixture re-moment-match includes prior_mix_var_present/_absent when supplied (2026-09-05, finding A4)", {
  set.seed(1) # simulation path: seeded here so other tests cannot shift its stream
  # Same fixture as above, but with real (non-zero) within-state variance at
  # the present/absent anchors -- as a real blend-mode
  # apply_undetected_evidence() row now carries. Reproducing v_mix WITHOUT
  # these two terms (the pre-fix formula) would give a smaller v_mix and
  # therefore a LARGER n_eff/alpha+beta (over-concentrated) than reproducing
  # it WITH them -- confirm the fix actually uses the supplied variances by
  # comparing against that pre-fix formula computed by hand.
  res <- .make_result()
  mixify <- res$observation_id == "S2" & res$taxon_name == "Sp_A"
  res$prior_mean[mixify] <- 1e-4 + (0.02 - 1e-4) * 0.5
  res$prior_alpha[mixify] <- 0.02
  res$prior_beta[mixify] <- 1.98
  res$prior_mix_w <- ifelse(mixify, 0.5, NA_real_)
  res$prior_mix_theta_present <- ifelse(mixify, 0.02, NA_real_)
  res$prior_mix_theta_absent <- ifelse(mixify, 1e-4, NA_real_)
  res$prior_mix_p_conc <- ifelse(mixify, 1, NA_real_)
  res$prior_mix_var_present <- ifelse(mixify, 5e-5, NA_real_)
  res$prior_mix_var_absent <- ifelse(mixify, 2e-6, NA_real_)

  out <- suppressMessages(suppressWarnings(
    .upf(res, .make_consensus(), n_sims = 50)
  ))
  boosted <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]

  w1 <- (1 * 0.5 + 0.2) / 1.2
  th1 <- 1e-4 + (0.02 - 1e-4) * w1
  v_mix_with_var <- w1 * (1 - w1) * (0.02 - 1e-4)^2 + w1 * 5e-5 + (1 - w1) * 2e-6
  v_mix_without_var <- w1 * (1 - w1) * (0.02 - 1e-4)^2
  ne_with_var <- max(th1 * (1 - th1) / v_mix_with_var - 1, 1e-3)
  ne_without_var <- max(th1 * (1 - th1) / v_mix_without_var - 1, 1e-3)
  expect_false(isTRUE(all.equal(ne_with_var, ne_without_var))) # sanity: fixture actually discriminates

  observed_phi <- boosted$prior_alpha + boosted$prior_beta
  expect_equal(observed_phi, ne_with_var, tolerance = 1e-6)
  expect_false(isTRUE(all.equal(observed_phi, ne_without_var, tolerance = 1e-6)))
})

test_that("mixture w-update is capped at prior_mix_veto_bound, never exceeds it (2026-09-05, finding B2)", {
  set.seed(1) # simulation path: seeded here so other tests cannot shift its stream
  res <- .make_result()
  mixify <- res$observation_id == "S2" & res$taxon_name == "Sp_A"
  res$prior_mean[mixify] <- 1e-4 + (0.02 - 1e-4) * 0.5
  res$prior_alpha[mixify] <- 0.02
  res$prior_beta[mixify] <- 1.98
  res$prior_mix_w <- ifelse(mixify, 0.5, NA_real_)
  res$prior_mix_theta_present <- ifelse(mixify, 0.02, NA_real_)
  res$prior_mix_theta_absent <- ifelse(mixify, 1e-4, NA_real_)
  res$prior_mix_p_conc <- ifelse(mixify, 1, NA_real_)
  # Uncapped update would reach w1 = (1*0.5 + 0.2)/1.2 = 0.5833... -- set the
  # bound below that so the cap is guaranteed to bind.
  res$prior_mix_veto_bound <- ifelse(mixify, 0.52, NA_real_)

  out <- suppressMessages(suppressWarnings(
    .upf(res, .make_consensus(), n_sims = 50)
  ))
  boosted <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_equal(boosted$prior_mix_w, 0.52, tolerance = 1e-8)
  expect_equal(boosted$prior_mean,
    1e-4 + (0.02 - 1e-4) * 0.52,
    tolerance = 1e-8
  )

  msgs <- capture_messages(suppressWarnings(
    .upf(res, .make_consensus(), n_sims = 50)
  ))
  expect_true(any(grepl("veto bound", msgs, ignore.case = TRUE)))
})

test_that("mixture w-update is NOT capped when prior_mix_veto_bound is NA or the column is absent", {
  set.seed(1) # simulation path: seeded here so other tests cannot shift its stream
  res <- .make_result()
  mixify <- res$observation_id == "S2" & res$taxon_name == "Sp_A"
  res$prior_mean[mixify] <- 1e-4 + (0.02 - 1e-4) * 0.5
  res$prior_alpha[mixify] <- 0.02
  res$prior_beta[mixify] <- 1.98
  res$prior_mix_w <- ifelse(mixify, 0.5, NA_real_)
  res$prior_mix_theta_present <- ifelse(mixify, 0.02, NA_real_)
  res$prior_mix_theta_absent <- ifelse(mixify, 1e-4, NA_real_)
  res$prior_mix_p_conc <- ifelse(mixify, 1, NA_real_)
  # No prior_mix_veto_bound column at all -- backward compatible, uncapped.

  out <- suppressMessages(suppressWarnings(
    .upf(res, .make_consensus(), n_sims = 50)
  ))
  boosted <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  w1 <- (1 * 0.5 + 0.2) / 1.2
  expect_equal(boosted$prior_mix_w, w1, tolerance = 1e-8)
})

# ---- Group-local evidence (detections + group_cols) ---------------------------
# Fixture builder: one observation's hypothesis rows. `post` is the observation's
# posterior support for each taxon; every prior starts at `prior`.
.obs_rows <- function(id, taxa, post, prior = 0.1) {
  tibble(
    observation_id = id,
    taxon_name = taxa,
    taxon_name_rank = "species",
    hypothesis_type = "specific_candidate",
    score_likelihood = post,
    score_likelihood_mean = post,
    score_likelihood_sd = 0.05,
    prior_mean = prior,
    prior_alpha = prior * 10,
    prior_beta = (1 - prior) * 10,
    posterior_point_est = post,
    posterior_mean = post,
    posterior_sd = 0.05,
    confidence_score = post
  )
}
.cons <- function(ids, resolved) {
  tibble(
    observation_id = ids,
    consensus_taxon = ifelse(resolved, "resolved_taxon", NA_character_),
    consensus_rank = ifelse(resolved, "species", NA_character_),
    is_resolved = resolved,
    consensus_posterior = ifelse(resolved, 0.9, NA_real_)
  )
}
.prior_of <- function(out, id, taxon) {
  out$prior_mean[out$observation_id == id & out$taxon_name == taxon]
}

# Two groups. Sp_X is strongly supported only in group A (S1); S2 is the
# unresolved observation that carries an Sp_X hypothesis. S3/S4 make both
# groups multi-member, so nothing is skipped as a singleton.
.two_group_fixture <- function() {
  list(
    result = bind_rows(
      .obs_rows("S1", c("Sp_X", "Sp_Y"), c(0.9, 0.1)),
      .obs_rows("S2", c("Sp_X", "Sp_W"), c(0.5, 0.5)),
      .obs_rows("S3", c("Sp_Z", "Sp_Y"), c(0.9, 0.1)),
      .obs_rows("S4", c("Sp_Q", "Sp_Y"), c(0.9, 0.1))
    ),
    consensus = .cons(c("S1", "S2", "S3", "S4"), c(TRUE, FALSE, TRUE, TRUE))
  )
}

test_that("isolation: support in group A never raises a hypothesis in group B (spatial_group_map)", {
  fx <- .two_group_fixture()
  map <- tibble(
    observation_id   = c("S1", "S3", "S2", "S4"),
    spatial_group_id = c("A", "A", "B", "B")
  )
  out <- suppressMessages(.upf(fx$result, fx$consensus,
    n_sims = 0, spatial_group_map = map
  ))
  expect_equal(.prior_of(out, "S2", "Sp_X"), 0.1)
})

test_that("isolation: support in group A never raises a hypothesis in group B (detections)", {
  fx <- .two_group_fixture()
  det <- tibble(observation_id = c("S1", "S3", "S2", "S4"), site = c("A", "A", "B", "B"))
  out <- suppressMessages(.upf(fx$result, fx$consensus,
    n_sims = 0, detections = det, group_cols = "site"
  ))
  expect_equal(.prior_of(out, "S2", "Sp_X"), 0.1)
})

test_that("within-group donation: the same observation placed in group A is raised", {
  fx <- .two_group_fixture()
  det <- tibble(observation_id = c("S1", "S3", "S2", "S4"), site = c("A", "A", "A", "B"))
  out <- suppressMessages(.upf(fx$result, fx$consensus,
    n_sims = 0, detections = det, group_cols = "site"
  ))
  expect_gt(.prior_of(out, "S2", "Sp_X"), 0.1)
})

test_that("cross-marker: observations from two markers sharing a sample id donate", {
  result <- bind_rows(
    .obs_rows("COI_ESV9", c("Sp_X", "Sp_Y"), c(0.9, 0.1)),
    .obs_rows("12S_ESV1", c("Sp_X", "Sp_W"), c(0.5, 0.5))
  )
  consensus <- .cons(c("COI_ESV9", "12S_ESV1"), c(TRUE, FALSE))
  det <- tibble(
    observation_id = c("COI_ESV9", "12S_ESV1"),
    sample_id = c("tube_1", "tube_1"),
    marker = c("COI", "12S")
  )
  out <- suppressMessages(.upf(result, consensus,
    n_sims = 0, detections = det
  ))
  expect_gt(.prior_of(out, "12S_ESV1", "Sp_X"), 0.1)

  # Same tube written differently per marker: nothing is shared, and the
  # function says so rather than silently pooling nothing.
  det_bad <- det
  det_bad$sample_id <- c("tube_1", "TUBE_1")
  expect_message(
    out_bad <- .upf(result, consensus,
      n_sims = 0, detections = det_bad
    ),
    "every group holds a single marker"
  )
  expect_equal(.prior_of(out_bad, "12S_ESV1", "Sp_X"), 0.1)
})

test_that("multi-group observation: per-group gains are averaged (hand-computed)", {
  # U sits in groups A and B. No theta_mean column, so the target is the
  # support-weighted quantile itself.
  #   A = {O1, U}: Sp_X support 0.8 + 0.5 = 1.3; leave-one-out 0.8;
  #       m = 0.25 * 0.8 = 0.2, s = 0.2 / 1.2 = 1/6;
  #       target = weighted 0.9-quantile of {0.5, 0.8} = 0.8;
  #       gain_A = (0.8 - 0.1) / 6 = 0.1166667
  #   B = {O2, U}: Sp_X support 0.4 + 0.5 = 0.9; leave-one-out 0.4;
  #       m = 0.1, s = 0.1 / 1.1 = 1/11;
  #       target = weighted 0.9-quantile of {0.4, 0.5} = 0.5;
  #       gain_B = (0.5 - 0.1) / 11 = 0.0363636
  #   prior = 0.1 + (gain_A + gain_B) / 2 = 0.1765152
  result <- bind_rows(
    .obs_rows("O1", c("Sp_X", "Sp_C"), c(0.8, 0.2)),
    .obs_rows("O2", c("Sp_X", "Sp_D"), c(0.4, 0.6)),
    .obs_rows("U", c("Sp_X", "Sp_B"), c(0.5, 0.5))
  )
  consensus <- .cons(c("O1", "O2", "U"), c(TRUE, TRUE, FALSE))
  det <- tibble(observation_id = c("O1", "U", "O2", "U"), sample_id = c("A", "A", "B", "B"))
  out <- suppressMessages(.upf(result, consensus,
    n_sims = 0, detections = det
  ))
  expected <- 0.1 + ((0.8 - 0.1) / 6 + (0.5 - 0.1) / 11) / 2
  expect_equal(.prior_of(out, "U", "Sp_X"), expected, tolerance = 1e-12)
  expect_equal(.prior_of(out, "U", "Sp_B"), 0.1) # no support anywhere else
  # Never more than the single best group could give on its own
  expect_lt(.prior_of(out, "U", "Sp_X"), 0.1 + (0.8 - 0.1) / 6)
})

test_that("leave-one-out per group: an observation never confirms itself", {
  # U is the ONLY supporter of Sp_X in group B (O3 has no Sp_X), so group B
  # contributes zero gain; only group A's O1 counts.
  #   A = {O1, U}: support 0.8 + 0.9; LOO 0.8; s = 1/6;
  #       target = weighted 0.9-quantile of {0.8, 0.9} = 0.9;
  #       gain_A = 0.8 / 6
  result <- bind_rows(
    .obs_rows("O1", c("Sp_X", "Sp_C"), c(0.8, 0.2)),
    .obs_rows("O3", c("Sp_Q", "Sp_C"), c(0.9, 0.1)),
    .obs_rows("U", c("Sp_X", "Sp_B"), c(0.9, 0.1))
  )
  consensus <- .cons(c("O1", "O3", "U"), c(TRUE, TRUE, FALSE))
  det <- tibble(observation_id = c("O1", "U", "O3", "U"), sample_id = c("A", "A", "B", "B"))
  out <- suppressMessages(.upf(result, consensus,
    n_sims = 0, detections = det
  ))
  expect_equal(.prior_of(out, "U", "Sp_X"), 0.1 + (0.8 / 6) / 2, tolerance = 1e-12)

  # U only in group B, where it is the sole Sp_X supporter: unchanged.
  det_b <- tibble(observation_id = c("O1", "U", "O3"), sample_id = c("A", "B", "B"))
  out_b <- suppressMessages(.upf(result, consensus,
    n_sims = 0, detections = det_b
  ))
  expect_equal(.prior_of(out_b, "U", "Sp_X"), 0.1)
})

test_that("composite key: group_cols = c('site', 'season') separates seasons", {
  result <- bind_rows(
    .obs_rows("O1", c("Sp_X", "Sp_Y"), c(0.9, 0.1)),
    .obs_rows("O2", c("Sp_Z", "Sp_Y"), c(0.9, 0.1)),
    .obs_rows("U", c("Sp_X", "Sp_W"), c(0.5, 0.5))
  )
  consensus <- .cons(c("O1", "O2", "U"), c(TRUE, TRUE, FALSE))
  det <- tibble(
    observation_id = c("O1", "O2", "U"),
    site = "Reef",
    season = c("spring", "fall", "fall")
  )
  out_both <- suppressMessages(.upf(result, consensus,
    n_sims = 0, detections = det, group_cols = c("site", "season")
  ))
  expect_equal(.prior_of(out_both, "U", "Sp_X"), 0.1)

  out_site <- suppressMessages(.upf(result, consensus,
    n_sims = 0, detections = det, group_cols = "site"
  ))
  expect_gt(.prior_of(out_site, "U", "Sp_X"), 0.1)
})

test_that("per-group report is attached with eligible/updated/raised counts", {
  fx <- .two_group_fixture()
  det <- tibble(observation_id = c("S1", "S3", "S2", "S4"), site = c("A", "A", "A", "B"))
  out <- suppressMessages(.upf(fx$result, fx$consensus,
    n_sims = 0, detections = det, group_cols = "site"
  ))
  rep <- attr(out, "prior_update_groups")
  expect_s3_class(rep, "data.frame")
  a <- rep[rep$group == "A", ]
  expect_equal(a$n_observations, 3L)
  expect_equal(a$n_eligible_unresolved, 1L)
  expect_equal(a$n_observations_updated, 1L)
  expect_equal(a$n_rows_raised, 1L)
  expect_equal(rep$n_rows_raised[rep$group == "B"], 0L)
})

test_that("all-singleton grouping says so and updates nothing", {
  fx <- .two_group_fixture()
  det <- tibble(observation_id = c("S1", "S2", "S3", "S4"), sample_id = c("t1", "t2", "t3", "t4"))
  expect_message(
    out <- .upf(fx$result, fx$consensus, n_sims = 0, detections = det),
    "Every group is a singleton"
  )
  expect_equal(.prior_of(out, "S2", "Sp_X"), 0.1)
})

test_that("NULL detections on multi-site combined priors is refused", {
  fx <- .two_group_fixture()
  fx$result$n_sites_combined <- c(1L, 1L, 3L, 3L, 1L, 1L, 1L, 1L)
  expect_error(
    suppressMessages(.upf(fx$result, fx$consensus, n_sims = 0)),
    "combined across"
  )
})

test_that("NULL detections pools the whole result and says so", {
  fx <- .two_group_fixture()
  expect_message(
    out <- .upf(fx$result, fx$consensus, n_sims = 0),
    "pooled across ALL"
  )
  expect_gt(.prior_of(out, "S2", "Sp_X"), 0.1)
})

test_that("detections and spatial_group_map together is an error; bad inputs are caught", {
  fx <- .two_group_fixture()
  det <- tibble(observation_id = c("S1", "S2"), sample_id = c("t1", "t1"))
  map <- tibble(observation_id = c("S1", "S2"), spatial_group_id = c("g", "g"))
  expect_error(
    .upf(fx$result, fx$consensus,
      detections = det, spatial_group_map = map
    ),
    "not both"
  )
  expect_error(
    .upf(fx$result, fx$consensus,
      detections = det, group_cols = "site"
    ),
    "detections missing required column"
  )
  expect_error(
    .upf(fx$result, fx$consensus,
      detections = tibble(observation_id = "nope", sample_id = "t1")
    ),
    "None of"
  )
})

# ---- memory: narrow merge reproduces merge() exactly (2026-10-05) ----------
test_that(".merge_rows_with() is identical to merge() on the full rows", {
  set.seed(11)
  n <- 60
  r <- data.frame(
    taxon_name = sample(c("A a", "B b", "C c"), n, TRUE),
    observation_id = sample(sprintf("obs%02d", c(3, 1, 10, 2, 7, 22)), n, TRUE), # several rows per obs, shuffled
    posterior_point_est = round(runif(n), 2), # ties
    flag = sample(c(TRUE, FALSE, NA), n, TRUE),
    f = factor(sample(c("x", "y"), n, TRUE)),
    d = as.Date("2026-01-01") + sample(0:5, n, TRUE),
    stringsAsFactors = FALSE
  )
  y <- data.frame(observation_id = sprintf("obs%02d", c(1, 2, 3, 7)), # obs10 / obs22 unmatched
    consensus_taxon_v1 = c("A a", NA, "B b", "C c"), consensus_rank_v1 = "species", stringsAsFactors = FALSE)
  for (idx in list(seq_len(n), which(r$flag %in% TRUE), sample(n, 20), integer(0))) {
    expect_identical(TaxaAssign:::.merge_rows_with(r, idx, y),
      merge(r[idx, , drop = FALSE], y, by = "observation_id", all.x = TRUE))
  }
  # the narrow path is the one taken for a plain data.frame (not the fallback)
  called <- 0L
  real_merge <- base::merge # captured BEFORE mocking (the mock must not call itself)
  local_mocked_bindings(merge = function(x, ...) { called <<- called + 1L; expect_identical(names(x), c("observation_id", ".upfc_row")); real_merge(x, ...) }, .package = "base")
  TaxaAssign:::.merge_rows_with(r, seq_len(n), y)
  expect_equal(called, 1L)
})

test_that(".merge_rows_with() falls back to merge() where it would differ (tibble, name collision)", {
  r <- data.frame(observation_id = c("o2", "o1", "o2"), consensus_taxon_v1 = "old", v = 1:3, stringsAsFactors = FALSE)
  y <- data.frame(observation_id = c("o1", "o2"), consensus_taxon_v1 = c("A", "B"), stringsAsFactors = FALSE)
  expect_identical(TaxaAssign:::.merge_rows_with(r, 1:3, y), merge(r, y, by = "observation_id", all.x = TRUE))
  tb <- dplyr::as_tibble(r[, c("observation_id", "v")])
  expect_identical(TaxaAssign:::.merge_rows_with(tb, 1:3, y), merge(tb, y, by = "observation_id", all.x = TRUE))
})

test_that(".merge_rows_with() matches merge() with NA keys and with keys repeated on BOTH sides", {
  set.seed(5)
  r <- data.frame(observation_id = sample(c("o1", "o2", NA, "o3"), 30, TRUE),
    v = 1:30, w = sample(letters, 30, TRUE), stringsAsFactors = FALSE)
  # NA key in x and in y: merge() pairs NA with NA (match() treats NA as matchable)
  y_na <- data.frame(observation_id = c("o2", NA, "o1"), consensus_taxon_v1 = c("B", "N", "A"),
    stringsAsFactors = FALSE)
  for (idx in list(seq_len(30), which(is.na(r$observation_id)), sample(30, 12))) {
    expect_identical(TaxaAssign:::.merge_rows_with(r, idx, y_na),
      merge(r[idx, , drop = FALSE], y_na, by = "observation_id", all.x = TRUE))
  }
  # keys repeated on both sides: a cartesian block per key, ordered by the pairing of match indices
  y_dup <- data.frame(observation_id = c("o1", "o2", "o1", "o3", "o2", "o1"),
    consensus_taxon_v1 = c("A1", "B1", "A2", "C1", "B2", "A3"), stringsAsFactors = FALSE)
  for (idx in list(seq_len(30), sample(30, 17))) {
    got <- TaxaAssign:::.merge_rows_with(r, idx, y_dup)
    expect_identical(got, merge(r[idx, , drop = FALSE], y_dup, by = "observation_id", all.x = TRUE))
    expect_gt(nrow(got), length(idx)) # the cartesian expansion really happened
  }
})

# ---- referenced candidates only (2026-10-06) ---------------------------------
test_that("an unreferenced-relative row is never raised by the soft confirmation", {
  r <- .make_result()
  r$hypothesis_type[r$observation_id == "S2" & r$taxon_name == "Sp_A"] <- "unreferenced_species"
  out <- suppressMessages(.upf(r, .make_consensus()))
  row <- out[out$observation_id == "S2" & out$taxon_name == "Sp_A", ]
  expect_equal(row$prior_mean, 0.5) # unchanged, although S1 confirms Sp_A
  # control: the same row as a referenced candidate IS raised
  out0 <- suppressMessages(.upf(.make_result(), .make_consensus()))
  expect_gt(out0$prior_mean[out0$observation_id == "S2" & out0$taxon_name == "Sp_A"], 0.5)
})

test_that("an unreferenced-relative row's posterior does not confirm a species elsewhere", {
  r <- .make_result()
  r$hypothesis_type[r$observation_id == "S1" & r$taxon_name == "Sp_A"] <- "unreferenced_species"
  out <- suppressMessages(.upf(r, .make_consensus()))
  expect_equal(out$prior_mean[out$observation_id == "S2" & out$taxon_name == "Sp_A"], 0.5)
})


# ---- Receiver guards (2026-10-07): likelihood node (G3), occurrence record (G1) ----
.g_rows <- function(id, taxa, phylum, L, prior = 1e-3, theta = 0.01) {
  tibble(observation_id = id, taxon_name = taxa, taxon_name_rank = "species",
    hypothesis_type = "specific_candidate", phylum = phylum, genus = sub(" .*", "", taxa),
    score_likelihood = L, score_likelihood_mean = L, score_likelihood_sd = 0.01,
    prior_mean = prior, prior_alpha = prior * 100, prior_beta = (1 - prior) * 100, theta_mean = theta,
    posterior_point_est = L / sum(L), posterior_mean = L / sum(L), posterior_sd = 0.01, confidence_score = L / sum(L))
}
.g_cons <- function(ids, resolved, taxon, lik_taxon, lik_rank) {
  tibble(observation_id = ids, consensus_taxon = ifelse(resolved, taxon, NA_character_),
    consensus_rank = ifelse(resolved, "species", NA_character_), is_resolved = resolved,
    consensus_posterior = ifelse(resolved, 0.95, NA_real_),
    likelihood_consensus_taxon = lik_taxon, likelihood_consensus_rank = lik_rank)
}
# S1 and S3 resolve Dictyota dichotoma (donor support); S2 is a red-alga sequence: Neoporphyra
# haitanensis fits (L 1.0), Dictyota does not (L 0.016). S2's likelihood node is the red-alga species.
.dictyota_fixture <- function() {
  list(
    result = bind_rows(
      .g_rows("S1", "Dictyota dichotoma", "Ochrophyta", 1),
      .g_rows("S3", "Dictyota dichotoma", "Ochrophyta", 1),
      .g_rows("S2", c("Neoporphyra haitanensis", "Dictyota dichotoma"), c("Rhodophyta", "Ochrophyta"), c(1, 0.016))
    ),
    consensus = .g_cons(c("S1", "S3", "S2"), c(TRUE, TRUE, FALSE), "Dictyota dichotoma",
      c("Dictyota dichotoma", "Dictyota dichotoma", "Neoporphyra haitanensis"), "species")
  )
}

test_that("G3: a supported row OUTSIDE its observation's likelihood node is never raised (Dictyota)", {
  fx <- .dictyota_fixture()
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0))
  expect_equal(.prior_of(out, "S2", "Dictyota dichotoma"), 1e-3)
  expect_message(.upg0(fx$result, fx$consensus, n_sims = 0),
    "1 supported row\\(s\\) not raised because they lie outside")
  # CONTROL: the same row IS raised with the guards explicitly off ...
  expect_message(off <- update_prior_from_consensus(fx$result, fx$consensus, n_sims = 0, require_support_columns = FALSE),
    "require_support_columns = FALSE")
  expect_gt(.prior_of(off, "S2", "Dictyota dichotoma"), 1e-3)
  # ... and when S2's node contains it and it ties the best likelihood (G4 then lets it through)
  inside <- fx$consensus
  inside$likelihood_consensus_taxon[3] <- "Ochrophyta"; inside$likelihood_consensus_rank[3] <- "phylum"
  tie <- fx$result; tie$score_likelihood[tie$observation_id == "S2" & tie$taxon_name == "Dictyota dichotoma"] <- 1
  expect_gt(.prior_of(suppressMessages(.upg0(tie, inside, n_sims = 0)), "S2", "Dictyota dichotoma"), 1e-3)
})

test_that("G3: an observation with no likelihood node has no row raised", {
  fx <- .dictyota_fixture()
  fx$consensus$likelihood_consensus_taxon[3] <- NA; fx$consensus$likelihood_consensus_rank[3] <- NA
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0))
  expect_equal(.prior_of(out, "S2", "Dictyota dichotoma"), 1e-3)
  expect_equal(.prior_of(out, "S2", "Neoporphyra haitanensis"), 1e-3)
})

test_that("G1: an unrecorded row INSIDE the likelihood node is not raised; a recorded one is (Aplanochytrium)", {
  # S2's node is the phylum Bigyra; both candidates are inside it. Aplanochytrium has no
  # occurrence record (theta NA); Thraustochytrium has one. Both have donor support.
  res <- bind_rows(
    .g_rows("S1", "Aplanochytrium stocchinoi", "Bigyra", 1, theta = NA),
    .g_rows("S3", "Thraustochytrium kinnei", "Bigyra", 1),
    .g_rows("S2", c("Aplanochytrium stocchinoi", "Thraustochytrium kinnei"), "Bigyra", c(0.378, 0.378), theta = c(NA, 0.01))
  )
  cons <- tibble(observation_id = c("S1", "S3", "S2"),
    consensus_taxon = c("Aplanochytrium stocchinoi", "Thraustochytrium kinnei", NA),
    consensus_rank = c("species", "species", NA), is_resolved = c(TRUE, TRUE, FALSE),
    consensus_posterior = c(0.95, 0.95, NA),
    likelihood_consensus_taxon = c("Aplanochytrium stocchinoi", "Thraustochytrium kinnei", "Bigyra"),
    likelihood_consensus_rank = c("species", "species", "phylum"))
  out <- suppressMessages(.upg0(res, cons, n_sims = 0))
  expect_equal(.prior_of(out, "S2", "Aplanochytrium stocchinoi"), 1e-3)
  expect_gt(.prior_of(out, "S2", "Thraustochytrium kinnei"), 1e-3)
  expect_false(any(out$confirmed_without_occurrence_record))
  # CONTROL: with the guards off the unrecorded row IS raised
  expect_gt(.prior_of(suppressMessages(update_prior_from_consensus(res, cons, n_sims = 0, require_support_columns = FALSE)),
    "S2", "Aplanochytrium stocchinoi"), 1e-3)
})

test_that("the receiver guards stop, naming the column, when their inputs are missing", {
  fx <- .dictyota_fixture()
  no_lik <- fx$consensus[, setdiff(names(fx$consensus), c("likelihood_consensus_taxon", "likelihood_consensus_rank"))]
  expect_error(.upg(fx$result, no_lik, n_sims = 0), "likelihood_consensus_taxon")
  expect_error(.upg(fx$result[, setdiff(names(fx$result), "theta_mean")], fx$consensus, n_sims = 0),
    "theta_mean")
  expect_error(update_prior_from_consensus(fx$result, fx$consensus, n_sims = 0, require_support_columns = NA), "require_support_columns")
  # with the guards off, neither column is needed
  expect_s3_class(suppressMessages(update_prior_from_consensus(fx$result[, setdiff(names(fx$result), "theta_mean")], no_lik,
    n_sims = 0, require_support_columns = FALSE)), "data.frame")
})

# ---- G4: a prior boost must not overturn the likelihood ordering (2026-10-07) ----
# S1 and S3 resolve the recorded Acrochaetium catenulatum (donor support at the Site). S2's sequence fits
# A. humile better (L 0.20 vs 0.0046). Its likelihood node is the class, so both are inside it (G3 passes).
.acro_fixture <- function(L_cat = 0.0046, L_hum = 0.20, theta_hum = 0.01) {
  r <- bind_rows(
    .g_rows("S1", "Acrochaetium catenulatum", "Rhodophyta", 1),
    .g_rows("S3", "Acrochaetium catenulatum", "Rhodophyta", 1),
    .g_rows("S2", c("Acrochaetium catenulatum", "Acrochaetium humile"), "Rhodophyta", c(L_cat, L_hum), theta = c(0.01, theta_hum))
  )
  r$class <- "Florideophyceae"
  list(result = r, consensus = .g_cons(c("S1", "S3", "S2"), c(TRUE, TRUE, FALSE), "Acrochaetium catenulatum",
    c("Acrochaetium catenulatum", "Acrochaetium catenulatum", "Florideophyceae"), c("species", "species", "class")))
}

test_that("G4: a lower-likelihood referenced row is not raised over a better one (Acrochaetium inversion)", {
  fx <- .acro_fixture()
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0))
  expect_equal(.prior_of(out, "S2", "Acrochaetium catenulatum"), 1e-3)
  expect_message(.upg0(fx$result, fx$consensus, n_sims = 0),
    "1 not raised because another referenced candidate in the observation has a higher likelihood")
  # CONTROL: with the guards off, the same row IS raised
  expect_gt(.prior_of(suppressMessages(update_prior_from_consensus(fx$result, fx$consensus, n_sims = 0,
    require_support_columns = FALSE)), "S2", "Acrochaetium catenulatum"), 1e-3)
})

test_that("G4: a tie is allowed (Round 2 may break it)", {
  fx <- .acro_fixture(L_cat = 0.2, L_hum = 0.2)
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0))
  expect_gt(.prior_of(out, "S2", "Acrochaetium catenulatum"), 1e-3)
})

test_that("G4: of two supported congeners, only the better-likelihood one is raised (no splitting)", {
  fx <- .acro_fixture(L_cat = 0.1, L_hum = 0.9)
  s4 <- .g_rows("S4", "Acrochaetium humile", "Rhodophyta", 1); s4$class <- "Florideophyceae"
  fx$result <- bind_rows(fx$result, s4)
  fx$consensus <- bind_rows(fx$consensus, .g_cons("S4", TRUE, "Acrochaetium humile", "Acrochaetium humile", "species"))
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0))
  expect_gt(.prior_of(out, "S2", "Acrochaetium humile"), 1e-3)
  expect_equal(.prior_of(out, "S2", "Acrochaetium catenulatum"), 1e-3)
  # CONTROL: with the guards off BOTH are raised (the split G4 removes)
  off <- suppressMessages(update_prior_from_consensus(fx$result, fx$consensus, n_sims = 0, require_support_columns = FALSE))
  expect_gt(.prior_of(off, "S2", "Acrochaetium catenulatum"), 1e-3)
  expect_gt(.prior_of(off, "S2", "Acrochaetium humile"), 1e-3)
})

test_that("G4: an UNREFERENCED row with a higher likelihood does not block a referenced one", {
  fx <- .acro_fixture(L_cat = 0.5, L_hum = 0.2)
  ring <- .g_rows("S2", "Acrochaetium", "Rhodophyta", 1, theta = NA)
  ring$class <- "Florideophyceae"; ring$hypothesis_type <- "unreferenced_species"; ring$taxon_name_rank <- "genus"
  fx$result <- bind_rows(fx$result, ring)
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0))
  expect_gt(.prior_of(out, "S2", "Acrochaetium catenulatum"), 1e-3)
})

test_that("G4: an NA-likelihood comparator is left out; an NA-likelihood receiver is never raised", {
  fx <- .acro_fixture(L_cat = 0.0046, L_hum = NA)
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0))
  expect_gt(.prior_of(out, "S2", "Acrochaetium catenulatum"), 1e-3)
  fx2 <- .acro_fixture(L_cat = NA, L_hum = 0.2)
  out2 <- suppressMessages(.upg0(fx2$result, fx2$consensus, n_sims = 0))
  expect_equal(.prior_of(out2, "S2", "Acrochaetium catenulatum"), 1e-3)
})


# ---- G5: a raise must beat the runner-up by more than the likelihood noise ----
# S1 and S3 resolve Clupea harengus (donor support). S2's likelihood node is the genus. G6 is stubbed
# (.upg0) so these tests see the margin alone.
.clupea_fixture <- function(L = c(1, 0.995), sd = c(0.05, 0.05), taxa = c("Clupea harengus", "Clupea pallasii")) {
  s2 <- .g_rows("S2", taxa, "Chordata", L)
  s2$score_likelihood_sd <- sd
  list(result = bind_rows(.g_rows("S1", "Clupea harengus", "Chordata", 1), .g_rows("S3", "Clupea harengus", "Chordata", 1), s2),
    consensus = .g_cons(c("S1", "S3", "S2"), c(TRUE, TRUE, FALSE), "Clupea harengus",
      c("Clupea harengus", "Clupea harengus", "Clupea"), c("species", "species", "genus")))
}

test_that("G5: a near-tie is not broken (Clupea harengus 1 vs C. pallasii 0.995)", {
  fx <- .clupea_fixture()
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0, likelihood_margin_z = 1.96))
  expect_equal(.prior_of(out, "S2", "Clupea harengus"), 1e-3)
  expect_message(.upg0(fx$result, fx$consensus, n_sims = 0, likelihood_margin_z = 1.96),
    "1 not raised because their likelihood does not beat")
  # CONTROL: without the margin (G4 alone) the same row IS raised
  expect_gt(.prior_of(suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0)), "S2", "Clupea harengus"), 1e-3)
})

test_that("G5: a clear likelihood lead is raised", {
  fx <- .clupea_fixture(L = c(1, 0.2))
  out <- suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0, likelihood_margin_z = 1.96))
  expect_gt(.prior_of(out, "S2", "Clupea harengus"), 1e-3)
})

test_that("G5: the band uses both rows' sd (a noisy runner-up widens it)", {
  # gap 0.2: band sqrt(0.05^2 + 0.2^2) = 0.206 -> 0.2 < 1.96 * 0.206, not raised;
  # band sqrt(0.05^2 + 0.05^2) = 0.0707 -> 0.2 > 0.139, raised
  wide <- .clupea_fixture(L = c(1, 0.8), sd = c(0.05, 0.2))
  narrow <- .clupea_fixture(L = c(1, 0.8), sd = c(0.05, 0.05))
  expect_equal(.prior_of(suppressMessages(.upg0(wide$result, wide$consensus, n_sims = 0, likelihood_margin_z = 1.96)),
    "S2", "Clupea harengus"), 1e-3)
  expect_gt(.prior_of(suppressMessages(.upg0(narrow$result, narrow$consensus, n_sims = 0, likelihood_margin_z = 1.96)),
    "S2", "Clupea harengus"), 1e-3)
})

test_that("G5: among comparators tied on likelihood, the larger sd sets the band", {
  # two runners-up at 0.9 with sd 0.01 and 0.2: the wider band (0.2) blocks a 0.1 lead;
  # had the 0.01 one been used (band 0.014) the row would be raised
  fx <- .clupea_fixture(L = c(1, 0.9, 0.9), sd = c(0.01, 0.01, 0.2),
    taxa = c("Clupea harengus", "Clupea pallasii", "Clupea bentincki"))
  expect_equal(.prior_of(suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0, likelihood_margin_z = 1.96)),
    "S2", "Clupea harengus"), 1e-3)
  fx2 <- .clupea_fixture(L = c(1, 0.9, 0.9), sd = c(0.01, 0.01, 0.01),
    taxa = c("Clupea harengus", "Clupea pallasii", "Clupea bentincki"))
  expect_gt(.prior_of(suppressMessages(.upg0(fx2$result, fx2$consensus, n_sims = 0, likelihood_margin_z = 1.96)),
    "S2", "Clupea harengus"), 1e-3)
})

test_that("G5: a sole referenced candidate (only an unreferenced rival) is raised", {
  fx <- .clupea_fixture(L = 1, sd = 0.05, taxa = "Clupea harengus")
  ring <- .g_rows("S2", "Clupea", "Chordata", 1, theta = NA)
  ring$hypothesis_type <- "unreferenced_species"; ring$taxon_name_rank <- "genus"
  fx$result <- bind_rows(fx$result, ring)
  expect_gt(.prior_of(suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0, likelihood_margin_z = 1.96)),
    "S2", "Clupea harengus"), 1e-3)
})

test_that("G5: a missing sd leaves the band undefined, so the row is not raised", {
  fx <- .clupea_fixture(L = c(1, 0.2), sd = c(0.05, NA))
  expect_equal(.prior_of(suppressMessages(.upg0(fx$result, fx$consensus, n_sims = 0, likelihood_margin_z = 1.96)),
    "S2", "Clupea harengus"), 1e-3)
})

test_that("the likelihood margin is an internal constant (1.96), not an argument", {
  expect_identical(.ROUND2_LIKELIHOOD_MARGIN_Z, 1.96)
  expect_false(any(c("likelihood_margin_z", "consensus_args") %in% names(formals(update_prior_from_consensus))))
  # the production path uses it: the Clupea near-tie is held back without mocking anything but G6
  fx <- .clupea_fixture()
  stub <- function() data.frame(observation_id = unique(posterior_df$observation_id), consensus_rank = NA_character_)
  formals(stub) <- formals(posterior_consensus)
  local_mocked_bindings(posterior_consensus = stub)
  expect_equal(.prior_of(suppressMessages(.upg(fx$result, fx$consensus, n_sims = 0)), "S2", "Clupea harengus"), 1e-3)
})

# ---- G6: Round 2 may not create a species call the likelihood alone does not make ----
test_that("G6: a raise that would make a species call is undone when the likelihood-only call is coarser", {
  fx <- .clupea_fixture(L = c(1, 0.2))
  expect_message(out <- .upg(fx$result, fx$consensus, n_sims = 0), "species guard undid every raise in 1 observation")
  expect_equal(attr(out, "round2_species_guard"), "S2")
  # every prior column of S2 is back at its Round 1 value, and the posterior is recomputed from it
  r1 <- fx$result[fx$result$observation_id == "S2", ]
  r2 <- out[out$observation_id == "S2", ]
  r2 <- r2[match(r1$taxon_name, r2$taxon_name), ]
  expect_equal(r2$prior_mean, r1$prior_mean)
  expect_equal(r2$prior_alpha, r1$prior_alpha)
  expect_equal(r2$prior_beta, r1$prior_beta)
  ref <- compute_posterior(r1[, setdiff(names(r1), c("posterior_point_est", "posterior_mean", "posterior_sd", "confidence_score"))], n_sims = 0)
  expect_equal(r2$posterior_point_est, ref$posterior_point_est[match(r1$taxon_name, ref$taxon_name)])
})

test_that("G6: the raise is kept when the likelihood-only call is already a species", {
  fx <- .clupea_fixture(L = c(1, 0.2))
  fx$consensus$likelihood_consensus_taxon[3] <- "Clupea harengus"; fx$consensus$likelihood_consensus_rank[3] <- "species"
  out <- suppressMessages(.upg(fx$result, fx$consensus, n_sims = 0))
  expect_gt(.prior_of(out, "S2", "Clupea harengus"), 1e-3)
  expect_length(attr(out, "round2_species_guard"), 0L)
})

test_that("G6: a raise that leaves the call coarser than species is kept", {
  # three candidates; the raised one stays well under the 0.9 credible mass, so the call is the genus
  fx <- .clupea_fixture(L = c(0.5, 0.45, 0.45), sd = c(0.01, 0.01, 0.01),
    taxa = c("Clupea harengus", "Clupea pallasii", "Clupea bentincki"))
  out <- suppressMessages(.upg(fx$result, fx$consensus, n_sims = 0))
  expect_gt(.prior_of(out, "S2", "Clupea harengus"), 1e-3)
  expect_length(attr(out, "round2_species_guard"), 0L)
  chk <- posterior_consensus(out[out$observation_id == "S2", ], cumulative_threshold = 0.9, min_posterior = 0.05)
  expect_false(chk$consensus_rank %in% "species")
})

test_that("G6 stops, with the fix, when the consensus carries no settings, and checks them", {
  fx <- .clupea_fixture()
  # a hand-built consensus has no settings attribute
  expect_error(update_prior_from_consensus(fx$result, fx$consensus, n_sims = 0), "consensus_settings")
  # row subsetting keeps it; merge() drops it, and the update stops rather than skipping the guard
  expect_identical(attr(.with_settings(fx$consensus)[1:3, ], "consensus_settings"), .CARGS)
  sub <- merge(.with_settings(fx$consensus), data.frame(observation_id = c("S1", "S2", "S3")))
  expect_null(attr(sub, "consensus_settings"))
  expect_error(update_prior_from_consensus(fx$result, sub, n_sims = 0), "Re-attach")
  # re-attaching restores the guarded run
  attr(sub, "consensus_settings") <- .CARGS
  expect_s3_class(suppressMessages(update_prior_from_consensus(fx$result, sub, n_sims = 0)), "data.frame")
  expect_error(.upg(fx$result, fx$consensus, n_sims = 0, settings = list(not_an_arg = 1)), "not_an_arg")
  expect_error(.upg(fx$result, fx$consensus, n_sims = 0, settings = list(0.9)), "named list")
  # the shim does not need them
  expect_s3_class(suppressMessages(update_prior_from_consensus(fx$result, fx$consensus, n_sims = 0,
    require_support_columns = FALSE)), "data.frame")
})

test_that("posterior_consensus() attaches its own settings, and the species guard reuses them", {
  fx <- .clupea_fixture(L = c(1, 0.2))
  cons <- posterior_consensus(fx$result, cumulative_threshold = 0.8, min_posterior = 0.05)
  cs <- attr(cons, "consensus_settings")
  expect_identical(sort(names(cs)), sort(setdiff(names(formals(posterior_consensus)), "posterior_df")))
  expect_identical(cs$cumulative_threshold, 0.8)
  expect_identical(cs$consensus_method, "lca") # match.arg()'d, as the call used it
  # the guard's consensus is called with exactly those settings
  seen <- NULL
  real <- posterior_consensus
  spy <- function() {
    seen <<- list(cumulative_threshold = cumulative_threshold, consensus_method = consensus_method)
    real(posterior_df, cumulative_threshold = cumulative_threshold, min_posterior = min_posterior,
      consensus_method = consensus_method)
  }
  formals(spy) <- formals(posterior_consensus)
  x <- fx$consensus
  attr(x, "consensus_settings") <- cs
  local_mocked_bindings(posterior_consensus = spy)
  suppressMessages(update_prior_from_consensus(fx$result, x, n_sims = 0))
  expect_identical(seen, list(cumulative_threshold = 0.8, consensus_method = "lca"))
})
