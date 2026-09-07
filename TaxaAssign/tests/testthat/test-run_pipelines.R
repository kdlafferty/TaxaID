# Tests for run_bayesian_pipeline() and run_llm_pipeline() input validation.
# All tests are offline — they hit validation errors before any computation.

# --- Shared test data --------------------------------------------------------

mock_match_df <- data.frame(
  observation_id = c("s1", "s1", "s2"),
  score_original = c(99, 85, 92),
  taxon_name = c("Sp A", "Sp B", "Sp A"),
  taxon_name_rank = c("species", "species", "species"),
  family = c("Fam1", "Fam1", "Fam1"),
  genus = c("Gen1", "Gen1", "Gen1"),
  species = c("Sp A", "Sp B", "Sp A"),
  stringsAsFactors = FALSE
)

# =============================================================================
# A. run_bayesian_pipeline() — input validation
# =============================================================================

test_that("run_bayesian_pipeline: rejects invalid constraint_behavior", {
  skip_if_not_installed("TaxaLikely")
  expect_error(
    run_bayesian_pipeline(
      match_df = mock_match_df,
      model_params = list(),
      taxaexpect_priors = data.frame(),
      site = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine"),
      constraint_behavior = "invalid_value",
      backbone_id = 11L
    ),
    "should be one of"
  )
})

test_that("run_bayesian_pipeline: rejects match_df with too few rank columns", {
  skip_if_not_installed("TaxaLikely")
  # Only one rank column (species) — needs at least 2
  narrow_df <- data.frame(
    observation_id = "s1",
    score_original = 99,
    taxon_name = "Sp A",
    taxon_name_rank = "species",
    species = "Sp A",
    stringsAsFactors = FALSE
  )
  expect_error(
    run_bayesian_pipeline(
      match_df          = narrow_df,
      model_params      = list(),
      taxaexpect_priors = data.frame(),
      site              = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine"),
      backbone_id       = 11L
    ),
    "fewer than 2 rank_system"
  )
})

test_that("run_bayesian_pipeline: accepts build_priors list and extracts $priors", {
  skip_if_not_installed("TaxaLikely")
  # Wrapping a data frame in a list with $priors should be accepted
  priors_df <- data.frame(
    grid_id = "Grid_34p1_m119p1",
    main_habitat = "Marine",
    taxon_name = "Sp A",
    theta = 0.5,
    stringsAsFactors = FALSE
  )
  # Should get past the $priors extraction and fail later on model_params
  expect_error(
    run_bayesian_pipeline(
      match_df          = mock_match_df,
      model_params      = list(),
      taxaexpect_priors = list(priors = priors_df),
      site              = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine"),
      backbone_id       = 11L
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
      site              = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Marine"),
      backbone_id       = 11L
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
      auto_context = FALSE,
      backbone_id  = 11L
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
      detect_unreferenced = FALSE,
      backbone_id         = 11L
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
      score_threshold      = 150,
      backbone_id          = 11L
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
      detect_unreferenced = FALSE,
      backbone_id         = 11L
    ),
    "llm_fn|function"
  )
})

test_that("run_llm_pipeline: NULL llm_fn without TaxaTools gives clear error", {
  skip_if(
    requireNamespace("TaxaTools", quietly = TRUE),
    "TaxaTools is installed -- cannot test missing-package path"
  )
  expect_error(
    run_llm_pipeline(match_df = mock_match_df, llm_fn = NULL, backbone_id = 11L),
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

# =============================================================================
# D. run_llm_pipeline() — auto-context regression
# =============================================================================

test_that("run_llm_pipeline: auto_context filters on score_original, not the removed `score` column", {
  # Regression: this call read match_df$score, a column renamed to
  # score_original ecosystem-wide in Session 99. `NULL >= score_threshold` is
  # logical(0), so build_context() always received character(0) and aborted --
  # i.e. the default auto_context path could never run on a real match_df.
  captured <- NULL
  local_mocked_bindings(
    build_context = function(taxon_names, ...) {
      captured <<- taxon_names
      stop("stop_after_build_context")
    },
    .env = asNamespace("TaxaAssign")
  )

  expect_error(
    run_llm_pipeline(
      match_df        = mock_match_df,
      llm_fn          = function(prompt) "[]",
      score_threshold = 90,
      backbone_id     = 11L,
      verbose         = FALSE
    ),
    "stop_after_build_context"
  )

  # Rows at/above score_original 90: s1/"Sp A" (99) and s2/"Sp A" (92).
  expect_equal(captured, "Sp A")
})
