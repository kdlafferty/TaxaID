.patches <- function(g, nsp, n, sd_deg, seed) {
  set.seed(seed)
  sp <- paste0(g, "_sp", seq_len(nsp))
  cl <- seq(34.15, 35.85, length.out = nsp); co <- seq(-121.35, -119.65, length.out = nsp)
  i <- sample(nsp, n, TRUE)
  data.frame(
    taxon_name       = sp[i],
    decimalLatitude  = pmin(pmax(stats::rnorm(n, cl[i], sd_deg), 34), 36),
    decimalLongitude = pmin(pmax(stats::rnorm(n, co[i], sd_deg), -121.5), -119.5),
    main_habitat     = "Marine",
    sampling_group   = g,
    stringsAsFactors = FALSE
  )
}
.args <- function(d) list(d, "Marine", lambda_grid = c(5, 10, 25, 50, 100, 200),
                          block_size_deg = 0.5, min_block_records = 20L)

test_that("sampling_group_col = NULL reproduces the ungrouped fit EXACTLY", {
  # The regression that matters: this function's default must not move. A
  # grouped code path that changes the pooled answer would silently
  # recalibrate every workflow that already shipped a lambda.
  d <- rbind(.patches("A", 12, 3000, 0.05, 1), .patches("B", 12, 1500, 0.30, 2))
  one <- d; one$sampling_group <- "everything"
  a <- suppressMessages(do.call(calibrate_kernel_bandwidth, .args(d)))
  b <- suppressMessages(do.call(calibrate_kernel_bandwidth,
                                c(.args(one), list(sampling_group_col = "sampling_group"))))
  # One group, however it is spelled, must equal the pooled fit.
  expect_equal(a$results$weighted_logloss, b$results$weighted_logloss)
  expect_equal(a$best$lambda_km, b$best$lambda_km)
  expect_null(a$by_group)
})

test_that("a single group yields no by_group table", {
  d <- .patches("A", 12, 2000, 0.05, 3)
  r <- suppressMessages(do.call(calibrate_kernel_bandwidth,
                                c(.args(d), list(sampling_group_col = "sampling_group"))))
  expect_null(r$by_group)
})

test_that("each group's own optimum is reported, and disagreement warns", {
  # 4 km patches vs 55 km patches: the groups genuinely want different
  # bandwidths, and the dominant one must not silently speak for both.
  d <- rbind(.patches("A", 14, 6000, 0.035, 3), .patches("B", 14, 1500, 0.50, 4))
  expect_warning(
    r <- suppressMessages(do.call(calibrate_kernel_bandwidth,
                                  c(.args(d), list(sampling_group_col = "sampling_group")))),
    regexp = "disagree on lambda_km"
  )
  expect_s3_class(r$by_group, "data.frame")
  expect_setequal(r$by_group$sampling_group, c("A", "B"))
  expect_true(all(r$by_group$n_blocks_scored > 0))
  # The tight group wants a narrower kernel than the broad one.
  lam <- stats::setNames(r$by_group$lambda_km, r$by_group$sampling_group)
  expect_lt(lam[["A"]], lam[["B"]])
  # And the single compromise follows the group with more records.
  expect_equal(r$best$lambda_km, lam[["A"]])
})

test_that("groups agreeing produces no warning", {
  d <- rbind(.patches("A", 12, 3000, 0.05, 5), .patches("B", 12, 3000, 0.05, 6))
  expect_no_warning(
    suppressMessages(do.call(calibrate_kernel_bandwidth,
                             c(.args(d), list(sampling_group_col = "sampling_group"))))
  )
})

test_that("an NA sampling_group becomes its own stratum rather than being dropped", {
  d <- rbind(.patches("A", 12, 3000, 0.05, 7), .patches("B", 12, 1200, 0.05, 8))
  d$sampling_group[d$sampling_group == "B"] <- NA
  r <- suppressMessages(do.call(calibrate_kernel_bandwidth,
                                c(.args(d), list(sampling_group_col = "sampling_group"))))
  expect_true("__ungrouped__" %in% r$by_group$sampling_group)
  expect_equal(sum(r$by_group$n_records), nrow(d))
})

