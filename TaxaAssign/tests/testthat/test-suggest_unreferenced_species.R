# test-suggest_unreferenced_species.R
#
# Tests for suggest_unreferenced_species() and its internal helpers.
# Network calls (NCBI, LLM) are mocked throughout so no internet
# connection is required.

library(TaxaAssign)

# ============================================================================
# Shared fixtures
# ============================================================================

make_spg_match_df <- function() {
  data.frame(
    observation_id       = c("S1", "S1", "S2", "S2"),
    score           = c(99, 88, 97, 85),
    taxon_name      = c("Fundulus lima", "Fundulus zebrinus",
                        "Gambusia affinis", "Gambusia holbrooki"),
    taxon_name_rank = rep("species", 4L),
    genus           = c("Fundulus", "Fundulus", "Gambusia", "Gambusia"),
    stringsAsFactors = FALSE
  )
}

# Returns valid JSON for the genera in the prompt
stub_plausible_llm <- function(prompt) {
  # Extract genera from "- GenusName" lines
  genera <- regmatches(prompt, gregexpr("(?m)(?<=^- )\\S+", prompt, perl = TRUE))[[1]]
  rows <- vapply(genera, function(g) {
    sprintf('{"genus":"%s","plausible_species":["%s parvipinnis","%s lima"]}', g, g, g)
  }, character(1L))
  paste0("[\n  ", paste(rows, collapse = ",\n  "), "\n]")
}

broken_plausible_llm <- function(prompt) "not valid json at all!!!"

error_plausible_llm  <- function(prompt) stop("API unavailable")


# ============================================================================
# TaxaTools::is_valid_species_name() — spot-check here (full tests in TaxaTools)
# ============================================================================

test_that("is_valid_species_name() accepts clean binomials", {
  skip_if_not_installed("TaxaTools")
  good <- c("Fundulus parvipinnis", "Gambusia affinis", "Salmo salar")
  expect_true(all(TaxaTools::is_valid_species_name(good)))
})

test_that("is_valid_species_name() rejects non-binomials and placeholders", {
  skip_if_not_installed("TaxaTools")
  bad <- c("Fundulus", "sp.", "Fundulus sp.", "Fundulus cf. lima",
           "uncultured Gambusia sp.", "environmental sample")
  expect_false(any(TaxaTools::is_valid_species_name(bad)))
})


# ============================================================================
# .parse_plausible_response()
# ============================================================================

test_that(".parse_plausible_response() parses valid JSON correctly", {
  json <- '[
    {"genus":"Fundulus","plausible_species":["Fundulus parvipinnis","Fundulus lima"]},
    {"genus":"Gambusia","plausible_species":["Gambusia affinis"]}
  ]'
  result <- TaxaAssign:::.parse_plausible_response(json, c("Fundulus", "Gambusia"))
  expect_equal(result[["Fundulus"]], c("Fundulus parvipinnis", "Fundulus lima"))
  expect_equal(result[["Gambusia"]], "Gambusia affinis")
})

test_that(".parse_plausible_response() handles markdown-fenced JSON ((?s) PCRE fix)", {
  # Markdown fence + newlines before/after array -- tests the (?s) dotall fix
  json <- "Here are the plausible species:\n\n```json\n[\n  {\"genus\":\"Fundulus\",\"plausible_species\":[\"Fundulus parvipinnis\"]}\n]\n```\n"
  result <- TaxaAssign:::.parse_plausible_response(json, "Fundulus")
  expect_equal(result[["Fundulus"]], "Fundulus parvipinnis")
})

test_that(".parse_plausible_response() returns empty list with warning on malformed JSON", {
  expect_warning(
    result <- TaxaAssign:::.parse_plausible_response("not json", "Fundulus"),
    regexp = "Failed to parse|empty species"
  )
  expect_equal(result[["Fundulus"]], character(0L))
})

test_that(".parse_plausible_response() returns empty list with warning for NULL response", {
  expect_warning(
    result <- TaxaAssign:::.parse_plausible_response(NULL, "Fundulus"),
    regexp = "Empty LLM response|empty species"
  )
  expect_equal(result[["Fundulus"]], character(0L))
})

test_that(".parse_plausible_response() filters invalid species names from valid JSON", {
  json <- '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis","Fundulus sp.","Fundulus cf. lima"]}]'
  result <- TaxaAssign:::.parse_plausible_response(json, "Fundulus")
  # sp. and cf. should be filtered; only parvipinnis survives
  expect_equal(result[["Fundulus"]], "Fundulus parvipinnis")
})

