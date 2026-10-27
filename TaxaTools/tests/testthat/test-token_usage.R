# Tests for token_usage() and reset_token_usage()
# All tests are fully offline -- no LLM calls.

# Helper: inject fake records into the ledger
.inject_records <- function(...) {
  recs <- list(...)
  .token_ledger$records <- recs
}

.make_record <- function(caller = "review_assignments", provider = "anthropic",
                         model = "claude-sonnet-4-6", input = 100L, output = 50L) {
  list(
    timestamp = Sys.time(),
    caller    = caller,
    provider  = provider,
    model     = model,
    input     = as.integer(input),
    output    = as.integer(output),
    total     = as.integer(input) + as.integer(output)
  )
}

# Clean up: reset ledger before each test group
on.exit(suppressMessages(reset_token_usage()), add = TRUE)


# ---- reset_token_usage() -----------------------------------------------------

test_that("reset_token_usage clears the ledger", {
  .inject_records(.make_record())
  expect_equal(length(.token_ledger$records), 1L)
  suppressMessages(reset_token_usage())
  expect_equal(length(.token_ledger$records), 0L)
})

test_that("reset_token_usage emits a message", {
  expect_message(reset_token_usage(), "cleared")
})


# ---- token_usage() -- empty ledger --------------------------------------------

test_that("token_usage with empty ledger emits message and returns invisibly", {
  suppressMessages(reset_token_usage())
  expect_message(token_usage(), "no LLM calls")
})


# ---- token_usage(by = 'call') ------------------------------------------------

test_that("token_usage by='call' returns one row per record", {
  .inject_records(
    .make_record(input = 100L, output = 50L),
    .make_record(caller = "review_assignments", input = 200L, output = 80L)
  )
  result <- token_usage(by = "call")
  expect_s3_class(result, "data.frame")
  expect_equal(nrow(result), 2L)
})

test_that("token_usage by='call' has expected columns", {
  .inject_records(.make_record())
  result <- token_usage(by = "call")
  expect_true(all(c(
    "timestamp", "caller", "provider", "model",
    "input", "output", "total"
  ) %in% names(result)))
})

test_that("token_usage by='call' total = input + output", {
  .inject_records(.make_record(input = 100L, output = 50L))
  result <- token_usage(by = "call")
  expect_equal(result$total, 150L)
})


# ---- token_usage(by = 'function') -------------------------------------------

test_that("token_usage by='function' aggregates by caller", {
  .inject_records(
    .make_record(caller = "review_assignments", input = 100L, output = 50L),
    .make_record(caller = "review_assignments", input = 120L, output = 60L),
    .make_record(caller = "build_habitat_lookup", input = 200L, output = 80L)
  )
  result <- token_usage(by = "function")
  expect_equal(nrow(result), 2L)
  ra <- result[result$caller == "review_assignments", ]
  expect_equal(ra$n_calls, 2L)
  expect_equal(ra$input, 220L)
  expect_equal(ra$output, 110L)
  expect_equal(ra$total, 330L)
})


# ---- token_usage(by = 'provider') -------------------------------------------

test_that("token_usage by='provider' aggregates by provider", {
  .inject_records(
    .make_record(provider = "anthropic", input = 100L, output = 50L),
    .make_record(provider = "gemini", input = 200L, output = 80L),
    .make_record(provider = "anthropic", input = 50L, output = 20L)
  )
  result <- token_usage(by = "provider")
  expect_equal(nrow(result), 2L)
  ant <- result[result$provider == "anthropic", ]
  expect_equal(ant$total, 220L)
})


# ---- token_usage(by = 'session') --------------------------------------------

test_that("token_usage by='session' returns single row with grand totals", {
  .inject_records(
    .make_record(input = 100L, output = 50L),
    .make_record(input = 200L, output = 80L)
  )
  result <- token_usage(by = "session")
  expect_equal(nrow(result), 1L)
  expect_equal(result$n_calls, 2L)
  expect_equal(result$input, 300L)
  expect_equal(result$output, 130L)
  expect_equal(result$total, 430L)
})


# ---- cost column -------------------------------------------------------------

test_that("cost_per_1k_input adds cost_usd column", {
  .inject_records(.make_record(input = 1000L, output = 1000L))
  result <- token_usage(
    by = "session",
    cost_per_1k_input = 0.003,
    cost_per_1k_output = 0.015
  )
  expect_true("cost_usd" %in% names(result))
  expect_equal(result$cost_usd, round((1 * 0.003 + 1 * 0.015), 4))
})

test_that("cost_per_1k_output defaults to cost_per_1k_input when NULL", {
  .inject_records(.make_record(input = 1000L, output = 1000L))
  result_same <- token_usage(
    by = "session",
    cost_per_1k_input = 0.003,
    cost_per_1k_output = NULL
  )
  result_equal <- token_usage(
    by = "session",
    cost_per_1k_input = 0.003,
    cost_per_1k_output = 0.003
  )
  expect_equal(result_same$cost_usd, result_equal$cost_usd)
})

test_that(".get_llm_caller() survives a closure in the function slot", {
  # do.call(fun_object, ...) puts the closure itself, not its name, in the
  # call's function slot. Deparsing a closure returns its whole source, and a
  # long vector in a scalar `&&` used to error after the API reply returned.
  long_fn <- function(x) {
    a <- 1
    b <- 2
    c <- 3
    a + b + c + x
  }
  closure_call <- as.call(list(long_fn, 1))
  # The old code deparsed the whole closure: confirm that is a vector, so the
  # stack below genuinely exercises the failure.
  expect_gt(length(deparse(closure_call[[1L]])), 1L)

  # Closure frame outermost, as when a workflow calls do.call(fn_object, ...)
  # at top level: it must be skipped, and the named frame inside it used.
  stack <- list(closure_call, quote(review_assignments(x)), quote(call_api(p)))
  expect_identical(TaxaTools:::.get_llm_caller(stack), "review_assignments")

  # A stack holding only the closure and skipped frames labels as "unknown".
  expect_identical(
    TaxaTools:::.get_llm_caller(list(closure_call, quote(call_api(p)))),
    "unknown"
  )

  # An anonymous call in the function slot deparses to several lines. It
  # must be skipped, not deparsed into a label such as "(function(x) {".
  anon_call <- quote((function(x) {
    a <- 1
    a + x
  })(1))
  expect_gt(length(deparse(anon_call[[1L]])), 1L)
  expect_identical(
    TaxaTools:::.get_llm_caller(list(anon_call, quote(review_assignments(x)))),
    "review_assignments"
  )

  # tryCatch's internal frames never label a caller.
  expect_identical(
    TaxaTools:::.get_llm_caller(list(
      quote(tryCatchList(expr, names, parentenv, handlers)),
      quote(doTryCatch(return(expr), name, parentenv, handler)),
      quote(review_assignments(x))
    )),
    "review_assignments"
  )

  # pkg::fn still labels by its full name.
  expect_identical(
    TaxaTools:::.get_llm_caller(list(quote(TaxaFlag::review_assignments(x)))),
    "TaxaFlag::review_assignments"
  )
})

test_that(".get_llm_caller() returns one string under a real do.call() on a closure", {
  long_fn <- function() {
    a <- 1
    b <- 2
    TaxaTools:::.get_llm_caller()
  }
  out <- do.call(long_fn, list())
  expect_type(out, "character")
  expect_length(out, 1L)
  expect_false(out %in% c("tryCatchList", "tryCatchOne", "doTryCatch"))
})
