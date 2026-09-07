# test-download_gbif_occurrences.R
# Tests for download_gbif_occurrences().
#
# Strategy:
#   - Input validation (credentials, keys, geometry, year_range): no network needed.
#   - issue -> issues rename: exercised end to end via a pre-populated cache hit
#     (synthetic SIMPLE_CSV zip + matching meta.rds), so no rgbif/network calls
#     are made. Regression test for a Session 129/131 finding: a prior session
#     incorrectly claimed this rename was never implemented; it was, and always
#     had been -- this test pins the behavior down so that claim can't silently
#     recur.

library(testthat)

skip_if_not_installed("rgbif")
skip_if_not_installed("zip")

# =============================================================================
# Fixtures
# =============================================================================

# Build a minimal SIMPLE_CSV-shaped zip: tab-delimited, "issue" column
# (singular, matching GBIF's real SIMPLE_CSV export), inside a zip whose
# member file name does not itself contain "occurrence" (exercises the
# fallback file-detection branch in .read_gbif_zip() as a side effect).
# Uses zip::zip()'s `root` argument to store a relative entry name without
# a setwd() dance, and to avoid depending on an external `zip` binary.
.make_fake_gbif_zip <- function(dir) {
  csv_name <- "0000000-000000000000000.csv"
  writeLines(
    c(
      paste(
        c(
          "gbifID", "taxonKey", "speciesKey", "kingdom", "phylum",
          "class", "order", "family", "genus", "species",
          "decimalLatitude", "decimalLongitude", "basisOfRecord",
          "issue", "occurrenceStatus", "year", "month", "day"
        ),
        collapse = "\t"
      ),
      paste(
        c(
          "1", "100", "100", "Animalia", "Chordata", "Actinopterygii",
          "Gadiformes", "Gadidae", "Gadus", "Gadus morhua",
          "60.0", "2.0", "HUMAN_OBSERVATION", "", "PRESENT",
          "2020", "1", "1"
        ),
        collapse = "\t"
      )
    ),
    file.path(dir, csv_name)
  )
  zip_path <- file.path(dir, "0000000-000000000000000.zip")
  zip::zip(zip_path, csv_name, root = dir)
  zip_path
}

# Same fixture shape, but named after a caller-supplied dl_key -- used to
# mock rgbif::occ_download_get()'s real behavior (writing "<dl_key>.zip"
# into the destination directory) for the overwrite/orphan-cleanup tests.
.make_fake_gbif_zip_named <- function(dir, dl_key) {
  csv_name <- paste0(dl_key, ".csv")
  writeLines(
    c(
      paste(
        c(
          "gbifID", "taxonKey", "speciesKey", "kingdom", "phylum",
          "class", "order", "family", "genus", "species",
          "decimalLatitude", "decimalLongitude", "basisOfRecord",
          "issue", "occurrenceStatus", "year", "month", "day"
        ),
        collapse = "\t"
      ),
      paste(
        c(
          "2", "100", "100", "Animalia", "Chordata", "Actinopterygii",
          "Gadiformes", "Gadidae", "Gadus", "Gadus morhua",
          "61.0", "3.0", "HUMAN_OBSERVATION", "", "PRESENT",
          "2021", "1", "1"
        ),
        collapse = "\t"
      )
    ),
    file.path(dir, csv_name)
  )
  zip_path <- file.path(dir, paste0(dl_key, ".zip"))
  zip::zip(zip_path, csv_name, root = dir)
  zip_path
}

# =============================================================================
# Input validation (no network)
# =============================================================================

test_that("stops with informative message when GBIF credentials are missing", {
  expect_error(
    download_gbif_occurrences(
      keys = 1L, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))",
      gbif_user = "", gbif_pwd = "", gbif_email = ""
    ),
    regexp = "missing GBIF credentials"
  )
})

test_that("stops if keys is empty after NA removal", {
  expect_error(
    download_gbif_occurrences(
      keys = NA_integer_, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))",
      gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
    ),
    regexp = "empty"
  )
})

test_that("stops on malformed year_range", {
  expect_error(
    download_gbif_occurrences(
      keys = 1L, geometry = "POLYGON((0 0,0 1,1 1,1 0,0 0))",
      year_range = "not-a-range",
      gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
    ),
    regexp = "year_range"
  )
})

