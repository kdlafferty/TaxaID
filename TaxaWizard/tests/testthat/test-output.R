# Tests for R/output.R -- script/markdown/app generation from a DAG.
# Offline only (no API calls, no shiny required).

# Fresh subdirectory per test (not the shared session tempdir()) so that
# .find_existing_script()'s "generated today" detection can't pick up a
# script left behind by an earlier test in this same file.
.tw_test_dir <- function() {
  dir <- file.path(tempdir(), sprintf("taxawizard-test-%s", basename(tempfile())))
  dir.create(dir, recursive = TRUE)
  dir
}

.make_dag <- function(n_steps = 2) {
  steps <- lapply(seq_len(n_steps), function(i) {
    list(
      step_id     = i,
      edge_id     = sprintf("edge_%d", i),
      package     = "TaxaTools",
      function_name = sprintf("fn_%d", i),
      description = sprintf("Step %d description", i),
      code        = sprintf('step_%d_out <- data.frame(x = 1:3)', i),
      output_var  = sprintf("step_%d_out", i)
    )
  })
  list(
    parameters = list(
      list(name = "input_file", value = '"data.csv"', description = "Input file")
    ),
    steps   = steps,
    outputs = "script"
  )
}

test_that(".generate_script writes a fresh script with header, params, and steps", {
  dir <- .tw_test_dir()
  dag <- .make_dag(2)

  path <- TaxaWizard:::.generate_script(dag, dir, trial = FALSE)
  expect_true(file.exists(path))

  lines <- readLines(path)
  expect_true(any(grepl("^library\\(TaxaWizard\\)", lines)))
  expect_true(any(grepl("^library\\(TaxaTools\\)", lines)))
  expect_true(any(grepl('^input_file <- "data.csv"', lines)))
  expect_true(any(grepl("--- Step 1: Step 1 description ---", lines, fixed = TRUE)))
  expect_true(any(grepl("--- Step 2: Step 2 description ---", lines, fixed = TRUE)))
  expect_true(any(grepl("^total_steps <- 2L", lines)))
})

test_that(".generate_script's debug-mode subsetting only follows the first step", {
  dir <- .tw_test_dir()
  dag <- .make_dag(2)

  path <- TaxaWizard:::.generate_script(dag, dir, trial = FALSE)
  lines <- readLines(path)

  debug_hits <- grep("Apply debug subsetting after initial data load", lines)
  expect_length(debug_hits, 1L)
})

test_that(".find_existing_script finds a script generated today and none otherwise", {
  dir <- .tw_test_dir()
  expect_null(TaxaWizard:::.find_existing_script(dir))

  dag <- .make_dag(1)
  path <- TaxaWizard:::.generate_script(dag, dir, trial = FALSE)

  found <- TaxaWizard:::.find_existing_script(dir)
  expect_equal(found, path)
})

test_that(".generate_script appends to an existing same-day script instead of overwriting", {
  dir <- .tw_test_dir()
  dag1 <- .make_dag(2)
  path1 <- TaxaWizard:::.generate_script(dag1, dir, trial = FALSE)

  dag2 <- .make_dag(1)
  dag2$steps[[1]]$description <- "Extension step"
  dag2$steps[[1]]$output_var  <- "ext_out"

  path2 <- TaxaWizard:::.generate_script(dag2, dir, trial = FALSE)
  expect_equal(path1, path2)

  lines <- readLines(path2)
  # Original two steps plus the appended one, renumbered from 3.
  expect_true(any(grepl("--- Step 1: Step 1 description ---", lines, fixed = TRUE)))
  expect_true(any(grepl("--- Step 2: Step 2 description ---", lines, fixed = TRUE)))
  expect_true(any(grepl("--- Step 3: Extension step ---", lines, fixed = TRUE)))
  expect_true(any(grepl("^total_steps <- 3L", lines)))
  # Only one "Workflow complete" footer -- not duplicated.
  expect_length(grep("^# --- Workflow complete ---$", lines), 1L)
})

test_that(".generate_markdown writes methods text", {
  dir <- .tw_test_dir()
  dag <- .make_dag(1)
  dag$methods_text <- "Samples were analyzed using TaxaID."

  path <- TaxaWizard:::.generate_markdown(dag, dir)
  lines <- readLines(path)
  expect_true(any(grepl("Samples were analyzed using TaxaID.", lines, fixed = TRUE)))
})

test_that(".generate_outputs saves a context file alongside generated outputs", {
  dir <- .tw_test_dir()
  dag <- .make_dag(1)

  generated <- TaxaWizard:::.generate_outputs(dag, outputs = "script", output_dir = dir)
  expect_true(file.exists(file.path(dir, "workflow_context.json")))
  expect_false(isTRUE(attr(generated, "appended")))

  generated2 <- TaxaWizard:::.generate_outputs(dag, outputs = "script", output_dir = dir)
  expect_true(isTRUE(attr(generated2, "appended")))
  # No known_script_path was passed, so this append was discovered purely by
  # same-day filename match -- from generated2's point of view, indistinguishable
  # from appending to an unrelated same-day workflow.
  expect_true(isTRUE(attr(generated2, "cross_session_append")))
})

test_that(".generate_outputs's known_script_path makes same-session continuation deterministic", {
  dir <- .tw_test_dir()
  dag <- .make_dag(1)

  generated1 <- TaxaWizard:::.generate_outputs(dag, outputs = "script", output_dir = dir)
  expect_false(isTRUE(attr(generated1, "appended")))
  expect_false(isTRUE(attr(generated1, "cross_session_append")))
  script_path <- attr(generated1, "script_path")
  expect_true(file.exists(script_path))

  # Passing back the script_path from the first call (as create.R's console/
  # viewer loops now do) appends to the SAME file with no ambiguity, and is
  # never flagged as a cross-session append.
  generated2 <- TaxaWizard:::.generate_outputs(dag, outputs = "script", output_dir = dir,
                                                known_script_path = script_path)
  expect_true(isTRUE(attr(generated2, "appended")))
  expect_false(isTRUE(attr(generated2, "cross_session_append")))
  expect_equal(attr(generated2, "script_path"), script_path)
})

test_that(".generate_app falls back to a placeholder when no script is available", {
  dir <- .tw_test_dir()
  dag <- .make_dag(1)

  path <- TaxaWizard:::.generate_app(dag, dir, script_path = NULL)
  expect_true(file.exists(path))
  lines <- readLines(path)
  expect_true(any(grepl("workflow_app\\(", lines)))
})
