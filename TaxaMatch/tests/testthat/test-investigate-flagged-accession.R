# ==============================================================================
# Tests for investigate_flagged_accession() / investigate_flagged_accessions()
# and their internal helpers (.blast_against_comparison_set(),
# .get_species_comparison_meta(), .investigate_verdict(), the persistent
# cache helpers).
#
# Fully offline: .fetch_reference_accession_records(), .search_species_
# accessions(), blast_sequences(), and .blast_remote() are all mocked via
# local_mocked_bindings(), matching test-evaluate-reference-accessions.R's
# established pattern.
#
# TWO different BLAST entry points are exercised in the real code path, and
# must be mocked separately:
#   - blast_sequences() -- the disagreeing-taxon DISCOVERY re-BLAST
#     (asv_id = the flagged accession itself), unchanged from before.
#   - .blast_remote() -- .blast_against_comparison_set()'s own
#     ENTREZ_QUERY-restricted comparison-set search (method = "remote",
#     the default), called directly rather than through the public
#     blast_sequences(). This split is itself the fix for a real bug found
#     live (2026-08-08) against the real MZ605481 case: an earlier version
#     of .blast_against_comparison_set() called blast_sequences() with an
#     UNRESTRICTED search and post-hoc-filtered the top hits down to the
#     comparison set -- and returned ZERO matches even for accessions
#     independently confirmed to exist, because they never happened to
#     rank among the unrestricted top hits. See .blast_against_comparison_
#     set()'s own roxygen `@section A real, live-found correction`.
# ==============================================================================

.blast_against_comparison_set_int <- function(...)
  get(".blast_against_comparison_set", envir = asNamespace("TaxaMatch"))(...)
.investigate_verdict_int <- function(...)
  get(".investigate_verdict", envir = asNamespace("TaxaMatch"))(...)
.filter_and_cap_accessions_int <- function(...)
  get(".filter_and_cap_accessions", envir = asNamespace("TaxaMatch"))(...)

# ------------------------------------------------------------------------------
# .filter_and_cap_accessions() -- the length-ratio pre-filter (Option B),
# extracted from .search_species_accessions() so its logic is directly
# unit-testable without mocking rentrez::entrez_search()/entrez_summary()
# (this package's convention mocks only its own internal NCBI-fetch
# wrappers). Confirmed REQUIRED, not optional, by live testing 2026-08-08:
# a real .search_species_accessions("Pseudorasbora parva") call returned 26
# of 30 candidates as whole-chromosome shotgun-assembly records 60-80+
# million bp long (a real published-reference-genome species) -- this
# fixture mirrors that exact real shape.
# ------------------------------------------------------------------------------

test_that(".filter_and_cap_accessions() discards whole-genome-assembly-scale candidates", {
  # Mirrors the real MZ605481 case: a 173bp flagged amplicon, 2 real
  # chromosome-assembly accessions (tens of millions of bp), 1 real
  # comparable-length barcode accession (643bp, still a real gene, just a
  # different one -- COI, not this test's concern).
  accs <- c("MZ605481_LIKE", "CM184582", "CM184583", "PV841430")
  lens <- c(173, 76718285, 69816937, 643)

  out <- .filter_and_cap_accessions_int(
    accs, lens, exclude = character(0L), max_records = 30L,
    reference_length = 173, max_length_ratio = 3
  )
  # 173*3 = 519 -- PV841430 (643bp) is just OUTSIDE the ratio window at this
  # setting; only the exact-length candidate itself would ever be kept from
  # this particular fixture. The chromosome-scale candidates are excluded
  # by many orders of magnitude either way.
  expect_false("CM184582" %in% out)
  expect_false("CM184583" %in% out)
})

test_that(".filter_and_cap_accessions() keeps a length-comparable candidate and applies the ratio symmetrically", {
  accs <- c("SHORT_OK", "TOO_LONG", "TOO_SHORT", "HUGE_GENOME")
  lens <- c(200, 700, 40, 76718285)  # reference_length = 173, ratio = 3 -> window [57.7, 519]

  out <- .filter_and_cap_accessions_int(
    accs, lens, exclude = character(0L), max_records = 30L,
    reference_length = 173, max_length_ratio = 3
  )
  expect_true("SHORT_OK" %in% out)
  expect_false("TOO_LONG" %in% out)
  expect_false("TOO_SHORT" %in% out)
  expect_false("HUGE_GENOME" %in% out)
})

