# build_sequence_matrix requires DECIPHER (Bioconductor -- Suggests).
# All online tests are guarded. Input validation and new-parameter offline tests
# run without DECIPHER.

# ---------------------------------------------------------------------------
# Shared synthetic sequences (120 bp, different enough to form valid pairs)
# ---------------------------------------------------------------------------
.seq_a <- paste(rep("ATGCATGCATGC", 10), collapse = "") # 120 bp
.seq_b <- paste(rep("ATGCATGCATGG", 10), collapse = "") # 120 bp, 1 diff/12
.seq_c <- paste(rep("ATGCATGCATCC", 10), collapse = "") # 120 bp, 2 diff/12

test_that("build_sequence_matrix: non-data-frame input errors", {
  expect_error(build_sequence_matrix(list(), "species"), "must be a data frame")
})

test_that("build_sequence_matrix: missing required columns errors", {
  df <- data.frame(composite_id = "A1", stringsAsFactors = FALSE)
  expect_error(build_sequence_matrix(df, "species"), "missing required columns")
})

test_that("build_sequence_matrix: fewer than 2 sequences after dedup errors", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = "A1", sequence = "ATGC",
    species = "Sp a", stringsAsFactors = FALSE
  )
  expect_error(
    build_sequence_matrix(df, "species"),
    "Fewer than 2 valid sequences"
  )
})

test_that("build_sequence_matrix: minimal two-sequence run succeeds", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c(
      paste(rep("ATGCATGCATGC", 10), collapse = ""),
      paste(rep("ATGCATGCATGG", 10), collapse = "")
    ),
    genus = c("Aa", "Aa"),
    species = c("Aa bb", "Aa cc"),
    stringsAsFactors = FALSE
  )
  out <- build_sequence_matrix(df, c("genus", "species"), max_dist = 1.0)
  expect_true(is.data.frame(out))
  expect_true(all(c("id_x", "id_y", "p_match", "species.x", "species.y") %in% names(out)))
})

# ---------------------------------------------------------------------------
# filter_unnamed -- offline validation
# ---------------------------------------------------------------------------

test_that("build_sequence_matrix: filter_unnamed non-logical errors", {
  df <- data.frame(
    composite_id = c("A1", "A2"),
    sequence = c(.seq_a, .seq_b),
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  expect_error(
    build_sequence_matrix(df, "species", filter_unnamed = "yes"),
    "filter_unnamed"
  )
  expect_error(
    build_sequence_matrix(df, "species", filter_unnamed = NA),
    "filter_unnamed"
  )
})

# ---------------------------------------------------------------------------
# max_seqs_per_taxon -- offline validation
# ---------------------------------------------------------------------------

test_that("build_sequence_matrix: max_seqs_per_taxon < 2 errors", {
  df <- data.frame(
    composite_id = c("A1", "A2"),
    sequence = c(.seq_a, .seq_b),
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  expect_error(
    build_sequence_matrix(df, "species", max_seqs_per_taxon = 1L),
    "max_seqs_per_taxon"
  )
  expect_error(
    build_sequence_matrix(df, "species", max_seqs_per_taxon = 0L),
    "max_seqs_per_taxon"
  )
})

test_that("build_sequence_matrix: max_seqs_per_taxon non-numeric errors", {
  df <- data.frame(
    composite_id = c("A1", "A2"),
    sequence = c(.seq_a, .seq_b),
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  expect_error(
    build_sequence_matrix(df, "species", max_seqs_per_taxon = "10"),
    "max_seqs_per_taxon"
  )
})

# ---------------------------------------------------------------------------
# Integration tests -- require DECIPHER
# ---------------------------------------------------------------------------

test_that("build_sequence_matrix: length filter drops short sequences", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c("ATGC", paste(rep("ATGCATGC", 20), collapse = "")),
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  # S1 is too short (< 100 bp); only S2 remains -> should error
  expect_error(
    build_sequence_matrix(df, "species", min_seq_len = 100L),
    "Fewer than 2 sequences remained"
  )
})

test_that("build_sequence_matrix: filter_unnamed removes blank-species sequences", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2", "S3"),
    sequence = c(.seq_a, .seq_b, .seq_c),
    species = c("Sp a", "", "Sp b"), # S2 has blank species
    stringsAsFactors = FALSE
  )
  out <- build_sequence_matrix(df, "species",
    max_dist = 1.0,
    filter_unnamed = TRUE
  )
  # S2 should be absent from all pairs
  expect_false(any(out$id_x == "S2" | out$id_y == "S2"))
  # S1 and S3 remain: 2 sequences x (2-1) = 2 directed pairs
  expect_equal(nrow(out), 2L)
})

