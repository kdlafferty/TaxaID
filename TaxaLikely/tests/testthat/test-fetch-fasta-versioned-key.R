# ==============================================================================
# test-fetch-fasta-versioned-key.R
# The FASTA store (P2 of the 2026-09-14 cache policy) documented itself as
# "keyed on the FULL accession including its version suffix" while actually
# keying on ESummary's `caption`, which carries no version -- 0 of 4,061 real
# cached files had one. A revised GenBank record was therefore a cache HIT,
# serving the superseded sequence under refreshed metadata.
#
# The load-bearing test here is "a versioned key does not hit a legacy
# unversioned file": if that ever passes by hitting the old file, the whole
# fix is undone and the bug is silently back.
# ==============================================================================

.fasta_tmpdir <- function() {
  d <- tempfile("taxalikely_fasta_")
  dir.create(d)
  d
}

test_that(".fasta_cache_keys() prefers the versioned accession", {
  meta <- data.frame(
    acc = c("AB000667", "AB018586"),
    acc_version = c("AB000667.1", "AB018586.2"),
    stringsAsFactors = FALSE
  )
  k <- TaxaLikely:::.fasta_cache_keys(meta)
  expect_identical(as.character(k), c("AB000667.1", "AB018586.2"))
  expect_identical(attr(k, "n_unversioned"), 0L)
  expect_identical(attr(k, "cacheable"), c(TRUE, TRUE))
})

test_that(".fasta_cache_keys() marks rows uncacheable when the column is absent entirely", {
  # A meta object with no acc_version column at all (e.g. from a pre-1.0
  # cache generation) can neither supply nor notice a GenBank revision, so
  # none of its rows are safe to persist under the bare accession.
  meta <- data.frame(acc = c("AB000667", "AB018586"), stringsAsFactors = FALSE)
  k <- TaxaLikely:::.fasta_cache_keys(meta)
  expect_identical(as.character(k), c("AB000667", "AB018586"))
  expect_identical(attr(k, "n_unversioned"), 2L)
  expect_identical(attr(k, "cacheable"), c(FALSE, FALSE))
})

test_that(".fasta_cache_keys() resolves per ROW, not per call", {
  # A record whose OWN accessionversion is genuinely absent (NCBI simply did
  # not return one) costs only its own row -- this is a real, present-tense
  # per-record possibility, not a whole-object schema gap.
  meta <- data.frame(
    acc = c("AB000667", "AB018586", "AB042345"),
    acc_version = c("AB000667.1", NA, ""),
    stringsAsFactors = FALSE
  )
  k <- TaxaLikely:::.fasta_cache_keys(meta)
  expect_identical(as.character(k), c("AB000667.1", "AB018586", "AB042345"))
  expect_identical(attr(k, "n_unversioned"), 2L)
  expect_identical(attr(k, "cacheable"), c(TRUE, FALSE, FALSE))
})

test_that(".fasta_cache_keys() returns one key per row for a single-row meta", {
  meta <- data.frame(acc = "AB000667", acc_version = "AB000667.1",
                     stringsAsFactors = FALSE)
  expect_identical(as.character(TaxaLikely:::.fasta_cache_keys(meta)), "AB000667.1")
})

test_that("a versioned key does NOT hit a legacy unversioned cache file", {
  # THE regression test. Seed the store the way every real file on disk today
  # is named, then ask for the same accession WITH its version.
  d <- .fasta_tmpdir()
  dir.create(file.path(d, "fasta"))
  saveRDS(
    data.frame(composite_id = "AB000667", sequence = "AAAA", stringsAsFactors = FALSE),
    file.path(d, "fasta", "AB000667_seq.rds")
  )

  downloaded <- NULL
  local_mocked_bindings(
    .fetch_fasta_batched = function(accessions, batch_size = 200L) {
      downloaded <<- accessions
      paste0(">", accessions[1L], " fresh\nGGGG\n")
    },
    .package = "TaxaLikely"
  )

  out <- TaxaLikely:::.fetch_fasta_cached("AB000667.1", cache_dir = d)

  # It re-downloaded rather than serving the stale sequence...
  expect_identical(downloaded, "AB000667.1")
  expect_identical(out$sequence, "GGGG")
  # ...wrote the versioned file...
  expect_true(file.exists(file.path(d, "fasta", "AB000667_1_seq.rds")))
  # ...and left the legacy file alone (eviction is not this function's job).
  expect_true(file.exists(file.path(d, "fasta", "AB000667_seq.rds")))
})

