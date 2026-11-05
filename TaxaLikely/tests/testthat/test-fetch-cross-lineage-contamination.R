# ==============================================================================
# test-fetch-cross-lineage-contamination.R
# .resolve_cross_lineage_contamination(): dropping homonym rows from the groups
# that are internally split, against the dominant organism of the OTHER groups
# in the same fetch.
#
# Ported from the kingdom-only version this replaces. The first blocks are the
# ones that matter: the rule exists because a within-group majority gets the
# real case exactly backwards -- the contaminant is 93% of the rows -- so these
# assert which rows SURVIVE, not merely how many went. A majority-rule
# reimplementation passes a "26 rows dropped" assertion and fails these.
#
# It now runs on the ASSEMBLED frame, grouped by queried_taxon, so priority
# rows are judged and vote like any other.
# ==============================================================================

# One group's rows: a "kingdom|phylum|class" lineage per row plus the accession
# that identifies it. "" means the rank did not resolve, which is ordinary --
# NCBI assigns no kingdom to several algal and ciliate groups.
.grp <- function(taxon, lineages, acc_prefix) {
  # character(0) in, zero rows out: paste0("x", integer(0)) is "x", not
  # character(0), so the empty case has to be said explicitly or a zero-row
  # fixture comes out one row wide.
  if (length(lineages) == 0L) {
    return(data.frame(
      queried_taxon = character(0), acc = character(0),
      kingdom = character(0), phylum = character(0), class = character(0),
      stringsAsFactors = FALSE
    ))
  }
  parts <- strsplit(lineages, "|", fixed = TRUE)
  pick <- function(i) {
    v <- vapply(parts, function(x) if (length(x) >= i) x[[i]] else "", character(1L))
    v[!nzchar(v)] <- NA_character_
    v
  }
  data.frame(
    queried_taxon = taxon,
    acc = paste0(acc_prefix, seq_along(lineages)),
    kingdom = pick(1L), phylum = pick(2L), class = pick(3L),
    stringsAsFactors = FALSE
  )
}
.fetch <- function(...) do.call(rbind, Filter(Negate(is.null), list(...)))

FISH <- "Metazoa|Chordata|Actinopteri"
ALGA <- "Viridiplantae|Chlorophyta|Ulvophyceae"
resolve <- function(meta, ...) TaxaLikely:::.resolve_cross_lineage_contamination(meta, ...)

# The real CalIntertidal 12S case: "Clevelandia" alone also matches Castilleja
# records through the LSU synonym, and the live probe returned 26 Viridiplantae
# rows against 2 genuine Metazoa ones.
.ci_fetch <- function() {
  ctx <- lapply(seq_len(7), function(i) {
    .grp(paste0("Fish", i), rep(FISH, 5L), paste0("M", i, "_"))
  })
  do.call(.fetch, c(ctx, list(
    .grp("Clevelandia", c(rep(ALGA, 26L), rep(FISH, 2L)), "C_")
  )))
}

test_that("the Clevelandia split drops the 26 plants and KEEPS the 2 gobies", {
  expect_message(
    out <- resolve(.ci_fetch()),
    "Clevelandia: dropping 26 of 28 record\\(s\\)"
  )
  got <- out$meta[out$meta$queried_taxon == "Clevelandia", , drop = FALSE]
  expect_identical(nrow(got), 2L)
  # WHICH rows survived, by accession, not just how many.
  expect_identical(sort(got$acc), c("C_27", "C_28"))
  expect_true(all(got$class == "Actinopteri"))
  expect_false(any(got$class == "Ulvophyceae"))
  # The dropped accessions come back so the dry run can prune its per-taxon
  # counts; without them the two halves of one report disagree.
  expect_identical(length(out$dropped_acc), 26L)
  expect_false(any(c("C_27", "C_28") %in% out$dropped_acc))
})

test_that("the within-group majority is NOT what decides -- the inversion guard", {
  # 26 of 28 Clevelandia rows are the contaminant. A majority rule inside the
  # group keeps the plants and drops the gobies: the exact inversion.
  out <- suppressMessages(resolve(.ci_fetch()))
  got <- out$meta[out$meta$queried_taxon == "Clevelandia", , drop = FALSE]
  expect_true(all(got$kingdom == "Metazoa"))
  expect_identical(nrow(out$meta), 7L * 5L + 2L)
})