test_that("build_sequence_matrix: filter_unnamed = FALSE retains blank-species sequences", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2", "S3"),
    sequence = c(.seq_a, .seq_b, .seq_c),
    species = c("Sp a", "", "Sp b"),
    stringsAsFactors = FALSE
  )
  out <- build_sequence_matrix(df, "species",
    max_dist = 1.0,
    filter_unnamed = FALSE
  )
  # All 3 sequences -> 3*(3-1) = 6 directed pairs
  expect_equal(nrow(out), 6L)
  # S2 appears in at least one pair
  expect_true(any(out$id_x == "S2" | out$id_y == "S2"))
})

test_that("build_sequence_matrix: filter_unnamed errors when all names blank", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c(.seq_a, .seq_b),
    species = c("", ""),
    stringsAsFactors = FALSE
  )
  expect_error(
    build_sequence_matrix(df, "species", max_dist = 1.0, filter_unnamed = TRUE),
    "Fewer than 2 sequences remained"
  )
})

test_that("build_sequence_matrix: max_seqs_per_taxon caps large species", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  # 4 sequences for "Sp a", 1 for "Sp b" -- cap at 2 for "Sp a"
  seqs <- c(
    .seq_a, .seq_b, .seq_c,
    paste(rep("ATGCATGCATTT", 10), collapse = ""), # S4, Sp a
    paste(rep("GCTAGCTAGCTA", 10), collapse = "")
  ) # S5, Sp b
  df <- data.frame(
    composite_id = paste0("S", 1:5),
    sequence = seqs,
    species = c("Sp a", "Sp a", "Sp a", "Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  set.seed(1L)
  out_capped <- build_sequence_matrix(df, "species",
    max_dist = 1.0,
    max_seqs_per_taxon = 2L
  )
  # With cap=2 for Sp a + 1 for Sp b = 3 sequences -> 3*(3-1) = 6 directed pairs
  # Uncapped (4 Sp a + 1 Sp b = 5 seqs) would give 5*4 = 20 directed pairs
  expect_lte(nrow(out_capped), 6L)
  # "Sp b" sequence (S5) must appear (it was under the cap)
  expect_true(any(out_capped$id_x == "S5" | out_capped$id_y == "S5"))
})

test_that("build_sequence_matrix: max_seqs_per_taxon = NULL leaves all sequences", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c(.seq_a, .seq_b),
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  out_null <- build_sequence_matrix(df, "species",
    max_dist = 1.0,
    max_seqs_per_taxon = NULL
  )
  # 2 sequences -> 2*(2-1) = 2 directed pairs
  expect_equal(nrow(out_null), 2L)
})

# ---------------------------------------------------------------------------
# barcode_term -- amplicon-length auto-resolution (soundness-review item 13)
# ---------------------------------------------------------------------------

test_that("build_sequence_matrix: barcode_term resolves and applies a length window", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c(.seq_a, .seq_b), # both 120 bp
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  # MiFishU resolves to [130, 210] bp -- both 120 bp sequences fall below the
  # resolved minimum, so this should behave exactly as if min_seq_len = 130L
  # had been passed explicitly (both dropped -> error), not the generic
  # default [100, 2000] (which would have kept both).
  expect_error(
    build_sequence_matrix(df, "species",
      max_dist = 1.0,
      barcode_term = "MiFishU"
    ),
    "Fewer than 2 sequences remained"
  )
})

