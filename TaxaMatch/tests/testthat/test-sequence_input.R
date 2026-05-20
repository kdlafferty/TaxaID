# ==============================================================================
# Tests for read_sequence_table() and filter_sequences()
# ==============================================================================

# --- Helpers ------------------------------------------------------------------

make_dada2_seqtab <- function(n_samples = 3, n_asvs = 5) {
  seqs <- vapply(seq_len(n_asvs), function(i) {
    paste0(sample(c("A", "C", "G", "T"), 150 + i * 10, replace = TRUE), collapse = "")
  }, character(1L))

  mat <- matrix(
    sample(0:100, n_samples * n_asvs, replace = TRUE),
    nrow = n_samples, ncol = n_asvs,
    dimnames = list(
      paste0("Sample_", seq_len(n_samples)),
      seqs
    )
  )
  mat
}


# ==============================================================================
# read_sequence_table() — DADA2 matrix input
# ==============================================================================

test_that("read_sequence_table reads DADA2 matrix correctly", {
  mat <- make_dada2_seqtab()
  result <- read_sequence_table(mat)

  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), ncol(mat))
  expect_true(all(c("asv_id", "sequence", "length", "abundance") %in% names(result)))
  expect_equal(result$sequence, colnames(mat))
  expect_equal(result$abundance, as.integer(colSums(mat)))
  expect_equal(result$length, nchar(colnames(mat)))
})

test_that("read_sequence_table generates sequential ASV IDs", {
  mat <- make_dada2_seqtab(n_asvs = 12)
  result <- read_sequence_table(mat)

  expect_equal(result$asv_id[1L], "ASV_01")
  expect_equal(result$asv_id[12L], "ASV_12")
})

test_that("read_sequence_table respects custom id_prefix", {
  mat <- make_dada2_seqtab(n_asvs = 3)
  result <- read_sequence_table(mat, id_prefix = "ESV")

  expect_true(all(grepl("^ESV_", result$asv_id)))
})

test_that("read_sequence_table errors on matrix without column names", {
  mat <- matrix(1:6, nrow = 2)
  expect_error(read_sequence_table(mat), "column names")
})


# ==============================================================================
# read_sequence_table() — Input validation
# ==============================================================================

test_that("read_sequence_table rejects invalid data types", {
  expect_error(read_sequence_table(42), "must be")
  expect_error(read_sequence_table(list()), "must be")
})

test_that("read_sequence_table rejects invalid id_prefix", {
  mat <- make_dada2_seqtab()
  expect_error(read_sequence_table(mat, id_prefix = NA), "id_prefix")
  expect_error(read_sequence_table(mat, id_prefix = 123), "id_prefix")
})

test_that("read_sequence_table rejects invalid taxonomy", {
  mat <- make_dada2_seqtab()
  expect_error(read_sequence_table(mat, taxonomy = "not a df"), "taxonomy")
})

test_that("read_sequence_table rejects invalid header_format", {
  mat <- make_dada2_seqtab()
  expect_error(read_sequence_table(mat, header_format = "csv"), "none.*semicolon")
})


# ==============================================================================
# read_sequence_table() — Data frame input (provider ESV tables)
# ==============================================================================

test_that("read_sequence_table reads data frame with sample abundance columns", {
  df <- data.frame(
    ESV = c("ESV_001", "ESV_002", "ESV_003"),
    sequence = c("ACGTACGT", "TGCATGCA", "AAACCCGG"),
    Kingdom = rep("Animalia", 3),
    Family = c("Gobiidae", "Cottidae", "Fundulidae"),
    Species = c("Gobius niger", "Cottus gobio", "Fundulus parvipinnis"),
    pctMatch = c(100, 98, 95),
    Sample_1 = c(10L, 0L, 5L),
    Sample_2 = c(20L, 15L, 0L),
    Sample_3 = c(0L, 5L, 3L),
    stringsAsFactors = FALSE
  )

  result <- read_sequence_table(df, observation_id_col = "ESV")

  expect_equal(nrow(result), 3L)
  expect_equal(result$asv_id, c("ESV_001", "ESV_002", "ESV_003"))
  expect_equal(result$abundance, c(30L, 20L, 8L))
  expect_true("family" %in% names(result))
  expect_true("species" %in% names(result))
  expect_equal(result$length, c(8L, 8L, 8L))
})

