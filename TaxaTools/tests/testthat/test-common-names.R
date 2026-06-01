# Tests for common_to_scientific()
# LLM-dependent tests are skipped unless a provider is configured.
# All input-validation tests run without LLM access.

# ---- input validation (no LLM needed) ---------------------------------------

test_that("non-character common_names raises error", {
  expect_error(
    common_to_scientific(123),
    "non-empty character vector"
  )
})

test_that("empty common_names raises error", {
  expect_error(
    common_to_scientific(character(0)),
    "non-empty character vector"
  )
})

test_that("non-scalar taxon_group raises error", {
  expect_error(
    common_to_scientific("Robin", taxon_group = c("birds", "mammals"),
                           llm_fn = identity),
    "single character string"
  )
})

test_that("non-scalar location raises error", {
  expect_error(
    common_to_scientific("Robin", location = c("USA", "UK"),
                           llm_fn = identity),
    "single character string"
  )
})

test_that("NULL llm_fn raises informative error", {
  expect_error(
    common_to_scientific("Robin", llm_fn = NULL),
    "No LLM function configured"
  )
})

test_that("non-function llm_fn raises error", {
  expect_error(
    common_to_scientific("Robin", llm_fn = "not_a_function"),
    "must be a function"
  )
})

test_that("non-logical verify raises error", {
  expect_error(
    common_to_scientific("Robin", verify = "yes", llm_fn = identity),
    "TRUE or FALSE"
  )
})


# ---- output structure (mock LLM) --------------------------------------------

.mock_llm <- function(prompt, ...) {
  '[{"common_name":"Robin","scientific_name":"Turdus migratorius","notes":""},
    {"common_name":"Song Sparrow","scientific_name":"Melospiza melodia","notes":""}]'
}

test_that("output is a data frame with expected columns", {
  result <- common_to_scientific(
    c("Robin", "Song Sparrow"),
    verify = FALSE,
    llm_fn = .mock_llm
  )
  expect_s3_class(result, "data.frame")
  expected_cols <- c("common_name", "scientific_name_llm",
                     "scientific_name_verified", "backbone_id",
                     "verified", "notes")
  expect_true(all(expected_cols %in% names(result)))
})

test_that("output has one row per input name", {
  result <- common_to_scientific(
    c("Robin", "Song Sparrow"),
    verify = FALSE,
    llm_fn = .mock_llm
  )
  expect_equal(nrow(result), 2L)
})

test_that("scientific_name_llm populated from mock LLM response", {
  result <- common_to_scientific(
    c("Robin", "Song Sparrow"),
    verify = FALSE,
    llm_fn = .mock_llm
  )
  expect_equal(result$scientific_name_llm,
               c("Turdus migratorius", "Melospiza melodia"))
})

test_that("verify = FALSE leaves scientific_name_verified as NA", {
  result <- common_to_scientific(
    c("Robin", "Song Sparrow"),
    verify = FALSE,
    llm_fn = .mock_llm
  )
  expect_true(all(is.na(result$scientific_name_verified)))
  expect_true(all(result$verified == FALSE))
})

test_that("malformed LLM response triggers warning and returns NA names", {
  bad_llm <- function(prompt, ...) "this is not json"
  result <- suppressWarnings(
    common_to_scientific("Robin", verify = FALSE, llm_fn = bad_llm)
  )
  expect_true(is.na(result$scientific_name_llm[[1]]))
})

test_that("LLM response wrapped in markdown fences is parsed correctly", {
  fenced_llm <- function(prompt, ...) {
    '```json\n[{"common_name":"Robin","scientific_name":"Turdus migratorius","notes":""}]\n```'
  }
  result <- suppressWarnings(
    common_to_scientific("Robin", verify = FALSE, llm_fn = fenced_llm)
  )
  expect_equal(result$scientific_name_llm, "Turdus migratorius")
})

test_that("null scientific_name in LLM response becomes NA", {
  null_llm <- function(prompt, ...) {
    '[{"common_name":"Hawk","scientific_name":null,"notes":"Too coarse"}]'
  }
  result <- common_to_scientific("Hawk", verify = FALSE, llm_fn = null_llm)
  expect_true(is.na(result$scientific_name_llm))
  expect_equal(result$notes, "Too coarse")
})

test_that("backbone_id is integer in output", {
  result <- common_to_scientific(
    "Robin", verify = FALSE, llm_fn = .mock_llm, backbone_id = 11L
  )
  expect_type(result$backbone_id, "integer")
  expect_equal(result$backbone_id, 11L)
})
