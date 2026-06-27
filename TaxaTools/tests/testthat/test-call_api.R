# ==============================================================================
# test-call_api.R
# Tests for call_api() and internal response parsers.
# All tests are fully offline — no live API calls.
#
# Coverage:
#   - call_api() input validation
#   - max_input_tokens pre-flight token guard
#   - .resolve_provider() error paths
#   - Unknown provider error
#   - .parse_anthropic_response() — success, HTTP error, no text blocks
#   - .parse_gemini_response()    — success, HTTP error, safety block
#   - .parse_openai_compat_response() — success, HTTP error, empty content
# ==============================================================================

# Helper: reset session registry state between tests.
# Uses asNamespace() so this works both via devtools::test() (load_all)
# and via testthat::test_dir() on an installed package.
.reset_registry <- function() {
  env <- get(".registry_env", envir = asNamespace("TaxaTools"))
  env$session_pins    <- NULL
  env$discovered      <- NULL
  env$registry        <- NULL
  env$registry_loaded <- FALSE
}

# ==============================================================================
# call_api() input validation
# ==============================================================================

test_that("call_api rejects non-character prompt_str", {
  expect_error(call_api(42),            "must be a length-1 character string")
  expect_error(call_api(TRUE),          "must be a length-1 character string")
  expect_error(call_api(list("text")),  "must be a length-1 character string")
})

test_that("call_api rejects length > 1 prompt_str", {
  expect_error(call_api(c("a", "b")), "must be a length-1 character string")
})

# ==============================================================================
# max_input_tokens pre-flight guard
# ==============================================================================

test_that("max_input_tokens stops before HTTP when estimated tokens exceed limit", {
  # ceiling(350 / 3.5) = 100; limit = 50 -> error
  big_prompt <- paste(rep("x", 350), collapse = "")
  expect_error(
    call_api(big_prompt, max_input_tokens = 50),
    "exceeds max_input_tokens"
  )
})

test_that("max_input_tokens pre-flight error reports estimated and limit values", {
  big_prompt <- paste(rep("x", 350), collapse = "")
  err <- tryCatch(
    call_api(big_prompt, max_input_tokens = 50),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "100")  # estimated tokens
  expect_match(err, "50")   # limit
})

test_that("short prompt passes max_input_tokens pre-flight and fails at provider step", {
  # "hi" = 2 chars -> ceiling(2/3.5) = 1 token; well under 1000
  # Should fail at .resolve_provider(), not at the token guard
  withr::with_options(list(TaxaID.provider = NULL),
    withr::with_envvar(c(
      ANTHROPIC_API_KEY    = NA,
      GEMINI_API_KEY       = NA,
      OPENAI_API_KEY       = NA,
      AZURE_OPENAI_API_KEY = NA
    ), {
      err <- tryCatch(
        call_api("hi", max_input_tokens = 1000),
        error = function(e) conditionMessage(e)
      )
      expect_false(grepl("exceeds max_input_tokens", err))
    })
  )
})

# ==============================================================================
# Provider resolution errors
# ==============================================================================

test_that("call_api errors with setup instructions when no provider configured", {
  withr::with_options(list(TaxaID.provider = NULL),
    withr::with_envvar(c(
      ANTHROPIC_API_KEY    = NA,
      GEMINI_API_KEY       = NA,
      OPENAI_API_KEY       = NA,
      AZURE_OPENAI_API_KEY = NA
    ), {
      expect_error(call_api("test"), "no LLM provider configured")
    })
  )
})

test_that("call_api error suggests library(TaxaTools) when key is set but option is missing", {
  withr::with_options(list(TaxaID.provider = NULL),
    withr::with_envvar(c(
      ANTHROPIC_API_KEY    = "fake-key",
      GEMINI_API_KEY       = NA,
      OPENAI_API_KEY       = NA,
      AZURE_OPENAI_API_KEY = NA
    ), {
      err <- tryCatch(call_api("test"), error = function(e) conditionMessage(e))
      expect_match(err, "library\\(TaxaTools\\)")
    })
  )
})

test_that("call_api errors on unknown provider", {
  on.exit(.reset_registry())
  expect_error(
    call_api("test", provider = "completely_unknown_xyz"),
    "unknown provider"
  )
})

# ==============================================================================
# .parse_anthropic_response() — internal parser
# ==============================================================================

test_that(".parse_anthropic_response extracts text and token counts from 200 response", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(
      content = list(list(type = "text", text = "Sea urchins belong to Echinodermata.")),
      usage   = list(input_tokens = 12L, output_tokens = 8L)
    ),
    .package = "httr2"
  )

  result <- TaxaTools:::.parse_anthropic_response(list(), "anthropic")
  expect_equal(result$text, "Sea urchins belong to Echinodermata.")
  expect_equal(result$tokens$input,  12L)
  expect_equal(result$tokens$output,  8L)
})