test_that("read_sequence_table auto-generates IDs for data frame without observation_id_col", {
  df <- data.frame(
    sequence = c("ACGT", "TGCA"),
    family = c("A", "B"),
    Sample_1 = c(10L, 5L),
    stringsAsFactors = FALSE
  )

  result <- read_sequence_table(df, id_prefix = "QRY")
  expect_equal(result$asv_id, c("QRY_1", "QRY_2"))
})

test_that("read_sequence_table uses explicit abundance_cols", {
  df <- data.frame(
    sequence = c("ACGT", "TGCA"),
    count_a = c(10L, 5L),
    count_b = c(20L, 15L),
    other_num = c(99.5, 88.3),  # should NOT be summed
    stringsAsFactors = FALSE
  )

  result <- read_sequence_table(df, abundance_cols = c("count_a", "count_b"))
  expect_equal(result$abundance, c(30L, 20L))
})

test_that("read_sequence_table sets abundance=1 when no abundance columns detected", {
  df <- data.frame(
    sequence = c("ACGT", "TGCA"),
    family = c("A", "B"),
    stringsAsFactors = FALSE
  )

  result <- read_sequence_table(df)
  expect_equal(result$abundance, c(1L, 1L))
})

test_that("read_sequence_table errors when sequence column not found", {
  df <- data.frame(seq = "ACGT", stringsAsFactors = FALSE)
  expect_error(read_sequence_table(df), "not found")
})

test_that("read_sequence_table respects custom sequence_col name", {
  df <- data.frame(
    dna_seq = c("ACGT", "TGCA"),
    family = c("A", "B"),
    stringsAsFactors = FALSE
  )

  result <- read_sequence_table(df, sequence_col = "dna_seq")
  expect_equal(result$sequence, c("ACGT", "TGCA"))
})


# ==============================================================================
# read_sequence_table() — Taxonomy joining
# ==============================================================================

test_that("read_sequence_table joins taxonomy by sequence", {
  mat <- make_dada2_seqtab(n_asvs = 3)
  tax <- data.frame(
    sequence = colnames(mat),
    family = c("Gobiidae", "Fundulidae", "Cottidae"),
    genus = c("Gobius", "Fundulus", "Cottus"),
    stringsAsFactors = FALSE
  )

  result <- read_sequence_table(mat, taxonomy = tax)
  expect_true("family" %in% names(result))
  expect_true("genus" %in% names(result))
  expect_equal(result$family, c("Gobiidae", "Fundulidae", "Cottidae"))
})

test_that("read_sequence_table warns when taxonomy has no joinable column", {
  mat <- make_dada2_seqtab(n_asvs = 2)
  tax <- data.frame(id = c("a", "b"), family = c("A", "B"),
                    stringsAsFactors = FALSE)

  expect_warning(
    result <- read_sequence_table(mat, taxonomy = tax),
    "sequence.*accession"
  )
  expect_false("family" %in% names(result))
})


# ==============================================================================
# read_sequence_table() — FASTA file (requires Biostrings)
# ==============================================================================

test_that("read_sequence_table reads FASTA file path", {
  skip_if_not_installed("Biostrings")

  tmp <- tempfile(fileext = ".fasta")
  writeLines(c(
    ">seq1;Animalia;Chordata;Actinopteri;Perciformes;Gobiidae;Gobius;Gobius niger",
    "ACGTACGTACGT",
    ">seq2;Animalia;Chordata;Actinopteri;Perciformes;Cottidae;Cottus;Cottus gobio",
    "TGCATGCATGCA"
  ), tmp)

  result <- read_sequence_table(tmp, header_format = "semicolon")

  expect_equal(nrow(result), 2L)
  expect_true("accession" %in% names(result))
  expect_true("family" %in% names(result))
  expect_equal(result$accession, c("seq1", "seq2"))
  expect_equal(result$family, c("Gobiidae", "Cottidae"))
  expect_equal(result$length, c(12L, 12L))
  unlink(tmp)
})

