# h1_clamp: the H1 density's score term is evaluated at min(score, H1 mean), so a score ABOVE the
# species' trained mean is never penalised. Fixtures in helper-h1_clamp.R; v1.0 golden outputs in
# fixtures/h1_clamp_v1_golden.R (generated from main 3e563f29, before the clamp existed).

test_that("h1_clamp is the LAST formal of evaluate_likelihoods() and defaults to TRUE", {
  f <- formals(evaluate_likelihoods)
  expect_identical(utils::tail(names(f), 1L), "h1_clamp")
  expect_identical(f$h1_clamp, TRUE)
})

test_that("h1_clamp = FALSE reproduces v1.0 exactly (point estimate and Monte Carlo)", {
  g <- eval(parse(test_path("fixtures", "h1_clamp_v1_golden.R")))
  expect_identical(g$commit, "3e563f29")
  expect_identical(.hc_eval(g$query, h1_clamp = FALSE), g$point)
  set.seed(20261114)
  expect_identical(.hc_eval(g$query, n_sims = 25L, h1_clamp = FALSE), g$mc)
  # the golden query is one the clamp DOES change, so the identity above is not vacuous
  expect_false(identical(.hc_eval(g$query), g$point))
})

test_that("the 027213 shape: v1.0 ranks a 100% match below a 91.8% congener; the clamp does not", {
  lk <- function(clamp) {
    r <- as.data.frame(.hc_eval(.hc_query(), h1_clamp = clamp)$likelihoods)
    r <- r[r$hypothesis_type == "specific_candidate", ]
    stats::setNames(r$raw_likelihood, r$taxon_name)
  }
  v1 <- lk(FALSE)
  # the fixture BREAKS the claim under v1.0: the 100% match scores below the 91.8% one
  expect_lt(v1[["Pleuro verticalis"]], v1[["Pleuro coenosus"]])
  cl <- lk(TRUE)
  expect_gt(cl[["Pleuro verticalis"]], cl[["Pleuro coenosus"]])
  expect_identical(names(which.max(cl)), "Pleuro verticalis")
})

test_that("with the clamp, H1 likelihood never decreases as the score rises above the H1 mean", {
  # Pleuro coenosus: mu_score -0.20 on the sqrt_mismatch scale, i.e. 96% identity
  sweep <- seq(96, 100, by = 0.25)
  raw_at <- function(clamp) vapply(sweep, function(s) {
    r <- as.data.frame(.hc_eval(.hc_query(s, "Pleuro coenosus"), h1_clamp = clamp)$likelihoods)
    r$raw_likelihood[r$hypothesis_type == "specific_candidate"]
  }, numeric(1))
  v1 <- raw_at(FALSE)
  expect_true(any(diff(v1) < 0)) # v1.0 falls off above the mean: the check below can fail
  cl <- raw_at(TRUE)
  expect_true(all(diff(cl) >= 0))
})

test_that("at or below every candidate's H1 mean the clamp changes nothing", {
  # means: verticalis 92.3%, coenosus 96%, decurrens 98.56%
  q <- .hc_query(c(92.0, 95.0, 98.0), id = "below")
  expect_identical(.hc_eval(q, h1_clamp = TRUE), .hc_eval(q, h1_clamp = FALSE))
})

test_that("the clamp touches only H1: ring (H2/H3) likelihoods are unchanged", {
  ring <- function(clamp) {
    r <- as.data.frame(.hc_eval(.hc_query(), h1_clamp = clamp)$likelihoods)
    r <- r[r$hypothesis_type != "specific_candidate", ]
    r[order(r$hypothesis_type, r$taxon_name), c("hypothesis_type", "taxon_name", "raw_likelihood")]
  }
  expect_identical(ring(TRUE), ring(FALSE))
})

test_that("h1_clamp must be a single TRUE or FALSE", {
  expect_error(.hc_eval(.hc_query(), h1_clamp = NA), "h1_clamp")
  expect_error(.hc_eval(.hc_query(), h1_clamp = "yes"), "h1_clamp")
})