test_that("a versioned key hits its own versioned file on the second call", {
  d <- .fasta_tmpdir()
  calls <- 0L
  local_mocked_bindings(
    .fetch_fasta_batched = function(accessions, batch_size = 200L) {
      calls <<- calls + 1L
      paste0(">", accessions[1L], " x\nCCCC\n")
    },
    .package = "TaxaLikely"
  )

  first <- TaxaLikely:::.fetch_fasta_cached("AB000667.1", cache_dir = d)
  expect_identical(calls, 1L)
  expect_identical(first$sequence, "CCCC")

  second <- suppressMessages(
    TaxaLikely:::.fetch_fasta_cached("AB000667.1", cache_dir = d)
  )
  expect_identical(calls, 1L) # served from disk, no second download
  expect_identical(second$sequence, "CCCC")
  # composite_id stays version-STRIPPED, which is the space reference_df
  # and .fetch_locations_batched() both join in.
  expect_identical(second$composite_id, "AB000667")
})

test_that(".fetch_fasta_cached() is an ordinary keyed cache when cacheable is not restricted", {
  # .fetch_fasta_cached() does not itself judge whether a key is safe to
  # reuse -- that judgment (does the accession carry a real GenBank version)
  # lives in .fasta_cache_keys(), and is threaded through via the
  # `cacheable` argument at the one real call site in
  # fetch_ncbi_reference_sequences(). Called directly with no `cacheable`
  # argument it behaves as an ordinary file-per-key cache; see the next test
  # for what happens when a caller marks a key uncacheable.
  d <- .fasta_tmpdir()
  dir.create(file.path(d, "fasta"))
  saveRDS(
    data.frame(composite_id = "AB000667", sequence = "TTTT", stringsAsFactors = FALSE),
    file.path(d, "fasta", "AB000667_seq.rds")
  )
  local_mocked_bindings(
    .fetch_fasta_batched = function(accessions, batch_size = 200L) {
      stop("must not download: the cached file should have been a hit")
    },
    .package = "TaxaLikely"
  )
  out <- suppressMessages(TaxaLikely:::.fetch_fasta_cached("AB000667", cache_dir = d))
  expect_identical(out$sequence, "TTTT")
})

test_that(".fetch_fasta_cached(cacheable = FALSE) never hits or writes disk", {
  # An unversioned accession (per .fasta_cache_keys()'s cacheable attribute)
  # is a cache MISS unconditionally: never served from a stale on-disk file
  # of that name, and never written back either, so re-fetching one never
  # recreates the very staleness risk this is meant to close.
  d <- .fasta_tmpdir()
  dir.create(file.path(d, "fasta"))
  saveRDS(
    data.frame(composite_id = "AB000667", sequence = "TTTT", stringsAsFactors = FALSE),
    file.path(d, "fasta", "AB000667_seq.rds")
  )
  downloaded <- NULL
  local_mocked_bindings(
    .fetch_fasta_batched = function(accessions, batch_size = 200L) {
      downloaded <<- accessions
      paste0(">", accessions[1L], " fresh\nGGGG\n")
    },
    .package = "TaxaLikely"
  )
  out <- TaxaLikely:::.fetch_fasta_cached("AB000667", cache_dir = d, cacheable = FALSE)
  expect_identical(downloaded, "AB000667")
  expect_identical(out$sequence, "GGGG")
  # The stale on-disk file is untouched -- not overwritten either.
  expect_identical(
    readRDS(file.path(d, "fasta", "AB000667_seq.rds"))$sequence, "TTTT"
  )
})

