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

# ------------------------------------------------------------------------------
# Climate-similarity (absolute-latitude) kernel factor (2026-08-31)
# ------------------------------------------------------------------------------

test_that("lambda_latitude = NULL reproduces the unfactored weights exactly", {
  occ <- .mk_occ(c("A", "B", "B"), lat = c(34, 35, 34),
                 lon = c(-120, -120, -119))
  kp0 <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50, m = 0)
  kp1 <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50, m = 0,
                                lambda_latitude = NULL)
  expect_equal(kp0$priors$theta_mean, kp1$priors$theta_mean, tolerance = 1e-12)
  expect_null(kp1$params$lambda_latitude)
})

test_that("lambda_latitude penalizes N-S displacement more than E-W", {
  # A due north of the site, B due east, both exactly 111 km away: the
  # geographic factor is identical, so only the climate factor separates them.
  occ <- .mk_occ(c("A", "B"), lat = c(35, 34),
                 lon = c(-120, -120 + 1 / cos(34 * pi / 180)))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 100, m = 0,
                               lambda_latitude = 111)
  th <- kp$priors$theta_mean[match(c("A", "B"), kp$priors$taxon_name)]
  # A carries the extra factor exp(-111*1/111) = exp(-1); B carries none.
  expect_equal(th[1] / th[2], exp(-1), tolerance = 1e-6)
})

test_that("climate factor is hemisphere-symmetric (absolute latitude)", {
  # site at 10 N; A at 10 S (|dlat| = 20 geographically, climate delta 0),
  # B at 30 N (|dlat| = 20 geographically, climate delta 20 deg). Same
  # longitude, same geographic distance -- only climate separates them.
  occ <- .mk_occ(c("A", "B"), lat = c(-10, 30), lon = c(-120, -120))
  kp <- estimate_kernel_priors(occ, 10, -120, "Marine", lambda_km = 1e9, m = 0,
                               lambda_latitude = 555)
  th <- kp$priors$theta_mean[match(c("A", "B"), kp$priors$taxon_name)]
  # A: climate factor exp(0) = 1; B: exp(-111*20/555) = exp(-4)
  expect_equal(th[1] / th[2], exp(4), tolerance = 1e-4)
})

test_that("calibrate_kernel_bandwidth sweeps lambda_latitude with an Inf off-switch", {
  set.seed(42)
  n <- 240
  occ <- .mk_occ(sample(c("A", "B", "C"), n, replace = TRUE),
                 lat = runif(n, 34, 36), lon = runif(n, -121, -119))
  cal <- calibrate_kernel_bandwidth(occ, "Marine", lambda_grid = c(50, 100),
                                    lambda_latitude_grid = c(50),
                                    block_size_deg = 0.5,
                                    min_block_records = 10L)
  expect_true("lambda_latitude" %in% names(cal$results))
  # Inf added automatically: both 50 and Inf appear among kernel rows
  ll <- cal$results$lambda_latitude
  expect_true(any(is.infinite(ll[!is.na(ll)])))
  expect_true(any(ll[!is.na(ll)] == 50))
  # NULL grid still works and yields NA column (references) without the sweep
  cal0 <- calibrate_kernel_bandwidth(occ, "Marine", lambda_grid = c(50, 100),
                                     block_size_deg = 0.5,
                                     min_block_records = 10L)
  expect_true(all(is.na(cal0$results$lambda_latitude)))
})

test_that("lambda_latitude = Inf in the sweep scores identically to no factor", {
  set.seed(7)
  n <- 200
  occ <- .mk_occ(sample(c("A", "B"), n, replace = TRUE),
                 lat = runif(n, 34, 36), lon = runif(n, -121, -119))
  cal_off <- calibrate_kernel_bandwidth(occ, "Marine", lambda_grid = 50,
                                        block_size_deg = 0.5,
                                        min_block_records = 10L)
  cal_inf <- calibrate_kernel_bandwidth(occ, "Marine", lambda_grid = 50,
                                        lambda_latitude_grid = c(25),
                                        block_size_deg = 0.5,
                                        min_block_records = 10L)
  off_ll <- cal_off$results$weighted_logloss[1]
  inf_row <- which(is.infinite(cal_inf$results$lambda_latitude))
  expect_equal(cal_inf$results$weighted_logloss[inf_row], off_ll,
               tolerance = 1e-12)
})

