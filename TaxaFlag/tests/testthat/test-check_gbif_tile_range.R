# test-check_gbif_tile_range.R
# Mocks .fetch_gbif_tile_alpha() (the network boundary) so tile math,
# stitching, distance, patch-growth, and zoom-escalation logic all run for
# real underneath -- same strategy as test-check_geographic_outliers.R
# (TaxaFetch), which mocks at the rgbif::occ_data layer and lets the rest of
# that function run live. Real end-to-end network verification against live
# GBIF tiles (round goby at Burns Harbor, two real European species that
# only resolve after escalating to zoom 3, a fabricated taxonKey exhausting
# to min_zoom = 0) was done manually during development -- see
# check_gbif_tile_range.R's own roxygen "Zoom escalation" section and
# .grow_patch_size()'s roxygen for the concrete numbers that motivated both
# designs.

library(testthat)

skip_if_not_installed("httr2")
skip_if_not_installed("png")

# Fixed query point + zoom used throughout -- Burns Harbor, matching the
# real GreatLakes2023_ConsensusWorkflow.R use case. Computed once so mocks
# can place presence pixels at known offsets from the query point.
.query_lat <- 41.67
.query_lon <- -87.15
.zoom      <- 6L
.tile_size <- 512L
.loc       <- .lonlat_to_tile_pixel(.query_lat, .query_lon, .zoom, .tile_size)

# All mocks below ignore taxon_key/base_url (irrelevant to the logic under
# test) and key behavior purely on which tile (zoom, x, y) is requested.

test_that("point_occupied = TRUE and dist = 0 when the query pixel itself is occupied, no escalation", {
  mock_fetch <- function(base_url, zoom, x, y, taxon_key, tile_size) {
    m <- matrix(0, tile_size, tile_size)
    if (zoom == .zoom && x == .loc$xtile && y == .loc$ytile) m[.loc$py + 1L, .loc$px + 1L] <- 1
    m
  }
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = mock_fetch)

  out <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom)
  expect_true(out$point_occupied)
  expect_equal(out$dist_nearest_occupied_km, 0)
  expect_false(out$beyond_buffer)
  expect_equal(out$patch_size_px, 1L)
  expect_false(out$patch_size_capped)
  expect_equal(out$zoom_used, .zoom)
  expect_false(out$escalated)
  # patch km conversions: 1-pixel patch -> area = res^2, diameter = res
  expect_equal(out$patch_area_km2, out$resolution_km_per_px^2)
  expect_equal(out$patch_diameter_km, out$resolution_km_per_px)
})

test_that("distance to a nearby-but-not-coincident occupied cell is computed correctly, no escalation", {
  d_row <- 5L; d_col <- 3L
  mock_fetch <- function(base_url, zoom, x, y, taxon_key, tile_size) {
    m <- matrix(0, tile_size, tile_size)
    if (zoom == .zoom && x == .loc$xtile && y == .loc$ytile) {
      m[.loc$py + 1L + d_row, .loc$px + 1L + d_col] <- 1
    }
    m
  }
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = mock_fetch)

  out <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom)
  expect_false(out$point_occupied)
  expect_false(out$beyond_buffer)
  expected_px_dist <- sqrt(d_row^2 + d_col^2)
  expect_equal(out$dist_nearest_occupied_km, expected_px_dist * out$resolution_km_per_px)
  expect_equal(out$patch_size_px, 1L)
  expect_false(out$escalated)
})

test_that("escalates to a coarser zoom when nothing is found at the requested zoom, and stops as soon as something is", {
  # Present ONLY at zoom 4, everywhere else empty -- forces escalation
  # through zoom 6 -> 5 -> 4, then stops (does not continue to 3/2/1/0).
  n_calls_by_zoom <- new.env()
  mock_fetch <- function(base_url, zoom, x, y, taxon_key, tile_size) {
    key <- as.character(zoom)
    n_calls_by_zoom[[key]] <- if (is.null(n_calls_by_zoom[[key]])) 1L else n_calls_by_zoom[[key]] + 1L
    m <- matrix(0, tile_size, tile_size)
    if (zoom == 4L) {
      loc4 <- .lonlat_to_tile_pixel(.query_lat, .query_lon, 4L, tile_size)
      if (x == loc4$xtile && y == loc4$ytile) m[loc4$py + 1L, loc4$px + 1L] <- 1
    }
    m
  }
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = mock_fetch)

  out <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom)
  expect_false(out$beyond_buffer)
  expect_equal(out$zoom_used, 4L)
  expect_true(out$escalated)
  expect_true(out$point_occupied)
  expect_equal(out$dist_nearest_occupied_km, 0)
  # zoom 6, 5, 4 each contribute tiles; zoom 3/2/1/0 must NOT have been called
  expect_setequal(ls(n_calls_by_zoom), c("6", "4", "5"))
})

