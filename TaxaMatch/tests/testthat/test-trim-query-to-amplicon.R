# .trim_queries_to_amplicon() / .extract_amplicon_one_tm() require Biostrings
# (Bioconductor -- Suggests). Fixture mirrors TaxaLikely's own
# test-trim-to-amplicon.R exactly (a real, verified MiFish-U primer pair
# wrapped around an arbitrary interior, embedded in a long flanking "genome"
# context) -- these two functions are algorithm-identical duplicates (see
# their own roxygen for why), so the same fixture shape is deliberate, not
# copy-paste-without-thought.

.mf_fwd <- "GTCGGTAAAACTCGTGCCAGC"
.mf_rev <- "CATAGTGGGGTATCTAATCCCAGTTTG"

# Interior sized so fwd(21) + interior(173) + rev_rc(27) = 221bp total --
# matching the REAL, empirically-measured full primer-inclusive MiFish-U span
# (confirmed 2026-08-10 against two real fish mitogenomes fetched live from
# NCBI, Danio rerio and Cyprinus carpio -- both gave an identical 221bp span).
# Deliberately NOT sized to fit inside TaxaTools::resolve_barcode_lengths(
# "MiFishU")'s general 130-210bp marker-length window -- an earlier version of
# this fixture was, and that silently masked a real bug where every genuine
# real-data MiFish-U hit was rejected by the plausible-span check (which now
# derives its bound from primer_info$amplicon_range + primer length instead;
# see .trim_queries_to_amplicon()'s own comment for the full account).
.build_genome_tm <- function(fwd = .mf_fwd, rev = .mf_rev,
                             interior = paste0(strrep("AAACCCGGGTTT", 14L), "AAAAA"),
                             flank5 = 300L, flank3 = 300L) {
  rev_rc <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(rev)))
  amplicon <- paste0(fwd, interior, rev_rc)
  genome <- paste0(strrep("N", flank5), amplicon, strrep("A", flank3))
  list(genome = genome, amplicon = amplicon, amplicon_len = nchar(amplicon))
}

test_that(".extract_amplicon_one_tm() correctly extracts a real MiFish-U amplicon from a synthetic over-length sequence", {
  skip_if_not_installed("Biostrings")
  g <- .build_genome_tm()
  rev_rc <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(.mf_rev)))
  result <- .extract_amplicon_one_tm(
    seq_char = g$genome, fwd_pattern = .mf_fwd, rev_pattern_rc = rev_rc,
    fwd_max_mm = 3L, rev_max_mm = 4L, min_len = 100L, max_len = 250L
  )
  expect_true(result$trimmed)
  expect_equal(result$sequence, g$amplicon)
  expect_match(result$note, "^extracted_via_primer_match_")
})

test_that(".extract_amplicon_one_tm() falls back gracefully when primers aren't found", {
  skip_if_not_installed("Biostrings")
  result <- .extract_amplicon_one_tm(
    seq_char = strrep("N", 500L), fwd_pattern = .mf_fwd, rev_pattern_rc = "AAAA",
    fwd_max_mm = 3L, rev_max_mm = 4L, min_len = 100L, max_len = 250L
  )
  expect_false(result$trimmed)
  expect_true(is.na(result$sequence))
  expect_equal(result$note, "primers_not_found_or_implausible_span")
})

test_that(".extract_amplicon_one_tm() handles missing/empty sequence", {
  skip_if_not_installed("Biostrings")
  result <- .extract_amplicon_one_tm(
    seq_char = NA_character_, fwd_pattern = .mf_fwd, rev_pattern_rc = "AAAA",
    fwd_max_mm = 3L, rev_max_mm = 4L, min_len = 100L, max_len = 250L
  )
  expect_equal(result$note, "missing_sequence")
})