test_that(".parse_anthropic_response errors on non-200 HTTP status", {
  local_mocked_bindings(
    resp_status    = function(resp) 401L,
    resp_body_json = function(resp, ...) list(error = list(message = "Unauthorized")),
    .package = "httr2"
  )

  expect_error(
    TaxaTools:::.parse_anthropic_response(list(), "anthropic"),
    "HTTP 401"
  )
})

test_that(".parse_anthropic_response includes provider name in HTTP error", {
  local_mocked_bindings(
    resp_status    = function(resp) 403L,
    resp_body_json = function(resp, ...) list(error = list(message = "Forbidden")),
    .package = "httr2"
  )

  err <- tryCatch(
    TaxaTools:::.parse_anthropic_response(list(), "anthropic"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "anthropic")
})

test_that(".parse_anthropic_response errors when response has no text blocks", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(
      content = list(list(type = "tool_use", id = "tool_123")),
      usage   = list(input_tokens = 5L, output_tokens = 0L)
    ),
    .package = "httr2"
  )

  expect_error(
    TaxaTools:::.parse_anthropic_response(list(), "anthropic"),
    "no text blocks"
  )
})

# ==============================================================================
# .parse_gemini_response() — internal parser
# ==============================================================================

test_that(".parse_gemini_response extracts text and token counts from 200 response", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(
      candidates    = list(list(
        content = list(parts = list(list(text = "Echinodermata")))
      )),
      usageMetadata = list(promptTokenCount = 10L, candidatesTokenCount = 3L)
    ),
    .package = "httr2"
  )

  result <- TaxaTools:::.parse_gemini_response(list(), "gemini")
  expect_equal(result$text, "Echinodermata")
  expect_equal(result$tokens$input,  10L)
  expect_equal(result$tokens$output,  3L)
})

test_that(".parse_gemini_response concatenates multi-part responses", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(
      candidates    = list(list(
        content = list(parts = list(list(text = "Echino"), list(text = "dermata")))
      )),
      usageMetadata = list(promptTokenCount = 5L, candidatesTokenCount = 2L)
    ),
    .package = "httr2"
  )

  result <- TaxaTools:::.parse_gemini_response(list(), "gemini")
  expect_equal(result$text, "Echinodermata")
})

test_that(".parse_gemini_response errors on non-200 HTTP status", {
  local_mocked_bindings(
    resp_status    = function(resp) 429L,
    resp_body_json = function(resp, ...) list(error = list(message = "Rate limited")),
    .package = "httr2"
  )

  expect_error(
    TaxaTools:::.parse_gemini_response(list(), "gemini"),
    "HTTP 429"
  )
})

test_that(".parse_gemini_response errors when blocked by safety filter", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(
      candidates     = list(),
      promptFeedback = list(blockReason = "SAFETY")
    ),
    .package = "httr2"
  )

  expect_error(
    TaxaTools:::.parse_gemini_response(list(), "gemini"),
    "safety filter"
  )
})

test_that(".parse_gemini_response errors when no candidates returned without safety block", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(candidates = list()),
    .package = "httr2"
  )

  expect_error(
    TaxaTools:::.parse_gemini_response(list(), "gemini"),
    "no candidates"
  )
})

# ==============================================================================
# .parse_openai_compat_response() — internal parser
# ==============================================================================

test_that(".parse_openai_compat_response extracts text and token counts", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(
      choices = list(list(
        message       = list(content = "Echinodermata"),
        finish_reason = "stop"
      )),
      usage = list(prompt_tokens = 8L, completion_tokens = 2L)
    ),
    .package = "httr2"
  )

  result <- TaxaTools:::.parse_openai_compat_response(list(), "openai")
  expect_equal(result$text, "Echinodermata")
  expect_equal(result$tokens$input,  8L)
  expect_equal(result$tokens$output, 2L)
})

test_that(".parse_openai_compat_response errors on non-200 HTTP status", {
  local_mocked_bindings(
    resp_status    = function(resp) 403L,
    resp_body_json = function(resp, ...) list(error = list(message = "Forbidden")),
    .package = "httr2"
  )

  expect_error(
    TaxaTools:::.parse_openai_compat_response(list(), "openai"),
    "HTTP 403"
  )
})

test_that(".parse_openai_compat_response errors when content is empty or whitespace", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(
      choices = list(list(
        message       = list(content = "   "),
        finish_reason = "length"
      ))
    ),
    .package = "httr2"
  )

  expect_error(
    TaxaTools:::.parse_openai_compat_response(list(), "openai"),
    "empty response"
  )
})

test_that(".parse_openai_compat_response errors when choices is empty", {
  local_mocked_bindings(
    resp_status    = function(resp) 200L,
    resp_body_json = function(resp, ...) list(choices = list()),
    .package = "httr2"
  )

  expect_error(
    TaxaTools:::.parse_openai_compat_response(list(), "openai"),
    "no choices"
  )
})
