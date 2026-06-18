# test-convert_taxonomy_backbone.R
# Tests for convert_taxonomy_backbone().
# All tests are offline using a mock verify_fn (dependency injection).

# ---------------------------------------------------------------------------
# Mock verify_fn for offline testing
#
# Simulates verify_taxon_names() output for three species with known
# NCBI vs GBIF hierarchy differences (based on real lookup results):
#
#   Girella nigricans:  NCBI family=Girellidae, GBIF family=Kyphosidae
#   Fundulus parvipinnis: NCBI order=Cyprinodontiformes,
#                          GBIF order=Cyprinodontiformes (same — consistent)
#   Acanthogobius flavimanus: NCBI order=Gobiiformes,
#                              GBIF order=Gobiiformes (same — consistent)
#   Nonexistent taxon: not found in backbone (verified = FALSE)
# ---------------------------------------------------------------------------

.make_verified_row <- function(name, matched, cls_path, cls_ranks,
                                verified = TRUE) {
  data.frame(
    user_supplied_name    = name,
    matched_name          = matched,
    classification_path   = cls_path,
    classification_ranks  = cls_ranks,
    verified              = verified,
    stringsAsFactors      = FALSE
  )
}

# Simulates GBIF (backbone_id = 11) responses
.mock_verify_gbif <- function(name_list, backbone_id) {
  stopifnot(backbone_id == 11)
  rows <- list(
    .make_verified_row(
      "Girella nigricans",
      "Girella nigricans (Ayres, 1860)",
      "Eukaryota|Chordata|Actinopteri|Eupercaria|Kyphosidae|Girella|Girella nigricans",
      "kingdom|phylum|class|order|family|genus|species"
    ),
    .make_verified_row(
      "Fundulus parvipinnis",
      "Fundulus parvipinnis Girard, 1854",
      "Eukaryota|Chordata|Actinopteri|Cyprinodontiformes|Fundulidae|Fundulus|Fundulus parvipinnis",
      "kingdom|phylum|class|order|family|genus|species"
    ),
    .make_verified_row(
      "Acanthogobius flavimanus",
      "Acanthogobius flavimanus (Temminck & Schlegel, 1845)",
      "Eukaryota|Chordata|Actinopteri|Gobiiformes|Gobiidae|Acanthogobius|Acanthogobius flavimanus",
      "kingdom|phylum|class|order|family|genus|species"
    ),
    .make_verified_row(
      "Nonexistent taxon",
      NA_character_,
      NA_character_,
      NA_character_,
      verified = FALSE
    )
  )
  do.call(rbind, rows)
}

# Minimal match-object-style data frame mimicking NCBI BLAST output
.ncbi_match_df <- data.frame(
  observation_id = c("ESV_001", "ESV_002", "ESV_003", "ESV_004"),
  taxon_name     = c("Girella nigricans", "Fundulus parvipinnis",
                     "Acanthogobius flavimanus", "Nonexistent taxon"),
  order          = c("Perciformes",        "Cyprinodontiformes",
                     "Gobiiformes",         "Unknowniformes"),
  family         = c("Girellidae",          "Fundulidae",
                     "Gobiidae",            "Unknownidae"),
  genus          = c("Girella",             "Fundulus",
                     "Acanthogobius",       "Nonexistent"),
  species        = c("Girella nigricans",   "Fundulus parvipinnis",
                     "Acanthogobius flavimanus", "Nonexistent taxon"),
  score_original = c(99.1, 97.5, 96.0, 88.0),
  stringsAsFactors = FALSE
)

# ===========================================================================
# Input validation
# ===========================================================================

test_that("non-data.frame input raises an error", {
  expect_error(
    convert_taxonomy_backbone(list(a = 1), target_backbone_id = 11),
    regexp = "data frame"
  )
})

test_that("missing taxon_col raises an informative error", {
  expect_error(
    convert_taxonomy_backbone(.ncbi_match_df, target_backbone_id = 11,
                              taxon_col = "no_such_col",
                              verify_fn = .mock_verify_gbif),
    regexp = "no_such_col"
  )
})

test_that("no rank_system columns in df raises an error", {
  df_no_ranks <- data.frame(taxon_name = "Foo", score = 99)
  expect_error(
    convert_taxonomy_backbone(df_no_ranks, target_backbone_id = 11,
                              rank_system = c("order", "family"),
                              verify_fn   = .mock_verify_gbif),
    regexp = "rank_system"
  )
})

test_that("invalid target_backbone_id raises an error", {
  expect_error(
    convert_taxonomy_backbone(.ncbi_match_df, target_backbone_id = c(11, 4),
                              verify_fn = .mock_verify_gbif),
    regexp = "target_backbone_id"
  )
})

