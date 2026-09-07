# Tests for kernel_budget_sensitivity() -- open decision #4 of
# ecosystem_docs/REENTRY_PROMPT_kernel_budget_pricing_and_scope.md.

.sens_pool <- function() {
  set.seed(7)
  # A ring structure: common taxa at the site, rare taxa placed at increasing
  # distance, so which of them count as singletons/doubletons genuinely depends
  # on the counting radius -- the effect the function exists to expose.
  common <- do.call(rbind, lapply(1:6, function(i) {
    data.frame(
      taxon_name = sprintf("Common_%02d", i),
      decimalLatitude = 34 + rnorm(25, 0, 0.05),
      decimalLongitude = -119 + rnorm(25, 0, 0.05),
      main_habitat = "Marine", sampling_group = "fish",
      stringsAsFactors = FALSE
    )
  }))
  rare <- do.call(rbind, lapply(1:12, function(i) {
    data.frame(
      taxon_name = sprintf("Rare_%02d", i),
      decimalLatitude = 34 + (i %% 4) * 0.35,
      decimalLongitude = -119 + (i %/% 4) * 0.35,
      main_habitat = "Marine", sampling_group = "fish",
      stringsAsFactors = FALSE
    )
  }))
  bird <- do.call(rbind, lapply(1:10, function(i) {
    data.frame(
      taxon_name = sprintf("Bird_%02d", i),
      decimalLatitude = 34 + rnorm(1, 0, 0.2),
      decimalLongitude = -119 + rnorm(1, 0, 0.2),
      main_habitat = "Marine", sampling_group = "bird",
      stringsAsFactors = FALSE
    )
  }))
  rbind(common, rare, bird)
}

test_that("the sweep reproduces the fit at the fit's own settings", {
  occ <- .sens_pool()
  fit <- suppressWarnings(
    estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)
  )
  s <- suppressWarnings(kernel_budget_sensitivity(fit, occ))
  expect_s3_class(s, "taxaexpect_kernel_budget_sensitivity")
  expect_true(s$reproduces_fit)
  expect_equal(s$at_fit$f1, fit$f1)
  expect_equal(s$at_fit$f2, fit$f2)
  expect_equal(s$at_fit$theta_present, fit$theta_present)
  # the fit's own support_weight is always in the sweep, even if not requested
  expect_true(fit$params$support_weight %in% s$budget$support_weight)
})

test_that("mismatched occurrence_data is reported, not silently accepted", {
  occ <- .sens_pool()
  fit <- suppressWarnings(
    estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)
  )
  other <- occ[occ$sampling_group == "fish", , drop = FALSE]
  s <- suppressWarnings(kernel_budget_sensitivity(fit, other))
  expect_false(s$reproduces_fit)
  expect_output(print(s), "did NOT reproduce")
})

test_that("moving only the counting radius moves f1/f2 and the price", {
  occ <- .sens_pool()
  fit <- suppressWarnings(
    estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)
  )
  s <- suppressWarnings(
    kernel_budget_sensitivity(fit, occ, support_weight_grid = exp(-(1:5)))
  )
  # one lambda only, so every row differs only in the counting boundary
  expect_equal(unique(s$budget$lambda_km), fit$params$lambda_km)
  expect_gt(diff(range(s$budget$f1)), 0)
  expect_equal(nrow(s$summary), 1L)
  expect_true(is.na(s$summary$sampling_group)) # ungrouped fit
  expect_gt(s$summary$theta_present_spread, 1)
  # radius bookkeeping
  expect_equal(s$budget$radius_lambdas, -log(s$budget$support_weight))
  expect_equal(s$budget$radius_km, s$budget$radius_lambdas * s$budget$lambda_km)
})

test_that("a grouped fit gets one summary row per sampling group", {
  occ <- .sens_pool()
  fit <- suppressWarnings(
    estimate_kernel_priors(occ, 34, -119, "Marine",
      lambda_km = 25,
      sampling_group_col = "sampling_group"
    )
  )
  s <- suppressWarnings(kernel_budget_sensitivity(fit, occ))
  expect_setequal(s$summary$sampling_group, c("fish", "bird"))
  expect_true(all(s$summary$n_settings == length(unique(s$budget$support_weight))))
  expect_true(s$reproduces_fit)
})

test_that("lambda_grid sweeps bandwidth as well as radius", {
  occ <- .sens_pool()
  fit <- suppressWarnings(
    estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)
  )
  s <- suppressWarnings(kernel_budget_sensitivity(
    fit, occ,
    support_weight_grid = exp(-c(2, 3)), lambda_grid = c(10, 25, 50)
  ))
  expect_setequal(unique(s$budget$lambda_km), c(10, 25, 50))
  expect_equal(s$params$n_settings, 6L)
  expect_true(s$reproduces_fit)
})

test_that("input validation is explicit", {
  occ <- .sens_pool()
  fit <- suppressWarnings(
    estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)
  )
  expect_error(kernel_budget_sensitivity(list(), occ), "taxaexpect_kernel_priors")
  expect_error(kernel_budget_sensitivity(fit, occ[0, ]), "non-empty")
  expect_error(
    kernel_budget_sensitivity(fit, occ, support_weight_grid = c(0, 0.5)),
    "\\(0, 1\\]"
  )
  expect_error(
    kernel_budget_sensitivity(fit, occ, support_weight_grid = 2),
    "\\(0, 1\\]"
  )
  expect_error(
    kernel_budget_sensitivity(fit, occ, lambda_grid = -5),
    "positive numerics"
  )
})

test_that("non-default column names round-trip through the fit's own params", {
  occ <- .sens_pool()
  names(occ)[names(occ) == "taxon_name"] <- "sp"
  names(occ)[names(occ) == "decimalLatitude"] <- "y"
  names(occ)[names(occ) == "decimalLongitude"] <- "x"
  names(occ)[names(occ) == "main_habitat"] <- "hab"
  fit <- suppressWarnings(
    estimate_kernel_priors(occ, 34, -119, "Marine",
      lambda_km = 25,
      taxon_col = "sp", lat_col = "y", lon_col = "x",
      habitat_col = "hab"
    )
  )
  s <- suppressWarnings(kernel_budget_sensitivity(fit, occ))
  expect_true(s$reproduces_fit)
})

test_that("print names the doubleton count the budget rests on", {
  occ <- .sens_pool()
  fit <- suppressWarnings(
    estimate_kernel_priors(occ, 34, -119, "Marine", lambda_km = 25)
  )
  # the ungrouped print now always shows f1/f2 next to the budget it produces
  expect_output(print(fit), "budget: f1 = ")
  expect_output(print(fit), "f2 = ")
  s <- suppressWarnings(kernel_budget_sensitivity(fit, occ))
  expect_output(print(s), "counting radius")
})
