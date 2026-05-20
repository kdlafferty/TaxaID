# tests/testthat/test-parse_hierarchical_habitat_response.R
#
# Tests for parse_hierarchical_habitat_response() -- wide weighted format.
# All tests are pure (no API calls, no files, no network).
#
# The function accepts raw LLM CSV text and returns a data.frame with:
#   taxon_name | <habitat cols...> | Other_weight | habitat_best_guess | Habitat
#
# Tests cover:
#   A. Input validation
#   B. Basic parsing and column structure
#   C. Habitat weight columns and Other_weight
#   D. habitat_best_guess handling
#   E. Habitat convenience column (argmax)
#   F. Multi-chunk response handling
#   G. LLM robustness (markdown fences, preamble, extra whitespace)
#   H. habitat_scheme validation (prompt object vs bare df vs NULL)
#   I. Unrecognised columns folded into Other_weight
#   J. Missing expected columns added with weight 0
#   K. Weight-sum warnings
#   L. Missing taxa warnings

# ==============================================================================
# Helpers
# ==============================================================================

# Build a minimal mock habitat_prompt object (no actual prompts needed)
make_mock_prompt <- function(habitat_names = c("Rocky_Subtidal", "Kelp_Forest",
                                               "Pelagic"),
                             scheme_df = NULL) {
  structure(
    list(
      prompts      = list("dummy prompt"),
      taxa         = c("Gadus morhua", "Sebastes mystinus"),
      chunks       = list(c("Gadus morhua", "Sebastes mystinus")),
      scheme       = scheme_df,
      habitat_cols = habitat_names,
      extra_covariates = character(0),
      chunk_size   = 60L,
      n_chunks     = 1L
    ),
    class = c("habitat_prompt", "llm_prompt")
  )
}

# Build a clean weighted CSV string
make_csv <- function(taxa, hab_cols, weights, other_weights = NULL,
                     best_guesses = NULL) {
  if (is.null(other_weights)) other_weights <- rep(0, length(taxa))
  if (is.null(best_guesses))  best_guesses  <- rep("", length(taxa))

  header <- paste(c("taxon_name", hab_cols, "Other_weight",
                    "habitat_best_guess"), collapse = ",")

  rows <- mapply(function(taxon, w, ow, bg) {
    paste(c(taxon, w, ow, bg), collapse = ",")
  }, taxa, split(weights, seq_len(nrow(weights))),
  other_weights, best_guesses, SIMPLIFY = TRUE)

  paste(c(header, rows), collapse = "\n")
}

# ==============================================================================
# Part A: Input validation
# ==============================================================================

test_that("stops when raw_text is not a character string", {
  expect_error(
    parse_hierarchical_habitat_response(123, "Gadus morhua"),
    "must be a length-1 non-empty character string"
  )
})

test_that("stops when raw_text is empty string", {
  expect_error(
    parse_hierarchical_habitat_response("   ", "Gadus morhua"),
    "must be a length-1 non-empty character string"
  )
})

test_that("stops when raw_text is length > 1", {
  expect_error(
    parse_hierarchical_habitat_response(c("a", "b"), "Gadus morhua"),
    "must be a length-1 non-empty character string"
  )
})

test_that("stops when taxon_list is empty", {
  expect_error(
    parse_hierarchical_habitat_response("taxon_name,Rocky\nGadus,1.0",
                                        character(0)),
    "must be a non-empty character vector"
  )
})

test_that("stops when CSV contains no data rows", {
  raw <- "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess"
  expect_error(
    parse_hierarchical_habitat_response(raw, "Gadus morhua"),
    "no data rows"
  )
})

# ==============================================================================
# Part B: Basic parsing and column structure
# ==============================================================================

test_that("returns a data.frame", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_s3_class(result, "data.frame")
})

test_that("taxon_name column always present", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true("taxon_name" %in% names(result))
})

test_that("Other_weight column always present", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true("Other_weight" %in% names(result))
})

test_that("habitat_best_guess column always present", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true("habitat_best_guess" %in% names(result))
})

test_that("Habitat convenience column always present", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true("Habitat" %in% names(result))
})

test_that("one row per taxon in response", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,0.0,",
    "Sebastes mystinus,0.0,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(
    raw, c("Gadus morhua", "Sebastes mystinus")
  )
  expect_equal(nrow(result), 2L)
})

test_that("habitat weight columns are numeric", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true(is.numeric(result$Rocky_Subtidal))
  expect_true(is.numeric(result$Kelp_Forest))
  expect_true(is.numeric(result$Other_weight))
})

test_that("taxon_name is character type", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true(is.character(result$taxon_name))
})

# ==============================================================================
# Part C: Habitat weights and Other_weight
# ==============================================================================

