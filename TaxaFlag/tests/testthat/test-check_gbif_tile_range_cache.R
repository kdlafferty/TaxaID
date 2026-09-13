# test-check_gbif_tile_range_cache.R
# Tests for check_gbif_tile_range(cache_dir=), added 2026-09-13 to close the
# 43-minute-per-run Stage 1 cost documented in this file's own roxygen
# "Caching" section. Fully offline: mocks .fetch_gbif_tile_alpha() (the same
# network boundary test-check_gbif_tile_range.R already mocks), so a "cache
# hit made zero HTTP requests" assertion is a real, direct call-count check,
# never a live GBIF call.

library(testthat)

skip_if_not_installed("httr2")
skip_if_not_installed("png")

.query_lat <- 41.67
.query_lon <- -87.15
.zoom <- 6L
.tile_size <- 512L
.loc <- .lonlat_to_tile_pixel(.query_lat, .query_lon, .zoom, .tile_size)
.base_url <- "https://api.gbif.org/v2/map/occurrence/density"

.new_cache_dir <- function() {
  file.path(tempdir(), paste0("tilecache_", as.integer(stats::runif(1, 1, 1e8))))
}

# A point-occupied mock, same shape as test-check_gbif_tile_range.R's first
# test -- deterministic, no escalation, cheap to reason about.
.mock_point_occupied <- function(call_counter = NULL) {
  function(base_url, zoom, x, y, taxon_key, tile_size) {
    if (!is.null(call_counter)) {
      assign("n", get("n", call_counter) + 1L, call_counter)
    }
    m <- matrix(0, tile_size, tile_size)
    if (zoom == .zoom && x == .loc$xtile && y == .loc$ytile) m[.loc$py + 1L, .loc$px + 1L] <- 1
    m
  }
}

test_that("(a) a second identical call is served entirely from cache: zero fetch calls, same verdict", {
  cache_dir <- .new_cache_dir()
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)

  ctr <- new.env()
  assign("n", 0L, ctr)
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = .mock_point_occupied(ctr))

  first <- check_gbif_tile_range(
    taxon_key = 42, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  n_after_first <- get("n", ctr)
  expect_gt(n_after_first, 0L) # a real fetch happened on the miss
  expect_true(is.na(attr(first, "cache_age_days")))

  second <- check_gbif_tile_range(
    taxon_key = 42, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  expect_equal(get("n", ctr), n_after_first) # ZERO additional fetch calls
  expect_false(is.na(attr(second, "cache_age_days")))
  expect_gte(attr(second, "cache_age_days"), 0)

  attr(first, "cache_age_days") <- NULL
  attr(second, "cache_age_days") <- NULL
  expect_equal(first, second) # same verdict
})

test_that("(b) a different taxon_key, location, or zoom is a cache MISS, not a stale hit", {
  cache_dir <- .new_cache_dir()
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)

  ctr <- new.env()
  assign("n", 0L, ctr)
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = .mock_point_occupied(ctr))

  check_gbif_tile_range(
    taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  n1 <- get("n", ctr)
  expect_gt(n1, 0L)

  # different taxon_key
  check_gbif_tile_range(
    taxon_key = 2, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  n2 <- get("n", ctr)
  expect_gt(n2, n1)

  # different location
  check_gbif_tile_range(
    taxon_key = 1, query_lat = .query_lat + 5, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  n3 <- get("n", ctr)
  expect_gt(n3, n2)

  # different zoom
  check_gbif_tile_range(
    taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom - 1L,
    cache_dir = cache_dir, escalate = FALSE
  )
  expect_gt(get("n", ctr), n3)
})

test_that("(c) a foreign/corrupted key stored at the expected hash path forces a re-fetch, never a wrong return", {
  cache_dir <- .new_cache_dir()
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)

  taxon_key <- 999
  real_key <- TaxaFlag:::.tile_cache_key(
    taxon_key, .query_lat, .query_lon, 512L, .zoom, TRUE, 0L, .base_url
  )
  path <- file.path(cache_dir, paste0(TaxaFlag:::.review_cache_hash(real_key), "_tile_range.rds"))
  saveRDS(list(
    key = "SOME OTHER TAXON'S KEY",
    row = data.frame(taxon_key = -1, beyond_buffer = FALSE, point_occupied = FALSE, stringsAsFactors = FALSE),
    fetched_at = Sys.time()
  ), path)

  ctr <- new.env()
  assign("n", 0L, ctr)
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = .mock_point_occupied(ctr))

  out <- check_gbif_tile_range(
    taxon_key = taxon_key, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  expect_gt(get("n", ctr), 0L) # forced a real fetch, not the colliding file's row
  expect_equal(out$taxon_key, taxon_key)
  expect_true(out$point_occupied) # the REAL mocked verdict, not the bogus cached one
})

