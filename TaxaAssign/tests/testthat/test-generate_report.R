# Tests for generate_report.R

# --- Helpers: mock data -------------------------------------------------------

.mock_llm_result <- function() {
  df <- data.frame(
    observation_id           = rep(c("S1", "S2", "S3"), each = 3),
    taxon_name          = rep(c("Gobius niger", "Pomatoschistus minutus", NA_character_), 3),
    taxon_name_rank     = rep(c("species", "species", NA_character_), 3),
    hypothesis_type     = rep(c("specific_candidate", "specific_candidate", "unreferenced_family"), 3),
    range_status        = rep(c("native", "native", "unknown"), 3),
    habitat_fit         = rep(c("expected", "occasional", "unlikely"), 3),
    information_quality = rep(c("high", "moderate", "low"), 3),
    score_likelihood = rep(c(0.6, 0.3, 0.1), 3),
    score_likelihood_mean      = rep(c(0.6, 0.3, 0.1), 3),
    score_likelihood_sd        = rep(c(0.05, 0.03, 0.01), 3),
    prior_mean           = rep(c(0.5, 0.3, 0.2), 3),
    prior_alpha          = rep(c(25, 3, 0.6), 3),
    prior_beta           = rep(c(25, 7, 2.4), 3),
    posterior_point_est  = rep(c(0.65, 0.25, 0.10), 3),
    posterior_mean       = rep(c(0.64, 0.26, 0.10), 3),
    posterior_sd         = rep(c(0.05, 0.04, 0.02), 3),
    confidence_score     = rep(c(0.80, 0.15, 0.05), 3),
    stringsAsFactors     = FALSE
  )
  attr(df, "report_params") <- list(
    score_sharpness       = 0.1,
    unknown_lik_weight    = 0.05,
    prior_phi             = c(high = 50, moderate = 10, low = 3),
    score_threshold       = 80,
    top_n                 = 10L,
    n_sims                = 1000L,
    absent_detection_prob = 0.80
  )
  df
}

.mock_bayesian_result <- function() {
  df <- data.frame(
    observation_id           = rep(c("S1", "S2", "S3"), each = 3),
    taxon_name          = rep(c("Gobius niger", "Pomatoschistus minutus", NA_character_), 3),
    taxon_name_rank     = rep(c("species", "species", NA_character_), 3),
    hypothesis_type     = rep(c("specific_candidate", "specific_candidate", "unreferenced_family"), 3),
    score_likelihood = rep(c(0.6, 0.3, 0.1), 3),
    score_likelihood_mean      = rep(c(0.6, 0.3, 0.1), 3),
    score_likelihood_sd        = rep(c(0.05, 0.03, 0.01), 3),
    prior_mean           = rep(c(0.5, 0.3, 0.2), 3),
    prior_alpha          = rep(c(25, 3, 0.6), 3),
    prior_beta           = rep(c(25, 7, 2.4), 3),
    posterior_point_est  = rep(c(0.65, 0.25, 0.10), 3),
    posterior_mean       = rep(c(0.64, 0.26, 0.10), 3),
    posterior_sd         = rep(c(0.05, 0.04, 0.02), 3),
    confidence_score     = rep(c(0.80, 0.15, 0.05), 3),
    stringsAsFactors     = FALSE
  )
  attr(df, "report_params") <- list(n_sims = 1000L)
  df
}

.mock_consensus <- function() {
  df <- data.frame(
    observation_id           = c("S1", "S2", "S3"),
    consensus_taxon     = c("Gobius niger", "Pomatoschistus minutus", "Gobius niger"),
    consensus_rank      = c("species", "species", "species"),
    is_resolved         = c(TRUE, TRUE, TRUE),
    consensus_posterior = c(0.65, 0.55, 0.60),
    consensus_confidence_score = c(0.80, 0.70, 0.75),
    n_plausible         = c(2L, 2L, 2L),
    stringsAsFactors    = FALSE
  )
  attr(df, "report_params") <- list(
    cumulative_threshold = 0.9,
    min_posterior        = 0.05,
    posterior_col        = "posterior_mean"
  )
  df
}


# --- .detect_workflow ---------------------------------------------------------

test_that(".detect_workflow identifies LLM workflow", {
  result <- .mock_llm_result()
  expect_equal(.detect_workflow(result), "llm")
})

test_that(".detect_workflow identifies Bayesian workflow", {
  result <- .mock_bayesian_result()
  expect_equal(.detect_workflow(result), "bayesian")
})


# --- .gather_report_params ----------------------------------------------------

test_that(".gather_report_params merges attributes from both objects", {
  result    <- .mock_llm_result()
  consensus <- .mock_consensus()
  params    <- .gather_report_params(result, consensus)

  expect_equal(params$score_sharpness, 0.1)
  expect_equal(params$cumulative_threshold, 0.9)
  # result n_sims should override consensus if both present
  expect_equal(params$n_sims, 1000L)
})


# --- .extract_report_stats ----------------------------------------------------

test_that(".extract_report_stats computes correct summary statistics", {
  result    <- .mock_llm_result()
  consensus <- .mock_consensus()
  stats     <- .extract_report_stats(result, consensus)

  expect_equal(stats$n_samples, 3)
  expect_equal(stats$n_resolved, 3)
  expect_equal(stats$resolution_rate, 100.0)
  expect_equal(stats$n_unique_taxa, 2)
  expect_true(stats$has_mc)
  expect_true(stats$has_confidence)
})


