# tests/testthat/test-llm_api_utils.R
#
# Tests for llm_api_utils.R — provider functions and prompt_api() dispatcher.
# All tests are pure: no real API calls, no network, no files.
#
# Coverage:
#   A. call_anthropic_api()  — input validation and error handling
#   B. call_gemini_api()     — input validation and error handling
#   C. call_openai_api()     — input validation and error handling
#   D. call_ollama_api()     — input validation and error handling
#   E. prompt_api()          — dispatcher: llm_fn routing, chunk handling,
#                              partial failure, mock provider integration
#   F. %||%                  — null-coalescing operator

# ==============================================================================
# Helpers
# ==============================================================================

# Minimal llm_prompt object sufficient to drive prompt_api()
.make_test_prompt <- function(n_chunks = 1L, taxa = c("Gadus morhua")) {
  chunks  <- split(taxa, ceiling(seq_along(taxa) / ceiling(length(taxa) / n_chunks)))
  prompts <- lapply(chunks, function(ch) paste("Rate habitats for:", paste(ch, collapse = ", ")))
  structure(
    list(
      prompts  = prompts,
      chunks   = chunks,
      taxa     = taxa,
      n_chunks = n_chunks,
      n_items  = length(taxa)
    ),
    class = c("habitat_prompt", "llm_prompt")
  )
}

# Mock provider: always succeeds, returns a predictable CSV string
.mock_llm_success <- function(prompt_str, ...) {
  "taxon_name,Marine,Terrestrial,Other_weight,habitat_best_guess\nGadus morhua,1.0,0.0,0.0,"
}

# Mock provider: always fails with an error
.mock_llm_fail <- function(prompt_str, ...) {
  stop("mock provider error")
}

# Mock provider that records how many times it was called
.make_counter_llm <- function() {
  count <- 0L
  list(
    fn = function(prompt_str, ...) {
      count <<- count + 1L
      "taxon_name,Marine,Other_weight,habitat_best_guess\nGadus morhua,1.0,0.0,"
    },
    get_count = function() count
  )
}

# ==============================================================================
# A. call_anthropic_api() — input validation
# ==============================================================================

test_that("call_anthropic_api: rejects non-character prompt_str", {
  expect_error(
    call_anthropic_api(123),
    "'prompt_str' must be a length-1 character string"
  )
})

test_that("call_anthropic_api: rejects length > 1 prompt_str", {
  expect_error(
    call_anthropic_api(c("a", "b")),
    "'prompt_str' must be a length-1 character string"
  )
})

test_that("call_anthropic_api: stops with clear message when api_key is empty", {
  expect_error(
    call_anthropic_api("hello", api_key = ""),
    "no API key found"
  )
})

test_that("call_anthropic_api: error message mentions ANTHROPIC_API_KEY", {
  expect_error(
    call_anthropic_api("hello", api_key = ""),
    "ANTHROPIC_API_KEY"
  )
})

# ==============================================================================
# B. call_gemini_api() — input validation
# ==============================================================================

test_that("call_gemini_api: rejects non-character prompt_str", {
  expect_error(
    call_gemini_api(123),
    "'prompt_str' must be a length-1 character string"
  )
})

test_that("call_gemini_api: rejects length > 1 prompt_str", {
  expect_error(
    call_gemini_api(c("a", "b")),
    "'prompt_str' must be a length-1 character string"
  )
})

test_that("call_gemini_api: stops with clear message when api_key is empty", {
  expect_error(
    call_gemini_api("hello", api_key = ""),
    "no API key found"
  )
})

test_that("call_gemini_api: error message mentions GEMINI_API_KEY", {
  expect_error(
    call_gemini_api("hello", api_key = ""),
    "GEMINI_API_KEY"
  )
})

test_that("call_gemini_api: error message mentions aistudio.google.com", {
  expect_error(
    call_gemini_api("hello", api_key = ""),
    "aistudio.google.com"
  )
})

# ==============================================================================
# C. call_openai_api() — input validation
# ==============================================================================

test_that("call_openai_api: rejects non-character prompt_str", {
  expect_error(
    call_openai_api(123),
    "'prompt_str' must be a length-1 character string"
  )
})

test_that("call_openai_api: rejects length > 1 prompt_str", {
  expect_error(
    call_openai_api(c("a", "b")),
    "'prompt_str' must be a length-1 character string"
  )
})

test_that("call_openai_api: stops with clear message when api_key is empty", {
  expect_error(
    call_openai_api("hello", api_key = ""),
    "no API key found"
  )
})

test_that("call_openai_api: error message mentions OPENAI_API_KEY", {
  expect_error(
    call_openai_api("hello", api_key = ""),
    "OPENAI_API_KEY"
  )
})

# ==============================================================================
# D. call_ollama_api() — input validation
# (Ollama needs no key, so no key-missing test; connection failure is tested)
# ==============================================================================

test_that("call_ollama_api: rejects non-character prompt_str", {
  expect_error(
    call_ollama_api(123),
    "'prompt_str' must be a length-1 character string"
  )
})

test_that("call_ollama_api: rejects length > 1 prompt_str", {
  expect_error(
    call_ollama_api(c("a", "b")),
    "'prompt_str' must be a length-1 character string"
  )
})

test_that("call_ollama_api: connection failure gives clear message", {
  # Use a port that is guaranteed to be closed
  expect_error(
    call_ollama_api("hello", base_url = "http://localhost:19999"),
    "could not connect to Ollama"
  )
})

test_that("call_ollama_api: connection failure message mentions ollama.com", {
  expect_error(
    call_ollama_api("hello", base_url = "http://localhost:19999"),
    "ollama.com"
  )
})

