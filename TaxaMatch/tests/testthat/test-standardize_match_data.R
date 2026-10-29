# test-standardize_match_data.R
# Tests for standardize_match_data().
# All tests are offline and use small inline data frames.

# ---------------------------------------------------------------------------
# Shared test data
# ---------------------------------------------------------------------------

# Mimics a MiFish eDNA output (subset of real columns)
.mifish <- data.frame(
  TestId = "MiFishU",
  ESVId = c("ESV_001", "ESV_001", "ESV_002"),
  Kingdom = "Eukaryota",
  Phylum = "Chordata",
  Class = "Actinopteri",
  Order = c("Gobiiformes", "Gobiiformes", "Cypriniformes"),
  Family = c("Gobiidae", "Gobiidae", "Leuciscidae"),
  Genus = c("Eucyclogobius", "Eucyclogobius", "Hybognathus"),
  Species = c("Eucyclogobius newberryi", "Eucyclogobius newberryi", NA_character_),
  Accession = c("NC_028288", "MF038886", "NC_031567"),
  PercMatch = c(98.8, 98.2, 92.0),
  stringsAsFactors = FALSE
)

# Minimal data: only Genus + Species ranks
.minimal <- data.frame(
  SampleID = c("S1", "S2"),
  genus = c("Rana", "Bufo"),
  species = c("Rana catesbeiana", NA_character_),
  pct = c(97.5, 85.0),
  stringsAsFactors = FALSE
)

# Already-canonical names (no rename needed)
.already_named <- data.frame(
  observation_id = "S1",
  score_original = 95.0,
  genus = "Homo",
  species = "Homo sapiens",
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

test_that("conflict with existing score_original column raises an error", {
  df <- .mifish
  df$score_original <- 0
  expect_error(
    standardize_match_data(df, observation_id_col = "ESVId", score_col = "PercMatch"),
    regexp = "score_original.*already exists"
  )
})

test_that("empty rank_system vector raises an error", {
  expect_error(
    standardize_match_data(.mifish,
      observation_id_col = "ESVId",
      score_col = "PercMatch",
      rank_system = character(0)
    ),
    regexp = "non-empty character vector"
  )
})

# ===========================================================================
# Core output structure
# ===========================================================================

test_that("output has required canonical columns", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_true(all(c("observation_id", "score_original", "taxon_name", "taxon_name_rank") %in% names(result)))
})

test_that("ESVId is renamed to observation_id and PercMatch to score_original", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_true("observation_id" %in% names(result))
  expect_true("score_original" %in% names(result))
  expect_false("ESVId" %in% names(result))
  expect_false("PercMatch" %in% names(result))
})

test_that("score values are preserved correctly in score_original", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_equal(result$score_original, .mifish$PercMatch)
})

test_that("row count is unchanged", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_equal(nrow(result), nrow(.mifish))
})

test_that("non-renamed columns (TestId, Accession) are retained (lowercased by default)", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_true("testid" %in% names(result))
  expect_true("accession" %in% names(result))
})

# ===========================================================================
# taxon_name derivation
# ===========================================================================

test_that("taxon_name uses Species when non-NA", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  # Row 1: Species = "Eucyclogobius newberryi"
  expect_equal(result$taxon_name[1], "Eucyclogobius newberryi")
  expect_equal(result$taxon_name_rank[1], "species")
})

test_that("taxon_name falls back to Genus when Species is NA", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
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
      score_col = "PercMatch"
    ),
    regexp = "detected rank columns"
  )
  expect_true("taxon_name" %in% names(result))
})

