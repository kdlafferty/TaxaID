# test-assign_spatial_group.R
# Tests for assign_spatial_group(). Fully offline.

library(testthat)

sites <- data.frame(
  observation_id   = paste0("obs", 1:4),
  lat              = c(34.40, 34.41, 36.60, 40.71),
  lon              = c(-119.86, -119.85, -121.90, -74.00),
  spatial_group_id = paste0("obs", 1:4),
  spatial_group_N  = 1L,
  stringsAsFactors = FALSE
)

test_that("assigns spatial_group_id to the named observations", {
  out <- assign_spatial_group(sites, c("obs1", "obs2"), "spatial_group_1")
  expect_equal(out$spatial_group_id[out$observation_id %in% c("obs1", "obs2")],
               rep("spatial_group_1", 2))
  expect_equal(out$spatial_group_id[out$observation_id %in% c("obs3", "obs4")],
               c("obs3", "obs4"))
})

test_that("recomputes spatial_group_N to stay in sync", {
  out <- assign_spatial_group(sites, c("obs1", "obs2"), "spatial_group_1")
  expect_equal(out$spatial_group_N[out$observation_id %in% c("obs1", "obs2")], c(2L, 2L))
  expect_equal(out$spatial_group_N[out$observation_id == "obs3"], 1L)
})

test_that("can add a member to an already-formed group by including its existing members", {
  grouped <- assign_spatial_group(sites, c("obs1", "obs2"), "spatial_group_1")
  merged  <- assign_spatial_group(grouped, c("obs1", "obs2", "obs3"), "spatial_group_1")
  expect_equal(merged$spatial_group_N[merged$observation_id == "obs1"], 3L)
  expect_equal(merged$spatial_group_id[merged$observation_id == "obs3"], "spatial_group_1")
})

test_that("errors when the target spatial_group_id is already used by an unnamed observation", {
  grouped <- assign_spatial_group(sites, c("obs1", "obs2"), "spatial_group_1")
  expect_error(
    assign_spatial_group(grouped, "obs3", "spatial_group_1"),
    "already used by observation"
  )
})

test_that("errors on unknown observation_ids", {
  expect_error(assign_spatial_group(sites, "obs_nonexistent", "spatial_group_1"),
               "not found in 'sites'")
})

test_that("errors on missing spatial_group_id/spatial_group_N columns", {
  bad <- sites[, c("observation_id", "lat", "lon")]
  expect_error(assign_spatial_group(bad, "obs1", "spatial_group_1"),
               "Run build_site_table")
})

test_that("errors on empty or NA observation_ids", {
  expect_error(assign_spatial_group(sites, character(0), "spatial_group_1"), "non-empty vector")
  expect_error(assign_spatial_group(sites, NA_character_, "spatial_group_1"), "non-empty vector")
})

test_that("errors on invalid spatial_group_id", {
  expect_error(assign_spatial_group(sites, "obs1", ""), "non-empty string")
  expect_error(assign_spatial_group(sites, "obs1", NA_character_), "non-empty string")
  expect_error(assign_spatial_group(sites, "obs1", c("a", "b")), "single non-NA")
})

test_that("errors on empty sites", {
  expect_error(assign_spatial_group(sites[0, ], "obs1", "spatial_group_1"), "non-empty data frame")
})

test_that("clears is_default_group for manually assigned observations, when present", {
  sites_marked <- sites
  sites_marked$is_default_group <- TRUE
  out <- assign_spatial_group(sites_marked, c("obs1", "obs2"), "spatial_group_1")
  expect_false(any(out$is_default_group[out$observation_id %in% c("obs1", "obs2")]))
  expect_true(all(out$is_default_group[out$observation_id %in% c("obs3", "obs4")]))
})

test_that("does not error when is_default_group column is absent (backward compatible)", {
  out <- assign_spatial_group(sites, c("obs1", "obs2"), "spatial_group_1")
  expect_false("is_default_group" %in% names(out))
})
