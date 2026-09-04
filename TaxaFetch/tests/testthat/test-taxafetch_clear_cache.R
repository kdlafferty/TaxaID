# test-taxafetch_clear_cache.R
# Tests for taxafetch_clear_cache() and its shared internal inventory helper.
# Fully offline -- everything operates on tempfile() directories.

test_that("taxafetch_clear_cache validates its arguments", {
  expect_error(taxafetch_clear_cache(cache_dir = 1L), "cache_dir")
  expect_error(taxafetch_clear_cache(older_than_days = -1), "older_than_days")
  expect_error(taxafetch_clear_cache(older_than_days = "a"), "older_than_days")
  expect_error(taxafetch_clear_cache(dry_run = "yes"), "dry_run")
})

test_that("taxafetch_clear_cache reports and no-ops on an empty/nonexistent cache dir", {
  d <- tempfile("empty_cache_")
  expect_message(out <- taxafetch_clear_cache(cache_dir = d), "no cache files found")
  expect_equal(nrow(out), 0L)
})

test_that("taxafetch_clear_cache dry_run reports the matching files without deleting", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f1 <- file.path(d, "0000000-000000000000000.zip"); writeLines("x", f1)
  f2 <- file.path(d, "gbif_dl_1k_s1_g1_2000_meta.rds"); saveRDS(list(), f2)
  f3 <- file.path(d, "not_a_cache_file.txt"); writeLines("y", f3)

  out <- taxafetch_clear_cache(cache_dir = d, dry_run = TRUE)
  expect_setequal(basename(out$path), c(basename(f1), basename(f2)))
  expect_true(file.exists(f1))
  expect_true(file.exists(f2))
  expect_true(file.exists(f3))
})

test_that("taxafetch_clear_cache(dry_run = FALSE) actually deletes matching files", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f1 <- file.path(d, "0000000-000000000000000.zip"); writeLines("x", f1)
  f2 <- file.path(d, "gbif_fetch_1k_s1_g1_2000_l10.rds"); saveRDS(list(), f2)

  out <- taxafetch_clear_cache(cache_dir = d, dry_run = FALSE)
  expect_equal(nrow(out), 2L)
  expect_false(file.exists(f1))
  expect_false(file.exists(f2))
})

test_that("taxafetch_clear_cache(older_than_days=) only targets stale files", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  old_f <- file.path(d, "old.zip"); writeLines("x", old_f)
  Sys.setFileTime(old_f, Sys.time() - 100 * 86400)
  new_f <- file.path(d, "new.zip"); writeLines("y", new_f)

  out <- taxafetch_clear_cache(cache_dir = d, older_than_days = 30, dry_run = FALSE)
  expect_equal(basename(out$path), "old.zip")
  expect_false(file.exists(old_f))
  expect_true(file.exists(new_f))
})

test_that("taxafetch_clear_cache reports a no-match message when older_than_days excludes everything", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "fresh.zip"))

  expect_message(
    out <- taxafetch_clear_cache(cache_dir = d, older_than_days = 9999, dry_run = TRUE),
    "no cache files match"
  )
  expect_equal(nrow(out), 0L)
})

# list_cache_files() itself is tested generically in TaxaTools; these two
# tests only pin down TaxaFetch's OWN pattern set (.taxafetch_cache_patterns).

test_that(".taxafetch_cache_patterns recognizes every real TaxaFetch cache file shape", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "0000000-000000000000000.zip"))
  writeLines("x", file.path(d, "gbif_dl_1k_s1_g1_2000_meta.rds"))
  writeLines("x", file.path(d, "gbif_fetch_1k_s1_g1_2000_l10.rds"))
  writeLines("x", file.path(d, "12345.geojson"))
  writeLines("x", file.path(d, "openalex_cache_abc123.rds"))
  writeLines("x", file.path(d, "not_cache.txt"))
  writeLines("x", file.path(d, "random_other.rds"))

  inv <- TaxaTools::list_cache_files(d, TaxaFetch:::.taxafetch_cache_patterns)
  expect_setequal(
    basename(inv$path),
    c("0000000-000000000000000.zip", "gbif_dl_1k_s1_g1_2000_meta.rds",
      "gbif_fetch_1k_s1_g1_2000_l10.rds", "12345.geojson", "openalex_cache_abc123.rds")
  )
})