test_that(".trim_queries_to_amplicon() trims only over-length sequences, leaves short ones untouched", {
  skip_if_not_installed("Biostrings")
  g <- .build_genome_tm()
  short_seq <- g$amplicon # already barcode-length, should NOT be touched
  sequences <- c(g$genome, short_seq)

  # Primer-INCLUSIVE span (the only behaviour before 2026-09-03).
  out <- .trim_queries_to_amplicon(sequences,
    barcode_term = "MiFishU",
    strip_primers = FALSE, verbose = FALSE
  )
  expect_equal(out[1], g$amplicon) # over-length -> trimmed
  expect_equal(out[2], short_seq) # already short -> untouched

  # Default (2026-09-03): primer-STRIPPED. The genome trims to the interior,
  # and a primer-inclusive input (221 bp > max_bp) is stripped to the same
  # interior; a primer-free interior passes through unchanged.
  interior <- substr(g$amplicon, nchar(.mf_fwd) + 1L, nchar(g$amplicon) - nchar(.mf_rev))
  out_default <- .trim_queries_to_amplicon(c(g$genome, short_seq, interior),
    barcode_term = "MiFishU", verbose = FALSE
  )
  expect_equal(as.character(out_default), c(interior, interior, interior))
  # Per-sequence trim record (2026-09-04): the genome and the inclusive input
  # were both shortened; the already-interior one was not.
  expect_equal(attr(out_default, "trimmed"), c(TRUE, TRUE, FALSE))
})

test_that(".trim_queries_to_amplicon() leaves an over-length sequence unchanged when primers can't be found", {
  skip_if_not_installed("Biostrings")
  no_primer_genome <- strrep("N", 500L)
  out <- .trim_queries_to_amplicon(no_primer_genome, barcode_term = "MiFishU", verbose = FALSE)
  expect_equal(as.character(out), no_primer_genome) # unchanged, not dropped or NA'd
  expect_false(attr(out, "trimmed"))
})

test_that("evaluate_reference_accessions(barcode_term =) trims an over-length query before BLASTing it", {
  skip_if_not_installed("Biostrings")
  g <- .build_genome_tm()

  seen_sequence <- NULL
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(
      accession = "ACC001", organism = "Testus fishus", create_date = "2020/01/01",
      sequence = g$genome, stringsAsFactors = FALSE
    )
  }
  mock_blast <- function(seq_df, ...) {
    seen_sequence <<- seq_df$sequence[seq_df$asv_id == "ACC001"]
    fx <- data.frame(
      observation_id = character(0), accession = character(0), score = numeric(0),
      family = character(0), genus = character(0), species = character(0),
      stringsAsFactors = FALSE
    )
    fx
  }
  mock_tax <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(accession = character(0), stringsAsFactors = FALSE)
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = mock_blast, .package = "TaxaMatch")
  local_mocked_bindings(.resolve_taxonomy_by_acc = mock_tax, .package = "TaxaMatch")

  suppressWarnings(evaluate_reference_accessions(
    "ACC001",
    cache_dir = NULL, barcode_term = "MiFishU", verbose = FALSE,
    query_span = "primer_inclusive"
  ))
  expect_equal(seen_sequence, g$amplicon)
  expect_lt(nchar(seen_sequence), nchar(g$genome))

  # Default query_span = "amplicon" (2026-09-03): the primers are stripped.
  suppressWarnings(evaluate_reference_accessions(
    "ACC001",
    cache_dir = NULL, barcode_term = "MiFishU", verbose = FALSE
  ))
  expect_equal(
    seen_sequence,
    substr(g$amplicon, nchar(.mf_fwd) + 1L, nchar(g$amplicon) - nchar(.mf_rev))
  )
})

test_that(".trim_queries_to_amplicon() isolates a per-accession extraction error instead of crashing the whole batch", {
  skip_if_not_installed("Biostrings")
  # Reproduces a real production crash (2026-08-30, PtConception 12S screen,
  # chunk 1/5 of a 200-accession batch): one accession's amplicon-extraction
  # coordinate math threw Biostrings::subseq()'s "Invalid sequence
  # coordinates" error, and with no per-accession isolation this aborted the
  # ENTIRE chunk -- losing progress on every other accession in it, not just
  # the one bad record. Confirms the fix: a per-accession error now degrades
  # to "leave this one sequence untrimmed" (the same fallback an ordinary
  # "primers not found" result gets), and a second, unrelated over-length
  # sequence in the same batch is still processed normally.
  g <- .build_genome_tm()

  call_n <- 0L
  mock_extract <- function(seq_char, ...) {
    call_n <<- call_n + 1L
    if (call_n == 1L) {
      stop(paste0(
        "Invalid sequence coordinates.\n",
        "  Please make sure the supplied 'start', 'end' and 'width' arguments\n",
        "  are defining a region that is within the limits of the sequence.."
      ))
    }
    list(sequence = g$amplicon, trimmed = TRUE, note = "extracted_via_primer_match_sense_strand")
  }
  local_mocked_bindings(.extract_amplicon_one_tm = mock_extract, .package = "TaxaMatch")

  sequences <- c(g$genome, g$genome)
  out <- NULL
  expect_no_error(
    out <- .trim_queries_to_amplicon(sequences, barcode_term = "MiFishU", verbose = FALSE)
  )

  expect_equal(out[1], g$genome) # the crashing sequence: left untrimmed, not lost
  expect_equal(out[2], g$amplicon) # a second, unrelated sequence: still processed normally
})

