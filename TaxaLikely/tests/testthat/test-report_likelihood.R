# test-report_likelihood.R
# Tests for report_likelihood()

.mock_model <- function(n_species = 30L, aic = 200.0, n_singletons = 5L,
                        n_anchors = 10L, n_errors = 2L) {
  structure(
    list(
      H1_Lookup = data.frame(
        lookup_key = paste0("sp", seq_len(n_species)),
        rank = rep("species", n_species),
        mu_score = runif(n_species, 3, 5),
        mu_gap = runif(n_species, 1, 3),
        sigma_score = runif(n_species, 0.3, 0.8),
        stringsAsFactors = FALSE
      ),
      H1_Global_Mu = c(score_logit = 4.2, gap_logit = 2.1),
      H1_Sigma = matrix(c(0.5, 0.1, 0.1, 0.4), 2, 2),
      H2 = list(delta = 3.0, sigma = matrix(c(0.8, 0.2, 0.2, 0.6), 2, 2)),
      H3 = list(delta = 5.0, sigma = matrix(c(1.2, 0.3, 0.3, 0.9), 2, 2)),
      Stats = list(
        AIC_Score = aic,
        n_species = n_species + n_singletons,
        n_singletons = n_singletons,
        n_anchors = n_anchors
      ),
      reference_errors = data.frame(
        accession = paste0("NC_", seq_len(n_errors + 1L)),
        error_type = c(rep("likely_mislabeled", n_errors), "unverified_singleton_high_match"),
        stringsAsFactors = FALSE
      )
    ),
    class = "taxa_model_params"
  )
}

test_that("report_likelihood returns valid report_section", {
  sec <- report_likelihood(.mock_model())
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaLikely")
  expect_equal(sec$section, "likelihood")
})

test_that("report_likelihood extracts correct statistics", {
  sec <- report_likelihood(.mock_model(n_species = 40, aic = 150.3,
                                        n_singletons = 7, n_anchors = 15,
                                        n_errors = 3))
  expect_equal(sec$statistics$n_species, 47L)
  expect_equal(sec$statistics$n_singletons, 7L)
  expect_equal(sec$statistics$n_anchors, 15L)
  expect_equal(sec$statistics$n_errors, 3L)
  expect_equal(sec$statistics$aic_score, 150.3)
  expect_equal(sec$statistics$n_profiled, 40L)
})

test_that("report_likelihood methods mentions species count", {
  sec <- report_likelihood(.mock_model(n_species = 50, n_singletons = 10))
  expect_true(grepl("60 species", sec$methods))
  expect_true(grepl("10 represented by a single sequence", sec$methods))
})

test_that("report_likelihood methods mentions anchoring", {
  sec <- report_likelihood(.mock_model(n_anchors = 20))
  expect_true(grepl("anchoring.*n = 20", sec$methods))
})

test_that("report_likelihood methods mentions mislabeled references", {
  sec <- report_likelihood(.mock_model(n_errors = 4))
  expect_true(grepl("4 likely mislabeled", sec$methods))
})

test_that("report_likelihood results mentions AIC", {
  sec <- report_likelihood(.mock_model(aic = 567.8))
  expect_true(grepl("567\\.8", sec$results))
})

test_that("report_likelihood errors on non-model input", {
  expect_error(report_likelihood(data.frame(x = 1)))
  expect_error(report_likelihood(list(a = 1)))
  expect_error(report_likelihood(NULL))
})

test_that("report_likelihood handles model without AIC", {
  model <- .mock_model()
  model$Stats$AIC_Score <- NULL

  sec <- report_likelihood(model)
  expect_s3_class(sec, "report_section")
  expect_null(sec$statistics$aic_score)
})

test_that("report_likelihood handles model without reference_errors", {
  model <- .mock_model()
  model$reference_errors <- NULL

  sec <- report_likelihood(model)
  expect_equal(sec$statistics$n_errors, 0L)
  expect_false(grepl("mislabeled", sec$methods))
})
