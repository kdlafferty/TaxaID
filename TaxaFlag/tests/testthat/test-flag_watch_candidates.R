# tests/testthat/test-flag_watch_candidates.R
# The likelihood-side surveillance guarantee (2026-08-26 mixture redesign, D4):
# fires from raw scores alone, never touches consensus columns.

library(testthat)

.make_consensus <- function() {
  data.frame(
    observation_id = c("A1", "A2", "A3", "A4"),
    primary_taxon = c(
      "Perca flavescens", "Perca flavescens",
      "Sander lucioperca", "Neogobius melanostomus"
    ),
    consensus_rank = c("species", "family", "species", "genus"),
    stringsAsFactors = FALSE
  )
}

.make_match <- function() {
  data.frame(
    observation_id = c("A1", "A1", "A2", "A2", "A3", "A3", "A4", "A4"),
    taxon_name = c(
      "Perca flavescens", "Sander lucioperca",
      "Perca flavescens", "Sander lucioperca",
      "Sander lucioperca", "Perca flavescens",
      "Neogobius melanostomus", "Neogobius fluviatilis"
    ),
    score_original = c(
      99.5, 97.0, # A1: winner outscores watch -> no flag
      98.0, 98.0, # A2: watch TIES winner -> flag
      99.0, 96.0, # A3: winner IS the watch species -> no flag
      99.0, 99.4
    ), # A4: watch outscores winner -> flag
    stringsAsFactors = FALSE
  )
}

WATCH <- c("Sander lucioperca", "Neogobius fluviatilis")

test_that("flags tie-or-outscore, skips winner-outscores and watch-is-winner", {
  out <- suppressMessages(flag_watch_candidates(.make_consensus(), .make_match(), WATCH))
  expect_equal(out$watch_flag, c(FALSE, TRUE, FALSE, TRUE))
  expect_equal(out$watch_taxon[2], "Sander lucioperca")
  expect_equal(out$watch_score[4], 99.4)
  expect_equal(out$watch_reference_score[4], 99.0)
  # A3: winner is itself watch-listed -> untouched detail columns
  expect_true(is.na(out$watch_taxon[3]))
})

test_that("score_margin widens the trigger", {
  out <- suppressMessages(flag_watch_candidates(.make_consensus(), .make_match(), WATCH,
    score_margin = 3
  ))
  expect_true(out$watch_flag[1]) # 97.0 >= 99.5 - 3
})

test_that("winner without its own match row falls back to best non-watch score", {
  cons <- data.frame(
    observation_id = "B1", primary_taxon = "Cottus bairdii",
    stringsAsFactors = FALSE
  ) # not in match rows
  m <- data.frame(
    observation_id = c("B1", "B1"),
    taxon_name = c("Perca flavescens", "Sander lucioperca"),
    score_original = c(95, 96), stringsAsFactors = FALSE
  )
  out <- suppressMessages(flag_watch_candidates(cons, m, WATCH))
  expect_true(out$watch_flag) # 96 >= 95 (best non-watch)
  expect_equal(out$watch_reference_score, 95)
})

test_that("no watch candidates and unmatched observations get FALSE with NA detail", {
  cons <- data.frame(
    observation_id = c("C1", "C2"), primary_taxon = "Perca flavescens",
    stringsAsFactors = FALSE
  )
  m <- data.frame(
    observation_id = "C1", taxon_name = "Perca flavescens",
    score_original = 99, stringsAsFactors = FALSE
  )
  out <- suppressMessages(flag_watch_candidates(cons, m, WATCH))
  expect_equal(out$watch_flag, c(FALSE, FALSE))
  expect_true(all(is.na(out$watch_taxon)))
})

test_that("never modifies consensus columns; validates inputs", {
  cons <- .make_consensus()
  out <- suppressMessages(flag_watch_candidates(cons, .make_match(), WATCH))
  expect_identical(out$primary_taxon, cons$primary_taxon)
  expect_identical(out$consensus_rank, cons$consensus_rank)
  expect_error(flag_watch_candidates(cons, .make_match(), character(0)), "watch_taxa")
  expect_error(flag_watch_candidates(cons, .make_match(), WATCH, score_margin = -1), "score_margin")
  expect_error(
    flag_watch_candidates(cons[, "observation_id", drop = FALSE], .make_match(), WATCH),
    "primary_taxon"
  )
})

test_that("an NA winner falls back to the best non-watch score, never an NA flag", {
  # A consensus row the pipeline left unresolved has no winner to look up, so
  # it takes the same fallback as an unreferenced/rank-expanded winner. Before
  # this was guarded, comparing NA elementwise produced NA indices, an NA
  # reference score and finally an NA in a column documented as logical (and
  # an "NA of N observation(s) flagged" message).
  cons <- data.frame(
    observation_id = c("D1", "D2"),
    primary_taxon = c(NA_character_, "Perca flavescens"),
    stringsAsFactors = FALSE
  )
  m <- data.frame(
    observation_id = c("D1", "D1", "D2", "D2"),
    taxon_name = c(
      "Sander lucioperca", "Perca flavescens",
      "Sander lucioperca", "Perca flavescens"
    ),
    score_original = c(99, 98, 97, 99),
    stringsAsFactors = FALSE
  )
  out <- suppressMessages(flag_watch_candidates(cons, m, WATCH))
  expect_false(anyNA(out$watch_flag))
  expect_equal(out$watch_flag, c(TRUE, FALSE))
  expect_equal(out$watch_reference_score, c(98, 99))
})
