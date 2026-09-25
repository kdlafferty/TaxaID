.mk_bands <- function() {
  b <- data.frame(
    taxon_name = c("A", "A", "B", "B", "C", "D"),
    band_lo_km = c(0, 25, 0, 50, 25, 100),
    band_hi_km = c(25, 50, 25, 100, 50, Inf),
    n = c(40, 10, 2, 30, 1, 5),
    sampling_group = c("g", "g", "g", "g", "g", "g"),
    stringsAsFactors = FALSE
  )
  attr(b, "query") <- list(site_lat = 34, site_lon = -120)
  b
}

test_that("bands are fitted as count-weighted records at the annulus-average-weight distance", {
  b <- .mk_bands()
  fp <- suppressWarnings(estimate_facet_priors(b, "Marine", lambda_km = 25))
  # Reconstruct by hand: one record per unit count at the representative
  # distance due east of the site, fitted by the record estimator.
  d <- ifelse(is.finite(b$band_hi_km), .band_representative_km(b$band_lo_km, b$band_hi_km, 25), 150)
  rec <- b[rep(seq_len(nrow(b)), b$n), ]
  rec$decimalLatitude <- 34
  rec$decimalLongitude <- -120 + rep(d, b$n) / (111 * cos(34 * pi / 180))
  rec$main_habitat <- "Marine"
  kp <- suppressWarnings(estimate_kernel_priors(rec, 34, -120, "Marine", lambda_km = 25))
  expect_equal(fp$priors$theta_mean, kp$priors$theta_mean)
  expect_equal(fp$priors$taxon_name, kp$priors$taxon_name)
  expect_equal(fp$n_eff, kp$n_eff)
  expect_s3_class(fp, "taxaexpect_kernel_priors")
  expect_equal(fp$params$source, "gbif_facet")
})

test_that("representative distance: annulus-average weight, inside the band", {
  d <- .band_representative_km(0, 25, 25)
  expect_true(d > 0 && d < 25)
  r <- seq(0, 25, length.out = 1e5)
  expect_equal(exp(-d / 25), sum(exp(-r / 25) * r) / sum(r), tolerance = 1e-4)
})

test_that("taxon-level habitat: below-threshold taxa leave numerator and denominator", {
  b <- .mk_bands()
  hl <- data.frame(taxon_name = c("A", "B", "C", "D"), Marine = c(1, 0.2, 0.6, 1), Terrestrial = c(0, 0.8, 0.4, 0))
  fp <- suppressWarnings(estimate_facet_priors(b, "Marine", lambda_km = 25, habitat_lookup = hl))
  expect_false("B" %in% fp$priors$taxon_name)
  expect_true(all(fp$priors$observed_in_habitat))
  expect_equal(fp$params$habitat_mode, "taxon_threshold")
  expect_equal(fp$params$n_records_stratum, sum(b$n[b$taxon_name != "B"]))
})

test_that("taxa missing from habitat_lookup are dropped with a message", {
  hl <- data.frame(taxon_name = c("A", "B"), Marine = c(1, 1))
  expect_message(
    suppressWarnings(estimate_facet_priors(.mk_bands(), "Marine", lambda_km = 25, habitat_lookup = hl)),
    "no habitat_lookup entry"
  )
})

test_that("no habitat_lookup warns and leaves observed_in_habitat NA", {
  expect_warning(estimate_facet_priors(.mk_bands(), "Marine", lambda_km = 25), "no habitat_lookup")
  fp <- suppressWarnings(estimate_facet_priors(.mk_bands(), "Marine", lambda_km = 25))
  expect_true(all(is.na(fp$priors$observed_in_habitat)))
})

test_that("support radius off the band edges warns; on an edge it does not", {
  b <- .mk_bands()
  expect_warning(estimate_facet_priors(b, "Marine", lambda_km = 25), "support radius")
  b$band_hi_km[b$band_hi_km == 100] <- 75
  b$band_lo_km[b$band_lo_km == 50] <- 50
  w <- character(0)
  withCallingHandlers(estimate_facet_priors(b, "Marine", lambda_km = 25),
    warning = function(cnd) {
      w <<- c(w, conditionMessage(cnd))
      invokeRestart("muffleWarning")
    }
  )
  expect_false(any(grepl("support radius", w)))
})

test_that("singleton coordinates are NA (a band is not a place)", {
  fp <- suppressWarnings(estimate_facet_priors(.mk_bands(), "Marine", lambda_km = 25))
  expect_gt(nrow(fp$singletons), 0)
  expect_true(all(is.na(fp$singletons$lat)))
})

test_that("sampling groups pass through to the per-group budget", {
  b <- .mk_bands()
  b$sampling_group <- c("g1", "g1", "g1", "g1", "g2", "g2")
  fp <- suppressWarnings(estimate_facet_priors(b, "Marine", lambda_km = 25, sampling_group_col = "sampling_group"))
  expect_setequal(fp$budget$sampling_group, c("g1", "g2"))
})

test_that("input validation", {
  expect_error(estimate_facet_priors(.mk_bands(), "Marine"), "lambda_km is required")
  expect_error(estimate_facet_priors(.mk_bands()[, -4], "Marine", 25), "missing column")
  expect_error(
    estimate_facet_priors(.mk_bands(), "Marine", 25, habitat_lookup = data.frame(taxon_name = "A")),
    "needs columns"
  )
})