test_that(".parse_plausible_response() ignores extra genera not in request", {
  json <- '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis"]},{"genus":"Salmo","plausible_species":["Salmo salar"]}]'
  result <- TaxaAssign:::.parse_plausible_response(json, "Fundulus")
  expect_null(result[["Salmo"]])
  expect_equal(names(result), "Fundulus")
})

test_that(".parse_plausible_response() warns when a genus has no species returned", {
  json <- '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis"]}]'
  expect_warning(
    result <- TaxaAssign:::.parse_plausible_response(
      json, c("Fundulus", "Gambusia"), group_label = "test batch"
    ),
    regexp = "no valid plausible species"
  )
  expect_equal(result[["Gambusia"]], character(0L))
})


# ============================================================================
# suggest_unreferenced_species() -- skip-list and basic logic (mocked NCBI)
# ============================================================================

test_that("suggest_unreferenced_species() excludes skip-list species from NCBI queries", {
  match_df <- make_spg_match_df()

  # Track which species are actually queried in NCBI
  queried_species <- character(0L)

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) {
      queried_species <<- c(queried_species, sp)
      0L   # all queried species are unreferenced
    },
    .env = asNamespace("TaxaAssign")
  )

  # LLM suggests: Fundulus parvipinnis (new) AND Fundulus lima (already in match_df)
  mock_llm <- function(prompt) {
    '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis","Fundulus lima"]},{"genus":"Gambusia","plausible_species":["Gambusia mexicana"]}]'
  }

  result <- suggest_unreferenced_species(
    match_df,
    llm_fn        = mock_llm,
    barcode_term  = "12S",
    pause_seconds = 0
  )

  # Fundulus lima is in match_df -> must NOT be queried
  expect_false("Fundulus lima" %in% queried_species)
  # Gambusia affinis and Gambusia holbrooki are in match_df -> must NOT be queried
  expect_false("Gambusia affinis" %in% queried_species)
  expect_false("Gambusia holbrooki" %in% queried_species)
  # Fundulus parvipinnis and Gambusia mexicana are new -> must be queried
  expect_true("Fundulus parvipinnis" %in% queried_species)
  expect_true("Gambusia mexicana" %in% queried_species)
})

test_that("suggest_unreferenced_species() returns character vector of unreferenced species", {
  match_df <- make_spg_match_df()

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) 0L,  # all are unreferenced
    .env = asNamespace("TaxaAssign")
  )

  mock_llm <- function(prompt) {
    '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis"]},{"genus":"Gambusia","plausible_species":["Gambusia mexicana"]}]'
  }

  result <- suggest_unreferenced_species(
    match_df, llm_fn = mock_llm, barcode_term = "12S", pause_seconds = 0
  )

  expect_s3_class(result, "character")
  expect_true(inherits(result, "unreferenced_species_result"))
  expect_true("Fundulus parvipinnis" %in% result)
  expect_true("Gambusia mexicana" %in% result)
  expect_equal(length(result), 2L)
})

test_that("suggest_unreferenced_species() excludes species with NCBI barcode seqs", {
  match_df <- make_spg_match_df()

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) {
      if (sp == "Fundulus parvipinnis") 0L   # unreferenced
      else 5L                                # has sequences -> referenced
    },
    .env = asNamespace("TaxaAssign")
  )

  mock_llm <- function(prompt) {
    '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis","Fundulus notatus"]},{"genus":"Gambusia","plausible_species":["Gambusia mexicana"]}]'
  }

  result <- suggest_unreferenced_species(
    match_df, llm_fn = mock_llm, barcode_term = "12S", pause_seconds = 0
  )

  expect_true("Fundulus parvipinnis" %in% result)
  expect_false("Fundulus notatus" %in% result)
})

test_that("suggest_unreferenced_species() treats NA NCBI count as unreferenced (conservative)", {
  match_df <- make_spg_match_df()

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) NA_integer_,
    .env = asNamespace("TaxaAssign")
  )

  mock_llm <- function(prompt) {
    '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis"]},{"genus":"Gambusia","plausible_species":["Gambusia mexicana"]}]'
  }

  expect_warning(
    result <- suggest_unreferenced_species(
      match_df, llm_fn = mock_llm, barcode_term = "12S", pause_seconds = 0
    ),
    regexp = "failed after 3 attempts"
  )
  expect_true("Fundulus parvipinnis" %in% result)
})