# --- .extract_unreferenced_stats ----------------------------------------------

test_that(".extract_unreferenced_stats extracts from S3 object", {
  # Build a minimal unreferenced_species_result
  unref <- structure(
    c("Gobius paganellus", "Gobius cobitis"),
    class = "unreferenced_species_result",
    census = data.frame(
      genus        = "Gobius",
      in_reference = 2L,
      unreferenced = 2L,
      stringsAsFactors = FALSE
    ),
    plausible = c("Gobius niger", "Gobius paganellus", "Gobius cobitis",
                   "Gobius bucchichii")
  )

  result    <- .mock_llm_result()
  consensus <- .mock_consensus()

  us <- .extract_unreferenced_stats(unref, result, consensus)

  expect_equal(us$n_unreferenced, 2)
  expect_equal(us$n_plausible, 4)
  expect_equal(us$frac_unreferenced, 0.5)
  expect_false(us$has_family_expansion)

  rc <- us$ref_completeness
  expect_equal(rc$n_genera, 1)
  expect_equal(rc$median_pct_ref, 50.0)
})


# --- .build_methods_text ------------------------------------------------------

test_that(".build_methods_text produces LLM workflow methods", {
  params <- list(
    score_sharpness    = 0.1,
    unknown_lik_weight = 0.05,
    score_threshold    = 80,
    top_n              = 10L,
    prior_phi          = c(high = 50, moderate = 10, low = 3),
    absent_detection_prob = 0.80,
    n_sims             = 1000L,
    cumulative_threshold = 0.9,
    min_posterior        = 0.05
  )

  text <- .build_methods_text("llm", params, "eDNA", "12S MiFish",
                               context_source = "user",
                               has_unreferenced = TRUE,
                               has_family_expansion = FALSE,
                               has_empirical_bayes = FALSE)

  expect_true(grepl("12S MiFish", text))
  expect_true(grepl("exponential weighting", text))
  expect_true(grepl("large language model", text))
  expect_true(grepl("Monte Carlo", text))
  expect_true(grepl("lowest common ancestor", text))
  expect_true(grepl("unreferenced", text))
  expect_true(grepl("specified by the analyst", text))
  expect_false(grepl("family level", text))  # no family expansion
})

test_that(".build_methods_text produces Bayesian workflow methods", {
  params <- list(
    n_sims               = 1000L,
    cumulative_threshold = 0.9,
    min_posterior        = 0.05,
    presence_multiplier  = 5
  )

  text <- .build_methods_text("bayesian", params, "eDNA", NULL,
                               context_source = "user",
                               has_unreferenced = FALSE,
                               has_family_expansion = FALSE,
                               has_empirical_bayes = TRUE)

  expect_true(grepl("hierarchical statistical model", text))
  expect_true(grepl("TaxaExpect", text))
  expect_true(grepl("empirical Bayes", text))
  expect_false(grepl("unreferenced", text))
})


# --- .build_results_template --------------------------------------------------

test_that(".build_results_template produces structured text", {
  result    <- .mock_llm_result()
  consensus <- .mock_consensus()
  stats     <- .extract_report_stats(result, consensus)

  text <- .build_results_template(stats, NULL)

  expect_true(grepl("3 observations", text))
  expect_true(grepl("100.0%", text, fixed = TRUE))
  expect_true(grepl("2 unique", text))
})


# --- generate_report (integration) -------------------------------------------

test_that("generate_report works with LLM result and NULL llm_fn", {
  result    <- .mock_llm_result()
  consensus <- .mock_consensus()

  report <- generate_report(result, consensus, llm_fn = NULL)

  expect_type(report, "character")
  expect_true(grepl("## Methods", report))
  expect_true(grepl("## Results", report))
  expect_true(grepl("exponential weighting", report))
})

test_that("generate_report works with Bayesian result and NULL llm_fn", {
  result    <- .mock_bayesian_result()
  consensus <- .mock_consensus()

  report <- generate_report(result, consensus, llm_fn = NULL)

  expect_type(report, "character")
  expect_true(grepl("## Methods", report))
  expect_true(grepl("hierarchical statistical model", report))
})

test_that("generate_report includes unreferenced stats when provided", {
  result    <- .mock_llm_result()
  consensus <- .mock_consensus()

  unref <- structure(
    c("Gobius paganellus"),
    class = "unreferenced_species_result",
    census = data.frame(
      genus        = "Gobius",
      in_reference = 2L,
      unreferenced = 1L,
      stringsAsFactors = FALSE
    ),
    plausible = c("Gobius niger", "Gobius paganellus")
  )

  report <- generate_report(result, consensus,
                             unreferenced_result = unref,
                             llm_fn = NULL)

  expect_true(grepl("unreferenced", report))
  expect_true(grepl("barcode", report))
})

test_that("generate_report validates inputs", {
  # consensus must be a data frame
  expect_error(generate_report(data.frame(), "not_df"), "data frame")

  # Missing columns in consensus
  expect_error(
    generate_report(data.frame(x = 1), data.frame(y = 1), llm_fn = NULL),
    "missing column"
  )

  # Posterior consensus requires non-NULL result
  posterior_con <- data.frame(
    observation_id = "s1", consensus_taxon = "Sp A", consensus_rank = "species",
    is_resolved = TRUE, consensus_posterior = 0.9
  )
  expect_error(
    generate_report(NULL, posterior_con, llm_fn = NULL),
    "data frame"
  )
})
