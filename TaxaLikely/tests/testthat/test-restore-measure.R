# Measured-first scoring of restored congeners (R/restore_measure.R and its
# wiring in restore_suppressed_candidates()).

skip_if_not_installed("pwalign")
skip_if_not_installed("Biostrings")

.q_seq <- paste0(
  "GTCGGTAAAACTCGTGCCAGCCACCGCGGTTATACGAGAGGCCCAAGTTGACAAACACCGGCGTAAAGCGTGG",
  "TTAAGTTAAAAATTAAACTAAAGCCGAACGCCCTCAAAGCTGTTATACGCAC"
)

.rm_match <- function(obs_id = "obs1", score = 80, species = "simplicidens",
                      sequence = .q_seq) {
  data.frame(
    observation_id = obs_id, score_original = score, taxon_name = species,
    taxon_name_rank = "species", family = "Kyphosidae", genus = "Girella",
    species = species, sequence = sequence, stringsAsFactors = FALSE
  )
}

.rm_ref <- function(seqs = c(simplicidens = .q_seq, nigricans = .q_seq),
                    trim_path = NULL) {
  out <- data.frame(
    family = "Kyphosidae", genus = "Girella", species = names(seqs),
    composite_id = paste0("ACC_", names(seqs)), sequence = unname(seqs),
    stringsAsFactors = FALSE
  )
  if (!is.null(trim_path)) out$trim_path <- trim_path
  out
}

.rm_sm <- function(p_match) {
  data.frame(
    id_x = "ACC_simplicidens", id_y = "ACC_nigricans", p_match = p_match,
    coverage = 1, stringsAsFactors = FALSE
  )
}

.rm_params <- function(sigma11 = 1) {
  list(
    H1_Sigma = matrix(c(sigma11, 0, 0, 1),
      nrow = 2,
      dimnames = list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit"))
    ),
    H1_Lookup = NULL, Score_Transform = "logit"
  )
}

test_that(".measure_query_identity: best identity among references covering the query", {
  mut <- .q_seq
  substr(mut, 10, 10) <- if (substr(mut, 10, 10) == "A") "C" else "A"
  pid <- .measure_query_identity(.q_seq, c(mut, .q_seq))
  expect_equal(pid, 100)
  pid_mut <- .measure_query_identity(.q_seq, mut)
  expect_lt(pid_mut, 100)
  expect_gt(pid_mut, 98)
})

test_that(".measure_query_identity: NA when no reference covers min_query_coverage of the query", {
  half <- substr(.q_seq, 1, floor(nchar(.q_seq) / 2))
  expect_true(is.na(.measure_query_identity(.q_seq, half)))
  expect_false(is.na(.measure_query_identity(.q_seq, half, min_query_coverage = 0.4)))
  expect_true(is.na(.measure_query_identity(NA_character_, .q_seq)))
  expect_true(is.na(.measure_query_identity(.q_seq, character(0))))
})

test_that(".impute_restored_score: anchor - (100 - ref_ref), and the ceiling assertion fires", {
  expect_equal(.impute_restored_score(78, 97, scale_100 = TRUE), 75)
  expect_equal(.impute_restored_score(0.78, 0.97, scale_100 = FALSE), 0.75)
  expect_equal(.impute_restored_score(100, 97, scale_100 = TRUE), 97)
  # A constructed violation (ref_ref above the scale's top) must fail loudly.
  expect_error(.impute_restored_score(78, 101, scale_100 = TRUE), "exceeds the observation's best")
})

test_that("a measured congener scoring above the anchor is restored untouched", {
  # The query is identical to nigricans' reference but the provider's best kept
  # hit (the anchor) is only 80: suppression does not follow identity.
  res <- restore_suppressed_candidates(
    .rm_match(score = 80), .rm_ref(),
    rank_system = c("family", "genus", "species"),
    sequence_col = "sequence", verbose = FALSE
  )
  r <- res[res$is_restored, ]
  expect_equal(r$species, "nigricans")
  expect_equal(r$score_original, 100)
  expect_gt(r$score_original, 80)
  expect_equal(r$restored_score_source, "measured")
  expect_equal(r$restored_reason, "measured_query_alignment")
  expect_false(r$restored_below_floor)
  expect_true(all(is.na(res$restored_score_source[!res$is_restored])))
})

