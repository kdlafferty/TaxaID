# test-add_pca_covariates.R
# Tests for add_pca_covariates() and apply_pca_transform().
# Fully offline — no NCBI, no GBIF, no glmmTMB.

library(testthat)

# =============================================================================
# Fixtures
# =============================================================================

# Build a minimal model_df-like data frame with two highly-correlated _s cols
.make_model_df <- function(n = 30L, cor_high = TRUE, extra_s = FALSE) {
  set.seed(42L)
  x <- rnorm(n)
  if (cor_high) {
    y <- x + rnorm(n, sd = 0.1)   # r ≈ 0.99
  } else {
    y <- rnorm(n)                  # r ≈ 0
  }
  df <- data.frame(
    grid_id      = paste0("G", seq_len(n)),
    taxon_name   = "Sp A",
    n_species    = 1L,
    n_other      = 5L,
    lat_r_s      = x,
    lon_r_s      = y,
    stringsAsFactors = FALSE
  )
  if (extra_s) df$depth_s <- rnorm(n)
  attr(df, "scale_params") <- list(
    lat_r = list(center = 0, scale = 1),
    lon_r = list(center = 0, scale = 1)
  )
  df
}

# =============================================================================
# Input validation — add_pca_covariates
# =============================================================================

test_that("stops if model_df is not a data frame", {
  expect_error(add_pca_covariates(list(a = 1)), regexp = "data frame")
})

test_that("stops if cor_threshold is out of range", {
  df <- .make_model_df()
  expect_error(add_pca_covariates(df, cor_threshold = 0),  regexp = "strictly between")
  expect_error(add_pca_covariates(df, cor_threshold = 1),  regexp = "strictly between")
  expect_error(add_pca_covariates(df, cor_threshold = NA), regexp = "strictly between")
})

test_that("stops if prefix is empty or non-character", {
  df <- .make_model_df()
  expect_error(add_pca_covariates(df, prefix = ""),     regexp = "non-empty")
  expect_error(add_pca_covariates(df, prefix = 123),    regexp = "non-empty")
})

# =============================================================================
# No-op paths
# =============================================================================

test_that("returns unchanged when fewer than 2 _s columns", {
  df <- data.frame(grid_id = 1L, lat_r_s = 1.0, stringsAsFactors = FALSE)
  expect_message(out <- add_pca_covariates(df), regexp = "fewer than 2")
  expect_identical(out, df)
})

test_that("returns unchanged when no pairs exceed threshold", {
  df <- .make_model_df(cor_high = FALSE)
  expect_message(out <- add_pca_covariates(df, cor_threshold = 0.7),
                 regexp = "no _s column pairs")
  expect_identical(out, df)
})

# =============================================================================
# Core behaviour
# =============================================================================

test_that("correlated _s columns are replaced by PC columns", {
  df  <- .make_model_df(cor_high = TRUE)
  out <- suppressMessages(add_pca_covariates(df, cor_threshold = 0.7))

  expect_false("lat_r_s" %in% names(out))
  expect_false("lon_r_s" %in% names(out))
  expect_true("PC1_s"   %in% names(out))
  expect_true("PC2_s"   %in% names(out))
})

test_that("non-covariate columns are preserved", {
  df  <- .make_model_df(cor_high = TRUE)
  out <- suppressMessages(add_pca_covariates(df))
  expect_true(all(c("grid_id", "taxon_name", "n_species", "n_other") %in% names(out)))
})

test_that("output is a tibble", {
  df  <- .make_model_df(cor_high = TRUE)
  out <- suppressMessages(add_pca_covariates(df))
  expect_s3_class(out, "tbl_df")
})

test_that("output has same number of rows as input", {
  df  <- .make_model_df(n = 20L)
  out <- suppressMessages(add_pca_covariates(df))
  expect_equal(nrow(out), 20L)
})

test_that("PC columns are uncorrelated (|r| < 1e-10)", {
  df  <- .make_model_df(cor_high = TRUE)
  out <- suppressMessages(add_pca_covariates(df))
  r   <- cor(out$PC1_s, out$PC2_s)
  expect_lt(abs(r), 1e-10)
})

test_that("number of PC columns equals number of replaced source columns", {
  df  <- .make_model_df(cor_high = TRUE, extra_s = TRUE)
  # depth_s is uncorrelated with lat_r_s/lon_r_s (random), lat/lon are correlated
  out <- suppressMessages(add_pca_covariates(df, cor_threshold = 0.7))
  # lat_r_s and lon_r_s replaced by 2 PCs; depth_s retained
  expect_true("PC1_s" %in% names(out))
  expect_true("PC2_s" %in% names(out))
  expect_true("depth_s" %in% names(out))
  expect_false("lat_r_s" %in% names(out))
})

# =============================================================================
# Attributes
# =============================================================================