test_that(".filter_and_cap_accessions() skips the length filter entirely when reference_length is NULL/invalid", {
  accs <- c("A", "B", "HUGE")
  lens <- c(173, 200, 76718285)

  out_null <- .filter_and_cap_accessions_int(
    accs, lens, exclude = character(0L), max_records = 30L,
    reference_length = NULL, max_length_ratio = 3
  )
  expect_setequal(out_null, c("A", "B", "HUGE"))

  out_na <- .filter_and_cap_accessions_int(
    accs, lens, exclude = character(0L), max_records = 30L,
    reference_length = NA_real_, max_length_ratio = 3
  )
  expect_setequal(out_na, c("A", "B", "HUGE"))
})

test_that(".filter_and_cap_accessions() excludes NA accessions, applies exclude and max_records", {
  accs <- c("A", NA, "B", "C")
  lens <- c(100, 100, 100, 100)

  out <- .filter_and_cap_accessions_int(
    accs, lens, exclude = "B", max_records = 1L,
    reference_length = NULL, max_length_ratio = 3
  )
  expect_equal(length(out), 1L)
  expect_true(out %in% c("A", "C"))
})

test_that(".filter_and_cap_accessions() excludes a candidate with unknown (NA) length when a reference_length is set", {
  # A real length-filter case: an accession NCBI's ESummary didn't return a
  # usable slen for should not be assumed comparable -- exclude, not include.
  accs <- c("KNOWN_OK", "UNKNOWN_LEN")
  lens <- c(180, NA_real_)

  out <- .filter_and_cap_accessions_int(
    accs, lens, exclude = character(0L), max_records = 30L,
    reference_length = 173, max_length_ratio = 3
  )
  expect_equal(out, "KNOWN_OK")
})

# ------------------------------------------------------------------------------
# .blast_against_comparison_set() -- Option A's BLAST-based replacement for
# the original pwalign::pairwiseAlignment() loop
# ------------------------------------------------------------------------------

test_that(".blast_against_comparison_set() (remote) filters to the comparison set and marks low-coverage hits", {
  # .blast_remote()'s raw return shape uses BLAST's own column names
  # (sacc/pident/qcovs), not blast_sequences()'s renamed output.
  mock_remote <- function(seq_df, database, program, megablast, max_target_seqs,
                          batch_size, email, ncbi_api_key, verbose, entrez_query = NULL) {
    expect_true(!is.null(entrez_query) && nzchar(entrez_query))
    data.frame(
      sacc = c("KEEP_A", "KEEP_B", "NOT_IN_SET"),
      pident = c(99, 100, 50),
      qcovs = c(90, 10, 5),
      stringsAsFactors = FALSE
    )
  }
  local_mocked_bindings(.blast_remote = mock_remote, .package = "TaxaMatch")

  comparison_meta <- data.frame(
    accession = c("KEEP_A", "KEEP_B"),
    sequence = c("X", "Y"),
    create_date = c("2020/01/01", "2020/02/01"),
    stringsAsFactors = FALSE
  )
  out <- .blast_against_comparison_set_int(
    "QUERYSEQ", comparison_meta, min_coverage = 0.5, verbose = FALSE
  )

  expect_setequal(out$accession, c("KEEP_A", "KEEP_B"))
  expect_true(out$meets_min_coverage[out$accession == "KEEP_A"])
  expect_false(out$meets_min_coverage[out$accession == "KEEP_B"])
  # NOT_IN_SET is a real BLAST hit but not part of the comparison set --
  # honestly absent, not force-included.
  expect_false("NOT_IN_SET" %in% out$accession)
})

test_that(".blast_against_comparison_set() returns an empty frame for an empty comparison set", {
  out <- .blast_against_comparison_set_int(
    "QUERYSEQ",
    data.frame(accession = character(0L), sequence = character(0L),
              create_date = character(0L), stringsAsFactors = FALSE),
    verbose = FALSE
  )
  expect_equal(nrow(out), 0L)
  expect_named(out, c("accession", "pident", "coverage", "meets_min_coverage", "create_date"))
})

test_that(".blast_against_comparison_set() (remote) honestly omits a comparison accession BLAST never surfaced", {
  mock_remote <- function(seq_df, database, program, megablast, max_target_seqs,
                          batch_size, email, ncbi_api_key, verbose, entrez_query = NULL) {
    data.frame(sacc = "KEEP_A", pident = 99, qcovs = 90, stringsAsFactors = FALSE)
  }
  local_mocked_bindings(.blast_remote = mock_remote, .package = "TaxaMatch")

  comparison_meta <- data.frame(
    accession = c("KEEP_A", "NEVER_A_HIT"),
    sequence = c("X", "Y"),
    create_date = c("2020/01/01", "2020/02/01"),
    stringsAsFactors = FALSE
  )
  out <- .blast_against_comparison_set_int("QUERYSEQ", comparison_meta, verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$accession, "KEEP_A")
})