# =============================================================================
# issue -> issues rename (cache-hit path, no network)
# =============================================================================

test_that("renames SIMPLE_CSV's 'issue' column to 'issues' on import", {
  cache_dir <- tempfile("gbif_test_")
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)
  zip_path <- .make_fake_gbif_zip(cache_dir)

  keys <- 100L
  geometry <- "POLYGON((0 0,0 1,1 1,1 0,0 0))"
  year_range <- "2000,2024"

  meta_path <- TaxaFetch:::.gbif_dl_meta_path(cache_dir, keys, geometry, year_range)
  saveRDS(
    list(dl_key = "0000000-000000000000000", zip_path = zip_path, timestamp = Sys.time()),
    meta_path
  )

  out <- download_gbif_occurrences(
    keys = keys,
    geometry = geometry,
    year_range = year_range,
    cache_dir = cache_dir,
    overwrite = FALSE,
    gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
  )

  expect_true("issues" %in% names(out))
  expect_false("issue" %in% names(out))
})

# =============================================================================
# overwrite = TRUE: orphan cleanup + cache summary (2026-09-03)
# =============================================================================

test_that("overwrite = TRUE in a non-interactive session removes the old cached zip after a fresh download", {
  cache_dir <- tempfile("gbif_test_")
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)

  old_zip <- .make_fake_gbif_zip(cache_dir)
  keys <- 100L
  geometry <- "POLYGON((0 0,0 1,1 1,1 0,0 0))"
  year_range <- "2000,2024"
  meta_path <- TaxaFetch:::.gbif_dl_meta_path(cache_dir, keys, geometry, year_range)
  saveRDS(
    list(dl_key = "0000000-000000000000000", zip_path = old_zip, timestamp = Sys.time() - 86400),
    meta_path
  )
  expect_true(file.exists(old_zip))

  new_dl_key <- "1111111-999999999999999"
  testthat::local_mocked_bindings(
    occ_download = function(...) new_dl_key,
    occ_download_wait = function(...) invisible(NULL),
    occ_download_get = function(key, path, overwrite = TRUE) {
      .make_fake_gbif_zip_named(path, key)
      invisible(NULL)
    },
    .package = "rgbif"
  )

  out <- download_gbif_occurrences(
    keys = keys, geometry = geometry, year_range = year_range,
    cache_dir = cache_dir, overwrite = TRUE,
    gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
  )

  expect_false(file.exists(old_zip))
  new_zip <- file.path(cache_dir, paste0(new_dl_key, ".zip"))
  expect_true(file.exists(new_zip))
  meta <- readRDS(meta_path)
  expect_equal(meta$dl_key, new_dl_key)
  expect_equal(attr(out, "download_key"), new_dl_key)
})

# The interactive confirmation prompt itself (`interactive()` + `utils::menu()`)
# is not covered by an automated test: `interactive()` is a .Primitive, not an
# ordinary closure, so it cannot be reliably intercepted by
# testthat::local_mocked_bindings() the way an ordinary base/utils function can
# -- confirmed directly (a mocked TRUE return silently had no effect on the
# real call path). The non-interactive orphan-cleanup path above already
# covers the actual bug fix (the old zip is never left behind); the prompt's
# own UI behavior (showing the cached zip's date/size, honoring both menu
# choices) is exercised by hand per this feature's plan verification step --
# run the same `overwrite = TRUE` repeat call from a real interactive R
# console and confirm both choices behave as documented in `@param overwrite`.

test_that("download_gbif_occurrences reports the total cache size after a run", {
  cache_dir <- tempfile("gbif_test_")
  dir.create(cache_dir, recursive = TRUE)
  on.exit(unlink(cache_dir, recursive = TRUE), add = TRUE)
  zip_path <- .make_fake_gbif_zip(cache_dir)

  keys <- 100L
  geometry <- "POLYGON((0 0,0 1,1 1,1 0,0 0))"
  year_range <- "2000,2024"
  meta_path <- TaxaFetch:::.gbif_dl_meta_path(cache_dir, keys, geometry, year_range)
  saveRDS(
    list(dl_key = "0000000-000000000000000", zip_path = zip_path, timestamp = Sys.time()),
    meta_path
  )

  expect_message(
    download_gbif_occurrences(
      keys = keys, geometry = geometry, year_range = year_range,
      cache_dir = cache_dir, overwrite = FALSE,
      gbif_user = "u", gbif_pwd = "p", gbif_email = "e@example.com"
    ),
    "TaxaFetch cache: 2 file"
  )
})

