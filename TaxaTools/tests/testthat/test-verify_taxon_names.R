# tests/testthat/test-verify_taxon_names.R
#
# Tests for verify_taxon_names()
#
# Tests are split into two groups:
#   1. Offline — test input validation without hitting the internet
#   2. Online  — test real API behavior (skipped on CRAN and CI if no internet)
#
# To run manually: devtools::test()

# ── Offline tests: input validation ─────────────────────────────────────────

test_that("rejects non-character input", {
  expect_error(verify_taxon_names(123, backbone_id = 4),
               "`name_list` must be a non-empty character vector")
})

test_that("rejects empty character vector", {
  expect_error(verify_taxon_names(character(0), backbone_id = 4),
               "`name_list` must be a non-empty character vector")
})

test_that("rejects missing or non-scalar backbone_id", {
  expect_error(verify_taxon_names("Homo sapiens", backbone_id = c(4, 9)),
               "`backbone_id` must be a single integer")
  expect_error(verify_taxon_names("Homo sapiens", backbone_id = "ncbi"),
               "`backbone_id` must be a single integer")
})

# ── Online tests: real API behavior ─────────────────────────────────────────
# These tests require internet access and are skipped otherwise.

test_that("returns correct structure for valid names", {
  skip_if_offline()

  result <- verify_taxon_names(
    name_list   = c("Homo sapiens", "Mus musculus"),
    backbone_id = 4
  )

  # Output is a data frame / tibble
  expect_s3_class(result, "data.frame")

  # Correct number of rows
  expect_equal(nrow(result), 2)

  # All expected columns present (fuzzy_corrected is specific to the
  # backbone_id = 4 / NCBI path)
  expect_named(result,
               c("user_supplied_name", "matched_name", "matched_rank",
                 "is_synonym", "classification_path", "classification_ranks",
                 "score", "verified", "fuzzy_corrected"),
               ignore.order = TRUE)

  # matched_rank correctly reflects the resolved rank (species, here)
  expect_true(all(result$matched_rank == "species"))
  # NCBI's direct-lookup bypass has no access to synonym relationships
  expect_true(all(is.na(result$is_synonym)))

  # All rows reached the API
  expect_true(all(result$verified))

  # Score is numeric
  expect_type(result$score, "double")

  # fuzzy_corrected column present (backbone_id = 4 path) and FALSE for
  # correctly-spelled names that matched on the first exact NCBI pass
  expect_true("fuzzy_corrected" %in% names(result))
  expect_false(any(result$fuzzy_corrected))
})

# ── Online tests: fuzzy cross-backbone fallback (Step 1c) ──────────────────
# Real motivating case: "Acanthogobius flavimannus" (double n, a real
# hand-transcription typo found in a Mugu literature-reported-species table)
# has zero hits in NCBI's own database under either spelling variant (confirmed
# directly against NCBI eutils) but is fuzzy-matched correctly by every other
# backbone (GBIF/CoL/ITIS/WoRMS all tested manually before this fix shipped).

test_that("NCBI path fuzzy-corrects a real misspelling via the fallback backbone", {
  skip_if_offline()
  skip_if_verifier_down()

  expect_warning(
    result <- verify_taxon_names("Acanthogobius flavimannus", backbone_id = 4),
    "fuzzy-matched via backbone 11"
  )

  expect_equal(result$matched_name, "Acanthogobius flavimanus")
  expect_true(result$fuzzy_corrected)
  expect_true(result$verified)
  # The corrected name is re-resolved through NCBI itself, not borrowed from
  # the fallback backbone -- NCBI's own lineage uses "Actinopteri", not GBIF's.
  expect_true(grepl("Actinopteri", result$classification_path))
})

test_that("NCBI path does not flag a correctly-spelled name as fuzzy-corrected", {
  skip_if_offline()

  result <- verify_taxon_names("Acanthogobius flavimanus", backbone_id = 4)

  expect_equal(result$matched_name, "Acanthogobius flavimanus")
  expect_false(result$fuzzy_corrected)
})

test_that("fallback_backbone_id = 4 errors immediately", {
  expect_error(
    verify_taxon_names("Homo sapiens", backbone_id = 4, fallback_backbone_id = 4),
    "`fallback_backbone_id` cannot be 4"
  )
})

test_that("a genuinely nonexistent name is left unmatched even after the fuzzy fallback", {
  skip_if_offline()
  skip_if_verifier_down()

  result <- verify_taxon_names("Zzznotarealtaxonxyz123", backbone_id = 4)

  expect_true(is.na(result$matched_name))
  expect_false(result$fuzzy_corrected)
})