test_that(".blast_against_comparison_set() (remote) restricts the BLAST search space via ENTREZ_QUERY", {
  captured_query <- NULL
  mock_remote <- function(seq_df, database, program, megablast, max_target_seqs,
                          batch_size, email, ncbi_api_key, verbose, entrez_query = NULL) {
    captured_query <<- entrez_query
    data.frame(sacc = character(0L), pident = numeric(0L), qcovs = numeric(0L),
              stringsAsFactors = FALSE)
  }
  local_mocked_bindings(.blast_remote = mock_remote, .package = "TaxaMatch")

  comparison_meta <- data.frame(
    accession = c("ACC1", "ACC2"), sequence = c("X", "Y"),
    create_date = c("2020/01/01", "2020/02/01"), stringsAsFactors = FALSE
  )
  .blast_against_comparison_set_int("QUERYSEQ", comparison_meta, verbose = FALSE)

  expect_true(grepl("ACC1\\[ACCN\\]", captured_query))
  expect_true(grepl("ACC2\\[ACCN\\]", captured_query))
  expect_true(grepl(" OR ", captured_query))
})

test_that(".blast_against_comparison_set() (local) falls back to post-hoc filtering via blast_sequences()", {
  # method = "local" has no ENTREZ_QUERY-equivalent restriction via rBLAST
  # -- this is the deliberately weaker fallback path, still exercised via
  # the public blast_sequences() (unlike the remote path above).
  mock_blast <- function(seq_df, ...) {
    data.frame(
      observation_id = "flagged_query",
      accession = c("KEEP_A", "NOT_IN_SET"),
      score = c(99, 50),
      query_coverage = c(90, 5),
      stringsAsFactors = FALSE
    )
  }
  local_mocked_bindings(blast_sequences = mock_blast, .package = "TaxaMatch")

  comparison_meta <- data.frame(
    accession = "KEEP_A", sequence = "X", create_date = "2020/01/01",
    stringsAsFactors = FALSE
  )
  out <- .blast_against_comparison_set_int(
    "QUERYSEQ", comparison_meta, method = "local", verbose = FALSE
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$accession, "KEEP_A")
})

# ------------------------------------------------------------------------------
# .investigate_verdict()
# ------------------------------------------------------------------------------

test_that(".investigate_verdict() classifies inconclusive-vs-evaluated correctly", {
  ok_result <- list(
    conspecific_comparison = data.frame(meets_min_coverage = c(TRUE, FALSE)),
    disagreeing_taxon_comparison = data.frame(meets_min_coverage = logical(0L))
  )
  expect_equal(.investigate_verdict_int(ok_result), "evaluated")

  inconclusive_result <- list(
    conspecific_comparison = data.frame(meets_min_coverage = c(FALSE, FALSE)),
    disagreeing_taxon_comparison = data.frame(meets_min_coverage = logical(0L))
  )
  expect_equal(.investigate_verdict_int(inconclusive_result), "inconclusive_length_mismatch")
})

# ------------------------------------------------------------------------------
# investigate_flagged_accession() / investigate_flagged_accessions() --
# full offline integration, mirroring the real MZ605481 case's shape (a
# self-consistency comparison with one weak/one coverage-failing hit, and a
# cross-taxon comparison with strong, coverage-safe identity)
# ------------------------------------------------------------------------------

.records_fixture_iv <- function() {
  data.frame(
    accession = c("ACC_FLAG", "ACC_FLAG2", "PPARVA_A", "PPARVA_B",
                 "CARPIO_A", "CARPIO_B", "HIT_CARPIO1", "HIT_SAMEBATCH"),
    # ACC_FLAG2's own sequence is deliberately the SAME LENGTH as ACC_FLAG's
    # (8 chars) -- the batch-sharing cache is keyed on (species,
    # reference_length) since 2026-08-08 (see .get_species_comparison_
    # meta()'s own @section Cache key includes reference_length), so two
    # flagged accessions only share one NCBI fetch when their sequence
    # lengths ALSO match, not just their listed species.
    sequence = c("QUERYSEQ", "QUERYSEZ", "PPARVA_A_SEQ", "PPARVA_B_SEQ",
                "CARPIO_A_SEQ", "CARPIO_B_SEQ", "HIT_CARPIO1_SEQ", "HIT_SAMEBATCH_SEQ"),
    organism = c("Pseudorasbora parva", "Pseudorasbora parva",
                NA, NA, NA, NA, NA, NA),
    create_date = c("2020/01/01", "2020/03/01", "2019/05/01", "2018/03/01",
                    "2021/07/01", "2021/08/01", "2021/07/15", "2020/01/02"),
    stringsAsFactors = FALSE
  )
}

