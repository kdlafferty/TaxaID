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
    headers = function(x) list(),
    .package = "httr"
  )
  # max_attempts = 1L: this test targets the non-200 -> NA outcome itself,
  # not the retry behaviour (covered separately below).
  n <- TaxaFetch:::.inat_observation_count(
    taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
    captive = "any", quality_grade = "any", api_token = "tok",
    max_attempts = 1L
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

# =============================================================================
# Retry/backoff on 429 and 5xx (RISK-1 fix)
# =============================================================================

test_that(".inat_observation_count: retries a 429 twice then succeeds on the third attempt", {
  call_count <- 0L
  local_mocked_bindings(
    GET = function(...) {
      call_count <<- call_count + 1L
      if (call_count <= 2L) .resp(429L) else .resp(200L)
    },
    status_code = function(x) x$status_code,
    content = function(...) list(total_results = 77L),
    headers = function(x) list(),
    .package = "httr"
  )
  n <- TaxaFetch:::.inat_observation_count(
    taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
    captive = "any", quality_grade = "any", api_token = "tok",
    waits = c(0, 0, 0) # keep the test fast; behaviour under test is attempt count, not timing
  )
  expect_equal(call_count, 3L)
  expect_equal(n, 77L)
})

test_that(".inat_observation_count: retries a 503 twice then succeeds (5xx is retried like 429)", {
  call_count <- 0L
  local_mocked_bindings(
    GET = function(...) {
      call_count <<- call_count + 1L
      if (call_count <= 2L) .resp(503L) else .resp(200L)
    },
    status_code = function(x) x$status_code,
    content = function(...) list(total_results = 9L),
    headers = function(x) list(),
    .package = "httr"
  )
  n <- TaxaFetch:::.inat_observation_count(
    taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
    captive = "any", quality_grade = "any", api_token = "tok",
    waits = c(0, 0, 0)
  )
  expect_equal(call_count, 3L)
  expect_equal(n, 9L)
})

test_that(".inat_observation_count: a persistent 429/5xx exhausts bounded attempts and returns NA (request_failed)", {
  call_count <- 0L
  local_mocked_bindings(
    GET = function(...) {
      call_count <<- call_count + 1L
      .resp(429L)
    },
    status_code = function(x) x$status_code,
    headers = function(x) list(),
    .package = "httr"
  )
  n <- TaxaFetch:::.inat_observation_count(
    taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
    captive = "any", quality_grade = "any", api_token = "tok",
    max_attempts = 3L, waits = c(0, 0, 0)
  )
  expect_equal(call_count, 3L) # bounded, not infinite
  expect_true(is.na(n)) # same documented failure value as any other failure
})

test_that(".inat_observation_count: a 401 is never retried", {
  call_count <- 0L
  local_mocked_bindings(
    GET = function(...) {
      call_count <<- call_count + 1L
      .resp(401L)
    },
    status_code = function(x) x$status_code,
    headers = function(x) list(),
    .package = "httr"
  )
  expect_error(
    TaxaFetch:::.inat_observation_count(
      taxon_id = 3855L, lat = 34.1, lng = -119.1, radius_km = 50,
      captive = "any", quality_grade = "any", api_token = "stale",
      waits = c(0, 0, 0)
    ),
    regexp = "401"
  )
  expect_equal(call_count, 1L)
})

test_that("fetch_inat_occurrences: retry_attempts/retry_wait are forwarded to .inat_observation_count", {
  captured <- new.env()
  local_mocked_bindings(
    .inat_taxon_id = function(...) .found_taxon,
    .inat_observation_count = function(..., max_attempts, waits) {
      captured$max_attempts <- max_attempts
      captured$waits <- waits
      5L
    },
    .package = "TaxaFetch"
  )
  fetch_inat_occurrences(
    "Calidris mauri",
    lat = 34.1, lng = -119.1, api_token = "tok",
    retry_attempts = 2L, retry_wait = c(1, 2)
  )
  expect_equal(captured$max_attempts, 2L)
  expect_equal(captured$waits, c(1, 2))
})

# =============================================================================
# .http_with_retry / .http_retry_wait
# =============================================================================

test_that(".http_with_retry: returns immediately on a non-retryable status (e.g. 404)", {
  call_count <- 0L
  local_mocked_bindings(
    status_code = function(x) x$status_code,
    .package = "httr"
  )
  resp <- TaxaFetch:::.http_with_retry(function() {
    call_count <<- call_count + 1L
    .resp(404L)
  })
  expect_equal(call_count, 1L)
  expect_equal(httr::status_code(resp), 404L)
})

test_that(".http_with_retry: a network-level failure (request_fn throws) is retried up to max_attempts", {
  call_count <- 0L
  resp <- TaxaFetch:::.http_with_retry(
    function() {
      call_count <<- call_count + 1L
      stop("simulated curl timeout")
    },
    max_attempts = 3L, waits = c(0, 0, 0)
  )
  expect_equal(call_count, 3L)
  expect_null(resp)
})

test_that(".http_retry_wait: honours a numeric Retry-After header over the default backoff", {
  local_mocked_bindings(
    headers = function(x) list(`retry-after` = "5"),
    .package = "httr"
  )
  w <- TaxaFetch:::.http_retry_wait(
    structure(list(), class = "response"),
    attempt = 1L, waits = c(15, 30, 60)
  )
  expect_equal(w, 5)
})

test_that(".http_retry_wait: falls back to waits when no Retry-After header is present", {
  local_mocked_bindings(
    headers = function(x) list(),
    .package = "httr"
  )
  w <- TaxaFetch:::.http_retry_wait(
    structure(list(), class = "response"),
    attempt = 2L, waits = c(15, 30, 60)
  )
  expect_equal(w, 30)
})

test_that(".http_retry_wait: falls back to waits when resp is NULL (network-level failure)", {
  w <- TaxaFetch:::.http_retry_wait(NULL, attempt = 3L, waits = c(15, 30, 60))
  expect_equal(w, 60)
})

test_that(".http_retry_wait: recycles the last wait value once attempts exceed the vector length", {
  w <- TaxaFetch:::.http_retry_wait(NULL, attempt = 10L, waits = c(15, 30, 60))
  expect_equal(w, 60)
})
