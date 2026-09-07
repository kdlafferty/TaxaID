# test-group_observations_by_bbox.R
# Tests for .assign_spatial_groups_from_polygons(), .bbox_center_radius(), and
# .review_drawn_groups()'s non-interactive no-ops -- the pure, non-Shiny logic
# behind group_observations_by_bbox(). The interactive wrapper itself (like
# TaxaTools::define_search_polygon()) requires a live gadget session and is
# not covered here.

library(testthat)

.site_defaults <- function(sites, id_col = "observation_id") {
  sites$spatial_group_id <- as.character(sites[[id_col]])
  sites$spatial_group_N <- 1L
  sites$is_default_group <- TRUE
  sites
}

# Local square-WKT builder (avoids an undeclared TaxaFetch test dependency;
# equivalent in shape to TaxaFetch::make_bbox_wkt()'s output).
.test_bbox_wkt <- function(lat, lon, radius_deg) {
  sprintf(
    "POLYGON ((%f %f, %f %f, %f %f, %f %f, %f %f))",
    lon - radius_deg, lat - radius_deg,
    lon + radius_deg, lat - radius_deg,
    lon + radius_deg, lat + radius_deg,
    lon - radius_deg, lat + radius_deg,
    lon - radius_deg, lat - radius_deg
  )
}

sites <- .site_defaults(data.frame(
  observation_id = paste0("obs", 1:6),
  lat = c(34.40, 34.41, 34.39, 36.60, 36.61, 40.71),
  lon = c(-119.86, -119.85, -119.87, -121.90, -121.89, -74.00),
  stringsAsFactors = FALSE
))

# Box tightly around obs1-3 (Santa Barbara-ish cluster)
box1 <- .test_bbox_wkt(lat = 34.40, lon = -119.86, radius_deg = 0.05)
# Box tightly around obs4-5 (Monterey-ish cluster)
box2 <- .test_bbox_wkt(lat = 36.605, lon = -121.895, radius_deg = 0.05)

# =============================================================================
# .assign_spatial_groups_from_polygons(): grouped observations
# =============================================================================

test_that("observations inside a drawn box get that box's spatial_group_id", {
  out <- .assign_spatial_groups_from_polygons(sites, c(box1, box2))
  expect_equal(
    out$spatial_group_id[out$observation_id %in% c("obs1", "obs2", "obs3")],
    rep("spatial_group_1", 3)
  )
  expect_equal(
    out$spatial_group_id[out$observation_id %in% c("obs4", "obs5")],
    rep("spatial_group_2", 2)
  )
  expect_equal(out$spatial_group_N[out$observation_id == "obs1"], 3L)
  expect_equal(out$spatial_group_N[out$observation_id == "obs4"], 2L)
})

test_that("observations outside every box keep their default singleton group, not dropped", {
  out <- .assign_spatial_groups_from_polygons(sites, c(box1, box2))
  expect_equal(nrow(out), nrow(sites)) # nothing dropped
  expect_equal(out$spatial_group_id[out$observation_id == "obs6"], "obs6")
  expect_equal(out$spatial_group_N[out$observation_id == "obs6"], 1L)
  expect_true(out$is_default_group[out$observation_id == "obs6"])
})

test_that("newly drawn groups never collide with pre-existing spatial_group_<n> default labels", {
  # Simulate build_site_table()'s own exact-match default already having
  # minted "spatial_group_1" for two unrelated, pre-grouped observations,
  # before any interactive drawing happens.
  pre_named <- sites
  pre_named$spatial_group_id[pre_named$observation_id %in% c("obs4", "obs5")] <- "spatial_group_1"
  pre_named$spatial_group_N[pre_named$observation_id %in% c("obs4", "obs5")] <- 2L
  pre_named$is_default_group[pre_named$observation_id %in% c("obs4", "obs5")] <- FALSE

  out <- .assign_spatial_groups_from_polygons(pre_named, box1) # captures obs1-3
  new_ids <- unique(out$spatial_group_id[out$observation_id %in% c("obs1", "obs2", "obs3")])
  expect_length(new_ids, 1L)
  expect_false(new_ids %in% "spatial_group_1") # would collide with obs4/obs5's group
  # obs4/obs5's pre-existing group is untouched
  expect_true(all(out$spatial_group_id[out$observation_id %in% c("obs4", "obs5")] == "spatial_group_1"))
})

test_that("observations captured by a drawn box get is_default_group = FALSE", {
  out <- .assign_spatial_groups_from_polygons(sites, c(box1, box2))
  expect_false(any(out$is_default_group[out$observation_id %in% c("obs1", "obs2", "obs3", "obs4", "obs5")]))
})

test_that("a message explains the outside-box reclassification", {
  expect_message(
    .assign_spatial_groups_from_polygons(sites, c(box1, box2)),
    "fell outside every drawn spatial"
  )
})

test_that("already-grouped observations are left untouched even if geometrically covered", {
  pre_grouped <- sites
  pre_grouped$spatial_group_id[pre_grouped$observation_id == "obs6"] <- "manual_group"
  pre_grouped$spatial_group_N[pre_grouped$observation_id == "obs6"] <- 1L
  pre_grouped$is_default_group[pre_grouped$observation_id == "obs6"] <- FALSE
  # A huge box that would geometrically cover obs6 too, were it still eligible
  huge_box <- .test_bbox_wkt(lat = 30, lon = -80, radius_deg = 40)
  out <- suppressMessages(.assign_spatial_groups_from_polygons(pre_grouped, c(huge_box)))
  expect_equal(out$spatial_group_id[out$observation_id == "obs6"], "manual_group")
})

