# Offline tests for the two-hypothesis mislabel test (R/reference_mislabel_test.R).

test_that("the copied comb helpers match TaxaLikely's behaviour on a pinned fixture", {
  # Pins this copy of TaxaLikely::.estimate_score_quantum()/.smooth_comb():
  # if the original is corrected and this copy is not, or vice versa, the
  # two packages disagree about the same artefact -- this test makes that
  # divergence fail something.
  x <- rep(c(0, 0.6, 1.2, 1.8, 2.4, 3.0, 3.6), times = c(40, 25, 12, 8, 6, 5, 4))
  expect_equal(.estimate_score_quantum(x), 0.6)
  s <- .smooth_comb(c(1, 1, 1, 2), 0.6)
  expect_equal(s, c(1 - 0.15, 1, 1 + 0.15, 2))
  expect_identical(.smooth_comb(x, 0.6), .smooth_comb(x, 0.6))
  expect_true(is.na(.estimate_score_quantum(stats::rnorm(200))))
  expect_identical(.smooth_comb(c(1, 2), NA_real_), c(1, 2))
})

test_that("submission batches group by prefix and number gap", {
  b <- .mislabel_batch_of(c("AB000100", "AB000150", "AB000400", "MZ1", "AB000151"))
  expect_equal(b[["AB000100"]], b[["AB000150"]])
  expect_equal(b[["AB000150"]], b[["AB000151"]])
  expect_false(b[["AB000100"]] == b[["AB000400"]])
  expect_false(b[["MZ1"]] == b[["AB000100"]])
})

# A small synthetic pool: species A1 (3 batches), species B1 (3 batches),
# both in genus G; reference "MZ900" is listed A1 but is really B1.
.mk_pool <- function() {
  acc <- c("AA100", "AB100", "AC100", "BA100", "BB100", "BC100", "MZ900")
  dep <- data.frame(acc = acc,
                    species = c("A1", "A1", "A1", "B1", "B1", "B1", "A1"),
                    genus = "G", family = "F", class = "C", stringsAsFactors = FALSE)
  dep$batch <- .mislabel_batch_of(dep$acc)[dep$acc]
  pid <- function(i, j) {
    si <- if (acc[i] == "MZ900") "B1" else dep$species[i]
    sj <- if (acc[j] == "MZ900") "B1" else dep$species[j]
    if (si == sj) 100 else 90
  }
  h <- expand.grid(i = seq_along(acc), j = seq_along(acc))
  h <- h[h$i != h$j, ]
  hits <- data.frame(q = acc[h$i], s = acc[h$j], pid = mapply(pid, h$i, h$j),
                     stringsAsFactors = FALSE)
  list(dep = dep, hits = hits)
}

test_that("rank statistics: x, y, d from independent batches; exclude removes deposits", {
  p <- .mk_pool()
  st <- .mislabel_rank_statistics(p$hits, p$dep,
    data.frame(accession = "MZ900", B = "B1"), "species")
  expect_equal(st$x, 90)
  expect_equal(st$x_batches, 3L)
  expect_equal(st$y, 100)
  expect_equal(st$y_batches, 3L)
  expect_equal(st$d, 90)
  expect_equal(st$d_batches, 3L)
  st2 <- .mislabel_rank_statistics(p$hits, p$dep,
    data.frame(accession = "MZ900", B = "B1"), "species", exclude = c("AA100", "AB100"))
  expect_equal(st2$x_batches, 1L)
  expect_equal(st2$d_batches, 1L)
})

test_that("a reference never vouches for itself through its own batch", {
  p <- .mk_pool()
  # add a copy of the mislabel in the SAME batch, listed A1, identical to it
  p$dep <- rbind(p$dep, data.frame(acc = "MZ901", species = "A1", genus = "G", family = "F",
                                   class = "C", batch = NA))
  p$dep$batch <- .mislabel_batch_of(p$dep$acc)[p$dep$acc]
  p$hits <- rbind(p$hits, data.frame(q = c("MZ900", "MZ901"), s = c("MZ901", "MZ900"), pid = 100))
  st <- .mislabel_rank_statistics(p$hits, p$dep, data.frame(accession = "MZ900", B = "B1"), "species")
  expect_equal(st$x, 90)
})

test_that("genus-rank statistics use congeners of OTHER species only", {
  p <- .mk_pool()
  p$dep$genus <- ifelse(p$dep$species == "B1", "H", "G")
  st <- .mislabel_rank_statistics(p$hits, p$dep, data.frame(accession = "MZ900", B = "H"),
                                  "genus")
  # MZ900's own species (A1) is excluded at genus rank, and genus G has no
  # other species, so there is nothing to compare against
  expect_true(is.na(st$x))
  expect_equal(st$x_batches, 0L)
})