# ==============================================================================
# Zip integrity (2026-09-04). A truncated GBIF download used to be cached as if
# complete, then fail at import on EVERY subsequent run -- a poisoned cache with
# no hint that the cache was the problem. Real case: 127,733,417 of GBIF's
# declared 130,577,434 bytes.
# ==============================================================================

.make_real_zip <- function(n = 3L) {
  d <- file.path(tempdir(), paste0("zipsrc_", as.integer(runif(1, 1, 1e9))))
  dir.create(d, showWarnings = FALSE)
  csv <- file.path(d, "occ.csv")
  utils::write.csv(data.frame(a = seq_len(n), b = strrep("x", 200)), csv,
    row.names = FALSE
  )
  z <- file.path(d, "good.zip")
  old <- setwd(d)
  on.exit(setwd(old), add = TRUE)
  utils::zip(z, "occ.csv", flags = "-q")
  z
}

test_that("a complete zip passes both the structural and the size test", {
  skip_on_cran()
  z <- .make_real_zip()
  skip_if(!file.exists(z), "system zip unavailable")
  chk <- TaxaFetch:::.gbif_zip_intact(z)
  expect_true(chk$ok)
  expect_true(is.na(chk$reason))
  expect_true(TaxaFetch:::.gbif_zip_intact(z, expected_size = file.info(z)$size)$ok)
})

test_that("a TRUNCATED zip is rejected -- the real 2026-09-04 failure", {
  skip_on_cran()
  z <- .make_real_zip()
  skip_if(!file.exists(z), "system zip unavailable")
  full <- file.info(z)$size
  # Chop the tail, exactly as an interrupted transfer does: the local header
  # survives, the central directory does not.
  raw <- readBin(z, "raw", n = full)
  trunc <- file.path(dirname(z), "truncated.zip")
  writeBin(raw[seq_len(floor(full * 0.9))], trunc)
  expect_equal(
    readBin(trunc, "raw", n = 4L),
    as.raw(c(0x50, 0x4b, 0x03, 0x04))
  ) # still looks like a zip
  chk <- TaxaFetch:::.gbif_zip_intact(trunc)
  expect_false(chk$ok)
  expect_match(chk$reason, "truncated|corrupt|unreadable")
  # and the size test names the shortfall when GBIF's figure is known
  chk2 <- TaxaFetch:::.gbif_zip_intact(trunc, expected_size = full)
  expect_false(chk2$ok)
  expect_match(chk2$reason, "size mismatch")
  expect_match(chk2$reason, "short by")
})

test_that("missing and empty files are rejected without erroring", {
  expect_false(TaxaFetch:::.gbif_zip_intact(NULL)$ok)
  expect_false(TaxaFetch:::.gbif_zip_intact(file.path(tempdir(), "nope.zip"))$ok)
  e <- file.path(tempdir(), "empty.zip")
  file.create(e)
  expect_match(TaxaFetch:::.gbif_zip_intact(e)$reason, "empty")
})

test_that("a wrecked central directory is rejected even at the right size", {
  skip_on_cran()
  z <- .make_real_zip(50L)
  skip_if(!file.exists(z), "system zip unavailable")
  full <- file.info(z)$size
  raw <- readBin(z, "raw", n = full)
  raw[(full - 21L):full] <- as.raw(0) # the whole 22-byte EOCD record
  bad <- file.path(dirname(z), "same_size_corrupt.zip")
  writeBin(raw, bad)
  expect_equal(file.info(bad)$size, full) # the size test alone would pass it
  expect_false(TaxaFetch:::.gbif_zip_intact(bad, expected_size = full)$ok)
})

