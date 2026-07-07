# test-build_site_table.R
# Tests for build_site_table(). Fully offline -- synthetic data frames only.

library(testthat)

# =============================================================================
# Image pathway: embedded lat/lng extracted directly
# =============================================================================

test_that("embedded lat/lng is extracted and lng renamed to lon", {
  img <- data.frame(
    observation_id = c("IMG_001", "IMG_001", "IMG_002"),
    taxon_name = c("Lynx rufus", "Canis latrans", "Procyon lotor"),
    lat = c(34.41, 34.41, 34.40), lng = c(-119.86, -119.86, -119.85),
    observed_on = c("2024-06-01", "2024-06-01", "2024-06-02"),
    stringsAsFactors = FALSE
  )
  out <- build_site_table(img)
  expect_true(all(c("observation_id", "lat", "lon", "observed_on") %in% names(out)))
  expect_false("lng" %in% names(out))
  expect_equal(nrow(out), 2L)  # one row per observation, not per candidate row
})

test_that("observed_on defaults to NA when absent from an embedded match_df", {
  img <- data.frame(observation_id = "IMG_001", lat = 34.41, lng = -119.86)
  out <- build_site_table(img)
  expect_true(is.na(out$observed_on))
})

test_that("supplying site_df alongside embedded lat/lng warns and is ignored", {
  img <- data.frame(observation_id = "IMG_001", lat = 34.41, lng = -119.86)
  bogus_site_df <- data.frame(observation_id = "IMG_001", lat = 0, lon = 0)
  expect_warning(
    out <- build_site_table(img, site_df = bogus_site_df),
    "ignoring supplied"
  )
  expect_equal(out$lat, 34.41)
})

# =============================================================================
# DNA/acoustic pathway: external site_df required, multi-site supported
# =============================================================================

test_that("errors informatively when no embedded site info and no site_df supplied", {
  asv <- data.frame(observation_id = c("ASV1", "ASV2"))
  expect_error(build_site_table(asv), "no embedded site info")
})

test_that("external site_df is joined for a pathway lacking embedded site info", {
  asv <- data.frame(observation_id = c("ASV1", "ASV2"))
  site_info <- data.frame(
    observation_id = c("ASV1", "ASV2"),
    lat = c(34.41, 36.60), lon = c(-119.86, -121.90)
  )
  out <- build_site_table(asv, site_df = site_info)
  expect_equal(nrow(out), 2L)
  expect_equal(out$lat, c(34.41, 36.60))
})

test_that("an ASV detected at multiple sites yields multiple rows (not collapsed)", {
  asv <- data.frame(observation_id = c("ASV1", "ASV2"))
  site_info <- data.frame(
    observation_id = c("ASV1", "ASV1", "ASV2"),
    lat = c(34.41, 36.60, 34.41), lon = c(-119.86, -121.90, -119.86)
  )
  out <- build_site_table(asv, site_df = site_info)
  expect_equal(nrow(out), 3L)
  expect_equal(sum(out$observation_id == "ASV1"), 2L)
})

test_that("warns (but does not error) when some observations have no site_df match", {
  asv <- data.frame(observation_id = c("ASV1", "ASV2"))
  site_info <- data.frame(observation_id = "ASV1", lat = 34.41, lon = -119.86)
  expect_warning(
    out <- build_site_table(asv, site_df = site_info),
    "no matching row"
  )
  expect_equal(nrow(out), 1L)
})

test_that("site_df missing required columns errors", {
  asv <- data.frame(observation_id = "ASV1")
  bad_site_df <- data.frame(observation_id = "ASV1", lat = 34.41)  # no lon
  expect_error(build_site_table(asv, site_df = bad_site_df), "missing required column")
})

# =============================================================================
# spatial_group_id / spatial_group_N / is_default_group defaults (Session 139)
# =============================================================================
# spatial_group_id defaults to an exact-(lat,lon)-match label, not
# observation_id (Session 139 fix) -- spatial_group_id is a LOCATION
# property, so two observations at different coordinates should default to
# different groups, and two observations sharing the EXACT SAME coordinate
# (even with different observation_id) should default to the SAME group. No
# distance tolerance/bin size -- see build_site_table()'s own Details for why
# a grid-snapping design was tried and rejected. is_default_group is TRUE
# until a grouping step reassigns it.