test_that("evaluate_reference_accessions() with barcode_term = NULL (default) submits queries at full length, unchanged", {
  skip_if_not_installed("Biostrings")
  g <- .build_genome_tm()

  seen_sequence <- NULL
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(
      accession = "ACC001", organism = "Testus fishus", create_date = "2020/01/01",
      sequence = g$genome, stringsAsFactors = FALSE
    )
  }
  mock_blast <- function(seq_df, ...) {
    seen_sequence <<- seq_df$sequence[seq_df$asv_id == "ACC001"]
    data.frame(
      observation_id = character(0), accession = character(0), score = numeric(0),
      family = character(0), genus = character(0), species = character(0),
      stringsAsFactors = FALSE
    )
  }
  mock_tax <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(accession = character(0), stringsAsFactors = FALSE)
  }

  local_mocked_bindings(
    .fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = mock_blast, .package = "TaxaMatch")
  local_mocked_bindings(.resolve_taxonomy_by_acc = mock_tax, .package = "TaxaMatch")

  suppressWarnings(evaluate_reference_accessions("ACC001", cache_dir = NULL, verbose = FALSE))

  expect_equal(seen_sequence, g$genome)
})

# ==============================================================================
# Feature-table-guided extraction fallback (2026-09-01) --
# .resolve_expected_marker() / .extract_feature_table_fallback() -- the
# rescue tried when primer trimming above leaves a query over-length.
# ==============================================================================

test_that(".resolve_expected_marker() bridges MiFish/Teleo-style barcode_term values to '12S'", {
  expect_equal(.resolve_expected_marker("MiFishU"), "12S")
  expect_equal(.resolve_expected_marker("mifish-e"), "12S")
  expect_equal(.resolve_expected_marker("teleo"), "12S")
})

test_that(".resolve_expected_marker() passes through a term .resolve_marker_pattern() already handles unchanged", {
  expect_equal(.resolve_expected_marker("18S_2"), "18S_2")
  expect_equal(.resolve_expected_marker("COI-Leray"), "COI-Leray")
})

.mock_ann_for_fallback <- function(feature_from = 301, feature_to = 500,
                                   gene = "12S", product = "12S ribosomal RNA",
                                   accession = "ACC001") {
  function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(
      accession = accession, feature_key = "rRNA",
      gene = gene, product = product,
      feature_from = feature_from, feature_to = feature_to,
      stringsAsFactors = FALSE
    )
  }
}

test_that(".extract_feature_table_fallback() extracts the matching feature's span plus margin", {
  full_seq <- strrep("N", 800L) # content-agnostic -- coordinate math only
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_ann_for_fallback(feature_from = 301, feature_to = 500),
    .package = "TaxaMatch"
  )
  out <- .extract_feature_table_fallback(
    accessions = "ACC001", sequences = full_seq, barcode_term = "MiFishU",
    margin = 100L, verbose = FALSE
  )
  # from = max(1, 301-100) = 201; to = min(800, 500+100) = 600 -> 400bp.
  expect_equal(nchar(out), 400L)
  expect_equal(as.character(out), substr(full_seq, 201L, 600L))
  # A rescued accession declines for no reason (2026-09-04).
  expect_true(is.na(attr(out, "decline_reason")))
})

test_that(".extract_feature_table_fallback() leaves a sequence unchanged when no annotated feature matches the marker", {
  full_seq <- strrep("N", 800L)
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_ann_for_fallback(gene = "16S", product = "16S ribosomal RNA"),
    .package = "TaxaMatch"
  )
  out <- .extract_feature_table_fallback(
    accessions = "ACC001", sequences = full_seq, barcode_term = "MiFishU", verbose = FALSE
  )
  expect_equal(as.character(out), full_seq)
  # The record HAS features and none is 12S -- positive evidence of a wrong
  # marker, distinct from "we could not look it up" (2026-09-04).
  expect_equal(attr(out, "decline_reason"), "marker_absent")
})

