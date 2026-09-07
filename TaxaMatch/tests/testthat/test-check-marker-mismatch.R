# ==============================================================================
# Tests for check_marker_mismatch() and its internal helpers
# (.resolve_marker_pattern(), .fetch_marker_annotation()).
#
# Fully offline: .fetch_marker_annotation() is mocked via
# local_mocked_bindings(), matching this package's established pattern.
# ==============================================================================

.resolve_marker_pattern_int <- function(...) {
  get(".resolve_marker_pattern", envir = asNamespace("TaxaMatch"))(...)
}

# ------------------------------------------------------------------------------
# .resolve_marker_pattern()
# ------------------------------------------------------------------------------

test_that(".resolve_marker_pattern() resolves known marker synonyms", {
  p12s <- .resolve_marker_pattern_int("12S")
  expect_true(grepl(p12s, "12S ribosomal RNA", ignore.case = TRUE))
  expect_true(grepl(p12s, "s-rRNA", ignore.case = TRUE))
  expect_false(grepl(p12s, "16S ribosomal RNA", ignore.case = TRUE))

  # case/punctuation-insensitive key matching
  p12s_lower <- .resolve_marker_pattern_int("mifish-12s")
  expect_true(grepl(p12s_lower, "12S ribosomal RNA", ignore.case = TRUE))
})

test_that(".resolve_marker_pattern() falls back to a literal match for an unlisted marker", {
  p_unknown <- .resolve_marker_pattern_int("XYZ-marker")
  expect_true(grepl(p_unknown, "some XYZ-marker region", ignore.case = TRUE))
  expect_false(grepl(p_unknown, "an unrelated gene", ignore.case = TRUE))
})

# ------------------------------------------------------------------------------
# check_marker_mismatch() -- full offline integration
# ------------------------------------------------------------------------------

# AY850362-style fixture: a real accession annotated as 16S (gene="16S",
# product="16S ribosomal RNA") checked against an expected marker of "12S"
# -- the real motivating case (Question 2, item 4) this function exists to
# catch cheaply, before ever reaching investigate_flagged_accession()'s
# much more expensive deep dive.
.mock_fetch_marker_annotation <- function(accessions, ncbi_api_key = NULL, verbose = TRUE) {
  fx <- data.frame(
    accession = c("AY850362", "AY850362", "MZ605481", "NOANNOT111"),
    feature_key = c("rRNA", "gene", "rRNA", NA_character_),
    gene = c(NA_character_, "16S", NA_character_, NA_character_),
    product = c("16S ribosomal RNA", NA_character_, "12S ribosomal RNA", NA_character_),
    stringsAsFactors = FALSE
  )
  fx[fx$accession %in% accessions, , drop = FALSE]
}

test_that("check_marker_mismatch() detects a real marker mismatch (AY850362-style)", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("AY850362", "12S", verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_false(out$marker_match)
  expect_equal(out$annotated_products, "16S ribosomal RNA")
  expect_equal(out$annotated_genes, "16S")
})

test_that("check_marker_mismatch() confirms a real marker match", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("MZ605481", "12S", verbose = FALSE)
  expect_true(out$marker_match)
  expect_equal(out$annotated_products, "12S ribosomal RNA")
})

test_that("check_marker_mismatch() returns NA marker_match when the record has no relevant annotation", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("NOANNOT111", "12S", verbose = FALSE)
  expect_true(is.na(out$marker_match))
})

test_that("check_marker_mismatch() returns NA marker_match for an accession not found at all", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("GHOST999", "12S", verbose = FALSE)
  expect_true(is.na(out$marker_match))
  expect_true(is.na(out$annotated_genes))
  expect_true(is.na(out$annotated_products))
})

test_that("check_marker_mismatch() checks multiple accessions and dedupes input", {
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch(
    c("AY850362", "MZ605481", "AY850362"), "12S",
    verbose = FALSE
  )
  expect_equal(nrow(out), 2L)
  expect_setequal(out$accession, c("AY850362", "MZ605481"))
  expect_false(out$marker_match[out$accession == "AY850362"])
  expect_true(out$marker_match[out$accession == "MZ605481"])
})

# ------------------------------------------------------------------------------
# .fetch_marker_annotation() -- feature_from/feature_to columns (2026-09-01,
# added for the feature-table-guided extraction fallback in
# R/trim_query_to_amplicon.R; check_marker_mismatch() itself never reads
# them). Schema-only check via the zero-accession early-return path -- no
# network call, real code path (not mocked).
# ------------------------------------------------------------------------------

test_that(".fetch_marker_annotation() empty-input result carries feature_from/feature_to columns", {
  out <- .fetch_marker_annotation(character(0L))
  expect_true(all(c("feature_from", "feature_to") %in% names(out)))
  expect_equal(nrow(out), 0L)
  expect_true(is.numeric(out$feature_from))
  expect_true(is.numeric(out$feature_to))
})

