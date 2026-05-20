# Tests for run_bayesian_pipeline() and run_llm_pipeline() input validation.
# All tests are offline — they hit validation errors before any computation.

# --- Shared test data --------------------------------------------------------

mock_match_df <- data.frame(
  observation_id       = c("s1", "s1", "s2"),
  score           = c(99, 85, 92),
  taxon_name      = c("Sp A", "Sp B", "Sp A"),
  taxon_name_rank = c("species", "species", "species"),
  family          = c("Fam1", "Fam1", "Fam1"),
  genus           = c("Gen1", "Gen1", "Gen1"),
  species         = c("Sp A", "Sp B", "Sp A"),
  stringsAsFactors = FALSE
)

# =============================================================================
# A. run_bayesian_pipeline() — input validation
# =============================================================================

test_that("run_bayesian_pipeline: rejects invalid constraint_behavior", {
  skip_if_not_installed("TaxaLikely")
  expect_error(
    run_bayesian_pipeline(
      match_df          = mock_match_df,
      model_params      = list(),
      taxaexpect_priors = data.frame(),
      site              = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine"),
      constraint_behavior = "invalid_value"
    ),
    "should be one of"
  )
})

test_that("run_bayesian_pipeline: rejects match_df with too few rank columns", {
  skip_if_not_installed("TaxaLikely")
  # Only one rank column (species) — needs at least 2
  narrow_df <- data.frame(
    observation_id       = "s1",
    score           = 99,
    taxon_name      = "Sp A",
    taxon_name_rank = "species",
    species         = "Sp A",
    stringsAsFactors = FALSE
  )
  expect_error(
    run_bayesian_pipeline(
      match_df          = narrow_df,
      model_params      = list(),
      taxaexpect_priors = data.frame(),
      site              = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine")
    ),
    "fewer than 2 rank_system"
  )
})

test_that("run_bayesian_pipeline: accepts build_priors list and extracts $priors", {
  skip_if_not_installed("TaxaLikely")
  # Wrapping a data frame in a list with $priors should be accepted
  priors_df <- data.frame(
    grid_id      = "Grid_34p1_m119p1",
    main_habitat = "Marine",
    taxon_name   = "Sp A",
    theta        = 0.5,
    stringsAsFactors = FALSE
  )
  # Should get past the $priors extraction and fail later on model_params
  expect_error(
    run_bayesian_pipeline(
      match_df          = mock_match_df,
      model_params      = list(),
      taxaexpect_priors = list(priors = priors_df),
      site              = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine")
    )
  )
})

test_that("run_bayesian_pipeline: rejects non-data-frame taxaexpect_priors", {
  skip_if_not_installed("TaxaLikely")
  # A string gets past the list-extraction check but fails when the pipeline

  # tries to access $grid_id on a non-data-frame object
  expect_error(
    run_bayesian_pipeline(
      match_df          = mock_match_df,
      model_params      = list(),
      taxaexpect_priors = "not_a_df",
      site              = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine")
    )
  )
})

# =============================================================================
# B. run_llm_pipeline() — input validation
# =============================================================================

test_that("run_llm_pipeline: rejects non-data-frame match_df", {
  # auto_context = FALSE to avoid triggering LLM calls
  expect_error(
    run_llm_pipeline(
      match_df     = "not a df",
      llm_fn       = function(x) "mock",
      auto_context = FALSE
    ),
    "match_df|data frame"
  )
})

test_that("run_llm_pipeline: rejects match_df missing required columns", {
  bad_df <- data.frame(observation_id = "s1", wrong_col = 99)
  expect_error(
    run_llm_pipeline(
      match_df            = bad_df,
      llm_fn              = function(x) "mock",
      auto_context        = FALSE,
      detect_unreferenced = FALSE
    ),
    "missing|column"
  )
})

test_that("run_llm_pipeline: rejects invalid score_threshold", {
  expect_error(
    run_llm_pipeline(
      match_df             = mock_match_df,
      llm_fn               = function(x) "mock",
      auto_context         = FALSE,
      detect_unreferenced  = FALSE,
      score_threshold      = 150
    ),
    "score_threshold"
  )
})

test_that("run_llm_pipeline: rejects non-function non-NULL llm_fn", {
  expect_error(
    run_llm_pipeline(
      match_df            = mock_match_df,
      llm_fn              = "not_a_function",
      auto_context        = FALSE,
      detect_unreferenced = FALSE
    ),
    "llm_fn|function"
  )
})

test_that("run_llm_pipeline: NULL llm_fn without TaxaTools gives clear error", {
  skip_if(requireNamespace("TaxaTools", quietly = TRUE),
          "TaxaTools is installed -- cannot test missing-package path")
  expect_error(
    run_llm_pipeline(match_df = mock_match_df, llm_fn = NULL),
    "TaxaTools"
  )
})

# =============================================================================
# C. .resolve_llm_fn() — internal helper
# =============================================================================

test_that(".resolve_llm_fn: returns user-supplied function unchanged", {
  my_fn <- function(x) paste("echo:", x)
  result <- TaxaAssign:::.resolve_llm_fn(my_fn, "test")
  expect_identical(result, my_fn)
})

test_that(".resolve_llm_fn: NULL resolves to TaxaTools provider when available", {
  skip_if_not_installed("TaxaTools")
  result <- TaxaAssign:::.resolve_llm_fn(NULL, "test")
  expect_true(is.function(result))
})
