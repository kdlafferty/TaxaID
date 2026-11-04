# ==============================================================================
# test-fetch-kingdom-contamination.R
# .resolve_kingdom_contamination(): dropping cross-kingdom homonym rows from
# the taxa that are internally split, against the dominant kingdom of the
# OTHER taxa in the same fetch.
#
# The first two blocks are the ones that matter. The rule exists because a
# within-taxon majority gets this exactly backwards on the real case -- the
# contaminant is 93% of the rows -- so these tests assert which rows SURVIVE,
# not merely how many went. A majority-rule reimplementation passes a
# "26 rows dropped" assertion and fails these.
# ==============================================================================

# One taxon's metadata, as the fetch assembles it: a kingdom per row plus the
# accession that identifies it. Mirrors the shape .resolve_kingdom_contamination()
# sees post-taxonomy-merge; only `kingdom` and the row count matter to it.
.km <- function(..., acc_prefix = "X") {
  k <- unlist(list(...), use.names = FALSE)
  # paste0("m3", integer(0)) is "m3", not character(0), so the empty case needs
  # saying explicitly or a zero-row fixture comes out one row wide.
  if (length(k) == 0L) {
    return(data.frame(acc = character(0), kingdom = character(0),
                      stringsAsFactors = FALSE))
  }
  data.frame(
    acc = paste0(acc_prefix, seq_along(k)),
    kingdom = k,
    stringsAsFactors = FALSE
  )
}

# The real CalIntertidal 12S case: Clevelandia ios (a goby) shares its name
# with nothing, but "Clevelandia" alone also matches Castilleja records
# through the LSU synonym, and the live probe returned 26 Viridiplantae rows
# against 2 genuine Metazoa ones.
.ci_fetch <- function() {
  taxa <- c("Cottus", "Fundulus", "Mugil", "Parablennius",
            "Girella", "Sebastes", "Gillichthys", "Clevelandia")
  meta <- c(
    lapply(seq_len(7), function(i) {
      .km(rep("Metazoa", 5L), acc_prefix = paste0("M", i, "_"))
    }),
    list(.km(rep("Viridiplantae", 26L), rep("Metazoa", 2L), acc_prefix = "C_"))
  )
  list(taxa = taxa, meta = meta)
}

test_that("the Clevelandia split drops the 26 plants and KEEPS the 2 gobies", {
  f <- .ci_fetch()
  expect_message(
    out <- TaxaLikely:::.resolve_kingdom_contamination(f$meta, f$taxa),
    "Clevelandia: dropping 26 of 28 record\\(s\\).*Viridiplantae.*against Metazoa"
  )
  got <- out[[8]]
  expect_identical(nrow(got), 2L)
  # Which rows survived, not just how many: the two Metazoa ones, by accession.
  expect_identical(sort(got$acc), c("C_27", "C_28"))
  expect_true(all(got$kingdom == "Metazoa"))
  # No plant row survived.
  expect_false(any(got$kingdom == "Viridiplantae"))
})

test_that("the within-taxon majority is NOT what decides -- the inversion guard", {
  # 93% of Clevelandia's rows are the contaminant. Any implementation that
  # consults the split taxon's own majority keeps those 26 and deletes the 2
  # real records. This block states that outcome and asserts it does NOT
  # happen, so the inversion cannot be reintroduced quietly.
  f <- .ci_fetch()
  out <- suppressMessages(
    TaxaLikely:::.resolve_kingdom_contamination(f$meta, f$taxa)
  )
  got <- out[[8]]
  expect_false(nrow(got) == 26L)
  expect_false(identical(sort(got$acc), paste0("C_", 1:26)))
  # The clean taxa are untouched either way.
  expect_identical(lapply(out[1:7], nrow), lapply(f$meta[1:7], nrow))
})

test_that("a split taxon casts no vote, so a contaminant cannot pick its own reference", {
  # Here the contaminated taxon holds far more ROWS than the whole clean
  # context. Per-row voting would make Viridiplantae dominant and delete the
  # genuine records; per-taxon voting gives the 3 clean taxa the say.
  taxa <- c("Cottus", "Fundulus", "Mugil", "Clevelandia")
  meta <- list(
    .km(rep("Metazoa", 2L), acc_prefix = "M1_"),
    .km(rep("Metazoa", 2L), acc_prefix = "M2_"),
    .km(rep("Metazoa", 2L), acc_prefix = "M3_"),
    .km(rep("Viridiplantae", 300L), rep("Metazoa", 1L), acc_prefix = "C_")
  )
  out <- suppressMessages(
    TaxaLikely:::.resolve_kingdom_contamination(meta, taxa)
  )
  expect_identical(nrow(out[[4]]), 1L)
  expect_identical(out[[4]]$kingdom, "Metazoa")
})