test_that("build_sequence_matrix: barcode_term messages the resolved range", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c(.seq_a, .seq_b),
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  expect_message(
    tryCatch(
      build_sequence_matrix(df, "species",
        max_dist = 1.0,
        barcode_term = "MiFishU"
      ),
      error = function(e) NULL
    ),
    "resolved to length range \\[130, 210\\]"
  )
})

test_that("build_sequence_matrix: explicit min_seq_len/max_seq_len override barcode_term", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c(.seq_a, .seq_b), # both 120 bp
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  # barcode_term alone would resolve to [130, 210] and drop both 120bp
  # sequences (see test above); explicit min_seq_len = 100L must win instead.
  out <- build_sequence_matrix(df, "species",
    max_dist = 1.0,
    barcode_term = "MiFishU", min_seq_len = 100L,
    max_seq_len = 2000L
  )
  expect_true(is.data.frame(out))
  expect_equal(nrow(out), 2L)
})

test_that("build_sequence_matrix: barcode_term = NULL (default) leaves existing behavior unchanged", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c(.seq_a, .seq_b),
    species = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  out <- build_sequence_matrix(df, "species", max_dist = 1.0)
  expect_true(is.data.frame(out))
  expect_equal(nrow(out), 2L)
})

# ---------------------------------------------------------------------------
# by_genus / check_cross_genus_sampling_noise -- per-genus alignment redesign
# (fable_ecosystem_review_2026-09-05, E1)
# ---------------------------------------------------------------------------

.seq_d <- paste(rep("ATGCATGCATAA", 10), collapse = "") # 120 bp, genus Bb
.seq_e <- paste(rep("ATGCATGCACGT", 10), collapse = "") # 120 bp, genus Bb
.seq_f <- paste(rep("ATGCATGCGCGT", 10), collapse = "") # 120 bp, genus Cc
.seq_g <- paste(rep("ATGCATGCTTAA", 10), collapse = "") # 120 bp, genus Dd
.seq_h <- paste(rep("ATGCATGCTTGG", 10), collapse = "") # 120 bp, genus Dd

.make_two_genus_df <- function() {
  data.frame(
    composite_id = c("S1", "S2", "S3", "S4"),
    sequence = c(.seq_a, .seq_b, .seq_c, .seq_d),
    genus = c("Aa", "Aa", "Aa", "Bb"),
    species = c("Aa bb", "Aa bb2", "Aa cc", "Bb dd"),
    stringsAsFactors = FALSE
  )
}

.make_three_genus_df <- function() {
  # Aa: 3 sequences, Bb: 2 sequences, Cc: 1 sequence (3 genera total).
  data.frame(
    composite_id = c("S1", "S2", "S3", "S4", "S5", "S6"),
    sequence = c(.seq_a, .seq_b, .seq_c, .seq_d, .seq_e, .seq_f),
    genus = c("Aa", "Aa", "Aa", "Bb", "Bb", "Cc"),
    species = c("Aa bb", "Aa bb2", "Aa cc", "Bb dd", "Bb dd2", "Cc ee"),
    stringsAsFactors = FALSE
  )
}

.make_four_genus_uniform_df <- function() {
  # 4 genera, 2 sequences each (8 total) -- uniform sizes so a partial cap's
  # resulting pair count is deterministic regardless of which specific
  # foreign representative gets drawn (see the capping tests below).
  data.frame(
    composite_id = c("S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8"),
    sequence = c(.seq_a, .seq_b, .seq_c, .seq_d, .seq_e, .seq_f, .seq_g, .seq_h),
    genus = c("Aa", "Aa", "Bb", "Bb", "Cc", "Cc", "Dd", "Dd"),
    species = c(
      "Aa bb", "Aa bb2", "Bb cc", "Bb cc2",
      "Cc dd", "Cc dd2", "Dd ee", "Dd ee2"
    ),
    stringsAsFactors = FALSE
  )
}

test_that("build_sequence_matrix: by_genus = TRUE non-logical/NA errors", {
  df <- .make_two_genus_df()
  expect_error(
    build_sequence_matrix(df, c("genus", "species"), by_genus = "yes"),
    "by_genus"
  )
  expect_error(
    build_sequence_matrix(df, c("genus", "species"), by_genus = NA),
    "by_genus"
  )
})

