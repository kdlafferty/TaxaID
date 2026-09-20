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
      step_id = i,
      edge_id = sprintf("edge_%d", i),
      package = "TaxaTools",
      function_name = sprintf("fn_%d", i),
      description = sprintf("Step %d description", i),
      code = sprintf("step_%d_out <- data.frame(x = 1:3)", i),
      output_var = sprintf("step_%d_out", i)
    )
  })
  list(
    parameters = list(
      list(name = "input_file", value = '"data.csv"', description = "Input file")
    ),
    steps = steps,
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
  dag2$steps[[1]]$output_var <- "ext_out"

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
  generated2 <- TaxaWizard:::.generate_outputs(dag,
    outputs = "script", output_dir = dir,
    known_script_path = script_path
  )
  expect_true(isTRUE(attr(generated2, "appended")))
  expect_false(isTRUE(attr(generated2, "cross_session_append")))
  expect_equal(attr(generated2, "script_path"), script_path)
})

test_that(".generate_script emits a Step 0 setup check with the dag's edge ids", {
  dir <- .tw_test_dir()
  dag <- .make_dag(2)
  dag$steps[[1]]$edge_id <- "seq_to_match"
  dag$steps[[2]]$edge_id <- "match_to_consensus_score"

  path <- TaxaWizard:::.generate_script(dag, dir, trial = FALSE)
  lines <- readLines(path)

  step0_idx <- grep("^# --- Step 0: setup check", lines)
  expect_length(step0_idx, 1L)
  setup_call_idx <- grep("^\\.setup <- TaxaWizard::workflow_check\\(edges = c\\(", lines)
  expect_length(setup_call_idx, 1L)
  expect_true(grepl('"seq_to_match"', lines[setup_call_idx], fixed = TRUE))
  expect_true(grepl('"match_to_consensus_score"', lines[setup_call_idx], fixed = TRUE))
  stop_idx <- grep('stop\\("Setup incomplete', lines)
  expect_length(stop_idx, 1L)

  # Step 0 comes before Step 1 in the file.
  step1_idx <- grep("--- Step 1:", lines, fixed = TRUE)
  expect_true(step0_idx < step1_idx[1L])
})

test_that(".generate_script falls back to edges = NULL when steps carry no edge_id", {
  dir <- .tw_test_dir()
  dag <- .make_dag(1)
  dag$steps[[1]]$edge_id <- NULL # legacy free-form dag shape

  path <- TaxaWizard:::.generate_script(dag, dir, trial = FALSE)
  lines <- readLines(path)

  setup_call_idx <- grep("^\\.setup <- TaxaWizard::workflow_check\\(edges = NULL", lines)
  expect_length(setup_call_idx, 1L)
})

# ---------------------------------------------------------------------------
# P2 Tier-B fallback: a step marked `validated: FALSE` (the DAG schema's new
# optional field -- set by the engine when .get_path_context() substituted a
# generated documentation block for a step with no validated snippet) gets a
# WARNING banner printed directly above it in the generated script.
# ---------------------------------------------------------------------------

test_that(".generate_script prints a WARNING banner above an unvalidated step, and not above a validated one", {
  dir <- .tw_test_dir()
  dag <- .make_dag(2)
  dag$steps[[2]]$validated <- FALSE

  path <- TaxaWizard:::.generate_script(dag, dir, trial = FALSE)
  lines <- readLines(path)

  warn_idx <- grep("^# WARNING: this step was generated without a validated snippet", lines)
  expect_length(warn_idx, 1L)

  step2_idx <- grep("--- Step 2: Step 2 description ---", lines, fixed = TRUE)
  expect_length(step2_idx, 1L)
  expect_equal(warn_idx + 1L, step2_idx)

  # Step 1 (validated defaults TRUE / field omitted) has no banner anywhere
  # near its own header.
  step1_idx <- grep("--- Step 1: Step 1 description ---", lines, fixed = TRUE)
  expect_false(grepl("WARNING", lines[step1_idx - 1L]))
})

test_that(".generate_script omits the WARNING banner when validated is TRUE or absent", {
  dir <- .tw_test_dir()
  dag <- .make_dag(1)
  dag$steps[[1]]$validated <- TRUE

  path <- TaxaWizard:::.generate_script(dag, dir, trial = FALSE)
  lines <- readLines(path)
  expect_length(grep("WARNING: this step was generated", lines), 0L)
})