test_that("payload corruption is NOT this check's job -- extraction's CRC catches it", {
  # Documents the real division of labour, established by probing both paths
  # (2026-09-04). .gbif_zip_intact() reads only the central DIRECTORY, so it
  # catches truncation and directory damage -- the failure that actually
  # happens, cheaply, without decompressing ~868 MB on every run. Corruption
  # inside the compressed payload leaves the directory perfectly readable and
  # passes this check; it is caught moments later by .read_gbif_zip(), because
  # unzip verifies each entry's CRC on EXTRACTION. Nothing reaches the data
  # silently; the two steps together are what make that true, so do not
  # "strengthen" this check into a full extraction and do not weaken the
  # extraction step assuming this one already validated the bytes.
  skip_on_cran()
  z <- .make_real_zip(50L)
  skip_if(!file.exists(z), "system zip unavailable")
  full <- file.info(z)$size
  raw <- readBin(z, "raw", n = full)
  raw[100:150] <- as.raw(0) # middle of the compressed data
  bad <- file.path(dirname(z), "payload_corrupt.zip")
  writeBin(raw, bad)
  expect_true(TaxaFetch:::.gbif_zip_intact(bad, expected_size = full)$ok)
  # NB signalled as a WARNING ("error -3 in extracting from zip file"), not an
  # error -- so a caller that ignores warnings would sail past it. .read_gbif_zip()
  # checks the extracted file afterwards, which is what makes this safe.
  expect_warning(
    utils::unzip(bad, exdir = file.path(dirname(z), "extract_here")),
    "extracting"
  )
})

test_that(".gbif_declared_size returns NULL rather than erroring when GBIF is unreachable", {
  local_mocked_bindings(
    occ_download_meta = function(...) stop("network down"),
    .package = "rgbif"
  )
  expect_null(TaxaFetch:::.gbif_declared_size("0000000-000000000000000"))
})

test_that(".read_gbif_zip() turns a failed extraction into an error, not a short table", {
  skip_on_cran()
  z <- .make_real_zip(50L)
  skip_if(!file.exists(z), "system zip unavailable")
  full <- file.info(z)$size
  raw <- readBin(z, "raw", n = full)
  raw[100:150] <- as.raw(0) # payload corrupt, directory fine
  bad <- file.path(dirname(z), "payload_for_read.zip")
  writeBin(raw, bad)
  # passes the cheap directory check ...
  expect_true(TaxaFetch:::.gbif_zip_intact(bad)$ok)
  # ... and is stopped here rather than silently returning fewer rows
  expect_error(TaxaFetch:::.read_gbif_zip(bad), "corrupt, not merely truncated")
})

test_that("overwrite = TRUE does not ASK when the cached zip is unusable", {
  # There is no trade-off to weigh once the cache fails verification, so the
  # menu is skipped and the file replaced. Regression for the prompt rewrite
  # of 2026-09-05, which the package's own author could not read confidently.
  cache_dir <- file.path(tempdir(), paste0("gbif_prompt_", as.integer(runif(1, 1, 1e9))))
  dir.create(cache_dir, recursive = TRUE)
  key <- "0000000-000000000000000"
  zp <- file.path(cache_dir, paste0(key, ".zip"))
  writeBin(as.raw(c(0x50, 0x4b, 0x03, 0x04, rep(0, 40))), zp) # truncated
  meta <- TaxaFetch:::.gbif_dl_meta_path(cache_dir,
    keys = 1L, geometry = "POLYGON",
    year_range = "2000,2024"
  )
  saveRDS(list(dl_key = key, zip_path = zp, timestamp = Sys.time()), meta)

  called <- new.env()
  called$menu <- FALSE
  local_mocked_bindings(
    menu = function(...) {
      called$menu <- TRUE
      1L
    },
    .package = "utils"
  )
  local_mocked_bindings(
    occ_download_meta = function(...) stop("offline"),
    occ_download = function(...) stop("STOPPED_BEFORE_REQUEST"),
    .package = "rgbif"
  )
  # Reaches the download stage (i.e. decided to replace) without ever asking.
  expect_error(
    suppressMessages(download_gbif_occurrences(
      keys = 1L, geometry = "POLYGON", year_range = "2000,2024",
      cache_dir = cache_dir, overwrite = TRUE,
      gbif_user = "u", gbif_pwd = "p", gbif_email = "e@x.org"
    )),
    "STOPPED_BEFORE_REQUEST"
  )
  expect_false(called$menu)
})

