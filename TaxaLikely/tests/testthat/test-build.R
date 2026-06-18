# build_sequence_matrix requires DECIPHER (Bioconductor — Suggests).
# All online tests are guarded. Input validation and new-parameter offline tests
# run without DECIPHER.

# ---------------------------------------------------------------------------
# Shared synthetic sequences (120 bp, different enough to form valid pairs)
# ---------------------------------------------------------------------------
.seq_a <- paste(rep("ATGCATGCATGC", 10), collapse = "")   # 120 bp
.seq_b <- paste(rep("ATGCATGCATGG", 10), collapse = "")   # 120 bp, 1 diff/12
.seq_c <- paste(rep("ATGCATGCATCC", 10), collapse = "")   # 120 bp, 2 diff/12

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
  df <- data.frame(composite_id = "A1", sequence = "ATGC",
                   species = "Sp a", stringsAsFactors = FALSE)
  expect_error(build_sequence_matrix(df, "species"),
               "Fewer than 2 valid sequences")
})

test_that("build_sequence_matrix: minimal two-sequence run succeeds", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence     = c(
      paste(rep("ATGCATGCATGC", 10), collapse = ""),
      paste(rep("ATGCATGCATGG", 10), collapse = "")
    ),
    genus        = c("Aa", "Aa"),
    species      = c("Aa bb", "Aa cc"),
    stringsAsFactors = FALSE
  )
  out <- build_sequence_matrix(df, c("genus", "species"), max_dist = 1.0)
  expect_true(is.data.frame(out))
  expect_true(all(c("id_x", "id_y", "p_match", "species.x", "species.y") %in% names(out)))
})

# ---------------------------------------------------------------------------
# filter_unnamed — offline validation
# ---------------------------------------------------------------------------

test_that("build_sequence_matrix: filter_unnamed non-logical errors", {
  df <- data.frame(composite_id = c("A1", "A2"),
                   sequence     = c(.seq_a, .seq_b),
                   species      = c("Sp a", "Sp b"),
                   stringsAsFactors = FALSE)
  expect_error(build_sequence_matrix(df, "species", filter_unnamed = "yes"),
               "filter_unnamed")
  expect_error(build_sequence_matrix(df, "species", filter_unnamed = NA),
               "filter_unnamed")
})

# ---------------------------------------------------------------------------
# max_seqs_per_taxon — offline validation
# ---------------------------------------------------------------------------

test_that("build_sequence_matrix: max_seqs_per_taxon < 2 errors", {
  df <- data.frame(composite_id = c("A1", "A2"),
                   sequence     = c(.seq_a, .seq_b),
                   species      = c("Sp a", "Sp b"),
                   stringsAsFactors = FALSE)
  expect_error(build_sequence_matrix(df, "species", max_seqs_per_taxon = 1L),
               "max_seqs_per_taxon")
  expect_error(build_sequence_matrix(df, "species", max_seqs_per_taxon = 0L),
               "max_seqs_per_taxon")
})

test_that("build_sequence_matrix: max_seqs_per_taxon non-numeric errors", {
  df <- data.frame(composite_id = c("A1", "A2"),
                   sequence     = c(.seq_a, .seq_b),
                   species      = c("Sp a", "Sp b"),
                   stringsAsFactors = FALSE)
  expect_error(build_sequence_matrix(df, "species", max_seqs_per_taxon = "10"),
               "max_seqs_per_taxon")
})

# ---------------------------------------------------------------------------
# Integration tests — require DECIPHER
# ---------------------------------------------------------------------------

test_that("build_sequence_matrix: length filter drops short sequences", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence     = c("ATGC", paste(rep("ATGCATGC", 20), collapse = "")),
    species      = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  # S1 is too short (< 100 bp); only S2 remains → should error
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
    sequence     = c(.seq_a, .seq_b, .seq_c),
    species      = c("Sp a", "",    "Sp b"),   # S2 has blank species
    stringsAsFactors = FALSE
  )
  out <- build_sequence_matrix(df, "species", max_dist = 1.0,
                               filter_unnamed = TRUE)
  # S2 should be absent from all pairs
  expect_false(any(out$id_x == "S2" | out$id_y == "S2"))
  # S1 and S3 remain: 2 sequences × (2-1) = 2 directed pairs
  expect_equal(nrow(out), 2L)
})

test_that("build_sequence_matrix: filter_unnamed = FALSE retains blank-species sequences", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2", "S3"),
    sequence     = c(.seq_a, .seq_b, .seq_c),
    species      = c("Sp a", "",    "Sp b"),
    stringsAsFactors = FALSE
  )
  out <- build_sequence_matrix(df, "species", max_dist = 1.0,
                               filter_unnamed = FALSE)
  # All 3 sequences → 3*(3-1) = 6 directed pairs
  expect_equal(nrow(out), 6L)
  # S2 appears in at least one pair
  expect_true(any(out$id_x == "S2" | out$id_y == "S2"))
})

test_that("build_sequence_matrix: filter_unnamed errors when all names blank", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(
    composite_id = c("S1", "S2"),
    sequence     = c(.seq_a, .seq_b),
    species      = c("", ""),
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
  # 4 sequences for "Sp a", 1 for "Sp b" — cap at 2 for "Sp a"
  seqs <- c(.seq_a, .seq_b, .seq_c,
            paste(rep("ATGCATGCATTT", 10), collapse = ""),  # S4, Sp a
            paste(rep("GCTAGCTAGCTA", 10), collapse = ""))   # S5, Sp b
  df <- data.frame(
    composite_id = paste0("S", 1:5),
    sequence     = seqs,
    species      = c("Sp a", "Sp a", "Sp a", "Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  set.seed(1L)
  out_capped <- build_sequence_matrix(df, "species", max_dist = 1.0,
                                      max_seqs_per_taxon = 2L)
  # With cap=2 for Sp a + 1 for Sp b = 3 sequences → 3*(3-1) = 6 directed pairs
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
    sequence     = c(.seq_a, .seq_b),
    species      = c("Sp a", "Sp b"),
    stringsAsFactors = FALSE
  )
  out_null <- build_sequence_matrix(df, "species", max_dist = 1.0,
                                    max_seqs_per_taxon = NULL)
  # 2 sequences → 2*(2-1) = 2 directed pairs
  expect_equal(nrow(out_null), 2L)
})