test_that(".append_to_script prints a WARNING banner above an unvalidated extension step", {
  dir <- .tw_test_dir()
  dag1 <- .make_dag(1)
  path1 <- TaxaWizard:::.generate_script(dag1, dir, trial = FALSE)

  dag2 <- .make_dag(1)
  dag2$steps[[1]]$description <- "Extension step"
  dag2$steps[[1]]$output_var <- "ext_out"
  dag2$steps[[1]]$validated <- FALSE

  path2 <- TaxaWizard:::.generate_script(dag2, dir, trial = FALSE)
  expect_equal(path1, path2) # appended, not a new file

  lines <- readLines(path2)
  warn_idx <- grep("^# WARNING: this step was generated without a validated snippet", lines)
  expect_length(warn_idx, 1L)
  ext_step_idx <- grep("--- Step 2: Extension step ---", lines, fixed = TRUE)
  expect_length(ext_step_idx, 1L)
  expect_equal(warn_idx + 1L, ext_step_idx)
})

test_that(".generate_app falls back to a placeholder when no script is available", {
  dir <- .tw_test_dir()
  dag <- .make_dag(1)

  path <- TaxaWizard:::.generate_app(dag, dir, script_path = NULL)
  expect_true(file.exists(path))
  lines <- readLines(path)
  expect_true(any(grepl("workflow_app\\(", lines)))
})


# --- P6: appending widens Step 0 rather than re-deriving it -------------------

.p6_script <- function(edges_arg) {
  c(
    "# TaxaID Workflow",
    "library(TaxaMatch)",
    "",
    "# --- Step 0: setup check (generated by TaxaWizard) ---",
    sprintf(".setup <- TaxaWizard::workflow_check(edges = %s, verbose = TRUE)", edges_arg),
    'if (any(.setup$status == "missing")) stop("Setup incomplete -- see the fix column above.")',
    "",
    "# --- Step 1: read data ---",
    "",
    "# --- Workflow complete ---"
  )
}

.p6_dag <- function(edge_ids) {
  list(steps = lapply(edge_ids, function(e) list(edge_id = e, package = "TaxaMatch")))
}

test_that(".widen_step0_edges() adds the extension's edges to the existing check", {
  out <- .widen_step0_edges(.p6_script('c("birdnet_to_match")'), .p6_dag("match_to_taxa"))
  line <- grep("^\\.setup <- TaxaWizard::workflow_check\\(", out, value = TRUE)

  expect_length(line, 1L)                       # never a SECOND Step 0
  expect_match(line, "birdnet_to_match", fixed = TRUE)  # original kept
  expect_match(line, "match_to_taxa", fixed = TRUE)     # extension added
})

test_that(".widen_step0_edges() does not duplicate an edge already listed", {
  out <- .widen_step0_edges(.p6_script('c("birdnet_to_match")'), .p6_dag("birdnet_to_match"))
  line <- grep("^\\.setup <- TaxaWizard::workflow_check\\(", out, value = TRUE)
  expect_equal(lengths(regmatches(line, gregexpr("birdnet_to_match", line, fixed = TRUE))), 1L)
})

test_that(".widen_step0_edges() leaves edges = NULL alone", {
  # NULL already checks the whole ecosystem; narrowing it would LOSE coverage.
  before <- .p6_script("NULL")
  expect_identical(.widen_step0_edges(before, .p6_dag("match_to_taxa")), before)
})

test_that(".widen_step0_edges() does not inject Step 0 into a script that has none", {
  legacy <- c("# hand-written script", "library(TaxaMatch)", "# --- Workflow complete ---")
  expect_identical(.widen_step0_edges(legacy, .p6_dag("match_to_taxa")), legacy)
})

test_that(".widen_step0_edges() leaves a script alone when the dag carries no edge ids", {
  before <- .p6_script('c("birdnet_to_match")')
  expect_identical(.widen_step0_edges(before, list(steps = list(list(package = "TaxaMatch")))), before)
})


# --- P7(a) finding: an LLM-invented edge id must not reach Step 0 -------------

test_that(".keep_known_edges() drops ids that are not in the graph", {
  # P7(a)'s console dry run produced edge_id "load_match_df" for its
  # data-loading step. No such edge exists; workflow_check() ignored it with a
  # message, so the script still ran -- but a fabricated identifier had reached
  # a line the user reads.
  expect_warning(
    kept <- .keep_known_edges(c("match_to_consensus_score", "load_match_df")),
    "not in the workflow graph"
  )
  expect_equal(kept, "match_to_consensus_score")
})

