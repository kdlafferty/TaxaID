# build_reference_matrix requires DECIPHER (Bioconductor — Suggests).
# All online tests are guarded. Input validation tests are offline.

test_that("build_reference_matrix: non-data-frame input errors", {
  expect_error(build_reference_matrix(list(), "species"), "must be a data frame")
})

test_that("build_reference_matrix: missing required columns errors", {
  df <- data.frame(composite_id = "A1", stringsAsFactors = FALSE)
  expect_error(build_reference_matrix(df, "species"), "missing required columns")
})

test_that("build_reference_matrix: fewer than 2 sequences after dedup errors", {
  skip_if_not_installed("DECIPHER")
  skip_if_not_installed("Biostrings")
  df <- data.frame(composite_id = "A1", sequence = "ATGC",
                   species = "Sp a", stringsAsFactors = FALSE)
  expect_error(build_reference_matrix(df, "species"),
               "Fewer than 2 valid sequences")
})

test_that("build_reference_matrix: minimal two-sequence run succeeds", {
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
  out <- build_reference_matrix(df, c("genus", "species"), max_dist = 1.0)
  expect_true(is.data.frame(out))
  expect_true(all(c("id_x", "id_y", "p_match", "species.x", "species.y") %in% names(out)))
})

test_that("build_reference_matrix: length filter drops short sequences", {
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
    build_reference_matrix(df, "species", min_seq_len = 100L),
    "Fewer than 2 sequences remained"
  )
})
