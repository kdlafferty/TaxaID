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

test_that(".impute_restored_score: min(ref_ref, anchor), and the ceiling assertion fires", {
  expect_equal(.impute_restored_score(78, 97, scale_100 = TRUE), 78)
  expect_equal(.impute_restored_score(0.78, 0.97, scale_100 = FALSE), 0.78)
  expect_equal(.impute_restored_score(100, 97, scale_100 = TRUE), 97)
  expect_equal(.impute_restored_score(98, 90, scale_100 = TRUE), 90)
  # The assertion itself must fire on a constructed violation.
  expect_error(.assert_imputed_ceiling(79, 78), "exceeds the observation's best")
  expect_silent(.assert_imputed_ceiling(78, 78))
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

test_that("without a query sequence the score is imputed as min(ref_ref, anchor)", {
  m <- .rm_match(score = 98)
  m$sequence <- NULL
  res <- restore_suppressed_candidates(
    m, .rm_ref(),
    rank_system = c("family", "genus", "species"),
    seq_matrix = .rm_sm(0.97), verbose = FALSE
  )
  r <- res[res$is_restored, ]
  expect_equal(r$score_original, 97)
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
  expect_equal(r$score_original, 97)
  expect_equal(r$restored_reason, "imputed_query_coverage_below_min")
})

test_that("a restored score below the training floor is kept and flagged", {
  m <- .rm_match(score = 78)
  m$sequence <- NULL
  # min(70, 78) = 70, below 1 - max_dist = 75; Purpose A admits it under a
  # wide sigma.
  res <- restore_suppressed_candidates(
    m, .rm_ref(),
    rank_system = c("family", "genus", "species"),
    seq_matrix = .rm_sm(0.70), model_params = .rm_params(sigma11 = 1), verbose = FALSE
  )
  r <- res[res$is_restored, ]
  expect_equal(nrow(r), 1L)
  expect_equal(r$score_original, 70)
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

# ---- dropped-hit replacement ---------------------------------------------------

.rm_dropped <- function(obs_id = "obs_gone", species = "simplicidens", score = 100) {
  d <- .rm_match(obs_id = obs_id, score = score, species = species)
  d$accession <- "DROPPED_ACC"
  d
}

test_that("an ESV whose only hit was dropped gains its species' kept reference", {
  m <- .rm_match(obs_id = "obs_other", score = 99)
  m$accession <- "KEPT_ACC"
  ref <- .rm_ref(c(simplicidens = .q_seq))
  res <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    dropped_matches = .rm_dropped(), verbose = FALSE
  )
  r <- res[res$observation_id == "obs_gone", ]
  expect_equal(nrow(r), 1L)
  expect_true(r$is_restored)
  expect_equal(r$species, "simplicidens")
  expect_equal(r$score_original, 100)
  expect_equal(r$restoration_basis, "dropped_hit_replacement")
  expect_equal(r$restored_reason, "replaced_dropped_hit")
  expect_equal(r$accession, "RESTORED_ACC_simplicidens")
})

test_that("dropped-hit replacement needs a kept reference covering the query", {
  m <- .rm_match(obs_id = "obs_other", score = 99)
  half <- substr(.q_seq, 1, floor(nchar(.q_seq) / 2))
  res <- restore_suppressed_candidates(
    m, .rm_ref(c(simplicidens = half)),
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    dropped_matches = .rm_dropped(), verbose = FALSE
  )
  expect_false("obs_gone" %in% res$observation_id)
  # No kept reference anywhere in the genus: nothing added either.
  res2 <- restore_suppressed_candidates(
    m, .rm_ref(c(simplicidens = .q_seq))[0, ],
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    dropped_matches = .rm_dropped(), verbose = FALSE
  )
  expect_false("obs_gone" %in% res2$observation_id)
})

test_that("replacement offers every congener with kept references, not only the dropped label", {
  m <- .rm_match(obs_id = "obs_other", score = 99)
  # The dropped hit was labelled simplicidens, which has no kept reference;
  # its congener nigricans does.
  res <- restore_suppressed_candidates(
    m, .rm_ref(c(nigricans = .q_seq)),
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    dropped_matches = .rm_dropped(), verbose = FALSE
  )
  r <- res[res$observation_id == "obs_gone", ]
  expect_equal(r$species, "nigricans")
  expect_equal(r$restoration_basis, "dropped_hit_replacement")
})

test_that("the better-aligned unlabelled congener wins on likelihood", {
  skip_if_not_installed("TaxaTools")
  mut <- .q_seq
  for (pos in c(10, 30, 50)) substr(mut, pos, pos) <- if (substr(mut, pos, pos) == "A") "C" else "A"
  m <- .rm_match(obs_id = "obs_other", score = 99)
  ref <- .rm_ref(c(simplicidens = mut, nigricans = .q_seq))
  res <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    dropped_matches = .rm_dropped(), verbose = FALSE
  )
  r <- res[res$observation_id == "obs_gone", ]
  expect_setequal(r$species, c("simplicidens", "nigricans"))
  expect_gt(r$score_original[r$species == "nigricans"], r$score_original[r$species == "simplicidens"])

  sigma <- matrix(c(2, 0.2, 0.2, 1), 2, dimnames = list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit")))
  i2 <- diag(2)
  dimnames(i2) <- list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit"))
  params <- structure(list(
    H1_Lookup = data.frame(lookup_key = character(0), rank = character(0), mu_score = numeric(0),
      mu_gap = numeric(0), sigma_score = numeric(0), n_obs_species = integer(0), stringsAsFactors = FALSE),
    H1_Global_Mu = c(score_logit = 4.5, gap_logit = 1.5), H1_Sigma = sigma,
    H2 = list(delta = 3, sigma = i2),
    H3 = list(delta = 5, sigma = i2),
    Stats = list(n_species = 1L, n_singletons = 0L), Score_Transform = "logit"
  ), class = "taxa_model_params")
  r$score <- r$score_original
  r$taxon_name <- r$species
  lk <- suppressWarnings(evaluate_likelihoods(r, params,
    rank_system = c("family", "genus", "species"), ratio_threshold = 0
  ))$likelihoods
  h1 <- lk[lk$hypothesis_type == "specific_candidate", ]
  expect_equal(h1$taxon_name[which.max(h1$score_likelihood)], "nigricans")
})

test_that("dropped-hit replacement never duplicates a species the observation already holds", {
  m <- .rm_match(obs_id = "obs1", score = 99, species = "simplicidens")
  res <- restore_suppressed_candidates(
    m, .rm_ref(c(simplicidens = .q_seq)),
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    dropped_matches = .rm_dropped(obs_id = "obs1"), verbose = FALSE
  )
  expect_equal(nrow(res), 1L)
  expect_false(any(res$is_restored))
})

test_that("dropped-hit replacement uses only placed references of a region-matched reference_df", {
  m <- .rm_match(obs_id = "obs_other", score = 99)
  ref <- .rm_ref(c(simplicidens = .q_seq), trim_path = "not_placed")
  res <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    dropped_matches = .rm_dropped(), verbose = FALSE
  )
  expect_false("obs_gone" %in% res$observation_id)
})

test_that("dropped_matches is validated", {
  expect_error(
    restore_suppressed_candidates(.rm_match(), .rm_ref(),
      rank_system = c("family", "genus", "species"), dropped_matches = .rm_dropped(),
      verbose = FALSE
    ),
    "requires 'sequence_col'"
  )
  expect_error(
    restore_suppressed_candidates(.rm_match(), .rm_ref(),
      rank_system = c("family", "genus", "species"), sequence_col = "sequence",
      dropped_matches = data.frame(x = 1), verbose = FALSE
    ),
    "must be a data frame with column"
  )
})

# ---- measured-score calibration to the observed scale -------------------------

.rm_calib_set <- function(n_obs, observed = 98) {
  m <- do.call(rbind, lapply(seq_len(n_obs), function(i) .rm_match(obs_id = sprintf("o%03d", i), score = observed)))
  m$accession <- "ACC_simplicidens" # its own best hit is in reference_df
  m
}

test_that("measured scores are shifted onto the observed scale by the median offset", {
  # Every query is identical to its own best hit's reference (pid 100) but
  # the provider scored it 98: offset +2, so a measured 100 becomes 98.
  res <- restore_suppressed_candidates(
    .rm_calib_set(40), .rm_ref(),
    rank_system = c("family", "genus", "species"), sequence_col = "sequence", verbose = FALSE
  )
  cal <- attr(res, "measured_score_calibration")
  expect_equal(cal$offset, 2)
  expect_equal(cal$n, 40L)
  expect_false(cal$thin)
  r <- res[res$is_restored, ]
  expect_true(all(r$score_original == 98))
  expect_true(all(r$restored_score_source == "measured"))
})

test_that("a thin calibration (fewer than 30 pairs) uses offset 0 and says so", {
  res <- restore_suppressed_candidates(
    .rm_calib_set(10), .rm_ref(),
    rank_system = c("family", "genus", "species"), sequence_col = "sequence", verbose = FALSE
  )
  cal <- attr(res, "measured_score_calibration")
  expect_equal(cal$offset, 0)
  expect_equal(cal$n, 10L)
  expect_true(cal$thin)
  expect_true(all(res$score_original[res$is_restored] == 100))
})

test_that("the calibration offset also applies to dropped-hit replacements", {
  m <- .rm_calib_set(40)
  d <- .rm_dropped(obs_id = "obs_gone", species = "nigricans")
  res <- restore_suppressed_candidates(
    m, .rm_ref(),
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    dropped_matches = d, verbose = FALSE
  )
  r <- res[res$observation_id == "obs_gone", ]
  expect_true(nrow(r) >= 1L)
  expect_true(all(r$score_original == 98))
})

test_that("a supplied measured_offset is used as given, regardless of the call's own data", {
  res <- restore_suppressed_candidates(
    .rm_calib_set(10), .rm_ref(),
    rank_system = c("family", "genus", "species"), sequence_col = "sequence",
    measured_offset = 2.25, verbose = FALSE
  )
  cal <- attr(res, "measured_score_calibration")
  expect_equal(cal$offset, 2.25)
  expect_equal(cal$source, "supplied")
  expect_true(all(res$score_original[res$is_restored] == 97.75))
  expect_error(
    restore_suppressed_candidates(.rm_calib_set(2), .rm_ref(),
      rank_system = c("family", "genus", "species"), sequence_col = "sequence",
      measured_offset = c(1, 2), verbose = FALSE
    ),
    "measured_offset"
  )
})
