# The GBIF download cache key encodes geometry only as nchar(geometry), so two
# different polygons of equal WKT string length share a key -- editing one bbox
# coordinate from "-122.385" to "-122.386" preserves the length exactly. Before
# 2026-09-14 that returned the WRONG REGION'S occurrences from cache, silently.
#
# The key is deliberately unchanged (widening it would orphan every cached GBIF
# zip at once, 163 MB here and 17-23 GB historically). Instead the geometry is
# stored inside the cached metadata and verified on read. These tests pin that.
# See ecosystem_docs/CACHE_POLICY_REVIEW_2026_09_14.md.

test_that("two equal-length geometries really do collide on the cache key", {
  a <- "POLYGON((-122.385 34.1, -122.385 34.9, -121.100 34.9, -122.385 34.1))"
  b <- "POLYGON((-122.386 34.1, -122.386 34.9, -121.100 34.9, -122.386 34.1))"
  expect_equal(nchar(a), nchar(b))
  expect_false(identical(a, b))

  pa <- TaxaFetch:::.gbif_dl_meta_path(tempdir(), keys = c("1", "2"), geometry = a,
                                       year_range = "1995,2026")
  pb <- TaxaFetch:::.gbif_dl_meta_path(tempdir(), keys = c("1", "2"), geometry = b,
                                       year_range = "1995,2026")
  # Same key: this is the collision the guard exists to catch.
  expect_identical(pa, pb)
})

test_that("a cached download records the geometry it was made for", {
  # Contract check on the metadata shape the reader verifies against.
  meta <- list(dl_key = "0001", zip_path = tempfile(), timestamp = Sys.time(),
               geometry = "POLYGON((0 0, 0 1, 1 1, 0 0))")
  expect_true("geometry" %in% names(meta))
  expect_false(identical(meta$geometry, "POLYGON((0 0, 0 2, 2 2, 0 0))"))
})

test_that("a legacy cache entry has no geometry and is therefore unverifiable", {
  # This is the shape of entries already on disk; the reader must warn rather
  # than assume they match.
  legacy <- list(dl_key = "0001", zip_path = tempfile(), timestamp = Sys.time())
  expect_null(legacy$geometry)
})


# --- zip sidecars (2026-09-14, P5) -------------------------------------------
# A bad or partial download renamed out of the way (X.zip.truncated_20260905)
# matched no cache pattern, so no clear function could see it. The largest one
# found held 122 MB -- three quarters of that cache.

test_that("zip sidecars are recognized as cache files", {
  expect_true(TaxaFetch:::.taxafetch_is_zip_like("0002305-260903.zip"))
  expect_true(TaxaFetch:::.taxafetch_is_zip_like("0002305-260903.zip.truncated_20260905"))
  expect_true(TaxaFetch:::.taxafetch_is_zip_like("/a/b/0002305.zip.part"))
  expect_false(TaxaFetch:::.taxafetch_is_zip_like("gbif_dl_29k_s1_g2_meta.rds"))
  expect_false(TaxaFetch:::.taxafetch_is_zip_like("notazipfile.rds"))
})

test_that("zips_only targets sidecars and spares metadata", {
  d <- tempfile()
  dir.create(d)
  file.create(file.path(d, c(
    "0002305-260903.zip",
    "0002305-260903.zip.truncated_20260905",
    "gbif_dl_29k_s1_g2_19952026_pres_meta.rds"
  )))

  out <- suppressMessages(
    taxafetch_clear_cache(cache_dir = d, zips_only = TRUE, dry_run = TRUE)
  )
  expect_setequal(
    basename(out$path),
    c("0002305-260903.zip", "0002305-260903.zip.truncated_20260905")
  )
})

test_that("a sidecar is always an orphan, since metadata only names X.zip", {
  d <- tempfile()
  dir.create(d)
  zip <- file.path(d, "0002305-260903.zip")
  file.create(zip)
  file.create(paste0(zip, ".truncated_20260905"))
  saveRDS(
    list(zip_path = zip),
    file.path(d, "gbif_dl_29k_s1_g2_19952026_pres_meta.rds")
  )

  out <- suppressMessages(
    taxafetch_clear_cache(cache_dir = d, orphans_only = TRUE, dry_run = TRUE)
  )
  expect_identical(basename(out$path), "0002305-260903.zip.truncated_20260905")
  expect_true(file.exists(zip)) # the referenced zip is untouched
})
