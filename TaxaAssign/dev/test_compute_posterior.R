# dev/test_compute_posterior.R
# Simulated test data and debugging script for compute_posterior()
#
# Run this file interactively in RStudio to test the function.
# Source the function first, then run each section.

# --- Load function (before package is installed) ---
source("R/compute_posterior.R")

# Packages needed for testing
library(dplyr)
library(purrr)
library(cli)

set.seed(42)

# =============================================================================
# TEST CASE 1: Typical case — 3 samples, 3-5 hypotheses each, SDs present
# =============================================================================
# Simulates realistic output from evaluate_candidates():
# - observation_id: unique observation ID
# - likelihood_point_est, likelihood_mean, likelihood_sd: from TaxaMatch
# - prior_mean: from TaxaExpect
# - taxon_name, Hypothesis_Type: extra columns that should pass through unchanged

test1 <- dplyr::bind_rows(

  # Sample A: clear winner (Gadus morhua has high likelihood and prior)
  dplyr::tibble(
    observation_id             = "Sample_A",
    taxon_name            = c("Gadus morhua", "Gadus chalcogrammus", "Missing_Species"),
    Hypothesis_Type       = c("Specific_Candidate", "Specific_Candidate", "Missing_Species"),
    likelihood_point_est  = c(0.85, 0.30, 0.10),
    likelihood_mean       = c(0.83, 0.31, 0.10),
    likelihood_sd         = c(0.05, 0.04, 0.02),
    prior_mean            = c(0.60, 0.30, 0.10),
    prior_sd              = c(0.05, 0.05, 0.02)
  ),

  # Sample B: ambiguous — two strong candidates with similar likelihoods
  dplyr::tibble(
    observation_id             = "Sample_B",
    taxon_name            = c("Salmo salar", "Salmo trutta", "Missing_Species"),
    Hypothesis_Type       = c("Specific_Candidate", "Specific_Candidate", "Missing_Species"),
    likelihood_point_est  = c(0.70, 0.65, 0.10),
    likelihood_mean       = c(0.68, 0.64, 0.10),
    likelihood_sd         = c(0.08, 0.08, 0.02),
    prior_mean            = c(0.50, 0.40, 0.10),
    prior_sd              = c(0.06, 0.06, 0.02)
  ),

  # Sample C: 5 hypotheses — tests larger groups
  dplyr::tibble(
    observation_id             = "Sample_C",
    taxon_name            = c("Thunnus thynnus", "Thunnus albacares",
                              "Thunnus obesus", "Missing_Species", "Missing_Genus"),
    Hypothesis_Type       = c(rep("Specific_Candidate", 3), "Missing_Species", "Missing_Genus"),
    likelihood_point_est  = c(0.90, 0.40, 0.20, 0.05, 0.02),
    likelihood_mean       = c(0.88, 0.41, 0.21, 0.05, 0.02),
    likelihood_sd         = c(0.06, 0.05, 0.04, 0.01, 0.01),
    prior_mean            = c(0.50, 0.25, 0.15, 0.07, 0.03),
    prior_sd              = c(0.05, 0.04, 0.03, 0.01, 0.01)
  )
)

cat("\n--- Test 1: Typical case with SDs ---\n")
result1 <- compute_posterior(test1, n_sims = 1000)
print(result1 %>% dplyr::select(observation_id, taxon_name, posterior_point_est,
                                 posterior_mean, posterior_sd, confidence_score))

# Quick sanity check: posteriors should sum to 1 within each observation_id
cat("\nPosterior sums by observation_id (should all be ~1.0):\n")
result1 %>%
  dplyr::group_by(observation_id) %>%
  dplyr::summarise(sum_point_est = sum(posterior_point_est),
                   sum_mean      = sum(posterior_mean)) %>%
  print()

# =============================================================================
# TEST CASE 2: No SDs — should skip simulation and warn user
# =============================================================================
test2 <- test1 %>%
  dplyr::mutate(likelihood_sd = 0, prior_sd = 0)

cat("\n--- Test 2: All SDs = 0 (should skip simulation) ---\n")
result2 <- compute_posterior(test2, n_sims = 1000)
cat("posterior_mean == posterior_point_est for all rows:",
    all(abs(result2$posterior_mean - result2$posterior_point_est) < 1e-10), "\n")

# =============================================================================
# TEST CASE 3: n_sims = 0 — point estimate path only
# =============================================================================
cat("\n--- Test 3: n_sims = 0 (point estimate path only) ---\n")
result3 <- compute_posterior(test1, n_sims = 0)
print(result3 %>% dplyr::select(observation_id, taxon_name, posterior_point_est,
                                 posterior_mean, posterior_sd, confidence_score))

# =============================================================================
# TEST CASE 4: Missing prior_sd — should add column silently with message
# =============================================================================
test4 <- test1 %>% dplyr::select(-prior_sd)

cat("\n--- Test 4: No prior_sd column (should add with message) ---\n")
result4 <- compute_posterior(test4, n_sims = 1000)
cat("prior_sd column present in output:", "prior_sd" %in% names(result4), "\n")

# =============================================================================
# TEST CASE 5: Missing required column — should error cleanly
# =============================================================================
test5 <- test1 %>% dplyr::select(-likelihood_sd, -prior_mean)

cat("\n--- Test 5: Missing required columns (should error with informative message) ---\n")
tryCatch(
  compute_posterior(test5),
  error = function(e) cat("Error caught:", conditionMessage(e), "\n")
)

# =============================================================================
# TEST CASE 6: NA values in SD columns — should replace with 0 and warn
# =============================================================================
test6 <- test1
test6$likelihood_sd[c(1, 4)] <- NA

cat("\n--- Test 6: NA values in likelihood_sd (should warn and replace with 0) ---\n")
result6 <- compute_posterior(test6, n_sims = 1000)
cat("Completed without error.\n")