test_that(".keep_known_edges() is silent when every id is real", {
  expect_silent(kept <- .keep_known_edges("match_to_consensus_score"))
  expect_equal(kept, "match_to_consensus_score")
})

test_that("a dag whose edge ids are ALL invented falls back to edges = NULL", {
  # Dropping every id must not produce edges = c() -- an empty vector would
  # make workflow_check() check nothing, which looks like a pass. NULL checks
  # the whole ecosystem, which is the safe direction.
  dag <- list(
    parameters = list(),
    steps = list(list(
      step_id = 1, edge_id = "not_a_real_edge", package = "TaxaTools",
      function_name = "detect_ranks", description = "invented step",
      code = "x <- 1", inputs = list(), output_var = "x"
    ))
  )
  out_dir <- tempfile("p7a_fallback_"); dir.create(out_dir)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  suppressWarnings(.generate_outputs(dag = dag, outputs = "script", output_dir = out_dir, trial = FALSE))
  script <- list.files(out_dir, pattern = "\\.R$", full.names = TRUE)[1]
  line <- grep("^\\.setup <- TaxaWizard::workflow_check\\(", readLines(script, warn = FALSE), value = TRUE)

  expect_length(line, 1L)
  expect_match(line, "edges = NULL", fixed = TRUE)
  expect_false(grepl("not_a_real_edge", line, fixed = TRUE))
})

test_that(".widen_step0_edges() does not append an invented edge id", {
  before <- .p6_script('c("birdnet_to_match")')
  suppressWarnings(
    out <- .widen_step0_edges(before, .p6_dag(c("match_to_taxa", "totally_made_up")))
  )
  line <- grep("^\\.setup <- TaxaWizard::workflow_check\\(", out, value = TRUE)
  expect_match(line, "match_to_taxa", fixed = TRUE)
  expect_false(grepl("totally_made_up", line, fixed = TRUE))
})


# --- Checkpoints must key on inputs, not just on the step number -------------
# A checkpoint keyed on step number alone answers "has step N run?", never
# "has step N run with THESE inputs?" -- so editing a parameter and re-running
# replayed the old result under the new parameters, silently. It also
# short-circuited content-addressed caches further down (TaxaFetch keys its
# GBIF checkpoints on the query itself).

.ck_dag <- function() list(
  parameters = list(list(name = "multiplier", value = "2"),
                    list(name = "unrelated", value = "99")),
  steps = list(
    list(step_id = 1, edge_id = "match_to_consensus_score", package = "TaxaTools",
         function_name = "f", description = "make a number",
         code = "value <- 10 * multiplier\nvalue", inputs = list(), output_var = "value"),
    list(step_id = 2, edge_id = "match_to_consensus_score", package = "TaxaTools",
         function_name = "g", description = "use it",
         code = "doubled <- value * 2\ndoubled", inputs = list(), output_var = "doubled")
  )
)

# These four are INTEGRATION tests: they execute the generated script in a
# fresh R process, which therefore has to be able to load TaxaWizard itself.
# That holds under devtools::test() against the user library, but not
# necessarily under R CMD check, where the package lives in a temporary check
# library the subprocess does not inherit. Check the precondition rather than
# assuming it -- a test that cannot run should say so, not fail.
.ck_rscript <- function() file.path(R.home("bin"), "Rscript")

# The precondition is NOT "can the subprocess load TaxaWizard" -- that was a
# proxy, and it passed under R CMD check while the test still failed. The
# generated script opens with Step 0, workflow_check(), which correctly refuses
# to run when the ecosystem packages are missing; under check the subprocess
# sees only a temporary library, reports 7 missing, and halts exactly as it is
# designed to. So the real precondition is that a fresh process can load the
# whole ecosystem, and that is what this asks.
.ck_subprocess_can_load <- function() {
  expr <- sprintf(
    "cat(all(vapply(c(%s), requireNamespace, logical(1), quietly = TRUE)))",
    paste(sprintf('"%s"', c("TaxaWizard", TaxaWizard:::TAXAID_PACKAGES)), collapse = ", ")
  )
  out <- suppressWarnings(system2(
    .ck_rscript(), c("-e", shQuote(expr)), stdout = TRUE, stderr = TRUE
  ))
  any(grepl("TRUE", out, fixed = TRUE))
}