test_that(".extract_feature_table_fallback() leaves a sequence unchanged when the record has no annotation at all", {
  full_seq <- strrep("N", 800L)
  local_mocked_bindings(
    .fetch_marker_annotation = function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
      data.frame(
        accession = "ACC001", feature_key = NA_character_,
        gene = NA_character_, product = NA_character_,
        feature_from = NA_real_, feature_to = NA_real_,
        stringsAsFactors = FALSE
      )
    },
    .package = "TaxaMatch"
  )
  out <- .extract_feature_table_fallback(
    accessions = "ACC001", sequences = full_seq, barcode_term = "MiFishU", verbose = FALSE
  )
  expect_equal(as.character(out), full_seq)
  expect_equal(attr(out, "decline_reason"), "no_annotation")
})

test_that(".extract_feature_table_fallback() leaves a sequence unchanged on a degenerate zero-width feature span (bounds guard)", {
  full_seq <- strrep("N", 800L)
  local_mocked_bindings(
    # A single-point feature (from == to) with margin = 0 collapses to
    # from == to after clamping -- the same "not a usable span" outcome
    # .extract_amplicon_one_tm()'s own 2026-08-30 bounds guard produces for
    # an inverted/degenerate primer match; must degrade to "not rescued",
    # never a zero-length or nonsensical substr() result.
    .fetch_marker_annotation = .mock_ann_for_fallback(feature_from = 10, feature_to = 10),
    .package = "TaxaMatch"
  )
  out <- .extract_feature_table_fallback(
    accessions = "ACC001", sequences = full_seq, barcode_term = "MiFishU",
    margin = 0L, verbose = FALSE
  )
  expect_equal(as.character(out), full_seq)
  expect_equal(attr(out, "decline_reason"), "span_unusable")
})

test_that(".extract_feature_table_fallback() never errors when .fetch_marker_annotation() itself fails", {
  full_seq <- strrep("N", 800L)
  local_mocked_bindings(
    .fetch_marker_annotation = function(...) stop("simulated NCBI failure"),
    .package = "TaxaMatch"
  )
  out <- NULL
  expect_no_error(
    out <- .extract_feature_table_fallback(
      accessions = "ACC001", sequences = full_seq, barcode_term = "MiFishU", verbose = FALSE
    )
  )
  expect_equal(as.character(out), full_seq)
  # A failed fetch is "we do not know what this record contains", NOT
  # "this record carries a different marker" -- the two must not collapse,
  # since only the latter is actionable.
  expect_equal(attr(out, "decline_reason"), "no_annotation")
})

test_that("evaluate_reference_accessions(barcode_term=) feature-table fallback rescues a query with no primer hits but a matching annotated feature", {
  skip_if_not_installed("Biostrings")
  full_seq <- strrep("N", 800L) # no MiFish-U primer sites anywhere

  seen_sequence <- NULL
  mock_fetch <- function(accessions, want_sequence = TRUE, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(
      accession = "ACC001", organism = "Testus fishus", create_date = "2020/01/01",
      sequence = full_seq, stringsAsFactors = FALSE
    )
  }
  mock_blast <- function(seq_df, ...) {
    seen_sequence <<- seq_df$sequence[seq_df$asv_id == "ACC001"]
    data.frame(
      observation_id = character(0), accession = character(0), score = numeric(0),
      family = character(0), genus = character(0), species = character(0),
      stringsAsFactors = FALSE
    )
  }
  mock_tax <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
    data.frame(accession = character(0), stringsAsFactors = FALSE)
  }

  local_mocked_bindings(.fetch_reference_accession_records = mock_fetch, .package = "TaxaMatch")
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_ann_for_fallback(feature_from = 301, feature_to = 500),
    .package = "TaxaMatch"
  )
  local_mocked_bindings(blast_sequences = mock_blast, .package = "TaxaMatch")
  local_mocked_bindings(.resolve_taxonomy_by_acc = mock_tax, .package = "TaxaMatch")

  suppressWarnings(suppressMessages(evaluate_reference_accessions(
    "ACC001",
    cache_dir = NULL, barcode_term = "MiFishU", verbose = FALSE
  )))

  expect_false(is.null(seen_sequence))
  expect_lt(nchar(seen_sequence), nchar(full_seq))
  expect_equal(nchar(seen_sequence), 400L) # 201-600, see the unit test above
})

# ---- primer-inclusive vs variable-region length conventions (2026-09-02) -----
# The bug this section pins: .trim_queries_to_amplicon() returns a span that
# INCLUDES both primers, while TaxaTools::resolve_barcode_lengths() reports the
# variable region EXCLUDING them. For MiFish-U those windows are disjoint
# (211-233 vs 130-210), so testing a correctly-trimmed query against max_bp
# calls it over-length 100% of the time. It was fixed once inside the trimmer
# (2026-08-10) and reintroduced by the 2026-09-01 feature-table-fallback caller.

