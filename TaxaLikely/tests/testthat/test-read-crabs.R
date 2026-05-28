# tests/testthat/test-read-crabs.R
# Offline tests for read_crabs_output() and the taxonomy_file path of
# read_reference_fasta().

# ---------------------------------------------------------------------------
# Helper: write a CRABS internal-format temp file
# ---------------------------------------------------------------------------
# Column order (no header):
# accession | taxid_string | ncbi_tax_number | kingdom | phylum | class |
# order | family | genus | species | sequence

make_crabs_row <- function(acc,
                           kingdom  = "Eukaryota",
                           phylum   = "Chordata",
                           class    = "Actinopteri",
                           order    = "Cyprinodontiformes",
                           family   = "Fundulidae",
                           genus    = "Fundulus",
                           species  = "Fundulus heteroclitus",
                           seq      = "ATCGATCGATCGATCG") {
  paste(c(acc, "12345", "9999", kingdom, phylum, class, order,
          family, genus, species, seq), collapse = "\t")
}

make_crabs_file <- function(...) {
  f <- tempfile(fileext = ".tsv")
  writeLines(c(...), f)
  f
}

# ===========================================================================
# read_crabs_output() tests
# ===========================================================================

test_that("read_crabs_output: basic reading and column structure", {
  f <- make_crabs_file(
    make_crabs_row("ACC001.1"),
    make_crabs_row("ACC002.1", species = "Fundulus parvipinnis",
                   seq = "GCTAGCTAGCTAGCTA")
  )
  ref <- read_crabs_output(f, rank_system = c("family", "genus", "species"))
  expect_s3_class(ref, "data.frame")
  expect_equal(nrow(ref), 2L)
  expect_equal(names(ref), c("composite_id", "family", "genus", "species", "sequence"))
})

test_that("read_crabs_output: version suffix stripped from accession", {
  f <- make_crabs_file(make_crabs_row("MT123456.2"))
  ref <- read_crabs_output(f, rank_system = c("genus", "species"))
  expect_equal(ref$composite_id, "MT123456")
})

test_that("read_crabs_output: auto-detect rank_system includes populated columns", {
  f <- make_crabs_file(make_crabs_row("ACC001"))
  expect_message(ref <- read_crabs_output(f), "Auto-detected rank_system")
  expect_true(all(c("family", "genus", "species") %in% names(ref)))
  # All 7 CRABS tax ranks should be present (all populated in our test row)
  expect_true(all(c("kingdom", "phylum", "class", "order",
                    "family", "genus", "species") %in% names(ref)))
})

test_that("read_crabs_output: literal 'NA' converted to NA", {
  # Species column contains literal string "NA"
  row1 <- paste(c("ACC001", "12345", "9999", "Eukaryota", "Chordata",
                   "Actinopteri", "Cyprinodontiformes", "Fundulidae",
                   "Fundulus", "NA", "ATCG"), collapse = "\t")
  f <- make_crabs_file(row1)
  ref <- read_crabs_output(f, rank_system = c("family", "genus", "species"),
                            require_species = FALSE)
  expect_true(is.na(ref$species[1L]))
})

test_that("read_crabs_output: require_species drops sp. and NA species", {
  f <- make_crabs_file(
    make_crabs_row("ACC001", species = "Fundulus heteroclitus"),
    make_crabs_row("ACC002", species = "Fundulus sp."),
    make_crabs_row("ACC003", species = "cf. Fundulus heteroclitus")
  )
  ref <- read_crabs_output(f, rank_system = c("family", "genus", "species"),
                            require_species = TRUE)
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$composite_id, "ACC001")
})

test_that("read_crabs_output: require_species = FALSE retains invalid names", {
  f <- make_crabs_file(
    make_crabs_row("ACC001", species = "Fundulus sp."),
    make_crabs_row("ACC002", species = "Fundulus heteroclitus")
  )
  ref <- read_crabs_output(f, rank_system = c("genus", "species"),
                            require_species = FALSE)
  expect_equal(nrow(ref), 2L)
})