test_that("priors/singletons are tibbles (drop-in parity with generate_full_priors)", {
  # Real breakage this guards (2026-09-01, first Mugu kernel run): a plain
  # data.frame drops a single-column `[` selection to a bare vector, so
  # workflow code written against the GLMM path's tibble output errored with
  # "no applicable method for 'left_join' applied to an object of class
  # character". bind_rows() also inherits its class from its first argument.
  occ <- .mk_occ(c("A", "A", "B"), lat = 34, lon = -120)
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50)
  expect_s3_class(kp$priors, "tbl_df")
  expect_s3_class(kp$singletons, "tbl_df")
  # the operative invariant: single-column selection stays a data frame
  expect_true(is.data.frame(kp$priors[!is.na(kp$priors$taxon_name), c("taxon_name")]))
  # and an assembled table keeps the class through bind_rows()
  expect_s3_class(dplyr::bind_rows(kp$priors, kp$priors), "tbl_df")
})

# ------------------------------------------------------------------------------
# Post-hoc fetch-scope guards (2026-09-02). lambda cannot inform the fetch
# radius a priori -- it is estimated FROM the fetched data -- so the honest
# controls are checked after the fact.
# ------------------------------------------------------------------------------

test_that("estimate_kernel_priors warns when the pool does not reach 6 lambda", {
  # records confined to ~10 km, lambda 50 km => 6 lambda = 300 km >> reach
  occ <- .mk_occ(rep(c("A", "B"), each = 5),
                 lat = 34 + seq(0, 0.09, length.out = 10), lon = -120)
  expect_warning(
    estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50),
    "truncated by the fetch boundary")
  # a small lambda against the same pool is fine
  expect_no_warning(
    estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 1))
})

test_that("calibrate_kernel_bandwidth warns when the best lambda is the grid maximum", {
  set.seed(11)
  n <- 300
  occ <- .mk_occ(sample(c("A", "B", "C"), n, replace = TRUE),
                 lat = runif(n, 34, 36), lon = runif(n, -121, -119))
  # Grid chosen by measuring this fixture, not by assumption: on these
  # spatially unstructured labels the loss curve is nearly flat, and among
  # c(50, 100) the larger bandwidth wins -- pinning the optimum at the top of
  # the grid, which is what the warning exists to report. (Very LARGE lambdas
  # would not test it: the kernel saturates, ties on loss, and which.min then
  # returns the FIRST row, i.e. the grid minimum.)
  expect_warning(
    calibrate_kernel_bandwidth(occ, "Marine", lambda_grid = c(50, 100),
                               block_size_deg = 0.5, min_block_records = 10L),
    "LARGEST value in lambda_grid")
  # and the opposite edge is reported too, as a message rather than a warning
  expect_message(
    calibrate_kernel_bandwidth(occ, "Marine", lambda_grid = c(1, 5, 25),
                               block_size_deg = 0.5, min_block_records = 10L),
    "SMALLEST value offered")
})

# ------------------------------------------------------------------------------
# sampling_group_col (2026-09-03). Composition and the Good-Turing budget are
# both SHARED-DENOMINATOR quantities that assume one detection process. The
# GLMM path enforced this (prepare_model_dataframe(sampling_group_col=),
# Session 149); the kernel rewrite dropped it. Restored here.
# ------------------------------------------------------------------------------

.mixed_pool <- function() {
  set.seed(42)
  fish <- do.call(rbind, lapply(1:20, function(i) data.frame(
    taxon_name = sprintf("Fish_%02d", i),
    decimalLatitude = 34.1 + rnorm(30, 0, .05),
    decimalLongitude = -119.1 + rnorm(30, 0, .05),
    main_habitat = "Coastal", sampling_group = "fish", stringsAsFactors = FALSE)))
  fish_rare <- do.call(rbind, lapply(1:4, function(i) data.frame(
    taxon_name = sprintf("FishRare_%02d", i),
    decimalLatitude = 34.1 + rnorm(1, 0, .05),
    decimalLongitude = -119.1 + rnorm(1, 0, .05),
    main_habitat = "Coastal", sampling_group = "fish", stringsAsFactors = FALSE)))
  # "downwash" taxa: present in the occurrence pool, one record each, and
  # effectively unsampleable by the assay the priors are for.
  bird <- do.call(rbind, lapply(1:30, function(i) data.frame(
    taxon_name = sprintf("Bird_%02d", i),
    decimalLatitude = 34.1 + rnorm(1, 0, .05),
    decimalLongitude = -119.1 + rnorm(1, 0, .05),
    main_habitat = "Coastal", sampling_group = "bird", stringsAsFactors = FALSE)))
  rbind(fish, fish_rare, bird)
}

