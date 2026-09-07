# test-fetch_gbif_occurrences.R
# Tests for fetch_gbif_occurrences() and internal helper .fetch_chunk().
#
# Strategy:
#   - Input validation: no rgbif needed.
#   - Behaviour / output structure: mock rgbif::occ_data.
#   - .fetch_chunk hierarchy validation: tested directly with fake data.
#   - Live API: guarded by skip_if_not_installed + skip_if_offline.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

.bbox <- make_bbox_wkt(34.5, -120.0, 1.0)

# Minimal fake occ_data response matching rgbif structure
.make_occ_resp <- function(key, n = 3) {
  df <- data.frame(
    decimalLatitude  = runif(n, 33.5, 35.5),
    decimalLongitude = runif(n, -121, -119),
    taxonKey         = key,
    speciesKey       = key,
    genusKey         = key + 1000L,
    familyKey        = key + 2000L,
    orderKey         = key + 3000L,
    classKey         = key + 4000L,
    phylumKey        = key + 5000L,
    kingdomKey       = key + 6000L,
    acceptedTaxonKey = key,
    stringsAsFactors = FALSE
  )
  list(data = df)
}

.make_occ_resp_mismatch <- function(key, n = 2) {
  # Returns records whose hierarchy does NOT contain the query key
  resp <- .make_occ_resp(key + 99999L, n) # wrong key throughout
  list(data = resp$data)
}

# =============================================================================
# Input validation
# =============================================================================

test_that("stops if rgbif is not installed", {
  skip_if(
    requireNamespace("rgbif", quietly = TRUE),
    "rgbif is installed; skipping missing-package test"
  )
  expect_error(
    fetch_gbif_occurrences(keys = 1L, geometry = .bbox),
    regexp = "rgbif"
  )
})

test_that("stops if keys is empty after NA removal", {
  skip_if_not_installed("rgbif")
  expect_error(
    fetch_gbif_occurrences(keys = NA_integer_, geometry = .bbox),
    regexp = "empty"
  )
})

test_that("stops if keys is entirely NA", {
  skip_if_not_installed("rgbif")
  expect_error(
    fetch_gbif_occurrences(keys = c(NA_integer_, NA_integer_), geometry = .bbox),
    regexp = "empty"
  )
})

test_that("stops if geometry is not a single character string", {
  skip_if_not_installed("rgbif")
  expect_error(
    fetch_gbif_occurrences(keys = 1L, geometry = 123),
    regexp = "geometry"
  )
  expect_error(
    fetch_gbif_occurrences(keys = 1L, geometry = c(.bbox, .bbox)),
    regexp = "geometry"
  )
})

test_that("removes duplicate keys before processing", {
  skip_if_not_installed("rgbif")
  call_count <- 0L
  local_mocked_bindings(
    occ_data = function(...) {
      call_count <<- call_count + 1L
      .make_occ_resp(1L)
    },
    .package = "rgbif"
  )
  fetch_gbif_occurrences(
    keys = c(1L, 1L, 1L), geometry = .bbox,
    pause_seconds = 0
  )
  expect_equal(call_count, 1L)
})

test_that("NA keys are silently dropped before processing", {
  skip_if_not_installed("rgbif")
  call_count <- 0L
  local_mocked_bindings(
    occ_data = function(...) {
      call_count <<- call_count + 1L
      .make_occ_resp(1L)
    },
    .package = "rgbif"
  )
  fetch_gbif_occurrences(
    keys = c(1L, NA_integer_), geometry = .bbox,
    pause_seconds = 0
  )
  expect_equal(call_count, 1L)
})

# =============================================================================
# Output structure (mocked API)
# =============================================================================

test_that("returns a data frame", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    occ_data = function(taxonKey, ...) .make_occ_resp(taxonKey),
    .package = "rgbif"
  )
  out <- fetch_gbif_occurrences(
    keys = 1L, geometry = .bbox,
    pause_seconds = 0
  )
  expect_true(is.data.frame(out))
})

test_that("returns rows from all keys combined", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    occ_data = function(taxonKey, ...) .make_occ_resp(taxonKey, n = 3),
    .package = "rgbif"
  )
  out <- fetch_gbif_occurrences(
    keys = c(1L, 2L, 3L), geometry = .bbox,
    pause_seconds = 0
  )
  expect_gte(nrow(out), 9L) # 3 rows × 3 keys
})