test_that("suggest_unreferenced_species() attaches census attribute", {
  match_df <- make_spg_match_df()

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) 0L,
    .env = asNamespace("TaxaAssign")
  )

  mock_llm <- function(prompt) {
    '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis"]},{"genus":"Gambusia","plausible_species":["Gambusia mexicana"]}]'
  }

  result  <- suggest_unreferenced_species(
    match_df, llm_fn = mock_llm, barcode_term = "12S", pause_seconds = 0
  )
  census  <- attr(result, "census")

  expect_s3_class(census, "data.frame")
  expect_true(all(c("genus", "plausible_count", "ncbi_count", "unreferenced_count") %in%
                    names(census)))
  expect_equal(nrow(census), 2L)

  fund_row <- census[census$genus == "Fundulus", ]
  expect_equal(fund_row$plausible_count, 1L)
  expect_equal(fund_row$unreferenced_count, 1L)
})

test_that("suggest_unreferenced_species() attaches plausible attribute", {
  match_df <- make_spg_match_df()

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) 0L,
    .env = asNamespace("TaxaAssign")
  )

  mock_llm <- function(prompt) {
    '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis","Fundulus lima"]},{"genus":"Gambusia","plausible_species":["Gambusia mexicana"]}]'
  }

  result    <- suggest_unreferenced_species(
    match_df, llm_fn = mock_llm, barcode_term = "12S", pause_seconds = 0
  )
  plausible <- attr(result, "plausible")

  # plausible includes Fundulus lima even though it is in the skip-list
  expect_true("Fundulus lima" %in% plausible)
  expect_true("Fundulus parvipinnis" %in% plausible)
})

test_that("suggest_unreferenced_species() returns empty result when LLM suggests nothing new", {
  match_df <- make_spg_match_df()

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) stop("should not be called"),
    .env = asNamespace("TaxaAssign")
  )

  # LLM only suggests species already in match_df
  mock_llm <- function(prompt) {
    '[{"genus":"Fundulus","plausible_species":["Fundulus lima","Fundulus zebrinus"]},{"genus":"Gambusia","plausible_species":["Gambusia affinis","Gambusia holbrooki"]}]'
  }

  result <- suggest_unreferenced_species(
    match_df, llm_fn = mock_llm, barcode_term = "12S", pause_seconds = 0
  )
  expect_equal(length(result), 0L)
})

test_that("suggest_unreferenced_species() batches genera per taxa_per_call", {
  match_df <- make_spg_match_df()
  call_count <- 0L

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) 0L,
    .env = asNamespace("TaxaAssign")
  )

  counting_llm <- function(prompt) {
    call_count <<- call_count + 1L
    stub_plausible_llm(prompt)
  }

  # 2 genera, taxa_per_call = 1 -> 2 LLM calls
  suggest_unreferenced_species(
    match_df, llm_fn = counting_llm, barcode_term = "12S",
    taxa_per_call = 1L, pause_seconds = 0
  )
  expect_equal(call_count, 2L)
})

test_that("suggest_unreferenced_species() handles erroring llm_fn with warning", {
  match_df <- make_spg_match_df()

  # LLM errors -> falls back to empty species lists -> no unreferenced species
  expect_warning(
    result <- suggest_unreferenced_species(
      match_df, llm_fn = error_plausible_llm,
      barcode_term = "12S", pause_seconds = 0
    ),
    regexp = "LLM call failed"
  )
  expect_equal(length(result), 0L)
})

test_that("suggest_unreferenced_species() derives genus from taxon_name when genus col absent", {
  match_df <- data.frame(
    observation_id       = "S1",
    score           = 99,
    taxon_name      = "Fundulus lima",
    taxon_name_rank = "species",
    stringsAsFactors = FALSE
  )

  local_mocked_bindings(
    .count_barcode_seqs = function(sp, ...) 0L,
    .env = asNamespace("TaxaAssign")
  )

  mock_llm <- function(prompt) {
    '[{"genus":"Fundulus","plausible_species":["Fundulus parvipinnis"]}]'
  }

  result <- suggest_unreferenced_species(
    match_df, llm_fn = mock_llm, barcode_term = "12S", pause_seconds = 0
  )
  expect_equal(as.character(result), "Fundulus parvipinnis")
})

# ---- Input validation -------------------------------------------------------

test_that("suggest_unreferenced_species() errors on non-data-frame match_df", {
  expect_error(
    suggest_unreferenced_species(list(taxon_name = "x"), llm_fn = stub_plausible_llm),
    regexp = "data frame"
  )
})