test_that("a genuinely multi-kingdom fetch (18S-like) drops nothing", {
  # An 18S reference set spans kingdoms by design. No kingdom reaches 90% of
  # the taxa, so there is no reference kingdom and the honest action is to
  # report and keep -- the negative control for the whole rule.
  taxa <- c("Calanus", "Ulva", "Thalassiosira", "Saccharomyces",
            "Mytilus", "Zostera", "Clevelandia")
  meta <- list(
    .km(rep("Metazoa", 4L), acc_prefix = "a"),
    .km(rep("Viridiplantae", 4L), acc_prefix = "b"),
    .km(rep("Chromista", 4L), acc_prefix = "c"),
    .km(rep("Fungi", 4L), acc_prefix = "d"),
    .km(rep("Metazoa", 4L), acc_prefix = "e"),
    .km(rep("Viridiplantae", 4L), acc_prefix = "f"),
    .km(rep("Viridiplantae", 26L), rep("Metazoa", 2L), acc_prefix = "g")
  )
  expect_message(
    out <- TaxaLikely:::.resolve_kingdom_contamination(meta, taxa),
    "CROSS-KINGDOM SPLIT KEPT \\(Clevelandia\\): no reference kingdom.*under the 90% needed"
  )
  expect_identical(out, meta)
})

test_that("the dominance threshold can fail: 90% acts, 80% does not", {
  split_one <- .km(rep("Viridiplantae", 5L), rep("Metazoa", 1L), acc_prefix = "s")
  build <- function(n_meta, n_other) {
    list(
      taxa = c(rep("fish", n_meta), rep("plant", n_other), "Split"),
      meta = c(
        lapply(seq_len(n_meta), function(i) .km(rep("Metazoa", 2L), acc_prefix = paste0("m", i))),
        lapply(seq_len(n_other), function(i) .km(rep("Viridiplantae", 2L), acc_prefix = paste0("p", i))),
        list(split_one)
      )
    )
  }
  # 9 of 10 unambiguous taxa are Metazoa == exactly 90%: acts.
  at <- build(9L, 1L)
  out_at <- suppressMessages(
    TaxaLikely:::.resolve_kingdom_contamination(at$meta, at$taxa)
  )
  expect_identical(nrow(out_at[[11]]), 1L)

  # 8 of 10 == 80%: declines, and says so.
  under <- build(8L, 2L)
  expect_message(
    out_under <- TaxaLikely:::.resolve_kingdom_contamination(under$meta, under$taxa),
    "no reference kingdom.*holds 80% of them"
  )
  expect_identical(out_under[[11]], split_one)
})

test_that("too little context cannot establish a reference kingdom", {
  # Two clean neighbours make any kingdom 100% dominant. That is not evidence,
  # so min_context (3, the same floor train_likelihood_model() uses before it
  # will fit a ring from grouped data) must refuse it.
  taxa <- c("Cottus", "Fundulus", "Clevelandia")
  meta <- list(
    .km(rep("Metazoa", 3L), acc_prefix = "m1"),
    .km(rep("Metazoa", 3L), acc_prefix = "m2"),
    .km(rep("Viridiplantae", 26L), rep("Metazoa", 2L), acc_prefix = "c")
  )
  expect_message(
    out <- TaxaLikely:::.resolve_kingdom_contamination(meta, taxa),
    "no reference kingdom -- 2 unambiguous taxon/taxa.*fewer than the 3 needed"
  )
  expect_identical(out, meta)

  # A single-taxon fetch has no context at all.
  solo <- list(.km(rep("Viridiplantae", 26L), rep("Metazoa", 2L), acc_prefix = "c"))
  expect_identical(
    suppressMessages(TaxaLikely:::.resolve_kingdom_contamination(solo, "Clevelandia")),
    solo
  )
})