# =============================================================================
# .assign_spatial_groups_from_polygons(): no boxes drawn at all
# =============================================================================

test_that("zero polygons -> every observation keeps its default singleton, none dropped", {
  out <- suppressMessages(.assign_spatial_groups_from_polygons(sites, character(0)))
  expect_equal(nrow(out), nrow(sites))
  expect_equal(out$spatial_group_id, sites$observation_id)
  expect_true(all(out$spatial_group_N == 1L))
})

test_that("a message explains the no-boxes-drawn case", {
  expect_message(
    .assign_spatial_groups_from_polygons(sites, character(0)),
    "no bounding-box groups were drawn"
  )
})

test_that("no message when a single drawn box captures every observation", {
  clustered <- .site_defaults(sites[1:3, ])
  expect_no_message(.assign_spatial_groups_from_polygons(clustered, box1))
})

test_that("a message explains there is nothing left when all observations are already grouped", {
  clustered <- sites
  clustered$spatial_group_id <- "already_grouped"
  clustered$spatial_group_N <- nrow(clustered)
  clustered$is_default_group <- FALSE
  expect_message(
    .assign_spatial_groups_from_polygons(clustered, box1),
    "nothing left to assign"
  )
})

# =============================================================================
# .assign_spatial_groups_from_polygons(): last-drawn-wins overlap rule
# =============================================================================

test_that("an observation inside two overlapping boxes gets the most recently drawn group", {
  overlap_sites <- .site_defaults(data.frame(
    observation_id = "obsA", lat = 34.40, lon = -119.86,
    stringsAsFactors = FALSE
  ))
  box_early <- .test_bbox_wkt(lat = 34.40, lon = -119.86, radius_deg = 0.5)
  box_late <- .test_bbox_wkt(lat = 34.40, lon = -119.86, radius_deg = 0.2)
  out <- suppressWarnings(.assign_spatial_groups_from_polygons(overlap_sites, c(box_early, box_late)))
  expect_equal(out$spatial_group_id, "spatial_group_2")
})

test_that("a warning names the ambiguous observation when boxes overlap", {
  overlap_sites <- .site_defaults(data.frame(
    observation_id = "obsA", lat = 34.40, lon = -119.86,
    stringsAsFactors = FALSE
  ))
  box_early <- .test_bbox_wkt(lat = 34.40, lon = -119.86, radius_deg = 0.5)
  box_late <- .test_bbox_wkt(lat = 34.40, lon = -119.86, radius_deg = 0.2)
  expect_warning(
    .assign_spatial_groups_from_polygons(overlap_sites, c(box_early, box_late)),
    "obsA"
  )
})

test_that("no warning when no observation falls inside more than one box", {
  expect_warning(.assign_spatial_groups_from_polygons(sites, c(box1, box2)), NA)
})

# =============================================================================
# .bbox_center_radius()
# =============================================================================

test_that("centres on the midpoint of the coordinate range", {
  out <- .bbox_center_radius(c(34.0, 36.0), c(-120.0, -118.0))
  expect_equal(out$lat, 35.0)
  expect_equal(out$lon, -119.0)
})

test_that("a single point still gets a positive, non-zero radius", {
  out <- .bbox_center_radius(34.4, -119.86)
  expect_gt(out$radius_deg, 0)
})

test_that("radius grows with a spread out set of points", {
  tight <- .bbox_center_radius(c(34.40, 34.41), c(-119.86, -119.85))
  wide <- .bbox_center_radius(c(34.0, 40.0), c(-121.0, -74.0))
  expect_gt(wide$radius_deg, tight$radius_deg)
})

test_that("the resulting square is guaranteed to fully enclose every input point", {
  lat <- c(34.0, 36.5, 40.71, 33.2)
  lon <- c(-119.86, -121.9, -74.0, -117.3)
  out <- .bbox_center_radius(lat, lon)
  expect_true(all(lat >= out$lat - out$radius_deg & lat <= out$lat + out$radius_deg))
  expect_true(all(lon >= out$lon - out$radius_deg & lon <= out$lon + out$radius_deg))
})

# =============================================================================
# .review_drawn_groups(): non-interactive / zero-polygon no-ops
# =============================================================================

test_that("returns polygons unchanged when zero polygons were drawn", {
  out <- .review_drawn_groups(character(0), sites, "observation_id", "lat", "lon", "Esri.OceanBasemap")
  expect_equal(out, character(0))
})

test_that("returns polygons unchanged in a non-interactive session", {
  # testthat runs non-interactively, so this exercises the real interactive() gate
  out <- .review_drawn_groups(c(box1, box2), sites, "observation_id", "lat", "lon", "Esri.OceanBasemap")
  expect_equal(out, c(box1, box2))
})

# =============================================================================
# group_observations_by_bbox(): input validation (no gadget needed)
# =============================================================================

test_that("errors on a non-interactive session before touching the gadget", {
  expect_error(group_observations_by_bbox(sites), "interactive R session")
})

test_that("errors on missing required columns", {
  bad <- data.frame(observation_id = "obs1")
  expect_error(group_observations_by_bbox(bad), "missing required column")
})

test_that("errors on NA coordinates", {
  bad <- sites
  bad$lat[1] <- NA
  expect_error(group_observations_by_bbox(bad), "NA coordinates")
})
