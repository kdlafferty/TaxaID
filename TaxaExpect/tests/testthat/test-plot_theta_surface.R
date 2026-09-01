# Tests for plot_theta_surface() (2026-09-01, branch theta-surface). The
# numeric engine (.theta_surface_engine / .theta_surface_fft_convolve) is
# tested directly with :::, matching the established convention of testing
# the pure internals without a live interactive session (see
# test-plot_theta_map_interactive.R). Fixtures are synthetic with
# hand-computable or estimator-comparable answers -- the site-identity
# reduction to estimate_kernel_priors() is the key invariant (spec:
# ecosystem_docs/SPEC_plot_theta_surface.md).

.mk_occ <- function(taxa, lat, lon, habitat = "Marine", depth = NA_real_) {
  data.frame(taxon_name = taxa, decimalLatitude = lat, decimalLongitude = lon,
             main_habitat = habitat, depth_m = depth, stringsAsFactors = FALSE)
}

.eng <- function(occ, site_lat, site_lon, site_habitat = "Marine", lambda_km,
                 m = 1, taxon, n_grid = 128L, bbox = NULL,
                 covariate_col = NULL, covariate_at = NULL, lambda_covariate = NULL,
                 lambda_latitude = NULL) {
  TaxaExpect:::.theta_surface_engine(
    occurrence_data = occ, site_lat = site_lat, site_lon = site_lon,
    site_habitat = site_habitat, lambda_km = lambda_km, m = m,
    covariate_col = covariate_col, covariate_at = covariate_at,
    lambda_covariate = lambda_covariate, lambda_latitude = lambda_latitude,
    taxon = taxon, n_grid = n_grid, bbox = bbox,
    taxon_col = "taxon_name", lat_col = "decimalLatitude",
    lon_col = "decimalLongitude", habitat_col = "main_habitat"
  )
}

.nearest_idx <- function(grid, v) which.min(abs(grid - v))

# ------------------------------------------------------------------------------
# FFT convolution vs brute force (small fixture)
# ------------------------------------------------------------------------------

test_that(".theta_surface_fft_convolve matches brute-force 2-D convolution", {
  set.seed(11)
  ny <- 6L; nx <- 7L
  mass <- matrix(0, ny, nx)
  mass[c(2, 4, 5), c(3, 1, 7)] <- c(1.3, 0.6, 2.1)
  kernel <- matrix(stats::rnorm((2 * ny - 1) * (2 * nx - 1)), 2 * ny - 1, 2 * nx - 1)

  fft_out <- TaxaExpect:::.theta_surface_fft_convolve(mass, kernel)

  brute <- matrix(0, ny, nx)
  for (xi in seq_len(ny)) for (xj in seq_len(nx)) {
    s <- 0
    for (ri in seq_len(ny)) for (rj in seq_len(nx)) {
      if (mass[ri, rj] == 0) next
      krow <- (xi - ri) + ny; kcol <- (xj - rj) + nx
      s <- s + mass[ri, rj] * kernel[krow, kcol]
    }
    brute[xi, xj] <- s
  }
  expect_equal(fft_out, brute, tolerance = 1e-9)
})

test_that(".theta_surface_fft_convolve_batch agrees with the single-pair convolution", {
  set.seed(12)
  ny <- 5L; nx <- 5L
  m1 <- matrix(stats::rpois(ny * nx, 1), ny, nx)
  m2 <- matrix(stats::rpois(ny * nx, 2), ny, nx)
  kernel <- matrix(exp(-abs(stats::rnorm((2 * ny - 1) * (2 * nx - 1)))),
                   2 * ny - 1, 2 * nx - 1)
  single1 <- TaxaExpect:::.theta_surface_fft_convolve(m1, kernel)
  single2 <- TaxaExpect:::.theta_surface_fft_convolve(m2, kernel)
  batch <- TaxaExpect:::.theta_surface_fft_convolve_batch(list(m1, m2), kernel)
  expect_equal(batch[[1L]], single1, tolerance = 1e-9)
  expect_equal(batch[[2L]], single2, tolerance = 1e-9)
})

