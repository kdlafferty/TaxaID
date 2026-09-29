# verify_taxon_names(cache_dir =): only answered names are cached, the key
# encodes everything that can change an answer, and a failure is never served.

.fake_verify <- function(answers) {
  # answers: named character; NA value = looked up, no match; "FAIL" = lookup failed
  calls <- new.env(); calls$names <- list()
  fn <- function(name_list, backbone_id, ...) {
    calls$names[[length(calls$names) + 1L]] <- name_list
    a <- answers[name_list]
    data.frame(
      user_supplied_name = name_list,
      matched_name = ifelse(is.na(a) | a == "FAIL", NA_character_, a),
      verified = !(a %in% "FAIL"),
      matched = !is.na(a) & a != "FAIL",
      stringsAsFactors = FALSE
    )
  }
  list(fn = fn, calls = calls)
}

test_that("answered names are cached and served; failures are asked again", {
  dir <- withr::local_tempdir()
  f <- .fake_verify(c(Aa = "Aa", Bb = NA, Cc = "FAIL"))
  local_mocked_bindings(.verify_taxon_names_uncached = f$fn)
  out1 <- verify_taxon_names(c("Aa", "Bb", "Cc", "Aa"), backbone_id = 11L, cache_dir = dir)
  expect_identical(out1$user_supplied_name, c("Aa", "Bb", "Cc", "Aa"))
  expect_identical(out1$matched, c(TRUE, FALSE, FALSE, TRUE))
  expect_identical(out1$verified, c(TRUE, TRUE, FALSE, TRUE))
  expect_length(list.files(dir, "_verified_name\\.rds$"), 2L)  # Aa and Bb, never Cc
  expect_message(
    out2 <- verify_taxon_names(c("Aa", "Bb", "Cc"), backbone_id = 11L, cache_dir = dir),
    "2 of 3 name\\(s\\) served from cache"
  )
  expect_identical(f$calls$names[[2]], "Cc")  # only the failure is re-asked
  expect_identical(out2$matched, c(TRUE, FALSE, FALSE))
})

test_that("the key covers backbone, fallback and decisions content, not batch settings", {
  dir <- withr::local_tempdir()
  f <- .fake_verify(c(Aa = "Aa"))
  local_mocked_bindings(.verify_taxon_names_uncached = f$fn)
  verify_taxon_names("Aa", backbone_id = 11L, cache_dir = dir)
  verify_taxon_names("Aa", backbone_id = 11L, cache_dir = dir, batch_size = 7, timeout_sec = 3)
  expect_length(f$calls$names, 1L)                     # batch settings: same key
  verify_taxon_names("Aa", backbone_id = 1L, cache_dir = dir)
  verify_taxon_names("Aa", backbone_id = 11L, fallback_backbone_id = 4L, cache_dir = dir)
  d1 <- data.frame(name = "Aa", taxid = 1L); d2 <- data.frame(name = "Aa", taxid = 2L)
  suppressWarnings(verify_taxon_names("Aa", backbone_id = 11L, decisions = d1, cache_dir = dir))
  suppressWarnings(verify_taxon_names("Aa", backbone_id = 11L, decisions = d2, cache_dir = dir))
  expect_length(f$calls$names, 5L)                     # each of those is a new question
  p <- tempfile(fileext = ".rds"); saveRDS(d1, p)
  suppressWarnings(verify_taxon_names("Aa", backbone_id = 11L, decisions = p, cache_dir = dir))
  saveRDS(d2, p)                                       # same path, new content
  suppressWarnings(verify_taxon_names("Aa", backbone_id = 11L, decisions = p, cache_dir = dir))
  expect_length(f$calls$names, 7L)
})

test_that("an expired entry is asked again, and cache_dir = NULL never touches disk", {
  dir <- withr::local_tempdir()
  f <- .fake_verify(c(Aa = "Aa"))
  local_mocked_bindings(.verify_taxon_names_uncached = f$fn)
  verify_taxon_names("Aa", backbone_id = 11L, cache_dir = dir)
  path <- list.files(dir, full.names = TRUE)
  x <- readRDS(path); x$written_at <- Sys.time() - 400 * 86400; saveRDS(x, path)
  verify_taxon_names("Aa", backbone_id = 11L, cache_dir = dir)
  expect_length(f$calls$names, 2L)
  expect_error(verify_taxon_names("Aa", backbone_id = 11L, cache_dir = dir, cache_ttl_days = 0), "cache_ttl_days")
  expect_true(file.exists(path))
})

test_that("taxatools_clear_cache() recognises the verified-name cache", {
  dir <- withr::local_tempdir()
  f <- .fake_verify(c(Aa = "Aa"))
  local_mocked_bindings(.verify_taxon_names_uncached = f$fn)
  verify_taxon_names("Aa", backbone_id = 11L, cache_dir = dir)
  expect_no_error(taxatools_clear_cache(dir, dry_run = TRUE))
})
