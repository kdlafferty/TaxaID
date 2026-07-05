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
# spatial_group_id / spatial_group_N defaults (Session 134b)
# =============================================================================

test_that("embedded pathway: spatial_group_id defaults to observation_id, spatial_group_N to 1", {
  img <- data.frame(observation_id = c("IMG_001", "IMG_002"),
                    lat = c(34.41, 34.40), lng = c(-119.86, -119.85))
  out <- build_site_table(img)
  expect_equal(out$spatial_group_id, out$observation_id)
  expect_equal(out$spatial_group_N, c(1L, 1L))
})

test_that("site_df pathway: spatial_group_id defaults to observation_id, spatial_group_N to 1", {
  asv <- data.frame(observation_id = c("ASV1", "ASV2"))
  site_info <- data.frame(
    observation_id = c("ASV1", "ASV2"),
    lat = c(34.41, 36.60), lon = c(-119.86, -121.90)
  )
  out <- build_site_table(asv, site_df = site_info)
  expect_equal(out$spatial_group_id, out$observation_id)
  expect_equal(out$spatial_group_N, c(1L, 1L))
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
