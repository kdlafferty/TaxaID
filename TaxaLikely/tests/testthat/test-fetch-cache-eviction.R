# ==============================================================================
# test-fetch-cache-eviction.R
# P5 of the 2026-09-14 cache policy review: eviction of cache generations
# orphaned by a key widening.
#
# The first block is the one that matters. Every deletion in this feature
# rests on a single claim -- "the current key cannot produce this name, so
# nothing can ever hit it" -- and that claim is only true while
# .ref_cache_grammar() and .ref_cache_file() agree. These tests pin them
# together. If a future key widening breaks the first test, the fix is to
# update the grammar IN THE SAME CHANGE, never to relax the test.
# ==============================================================================

# testthat's withr is not a declared dependency of this package, so tests use
# a plain session-temp directory instead of withr::local_tempdir().
.cache_tmpdir <- function() {
  d <- tempfile("taxalikely_cache_")
  dir.create(d)
  d
}

test_that("the grammar accepts every name .ref_cache_file() can produce", {
  grid <- expand.grid(
    name = c("Abudefduf", "Sebastes miniatus", "X-y/z"),
    barcode = c("12S", "MiFishU"),
    min_len = c(100L, 130L),
    max_len = c(600L, 5000L),
    dates = c("none", "both", "min"),
    oor = c(FALSE, TRUE),
    ranks = c("short", "long"),
    prefix = c("", "priority_"),
    taxid = c("none", "1261581"),
    stringsAsFactors = FALSE
  )
  g <- TaxaLikely:::.ref_cache_grammar()

  produced <- vapply(seq_len(nrow(grid)), function(i) {
    r <- grid[i, ]
    basename(TaxaLikely:::.ref_cache_file(
      cache_dir = "/tmp/cache",
      name = r$name,
      barcode_term = if (r$barcode == "MiFishU") c("MiFish", "U") else r$barcode,
      min_len = r$min_len, max_len = r$max_len,
      min_date = if (r$dates == "none") NULL else "1990/01/01",
      max_date = if (r$dates == "both") "2026/12/31" else NULL,
      keep_out_of_range = r$oor,
      max_out_of_range_per_species = 2L,
      max_out_of_range_len = 200000L,
      rank_system = if (r$ranks == "short") {
        c("family", "genus", "species")
      } else {
        c("kingdom", "phylum", "class", "order", "family", "genus", "species")
      },
      prefix = r$prefix,
      taxid = if (r$taxid == "none") NULL else r$taxid
    ))
  }, character(1L))

  unmatched <- produced[!grepl(g, produced)]
  expect_identical(
    unmatched, character(0L),
    info = paste(
      "The cache key and .ref_cache_grammar() have drifted. Names the key",
      "produces but the grammar rejects would be deleted as 'unreachable'",
      "while still live:", paste(utils::head(unmatched, 5L), collapse = ", ")
    )
  )
})

test_that("the grammar rejects the superseded generations it is meant to", {
  g <- TaxaLikely:::.ref_cache_grammar()
  # Real names from the development machine's cache, one per historical
  # generation. None can be produced by the current key.
  expect_false(grepl(g, "Abietinaria_18S_l100_2000_d_meta.rds"))
  expect_false(grepl(g, "Delftia_12S_l100_5000_d_meta.rds"))
  expect_false(grepl(g, "Abudefduf_12S_meta.rds"))
  # ...and accepts the current shape, including the seven-rank system.
  expect_true(grepl(g, "Abudefduf_12S_l100_5000_d_rk-family-genus-species_meta.rds"))
  expect_true(grepl(
    g,
    paste0(
      "Macrhybopsis_MiFishU_l130_210_d_oor1000000_l200000",
      "_rk-kingdom-phylum-class-order-family-genus-species_meta.rds"
    )
  ))
})

test_that(".ref_cache_stem_of() inverts .ref_cache_stem() through the key", {
  for (nm in c("Abudefduf", "Sebastes miniatus", "Foo_l100_200_bar")) {
    for (bc in list("12S", c("MiFish", "U"))) {
      for (oor in c(FALSE, TRUE)) {
        f <- basename(TaxaLikely:::.ref_cache_file(
          "/tmp/c", nm, bc, 100L, 600L, NULL, NULL, oor, 2L, 200000L,
          c("family", "genus", "species")
        ))
        expect_identical(
          TaxaLikely:::.ref_cache_stem_of(f),
          TaxaLikely:::.ref_cache_stem(nm, bc)
        )
      }
    }
  }
})

test_that("a different length window or rank system is NOT unreachable", {
  d <- .cache_tmpdir()
  # Two genuinely different QUERIES for one taxon. A caller may want both.
  file.create(file.path(d, c(
    "Abudefduf_12S_l100_600_d_rk-family-genus-species_meta.rds",
    "Abudefduf_12S_l100_5000_d_rk-family-genus-species_meta.rds",
    "Abudefduf_12S_l100_5000_d_rk-genus-species_meta.rds"
  )))
  expect_identical(TaxaLikely:::.ref_cache_unreachable(d), character(0L))
})