test_that("a versioned request maps the stripped header id back to its key", {
  # NCBI's FASTA header always carries the version, and .parse_fasta_text()
  # strips it -- so the write-back has to map the stripped id to the string
  # that was requested, or the file lands under the wrong name.
  d <- .fasta_tmpdir()
  local_mocked_bindings(
    .fetch_fasta_batched = function(accessions, batch_size = 200L) {
      # Header format verified live against NCBI on 2026-09-14.
      ">AB000667.1 Paralichthys olivaceus mitochondrial\nACGT\n"
    },
    .package = "TaxaLikely"
  )
  out <- TaxaLikely:::.fetch_fasta_cached("AB000667.1", cache_dir = d)
  expect_identical(out$composite_id, "AB000667")
  expect_true(file.exists(file.path(d, "fasta", "AB000667_1_seq.rds")))
})

test_that("a RefSeq accession's underscore cannot collide with a version key", {
  # XM_079904330 vs XM_079904330.1 sanitise to distinct names; the 34 cached
  # files that "looked versioned" on disk were RefSeq prefixes, not versions.
  d <- .fasta_tmpdir()
  local_mocked_bindings(
    .fetch_fasta_batched = function(accessions, batch_size = 200L) {
      paste0(">", accessions[1L], " x\nAAAA\n")
    },
    .package = "TaxaLikely"
  )
  TaxaLikely:::.fetch_fasta_cached("XM_079904330.1", cache_dir = d)
  TaxaLikely:::.fetch_fasta_cached("XM_079904330", cache_dir = d)
  expect_setequal(
    list.files(file.path(d, "fasta")),
    c("XM_079904330_1_seq.rds", "XM_079904330_seq.rds")
  )
})


# --- .fetch_summaries_batched() must actually emit acc_version ---------------
# Field names and values below are a REAL rentrez::entrez_summary(db =
# "nucleotide") record, captured live 2026-09-14. `caption` is unversioned,
# `accessionversion` is versioned; both ride the same batched call, so this
# costs no extra NCBI round trip.

test_that(".fetch_summaries_batched() carries the versioned accession", {
  fake_summary <- function(db, web_history, retstart, retmax) {
    list(
      list(
        uid = "1816411", caption = "AB000667", accessionversion = "AB000667.1",
        title = "Paralichthys olivaceus mitochondrial Cyt-b gene",
        taxid = "8267", slen = 3576, organism = "Paralichthys olivaceus",
        createdate = "1997/03/06"
      ),
      list(
        uid = "3192188758", caption = "XM_079904330",
        accessionversion = "XM_079904330.1", title = "predicted mRNA",
        taxid = "9999", slen = 1882, organism = "Somethingus exampleii",
        createdate = "2026/01/01"
      )
    )
  }
  local_mocked_bindings(entrez_summary = fake_summary, .package = "rentrez")

  out <- TaxaLikely:::.fetch_summaries_batched(
    list(count = "2", web_history = NULL)
  )
  expect_identical(out$acc, c("AB000667", "XM_079904330"))
  expect_identical(out$acc_version, c("AB000667.1", "XM_079904330.1"))
  # acc must STAY unversioned: composite_id is derived from it, and
  # .fetch_locations_batched() joins on GBSeq_primary-accession, which
  # carries no version.
  expect_false(any(grepl("\\.[0-9]+$", out$acc)))

  keys <- TaxaLikely:::.fasta_cache_keys(out)
  expect_identical(as.character(keys), c("AB000667.1", "XM_079904330.1"))
  expect_identical(attr(keys, "n_unversioned"), 0L)
})

test_that(".fetch_summaries_batched() tolerates a record with no version", {
  fake_summary <- function(db, web_history, retstart, retmax) {
    list(list(
      uid = "1", caption = "AB000667", title = "x", taxid = "1",
      slen = 100, organism = "y", createdate = "2000/01/01"
    ))
  }
  local_mocked_bindings(entrez_summary = fake_summary, .package = "rentrez")

  out <- TaxaLikely:::.fetch_summaries_batched(
    list(count = "1", web_history = NULL)
  )
  expect_true(is.na(out$acc_version))
  expect_identical(as.character(TaxaLikely:::.fasta_cache_keys(out)), "AB000667")
})
