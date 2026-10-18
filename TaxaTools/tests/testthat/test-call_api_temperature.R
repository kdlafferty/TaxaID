# ==============================================================================
# test-call_api_temperature.R
# Tests for the optional `temperature` argument of call_api() and
# call_anthropic_api(). Fully offline: the HTTP layer is mocked.
# ==============================================================================

.body_of <- function(req) req$body$data

.builders <- function() {
  list(
    anthropic = TaxaTools:::.build_anthropic_request,
    gemini = TaxaTools:::.build_gemini_request,
    openai = TaxaTools:::.build_openai_compat_request
  )
}

.build_with <- function(fn, temperature) {
  fn("https://example.invalid/v1", "dummy-model", "hello", 100L, "dummy-key",
    list(),
    temperature = temperature
  )
}

# 1. Builders ------------------------------------------------------------------

test_that("builders omit temperature entirely when NULL", {
  for (nm in names(.builders())) {
    b <- .body_of(.build_with(.builders()[[nm]], NULL))
    expect_false("temperature" %in% names(b), info = nm)
    if (nm == "gemini") {
      expect_false("temperature" %in% names(b$generationConfig), info = nm)
      expect_equal(b$generationConfig$maxOutputTokens, 100L)
    }
  }
})

test_that("builders send temperature = 0.2 in the right place", {
  b <- .body_of(.build_with(TaxaTools:::.build_anthropic_request, 0.2))
  expect_identical(b$temperature, 0.2)
  expect_equal(b$max_tokens, 100L)

  b <- .body_of(.build_with(TaxaTools:::.build_openai_compat_request, 0.2))
  expect_identical(b$temperature, 0.2)
  expect_equal(b$max_tokens, 100L)

  b <- .body_of(.build_with(TaxaTools:::.build_gemini_request, 0.2))
  expect_identical(b$generationConfig$temperature, 0.2)
  expect_equal(b$generationConfig$maxOutputTokens, 100L)
  expect_false("temperature" %in% names(b))
})

test_that("temperature = 0 is sent (not dropped as falsy)", {
  for (nm in names(.builders())) {
    b <- .body_of(.build_with(.builders()[[nm]], 0))
    val <- if (nm == "gemini") b$generationConfig$temperature else b$temperature
    expect_identical(val, 0, info = nm)
  }
})

# 2. call_api() end to end with mocked HTTP ------------------------------------

.captured_body <- function(provider, temperature) {
  captured <- NULL
  testthat::local_mocked_bindings(
    req_perform = function(req, ...) {
      captured <<- req
      list()
    },
    resp_status = function(resp) 200L,
    resp_body_json = function(resp, ...) {
      list(
        content = list(list(type = "text", text = "ok")),
        usage = list(input_tokens = 1L, output_tokens = 1L),
        candidates = list(list(content = list(parts = list(list(text = "ok"))))),
        usageMetadata = list(promptTokenCount = 1L, candidatesTokenCount = 1L),
        choices = list(list(message = list(content = "ok"))),
        usage = list(prompt_tokens = 1L, completion_tokens = 1L)
      )
    },
    .package = "httr2",
    .env = parent.frame()
  )
  suppressWarnings(
    call_api("hello",
      provider = provider, api_key = "dummy-key",
      model = "dummy-model", temperature = temperature
    )
  )
  expect_false(is.null(captured))
  captured$body$data
}

test_that("call_api end to end: NULL omits temperature, 0.2 sends it", {
  b <- .captured_body("anthropic", NULL)
  expect_false("temperature" %in% names(b))
  b <- .captured_body("anthropic", 0.2)
  expect_identical(b$temperature, 0.2)

  b <- .captured_body("openai", NULL)
  expect_false("temperature" %in% names(b))
  b <- .captured_body("openai", 0.2)
  expect_identical(b$temperature, 0.2)

  b <- .captured_body("gemini", NULL)
  expect_false("temperature" %in% names(b$generationConfig))
  b <- .captured_body("gemini", 0.2)
  expect_identical(b$generationConfig$temperature, 0.2)
})

# 3. Validation -----------------------------------------------------------------

test_that("call_api rejects invalid temperature with a message naming it", {
  expect_error(call_api("hi", temperature = -1), "temperature")
  expect_error(call_api("hi", temperature = "0.2"), "temperature")
  expect_error(call_api("hi", temperature = c(0.1, 0.2)), "temperature")
  expect_error(call_api("hi", temperature = NA), "temperature")
  expect_error(call_api("hi", temperature = NA_real_), "temperature")
  expect_error(call_api("hi", temperature = Inf), "temperature")
})

test_that("call_api accepts temperature 0 and 1 (no temperature error)", {
  for (tt in c(0, 1)) {
    err <- tryCatch(
      call_api(42, temperature = tt),
      error = function(e) conditionMessage(e)
    )
    # Fails later on prompt_str, so validation passed.
    expect_match(err, "prompt_str")
    expect_false(grepl("temperature", err))
  }
})

# 4. call_anthropic_api forwards -------------------------------------------------

test_that("call_anthropic_api forwards temperature to call_api", {
  seen <- "unset"
  local_mocked_bindings(
    call_api = function(prompt_str, ..., temperature = NULL) {
      seen <<- temperature
      "ok"
    }
  )
  call_anthropic_api("hi", api_key = "k", temperature = 0.2)
  expect_identical(seen, 0.2)

  seen <- "unset"
  call_anthropic_api("hi", api_key = "k")
  expect_null(seen)
})

# 5. Formals ---------------------------------------------------------------------

test_that("temperature is the last formal, default NULL, of both functions", {
  for (f in list(call_api, call_anthropic_api)) {
    fm <- formals(f)
    expect_identical(names(fm)[length(fm)], "temperature")
    expect_null(fm$temperature)
  }
})
