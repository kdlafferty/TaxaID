# test-fetch_inat_occurrences.R
# Tests for fetch_inat_occurrences() and its internal helper.
#
# Strategy (mirrors test-check_inat_range.R):
#   - Input validation: no HTTP calls needed.
#   - fetch_inat_occurrences() outcomes: mock .inat_taxon_id() (already
#     covered directly by test-check_inat_range.R) and .inat_observation_count().
#   - .inat_observation_count(): mock httr::GET / httr::status_code / httr::content.

library(testthat)

.found_taxon <- list(
  taxon_id = 3855L, matched_name = "Calidris mauri",
  rank = "species", iconic_taxon_name = "Aves",
  n_observations = 21169L
)

.not_found_taxon <- list(
  taxon_id = NA_integer_, matched_name = NA_character_,
  rank = NA_character_, iconic_taxon_name = NA_character_,
  n_observations = NA_integer_
)

.resp <- function(status) structure(list(status_code = status), class = "response")

# =============================================================================
# Input validation
# =============================================================================

test_that("stops when api_token is empty string", {
  expect_error(
    fetch_inat_occurrences("Felis catus", lat = 34.1, lng = -119.1, api_token = ""),
    regexp = "INAT_API_TOKEN"
  )
})

test_that("stops when lat is non-numeric", {
  expect_error(
    fetch_inat_occurrences("Felis catus", lat = "34.1", lng = -119.1, api_token = "tok"),
    regexp = "lat"
  )
})

test_that("stops when lng is NA", {
  expect_error(
    fetch_inat_occurrences("Felis catus", lat = 34.1, lng = NA_real_, api_token = "tok"),
    regexp = "lng"
  )
})

test_that("stops when radius_km is not positive", {
  expect_error(
    fetch_inat_occurrences("Felis catus", lat = 34.1, lng = -119.1, radius_km = 0, api_token = "tok"),
    regexp = "radius_km"
  )
})

test_that("match.arg errors on an invalid captive value", {
  expect_error(
    fetch_inat_occurrences("Felis catus", lat = 34.1, lng = -119.1, captive = "bogus", api_token = "tok")
  )
})

# =============================================================================
# Output structure and outcomes
# =============================================================================

test_that("returns a tibble with the correct nine columns", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .not_found_taxon,
    .package = "TaxaFetch"
  )
  out <- fetch_inat_occurrences("Unknown taxon", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_s3_class(out, "tbl_df")
  expect_named(out, c(
    "taxon_name", "taxon_id", "matched_name", "inat_kingdom",
    "n_observations_local", "query_status", "radius_km",
    "captive", "quality_grade"
  ))
})

test_that("inat_kingdom reflects iconic_taxon_name for a found taxon", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .found_taxon, # iconic_taxon_name = "Aves"
    .inat_observation_count = function(...) 5L,
    .package = "TaxaFetch"
  )
  out <- fetch_inat_occurrences("Calidris mauri", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_equal(out$inat_kingdom, "Animalia")
})

test_that("inat_kingdom is NA for taxon_not_found rows", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .not_found_taxon,
    .package = "TaxaFetch"
  )
  out <- fetch_inat_occurrences("Unknown taxon", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_true(is.na(out$inat_kingdom))
})

test_that("taxon_not_found: correct status and NA count", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .not_found_taxon,
    .package = "TaxaFetch"
  )
  out <- fetch_inat_occurrences("Definitely notaspecies", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_equal(out$query_status, "taxon_not_found")
  expect_true(is.na(out$n_observations_local))
  expect_true(is.na(out$taxon_id))
})

test_that("ok: real count is returned and query_status is ok", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .found_taxon,
    .inat_observation_count = function(...) 42L,
    .package = "TaxaFetch"
  )
  out <- fetch_inat_occurrences("Calidris mauri", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_equal(out$n_observations_local, 42L)
  expect_equal(out$query_status, "ok")
  expect_equal(out$taxon_id, 3855L)
})

test_that("request_failed: NA count maps to request_failed status", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .found_taxon,
    .inat_observation_count = function(...) NA_integer_,
    .package = "TaxaFetch"
  )
  out <- fetch_inat_occurrences("Calidris mauri", lat = 34.1, lng = -119.1, api_token = "tok")
  expect_true(is.na(out$n_observations_local))
  expect_equal(out$query_status, "request_failed")
})

test_that("captive and quality_grade filters are recorded on output", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .found_taxon,
    .inat_observation_count = function(...) 5L,
    .package = "TaxaFetch"
  )
  out <- fetch_inat_occurrences("Calidris mauri",
    lat = 34.1, lng = -119.1,
    captive = "true", quality_grade = "casual",
    api_token = "tok"
  )
  expect_equal(out$captive, "true")
  expect_equal(out$quality_grade, "casual")
})

test_that("returns one row per input taxon name, mixed outcomes", {
  call_count <- 0L
  taxon_info <- list(.found_taxon, .not_found_taxon, .found_taxon)
  local_mocked_bindings(
    .inat_taxon_id = function(...) {
      call_count <<- call_count + 1L
      taxon_info[[call_count]]
    },
    .inat_observation_count = function(...) 7L,
    .package = "TaxaFetch"
  )
  out <- fetch_inat_occurrences(c("Taxon a", "Unknown", "Taxon c"),
    lat = 0, lng = 0, api_token = "tok"
  )
  expect_equal(nrow(out), 3L)
  expect_equal(out$query_status, c("ok", "taxon_not_found", "ok"))
})

test_that("verbose emits progress messages", {
  local_mocked_bindings(
    .inat_taxon_id = function(...) .not_found_taxon,
    .package = "TaxaFetch"
  )
  expect_message(
    fetch_inat_occurrences(c("Foo bar", "Baz qux"),
      lat = 0, lng = 0,
      api_token = "tok", verbose = TRUE
    ),
    regexp = "\\[1/2\\]"
  )
})

# =============================================================================
# .inat_observation_count helper
# =============================================================================

test_that(".inat_observation_count: returns total_results from a 200 response", {
  local_mocked_bindings(
    GET = function(...) .resp(200L),
    status_code = function(x) x$status_code,
    content = function(...) list(total_results = 123L),
    .package = "httr"
  )
  n <- TaxaFetch:::.inat_observation_count(
    taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
    captive = "any", quality_grade = "any", api_token = "tok"
  )
  expect_equal(n, 123L)
})

test_that(".inat_observation_count: returns NA on non-200 status", {
  local_mocked_bindings(
    GET = function(...) .resp(500L),
    status_code = function(x) x$status_code,
    .package = "httr"
  )
  n <- TaxaFetch:::.inat_observation_count(
    taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
    captive = "any", quality_grade = "any", api_token = "tok"
  )
  expect_true(is.na(n))
})

test_that(".inat_observation_count: stops with token message on 401", {
  local_mocked_bindings(
    GET = function(...) .resp(401L),
    status_code = function(x) x$status_code,
    .package = "httr"
  )
  expect_error(
    TaxaFetch:::.inat_observation_count(
      taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
      captive = "any", quality_grade = "any", api_token = "stale"
    ),
    regexp = "401 Unauthorized|expired|INAT_API_TOKEN"
  )
})

test_that(".inat_observation_count: returns NA when total_results missing", {
  local_mocked_bindings(
    GET = function(...) .resp(200L),
    status_code = function(x) x$status_code,
    content = function(...) list(),
    .package = "httr"
  )
  n <- TaxaFetch:::.inat_observation_count(
    taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
    captive = "any", quality_grade = "any", api_token = "tok"
  )
  expect_true(is.na(n))
})