test_that("no occurrences at any zoom down to min_zoom -> beyond_buffer, zoom_used NA, resolution still reported at the finest zoom", {
  mock_fetch <- function(base_url, zoom, x, y, taxon_key, tile_size) matrix(0, tile_size, tile_size)
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = mock_fetch)

  out <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = 2L, min_zoom = 0L)
  expect_true(out$beyond_buffer)
  expect_true(is.na(out$zoom_used))
  expect_true(is.na(out$dist_nearest_occupied_km))
  expect_true(is.na(out$patch_size_px))
  expect_true(is.na(out$patch_size_capped))
  expect_true(is.na(out$patch_area_km2))
  expect_true(is.na(out$patch_diameter_km))
  # resolution is still reported, computed at the originally requested (finest) zoom
  expect_equal(out$resolution_km_per_px, .mercator_resolution_km(.query_lat, 2L, .tile_size))
})

test_that("escalate = FALSE restores single-zoom behaviour: no widening, zoom_used == zoom_requested even when not found", {
  mock_fetch <- function(base_url, zoom, x, y, taxon_key, tile_size) matrix(0, tile_size, tile_size)
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = mock_fetch)

  out <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon,
                                zoom = .zoom, escalate = FALSE)
  expect_true(out$beyond_buffer)
  expect_equal(out$zoom_used, .zoom)
  expect_false(out$escalated)
  expect_equal(out$n_tiles_fetched, 9L)  # only ever tries the one requested zoom
})

test_that("HTTP 204 (GBIF's empty-tile response) is treated as zero occurrences, not an error", {
  testthat::local_mocked_bindings(
    req_perform = function(req) httr2::response(status_code = 204L),
    .package    = "httr2"
  )
  out <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon,
                                zoom = .zoom, escalate = FALSE)
  expect_true(out$beyond_buffer)
})

test_that("a patch large enough to hit the growth cap is reported as capped, size is a lower bound", {
  mock_fetch <- function(base_url, zoom, x, y, taxon_key, tile_size) {
    matrix(1, tile_size, tile_size)  # every cell in every tile occupied
  }
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = mock_fetch)

  out <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom)
  expect_true(out$point_occupied)
  expect_true(out$patch_size_capped)
  expect_gt(out$patch_size_px, 1L)  # a lower bound, but growth did proceed beyond the seed
  expect_gt(out$patch_area_km2, out$resolution_km_per_px^2)  # km conversion still tracks the (capped) pixel count
  expect_false(out$escalated)  # found immediately at the requested zoom, no need to widen
})

test_that("buffer_px is rounded up to whole tiles and n_tiles_fetched reflects it (single zoom)", {
  mock_fetch <- function(base_url, zoom, x, y, taxon_key, tile_size) matrix(0, tile_size, tile_size)
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = mock_fetch)

  out_default <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon,
                                        zoom = .zoom, buffer_px = 512L, escalate = FALSE)
  expect_equal(out_default$n_tiles_fetched, 9L)  # 3x3 block, tile_radius = 1

  out_small <- check_gbif_tile_range(taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon,
                                      zoom = .zoom, buffer_px = 100L, escalate = FALSE)
  expect_equal(out_small$n_tiles_fetched, 9L)  # rounds up to a full tile radius of 1
})

test_that("resolution_km_per_px decreases with latitude (Mercator distortion) and with zoom", {
  expect_lt(.mercator_resolution_km(60, 6L, 512L), .mercator_resolution_km(0, 6L, 512L))
  expect_lt(.mercator_resolution_km(0, 8L, 512L), .mercator_resolution_km(0, 6L, 512L))
})

test_that("tile pixel math lands within [0, tile_size) and matches a hand-computed case", {
  # zoom 0: the whole world is one 512x512 tile; (0, 0) lon/lat is dead centre.
  loc0 <- .lonlat_to_tile_pixel(0, 0, 0L, 512L)
  expect_equal(loc0$xtile, 0L)
  expect_equal(loc0$ytile, 0L)
  expect_equal(loc0$px, 256L)
  expect_equal(loc0$py, 256L)
})

test_that(".dilate8 grows a single seed to its full 3x3 neighbourhood in one step", {
  m <- matrix(FALSE, 5, 5)
  m[3, 3] <- TRUE
  grown <- .dilate8(m)
  expect_equal(sum(grown), 9L)
  expect_true(all(grown[2:4, 2:4]))
})

test_that("input validation catches malformed arguments before any network call", {
  expect_error(check_gbif_tile_range(NA, 41, -87), "non-NA")
  expect_error(check_gbif_tile_range(1, 999, -87), "Web Mercator")
  expect_error(check_gbif_tile_range(1, 41, NA), "non-NA")
  expect_error(check_gbif_tile_range(1, 41, -87, zoom = -1), "\\[0, 12\\]")
  expect_error(check_gbif_tile_range(1, 41, -87, buffer_px = 0), "positive")
  expect_error(check_gbif_tile_range(1, 41, -87, escalate = NA), "non-NA logical")
  expect_error(check_gbif_tile_range(1, 41, -87, zoom = 4L, min_zoom = 5L), "\\[0, zoom\\]")
  expect_error(check_gbif_tile_range(1, 41, -87, min_zoom = -1), "\\[0, zoom\\]")
})
