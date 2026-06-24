# test-adjust_inat_range_priors.R
# Tests for adjust_inat_range_priors().
#
# Strategy: fully offline. Fixtures supply minimal data frames mimicking the
# output of join_priors() (likelihoods_ready) and check_inat_range() (inat_range).

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

# Minimal likelihoods_ready row: one unmodelled taxon (alpha = NA)
.make_lr <- function(taxon_name    = "Foo bar",
                     alpha         = NA_real_,    # NA = unmodelled
                     prior_alpha   = 0.5,
                     prior_beta    = 99.5,
                     singleton_alpha = 2.0,
                     singleton_beta  = 98.0) {
  prior_mean <- prior_alpha / (prior_alpha + prior_beta)
  data.frame(
    observation_id  = "OBS1",
    taxon_name      = taxon_name,
    taxon_name_rank = "species",
    score_likelihood = 0.9,
    score_likelihood_mean = 0.9,
    score_likelihood_sd   = 0.05,
    alpha           = alpha,
    prior_alpha     = prior_alpha,
    prior_beta      = prior_beta,
    prior_mean      = prior_mean,
    singleton_alpha = singleton_alpha,
    singleton_beta  = singleton_beta,
    stringsAsFactors = FALSE
  )
}

# Minimal inat_range row
.make_ir <- function(taxon_name     = "Foo bar",
                     in_range       = TRUE,
                     n_observations = 1000L) {
  data.frame(
    taxon_name      = taxon_name,
    in_range        = in_range,
    n_observations  = n_observations,
    range_status    = if (isTRUE(in_range)) "in_range" else "out_of_range",
    stringsAsFactors = FALSE
  )
}

# =============================================================================
# Input validation
# =============================================================================

test_that("stops when likelihoods_ready is not a data frame", {
  expect_error(
    adjust_inat_range_priors("not_a_df", .make_ir()),
    regexp = "likelihoods_ready.*data frame"
  )
})

test_that("stops when inat_range is not a data frame", {
  expect_error(
    adjust_inat_range_priors(.make_lr(), "not_a_df"),
    regexp = "inat_range.*data frame"
  )
})

test_that("stops when likelihoods_ready is missing required columns", {
  lr <- .make_lr()
  lr$singleton_alpha <- NULL
  expect_error(
    adjust_inat_range_priors(lr, .make_ir()),
    regexp = "singleton_alpha"
  )
})

test_that("stops when inat_range is missing required columns", {
  ir <- .make_ir()
  ir$n_observations <- NULL
  expect_error(
    adjust_inat_range_priors(.make_lr(), ir),
    regexp = "n_observations"
  )
})

test_that("stops when n_obs_threshold is not a single positive number", {
  expect_error(
    adjust_inat_range_priors(.make_lr(), .make_ir(), n_obs_threshold = -1),
    regexp = "n_obs_threshold"
  )
  expect_error(
    adjust_inat_range_priors(.make_lr(), .make_ir(), n_obs_threshold = c(100, 200)),
    regexp = "n_obs_threshold"
  )
})

# =============================================================================
# Output structure
# =============================================================================

test_that("always adds inat_range_elevated column", {
  out <- adjust_inat_range_priors(.make_lr(), .make_ir())
  expect_true("inat_range_elevated" %in% names(out))
})

test_that("returns same number of rows as input", {
  lr <- rbind(.make_lr("Foo bar"), .make_lr("Baz qux"))
  ir <- .make_ir("Foo bar")
  out <- adjust_inat_range_priors(lr, ir)
  expect_equal(nrow(out), 2L)
})

# =============================================================================
# No elevation scenarios
# =============================================================================

test_that("no elevation when all rows are modelled (alpha not NA)", {
  lr <- .make_lr(alpha = 2.0)   # modelled — has TaxaExpect prior
  out <- adjust_inat_range_priors(lr, .make_ir())
  expect_false(any(out$inat_range_elevated))
  expect_equal(out$prior_alpha, lr$prior_alpha)
})

test_that("no elevation when in_range = FALSE", {
  out <- adjust_inat_range_priors(.make_lr(), .make_ir(in_range = FALSE))
  expect_false(any(out$inat_range_elevated))
})

