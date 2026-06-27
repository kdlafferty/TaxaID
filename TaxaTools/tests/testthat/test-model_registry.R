# ==============================================================================
# test-model_registry.R
# Offline tests for the model registry, tier resolution, register_provider(),
# and the base_url parameter on call_openai_api().
# All tests avoid live API calls.
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

# Convenience wrappers for internal functions (same namespace portability reason)
.get_registry  <- function(...) get(".get_registry",  envir = asNamespace("TaxaTools"))(...)
.resolve_model <- function(...) get(".resolve_model", envir = asNamespace("TaxaTools"))(...)


# --- register_provider() input validation -------------------------------------

test_that("register_provider rejects blank name", {
  expect_error(register_provider("", "MY_KEY", "https://example.com"),
               "'name' must be a non-empty character string")
})

test_that("register_provider rejects blank api_key_var", {
  expect_error(register_provider("myprov", "", "https://example.com"),
               "'api_key_var' must be a non-empty character string")
})

test_that("register_provider rejects blank base_url", {
  expect_error(register_provider("myprov", "MY_KEY", ""),
               "'base_url' must be a non-empty character string")
})

test_that("register_provider rejects built-in provider names", {
  for (prov in c("anthropic", "gemini", "openai", "azure_openai")) {
    expect_error(
      register_provider(prov, "SOME_KEY", "https://example.com"),
      "built-in provider"
    )
  }
})


# --- register_provider() registry integration ---------------------------------

test_that("register_provider adds provider to session registry", {
  on.exit(.reset_registry())

  suppressMessages(
    register_provider("testprov", "TEST_API_KEY", "https://api.test.example.com",
      fallback_models = list(fast = "test-mini", mid = "test-std", top = "test-top")
    )
  )

  reg <- .get_registry()
  expect_true("testprov" %in% names(reg$providers))
  expect_equal(reg$providers$testprov$api_key_var, "TEST_API_KEY")
  expect_equal(reg$providers$testprov$base_url, "https://api.test.example.com")
  expect_equal(reg$providers$testprov$models_endpoint,
               "https://api.test.example.com/v1/models")
  expect_equal(reg$providers$testprov$handler_family, "openai_compat")
  expect_equal(reg$providers$testprov$fallback_models$mid, "test-std")
})

test_that("register_provider strips trailing slash from base_url", {
  on.exit(.reset_registry())

  suppressMessages(
    register_provider("slashprov", "SLASH_KEY", "https://api.slash.example.com/",
      fallback_models = list(mid = "model-a")
    )
  )

  reg <- .get_registry()
  expect_equal(reg$providers$slashprov$base_url, "https://api.slash.example.com")
  expect_equal(reg$providers$slashprov$models_endpoint,
               "https://api.slash.example.com/v1/models")
})

test_that("register_provider fallback resolves via .resolve_model()", {
  on.exit(.reset_registry())

  Sys.setenv(TEST_FALLBACK_KEY = "fake-key-value")
  on.exit(Sys.unsetenv("TEST_FALLBACK_KEY"), add = TRUE)

  suppressMessages(
    register_provider("fallbackprov", "TEST_FALLBACK_KEY",
      "https://api.fallback.example.com",
      fallback_models = list(fast = "fb-mini", mid = "fb-std", top = "fb-top")
    )
  )

  # No live API reachable -- should fall back to registered fallback_models
  m <- .resolve_model("fallbackprov", "mid")
  expect_equal(m, "fb-std")

  m_fast <- .resolve_model("fallbackprov", "fast")
  expect_equal(m_fast, "fb-mini")
})


# --- set_model() with registered providers ------------------------------------

test_that("set_model accepts a registered custom provider", {
  on.exit(.reset_registry())

  suppressMessages(
    register_provider("pinprov", "PIN_KEY", "https://api.pin.example.com",
      fallback_models = list(mid = "pin-default")
    )
  )
  Sys.setenv(PIN_KEY = "x")
  on.exit(Sys.unsetenv("PIN_KEY"), add = TRUE)

  suppressMessages(set_model("pinprov", "mid", "pin-custom-v2"))
  m <- .resolve_model("pinprov", "mid")
  expect_equal(m, "pin-custom-v2")

  suppressMessages(set_model("pinprov", "mid", NULL))  # unpin
  m2 <- .resolve_model("pinprov", "mid")
  expect_equal(m2, "pin-default")
})

test_that("set_model still rejects completely unknown provider names", {
  on.exit(.reset_registry())
  expect_error(set_model("doesnotexist", "mid", "some-model"),
               "unknown provider")
})


# --- list_models() with registered providers ----------------------------------

test_that("list_models() includes registered providers when key is set", {
  on.exit(.reset_registry())

  suppressMessages(
    register_provider("listprov", "LIST_TEST_KEY", "https://api.list.example.com",
      fallback_models = list(fast = "lp-mini", mid = "lp-std", top = "lp-top")
    )
  )
  Sys.setenv(LIST_TEST_KEY = "fake")
  on.exit(Sys.unsetenv("LIST_TEST_KEY"), add = TRUE)

  result <- suppressMessages(list_models("listprov"))
  expect_s3_class(result, "data.frame")
  expect_true("listprov" %in% result$provider)
  expect_equal(nrow(result[result$provider == "listprov", ]), 3L)
})


# --- call_openai_api() base_url -----------------------------------------------

test_that("call_openai_api errors with clear message for unregistered base_url", {
  on.exit(.reset_registry())

  err <- tryCatch(
    call_openai_api("test", base_url = "https://unknown.provider.example.com"),
    error = function(e) conditionMessage(e)
  )
  expect_match(err, "'model' must be specified")
  expect_match(err, "register_provider")
})

test_that("call_openai_api resolves tier via registered provider for matching base_url", {
  on.exit(.reset_registry())

  Sys.setenv(COMPAT_TEST_KEY = "fake")
  on.exit(Sys.unsetenv("COMPAT_TEST_KEY"), add = TRUE)

  suppressMessages(
    register_provider("compat", "COMPAT_TEST_KEY", "https://api.compat.example.com",
      fallback_models = list(fast = "compat-mini", mid = "compat-std", top = "compat-top")
    )
  )

  # We can't make a live API call, but we CAN check that model resolution
  # works (reaches the no-key / connection-refused error, not the "must specify model" error)
  err <- tryCatch(
    call_openai_api("test",
      base_url = "https://api.compat.example.com",
      api_key  = "fake"
    ),
    error = function(e) conditionMessage(e)
  )
  # Should fail at HTTP level (connection refused / auth), NOT at model resolution
  expect_false(grepl("'model' must be specified", err))
})