.mock_fetch_records_iv <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL,
                                   verbose = TRUE) {
  fx <- .records_fixture_iv()
  out <- fx[fx$accession %in% accessions, , drop = FALSE]
  if (!want_sequence) out$sequence <- NA_character_
  rownames(out) <- NULL
  out
}

.mock_search_species_accessions <- function(species, exclude = character(0L), max_records = 30L,
                                            reference_length = NULL, max_length_ratio = 3,
                                            ncbi_api_key = NULL, verbose = TRUE) {
  strip_v <- function(x) sub("\\.[0-9]+$", "", x)
  ids <- if (identical(species, "Pseudorasbora parva")) {
    c("PPARVA_A", "PPARVA_B")
  } else if (identical(species, "Cyprinus carpio")) {
    c("CARPIO_A", "CARPIO_B")
  } else {
    character(0L)
  }
  ids <- ids[!strip_v(ids) %in% strip_v(exclude)]
  utils::head(ids, max_records)
}

# ACC_FLAG (and ACC_FLAG2, same listed species) re-BLASTs (blast_sequences())
# to HIT_CARPIO1/HIT_SAMEBATCH ("Cyprinus carpio" both) -- HIT_SAMEBATCH is
# same-submission-batch with ACC_FLAG (dates 2 days apart) so gets excluded
# from ACC_FLAG's own independent hits, same PV382872-style independence-
# filter test this file's sibling already establishes.
.mock_blast_sequences_iv <- function(seq_df, method = "remote", database = "nt",
                                     score_range = 8, min_score = 70, max_hits = 20L,
                                     resolve_taxonomy = TRUE, ...) {
  data.frame(
    observation_id = seq_df$asv_id[1L],
    accession = c("HIT_CARPIO1", "HIT_SAMEBATCH"),
    score = c(99.5, 99.8),
    query_coverage = c(97, 98),
    species = c("Cyprinus carpio", "Cyprinus carpio"),
    stringsAsFactors = FALSE
  )
}

# .blast_against_comparison_set()'s own ENTREZ_QUERY-restricted comparison-
# set calls (asv_id always "flagged_query") -- returns the UNION of every
# real comparison accession's own hit; .blast_against_comparison_set()
# always post-filters down to its OWN caller-supplied comparison_meta$
# accession set, so a superset response works identically for both the
# self- and cross-taxon calls. PPARVA_B is deliberately low-coverage (15%,
# below the 50% default floor), mirroring the real coverage-blindness case
# this function's Option A fix exists to catch honestly rather than
# silently.
.mock_blast_remote_iv <- function(seq_df, database, program, megablast, max_target_seqs,
                                  batch_size, email, ncbi_api_key, verbose,
                                  entrez_query = NULL) {
  data.frame(
    sacc = c("PPARVA_A", "PPARVA_B", "CARPIO_A", "CARPIO_B"),
    pident = c(97, 99, 100, 100),
    qcovs = c(90, 15, 96, 94),
    stringsAsFactors = FALSE
  )
}

.mock_all_investigate <- function(expr) {
  local_mocked_bindings(
    .fetch_reference_accession_records = .mock_fetch_records_iv,
    .search_species_accessions = .mock_search_species_accessions,
    blast_sequences = .mock_blast_sequences_iv,
    .blast_remote = .mock_blast_remote_iv,
    .package = "TaxaMatch"
  )
  force(expr)
}