test_that("warns and returns empty tibble when no records pass", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    occ_data = function(...) list(data = NULL),
    .package = "rgbif"
  )
  expect_warning(
    out <- fetch_gbif_occurrences(
      keys = 1L, geometry = .bbox,
      pause_seconds = 0
    ),
    regexp = "no records"
  )
  expect_equal(nrow(out), 0L)
})

test_that("geometry = NULL issues an unrestricted global search", {
  skip_if_not_installed("rgbif")
  captured_geometry <- "unset"
  local_mocked_bindings(
    occ_data = function(taxonKey, geometry, ...) {
      captured_geometry <<- geometry
      .make_occ_resp(taxonKey)
    },
    .package = "rgbif"
  )
  out <- fetch_gbif_occurrences(
    keys = 1L, geometry = NULL,
    pause_seconds = 0, cache_dir = NULL
  )
  expect_true(is.null(captured_geometry))
  expect_true(is.data.frame(out))
})

test_that(".gbif_checkpoint_path handles NULL geometry without error", {
  path <- TaxaFetch:::.gbif_checkpoint_path(
    cache_dir  = tempdir(),
    keys       = c(1L, 2L),
    geometry   = NULL,
    year_range = "2000,2024",
    limit      = 100L
  )
  expect_true(is.character(path))
  expect_true(grepl("_g0_", path))
})

test_that(".gbif_checkpoint_path handles NULL year_range without error (real bug, 2026-08 review)", {
  # Before the fix, gsub() on a NULL year_range silently produced
  # character(0), which propagated through sprintf() into a length-zero
  # checkpoint_path -- fetch_gbif_occurrences()'s own
  # `if (!is.null(checkpoint_path) && file.exists(checkpoint_path))` check
  # then crashed with "argument is of length zero". Reachable from a real
  # caller: TaxaExpect::build_priors()'s own year_range = NULL default
  # forwards straight through to fetch_gbif_occurrences().
  path <- TaxaFetch:::.gbif_checkpoint_path(
    cache_dir  = tempdir(),
    keys       = c(1L, 2L),
    geometry   = "POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))",
    year_range = NULL,
    limit      = 100L
  )
  expect_true(is.character(path))
  expect_length(path, 1L)
  expect_true(grepl("_all_", path))

  # Also confirm the actual downstream check that crashed does not error.
  expect_no_error(
    if (!is.null(path) && file.exists(path)) {
      TRUE
    } else {
      FALSE
    }
  )
})

test_that(".gbif_default_year_range() returns 2000 through the current year", {
  yr <- TaxaFetch:::.gbif_default_year_range()
  expect_match(yr, "^2000,[0-9]{4}$")
  end_year <- as.integer(strsplit(yr, ",")[[1L]][2L])
  expect_equal(end_year, as.integer(format(Sys.Date(), "%Y")))
})

# =============================================================================
# Chunking behaviour
# =============================================================================

test_that("splits keys into correct number of chunks", {
  skip_if_not_installed("rgbif")
  call_count <- 0L
  local_mocked_bindings(
    occ_data = function(taxonKey, ...) {
      call_count <<- call_count + 1L
      .make_occ_resp(taxonKey)
    },
    .package = "rgbif"
  )
  # 5 keys, chunk_size = 2 -> 3 chunks, 5 occ_data calls
  fetch_gbif_occurrences(
    keys = 1L:5L, geometry = .bbox,
    chunk_size = 2L, pause_seconds = 0
  )
  expect_equal(call_count, 5L)
})

# =============================================================================
# Hierarchy validation (via .fetch_chunk directly)
# =============================================================================

test_that("hierarchy validation retains records where query key is in lineage", {
  skip_if_not_installed("rgbif")
  key <- 42L
  resp <- .make_occ_resp(key, n = 4)
  local_mocked_bindings(
    occ_data = function(...) resp,
    .package = "rgbif"
  )
  out <- TaxaFetch:::.fetch_chunk(
    keys_chunk = key,
    geometry   = .bbox,
    year_range = "2000,2024",
    limit      = 100L,
    global_pos = 0L,
    total      = 1L
  )
  expect_equal(nrow(out$records), 4L)
  expect_false(out$aborted)
})

test_that("hierarchy validation drops records where query key is absent from lineage", {
  skip_if_not_installed("rgbif")
  key <- 42L
  resp <- .make_occ_resp_mismatch(key, n = 3)
  local_mocked_bindings(
    occ_data = function(...) resp,
    .package = "rgbif"
  )
  out <- TaxaFetch:::.fetch_chunk(
    keys_chunk = key,
    geometry   = .bbox,
    year_range = "2000,2024",
    limit      = 100L,
    global_pos = 0L,
    total      = 1L
  )
  expect_true(is.null(out$records) || nrow(out$records) == 0L)
  expect_false(out$aborted)
})