test_that("build_sequence_matrix: by_genus = TRUE requires 'genus' in rank_system", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_two_genus_df()
  expect_error(
    build_sequence_matrix(df, "species", max_dist = 1.0, by_genus = TRUE),
    "requires 'genus' in rank_system"
  )
})

test_that("build_sequence_matrix: by_genus = TRUE drops blank/NA-genus sequences with a message instead of erroring", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  # 2026-09-06: a real production run against a real 1,412-genus/21,896-
  # sequence 18S fetch hit exactly this case (some accessions legitimately
  # unresolved to genus level, e.g. environmental samples) -- this used to be
  # a hard stop() for the whole run; now it drops just those sequences.
  df <- .make_two_genus_df()
  df$genus[1] <- NA
  expect_message(
    out <- build_sequence_matrix(df, c("genus", "species"),
      max_dist = 1.0,
      by_genus = TRUE, verbose = FALSE
    ),
    "dropped 1 sequence\\(s\\) with blank/NA 'genus'"
  )
  expect_false(any(out$id_x == "S1" | out$id_y == "S1"))

  df2 <- .make_two_genus_df()
  df2$genus[1] <- ""
  expect_message(
    out2 <- build_sequence_matrix(df2, c("genus", "species"),
      max_dist = 1.0,
      by_genus = TRUE, verbose = FALSE
    ),
    "dropped 1 sequence\\(s\\) with blank/NA 'genus'"
  )
  expect_false(any(out2$id_x == "S1" | out2$id_y == "S1"))
})

test_that("build_sequence_matrix: by_genus = TRUE errors when dropping blank-genus rows leaves fewer than 2 sequences", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence = c(.seq_a, .seq_b),
    genus = c("Aa", NA),
    species = c("Aa bb", "Bb cc"),
    stringsAsFactors = FALSE
  )
  expect_error(
    build_sequence_matrix(df, c("genus", "species"),
      max_dist = 1.0,
      by_genus = TRUE, verbose = FALSE
    ),
    "Fewer than 2 sequences remained after dropping blank/NA 'genus'"
  )
})

test_that("build_sequence_matrix: by_genus = TRUE produces within-genus and cross-genus pairs", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_two_genus_df()
  set.seed(42L)
  out <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, verbose = FALSE
  )
  expect_true(is.data.frame(out))
  expect_true(all(c("genus.x", "genus.y") %in% names(out)))

  within_genus <- out[out$genus.x == out$genus.y, , drop = FALSE]
  cross_genus <- out[out$genus.x != out$genus.y, , drop = FALSE]

  # Genus Aa has 3 sequences -> 3*(3-1) = 6 directed within-genus pairs
  # (unaffected by the cross-genus augmentation).
  # Genus Bb has 1 sequence -> 0 within-genus pairs (never aligned alone).
  expect_equal(nrow(within_genus), 6L)
  expect_true(all(within_genus$genus.x == "Aa"))

  # Every one of Aa's 3 sequences now gets compared against Bb's single
  # member (either directly, via Aa's own augmented alignment, if it isn't
  # Aa's own representative, or via the dedicated representative alignment,
  # if it is) -- 3 Aa members x 1 Bb member x 2 directions = 6 directed
  # cross-genus pairs (up from 2 under the representative-only design).
  expect_equal(nrow(cross_genus), 6L)

  expect_equal(nrow(out), 12L)
})

test_that("build_sequence_matrix: by_genus = TRUE forces a singleton genus's only sequence as its representative", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_two_genus_df()
  set.seed(1L)
  out <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, verbose = FALSE
  )
  # Bb has exactly one sequence (S4) -- it must appear as the cross-genus
  # representative even though it contributes zero within-genus pairs.
  cross_genus <- out[out$genus.x != out$genus.y, , drop = FALSE]
  expect_true(any(cross_genus$id_x == "S4" | cross_genus$id_y == "S4"))
})

