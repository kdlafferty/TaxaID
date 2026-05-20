# Tests for workflow engine — offline only (no API calls)

test_that(".parse_engine_response: parses clean JSON", {
  raw <- '{"status": "incomplete", "message": "What marker?", "dag": null}'
  result <- TaxaWizard:::.parse_engine_response(raw)
  expect_equal(result$status, "incomplete")
  expect_equal(result$message, "What marker?")
})

test_that(".parse_engine_response: strips markdown fences", {
  raw <- '```json\n{"status": "complete", "message": "Ready."}\n```'
  result <- TaxaWizard:::.parse_engine_response(raw)
  expect_equal(result$status, "complete")
})

test_that(".parse_engine_response: wraps plain text as incomplete response", {
  result <- suppressWarnings(
    TaxaWizard:::.parse_engine_response("not json at all")
  )
  expect_equal(result$status, "incomplete")
  expect_equal(result$message, "not json at all")
})

test_that(".estimate_scaling: linear scaling", {
  est <- TaxaWizard:::.estimate_scaling(10, 20, 2000, "linear")
  expect_equal(est$estimated_seconds, 1000)
})

test_that(".estimate_scaling: quadratic scaling", {
  est <- TaxaWizard:::.estimate_scaling(10, 20, 200, "quadratic")
  expect_equal(est$estimated_seconds, 1000)
})

test_that(".subset_for_trial: subsets by observation_id", {
  df <- data.frame(
    observation_id = rep(paste0("s", 1:50), each = 3),
    score     = runif(150)
  )
  sub <- TaxaWizard:::.subset_for_trial(df, n = 5)
  expect_equal(length(unique(sub$observation_id)), 5)
  expect_true(nrow(sub) <= 15)
})

test_that(".subset_for_trial: falls back to head when column missing", {
  df <- data.frame(x = 1:100)
  sub <- TaxaWizard:::.subset_for_trial(df, n = 10, by = "observation_id")
  expect_equal(nrow(sub), 10)
})


# --- Phase Detection Tests ---

test_that(".detect_phase: empty history -> classify", {
  result <- TaxaWizard:::.detect_phase(list())
  expect_equal(result$phase, "classify")
})

test_that(".detect_phase: no assistant messages -> classify", {
  history <- list(
    list(role = "user", content = "I have eDNA data")
  )
  result <- TaxaWizard:::.detect_phase(history)
  expect_equal(result$phase, "classify")
})

test_that(".detect_phase: classify complete -> path_select", {
  history <- list(
    list(role = "user", content = "I have match data and want consensus"),
    list(role = "assistant", content = jsonlite::toJSON(list(
      status = "incomplete", phase = "classify",
      message = "Got it.",
      input_type = "match_df", output_type = "consensus",
      selected_path = NULL, dag = NULL
    ), auto_unbox = TRUE))
  )
  result <- TaxaWizard:::.detect_phase(history)
  expect_equal(result$phase, "path_select")
  expect_equal(result$context$input_type, "match_df")
  expect_equal(result$context$output_type, "consensus")
  # Paths should be computed
  expect_true(length(result$context$paths) >= 2)
})

test_that(".detect_phase: path selected -> parameterize", {
  history <- list(
    list(role = "user", content = "Score-based please"),
    list(role = "assistant", content = jsonlite::toJSON(list(
      status = "incomplete", phase = "path_select",
      message = "OK, score-based it is.",
      input_type = "match_df", output_type = "consensus",
      selected_path = list("match_to_consensus_score"), dag = NULL
    ), auto_unbox = TRUE))
  )
  result <- TaxaWizard:::.detect_phase(history)
  expect_equal(result$phase, "parameterize")
  expect_equal(result$context$selected_path, "match_to_consensus_score")
})

test_that(".detect_phase: error text -> error_fix", {
  history <- list(
    list(role = "assistant", content = jsonlite::toJSON(list(
      status = "complete", phase = "parameterize",
      message = "Here's your workflow.",
      input_type = "match_df", output_type = "consensus",
      selected_path = list("match_to_consensus_score"),
      dag = list(steps = list())
    ), auto_unbox = TRUE)),
    list(role = "user", content = "Error in score_consensus: unused argument (threshold = 80)")
  )
  result <- TaxaWizard:::.detect_phase(history)
  expect_equal(result$phase, "error_fix")
})

test_that(".parse_error_context: extracts step number", {
  session <- list(history = list(
    list(role = "assistant", content = jsonlite::toJSON(list(
      status = "complete", message = "Done.",
      selected_path = list("seq_to_match", "match_to_consensus_score"),
      dag = list(steps = list(
        list(step_id = 1, edge_id = "seq_to_match",
             description = "BLAST sequences", code = "match <- blast()"),
        list(step_id = 2, edge_id = "match_to_consensus_score",
             description = "Score consensus", code = "cons <- score_consensus()")
      ))
    ), auto_unbox = TRUE))
  ))
  ctx <- TaxaWizard:::.parse_error_context(
    "Step 2 (Score consensus) failed: unused argument",
    session
  )
  expect_equal(ctx$step_number, 2L)
  expect_equal(ctx$edge_id, "match_to_consensus_score")
  expect_equal(ctx$step_code, "cons <- score_consensus()")
})

test_that(".parse_error_context: handles missing step number", {
  session <- list(history = list())
  ctx <- TaxaWizard:::.parse_error_context("Error: something broke", session)
  expect_equal(ctx$step_number, "?")
  expect_equal(ctx$edge_id, "unknown")
})

test_that(".looks_like_error: detects common error patterns", {
  expect_true(TaxaWizard:::.looks_like_error("Error in build_context: bad arg"))
  expect_true(TaxaWizard:::.looks_like_error("Step 3 (Compute...) failed: missing column"))
  expect_true(TaxaWizard:::.looks_like_error("unused argument (x = 1)"))
  expect_false(TaxaWizard:::.looks_like_error("I want to identify fish species"))
  expect_false(TaxaWizard:::.looks_like_error("yes, that looks good"))
})
