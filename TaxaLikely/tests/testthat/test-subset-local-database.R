# tests/testthat/test-subset-local-database.R
# Offline tests for subset_local_database()
#
# Strategy: write tiny temp FASTA + taxonomy TSV files inline.
# No external databases required.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

make_tax_tsv <- function(rows, file = tempfile(fileext = ".tsv")) {
  # rows: list of c(id, "Family;Genus;Species") character pairs
  lines <- vapply(rows, paste, character(1L), collapse = "\t")
  writeLines(lines, file)
  file
}

make_fasta <- function(records, gz = FALSE) {
  # records: named character vector (id -> sequence)
  lines <- character(0L)
  for (id in names(records)) {
    lines <- c(lines, paste0(">", id, " extra header text"), records[[id]])
  }
  f <- tempfile(fileext = if (gz) ".fasta.gz" else ".fasta")
  if (gz) {
    con <- gzfile(f, open = "w")
    writeLines(lines, con)
    close(con)
  } else {
    writeLines(lines, f)
  }
  f
}

# Positional taxonomy string (no prefix style)
SEQS <- c(
  "ACC001" = "ATCGATCGATCG",
  "ACC002" = "GCTAGCTAGCTA",
  "ACC003" = "TTTTCCCCAAAA",
  "ACC004" = "GGGGAAAAGGGG"
)

# Positional format: full 7-level hierarchy (Kingdom;Phylum;Class;Order;Family;Genus;Species)
# Required because .parse_tax_string maps positions to .crabs_std_hierarchy left-to-right.
TAX_ROWS <- list(
  c("ACC001", "Eukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;Fundulus heteroclitus"),
  c("ACC002", "Eukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;Fundulus parvipinnis"),
  c("ACC003", "Eukaryota;Chordata;Actinopteri;Gobiiformes;Gobiidae;Gillichthys;Gillichthys mirabilis"),
  c("ACC004", "Eukaryota;Chordata;Actinopteri;Gobiiformes;Gobiidae;Clevelandia;Clevelandia ios")
)

# ===========================================================================
# Part A: Basic filtering
# ===========================================================================

test_that("subset_local_database: family filter returns correct rows", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax)
  )
  expect_s3_class(ref, "data.frame")
  expect_equal(nrow(ref), 2L)
  expect_true(all(ref$family == "Fundulidae"))
})

test_that("subset_local_database: genus filter returns correct rows", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Gillichthys", rank = "genus",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax)
  )
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$genus, "Gillichthys")
})

test_that("subset_local_database: multiple taxa can be requested", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(fasta,
                          taxa = c("Fundulidae", "Gobiidae"),
                          rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax)
  )
  expect_equal(nrow(ref), 4L)
})

# ===========================================================================
# Part B: Column structure and ordering
# ===========================================================================

test_that("subset_local_database: output has canonical column order", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax)
  )
  expect_equal(names(ref),
               c("composite_id", "family", "genus", "species", "sequence"))
})

test_that("subset_local_database: sequences are populated and non-empty", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax)
  )
  expect_true(all(nchar(ref$sequence) > 0L))
})

test_that("subset_local_database: composite_id matches FASTA IDs (no suffix strip needed)", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax)
  )
  expect_true(all(ref$composite_id %in% names(SEQS)))
})

# ===========================================================================
# Part C: max_n_bases filter
# ===========================================================================

test_that("subset_local_database: max_n_bases drops long sequences", {
  seqs <- c("SHORT001" = "ATCG", "LONG001" = paste(rep("A", 20L), collapse = ""))
  tax_rows <- list(
    c("SHORT001", "Eukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;Fundulus heteroclitus"),
    c("LONG001",  "Eukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;Fundulus parvipinnis")
  )
  fasta <- make_fasta(seqs)
  tax   <- make_tax_tsv(tax_rows)
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax,
                          max_n_bases = 10L)
  )
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$composite_id, "SHORT001")
})

# ===========================================================================
# Part D: require_species filter
# ===========================================================================