test_that("investigate_flagged_accession() runs both comparisons via BLAST and reports coverage-safe results", {
  .mock_all_investigate({
    out <- investigate_flagged_accession("ACC_FLAG", cache_dir = NULL, verbose = FALSE)
  })

  expect_equal(out$accession, "ACC_FLAG")
  expect_equal(out$listed_species, "Pseudorasbora parva")
  expect_equal(out$disagreeing_taxon, "Cyprinus carpio")

  self_cmp <- out$conspecific_comparison
  expect_setequal(self_cmp$accession, c("PPARVA_A", "PPARVA_B"))
  expect_true(self_cmp$meets_min_coverage[self_cmp$accession == "PPARVA_A"])
  expect_false(self_cmp$meets_min_coverage[self_cmp$accession == "PPARVA_B"])

  cross_cmp <- out$disagreeing_taxon_comparison
  expect_setequal(cross_cmp$accession, c("CARPIO_A", "CARPIO_B"))
  expect_true(all(cross_cmp$meets_min_coverage))
  expect_true(all(cross_cmp$pident == 100))
})

test_that("investigate_flagged_accession() validates its accession argument", {
  expect_error(investigate_flagged_accession(123), "single non-NA")
  expect_error(investigate_flagged_accession(c("A", "B")), "single non-NA")
  expect_error(investigate_flagged_accession(NA_character_), "single non-NA")
  expect_error(investigate_flagged_accession(""), "single non-NA")
})

test_that("investigate_flagged_accession() caches results across calls", {
  cache_dir <- withr::local_tempdir()
  fetch_calls <- 0L
  counting_fetch <- function(...) {
    fetch_calls <<- fetch_calls + 1L
    .mock_fetch_records_iv(...)
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch,
    .search_species_accessions = .mock_search_species_accessions,
    blast_sequences = .mock_blast_sequences_iv,
    .blast_remote = .mock_blast_remote_iv,
    .package = "TaxaMatch"
  )

  out1 <- investigate_flagged_accession("ACC_FLAG", cache_dir = cache_dir, verbose = FALSE)
  calls_after_first <- fetch_calls
  expect_gt(calls_after_first, 0L)

  out2 <- investigate_flagged_accession("ACC_FLAG", cache_dir = cache_dir, verbose = FALSE)
  expect_equal(fetch_calls, calls_after_first)  # no new fetches -- pure cache hit
  expect_equal(out2, out1)
})

test_that("investigate_flagged_accession() gracefully discards an old-schema cache file instead of erroring", {
  cache_dir <- withr::local_tempdir()
  dir.create(cache_dir, showWarnings = FALSE)
  old_schema_cache <- data.frame(accession = "ACC_FLAG", stringsAsFactors = FALSE)
  saveRDS(old_schema_cache, file.path(cache_dir, "investigate_flagged_accession_cache.rds"))

  .mock_all_investigate({
    expect_warning(
      out <- investigate_flagged_accession("ACC_FLAG", cache_dir = cache_dir, verbose = FALSE),
      "predates this package version"
    )
  })
  expect_equal(out$accession, "ACC_FLAG")
})

# .mock_blast_remote_iv, above, is deliberately built so BOTH the
# self-consistency and cross-taxon comparisons have at least one
# coverage-clearing hit -- i.e. an "evaluated" verdict, cached indefinitely.
# This separate, low-coverage-everywhere mock reproduces the real
# MZ605481-class "inconclusive_length_mismatch" outcome instead, to test
# the asymmetric short-TTL cache path.
.mock_blast_remote_inconclusive <- function(seq_df, database, program, megablast,
                                            max_target_seqs, batch_size, email,
                                            ncbi_api_key, verbose, entrez_query = NULL) {
  data.frame(
    sacc = c("PPARVA_A", "PPARVA_B", "CARPIO_A", "CARPIO_B"),
    pident = c(97, 99, 100, 100),
    qcovs = c(4, 4, 4, 4),  # every hit below the 50% default coverage floor
    stringsAsFactors = FALSE
  )
}

test_that("investigate_flagged_accession() caches an inconclusive verdict with a short TTL and retries after it expires", {
  cache_dir <- withr::local_tempdir()
  search_calls <- 0L
  counting_search <- function(...) {
    search_calls <<- search_calls + 1L
    .mock_search_species_accessions(...)
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = .mock_fetch_records_iv,
    .search_species_accessions = counting_search,
    blast_sequences = .mock_blast_sequences_iv,
    .blast_remote = .mock_blast_remote_inconclusive,
    .package = "TaxaMatch"
  )

  out1 <- investigate_flagged_accession(
    "ACC_FLAG", cache_dir = cache_dir, inconclusive_ttl_days = 10, verbose = FALSE
  )
  expect_equal(.investigate_verdict_int(out1), "inconclusive_length_mismatch")
  calls_after_first <- search_calls
  expect_gt(calls_after_first, 0L)

  # Immediately re-calling stays a cache hit (well within the 10-day TTL).
  investigate_flagged_accession(
    "ACC_FLAG", cache_dir = cache_dir, inconclusive_ttl_days = 10, verbose = FALSE
  )
  expect_equal(search_calls, calls_after_first)

  # Backdate the cached evaluated_at past the short TTL and confirm it's retried.
  cache_path <- file.path(cache_dir, "investigate_flagged_accession_cache.rds")
  cached <- readRDS(cache_path)
  cached$evaluated_at <- cached$evaluated_at - (11 * 86400)
  saveRDS(cached, cache_path)

  investigate_flagged_accession(
    "ACC_FLAG", cache_dir = cache_dir, inconclusive_ttl_days = 10, verbose = FALSE
  )
  expect_gt(search_calls, calls_after_first)
})

