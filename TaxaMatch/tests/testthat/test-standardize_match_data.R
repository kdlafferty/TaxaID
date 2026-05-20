# test-standardize_match_data.R
# Tests for standardize_match_data().
# All tests are offline and use small inline data frames.

# ---------------------------------------------------------------------------
# Shared test data
# ---------------------------------------------------------------------------

# Mimics a MiFish eDNA output (subset of real columns)
.mifish <- data.frame(
  TestId   = "MiFishU",
  ESVId    = c("ESV_001", "ESV_001", "ESV_002"),
  Kingdom  = "Eukaryota",
  Phylum   = "Chordata",
  Class    = "Actinopteri",
  Order    = c("Gobiiformes", "Gobiiformes", "Cypriniformes"),
  Family   = c("Gobiidae", "Gobiidae", "Leuciscidae"),
  Genus    = c("Eucyclogobius", "Eucyclogobius", "Hybognathus"),
  Species  = c("Eucyclogobius newberryi", "Eucyclogobius newberryi", NA_character_),
  Accession = c("NC_028288", "MF038886", "NC_031567"),
  PercMatch = c(98.8, 98.2, 92.0),
  stringsAsFactors = FALSE
)

# Minimal data: only Genus + Species ranks
.minimal <- data.frame(
  SampleID = c("S1", "S2"),
  genus    = c("Rana", "Bufo"),
  species  = c("Rana catesbeiana", NA_character_),
  pct      = c(97.5, 85.0),
  stringsAsFactors = FALSE
)

# Already-canonical names (no rename needed)
.already_named <- data.frame(
  observation_id = "S1",
  score     = 95.0,
  genus     = "Homo",
  species   = "Homo sapiens",
  stringsAsFactors = FALSE
)

# ===========================================================================
# Input validation
# ===========================================================================

test_that("non-data.frame data raises an error", {
  expect_error(
    standardize_match_data(data = list(a = 1), observation_id_col = "a", score_col = "b"),
    regexp = "data frame"
  )
})

test_that("missing observation_id_col raises an informative error", {
  expect_error(
    standardize_match_data(.mifish, observation_id_col = "NoSuchCol", score_col = "PercMatch"),
    regexp = "NoSuchCol"
  )
})

test_that("missing score_col raises an informative error", {
  expect_error(
    standardize_match_data(.mifish, observation_id_col = "ESVId", score_col = "NoSuchScore"),
    regexp = "NoSuchScore"
  )
})

test_that("non-character observation_id_col raises an error", {
  expect_error(
    standardize_match_data(.mifish, observation_id_col = 1L, score_col = "PercMatch"),
    regexp = "observation_id_col"
  )
})

test_that("conflict with existing observation_id column raises an error", {
  df <- .mifish
  df$observation_id <- "existing"
  expect_error(
    standardize_match_data(df, observation_id_col = "ESVId", score_col = "PercMatch"),
    regexp = "observation_id.*already exists"
  )
})

test_that("conflict with existing score column raises an error", {
  df <- .mifish
  df$score <- 0
  expect_error(
    standardize_match_data(df, observation_id_col = "ESVId", score_col = "PercMatch"),
    regexp = "score.*already exists"
  )
})

test_that("empty rank_system vector raises an error", {
  expect_error(
    standardize_match_data(.mifish,
                           observation_id_col  = "ESVId",
                           score_col      = "PercMatch",
                           rank_system = character(0)),
    regexp = "non-empty character vector"
  )
})

# ===========================================================================
# Core output structure
# ===========================================================================

test_that("output has required canonical columns", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_true(all(c("observation_id", "score", "taxon_name", "taxon_name_rank") %in% names(result)))
})

test_that("ESVId is renamed to observation_id and PercMatch to score", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_true("observation_id" %in% names(result))
  expect_true("score"     %in% names(result))
  expect_false("ESVId"    %in% names(result))
  expect_false("PercMatch" %in% names(result))
})

test_that("score values are preserved correctly", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_equal(result$score, .mifish$PercMatch)
})

test_that("row count is unchanged", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_equal(nrow(result), nrow(.mifish))
})