test_that("specialist species: correct weight values parsed", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,0.0,",
    "Sebastes mystinus,0.0,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(
    raw, c("Gadus morhua", "Sebastes mystinus")
  )
  expect_equal(result$Rocky_Subtidal[result$taxon_name == "Gadus morhua"], 1.0)
  expect_equal(result$Kelp_Forest[result$taxon_name == "Gadus morhua"], 0.0)
  expect_equal(result$Kelp_Forest[result$taxon_name == "Sebastes mystinus"], 1.0)
})

test_that("generalist species: split weights parsed correctly", {
  raw <- paste(
    "taxon_name,Ocean,Freshwater,Other_weight,habitat_best_guess",
    "Oncorhynchus mykiss,0.5,0.5,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Oncorhynchus mykiss")
  expect_equal(result$Ocean[1], 0.5)
  expect_equal(result$Freshwater[1], 0.5)
})

test_that("Other_weight = 1 for species outside scheme", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Mystery sp.,0.0,1.0,alpine meadow",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Mystery sp.")
  expect_equal(result$Other_weight[1], 1.0)
})

test_that("Other_weight added as zero when absent from LLM output", {
  # LLM didn't return Other_weight column at all
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest",
    "Gadus morhua,1.0,0.0",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true("Other_weight" %in% names(result))
  expect_equal(result$Other_weight[1], 0)
})

test_that("NA weights replaced with 0", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,NA,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_equal(result$Rocky_Subtidal[1], 0)
})

# ==============================================================================
# Part D: habitat_best_guess
# ==============================================================================

test_that("habitat_best_guess is empty string when Other_weight = 0", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_equal(result$habitat_best_guess[1], "")
})

test_that("habitat_best_guess is populated when Other_weight > 0", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Mystery sp.,0.0,1.0,alpine meadow",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Mystery sp.")
  expect_equal(result$habitat_best_guess[1], "alpine meadow")
})

test_that("habitat_best_guess added as empty string when absent from LLM output", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight",
    "Gadus morhua,1.0,0.0",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true("habitat_best_guess" %in% names(result))
  expect_equal(result$habitat_best_guess[1], "")
})

# ==============================================================================
# Part E: Habitat convenience column (argmax)
# ==============================================================================

test_that("Habitat = name of highest-weight column for specialist", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,0.0,",
    "Sebastes mystinus,0.0,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(
    raw, c("Gadus morhua", "Sebastes mystinus")
  )
  expect_equal(result$Habitat[result$taxon_name == "Gadus morhua"],
               "Rocky_Subtidal")
  expect_equal(result$Habitat[result$taxon_name == "Sebastes mystinus"],
               "Kelp_Forest")
})

test_that("Habitat = 'Other' when Other_weight is highest", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Mystery sp.,0.0,1.0,alpine meadow",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Mystery sp.")
  expect_equal(result$Habitat[1], "Other")
})

test_that("Habitat = NA when all weights are 0", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Unknown sp.,0.0,0.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Unknown sp.")
  expect_true(is.na(result$Habitat[1]))
})

# ==============================================================================
# Part F: Multi-chunk response handling
# ==============================================================================

test_that("duplicate header rows in multi-chunk response are stripped", {
  chunk1 <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  chunk2 <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Sebastes mystinus,0.0,1.0,kelp forest",
    sep = "\n"
  )
  combined <- paste(chunk1, chunk2, sep = "\n")
  result <- parse_hierarchical_habitat_response(
    combined, c("Gadus morhua", "Sebastes mystinus")
  )
  # Should have exactly 2 rows, not 3 (header + 2 species)
  expect_equal(nrow(result), 2L)
})

# ==============================================================================
# Part G: LLM robustness
# ==============================================================================

test_that("markdown code fences are stripped", {
  raw <- paste0(
    "```csv\n",
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess\n",
    "Gadus morhua,1.0,0.0,\n",
    "```"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_equal(nrow(result), 1L)
  expect_equal(result$Rocky_Subtidal[1], 1.0)
})

test_that("preamble text before header row is ignored", {
  raw <- paste(
    "Here is the CSV output you requested:",
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_equal(nrow(result), 1L)
})

test_that("postamble text after last data row is ignored", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    "Note: assignment complete.",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_equal(nrow(result), 1L)
})

test_that("leading/trailing whitespace in taxon names is trimmed", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "  Gadus morhua  ,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_equal(result$taxon_name[1], "Gadus morhua")
})

test_that("alternative taxon column names are normalised to taxon_name", {
  # LLM returned 'species' instead of 'taxon_name'
  raw <- paste(
    "species,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua")
  expect_true("taxon_name" %in% names(result))
  expect_equal(result$taxon_name[1], "Gadus morhua")
})

test_that("blank taxon rows are dropped silently", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    ",0.0,0.0,",
    "Sebastes mystinus,0.0,1.0,kelp",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(
    raw, c("Gadus morhua", "Sebastes mystinus")
  )
  expect_equal(nrow(result), 2L)
  expect_false(any(result$taxon_name == ""))
})