test_that("build_sequence_matrix: by_genus = TRUE representative draw is reproducible via set.seed()", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_two_genus_df()

  set.seed(7L)
  out1 <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, verbose = FALSE
  )
  set.seed(7L)
  out2 <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, verbose = FALSE
  )

  expect_equal(out1, out2)
})

test_that("build_sequence_matrix: by_genus = TRUE and FALSE give the same within-genus pairs", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  # Restrict to genus Aa alone (3 sequences, no cross-genus complication) and
  # confirm by_genus = TRUE's within-genus alignment reproduces the same pair
  # set the whole-set path would give for that same genus-restricted input.
  df <- .make_two_genus_df()
  df_aa <- df[df$genus == "Aa", , drop = FALSE]

  out_whole <- build_sequence_matrix(df_aa, c("genus", "species"),
    max_dist = 1.0,
    verbose = FALSE
  )
  set.seed(3L)
  out_by_genus <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, verbose = FALSE
  )
  within_genus <- out_by_genus[out_by_genus$genus.x == out_by_genus$genus.y, , drop = FALSE]

  expect_equal(nrow(within_genus), nrow(out_whole))
  expect_equal(
    sort(paste(within_genus$id_x, within_genus$id_y)),
    sort(paste(out_whole$id_x, out_whole$id_y))
  )
})

test_that("build_sequence_matrix: by_genus = TRUE gives every sequence real cross-genus visibility, not just the representative", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_three_genus_df()
  set.seed(5L)
  out <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, verbose = FALSE
  )
  cross_genus <- out[out$genus.x != out$genus.y, , drop = FALSE]

  # The whole point of the 2026-09-05 revision: every one of the 6 sequences
  # (not only its genus's randomly-chosen representative) must appear in at
  # least one cross-genus pair.
  all_ids <- df$composite_id
  ids_with_cross_visibility <- unique(c(cross_genus$id_x, cross_genus$id_y))
  expect_true(all(all_ids %in% ids_with_cross_visibility))
})

test_that("build_sequence_matrix: by_genus = TRUE never double-counts a representative-vs-representative pair", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_three_genus_df()
  set.seed(5L)
  out <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, verbose = FALSE
  )

  # Hand-derived expected total for genus sizes (3, 2, 1) at max_dist = 1.0
  # (every possible pair retained): within-genus 3*2 + 2*1 + 0 = 8; the
  # augmented per-genus step additionally captures every non-representative
  # sequence's cross-genus pairs (2 non-rep Aa members + 1 non-rep Bb member,
  # each x 2 foreign reps x 2 directions = 12); the dedicated representative
  # alignment supplies the 3*2 = 6 representative-vs-representative pairs
  # exactly once. Total = 8 + 12 + 6 = 26 -- if representative pairs were
  # ever double-computed (once from the augmented step, once from the
  # dedicated step), this total would be higher.
  expect_equal(nrow(out), 26L)

  # No exact-duplicate (id_x, id_y) row.
  pair_keys <- paste(out$id_x, out$id_y)
  expect_equal(length(pair_keys), length(unique(pair_keys)))
})

test_that("build_sequence_matrix: max_foreign_reps_per_genus non-numeric/negative/NA errors", {
  df <- .make_three_genus_df()
  expect_error(
    build_sequence_matrix(df, c("genus", "species"),
      by_genus = TRUE,
      max_foreign_reps_per_genus = "20"
    ),
    "max_foreign_reps_per_genus"
  )
  expect_error(
    build_sequence_matrix(df, c("genus", "species"),
      by_genus = TRUE,
      max_foreign_reps_per_genus = -1L
    ),
    "max_foreign_reps_per_genus"
  )
  expect_error(
    build_sequence_matrix(df, c("genus", "species"),
      by_genus = TRUE,
      max_foreign_reps_per_genus = NA
    ),
    "max_foreign_reps_per_genus"
  )
})