# ==============================================================================
# E. prompt_api() — dispatcher behaviour
# ==============================================================================

test_that("prompt_api: rejects non-llm_prompt object", {
  expect_error(
    prompt_api(list(prompts = "x")),
    "must be an llm_prompt object"
  )
})

test_that("prompt_api: rejects non-function llm_fn", {
  prompt <- .make_test_prompt()
  expect_error(
    prompt_api(prompt, llm_fn = "not_a_function"),
    "llm_fn.*must be a function"
  )
})

test_that("prompt_api: calls llm_fn and returns character string", {
  prompt <- .make_test_prompt()
  result <- prompt_api(prompt, llm_fn = .mock_llm_success, verbose = FALSE)
  expect_true(is.character(result))
  expect_length(result, 1L)
})

test_that("prompt_api: result contains expected CSV content from mock", {
  prompt <- .make_test_prompt()
  result <- prompt_api(prompt, llm_fn = .mock_llm_success, verbose = FALSE)
  expect_true(grepl("taxon_name", result))
  expect_true(grepl("Gadus morhua", result))
})

test_that("prompt_api: calls llm_fn once per chunk", {
  counter <- .make_counter_llm()
  prompt  <- .make_test_prompt(n_chunks = 3L,
                               taxa = paste0("Species ", seq_len(6)))
  prompt_api(prompt, llm_fn = counter$fn, verbose = FALSE)
  expect_equal(counter$get_count(), 3L)
})

test_that("prompt_api: works with a custom provider closure", {
  my_provider <- function(p, ...) {
    paste0("taxon_name,Kelp_Forest,Other_weight,habitat_best_guess\n",
           "Gadus morhua,1.0,0.0,")
  }
  prompt <- .make_test_prompt()
  result <- prompt_api(prompt, llm_fn = my_provider, verbose = FALSE)
  expect_true(grepl("Kelp_Forest", result))
})

test_that("prompt_api: all-chunk failure stops with informative error", {
  prompt <- .make_test_prompt()
  expect_error(
    suppressWarnings(
      prompt_api(prompt, llm_fn = .mock_llm_fail, verbose = FALSE)
    ),
    "all chunks failed"
  )
})

test_that("prompt_api: partial chunk failure warns but returns partial result", {
  # Two-chunk prompt; first chunk succeeds, second fails
  chunk_num <- 0L
  mixed_llm <- function(p, ...) {
    chunk_num <<- chunk_num + 1L
    if (chunk_num == 1L) {
      "taxon_name,Marine,Other_weight,habitat_best_guess\nSpecies 1,1.0,0.0,"
    } else {
      stop("chunk 2 failed")
    }
  }
  prompt <- .make_test_prompt(n_chunks = 2L,
                              taxa = paste0("Species ", seq_len(4)))
  expect_warning(
    result <- prompt_api(prompt, llm_fn = mixed_llm, verbose = FALSE),
    "chunk.*failed"
  )
  # Result should still contain chunk 1 output
  expect_true(grepl("Species 1", result))
})

test_that("prompt_api: multi-chunk results are concatenated into one string", {
  chunk_num <- 0L
  multi_llm <- function(p, ...) {
    chunk_num <<- chunk_num + 1L
    if (chunk_num == 1L) {
      "taxon_name,Marine,Other_weight,habitat_best_guess\nSpecies 1,1.0,0.0,"
    } else {
      # Chunk 2 repeats the header (as a real LLM would); dispatcher strips it
      "taxon_name,Marine,Other_weight,habitat_best_guess\nSpecies 2,0.0,1.0,estuarine"
    }
  }
  prompt <- .make_test_prompt(n_chunks = 2L,
                              taxa = paste0("Species ", seq_len(4)))
  result <- prompt_api(prompt, llm_fn = multi_llm, verbose = FALSE)
  # Both species should appear; header should appear only once
  expect_true(grepl("Species 1", result))
  expect_true(grepl("Species 2", result))
  header_count <- lengths(regmatches(result, gregexpr("taxon_name", result)))
  expect_equal(header_count, 1L)
})

test_that("prompt_api: verbose = FALSE suppresses messages", {
  prompt <- .make_test_prompt()
  expect_silent(
    prompt_api(prompt, llm_fn = .mock_llm_success, verbose = FALSE)
  )
})

test_that("prompt_api: verbose = TRUE emits messages", {
  prompt <- .make_test_prompt()
  expect_message(
    prompt_api(prompt, llm_fn = .mock_llm_success, verbose = TRUE)
  )
})

test_that("prompt_api: default llm_fn is call_anthropic_api (fails without key)", {
  # With no valid API key in env, the default llm_fn should fire a key error
  withr::with_envvar(
    c(ANTHROPIC_API_KEY = ""),
    expect_error(
      suppressWarnings(
        prompt_api(.make_test_prompt(), verbose = FALSE)
      ),
      "no API key found|all chunks failed"
    )
  )
})

# ==============================================================================
# F. %||% operator
# ==============================================================================

test_that("%||%: returns left when non-NULL and non-empty", {
  expect_equal("a" %||% "b", "a")
  expect_equal(1L  %||% 2L,  1L)
})

test_that("%||%: returns right when left is NULL", {
  expect_equal(NULL %||% "fallback", "fallback")
})

test_that("%||%: returns right when left is length-0 vector", {
  expect_equal(character(0) %||% "fallback", "fallback")
  expect_equal(integer(0)   %||% 99L,        99L)
})

test_that("%||%: does not trigger on FALSE or NA (only NULL/empty)", {
  expect_equal(FALSE %||% TRUE, FALSE)
  expect_equal(NA    %||% "x",  NA)
})
