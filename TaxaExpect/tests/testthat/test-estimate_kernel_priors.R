# Tests for estimate_kernel_priors() / calibrate_kernel_bandwidth()
# (kernel-priors redesign, 2026-08-30). Fixtures are synthetic with
# hand-computable answers; the grid-as-top-hat reduction is the key invariant.

.mk_occ <- function(taxa, lat, lon, habitat = "Marine", depth = NA_real_) {
  data.frame(taxon_name = taxa, decimalLatitude = lat, decimalLongitude = lon,
             main_habitat = habitat, depth_m = depth, stringsAsFactors = FALSE)
}

test_that("near-flat kernel reduces to ordinary record shares (top-hat limit)", {
  # 6 records at (essentially) the site: A x3, B x2, C x1
  occ <- .mk_occ(c("A", "A", "A", "B", "B", "C"),
                 lat = 34 + (1:6) * 1e-6, lon = -120 + (1:6) * 1e-6)
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 1e9, m = 0)
  expect_equal(kp$n_eff, 6, tolerance = 1e-6)
  th <- kp$priors$theta_mean[match(c("A", "B", "C"), kp$priors$taxon_name)]
  expect_equal(th, c(3, 2, 1) / 6, tolerance = 1e-6)
  expect_equal(sum(kp$priors$theta_mean), 1, tolerance = 1e-9)
  # concentration = n_eff + m
  expect_equal(kp$priors$alpha + kp$priors$beta, rep(6, 3), tolerance = 1e-6)
})

test_that("Kish n_eff matches hand computation under unequal weights", {
  # two records: one at the site (w = 1), one ~ lambda away (w = exp(-1))
  occ <- .mk_occ(c("A", "B"), lat = c(34, 34), lon = c(-120, -120 + 50 / (111 * cos(34 * pi / 180))))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50, m = 0)
  w <- c(1, exp(-1))
  expect_equal(kp$W, sum(w), tolerance = 1e-6)
  expect_equal(kp$n_eff, sum(w)^2 / sum(w^2), tolerance = 1e-6)
  # theta ratios follow the weights
  th <- kp$priors$theta_mean[match(c("A", "B"), kp$priors$taxon_name)]
  expect_equal(th[1] / th[2], 1 / exp(-1), tolerance = 1e-6)
})

test_that("m back-off shrinks toward regional composition and m=0 disables it", {
  # local neighborhood is all-A; region also holds B far away
  far <- 5000 / 111
  occ <- .mk_occ(c("A", "A", "A", "B"),
                 lat = c(34, 34, 34, 34 + far), lon = rep(-120, 4))
  kp0 <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 10, m = 0)
  kp1 <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 10, m = 5)
  b0 <- kp0$priors$theta_mean[kp0$priors$taxon_name == "B"]
  b1 <- kp1$priors$theta_mean[kp1$priors$taxon_name == "B"]
  expect_lt(b0, 1e-6)          # kernel alone: B is invisible locally
  expect_gt(b1, b0)            # back-off gives B its regional share of m
  expect_equal(b1, 5 * 0.25 / (kp1$n_eff + 5), tolerance = 1e-6)
})

test_that("covariate (depth) kernel down-weights mismatched records", {
  # equal distances; A records at site depth, B records 100 m off
  occ <- .mk_occ(c("A", "A", "B", "B"), lat = rep(34, 4), lon = rep(-120, 4),
                 depth = c(5, 5, 105, 105))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50, m = 0,
                               covariate_col = "depth_m", site_covariate = 5,
                               lambda_covariate = 20)
  th <- kp$priors$theta_mean[match(c("A", "B"), kp$priors$taxon_name)]
  expect_equal(th[1] / th[2], 1 / exp(-100 / 20), tolerance = 1e-6)
  # NA covariate gets neutral weight, not dropped
  occ$depth_m[3:4] <- NA_real_
  kp2 <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50, m = 0,
                                covariate_col = "depth_m", site_covariate = 5,
                                lambda_covariate = 20)
  th2 <- kp2$priors$theta_mean[match(c("A", "B"), kp2$priors$taxon_name)]
  expect_equal(th2[1], th2[2], tolerance = 1e-6)
})

test_that("singletons and Good-Turing mass reduce to classical values in the top-hat limit", {
  occ <- .mk_occ(c("A", "A", "A", "B", "C"),
                 lat = 34 + (1:5) * 1e-6, lon = rep(-120, 5))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 1e9, m = 0)
  expect_setequal(kp$singletons$taxon_name, c("B", "C"))
  expect_equal(kp$missing_mass, 2 / 5, tolerance = 1e-6)  # f1/n
  # a far-away record does not count as neighborhood support
  occ2 <- rbind(occ, .mk_occ("D", lat = 34 + 5000 / 111, lon = -120))
  kp2 <- estimate_kernel_priors(occ2, 34, -120, "Marine", lambda_km = 10, m = 0)
  expect_false("D" %in% kp2$singletons$taxon_name)
})

