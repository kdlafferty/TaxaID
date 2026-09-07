# test-join_event_site_metadata.R
# Tests for join_event_site_metadata(). Fully offline.

library(testthat)

.detections <- data.frame(
  observation_id = c("ASV1", "ASV1", "ASV2", "ASV3"),
  event_id = c("site_A", "site_B", "site_A", "blank_1"),
  stringsAsFactors = FALSE
)

.site_metadata <- data.frame(
  event_id = c("site_A", "site_B", "blank_1"),
  lat = c(34.41, 36.60, NA),
  lon = c(-119.86, -121.90, NA),
  observed_on = c("2026-03-14", "2026-03-15", "2026-03-14"),
  stringsAsFactors = FALSE
)

# =============================================================================
# Input validation
# =============================================================================

test_that("stops if detections is not a non-empty data frame", {
  expect_error(join_event_site_metadata(data.frame(), .site_metadata), regexp = "non-empty")
  expect_error(join_event_site_metadata("x", .site_metadata), regexp = "non-empty")
})

test_that("stops if site_metadata is not a non-empty data frame", {
  expect_error(join_event_site_metadata(.detections, data.frame()), regexp = "non-empty")
})

test_that("stops if detections missing id_col or event_col", {
  expect_error(
    join_event_site_metadata(data.frame(event_id = "site_A"), .site_metadata),
    regexp = "missing column"
  )
})

test_that("stops if site_metadata missing lat/lon columns", {
  bad_meta <- data.frame(event_id = "site_A", lat = 34.41)
  expect_error(join_event_site_metadata(.detections, bad_meta), regexp = "missing column")
})

test_that("stops if observed_on_col is specified but absent", {
  bad_meta <- data.frame(event_id = "site_A", lat = 34.41, lon = -119.86)
  expect_error(
    join_event_site_metadata(.detections, bad_meta, observed_on_col = "observed_on"),
    regexp = "observed_on_col"
  )
})

# =============================================================================
# Core join behavior
# =============================================================================

test_that("joins detections to site metadata correctly", {
  out <- suppressWarnings(join_event_site_metadata(.detections, .site_metadata))
  expect_equal(nrow(out), 4L)
  expect_equal(out$lat[out$observation_id == "ASV1" & out$event_id == "site_A"], 34.41)
  expect_equal(out$lat[out$observation_id == "ASV1" & out$event_id == "site_B"], 36.60)
})

test_that("output has canonical lat/lon/observed_on column names", {
  out <- suppressWarnings(join_event_site_metadata(.detections, .site_metadata))
  expect_true(all(c("observation_id", "lat", "lon", "observed_on", "event_id") %in% names(out)))
})

test_that("supports custom lat_col/lon_col/observed_on_col names", {
  custom_meta <- data.frame(
    event_id = c("site_A", "site_B"),
    latitude = c(34.41, 36.60),
    longitude = c(-119.86, -121.90),
    collected = c("2026-03-14", "2026-03-15"),
    stringsAsFactors = FALSE
  )
  out <- join_event_site_metadata(
    .detections[.detections$event_id != "blank_1", ],
    custom_meta,
    lat_col = "latitude", lon_col = "longitude", observed_on_col = "collected"
  )
  expect_equal(out$lat[out$event_id == "site_A"][1], 34.41)
  expect_equal(out$observed_on[out$event_id == "site_A"][1], "2026-03-14")
})

test_that("observed_on_col = NULL fills observed_on with NA", {
  meta_no_date <- data.frame(
    event_id = c("site_A", "site_B"),
    lat = c(34.41, 36.60), lon = c(-119.86, -121.90)
  )
  out <- join_event_site_metadata(
    .detections[.detections$event_id != "blank_1", ],
    meta_no_date,
    observed_on_col = NULL
  )
  expect_true(all(is.na(out$observed_on)))
})

test_that("preserves multiple rows per observation_id (multi-site ASV)", {
  out <- suppressWarnings(join_event_site_metadata(.detections, .site_metadata))
  expect_equal(sum(out$observation_id == "ASV1"), 2L)
})

# =============================================================================
# control_samples exclusion
# =============================================================================

test_that("control_samples excludes matching event rows before joining", {
  expect_message(
    out <- join_event_site_metadata(.detections, .site_metadata, control_samples = "blank_1"),
    regexp = "excluded 1 control"
  )
  expect_false("blank_1" %in% out$event_id)
  expect_equal(nrow(out), 3L)
})

test_that("stops when control_samples excludes every row", {
  expect_error(
    suppressMessages(join_event_site_metadata(
      .detections, .site_metadata,
      control_samples = unique(.detections$event_id)
    )),
    regexp = "nothing left to join"
  )
})

# =============================================================================
# Unmatched events
# =============================================================================

test_that("warns and returns NA lat/lon for events missing from site_metadata", {
  meta_incomplete <- .site_metadata[.site_metadata$event_id != "site_B", ]
  expect_warning(
    out <- join_event_site_metadata(.detections, meta_incomplete, control_samples = "blank_1"),
    regexp = "site_B"
  )
  expect_true(is.na(out$lat[out$event_id == "site_B"]))
})
