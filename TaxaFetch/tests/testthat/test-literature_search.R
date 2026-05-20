test_that("search_literature: input validation — empty taxon_scope", {
  expect_error(
    search_literature(taxon_scope = "", bbox = NULL, api_key = "fake"),
    "'taxon_scope' must be a non-empty character string"
  )
})

test_that("search_literature: input validation — NA taxon_scope", {
  expect_error(
    search_literature(taxon_scope = NA_character_, bbox = NULL, api_key = "fake"),
    "'taxon_scope' must be a non-empty character string"
  )
})

test_that("search_literature: input validation — bad bbox", {
  expect_error(
    search_literature("gobies", bbox = c(-120, -117), api_key = "fake"),
    "'bbox' must be a numeric vector of length 4"
  )
  expect_error(
    search_literature("gobies", bbox = c("a", "b", "c", "d"), api_key = "fake"),
    "'bbox' must be a numeric vector of length 4"
  )
})

test_that("search_literature: input validation — missing API key", {
  # Only fires when api_key is empty string (env var not set)
  expect_error(
    search_literature("gobies", api_key = ""),
    "OpenAlex API key not found"
  )
})

test_that(".decode_openalex_abstract: handles NULL and empty input", {
  expect_identical(TaxaFetch:::.decode_openalex_abstract(NULL), NA_character_)
  expect_identical(TaxaFetch:::.decode_openalex_abstract(list()), NA_character_)
})

test_that(".decode_openalex_abstract: decodes simple inverted index correctly", {
  # Simulated inverted index: "hello world" at positions 0, 1
  inv <- list(hello = list(0L), world = list(1L))
  result <- TaxaFetch:::.decode_openalex_abstract(inv)
  expect_equal(result, "hello world")
})

test_that(".decode_openalex_abstract: handles numeric (non-list) positions", {
  # OpenAlex sometimes returns positions as plain integers not nested lists
  inv <- list(hello = 0L, world = 1L)
  result <- TaxaFetch:::.decode_openalex_abstract(inv)
  expect_equal(result, "hello world")
})

test_that("search_literature: geo_scope validation — empty string rejected", {
  expect_error(
    search_literature("gobies", geo_scope = "", api_key = "fake"),
    "geo_scope.*non-empty character string"
  )
})

test_that("search_literature: geo_scope validation — NA rejected", {
  expect_error(
    search_literature("gobies", geo_scope = NA_character_, api_key = "fake"),
    "geo_scope.*non-empty character string"
  )
})

test_that(".query_hash: returns consistent string for same inputs", {
  h1 <- TaxaFetch:::.query_hash("gobies", "California", "200", "2000", "TRUE")
  h2 <- TaxaFetch:::.query_hash("gobies", "California", "200", "2000", "TRUE")
  expect_identical(h1, h2)
})

test_that(".query_hash: returns different strings for different inputs", {
  h1 <- TaxaFetch:::.query_hash("gobies", "California")
  h2 <- TaxaFetch:::.query_hash("rockfish", "California")
  expect_false(identical(h1, h2))
})

test_that("download_literature_pdfs: input validation — not a data frame", {
  expect_error(
    download_literature_pdfs("not_a_df", output_dir = tempdir()),
    "'catalog' must be a data frame"
  )
})

test_that("download_literature_pdfs: input validation — missing columns", {
  bad_catalog <- data.frame(title = "Test", stringsAsFactors = FALSE)
  expect_error(
    download_literature_pdfs(bad_catalog, output_dir = tempdir()),
    "missing required columns"
  )
})

test_that("download_literature_pdfs: returns catalog with local_pdf_path column", {
  catalog <- data.frame(
    id      = "W123",
    pdf_url = NA_character_,
    stringsAsFactors = FALSE
  )
  result <- download_literature_pdfs(
    catalog    = catalog,
    output_dir = file.path(tempdir(), "test_dl"),
    verbose    = FALSE
  )
  expect_true("local_pdf_path" %in% names(result))
  expect_equal(nrow(result), 1L)
  expect_true(is.na(result$local_pdf_path[1L]))
})

test_that("download_literature_pdfs: creates output_dir if absent", {
  new_dir <- file.path(tempdir(), paste0("dl_test_", sample(1e6, 1L)))
  expect_false(dir.exists(new_dir))
  catalog <- data.frame(id = "W1", pdf_url = NA_character_,
                         stringsAsFactors = FALSE)
  download_literature_pdfs(catalog, output_dir = new_dir, verbose = FALSE)
  expect_true(dir.exists(new_dir))
  unlink(new_dir, recursive = TRUE)
})
