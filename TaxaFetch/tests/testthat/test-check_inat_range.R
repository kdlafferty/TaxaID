# test-check_inat_range.R
# Tests for check_inat_range() and its internal helpers.
#
# Strategy:
#   - Input validation: no HTTP calls needed.
#   - check_inat_range() outcomes: mock the three internal helpers
#     (.inat_taxon_id, .inat_range_polygon, .point_in_inat_range).
#   - .inat_taxon_id: mock httr::GET / httr::status_code / httr::content.
#   - .inat_range_polygon: mock httr functions; caching uses real filesystem.
#   - .point_in_inat_range: real sf polygon (skip if sf unavailable).

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

# Minimal parsed taxa API response (mimics httr::content(as = "parsed"))
.taxa_resp <- function(id = 3855L, name = "Calidris mauri", rank = "species",
                       iconic = "Aves", n_obs = 21169L) {
  list(results = list(list(
    id                 = id,
    name               = name,
    rank               = rank,
    iconic_taxon_name  = iconic,
    observations_count = n_obs
  )))
}

# Minimal GeoJSON square: covers lng 0-1, lat 0-1
.square_geojson <- paste0(
  '{"type":"FeatureCollection","features":[{"type":"Feature",',
  '"geometry":{"type":"Polygon","coordinates":[[[0,0],[1,0],[1,1],[0,1],[0,0]]]}',
  ',"properties":{}}]}'
)

# Minimal httr-style mock response (status only; content mocked separately)
.resp <- function(status) structure(list(status_code = status), class = "response")

# Shared no-result taxon info (returned by .inat_taxon_id when taxon not found)
.not_found <- list(
  taxon_id = NA_integer_, matched_name = NA_character_,
  rank = NA_character_, iconic_taxon_name = NA_character_,
  n_observations = NA_integer_
)

# Shared found taxon info
.found <- list(
  taxon_id = 3855L, matched_name = "Calidris mauri",
  rank = "species", iconic_taxon_name = "Aves",
  n_observations = 21169L
)

# =============================================================================
# Input validation
# =============================================================================

test_that("stops when api_token is empty string", {
  expect_error(
    check_inat_range("Calidris mauri", lat = 34.1, lng = -119.1, api_token = ""),
    regexp = "INAT_API_TOKEN"
  )
})

test_that("stops when lat is non-numeric", {
  expect_error(
    check_inat_range("Calidris mauri", lat = "34.1", lng = -119.1, api_token = "tok"),
    regexp = "lat"
  )
})

test_that("stops when lng is non-numeric", {
  expect_error(
    check_inat_range("Calidris mauri", lat = 34.1, lng = "-119.1", api_token = "tok"),
    regexp = "lng"
  )
})

test_that("stops when lat is NA", {
  expect_error(
    check_inat_range("Calidris mauri", lat = NA_real_, lng = -119.1, api_token = "tok"),
    regexp = "lat"
  )
})

test_that("stops when lat has length > 1", {
  expect_error(
    check_inat_range("Calidris mauri", lat = c(34.1, 35.0), lng = -119.1, api_token = "tok"),
    regexp = "lat"
  )
})

test_that("stops when lng is NA", {
  expect_error(
    check_inat_range("Calidris mauri", lat = 34.1, lng = NA_real_, api_token = "tok"),
    regexp = "lng"
  )
})

# =============================================================================
# Output structure
# =============================================================================

test_that("returns a tibble with the correct eight columns", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .not_found,
    .package = "TaxaFetch"
  )
  out <- check_inat_range("Unknown taxon", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_s3_class(out, "tbl_df")
  expect_named(out, c("taxon_name", "taxon_id", "matched_name", "rank",
                      "iconic_taxon_name", "n_observations", "in_range", "range_status"))
})

test_that("returns one row per input taxon name", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .not_found,
    .package = "TaxaFetch"
  )
  out <- check_inat_range(c("Foo bar", "Baz qux", "Quux quuz"),
                          lat = 34.1, lng = -119.1, api_token = "tok")
  expect_equal(nrow(out), 3L)
  expect_equal(out$taxon_name, c("Foo bar", "Baz qux", "Quux quuz"))
})

# =============================================================================
# range_status outcomes
# =============================================================================

test_that("taxon_not_found: correct status and all-NA metadata", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .not_found,
    .package = "TaxaFetch"
  )
  out <- check_inat_range("Definitely notaspecies", lat = 34.1, lng = -119.1,
                          api_token = "tok")
  expect_equal(out$range_status, "taxon_not_found")
  expect_true(is.na(out$in_range))
  expect_true(is.na(out$taxon_id))
  expect_true(is.na(out$matched_name))
  expect_true(is.na(out$n_observations))
})

