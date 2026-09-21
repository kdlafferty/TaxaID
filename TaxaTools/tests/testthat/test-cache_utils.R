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

  # c_ckpt.rds and not_matched.txt match neither pattern given here, so this
  # is deliberately a mixed directory -- force = TRUE is required (see the
  # containment-check tests below).
  inv <- list_cache_files(d, c("\\.zip$", "_meta\\.rds$"), force = TRUE)
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
  ok_inv <- data.frame(
    path = character(0), size_mb = numeric(0),
    mtime = as.POSIXct(character(0))
  )
  expect_error(report_and_clear_cache(inv = 1L, "lbl", "dir"), "inv")
  expect_error(report_and_clear_cache(ok_inv, label = 1L, "dir"), "label")
  expect_error(report_and_clear_cache(ok_inv, "lbl", cache_dir = 1L), "cache_dir")
  expect_error(report_and_clear_cache(ok_inv, "lbl", "dir", older_than_days = -1), "older_than_days")
  expect_error(report_and_clear_cache(ok_inv, "lbl", "dir", dry_run = "yes"), "dry_run")
})

test_that("report_and_clear_cache uses 'label' in its messages", {
  ok_inv <- data.frame(
    path = character(0), size_mb = numeric(0),
    mtime = as.POSIXct(character(0))
  )
  expect_message(report_and_clear_cache(ok_inv, "my_custom_label", "some/dir"), "my_custom_label")
  expect_error(report_and_clear_cache(ok_inv, "my_custom_label", "dir", dry_run = "x"), "my_custom_label")
})

test_that("report_and_clear_cache dry_run reports without deleting", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, "a.zip")
  writeLines("x", f)
  inv <- list_cache_files(d, "\\.zip$")

  out <- report_and_clear_cache(inv, "lbl", d, dry_run = TRUE)
  expect_equal(nrow(out), 1L)
  expect_true(file.exists(f))
})

test_that("report_and_clear_cache(dry_run = FALSE) actually deletes", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f <- file.path(d, "a.zip")
  writeLines("x", f)
  inv <- list_cache_files(d, "\\.zip$")

  out <- report_and_clear_cache(inv, "lbl", d, dry_run = FALSE)
  expect_equal(nrow(out), 1L)
  expect_false(file.exists(f))
})

test_that("report_and_clear_cache(older_than_days=) only targets stale rows", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  old_f <- file.path(d, "old.zip")
  writeLines("x", old_f)
  Sys.setFileTime(old_f, Sys.time() - 100 * 86400)
  new_f <- file.path(d, "new.zip")
  writeLines("y", new_f)
  inv <- list_cache_files(d, "\\.zip$")

  out <- report_and_clear_cache(inv, "lbl", d, older_than_days = 30, dry_run = FALSE)
  expect_equal(basename(out$path), "old.zip")
  expect_false(file.exists(old_f))
  expect_true(file.exists(new_f))
})

