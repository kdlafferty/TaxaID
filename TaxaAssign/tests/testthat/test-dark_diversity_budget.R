# tests/testthat/test-dark_diversity_budget.R
# Per-clade dark diversity: each unrecorded candidate gets min(1, N*/K) * D.

.sing <- function(n = 4, genus = "Gen1", family = "Fam1", theta = 1e-5) {
  data.frame(taxon_name = paste0("s", seq_len(n)), alpha = theta * 1e5, beta = (1 - theta) * 1e5,
    genus = genus, family = family, stringsAsFactors = FALSE)
}
.cand <- function(k, genus = "Gen1", family = "Fam1") {
  data.frame(taxon_name = paste0("c", seq_len(k)), genus = genus, family = family, stringsAsFactors = FALSE)
}
.pm <- function(out) out$group_prior_alpha / (out$group_prior_alpha + out$group_prior_beta)

test_that("4 missing species shared among 10 candidates: each gets 0.4 * D", {
  out <- .compute_dark_diversity_groups(.cand(10), .sing(4), global_singleton_mean = 1e-5)
  expect_equal(.pm(out), rep(0.4 * 1e-5, 10), tolerance = 1e-9)
})

test_that("fewer candidates than missing species: capped at one species' share, remainder to the ring", {
  out <- .compute_dark_diversity_groups(.cand(2), .sing(4), global_singleton_mean = 1e-5)
  expect_equal(.pm(out), rep(1e-5, 2), tolerance = 1e-9)
  b <- attr(out, "dark_budget")
  expect_equal(b$remainder[b$rank == "genus" & b$clade == "Gen1"], 2 * 1e-5, tolerance = 1e-9)
})

test_that("total allotted to a clade never exceeds its missing-species mass", {
  for (k in c(1, 3, 4, 10, 50)) {
    out <- .compute_dark_diversity_groups(.cand(k), .sing(4), global_singleton_mean = 1e-5)
    b <- attr(out, "dark_budget")
    g <- b[b$rank == "genus", ]
    expect_lte(sum(.pm(out)) + g$remainder, g$N * g$D + 1e-15)
  }
})

test_that("a genus with no singletons borrows from its family, shrunk", {
  s <- .sing(4, genus = "Gen1")
  c2 <- .cand(2, genus = "Gen2")
  out <- .compute_dark_diversity_groups(c2, s, global_singleton_mean = 1e-5)
  b <- attr(out, "dark_budget")
  expect_equal(b$f1[b$rank == "genus" & b$clade == "Gen2"], 0)
  expect_gt(b$N[b$rank == "genus" & b$clade == "Gen2"], 0)
  expect_true(all(.pm(out) > 0))
})

test_that("evidence-priced taxa use up part of the clade's budget", {
  ev <- data.frame(taxon_name = "e1", w = 1, genus = "Gen1", family = "Fam1")
  out <- .compute_dark_diversity_groups(.cand(10), .sing(4), global_singleton_mean = 1e-5, evidence_df = ev)
  expect_equal(.pm(out), rep(0.3 * 1e-5, 10), tolerance = 1e-9)
})

test_that("a candidate with no taxonomy is left to the global floor", {
  c0 <- data.frame(taxon_name = "x", genus = NA_character_, family = NA_character_)
  out <- .compute_dark_diversity_groups(c0, .sing(4), global_singleton_mean = 1e-5)
  expect_true(is.na(out$group_prior_alpha))
  expect_equal(out$dark_diversity_group, "no_phylum")
})
