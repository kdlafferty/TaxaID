# trim_to_amplicon() requires Biostrings (Bioconductor -- Suggests).
# Input validation runs offline unconditionally; primer-matching tests are
# guarded with skip_if_not_installed("Biostrings").

# ---------------------------------------------------------------------------
# Shared synthetic fixtures: a real, verified MiFish-U primer pair wrapped
# around an arbitrary interior, embedded in a long flanking "genome" context
# (mimicking a full mitogenome record containing the barcode locus).
# ---------------------------------------------------------------------------
.mf_fwd <- "GTCGGTAAAACTCGTGCCAGC"
.mf_rev <- "CATAGTGGGGTATCTAATCCCAGTTTG"

.build_genome <- function(fwd = .mf_fwd, rev = .mf_rev,
                           interior = paste(rep("AAACCCGGGTTT", 3), collapse = ""),
                           flank5 = 300L, flank3 = 300L, revcomp_deposit = FALSE) {
  rev_rc <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(rev)))
  amplicon <- paste0(fwd, interior, rev_rc)
  genome <- paste0(strrep("N", flank5), amplicon, strrep("A", flank3))
  if (revcomp_deposit)
    genome <- as.character(Biostrings::reverseComplement(Biostrings::DNAString(genome)))
  list(genome = genome, amplicon = amplicon, amplicon_len = nchar(amplicon))
}

# ---- input validation (offline, no Biostrings needed) ------------------------

test_that("trim_to_amplicon: non-data-frame input errors", {
  expect_error(trim_to_amplicon(list(), barcode_term = "MiFishU"), "must be a data frame")
})

test_that("trim_to_amplicon: missing required columns errors", {
  df <- data.frame(composite_id = "A1", stringsAsFactors = FALSE)
  expect_error(trim_to_amplicon(df, barcode_term = "MiFishU"), "missing required columns")
})

test_that("trim_to_amplicon: only one of primer_fwd/primer_rev errors", {
  df <- data.frame(composite_id = "A1", sequence = "ACGT", stringsAsFactors = FALSE)
  expect_error(trim_to_amplicon(df, primer_fwd = "ACGT"), "supply both primer_fwd and primer_rev")
})

test_that("trim_to_amplicon: no primers and no barcode_term errors", {
  df <- data.frame(composite_id = "A1", sequence = "ACGT", stringsAsFactors = FALSE)
  expect_error(trim_to_amplicon(df), "supply barcode_term")
})

test_that("trim_to_amplicon: explicit primers but no length info errors", {
  df <- data.frame(composite_id = "A1", sequence = "ACGT", stringsAsFactors = FALSE)
  expect_error(
    trim_to_amplicon(df, primer_fwd = "ACGT", primer_rev = "TTTT"),
    "supply min_len and max_len"
  )
})

test_that("trim_to_amplicon: invalid max_mismatch_rate errors", {
  skip_if_not_installed("Biostrings")
  df <- data.frame(composite_id = "A1", sequence = "ACGT", stringsAsFactors = FALSE)
  expect_error(
    trim_to_amplicon(df, barcode_term = "MiFishU", max_mismatch_rate = 1.5),
    "max_mismatch_rate"
  )
  expect_error(
    trim_to_amplicon(df, barcode_term = "MiFishU", max_mismatch_rate = -0.1),
    "max_mismatch_rate"
  )
})

test_that("trim_to_amplicon: unregistered barcode_term with no explicit primers errors clearly", {
  skip_if_not_installed("Biostrings")
  df <- data.frame(composite_id = "A1", sequence = "ACGT", stringsAsFactors = FALSE)
  expect_error(trim_to_amplicon(df, barcode_term = "ITS2"), "no primer defaults found")
})

# ---- primer-matching behavior (requires Biostrings) ---------------------------

