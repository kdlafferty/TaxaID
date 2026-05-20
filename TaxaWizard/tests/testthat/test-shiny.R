# Tests for workflow_app() script parser and app generation

test_that(".classify_param detects file paths", {
  p <- TaxaWizard:::.classify_param("input_file", '"/path/to/data.csv"')
  expect_equal(p$type, "file_input")
  expect_equal(p$default, "/path/to/data.csv")
})

test_that(".classify_param detects output file paths", {
  p <- TaxaWizard:::.classify_param("output_path", '"/path/to/results.rds"')
  expect_equal(p$type, "file_output")
})

test_that(".classify_param detects numeric", {
  p <- TaxaWizard:::.classify_param("min_score", "97")
  expect_equal(p$type, "numeric")
  expect_equal(p$default, 97)
})

test_that(".classify_param detects integer", {
  p <- TaxaWizard:::.classify_param("n", "10L")
  expect_equal(p$type, "numeric")
  expect_equal(p$default, 10)
})

test_that(".classify_param detects logical", {
  p <- TaxaWizard:::.classify_param("verbose", "TRUE")
  expect_equal(p$type, "logical")
  expect_equal(p$default, TRUE)
})

test_that(".classify_param detects named numeric vector", {
  p <- TaxaWizard:::.classify_param("thresholds", "c(species = 98, genus = 95)")
  expect_equal(p$type, "named_numeric")
  expect_equal(p$default, c(species = 98, genus = 95))
})

test_that(".classify_param detects numeric range", {
  p <- TaxaWizard:::.classify_param("year_range", "c(2000, 2026)")
  expect_equal(p$type, "numeric_range")
  expect_equal(p$default, c(2000, 2026))
})

test_that(".classify_param detects data.frame", {
  p <- TaxaWizard:::.classify_param("scheme", 'data.frame(l1_name = c("A", "B"))')
  expect_equal(p$type, "data_frame")
})

test_that(".classify_param detects function reference", {
  p <- TaxaWizard:::.classify_param("llm_fn", "TaxaTools::call_anthropic_api")
  expect_equal(p$type, "function_ref")
  expect_equal(p$default, "TaxaTools::call_anthropic_api")
})

test_that(".classify_param detects NULL", {
  p <- TaxaWizard:::.classify_param("date", "NULL")
  expect_equal(p$type, "null_param")
  expect_null(p$default)
})

test_that(".classify_param detects character string", {
  p <- TaxaWizard:::.classify_param("hint", '"Santa Barbara, CA"')
  expect_equal(p$type, "character")
  expect_equal(p$default, "Santa Barbara, CA")
})

test_that(".extract_libraries works", {
  lines <- c(
    "library(TaxaWizard)",
    "library(base)",
    "library(TaxaAssign)",
    "library(TaxaFlag)"
  )
  libs <- TaxaWizard:::.extract_libraries(lines)
  expect_equal(libs, c("TaxaAssign", "TaxaFlag"))
})

test_that(".extract_params finds user parameters", {
  lines <- c(
    "# --- User Parameters ---",
    'input_file <- "/path/to/file.csv"',
    "min_score <- 97",
    "# --- Step 1: Load data ---"
  )
  params <- TaxaWizard:::.extract_params(lines)
  expect_length(params, 2)
  expect_equal(params[[1]]$name, "input_file")
  expect_equal(params[[2]]$name, "min_score")
})

test_that(".extract_params skips infrastructure params", {
  lines <- c(
    "# --- User Parameters ---",
    "debug_mode <- TRUE",
    "debug_n <- 20L",
    "min_score <- 97",
    "# --- Step 1: test ---"
  )
  params <- TaxaWizard:::.extract_params(lines)
  expect_length(params, 1)
  expect_equal(params[[1]]$name, "min_score")
})

test_that(".extract_steps parses quote-style steps", {
  lines <- c(
    '# --- Step 1: Load data ---',
    'df <- .run_step(1, "Load data", quote({',
    '  df <- read.csv("test.csv")',
    '  df',
    '}))',
    '',
    '# --- Step 2: Process ---',
    'result <- .run_step(2, "Process", quote({',
    '  result <- nrow(df)',
    '  result',
    '}))'
  )
  steps <- TaxaWizard:::.extract_steps(lines)
  expect_length(steps, 2)
  expect_equal(steps[[1]]$step_id, 1L)
  expect_equal(steps[[1]]$output_var, "df")
  expect_equal(steps[[2]]$step_id, 2L)
  expect_equal(steps[[2]]$output_var, "result")
})