# ===========================================================================
# Rank column updates (per-column fallback)
# ===========================================================================

test_that("family updated for Girella nigricans (NCBI Girellidae -> GBIF Kyphosidae)", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  girella_row <- result[result$taxon_name == "Girella nigricans", ]
  expect_equal(girella_row$family, "Kyphosidae")
})

test_that("order updated for Girella nigricans (NCBI Perciformes -> GBIF Eupercaria)", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  girella_row <- result[result$taxon_name == "Girella nigricans", ]
  expect_equal(girella_row$order, "Eupercaria")
})

test_that("consistent rows are not modified (Fundulus parvipinnis)", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  fund_row <- result[result$taxon_name == "Fundulus parvipinnis", ]
  expect_equal(fund_row$family, "Fundulidae")
  expect_equal(fund_row$order,  "Cyprinodontiformes")
})

# ===========================================================================
# taxonomy_collision values
# ===========================================================================

test_that("collision_col is 'consistent' for unchanged rows", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  fund_collision <- result[result$observation_id == "ESV_002", "taxonomy_collision"]
  expect_equal(fund_collision, "consistent")
  goby_collision <- result[result$observation_id == "ESV_003", "taxonomy_collision"]
  expect_equal(goby_collision, "consistent")
})

test_that("collision_col encodes target backbone and changed columns for Girella", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  girella_collision <- result[result$observation_id == "ESV_001", "taxonomy_collision"]
  # Changed columns are sorted: family, order
  expect_equal(girella_collision, "backbone_11[family,order]")
})

test_that("not-found rows get source_label in collision_col", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  nf_collision <- result[result$observation_id == "ESV_004", "taxonomy_collision"]
  expect_equal(nf_collision, "backbone_4")
})

test_that("not-found rows labelled 'original' when source_backbone_id is NULL", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = NULL,
    verify_fn          = .mock_verify_gbif
  ))
  nf_collision <- result[result$observation_id == "ESV_004", "taxonomy_collision"]
  expect_equal(nf_collision, "original")
})

# ===========================================================================
# taxonomy_backbone column
# ===========================================================================

test_that("backbone_col is target_label for found rows", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  expect_equal(result[result$observation_id == "ESV_001", "taxonomy_backbone"],
               "backbone_11")
  expect_equal(result[result$observation_id == "ESV_002", "taxonomy_backbone"],
               "backbone_11")
})

test_that("backbone_col is source_label for not-found rows", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  expect_equal(result[result$observation_id == "ESV_004", "taxonomy_backbone"],
               "backbone_4")
})

# ===========================================================================
# update_taxon_name
# ===========================================================================

test_that("update_taxon_name = TRUE does not add authority to genus-level taxon_name", {
  # GBIF returns matched_name with author for genus-level entries
  # (e.g. "Atherinops Steindachner,"). The fix derives taxon_name from the
  # parsed classification_path rank column instead, which is always clean.
  .mock_verify_genus_authority <- function(name_list, backbone_id) {
    .make_verified_row(
      "Atherinops",
      "Atherinops Steindachner,",           # authority-laden matched_name
      "Eukaryota|Chordata|Actinopteri|Atheriniformes|Atherinopsidae|Atherinops",
      "kingdom|phylum|class|order|family|genus"
    )
  }
  df_genus <- data.frame(
    observation_id = "ESV_G01",
    taxon_name     = "Atherinops",
    taxon_name_rank = "genus",
    order          = "Atheriniformes",
    family         = "Atherinopsidae",
    genus          = "Atherinops",
    species        = NA_character_,
    stringsAsFactors = FALSE
  )
  result <- convert_taxonomy_backbone(
    df_genus,
    target_backbone_id = 11,
    source_backbone_id = 4,
    update_taxon_name  = TRUE,
    verify_fn          = .mock_verify_genus_authority
  )
  expect_equal(result$taxon_name, "Atherinops")
})

test_that("update_taxon_name = TRUE cleans authority from matched_name", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    update_taxon_name  = TRUE,
    verify_fn          = .mock_verify_gbif
  ))
  # matched_name for Girella nigricans = "Girella nigricans (Ayres, 1860)"
  # clean_taxon_names should strip the authority
  girella_name <- result[result$observation_id == "ESV_001", "taxon_name"]
  expect_equal(girella_name, "Girella nigricans")
})

test_that("update_taxon_name = TRUE saves original to original_col", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    update_taxon_name  = TRUE,
    original_col       = "taxon_name_original",
    verify_fn          = .mock_verify_gbif
  ))
  expect_true("taxon_name_original" %in% names(result))
  expect_equal(result[result$observation_id == "ESV_001", "taxon_name_original"],
               "Girella nigricans")
})

