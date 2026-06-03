# test-score_consensus.R

# ==============================================================================
# Helpers
# ==============================================================================

make_match <- function(observation_id, taxon_name, taxon_name_rank, score,
                       genus = NULL, family = NULL, species = NULL) {
  df <- data.frame(
    observation_id       = observation_id,
    taxon_name      = taxon_name,
    taxon_name_rank = taxon_name_rank,
    score_original = score,
    stringsAsFactors = FALSE
  )
  if (!is.null(genus))   df$genus   <- genus
  if (!is.null(family))  df$family  <- family
  if (!is.null(species)) df$species <- species
  df
}

# ==============================================================================
# Basic score filtering
# ==============================================================================

test_that("single species above min_score resolves", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df, min_score = 97,
                         rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_equal(out$consensus_rank, "species")
  expect_true(out$is_resolved)
  expect_equal(out$top_score, 99)
  expect_equal(out$n_retained, 1L)
})

test_that("all hits below min_score returns NA", {
  df <- make_match("s1", "Cottus bairdii", "species", 90,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df, min_score = 97,
                         rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$consensus_taxon))
  expect_equal(out$n_retained, 0L)
})

# ==============================================================================
# Gap filtering
# ==============================================================================

test_that("max_gap keeps only hits within gap of top score", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
               genus = "Cottus", family = "Cottidae"),
    make_match("s1", "Cottus asper", "species", 98.5,
               genus = "Cottus", family = "Cottidae"),
    make_match("s1", "Leptocottus armatus", "species", 95,
               genus = "Leptocottus", family = "Cottidae")
  )
  out <- score_consensus(df, max_gap = 1,
                         rank_system = c("family", "genus", "species"))
  # Top two within 1% gap -> genus-level LCA (both Cottus)
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_equal(out$n_retained, 2L)
  expect_equal(out$n_taxa, 2L)
})

test_that("max_gap = 0 keeps only exact top score", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
               genus = "Cottus", family = "Cottidae"),
    make_match("s1", "Cottus asper", "species", 98.9,
               genus = "Cottus", family = "Cottidae")
  )
  out <- score_consensus(df, max_gap = 0,
                         rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_true(out$is_resolved)
  expect_equal(out$n_retained, 1L)
})

# ==============================================================================
# LCA across genera
# ==============================================================================

test_that("hits from different genera resolve to family", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
               genus = "Cottus", family = "Cottidae"),
    make_match("s1", "Leptocottus armatus", "species", 99,
               genus = "Leptocottus", family = "Cottidae")
  )
  out <- score_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottidae")
  expect_equal(out$consensus_rank, "family")
  expect_false(out$is_resolved)
})

# ==============================================================================
# Rank thresholds
# ==============================================================================

test_that("rank_thresholds caps species to genus when top score below species threshold", {
  df <- make_match("s1", "Cottus bairdii", "species", 96,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df, rank_thresholds = c(species = 97, genus = 95, family = 90),
                         rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_true(out$rank_capped)
  expect_false(out$is_resolved)
})

test_that("rank_thresholds with score meeting species threshold keeps species", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df, rank_thresholds = c(species = 97, genus = 95, family = 90),
                         rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_equal(out$consensus_rank, "species")
  expect_false(out$rank_capped)
})

test_that("rank_thresholds below all thresholds returns NA", {
  df <- make_match("s1", "Cottus bairdii", "species", 85,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df, min_score = 80,
                         rank_thresholds = c(species = 97, genus = 95, family = 90),
                         rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$consensus_taxon))
})

test_that("rank_thresholds caps genus LCA appropriately", {
  # Two Cottus species tie -> LCA = genus, but score only meets family threshold
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 94,
               genus = "Cottus", family = "Cottidae"),
    make_match("s1", "Cottus asper", "species", 94,
               genus = "Cottus", family = "Cottidae")
  )
  out <- score_consensus(df, rank_thresholds = c(species = 97, genus = 95, family = 90),
                         rank_system = c("family", "genus", "species"))
  # LCA is genus (Cottus), but 94 < 95 genus threshold -> cap to family
  expect_equal(out$consensus_taxon, "Cottidae")
  expect_equal(out$consensus_rank, "family")
  expect_true(out$rank_capped)
})

# ==============================================================================
# Whitelist upranking
# ==============================================================================

