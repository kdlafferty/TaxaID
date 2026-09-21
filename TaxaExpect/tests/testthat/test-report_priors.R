# test-report_priors.R
# Tests for report_priors()

test_that("report_priors works with build_priors list output", {
  priors_df <- data.frame(
    grid_id = rep(c("G1", "G2"), each = 3),
    taxon_name = rep(c("Sp A", "Sp B", "Sp C"), 2),
    theta_mean = runif(6, 0.01, 0.5),
    prior_branch = c(
      "kernel_estimated", "kernel_estimated", "resident_undetected",
      "kernel_estimated", "transport", "resident_undetected"
    ),
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
    prior_branch = c("kernel_estimated", "kernel_estimated", "resident_undetected", "kernel_estimated"),
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
    prior_branch = c(
      "kernel_estimated", "kernel_estimated", "kernel_estimated",
      "resident_undetected", "resident_undetected", "transport"
    ),
    stringsAsFactors = FALSE
  )

  sec <- report_priors(priors_df)
  expect_true(grepl("kernel_estimated: 3", sec$results))
  expect_true(grepl("resident_undetected: 2", sec$results))
  expect_true(grepl("transport: 1", sec$results))
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
    priors = data.frame(
      grid_id = "G1", taxon_name = "Sp A", theta_mean = 0.3,
      stringsAsFactors = FALSE
    ),
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

test_that("kernel tables report by prior_branch including resident rows (2026-09-01)", {
  df <- data.frame(
    taxon_name = c("A a", "B b", "C c", "D d"),
    theta_mean = c(0.3, 0.2, 1e-4, 5e-4),
    prior_branch = c(
      "kernel_estimated", "kernel_estimated",
      "resident_undetected", "transport"
    ),
    model_tier = c(NA, NA, "tier_undetected_evidence", "tier_domestic_food"),
    stringsAsFactors = FALSE
  )
  sec <- report_priors(df)
  tb <- sec$statistics$tier_breakdown
  expect_equal(tb$kernel_estimated, 2L) # model_tier-only counting would have dropped these
  expect_equal(tb$resident_undetected, 1L)
  expect_equal(tb$transport, 1L)
  expect_true(grepl("Prior branch breakdown", sec$results))
  expect_true(grepl("kernel estimation", sec$methods))
})

test_that("a model_tier-only table (no prior_branch) is refused as the retired GLMM schema", {
  # No 1.0 producer emits model_tier without prior_branch -- this is the
  # schema of the retired GLMM/grid prior pipeline, which TaxaID 1.0 has no
  # predecessor for and does not support.
  df2 <- data.frame(
    taxon_name = c("A a", "B b", "C c", "D d"),
    theta_mean = c(0.3, 0.2, 1e-4, 5e-4),
    model_tier = c("tier1", "tier2", NA, NA),
    stringsAsFactors = FALSE
  )
  expect_error(report_priors(df2), regexp = "GLMM")
})