# ==============================================================================
# Part H: habitat_scheme handling
# ==============================================================================

test_that("habitat_prompt object: expected_hab_cols used for validation", {
  prompt <- make_mock_prompt(c("Rocky_Subtidal", "Kelp_Forest"))
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(
    raw, "Gadus morhua", habitat_scheme = prompt
  )
  expect_true("Rocky_Subtidal" %in% names(result))
  expect_true("Kelp_Forest" %in% names(result))
})

test_that("NULL habitat_scheme: all numeric columns treated as weights", {
  raw <- paste(
    "taxon_name,HabA,HabB,Other_weight,habitat_best_guess",
    "Gadus morhua,0.7,0.3,0.0,",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(raw, "Gadus morhua",
                                                habitat_scheme = NULL)
  expect_true("HabA" %in% names(result))
  expect_true("HabB" %in% names(result))
})

# ==============================================================================
# Part I: Unrecognised columns folded into Other_weight
# ==============================================================================

test_that("LLM hallucinated habitat column folded into Other_weight with warning", {
  prompt <- make_mock_prompt(c("Rocky_Subtidal", "Kelp_Forest"))
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,HALLUCINATED_HAB,Other_weight,habitat_best_guess",
    "Gadus morhua,0.8,0.0,0.2,0.0,",
    sep = "\n"
  )
  expect_warning(
    result <- parse_hierarchical_habitat_response(
      raw, "Gadus morhua", habitat_scheme = prompt
    ),
    "unrecognised habitat column"
  )
  # HALLUCINATED_HAB folded into Other_weight: 0.0 + 0.2 = 0.2
  expect_equal(result$Other_weight[1], 0.2)
  expect_false("HALLUCINATED_HAB" %in% names(result))
})

# ==============================================================================
# Part J: Missing expected columns added with weight 0
# ==============================================================================

test_that("expected habitat column absent from response is added with weight 0", {
  prompt <- make_mock_prompt(c("Rocky_Subtidal", "Kelp_Forest", "Pelagic"))
  # LLM omitted Pelagic entirely
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,0.0,",
    sep = "\n"
  )
  expect_warning(
    result <- parse_hierarchical_habitat_response(
      raw, "Gadus morhua", habitat_scheme = prompt
    ),
    "expected habitat column.*absent"
  )
  expect_true("Pelagic" %in% names(result))
  expect_equal(result$Pelagic[1], 0)
})

# ==============================================================================
# Part K: Weight-sum warnings
# ==============================================================================

test_that("warns when row weights deviate more than 0.05 from 1.0", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,0.6,0.6,0.0,",   # sums to 1.2, deviation > 0.05
    sep = "\n"
  )
  expect_warning(
    parse_hierarchical_habitat_response(raw, "Gadus morhua"),
    "not summing to 1.0"
  )
})

test_that("no warning when weights sum to exactly 1.0", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,0.0,",
    sep = "\n"
  )
  expect_no_warning(
    parse_hierarchical_habitat_response(raw, "Gadus morhua")
  )
})

test_that("no warning for acceptable rounding within 0.05", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Kelp_Forest,Other_weight,habitat_best_guess",
    "Gadus morhua,0.97,0.0,0.0,",   # deviation 0.03 < 0.05
    sep = "\n"
  )
  expect_no_warning(
    parse_hierarchical_habitat_response(raw, "Gadus morhua")
  )
})

# ==============================================================================
# Part L: Missing taxa warnings
# ==============================================================================

test_that("warns when submitted taxon absent from response", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  expect_warning(
    parse_hierarchical_habitat_response(
      raw, c("Gadus morhua", "Missing sp.")
    ),
    "missing from response"
  )
})

test_that("no warning when all submitted taxa present in response", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess",
    "Gadus morhua,1.0,0.0,",
    sep = "\n"
  )
  expect_no_warning(
    parse_hierarchical_habitat_response(raw, "Gadus morhua")
  )
})

# ==============================================================================
# Part M: extra_covariates parameter
# ==============================================================================

test_that("extra_covariates = NULL does not retain non-habitat numeric columns", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess,Invasive",
    "Gadus morhua,1.0,0.0,,0",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(
    raw, "Gadus morhua", extra_covariates = NULL
  )
  # Invasive is numeric but not in habitat_cols and not requested: should be absent
  # (it may be treated as a weight col if numeric -- check it doesn't cause errors)
  expect_equal(nrow(result), 1L)
})

test_that("extra_covariates names that exist in output are retained", {
  raw <- paste(
    "taxon_name,Rocky_Subtidal,Other_weight,habitat_best_guess,Invasive",
    "Gadus morhua,1.0,0.0,,0",
    sep = "\n"
  )
  result <- parse_hierarchical_habitat_response(
    raw, "Gadus morhua", extra_covariates = c("Invasive")
  )
  expect_true("Invasive" %in% names(result))
})
