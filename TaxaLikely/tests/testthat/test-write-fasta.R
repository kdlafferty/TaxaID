test_that("write_reference_fasta: rejects invalid inputs", {
  expect_error(write_reference_fasta("not_df", "out.fasta"),
               "data frame")
  expect_error(write_reference_fasta(
    data.frame(x = 1), "out.fasta"),
    "composite_id.*sequence|sequence.*composite_id")
  expect_error(write_reference_fasta(
    data.frame(composite_id = "a", sequence = "ACGT"),
    123),
    "single non-empty character")
})

test_that("write_reference_fasta: rank_system column missing gives error", {
  df <- data.frame(composite_id = "acc1", sequence = "ACGT",
                   genus = "Fundulus", species = "Fundulus parvipinnis",
                   stringsAsFactors = FALSE)
  expect_error(
    write_reference_fasta(df, tempfile(), rank_system = c("family", "genus")),
    "family"
  )
})

test_that("write_reference_fasta: writes valid FASTA", {
  df <- data.frame(
    composite_id = c("acc1", "acc2"),
    sequence     = c("ACGTACGT", "TTTTCCCC"),
    genus        = c("Fundulus", "Gambusia"),
    species      = c("Fundulus parvipinnis", "Gambusia affinis"),
    stringsAsFactors = FALSE
  )
  fasta_file <- tempfile(fileext = ".fasta")
  res <- write_reference_fasta(df, fasta_file)

  lines <- readLines(fasta_file)
  expect_equal(length(lines), 4L)         # 2 headers + 2 sequences
  expect_true(startsWith(lines[1], ">acc1"))
  expect_true(grepl("Fundulus parvipinnis", lines[1]))
  expect_equal(lines[2], "ACGTACGT")
  expect_true(startsWith(lines[3], ">acc2"))
  expect_equal(lines[4], "TTTTCCCC")

  # Returns input invisibly
  expect_identical(res, df)
})

test_that("write_reference_fasta: header excludes NA taxonomy values", {
  df <- data.frame(
    composite_id = "acc1",
    sequence     = "ACGT",
    family       = NA_character_,
    genus        = "Fundulus",
    species      = NA_character_,
    stringsAsFactors = FALSE
  )
  fasta_file <- tempfile(fileext = ".fasta")
  write_reference_fasta(df, fasta_file)
  lines <- readLines(fasta_file)
  # Header should contain genus but not "NA"
  expect_true(grepl("Fundulus", lines[1]))
  expect_false(grepl("\\bNA\\b", lines[1]))
})

test_that("write_reference_fasta: writes taxonomy TSV companion", {
  df <- data.frame(
    composite_id = c("acc1", "acc2"),
    sequence     = c("ACGT", "TTTT"),
    family       = c("Fundulidae", "Poeciliidae"),
    genus        = c("Fundulus", "Gambusia"),
    species      = c("Fundulus parvipinnis", "Gambusia affinis"),
    stringsAsFactors = FALSE
  )
  fasta_file <- tempfile(fileext = ".fasta")
  tsv_file   <- tempfile(fileext = ".tsv")
  write_reference_fasta(df, fasta_file, taxonomy_file = tsv_file)

  tsv_lines <- readLines(tsv_file)
  expect_equal(length(tsv_lines), 2L)
  expect_true(startsWith(tsv_lines[1], "acc1\t"))
  expect_true(grepl("Fundulidae;Fundulus;Fundulus parvipinnis", tsv_lines[1]))
  expect_true(grepl("Poeciliidae;Gambusia;Gambusia affinis", tsv_lines[2]))
})

test_that("write_reference_fasta: auto-detects rank_system from columns", {
  df <- data.frame(
    composite_id = "acc1",
    sequence     = "ACGT",
    family       = "Fundulidae",
    genus        = "Fundulus",
    stringsAsFactors = FALSE
  )
  fasta_file <- tempfile(fileext = ".fasta")
  expect_no_error(write_reference_fasta(df, fasta_file))
})

test_that("write_reference_fasta: single-column taxonomy works", {
  df <- data.frame(
    composite_id = "acc1",
    sequence     = "ACGT",
    species      = "Fundulus parvipinnis",
    stringsAsFactors = FALSE
  )
  fasta_file <- tempfile(fileext = ".fasta")
  write_reference_fasta(df, fasta_file)
  lines <- readLines(fasta_file)
  expect_equal(lines[1], ">acc1 Fundulus parvipinnis")
})

test_that("build_site_reference: validates required inputs", {
  expect_error(build_site_reference(123, "MiFishU"), "taxa must be")
  expect_error(build_site_reference("Fundulus", 123), "barcode_term must be")
  expect_error(build_site_reference(character(0), "MiFishU"), "taxa must be")
})