test_that("whitelist keeps consensus when taxon is in whitelist", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df, whitelist = c("Cottus bairdii", "Cottus asper"),
                         rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus bairdii")
  expect_false(out$whitelist_capped)
})

test_that("whitelist upranks to genus when species not in whitelist", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df, whitelist = c("Cottus", "Leptocottus"),
                         rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_true(out$whitelist_capped)
})

test_that("whitelist returns NA when no rank matches whitelist", {
  df <- make_match("s1", "Cottus bairdii", "species", 99,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df, whitelist = c("Salmo", "Oncorhynchus"),
                         rank_system = c("family", "genus", "species"))
  expect_true(is.na(out$consensus_taxon))
  expect_true(out$whitelist_capped)
})

# ==============================================================================
# Multiple samples
# ==============================================================================

test_that("multiple samples processed independently", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
               genus = "Cottus", family = "Cottidae"),
    make_match("s2", "Cottus asper", "species", 98,
               genus = "Cottus", family = "Cottidae"),
    make_match("s2", "Cottus bairdii", "species", 97,
               genus = "Cottus", family = "Cottidae")
  )
  out <- score_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(nrow(out), 2L)
  expect_equal(out$consensus_taxon[out$observation_id == "s1"], "Cottus bairdii")
  expect_equal(out$consensus_rank[out$observation_id == "s2"], "genus")
})

# ==============================================================================
# Interaction: rank_thresholds + whitelist
# ==============================================================================

test_that("rank_thresholds applied before whitelist", {
  # Species consensus, but top score only meets genus threshold.
  # After rank cap -> genus. Genus IS in whitelist -> no further upranking.
  df <- make_match("s1", "Cottus bairdii", "species", 96,
                   genus = "Cottus", family = "Cottidae")
  out <- score_consensus(df,
                         rank_thresholds = c(species = 97, genus = 95),
                         whitelist = c("Cottus", "Cottidae"),
                         rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
  expect_true(out$rank_capped)
  expect_false(out$whitelist_capped)
})

# ==============================================================================
# Genus derived from binomial (no explicit genus column)
# ==============================================================================

test_that("genus derived from species binomial when genus column absent", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99, family = "Cottidae"),
    make_match("s1", "Cottus asper", "species", 98.5, family = "Cottidae")
  )
  out <- score_consensus(df, max_gap = 1,
                         rank_system = c("family", "genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus")
  expect_equal(out$consensus_rank, "genus")
})

# ==============================================================================
# Input validation
# ==============================================================================

test_that("missing required columns errors", {
  df <- data.frame(observation_id = "s1", taxon_name = "A", stringsAsFactors = FALSE)
  expect_error(score_consensus(df), "missing required column")
})

test_that("non-numeric score errors", {
  df <- data.frame(observation_id = "s1", taxon_name = "A",
                   taxon_name_rank = "species", score_original = "high",
                   stringsAsFactors = FALSE)
  expect_error(score_consensus(df), "must be numeric")
})

test_that("negative max_gap errors", {
  df <- make_match("s1", "A", "species", 99)
  expect_error(score_consensus(df, max_gap = -1), "non-negative")
})

# ==============================================================================
# Edge cases
# ==============================================================================

test_that("duplicate accessions for same taxon counted once in n_taxa", {
  df <- rbind(
    make_match("s1", "Cottus bairdii", "species", 99,
               genus = "Cottus", family = "Cottidae"),
    make_match("s1", "Cottus bairdii", "species", 98.5,
               genus = "Cottus", family = "Cottidae")
  )
  out <- score_consensus(df, rank_system = c("family", "genus", "species"))
  expect_equal(out$n_retained, 2L)
  expect_equal(out$n_taxa, 1L)
  expect_equal(out$consensus_taxon, "Cottus bairdii")
})

test_that("custom score_col works", {
  df <- data.frame(
    observation_id       = "s1",
    taxon_name      = "Cottus bairdii",
    taxon_name_rank = "species",
    pct_identity    = 99,
    genus           = "Cottus",
    stringsAsFactors = FALSE
  )
  out <- score_consensus(df, score_col = "pct_identity",
                         rank_system = c("genus", "species"))
  expect_equal(out$consensus_taxon, "Cottus bairdii")
})