test_that("a failing cache-size report cannot discard the imported data", {
  # Regression for 2026-09-05: a lazy-load failure inside the purely cosmetic
  # cache report threw away 1,717,250 successfully imported rows at the last
  # step of the function. The report is now advisory only.
  cache_dir <- file.path(tempdir(), paste0("gbif_rep_", as.integer(runif(1, 1, 1e9))))
  dir.create(cache_dir, recursive = TRUE)
  local_mocked_bindings(
    list_cache_files = function(...) stop("lazy-load database is corrupt"),
    .package = "TaxaTools"
  )
  local_mocked_bindings(
    .read_gbif_zip = function(...) {
      data.frame(
        gbifID = 1:3, species = "A a",
        stringsAsFactors = FALSE
      )
    },
    .gbif_zip_intact = function(...) list(ok = TRUE, reason = NA_character_),
    .gbif_declared_size = function(...) NULL
  )
  key <- "0000000-000000000000000"
  zp <- file.path(cache_dir, paste0(key, ".zip"))
  file.create(zp)
  meta <- TaxaFetch:::.gbif_dl_meta_path(cache_dir,
    keys = 1L, geometry = "POLYGON",
    year_range = "2000,2024"
  )
  saveRDS(list(dl_key = key, zip_path = zp, timestamp = Sys.time()), meta)

  expect_warning(
    out <- suppressMessages(download_gbif_occurrences(
      keys = 1L, geometry = "POLYGON", year_range = "2000,2024",
      cache_dir = cache_dir, gbif_user = "u", gbif_pwd = "p",
      gbif_email = "e@x.org"
    )),
    "cache-size report failed"
  )
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 3L) # the data survives
})

test_that("the pre-download summary reports size, records and cache impact", {
  local_mocked_bindings(
    occ_download_meta = function(...) {
      list(
        size = 124.5 * 1024^2,
        totalRecords = 1717250
      )
    },
    .package = "rgbif"
  )
  cd <- file.path(tempdir(), paste0("consent_", as.integer(runif(1, 1, 1e9))))
  dir.create(cd, recursive = TRUE)
  msgs <- capture_messages(
    d <- TaxaFetch:::.gbif_download_consent("KEY", cd, NULL,
      prompt_mb = 50,
      keys = rep(1L, 762)
    )
  )
  txt <- paste(msgs, collapse = "")
  expect_match(txt, "1,717,250") # (a) records
  expect_match(txt, "124.5 MB") # (a) size
  expect_match(txt, "none for this query") # (b) cache state
  expect_match(txt, "no download") # what caching buys
  expect_equal(d, "download") # non-interactive never blocks
})

test_that("an existing cache is named, and replacement is stated plainly", {
  local_mocked_bindings(
    occ_download_meta = function(...) list(size = 124.5 * 1024^2, totalRecords = 10),
    .package = "rgbif"
  )
  cd <- file.path(tempdir(), paste0("consent2_", as.integer(runif(1, 1, 1e9))))
  dir.create(cd, recursive = TRUE)
  z <- file.path(cd, "KEY.zip")
  writeBin(raw(2048), z)
  msgs <- capture_messages(
    d <- TaxaFetch:::.gbif_download_consent("KEY", cd, z, prompt_mb = 50)
  )
  txt <- paste(msgs, collapse = "")
  expect_match(txt, "THIS EXACT query already exists") # (b)
  expect_match(txt, "REPLACES it") # (c)
  # Non-interactive must NOT override an explicit overwrite = TRUE (which is
  # the only way a cached zip reaches this code path).
  expect_equal(d, "download")
})

test_that("small downloads and Inf prompt_mb stay silent about choices", {
  local_mocked_bindings(
    occ_download_meta = function(...) list(size = 2 * 1024^2, totalRecords = 5),
    .package = "rgbif"
  )
  cd <- file.path(tempdir(), paste0("consent3_", as.integer(runif(1, 1, 1e9))))
  dir.create(cd, recursive = TRUE)
  expect_equal(
    suppressMessages(TaxaFetch:::.gbif_download_consent("KEY", cd, NULL, prompt_mb = 50)),
    "download"
  )
})