# ------------------------------------------------------------------------------
# Site-identity invariant (THE critical test)
# ------------------------------------------------------------------------------

test_that("surface theta at the site reduces to estimate_kernel_priors() theta (no latitude factor)", {
  set.seed(42)
  n <- 400
  occ <- .mk_occ(sample(c("A", "B", "C", "D"), n, TRUE, prob = c(0.4, 0.3, 0.2, 0.1)),
                lat = 34 + stats::rnorm(n, 0, 0.5), lon = -120 + stats::rnorm(n, 0, 0.5))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 30, m = 2)
  surf <- .eng(occ, 34, -120, lambda_km = 30, m = 2, taxon = c("A", "B", "C", "D"), n_grid = 200L)

  i0 <- .nearest_idx(surf$lat_grid, 34); j0 <- .nearest_idx(surf$lon_grid, -120)
  expect_equal(surf$lat_grid[i0], 34, tolerance = 1e-9)   # anchored exactly on the site
  expect_equal(surf$lon_grid[j0], -120, tolerance = 1e-9)
  expect_equal(surf$n_eff[i0, j0], kp$n_eff, tolerance = 1e-2)

  # 1e-2 absolute: the surface is a BINNED (histogram) KDE approximation of
  # the exact estimator, so equality holds only to grid-quantization
  # tolerance, not machine precision -- tighter at finer n_grid (see
  # @section The estimator, on a lattice).
  for (tx in c("A", "B", "C", "D")) {
    est <- kp$priors$theta_mean[kp$priors$taxon_name == tx]
    expect_equal(surf$theta[[tx]][i0, j0], est, tolerance = 1e-2)
  }
})

test_that("surface theta at the site reduces to estimate_kernel_priors() theta WITH a latitude factor", {
  set.seed(43)
  n <- 400
  occ <- .mk_occ(sample(c("A", "B", "C"), n, TRUE, prob = c(0.5, 0.3, 0.2)),
                lat = 34 + stats::rnorm(n, 0, 0.5), lon = -120 + stats::rnorm(n, 0, 0.5))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 25, m = 1,
                               lambda_latitude = 200)
  surf <- .eng(occ, 34, -120, lambda_km = 25, m = 1, taxon = c("A", "B", "C"),
              n_grid = 200L, lambda_latitude = 200)

  i0 <- .nearest_idx(surf$lat_grid, 34); j0 <- .nearest_idx(surf$lon_grid, -120)
  for (tx in c("A", "B", "C")) {
    est <- kp$priors$theta_mean[kp$priors$taxon_name == tx]
    expect_equal(surf$theta[[tx]][i0, j0], est, tolerance = 1e-2)
  }
})

test_that("m override changes the surface but defaulting to the fit's own m reproduces it", {
  set.seed(44)
  n <- 300
  # local composition all-A, region also holds B far away (same construction
  # as test-estimate_kernel_priors.R's own m-backoff test) -- so m has real
  # leverage here, unlike a fixture where local ~ regional composition
  # already and back-off is a near no-op regardless of m.
  far <- 5000 / 111
  occ <- .mk_occ(c(rep("A", 20), "B"),
                lat = c(rep(34, 20), 34 + far), lon = rep(-120, 21))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 20, m = 3)
  surf_default <- .eng(occ, 34, -120, lambda_km = 20, m = 3, taxon = "B", n_grid = 150L)
  surf_other   <- .eng(occ, 34, -120, lambda_km = 20, m = 500, taxon = "B", n_grid = 150L)
  i0 <- .nearest_idx(surf_default$lat_grid, 34); j0 <- .nearest_idx(surf_default$lon_grid, -120)
  est <- kp$priors$theta_mean[kp$priors$taxon_name == "B"]
  expect_equal(surf_default$theta[i0, j0], est, tolerance = 1e-2)
  expect_gt(abs(surf_other$theta[i0, j0] - est), 0.02)
})