test_that("a taxid-scoped and a name-scoped cache for the same taxon are both reachable", {
  # A name-based query and a txid-based query for the same taxon can return
  # genuinely different sequences (the whole point of the homonym fix) --
  # neither one orphans the other.
  d <- .cache_tmpdir()
  file.create(file.path(d, c(
    "Vertebrata_12S_l100_5000_d_rk-family-genus-species_meta.rds",
    "Vertebrata_12S_l100_5000_d_rk-family-genus-species_txid1261581_meta.rds"
  )))
  expect_identical(TaxaLikely:::.ref_cache_unreachable(d), character(0L))
})

test_that(".ref_cache_stem_of() strips the taxid suffix, keeping the two files one stem", {
  f_name <- basename(TaxaLikely:::.ref_cache_file(
    "/tmp/c", "Vertebrata", "12S", 100L, 5000L, NULL, NULL, FALSE, 2L, 200000L,
    c("family", "genus", "species")
  ))
  f_taxid <- basename(TaxaLikely:::.ref_cache_file(
    "/tmp/c", "Vertebrata", "12S", 100L, 5000L, NULL, NULL, FALSE, 2L, 200000L,
    c("family", "genus", "species"), taxid = "1261581"
  ))
  expect_identical(
    TaxaLikely:::.ref_cache_stem_of(f_name),
    TaxaLikely:::.ref_cache_stem_of(f_taxid)
  )
})

test_that(".ref_cache_unreachable() finds orphans and scopes them by stem", {
  d <- .cache_tmpdir()
  live <- "Abudefduf_12S_l100_5000_d_rk-family-genus-species_meta.rds"
  dead_same <- "Abudefduf_12S_l100_5000_d_meta.rds"
  dead_other <- "Sebastes_12S_l100_5000_d_meta.rds"
  # A taxon whose name PREFIX-matches the first -- prefix matching would
  # wrongly claim this one.
  dead_lookalike <- "Abudefduf_saxatilis_12S_l100_5000_d_meta.rds"
  file.create(file.path(d, c(live, dead_same, dead_other, dead_lookalike)))

  all_dead <- basename(TaxaLikely:::.ref_cache_unreachable(d))
  expect_setequal(all_dead, c(dead_same, dead_other, dead_lookalike))

  scoped <- basename(TaxaLikely:::.ref_cache_unreachable(
    d,
    stem = TaxaLikely:::.ref_cache_stem("Abudefduf", "12S")
  ))
  expect_identical(scoped, dead_same)
})

test_that(".ref_cache_unreachable() ignores the fasta store and checkpoints", {
  d <- .cache_tmpdir()
  dir.create(file.path(d, "fasta"))
  file.create(file.path(d, "fasta", "AB000667_seq.rds"))
  file.create(file.path(d, "coverage_genus_12S_dX_n412_ckpt.rds"))
  file.create(file.path(d, "Abudefduf_12S_l100_5000_d_meta.rds"))
  expect_identical(
    basename(TaxaLikely:::.ref_cache_unreachable(d)),
    "Abudefduf_12S_l100_5000_d_meta.rds"
  )
})

test_that(".ref_cache_evict() deletes the dead, keeps the live, and says so", {
  d <- .cache_tmpdir()
  live <- file.path(d, "Abudefduf_12S_l100_5000_d_rk-family-genus-species_meta.rds")
  dead <- file.path(d, "Abudefduf_12S_l100_5000_d_meta.rds")
  other <- file.path(d, "Sebastes_12S_l100_5000_d_meta.rds")
  file.create(c(live, dead, other))

  stem <- TaxaLikely:::.ref_cache_stem("Abudefduf", "12S")
  expect_message(
    n <- TaxaLikely:::.ref_cache_evict(d, stem),
    "evicted 1 superseded file"
  )
  expect_identical(n, 1L)
  expect_true(file.exists(live))
  expect_false(file.exists(dead))
  expect_true(file.exists(other)) # different taxon, untouched
})

test_that(".ref_cache_evict() leaves oversized files in place", {
  d <- .cache_tmpdir()
  dead <- file.path(d, "Abudefduf_12S_l100_5000_d_meta.rds")
  writeBin(raw(6 * 1024^2), dead)
  stem <- TaxaLikely:::.ref_cache_stem("Abudefduf", "12S")
  expect_message(
    n <- TaxaLikely:::.ref_cache_evict(d, stem),
    "over 5 MB left in place"
  )
  expect_identical(n, 0L)
  expect_true(file.exists(dead))
})

test_that("taxalikely_clear_cache() now reaches the fasta/ store", {
  d <- .cache_tmpdir()
  dir.create(file.path(d, "fasta"))
  file.create(file.path(d, "fasta", "AB000667_seq.rds"))
  file.create(file.path(d, "Abudefduf_12S_l100_5000_d_rk-family-genus-species_meta.rds"))

  out <- suppressMessages(taxalikely_clear_cache(cache_dir = d, dry_run = TRUE))
  expect_true("AB000667_seq.rds" %in% basename(out$path))
  expect_identical(nrow(out), 2L)
})
