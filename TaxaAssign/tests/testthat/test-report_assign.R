# test-report_assign.R
# Tests for report_assign()

test_that("report_assign works with posterior consensus", {
  result <- data.frame(
    observation_id = rep(paste0("S", 1:5), each = 2),
    taxon_name = rep(c("Sp A", "Sp B"), 5),
    posterior_mean = c(0.8, 0.2, 0.9, 0.1, 0.7, 0.3, 0.85, 0.15, 0.6, 0.4),
    hypothesis_type = "specific_candidate",
    range_status = "present",
    habitat_fit = "expected",
    information_quality = "high",
    stringsAsFactors = FALSE
  )
  attr(result, "report_params") <- list(n_sims = 1000L)

  consensus <- data.frame(
    observation_id = paste0("S", 1:5),
    consensus_taxon = c("Sp A", "Sp A", "Sp A", "Sp A", "Sp A"),
    consensus_rank = c("species", "species", "species", "species", "genus"),
    is_resolved = c(TRUE, TRUE, TRUE, TRUE, FALSE),
    consensus_posterior = c(0.8, 0.9, 0.7, 0.85, 0.6),
    stringsAsFactors = FALSE
  )
  attr(consensus, "report_params") <- list(cumulative_threshold = 0.95)

  sec <- report_assign(result, consensus, data_type = "eDNA")
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaAssign")
  expect_equal(sec$section, "assign")
  expect_equal(sec$params$workflow, "llm")
  expect_equal(sec$statistics$n_samples, 5L)
  expect_equal(sec$statistics$n_resolved, 4L)
  expect_equal(sec$statistics$resolution_rate, 80.0)
  expect_true(grepl("LLM-shortcut", sec$methods))
  expect_true(grepl("eDNA", sec$methods))
  expect_true(grepl("95%", sec$methods))
})

test_that("report_assign detects bayesian workflow", {
  result <- data.frame(
    observation_id = c("S1", "S1"),
    taxon_name = c("Sp A", "Sp B"),
    posterior_mean = c(0.8, 0.2),
    stringsAsFactors = FALSE
  )

  consensus <- data.frame(
    observation_id = "S1",
    consensus_taxon = "Sp A",
    consensus_rank = "species",
    is_resolved = TRUE,
    stringsAsFactors = FALSE
  )

  sec <- report_assign(result, consensus)
  expect_equal(sec$params$workflow, "bayesian")
  expect_true(grepl("full Bayesian", sec$methods))
})

test_that("report_assign works with score consensus (NULL result)", {
  consensus <- data.frame(
    observation_id = paste0("S", 1:8),
    consensus_taxon = paste0("Sp ", LETTERS[1:8]),
    consensus_rank = rep("species", 8),
    is_resolved = c(rep(TRUE, 6), FALSE, FALSE),
    top_score = runif(8, 90, 100),
    stringsAsFactors = FALSE
  )
  attr(consensus, "report_params") <- list(min_score = 97)

  sec <- report_assign(NULL, consensus, data_type = "eDNA")
  expect_equal(sec$params$workflow, "score")
  expect_true(grepl("score-based", sec$methods))
  expect_true(grepl("97%", sec$methods))
  expect_equal(sec$statistics$n_samples, 8L)
  expect_equal(sec$statistics$n_resolved, 6L)
  expect_false(is.null(sec$statistics$median_top_score))
})

test_that("report_assign reports resolution rate correctly", {
  consensus <- data.frame(
    observation_id = paste0("S", 1:10),
    consensus_taxon = paste0("Sp", 1:10),
    consensus_rank = rep("species", 10),
    is_resolved = c(rep(TRUE, 7), rep(FALSE, 3)),
    top_score = runif(10, 90, 100),
    stringsAsFactors = FALSE
  )

  sec <- report_assign(NULL, consensus)
  expect_equal(sec$statistics$resolution_rate, 70.0)
  expect_true(grepl("70\\.0%", sec$results))
})

test_that("report_assign errors on empty consensus", {
  expect_error(report_assign(NULL, data.frame()))
  expect_error(report_assign(NULL, NULL))
})

test_that("report_assign reports median posterior", {
  result <- data.frame(
    observation_id = c("S1", "S1", "S2", "S2"),
    taxon_name = c("A", "B", "A", "B"),
    posterior_mean = c(0.8, 0.2, 0.9, 0.1),
    stringsAsFactors = FALSE
  )
  consensus <- data.frame(
    observation_id = c("S1", "S2"),
    consensus_taxon = c("A", "A"),
    consensus_rank = c("species", "species"),
    is_resolved = c(TRUE, TRUE),
    stringsAsFactors = FALSE
  )

  sec <- report_assign(result, consensus)
  # Top posteriors are 0.8 and 0.9, median = 0.85
  expect_equal(sec$statistics$median_posterior, 0.85)
  expect_true(grepl("0\\.850", sec$results))
})
