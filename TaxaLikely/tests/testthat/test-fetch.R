# tests/testthat/test-fetch.R
# Tests for fetch_reference_sequences() and read_reference_fasta() —
# input validation only (network tests are separate)

# ---- fetch_reference_sequences validation ------------------------------------

test_that("fetch_reference_sequences errors on non-character taxa", {
  expect_error(
    fetch_reference_sequences(taxa = 123, barcode_term = "COI"),
    "character"
  )
})

test_that("fetch_reference_sequences errors on missing barcode_term", {
  expect_error(
    fetch_reference_sequences(taxa = "Gadidae"),
    'argument "barcode_term" is missing'
  )
})

# ---- read_reference_fasta validation -----------------------------------------

test_that("read_reference_fasta errors on non-existent file", {
  expect_error(
    read_reference_fasta("/nonexistent/path.fasta",
                         taxonomy = data.frame(composite_id = "x"),
                         rank_system = "species"),
    "not found"
  )
})

test_that("read_reference_fasta errors on non-data-frame taxonomy", {
  # Create a temp fasta file
  tmp <- tempfile(fileext = ".fasta")
  writeLines(c(">seq1", "ATCG"), tmp)
  on.exit(unlink(tmp))

  expect_error(
    read_reference_fasta(tmp, taxonomy = list(), rank_system = "species"),
    "must be a data frame"
  )
})

test_that("read_reference_fasta errors on empty FASTA", {
  tmp <- tempfile(fileext = ".fasta")
  file.create(tmp)
  on.exit(unlink(tmp))

  expect_error(
    read_reference_fasta(tmp,
                         taxonomy = data.frame(composite_id = "x", species = "A"),
                         rank_system = "species"),
    "empty"
  )
})

# ---- .build_search_term (internal) -------------------------------------------

test_that(".build_search_term builds correct NCBI query with GENE tags", {
  # Access internal function
  bst <- TaxaLikely:::.build_search_term

  out <- bst("Gadidae", "COI")
  expect_true(grepl("Gadidae\\[Organism\\]", out))
  expect_true(grepl("COI\\[GENE\\]", out))
})

test_that(".build_search_term uses All Fields for primer names", {
  bst <- TaxaLikely:::.build_search_term
  out <- bst("Gadidae", "MiFish")
  expect_true(grepl("MiFish\\[All Fields\\]", out))
})

test_that(".build_search_term adds date clause", {
  bst <- TaxaLikely:::.build_search_term
  out <- bst("Gadidae", "12S", min_date = "2020/01/01", max_date = "2024/12/31")
  expect_true(grepl("\\[PDAT\\]", out))
  expect_true(grepl("2020/01/01", out))
})

test_that(".build_search_term uses All Fields for ribosomal subunits", {
  bst <- TaxaLikely:::.build_search_term
  out12 <- bst("Gadidae", "12S")
  expect_true(grepl("12S\\[All Fields\\]", out12))
  out16 <- bst("Gadidae", "16S")
  expect_true(grepl("16S\\[All Fields\\]", out16))
})

test_that(".build_search_term ORs multiple barcode terms", {
  bst <- TaxaLikely:::.build_search_term
  out <- bst("Gadidae", c("12S", "16S"))
  expect_true(grepl("12S\\[All Fields\\]", out))
  expect_true(grepl("16S\\[All Fields\\]", out))
  expect_true(grepl(" OR ", out))
})