test_that("embedded pathway: differently-located observations get different default groups", {
  img <- data.frame(observation_id = c("IMG_001", "IMG_002"),
                    lat = c(34.41, 40.71), lng = c(-119.86, -74.00))
  out <- build_site_table(img)
  expect_true(all(grepl("^spatial_group_", out$spatial_group_id)))
  expect_equal(length(unique(out$spatial_group_id)), 2L)
  expect_equal(out$spatial_group_N, c(1L, 1L))
  expect_true(all(out$is_default_group))
})

test_that("embedded pathway: co-located observations (different observation_id, exact same coordinate) share a default group", {
  img <- data.frame(observation_id = c("IMG_001", "IMG_002"),
                    lat = c(34.41, 34.41), lng = c(-119.86, -119.86))
  out <- build_site_table(img)
  expect_equal(length(unique(out$spatial_group_id)), 1L)
  expect_equal(out$spatial_group_N, c(2L, 2L))
})

test_that("embedded pathway: nearby but non-identical coordinates do NOT share a default group", {
  img <- data.frame(observation_id = c("IMG_001", "IMG_002"),
                    lat = c(34.410, 34.411), lng = c(-119.860, -119.860))
  out <- build_site_table(img)
  expect_equal(length(unique(out$spatial_group_id)), 2L)
})

test_that("site_df pathway: differently-located observations get different default groups", {
  asv <- data.frame(observation_id = c("ASV1", "ASV2"))
  site_info <- data.frame(
    observation_id = c("ASV1", "ASV2"),
    lat = c(34.41, 36.60), lon = c(-119.86, -121.90)
  )
  out <- build_site_table(asv, site_df = site_info)
  expect_equal(length(unique(out$spatial_group_id)), 2L)
  expect_equal(out$spatial_group_N, c(1L, 1L))
  expect_true(all(out$is_default_group))
})

test_that("site_df pathway: two different observations sharing an exact site coordinate default to one group", {
  asv <- data.frame(observation_id = c("ASV1", "ASV2", "ASV3"))
  site_info <- data.frame(
    observation_id = c("ASV1", "ASV2", "ASV3"),
    lat = c(34.40, 34.40, 36.60), lon = c(-120.41, -120.41, -121.90)
  )
  out <- build_site_table(asv, site_df = site_info)
  expect_equal(length(unique(out$spatial_group_id)), 2L)
  expect_equal(out$spatial_group_N[out$observation_id %in% c("ASV1", "ASV2")], c(2L, 2L))
  expect_equal(out$spatial_group_N[out$observation_id == "ASV3"], 1L)
})

test_that("a multi-site observation's own differently-located sites default to different groups", {
  asv <- data.frame(observation_id = "ASV1")
  site_info <- data.frame(
    observation_id = c("ASV1", "ASV1"),
    lat = c(34.41, 40.71), lon = c(-119.86, -74.00)
  )
  out <- build_site_table(asv, site_df = site_info)
  expect_equal(nrow(out), 2L)
  expect_equal(length(unique(out$spatial_group_id)), 2L)
  expect_equal(out$spatial_group_N, c(1L, 1L))
})

# =============================================================================
# .next_spatial_group_number() (Session 139)
# =============================================================================

test_that(".next_spatial_group_number() returns 1 when no spatial_group_<n> ids exist", {
  expect_equal(.next_spatial_group_number(character(0)), 1L)
  expect_equal(.next_spatial_group_number(c("ASV1", "IMG_002")), 1L)
})

test_that(".next_spatial_group_number() continues past the highest existing number", {
  expect_equal(.next_spatial_group_number(c("spatial_group_1", "spatial_group_3")), 4L)
  expect_equal(.next_spatial_group_number(c("spatial_group_1", "spatial_group_1", "obs1")), 2L)
})

# =============================================================================
# Input validation
# =============================================================================

test_that("errors on empty match_df", {
  expect_error(build_site_table(data.frame(observation_id = character(0))),
               "non-empty data frame")
})

test_that("errors when match_df lacks the id column", {
  expect_error(build_site_table(data.frame(x = 1)), "missing id column")
})
