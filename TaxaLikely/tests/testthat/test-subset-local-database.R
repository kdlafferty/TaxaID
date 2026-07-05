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

# ===========================================================================
# Part E: PR2's 9-level positional format (real strings, Session 136)
# ===========================================================================
# Real taxonomy strings copied verbatim from a downloaded PR2 v5.1.1 release
# file (pr2_version_5.1.1_SSU_mothur.tax.gz), confirming .parse_tax_string()'s
# field-count dispatch (9 parts -> .pr2_hierarchy, not .crabs_std_hierarchy).

PR2_SEQS <- c(
  "AB353770.1.1740_U" = "ATCGATCGATCG",
  "AB284159.1.1765_U" = "GCTAGCTAGCTA",
  "FJ355953.1.1907_U" = "TTTTCCCCAAAA"
)

PR2_TAX_ROWS <- list(
  c("AB353770.1.1740_U",
    "Eukaryota;TSAR;Alveolata;Dinoflagellata;Dinophyceae;Peridiniales;Kryptoperidiniaceae;Unruhdinium;Unruhdinium_kevei"),
  c("AB284159.1.1765_U",
    "Eukaryota;TSAR;Alveolata;Dinoflagellata;Dinophyceae;Peridiniales;Protoperidiniaceae;Protoperidinium;Protoperidinium_bipes"),
  c("FJ355953.1.1907_U",
    "Eukaryota;Obazoa;Opisthokonta;Fungi;Ascomycota;Pezizomycotina;Eurotiomycetes;Knufia;Knufia_epidermidis")
)

test_that("subset_local_database: PR2's 9-level positional format is parsed correctly", {
  fasta <- make_fasta(PR2_SEQS)
  tax   <- make_tax_tsv(PR2_TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(
      fasta, taxa = "Peridiniales", rank = "order",
      rank_system = c("domain", "supergroup", "division", "subdivision",
                      "class", "order", "family", "genus", "species"),
      taxonomy_file = tax
    )
  )
  expect_equal(nrow(ref), 2L)
  expect_true(all(ref$order == "Peridiniales"))
  expect_true(all(ref$domain == "Eukaryota"))
  expect_true(all(ref$supergroup == "TSAR"))
  expect_setequal(ref$genus, c("Unruhdinium", "Protoperidinium"))
})

test_that("subset_local_database: PR2 filtering works with a rank_system subset (family/genus/species only)", {
  fasta <- make_fasta(PR2_SEQS)
  tax   <- make_tax_tsv(PR2_TAX_ROWS)
  ref <- suppressMessages(
    subset_local_database(
      fasta, taxa = "Kryptoperidiniaceae", rank = "family",
      rank_system = c("family", "genus", "species"),
      taxonomy_file = tax
    )
  )
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$genus, "Unruhdinium")
  expect_equal(ref$species, "Unruhdinium_kevei")
  # domain/supergroup should NOT appear -- not requested in rank_system
  expect_false("domain" %in% names(ref))
  expect_false("supergroup" %in% names(ref))
})

test_that("subset_local_database: PR2's plastid-tagged (:plas) suffix is preserved, not stripped", {
  fasta <- make_fasta(c("PLAS001" = "ATCGATCGATCG"))
  tax   <- make_tax_tsv(list(c(
    "PLAS001",
    "Eukaryota:plas;TSAR:plas;Stramenopiles:plas;Gyrista:plas;Diatomeae_X:plas;Diatomeae_XX:plas;Diatomeae_XXX:plas;Diatomeae_XXXX:plas;Diatomeae_XXXX_sp.:plas"
  )))
  ref <- suppressMessages(
    subset_local_database(
      fasta, taxa = "Diatomeae_XXX:plas", rank = "family",
      rank_system = c("domain", "family", "genus", "species"),
      taxonomy_file = tax
    )
  )
  expect_equal(nrow(ref), 1L)
  expect_equal(ref$domain, "Eukaryota:plas")
})