test_that("build_sequence_matrix: max_foreign_reps_per_genus = 0 reduces to representative-only cross-genus pairs", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_three_genus_df()
  set.seed(9L)
  out <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, max_foreign_reps_per_genus = 0L,
    verbose = FALSE
  )
  cross_genus <- out[out$genus.x != out$genus.y, , drop = FALSE]

  # With no foreign augmentation at all, the only cross-genus pairs left are
  # the dedicated representative-vs-representative alignment's own output:
  # 3 genera -> 3*(3-1) = 6 directed pairs, all involving genus reps only.
  expect_equal(nrow(cross_genus), 6L)

  # Within-genus totals are unaffected by the cap (3*2 + 2*1 + 0 = 8), so the
  # grand total is exactly 8 + 6 = 14.
  expect_equal(nrow(out), 14L)
})

test_that("build_sequence_matrix: max_foreign_reps_per_genus caps cost between the 0 and uncapped extremes", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_four_genus_uniform_df()

  set.seed(1L)
  out_uncapped <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE,
    max_foreign_reps_per_genus = NULL,
    verbose = FALSE
  )
  set.seed(1L)
  out_cap1 <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, max_foreign_reps_per_genus = 1L,
    verbose = FALSE
  )
  set.seed(1L)
  out_cap0 <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, max_foreign_reps_per_genus = 0L,
    verbose = FALSE
  )

  # 4 uniform-sized (2-sequence) genera: hand-derived exact totals --
  # cap = 0 (no augmentation): 4 genera x within-genus 2 pairs + dedicated
  # 4*3 = 12 rep pairs = 8 + 12 = 20.
  # cap = 1 (each genus adds exactly 1 of 3 possible foreign reps -- uniform
  # genus sizes make this count independent of WHICH foreign rep is drawn):
  # 4 genera x 4 kept augmented pairs + 12 dedicated = 16 + 12 = 28.
  # uncapped (cap >= 3, all 3 other reps added): 4 genera x 8 kept augmented
  # pairs + 12 dedicated = 32 + 12 = 44.
  expect_equal(nrow(out_cap0), 20L)
  expect_equal(nrow(out_cap1), 28L)
  expect_equal(nrow(out_uncapped), 44L)
})

test_that("build_sequence_matrix: max_foreign_reps_per_genus default (20L) behaves as uncapped when it exceeds genus count", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_three_genus_df()
  set.seed(3L)
  out_default <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE, verbose = FALSE
  )
  set.seed(3L)
  out_uncapped <- build_sequence_matrix(df, c("genus", "species"),
    max_dist = 1.0,
    by_genus = TRUE,
    max_foreign_reps_per_genus = NULL,
    verbose = FALSE
  )
  # 3 genera -> n_genera - 1 = 2 possible foreign reps per genus, always
  # under the default cap of 20 -- default and explicit NULL must agree.
  expect_equal(out_default, out_uncapped)
})

test_that("check_cross_genus_sampling_noise: returns the documented list(replicates=, summary=) shape", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_two_genus_df()
  set.seed(11L)
  result <- check_cross_genus_sampling_noise(df,
    rank_system = c("genus", "species"),
    max_dist = 1.0, n_replicates = 2L
  )
  expect_type(result, "list")
  expect_named(result, c("replicates", "summary"))
  expect_true(is.data.frame(result$replicates))
  expect_equal(nrow(result$replicates), 2L)
  expect_true(all(c(
    "replicate", "n_cross_genus_pairs", "mean_p_match",
    "median_p_match", "sd_p_match"
  ) %in% names(result$replicates)))
  expect_named(result$summary, c("mean_p_match_range", "mean_p_match_cv"))
  expect_length(result$summary$mean_p_match_range, 2L)
})

test_that("check_cross_genus_sampling_noise: errors clearly when rank_system lacks genus", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- .make_two_genus_df()
  expect_error(
    check_cross_genus_sampling_noise(df,
      rank_system = "species", max_dist = 1.0,
      n_replicates = 2L
    ),
    "genus"
  )
})

test_that("check_cross_genus_sampling_noise: n_replicates < 2 errors", {
  df <- .make_two_genus_df()
  expect_error(
    check_cross_genus_sampling_noise(df,
      rank_system = c("genus", "species"),
      n_replicates = 1L
    ),
    "n_replicates"
  )
})

