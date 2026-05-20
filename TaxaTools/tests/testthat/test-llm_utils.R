# ==============================================================================
# test-llm_utils.R
# Tests for prompt_api(), read_llm_response(), and %||% (already tested elsewhere)
# prompt_manual() requires readline() so only input validation is tested.
# ==============================================================================

# --- prompt_api() input validation --------------------------------------------

test_that("prompt_api rejects non-llm_prompt input", {
  expect_error(prompt_api("plain string"), "must be an llm_prompt object")
  expect_error(prompt_api(list(a = 1)), "must be an llm_prompt object")
})

test_that("prompt_api rejects non-function llm_fn", {
  mock_prompt <- structure(
    list(prompts = list("test"), chunks = list("taxon"),
         n_chunks = 1L, taxa = "Fundulus"),
    class = "llm_prompt"
  )
  expect_error(prompt_api(mock_prompt, llm_fn = "not_a_function"),
               "must be a function")
})

test_that("prompt_api calls llm_fn for each chunk and combines", {
  mock_prompt <- structure(
    list(
      prompts = list("prompt_1", "prompt_2"),
      chunks = list("Fundulus", "Cottus"),
      n_chunks = 2L,
      n_items = 2L,
      taxa = c("Fundulus", "Cottus")
    ),
    class = "llm_prompt"
  )

  call_count <- 0L
  mock_llm <- function(prompt_str, ...) {
    call_count <<- call_count + 1L
    paste0("taxon_name,habitat\nResponse_", call_count)
  }

  result <- suppressMessages(
    prompt_api(mock_prompt, llm_fn = mock_llm, pause_seconds = 0)
  )
  expect_equal(call_count, 2L)
  expect_true(is.character(result))
  expect_true(nchar(result) > 0)
})

test_that("prompt_api errors when all chunks fail", {
  mock_prompt <- structure(
    list(
      prompts = list("fail_1"),
      chunks = list("Fundulus"),
      n_chunks = 1L,
      n_items = 1L,
      taxa = "Fundulus"
    ),
    class = "llm_prompt"
  )

  failing_llm <- function(prompt_str, ...) stop("API error")

  expect_error(
    suppressWarnings(suppressMessages(
      prompt_api(mock_prompt, llm_fn = failing_llm, pause_seconds = 0)
    )),
    "all chunks failed"
  )
})

# --- prompt_manual() input validation -----------------------------------------

test_that("prompt_manual rejects non-llm_prompt input", {
  expect_error(prompt_manual("plain string"), "must be an llm_prompt object")
})

# --- read_llm_response() -----------------------------------------------------

test_that("read_llm_response rejects non-character input", {
  expect_error(read_llm_response(42), "must be a non-empty character vector")
  expect_error(read_llm_response(character(0)), "must be a non-empty character vector")
})

test_that("read_llm_response reads a single file", {
  tmp <- tempfile(fileext = ".txt")
  writeLines(c("taxon_name,Marine,Freshwater",
               "Fundulus parvipinnis,0.9,0.1"), tmp)
  result <- read_llm_response(tmp)
  expect_true(grepl("taxon_name", result))
  expect_true(grepl("Fundulus parvipinnis", result))
  unlink(tmp)
})

test_that("read_llm_response strips duplicate headers from chunk 2+", {
  tmp1 <- tempfile(fileext = ".txt")
  tmp2 <- tempfile(fileext = ".txt")
  writeLines(c("taxon_name,Marine,Freshwater",
               "Fundulus parvipinnis,0.9,0.1"), tmp1)
  writeLines(c("taxon_name,Marine,Freshwater",
               "Cottus asper,0.0,1.0"), tmp2)
  result <- read_llm_response(c(tmp1, tmp2))
  # Header should appear once from file 1, stripped from file 2
  header_count <- length(gregexpr("taxon_name", result)[[1]])
  expect_equal(header_count, 1L)
  expect_true(grepl("Fundulus parvipinnis", result))
  expect_true(grepl("Cottus asper", result))
  unlink(c(tmp1, tmp2))
})

test_that("read_llm_response warns on missing file", {
  expect_warning(
    read_llm_response("nonexistent_file_12345.txt"),
    "file not found"
  )
})

test_that("read_llm_response warns when taxon_name absent", {
  tmp <- tempfile(fileext = ".txt")
  writeLines("just some text without the expected column", tmp)
  expect_warning(
    read_llm_response(tmp),
    "taxon_name.*not found"
  )
  unlink(tmp)
})