test_that("NO menu() is ever reached with default allow_prompts = FALSE", {
  # THE regression for 2026-09-05: a menu() inside a function called from a
  # sourced script consumes the remaining SCRIPT LINES as its answers --
  # re-prompting on each and silently swallowing them so they never run. The
  # real incident ate the entire PtConception 18S workflow after the GBIF
  # download; only raw_gbif had been saved. Nothing may block by default.
  cache_dir <- file.path(tempdir(), paste0("noprompt_", as.integer(runif(1, 1, 1e9))))
  dir.create(cache_dir, recursive = TRUE)
  called <- new.env()
  called$menu <- FALSE
  local_mocked_bindings(
    menu = function(...) {
      called$menu <- TRUE
      1L
    },
    .package = "utils"
  )
  local_mocked_bindings(
    list_cache_files = function(...) {
      data.frame(
        path = file.path(cache_dir, "big.zip"), size_mb = 99999,
        mtime = Sys.time(), stringsAsFactors = FALSE
      )
    },
    .package = "TaxaTools"
  )
  local_mocked_bindings(
    .read_gbif_zip = function(...) {
      data.frame(
        gbifID = 1:2, species = "A a",
        stringsAsFactors = FALSE
      )
    },
    .gbif_zip_intact = function(...) list(ok = TRUE, reason = NA_character_),
    .gbif_declared_size = function(...) NULL
  )
  key <- "0000000-000000000000000"
  zp <- file.path(cache_dir, paste0(key, ".zip"))
  file.create(zp)
  meta <- TaxaFetch:::.gbif_dl_meta_path(cache_dir,
    keys = 1L, geometry = "POLYGON",
    year_range = "2000,2024"
  )
  saveRDS(list(dl_key = key, zip_path = zp, timestamp = Sys.time()), meta)

  # A 97 GB cache is far over cache_prompt_mb -- the old code would have asked.
  out <- suppressMessages(download_gbif_occurrences(
    keys = 1L, geometry = "POLYGON", year_range = "2000,2024",
    cache_dir = cache_dir, gbif_user = "u", gbif_pwd = "p", gbif_email = "e@x.org"
  ))
  expect_false(called$menu)
  expect_equal(nrow(out), 2L)
})

test_that("the cache report names the clear commands instead of prompting", {
  cache_dir <- file.path(tempdir(), paste0("cmds_", as.integer(runif(1, 1, 1e9))))
  dir.create(cache_dir, recursive = TRUE)
  local_mocked_bindings(
    list_cache_files = function(...) {
      data.frame(
        path = file.path(cache_dir, "big.zip"), size_mb = 20000,
        mtime = Sys.time(), stringsAsFactors = FALSE
      )
    },
    .package = "TaxaTools"
  )
  local_mocked_bindings(
    .read_gbif_zip = function(...) {
      data.frame(
        gbifID = 1L, species = "A a",
        stringsAsFactors = FALSE
      )
    },
    .gbif_zip_intact = function(...) list(ok = TRUE, reason = NA_character_),
    .gbif_declared_size = function(...) NULL
  )
  key <- "0000000-000000000000000"
  zp <- file.path(cache_dir, paste0(key, ".zip"))
  file.create(zp)
  meta <- TaxaFetch:::.gbif_dl_meta_path(cache_dir,
    keys = 1L, geometry = "POLYGON",
    year_range = "2000,2024"
  )
  saveRDS(list(dl_key = key, zip_path = zp, timestamp = Sys.time()), meta)
  msgs <- capture_messages(download_gbif_occurrences(
    keys = 1L, geometry = "POLYGON", year_range = "2000,2024",
    cache_dir = cache_dir, gbif_user = "u", gbif_pwd = "p", gbif_email = "e@x.org"
  ))
  txt <- paste(msgs, collapse = "")
  expect_match(txt, "taxafetch_clear_cache\\(dry_run = TRUE\\)")
  expect_match(txt, "orphans_only = TRUE")
  expect_match(txt, "19.5 GB") # reported in GB, not 20000 MB
})

test_that("keep_zip = FALSE removes the zip after import but keeps the metadata", {
  cache_dir <- file.path(tempdir(), paste0("keepzip_", as.integer(runif(1, 1, 1e9))))
  dir.create(cache_dir, recursive = TRUE)
  local_mocked_bindings(
    .read_gbif_zip = function(...) {
      data.frame(
        gbifID = 1:4, species = "A a",
        stringsAsFactors = FALSE
      )
    },
    .gbif_zip_intact = function(...) list(ok = TRUE, reason = NA_character_),
    .gbif_declared_size = function(...) NULL
  )
  key <- "0000000-000000000000000"
  zp <- file.path(cache_dir, paste0(key, ".zip"))
  writeBin(raw(4096), zp)
  meta <- TaxaFetch:::.gbif_dl_meta_path(cache_dir,
    keys = 1L, geometry = "POLYGON",
    year_range = "2000,2024"
  )
  saveRDS(list(dl_key = key, zip_path = zp, timestamp = Sys.time()), meta)

  out <- suppressMessages(download_gbif_occurrences(
    keys = 1L, geometry = "POLYGON", year_range = "2000,2024",
    cache_dir = cache_dir, keep_zip = FALSE,
    gbif_user = "u", gbif_pwd = "p", gbif_email = "e@x.org"
  ))
  expect_equal(nrow(out), 4L) # data returned
  expect_false(file.exists(zp)) # zip gone
  expect_true(file.exists(meta)) # key still recoverable
  expect_equal(readRDS(meta)$dl_key, key)
})