test_that("trim_to_amplicon: already-short sequences are left untouched", {
  skip_if_not_installed("Biostrings")
  short_seq <- paste0(.mf_fwd, "AAACCCGGGTTT",
                       as.character(Biostrings::reverseComplement(Biostrings::DNAString(.mf_rev))))
  df <- data.frame(composite_id = "S1", sequence = short_seq, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", verbose = FALSE)
  expect_equal(out$sequence, short_seq)
  expect_false(out$amplicon_trimmed)
  expect_equal(out$amplicon_trim_note, "within_length_range_no_trim_needed")
})

test_that("trim_to_amplicon: extracts the correct amplicon from an over-length sequence (sense strand)", {
  skip_if_not_installed("Biostrings")
  g <- .build_genome()
  df <- data.frame(composite_id = "MITO1", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", min_len = 50L, max_len = 100L, verbose = FALSE)
  expect_true(out$amplicon_trimmed)
  expect_equal(out$amplicon_trim_note, "extracted_via_primer_match_sense_strand")
  expect_equal(out$sequence, g$amplicon)
  expect_equal(nchar(out$sequence), g$amplicon_len)
})

test_that("trim_to_amplicon: extracts correctly when the sequence was deposited on the opposite strand", {
  skip_if_not_installed("Biostrings")
  g <- .build_genome(revcomp_deposit = TRUE)
  df <- data.frame(composite_id = "MITO2", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", min_len = 50L, max_len = 100L, verbose = FALSE)
  expect_true(out$amplicon_trimmed)
  expect_equal(out$amplicon_trim_note, "extracted_via_primer_match_antisense_strand")
  expect_equal(out$sequence, g$amplicon)
})

test_that("trim_to_amplicon: tolerates a real single-base mismatch in a primer-binding site", {
  skip_if_not_installed("Biostrings")
  mutated_fwd <- .mf_fwd
  substr(mutated_fwd, 10, 10) <- if (substr(mutated_fwd, 10, 10) == "A") "T" else "A"
  g <- .build_genome(fwd = mutated_fwd)
  df <- data.frame(composite_id = "MITO3", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", min_len = 50L, max_len = 100L,
                           max_mismatch_rate = 0.15, verbose = FALSE)
  expect_true(out$amplicon_trimmed)
  expect_equal(nchar(out$sequence), g$amplicon_len)
})

test_that("trim_to_amplicon: rejects the mismatch when max_mismatch_rate is 0", {
  skip_if_not_installed("Biostrings")
  mutated_fwd <- .mf_fwd
  substr(mutated_fwd, 10, 10) <- if (substr(mutated_fwd, 10, 10) == "A") "T" else "A"
  g <- .build_genome(fwd = mutated_fwd)
  df <- data.frame(composite_id = "MITO4", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", min_len = 50L, max_len = 100L,
                           max_mismatch_rate = 0, verbose = FALSE)
  expect_false(out$amplicon_trimmed)
  expect_equal(out$amplicon_trim_note, "primers_not_found_or_implausible_span")
  expect_equal(out$sequence, g$genome)  # unchanged, falls back to length filter
})

test_that("trim_to_amplicon: falls back gracefully when a primer is genuinely absent", {
  skip_if_not_installed("Biostrings")
  genome_no_primers <- paste(rep("ATGCATGCATGC", 100), collapse = "")  # 1200bp, no primer sites
  df <- data.frame(composite_id = "NOPRIMER1", sequence = genome_no_primers, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", min_len = 50L, max_len = 100L, verbose = FALSE)
  expect_false(out$amplicon_trimmed)
  expect_equal(out$amplicon_trim_note, "primers_not_found_or_implausible_span")
  expect_equal(out$sequence, genome_no_primers)
})

test_that("trim_to_amplicon: rejects an implausible span even when both primers technically match", {
  skip_if_not_installed("Biostrings")
  # fwd and rev found, but far enough apart that the implied amplicon
  # exceeds max_len -- should be rejected, not accepted as a giant "amplicon".
  g <- .build_genome(interior = strrep("ATGC", 50), flank5 = 10L, flank3 = 10L)  # long interior
  df <- data.frame(composite_id = "FAR1", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", min_len = 50L, max_len = 100L, verbose = FALSE)
  expect_false(out$amplicon_trimmed)
  expect_equal(out$sequence, g$genome)
})

test_that("trim_to_amplicon: explicit primer_fwd/primer_rev works without barcode_term", {
  skip_if_not_installed("Biostrings")
  g <- .build_genome()
  df <- data.frame(composite_id = "MITO5", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, primer_fwd = .mf_fwd, primer_rev = .mf_rev,
                           min_len = 50L, max_len = 100L, verbose = FALSE)
  expect_true(out$amplicon_trimmed)
  expect_equal(out$sequence, g$amplicon)
})

test_that("trim_to_amplicon: multiple rows handled independently, mixed outcomes", {
  skip_if_not_installed("Biostrings")
  g <- .build_genome()
  short_seq <- g$amplicon
  no_primer_seq <- paste(rep("ATGCATGCATGC", 100), collapse = "")
  df <- data.frame(
    composite_id = c("SHORT1", "MITO_OK", "MITO_FAIL"),
    sequence = c(short_seq, g$genome, no_primer_seq),
    stringsAsFactors = FALSE
  )
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", min_len = 50L, max_len = 100L, verbose = FALSE)
  expect_equal(out$amplicon_trim_note,
               c("within_length_range_no_trim_needed",
                 "extracted_via_primer_match_sense_strand",
                 "primers_not_found_or_implausible_span"))
  expect_equal(out$amplicon_trimmed, c(FALSE, TRUE, FALSE))
  expect_equal(out$sequence[1], short_seq)
  expect_equal(out$sequence[2], g$amplicon)
  expect_equal(out$sequence[3], no_primer_seq)
})

test_that("trim_to_amplicon: non-IUPAC sequence (e.g. protein accession) is flagged, not trimmed", {
  skip_if_not_installed("Biostrings")
  bad_seq <- "MEEPQSDPSVEPPLSQETFSDLWKLLPENNV"  # protein-looking string
  df <- data.frame(composite_id = "BAD1", sequence = bad_seq, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "MiFishU", min_len = 5L, max_len = 10L, verbose = FALSE)
  expect_false(out$amplicon_trimmed)
  expect_equal(out$amplicon_trim_note, "non_iupac_dna_skipped")
})

# ---- mito/chloroplast markers (Session 141): real, verified primer pairs ----
# (COI-Folmer, rbcLa) embedded in synthetic flanking context, mirroring the
# MiFish fixtures above. Sequences are the real, literature-verified pairs,
# not fabricated -- see TaxaTools::barcode_primer_defaults' own roxygen for
# the verification record (including empirical confirmation against real
# GenBank mitogenomes/chloroplast genomes).

test_that("trim_to_amplicon: extracts a real COI-Folmer amplicon from an over-length sequence", {
  skip_if_not_installed("Biostrings")
  coi <- TaxaTools::resolve_barcode_primers("COI-Folmer")
  g <- .build_genome(fwd = coi$fwd, rev = coi$rev,
                      interior = paste(rep("ATGCATGCATGCATG", 40), collapse = ""))  # ~658bp interior
  df <- data.frame(composite_id = "COI_MITO1", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "COI-Folmer", min_len = 300L, max_len = 900L, verbose = FALSE)
  expect_true(out$amplicon_trimmed)
  expect_equal(out$sequence, g$amplicon)
  expect_equal(nchar(out$sequence), g$amplicon_len)
})

test_that("trim_to_amplicon: extracts a real COI-Leray (mini-barcode) amplicon from an over-length sequence", {
  skip_if_not_installed("Biostrings")
  coi <- TaxaTools::resolve_barcode_primers("COI-Leray")
  g <- .build_genome(fwd = coi$fwd, rev = coi$rev,
                      interior = paste(rep("ATGCATGCATGCATG", 20), collapse = ""))  # ~313bp interior
  df <- data.frame(composite_id = "COI_LERAY1", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "COI-Leray", min_len = 300L, max_len = 900L, verbose = FALSE)
  expect_true(out$amplicon_trimmed)
  expect_equal(out$sequence, g$amplicon)
  expect_equal(nchar(out$sequence), g$amplicon_len)
})

test_that("trim_to_amplicon: bare 'COI' is ambiguous now that Folmer and Leray are both registered", {
  skip_if_not_installed("Biostrings")
  df <- data.frame(composite_id = "A1", sequence = "ACGT", stringsAsFactors = FALSE)
  expect_error(trim_to_amplicon(df, barcode_term = "COI"), "ambiguous")
})

test_that("trim_to_amplicon: extracts a real rbcLa amplicon from an over-length sequence", {
  skip_if_not_installed("Biostrings")
  rbcl <- TaxaTools::resolve_barcode_primers("rbcLa")
  g <- .build_genome(fwd = rbcl$fwd, rev = rbcl$rev,
                      interior = paste(rep("ATGCATGCATGCATG", 35), collapse = ""))
  df <- data.frame(composite_id = "RBCL_CP1", sequence = g$genome, stringsAsFactors = FALSE)
  out <- trim_to_amplicon(df, barcode_term = "rbcL", min_len = 400L, max_len = 800L, verbose = FALSE)
  expect_true(out$amplicon_trimmed)
  expect_equal(out$sequence, g$amplicon)
})

test_that("trim_to_amplicon: works end-to-end for every registered mito/chloroplast primer set", {
  skip_if_not_installed("Biostrings")
  markers <- c("16S-Palumbi", "COI-Folmer", "cytb-Kocher", "rbcLa", "matK-Kim", "trnL-Taberlet")
  for (term in markers) {
    primers <- TaxaTools::resolve_barcode_primers(term)
    g <- .build_genome(fwd = primers$fwd, rev = primers$rev,
                        interior = paste(rep("ATGCATGCATGCATG", 20), collapse = ""))
    df <- data.frame(composite_id = paste0("TEST_", term), sequence = g$genome, stringsAsFactors = FALSE)
    out <- trim_to_amplicon(df, primer_fwd = primers$fwd, primer_rev = primers$rev,
                             min_len = 10L, max_len = g$amplicon_len + 50L, verbose = FALSE)
    expect_true(out$amplicon_trimmed, info = term)
    expect_equal(out$sequence, g$amplicon, info = term)
  }
})