test_that("sampling_group_col = NULL reproduces the ungrouped result exactly", {
  occ <- .mixed_pool()
  a <- suppressWarnings(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal",
                                               lambda_km = 25, m = 1))
  # one constant group must be identical to no grouping at all
  occ$one <- "only"
  b <- suppressWarnings(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal",
                                               lambda_km = 25, m = 1,
                                               sampling_group_col = "one"))
  expect_equal(a$priors$theta_mean,
               b$priors$theta_mean[match(a$priors$taxon_name, b$priors$taxon_name)])
  expect_equal(a$n_eff, b$n_eff)
  expect_equal(a$f1, b$f1); expect_equal(a$f2, b$f2)
  expect_equal(a$theta_present, b$theta_present)
  # the ungrouped schema must not gain a column
  expect_false("sampling_group" %in% names(a$priors))
  expect_true("sampling_group" %in% names(b$priors))
})

test_that("pooling groups with different detection processes deflates theta_present", {
  # The mechanism: barely-sampled taxa contribute singletons that inflate f1 --
  # and so Chao, quadratically -- while adding almost nothing to missing_mass.
  occ <- .mixed_pool()
  pooled  <- suppressWarnings(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal",
                                                     lambda_km = 25, m = 1))
  grouped <- suppressWarnings(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal",
                                                     lambda_km = 25, m = 1,
                                                     sampling_group_col = "sampling_group"))
  tp_fish <- grouped$budget$theta_present[grouped$budget$sampling_group == "fish"]

  # pooling drags the detectable group's price DOWN, substantially
  expect_true(pooled$theta_present < tp_fish)
  expect_gt(tp_fish / pooled$theta_present, 2)

  # the pooled f1 is the sum of the groups' f1; the fish group's own is small
  expect_equal(pooled$f1, sum(grouped$budget$f1))
  expect_lt(grouped$budget$f1[grouped$budget$sampling_group == "fish"], pooled$f1)
})

test_that("grouped fits give each group its own simplex and its own budget", {
  occ <- .mixed_pool()
  g <- suppressWarnings(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal",
                                               lambda_km = 25, m = 1,
                                               sampling_group_col = "sampling_group"))
  for (grp in c("fish", "bird")) {
    s <- sum(g$priors$theta_mean[g$priors$sampling_group == grp])
    expect_equal(s, 1, tolerance = 1e-6)
  }
  expect_equal(nrow(g$budget), 2L)
  expect_setequal(g$budget$sampling_group, c("fish", "bird"))
  expect_true(all(g$budget$n_eff > 0))
})

test_that("a multi-group fit reports NA pooled scalars rather than a wrong number", {
  occ <- .mixed_pool()
  g <- suppressWarnings(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal",
                                               lambda_km = 25, m = 1,
                                               sampling_group_col = "sampling_group"))
  # There is no single budget across detection processes; a scalar would be
  # silently wrong wherever it were used.
  expect_true(is.na(g$theta_present))
  expect_true(is.na(g$chao_missing))
  expect_true(is.na(g$f1)); expect_true(is.na(g$f2))
  expect_equal(g$params$n_sampling_groups, 2L)
  # ...but the per-group table is complete
  expect_false(any(is.na(g$budget$theta_present)))
})

test_that("curve pricing refuses a multi-group fit with an actionable message", {
  occ <- .mixed_pool()
  g <- suppressWarnings(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal",
                                               lambda_km = 25, m = 1,
                                               sampling_group_col = "sampling_group"))
  ev <- data.frame(taxon_name = "Fish_01", w = 0.5, p_conc = 1,
                   source = "test", stringsAsFactors = FALSE)
  expect_error(
    apply_undetected_evidence(taxaexpect_priors = g$priors, evidence = ev,
                              model_obj = g, grid_id = "x", pricing = "curve"),
    "no single theta_present|sampling_group_col")
})

test_that("sampling_group_col validates its input", {
  occ <- .mixed_pool()
  expect_error(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal", lambda_km = 25,
                                      sampling_group_col = "nope"), "not found")
  expect_error(estimate_kernel_priors(occ, 34.1, -119.1, "Coastal", lambda_km = 25,
                                      sampling_group_col = c("a", "b")), "single column")
})
