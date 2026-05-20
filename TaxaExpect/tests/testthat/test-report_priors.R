# test-report_priors.R
# Tests for report_priors()

test_that("report_priors works with build_priors list output", {
  priors_df <- data.frame(
    grid_id = rep(c("G1", "G2"), each = 3),
    taxon_name = rep(c("Sp A", "Sp B", "Sp C"), 2),
    theta_mean = runif(6, 0.01, 0.5),
    model_tier = c("tier1", "tier1", "tier2", "tier1", "tier3_undetected", "tier2"),
    stringsAsFactors = FALSE
  )

  bp_output <- list(
    priors = priors_df,
    model = NULL,
    occurrences = data.frame(x = 1:100),
    grid_result = NULL
  )
  attr(bp_output, "habitat_scheme") <- "3-category"
  attr(bp_output, "report_params") <- list(
    citations = c("GBIF Download", "BioTIME Study"),
    n_occurrence_records = 100L
  )

  sec <- report_priors(bp_output)
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaExpect")
  expect_equal(sec$section, "priors")
  expect_equal(sec$statistics$n_taxa, 3L)
  expect_equal(sec$statistics$n_grid_cells, 2L)
  expect_equal(length(sec$citations), 2)
  expect_true(grepl("3-category", sec$methods))
})

test_that("report_priors works with raw data frame", {
  priors_df <- data.frame(
    grid_id = rep("G1", 4),
    taxon_name = paste0("Sp ", LETTERS[1:4]),
    theta_mean = runif(4),
    model_tier = c("tier1", "tier1", "tier2", "tier1"),
    stringsAsFactors = FALSE
  )

  sec <- report_priors(priors_df)
  expect_s3_class(sec, "report_section")
  expect_equal(sec$statistics$n_taxa, 4L)
  expect_equal(sec$statistics$n_grid_cells, 1L)
})

test_that("report_priors includes tier breakdown", {
  priors_df <- data.frame(
    grid_id = rep("G1", 6),
    taxon_name = paste0("Sp", 1:6),
    theta_mean = runif(6),
    model_tier = c("tier1", "tier1", "tier1", "tier2", "tier2", "tier3_undetected"),
    stringsAsFactors = FALSE
  )

  sec <- report_priors(priors_df)
  expect_true(grepl("tier1: 3", sec$results))
  expect_true(grepl("tier2: 2", sec$results))
  expect_true(grepl("tier3_undetected: 1", sec$results))
})

test_that("report_priors propagates citations from report_params", {
  priors_df <- data.frame(
    grid_id = "G1", taxon_name = "Sp A", theta_mean = 0.5,
    stringsAsFactors = FALSE
  )
  attr(priors_df, "report_params") <- list(
    citations = c("Source 1", "Source 2")
  )

  sec <- report_priors(priors_df)
  expect_equal(sec$citations, c("Source 1", "Source 2"))
})

test_that("report_priors includes occurrence count from list output", {
  bp_output <- list(
    priors = data.frame(grid_id = "G1", taxon_name = "Sp A", theta_mean = 0.3,
                        stringsAsFactors = FALSE),
    model = NULL,
    occurrences = data.frame(x = 1:500),
    grid_result = NULL
  )
  attr(bp_output, "report_params") <- list(n_occurrence_records = 500L)

  sec <- report_priors(bp_output)
  expect_true(grepl("500", sec$methods))
})

test_that("report_priors errors on invalid input", {
  expect_error(report_priors(NULL))
  expect_error(report_priors(data.frame()))
  expect_error(report_priors("not valid"))
})