test_that("measurement wins over the hierarchy when both are available", {
  res <- restore_suppressed_candidates(
    .rm_match(score = 80), .rm_ref(),
    rank_system = c("family", "genus", "species"),
    seq_matrix = .rm_sm(0.90), sequence_col = "sequence", verbose = FALSE
  )
  r <- res[res$is_restored, ]
  expect_equal(r$score_original, 100) # not 80 - 10 = 70, nor 90
  expect_equal(r$restored_score_source, "measured")
})

test_that("without a query sequence the score is imputed as anchor - (100 - ref_ref)", {
  m <- .rm_match(score = 98)
  m$sequence <- NULL
  res <- restore_suppressed_candidates(
    m, .rm_ref(),
    rank_system = c("family", "genus", "species"),
    seq_matrix = .rm_sm(0.97), verbose = FALSE
  )
  r <- res[res$is_restored, ]
  expect_equal(r$score_original, 95)
  expect_lte(r$score_original, 98)
  expect_equal(r$restored_score_source, "imputed")
  expect_equal(r$restored_reason, "imputed_no_query_sequence")
})

test_that("a query the candidate's references cover too little of falls back to imputation", {
  half <- substr(.q_seq, 1, floor(nchar(.q_seq) / 2))
  res <- restore_suppressed_candidates(
    .rm_match(score = 98), .rm_ref(c(simplicidens = .q_seq, nigricans = half)),
    rank_system = c("family", "genus", "species"),
    seq_matrix = .rm_sm(0.97), sequence_col = "sequence", verbose = FALSE
  )
  r <- res[res$is_restored, ]
  expect_equal(r$score_original, 95)
  expect_equal(r$restored_reason, "imputed_query_coverage_below_min")
})

test_that("a restored score below the training floor is kept and flagged", {
  m <- .rm_match(score = 78)
  m$sequence <- NULL
  # 78 - (100 - 90) = 68, below 1 - max_dist = 75; Purpose A admits it under a
  # wide sigma.
  res <- restore_suppressed_candidates(
    m, .rm_ref(),
    rank_system = c("family", "genus", "species"),
    seq_matrix = .rm_sm(0.90), model_params = .rm_params(sigma11 = 1), verbose = FALSE
  )
  r <- res[res$is_restored, ]
  expect_equal(nrow(r), 1L)
  expect_equal(r$score_original, 68)
  expect_true(r$restored_below_floor)
})

test_that("an observation with no observed score and no measurement is skipped with a reason", {
  m <- rbind(
    .rm_match(obs_id = "obs_na", score = NA_real_),
    .rm_match(obs_id = "obs_ok", score = 98)
  )
  m$sequence <- NULL
  res <- restore_suppressed_candidates(
    m, .rm_ref(),
    rank_system = c("family", "genus", "species"),
    seq_matrix = .rm_sm(0.97), verbose = FALSE
  )
  expect_false(any(res$is_restored & res$observation_id == "obs_na"))
  expect_true(any(res$is_restored & res$observation_id == "obs_ok"))
  skipped <- attr(res, "restoration_skipped")
  expect_equal(skipped$observation_id, "obs_na")
  expect_equal(skipped$species, "nigricans")
  expect_equal(skipped$reason, "restored_no_anchor_score")
})

test_that("with a region-matched reference_df, a candidate with no placed reference is not restored", {
  ref <- .rm_ref(trim_path = c("esv_aligned", "not_placed"))
  res <- restore_suppressed_candidates(
    .rm_match(score = 80), ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix = .rm_sm(0.97), sequence_col = "sequence", verbose = FALSE
  )
  expect_false(any(res$is_restored))
  ru <- attr(res, "regional_unreferenced")
  expect_equal(ru$species, "nigricans")
  expect_equal(ru$basis, "no_placed_region_reference")

  # Placed: restored as usual.
  ref$trim_path <- "esv_aligned"
  res2 <- restore_suppressed_candidates(
    .rm_match(score = 80), ref,
    rank_system = c("family", "genus", "species"),
    sequence_col = "sequence", verbose = FALSE
  )
  expect_equal(sum(res2$is_restored), 1L)
})

test_that("min_query_coverage is validated", {
  expect_error(
    restore_suppressed_candidates(.rm_match(), .rm_ref(),
      rank_system = c("family", "genus", "species"), min_query_coverage = 0, verbose = FALSE
    ),
    "min_query_coverage"
  )
})
