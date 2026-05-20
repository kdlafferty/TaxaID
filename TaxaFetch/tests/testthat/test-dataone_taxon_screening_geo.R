# Tests for the geo_scope extension to build_taxon_screen_prompt() and
# the combined-mode parser in parse_taxon_screening_response().
# Session 25: initial tests.

# Minimal catalog fixture matching harvest_dataone_catalog() / search_literature()
.make_catalog <- function(n = 3L) {
  tibble::tibble(
    id          = paste0("W", seq_len(n)),
    title       = paste("Paper", seq_len(n)),
    abstract    = paste("Abstract about fish species in California", seq_len(n)),
    keywords    = "fish; ecology; California",
    doi         = paste0("10.1234/test.", seq_len(n)),
    pdf_url     = NA_character_,
    year        = 2020L,
    authors     = "Smith J",
    journal     = "Test Journal",
    geo_match   = NA_character_,
    taxon_match = NA_character_
  )
}

test_that("build_taxon_screen_prompt: geo_scope = NULL produces solo mode prompt", {
  catalog <- .make_catalog()
  prompt  <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = NULL,
    verbose     = FALSE
  )
  expect_null(prompt$geo_scope)
  # Solo mode prompt must contain "index, match" column spec
  expect_true(grepl("index.*match", prompt$prompts[[1L]], ignore.case = TRUE))
  # Must NOT contain geo_match column spec
  expect_false(grepl("geo_match", prompt$prompts[[1L]], ignore.case = TRUE))
})

test_that("build_taxon_screen_prompt: geo_scope supplied produces combined mode prompt", {
  catalog <- .make_catalog()
  prompt  <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = "southern California",
    verbose     = FALSE
  )
  expect_equal(prompt$geo_scope, "southern California")
  # Combined prompt must contain both column names
  expect_true(grepl("taxon_match", prompt$prompts[[1L]]))
  expect_true(grepl("geo_match",   prompt$prompts[[1L]]))
  # Must contain the geo scope text
  expect_true(grepl("southern California", prompt$prompts[[1L]]))
})

test_that("build_taxon_screen_prompt: geo_scope validation", {
  catalog <- .make_catalog()
  expect_error(
    build_taxon_screen_prompt(catalog, "gobies", geo_scope = "", verbose = FALSE),
    "geo_scope.*non-empty character string"
  )
  expect_error(
    build_taxon_screen_prompt(catalog, "gobies", geo_scope = NA, verbose = FALSE),
    "geo_scope.*non-empty character string"
  )
})

test_that("build_taxon_screen_prompt: geo_scope stored in S3 object", {
  catalog <- .make_catalog()
  prompt  <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = "Santa Barbara Channel",
    verbose     = FALSE
  )
  expect_equal(prompt$geo_scope, "Santa Barbara Channel")
  expect_s3_class(prompt, "taxon_prompt")
  expect_s3_class(prompt, "llm_prompt")
})

test_that("print.taxon_prompt: shows geo_scope when present", {
  catalog <- .make_catalog(1L)
  prompt  <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = "southern California",
    verbose     = FALSE
  )
  out <- capture.output(print(prompt))
  expect_true(any(grepl("Geo scope", out)))
  expect_true(any(grepl("southern California", out)))
})

test_that("print.taxon_prompt: no geo_scope line when NULL", {
  catalog <- .make_catalog(1L)
  prompt  <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = NULL,
    verbose     = FALSE
  )
  out <- capture.output(print(prompt))
  expect_false(any(grepl("Geo scope", out)))
})

test_that("parse_taxon_screening_response: solo mode parses index,match correctly", {
  catalog <- .make_catalog(2L)
  prompt  <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = NULL,
    verbose     = FALSE
  )
  raw_text <- "index,match\n1,YES\n2,NO"
  result   <- parse_taxon_screening_response(raw_text, prompt)

  expect_true("taxon_match" %in% names(result))
  expect_false("geo_match"  %in% names(result))
  expect_equal(result$taxon_match[result$id == "W1"], TRUE)
  expect_equal(result$taxon_match[result$id == "W2"], FALSE)
  expect_equal(result$taxon_source[result$id == "W1"], "llm_yes")
  expect_equal(result$taxon_source[result$id == "W2"], "llm_no")
})

test_that("parse_taxon_screening_response: combined mode parses taxon_match and geo_match", {
  catalog <- .make_catalog(2L)
  prompt  <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = "southern California",
    verbose     = FALSE
  )
  raw_text <- "index,taxon_match,geo_match\n1,YES,YES\n2,NO,YES"
  result   <- parse_taxon_screening_response(raw_text, prompt)

  expect_true("taxon_match" %in% names(result))
  expect_true("geo_match"   %in% names(result))
  expect_true(is.logical(result$taxon_match))
  expect_true(is.logical(result$geo_match))
  expect_equal(result$taxon_match[result$id == "W1"], TRUE)
  expect_equal(result$geo_match[result$id   == "W1"], TRUE)
  expect_equal(result$taxon_match[result$id == "W2"], FALSE)
  expect_equal(result$geo_match[result$id   == "W2"], TRUE)
})

test_that("parse_taxon_screening_response: stale geo_match column dropped before join", {
  # Catalog has pre-existing geo_match column (e.g. from search_literature())
  catalog <- .make_catalog(1L)
  # The parser should strip stale columns and not produce geo_match.x / geo_match.y
  prompt  <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = "California",
    verbose     = FALSE
  )
  raw_text <- "index,taxon_match,geo_match\n1,YES,YES"
  result   <- parse_taxon_screening_response(raw_text, prompt)

  # No .x / .y collision columns
  expect_false(any(grepl("\\.x$|\\.y$", names(result))))
  expect_true("taxon_match" %in% names(result))
  expect_true("geo_match"   %in% names(result))
})

test_that("parse_taxon_screening_response: combined mode all rows returned", {
  catalog  <- .make_catalog(3L)
  prompt   <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = "California",
    verbose     = FALSE
  )
  raw_text <- "index,taxon_match,geo_match\n1,YES,NO\n2,NO,YES\n3,YES,YES"
  result   <- parse_taxon_screening_response(raw_text, prompt)

  # All input rows returned
  expect_equal(nrow(result), nrow(catalog))
})

test_that("parse_taxon_screening_response: missing LLM response rows default to FALSE", {
  catalog  <- .make_catalog(3L)
  prompt   <- build_taxon_screen_prompt(
    catalog     = catalog,
    taxon_scope = "gobies",
    geo_scope   = "California",
    verbose     = FALSE
  )
  # LLM only returned row 1
  raw_text <- "index,taxon_match,geo_match\n1,YES,YES"
  result   <- suppressWarnings(
    parse_taxon_screening_response(raw_text, prompt)
  )
  expect_equal(nrow(result), 3L)
  # Rows 2 and 3 should be FALSE / llm_no_response
  expect_false(result$taxon_match[result$id == "W2"])
  expect_equal(result$taxon_source[result$id == "W2"], "llm_no_response")
})