test_that("records kept when no hierarchy columns are present (can't validate)", {
  skip_if_not_installed("rgbif")
  key <- 99L
  df_no_hier <- data.frame(
    decimalLatitude  = c(34.0, 35.0),
    decimalLongitude = c(-120.0, -119.5),
    stringsAsFactors = FALSE
  )
  local_mocked_bindings(
    occ_data = function(...) list(data = df_no_hier),
    .package = "rgbif"
  )
  out <- TaxaFetch:::.fetch_chunk(
    keys_chunk = key,
    geometry   = .bbox,
    year_range = "2000,2024",
    limit      = 100L,
    global_pos = 0L,
    total      = 1L
  )
  expect_equal(nrow(out$records), 2L)
  expect_false(out$aborted)
})

# =============================================================================
# Error handling -- exhausted retries abort the run (no silent skipping)
# =============================================================================

test_that("checkpoint's remaining_keys includes the failed key itself, not just keys after its whole chunk", {
  # Regression test for a real production bug (2026-07-20, found via a real
  # GBIF timeout mid-run): the checkpoint-save path previously computed
  # global_pos AFTER adding the whole aborting chunk's size, so the key that
  # actually failed (and any others in that same chunk queued after it) were
  # silently excluded from remaining_keys -- never retried on resume, a
  # direct violation of this function's own "never silently skip a key"
  # design (see the module-level error-handling comment above .fetch_chunk).
  skip_if_not_installed("rgbif")
  cache_dir <- tempfile("gbif_ckpt_test_")
  dir.create(cache_dir)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)

  local_mocked_bindings(
    occ_data = function(taxonKey, ...) {
      if (taxonKey == 4L) stop("simulated API error")
      .make_occ_resp(taxonKey)
    },
    .package = "rgbif"
  )
  # 5 keys, chunk_size = 2 -> chunks [1,2], [3,4], [5]; key 4 (2nd key of the
  # 2nd chunk) fails after key 3 succeeds within the same chunk.
  expect_error(
    fetch_gbif_occurrences(
      keys = 1L:5L, geometry = .bbox, chunk_size = 2L,
      pause_seconds = 0, cache_dir = cache_dir
    ),
    regexp = "aborted"
  )

  ckpt_files <- list.files(cache_dir, pattern = "^gbif_fetch_", full.names = TRUE)
  expect_length(ckpt_files, 1L)
  ckpt <- readRDS(ckpt_files[1])
  expect_true(4L %in% ckpt$remaining_keys)
  # The whole aborting chunk [3,4] is re-attempted on resume (not just key 4
  # onward) -- key 3's own partial success within that chunk is deliberately
  # discarded rather than risk duplicate rows on resume; see the fix's own
  # comment in fetch_gbif_occurrences.R for why.
  expect_setequal(ckpt$remaining_keys, c(3L, 4L, 5L))
})

test_that("a failing key aborts the run with an error (no silent partial results)", {
  skip_if_not_installed("rgbif")
  local_mocked_bindings(
    occ_data = function(taxonKey, ...) {
      if (taxonKey == 999L) stop("simulated API error")
      .make_occ_resp(taxonKey)
    },
    .package = "rgbif"
  )
  # Key 999 fails immediately (non-transient error, no retry) -> abort
  # cache_dir = NULL so checkpoint is not written during the test
  expect_error(
    fetch_gbif_occurrences(
      keys = c(1L, 999L, 2L), geometry = .bbox,
      pause_seconds = 0, cache_dir = NULL
    ),
    regexp = "aborted"
  )
})

# =============================================================================
# Live API (skipped offline)
# =============================================================================

test_that("live API: returns records for a known taxon key", {
  skip_if_not_installed("rgbif")
  skip_if_offline()
  # GBIF key for Engraulis mordax (northern anchovy) -- stable
  bbox <- make_bbox_wkt(37.0, -122.5, 2.0)
  out <- fetch_gbif_occurrences(
    keys = 2360464L,
    geometry = bbox,
    year_range = "2010,2024",
    limit = 10L,
    pause_seconds = 0
  )
  expect_true(is.data.frame(out))
  # May be 0 rows in some regions; just check it doesn't error
})
