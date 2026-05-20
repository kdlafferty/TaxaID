# test_compute_moran_basis.R
# testthat unit tests for compute_moran_basis().
# Run via devtools::test() or testthat::test_file().
# All tests use base R only -- no additional package dependencies.

# ---------------------------------------------------------------------------
# Helper: build grid_id string from lat/lon (mirrors make_grid_id in workflow)
# ---------------------------------------------------------------------------
.make_gid <- function(lat, lon) {
  lat_str <- gsub("\\.", "p", as.character(abs(round(lat, 4))))
  lon_str <- gsub("\\.", "p", as.character(abs(round(lon, 4))))
  paste0("Grid_", lat_str, "_", if (lon < 0) "m" else "", lon_str)
}

# Standard 5x5 test grid reused across tests
.grid5x5 <- local({
  g <- expand.grid(lat = seq(33.0, 33.4, by = 0.1),
                   lon = seq(-119.0, -118.6, by = 0.1))
  g$grid_id <- mapply(.make_gid, g$lat, g$lon)
  g
})

# ===========================================================================
# Test 1: Happy path -- regular 5x5 grid
# ===========================================================================
test_that("regular 5x5 grid returns correct structure", {
  basis <- suppressMessages(compute_moran_basis(.grid5x5$grid_id, k = 5L))

  expect_s3_class(basis, "data.frame")
  expect_equal(nrow(basis), 25L)
  expect_equal(ncol(basis), 6L)
  expect_equal(names(basis)[1], "grid_id")
  expect_equal(names(basis)[-1], paste0("B", 1:5))
  expect_equal(sum(is.na(basis)), 0L)
  expect_true(all(.grid5x5$grid_id %in% basis$grid_id))
})

test_that("B columns have unit variance", {
  basis <- suppressMessages(compute_moran_basis(.grid5x5$grid_id, k = 5L))
  b_vars <- sapply(basis[, -1], var)
  expect_true(all(abs(b_vars - 1.0) < 1e-8))
})

test_that("B columns are orthogonal (max |off-diagonal correlation| < 0.01)", {
  basis    <- suppressMessages(compute_moran_basis(.grid5x5$grid_id, k = 5L))
  cor_mat  <- cor(basis[, -1])
  off_diag <- abs(cor_mat[upper.tri(cor_mat)])
  expect_lt(max(off_diag), 0.01)
})

# ===========================================================================
# Test 2: Gap handling
# ===========================================================================
test_that("isolated cells are dropped with a warning", {
  # Remove all neighbours of corner cell (33.0, -119.0) including diagonal
  gaps <- c(.make_gid(33.0, -118.9),
            .make_gid(33.1, -119.0),
            .make_gid(33.1, -118.9))
  grid_gaps <- .grid5x5[!.grid5x5$grid_id %in% gaps, ]

  expect_warning(
    suppressMessages(compute_moran_basis(grid_gaps$grid_id, k = 3L)),
    regexp = "0 neighbours"
  )
})

test_that("isolated cell is excluded from output", {
  gaps <- c(.make_gid(33.0, -118.9),
            .make_gid(33.1, -119.0),
            .make_gid(33.1, -118.9))
  grid_gaps <- .grid5x5[!.grid5x5$grid_id %in% gaps, ]

  basis <- suppressMessages(suppressWarnings(
    compute_moran_basis(grid_gaps$grid_id, k = 3L)
  ))
  # 25 - 3 removed - 1 isolated corner = 21
  expect_equal(nrow(basis), 21L)
  expect_equal(sum(is.na(basis)), 0L)
})

# ===========================================================================
# Test 3: grid_id parsing -- positive and negative coordinates
# ===========================================================================
test_that("southern hemisphere / eastern longitude grid parses correctly", {
  g <- expand.grid(lat = seq(-34.0, -33.8, by = 0.1),
                   lon = seq(151.0, 151.2, by = 0.1))
  g$grid_id <- mapply(.make_gid, g$lat, g$lon)
  basis <- suppressMessages(compute_moran_basis(g$grid_id, k = 3L))
  expect_equal(nrow(basis), nrow(g))
  expect_equal(sum(is.na(basis)), 0L)
})