test_that("a split group casts no vote, so a contaminant cannot pick its own reference", {
  # Two fish groups and one split group. If the split group voted, its 26 plant
  # rows would make Viridiplantae look like a contender.
  meta <- .fetch(
    .grp("Fish1", rep(FISH, 5L), "A_"),
    .grp("Fish2", rep(FISH, 5L), "B_"),
    .grp("Fish3", rep(FISH, 5L), "D_"),
    .grp("Clevelandia", c(rep(ALGA, 26L), rep(FISH, 2L)), "C_")
  )
  out <- suppressMessages(resolve(meta))
  got <- out$meta[out$meta$queried_taxon == "Clevelandia", , drop = FALSE]
  expect_identical(sort(got$acc), c("C_27", "C_28"))
})

test_that("a kingdom-blind split is caught at class -- the new capability", {
  # Eisenia: a brown alga (Ochrophyta, which NCBI gives no kingdom) and an
  # earthworm. The kingdom-only rule this replaces could not see this at all,
  # because one side has no kingdom to compare.
  meta <- .fetch(
    .grp("Worm1", rep("Metazoa|Annelida|Clitellata", 4L), "W1_"),
    .grp("Worm2", rep("Metazoa|Annelida|Clitellata", 4L), "W2_"),
    .grp("Worm3", rep("Metazoa|Annelida|Clitellata", 4L), "W3_"),
    .grp("Eisenia", c("|Ochrophyta|Phaeophyceae", "|Ochrophyta|Phaeophyceae",
                      "Metazoa|Annelida|Clitellata"), "E_")
  )
  expect_message(
    out <- resolve(meta),
    "Eisenia: dropping 2 of 3 record\\(s\\)"
  )
  got <- out$meta[out$meta$queried_taxon == "Eisenia", , drop = FALSE]
  expect_identical(got$acc, "E_3")
  expect_identical(sort(out$dropped_acc), c("E_1", "E_2"))
})

test_that("a within-class split is a revision and is NEVER filtered", {
  # Mytilidae against Modiolidae, both Bivalvia: the 23-case population the
  # oracle holds back. Family differs, class does not, so there is no split to
  # resolve and nothing is dropped.
  meta <- .fetch(
    .grp("Mussel1", rep("Metazoa|Mollusca|Bivalvia", 4L), "S1_"),
    .grp("Mussel2", rep("Metazoa|Mollusca|Bivalvia", 4L), "S2_"),
    .grp("Mussel3", rep("Metazoa|Mollusca|Bivalvia", 4L), "S3_"),
    .grp("Modiolus", rep("Metazoa|Mollusca|Bivalvia", 6L), "R_")
  )
  out <- resolve(meta)
  expect_identical(nrow(out$meta), nrow(meta))
  expect_identical(out$dropped_acc, character(0L))
})

test_that("a genuinely multi-organism fetch (18S-like) drops nothing", {
  meta <- .fetch(
    .grp("Anim", rep(FISH, 3L), "A_"),
    .grp("Plant", rep(ALGA, 3L), "P_"),
    .grp("Fung", rep("Fungi|Ascomycota|Dothideomycetes", 3L), "F_"),
    .grp("Cil", rep("|Ciliophora|Oligohymenophorea", 3L), "L_"),
    .grp("Split", c(FISH, ALGA), "S_")
  )
  expect_message(out <- resolve(meta), "CROSS-LINEAGE SPLIT KEPT")
  expect_identical(nrow(out$meta), nrow(meta))
  expect_identical(out$dropped_acc, character(0L))
})

test_that("the dominance threshold can fail: 90% acts, 80% does not", {
  build <- function(n_fish, n_other) {
    ctx <- c(
      lapply(seq_len(n_fish), function(i) .grp(paste0("F", i), FISH, paste0("F", i, "_"))),
      lapply(seq_len(n_other), function(i) .grp(paste0("O", i), ALGA, paste0("O", i, "_")))
    )
    do.call(.fetch, c(ctx, list(.grp("Split", c(FISH, ALGA), "S_"))))
  }
  # 9 of 10 unambiguous groups are fish: at the bar, so it acts.
  at_bar <- suppressMessages(resolve(build(9L, 1L)))
  expect_identical(length(at_bar$dropped_acc), 1L)
  # 8 of 10: under the bar, so nothing is dropped.
  under <- suppressMessages(resolve(build(8L, 2L)))
  expect_identical(under$dropped_acc, character(0L))
  expect_identical(nrow(under$meta), nrow(build(8L, 2L)))
})