# =============================================================================
# orphans_only (2026-09-03) -- "keep the most recent cache per query, remove
# only stale leftovers never cleaned up by a pre-fix overwrite = TRUE run"
# =============================================================================

test_that("orphans_only validates its argument", {
  expect_error(taxafetch_clear_cache(orphans_only = "yes"), "orphans_only")
  expect_error(taxafetch_clear_cache(orphans_only = NA), "orphans_only")
})

test_that(".taxafetch_referenced_zips reads zip_path out of every meta.rds", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  z1 <- file.path(d, "AAA.zip"); writeLines("x", z1)
  z2 <- file.path(d, "BBB.zip"); writeLines("x", z2)
  saveRDS(list(dl_key = "AAA", zip_path = z1, timestamp = Sys.time()),
          file.path(d, "gbif_dl_1_meta.rds"))
  saveRDS(list(dl_key = "BBB", zip_path = z2, timestamp = Sys.time()),
          file.path(d, "gbif_dl_2_meta.rds"))

  refs <- TaxaFetch:::.taxafetch_referenced_zips(d)
  expect_setequal(basename(refs), c("AAA.zip", "BBB.zip"))
})

test_that("orphans_only removes only a zip no current meta.rds points to", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)

  # One query: an orphaned OLD zip (superseded, un-cleaned pre-fix leftover)
  # plus the CURRENT zip its meta.rds actually points to.
  old_zip <- file.path(d, "OLD.zip"); writeLines("x", old_zip)
  new_zip <- file.path(d, "NEW.zip"); writeLines("x", new_zip)
  saveRDS(list(dl_key = "NEW", zip_path = new_zip, timestamp = Sys.time()),
          file.path(d, "gbif_dl_1k_s1_g1_2000_meta.rds"))

  # A second, unrelated query, fully current (no orphan).
  other_zip <- file.path(d, "OTHER.zip"); writeLines("x", other_zip)
  saveRDS(list(dl_key = "OTHER", zip_path = other_zip, timestamp = Sys.time()),
          file.path(d, "gbif_dl_2k_s2_g2_2000_meta.rds"))

  out <- taxafetch_clear_cache(cache_dir = d, orphans_only = TRUE, dry_run = TRUE)
  expect_equal(basename(out$path), "OLD.zip")

  taxafetch_clear_cache(cache_dir = d, orphans_only = TRUE, dry_run = FALSE)
  expect_false(file.exists(old_zip))
  expect_true(file.exists(new_zip))
  expect_true(file.exists(other_zip))
  # meta.rds files themselves are never touched by orphans_only.
  expect_true(file.exists(file.path(d, "gbif_dl_1k_s1_g1_2000_meta.rds")))
  expect_true(file.exists(file.path(d, "gbif_dl_2k_s2_g2_2000_meta.rds")))
})

test_that("orphans_only never targets checkpoint or geojson files", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  ckpt <- file.path(d, "gbif_fetch_1k_s1_g1_2000_l10.rds"); saveRDS(list(), ckpt)
  geo  <- file.path(d, "12345.geojson"); writeLines("x", geo)
  writeLines("x", file.path(d, "CURRENT.zip"))
  saveRDS(list(dl_key = "CURRENT", zip_path = file.path(d, "CURRENT.zip"), timestamp = Sys.time()),
          file.path(d, "gbif_dl_1k_s1_g1_2000_meta.rds"))

  expect_message(
    out <- taxafetch_clear_cache(cache_dir = d, orphans_only = TRUE, dry_run = TRUE),
    "no orphaned zips found"
  )
  expect_equal(nrow(out), 0L)
  expect_true(file.exists(ckpt))
  expect_true(file.exists(geo))
})

test_that("orphans_only reports nothing to remove when every zip is current", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  z <- file.path(d, "AAA.zip"); writeLines("x", z)
  saveRDS(list(dl_key = "AAA", zip_path = z, timestamp = Sys.time()),
          file.path(d, "gbif_dl_1_meta.rds"))

  expect_message(
    out <- taxafetch_clear_cache(cache_dir = d, orphans_only = TRUE, dry_run = TRUE),
    "no orphaned zips found"
  )
  expect_equal(nrow(out), 0L)
  expect_true(file.exists(z))
})