test_that("scale_params attribute is preserved unchanged", {
  df  <- .make_model_df(cor_high = TRUE)
  out <- suppressMessages(add_pca_covariates(df))
  expect_identical(attr(out, "scale_params"), attr(df, "scale_params"))
})

test_that("pca_rotation attribute has required fields", {
  df   <- .make_model_df(cor_high = TRUE)
  out  <- suppressMessages(add_pca_covariates(df))
  prot <- attr(out, "pca_rotation")
  expect_true(is.list(prot))
  expect_true(all(c("source_cols", "pc_cols", "rotation", "prefix") %in% names(prot)))
})

test_that("pca_rotation source_cols matches replaced columns", {
  df   <- .make_model_df(cor_high = TRUE)
  out  <- suppressMessages(add_pca_covariates(df))
  prot <- attr(out, "pca_rotation")
  expect_setequal(prot$source_cols, c("lat_r_s", "lon_r_s"))
})

test_that("pca_rotation pc_cols matches PC columns in output", {
  df   <- .make_model_df(cor_high = TRUE)
  out  <- suppressMessages(add_pca_covariates(df))
  prot <- attr(out, "pca_rotation")
  expect_setequal(prot$pc_cols, c("PC1_s", "PC2_s"))
})

test_that("pca_rotation rotation is a matrix with correct dims", {
  df   <- .make_model_df(cor_high = TRUE)
  out  <- suppressMessages(add_pca_covariates(df))
  prot <- attr(out, "pca_rotation")
  rot  <- prot$rotation
  expect_true(is.matrix(rot))
  expect_equal(nrow(rot), 2L)   # 2 source columns
  expect_equal(ncol(rot), 2L)   # 2 PCs
})

test_that("custom prefix is respected", {
  df   <- .make_model_df(cor_high = TRUE)
  out  <- suppressMessages(add_pca_covariates(df, prefix = "MEM"))
  expect_true("MEM1_s" %in% names(out))
  expect_true("MEM2_s" %in% names(out))
  expect_equal(attr(out, "pca_rotation")$prefix, "MEM")
})

test_that("name collision with existing columns raises error", {
  set.seed(1L)
  df <- .make_model_df(cor_high = TRUE)
  df$PC1_s <- rnorm(nrow(df))   # non-constant so cor() works; name will collide
  expect_error(
    suppressMessages(add_pca_covariates(df, prefix = "PC")),
    regexp = "collide"
  )
})

# =============================================================================
# apply_pca_transform
# =============================================================================

test_that("apply_pca_transform stops if new_sites not a data frame", {
  prot <- list(source_cols = "a_s", pc_cols = "PC1_s",
               rotation = matrix(1, 1, 1))
  expect_error(apply_pca_transform(list(), prot), regexp = "data frame")
})

test_that("apply_pca_transform stops if pca_rotation is malformed", {
  df <- data.frame(a_s = 1.0)
  expect_error(apply_pca_transform(df, list()), regexp = "source_cols")
})

test_that("apply_pca_transform stops if source columns are missing", {
  df   <- data.frame(other = 1.0)
  prot <- list(source_cols = "lat_r_s", pc_cols = "PC1_s",
               rotation = matrix(1, 1, 1))
  expect_error(apply_pca_transform(df, prot), regexp = "not found")
})

test_that("apply_pca_transform produces PC columns and drops source columns", {
  df  <- .make_model_df(cor_high = TRUE)
  out <- suppressMessages(add_pca_covariates(df))
  rot <- attr(out, "pca_rotation")

  # Simulate scaled new_sites with the source columns
  new_sites <- data.frame(
    lat_r_s = rnorm(5L),
    lon_r_s = rnorm(5L),
    grid_id = 1:5L
  )
  result <- apply_pca_transform(new_sites, rot)

  expect_false("lat_r_s" %in% names(result))
  expect_false("lon_r_s" %in% names(result))
  expect_true("PC1_s"   %in% names(result))
  expect_true("PC2_s"   %in% names(result))
  expect_true("grid_id" %in% names(result))
  expect_equal(nrow(result), 5L)
})

test_that("apply_pca_transform round-trips: scores match direct prcomp projection", {
  set.seed(7L)
  df   <- .make_model_df(cor_high = TRUE, n = 20L)
  out  <- suppressMessages(add_pca_covariates(df))
  rot  <- attr(out, "pca_rotation")

  new_s <- data.frame(lat_r_s = rnorm(4L), lon_r_s = rnorm(4L))
  result <- apply_pca_transform(new_s, rot)

  # Must subtract training center before rotating (matches prcomp(center=TRUE))
  centered <- sweep(as.matrix(new_s), 2L, rot$center, "-")
  expected <- centered %*% rot$rotation
  expect_equal(result$PC1_s, expected[, 1L], tolerance = 1e-10)
  expect_equal(result$PC2_s, expected[, 2L], tolerance = 1e-10)
})
