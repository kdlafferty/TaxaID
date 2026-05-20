# --- Mock LLM function ---
# Returns canned JSON for known taxa; simulates real LLM behavior

mock_llm_fn <- function(prompt_str, ...) {
  # Return a realistic JSON response for Palmyra Atoll reef taxa
  '[
    {"taxon_name": "Carcharhinus melanopterus", "review_habitat": "expected", "review_geography": "expected", "review_scope": "in_scope", "review_contaminant": "unlikely", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Blacktip reef shark, common on Pacific coral reefs"},
    {"taxon_name": "Homo sapiens", "review_habitat": "unlikely", "review_geography": "expected", "review_scope": "out_of_scope", "review_contaminant": "likely", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Common lab contaminant in eDNA studies"},
    {"taxon_name": "Gobiidae", "review_habitat": "expected", "review_geography": "expected", "review_scope": "in_scope", "review_contaminant": "unlikely", "review_alternatives": null, "review_lower_hypotheses": "Eviota sp., Trimma sp.", "review_confidence": "moderate", "review_comment": "Diverse family on coral reefs; many cryptic species"},
    {"taxon_name": "Salmo salar", "review_habitat": "unlikely", "review_geography": "unlikely", "review_scope": "in_scope", "review_contaminant": "possible", "review_alternatives": "Lutjanus bohar, Lutjanus kasmira", "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Atlantic salmon; not found in central Pacific. Possible food-source contaminant"},
    {"taxon_name": "Bos taurus", "review_habitat": "unlikely", "review_geography": "unlikely", "review_scope": "out_of_scope", "review_contaminant": "likely", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": "Domestic cattle; common food-source contaminant"}
  ]'
}


# --- Mock consensus data ---
mock_consensus <- data.frame(
  observation_id       = c("S1", "S1", "S2", "S2", "S3"),
  consensus_taxon = c("Carcharhinus melanopterus", "Homo sapiens",
                      "Gobiidae", "Salmo salar", "Bos taurus"),
  consensus_rank  = c("species", "species", "family", "species", "species"),
  stringsAsFactors = FALSE
)

mock_context <- list(
  geography = "Palmyra Atoll, central Pacific",
  habitat   = "coral reef"
)


# ===========================================================================
# Basic functionality
# ===========================================================================

test_that("review_assignments adds 8 columns", {
  result <- review_assignments(
    df           = mock_consensus,
    taxon_col    = "consensus_taxon",
    context      = mock_context,
    target_group = "fish",
    llm_fn       = mock_llm_fn,
    verbose      = FALSE
  )

  expect_true("review_habitat" %in% names(result))
  expect_true("review_geography" %in% names(result))
  expect_true("review_scope" %in% names(result))
  expect_true("review_contaminant" %in% names(result))
  expect_true("review_alternatives" %in% names(result))
  expect_true("review_lower_hypotheses" %in% names(result))
  expect_true("review_confidence" %in% names(result))
  expect_true("review_comment" %in% names(result))
  expect_equal(nrow(result), nrow(mock_consensus))
})

test_that("review values are correct for known taxa", {
  result <- review_assignments(
    df           = mock_consensus,
    taxon_col    = "consensus_taxon",
    context      = mock_context,
    target_group = "fish",
    llm_fn       = mock_llm_fn,
    verbose      = FALSE
  )

  # Homo sapiens should be flagged as contaminant
  hs <- result[result$consensus_taxon == "Homo sapiens", ]
  expect_equal(hs$review_contaminant, "likely")
  expect_equal(hs$review_scope, "out_of_scope")

  # Carcharhinus melanopterus should be expected
  cm <- result[result$consensus_taxon == "Carcharhinus melanopterus", ]
  expect_equal(cm$review_habitat, "expected")
  expect_equal(cm$review_geography, "expected")
  expect_equal(cm$review_contaminant, "unlikely")
})

test_that("alternatives populated for implausible taxa", {
  result <- review_assignments(
    df           = mock_consensus,
    taxon_col    = "consensus_taxon",
    context      = mock_context,
    target_group = "fish",
    llm_fn       = mock_llm_fn,
    verbose      = FALSE
  )

  ss <- result[result$consensus_taxon == "Salmo salar", ]
  expect_true(!is.na(ss$review_alternatives))
  expect_true(grepl("Lutjanus", ss$review_alternatives))
})


# ===========================================================================
# taxon_rank_col and lower hypotheses
# ===========================================================================

test_that("review_lower_hypotheses populated when taxon_rank_col supplied", {
  result <- review_assignments(
    df             = mock_consensus,
    taxon_col      = "consensus_taxon",
    taxon_rank_col = "consensus_rank",
    context        = mock_context,
    target_group   = "fish",
    llm_fn         = mock_llm_fn,
    verbose        = FALSE
  )

  gov <- result[result$consensus_taxon == "Gobiidae", ]
  expect_true(!is.na(gov$review_lower_hypotheses))
})

test_that("review_lower_hypotheses is NA when taxon_rank_col not supplied", {
  result <- review_assignments(
    df           = mock_consensus,
    taxon_col    = "consensus_taxon",
    context      = mock_context,
    target_group = "fish",
    llm_fn       = mock_llm_fn,
    verbose      = FALSE
  )

  # All lower_hypotheses should be NA when no rank column
  expect_true(all(is.na(result$review_lower_hypotheses)))
})


# ===========================================================================
# target_group controls review_scope
# ===========================================================================

test_that("review_scope is NA when target_group not supplied", {
  result <- review_assignments(
    df       = mock_consensus,
    taxon_col = "consensus_taxon",
    context  = mock_context,
    llm_fn   = mock_llm_fn,
    verbose  = FALSE
  )

  expect_true(all(is.na(result$review_scope)))
})


# ===========================================================================
# Context normalisation
# ===========================================================================

test_that("build_context() style data frame works as context", {
  ctx_df <- data.frame(
    ecoregion    = "Central Pacific",
    main_habitat = "coral reef",
    date         = "2025",
    stringsAsFactors = FALSE
  )

  result <- review_assignments(
    df        = mock_consensus,
    taxon_col = "consensus_taxon",
    context   = ctx_df,
    llm_fn    = mock_llm_fn,
    verbose   = FALSE
  )

  expect_equal(nrow(result), nrow(mock_consensus))
})


# ===========================================================================
# Error handling
# ===========================================================================

test_that("graceful handling of LLM failure", {
  fail_fn <- function(prompt_str, ...) stop("API error")

  expect_warning(
    result <- review_assignments(
      df        = mock_consensus,
      taxon_col = "consensus_taxon",
      context   = mock_context,
      llm_fn    = fail_fn,
      verbose   = FALSE
    ),
    "LLM call failed"
  )

  # Should still return all rows with NA review columns
  expect_equal(nrow(result), nrow(mock_consensus))
  expect_true(all(is.na(result$review_habitat)))
})

test_that("graceful handling of invalid JSON response", {
  bad_fn <- function(prompt_str, ...) "This is not JSON at all"

  expect_warning(
    result <- review_assignments(
      df        = mock_consensus,
      taxon_col = "consensus_taxon",
      context   = mock_context,
      llm_fn    = bad_fn,
      verbose   = FALSE
    ),
    "Could not parse"
  )

  expect_equal(nrow(result), nrow(mock_consensus))
  expect_true(all(is.na(result$review_habitat)))
})

test_that("graceful handling of partial LLM response", {
  # Returns only 2 of 5 taxa
  partial_fn <- function(prompt_str, ...) {
    '[
      {"taxon_name": "Carcharhinus melanopterus", "review_habitat": "expected", "review_geography": "expected", "review_scope": null, "review_contaminant": "unlikely", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null},
      {"taxon_name": "Homo sapiens", "review_habitat": "unlikely", "review_geography": "expected", "review_scope": null, "review_contaminant": "likely", "review_alternatives": null, "review_lower_hypotheses": null, "review_confidence": "high", "review_comment": null}
    ]'
  }

  expect_warning(
    result <- review_assignments(
      df        = mock_consensus,
      taxon_col = "consensus_taxon",
      context   = mock_context,
      llm_fn    = partial_fn,
      verbose   = FALSE
    ),
    "omitted"
  )

  # All rows should be present
  expect_equal(nrow(result), nrow(mock_consensus))
  # The two returned taxa should have values
  cm <- result[result$consensus_taxon == "Carcharhinus melanopterus", ]
  expect_equal(cm$review_habitat, "expected")
  # The missing taxa should have NA
  bt <- result[result$consensus_taxon == "Bos taurus", ]
  expect_true(is.na(bt$review_habitat))
})


# ===========================================================================
# Input validation
# ===========================================================================

test_that("error when taxon column missing", {
  expect_error(
    review_assignments(mock_consensus, taxon_col = "nonexistent",
                       context = mock_context, llm_fn = mock_llm_fn,
                       verbose = FALSE),
    "not found"
  )
})

test_that("error when context missing", {
  expect_error(
    review_assignments(mock_consensus, taxon_col = "consensus_taxon",
                       llm_fn = mock_llm_fn, verbose = FALSE),
    "context.*required"
  )
})

test_that("error when taxon_rank_col not in df", {
  expect_error(
    review_assignments(mock_consensus, taxon_col = "consensus_taxon",
                       taxon_rank_col = "nonexistent",
                       context = mock_context, llm_fn = mock_llm_fn,
                       verbose = FALSE),
    "not found"
  )
})


# ===========================================================================
# Row order preservation
# ===========================================================================

test_that("output row order matches input", {
  result <- review_assignments(
    df        = mock_consensus,
    taxon_col = "consensus_taxon",
    context   = mock_context,
    llm_fn    = mock_llm_fn,
    verbose   = FALSE
  )

  expect_equal(result$consensus_taxon, mock_consensus$consensus_taxon)
  expect_equal(result$observation_id, mock_consensus$observation_id)
})
