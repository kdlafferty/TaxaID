# test-filter_redundant_hypotheses.R
# Tests for filter_redundant_hypotheses().
# All tests are offline and use small inline data frames.

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

.make_df <- function(...) {
  rows <- list(...)
  data.frame(
    observation_id = vapply(rows, `[[`, character(1), "sid"),
    kingdom = vapply(rows, `[[`, character(1), "kingdom"),
    family = vapply(rows, `[[`, character(1), "family"),
    genus = vapply(rows, `[[`, character(1), "genus"),
    species = vapply(rows, `[[`, character(1), "species"),
    taxon_name_rank = vapply(rows, `[[`, character(1), "rank"),
    score_original = vapply(rows, `[[`, numeric(1), "score"),
    stringsAsFactors = FALSE
  )
}

.ro <- c("kingdom", "family", "genus", "species")

# ---------------------------------------------------------------------------
# Core behaviour: lineage-local redundancy
# ---------------------------------------------------------------------------

test_that("genus row superseded by species in same lineage is dropped", {
  df <- data.frame(
    observation_id = "S1",
    kingdom = "Eukaryota",
    family = "Gobiidae",
    genus = c("Gobius", "Gobius"),
    species = c("Gobius paganellus", NA_character_),
    taxon_name_rank = c("species", "genus"),
    score = c(99, 95),
    stringsAsFactors = FALSE
  )
  out <- filter_redundant_hypotheses(df, rank_system = .ro)
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name_rank, "species")
})

test_that("genus row for DIFFERENT lineage is retained even when another species exists", {
  df <- data.frame(
    observation_id = "S1",
    kingdom = "Eukaryota",
    family = c("Gobiidae", "Gobiidae", "Gobiidae"),
    genus = c("Gobius", "Gobius", "Acanthogobius"),
    species = c("Gobius paganellus", NA, NA),
    taxon_name_rank = c("species", "genus", "genus"),
    score = c(99, 95, 88),
    stringsAsFactors = FALSE
  )
  out <- filter_redundant_hypotheses(df, rank_system = .ro)
  expect_equal(nrow(out), 2L)
  expect_true("species" %in% out$taxon_name_rank)
  expect_true(any(out$genus == "Acanthogobius"))
  expect_false(any(out$genus == "Gobius" & out$taxon_name_rank == "genus"))
})

test_that("family row dropped when both genus and species exist in same lineage", {
  df <- data.frame(
    observation_id = "S1",
    kingdom = "Eukaryota",
    family = "Gobiidae",
    genus = c("Gobius", "Gobius", "Gobius"),
    species = c("Gobius paganellus", NA, NA),
    taxon_name_rank = c("species", "genus", "family"),
    score = c(99, 95, 80),
    stringsAsFactors = FALSE
  )
  out <- filter_redundant_hypotheses(df, rank_system = .ro)
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name_rank, "species")
})

test_that("genus row retained when it has no species-level match in same sample", {
  df <- data.frame(
    observation_id = c("S1", "S1"),
    kingdom = "Eukaryota",
    family = c("Gobiidae", "Leuciscidae"),
    genus = c("Gobius", "Hybognathus"),
    species = c(NA, NA),
    taxon_name_rank = c("genus", "genus"),
    score = c(90, 85),
    stringsAsFactors = FALSE
  )
  out <- filter_redundant_hypotheses(df, rank_system = .ro)
  expect_equal(nrow(out), 2L)
})

# ---------------------------------------------------------------------------
# Redundancy is per observation_id, not global
# ---------------------------------------------------------------------------

test_that("genus row is dropped in S1 but kept in S2 where species absent", {
  df <- data.frame(
    observation_id = c("S1", "S1", "S2"),
    kingdom = "Eukaryota",
    family = "Gobiidae",
    genus = "Gobius",
    species = c("Gobius paganellus", NA, NA),
    taxon_name_rank = c("species", "genus", "genus"),
    score = c(99, 95, 88),
    stringsAsFactors = FALSE
  )
  out <- filter_redundant_hypotheses(df, rank_system = .ro)
  expect_equal(nrow(out), 2L)
  s1_out <- out[out$observation_id == "S1", ]
  s2_out <- out[out$observation_id == "S2", ]
  expect_equal(s1_out$taxon_name_rank, "species")
  expect_equal(s2_out$taxon_name_rank, "genus")
})