test_that("suggest_unreferenced_species() errors when taxon_name column is absent", {
  expect_error(
    suggest_unreferenced_species(data.frame(x = 1), llm_fn = stub_plausible_llm),
    regexp = "taxon_name"
  )
})

test_that("suggest_unreferenced_species() errors on invalid max_date format", {
  expect_error(
    suggest_unreferenced_species(make_spg_match_df(), llm_fn = stub_plausible_llm,
                              max_date = "24/12/31"),
    regexp = "YYYY"
  )
})

# ---- print.unreferenced_species_result -------------------------------------------------------

test_that("print.unreferenced_species_result outputs invisibly and shows count", {
  obj <- TaxaAssign:::.new_unreferenced_species_result(
    c("Fundulus parvipinnis", "Gambusia mexicana"),
    c("Fundulus parvipinnis", "Gambusia mexicana"),
    data.frame(genus = c("Fundulus", "Gambusia"), plausible_count = 1L,
               ncbi_count = 0L, unreferenced_count = 1L, stringsAsFactors = FALSE)
  )
  out <- capture.output(print(obj))
  expect_true(any(grepl("2", out)))
  expect_true(any(grepl("Fundulus parvipinnis", out)))
})

test_that("print.unreferenced_species_result truncates at 10 species", {
  many_unref <- paste0("Genus species", seq_len(12L))
  obj <- TaxaAssign:::.new_unreferenced_species_result(
    many_unref,
    many_unref,
    data.frame(genus = "Genus", plausible_count = 12L,
               ncbi_count = 0L, unreferenced_count = 12L, stringsAsFactors = FALSE)
  )
  out <- capture.output(print(obj))
  expect_true(any(grepl("more", out)))
})


# ============================================================================
# .parse_family_response() -- range_status filtering
# ============================================================================

test_that(".parse_family_response keeps only plausible range_status species", {
  response <- '[
    {"species": "Lucania parva",   "range_status": "native"},
    {"species": "Lucania goodei",  "range_status": "documented_nearby"},
    {"species": "Lucania interioris", "range_status": "not_documented"},
    {"species": "Lucania exotica", "range_status": "taxonomically_impossible"}
  ]'
  result <- TaxaAssign:::.parse_family_response(response, "Fundulidae", character(0L))
  expect_true("Lucania parva" %in% result)
  expect_true("Lucania goodei" %in% result)
  expect_false("Lucania interioris" %in% result)
  expect_false("Lucania exotica" %in% result)
})

test_that(".parse_family_response accepts introduced_established", {
  response <- '[{"species": "Gambusia affinis", "range_status": "introduced_established"}]'
  result <- TaxaAssign:::.parse_family_response(response, "Poeciliidae", character(0L))
  expect_true("Gambusia affinis" %in% result)
})

test_that(".parse_family_response excludes uncertain range_status", {
  response <- '[{"species": "Fundulus cingulatus", "range_status": "uncertain"}]'
  result <- TaxaAssign:::.parse_family_response(response, "Fundulidae", character(0L))
  expect_length(result, 0L)
})

test_that(".parse_family_response removes excluded_genera even if range_status is plausible", {
  response <- '[
    {"species": "Fundulus parvipinnis", "range_status": "native"},
    {"species": "Lucania parva",        "range_status": "native"}
  ]'
  result <- TaxaAssign:::.parse_family_response(response, "Fundulidae",
                                                 exclude_genera = "Fundulus")
  expect_false("Fundulus parvipinnis" %in% result)
  expect_true("Lucania parva" %in% result)
})

test_that(".parse_family_response handles empty array", {
  result <- TaxaAssign:::.parse_family_response("[]", "Fundulidae", character(0L))
  expect_length(result, 0L)
})

test_that(".parse_family_response warns and returns empty on NULL response", {
  expect_warning(
    result <- TaxaAssign:::.parse_family_response(NULL, "Fundulidae", character(0L)),
    regexp = "Empty LLM"
  )
  expect_length(result, 0L)
})

test_that(".parse_family_response falls back gracefully on plain string array with warning", {
  response <- '["Lucania parva", "Lucania goodei"]'
  expect_warning(
    result <- TaxaAssign:::.parse_family_response(response, "Fundulidae", character(0L)),
    regexp = "plain species array"
  )
  expect_true("Lucania parva" %in% result)
})