test_that("a taxon that is NOT split is never filtered, however much it disagrees", {
  # Disagreeing with the fetch is what a legitimate out-of-kingdom reference
  # looks like; only an internally split taxon is ever touched.
  taxa <- c(paste0("fish", 1:9), "Zostera")
  meta <- c(
    lapply(1:9, function(i) .km(rep("Metazoa", 3L), acc_prefix = paste0("m", i))),
    list(.km(rep("Viridiplantae", 7L), acc_prefix = "z"))
  )
  expect_silent(
    out <- TaxaLikely:::.resolve_kingdom_contamination(meta, taxa)
  )
  expect_identical(out, meta)
  expect_identical(nrow(out[[10]]), 7L)
})

test_that("a row with no resolved kingdom is kept", {
  # Absence of a kingdom is not evidence of belonging to another one.
  taxa <- c("Cottus", "Fundulus", "Mugil", "Clevelandia")
  meta <- list(
    .km(rep("Metazoa", 3L), acc_prefix = "m1"),
    .km(rep("Metazoa", 3L), acc_prefix = "m2"),
    .km(rep("Metazoa", 3L), acc_prefix = "m3"),
    .km("Viridiplantae", "Viridiplantae", NA_character_, "", "Metazoa",
        acc_prefix = "c")
  )
  out <- suppressMessages(
    TaxaLikely:::.resolve_kingdom_contamination(meta, taxa)
  )
  got <- out[[4]]
  expect_identical(nrow(got), 3L)
  expect_identical(sort(got$acc), c("c3", "c4", "c5"))
})

test_that("a taxon losing every record is named as such", {
  taxa <- c("Cottus", "Fundulus", "Mugil", "Castilleja")
  meta <- list(
    .km(rep("Metazoa", 3L), acc_prefix = "m1"),
    .km(rep("Metazoa", 3L), acc_prefix = "m2"),
    .km(rep("Metazoa", 3L), acc_prefix = "m3"),
    .km(rep("Viridiplantae", 4L), rep("Fungi", 1L), acc_prefix = "c")
  )
  expect_message(
    out <- TaxaLikely:::.resolve_kingdom_contamination(meta, taxa),
    "EVERY record went; this taxon now contributes none"
  )
  expect_identical(nrow(out[[4]]), 0L)
})

test_that("no kingdom column, empty and NULL entries are all handled", {
  taxa <- c("Cottus", "Fundulus", "Mugil", "Clevelandia")
  no_k <- list(
    data.frame(acc = "a1", stringsAsFactors = FALSE),
    data.frame(acc = "a2", stringsAsFactors = FALSE),
    data.frame(acc = "a3", stringsAsFactors = FALSE),
    data.frame(acc = "a4", stringsAsFactors = FALSE)
  )
  expect_identical(
    TaxaLikely:::.resolve_kingdom_contamination(no_k, taxa), no_k
  )

  mixed <- list(
    .km(rep("Metazoa", 3L), acc_prefix = "m1"),
    NULL,
    .km(character(0), acc_prefix = "m3"),
    .km(rep("Viridiplantae", 26L), rep("Metazoa", 2L), acc_prefix = "c")
  )
  # Only one voting taxon survives the NULL and the empty frame, so there is
  # too little context and nothing is dropped.
  expect_message(
    out <- TaxaLikely:::.resolve_kingdom_contamination(mixed, taxa),
    "fewer than the 3 needed"
  )
  expect_identical(nrow(out[[4]]), 28L)

  expect_identical(
    TaxaLikely:::.resolve_kingdom_contamination(list(), character(0)), list()
  )
})

test_that("the verdict does not depend on the order the taxa arrive in", {
  # The reference kingdom is a property of the whole fetch, so a reshuffle --
  # which is what a different cache state amounts to -- must not change it.
  f <- .ci_fetch()
  base <- suppressMessages(
    TaxaLikely:::.resolve_kingdom_contamination(f$meta, f$taxa)
  )
  ord <- c(8L, 3L, 1L, 6L, 2L, 7L, 4L, 5L)
  shuf <- suppressMessages(
    TaxaLikely:::.resolve_kingdom_contamination(f$meta[ord], f$taxa[ord])
  )
  expect_identical(shuf[[1]], base[[8]])
  expect_identical(lapply(shuf, nrow)[order(ord)], lapply(base, nrow))
})