# ------------------------------------------------------------------------------
# Top-hat limit
# ------------------------------------------------------------------------------

test_that("a very large lambda flattens the surface to the regional composition", {
  set.seed(45)
  n <- 300
  occ <- .mk_occ(sample(c("A", "B", "C"), n, TRUE, prob = c(0.5, 0.3, 0.2)),
                lat = 34 + stats::rnorm(n, 0, 0.3), lon = -120 + stats::rnorm(n, 0, 0.3))
  reg <- table(occ$taxon_name) / nrow(occ)
  surf <- .eng(occ, 34, -120, lambda_km = 1e9, m = 0, taxon = c("A", "B", "C"), n_grid = 60L)
  for (tx in c("A", "B", "C")) {
    expect_equal(as.numeric(range(surf$theta[[tx]])),
                rep(unname(reg[tx]), 2), tolerance = 1e-6)
  }
})

# ------------------------------------------------------------------------------
# Covariate honesty
# ------------------------------------------------------------------------------

test_that("covariate_at = NULL on a covariate-built fit emits a message and omits the factor", {
  occ <- .mk_occ(c("A", "A", "B", "B"), lat = rep(34, 4), lon = rep(-120, 4),
                depth = c(5, 5, 105, 105))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50, m = 0,
                               covariate_col = "depth_m", site_covariate = 5,
                               lambda_covariate = 20)
  expect_message(
    out <- plot_theta_surface(kp, occ, taxon = "A", n_grid = 20L),
    "covariate_at not supplied.*OMITTED"
  )
  expect_null(out$surface$params$covariate_at)
})

test_that("supplying covariate_at reweights the surface toward the matching covariate value", {
  occ <- .mk_occ(c("A", "A", "B", "B"), lat = rep(34, 4), lon = rep(-120, 4),
                depth = c(5, 5, 105, 105))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50, m = 0,
                               covariate_col = "depth_m", site_covariate = 5,
                               lambda_covariate = 20)
  surf <- .eng(occ, 34, -120, lambda_km = 50, m = 0, taxon = c("A", "B"), n_grid = 60L,
              covariate_col = "depth_m", covariate_at = 5, lambda_covariate = 20)
  i0 <- .nearest_idx(surf$lat_grid, 34); j0 <- .nearest_idx(surf$lon_grid, -120)
  th <- c(surf$theta$A[i0, j0], surf$theta$B[i0, j0])
  expect_equal(th[1] / th[2], 1 / exp(-100 / 20), tolerance = 1e-2)
})

test_that("covariate_at supplied against a fit with no covariate_col errors", {
  occ <- .mk_occ(c("A", "B"), c(34, 34), c(-120, -120))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50)
  expect_error(
    plot_theta_surface(kp, occ, taxon = "A", covariate_at = 5, n_grid = 20L),
    "no covariate_col"
  )
})

# ------------------------------------------------------------------------------
# Zero-record species / empty bbox -- graceful, no error
# ------------------------------------------------------------------------------

test_that("a taxon absent from the habitat stratum returns a graceful zero-ish surface, no error", {
  occ <- .mk_occ(c("A", "A", "B"), lat = rep(34, 3), lon = rep(-120, 3))
  expect_message(
    surf <- .eng(occ, 34, -120, lambda_km = 20, m = 1, taxon = "Z", n_grid = 30L),
    "zero records"
  )
  expect_true(all(is.finite(surf$theta)))
  expect_true(all(surf$theta >= 0))
})

test_that("a bbox with no nearby records returns gracefully (W = 0, no error)", {
  occ <- .mk_occ(c("A", "A", "B"), lat = rep(34, 3), lon = rep(-120, 3))
  far_bbox <- c(lat_min = 10, lat_max = 10.5, lon_min = -60, lon_max = -59.5)
  expect_no_error(
    surf <- .eng(occ, 34, -120, lambda_km = 5, m = 1, taxon = "A", n_grid = 20L, bbox = far_bbox)
  )
  expect_true(all(surf$W == 0))
  expect_true(all(surf$n_eff == 0))
  # m > 0: theta backs off entirely to the regional composition p_i
  expect_equal(as.numeric(surf$theta), rep(surf$regional_composition["A"], length(surf$theta)),
              tolerance = 1e-9, ignore_attr = TRUE)
})

