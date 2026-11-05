# .cap_hits_keeping_ties(): the hit caps must not split a tie.
#
# blast_sequences() applies two caps -- max_hits_per_taxon per (query, taxon)
# and max_hits per query. Both cut the hit list, and both used
# utils::head(order(-pident)). order() is STABLE, so hits tied at the boundary
# were kept or dropped by their position in the BLAST output: the retained set
# depended on input row order rather than on the data.
#
# Measured on Mugu's saved hits (622 ASVs, one read, no network): of the 93 ASVs
# the per-query cap acted on, 89 had the cut land inside a run of equal
# identities and 48 had all twenty kept hits at a single identity, median
# lowest-kept identity 98.99. So this was splitting ties among near-perfect
# matches in almost every case where it fired.

cap <- function(...) TaxaMatch:::.cap_hits_keeping_ties(...)

# acc is the identity of a row, so assertions can name WHICH hits survived
# rather than only how many.
hits <- function(pident, acc = NULL) {
  data.frame(
    acc = acc %||% paste0("A", seq_along(pident)),
    pident = pident, stringsAsFactors = FALSE
  )
}
`%||%` <- function(x, y) if (is.null(x)) y else x


test_that("a tie AT the boundary is kept whole, so the result exceeds max_n", {
  # Ranks 5 and 6 are both 99.0: a row-count cut at 5 keeps one and drops the
  # other by input position. This is the block that fails under head().
  h <- hits(c(100, 99.9, 99.8, 99.7, 99.0, 99.0, 98.0), paste0("A", 1:7))
  out <- cap(h, 5L)
  expect_gt(nrow(out), 5L)
  expect_identical(nrow(out), 6L)
  expect_identical(sort(out$acc), paste0("A", 1:6))
  # A5 and A6 are tied; neither may be preferred over the other.
  expect_true(all(c("A5", "A6") %in% out$acc))
})

test_that("the retained set does not depend on input row order", {
  # The property, stated directly: a count-based cap fails this.
  h <- hits(c(100, 99.9, 99.8, 99.7, 99.0, 99.0, 98.0), paste0("A", 1:7))
  base <- sort(cap(h, 5L)$acc)
  set.seed(1)
  for (i in 1:12) {
    perm <- h[sample(nrow(h)), , drop = FALSE]
    expect_identical(sort(cap(perm, 5L)$acc), base)
  }
  # And explicitly with the tied pair swapped, which is the minimal case.
  swapped <- h[c(1:4, 6, 5, 7), , drop = FALSE]
  expect_identical(sort(cap(swapped, 5L)$acc), base)
})

test_that("no tie at the boundary keeps exactly max_n, so the fix does not widen every result", {
  h <- hits(c(100, 99.9, 99.8, 99.7, 99.6, 99.0, 98.0))
  out <- cap(h, 5L)
  expect_identical(nrow(out), 5L)
  expect_identical(sort(out$acc), paste0("A", 1:5))
})

test_that("a tie BELOW the boundary is still cut", {
  # Ranks 6 and 7 tie, but the cut is at 5 and rank 5 is unique: the rule keeps
  # ties with the LAST HIT KEPT, not every tie anywhere in the list.
  h <- hits(c(100, 99.9, 99.8, 99.7, 99.6, 99.0, 99.0))
  out <- cap(h, 5L)
  expect_identical(nrow(out), 5L)
  expect_false(any(c("A6", "A7") %in% out$acc))
})

test_that("a tie spanning the whole window fabricates nothing", {
  # Every hit at one identity: all are kept, and the result never exceeds the
  # rows supplied. This is the max_target_seqs ceiling holding.
  h <- hits(rep(100, 8))
  out <- cap(h, 5L)
  expect_identical(nrow(out), 8L)
  expect_identical(sort(out$acc), sort(h$acc))
  # Fewer rows than the cap: returned untouched, not padded.
  expect_identical(nrow(cap(hits(rep(100, 3)), 5L)), 3L)
})

test_that("degenerate max_n and empty input are returned untouched", {
  h <- hits(c(100, 99, 98))
  expect_identical(nrow(cap(h, NULL)), 3L)
  expect_identical(nrow(cap(h, NA_integer_)), 3L)
  z <- h[0L, , drop = FALSE]
  expect_identical(nrow(cap(z, 5L)), 0L)
})

test_that("the per-taxon cap is a HARD count with a deterministic tie-break", {
  # Deliberately different from the per-query cap. A tie here is between
  # deposits of ONE taxon -- repeated submissions of the same species, which is
  # what this cap exists to collapse -- so keeping them would restore the
  # crowding-out of real congeners the cap prevents. What must not depend on
  # BLAST output row order is WHICH tied deposit survives.
  h <- data.frame(
    sacc = c("ACC_9", "ACC_2", "ACC_5"),
    pident = c(100, 100, 99),
    stringsAsFactors = FALSE
  )
  out <- TaxaMatch:::.cap_hits_per_taxon(h, 1L)
  expect_identical(nrow(out), 1L)
  # ACC_2 wins the tie: identity first, then accession. Not the first row given.
  expect_identical(out$sacc, "ACC_2")

  # The property: any input order gives the same survivor.
  set.seed(2)
  for (i in 1:12) {
    perm <- h[sample(nrow(h)), , drop = FALSE]
    expect_identical(TaxaMatch:::.cap_hits_per_taxon(perm, 1L)$sacc, "ACC_2")
  }
  # And it never exceeds the count, however deep the tie.
  deep <- data.frame(sacc = paste0("ACC_", 1:50), pident = rep(100, 50),
                     stringsAsFactors = FALSE)
  expect_identical(nrow(TaxaMatch:::.cap_hits_per_taxon(deep, 1L)), 1L)
})
