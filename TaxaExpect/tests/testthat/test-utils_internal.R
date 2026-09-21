# Tests for .approx_distance_km() (2026-09-21) -- the shared
# equirectangular-approximation helper that replaced four separate inline
# copies of `111 * sqrt(dlat^2 + (dlon * cos(lat))^2)` in
# estimate_kernel_priors.R, calibrate_kernel_bandwidth.R, plot_theta_surface.R
# and generate_uncertain_habitat_evidence.R, none of which wrapped longitude
# at the antimeridian. Reproduced: a site at lon 179.9 with records at
# lon -179.9 (~22 km away in reality) read as ~40,000 km away under the old
# naive `lon1 - lon2`, so theta_mean for those records collapsed to ~1.1e-33
# while records ~2,000 km away (at a mid-longitude, no wrap involved) read as
# theta_mean 1.0; at a small enough lambda_km every weight in the call
# underflowed to exactly zero ("All kernel weights are zero").

# The formula every call site used to compute inline, kept here ONLY as the
# "old behaviour" reference for the equivalence test below -- this is
# deliberately NOT wrapped, so it reproduces the bug the fix removes.
.old_naive_km <- function(la1, lo1, la2, lo2, ref_lat) {
  111 * sqrt((la1 - la2)^2 + ((lo1 - lo2) * cos(ref_lat * pi / 180))^2)
}

test_that(".approx_distance_km() matches the old naive formula away from the antimeridian", {
  # Mid-longitude fixtures shaped like the package's real sites: PtConception
  # (~34 N, -120 W) and GreatLakes (~44 N, -85 W). No pair here is anywhere
  # near +/-180, so the wrap is a no-op and old/new must agree exactly.
  set.seed(1)
  la1 <- 34 + stats::runif(20, -2, 2)
  lo1 <- -120 + stats::runif(20, -3, 3)
  la2 <- 44 + stats::runif(20, -2, 2)
  lo2 <- -85 + stats::runif(20, -3, 3)
  ref_lat <- (la1 + la2) / 2

  old <- .old_naive_km(la1, lo1, la2, lo2, ref_lat)
  new <- TaxaExpect:::.approx_distance_km(la1, lo1, la2, lo2, ref_lat)
  expect_equal(new, old, tolerance = 1e-9)
})

test_that(".approx_distance_km() is a no-op change for a single mid-longitude pair (scalar case)", {
  expect_equal(
    TaxaExpect:::.approx_distance_km(34, -120, 34.5, -119, 34.25),
    .old_naive_km(34, -120, 34.5, -119, 34.25),
    tolerance = 1e-9
  )
})

test_that(".approx_distance_km() wraps the antimeridian instead of measuring the long way around", {
  # lon 179.9 to lon -179.9 is ~0.2 deg of longitude the short way (~22 km at
  # the equator), not ~359.8 deg the long way (~40,000 km).
  d <- TaxaExpect:::.approx_distance_km(0, 179.9, 0, -179.9, 0)
  expect_lt(d, 50)
  # The naive (unwrapped) formula gets this catastrophically wrong, which is
  # exactly the bug being fixed -- pinned here so a future edit that removes
  # the wrap is caught immediately, not just at the end-to-end level below.
  naive <- .old_naive_km(0, 179.9, 0, -179.9, 0)
  expect_gt(naive, 39000)
})

test_that(paste0(
  ".approx_distance_km() gives the same (small) answer regardless of which ",
  "side of the antimeridian each point is measured from"
), {
  d1 <- TaxaExpect:::.approx_distance_km(10, 179.9, 10, -179.9, 10)
  d2 <- TaxaExpect:::.approx_distance_km(10, -179.9, 10, 179.9, 10)
  expect_equal(d1, d2, tolerance = 1e-9)
  expect_lt(d1, 50)
})

# ---- end-to-end: estimate_kernel_priors() at the antimeridian --------------

.mk_occ_lonlat <- function(taxa, lat, lon, habitat = "Marine") {
  data.frame(
    taxon_name = taxa, decimalLatitude = lat, decimalLongitude = lon,
    main_habitat = habitat, stringsAsFactors = FALSE
  )
}

test_that(paste0(
  "estimate_kernel_priors() at a site on the antimeridian: the truly-nearby ",
  "records (other side of the dateline) dominate, not the far ones"
), {
  # Site at lon 179.9. "A" records sit just across the dateline at -179.9
  # (~22 km away in reality). "B" records sit at +170 (~1,100 km away, no
  # wrap involved). Under the pre-fix naive formula, A's distance would
  # compute as ~40,000 km (it wrapped the WRONG way) while B's ~1,100 km
  # would look close by comparison -- exactly backwards from reality.
  occ <- .mk_occ_lonlat(
    taxa = c("A", "A", "A", "B", "B", "B"),
    lat = rep(0, 6),
    lon = c(-179.9, -179.9, -179.9, 170, 170, 170)
  )
  kp <- estimate_kernel_priors(occ, site_lat = 0, site_lon = 179.9,
    site_habitat = "Marine", lambda_km = 500, m = 0
  )
  th <- kp$priors$theta_mean[match(c("A", "B"), kp$priors$taxon_name)]
  expect_gt(th[1], th[2])
  # A is genuinely close (~22 km, weight ~exp(-22/500) ~ 0.96) and clearly
  # dominates B (~1,100 km, weight ~exp(-1100/500) ~ 0.11) -- not underflowed
  # to ~0 the way the antimeridian bug produced.
  expect_gt(th[1], 0.85)
})