# ------------------------------------------------------------------------------
# Public wrapper: validation, class, plot object
# ------------------------------------------------------------------------------

test_that("plot_theta_surface validates kernel_fit and taxon", {
  occ <- .mk_occ(c("A", "B"), c(34, 34), c(-120, -120))
  expect_error(plot_theta_surface(list(), occ, taxon = "A"), "taxaexpect_kernel_priors")
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 50)
  expect_error(plot_theta_surface(kp, occ, taxon = 1), "character vector")
})

test_that("plot_theta_surface returns a taxaexpect_theta_surface object with surface + plot", {
  occ <- .mk_occ(c("A", "A", "B"), lat = rep(34, 3), lon = rep(-120, 3))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 20)
  out <- plot_theta_surface(kp, occ, taxon = "A", n_grid = 24L)
  expect_s3_class(out, "taxaexpect_theta_surface")
  expect_true(all(c("lat_grid", "lon_grid", "theta", "n_eff", "W") %in% names(out$surface)))
  expect_output(print(out), "taxaexpect_theta_surface")
})

test_that("plot_theta_surface supports multiple taxa as a named list of surfaces", {
  occ <- .mk_occ(c("A", "A", "B", "C"), lat = rep(34, 4), lon = rep(-120, 4))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 20)
  out <- plot_theta_surface(kp, occ, taxon = c("A", "B"), n_grid = 24L)
  expect_true(is.list(out$surface$theta))
  expect_setequal(names(out$surface$theta), c("A", "B"))
})

test_that("plot_theta_surface(interactive = TRUE) requires leaflet and returns a leaflet map when available", {
  skip_if_not_installed("leaflet")
  occ <- .mk_occ(c("A", "A", "B"), lat = rep(34, 3), lon = rep(-120, 3))
  kp <- estimate_kernel_priors(occ, 34, -120, "Marine", lambda_km = 20)
  out <- plot_theta_surface(kp, occ, taxon = "A", n_grid = 24L, interactive = TRUE)
  expect_s3_class(out$plot, "leaflet")
})

# ------------------------------------------------------------------------------
# User-feedback round (2026-09-01, first real click-through): mask parameter,
# and the interactive map's marker/legend/hover/selector behaviour.
# ------------------------------------------------------------------------------

test_that("mask (lon/lat matrix) NAs out cells outside the polygon", {
  occ <- data.frame(
    taxon_name = rep(c("A", "B"), each = 6),
    decimalLatitude = c(34.0, 34.1, 34.2, 34.3, 34.4, 34.5, 34.0, 34.1, 34.2, 34.3, 34.4, 34.5),
    decimalLongitude = rep(c(-120.0, -119.9, -119.8), 4),
    main_habitat = "Marine", stringsAsFactors = FALSE)
  kp <- estimate_kernel_priors(occ, 34.2, -119.9, "Marine", lambda_km = 50)
  # a small box around the site only
  box <- cbind(c(-120.0, -119.8, -119.8, -120.0),
               c(34.15,  34.15,  34.25,  34.25))
  s_all  <- plot_theta_surface(kp, occ, taxon = "A", n_grid = 32L)
  s_mask <- plot_theta_surface(kp, occ, taxon = "A", n_grid = 32L, mask = box)
  expect_true(all(is.finite(s_all$surface$theta)))
  expect_true(any(is.na(s_mask$surface$theta)))
  # inside the box the values are untouched
  ilat <- which.min(abs(s_mask$surface$lat_grid - 34.2))
  ilon <- which.min(abs(s_mask$surface$lon_grid - -119.9))
  expect_equal(s_mask$surface$theta[ilat, ilon], s_all$surface$theta[ilat, ilon])
  expect_gt(s_mask$surface$params$masked_cells, 0)
  # n_eff/W are masked consistently with theta
  expect_true(all(is.na(s_mask$surface$n_eff[is.na(s_mask$surface$theta)])))
})