test_that("check_cross_genus_sampling_noise: n_replicates non-numeric/NA errors", {
  df <- .make_two_genus_df()
  expect_error(
    check_cross_genus_sampling_noise(df,
      rank_system = c("genus", "species"),
      n_replicates = "5"
    ),
    "n_replicates"
  )
  expect_error(
    check_cross_genus_sampling_noise(df,
      rank_system = c("genus", "species"),
      n_replicates = NA
    ),
    "n_replicates"
  )
})

# ---- 2026-09-07 review regressions -------------------------------------------

test_that("build_sequence_matrix: max_seqs_per_taxon keeps NA-species rows when filter_unnamed = FALSE", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  # sum(finest_vals == tx) is NA once ANY finest value is NA, so `over_cap`
  # became all-NA (branch fires unconditionally, cap count nonsense) and
  # which(finest_vals == NA) is integer(0), silently deleting every unnamed
  # sequence from training. filter_unnamed = FALSE asked to keep them.
  df <- data.frame(
    composite_id = c("S1", "S2", "S3", "S4", "S5", "S6"),
    sequence = c(.seq_a, .seq_b, .seq_c, .seq_a, .seq_b, .seq_c),
    genus = c("Aa", "Aa", "Aa", "Aa", "Aa", "Aa"),
    species = c("Aa bb", "Aa bb", "Aa bb", NA, NA, "Aa cc"),
    stringsAsFactors = FALSE
  )
  set.seed(1)
  out <- build_sequence_matrix(df, c("genus", "species"),
    filter_unnamed = FALSE,
    max_seqs_per_taxon = 2L
  )
  kept <- unique(c(out$id_x, out$id_y))
  expect_true(all(c("S4", "S5") %in% kept))
})

test_that("build_sequence_matrix: by_genus = TRUE works on a single-genus reference set", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  # One genus means one representative, and DECIPHER::AlignSeqs() hard-errors
  # on a 1-sequence input -- previously surfacing as an opaque DECIPHER
  # message rather than simply having no cross-genus pairs to sample.
  df <- data.frame(
    composite_id = c("S1", "S2", "S3"),
    sequence = c(.seq_a, .seq_b, .seq_c),
    genus = c("Aa", "Aa", "Aa"),
    species = c("Aa bb", "Aa bb", "Aa cc"),
    stringsAsFactors = FALSE
  )
  expect_message(
    out <- build_sequence_matrix(df, c("genus", "species"), by_genus = TRUE),
    "only 1 genus present"
  )
  expect_true(nrow(out) > 0L)
  expect_true(all(out$genus.x == "Aa" & out$genus.y == "Aa"))
})

test_that("check_cross_genus_sampling_noise: barcode_term actually resolves the length window", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  # 240 bp sequences are outside MiFishU's 130-210 bp window, so a real
  # barcode_term must filter them all out -- exactly as
  # build_sequence_matrix(barcode_term = "MiFishU") does. Previously this
  # function forwarded its own min_seq_len/max_seq_len defaults
  # unconditionally, defeating build_sequence_matrix()'s missing() gate, and
  # the diagnostic silently ran on the unfiltered 240 bp set instead.
  long_a <- paste(rep("ATGCATGCATGC", 20), collapse = "") # 240 bp
  long_b <- paste(rep("ATGCATGCATGG", 20), collapse = "")
  long_c <- paste(rep("ATGCATGCATCC", 20), collapse = "")
  df <- data.frame(
    composite_id = c("S1", "S2", "S3"),
    sequence = c(long_a, long_b, long_c),
    genus = c("Aa", "Bb", "Cc"),
    species = c("Aa bb", "Bb cc", "Cc dd"),
    stringsAsFactors = FALSE
  )
  expect_error(
    suppressMessages(check_cross_genus_sampling_noise(
      df,
      rank_system = c("genus", "species"),
      barcode_term = "MiFishU", n_replicates = 2L
    )),
    "after length filtering"
  )
})