test_that("schema carries prior_branch and effective_records, habitat stratifies, site_id lands in grid_id", {
  occ <- rbind(.mk_occ(c("A", "B"), c(34, 34), c(-120, -120)),
               .mk_occ("Z", 34, -120, habitat = "Terrestrial"))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50,
                               site_id = "BurnsTest")
  expect_true(all(c("taxon_name", "grid_id", "main_habitat", "alpha", "beta",
                    "theta_mean", "theta_sd", "prior_branch",
                    "effective_records") %in% names(kp$priors)))
  expect_false("Z" %in% kp$priors$taxon_name)   # wrong habitat excluded
  expect_true(all(kp$priors$prior_branch == "resident_observed"))
  expect_true(all(kp$priors$grid_id == "BurnsTest"))
  expect_true(all(kp$priors$effective_records > 0))
})

test_that("input validation errors are informative", {
  occ <- .mk_occ("A", 34, -120)
  expect_error(estimate_kernel_priors(occ, 34, -120, "Marine"),
               "calibrate_kernel_bandwidth")           # lambda required
  expect_error(estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = -1),
               "lambda_km")
  expect_error(estimate_kernel_priors(occ, 34, -120, "Freshwater", lambda_km = 10),
               "No usable records")
  expect_error(estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 10,
                                      covariate_col = "depth_m"),
               "site_covariate")
})

test_that("calibrate_kernel_bandwidth prefers locality on spatially structured data", {
  set.seed(42)
  # two regions 300 km apart with different compositions; blocks inside each
  n <- 400
  reg <- rep(c(0, 1), each = n / 2)
  lat <- 34 + reg * (300 / 111) + stats::runif(n, 0, 0.9)
  lon <- -120 + stats::runif(n, 0, 0.9)
  taxa <- ifelse(reg == 0,
                 sample(c("A", "B"), n, TRUE, prob = c(0.9, 0.1)),
                 sample(c("A", "B"), n, TRUE, prob = c(0.1, 0.9)))[seq_len(n)]
  occ <- .mk_occ(taxa, lat, lon)
  cal <- calibrate_kernel_bandwidth(occ, "Marine",
                                    lambda_grid = c(25, 5000),
                                    block_size_deg = 0.45,
                                    min_block_records = 10L)
  r <- cal$results
  ll_local <- r$weighted_logloss[which(r$lambda_km == 25)]
  ll_flat <- r$weighted_logloss[which(r$lambda_km == 5000)]
  expect_lt(ll_local, ll_flat)   # locality must win when structure exists
  expect_true(all(c("regional", "nearest_block") %in% rownames(r)))
  expect_equal(cal$best$lambda_km, 25)
})

test_that("calibrate_kernel_bandwidth validates inputs", {
  occ <- .mk_occ(rep("A", 10), rep(34, 10), rep(-120, 10))
  expect_error(calibrate_kernel_bandwidth(occ, "Marine"), "Too few records")
  expect_error(calibrate_kernel_bandwidth(occ, "Marine", lambda_grid = -5),
               "lambda_grid")
})

test_that("generate_undetected_diversity() accepts a kernel-priors object (B5 port)", {
  occ <- .mk_occ(c("A", "A", "A", "B", "C"),
                 lat = 34 + (1:5) * 1e-6, lon = rep(-120, 5))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 1e9, m = 0,
                               site_id = "KTest")
  ud <- suppressMessages(generate_undetected_diversity(kp))
  # one mirror per neighborhood singleton (B, C) + one global floor
  expect_equal(sum(ud$undetected_type == "singleton_mirror"), 2L)
  expect_equal(sum(ud$undetected_type == "global_floor"), 1L)
  # mirrors are stamped with the SITE id and focal habitat (not dropped-distant cells)
  mir <- ud[ud$undetected_type == "singleton_mirror", ]
  expect_true(all(mir$grid_id == "KTest"))
  expect_true(all(mir$main_habitat == "Marine"))
  expect_setequal(mir$source_taxon_name, c("B", "C"))
  # mirror theta ~ singleton effective share (1/5 in the top-hat limit)
  expect_equal(mir$theta_mean, rep(1 / 5, 2), tolerance = 1e-6)
  # floor = Beta(1, N_eff - 1) on the Kish N
  fl <- ud[ud$undetected_type == "global_floor", ]
  expect_equal(fl$alpha, 1); expect_equal(fl$beta, 5 - 1)
  expect_equal(fl$n_obs, 5L)
  # frozen-machinery columns + new branch label both present
  expect_true(all(ud$model_tier == "tier3_undetected"))
  expect_true(all(ud$prior_branch == "resident_undetected"))
  # taxonomy join still works through the adapter
  tx <- data.frame(taxon_name = c("B", "C"), genus = c("Bg", "Cg"),
                   family = c("Bf", "Cf"), stringsAsFactors = FALSE)
  ud2 <- suppressMessages(generate_undetected_diversity(kp, taxonomy = tx))
  mir2 <- ud2[ud2$undetected_type == "singleton_mirror", ]
  expect_setequal(mir2$genus, c("Bg", "Cg"))
})

test_that("kernel priors carry observed_in_habitat = TRUE (join_priors D1 guard)", {
  occ <- .mk_occ(c("A", "B"), c(34, 34), c(-120, -120))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50)
  expect_true(all(kp$priors$observed_in_habitat))
})