.ck_generate <- function() {
  d <- tempfile("ck_"); dir.create(d)
  suppressWarnings(.generate_outputs(dag = .ck_dag(), outputs = "script",
                                     output_dir = d, trial = FALSE))
  list(dir = d, script = list.files(d, pattern = "\\.R$", full.names = TRUE)[1])
}

test_that("a generated script declares the parameters its signatures digest", {
  g <- .ck_generate(); on.exit(unlink(g$dir, recursive = TRUE), add = TRUE)
  line <- grep("^\\.workflow_params <- ", readLines(g$script, warn = FALSE), value = TRUE)

  expect_length(line, 1L)
  expect_match(line, "multiplier", fixed = TRUE)
  expect_match(line, "unrelated", fixed = TRUE)
})

test_that("a DAG with no parameters still defines .workflow_params", {
  # Otherwise the first .run_step() call errors on an undefined object.
  d <- tempfile("ck0_"); dir.create(d); on.exit(unlink(d, recursive = TRUE), add = TRUE)
  dag <- .ck_dag(); dag$parameters <- list()
  suppressWarnings(.generate_outputs(dag = dag, outputs = "script", output_dir = d, trial = FALSE))
  script <- list.files(d, pattern = "\\.R$", full.names = TRUE)[1]

  expect_match(
    grep("^\\.workflow_params <- ", readLines(script, warn = FALSE), value = TRUE),
    "character(0)", fixed = TRUE
  )
})

test_that("editing a parameter a step reads invalidates it AND every later step", {
  skip_on_cran()
  skip_if_not(.ck_subprocess_can_load(),
              "a fresh R process cannot load TaxaWizard (e.g. under R CMD check)")
  g <- .ck_generate(); on.exit(unlink(g$dir, recursive = TRUE), add = TRUE)
  run <- function() paste(system2(.ck_rscript(), shQuote(g$script), stdout = TRUE, stderr = TRUE),
                          collapse = "\n")

  run()                                   # cold
  reuse <- run()                          # nothing changed
  expect_match(reuse, "Step 1: make a number [cached, skipping]", fixed = TRUE)
  expect_match(reuse, "Step 2: use it [cached, skipping]", fixed = TRUE)

  txt <- readLines(g$script, warn = FALSE)
  txt[txt == "multiplier <- 2"] <- "multiplier <- 5"
  writeLines(txt, g$script)
  changed <- run()

  expect_match(changed, "inputs changed since the cached run", fixed = TRUE)
  expect_match(changed, "cleared 1 later checkpoint", fixed = TRUE)
  # and the RESULT is recomputed, not the stale one: 10 * 5 * 2
  expect_equal(readRDS(file.path(g$dir, ".workflow_checkpoints", "step_02.rds")), 100)
})

test_that("editing a parameter NO step reads does not invalidate anything", {
  # The other half of the proof: a signature that fires on every edit would be
  # switched off within a week.
  skip_on_cran()
  skip_if_not(.ck_subprocess_can_load(),
              "a fresh R process cannot load TaxaWizard (e.g. under R CMD check)")
  g <- .ck_generate(); on.exit(unlink(g$dir, recursive = TRUE), add = TRUE)
  run <- function() paste(system2(.ck_rscript(), shQuote(g$script), stdout = TRUE, stderr = TRUE),
                          collapse = "\n")
  run()

  txt <- readLines(g$script, warn = FALSE)
  txt[txt == "unrelated <- 99"] <- "unrelated <- 123"
  writeLines(txt, g$script)
  out <- run()

  expect_match(out, "Step 1: make a number [cached, skipping]", fixed = TRUE)
  expect_match(out, "Step 2: use it [cached, skipping]", fixed = TRUE)
  expect_false(grepl("inputs changed", out, fixed = TRUE))
})

test_that(".widen_workflow_params() adds an extension's parameters to the list", {
  lines <- c("# x", '.workflow_params <- c("a", "b")', "# y")
  dag <- list(parameters = list(list(name = "b", value = "1"), list(name = "c", value = "2")))
  out <- .widen_workflow_params(lines, dag)
  line <- grep("^\\.workflow_params <- ", out, value = TRUE)

  expect_match(line, '"c"', fixed = TRUE)
  expect_equal(lengths(regmatches(line, gregexpr('"b"', line, fixed = TRUE))), 1L)
})

test_that(".widen_workflow_params() leaves a script without that line alone", {
  legacy <- c("# hand-written", "library(TaxaMatch)")
  dag <- list(parameters = list(list(name = "c", value = "2")))
  expect_identical(.widen_workflow_params(legacy, dag), legacy)
})
