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


# ==============================================================================
# Tests for scientific_to_common()
# ==============================================================================

# ---- input validation --------------------------------------------------------

test_that("non-character scientific_names raises error", {
  expect_error(
    scientific_to_common(123, use_llm = FALSE),
    "non-empty character vector"
  )
})

test_that("empty scientific_names raises error", {
  expect_error(
    scientific_to_common(character(0), use_llm = FALSE),
    "non-empty character vector"
  )
})

test_that("unsupported backbone_id warns and falls through to LLM", {
  mock_llm <- function(prompt, ...) {
    '[{"scientific_name":"Homo sapiens","common_name":"human","common_name_alternatives":null}]'
  }
  expect_warning(
    scientific_to_common("Homo sapiens", backbone_id = 9L, llm_fn = mock_llm),
    "not supported"
  )
})

test_that("NULL llm_fn with use_llm = TRUE raises error", {
  expect_error(
    scientific_to_common("Homo sapiens", backbone_id = NULL,
                         use_llm = TRUE, llm_fn = NULL),
    "No LLM function configured"
  )
})

test_that("non-logical use_llm raises error", {
  expect_error(
    scientific_to_common("Homo sapiens", use_llm = "yes", llm_fn = NULL),
    "TRUE or FALSE"
  )
})

test_that("non-function llm_fn raises error", {
  expect_error(
    scientific_to_common("Homo sapiens", backbone_id = NULL,
                         llm_fn = "not_a_function"),
    "must be a function"
  )
})


# ---- output structure (mocked backbone + LLM) --------------------------------

.mock_gbif <- function(name) {
  list(primary = "rainbow trout", alternatives = "steelhead; redband trout")
}

.mock_llm_s2c <- function(prompt, ...) {
  '[{"scientific_name":"Salmo salar","common_name":"Atlantic salmon","common_name_alternatives":"salmon"}]'
}

test_that("output is a data frame with expected columns", {
  local_mocked_bindings(.gbif_common_names = .mock_gbif, .package = "TaxaTools")
  result <- scientific_to_common("Oncorhynchus mykiss", backbone_id = 11L,
                                 use_llm = FALSE, llm_fn = NULL)
  expect_s3_class(result, "data.frame")
  expect_true(all(c("scientific_name", "common_name",
                    "common_name_alternatives", "source",
                    "backbone_id") %in% names(result)))
})

test_that("output has one row per input name", {
  local_mocked_bindings(.gbif_common_names = .mock_gbif, .package = "TaxaTools")
  result <- scientific_to_common(c("Oncorhynchus mykiss", "Oncorhynchus nerka"),
                                 backbone_id = 11L, use_llm = FALSE, llm_fn = NULL)
  expect_equal(nrow(result), 2L)
})

test_that("backbone hit sets source to 'gbif' and backbone_id to 11", {
  local_mocked_bindings(.gbif_common_names = .mock_gbif, .package = "TaxaTools")
  result <- scientific_to_common("Oncorhynchus mykiss", backbone_id = 11L,
                                 use_llm = FALSE, llm_fn = NULL)
  expect_equal(result$source,      "gbif")
  expect_equal(result$backbone_id, 11L)
  expect_equal(result$common_name, "rainbow trout")
  expect_equal(result$common_name_alternatives, "steelhead; redband trout")
})

test_that("backbone hit sets source to 'itis' and backbone_id to 3", {
  local_mocked_bindings(.itis_common_names = .mock_gbif, .package = "TaxaTools")
  result <- scientific_to_common("Oncorhynchus mykiss", backbone_id = 3L,
                                 use_llm = FALSE, llm_fn = NULL)
  expect_equal(result$source,      "itis")
  expect_equal(result$backbone_id, 3L)
})