# ---------------------------------------------------------------------------
# Edge cases
# ---------------------------------------------------------------------------

test_that("single-row data frame is returned unchanged", {
  df <- data.frame(
    observation_id = "S1", kingdom = "Eukaryota", family = "Gobiidae",
    genus = "Gobius", species = NA_character_,
    taxon_name_rank = "genus", score = 90,
    stringsAsFactors = FALSE
  )
  out <- filter_redundant_hypotheses(df, rank_system = .ro)
  expect_equal(nrow(out), 1L)
})

test_that("rows with unknown taxon_name_rank are retained with a warning", {
  df <- data.frame(
    observation_id = "S1",
    kingdom = "Eukaryota",
    family = "Gobiidae",
    genus = c("Gobius", "Gobius"),
    species = c("Gobius paganellus", NA),
    taxon_name_rank = c("species", "subspecies"), # subspecies not in .ro
    score = c(99, 95),
    stringsAsFactors = FALSE
  )
  expect_warning(
    out <- filter_redundant_hypotheses(df, rank_system = .ro),
    "taxon_name_rank not in rank_system"
  )
  expect_equal(nrow(out), 2L) # subspecies row retained, species row retained
})

test_that("all columns are preserved in output", {
  df <- data.frame(
    observation_id = "S1",
    kingdom = "Eukaryota",
    family = "Gobiidae",
    genus = c("Gobius", "Gobius"),
    species = c("Gobius paganellus", NA),
    taxon_name_rank = c("species", "genus"),
    score = c(99, 95),
    extra_col = c("a", "b"),
    stringsAsFactors = FALSE
  )
  out <- filter_redundant_hypotheses(df, rank_system = .ro)
  expect_true("extra_col" %in% names(out))
})

# ---------------------------------------------------------------------------
# Input validation
# ---------------------------------------------------------------------------

test_that("stops if match_df is not a data frame", {
  expect_error(filter_redundant_hypotheses(list(a = 1)), "`match_df` must be a data frame")
})

test_that("stops if required columns are missing", {
  df <- data.frame(x = 1)
  expect_error(filter_redundant_hypotheses(df), "missing required column")
})

test_that("stops if rank_system is empty", {
  df <- data.frame(observation_id = "S1", taxon_name_rank = "genus", genus = "Gobius")
  expect_error(
    filter_redundant_hypotheses(df, rank_system = character(0)),
    "non-empty character vector"
  )
})

# ---------------------------------------------------------------------------
# Missing-column warning: only a load-bearing (non-finest) gap should warn
# (2026-09-07 -- found via TaxaAssign::join_priors()'s own call, whose
# `likelihoods` input never carries a literal "species" column even when
# "species" is the finest entry in rank_system)
# ---------------------------------------------------------------------------

test_that("no warning when only rank_system's own finest entry lacks a column", {
  # "species" is the finest entry in .ro but has no column here -- provably
  # inert (nothing is ever finer than species, so no row can be superseded
  # by it, and no coarser row's own comparison ever needs it).
  df <- data.frame(
    observation_id = c("S1", "S1"),
    kingdom = "Eukaryota",
    family = c("Gobiidae", "Gobiidae"),
    genus = c("Gobius", "Acanthogobius"),
    taxon_name_rank = c("genus", "genus"),
    score = c(95, 88),
    stringsAsFactors = FALSE
  )
  expect_no_warning(out <- filter_redundant_hypotheses(df, rank_system = .ro))
  expect_equal(nrow(out), 2L)
})

test_that("still warns when a genuinely load-bearing (non-finest) column is missing", {
  # "family" is missing here, and family IS needed as a coarser-or-equal
  # comparison column for any genus-rank redundancy check -- a real gap,
  # not the finest-rank false positive the fix above closes.
  df <- data.frame(
    observation_id = c("S1", "S1"),
    kingdom = "Eukaryota",
    genus = c("Gobius", "Gobius"),
    species = c("Gobius paganellus", NA),
    taxon_name_rank = c("species", "genus"),
    score = c(99, 95),
    stringsAsFactors = FALSE
  )
  expect_warning(
    filter_redundant_hypotheses(df, rank_system = .ro),
    "family"
  )
})
