# Regression tests for the 2026-09-14 cache-policy fix (P1/P2).
#
# The 2026-09-14 silent reference loss was NOT caused by missing caching. All
# seven genera that vanished (Medialuna, Zalophus, Tursiops, Symphurus,
# Apodichthys, Cymatogaster, Delphinus) had valid cached metadata on disk from
# 2026-08-29. The count loop ran unconditionally BEFORE the per-taxon cache
# check; a transient count failure set retmax_cap to 0 and dropped each taxon
# before its cache file was ever consulted -- an uncached, network-dependent
# query gating an already-cached payload.
#
# These tests pin the properties that close that hole for good.
# See ecosystem_docs/CACHE_POLICY_REVIEW_2026_09_14.md.

# Write a cache file under exactly the key fetch_ncbi_reference_sequences()
# will compute for these arguments. If the key format ever changes, these
# tests fail loudly rather than silently testing a cache miss.
write_cached_taxon <- function(cache_dir, taxon, accs) {
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  meta <- data.frame(
    taxid = seq_along(accs), acc = accs,
    title = paste(taxon, "12S ribosomal RNA gene"),
    slen = 400L, organism = paste(taxon, "sp."),
    create_date = "2026/08/29", in_barcode_range = TRUE,
    family = paste0(taxon, "idae"), genus = taxon,
    species = paste(taxon, "sp."), stringsAsFactors = FALSE
  )
  f <- file.path(cache_dir, sprintf(
    "%s_12S_l100_5000_d_rk-family-genus-species_meta.rds", taxon
  ))
  saveRDS(meta, f)
  f
}

fake_fasta <- function(accs) {
  paste(sprintf(">%s Fake\nACGTACGTACGTACGTACGT", accs), collapse = "\n")
}


test_that("a cached taxon issues no count query at all", {
  skip_if_not_installed("rentrez")

  cache_dir <- tempfile("tl_p1_")
  write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1", "AB000002.1"))

  searched <- character(0)
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) {
      searched <<- c(searched, term)
      list(count = "5")
    },
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  suppressMessages(fetch_ncbi_reference_sequences(
    taxa = "Sebastes", barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir
  ))

  # THE core property: the network was never asked about a taxon we already had.
  expect_length(searched, 0L)
})


test_that("a cached taxon survives even when every count query fails", {
  skip_if_not_installed("rentrez")

  # This is the 2026-09-14 incident, reproduced: NCBI is throwing on every
  # count query, and the taxon must still come back with its reference data.
  cache_dir <- tempfile("tl_p1_")
  write_cached_taxon(cache_dir, "Medialuna", c("AB000003.1"))

  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) stop("subscript out of bounds"),
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  out <- suppressMessages(fetch_ncbi_reference_sequences(
    taxa = "Medialuna", barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir
  ))

  expect_gt(nrow(out), 0L)
  expect_true("Medialuna" %in% out$genus)
  # And it must NOT be reported as a count failure: no query was issued.
  expect_false("Medialuna" %in% attr(out, "count_failures"))
})


test_that("an all-cached call does not return an empty reference_df", {
  skip_if_not_installed("rentrez")

  # When every taxon is cached, `total` is legitimately 0. The pre-existing
  # `if (total == 0L) return(empty)` guard would have discarded a complete
  # cached reference set.
  cache_dir <- tempfile("tl_p1_")
  write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1"))
  write_cached_taxon(cache_dir, "Girella", c("AB000004.1"))

  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) stop("should not be called"),
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  out <- suppressMessages(fetch_ncbi_reference_sequences(
    taxa = c("Sebastes", "Girella"), barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir
  ))

  expect_equal(nrow(out), 2L)
  expect_setequal(out$genus, c("Sebastes", "Girella"))
})


test_that("an uncached taxon is still counted and fetched alongside cached ones", {
  skip_if_not_installed("rentrez")

  cache_dir <- tempfile("tl_p1_")
  write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1"))

  searched <- character(0)
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) {
      searched <<- c(searched, term)
      list(count = "1", ids = "AB000005.1")
    },
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  # The uncached taxon's fetch no-ops under this minimal mock (no esummary
  # stub); irrelevant here -- this test is about which taxa get COUNTED.
  suppressWarnings(suppressMessages(fetch_ncbi_reference_sequences(
    taxa = c("Sebastes", "Atractoscion"), barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir
  )))

  # Exactly one taxon was asked about, and it was the uncached one.
  expect_true(any(grepl("Atractoscion", searched)))
  expect_false(any(grepl("Sebastes", searched)))
})


test_that("P2: FASTA is cached per accession and not re-downloaded", {
  skip_if_not_installed("rentrez")

  cache_dir <- tempfile("tl_p2_")
  write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1", "AB000002.1"))

  fetched <- list()
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) list(count = "0"),
    entrez_fetch = function(db, id, rettype, retmode, ...) {
      fetched[[length(fetched) + 1L]] <<- id
      fake_fasta(id)
    },
    .package = "rentrez"
  )

  args <- list(
    taxa = "Sebastes", barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir
  )
  first <- suppressMessages(do.call(fetch_ncbi_reference_sequences, args))
  n_after_first <- length(fetched)
  second <- suppressMessages(do.call(fetch_ncbi_reference_sequences, args))

  expect_gt(n_after_first, 0L) # first run really did download
  expect_equal(length(fetched), n_after_first) # second run downloaded nothing
  expect_equal(nrow(second), nrow(first)) # and returned the same data
})


