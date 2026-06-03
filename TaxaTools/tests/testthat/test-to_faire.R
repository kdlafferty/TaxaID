# tests/testthat/test-to_faire.R
# Offline tests for to_faire()

# ---------------------------------------------------------------------------
# Minimal fixture: match-object-style data frame
# ---------------------------------------------------------------------------
make_match_df <- function() {
  data.frame(
    observation_id  = c("ASV1", "ASV2"),
    taxon_name      = c("Fundulus parvipinnis", "Atherinops affinis"),
    taxon_name_rank = c("species", "species"),
    score           = c(98.7, 95.1),
    coverage        = c(0.98, 0.94),
    accession       = c("MG002616.1", "KT215432.1"),
    family          = c("Fundulidae", "Atherinopsidae"),
    genus           = c("Fundulus", "Atherinops"),
    species         = c("Fundulus parvipinnis", "Atherinops affinis"),
    testid          = c("MiFishU", "MiFishU"),
    stringsAsFactors = FALSE
  )
}

# ===========================================================================
# Part A: Column renames
# ===========================================================================

test_that("to_faire: core column renames are applied", {
  out <- to_faire(make_match_df())
  expect_true("seq_id"             %in% names(out))
  expect_true("scientificName"     %in% names(out))
  expect_true("taxonRank"          %in% names(out))
  expect_true("percent_match"      %in% names(out))
  expect_true("percent_query_cover" %in% names(out))
  expect_true("accession_id"       %in% names(out))
  expect_true("assay_name"         %in% names(out))
})

test_that("to_faire: original TaxaID column names are gone after rename", {
  out <- to_faire(make_match_df())
  expect_false("observation_id"  %in% names(out))
  expect_false("taxon_name"      %in% names(out))
  expect_false("taxon_name_rank" %in% names(out))
  expect_false("score"           %in% names(out))
  expect_false("coverage"        %in% names(out))
  expect_false("accession"       %in% names(out))
  expect_false("testid"          %in% names(out))
})

test_that("to_faire: values are preserved through renames", {
  df  <- make_match_df()
  out <- to_faire(df)
  expect_equal(out$seq_id,              df$observation_id)
  expect_equal(out$scientificName,      df$taxon_name)
  expect_equal(out$taxonRank,           df$taxon_name_rank)
  expect_equal(out$percent_match,       df$score)
  expect_equal(out$percent_query_cover, df$coverage)
  expect_equal(out$accession_id,        df$accession)
  expect_equal(out$assay_name,          df$testid)
})

test_that("to_faire: taxonomy rank columns (family/genus/species) are unchanged", {
  df  <- make_match_df()
  out <- to_faire(df)
  expect_equal(out$family,  df$family)
  expect_equal(out$genus,   df$genus)
  expect_equal(out$species, df$species)
})

# ===========================================================================
# Part B: Constructed columns
# ===========================================================================

test_that("to_faire: verbatimIdentification is semicolon-delimited taxonomy", {
  out <- to_faire(make_match_df())
  expect_true("verbatimIdentification" %in% names(out))
  expect_true(grepl(";", out$verbatimIdentification[1L]))
  # Should contain family, genus, and species values
  expect_true(grepl("Fundulidae",            out$verbatimIdentification[1L]))
  expect_true(grepl("Fundulus parvipinnis",  out$verbatimIdentification[1L]))
})

test_that("to_faire: specificEpithet is second word of species binomial", {
  out <- to_faire(make_match_df())
  expect_true("specificEpithet" %in% names(out))
  expect_equal(out$specificEpithet[1L], "parvipinnis")
  expect_equal(out$specificEpithet[2L], "affinis")
})

test_that("to_faire: specificEpithet is NA when species is NA", {
  df <- make_match_df()
  df$species[1L] <- NA_character_
  out <- to_faire(df)
  expect_true(is.na(out$specificEpithet[1L]))
  expect_false(is.na(out$specificEpithet[2L]))
})

test_that("to_faire: checkls_ver column is added with default value", {
  out <- to_faire(make_match_df())
  expect_true("checkls_ver" %in% names(out))
  expect_true(all(out$checkls_ver == "1.02"))
})

test_that("to_faire: custom checkls_ver is used", {
  out <- to_faire(make_match_df(), checkls_ver = "2.0")
  expect_true(all(out$checkls_ver == "2.0"))
})

# ===========================================================================
# Part C: faire_table attribute
# ===========================================================================

test_that("to_faire: faire_table attribute is attached", {
  out <- to_faire(make_match_df(), table_type = "taxaRaw")
  att <- attr(out, "faire_table")
  expect_equal(att$table_type,  "taxaRaw")
  expect_equal(att$checkls_ver, "1.02")
})

test_that("to_faire: table_type = taxaFinal is default", {
  out <- to_faire(make_match_df())
  expect_equal(attr(out, "faire_table")$table_type, "taxaFinal")
})

# ===========================================================================
# Part D: Missing optional columns
# ===========================================================================

test_that("to_faire: works when testid column is absent (messages and skips)", {
  df <- make_match_df()
  df$testid <- NULL
  expect_message(out <- to_faire(df), "assay_name.*omitted")
  expect_false("assay_name" %in% names(out))
})

test_that("to_faire: assay_name param fills in when testid absent", {
  df <- make_match_df()
  df$testid <- NULL
  suppressMessages(out <- to_faire(df, assay_name = "MiFishU"))
  expect_true("assay_name" %in% names(out))
  expect_true(all(out$assay_name == "MiFishU"))
})

test_that("to_faire: works without score/coverage columns (partial match df)", {
  df <- make_match_df()[, c("observation_id", "taxon_name", "taxon_name_rank",
                             "family", "genus", "species")]
  out <- suppressMessages(to_faire(df))
  expect_true("seq_id" %in% names(out))
  expect_false("percent_match"       %in% names(out))
  expect_false("percent_query_cover" %in% names(out))
})

test_that("to_faire: non-FAIRe columns are retained unchanged", {
  df <- make_match_df()
  df$custom_col <- "keep_me"
  out <- to_faire(df)
  expect_true("custom_col" %in% names(out))
  expect_true(all(out$custom_col == "keep_me"))
})

# ===========================================================================
# Part E: Input validation
# ===========================================================================

test_that("to_faire: error on non-data-frame input", {
  expect_error(to_faire(list(a = 1)), "data frame")
})

test_that("to_faire: error on invalid checkls_ver", {
  expect_error(to_faire(make_match_df(), checkls_ver = 1.02), "non-empty single string")
})

test_that("to_faire: error on invalid assay_name", {
  expect_error(to_faire(make_match_df(), assay_name = 42), "non-empty single string")
})

test_that("to_faire: error on invalid table_type", {
  expect_error(to_faire(make_match_df(), table_type = "taxaMiddle"), "should be one of")
})