test_that("report_and_clear_cache reports 'no cache files found' for an empty inv", {
  empty_inv <- data.frame(
    path = character(0), size_mb = numeric(0),
    mtime = as.POSIXct(character(0))
  )
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


# --- cache_ok() -------------------------------------------------------------
# Lifted 2026-09-14 from three identical workflow-script copies; these tests
# pin the behaviour those copies had, so the lift cannot drift.

test_that("cache_ok returns FALSE for a file that does not exist", {
  expect_false(cache_ok(tempfile()))
})

test_that("cache_ok returns TRUE when no inputs are declared", {
  f <- tempfile()
  writeLines("x", f)
  expect_true(cache_ok(f))
  expect_true(cache_ok(f, inputs = NULL))
})

test_that("cache_ok rejects a cache older than a declared input", {
  cached <- tempfile()
  writeLines("cached", cached)
  Sys.setFileTime(cached, Sys.time() - 60)
  upstream <- tempfile()
  writeLines("upstream", upstream)

  expect_message(
    expect_false(cache_ok(cached, inputs = upstream)),
    "STALE CACHE"
  )
})

test_that("cache_ok accepts a cache newer than every declared input", {
  upstream <- tempfile()
  writeLines("upstream", upstream)
  Sys.setFileTime(upstream, Sys.time() - 60)
  cached <- tempfile()
  writeLines("cached", cached)

  expect_true(cache_ok(cached, inputs = upstream))
})

test_that("cache_ok ignores NA and non-existent inputs", {
  cached <- tempfile()
  writeLines("cached", cached)
  # A caller passing an optional upstream should not need to branch.
  expect_true(cache_ok(cached, inputs = c(NA_character_, tempfile())))
})

test_that("cache_ok rejects when ANY of several inputs is newer", {
  old <- tempfile()
  writeLines("old", old)
  Sys.setFileTime(old, Sys.time() - 120)
  cached <- tempfile()
  writeLines("cached", cached)
  Sys.setFileTime(cached, Sys.time() - 60)
  new <- tempfile()
  writeLines("new", new)

  expect_message(
    expect_false(cache_ok(cached, inputs = c(old, new))),
    "STALE CACHE"
  )
})


# --- taxaid_cache_report() --------------------------------------------------
# The ecosystem-level view that was missing while it accumulated 23 GB and
# then 17 GB unnoticed. Reports, never deletes.

test_that("taxaid_cache_report returns one row per cache and never deletes", {
  d <- tempfile()
  dir.create(d)
  writeLines("x", file.path(d, "a.rds"))
  writeLines("y", file.path(d, "b.rds"))

  out <- suppressMessages(taxaid_cache_report(extra_dirs = d))

  expect_s3_class(out, "data.frame")
  expect_true(all(c("cache", "path", "exists", "n_files", "size_mb",
                    "oldest", "newest") %in% names(out)))
  row <- out[out$path == d, ]
  expect_equal(nrow(row), 1L)
  expect_equal(row$n_files, 2L)
  expect_true(row$exists)
  # Nothing removed.
  expect_equal(length(list.files(d)), 2L)
})

test_that("taxaid_cache_report counts nested cache subdirectories", {
  # TaxaLikely keeps its per-accession FASTA store in a fasta/ subdirectory;
  # a non-recursive scan would report it as empty.
  d <- tempfile()
  dir.create(file.path(d, "fasta"), recursive = TRUE)
  writeLines("x", file.path(d, "top.rds"))
  writeLines("y", file.path(d, "fasta", "nested.rds"))

  out <- suppressMessages(taxaid_cache_report(extra_dirs = d))
  expect_equal(out[out$path == d, ]$n_files, 2L)
})

test_that("taxaid_cache_report reports a missing directory rather than dropping it", {
  missing <- file.path(tempdir(), "definitely_not_here_xyz")
  out <- suppressMessages(taxaid_cache_report(extra_dirs = missing))
  row <- out[out$path == missing, ]
  expect_equal(nrow(row), 1L) # a typo stays visible
  expect_false(row$exists)
  expect_equal(row$n_files, 0L)
})

test_that("taxaid_cache_report validates its arguments", {
  expect_error(taxaid_cache_report(extra_dirs = 1), "character vector")
  expect_error(taxaid_cache_report(warn_gb = "big"), "single number")
})


# --- list_cache_files(recursive=) (2026-09-14, P5) ----------------------------
# TaxaLikely's per-accession fasta/ store (P2) lives in a subdirectory, so
# while this argument did not exist its 4,061 files were invisible to every
# clear function in the ecosystem.

test_that("list_cache_files() is non-recursive by default", {
  d <- tempfile()
  dir.create(file.path(d, "sub"), recursive = TRUE)
  writeLines("x", file.path(d, "top_meta.rds"))
  writeLines("x", file.path(d, "sub", "nested_meta.rds"))

  out <- list_cache_files(d, "_meta\\.rds$")
  expect_identical(basename(out$path), "top_meta.rds")
})

test_that("list_cache_files(recursive = TRUE) reaches nested stores", {
  d <- tempfile()
  dir.create(file.path(d, "fasta"), recursive = TRUE)
  writeLines("x", file.path(d, "top_meta.rds"))
  writeLines("x", file.path(d, "fasta", "AB000667_seq.rds"))

  out <- list_cache_files(d, c("_meta\\.rds$", "_seq\\.rds$"), recursive = TRUE)
  expect_setequal(basename(out$path), c("top_meta.rds", "AB000667_seq.rds"))
})

test_that("list_cache_files() never returns a directory as a cache file", {
  d <- tempfile()
  # A directory whose own name matches the pattern would otherwise be
  # reported (and then handed to file.remove()).
  dir.create(file.path(d, "decoy_meta.rds"), recursive = TRUE)
  writeLines("x", file.path(d, "real_meta.rds"))

  out <- list_cache_files(d, "_meta\\.rds$")
  expect_identical(basename(out$path), "real_meta.rds")
})

test_that("list_cache_files() validates 'recursive'", {
  d <- tempfile()
  dir.create(d)
  expect_error(list_cache_files(d, "x$", recursive = NA), "TRUE or FALSE")
  expect_error(list_cache_files(d, "x$", recursive = "yes"), "TRUE or FALSE")
})


# =============================================================================
# Containment checks (2026-09-21). Reproduced by a reviewer: in a tempdir
# holding an unrelated "my_species_common_name.rds" data file,
# taxatools_clear_cache(cache_dir = ".", dry_run = FALSE) deleted it, because
# the working directory happened to be the tempdir and the file's basename
# happened to match the cache pattern. Every <pkg>_clear_cache() is built on
# list_cache_files()/report_and_clear_cache(), so the gap was ecosystem-wide.
# =============================================================================

# --- (a) refuse a cache_dir that is not a dedicated cache directory --------

test_that("list_cache_files refuses a cache_dir that resolves to the working directory", {
  d <- withr::local_tempdir()
  writeLines("x", file.path(d, "a.zip"))
  withr::local_dir(d)
  expect_error(
    list_cache_files(".", "\\.zip$"),
    "current working directory"
  )
})

test_that("list_cache_files refuses the user's home directory", {
  expect_error(list_cache_files(path.expand("~"), "\\.zip$"), "home directory")
})

test_that("list_cache_files refuses a filesystem root", {
  expect_error(list_cache_files("/", "\\.zip$"), "filesystem root")
})

test_that("list_cache_files refusing the working directory is not overridable by force", {
  d <- withr::local_tempdir()
  withr::local_dir(d)
  expect_error(list_cache_files(".", "\\.zip$", force = TRUE), "current working directory")
})

test_that(
  "report_and_clear_cache refuses a cache_dir that resolves to the working directory, even under dry_run = FALSE",
  {
    d <- withr::local_tempdir()
    writeLines("x", file.path(d, "a.zip"))
    withr::local_dir(d)
    inv <- data.frame(
      path = file.path(d, "a.zip"), size_mb = 0.001,
      mtime = Sys.time(), stringsAsFactors = FALSE
    )
    expect_error(
      report_and_clear_cache(inv, "lbl", ".", dry_run = FALSE),
      "current working directory"
    )
    expect_true(file.exists(file.path(d, "a.zip"))) # never reached file.remove()
  }
)

test_that("report_and_clear_cache refuses a filesystem root", {
  empty_inv <- data.frame(
    path = character(0), size_mb = numeric(0),
    mtime = as.POSIXct(character(0))
  )
  expect_error(report_and_clear_cache(empty_inv, "lbl", "/"), "filesystem root")
})

# --- (b) refuse a mixed directory unless force = TRUE ----------------------

test_that("list_cache_files refuses a directory holding a non-matching file", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "a.zip"))
  writeLines("x", file.path(d, "my_project_notes.txt"))

  expect_error(
    list_cache_files(d, "\\.zip$"),
    "my_project_notes\\.txt"
  )
})