test_that(".extract_steps parses function-style steps", {
  lines <- c(
    'df <- .run_step(1, "Load data", function() {',
    '  df <- read.csv("test.csv")',
    '  df',
    '})'
  )
  steps <- TaxaWizard:::.extract_steps(lines)
  expect_length(steps, 1)
  expect_equal(steps[[1]]$output_var, "df")
})

test_that(".parse_workflow_script returns complete structure", {
  lines <- c(
    "library(TaxaAssign)",
    "",
    "# --- User Parameters ---",
    "min_score <- 97",
    "",
    '# --- Step 1: Load ---',
    'df <- .run_step(1, "Load", quote({',
    '  data.frame(x = 1)',
    '}))'
  )
  parsed <- TaxaWizard:::.parse_workflow_script(lines)
  expect_true("libraries" %in% names(parsed))
  expect_true("params" %in% names(parsed))
  expect_true("steps" %in% names(parsed))
  expect_equal(parsed$libraries, "TaxaAssign")
  expect_length(parsed$params, 1)
  expect_length(parsed$steps, 1)
})

test_that(".build_app_code produces valid structure", {
  lines <- c(
    "library(TaxaAssign)",
    "",
    "# --- User Parameters ---",
    "min_score <- 97",
    "",
    '# --- Step 1: Load ---',
    'df <- .run_step(1, "Load", quote({',
    '  data.frame(x = 1)',
    '}))'
  )
  parsed <- TaxaWizard:::.parse_workflow_script(lines)
  app_code <- TaxaWizard:::.build_app_code(parsed)
  app_text <- paste(app_code, collapse = "\n")

  expect_true(grepl("library\\(shiny\\)", app_text))
  expect_true(grepl("library\\(TaxaAssign\\)", app_text))
  expect_true(grepl("shinyApp\\(ui, server\\)", app_text))
  expect_true(grepl("param_min_score", app_text))
  expect_true(grepl("numericInput", app_text))
  expect_true(grepl("downloadButton", app_text))
})

test_that("workflow_app rejects missing script", {
  expect_error(
    workflow_app("/nonexistent/script.R"),
    "Please provide the path"
  )
})

test_that("workflow_app writes app.R", {
  skip_if_not_installed("shiny")
  lines <- c(
    "library(utils)",
    "",
    "# --- User Parameters ---",
    "n <- 10",
    "",
    '# --- Step 1: Create data ---',
    'df <- .run_step(1, "Create", quote({',
    '  data.frame(x = seq_len(n))',
    '}))'
  )
  tmp_script <- tempfile(fileext = ".R")
  writeLines(lines, tmp_script)
  tmp_dir <- tempdir()

  app_path <- workflow_app(tmp_script, output_dir = tmp_dir, launch = FALSE)
  expect_true(file.exists(app_path))

  app_code <- readLines(app_path)
  expect_true(any(grepl("shinyApp", app_code)))

  unlink(tmp_script)
})


# ============================================================================
# .segment_script() tests
# ============================================================================