test_that("no_polygon: correct status, in_range NA, metadata preserved", {
  local_mocked_bindings(
    .inat_taxon_id     = function(...) .found,
    .inat_range_polygon = function(...) NULL,
    .package = "TaxaFetch"
  )
  out <- check_inat_range("Calidris mauri", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_equal(out$range_status, "no_polygon")
  expect_true(is.na(out$in_range))
  expect_equal(out$taxon_id, 3855L)
  expect_equal(out$matched_name, "Calidris mauri")
  expect_equal(out$iconic_taxon_name, "Aves")
  expect_equal(out$n_observations, 21169L)
})

test_that("in_range: in_range TRUE and range_status correct", {
  local_mocked_bindings(
    .inat_taxon_id      = function(...) .found,
    .inat_range_polygon  = function(...) "sentinel",
    .point_in_inat_range = function(...) TRUE,
    .package = "TaxaFetch"
  )
  out <- check_inat_range("Calidris mauri", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_true(out$in_range)
  expect_equal(out$range_status, "in_range")
})

test_that("out_of_range: in_range FALSE and range_status correct", {
  local_mocked_bindings(
    .inat_taxon_id      = function(...) .found,
    .inat_range_polygon  = function(...) "sentinel",
    .point_in_inat_range = function(...) FALSE,
    .package = "TaxaFetch"
  )
  out <- check_inat_range("Calidris mauri", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_false(out$in_range)
  expect_equal(out$range_status, "out_of_range")
})

test_that("mixed taxon list produces correct per-row outcomes", {
  call_count <- 0L
  taxon_info <- list(
    list(taxon_id = 1L, matched_name = "Taxon a", rank = "species",
         iconic_taxon_name = "Aves", n_observations = 100L),
    .not_found,
    list(taxon_id = 2L, matched_name = "Taxon c", rank = "species",
         iconic_taxon_name = "Plantae", n_observations = 50L)
  )
  local_mocked_bindings(
    .inat_taxon_id = function(...) {
      call_count <<- call_count + 1L
      taxon_info[[call_count]]
    },
    .inat_range_polygon  = function(...) "sentinel",
    .point_in_inat_range = function(...) TRUE,
    .package = "TaxaFetch"
  )
  out <- check_inat_range(c("Taxon a", "Unknown", "Taxon c"),
                          lat = 0, lng = 0, api_token = "tok")
  expect_equal(nrow(out), 3L)
  expect_equal(out$range_status, c("in_range", "taxon_not_found", "in_range"))
})

test_that("verbose emits progress messages", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .not_found,
    .package = "TaxaFetch"
  )
  expect_message(
    check_inat_range(c("Foo bar", "Baz qux"), lat = 0, lng = 0,
                     api_token = "tok", verbose = TRUE),
    regexp = "\\[1/2\\]"
  )
  expect_message(
    check_inat_range(c("Foo bar", "Baz qux"), lat = 0, lng = 0,
                     api_token = "tok", verbose = TRUE),
    regexp = "\\[2/2\\]"
  )
})

# =============================================================================
# .inat_taxon_id helper
# =============================================================================

test_that(".inat_taxon_id: returns NAs when HTTP status is not 200", {
  local_mocked_bindings(
    GET         = function(...) .resp(500L),
    status_code = function(x) x$status_code,
    .package = "httr"
  )
  result <- TaxaFetch:::.inat_taxon_id("Calidris mauri", "tok")
  expect_true(is.na(result$taxon_id))
  expect_true(is.na(result$matched_name))
  expect_true(is.na(result$n_observations))
})

test_that(".inat_taxon_id: returns NAs when results list is empty", {
  local_mocked_bindings(
    GET         = function(...) .resp(200L),
    status_code = function(x) x$status_code,
    content     = function(...) list(results = list()),
    .package = "httr"
  )
  result <- TaxaFetch:::.inat_taxon_id("Calidris mauri", "tok")
  expect_true(is.na(result$taxon_id))
})

test_that(".inat_taxon_id: parses all metadata fields correctly", {
  local_mocked_bindings(
    GET         = function(...) .resp(200L),
    status_code = function(x) x$status_code,
    content     = function(...) .taxa_resp(id = 3855L, name = "Calidris mauri",
                                           rank = "species", iconic = "Aves",
                                           n_obs = 21169L),
    .package = "httr"
  )
  result <- TaxaFetch:::.inat_taxon_id("Calidris mauri", "tok")
  expect_equal(result$taxon_id, 3855L)
  expect_equal(result$matched_name, "Calidris mauri")
  expect_equal(result$rank, "species")
  expect_equal(result$iconic_taxon_name, "Aves")
  expect_equal(result$n_observations, 21169L)
})

test_that(".inat_taxon_id: taxon_id is returned as integer", {
  local_mocked_bindings(
    GET         = function(...) .resp(200L),
    status_code = function(x) x$status_code,
    content     = function(...) .taxa_resp(id = 3855L),
    .package = "httr"
  )
  result <- TaxaFetch:::.inat_taxon_id("Calidris mauri", "tok")
  expect_type(result$taxon_id, "integer")
})

# =============================================================================
# .inat_range_polygon helper
# =============================================================================

test_that(".inat_range_polygon: returns NULL on 404", {
  local_mocked_bindings(
    GET         = function(...) .resp(404L),
    status_code = function(x) x$status_code,
    .package = "httr"
  )
  result <- TaxaFetch:::.inat_range_polygon(99999L, cache_dir = NULL)
  expect_null(result)
})

test_that(".inat_range_polygon: returns NULL on 403", {
  local_mocked_bindings(
    GET         = function(...) .resp(403L),
    status_code = function(x) x$status_code,
    .package = "httr"
  )
  result <- TaxaFetch:::.inat_range_polygon(99999L, cache_dir = NULL)
  expect_null(result)
})

test_that(".inat_range_polygon: reads from cache without calling GET", {
  skip_if_not_installed("sf")
  cache <- tempfile()
  dir.create(cache)
  on.exit(unlink(cache, recursive = TRUE))
  writeLines(.square_geojson, file.path(cache, "3855.geojson"))

  get_called <- FALSE
  local_mocked_bindings(
    GET = function(...) { get_called <<- TRUE; .resp(200L) },
    .package = "httr"
  )
  result <- TaxaFetch:::.inat_range_polygon(3855L, cache_dir = cache)
  expect_false(get_called)
  expect_s3_class(result, "sf")
})

test_that(".inat_range_polygon: writes GeoJSON to cache after successful download", {
  skip_if_not_installed("sf")
  cache <- tempfile()
  dir.create(cache)
  on.exit(unlink(cache, recursive = TRUE))

  local_mocked_bindings(
    GET         = function(...) .resp(200L),
    status_code = function(x) x$status_code,
    content     = function(...) .square_geojson,
    .package = "httr"
  )
  TaxaFetch:::.inat_range_polygon(3855L, cache_dir = cache)
  expect_true(file.exists(file.path(cache, "3855.geojson")))
})

test_that(".inat_range_polygon: does not write to cache on 404", {
  cache <- tempfile()
  dir.create(cache)
  on.exit(unlink(cache, recursive = TRUE))

  local_mocked_bindings(
    GET         = function(...) .resp(404L),
    status_code = function(x) x$status_code,
    .package = "httr"
  )
  TaxaFetch:::.inat_range_polygon(3855L, cache_dir = cache)
  expect_length(list.files(cache), 0L)
})

# =============================================================================
# .point_in_inat_range helper
# =============================================================================

test_that(".point_in_inat_range: TRUE for point inside polygon", {
  skip_if_not_installed("sf")
  polygon_sf <- sf::st_read(.square_geojson, quiet = TRUE)
  # Point at (lng=0.5, lat=0.5) is inside the unit square
  expect_true(TaxaFetch:::.point_in_inat_range(polygon_sf, lat = 0.5, lng = 0.5))
})

test_that(".point_in_inat_range: FALSE for point outside polygon", {
  skip_if_not_installed("sf")
  polygon_sf <- sf::st_read(.square_geojson, quiet = TRUE)
  # Point at (lng=2, lat=2) is outside the unit square
  expect_false(TaxaFetch:::.point_in_inat_range(polygon_sf, lat = 2.0, lng = 2.0))
})

test_that(".point_in_inat_range: FALSE for point on boundary edge", {
  skip_if_not_installed("sf")
  polygon_sf <- sf::st_read(.square_geojson, quiet = TRUE)
  # sf::st_within is strict (not st_covers), so boundary points return FALSE
  expect_false(TaxaFetch:::.point_in_inat_range(polygon_sf, lat = 0.0, lng = 0.5))
})
