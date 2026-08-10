# .trim_queries_to_amplicon() / .extract_amplicon_one_tm() require Biostrings
# (Bioconductor -- Suggests). Fixture mirrors TaxaLikely's own
# test-trim-to-amplicon.R exactly (a real, verified MiFish-U primer pair
# wrapped around an arbitrary interior, embedded in a long flanking "genome"
# context) -- these two functions are algorithm-identical duplicates (see
# their own roxygen for why), so the same fixture shape is deliberate, not
# copy-paste-without-thought.

.mf_fwd <- "GTCGGTAAAACTCGTGCCAGC"
.mf_rev <- "CATAGTGGGGTATCTAATCCCAGTTTG"

# Interior sized so fwd(21) + interior(96) + rev_rc(27) = 144bp total --
# within MiFish-U's real registered range (130-210bp, TaxaTools::
# resolve_barcode_lengths("MiFishU")), so tests relying on auto-resolved
# length bounds (not an explicit min_len/max_len override) pass the
# plausible-span check.
.build_genome_tm <- function(fwd = .mf_fwd, rev = .mf_rev,
                             interior = paste(rep("AAACCCGGGTTT", 8), collapse = ""),
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
  short_seq <- g$amplicon  # already barcode-length, should NOT be touched
  sequences <- c(g$genome, short_seq)

  out <- .trim_queries_to_amplicon(sequences, barcode_term = "MiFishU", verbose = FALSE)

  expect_equal(out[1], g$amplicon)   # over-length -> trimmed
  expect_equal(out[2], short_seq)    # already short -> untouched
})

test_that(".trim_queries_to_amplicon() leaves an over-length sequence unchanged when primers can't be found", {
  skip_if_not_installed("Biostrings")
  no_primer_genome <- strrep("N", 500L)
  out <- .trim_queries_to_amplicon(no_primer_genome, barcode_term = "MiFishU", verbose = FALSE)
  expect_equal(out, no_primer_genome)  # unchanged, not dropped or NA'd
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
    "ACC001", cache_dir = NULL, barcode_term = "MiFishU", verbose = FALSE
  ))

  expect_equal(seen_sequence, g$amplicon)
  expect_lt(nchar(seen_sequence), nchar(g$genome))
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