# --- The audit trail must survive the cache short-circuit -------------------
# Raised 2026-09-14: consulting the cache before the count query removes most
# count queries, but it must not also remove the reporting for a taxon that
# was NEITHER cached NOR successfully counted. That taxon is exactly the
# 2026-09-14 failure case and must still surface.

test_that("count_failures still names a taxon that was neither cached nor counted", {
  skip_if_not_installed("rentrez")

  cache_dir <- tempfile("tl_audit_")
  write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1"))

  # Sebastes is cached (never queried). Medialuna is not cached and its count
  # query fails persistently -- it must be reported.
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) {
      stop("subscript out of bounds")
    },
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  expect_warning(
    out <- suppressMessages(fetch_ncbi_reference_sequences(
      taxa = c("Sebastes", "Medialuna"), barcode_term = "12S",
      min_len = 100L, max_len = 5000L, cache_dir = cache_dir
    )),
    "Medialuna"
  )

  # The uncached, uncounted taxon is reported...
  expect_true("Medialuna" %in% attr(out, "count_failures"))
  # ...and the cached one is NOT falsely reported as a failure.
  expect_false("Sebastes" %in% attr(out, "count_failures"))
  # ...and the cached one's data still came back.
  expect_true("Sebastes" %in% out$genus)
})


# --- Selection parameters are verified, not assumed -------------------------
# The cache KEY captures what gets fetched; these tests cover what gets KEPT.
# The cached object is written post-blacklist and post-slice_sample(), so a
# cache built at max_per_species = 10 must not be served to a call asking for
# 50. Stored inside the object rather than added to the key, because widening
# the key would orphan every existing cache file at once.

test_that("a cache built under different max_per_species is rejected", {
  skip_if_not_installed("rentrez")

  cache_dir <- tempfile("tl_sel_")
  f <- write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1"))
  meta <- readRDS(f)
  attr(meta, "sel_params") <- list(
    max_per_species = 10L, max_per_genus = NULL,
    blacklist_regex = "uncultured"
  )
  saveRDS(meta, f)

  searched <- character(0)
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) {
      searched <<- c(searched, term)
      list(count = "0")
    },
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  suppressMessages(fetch_ncbi_reference_sequences(
    taxa = "Sebastes", barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir,
    max_per_species = 50L, blacklist_regex = "uncultured"
  ))

  # Asking for 50 when the cache holds 10 must re-query, not silently under-fill.
  expect_true(any(grepl("Sebastes", searched)))
})

test_that("a cache built under the SAME selection settings is reused", {
  skip_if_not_installed("rentrez")

  cache_dir <- tempfile("tl_sel_")
  f <- write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1"))
  meta <- readRDS(f)
  attr(meta, "sel_params") <- list(
    max_per_species = 10L, max_per_genus = NULL,
    blacklist_regex = "uncultured"
  )
  saveRDS(meta, f)

  searched <- character(0)
  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) {
      searched <<- c(searched, term)
      list(count = "0")
    },
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  suppressMessages(fetch_ncbi_reference_sequences(
    taxa = "Sebastes", barcode_term = "12S",
    min_len = 100L, max_len = 5000L, cache_dir = cache_dir,
    max_per_species = 10L, blacklist_regex = "uncultured"
  ))

  expect_length(searched, 0L)
})

test_that("a legacy cache file (no recorded settings) is used, with a note", {
  skip_if_not_installed("rentrez")

  # write_cached_taxon() deliberately writes no sel_params attribute, which is
  # exactly the shape of the ~3,516 files already on disk.
  cache_dir <- tempfile("tl_sel_")
  write_cached_taxon(cache_dir, "Sebastes", c("AB000001.1"))

  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) stop("should not be called"),
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  expect_message(
    out <- fetch_ncbi_reference_sequences(
      taxa = "Sebastes", barcode_term = "12S",
      min_len = 100L, max_len = 5000L, cache_dir = cache_dir
    ),
    "predate selection-parameter recording"
  )
  expect_gt(nrow(out), 0L)
})

test_that("a freshly written cache file records its selection settings", {
  skip_if_not_installed("rentrez")

  cache_dir <- tempfile("tl_sel_")
  dir.create(cache_dir, recursive = TRUE)

  testthat::local_mocked_bindings(
    entrez_search = function(db, term, retmax, ...) list(count = "0"),
    entrez_fetch = function(db, id, rettype, retmode, ...) fake_fasta(id),
    .package = "rentrez"
  )

  # A zero-count taxon writes no cache file, so this documents the contract
  # via the helper the writer uses rather than via a live fetch.
  expect_equal(
    TaxaLikely:::.sel_params(10L, NULL, "uncultured"),
    list(max_per_species = 10L, max_per_genus = NULL, blacklist_regex = "uncultured")
  )
  expect_equal(
    TaxaLikely:::.sel_params_status(
      structure(data.frame(a = 1), sel_params = TaxaLikely:::.sel_params(10L, NULL, "x")),
      TaxaLikely:::.sel_params(10L, NULL, "x")
    ),
    "ok"
  )
  expect_equal(
    TaxaLikely:::.sel_params_status(
      structure(data.frame(a = 1), sel_params = TaxaLikely:::.sel_params(10L, NULL, "x")),
      TaxaLikely:::.sel_params(50L, NULL, "x")
    ),
    "mismatch"
  )
  expect_equal(
    TaxaLikely:::.sel_params_status(data.frame(a = 1), TaxaLikely:::.sel_params(10L, NULL, "x")),
    "legacy"
  )
})
