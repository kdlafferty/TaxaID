# Regression tests for the 2026-09-14 silent reference-database loss.
#
# On the real PtConception 12S run, 7 per-taxon NCBI count queries failed
# transiently (rentrez surfaced "subscript out of bounds"). An NA count is
# excluded from the sequence budget, which sets that taxon's retmax_cap to 0,
# so the taxon contributed ZERO reference sequences -- silently, apart from
# one warning per taxon buried in a 17,000-line log. 352 species-level
# consensus rows ended up resting on no reference data of their own.
#
# These tests pin the three properties that close that hole: transient
# failures are retried, a surviving failure is reported by name with its
# consequence stated, and the affected taxa are recoverable programmatically
# from the returned object rather than from the log.

test_that("a transient count failure is retried and then succeeds", {
  skip_if_not_installed("rentrez")

  calls <- 0L
  fake_search <- function(db, term, retmax) {
    calls <<- calls + 1L
    if (calls == 1L) stop("subscript out of bounds")
    list(count = "0") # second attempt succeeds, zero hits -> early return
  }

  testthat::local_mocked_bindings(
    entrez_search = fake_search, .package = "rentrez"
  )

  out <- suppressMessages(
    fetch_ncbi_reference_sequences(
      taxa = "Cymatogaster", barcode_term = "12S",
      cache_dir = tempfile("tl_cache_")
    )
  )

  expect_gte(calls, 2L) # it retried rather than giving up on the first error
  expect_length(attr(out, "count_failures"), 0L)
})

test_that("a persistent count failure is named, and its consequence stated", {
  skip_if_not_installed("rentrez")

  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax) stop("subscript out of bounds"),
    .package = "rentrez"
  )

  # All taxa failing is the pre-existing hard stop, so give one that succeeds.
  succeed_for <- function(db, term, retmax) {
    if (grepl("Sebastes", term)) list(count = "5") else stop("subscript out of bounds")
  }
  testthat::local_mocked_bindings(
    entrez_search = succeed_for, .package = "rentrez"
  )

  expect_warning(
    out <- suppressMessages(
      fetch_ncbi_reference_sequences(
        taxa = c("Sebastes", "Cymatogaster", "Medialuna"),
        barcode_term = "12S",
        count_attempts = 2L,
        cache_dir = tempfile("tl_cache_")
      )
    ),
    "ZERO reference sequences"
  )

  # named, not just counted
  expect_true(all(c("Cymatogaster", "Medialuna") %in%
    attr(out, "count_failures")))
  expect_false("Sebastes" %in% attr(out, "count_failures"))
})

test_that("on_count_failure = 'error' refuses a degraded reference database", {
  skip_if_not_installed("rentrez")

  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax) {
      if (grepl("Sebastes", term)) list(count = "5") else stop("boom")
    },
    .package = "rentrez"
  )

  expect_error(
    suppressMessages(suppressWarnings(
      fetch_ncbi_reference_sequences(
        taxa = c("Sebastes", "Cymatogaster"), barcode_term = "12S",
        count_attempts = 1L, on_count_failure = "error",
        cache_dir = tempfile("tl_cache_")
      )
    )),
    "ZERO reference sequences"
  )
})

test_that("count_attempts is validated", {
  expect_error(
    fetch_ncbi_reference_sequences(
      taxa = "Sebastes", barcode_term = "12S", count_attempts = 0L
    ),
    "positive integer"
  )
})