test_that("read_crabs_output: max_n_bases drops long sequences", {
  f <- make_crabs_file(
    make_crabs_row("ACC001", seq = "ATCG"),                       # 4 bp
    make_crabs_row("ACC002", species = "Fundulus parvipinnis",
                   seq = paste(rep("A", 300L), collapse = ""))    # 300 bp
  )
  ref <- read_crabs_output(f, rank_system = c("genus", "species"),
                            max_n_bases = 100L)
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$composite_id, "ACC001")
})

test_that("read_crabs_output: max_n_bases = NULL retains all lengths", {
  f <- make_crabs_file(
    make_crabs_row("ACC001", seq = paste(rep("A", 500L), collapse = ""))
  )
  ref <- read_crabs_output(f, rank_system = c("genus", "species"),
                            max_n_bases = NULL)
  expect_equal(nrow(ref), 1L)
})

test_that("read_crabs_output: dereplicate removes same-species exact duplicates", {
  f <- make_crabs_file(
    make_crabs_row("ACC001", seq = "ATCGATCG"),              # same species, same seq
    make_crabs_row("ACC002", seq = "ATCGATCG"),              # duplicate -> dropped
    make_crabs_row("ACC003", species = "Fundulus parvipinnis",
                   seq = "ATCGATCG")                         # different species -> kept
  )
  ref <- read_crabs_output(f, rank_system = c("genus", "species"),
                            dereplicate = TRUE)
  expect_equal(nrow(ref), 2L)
  expect_true("ACC001" %in% ref$composite_id)
  expect_true("ACC003" %in% ref$composite_id)
  expect_false("ACC002" %in% ref$composite_id)
})

test_that("read_crabs_output: dereplicate = FALSE keeps all rows", {
  f <- make_crabs_file(
    make_crabs_row("ACC001", seq = "ATCGATCG"),
    make_crabs_row("ACC002", seq = "ATCGATCG")
  )
  ref <- read_crabs_output(f, rank_system = c("genus", "species"),
                            dereplicate = FALSE)
  expect_equal(nrow(ref), 2L)
})

test_that("read_crabs_output: dereplicate keeps same sequence in different species", {
  f <- make_crabs_file(
    make_crabs_row("ACC001", species = "Fundulus heteroclitus", seq = "AAAA"),
    make_crabs_row("ACC002", species = "Fundulus parvipinnis",  seq = "AAAA")
  )
  ref <- read_crabs_output(f, rank_system = c("genus", "species"),
                            dereplicate = TRUE)
  expect_equal(nrow(ref), 2L)
})

test_that("read_crabs_output: file not found stops with clear message", {
  expect_error(read_crabs_output("does_not_exist_crabs.tsv"), "File not found")
})

test_that("read_crabs_output: empty file (0 bytes) stops", {
  f <- tempfile(fileext = ".tsv")
  file.create(f)
  on.exit(unlink(f))
  expect_error(read_crabs_output(f), "empty")
})

test_that("read_crabs_output: invalid rank_system errors with informative message", {
  f <- make_crabs_file(make_crabs_row("ACC001"))
  expect_error(read_crabs_output(f, rank_system = c("family", "superfamily")),
               "ranks not in CRABS format")
})

test_that("read_crabs_output: explicit rank_system subset selects correct columns", {
  f <- make_crabs_file(make_crabs_row("ACC001"))
  ref <- read_crabs_output(f, rank_system = c("genus", "species"))
  expect_equal(names(ref), c("composite_id", "genus", "species", "sequence"))
  expect_false("family" %in% names(ref))
})

test_that("read_crabs_output: all rows filtered returns empty df with warning", {
  f <- make_crabs_file(
    make_crabs_row("ACC001", species = "Fundulus sp."),
    make_crabs_row("ACC002", species = "uncultured organism")
  )
  expect_warning(
    ref <- read_crabs_output(f, rank_system = c("genus", "species"),
                              require_species = TRUE),
    "No sequences remained"
  )
  expect_equal(nrow(ref), 0L)
})