test_that("list_cache_files(force = TRUE) scans a mixed directory anyway", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "a.zip"))
  writeLines("x", file.path(d, "my_project_notes.txt"))

  out <- list_cache_files(d, "\\.zip$", force = TRUE)
  expect_identical(basename(out$path), "a.zip")
})

test_that(
  "list_cache_files does not trip the mixed-directory guard on a directory holding only recognized cache files",
  {
    d <- tempfile("cache_")
    dir.create(d)
    on.exit(unlink(d, recursive = TRUE), add = TRUE)
    writeLines("x", file.path(d, "a.zip"))
    writeLines("x", file.path(d, "b_meta.rds"))

    out <- list_cache_files(d, c("\\.zip$", "_meta\\.rds$"))
    expect_setequal(basename(out$path), c("a.zip", "b_meta.rds"))
  }
)

test_that("taxatools_clear_cache(force=) threads through to list_cache_files()", {
  d <- withr::local_tempdir()
  writeLines("x", file.path(d, "a_common_name.rds"))
  writeLines("x", file.path(d, "unrelated_data.rds"))
  expect_error(
    suppressMessages(taxatools_clear_cache(d, dry_run = TRUE)),
    "unrelated_data\\.rds"
  )
  inv <- suppressMessages(taxatools_clear_cache(d, dry_run = TRUE, force = TRUE))
  expect_identical(basename(inv$path), "a_common_name.rds")
  expect_true(file.exists(file.path(d, "unrelated_data.rds"))) # dry_run: nothing deleted
})

# --- (c) never follow a symlink out of cache_dir ----------------------------

test_that("list_cache_files(recursive = TRUE) does not follow a symlinked subdirectory out of cache_dir", {
  skip_on_os("windows")
  outside <- tempfile("outside_")
  dir.create(outside)
  on.exit(unlink(outside, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(outside, "escaped_meta.rds"))

  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "real_meta.rds"))
  link <- file.path(d, "escaped_link")
  ok <- tryCatch(file.symlink(outside, link), error = function(e) FALSE)
  skip_if_not(isTRUE(ok), "symlinks not supported in this environment")

  out <- list_cache_files(d, "_meta\\.rds$", recursive = TRUE)
  expect_identical(basename(out$path), "real_meta.rds")
  expect_false("escaped_meta.rds" %in% basename(out$path))
})

test_that("list_cache_files does not follow a symlinked FILE that resolves outside cache_dir", {
  skip_on_os("windows")
  outside <- tempfile("outside_")
  dir.create(outside)
  on.exit(unlink(outside, recursive = TRUE), add = TRUE)
  target <- file.path(outside, "escaped_meta.rds")
  writeLines("x", target)

  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "real_meta.rds"))
  link <- file.path(d, "linked_meta.rds")
  ok <- tryCatch(file.symlink(target, link), error = function(e) FALSE)
  skip_if_not(isTRUE(ok), "symlinks not supported in this environment")

  out <- list_cache_files(d, "_meta\\.rds$")
  expect_identical(basename(out$path), "real_meta.rds")
})
