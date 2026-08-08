# test-compute_local_occurrence_distance.R
# Fully offline -- no network calls, pure arithmetic over a supplied
# occurrence_data frame.

library(testthat)

.make_occ <- function() {
  data.frame(
    taxon_name = c(
      "Neogobius melanostomus", "Neogobius melanostomus", "Neogobius melanostomus",
      "Salmo salar", "Missing Coords sp."
    ),
    decimalLatitude  = c(41.68, 41.60, 41.90, 41.50, NA),
    decimalLongitude = c(-87.14, -87.30, -86.80, -87.60, NA),
    stringsAsFactors = FALSE
  )
}

test_that("finds the nearest of several records for a present taxon", {
  occ <- .make_occ()
  out <- compute_local_occurrence_distance(
    taxon_names = "Neogobius melanostomus",
    query_lat = 41.67, query_lon = -87.15,
    occurrence_data = occ
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$n_local_records, 3L)
  # (41.68, -87.14) is the closest of the three real rows to (41.67, -87.15)
  expect_equal(out$nearest_lat, 41.68)
  expect_equal(out$nearest_lon, -87.14)
  expect_gt(out$dist_nearest_km, 0)
  expect_lt(out$dist_nearest_km, 5)  # sanity: sub-5km for a ~0.01 deg offset
})

test_that("a genuinely absent taxon returns zero records and NA distance", {
  occ <- .make_occ()
  out <- compute_local_occurrence_distance(
    taxon_names = "Truly Unprecedented sp.",
    query_lat = 41.67, query_lon = -87.15,
    occurrence_data = occ
  )
  expect_equal(out$n_local_records, 0L)
  expect_true(is.na(out$dist_nearest_km))
  expect_true(is.na(out$nearest_lat))
  expect_true(is.na(out$nearest_lon))
})

test_that("rows with missing coordinates are excluded, not counted", {
  occ <- .make_occ()
  out <- compute_local_occurrence_distance(
    taxon_names = "Missing Coords sp.",
    query_lat = 41.67, query_lon = -87.15,
    occurrence_data = occ
  )
  expect_equal(out$n_local_records, 0L)
})

test_that("handles multiple taxa in one call, one row each, order-independent", {
  occ <- .make_occ()
  out <- compute_local_occurrence_distance(
    taxon_names = c("Salmo salar", "Neogobius melanostomus", "Truly Unprecedented sp."),
    query_lat = 41.67, query_lon = -87.15,
    occurrence_data = occ
  )
  expect_equal(nrow(out), 3L)
  expect_setequal(out$taxon_name, c("Salmo salar", "Neogobius melanostomus", "Truly Unprecedented sp."))
  expect_equal(out$n_local_records[out$taxon_name == "Salmo salar"], 1L)
})

test_that("duplicate taxon_names collapse to one row", {
  occ <- .make_occ()
  out <- compute_local_occurrence_distance(
    taxon_names = c("Salmo salar", "Salmo salar"),
    query_lat = 41.67, query_lon = -87.15,
    occurrence_data = occ
  )
  expect_equal(nrow(out), 1L)
})

test_that("respects custom column names", {
  occ <- .make_occ()
  names(occ) <- c("sp", "lat", "lon")
  out <- compute_local_occurrence_distance(
    taxon_names = "Salmo salar",
    query_lat = 41.67, query_lon = -87.15,
    occurrence_data = occ,
    taxon_col = "sp", lat_col = "lat", lon_col = "lon"
  )
  expect_equal(out$n_local_records, 1L)
})

test_that("haversine distance is symmetric and zero at the same point", {
  expect_equal(.haversine_km(41.67, -87.15, 41.67, -87.15), 0)
  d1 <- .haversine_km(41.67, -87.15, 40.00, -83.00)
  d2 <- .haversine_km(40.00, -83.00, 41.67, -87.15)
  expect_equal(d1, d2)
  expect_gt(d1, 300)  # Burns Harbor to central Ohio is genuinely several hundred km
  expect_lt(d1, 600)
})

test_that("input validation catches malformed arguments", {
  occ <- .make_occ()
  expect_error(compute_local_occurrence_distance(character(0), 41, -87, occ), "non-empty")
  expect_error(compute_local_occurrence_distance("x", NA, -87, occ), "non-NA")
  expect_error(compute_local_occurrence_distance("x", 41, -87, list()), "data frame")
  expect_error(
    compute_local_occurrence_distance("x", 41, -87, occ, taxon_col = "nope"),
    "missing columns"
  )
})
