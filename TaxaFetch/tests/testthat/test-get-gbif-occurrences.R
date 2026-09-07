# ------------------------------------------------------------------------------
# Per-key truncation ("cap") detection (2026-09-02). Real incident: 45 of Mugu's
# 231 taxa sat at a 10,000-record cap holding 95% of the pool, all with an
# identical spatial distribution, and nothing warned.
# ------------------------------------------------------------------------------

.cap_raw <- function(limit = 10L) {
  # key 1 truncated exactly at the limit; key 2 well under it
  data.frame(
    taxonKey = c(rep(1L, limit), rep(2L, 3L)),
    taxonRank = "SPECIES",
    species = c(rep("Aa aa", limit), rep("Bb bb", 3L)),
    decimalLatitude = 34, decimalLongitude = -120,
    stringsAsFactors = FALSE
  )
}

test_that("a key returning exactly the limit is detected, warned, and reported", {
  testthat::local_mocked_bindings(
    fetch_gbif_occurrences = function(...) .cap_raw(10L), .package = "TaxaFetch"
  )
  expect_warning(
    out <- get_gbif_occurrences(
      keys = c(1, 2), geometry = "POLYGON((0 0,1 0,1 1,0 1,0 0))",
      limit = 10L, key_threshold = 100L, rank_filter = FALSE,
      columns = "all", cache_dir = NULL
    ),
    "TRUNCATED"
  )
  expect_equal(attr(out, "capped_keys"), 1L)
})

test_that("on_cap = 'error' stops and 'warn' is the default", {
  testthat::local_mocked_bindings(
    fetch_gbif_occurrences = function(...) .cap_raw(10L), .package = "TaxaFetch"
  )
  expect_error(
    get_gbif_occurrences(
      keys = c(1, 2), geometry = "POLYGON((0 0,1 0,1 1,0 1,0 0))",
      limit = 10L, key_threshold = 100L, rank_filter = FALSE,
      columns = "all", cache_dir = NULL, on_cap = "error"
    ),
    "TRUNCATED"
  )
})

test_that("no cap, no warning, and capped_keys is empty", {
  testthat::local_mocked_bindings(
    fetch_gbif_occurrences = function(...) .cap_raw(10L)[11:13, ], .package = "TaxaFetch"
  )
  expect_no_warning(
    out <- get_gbif_occurrences(
      keys = 2, geometry = "POLYGON((0 0,1 0,1 1,0 1,0 0))",
      limit = 10L, key_threshold = 100L, rank_filter = FALSE,
      columns = "all", cache_dir = NULL
    )
  )
  expect_length(attr(out, "capped_keys"), 0L)
})

test_that("on_cap = 'escalate' re-fetches capped keys via the download API", {
  testthat::local_mocked_bindings(
    fetch_gbif_occurrences = function(...) .cap_raw(10L),
    download_gbif_occurrences = function(keys, ...) {
      data.frame(
        taxonKey = rep(1L, 25L), taxonRank = "SPECIES", species = "Aa aa",
        decimalLatitude = 34, decimalLongitude = -120, stringsAsFactors = FALSE
      )
    },
    .package = "TaxaFetch"
  )
  expect_message(
    out <- get_gbif_occurrences(
      keys = c(1, 2), geometry = "POLYGON((0 0,1 0,1 1,0 1,0 0))",
      limit = 10L, key_threshold = 100L, rank_filter = FALSE,
      columns = "all", cache_dir = NULL, on_cap = "escalate"
    ),
    "escalation replaced"
  )
  expect_equal(sum(out$taxonKey == 1L), 25L) # full record set, not the prefix
  expect_length(attr(out, "capped_keys"), 0L)
})

test_that("on_cap = 'escalate' passes a fully-resolved select_cols to the download API", {
  # Regression: select_cols_dl was computed only inside the DOWNLOAD branch,
  # but escalation reaches download_gbif_occurrences() from the FETCH branch --
  # so the argument referenced an object that did not exist, and every
  # escalation failed at import, AFTER paying for the whole download. The
  # earlier escalate test could not catch it: its mock swallowed the argument
  # in `...` and so never forced the promise.
  seen <- NULL
  testthat::local_mocked_bindings(
    fetch_gbif_occurrences = function(...) .cap_raw(10L),
    download_gbif_occurrences = function(keys, select_cols, ...) {
      seen <<- select_cols # forcing the promise is the point
      data.frame(
        taxonKey = rep(1L, 25L), issues = NA_character_,
        species = "Aa aa", stringsAsFactors = FALSE
      )
    },
    .package = "TaxaFetch"
  )
  expect_message(
    out <- get_gbif_occurrences(
      keys = c(1, 2), geometry = "POLYGON((0 0,1 0,1 1,0 1,0 0))",
      limit = 10L, key_threshold = 100L, rank_filter = FALSE,
      columns = c("taxonKey", "issues", "species"),
      cache_dir = NULL, on_cap = "escalate"
    ),
    "escalation replaced"
  )
  # "issues" is the wrapper's canonical name; SIMPLE_CSV calls it "issue".
  expect_equal(seen, c("taxonKey", "issue", "species"))
})