test_that("backbone miss with use_llm = TRUE falls back to LLM", {
  local_mocked_bindings(.gbif_common_names = function(name) NULL,
                        .package = "TaxaTools")
  result <- scientific_to_common("Salmo salar", backbone_id = 11L,
                                 use_llm = TRUE, llm_fn = .mock_llm_s2c)
  expect_equal(result$source,      "llm")
  expect_equal(result$common_name, "Atlantic salmon")
})

test_that("backbone miss with use_llm = FALSE returns source 'none' and NA common_name", {
  local_mocked_bindings(.gbif_common_names = function(name) NULL,
                        .package = "TaxaTools")
  result <- scientific_to_common("Rare taxon sp.", backbone_id = 11L,
                                 use_llm = FALSE, llm_fn = NULL)
  expect_equal(result$source,      "none")
  expect_true(is.na(result$common_name))
})

test_that("backbone_id = NULL goes straight to LLM for all names", {
  result <- scientific_to_common("Salmo salar", backbone_id = NULL,
                                 llm_fn = .mock_llm_s2c)
  expect_equal(result$source,      "llm")
  expect_equal(result$common_name, "Atlantic salmon")
  expect_true(is.na(result$backbone_id))
})

test_that("location param is accepted and passed to LLM without error", {
  captured <- NULL
  capture_llm <- function(prompt, ...) {
    captured <<- prompt
    '[{"scientific_name":"Salmo salar","common_name":"Atlantic salmon","common_name_alternatives":null}]'
  }
  result <- scientific_to_common("Salmo salar", backbone_id = NULL,
                                 location = "Pacific Northwest, USA",
                                 llm_fn = capture_llm)
  expect_equal(result$common_name, "Atlantic salmon")
  expect_true(grepl("Pacific Northwest", captured))
})

test_that("non-scalar location raises error", {
  expect_error(
    scientific_to_common("Salmo salar", location = c("USA", "UK"),
                         backbone_id = NULL, llm_fn = .mock_llm_s2c),
    "single character string"
  )
})

test_that("LLM null common_name returns NA and source 'none'", {
  null_llm <- function(prompt, ...) {
    '[{"scientific_name":"Obscura sp.","common_name":null,"common_name_alternatives":null}]'
  }
  result <- scientific_to_common("Obscura sp.", backbone_id = NULL,
                                 llm_fn = null_llm)
  expect_true(is.na(result$common_name))
  expect_equal(result$source, "none")
})

test_that("malformed LLM response warns and returns NA common_name", {
  bad_llm <- function(prompt, ...) "not json"
  result <- suppressWarnings(
    scientific_to_common("Salmo salar", backbone_id = NULL, llm_fn = bad_llm)
  )
  expect_true(is.na(result$common_name))
})

test_that("LLM response wrapped in markdown fences is parsed correctly", {
  fenced_llm <- function(prompt, ...) {
    '```json\n[{"scientific_name":"Salmo salar","common_name":"Atlantic salmon","common_name_alternatives":null}]\n```'
  }
  result <- scientific_to_common("Salmo salar", backbone_id = NULL,
                                 llm_fn = fenced_llm)
  expect_equal(result$common_name, "Atlantic salmon")
})

test_that("backbone_id is integer NA for llm-sourced rows", {
  result <- scientific_to_common("Salmo salar", backbone_id = NULL,
                                 llm_fn = .mock_llm_s2c)
  expect_type(result$backbone_id, "integer")
  expect_true(is.na(result$backbone_id))
})

test_that("mixed batch: backbone hit for first, LLM fallback for second", {
  local_mocked_bindings(
    .gbif_common_names = function(name) {
      if (name == "Oncorhynchus mykiss") .mock_gbif(name) else NULL
    },
    .package = "TaxaTools"
  )
  result <- scientific_to_common(c("Oncorhynchus mykiss", "Salmo salar"),
                                 backbone_id = 11L, use_llm = TRUE,
                                 llm_fn = .mock_llm_s2c)
  expect_equal(result$source,      c("gbif", "llm"))
  expect_equal(result$common_name, c("rainbow trout", "Atlantic salmon"))
})