test_that("check_marker_mismatch() output is unaffected by the new feature_from/feature_to columns on the fetch side", {
  # .mock_fetch_marker_annotation() (above) deliberately does NOT carry
  # feature_from/feature_to -- confirms check_marker_mismatch() never reads
  # them and keeps working against a fetcher shaped like the pre-2026-09-01
  # schema.
  local_mocked_bindings(
    .fetch_marker_annotation = .mock_fetch_marker_annotation, .package = "TaxaMatch"
  )
  out <- check_marker_mismatch("MZ605481", "12S", verbose = FALSE)
  expect_true(out$marker_match)
})

test_that("check_marker_mismatch() validates inputs", {
  expect_error(check_marker_mismatch(123, "12S"), "character vector")
  expect_error(check_marker_mismatch(character(0L), "12S"), "non-empty")
  expect_error(check_marker_mismatch(c(NA, ""), "12S"), "No valid")
  expect_error(check_marker_mismatch("AY850362", NA_character_), "expected_marker")
  expect_error(check_marker_mismatch("AY850362", c("12S", "16S")), "expected_marker")
})

# ------------------------------------------------------------------------------
# .fetch_marker_annotation() -- GBQualifier name/value pairing and the
# version-suffix-stripped join back to the caller's own accession strings.
#
# Both were real defects (fixed 2026-09-07, formal review pass), both
# reproduced here against fixtures shaped exactly like real NCBI GBSet XML:
#
#   (1) The INSDC GBSet DTD makes GBQualifier_value OPTIONAL, so a valueless
#       qualifier (/trans_splicing here -- real, on NC_000932's rps12
#       gene/CDS features) shifts every subsequent value onto the wrong name
#       when name and value are read as two independent xml_find_all()
#       sweeps. Confirmed on the real record before fixing.
#   (2) GBSeq_primary-accession is always version-free, but both consumers
#       key on the string the CALLER asked about -- so a versioned request
#       matched nothing and read as "this record has no annotation at all".
# ------------------------------------------------------------------------------

.gbseq_xml_with_valueless_qualifier <- function() {
  paste0(
    '<?xml version="1.0"?><GBSet><GBSeq>',
    "<GBSeq_primary-accession>NC_000932</GBSeq_primary-accession>",
    "<GBSeq_accession-version>NC_000932.1</GBSeq_accession-version>",
    "<GBSeq_feature-table><GBFeature>",
    "<GBFeature_key>CDS</GBFeature_key>",
    "<GBFeature_intervals><GBInterval>",
    "<GBInterval_from>100</GBInterval_from><GBInterval_to>400</GBInterval_to>",
    "</GBInterval></GBFeature_intervals>",
    "<GBFeature_quals>",
    "<GBQualifier><GBQualifier_name>gene</GBQualifier_name>",
    "<GBQualifier_value>rps12</GBQualifier_value></GBQualifier>",
    # valueless qualifier, exactly as GenBank emits /trans_splicing
    "<GBQualifier><GBQualifier_name>trans_splicing</GBQualifier_name></GBQualifier>",
    "<GBQualifier><GBQualifier_name>codon_start</GBQualifier_name>",
    "<GBQualifier_value>1</GBQualifier_value></GBQualifier>",
    "<GBQualifier><GBQualifier_name>product</GBQualifier_name>",
    "<GBQualifier_value>12S ribosomal RNA</GBQualifier_value></GBQualifier>",
    "</GBFeature_quals></GBFeature></GBSeq_feature-table>",
    "</GBSeq></GBSet>"
  )
}

test_that(".fetch_marker_annotation() pairs a valueless GBQualifier with the right name", {
  local_mocked_bindings(
    entrez_fetch = function(...) .gbseq_xml_with_valueless_qualifier(),
    .package = "rentrez"
  )
  out <- .fetch_marker_annotation("NC_000932", verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_equal(out$gene, "rps12")
  # Before the fix this read "1" (codon_start's value, shifted one position
  # by the valueless /trans_splicing qualifier), not the real product.
  expect_equal(out$product, "12S ribosomal RNA")
  expect_equal(out$feature_from, 100)
  expect_equal(out$feature_to, 400)
})

test_that(".fetch_marker_annotation() reports rows under the caller's own versioned accession", {
  local_mocked_bindings(
    entrez_fetch = function(...) .gbseq_xml_with_valueless_qualifier(),
    .package = "rentrez"
  )
  out <- .fetch_marker_annotation("NC_000932.1", verbose = FALSE)
  expect_equal(out$accession, "NC_000932.1")

  # ... and unchanged for a version-free request.
  out2 <- .fetch_marker_annotation("NC_000932", verbose = FALSE)
  expect_equal(out2$accession, "NC_000932")
})

test_that("check_marker_mismatch() resolves a versioned accession (regression)", {
  local_mocked_bindings(
    entrez_fetch = function(...) .gbseq_xml_with_valueless_qualifier(),
    .package = "rentrez"
  )
  # Before the fix this returned marker_match = NA and all-NA annotation,
  # purely because "NC_000932.1" != NCBI's version-free primary accession.
  out <- check_marker_mismatch("NC_000932.1", "12S", verbose = FALSE)
  expect_equal(nrow(out), 1L)
  expect_true(out$marker_match)
  expect_equal(out$annotated_products, "12S ribosomal RNA")
})