# A larger synthetic population for the test itself
.mk_stats <- function(n = 300, seed = 1) {
  set.seed(seed)
  # correct references: x near 100 on a comb, y and d well separated
  x <- 100 - 0.6 * stats::rpois(n, 0.5)
  d <- 100 - 0.6 * (8 + stats::rpois(n, 6))
  y <- d + 0.6 * stats::rpois(n, 1) - 0.6
  s <- data.frame(accession = sprintf("R%04d", seq_len(n)), rank = "species", A = "a", B = "b",
                  x = x, x_batches = 4L, y = pmin(y, 100), y_batches = 4L, d = d, d_batches = 4L,
                  class = "C", stringsAsFactors = FALSE)
  # one clear mislabel: far from its own group, identical to B
  s <- rbind(s, data.frame(accession = "MIS1", rank = "species", A = "a", B = "b", x = 88,
                           x_batches = 10L, y = 100, y_batches = 10L, d = 88.5, d_batches = 10L,
                           class = "C"))
  # one close pair: B within ordinary within-species variation of A
  s <- rbind(s, data.frame(accession = "CLOSE", rank = "species", A = "a", B = "b", x = 99.4,
                           x_batches = 5L, y = 100, y_batches = 5L, d = 99.4, d_batches = 5L,
                           class = "C"))
  # one with thin evidence
  s <- rbind(s, data.frame(accession = "THIN", rank = "species", A = "a", B = "b", x = 88,
                           x_batches = 1L, y = 100, y_batches = 1L, d = 88, d_batches = 1L,
                           class = "C"))
  s
}

test_that("the LR test selects a clear mislabel and keeps close pairs and thin evidence", {
  out <- .mislabel_lr_test(.mk_stats(), rank_system = "species")
  expect_true(out$selected[out$accession == "MIS1"])
  expect_equal(out$status[out$accession == "CLOSE"], "below_separation")
  expect_false(out$selected[out$accession == "CLOSE"])
  expect_equal(out$status[out$accession == "THIN"], "insufficient_evidence")
  expect_true(is.na(out$posterior[out$accession == "THIN"]))
  g <- attr(out, "guard")
  expect_true(g$cutoff[g$rank == "species"] > 0)
  # the guard is learned only from references closer to their own group
  expect_true(is.finite(attr(out, "pi")))
})

test_that("the prior is estimated over the testable references only", {
  s <- .mk_stats()
  # adding many untestable references must not change pi
  extra <- s[rep(which(s$accession == "THIN"), 500), ]
  extra$accession <- sprintf("U%04d", seq_len(nrow(extra)))
  a <- .mislabel_lr_test(s, rank_system = "species")
  b <- .mislabel_lr_test(rbind(s, extra), rank_system = "species")
  expect_equal(attr(a, "pi"), attr(b, "pi"))
})

test_that("each reference is tested at its finest testable rank", {
  s <- .mk_stats()
  sg <- s
  sg$rank <- "genus"
  # MIS1 has no species-rank evidence, but genus-rank evidence
  s$x_batches[s$accession == "MIS1"] <- 0L
  out <- .mislabel_lr_test(rbind(s, sg), rank_system = c("species", "genus"))
  expect_equal(out$rank[out$accession == "MIS1"], "genus")
  expect_equal(out$rank[out$accession == "R0001"], "species")
  expect_equal(sum(out$accession == "MIS1"), 1L)
})

test_that("a rank with too few within-group references is not tested", {
  s <- .mk_stats(n = 10)
  out <- .mislabel_lr_test(s, rank_system = "species", min_within = 50L)
  expect_true(all(out$status == "rank_not_learnable"))
  expect_false(any(out$selected))
})

test_that("two-pass rule and last-references guard set the action", {
  s <- .mk_stats()
  s <- rbind(s, transform(s[s$accession == "MIS1", ], accession = "MIS2"))
  # MIS2 loses its evidence once pass-1 selections are excluded
  stats_fun <- function(ex) {
    z <- s
    if (length(ex)) z$d_batches[z$accession == "MIS2"] <- 1L
    z
  }
  sp <- c(stats::setNames(rep("spX", nrow(s)), s$accession))
  sp[["MIS1"]] <- "lonely"
  out <- .test_reference_mislabels(stats_fun, sp, rank_system = "species")
  # MIS1 selected twice but its species would have no reference left
  expect_equal(out$action[out$accession == "MIS1"], "inspect")
  expect_equal(out$reason[out$accession == "MIS1"], "would_leave_too_few_references")
  # MIS2 selected in pass 1 only
  expect_true(out$selected_pass1[out$accession == "MIS2"])
  expect_equal(out$action[out$accession == "MIS2"], "keep")
  expect_equal(out$reason[out$accession == "MIS2"], "not_selected_in_pass2")
  expect_equal(out$action[out$accession == "CLOSE"], "untested")
  expect_match(attr(out, "rule_key"), "^mislabel_lr_v1\\|ranks=species\\|sep_q=0.95")
  expect_match(attr(out, "rule_key"), "two_pass$")
})

test_that("the test is deterministic", {
  a <- .mislabel_lr_test(.mk_stats(), rank_system = "species")
  b <- .mislabel_lr_test(.mk_stats(), rank_system = "species")
  expect_identical(a, b)
})