test_that("read_sequence_table errors on missing FASTA file", {
  skip_if_not_installed("Biostrings")
  expect_error(read_sequence_table("/no/such/file.fasta"), "not found")
})


# ==============================================================================
# filter_sequences()
# ==============================================================================

test_that("filter_sequences removes short and long sequences", {
  df <- data.frame(
    asv_id = paste0("ASV_", 1:5),
    sequence = c("AA", "AAAA", strrep("A", 150), strrep("A", 200), strrep("A", 800)),
    length = c(2L, 4L, 150L, 200L, 800L),
    abundance = rep(10L, 5),
    stringsAsFactors = FALSE
  )

  result <- filter_sequences(df, min_length = 100, max_length = 300)
  expect_equal(nrow(result), 2L)
  expect_equal(result$asv_id, c("ASV_3", "ASV_4"))
})

test_that("filter_sequences removes low abundance sequences", {
  df <- data.frame(
    asv_id = paste0("ASV_", 1:4),
    sequence = rep("ACGT", 4),
    length = rep(4L, 4),
    abundance = c(1L, 2L, 5L, 100L),
    stringsAsFactors = FALSE
  )

  result <- filter_sequences(df, min_abundance = 3)
  expect_equal(nrow(result), 2L)
  expect_equal(result$abundance, c(5L, 100L))
})

test_that("filter_sequences uses barcode_term for length detection", {
  df <- data.frame(
    asv_id = paste0("ASV_", 1:3),
    sequence = c(strrep("A", 50), strrep("A", 170), strrep("A", 700)),
    length = c(50L, 170L, 700L),
    abundance = rep(10L, 3),
    stringsAsFactors = FALSE
  )

  # MiFish defaults: 100-600 bp
  # 50 bp too short, 170 in range, 700 bp too long
  result <- filter_sequences(df, barcode_term = "MiFish", min_abundance = 1)
  expect_equal(nrow(result), 1L)
  expect_equal(result$length, 170L)
})

test_that("filter_sequences derives length from sequence if missing", {
  df <- data.frame(
    asv_id = c("A", "B"),
    sequence = c("ACGT", strrep("A", 50)),
    abundance = c(10L, 10L),
    stringsAsFactors = FALSE
  )

  result <- filter_sequences(df, min_length = 5, max_length = 100)
  expect_equal(nrow(result), 1L)
})

test_that("filter_sequences errors without length or sequence column", {
  df <- data.frame(asv_id = "A", abundance = 10L, stringsAsFactors = FALSE)
  expect_error(filter_sequences(df, min_length = 10, max_length = 100), "length.*sequence")
})

test_that("filter_sequences passes all when no filters specified", {
  df <- data.frame(
    asv_id = paste0("ASV_", 1:3),
    sequence = rep("ACGT", 3),
    length = rep(4L, 3),
    abundance = rep(10L, 3),
    stringsAsFactors = FALSE
  )

  result <- filter_sequences(df, min_abundance = NULL)
  expect_equal(nrow(result), 3L)
})


# ==============================================================================
# TaxaTools::resolve_barcode_lengths() — tested via TaxaTools; spot-check here
# ==============================================================================

test_that("barcode length defaults resolve correctly via TaxaTools", {
  skip_if_not_installed("TaxaTools")
  result <- TaxaTools::resolve_barcode_lengths("12S", NULL, NULL)
  expect_equal(result, c(100L, 600L))

  result <- TaxaTools::resolve_barcode_lengths("COI", NULL, NULL)
  expect_equal(result, c(300L, 900L))
})