test_that("(d) a fetch that errors (unusable) is never cached -- the next call re-fetches too", {
  cache_dir <- .new_cache_dir()
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)

  ctr <- new.env()
  assign("n", 0L, ctr)
  mock_fail <- function(base_url, zoom, x, y, taxon_key, tile_size) {
    assign("n", get("n", ctr) + 1L, ctr)
    stop("simulated unusable tile response")
  }
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = mock_fail)

  expect_error(
    check_gbif_tile_range(
      taxon_key = 7, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
      cache_dir = cache_dir
    ),
    "simulated unusable"
  )
  # Nothing was ever written -- the cache directory holds no *_tile_range.rds file.
  expect_equal(nrow(TaxaTools::list_cache_files(cache_dir, "_tile_range\\.rds$")), 0L)

  n_after_first_error <- get("n", ctr)
  expect_error(
    check_gbif_tile_range(
      taxon_key = 7, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
      cache_dir = cache_dir
    ),
    "simulated unusable"
  )
  expect_gt(get("n", ctr), n_after_first_error) # re-fetched -- not served a bogus cache entry
})

test_that("(e) cache_age_days reports the real elapsed time since the cached fetch, to the day", {
  cache_dir <- .new_cache_dir()
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)

  taxon_key <- 555
  key <- TaxaFlag:::.tile_cache_key(taxon_key, .query_lat, .query_lon, 512L, .zoom, TRUE, 0L, .base_url)
  path <- file.path(cache_dir, paste0(TaxaFlag:::.review_cache_hash(key), "_tile_range.rds"))
  row <- data.frame(
    taxon_key = taxon_key, query_lat = .query_lat, query_lon = .query_lon,
    zoom_requested = .zoom, zoom_used = .zoom, escalated = FALSE, tile_size = 512L,
    n_tiles_fetched = 9L, resolution_km_per_px = 1, point_occupied = TRUE,
    dist_nearest_occupied_km = 0, patch_size_px = 1L, patch_size_capped = FALSE,
    patch_area_km2 = 1, patch_diameter_km = 1, beyond_buffer = FALSE,
    stringsAsFactors = FALSE
  )
  saveRDS(list(key = key, row = row, fetched_at = Sys.time() - 37 * 86400), path)

  # If a hit somehow fell through to a real fetch, this would error loudly --
  # this doubles as extra confirmation that a hit makes NO fetch call at all.
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = function(...) stop("must not be called on a cache hit"))

  out <- check_gbif_tile_range(
    taxon_key = taxon_key, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  age <- attr(out, "cache_age_days")
  expect_false(is.na(age))
  expect_gt(age, 36.9)
  expect_lt(age, 37.1)
})

test_that("cache_age_days is NA on a miss, and NA when cache_dir is NULL (uncached call)", {
  cache_dir <- .new_cache_dir()
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = .mock_point_occupied())

  miss <- check_gbif_tile_range(
    taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  expect_true(is.na(attr(miss, "cache_age_days")))

  uncached <- check_gbif_tile_range(
    taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom
  )
  expect_true(is.na(attr(uncached, "cache_age_days")))
})

test_that("cache files are the file-per-key shape taxaflag_clear_cache() reports and prunes", {
  cache_dir <- .new_cache_dir()
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)
  testthat::local_mocked_bindings(.fetch_gbif_tile_alpha = .mock_point_occupied())

  check_gbif_tile_range(
    taxon_key = 1, query_lat = .query_lat, query_lon = .query_lon, zoom = .zoom,
    cache_dir = cache_dir
  )
  inv <- taxaflag_clear_cache(cache_dir = cache_dir, dry_run = TRUE)
  expect_gt(nrow(inv), 0L)
  expect_true(all(grepl("_tile_range\\.rds$", basename(inv$path))))
  expect_true(all(file.exists(inv$path))) # dry_run kept them

  taxaflag_clear_cache(cache_dir = cache_dir)
  expect_equal(nrow(TaxaTools::list_cache_files(cache_dir, .taxaflag_cache_patterns)), 0L)
})
