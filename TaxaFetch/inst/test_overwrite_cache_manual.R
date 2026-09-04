# ==============================================================================
# test_overwrite_cache_manual.R
# TaxaFetch -- manual, interactive live test of download_gbif_occurrences()'s
# overwrite/cache mechanics (2026-09-03 orphan-cleanup + confirmation-prompt fix)
#
# RUN THIS FROM AN INTERACTIVE R SESSION (RStudio console, or
# `source()`-ed from one) -- NOT via a bare `Rscript`. interactive() reflects
# whether the R *process* is interactive, not how this file was invoked, so
# source()-ing it from RStudio is fine; a plain `Rscript
# test_overwrite_cache_manual.R` is not, since it will skip the confirmation
# prompt entirely (the documented, correct non-interactive behavior) and you
# won't see what you're trying to try out.
#
# What this does:
#   1. Downloads a small, real GBIF result into a DEDICATED, disposable test
#      cache directory (not your real ~/Library/Caches TaxaFetch cache --
#      nothing here touches the 23GB you already have).
#   2. Re-runs with overwrite = FALSE to confirm the reuse path is unaffected.
#   3. Re-runs with overwrite = TRUE -- THIS is the interesting part. You
#      should be shown the cached zip's date/size and asked whether to
#      overwrite it or keep it.
#   4. Checks that exactly one zip is left in the cache dir afterward (the
#      actual bug fix: no orphaned old zip).
#
# Needs real GBIF credentials (GBIF_USER/GBIF_PWD/GBIF_EMAIL in ~/.Renviron)
# -- confirmed already set in this environment. Each fresh-download run
# submits a real async GBIF request and polls until it's ready; this
# typically takes anywhere from several seconds to a couple of minutes
# depending on GBIF's queue, not instant.
# ==============================================================================

library(TaxaFetch)

# --- 1. A dedicated, disposable cache directory for this test only ----------
test_cache_dir <- file.path(Sys.getenv("HOME"), "taxafetch_overwrite_test_cache")
dir.create(test_cache_dir, showWarnings = FALSE)
cat("Test cache dir:", test_cache_dir, "\n")

# --- 2. A deliberately tiny search area + narrow year range ------------------
# The bbox below is a ~0.02-degree box (a few city blocks) around Santa
# Barbara harbor -- small geometry keeps the download tiny and fast
# regardless of which taxon key is used. Adjust lat/lon below if this comes
# back with 0 records for you.
geometry <- TaxaFetch::make_bbox_wkt(lat = 34.408, lon = -119.843, radius_deg = 0.02)

keys <- 212L   # Aves (birds) -- broad taxonomically, but the tiny bbox above
               # is what actually keeps this small, not the taxon choice.

cat("\n=== Run 1: fresh download (nothing cached yet) ===\n")
occ1 <- download_gbif_occurrences(
  keys       = keys,
  geometry   = geometry,
  year_range = "2023,2023",
  cache_dir  = test_cache_dir,
  overwrite  = FALSE
)
cat(sprintf("Run 1: %d records, download_key = %s\n", nrow(occ1), attr(occ1, "download_key")))
cat("Files in test cache dir after run 1:\n")
print(list.files(test_cache_dir))

cat("\n=== Run 2: identical args, overwrite = FALSE (should just reuse, no new download) ===\n")
occ2 <- download_gbif_occurrences(
  keys       = keys,
  geometry   = geometry,
  year_range = "2023,2023",
  cache_dir  = test_cache_dir,
  overwrite  = FALSE
)
stopifnot(identical(attr(occ1, "download_key"), attr(occ2, "download_key")))
cat("PASS: run 2 reused the same cached download_key, no fresh download.\n")

cat("\n=== Run 3: overwrite = TRUE -- THIS is the one to watch ===\n")
cat("You should be shown the cached zip's date/size and asked to Overwrite or Keep.\n")
cat("Pick 'Overwrite' this time.\n\n")
occ3 <- download_gbif_occurrences(
  keys       = keys,
  geometry   = geometry,
  year_range = "2023,2023",
  cache_dir  = test_cache_dir,
  overwrite  = TRUE
)
cat(sprintf("\nRun 3: %d records, download_key = %s\n", nrow(occ3), attr(occ3, "download_key")))
cat("Files in test cache dir after run 3:\n")
print(list.files(test_cache_dir))

# --- 3. Verify the orphan-cleanup fix: exactly one zip should remain --------
n_zips <- length(list.files(test_cache_dir, pattern = "\\.zip$"))
cat(sprintf("\nZip files remaining in test cache dir: %d (should be 1, not 2)\n", n_zips))
if (n_zips == 1L) {
  cat("PASS: the old cached zip was cleaned up -- no orphan left behind.\n")
} else {
  cat("UNEXPECTED -- inspect test_cache_dir manually:\n")
  print(list.files(test_cache_dir, full.names = TRUE))
}

cat("\n=== Optional: try the 'Keep' branch too ===\n")
cat("Re-run the Run 3 block above again, but pick 'Keep the cached zip instead'\n")
cat("at the prompt. You should see NO 'submitting GBIF download request' message,\n")
cat("and list.files(test_cache_dir) should be unchanged.\n")

# --- 4. Cleanup when you're done ---------------------------------------------
cat("\nWhen you're done, clean up with:\n")
cat(sprintf('  unlink("%s", recursive = TRUE)\n', test_cache_dir))