test_that("auto-detection works with lowercase rank column names", {
  result <- suppressMessages(standardize_match_data(
    .minimal,
    observation_id_col = "SampleID",
    score_col = "pct"
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

test_that("already-canonical names (observation_id, score_original) work without error", {
  result <- standardize_match_data(
    .already_named,
    observation_id_col = "observation_id",
    score_col = "score_original",
    rank_system = c("genus", "species")
  )
  expect_equal(result$observation_id, "S1")
  expect_equal(result$score_original, 95.0)
  expect_equal(result$taxon_name, "Homo sapiens")
})

# ===========================================================================
# col_map extra renames
# ===========================================================================

test_that("col_map renames non-standard columns before core processing", {
  df <- .minimal
  names(df)[names(df) == "pct"] <- "PERC_ID" # non-standard score name
  result <- standardize_match_data(
    df,
    observation_id_col = "SampleID",
    score_col = "PERC_ID",
    rank_system = c("genus", "species")
  )
  expect_true("score_original" %in% names(result))
  expect_equal(result$score_original, c(97.5, 85.0))
})

# ===========================================================================
# lowercase_names
# ===========================================================================

test_that("lowercase_names = TRUE (default) lowercases all column names", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species")
  )
  expect_true(all(names(result) == tolower(names(result))))
})

test_that("lowercase_names = FALSE preserves original column casing", {
  result <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId",
    score_col = "PercMatch",
    rank_system = c("Kingdom", "Phylum", "Class", "Order", "Family", "Genus", "Species"),
    lowercase_names = FALSE
  )
  # Mixed-case columns from the source should still be present
  expect_true("Kingdom" %in% names(result))
  expect_true("TestId" %in% names(result))
})

test_that("invalid lowercase_names raises an error", {
  expect_error(
    standardize_match_data(.mifish,
      observation_id_col = "ESVId", score_col = "PercMatch",
      lowercase_names = NA
    ),
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
    observation_id_col = "ESVId",
    score_col = "PercMatch",
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
      score_col = "PercMatch"
    ),
    regexp = "File not found"
  )
})

# ---- a match object must not carry a blank rank value -----------------------
# read.csv() turns an empty cell into "", and a source table routinely leaves a
# rank blank when a match could not resolve it. A blank is not a taxon name;
# left in place it reaches every downstream reader as if it were one.

test_that("standardize_match_data() reads a blank rank value as absent", {
  d <- data.frame(
    ESVId = c("E1", "E2", "E3"),
    PercMatch = c(99, 95, 90),
    Family = c("Gobiidae", "Gobiidae", "Gobiidae"),
    Genus = c("Gobius", "", "   "),
    Species = c("Gobius niger", "", ""),
    stringsAsFactors = FALSE
  )
  out <- suppressMessages(standardize_match_data(
    d, observation_id_col = "ESVId", score_col = "PercMatch",
    rank_system = c("Family", "Genus", "Species")
  ))
  # The rank columns themselves carry NA, not a blank string.
  expect_true(all(is.na(out$genus[2:3])))
  expect_true(all(is.na(out$species[2:3])))
  # And the derived name falls back to the finest rank that is really present.
  expect_equal(out$taxon_name, c("Gobius niger", "Gobiidae", "Gobiidae"))
  expect_equal(out$taxon_name_rank, c("species", "family", "family"))
})

test_that("standardize_match_data() leaves a non-blank rank value untouched", {
  d <- data.frame(
    ESVId = "E1", PercMatch = 99, Family = "Gobiidae",
    Genus = " Gobius ", Species = NA_character_, stringsAsFactors = FALSE
  )
  out <- suppressMessages(standardize_match_data(
    d, observation_id_col = "ESVId", score_col = "PercMatch",
    rank_system = c("Family", "Genus", "Species")
  ))
  expect_equal(out$genus, " Gobius ")
})

# ==============================================================================
# provenance: recording the search behind an imported hit list
# ==============================================================================

# The real CalIntertidal shape: a Jonah Ventures vsearch hit list, whose tool,
# version, reference database and search date exist only in the provider's own
# documentation and so cannot be derived from the table.
.jv_provenance <- list(
  method = "vsearch --usearch_global",
  tool_version = "2.22.1",
  database = "Jonah Ventures 12S reference library",
  database_date = "2024-12-31",
  search_started = "2025-02-14",
  parameters = "query-centric percent identity; hits kept at 100% or within 1% of the top hit"
)

