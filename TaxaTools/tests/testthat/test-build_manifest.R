# Build manifest: detecting that the library a run used is not the library you
# think it used. Every TaxaID package sits at 0.1.0 and is reinstalled
# constantly, so the version string is silent by construction and the Built
# timestamp moves on every harmless rebuild -- hence a code hash.
#
# Verified against REAL installs, not just simulated hashes:
#   rebuild with no source change : Built moved 05:56:58 -> 05:59:33,
#                                   hash 2f887268... unchanged  -> no alarm
#   one-line code change          : hash 2f887268... -> 93bd9e99...  -> alarm
#   revert + reinstall            : hash back to 2f887268...
# and the hash was identical across three separate R processes.

test_that("taxaid_build_manifest records installed and missing packages alike", {
  m <- taxaid_build_manifest(c("TaxaTools", "NoSuchPackageXYZ"))
  expect_equal(nrow(m), 2L)
  expect_true(all(c("package", "version", "built", "code_hash", "installed") %in% names(m)))
  expect_true(m$installed[m$package == "TaxaTools"])
  # A missing package must be PRESENT as a row with installed = FALSE, not
  # dropped -- absence has to be representable or the check cannot report it.
  expect_false(m$installed[m$package == "NoSuchPackageXYZ"])
  expect_true(is.na(m$code_hash[m$package == "NoSuchPackageXYZ"]))
})

test_that(".taxaid_code_hash is stable and package-specific", {
  h1 <- .taxaid_code_hash("TaxaTools")
  h2 <- .taxaid_code_hash("TaxaTools")
  expect_identical(h1, h2)
  expect_match(h1, "^[0-9a-f]{32}$")
  expect_true(is.na(.taxaid_code_hash("NoSuchPackageXYZ")))
})

test_that("check_taxaid_manifest passes when nothing has moved", {
  p <- withr::local_tempfile(fileext = ".rds")
  suppressMessages(write_taxaid_manifest(p, packages = "TaxaTools"))
  r <- suppressMessages(check_taxaid_manifest(p, packages = "TaxaTools"))
  expect_true(r$ok)
  expect_length(r$changed, 0L)
  expect_length(r$missing, 0L)
})

test_that("a CHANGED code hash errors and names the package", {
  p <- withr::local_tempfile(fileext = ".rds")
  m <- suppressMessages(write_taxaid_manifest(p, packages = "TaxaTools"))
  m$code_hash <- "deadbeefdeadbeefdeadbeefdeadbeef"
  saveRDS(m, p)
  expect_error(
    check_taxaid_manifest(p, packages = "TaxaTools"),
    "CHANGED"
  )
  expect_error(check_taxaid_manifest(p, packages = "TaxaTools"), "TaxaTools")
})

test_that("a MISSING package is reported, and reported FIRST", {
  # The dangerous case: in the manifest, gone from the library. A checker that
  # only compares what it finds on both sides cannot see this at all.
  p <- withr::local_tempfile(fileext = ".rds")
  m <- suppressMessages(write_taxaid_manifest(p, packages = "TaxaTools"))
  m <- rbind(m, data.frame(
    package = "TaxaGhost", version = "0.1.0", built = "then",
    code_hash = "abc", installed = TRUE, stringsAsFactors = FALSE
  ))
  saveRDS(m, p)
  err <- tryCatch(
    check_taxaid_manifest(p, packages = c("TaxaTools", "TaxaGhost")),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "MISSING")
  expect_match(err, "TaxaGhost")
  # MISSING must appear before CHANGED/EXTRA in the message
  expect_lt(regexpr("MISSING", err, fixed = TRUE), 1e9)
})

test_that("an EXTRA package is reported", {
  # Hermetic on purpose: an earlier version of this test asserted that
  # TaxaHabitat shows up as EXTRA, which passes under devtools::test() and
  # FAILS under R CMD check, where sibling TaxaID packages are not loadable.
  # The test must not depend on which other packages happen to be installed --
  # so the manifest omits a package that is certainly present (TaxaTools
  # itself, since these tests run inside it).
  p <- withr::local_tempfile(fileext = ".rds")
  m <- suppressMessages(write_taxaid_manifest(p, packages = "TaxaTools"))
  ghost <- m
  ghost$package <- "TaxaGhostNotInstalled"
  ghost$installed <- FALSE
  ghost$code_hash <- NA_character_
  saveRDS(ghost, p)
  expect_error(
    check_taxaid_manifest(p, packages = "TaxaTools"),
    "EXTRA"
  )
})

test_that("on_mismatch controls severity without changing the verdict", {
  p <- withr::local_tempfile(fileext = ".rds")
  m <- suppressMessages(write_taxaid_manifest(p, packages = "TaxaTools"))
  m$code_hash <- "deadbeefdeadbeefdeadbeefdeadbeef"
  saveRDS(m, p)
  expect_error(check_taxaid_manifest(p, packages = "TaxaTools", on_mismatch = "error"))
  expect_warning(check_taxaid_manifest(p, packages = "TaxaTools", on_mismatch = "warning"))
  expect_message(check_taxaid_manifest(p, packages = "TaxaTools", on_mismatch = "message"))
  r <- check_taxaid_manifest(p, packages = "TaxaTools", on_mismatch = "silent")
  expect_false(r$ok)   # the verdict is the same; only the noise differs
})

test_that("check_taxaid_manifest validates its inputs", {
  expect_error(check_taxaid_manifest("no_such_file.rds"), "not found")
  p <- withr::local_tempfile(fileext = ".rds")
  saveRDS(data.frame(x = 1), p)
  expect_error(check_taxaid_manifest(p), "not a build manifest")
  expect_error(taxaid_build_manifest(NA_character_), "non-empty")
  expect_error(taxaid_build_manifest(123), "non-empty")
  # character(0) is NOT an error: TaxaTools' own %||% treats a zero-length
  # value as absent (R/llm_api_utils.R), so it falls through to the default
  # nine-package set. Asserted rather than left implicit, because a future
  # change to %||% would otherwise silently turn this into an error.
  expect_equal(nrow(taxaid_build_manifest(character(0))), 9L)
})

test_that("an older manifest without an 'installed' column still works", {
  p <- withr::local_tempfile(fileext = ".rds")
  m <- suppressMessages(write_taxaid_manifest(p, packages = "TaxaTools"))
  m$installed <- NULL
  saveRDS(m, p)
  r <- suppressMessages(check_taxaid_manifest(p, packages = "TaxaTools"))
  expect_true(r$ok)
})