test_that("read_crabs_output: non-logical require_species stops", {
  f <- make_crabs_file(make_crabs_row("ACC001"))
  expect_error(read_crabs_output(f, require_species = "yes"), "TRUE or FALSE")
})

test_that("read_crabs_output: non-logical dereplicate stops", {
  f <- make_crabs_file(make_crabs_row("ACC001"))
  expect_error(read_crabs_output(f, dereplicate = 1L), "TRUE or FALSE")
})

# ===========================================================================
# read_reference_fasta() – taxonomy_file parameter (Tier 2)
# ===========================================================================

# Helper: write a minimal FASTA temp file
make_fasta_file <- function(entries) {
  f <- tempfile(fileext = ".fasta")
  writeLines(entries, f)
  f
}

# Helper: write a taxonomy TSV temp file
make_tax_tsv <- function(rows) {
  f <- tempfile(fileext = ".tsv")
  writeLines(rows, f)
  f
}

test_that("read_reference_fasta: taxonomy_file (prefix-style) is parsed correctly", {
  fasta <- make_fasta_file(c(">ACC001", "ATCGATCG"))
  tsv   <- make_tax_tsv(
    "ACC001\tk__Eukaryota;p__Chordata;c__Actinopteri;o__Cyprinodontiformes;f__Fundulidae;g__Fundulus;s__Fundulus heteroclitus"
  )
  ref <- read_reference_fasta(fasta,
                              rank_system   = c("family", "genus", "species"),
                              taxonomy_file = tsv)
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$family,  "Fundulidae")
  expect_equal(ref$genus,   "Fundulus")
  expect_equal(ref$species, "Fundulus heteroclitus")
})

test_that("read_reference_fasta: taxonomy_file (positional, no prefix) is parsed", {
  fasta <- make_fasta_file(c(">ACC001", "GCTAGCTA"))
  tsv   <- make_tax_tsv(
    "ACC001\tEukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;Fundulus heteroclitus"
  )
  ref <- read_reference_fasta(fasta,
                              rank_system   = c("family", "genus", "species"),
                              taxonomy_file = tsv)
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$family, "Fundulidae")
})

test_that("read_reference_fasta: taxonomy_file with QIIME2 header row skipped", {
  fasta <- make_fasta_file(c(">ACC001", "ATCG"))
  tsv   <- make_tax_tsv(c(
    "Feature ID\tTaxon",
    "ACC001\tf__Fundulidae;g__Fundulus;s__Fundulus heteroclitus"
  ))
  ref <- read_reference_fasta(fasta,
                              rank_system   = c("family", "genus", "species"),
                              taxonomy_file = tsv)
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$family, "Fundulidae")
})

test_that("read_reference_fasta: both taxonomy and taxonomy_file stops", {
  fasta <- make_fasta_file(c(">ACC001", "ATCG"))
  tsv   <- make_tax_tsv("ACC001\tf__Fundulidae;g__Fundulus;s__Fundulus sp.")
  tax   <- data.frame(composite_id = "ACC001", family = "Fundulidae",
                      genus = "Fundulus", species = "Fundulus sp.",
                      stringsAsFactors = FALSE)
  expect_error(
    read_reference_fasta(fasta, taxonomy = tax, rank_system = c("family"),
                         taxonomy_file = tsv),
    "not both"
  )
})

test_that("read_reference_fasta: neither taxonomy nor taxonomy_file stops", {
  fasta <- make_fasta_file(c(">ACC001", "ATCG"))
  expect_error(
    read_reference_fasta(fasta, rank_system = c("family", "genus", "species")),
    "must be supplied"
  )
})

test_that("read_reference_fasta: existing data frame path still works", {
  fasta <- make_fasta_file(c(">ACC001", "ATCG"))
  tax   <- data.frame(composite_id = "ACC001", family = "Fundulidae",
                      genus = "Fundulus", species = "Fundulus heteroclitus",
                      stringsAsFactors = FALSE)
  ref <- read_reference_fasta(fasta, taxonomy = tax,
                              rank_system = c("family", "genus", "species"))
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$family, "Fundulidae")
})