test_that("too little context cannot establish a reference organism", {
  meta <- .fetch(
    .grp("Fish1", FISH, "A_"),
    .grp("Fish2", FISH, "B_"),
    .grp("Split", c(FISH, ALGA), "S_")
  )
  expect_message(out <- resolve(meta), "fewer than the 3 needed")
  expect_identical(out$dropped_acc, character(0L))
})

test_that("a group that is NOT split is never filtered, however much it disagrees", {
  meta <- .fetch(
    .grp("Fish1", rep(FISH, 3L), "A_"),
    .grp("Fish2", rep(FISH, 3L), "B_"),
    .grp("Fish3", rep(FISH, 3L), "D_"),
    .grp("PureAlga", rep(ALGA, 5L), "P_")
  )
  out <- resolve(meta)
  expect_identical(nrow(out$meta), nrow(meta))
  expect_identical(out$dropped_acc, character(0L))
})

test_that("a row that declares none of the comparison ranks is kept", {
  meta <- .fetch(
    .grp("Fish1", rep(FISH, 3L), "A_"),
    .grp("Fish2", rep(FISH, 3L), "B_"),
    .grp("Fish3", rep(FISH, 3L), "D_"),
    .grp("Split", c(FISH, ALGA, "||"), "S_")
  )
  out <- suppressMessages(resolve(meta))
  got <- out$meta[out$meta$queried_taxon == "Split", , drop = FALSE]
  expect_true("S_3" %in% got$acc)
  expect_false("S_2" %in% got$acc)
})

test_that("a group losing every record is named as such", {
  meta <- .fetch(
    .grp("Fish1", rep(FISH, 3L), "A_"),
    .grp("Fish2", rep(FISH, 3L), "B_"),
    .grp("Fish3", rep(FISH, 3L), "D_"),
    .grp("AllAlga", c(ALGA, "Viridiplantae|Chlorophyta|Chlorophyceae"), "P_")
  )
  expect_message(
    out <- resolve(meta),
    "EVERY record went; this taxon now contributes none"
  )
  expect_false(any(out$meta$queried_taxon == "AllAlga"))
})

test_that("a missing rank column, zero rows and NULL are all handled", {
  expect_identical(resolve(NULL)$meta, NULL)
  z <- .grp("X", character(0), "Z_")
  expect_identical(nrow(resolve(z)$meta), 0L)
  # No comparison rank at all -> nothing to compare, returned untouched.
  bare <- data.frame(queried_taxon = c("a", "b"), acc = c("1", "2"),
    stringsAsFactors = FALSE)
  expect_identical(resolve(bare)$meta, bare)
  # No grouping column -> likewise untouched, rather than treated as one group.
  nogrp <- data.frame(acc = c("1", "2"), kingdom = c("Metazoa", "Fungi"),
    stringsAsFactors = FALSE)
  expect_identical(resolve(nogrp)$meta, nogrp)
})

test_that("the verdict does not depend on the order the groups arrive in", {
  meta <- .ci_fetch()
  shuffled <- meta[rev(seq_len(nrow(meta))), , drop = FALSE]
  a <- suppressMessages(resolve(meta))
  b <- suppressMessages(resolve(shuffled))
  expect_identical(sort(a$dropped_acc), sort(b$dropped_acc))
  expect_identical(sort(a$meta$acc), sort(b$meta$acc))
})


test_that("the missing-queried_taxon guard warns and reports, rather than skipping silently", {
  # This guard is unreachable through fetch_ncbi_reference_sequences(), because
  # queried_taxon is stamped at assembly on every path. It is extracted so it
  # can be triggered at all: a guard no test can fire is not a guard.
  ok <- data.frame(queried_taxon = "a", acc = "1", stringsAsFactors = FALSE)
  expect_silent(res <- TaxaLikely:::.warn_if_no_queried_taxon(ok))
  expect_true(res)

  missing <- data.frame(acc = "1", stringsAsFactors = FALSE)
  expect_warning(
    res <- TaxaLikely:::.warn_if_no_queried_taxon(missing),
    "queried_taxon is absent"
  )
  # expect_warning() returns the CONDITION, not the value, so the result is
  # captured by assigning inside the expectation rather than around it.
  expect_false(res)

  # And it says the checks were SKIPPED, not merely that something was odd:
  # the caller's attribute is absent afterwards, and the message has to say so.
  expect_warning(
    TaxaLikely:::.warn_if_no_queried_taxon(missing),
    "taxa_without_sequences"
  )
  expect_warning(TaxaLikely:::.warn_if_no_queried_taxon(NULL), "queried_taxon is absent")
})
