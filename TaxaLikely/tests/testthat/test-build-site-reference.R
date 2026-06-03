# tests/testthat/test-build-site-reference.R
# Offline tests for build_site_reference().
#
# build_site_reference() orchestrates fetch_reference_sequences(),
# optionally flag_reference_errors() + build_sequence_matrix(), optionally
# audit_barcode_coverage(), and optionally write_reference_fasta().
# All external calls are mocked via local_mocked_bindings().

# ---------------------------------------------------------------------------
# Shared fixtures
# ---------------------------------------------------------------------------

make_ref_df <- function() {
  data.frame(
    composite_id = c("ACC001", "ACC002", "ACC003"),
    family       = c("Fundulidae", "Fundulidae", "Gobiidae"),
    genus        = c("Fundulus",   "Fundulus",   "Gillichthys"),
    species      = c("Fundulus heteroclitus", "Fundulus parvipinnis",
                     "Gillichthys mirabilis"),
    sequence     = c("ATCG", "GCTA", "TTTT"),
    stringsAsFactors = FALSE
  )
}

make_coverage <- function() {
  list(
    census = data.frame(
      group               = c("Fundulus", "Gillichthys"),
      total               = c(3L, 2L),
      in_reference        = c(2L, 1L),
      has_seqs_not_in_ref = c(0L, 0L),
      unreferenced        = c(1L, 1L),
      is_complete         = c(FALSE, FALSE),
      stringsAsFactors    = FALSE
    ),
    unreferenced = c("Fundulus majalis", "Gillichthys seta")
  )
}

# ===========================================================================
# Part A: Input validation (fully offline — no mocks needed)
# ===========================================================================

test_that("build_site_reference: error on empty taxa", {
  expect_error(
    build_site_reference(taxa = character(0), barcode_term = "MiFishU"),
    "non-empty character vector"
  )
})

test_that("build_site_reference: error on empty barcode_term", {
  expect_error(
    build_site_reference(taxa = "Fundulus", barcode_term = character(0)),
    "non-empty character vector"
  )
})

test_that("build_site_reference: error on non-character taxa", {
  expect_error(
    build_site_reference(taxa = 123, barcode_term = "MiFishU"),
    "non-empty character vector"
  )
})

test_that("build_site_reference: error on invalid output_dir type", {
  expect_error(
    build_site_reference(taxa = "Fundulus", barcode_term = "MiFishU",
                         output_dir = 123),
    "output_dir"
  )
})

# ===========================================================================
# Part B: Mocked functional tests — no NCBI, flag_errors=FALSE
# ===========================================================================

test_that("build_site_reference: returns named list with correct components", {
  local_mocked_bindings(
    fetch_reference_sequences = function(...) make_ref_df(),
    audit_barcode_coverage    = function(...) make_coverage(),
    .package = "TaxaLikely"
  )
  result <- suppressMessages(
    build_site_reference(taxa = "Fundulus", barcode_term = "MiFishU")
  )
  expect_type(result, "list")
  expect_named(result, c("reference_df", "errors", "census", "unreferenced"))
})

test_that("build_site_reference: reference_df matches fetched data", {
  local_mocked_bindings(
    fetch_reference_sequences = function(...) make_ref_df(),
    audit_barcode_coverage    = function(...) make_coverage(),
    .package = "TaxaLikely"
  )
  result <- suppressMessages(
    build_site_reference(taxa = "Fundulus", barcode_term = "MiFishU")
  )
  expect_equal(nrow(result$reference_df), 3L)
  expect_equal(result$reference_df$composite_id,
               c("ACC001", "ACC002", "ACC003"))
})

test_that("build_site_reference: errors is NULL when flag_errors = FALSE", {
  local_mocked_bindings(
    fetch_reference_sequences = function(...) make_ref_df(),
    audit_barcode_coverage    = function(...) make_coverage(),
    .package = "TaxaLikely"
  )
  result <- suppressMessages(
    build_site_reference(taxa = "Fundulus", barcode_term = "MiFishU",
                         flag_errors = FALSE)
  )
  expect_null(result$errors)
})

test_that("build_site_reference: census populated when audit_coverage = TRUE", {
  local_mocked_bindings(
    fetch_reference_sequences = function(...) make_ref_df(),
    audit_barcode_coverage    = function(...) make_coverage(),
    .package = "TaxaLikely"
  )
  result <- suppressMessages(
    build_site_reference(taxa = "Fundulus", barcode_term = "MiFishU",
                         audit_coverage = TRUE)
  )
  expect_equal(nrow(result$census), 2L)
  expect_equal(result$unreferenced,
               c("Fundulus majalis", "Gillichthys seta"))
})

test_that("build_site_reference: census is empty df when audit_coverage = FALSE", {
  local_mocked_bindings(
    fetch_reference_sequences = function(...) make_ref_df(),
    .package = "TaxaLikely"
  )
  result <- suppressMessages(
    build_site_reference(taxa = "Fundulus", barcode_term = "MiFishU",
                         audit_coverage = FALSE)
  )
  expect_equal(nrow(result$census),        0L)
  expect_equal(length(result$unreferenced), 0L)
})

# ===========================================================================
# Part C: output_dir writes files
# ===========================================================================

test_that("build_site_reference: creates output_dir and writes fasta + tsv", {
  out_dir <- tempfile()
  local_mocked_bindings(
    fetch_reference_sequences = function(...) make_ref_df(),
    audit_barcode_coverage    = function(...) make_coverage(),
    write_reference_fasta     = function(reference_df, file, taxonomy_file, ...) {
      writeLines("", file)
      writeLines("", taxonomy_file)
    },
    .package = "TaxaLikely"
  )
  suppressMessages(
    build_site_reference(taxa = "Fundulus", barcode_term = "MiFishU",
                         output_dir = out_dir)
  )
  expect_true(dir.exists(out_dir))
  expect_true(file.exists(file.path(out_dir, "reference.fasta")))
  expect_true(file.exists(file.path(out_dir, "reference_taxonomy.tsv")))
})

# ===========================================================================
# Part D: flag_errors = TRUE requires DECIPHER
# ===========================================================================

test_that("build_site_reference: flag_errors = TRUE errors when DECIPHER absent", {
  skip_if(
    requireNamespace("DECIPHER", quietly = TRUE) &&
    requireNamespace("Biostrings", quietly = TRUE),
    "DECIPHER + Biostrings installed — skipping absent-package test"
  )
  local_mocked_bindings(
    fetch_reference_sequences = function(...) make_ref_df(),
    .package = "TaxaLikely"
  )
  expect_error(
    suppressMessages(
      build_site_reference(taxa = "Fundulus", barcode_term = "MiFishU",
                           flag_errors = TRUE, audit_coverage = FALSE)
    ),
    "DECIPHER"
  )
})

# ===========================================================================
# Part E: fetch returns 0 rows → error
# ===========================================================================

test_that("build_site_reference: error when fetch returns 0 sequences", {
  empty_df <- make_ref_df()[0L, ]
  local_mocked_bindings(
    fetch_reference_sequences = function(...) empty_df,
    .package = "TaxaLikely"
  )
  expect_error(
    suppressMessages(
      build_site_reference(taxa = "Notafish", barcode_term = "MiFishU",
                           audit_coverage = FALSE)
    ),
    "No sequences downloaded"
  )
})