test_that("exact matches return score of 1", {
  skip_if_offline()

  result <- verify_taxon_names("Homo sapiens", backbone_id = 4)
  expect_equal(result$score, 1)
})

test_that("unrecognized name returns NA matched_name with verified = TRUE", {
  skip_if_offline()
  skip_if_verifier_down()

  result <- verify_taxon_names("Xyzzy fakeii", backbone_id = 4)
  expect_true(result$verified)
  expect_true(is.na(result$matched_name))
})

test_that("duplicates are deduplicated for API but output preserves input length", {
  skip_if_offline()

  result <- verify_taxon_names(
    c("Homo sapiens", "Homo sapiens", "Homo sapiens"),
    backbone_id = 4
  )
  # Output has same length as input; duplicates get identical results
  expect_equal(nrow(result), 3)
  expect_equal(result$matched_name[1], result$matched_name[2])
  expect_equal(result$matched_name[2], result$matched_name[3])
})

test_that("whitespace in names is trimmed", {
  skip_if_offline()

  result <- verify_taxon_names("  Homo sapiens  ", backbone_id = 4)
  expect_equal(result$user_supplied_name, "Homo sapiens")
})

# ── Online tests: matched_rank / is_synonym (Global Names Verifier path) ────
# Real motivating case: an NCBI reference sequence for accession LC765844 is
# labelled "Inu sp. 1 sensu Shibukawa et al., 2020." -- an informally-named
# goby (Gobiidae) species. GBIF's backbone resolves "Inu" (Snyder, 1909) as a
# taxonomic SYNONYM of the currently-accepted genus "Luciogobius" (Gill,
# 1859) and can only match at genus rank (no species-level entry exists for
# the informal name). Before this fix, downstream code (TaxaMatch::
# convert_taxonomy_backbone()) had no way to tell the match was genus-only,
# not species-level, and a naive genus-name-duplication fallback elsewhere in
# the ecosystem manufactured a fabricated pseudo-binomial ("Inu Inu") from
# it. Confirmed live against the real GNVerifier API across 5 backbones
# (Catalogue of Life, ITIS, NCBI, WoRMS, GBIF) before this test was written --
# see TaxaTools/CLAUDE.md's matching session note for the full record,
# including confirmation that NCBI's own taxonomy does NOT consider "Inu" a
# synonym at all (a genuine cross-backbone disagreement, not a bug).

test_that("a genus-only synonym match resolves to the current accepted genus, not the synonym", {
  skip_if_offline()
  skip_if_verifier_down()

  result <- verify_taxon_names(
    "Inu sp. 1 sensu Shibukawa et al., 2020.",
    backbone_id = 11L  # GBIF
  )

  expect_equal(result$matched_name, "Luciogobius")
  expect_equal(result$matched_rank, "genus")
  expect_true(result$is_synonym)
})

test_that("matched_rank correctly reports genus when only genus-level data exists (GBIF)", {
  skip_if_offline()
  skip_if_verifier_down()

  result <- verify_taxon_names(
    "Inu sp. 1 sensu Shibukawa et al., 2020.",
    backbone_id = 11L
  )
  expect_equal(result$matched_rank, "genus")
})

test_that("a non-synonym match is left unchanged and is_synonym is FALSE", {
  skip_if_offline()
  skip_if_verifier_down()

  result <- verify_taxon_names("Homo sapiens", backbone_id = 11L)

  expect_equal(result$matched_name, "Homo sapiens")
  expect_equal(result$matched_rank, "species")
  expect_false(result$is_synonym)
})

test_that("a subspecies-rank match preserves the full trinomial, not just genus+epithet", {
  skip_if_offline()
  skip_if_verifier_down()

  # Real regression case: the previous strip_authority() regex only captured
  # "genus + at most one lowercase word", silently truncating any
  # subspecies-rank match down to a binomial (verified directly:
  # "Delphinus delphis ponticus Barabash, 1935" -> "Delphinus delphis",
  # dropping "ponticus" entirely). matchedCanonicalSimple does not have this
  # problem.
  result <- verify_taxon_names("Delphinus delphis ponticus", backbone_id = 11L)

  expect_equal(result$matched_name, "Delphinus delphis ponticus")
  expect_equal(result$matched_rank, "subspecies")
})

test_that("a no-match result has NA matched_rank and NA is_synonym", {
  skip_if_offline()
  skip_if_verifier_down()

  result <- verify_taxon_names("Zzznotarealtaxonxyz123", backbone_id = 11L)

  expect_true(is.na(result$matched_name))
  expect_true(is.na(result$matched_rank))
  expect_true(is.na(result$is_synonym))
})