test_that("investigate_flagged_accessions() validates its inputs", {
  expect_error(investigate_flagged_accessions(character(0L)), "non-empty")
  expect_error(investigate_flagged_accessions(c("A", NA)), "no NA or blank")
  expect_error(investigate_flagged_accessions(c("A", "")), "no NA or blank")
  expect_error(investigate_flagged_accessions("A", species = c("X", "Y")), "same length")
})

test_that("investigate_flagged_accessions() shares NCBI species searches across a batch", {
  search_calls <- character(0L)
  counting_search <- function(species, ...) {
    search_calls <<- c(search_calls, species)
    .mock_search_species_accessions(species, ...)
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = .mock_fetch_records_iv,
    .search_species_accessions = counting_search,
    blast_sequences = .mock_blast_sequences_iv,
    .blast_remote = .mock_blast_remote_iv,
    .package = "TaxaMatch"
  )

  out <- investigate_flagged_accessions(
    c("ACC_FLAG", "ACC_FLAG2"), cache_dir = NULL, verbose = FALSE
  )

  expect_equal(length(out), 2L)
  expect_named(out, c("ACC_FLAG", "ACC_FLAG2"))
  expect_equal(out$ACC_FLAG$listed_species, "Pseudorasbora parva")
  expect_equal(out$ACC_FLAG2$listed_species, "Pseudorasbora parva")
  expect_equal(out$ACC_FLAG$disagreeing_taxon, "Cyprinus carpio")
  expect_equal(out$ACC_FLAG2$disagreeing_taxon, "Cyprinus carpio")

  # ACC_FLAG and ACC_FLAG2 share BOTH listed_species ("Pseudorasbora parva")
  # and disagreeing_taxon ("Cyprinus carpio") -- each species should be
  # searched via .search_species_accessions() exactly ONCE across the whole
  # batch, not once per accession (Question 3, item 2).
  expect_equal(sum(search_calls == "Pseudorasbora parva"), 1L)
  expect_equal(sum(search_calls == "Cyprinus carpio"), 1L)
})

test_that("investigate_flagged_accessions() reuses investigate_flagged_accession()'s own persistent cache", {
  cache_dir <- withr::local_tempdir()
  fetch_calls <- 0L
  counting_fetch <- function(...) {
    fetch_calls <<- fetch_calls + 1L
    .mock_fetch_records_iv(...)
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = counting_fetch,
    .search_species_accessions = .mock_search_species_accessions,
    blast_sequences = .mock_blast_sequences_iv,
    .blast_remote = .mock_blast_remote_iv,
    .package = "TaxaMatch"
  )

  investigate_flagged_accession("ACC_FLAG", cache_dir = cache_dir, verbose = FALSE)
  calls_after_single <- fetch_calls

  # A subsequent batch call covering the SAME accession (plus a new one)
  # should reuse the cached ACC_FLAG result -- fetch_calls should only grow
  # by whatever ACC_FLAG2 alone requires, not by ACC_FLAG's own work again.
  out <- investigate_flagged_accessions(
    c("ACC_FLAG", "ACC_FLAG2"), cache_dir = cache_dir, verbose = FALSE
  )
  expect_equal(out$ACC_FLAG$disagreeing_taxon, "Cyprinus carpio")
  expect_gt(fetch_calls, calls_after_single)  # ACC_FLAG2 still needed real work

  fetch_calls <- 0L
  out2 <- investigate_flagged_accessions(
    c("ACC_FLAG", "ACC_FLAG2"), cache_dir = cache_dir, verbose = FALSE
  )
  expect_equal(fetch_calls, 0L)  # both now pure cache hits
  expect_equal(out2$ACC_FLAG, out$ACC_FLAG)
  expect_equal(out2$ACC_FLAG2, out$ACC_FLAG2)
})
