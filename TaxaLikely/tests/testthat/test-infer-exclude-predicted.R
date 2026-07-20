# Tests for infer_exclude_predicted().
# Fixtures ported from the ad hoc inst/test_infer_exclude_predicted.R script
# (deleted this session) -- four scenarios covering the function's full
# return-value space, using accession patterns that mimic real reference
# database conventions (GenBank/RefSeq NR_, Jonah Ventures custom vouchers,
# predicted XR_/XM_ RefSeq records, and WilderLab's accession-free tables).

.make_match_ncbi <- function() {
  data.frame(
    observation_id = paste0("ESV_", 1:6),
    accession      = c("AB123456.1", "KP891234.2", "NR_036856.1",
                       "MH213045.1", "NR_024642.1", "AB987654.1"),
    genus          = "Sebastes",
    species        = "Sebastes mystinus",
    score_original = 99,
    stringsAsFactors = FALSE
  )
}

.make_match_mixed <- function() {
  data.frame(
    observation_id = paste0("ESV_", 1:8),
    accession      = c("AB123456.1", "NR_036856.1", "KP891234.2",
                       "JV_voucher_00001", "JV_voucher_00002", "JV_voucher_00003",
                       "MH213045.1", "NR_024642.1"),
    genus          = "Haliotis",
    species        = c(rep("Haliotis rufescens", 4), rep("Haliotis fulgens", 4)),
    score_original = 98,
    stringsAsFactors = FALSE
  )
}

.make_match_predicted <- function() {
  data.frame(
    observation_id = paste0("ESV_", 1:6),
    accession      = c("AB123456.1", "NR_036856.1", "XR_003654321.1",
                       "XM_012345678.2", "KP891234.2", "NM_001234567.1"),
    genus          = "Gadus",
    species        = "Gadus morhua",
    score_original = 97,
    stringsAsFactors = FALSE
  )
}

.make_match_wilderlab <- function() {
  data.frame(
    observation_id  = paste0("ESV_", 1:4),
    taxon_name      = "Sebastes mystinus",
    taxon_name_rank = "species",
    genus           = "Sebastes",
    species         = "Sebastes mystinus",
    score_original  = 100,
    stringsAsFactors = FALSE
  )
}

test_that("infer_exclude_predicted: NCBI-only accessions (no XR_/XM_) return TRUE", {
  expect_true(suppressMessages(infer_exclude_predicted(.make_match_ncbi())))
})

test_that("infer_exclude_predicted: mixed NCBI + custom-voucher accessions still return TRUE", {
  # Jonah Ventures-style custom accessions coexist with real NCBI ones; the
  # NCBI subset alone has no XR_/XM_ records.
  expect_true(suppressMessages(infer_exclude_predicted(.make_match_mixed())))
})

test_that("infer_exclude_predicted: predicted XR_/XM_ accessions present return FALSE", {
  expect_false(suppressMessages(infer_exclude_predicted(.make_match_predicted())))
})

test_that("infer_exclude_predicted: no accession column returns NA", {
  expect_true(is.na(suppressMessages(infer_exclude_predicted(.make_match_wilderlab()))))
})

test_that("infer_exclude_predicted: !isFALSE() coalesces NA and TRUE to TRUE, FALSE stays FALSE", {
  # Documented usage pattern feeding audit_barcode_coverage(exclude_predicted=)
  ep_ncbi      <- suppressMessages(infer_exclude_predicted(.make_match_ncbi()))
  ep_predicted <- suppressMessages(infer_exclude_predicted(.make_match_predicted()))
  ep_na        <- suppressMessages(infer_exclude_predicted(.make_match_wilderlab()))
  expect_true(!isFALSE(ep_ncbi))
  expect_false(!isFALSE(ep_predicted))
  expect_true(!isFALSE(ep_na))
})

test_that("infer_exclude_predicted: explicit accession_col overrides auto-detection", {
  df <- .make_match_predicted()
  names(df)[names(df) == "accession"] <- "acc_number"
  expect_false(suppressMessages(infer_exclude_predicted(df, accession_col = "acc_number")))
})

test_that("infer_exclude_predicted: non-data-frame input errors", {
  expect_error(infer_exclude_predicted(list()), "must be a data frame")
})

test_that("infer_exclude_predicted: invalid explicit accession_col errors", {
  expect_error(
    infer_exclude_predicted(.make_match_ncbi(), accession_col = "nope"),
    "not found"
  )
})