test_that("a missing zip re-fetches the SAME prepared key, not a new request", {
  cache_dir <- file.path(tempdir(), paste0("regone_", as.integer(runif(1, 1, 1e9))))
  dir.create(cache_dir, recursive = TRUE)
  key <- "0000000-000000000000000"
  zp <- file.path(cache_dir, paste0(key, ".zip")) # deliberately absent
  meta <- TaxaFetch:::.gbif_dl_meta_path(cache_dir,
    keys = 1L, geometry = "POLYGON",
    year_range = "2000,2024"
  )
  saveRDS(list(dl_key = key, zip_path = zp, timestamp = Sys.time()), meta)
  local_mocked_bindings(
    occ_download = function(...) stop("A NEW REQUEST WAS SUBMITTED"),
    occ_download_get = function(dl_key, path, ...) {
      writeBin(raw(4096), file.path(path, paste0(dl_key, ".zip")))
      invisible(TRUE)
    },
    occ_download_meta = function(...) stop("offline"),
    .package = "rgbif"
  )
  local_mocked_bindings(
    .read_gbif_zip = function(...) {
      data.frame(
        gbifID = 1:2, species = "A a",
        stringsAsFactors = FALSE
      )
    },
    .gbif_zip_intact = function(...) list(ok = TRUE, reason = NA_character_),
    .gbif_declared_size = function(...) NULL
  )
  msgs <- capture_messages(
    out <- download_gbif_occurrences(
      keys = 1L, geometry = "POLYGON", year_range = "2000,2024",
      cache_dir = cache_dir, gbif_user = "u", gbif_pwd = "p", gbif_email = "e@x.org"
    )
  )
  expect_equal(nrow(out), 2L)
  expect_true(any(grepl("no new request", paste(msgs, collapse = ""))))
})

test_that("geometry = NULL is a global download: no pred_within, cache signs g0", {
  # Regression for 2026-09-05: fetch_gbif_occurrences() has supported
  # geometry = NULL since 2026-07 (check_geographic_outliers() needs a species'
  # whole global range), but this backend rejected it -- so routing that call
  # through get_gbif_occurrences() died at the 50-key threshold with
  # "'geometry' must be a single non-empty WKT string".
  seen <- new.env()
  seen$preds <- NULL
  local_mocked_bindings(
    pred_within = function(...) stop("pred_within must NOT be built for a global query"),
    occ_download = function(...) {
      seen$preds <- list(...)
      stop("STOP_AFTER_PREDICATES")
    },
    .package = "rgbif"
  )
  expect_error(
    suppressMessages(download_gbif_occurrences(
      keys = c(1L, 2L), geometry = NULL, year_range = "2000,2024",
      cache_dir = NULL, gbif_user = "u", gbif_pwd = "p", gbif_email = "e@x.org"
    )),
    "STOP_AFTER_PREDICATES"
  )

  # the cache signature must not choke on NULL (nchar(NULL) is integer(0))
  pth <- TaxaFetch:::.gbif_dl_meta_path(tempdir(),
    keys = c(1L, 2L),
    geometry = NULL, year_range = "2000,2024"
  )
  expect_match(basename(pth), "_g0_")

  # and a real WKT still restricts
  expect_error(
    suppressMessages(download_gbif_occurrences(
      keys = 1L, geometry = "POLYGON((0 0,1 0,1 1,0 0))", year_range = "2000,2024",
      cache_dir = NULL, gbif_user = "u", gbif_pwd = "p", gbif_email = "e@x.org"
    )),
    "pred_within must NOT be built"
  )
})
