# tests/testthat/test-change_backbone.R
#
# Tests for change_backbone()
# All tests are offline — uses mocked verify_taxon_names() output.

# Helper: build a minimal verify_taxon_names()-style tibble
mock_verified <- function(
    user_supplied_name   = "Homo sapiens",
    matched_name         = "Homo sapiens",
    classification_path  = "Animalia|Chordata|Mammalia|Primates|Hominidae|Homo|Homo sapiens",
    classification_ranks = "kingdom|phylum|class|order|family|genus|species",
    score                = 1.0,
    verified             = TRUE
) {
  data.frame(
    user_supplied_name   = user_supplied_name,
    matched_name         = matched_name,
    classification_path  = classification_path,
    classification_ranks = classification_ranks,
    score                = score,
    verified             = verified,
    stringsAsFactors     = FALSE
  )
}

# ==============================================================================
# Input validation
# ==============================================================================

test_that("rejects non-data-frame input_df", {
  expect_error(change_backbone("not a df", input_col = "user_supplied_name"),
               "`input_df` must be a data frame")
})

test_that("rejects non-scalar input_col", {
  df <- mock_verified()
  expect_error(change_backbone(df, input_col = c("a", "b")),
               "`input_col` must be a single column name string")
  expect_error(change_backbone(df, input_col = 1),
               "`input_col` must be a single column name string")
})

test_that("rejects non-scalar backbone label arguments", {
  df <- mock_verified()
  expect_error(
    change_backbone(df, input_col = "user_supplied_name",
                    old_backbone_label = c("A", "B")),
    "`old_backbone_label` must be a single string"
  )
  expect_error(
    change_backbone(df, input_col = "user_supplied_name",
                    new_backbone_label = 99),
    "`new_backbone_label` must be a single string"
  )
})

test_that("stops when required columns are missing from df", {
  df <- data.frame(user_supplied_name = "Homo sapiens")   # missing most required cols
  expect_error(
    change_backbone(df, input_col = "user_supplied_name"),
    "Required column\\(s\\) missing"
  )
})

test_that("stops when input_col itself is missing from df", {
  df <- mock_verified()
  expect_error(
    change_backbone(df, input_col = "nonexistent_col"),
    "Required column\\(s\\) missing"
  )
})

# ==============================================================================
# Column renaming
# ==============================================================================

test_that("renames input_col and matched_name to backbone labels", {
  df  <- mock_verified()
  out <- change_backbone(df,
                         input_col          = "user_supplied_name",
                         old_backbone_label = "NCBI",
                         new_backbone_label = "GBIF")

  expect_true("NCBI" %in% names(out))
  expect_true("GBIF" %in% names(out))
  expect_false("user_supplied_name" %in% names(out))
  expect_false("matched_name"       %in% names(out))
})

test_that("default backbone label names are used when not supplied", {
  df  <- mock_verified()
  out <- change_backbone(df, input_col = "user_supplied_name")

  expect_true("source_name"     %in% names(out))
  expect_true("translated_name" %in% names(out))
})

# ==============================================================================
# Classification path parsing
# ==============================================================================

test_that("produces a column per rank from classification_path", {
  df  <- mock_verified()
  out <- change_backbone(df, input_col = "user_supplied_name",
                         old_backbone_label = "NCBI", new_backbone_label = "GBIF")

  expect_true("kingdom" %in% names(out))
  expect_true("phylum"  %in% names(out))
  expect_true("class"   %in% names(out))
  expect_true("species" %in% names(out))
})

test_that("rank column values are correct", {
  df  <- mock_verified()
  out <- change_backbone(df, input_col = "user_supplied_name",
                         old_backbone_label = "NCBI", new_backbone_label = "GBIF")

  expect_equal(out$kingdom, "Animalia")
  expect_equal(out$phylum,  "Chordata")
  expect_equal(out$genus,   "Homo")
  expect_equal(out$species, "Homo sapiens")
})

test_that("drops classification_path and classification_ranks from output", {
  df  <- mock_verified()
  out <- change_backbone(df, input_col = "user_supplied_name",
                         old_backbone_label = "NCBI", new_backbone_label = "GBIF")

  expect_false("classification_path"  %in% names(out))
  expect_false("classification_ranks" %in% names(out))
})

test_that("score and verified are retained in output", {
  df  <- mock_verified()
  out <- change_backbone(df, input_col = "user_supplied_name",
                         old_backbone_label = "NCBI", new_backbone_label = "GBIF")

  expect_true("score"    %in% names(out))
  expect_true("verified" %in% names(out))
  expect_equal(out$score,    1.0)
  expect_equal(out$verified, TRUE)
})

# ==============================================================================
# NA handling — unverified rows
# ==============================================================================

test_that("NA classification_path produces NA rank columns for that row", {
  df <- mock_verified(
    classification_path  = NA_character_,
    classification_ranks = NA_character_,
    verified             = FALSE,
    score                = NA_real_
  )
  out <- change_backbone(df, input_col = "user_supplied_name",
                         old_backbone_label = "NCBI", new_backbone_label = "GBIF")

  # Should not error; rank columns may be absent or all-NA
  expect_s3_class(out, "data.frame")
  expect_equal(nrow(out), 1L)
})

test_that("handles mixed verified and unverified rows", {
  df <- rbind(
    mock_verified(user_supplied_name = "Homo sapiens",  verified = TRUE),
    mock_verified(user_supplied_name = "Fakus nonexistii",
                  matched_name = NA_character_,
                  classification_path  = NA_character_,
                  classification_ranks = NA_character_,
                  score    = NA_real_,
                  verified = FALSE)
  )
  out <- change_backbone(df, input_col = "user_supplied_name",
                         old_backbone_label = "NCBI", new_backbone_label = "GBIF")

  expect_equal(nrow(out), 2L)
  expect_equal(out$kingdom[1], "Animalia")
})

# ==============================================================================
# Multi-row output
# ==============================================================================

test_that("processes multiple rows correctly", {
  df <- rbind(
    mock_verified(
      user_supplied_name   = "Homo sapiens",
      classification_path  = "Animalia|Chordata|Mammalia|Primates|Hominidae|Homo|Homo sapiens",
      classification_ranks = "kingdom|phylum|class|order|family|genus|species"
    ),
    mock_verified(
      user_supplied_name   = "Mus musculus",
      matched_name         = "Mus musculus",
      classification_path  = "Animalia|Chordata|Mammalia|Rodentia|Muridae|Mus|Mus musculus",
      classification_ranks = "kingdom|phylum|class|order|family|genus|species"
    )
  )

  out <- change_backbone(df, input_col = "user_supplied_name",
                         old_backbone_label = "NCBI", new_backbone_label = "GBIF")

  expect_equal(nrow(out), 2L)
  expect_equal(out$genus, c("Homo", "Mus"))
  expect_equal(out$order, c("Primates", "Rodentia"))
})

# ==============================================================================
# Pipe-friendly
# ==============================================================================

test_that("is pipe-friendly", {
  out <- mock_verified() |>
    change_backbone(input_col = "user_supplied_name",
                    old_backbone_label = "NCBI",
                    new_backbone_label = "GBIF")
  expect_s3_class(out, "data.frame")
  expect_true("NCBI" %in% names(out))
})
