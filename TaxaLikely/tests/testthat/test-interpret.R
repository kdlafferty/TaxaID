# Reuse helper from test-evaluate.R (or redefine minimally here)
.make_model_params_interp <- function() {
  sigma <- matrix(c(2.0, 0.2, 0.2, 1.0), nrow = 2L,
                  dimnames = list(c("score_logit","gap_logit"),
                                  c("score_logit","gap_logit")))
  h2s <- diag(2); rownames(h2s) <- colnames(h2s) <- c("score_logit","gap_logit")
  h3s <- diag(2); rownames(h3s) <- colnames(h3s) <- c("score_logit","gap_logit")
  structure(
    list(
      H1_Lookup    = data.frame(lookup_key  = c("Hybognathus nuchalis", "Rhinichthys obtusus"),
                                rank        = "species",
                                mu_score    = c(4.5, 3.8),
                                mu_gap      = c(2.0, 0.05),
                                sigma_score = c(2.0, 1.5),
                                stringsAsFactors = FALSE),
      H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
      H1_Sigma     = sigma,
      H2           = list(delta = 3.0, sigma = h2s),
      H3           = list(delta = 5.0, sigma = h3s),
      Stats        = list(n_species = 2L, n_singletons = 0L)
    ),
    class = "taxa_model_params"
  )
}

test_that("interpret_model: returns list with required elements", {
  out <- interpret_model(.make_model_params_interp(), print_report = FALSE)
  expect_type(out, "list")
  expect_true(all(c("hypothesis_baselines", "global_h1", "hierarchy",
                     "species_thresholds", "raw_sigma") %in% names(out)))
})

test_that("interpret_model: hypothesis_baselines has 3 rows", {
  out <- interpret_model(.make_model_params_interp(), print_report = FALSE)
  expect_equal(nrow(out$hypothesis_baselines), 3L)
})

test_that("interpret_model: H1 > H2 > H3 expected match pct", {
  out <- interpret_model(.make_model_params_interp(), print_report = FALSE)
  pcts <- out$hypothesis_baselines$expected_match_pct
  expect_gt(pcts[1], pcts[2])
  expect_gt(pcts[2], pcts[3])
})

test_that("interpret_model: species_thresholds has status column", {
  out <- interpret_model(.make_model_params_interp(), print_report = FALSE)
  expect_true("status" %in% names(out$species_thresholds))
})

test_that("interpret_model: low gap species flagged as INDISTINGUISHABLE", {
  out <- interpret_model(.make_model_params_interp(), print_report = FALSE)
  expect_true("INDISTINGUISHABLE" %in% out$species_thresholds$status)
})

test_that("interpret_model: raw_sigma matches input", {
  params <- .make_model_params_interp()
  out    <- interpret_model(params, print_report = FALSE)
  expect_equal(out$raw_sigma, params$H1_Sigma)
})

test_that("interpret_model: empty H1_Lookup returns flat-model message", {
  params <- .make_model_params_interp()
  params$H1_Lookup <- params$H1_Lookup[0L, ]
  out <- interpret_model(params, print_report = FALSE)
  expect_true("message" %in% names(out$species_thresholds))
})

test_that("interpret_model: non-taxa_model_params input errors", {
  expect_error(interpret_model(list()), "taxa_model_params")
})

test_that("interpret_model: returns invisibly", {
  params <- .make_model_params_interp()
  expect_invisible(interpret_model(params, print_report = FALSE))
})