test_that(".resolve_trimmed_span_max() reports the primer-INCLUSIVE bound, above max_bp", {
  skip_if_not_installed("TaxaTools")
  span_max <- .resolve_trimmed_span_max("MiFishU")
  pi <- TaxaTools::resolve_barcode_primers("MiFishU")
  expect_equal(
    span_max,
    pi$amplicon_range[2] + nchar(pi$fwd) + nchar(pi$rev)
  )
  # The regression guard: the two conventions must not be confused again.
  expect_gt(span_max, TaxaTools::resolve_barcode_lengths("MiFishU")[["max_bp"]])
})

test_that("a correctly primer-trimmed MiFish-U query is NOT classified still-over-length", {
  skip_if_not_installed("TaxaTools")
  pi <- TaxaTools::resolve_barcode_primers("MiFishU")
  rev_rc <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(pi$rev)))
  set.seed(42)
  variable <- paste(sample(c("A", "C", "G", "T"), 170L, replace = TRUE), collapse = "")
  flank <- paste(sample(c("A", "C", "G", "T"), 2000L, replace = TRUE), collapse = "")
  full_seq <- paste0(flank, pi$fwd, variable, rev_rc, flank)

  trimmed <- .trim_queries_to_amplicon(full_seq,
    barcode_term = "MiFishU",
    strip_primers = FALSE, verbose = FALSE
  )
  # Really trimmed, and to the primer-inclusive span.
  expect_lt(nchar(trimmed), nchar(full_seq))
  expect_equal(nchar(trimmed), nchar(pi$fwd) + 170L + nchar(pi$rev))

  # The test evaluate_reference_accessions() actually applies. Under the old
  # max_bp bound this was TRUE for every successfully trimmed query.
  expect_false(nchar(trimmed) > .resolve_trimmed_span_max("MiFishU"))
  expect_true(nchar(trimmed) > TaxaTools::resolve_barcode_lengths("MiFishU")[["max_bp"]])

  # And the stripped counterpart (2026-09-03): the same query under the
  # default query_span is not still-over-length under the STRIPPED bound.
  stripped <- .trim_queries_to_amplicon(full_seq, barcode_term = "MiFishU", verbose = FALSE)
  expect_equal(nchar(stripped), 170L)
  expect_false(nchar(stripped) > .resolve_trimmed_span_max("MiFishU", strip_primers = TRUE))
})

test_that(".extract_feature_table_fallback() refuses a span that does not fit the sequence in hand", {
  # The failure this closes: feature coordinates describe the FULL deposited
  # record. Handed an already-trimmed 217bp query, the clamp degraded to
  # substr(seq, 1, 217) -- returning the input unchanged while counting itself
  # a rescue, which is how a real run reported "rescued 40 of 40" queries it
  # had not touched.
  short_seq <- strrep("A", 217L)
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_ann_for_fallback(feature_from = 68, feature_to = 1015),
    .package = "TaxaMatch"
  )
  out <- .extract_feature_table_fallback(
    accessions = "ACC001", sequences = short_seq, barcode_term = "MiFishU",
    margin = 100L, verbose = FALSE
  )
  expect_equal(as.character(out), short_seq) # unchanged...
  # The span exists and MATCHES the marker -- it simply does not fit the
  # sequence in hand, which is not a wrong-marker record (2026-09-04).
  expect_equal(attr(out, "decline_reason"), "span_unusable")
  expect_message(
    .extract_feature_table_fallback(
      accessions = "ACC001", sequences = short_seq, barcode_term = "MiFishU",
      margin = 100L, verbose = TRUE
    ),
    "rescued 0 of 1" # ...and honestly reported as no rescue
  )
})

test_that(".extract_feature_table_fallback() still rescues when the span genuinely fits", {
  full_seq <- strrep("N", 1200L)
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_ann_for_fallback(feature_from = 68, feature_to = 1015),
    .package = "TaxaMatch"
  )
  expect_message(
    out <- .extract_feature_table_fallback(
      accessions = "ACC001", sequences = full_seq, barcode_term = "MiFishU",
      margin = 100L, verbose = TRUE
    ),
    "rescued 1 of 1"
  )
  expect_equal(nchar(out), 1115L) # from = 1, to = min(1200, 1115)
})
