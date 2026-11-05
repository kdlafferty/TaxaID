# ------------------------------------------------------------------------------
# A truncated GBIF cloud must not submit a download on its own.
#
# `on_cap` reaches the download API through two functions, and their defaults
# have to agree: check_geographic_outliers() forwards its own `on_cap` verbatim
# to get_gbif_occurrences(), which is where escalation actually happens. If the
# caller defaults to "escalate" while the fetcher defaults to "warn", reading
# either function's documentation gives the wrong answer about what a plain
# call does, and the plain call spends a real GBIF account: an escalation
# retrieves a species' full global record set and a completed download carries
# a DOI to cite.
#
# The chain is tested in two cheap pieces rather than one expensive one:
#   (1) the two defaults are the same value, and the caller forwards it
#       (the forwarding itself is asserted in test-check_geographic_outliers.R);
#   (2) that value, in get_gbif_occurrences(), does not reach the download API
#       even when credentials are supplied -- and "escalate" does.
# Driving (2) through check_geographic_outliers() would need a 10,000-row
# global cloud, because that function fetches with limit = NULL, and would then
# run CoordinateCleaner over it to prove a point about a branch taken long
# before.
# ------------------------------------------------------------------------------

skip_if_not_installed("rgbif")

.oncap_raw <- function(limit = 10L) {
  # key 1 sits exactly at the limit -- i.e. was truncated; key 2 is well under.
  data.frame(
    taxonKey = c(rep(1L, limit), rep(2L, 3L)),
    taxonRank = "SPECIES",
    species = c(rep("Aa aa", limit), rep("Bb bb", 3L)),
    decimalLatitude = 34, decimalLongitude = -120,
    stringsAsFactors = FALSE
  )
}

test_that("both on_cap defaults are 'warn'", {
  caller <- eval(formals(check_geographic_outliers)$on_cap)
  fetcher <- eval(formals(get_gbif_occurrences)$on_cap)
  expect_identical(caller[[1L]], "warn")
  expect_identical(fetcher[[1L]], "warn")
  expect_identical(caller[[1L]], fetcher[[1L]])
  # Same vocabulary too, so match.arg() accepts the same words in both.
  expect_setequal(caller, fetcher)
})

test_that("under the default a capped key does not reach the download API, with credentials supplied", {
  n_download <- 0L
  testthat::local_mocked_bindings(
    fetch_gbif_occurrences = function(...) .oncap_raw(10L),
    download_gbif_occurrences = function(...) {
      n_download <<- n_download + 1L
      data.frame(
        taxonKey = rep(1L, 25L), taxonRank = "SPECIES", species = "Aa aa",
        decimalLatitude = 34, decimalLongitude = -120, stringsAsFactors = FALSE
      )
    },
    .package = "TaxaFetch"
  )
  expect_warning(
    out <- get_gbif_occurrences(
      keys = c(1, 2), geometry = "POLYGON((0 0,1 0,1 1,0 1,0 0))",
      limit = 10L, key_threshold = 100L, rank_filter = FALSE,
      columns = "all", cache_dir = NULL,
      gbif_user = "someone", gbif_pwd = "secret", gbif_email = "someone@example.org"
    ),
    "TRUNCATED"
  )
  # A counter, not a stop(): the escalate branch wraps its call in try(), so a
  # tripwire that threw would be swallowed and the test would pass anyway.
  expect_identical(n_download, 0L)
  # The truncated prefix is kept and reported rather than silently replaced.
  expect_equal(attr(out, "capped_keys"), 1L)
  expect_equal(sum(out$taxonKey == 1L), 10L)
})

test_that("on_cap = 'escalate' does reach the download API with the same credentials", {
  n_download <- 0L
  seen_keys <- NULL
  testthat::local_mocked_bindings(
    fetch_gbif_occurrences = function(...) .oncap_raw(10L),
    download_gbif_occurrences = function(keys, ...) {
      n_download <<- n_download + 1L
      seen_keys <<- keys
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
      columns = "all", cache_dir = NULL, on_cap = "escalate",
      gbif_user = "someone", gbif_pwd = "secret", gbif_email = "someone@example.org"
    ),
    "escalation replaced"
  )
  expect_identical(n_download, 1L)
  expect_equal(seen_keys, 1L) # only the capped key
  expect_equal(sum(out$taxonKey == 1L), 25L)
  expect_length(attr(out, "capped_keys"), 0L)
})