test_that("subset_local_database: require_species drops NA species rows", {
  seqs <- c("HAS001" = "ATCGATCG", "NO001" = "GCTAGCTA")
  # Full 7-level hierarchy; "NA" in species position is converted to NA by .parse_tax_string
  tax_rows <- list(
    c("HAS001", "Eukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;Fundulus heteroclitus"),
    c("NO001",  "Eukaryota;Chordata;Actinopteri;Cyprinodontiformes;Fundulidae;Fundulus;NA")
  )
  fasta <- make_fasta(seqs)
  tax   <- make_tax_tsv(tax_rows)
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax,
                          require_species = TRUE)
  )
  # "NA" in species position → NA via .parse_tax_string; NO001 is dropped
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$composite_id, "HAS001")
})

# ===========================================================================
# Part E: gz FASTA support
# ===========================================================================

test_that("subset_local_database: reads .gz-compressed FASTA", {
  fasta <- make_fasta(SEQS, gz = TRUE)
  tax   <- make_tax_tsv(TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Gobiidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax)
  )
  expect_equal(nrow(ref), 2L)
  expect_true(all(ref$family == "Gobiidae"))
})

# ===========================================================================
# Part F: Pre-parsed taxonomy data frame
# ===========================================================================

test_that("subset_local_database: accepts pre-parsed taxonomy data frame", {
  fasta <- make_fasta(SEQS)
  tax_df <- data.frame(
    composite_id = c("ACC001", "ACC002", "ACC003", "ACC004"),
    family  = c("Fundulidae", "Fundulidae", "Gobiidae", "Gobiidae"),
    genus   = c("Fundulus", "Fundulus", "Gillichthys", "Clevelandia"),
    species = c("Fundulus heteroclitus", "Fundulus parvipinnis",
                "Gillichthys mirabilis", "Clevelandia ios"),
    stringsAsFactors = FALSE
  )
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy = tax_df)
  )
  expect_equal(nrow(ref), 2L)
  expect_true(all(ref$family == "Fundulidae"))
})

# ===========================================================================
# Part G: Empty result warning
# ===========================================================================

test_that("subset_local_database: warns and returns 0-row df when no taxa match", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  expect_error(
    suppressMessages(
      subset_local_database(fasta, taxa = "Notafish", rank = "family",
                            rank_system = c("family", "genus", "species"),
                            taxonomy_file = tax)
    ),
    "No taxonomy entries matched"
  )
})

test_that("subset_local_database: warns when taxa in taxonomy but absent from FASTA", {
  # Only ACC001 in the FASTA; ACC002 present in taxonomy, missing from FASTA.
  # Result: 1 sequence extracted (not 0), so no warning is expected — just 1 row returned.
  fasta <- make_fasta(SEQS["ACC001"])
  tax   <- make_tax_tsv(TAX_ROWS[1:2])  # ACC001 + ACC002 both Fundulidae
  ref <- suppressMessages(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax)
  )
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$composite_id, "ACC001")
})

# ===========================================================================
# Part H: Input validation
# ===========================================================================

test_that("subset_local_database: error when fasta_path not found", {
  expect_error(
    subset_local_database("nonexistent.fasta", taxa = "Fundulidae",
                          rank = "family",
                          taxonomy_file = tempfile()),
    "not found"
  )
})

test_that("subset_local_database: error when rank not in rank_system", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  expect_error(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "order",
                          rank_system = c("family", "genus", "species"),
                          taxonomy_file = tax),
    "not in rank_system"
  )
})

test_that("subset_local_database: error when both taxonomy and taxonomy_file supplied", {
  fasta <- make_fasta(SEQS)
  expect_error(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          taxonomy_file = tempfile(),
                          taxonomy = data.frame()),
    "exactly one"
  )
})

test_that("subset_local_database: error when neither taxonomy source supplied", {
  fasta <- make_fasta(SEQS)
  expect_error(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family"),
    "exactly one"
  )
})

test_that("subset_local_database: error when require_species = TRUE but species not in rank_system", {
  fasta <- make_fasta(SEQS)
  tax   <- make_tax_tsv(TAX_ROWS)
  expect_error(
    subset_local_database(fasta, taxa = "Fundulidae", rank = "family",
                          rank_system = c("family", "genus"),
                          taxonomy_file = tax,
                          require_species = TRUE),
    "require_species"
  )
})