test_that("update_taxon_name = FALSE leaves taxon_col unchanged", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    update_taxon_name  = FALSE,
    verify_fn          = .mock_verify_gbif
  ))
  expect_false("taxon_name_original" %in% names(result))
  # taxon_name should remain the original NCBI name
  expect_equal(result$taxon_name, .ncbi_match_df$taxon_name)
})

# ===========================================================================
# Per-column fallback: NA in target does not overwrite existing value
# ===========================================================================

test_that("rank column with NA in target is left unchanged (per-column fallback)", {
  # Simulate a backbone that returns NA for 'genus' (e.g., GBIF doesn't
  # resolve genus separately for some older entries)
  .mock_verify_no_genus <- function(name_list, backbone_id) {
    df <- .mock_verify_gbif(name_list, backbone_id)
    # Remove genus from classification path for Girella nigricans
    gi <- df$user_supplied_name == "Girella nigricans"
    df$classification_path[gi] <- sub("\\|Girella\\|", "|", df$classification_path[gi])
    df$classification_ranks[gi] <- sub("\\|genus\\|", "|", df$classification_ranks[gi])
    df
  }
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    rank_system        = c("order", "family", "genus", "species"),
    verify_fn          = .mock_verify_no_genus
  ))
  # genus should remain "Girella" (original), not NA
  girella_genus <- result[result$observation_id == "ESV_001", "genus"]
  expect_equal(girella_genus, "Girella")
})

# ===========================================================================
# backbone_cols attribute
# ===========================================================================

test_that("backbone_cols attribute is set on returned data frame", {
  result <- suppressWarnings(convert_taxonomy_backbone(
    .ncbi_match_df,
    target_backbone_id = 11,
    source_backbone_id = 4,
    rank_system        = c("order", "family", "genus", "species"),
    verify_fn          = .mock_verify_gbif
  ))
  bbone <- attr(result, "backbone_cols")
  expect_true(is.list(bbone))
  expect_true("backbone_11_cols" %in% names(bbone))
  expect_setequal(bbone[["backbone_11_cols"]],
                  c("order", "family", "genus", "species"))
})

# ===========================================================================
# Warning behaviour
# ===========================================================================

test_that("warning is issued when rows have inconsistent taxonomy", {
  expect_warning(
    convert_taxonomy_backbone(
      .ncbi_match_df,
      target_backbone_id = 11,
      source_backbone_id = 4,
      verify_fn          = .mock_verify_gbif
    ),
    regexp = "inconsistent taxonomy"
  )
})

test_that("no warning when all rows are consistent or all are found + unchanged", {
  df_consistent <- data.frame(
    taxon_name     = c("Fundulus parvipinnis", "Acanthogobius flavimanus"),
    order          = c("Cyprinodontiformes", "Gobiiformes"),
    family         = c("Fundulidae", "Gobiidae"),
    genus          = c("Fundulus", "Acanthogobius"),
    species        = c("Fundulus parvipinnis", "Acanthogobius flavimanus"),
    score_original = c(97.5, 96.0),
    stringsAsFactors = FALSE
  )
  expect_no_warning(
    convert_taxonomy_backbone(
      df_consistent,
      target_backbone_id = 11,
      source_backbone_id = 4,
      verify_fn          = .mock_verify_gbif
    )
  )
})

# ===========================================================================
# NA taxon names are skipped
# ===========================================================================

test_that("rows with NA taxon_name are skipped without error", {
  df_with_na <- .ncbi_match_df
  df_with_na$taxon_name[2] <- NA_character_

  result <- suppressWarnings(convert_taxonomy_backbone(
    df_with_na,
    target_backbone_id = 11,
    source_backbone_id = 4,
    verify_fn          = .mock_verify_gbif
  ))
  # NA row should have NA in backbone_col and collision_col
  na_row <- result[result$observation_id == "ESV_002", ]
  expect_true(is.na(na_row$taxonomy_backbone))
  expect_true(is.na(na_row$taxonomy_collision))
  # Other rows should still be processed
  girella_row <- result[result$observation_id == "ESV_001", ]
  expect_equal(girella_row$family, "Kyphosidae")
})

# ===========================================================================
# All-NA taxon column early return
# ===========================================================================

test_that("all-NA taxon_col returns df unchanged with a warning", {
  df_all_na <- .ncbi_match_df
  df_all_na$taxon_name <- NA_character_
  expect_warning(
    result <- convert_taxonomy_backbone(
      df_all_na,
      target_backbone_id = 11,
      verify_fn          = .mock_verify_gbif
    ),
    regexp = "NA"
  )
  # Returned df should be identical to input
  expect_equal(result$family, df_all_na$family)
})