test_that(".segment_script extracts libraries", {
  lines <- c(
    'library(dplyr)',
    'library(ggplot2)',
    '',
    'x <- 10',
    'plot(x)'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  expect_true("dplyr" %in% seg$libraries)
  expect_true("ggplot2" %in% seg$libraries)
})

test_that(".segment_script identifies parameter candidates", {
  lines <- c(
    'library(stats)',
    '',
    'n_iter <- 100',
    'threshold <- 0.05',
    'input_file <- "data.csv"',
    'use_cache <- TRUE',
    '',
    '# Analysis',
    'result <- lm(y ~ x, data = df)'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  expect_equal(length(seg$param_candidates), 4L)
  nms <- vapply(seg$param_candidates, `[[`, character(1), "name")
  expect_true(all(c("n_iter", "threshold", "input_file", "use_cache") %in% nms))
})

test_that(".segment_script classifies param types correctly", {
  lines <- c(
    'n <- 100',
    'flag <- TRUE',
    'path <- "output.csv"',
    'label <- "hello"',
    '',
    'print(n)'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  types <- setNames(
    vapply(seg$param_candidates, `[[`, character(1), "type"),
    vapply(seg$param_candidates, `[[`, character(1), "name")
  )
  expect_equal(types[["n"]], "numeric")
  expect_equal(types[["flag"]], "logical")
  expect_equal(types[["label"]], "character")
})

test_that(".segment_script stops collecting params at first non-assignment", {
  lines <- c(
    'x <- 10',
    'print("hello")',
    'y <- 20'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  # Only x should be a param; y comes after a non-assignment
  nms <- vapply(seg$param_candidates, `[[`, character(1), "name")
  expect_true("x" %in% nms)
  expect_false("y" %in% nms)
})

test_that(".segment_script identifies steps from remaining code", {
  lines <- c(
    'n <- 10',
    '',
    '# Step 1: Load data',
    'df <- read.csv("data.csv")',
    '',
    '# Step 2: Analyze',
    'result <- summary(df)',
    'print(result)'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  expect_true(length(seg$step_candidates) >= 2L)
  # Each step should have code_text
  for (s in seg$step_candidates) {
    expect_true(nzchar(s$code_text))
  }
})

test_that(".segment_script uses comment headers as step descriptions", {
  lines <- c(
    '## Load data',
    'df <- read.csv("x.csv")',
    '',
    '## Run model',
    'mod <- lm(y ~ x, data = df)'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  descs <- vapply(seg$step_candidates, `[[`, character(1), "description")
  expect_true(any(grepl("Load data", descs)))
  expect_true(any(grepl("Run model", descs)))
})

test_that(".segment_script extracts output_var from last assignment", {
  lines <- c(
    '# Step',
    'tmp <- read.csv("x.csv")',
    'df <- tmp[1:10, ]',
    '',
    '# Another step',
    'print(df)'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  # First step's output_var should be "df"
  expect_equal(seg$step_candidates[[1]]$output_var, "df")
})

test_that(".segment_script handles script with no params", {
  lines <- c(
    'df <- read.csv("x.csv")',
    'print(df)'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  expect_equal(length(seg$param_candidates), 0L)
  expect_true(length(seg$step_candidates) >= 1L)
})

test_that(".segment_script handles empty script", {
  lines <- character(0)
  seg <- TaxaWizard:::.segment_script(lines)
  expect_equal(length(seg$libraries), 0L)
  expect_equal(length(seg$param_candidates), 0L)
  expect_equal(length(seg$step_candidates), 0L)
})

test_that(".segment_script handles script with parse errors", {
  lines <- c("x <-", "if (")
  expect_warning(
    seg <- TaxaWizard:::.segment_script(lines),
    "parse errors"
  )
  expect_equal(length(seg$param_candidates), 0L)
})

test_that(".segment_script skips library and source calls in step detection", {
  lines <- c(
    'library(dplyr)',
    'source("helpers.R")',
    'n <- 5',
    '',
    'result <- n + 1'
  )
  seg <- TaxaWizard:::.segment_script(lines)
  # n is a param, library/source skipped, result is a step
  nms <- vapply(seg$param_candidates, `[[`, character(1), "name")
  expect_true("n" %in% nms)
  expect_true(length(seg$step_candidates) >= 1L)
})

test_that(".is_simple_assignment recognizes literals", {
  expect_true(TaxaWizard:::.is_simple_assignment(quote(x <- 10)))
  expect_true(TaxaWizard:::.is_simple_assignment(quote(x <- "hello")))
  expect_true(TaxaWizard:::.is_simple_assignment(quote(x <- TRUE)))
  expect_true(TaxaWizard:::.is_simple_assignment(quote(x <- NULL)))
  expect_true(TaxaWizard:::.is_simple_assignment(quote(x <- c(1, 2, 3))))
})

test_that(".is_simple_assignment rejects function calls", {
  expect_false(TaxaWizard:::.is_simple_assignment(quote(x <- read.csv("f"))))
  expect_false(TaxaWizard:::.is_simple_assignment(quote(x <- lm(y ~ x))))
  expect_false(TaxaWizard:::.is_simple_assignment(quote(print("hello"))))
})

test_that("workflow_app errors with annotate='none' on generic script", {
  skip_if_not_installed("shiny")
  lines <- c('x <- 10', 'print(x)')
  tmp <- tempfile(fileext = ".R")
  writeLines(lines, tmp)
  expect_error(
    workflow_app(tmp, launch = FALSE, annotate = "none"),
    "No TaxaWizard step markers"
  )
  unlink(tmp)
})

test_that("annotate_script errors when file not found", {
  expect_error(
    annotate_script("/nonexistent/file.R"),
    "Script not found"
  )
})

test_that("annotate_script errors when llm mode without llm_fn", {
  tmp <- tempfile(fileext = ".R")
  writeLines("x <- 1", tmp)
  expect_error(
    annotate_script(tmp, mode = "llm"),
    "llm_fn is required"
  )
  unlink(tmp)
})