test_that("min_group_records defaults to min_block_records, matching the subsetting route", {
  # Block ELIGIBILITY is decided from the pooled record set before grouping
  # exists, so without a per-group bar a block qualifies on its pooled count
  # and a thin group joins it with a handful of records. The other way of
  # fitting per group -- subsetting and calling this function per subset,
  # as Multi_site_multi_marker/21_calibrate_depth_per_group.R does -- requires
  # min_block_records of that group's OWN records. The default makes the two
  # agree, so their answers are comparable.
  d <- rbind(.patches("A", 14, 6000, 0.035, 3), .patches("B", 14, 1500, 0.50, 4))
  G <- c(5, 10, 25, 50, 100, 200)
  strat <- suppressWarnings(suppressMessages(calibrate_kernel_bandwidth(
    d, "Marine", lambda_grid = G, block_size_deg = 0.5, min_block_records = 20L,
    sampling_group_col = "sampling_group")))
  blk <- function(x) paste0(floor(x$decimalLatitude / 0.5), "_", floor(x$decimalLongitude / 0.5))
  for (g in c("A", "B")) {
    dg <- d[d$sampling_group == g, ]
    sub <- suppressWarnings(suppressMessages(calibrate_kernel_bandwidth(
      dg, "Marine", lambda_grid = G, block_size_deg = 0.5, min_block_records = 20L)))
    tb <- table(blk(dg))
    expect_equal(sub$n_blocks, sum(tb >= 20))
    expect_equal(strat$by_group$n_blocks_scored[strat$by_group$sampling_group == g],
                 sum(tb >= 20))
  }
})

test_that("lowering min_group_records admits the sparse cells it is meant to", {
  # The fixture has to CONTAIN sparse cells or this tests nothing: group "thin"
  # is spread so it contributes a handful of records to blocks that qualify on
  # the dominant group's count. A first version of this test used two patchy
  # groups and passed vacuously -- a patchy group puts either >= 20 or < 2
  # records in a block, never 5, so the bar had nothing to exclude.
  set.seed(21)
  dom <- .patches("dom", 14, 6000, 0.30, 12)
  n <- 120
  thin <- data.frame(
    taxon_name       = sample(paste0("thin_sp", 1:6), n, TRUE),
    decimalLatitude  = stats::runif(n, 34, 36),
    decimalLongitude = stats::runif(n, -121.5, -119.5),
    main_habitat     = "Marine",
    sampling_group   = "thin",
    stringsAsFactors = FALSE
  )
  d <- rbind(dom, thin)
  blk <- paste0(floor(d$decimalLatitude / 0.5), "_", floor(d$decimalLongitude / 0.5))
  tt <- table(blk[d$sampling_group == "thin"])
  expect_gt(sum(tt >= 2 & tt < 20), 0)   # the fixture really has sparse cells

  G <- c(10, 25, 50)
  strict <- suppressWarnings(suppressMessages(calibrate_kernel_bandwidth(
    d, "Marine", lambda_grid = G, block_size_deg = 0.5, min_block_records = 20L,
    sampling_group_col = "sampling_group")))
  loose <- suppressWarnings(suppressMessages(calibrate_kernel_bandwidth(
    d, "Marine", lambda_grid = G, block_size_deg = 0.5, min_block_records = 20L,
    sampling_group_col = "sampling_group", min_group_records = 2)))
  n_thin <- function(r) {
    v <- r$by_group$n_blocks_scored[r$by_group$sampling_group == "thin"]
    if (length(v) == 0L) 0L else v
  }
  expect_gt(n_thin(loose), n_thin(strict))
})

test_that("min_group_records below 2 is refused", {
  d <- rbind(.patches("A", 12, 2000, 0.05, 9), .patches("B", 12, 2000, 0.05, 10))
  expect_error(
    calibrate_kernel_bandwidth(d, "Marine", lambda_grid = c(10, 25),
                               sampling_group_col = "sampling_group",
                               min_group_records = 1),
    regexp = "min_group_records"
  )
})
