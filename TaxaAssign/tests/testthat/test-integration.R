# tests/testthat/test-integration.R
# Cross-package integration tests for the TaxaID ecosystem.
# Tests the data flow between packages using synthetic data.
# Skips tests when upstream packages are not installed.

library(dplyr)

# ==============================================================================
# Shared synthetic data — realistic enough to flow through the full pipeline
# ==============================================================================

# Simulates the output of TaxaMatch::standardize_match_data()
.make_match_df <- function() {
  tibble(
    observation_id       = rep(c("ESV_001", "ESV_002"), each = 3),
    score_original = c(99.5, 95.2, 88.0, 97.1, 96.8, 80.0),
    taxon_name      = c("Fundulus parvipinnis", "Fundulus lima",
                        "Atherinops affinis",
                        "Fundulus parvipinnis", "Atherinops affinis",
                        "Mugil cephalus"),
    taxon_name_rank = "species",
    family          = c("Fundulidae", "Fundulidae", "Atherinopsidae",
                        "Fundulidae", "Atherinopsidae", "Mugilidae"),
    genus           = c("Fundulus", "Fundulus", "Atherinops",
                        "Fundulus", "Atherinops", "Mugil"),
    species         = c("Fundulus parvipinnis", "Fundulus lima",
                        "Atherinops affinis",
                        "Fundulus parvipinnis", "Atherinops affinis",
                        "Mugil cephalus"),
    testid          = "MiFishU"
  )
}

# ==============================================================================
# Test 1: TaxaTools create_taxon_names -> match object columns
# ==============================================================================

test_that("TaxaTools::create_taxon_names produces match-compatible columns", {
  skip_if_not_installed("TaxaTools")

  df <- data.frame(
    family  = c("Fundulidae", "Atherinopsidae"),
    genus   = c("Fundulus", "Atherinops"),
    species = c("Fundulus parvipinnis", "Atherinops affinis"),
    stringsAsFactors = FALSE
  )

  out <- TaxaTools::create_taxon_names(df, rank_system = c("family", "genus", "species"))
  expect_true("taxon_name" %in% names(out))
  expect_true("taxon_name_rank" %in% names(out))
  expect_equal(out$taxon_name, c("Fundulus parvipinnis", "Atherinops affinis"))
  expect_equal(out$taxon_name_rank, c("species", "species"))
})

# ==============================================================================
# Test 2: TaxaTools detect_ranks -> TaxaLikely evaluate_likelihoods rank_system
# ==============================================================================

test_that("TaxaTools::detect_ranks on match_df yields valid rank_system", {
  skip_if_not_installed("TaxaTools")

  match_df <- .make_match_df()
  ranks <- TaxaTools::detect_ranks(match_df)
  expect_true(length(ranks) >= 2L)
  expect_true("species" %in% ranks)
  expect_true("genus" %in% ranks || "family" %in% ranks)
})

# ==============================================================================
# Test 3: TaxaLikely likelihood output -> TaxaAssign compute_posterior
# ==============================================================================

test_that("TaxaLikely likelihood columns feed into compute_posterior", {
  # Simulate evaluate_likelihoods output
  lik <- tibble(
    observation_id            = rep("ESV_001", 3),
    taxon_name           = c("Fundulus parvipinnis", "Fundulus lima", "Fundulus"),
    taxon_name_rank      = c("species", "species", "genus"),
    hypothesis_type      = c("specific_candidate", "specific_candidate",
                             "unreferenced_species"),
    score_likelihood = c(0.85, 0.30, 0.15),
    score_likelihood_mean      = c(0.83, 0.31, 0.15),
    score_likelihood_sd        = c(0.05, 0.04, 0.03),
    # Priors (would come from join_priors in real pipeline)
    prior_mean           = c(0.5, 0.3, 0.2),
    prior_alpha          = c(5, 3, 2),
    prior_beta           = c(5, 7, 8),
    genus                = c("Fundulus", "Fundulus", "Fundulus"),
    family               = c("Fundulidae", "Fundulidae", "Fundulidae"),
    species              = c("Fundulus parvipinnis", "Fundulus lima", NA)
  )

  result <- compute_posterior(lik, n_sims = 100)

  expect_true(all(c("posterior_point_est", "posterior_mean",
                     "posterior_sd", "confidence_score") %in% names(result)))
  expect_equal(nrow(result), 3L)
  expect_true(all(result$posterior_point_est >= 0))
  expect_true(all(result$posterior_point_est <= 1))
  # Posteriors should sum to ~1 within sample
  post_sum <- sum(result$posterior_point_est)
  expect_true(abs(post_sum - 1) < 0.001)
})

# ==============================================================================
# Test 4: compute_posterior -> posterior_consensus -> update_prior_from_consensus
# ==============================================================================

