# test-define_search_polygon.R
# Tests for the pure WKT helpers behind define_search_polygon() -- .pts_to_wkt()
# and .wkt_to_pts(). The gadget itself requires a live interactive session and
# is not covered here (same testing boundary the ecosystem already uses for
# other Shiny-gated functions).

library(testthat)

test_that(".pts_to_wkt() closes the ring and orders coordinates lng-lat", {
  wkt <- .pts_to_wkt(lng = c(-120, -119, -119, -120), lat = c(34, 34, 35, 35))
  expect_match(wkt, "^POLYGON \\(\\(.*\\)\\)$")
  expect_match(wkt, "-120\\.000000 34\\.000000")
})

test_that(".pts_to_wkt() repeats the first vertex to close the ring", {
  wkt <- .pts_to_wkt(lng = c(-120, -119, -119.5), lat = c(34, 34, 35))
  coords <- strsplit(sub("^POLYGON \\(\\((.*)\\)\\)$", "\\1", wkt), ", ")[[1]]
  expect_equal(coords[1], coords[length(coords)])
})

test_that(".wkt_to_pts() round-trips .pts_to_wkt() output, dropping the closing vertex", {
  lng <- c(-120, -119, -119, -120)
  lat <- c(34, 34, 35, 35)
  wkt <- .pts_to_wkt(lng, lat)
  parsed <- .wkt_to_pts(wkt)
  expect_equal(parsed$lng, lng, tolerance = 1e-6)
  expect_equal(parsed$lat, lat, tolerance = 1e-6)
})

test_that(".wkt_to_pts() handles a triangle (minimum valid polygon)", {
  wkt <- .pts_to_wkt(lng = c(-120, -119, -119.5), lat = c(34, 34, 35))
  parsed <- .wkt_to_pts(wkt)
  expect_length(parsed$lng, 3L)
  expect_length(parsed$lat, 3L)
})

test_that(".wkt_to_pts() is case-insensitive on the POLYGON keyword", {
  wkt <- "polygon ((-120.000000 34.000000, -119.000000 34.000000, -119.500000 35.000000, -120.000000 34.000000))"
  parsed <- .wkt_to_pts(wkt)
  expect_length(parsed$lng, 3L)
})
