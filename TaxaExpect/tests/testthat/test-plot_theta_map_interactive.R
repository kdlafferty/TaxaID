# Tests for the pure internal helpers behind plot_theta_map_interactive().
# The gadget itself requires a live interactive Shiny session and is outside
# this file's testing boundary (matches the established convention elsewhere
# in this ecosystem, e.g. TaxaTools::define_search_polygon()'s
# .pts_to_wkt()/.wkt_to_pts() -- tested without a live gadget session).

test_that(".parse_grid_id_coords parses a well-formed grid_id", {
  out <- TaxaExpect:::.parse_grid_id_coords("Grid_33p1_m118p5")
  expect_equal(out$lat, 33.1)
  expect_equal(out$lon, -118.5)
})

test_that(".parse_grid_id_coords handles positive lon and multi-digit values", {
  out <- TaxaExpect:::.parse_grid_id_coords("Grid_34p0_119p0")
  expect_equal(out$lat, 34.0)
  expect_equal(out$lon, 119.0)
})

test_that(".parse_grid_id_coords is vectorised and preserves length/order", {
  ids <- c("Grid_33p1_m118p5", "Grid_34p0_119p0", "Grid_0p0_0p0")
  out <- TaxaExpect:::.parse_grid_id_coords(ids)
  expect_equal(nrow(out), 3L)
  expect_equal(out$lat, c(33.1, 34.0, 0.0))
  expect_equal(out$lon, c(-118.5, 119.0, 0.0))
})

test_that(".parse_grid_id_coords returns NA (not dropped) for malformed/NA input", {
  ids <- c("Grid_33p1_m118p5", NA_character_, "not_a_grid_id")
  out <- TaxaExpect:::.parse_grid_id_coords(ids)
  expect_equal(nrow(out), 3L)
  expect_equal(out$lat[1], 33.1)
  expect_true(is.na(out$lat[2]))
})

test_that(".truncate_label leaves short strings unchanged", {
  expect_equal(TaxaExpect:::.truncate_label("short", 20L), "short")
})

test_that(".truncate_label truncates long strings with an ellipsis", {
  out <- TaxaExpect:::.truncate_label("a_very_long_taxon_name_indeed", 10L)
  expect_equal(nchar(out), 10L)
  expect_true(endsWith(out, "\u2026"))
})