test_that("standardize_match_data attaches provenance as report_params", {
  out <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId", score_col = "PercMatch",
    provenance = .jv_provenance
  )
  rp <- attr(out, "report_params")
  expect_type(rp, "list")
  expect_identical(rp$method, "vsearch --usearch_global")
  expect_identical(rp$tool_version, "2.22.1")
  expect_identical(rp$database_date, "2024-12-31")
  expect_true(grepl("within 1%", rp$parameters, fixed = TRUE))
})

test_that("standardize_match_data attaches nothing when provenance is NULL", {
  out <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId", score_col = "PercMatch"
  )
  expect_null(attr(out, "report_params"))
})

test_that("provenance survives to report_match, which then names the real tool", {
  # The point of the whole record: the published methods sentence names
  # vsearch, not BLAST, and carries no BLAST citation.
  out <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId", score_col = "PercMatch",
    provenance = .jv_provenance
  )
  sec <- report_match(out)
  expect_true(grepl("vsearch", sec$methods, fixed = TRUE))
  expect_false(grepl("BLAST", sec$methods, fixed = TRUE))
  expect_false(any(grepl("BLAST", unlist(sec$citations), fixed = TRUE)))
  expect_true(grepl("2.22.1", sec$methods, fixed = TRUE))
  expect_true(grepl("2024-12-31", sec$methods, fixed = TRUE))
})

test_that("provenance merges into an existing report_params, taking precedence", {
  d <- .mifish
  attr(d, "report_params") <- list(method = "stale", n_samples = 99L)
  out <- standardize_match_data(
    d,
    observation_id_col = "ESVId", score_col = "PercMatch",
    provenance = .jv_provenance
  )
  rp <- attr(out, "report_params")
  expect_identical(rp$method, "vsearch --usearch_global")
  # An unrelated field already present is kept, not discarded.
  expect_identical(rp$n_samples, 99L)
})

test_that("provenance requires every field a methods section needs", {
  for (drop in c("method", "tool_version", "database", "database_date", "search_started")) {
    expect_error(
      standardize_match_data(
        .mifish,
        observation_id_col = "ESVId", score_col = "PercMatch",
        provenance = .jv_provenance[setdiff(names(.jv_provenance), drop)]
      ),
      drop,
      fixed = TRUE
    )
  }
})

test_that("provenance accepts an explicit NA for a field genuinely unknown", {
  # NA is reportable; an absent field is indistinguishable from an oversight.
  prov <- .jv_provenance
  prov$database_date <- NA_character_
  out <- standardize_match_data(
    .mifish,
    observation_id_col = "ESVId", score_col = "PercMatch",
    provenance = prov
  )
  expect_true(is.na(attr(out, "report_params")$database_date))
  # And the methods text stays silent rather than printing "NA".
  sec <- report_match(out)
  expect_false(grepl("Reference database build date", sec$methods, fixed = TRUE))
})

test_that("provenance rejects an unrecognised field rather than dropping it", {
  prov <- .jv_provenance
  prov$tool_verison <- "2.22.1" # typo
  expect_error(
    standardize_match_data(
      .mifish,
      observation_id_col = "ESVId", score_col = "PercMatch",
      provenance = prov
    ),
    "tool_verison",
    fixed = TRUE
  )
})

test_that("provenance rejects a non-list and a multi-value field", {
  expect_error(
    standardize_match_data(
      .mifish,
      observation_id_col = "ESVId", score_col = "PercMatch",
      provenance = "vsearch"
    ),
    "named list"
  )
  prov <- .jv_provenance
  prov$tool_version <- c("2.22.1", "2.23.0")
  expect_error(
    standardize_match_data(
      .mifish,
      observation_id_col = "ESVId", score_col = "PercMatch",
      provenance = prov
    ),
    "single value"
  )
})

test_that("provenance is the LAST formal of standardize_match_data", {
  # New arguments go last so a positional call written against the previous
  # signature cannot silently bind to a different argument.
  fm <- names(formals(standardize_match_data))
  expect_identical(fm[length(fm)], "provenance")
})