test_that("mask accepts a list of polygons and validates its input", {
  occ <- data.frame(taxon_name = c("A", "A", "B"),
                    decimalLatitude = c(34, 34.1, 34.2),
                    decimalLongitude = c(-120, -119.9, -119.8),
                    main_habitat = "Marine", stringsAsFactors = FALSE)
  kp <- estimate_kernel_priors(occ, 34.1, -119.9, "Marine", lambda_km = 50)
  two <- list(cbind(c(-120.05, -119.95, -119.95, -120.05), c(33.95, 33.95, 34.05, 34.05)),
              cbind(c(-119.85, -119.75, -119.75, -119.85), c(34.15, 34.15, 34.25, 34.25)))
  s <- plot_theta_surface(kp, occ, taxon = "A", n_grid = 24L, mask = two)
  expect_true(any(is.na(s$surface$theta)))
  expect_true(any(is.finite(s$surface$theta)))   # both boxes survive
  expect_error(plot_theta_surface(kp, occ, taxon = "A", n_grid = 16L,
                                  mask = cbind(1:2, 1:2)), "at least 3 vertices")
})

test_that("interactive map carries legend, hover labels, small site marker and a species selector", {
  skip_if_not_installed("leaflet")
  occ <- data.frame(taxon_name = rep(c("A", "B"), each = 4),
                    decimalLatitude = rep(c(34.0, 34.1, 34.2, 34.3), 2),
                    decimalLongitude = rep(c(-120.0, -119.9), 4),
                    main_habitat = "Marine", stringsAsFactors = FALSE)
  kp <- estimate_kernel_priors(occ, 34.15, -119.95, "Marine", lambda_km = 50)
  m <- plot_theta_surface(kp, occ, taxon = c("A", "B"), n_grid = 16L, interactive = TRUE)$plot
  calls <- vapply(m$x$calls, function(cl) cl$method, character(1))
  expect_true("addLegend" %in% calls)          # legend present
  expect_true("addCircleMarkers" %in% calls)   # small hollow site marker, not addMarkers
  expect_false("addMarkers" %in% calls)
  expect_true("addLayersControl" %in% calls)   # species selector
  # radio (baseGroups), not stacked overlays
  lc <- m$x$calls[[which(calls == "addLayersControl")[1]]]
  expect_setequal(unlist(lc$args[[1]]), c("A", "B"))
  # hover labels reached the rectangles
  rect <- m$x$calls[[which(calls == "addRectangles")[1]]]
  expect_true(any(grepl("theta =", unlist(rect$args), fixed = TRUE)))
})

test_that("printing the object renders the map, not just a summary (2026-09-01)", {
  occ <- data.frame(taxon_name = rep(c("A", "B"), each = 3),
                    decimalLatitude = rep(c(34.0, 34.1, 34.2), 2),
                    decimalLongitude = rep(c(-120.0, -119.9, -119.8), 2),
                    main_habitat = "Marine", stringsAsFactors = FALSE)
  kp <- estimate_kernel_priors(occ, 34.1, -119.9, "Marine", lambda_km = 50)
  # static path: base graphics draws at construction, so $plot is NULL and the
  # summary alone is correct behaviour
  s <- plot_theta_surface(kp, occ, taxon = "A", n_grid = 16L)
  expect_output(print(s), "taxaexpect_theta_surface")
  expect_invisible(print(s))

  # interactive path: the widget MUST be carried on the result and printed,
  # otherwise a console call shows only a summary while a stale earlier map
  # stays on screen -- the real 2026-09-01 confusion this guards against.
  skip_if_not_installed("leaflet")
  si <- plot_theta_surface(kp, occ, taxon = c("A", "B"), n_grid = 16L, interactive = TRUE)
  expect_false(is.null(si$plot))
  expect_s3_class(si$plot, "leaflet")
  expect_output(print(si), "taxaexpect_theta_surface")
})
