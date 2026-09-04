# test-cache_utils.R
# Tests for list_cache_files() and report_and_clear_cache() -- the shared
# engine behind downstream packages' own <pkg>_clear_cache() helpers.
# Fully offline -- everything operates on tempfile() directories.

# =============================================================================
# list_cache_files()
# =============================================================================

test_that("list_cache_files validates its arguments", {
  expect_error(list_cache_files(cache_dir = 1L, patterns = "x"), "cache_dir")
  expect_error(list_cache_files(cache_dir = "x", patterns = character(0)), "patterns")
})

test_that("list_cache_files matches basenames against any supplied pattern", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "a.zip"))
  writeLines("x", file.path(d, "b_meta.rds"))
  writeLines("x", file.path(d, "c_ckpt.rds"))
  writeLines("x", file.path(d, "not_matched.txt"))

  inv <- list_cache_files(d, c("\\.zip$", "_meta\\.rds$"))
  expect_setequal(basename(inv$path), c("a.zip", "b_meta.rds"))
  expect_named(inv, c("path", "size_mb", "mtime"))
})

test_that("list_cache_files returns a zero-row frame for an empty/nonexistent directory", {
  inv1 <- list_cache_files(tempfile("does_not_exist_"), "\\.zip$")
  expect_equal(nrow(inv1), 0L)
  expect_named(inv1, c("path", "size_mb", "mtime"))

  d <- tempfile("empty_cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  inv2 <- list_cache_files(d, "\\.zip$")
  expect_equal(nrow(inv2), 0L)
})

test_that("list_cache_files reports real size and mtime", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, "a.zip")
  writeLines(strrep("x", 2048), f)

  inv <- list_cache_files(d, "\\.zip$")
  expect_equal(nrow(inv), 1L)
  expect_gt(inv$size_mb, 0)
  expect_s3_class(inv$mtime, "POSIXct")
})

# =============================================================================
# report_and_clear_cache()
# =============================================================================

test_that("report_and_clear_cache validates its arguments", {
  ok_inv <- data.frame(path = character(0), size_mb = numeric(0),
                       mtime = as.POSIXct(character(0)))
  expect_error(report_and_clear_cache(inv = 1L, "lbl", "dir"), "inv")
  expect_error(report_and_clear_cache(ok_inv, label = 1L, "dir"), "label")
  expect_error(report_and_clear_cache(ok_inv, "lbl", cache_dir = 1L), "cache_dir")
  expect_error(report_and_clear_cache(ok_inv, "lbl", "dir", older_than_days = -1), "older_than_days")
  expect_error(report_and_clear_cache(ok_inv, "lbl", "dir", dry_run = "yes"), "dry_run")
})

test_that("report_and_clear_cache uses 'label' in its messages", {
  ok_inv <- data.frame(path = character(0), size_mb = numeric(0),
                       mtime = as.POSIXct(character(0)))
  expect_message(report_and_clear_cache(ok_inv, "my_custom_label", "some/dir"), "my_custom_label")
  expect_error(report_and_clear_cache(ok_inv, "my_custom_label", "dir", dry_run = "x"), "my_custom_label")
})

test_that("report_and_clear_cache dry_run reports without deleting", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, "a.zip"); writeLines("x", f)
  inv <- list_cache_files(d, "\\.zip$")

  out <- report_and_clear_cache(inv, "lbl", d, dry_run = TRUE)
  expect_equal(nrow(out), 1L)
  expect_true(file.exists(f))
})

test_that("report_and_clear_cache(dry_run = FALSE) actually deletes", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, "a.zip"); writeLines("x", f)
  inv <- list_cache_files(d, "\\.zip$")

  out <- report_and_clear_cache(inv, "lbl", d, dry_run = FALSE)
  expect_equal(nrow(out), 1L)
  expect_false(file.exists(f))
})

test_that("report_and_clear_cache(older_than_days=) only targets stale rows", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  old_f <- file.path(d, "old.zip"); writeLines("x", old_f)
  Sys.setFileTime(old_f, Sys.time() - 100 * 86400)
  new_f <- file.path(d, "new.zip"); writeLines("y", new_f)
  inv <- list_cache_files(d, "\\.zip$")

  out <- report_and_clear_cache(inv, "lbl", d, older_than_days = 30, dry_run = FALSE)
  expect_equal(basename(out$path), "old.zip")
  expect_false(file.exists(old_f))
  expect_true(file.exists(new_f))
})

test_that("report_and_clear_cache reports 'no cache files found' for an empty inv", {
  empty_inv <- data.frame(path = character(0), size_mb = numeric(0),
                          mtime = as.POSIXct(character(0)))
  expect_message(out <- report_and_clear_cache(empty_inv, "lbl", "some/dir"), "no cache files found")
  expect_equal(nrow(out), 0L)
})

test_that("report_and_clear_cache reports 'no cache files match' when older_than_days excludes everything", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "fresh.zip"))
  inv <- list_cache_files(d, "\\.zip$")

  expect_message(
    out <- report_and_clear_cache(inv, "lbl", d, older_than_days = 9999, dry_run = TRUE),
    "no cache files match"
  )
  expect_equal(nrow(out), 0L)
})