test_that("Full posterior pipeline: compute -> consensus -> empirical Bayes -> final consensus", {
  # Two samples, clear winner in S1, ambiguous in S2
  input <- bind_rows(
    tibble(
      observation_id            = "S1",
      taxon_name           = c("Sp_A", "Sp_B"),
      taxon_name_rank      = "species",
      hypothesis_type      = "specific_candidate",
      score_likelihood = c(0.9, 0.1),
      score_likelihood_mean      = c(0.9, 0.1),
      score_likelihood_sd        = c(0.02, 0.02),
      prior_mean           = c(0.6, 0.4),
      prior_alpha          = c(6, 4),
      prior_beta           = c(4, 6),
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
      genus                = c("GenA", "GenC"),
      family               = c("FamA", "FamC"),
      species              = c("Sp_A", "Sp_C")
    )
  )

  # Step 1: compute_posterior
  result <- compute_posterior(input, n_sims = 100)
  expect_true(all(c("posterior_point_est", "confidence_score") %in% names(result)))

  # Step 2: posterior_consensus
  con <- posterior_consensus(
    result,
    cumulative_threshold = 0.90,
    min_posterior        = 0.05,
    rank_system          = c("family", "genus", "species")
  )
  expect_equal(nrow(con), 2L)
  expect_true(all(c("consensus_taxon", "consensus_rank", "is_resolved") %in% names(con)))

  # S1 should be resolved to Sp_A (clear winner)
  s1 <- con[con$observation_id == "S1", ]
  expect_true(s1$is_resolved)
  expect_equal(s1$consensus_taxon, "Sp_A")

  # Step 3: empirical Bayes refinement
  result_updated <- update_prior_from_consensus(result, con,
                                                 presence_multiplier = 5,
                                                 n_sims = 100)
  expect_s3_class(result_updated, "data.frame")

  # Step 4: final consensus
  con_final <- posterior_consensus(
    result_updated,
    cumulative_threshold = 0.90,
    min_posterior        = 0.05,
    rank_system          = c("family", "genus", "species")
  )
  expect_equal(nrow(con_final), 2L)

  # After EB refinement, Sp_A (confirmed in S1) should get boosted in S2
  # The final consensus may or may not resolve S2, but it should complete
  s2_final <- con_final[con_final$observation_id == "S2", ]
  expect_true(is.logical(s2_final$is_resolved))
})

# ==============================================================================
# Test 5: expand_unreferenced -> compute_posterior -> score_consensus
# ==============================================================================

test_that("expand_unreferenced output feeds into compute_posterior and score_consensus", {
  # H1 is Atherinops affinis (Atherinopsidae) — different genus from H2 (Fundulus),
  # so H2 expansion fires and produces Fundulus parvipinnis.
  lik <- data.frame(
    observation_id            = "ESV_001",
    taxon_name           = c("Atherinops affinis", "Fundulus"),
    taxon_name_rank      = c("species", "genus"),
    hypothesis_type      = c("specific_candidate", "unreferenced_species"),
    score_likelihood = c(0.90, 0.30),
    score_likelihood_mean      = c(0.90, 0.30),
    score_likelihood_sd        = c(0.05, 0.05),
    genus                = c("Atherinops", "Fundulus"),
    family               = c("Atherinopsidae", "Fundulidae"),
    species              = c("Atherinops affinis", NA),
    score_original                = c(99, 90),
    stringsAsFactors     = FALSE
  )
  unref <- data.frame(
    species = "Fundulus parvipinnis",
    genus   = "Fundulus",
    family  = "Fundulidae",
    stringsAsFactors = FALSE
  )

  # Expand
  expanded <- expand_unreferenced_hypotheses(lik, unref)
  expect_true("Fundulus parvipinnis" %in% expanded$taxon_name)
  expect_false("Fundulus" %in% expanded$taxon_name[
    expanded$hypothesis_type == "unreferenced_species"])

  # Add priors and compute posterior
  expanded$prior_mean  <- c(0.5, 0.5)
  expanded$prior_alpha <- c(5, 5)
  expanded$prior_beta  <- c(5, 5)

  result <- compute_posterior(expanded, n_sims = 0)
  expect_true(all(result$posterior_point_est >= 0))

  # Score consensus on match-like data
  match_like <- data.frame(
    observation_id = "ESV_001",
    score_original     = c(99, 85),
    taxon_name = c("Fundulus lima", "Fundulus parvipinnis"),
    taxon_name_rank = "species",
    family    = "Fundulidae",
    genus     = "Fundulus",
    species   = c("Fundulus lima", "Fundulus parvipinnis"),
    stringsAsFactors = FALSE
  )
  scon <- score_consensus(match_like, min_score = 80, max_gap = 5)
  expect_equal(nrow(scon), 1L)
  expect_true("consensus_taxon" %in% names(scon))
})

# ==============================================================================
# Test 6: TaxaTools is_plausible_binomial + resolve_barcode_lengths integration
# ==============================================================================

test_that("TaxaTools utilities work together for reference QC context", {
  skip_if_not_installed("TaxaTools")

  # Species names from a match object
  names <- c("Fundulus parvipinnis", "Fundulus sp.", "uncultured clone",
             "Atherinops affinis", "cf. Mugil cephalus")

  valid <- TaxaTools::is_plausible_binomial(names)
  expect_equal(valid, c(TRUE, FALSE, FALSE, TRUE, FALSE))

  # Barcode lengths for a marker
  lens <- TaxaTools::resolve_barcode_lengths("MiFishU")
  expect_length(lens, 2L)
  expect_true(lens[1] < lens[2])
})