test_that("non-renamed columns (TestId, Accession) are retained (lowercased by default)", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_true("testid"    %in% names(result))
  expect_true("accession" %in% names(result))
})

# ===========================================================================
# taxon_name derivation
# ===========================================================================

test_that("taxon_name uses Species when non-NA", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  # Row 1: Species = "Eucyclogobius newberryi"
  expect_equal(result$taxon_name[1], "Eucyclogobius newberryi")
  expect_equal(result$taxon_name_rank[1], "species")
})

test_that("taxon_name falls back to Genus when Species is NA", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  # Row 3: Species = NA, Genus = "Hybognathus"
  expect_equal(result$taxon_name[3], "Hybognathus")
  expect_equal(result$taxon_name_rank[3], "genus")
})

# ===========================================================================
# Auto-detection of rank columns
# ===========================================================================

test_that("auto-detection finds standard rank columns (MiFish)", {
  expect_message(
    result <- standardize_match_data(
      .mifish,
      observation_id_col = "ESVId",
      score_col     = "PercMatch"
    ),
    regexp = "detected rank columns"
  )
  expect_true("taxon_name" %in% names(result))
})

test_that("auto-detection works with lowercase rank column names", {
  result <- suppressMessages(standardize_match_data(
    .minimal,
    observation_id_col = "SampleID",
    score_col     = "pct"
  ))
  expect_equal(result$taxon_name[1], "Rana catesbeiana")
  expect_equal(result$taxon_name[2], "Bufo")
})

test_that("auto-detection raises an error when no rank columns present", {
  df <- data.frame(SampleID = "S1", pct = 95, stringsAsFactors = FALSE)
  expect_error(
    standardize_match_data(df, observation_id_col = "SampleID", score_col = "pct"),
    regexp = "No standard taxonomic rank columns"
  )
})

# ===========================================================================
# Already-canonical column names (identity renames)
# ===========================================================================

test_that("already-canonical names (observation_id, score) work without error", {
  result <- standardize_match_data(
    .already_named,
    observation_id_col  = "observation_id",
    score_col      = "score",
    rank_system = c("genus", "species")
  )
  expect_equal(result$observation_id, "S1")
  expect_equal(result$score, 95.0)
  expect_equal(result$taxon_name, "Homo sapiens")
})

# ===========================================================================
# col_map extra renames
# ===========================================================================

test_that("col_map renames non-standard columns before core processing", {
  df <- .minimal
  names(df)[names(df) == "pct"] <- "PERC_ID"  # non-standard score name
  result <- standardize_match_data(
    df,
    observation_id_col  = "SampleID",
    score_col      = "PERC_ID",
    rank_system = c("genus", "species")
  )
  expect_true("score" %in% names(result))
  expect_equal(result$score, c(97.5, 85.0))
})

# ===========================================================================
# lowercase_names
# ===========================================================================

test_that("lowercase_names = TRUE (default) lowercases all column names", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_true(all(names(result) == tolower(names(result))))
})

test_that("lowercase_names = FALSE preserves original column casing", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col   = "ESVId",
    score_col       = "PercMatch",
    rank_system  = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"),
    lowercase_names = FALSE
  )
  # Mixed-case columns from the source should still be present
  expect_true("Kingdom" %in% names(result))
  expect_true("TestId"  %in% names(result))
})

test_that("invalid lowercase_names raises an error", {
  expect_error(
    standardize_match_data(.mifish, observation_id_col = "ESVId", score_col = "PercMatch",
                           lowercase_names = NA),
    regexp = "TRUE or FALSE"
  )
})

# ===========================================================================
# File reading
# ===========================================================================

test_that("file path (CSV) is accepted and parsed correctly", {
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(.mifish, tmp, row.names = FALSE)
  on.exit(unlink(tmp))

  result <- standardize_match_data(
    tmp,
    observation_id_col  = "ESVId",
    score_col      = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_equal(nrow(result), nrow(.mifish))
  expect_true("observation_id" %in% names(result))
})

test_that("non-existent file path raises an error", {
  expect_error(
    standardize_match_data(
      "/no/such/file.csv",
      observation_id_col = "ESVId",
      score_col     = "PercMatch"
    ),
    regexp = "File not found"
  )
})