test_that("no elevation when in_range = NA", {
  out <- adjust_inat_range_priors(.make_lr(), .make_ir(in_range = NA))
  expect_false(any(out$inat_range_elevated))
})

test_that("no elevation when n_observations below threshold", {
  out <- adjust_inat_range_priors(
    .make_lr(), .make_ir(n_observations = 100L),
    n_obs_threshold = 500L
  )
  expect_false(any(out$inat_range_elevated))
})

test_that("no elevation when taxon not in likelihoods_ready", {
  lr <- .make_lr("Species A")
  ir <- .make_ir("Species B")   # different name
  out <- adjust_inat_range_priors(lr, ir)
  expect_false(any(out$inat_range_elevated))
})

test_that("no elevation when singleton floor does not exceed current prior", {
  # prior_mean = 0.9; singleton floor = 0.02 — floor is lower, should not touch
  lr <- .make_lr(prior_alpha = 9.0, prior_beta = 1.0,   # prior_mean = 0.9
                 singleton_alpha = 2.0, singleton_beta = 98.0)  # singleton floor ~0.02
  out <- adjust_inat_range_priors(lr, .make_ir())
  expect_false(any(out$inat_range_elevated))
  expect_equal(out$prior_alpha, lr$prior_alpha)
})

# =============================================================================
# Successful elevation
# =============================================================================

test_that("prior_alpha/beta/mean updated to singleton floor on elevation", {
  lr  <- .make_lr(prior_alpha = 0.5, prior_beta = 99.5,
                  singleton_alpha = 2.0, singleton_beta = 98.0)
  out <- adjust_inat_range_priors(lr, .make_ir())
  expect_true(out$inat_range_elevated[[1]])
  expect_equal(out$prior_alpha[[1]], 2.0)
  expect_equal(out$prior_beta[[1]],  98.0)
  expect_equal(out$prior_mean[[1]],  2.0 / (2.0 + 98.0))
})

test_that("inat_range_elevated is TRUE only for elevated rows", {
  lr <- rbind(
    .make_lr("Species A"),   # unmodelled, will match
    .make_lr("Species B", alpha = 2.0)   # modelled, must not change
  )
  ir <- .make_ir("Species A")
  out <- adjust_inat_range_priors(lr, ir)
  expect_equal(out$inat_range_elevated, c(TRUE, FALSE))
})

test_that("modelled rows are unchanged when unmodelled rows are elevated", {
  modelled_alpha <- 5.0
  lr <- rbind(
    .make_lr("Species A"),
    .make_lr("Species B", alpha = modelled_alpha, prior_alpha = modelled_alpha, prior_beta = 95.0)
  )
  ir <- .make_ir("Species A")
  out <- adjust_inat_range_priors(lr, ir)
  # Species B prior unchanged
  expect_equal(out$prior_alpha[out$taxon_name == "Species B"], modelled_alpha)
})

test_that("n_obs_threshold exactly met triggers elevation", {
  out <- adjust_inat_range_priors(
    .make_lr(), .make_ir(n_observations = 500L),
    n_obs_threshold = 500L
  )
  expect_true(any(out$inat_range_elevated))
})

test_that("n_obs_threshold one below does not trigger elevation", {
  out <- adjust_inat_range_priors(
    .make_lr(), .make_ir(n_observations = 499L),
    n_obs_threshold = 500L
  )
  expect_false(any(out$inat_range_elevated))
})

test_that("multiple qualifying taxa in one call all elevated", {
  lr <- rbind(.make_lr("Species A"), .make_lr("Species B"))
  ir <- rbind(.make_ir("Species A"), .make_ir("Species B"))
  out <- adjust_inat_range_priors(lr, ir)
  expect_true(all(out$inat_range_elevated))
})

test_that("prior_mean is re-derived from elevated alpha/beta, not stale", {
  lr  <- .make_lr(singleton_alpha = 3.0, singleton_beta = 97.0)
  out <- adjust_inat_range_priors(lr, .make_ir())
  expected_mean <- 3.0 / (3.0 + 97.0)
  expect_equal(out$prior_mean[out$inat_range_elevated], expected_mean)
})
