# test-report_flags.R
# Tests for report_flags()

test_that("report_flags detects contaminant flags", {
  df <- data.frame(
    observation_id = paste0("S", 1:5),
    flag_lab = c("likely", "likely", "unlikely", "possible", "likely"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_s3_class(sec, "report_section")
  expect_equal(sec$package, "TaxaFlag")
  expect_equal(sec$section, "flags")
  expect_true("contamination" %in% sec$params$flag_types)
  expect_equal(sec$statistics$n_total, 5L)
  expect_equal(sec$statistics$n_flagged, 2L) # "unlikely" + "possible"
})

test_that("report_flags detects handler flags", {
  df <- data.frame(
    observation_id = paste0("S", 1:4),
    flag_handler = c("likely", "unlikely", "likely", "likely"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_true("handler artifacts" %in% sec$params$flag_types)
})

test_that("report_flags detects multiple flag types", {
  df <- data.frame(
    observation_id = paste0("S", 1:3),
    flag_lab = c("likely", "unlikely", "likely"),
    flag_handler = c("likely", "likely", "possible"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_equal(sec$statistics$flag_types_detected, 2L)
  expect_true("contamination" %in% sec$params$flag_types)
  expect_true("handler artifacts" %in% sec$params$flag_types)
})

test_that("report_flags reports zero flags correctly", {
  df <- data.frame(
    observation_id = paste0("S", 1:5),
    flag_lab = rep("likely", 5),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_equal(sec$statistics$n_flagged, 0L)
  expect_true(grepl("none were flagged", sec$results))
})

test_that("report_flags detects review columns", {
  df <- data.frame(
    observation_id = paste0("S", 1:3),
    review_confidence = c("high", "low", "medium"),
    review_comment = c("OK", "Suspect", "Fine"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_true("expert review" %in% sec$params$flag_types)
})

test_that("report_flags handles data with no flag columns", {
  df <- data.frame(
    observation_id = paste0("S", 1:3),
    taxon = c("A", "B", "C"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_equal(sec$statistics$flag_types_detected, 0L)
  expect_true(grepl("No quality flags", sec$methods))
})

test_that("report_flags errors on empty data", {
  expect_error(report_flags(data.frame()))
  expect_error(report_flags(NULL))
})

test_that("report_flags percentage is correct", {
  df <- data.frame(
    observation_id = paste0("S", 1:10),
    flag_field = c(rep("unlikely", 3), rep("likely", 7)),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  # 3 out of 10 = 30%
  expect_equal(sec$statistics$n_flagged, 3L)
  expect_true(grepl("30\\.0%", sec$results))
})

# ===========================================================================
# Unified validity schema (2026-07-24) -- flag_contaminant()/flag_handler()
# now share one literal column name (validity_flag), so detection has to
# read the check type out of the VALUES ("invalid_{type}"/
# "questionable_{type}"), not the column name. Additive to, not a
# replacement for, the two naming eras tested above.
# ===========================================================================

test_that("report_flags detects the unified validity schema (contaminant)", {
  df <- data.frame(
    observation_id = paste0("S", 1:5),
    observation_validity = c(0.9, 0.9, 0.1, 0.6, 0.9),
    validity_flag = c(
      "valid", "valid", "invalid_lab_contaminant",
      "questionable_lab_contaminant", "valid"
    ),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_true("contamination" %in% sec$params$flag_types)
  expect_equal(sec$statistics$n_total, 5L)
  expect_equal(sec$statistics$n_flagged, 2L) # invalid + questionable
  expect_equal(sec$statistics$flag_counts[["invalid_lab_contaminant"]], 1L)
  expect_equal(sec$statistics$flag_counts[["questionable_lab_contaminant"]], 1L)
})

test_that("report_flags detects the unified validity schema (handler)", {
  df <- data.frame(
    observation_id = paste0("S", 1:4),
    observation_validity = c(1.0, 0.0, 1.0, 0.6),
    validity_flag = c(
      "valid", "invalid_handling", "valid",
      "questionable_handling"
    ),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_true("handler artifacts" %in% sec$params$flag_types)
  expect_equal(sec$statistics$n_flagged, 2L)
})

test_that("report_flags: unified validity schema with all-valid rows reports zero flags", {
  df <- data.frame(
    observation_id = paste0("S", 1:3),
    observation_validity = rep(1.0, 3),
    validity_flag = rep("valid", 3),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_equal(sec$statistics$n_flagged, 0L)
  expect_true(grepl("none were flagged", sec$results))
})

test_that("report_flags: unified validity schema still works alongside an old-era column", {
  # Confirms the new schema doesn't regress the pre-existing naming eras --
  # a data frame could plausibly carry both if built from different-vintage
  # checkpoints.
  df <- data.frame(
    observation_id = paste0("S", 1:4),
    flag_lab = c("likely", "unlikely", "likely", "likely"),
    observation_validity = c(1.0, 1.0, 0.0, 1.0),
    validity_flag = c("valid", "valid", "invalid_handling", "valid"),
    stringsAsFactors = FALSE
  )

  sec <- report_flags(df)
  expect_true("contamination" %in% sec$params$flag_types)
  expect_true("handler artifacts" %in% sec$params$flag_types)
  expect_equal(sec$statistics$n_flagged, 2L) # row 2 (old-era) + row 3 (new-era)
})


# ---- reference support (information only) ------------------------------------

.rf_ref <- function() {
  data.frame(
    taxon_name = c("Girella nigricans", "Homo sapiens", "Mytilus", "Sarda chiliensis"),
    validity_flag = c("valid", "invalid_lab_contaminant", "valid", "valid"),
    winner_n_references = c(3L, 20L, NA_integer_, NA_integer_),
    winner_reference_basis = c(
      "model_species_row", "model_species_row", "rank_not_in_model",
      "no_model_row"
    ),
    winner_at_model_max = c(FALSE, TRUE, NA, NA),
    stringsAsFactors = FALSE
  )
}

test_that("report_flags summarises reference support without counting it as a flag", {
  sec <- report_flags(.rf_ref())
  rs <- sec$statistics$reference_support$winner

  expect_equal(rs$n_rows, 4L)
  expect_equal(rs$n_with_count, 2L)
  expect_equal(rs$min, 3)
  expect_equal(rs$max, 20)
  expect_equal(rs$n_at_model_max, 1L)
  expect_equal(rs$basis$no_model_row, 1L)
  expect_equal(rs$basis$rank_not_in_model, 1L)

  # The one real flag is the contaminant row. Reference support must not
  # inflate it -- the whole point of the column is that it accuses nobody.
  expect_equal(sec$statistics$n_flagged, 1L)
})

test_that("the report text says a low count is not evidence a call is wrong", {
  sec <- report_flags(.rf_ref())
  expect_match(sec$methods, "information only", fixed = TRUE)
  expect_match(sec$methods, "not evidence that a call is", fixed = TRUE)
  expect_match(sec$results, "Reference support (winner)", fixed = TRUE)
  # ...and that the uncounted rows are the thinner ones, not the better ones.
  expect_match(sec$results, "not more", fixed = TRUE)
})

test_that("a prefix other than winner_ is detected too", {
  d <- .rf_ref()
  names(d) <- sub("^winner_", "primary_", names(d))
  sec <- report_flags(d)
  expect_equal(sec$statistics$reference_support$primary$n_with_count, 2L)
})

test_that("data with no reference-support columns reports none", {
  sec <- report_flags(.rf_ref()[, c("taxon_name", "validity_flag")])
  expect_null(sec$statistics$reference_support)
  expect_false(grepl("Reference support", sec$results, fixed = TRUE))
})
