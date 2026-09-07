# test-taxalikely_clear_cache.R
# Tests for taxalikely_clear_cache() and its shared internal inventory helper.
# Fully offline -- everything operates on tempfile() directories.

test_that("taxalikely_clear_cache validates its arguments", {
  expect_error(taxalikely_clear_cache(cache_dir = 1L), "cache_dir")
  expect_error(taxalikely_clear_cache(older_than_days = -1), "older_than_days")
  expect_error(taxalikely_clear_cache(older_than_days = "a"), "older_than_days")
  expect_error(taxalikely_clear_cache(dry_run = "yes"), "dry_run")
})

test_that("taxalikely_clear_cache reports and no-ops on an empty/nonexistent cache dir", {
  d <- tempfile("empty_cache_")
  expect_message(out <- taxalikely_clear_cache(cache_dir = d), "no cache files found")
  expect_equal(nrow(out), 0L)
})

test_that("taxalikely_clear_cache dry_run reports the matching files without deleting", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f1 <- file.path(d, "Gadus_MiFishU_l130_210_d_meta.rds")
  saveRDS(list(), f1)
  f2 <- file.path(d, "coverage_genus_12S_dX_n412_s4714_l100_600_v2_ckpt.rds")
  saveRDS(list(), f2)
  f3 <- file.path(d, "not_a_cache_file.txt")
  writeLines("y", f3)

  out <- taxalikely_clear_cache(cache_dir = d, dry_run = TRUE)
  expect_setequal(basename(out$path), c(basename(f1), basename(f2)))
  expect_true(file.exists(f1))
  expect_true(file.exists(f2))
  expect_true(file.exists(f3))
})

test_that("taxalikely_clear_cache(dry_run = FALSE) actually deletes matching files", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  f1 <- file.path(d, "Gadus_MiFishU_l130_210_d_meta.rds")
  saveRDS(list(), f1)
  f2 <- file.path(d, "coverage_genus_12S_dX_n412_s4714_l100_600_v2_ckpt.rds")
  saveRDS(list(), f2)

  out <- taxalikely_clear_cache(cache_dir = d, dry_run = FALSE)
  expect_equal(nrow(out), 2L)
  expect_false(file.exists(f1))
  expect_false(file.exists(f2))
})

test_that("taxalikely_clear_cache(older_than_days=) only targets stale files", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  old_f <- file.path(d, "Old_taxon_12S_l100_600_d_meta.rds")
  saveRDS(list(), old_f)
  Sys.setFileTime(old_f, Sys.time() - 200 * 86400)
  new_f <- file.path(d, "New_taxon_12S_l100_600_d_meta.rds")
  saveRDS(list(), new_f)

  out <- taxalikely_clear_cache(cache_dir = d, older_than_days = 90, dry_run = FALSE)
  expect_equal(basename(out$path), basename(old_f))
  expect_false(file.exists(old_f))
  expect_true(file.exists(new_f))
})

# list_cache_files() itself is tested generically in TaxaTools; this test
# only pins down TaxaLikely's OWN pattern set (.taxalikely_cache_patterns).

test_that(".taxalikely_cache_patterns recognizes every real TaxaLikely cache file shape", {
  d <- tempfile("cache_")
  dir.create(d)
  on.exit(unlink(d, recursive = TRUE), add = TRUE)
  writeLines("x", file.path(d, "Gadus_MiFishU_l130_210_d_meta.rds"))
  writeLines("x", file.path(d, "coverage_genus_12S_dX_n412_s4714_l100_600_v2_ckpt.rds"))
  writeLines("x", file.path(d, "not_cache.txt"))
  writeLines("x", file.path(d, "unrelated.rds"))

  inv <- TaxaTools::list_cache_files(d, TaxaLikely:::.taxalikely_cache_patterns)
  expect_setequal(
    basename(inv$path),
    c(
      "Gadus_MiFishU_l130_210_d_meta.rds",
      "coverage_genus_12S_dX_n412_s4714_l100_600_v2_ckpt.rds"
    )
  )
})
