# ==============================================================================
# test-draft_text.R
# Tests for build_report_context(), draft_methods_text(), draft_results_text()
# ==============================================================================

# --- build_report_context() ---------------------------------------------------

test_that("build_report_context returns report_context S3 object", {
  ctx <- build_report_context(study_description = "eDNA survey")
  expect_s3_class(ctx, "report_context")
  expect_equal(ctx$study_description, "eDNA survey")
})

test_that("build_report_context with all fields", {
  ctx <- build_report_context(
    study_description = "test study",
    data_type = "eDNA",
    workflow = "Bayesian",
    packages = c("lme4", "dplyr"),
    parameters = list(alpha = 0.05),
    statistics = list(n = 100),
    citations = c("Smith 2020"),
    facts = list(location = "Pacific")
  )
  expect_equal(ctx$data_type, "eDNA")
  expect_equal(ctx$workflow, "Bayesian")
  expect_equal(ctx$packages, c("lme4", "dplyr"))
  expect_equal(ctx$parameters$alpha, 0.05)
  expect_equal(ctx$statistics$n, 100)
  expect_equal(ctx$citations, "Smith 2020")
  expect_equal(ctx$facts$location, "Pacific")
})

test_that("build_report_context removes NULL fields", {
  ctx <- build_report_context(study_description = "test")
  expect_false("data_type" %in% names(ctx))
  expect_false("workflow" %in% names(ctx))
})

test_that("build_report_context with no args returns empty context", {
  ctx <- build_report_context()
  expect_s3_class(ctx, "report_context")
  expect_length(ctx, 0L)
})

test_that("build_report_context validates study_description type", {
  expect_error(build_report_context(study_description = 42),
               "study_description must be a single character")
  expect_error(build_report_context(study_description = c("a", "b")),
               "study_description must be a single character")
})

test_that("build_report_context validates data_type type", {
  expect_error(build_report_context(data_type = 42),
               "data_type must be a single character")
})

test_that("build_report_context validates workflow type", {
  expect_error(build_report_context(workflow = list("x")),
               "workflow must be a single character")
})

test_that("build_report_context validates packages type", {
  expect_error(build_report_context(packages = 42),
               "packages must be a character vector")
})

test_that("build_report_context validates parameters type", {
  expect_error(build_report_context(parameters = "not a list"),
               "parameters must be a named list")
})

test_that("build_report_context validates statistics type", {
  expect_error(build_report_context(statistics = "not a list"),
               "statistics must be a named list")
})

test_that("build_report_context validates citations type", {
  expect_error(build_report_context(citations = 42),
               "citations must be a character vector")
})

test_that("build_report_context validates facts type", {
  expect_error(build_report_context(facts = "not a list"),
               "facts must be a named list")
})

# --- print.report_context() ---------------------------------------------------

test_that("print.report_context produces output and returns invisibly", {
  ctx <- build_report_context(
    study_description = "test study",
    data_type = "eDNA",
    statistics = list(n = 100)
  )
  out <- capture.output(result <- print(ctx))
  expect_true(length(out) > 0)
  expect_true(any(grepl("Report Context", out)))
  expect_true(any(grepl("eDNA", out)))
  expect_identical(result, ctx)
})

# --- draft_methods_text() input validation ------------------------------------

test_that("draft_methods_text rejects non-character code", {
  expect_error(draft_methods_text(code = 42), "code must be a non-empty character")
})

test_that("draft_methods_text rejects empty character code", {
  expect_error(draft_methods_text(code = character(0)),
               "code must be a non-empty character")
})

test_that("draft_methods_text rejects bad context type", {
  expect_error(
    draft_methods_text(code = "x <- 1", context = list(a = 1)),
    "context must be a report_context"
  )
})

test_that("draft_methods_text rejects bad description type", {
  expect_error(
    draft_methods_text(code = "x <- 1", description = 42),
    "description must be a single character"
  )
})

test_that("draft_methods_text rejects bad audience", {
  expect_error(
    draft_methods_text(code = "x <- 1", audience = "invalid"),
    "'arg' should be one of"
  )
})

test_that("draft_methods_text rejects non-function llm_fn", {
  expect_error(
    draft_methods_text(code = "x <- 1", llm_fn = "not a function"),
    "llm_fn must be a function"
  )
})

test_that("draft_methods_text calls llm_fn with prompt string", {
  captured_prompt <- NULL
  mock_llm <- function(prompt, ...) {
    captured_prompt <<- prompt
    "Methods text here."
  }
  out <- capture.output(
    result <- draft_methods_text(code = "x <- lm(y ~ x)", llm_fn = mock_llm)
  )
  expect_true(is.character(captured_prompt))
  expect_true(grepl("lm\\(y ~ x\\)", captured_prompt))
  expect_equal(result, "Methods text here.")
})

test_that("draft_methods_text includes context in prompt", {
  captured_prompt <- NULL
  mock_llm <- function(prompt, ...) {
    captured_prompt <<- prompt
    "Done."
  }
  ctx <- build_report_context(
    study_description = "reef fish survey",
    facts = list(marker = "12S")
  )
  capture.output(draft_methods_text(code = "x <- 1", context = ctx,
                                     llm_fn = mock_llm))
  expect_true(grepl("reef fish survey", captured_prompt))
  expect_true(grepl("12S", captured_prompt))
})

test_that("draft_methods_text truncates long code", {
  captured_prompt <- NULL
  mock_llm <- function(prompt, ...) {
    captured_prompt <<- prompt
    "Done."
  }
  long_code <- paste0("line_", seq_len(500))
  capture.output(
    draft_methods_text(code = long_code, llm_fn = mock_llm, max_code_lines = 50)
  )
  expect_true(grepl("truncated", captured_prompt))
})

# --- draft_results_text() input validation ------------------------------------

test_that("draft_results_text rejects no arguments", {
  expect_error(
    draft_results_text(llm_fn = identity),
    "At least one named R object"
  )
})

test_that("draft_results_text rejects unnamed arguments", {
  expect_error(
    draft_results_text(data.frame(x = 1), llm_fn = identity),
    "All objects passed to ... must be named"
  )
})

test_that("draft_results_text rejects all-NULL arguments", {
  expect_error(
    draft_results_text(a = NULL, b = NULL, llm_fn = identity),
    "All objects passed via ... are NULL"
  )
})

test_that("draft_results_text rejects bad context type", {
  expect_error(
    draft_results_text(x = 1:5, context = "bad", llm_fn = identity),
    "context must be a report_context"
  )
})

test_that("draft_results_text calls llm_fn with object summaries", {
  captured_prompt <- NULL
  mock_llm <- function(prompt, ...) {
    captured_prompt <<- prompt
    "Results here."
  }
  df <- data.frame(species = c("A", "B"), count = c(10, 20))
  capture.output(
    result <- draft_results_text(my_data = df, llm_fn = mock_llm)
  )
  expect_true(grepl("my_data", captured_prompt))
  expect_true(grepl("2 rows", captured_prompt))
  expect_equal(result, "Results here.")
})

test_that("draft_results_text handles different object types", {
  captured_prompt <- NULL
  mock_llm <- function(prompt, ...) {
    captured_prompt <<- prompt
    "Done."
  }
  capture.output(
    draft_results_text(
      nums = 1:10,
      chars = c("a", "b", "c"),
      nested = list(x = 1, y = "two"),
      llm_fn = mock_llm
    )
  )
  expect_true(grepl("nums", captured_prompt))
  expect_true(grepl("chars", captured_prompt))
  expect_true(grepl("nested", captured_prompt))
})