test_that("northern hemisphere / western longitude (California) grid parses correctly", {
  g <- expand.grid(lat = seq(34.0, 34.4, by = 0.1),
                   lon = seq(-120.0, -119.6, by = 0.1))
  g$grid_id <- mapply(.make_gid, g$lat, g$lon)
  basis <- suppressMessages(compute_moran_basis(g$grid_id, k = 4L))
  expect_equal(nrow(basis), nrow(g))
  expect_equal(sum(is.na(basis)), 0L)
})

# ===========================================================================
# Test 4: Spatial ordering
# ===========================================================================
test_that("B1 or B2 has higher lat correlation than B3 (broadest first)", {
  basis  <- suppressMessages(compute_moran_basis(.grid5x5$grid_id, k = 5L))
  merged <- merge(basis, .grid5x5, by = "grid_id")

  max_b12 <- max(abs(cor(merged$B1, merged$lat)),
                 abs(cor(merged$B2, merged$lat)))
  b3_cor  <- abs(cor(merged$B3, merged$lat))

  expect_gt(max_b12, b3_cor)
  expect_gt(max_b12, 0.5)
})

# ===========================================================================
# Test 5: k auto-reduction
# ===========================================================================
test_that("k is silently reduced when fewer positive eigenvalues are available", {
  # 3x3 grid; request k=7 which exceeds available positive eigenvalues
  g <- expand.grid(lat = seq(33.0, 33.2, by = 0.1),
                   lon = seq(-119.0, -118.8, by = 0.1))
  g$grid_id <- mapply(.make_gid, g$lat, g$lon)

  basis <- suppressMessages(compute_moran_basis(g$grid_id, k = 7L))
  expect_equal(nrow(basis), 9L)
  expect_lt(ncol(basis), 9L)   # grid_id + fewer than 8 B columns
  expect_equal(sum(is.na(basis)), 0L)
})

# ===========================================================================
# Test 6: Explicit distance_threshold
# ===========================================================================
test_that("threshold too small to connect any cells raises an error", {
  expect_error(
    suppressWarnings(suppressMessages(
      compute_moran_basis(.grid5x5$grid_id, k = 3L, distance_threshold = 0.05)
    )),
    regexp = "fewer than 3 connected"
  )
})

test_that("explicit threshold just above grid spacing produces valid output", {
  basis <- suppressMessages(
    compute_moran_basis(.grid5x5$grid_id, k = 3L, distance_threshold = 0.11)
  )
  expect_s3_class(basis, "data.frame")
  expect_equal(sum(is.na(basis)), 0L)
})

# ===========================================================================
# Test 7: Input validation
# ===========================================================================
test_that("non-character grid_ids raises an error", {
  expect_error(compute_moran_basis(123L, k = 3L))
})

test_that("empty grid_ids raises an error", {
  expect_error(compute_moran_basis(character(0), k = 3L))
})

test_that("k = 0 raises an error", {
  expect_error(compute_moran_basis(.grid5x5$grid_id, k = 0L))
})

test_that("non-integer k raises an error", {
  expect_error(compute_moran_basis(.grid5x5$grid_id, k = 1.5))
})

test_that("k >= n_cells raises an error", {
  expect_error(compute_moran_basis(.grid5x5$grid_id, k = 100L))
})

test_that("unparseable grid_ids emit a warning", {
  mixed <- c(.grid5x5$grid_id[1:10], "NOT_A_GRID_ID_1", "NOT_A_GRID_ID_2")
  expect_warning(
    suppressMessages(compute_moran_basis(mixed, k = 3L)),
    regexp = "could not be parsed"
  )
})

# ===========================================================================
# Test 8: Single-latitude grid (lon-based spacing fallback)
# ===========================================================================
test_that("single-latitude grid uses lon-based spacing and returns valid output", {
  g <- data.frame(
    lat     = rep(33.0, 6),
    lon     = seq(-120.0, -119.5, by = 0.1)
  )
  g$grid_id <- mapply(.make_gid, g$lat, g$lon)

  basis <- suppressMessages(compute_moran_basis(g$grid_id, k = 3L))
  expect_s3_class(basis, "data.frame")
  expect_equal(nrow(basis), 6L)
  expect_equal(sum(is.na(basis)), 0L)
})
