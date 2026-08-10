# Tests for detect_suppressed_candidates() and restore_suppressed_candidates()
# All tests are fully offline.

# ---- detect_suppressed_candidates() ------------------------------------------

test_that("detect_suppressed_candidates detects perfect_only rule (0-100 scale)", {
  # obs1, obs2: singletons at 100; obs3: two rows below 100
  m <- data.frame(
    observation_id = c("obs1", "obs2", "obs3", "obs3"),
    score_original = c(100, 100, 98, 97),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D"),
    stringsAsFactors = FALSE
  )
  res <- detect_suppressed_candidates(m)
  expect_true(res$rule_detected)
  expect_true(res$perfect_only)
  expect_false(res$max_score_ties)
  expect_equal(res$n_perfect_obs, 2L)
  expect_equal(res$purity_perfect, 1.0)
})

test_that("detect_suppressed_candidates detects perfect_only rule (0-1 scale)", {
  m <- data.frame(
    observation_id = c("obs1", "obs2", "obs3", "obs3"),
    score_original = c(1.0, 1.0, 0.97, 0.95),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D"),
    stringsAsFactors = FALSE
  )
  res <- detect_suppressed_candidates(m, perfect_threshold = 1.0)
  expect_true(res$perfect_only)
})

test_that("detect_suppressed_candidates detects max_score_ties rule", {
  # obs1: two candidates at same score (ties); obs2: singleton below perfect
  m <- data.frame(
    observation_id = c("obs1", "obs1", "obs2"),
    score_original = c(98, 98, 97),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C"),
    stringsAsFactors = FALSE
  )
  res <- detect_suppressed_candidates(m)
  expect_true(res$rule_detected)
  expect_true(res$max_score_ties)
  expect_false(res$perfect_only)
  expect_equal(res$n_multi_obs, 1L)
  expect_equal(res$purity_ties, 1.0)
})

test_that("detect_suppressed_candidates detects best_only rule", {
  # All observations have exactly one row
  m <- data.frame(
    observation_id = c("obs1", "obs2", "obs3"),
    score_original = c(98, 97, 95),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C"),
    stringsAsFactors = FALSE
  )
  res <- detect_suppressed_candidates(m)
  expect_true(res$best_only)
  expect_equal(res$frac_singleton, 1.0)
})

test_that("detect_suppressed_candidates detects both perfect_only and max_score_ties", {
  # obs1: singleton at 100 -> perfect_only
  # obs2, obs3: two candidates at tied scores -> max_score_ties (purity = 2/2 = 1.0)
  m <- data.frame(
    observation_id = c("obs1", "obs2", "obs2", "obs3", "obs3"),
    score_original = c(100,    98,    98,    97,    97),
    taxon_name     = c("A",    "B",   "C",   "D",   "E"),
    stringsAsFactors = FALSE
  )
  res <- detect_suppressed_candidates(m)
  expect_true(res$perfect_only)
  expect_true(res$max_score_ties)
  expect_true(res$rule_detected)
  expect_equal(sort(res$rules), sort(c("perfect_only", "max_score_ties")))
})

test_that("detect_suppressed_candidates returns no rules for normal multi-candidate data", {
  m <- data.frame(
    observation_id = c("obs1", "obs1", "obs2", "obs2"),
    score_original = c(98, 95, 97, 93),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D"),
    stringsAsFactors = FALSE
  )
  res <- detect_suppressed_candidates(m)
  expect_false(res$rule_detected)
  expect_false(res$perfect_only)
  expect_false(res$max_score_ties)
  expect_false(res$best_only)
  expect_equal(res$rules, character(0L))
})

test_that("detect_suppressed_candidates respects purity_threshold for Rule 1", {
  # obs1: singleton at 100 (pure); obs2: 100 + 97 (impure -- has sub-threshold row)
  m <- data.frame(
    observation_id = c("obs1", "obs2", "obs2"),
    score_original = c(100,    100,   97),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C"),
    stringsAsFactors = FALSE
  )
  # purity_perfect = 1/2 = 0.50; threshold 0.50 -> detect
  res50 <- detect_suppressed_candidates(m, purity_threshold = 0.50)
  expect_true(res50$perfect_only)
  # threshold 0.60 -> do not detect
  res60 <- detect_suppressed_candidates(m, purity_threshold = 0.60)
  expect_false(res60$perfect_only)
})

test_that("detect_suppressed_candidates respects purity_threshold for Rule 2", {
  # obs1: tied; obs2: not tied (different scores)
  m <- data.frame(
    observation_id = c("obs1", "obs1", "obs2", "obs2"),
    score_original = c(98,     98,    97,    93),
    taxon_name     = c("A",    "B",   "C",   "D"),
    stringsAsFactors = FALSE
  )
  # purity_ties = 1/2 = 0.50; threshold 0.50 -> detect
  res50 <- detect_suppressed_candidates(m, purity_threshold = 0.50)
  expect_true(res50$max_score_ties)
  # threshold 0.60 -> do not detect
  res60 <- detect_suppressed_candidates(m, purity_threshold = 0.60)
  expect_false(res60$max_score_ties)
})

test_that("detect_suppressed_candidates respects user-supplied perfect_threshold", {
  # obs1: score = 97 (below default 100, but above custom threshold 95)
  m <- data.frame(
    observation_id = c("obs1", "obs2"),
    score_original = c(97, 96),
    taxon_name     = c("Sp_A", "Sp_B"),
    stringsAsFactors = FALSE
  )
  # default threshold 100: no perfect obs -> perfect_only = FALSE
  res_default <- detect_suppressed_candidates(m)
  expect_false(res_default$perfect_only)
  # custom threshold 95: both obs are "perfect"
  res_custom <- detect_suppressed_candidates(m, perfect_threshold = 95)
  expect_true(res_custom$perfect_only)
})

test_that("detect_suppressed_candidates handles absent score column (best_only only)", {
  m <- data.frame(observation_id = c("obs1", "obs2", "obs3"),
                  taxon_name     = c("Sp_A", "Sp_B", "Sp_C"),
                  stringsAsFactors = FALSE)
  res <- detect_suppressed_candidates(m)
  expect_false(res$has_score_col)
  expect_false(res$perfect_only)
  expect_false(res$max_score_ties)
  # best_only: all three are singletons -> frac = 1.0 -> TRUE
  expect_true(res$best_only)
})

test_that("detect_suppressed_candidates errors on missing observation_id column", {
  m <- data.frame(score_original = 100, taxon_name = "Sp_A")
  expect_error(detect_suppressed_candidates(m), "observation_id")
})

test_that("detect_suppressed_candidates example_observations contains affected IDs", {
  m <- data.frame(
    observation_id = c("ESV001", "ESV002", "ESV003", "ESV003"),
    score_original = c(100, 100, 98, 95),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D"),
    stringsAsFactors = FALSE
  )
  res <- detect_suppressed_candidates(m)
  # ESV001 and ESV002 are pure-perfect singletons
  expect_true(all(res$example_observations %in% c("ESV001", "ESV002")))
})


# ---- restore_suppressed_candidates() -----------------------------------------

make_match <- function(obs_id = "obs1", score = 100, genus = "Girella",
                       species = "simplicidens") {
  data.frame(
    observation_id  = obs_id,
    score_original  = score,
    taxon_name      = species,
    taxon_name_rank = "species",
    family          = "Kyphosidae",
    genus           = genus,
    species         = species,
    stringsAsFactors = FALSE
  )
}

make_ref <- function(genus = "Girella",
                     species = c("simplicidens", "nigricans", "laevifrons")) {
  data.frame(
    family       = "Kyphosidae",
    genus        = genus,
    species      = species,
    composite_id = paste0("ACC_", species),
    stringsAsFactors = FALSE
  )
}

# Section 3a's score-sourcing hierarchy sources restored scores from
# seq_matrix (Levels 1-3) rather than a flat delta -- this builds a
# synthetic seq_matrix with every within-genus, cross-species pair at a
# high, Purpose-B-clearing p_match (default 0.95, well above max_dist's
# default 0.25/0.75-identity floor), the free-tier evidence real workflows
# would have from build_sequence_matrix().
make_seq_matrix_for_ref <- function(ref, p_match = 0.95) {
  ids <- unique(ref$composite_id)
  if (length(ids) < 2L)
    return(data.frame(id_x = character(0), id_y = character(0),
                      p_match = numeric(0), coverage = numeric(0),
                      stringsAsFactors = FALSE))
  combos <- utils::combn(ids, 2L)
  data.frame(
    id_x     = combos[1L, ],
    id_y     = combos[2L, ],
    p_match  = p_match,
    coverage = 1.0,
    stringsAsFactors = FALSE
  )
}

test_that("restore_suppressed_candidates adds congeners from reference via Purpose B (seq_matrix evidence)", {
  ref <- make_ref()
  result <- restore_suppressed_candidates(
    make_match(), ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  expect_equal(nrow(result), 3L)  # 1 original + 2 restored
  expect_true(any(result$is_restored))
  expect_setequal(result$species,
                  c("simplicidens", "nigricans", "laevifrons"))
})

test_that("restore_suppressed_candidates is a no-op without any evidence source (seq_matrix/model_params/check_regional_overlap all absent)", {
  # This is the redesign's central behavior change: the old flat
  # anchor_score - delta imputation always restored every congener; the
  # redesign requires real evidence (seq_matrix for the free hierarchy
  # levels, or check_regional_overlap for Level 4) before restoring
  # anything, so a bare call with none of those is correctly a no-op.
  result <- restore_suppressed_candidates(
    make_match(), make_ref(),
    rank_system = c("family", "genus", "species"),
    verbose = FALSE
  )
  expect_equal(nrow(result), 1L)
  expect_false(any(result$is_restored))
})

test_that("restore_suppressed_candidates adds is_restored column", {
  ref <- make_ref()
  result <- restore_suppressed_candidates(
    make_match(), ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  expect_true("is_restored" %in% names(result))
  expect_equal(sum(!result$is_restored), 1L)
  expect_equal(sum(result$is_restored), 2L)
})

test_that("restore_suppressed_candidates marks hypothesis_type = suppressed_candidate", {
  ref <- make_ref()
  result <- restore_suppressed_candidates(
    make_match(), ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(restored$hypothesis_type == "suppressed_candidate"))
})

test_that("restore_suppressed_candidates marks restoration_basis = plausible_prior for Purpose-B-only admissions", {
  # No model_params supplied -> Purpose A's outlier test never admits
  # anything, so every restored row here must be plausible_prior, never
  # competitive_score or both.
  ref <- make_ref()
  result <- restore_suppressed_candidates(
    make_match(), ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(restored$restoration_basis == "plausible_prior"))
  expect_true(all(is.na(result$restoration_basis[!result$is_restored])))
})

test_that("restore_suppressed_candidates imputes score from the seq_matrix hierarchy, not a flat delta (0-100 scale)", {
  ref <- make_ref()
  result <- restore_suppressed_candidates(
    make_match(score = 100), ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref, p_match = 0.9),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  # p_match = 0.9 on the seq_matrix's own 0-1 scale -> 90 on match_obj's
  # 0-100 scale, NOT anchor_score (100) minus a flat delta.
  expect_true(all(abs(restored$score_original - 90) < 1e-9))
})

test_that("restore_suppressed_candidates imputes score from the seq_matrix hierarchy, not a flat delta (0-1 scale)", {
  ref <- make_ref()
  m <- make_match(score = 1.0)
  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref, p_match = 0.9),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(abs(restored$score_original - 0.9) < 1e-9))
})

test_that("restore_suppressed_candidates aggregates multiple seq_matrix pairs via median, not max", {
  # Two accessions for the anchor species, giving Level 2 two candidate
  # p_match values (0.80, 0.98) for the SAME congener -- median (0.89)
  # should be imputed, not the max (0.98).
  ref <- data.frame(
    family = "Kyphosidae", genus = "Girella",
    species = c("simplicidens", "simplicidens", "nigricans"),
    composite_id = c("ACC_simp_1", "ACC_simp_2", "ACC_nigr_1"),
    stringsAsFactors = FALSE
  )
  seq_matrix <- data.frame(
    id_x = c("ACC_simp_1", "ACC_simp_2"),
    id_y = c("ACC_nigr_1", "ACC_nigr_1"),
    p_match = c(0.80, 0.98),
    coverage = 1.0,
    stringsAsFactors = FALSE
  )
  m <- make_match(species = "simplicidens")
  m$accession <- "ACC_ANCHOR_NOT_IN_MATRIX"  # forces Level 2, not Level 1
  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = seq_matrix,
    accession_col = "accession",
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_equal(nrow(restored), 1L)
  expect_equal(restored$score_original, 89, tolerance = 1e-9)
})

test_that("restore_suppressed_candidates respects max_per_obs (applied to the admitted set)", {
  ref_big <- make_ref(species = paste0("Sp_", LETTERS[1:15]))
  result <- restore_suppressed_candidates(
    make_match(species = "Sp_A"), ref_big,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref_big),
    max_per_obs = 4L, verbose = FALSE
  )
  expect_equal(sum(result$is_restored), 4L)
})

test_that("restore_suppressed_candidates skips when no congeners in reference", {
  ref_other <- data.frame(
    family = "Kyphosidae", genus = "Medialuna", species = "californiensis",
    composite_id = "ACC_med_1",
    stringsAsFactors = FALSE
  )
  result <- restore_suppressed_candidates(
    make_match(), ref_other,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref_other),
    verbose = FALSE
  )
  expect_equal(nrow(result), 1L)
  expect_false(any(result$is_restored))
})

test_that("restore_suppressed_candidates checks every observation regardless of whether a global suppression rule is detected", {
  # Two rows at different scores -> detect_suppressed_candidates() would not
  # flag a global rule, but this redesign no longer gates on that at all
  # (Purpose A/B are evaluated per observation, unconditionally) -- the
  # missing congener (laevifrons) is still evaluated for restoration.
  ref <- make_ref()
  m <- rbind(make_match("obs1", 100, "Girella", "simplicidens"),
             make_match("obs1", 98,  "Girella", "nigricans"))
  expect_false(detect_suppressed_candidates(m)$rule_detected)
  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  expect_true("laevifrons" %in% result$species[result$is_restored])
})

test_that("restore_suppressed_candidates targets every observation, not just ones matching a suppression rule", {
  ref <- make_ref()
  m <- rbind(
    make_match("obs1", 97, "Girella", "simplicidens"),
    make_match("obs2", 96, "Girella", "nigricans"),
    make_match("obs3", 95, "Girella", "laevifrons")
  )
  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  # Each obs gains congeners that were not its own species; laevifrons for obs1/obs2,
  # nigricans for obs1/obs3, simplicidens for obs2/obs3.
  expect_true(sum(result$is_restored) > 0L)
  # All 3 original observations should have restored rows
  obs_with_restored <- unique(result[[1]][result$is_restored])
  expect_equal(length(obs_with_restored), 3L)
})

test_that("restore_suppressed_candidates handles accession column", {
  ref <- make_ref()
  m <- make_match()
  m$accession <- "ACC_simplicidens"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(nrow(restored) > 0L)
  expect_true(all(grepl("^RESTORED_", restored$accession)))
})

test_that("restore_suppressed_candidates clears coverage for restored rows", {
  ref <- make_ref()
  m <- make_match()
  m$coverage <- 0.98
  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(nrow(restored) > 0L)
  expect_true(all(is.na(restored$coverage)))
  expect_equal(result$coverage[!result$is_restored], 0.98)
})

test_that("restore_suppressed_candidates no-score path creates synthetic scores", {
  m <- make_match()
  m$score_original <- NULL  # remove score column
  result <- restore_suppressed_candidates(
    m, make_ref(),
    rank_system = c("family", "genus", "species"),
    delta = 0.5, verbose = FALSE
  )
  expect_true("score_original" %in% names(result))
  # Original rows: H1 score = 1.0
  expect_equal(result$score_original[!result$is_restored], 1.0)
  # Restored rows: 1.0 - delta/100 = 0.995
  expect_true(all(abs(result$score_original[result$is_restored] - 0.995) < 1e-9))
})

test_that("restore_suppressed_candidates no-score path verbose message has no split-string sprintf warning", {
  # Regression test for a real split-string sprintf() bug (see review response
  # for score_collapse.R): the verbose message previously dropped its whole
  # "(H1 = 1.0, restored = ...)" clause and raised an "arguments not used by
  # format" warning on every verbose=TRUE call through this path.
  m <- make_match()
  m$score_original <- NULL
  call_fn <- function() {
    restore_suppressed_candidates(
      m, make_ref(),
      rank_system = c("family", "genus", "species"),
      delta = 0.5, verbose = TRUE
    )
  }
  expect_message(call_fn(), "H1 = 1.0, restored = 0.9950")
  expect_no_warning(suppressMessages(call_fn()))
})

# ---- .check_regional_overlap() (internal, Session 159) -----------------------
# Synthetic "genome" built from two clearly distinct, non-repetitive 60bp
# regions separated by an 80bp spacer, so local alignment behavior is
# deterministic: a candidate built from region_A should align well to the
# anchor ONLY at region_A's own known coordinates, never at region_B's.

.check_regional_overlap <- function(...) {
  get(".check_regional_overlap", envir = asNamespace("TaxaLikely"))(...)
}

region_A <- "ACGTTGCAATCGGATCCGTAGCTTAACGGTTCCAAGGTTCAGGCTTAACCGGATCGGTA"
region_B <- "TTGGCCAATTCCGGAACCTTGGAACCTTAAGGCCTTAAGGCCAATTGGCCTTAAGGCCA"
spacer   <- "GATTACAGATTACAGATTACAGATTACAGATTACAGATTACAGATTACAGATTACAGA"
anchor_full <- paste0(region_A, spacer, region_B)
# region_A occupies 1-60; region_B occupies (60 + nchar(spacer) + 1)-(that + 60)
region_A_range <- c(1L, 60L)
region_B_start <- nchar(region_A) + nchar(spacer) + 1L
region_B_range <- c(region_B_start, region_B_start + 59L)

# candidate: a few point mutations from region_A (mimics a real congener --
# same region, genuine but small divergence)
.mutate_seq <- function(s, positions, new_bases) {
  chars <- strsplit(s, "")[[1]]
  chars[positions] <- new_bases
  paste(chars, collapse = "")
}
candidate_seq <- .mutate_seq(region_A, c(5, 20, 40), c("T", "A", "G"))

make_overlap_ref_df <- function() {
  data.frame(
    composite_id = c("ANCHOR_ACC", "CANDIDATE_ACC"),
    sequence      = c(anchor_full, candidate_seq),
    genus         = c("Testgenus", "Testgenus"),
    species       = c("Testgenus anchorus", "Testgenus candidatus"),
    stringsAsFactors = FALSE
  )
}

test_that(".check_regional_overlap Tier 2 accepts a candidate overlapping the query's real position", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  result <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = NULL,
    anchor_subject_range   = region_A_range,
    min_coverage           = 0.5
  )
  expect_true(isTRUE(result))
})

test_that(".check_regional_overlap Tier 2 rejects a candidate that does NOT overlap the query's real position", {
  # This is the exact real-world bug (Session 159): the candidate DOES align
  # well to the anchor's full sequence (region_A), but the query itself hit a
  # totally different part of the anchor (region_B) -- must be rejected, not
  # accepted just because SOME good alignment exists somewhere in the anchor.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  result <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = NULL,
    anchor_subject_range   = region_B_range,
    min_coverage           = 0.5
  )
  expect_false(isTRUE(result))
  expect_identical(result, FALSE)
})

test_that(".check_regional_overlap returns NA when anchor_subject_range is missing (Tier 2 unreachable)", {
  result <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = NULL,
    anchor_subject_range   = NULL,
    min_coverage           = 0.5
  )
  expect_true(is.na(result))
})

test_that(".check_regional_overlap returns NA when the anchor's own sequence isn't in reference_df", {
  result <- .check_regional_overlap(
    anchor_accession      = "UNKNOWN_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = NULL,
    anchor_subject_range   = region_A_range,
    min_coverage           = 0.5
  )
  expect_true(is.na(result))
})

test_that(".check_regional_overlap Tier 1 (seq_matrix) short-circuits before Tier 2, no position check needed", {
  # A seq_matrix hit is trusted at face value (no position check) because
  # build_sequence_matrix() only ever includes properly-sized sequences.
  sm <- data.frame(
    id_x = "ANCHOR_ACC", id_y = "CANDIDATE_ACC", coverage = 0.9,
    stringsAsFactors = FALSE
  )
  result <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = sm,
    anchor_subject_range   = NULL,  # Tier 2 unreachable, but Tier 1 doesn't need it
    min_coverage           = 0.5
  )
  expect_true(isTRUE(result))
})

test_that(".check_regional_overlap Tier 2b derives anchor position on the fly from query_sequence", {
  # No anchor_subject_range at all -- only a raw query sequence, mirroring a
  # match_obj with no live BLAST alignment coordinates (e.g. PtConception
  # 12S/18S, built from an externally pre-computed match table). Using
  # region_A itself as the "query" should derive a position overlapping
  # region_A_range and accept the candidate (built from region_A).
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  result <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = NULL,
    anchor_subject_range   = NULL,
    query_sequence         = region_A,
    min_coverage           = 0.5
  )
  expect_true(isTRUE(result))
})

test_that(".check_regional_overlap Tier 2b correctly rejects when the query's derived position doesn't overlap the candidate", {
  # This is the exact real-world case (Session 159): using region_B as the
  # "query" derives a position at region_B's real coordinates, which the
  # candidate (built from region_A) does not overlap.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  result <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = NULL,
    anchor_subject_range   = NULL,
    query_sequence         = region_B,
    min_coverage           = 0.5
  )
  expect_false(isTRUE(result))
  expect_identical(result, FALSE)
})

test_that(".check_regional_overlap prefers Tier 2a (anchor_subject_range) over Tier 2b when both are supplied", {
  # Tier 2a is cheaper (no extra alignment needed to establish the anchor's
  # position) -- supplying a query_sequence that would derive a DIFFERENT
  # (non-overlapping) range must not override an already-known correct one.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")
  result <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = NULL,
    anchor_subject_range   = region_A_range,  # correct, overlapping range
    query_sequence         = region_B,        # would derive a non-overlapping range
    min_coverage           = 0.5
  )
  expect_true(isTRUE(result))
})

test_that(".check_regional_overlap memoizes the (anchor, candidate) alignment via align_cache, but still re-evaluates position overlap per call", {
  # Performance regression (Session 159, continued further): a real Mugu run
  # exceeded 15 minutes for one marker because the same (anchor, candidate)
  # alignment was recomputed once per observation even when many observations
  # shared the same anchor (one real anchor was reused by 113 of 401
  # observations). align_cache must make the SECOND call for the same pair
  # reuse the cached alignment rather than recomputing it.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  cache <- new.env(parent = emptyenv())
  ref <- make_overlap_ref_df()

  # First call: real overlap (region_A_range) -- computes and caches the alignment.
  result1 <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = ref,
    anchor_subject_range   = region_A_range,
    min_coverage           = 0.5,
    align_cache             = cache
  )
  expect_true(isTRUE(result1))
  expect_true(exists("pair::ANCHOR_ACC::CANDIDATE_ACC", envir = cache, inherits = FALSE))

  # Second call: SAME anchor/candidate pair, but reference_df's candidate
  # sequence is now corrupted (would fail to build a DNAString if actually
  # re-parsed/re-aligned), and a DIFFERENT observation's anchor_subject_range
  # (region_B_range, non-overlapping with the candidate's real position). If
  # the alignment were genuinely recomputed against the corrupted sequence,
  # DNAString() would error and the cached tryCatch would store NULL, giving
  # a result indistinguishable from this test's expectation by accident --
  # so this alone doesn't prove reuse. The proof is the position comparison:
  # getting a clean FALSE (not NA) means a real cached subj_start/subj_end
  # from the ORIGINAL alignment was compared against region_B_range, exactly
  # as .check_regional_overlap's non-cached tests already prove for that
  # comparison in isolation.
  ref_corrupted <- ref
  ref_corrupted$sequence[ref_corrupted$composite_id == "CANDIDATE_ACC"] <- "N"
  result2 <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = ref_corrupted,
    anchor_subject_range   = region_B_range,
    min_coverage           = 0.5,
    align_cache             = cache
  )
  expect_identical(result2, FALSE)
})

test_that(".check_regional_overlap memoizes seq_matrix's stripped id_x/id_y via align_cache under a fixed key", {
  # Performance fix (Session 159, PtConception rollout): Tier 1's version-
  # suffix stripping of seq_matrix$id_x/id_y is, on its own, an
  # O(nrow(seq_matrix)) regex pass -- cheap once, but seq_matrix is unchanged
  # across every call sharing one align_cache (one call per candidate species
  # per observation), so recomputing it every call turned "Tier 1, free" into
  # the dominant real cost on real PtConception data: a ~3M-row seq_matrix
  # made sub() alone over 90% of total wall time in profiling, an order of
  # magnitude more than any Tier 2 alignment cost. Verify the cached ids are
  # actually consulted on a later call, not just computed and stored once.
  cache <- new.env(parent = emptyenv())
  sm <- data.frame(
    id_x = "ANCHOR_ACC.1", id_y = "CANDIDATE_ACC.1", coverage = 0.9,
    stringsAsFactors = FALSE
  )
  result1 <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = sm,
    anchor_subject_range   = NULL,
    min_coverage           = 0.5,
    align_cache             = cache
  )
  expect_true(isTRUE(result1))
  expect_true(exists("seq_matrix_ids", envir = cache, inherits = FALSE))

  # Corrupt the cached ids to values that would NOT match this (anchor,
  # candidate) pair. sm itself is unchanged and would still give a genuine
  # Tier 1 hit if the ids were freshly recomputed -- getting NA instead
  # (Tier 1 miss, Tier 2 unreachable since no subject_start/query_sequence is
  # supplied here) proves the corrupted CACHED ids were used, not fresh ones.
  assign("seq_matrix_ids", list(id_x = "OTHER1", id_y = "OTHER2"), envir = cache)
  result2 <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = make_overlap_ref_df(),
    seq_matrix             = sm,
    anchor_subject_range   = NULL,
    min_coverage           = 0.5,
    align_cache             = cache
  )
  expect_true(is.na(result2))
})

test_that(".check_regional_overlap memoizes Tier 2b's query-vs-anchor alignment via align_cache, keyed on (anchor_accession, query_sequence)", {
  # Performance fix (Session 159, PtConception rollout): unlike Tier 2a's
  # anchor_subject_range (supplied directly, no alignment needed), Tier 2b's
  # anchor_subject_range must be DERIVED by aligning query_sequence against
  # the anchor -- and this derivation depends only on (anchor_accession,
  # query_sequence), never on which candidate is being checked. The caller
  # (restore_suppressed_candidates()'s vapply loop) invokes this function once
  # PER CANDIDATE SPECIES for a given observation, so without caching this
  # derivation, an observation with several congeners re-runs the identical
  # query-vs-anchor alignment once per congener -- confirmed a real,
  # measurable cost on real PtConception 12S data. This must be memoized the
  # same way the (anchor, candidate) alignment already is.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  cache <- new.env(parent = emptyenv())
  ref <- make_overlap_ref_df()

  # First call: query_sequence = region_A, a genuine hit at region_A_range,
  # overlapping CANDIDATE_ACC (built from region_A) -- derives and caches
  # anchor_subject_range under a key scoped to (anchor_accession, query_sequence).
  result1 <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = ref,
    anchor_subject_range   = NULL,
    query_sequence         = region_A,
    min_coverage           = 0.5,
    align_cache             = cache
  )
  expect_true(isTRUE(result1))
  query_key <- paste0("query::ANCHOR_ACC::", region_A)
  expect_true(exists(query_key, envir = cache, inherits = FALSE))

  # Second call: SAME anchor_accession + SAME query_sequence (so a real
  # recomputation would derive the identical region_A_range and accept the
  # candidate again) -- but the cached value under that exact key is
  # overwritten with a non-overlapping range (region_B_range) first. Getting
  # a rejection instead of the expected acceptance proves the corrupted
  # CACHED value was consulted and used, not a fresh alignment.
  assign(query_key, region_B_range, envir = cache)
  result2 <- .check_regional_overlap(
    anchor_accession      = "ANCHOR_ACC",
    candidate_accessions  = "CANDIDATE_ACC",
    reference_df          = ref,
    anchor_subject_range   = NULL,
    query_sequence         = region_A,
    min_coverage           = 0.5,
    align_cache             = cache
  )
  expect_identical(result2, FALSE)
})

# ---- restore_suppressed_candidates(check_regional_overlap = TRUE) ------------

test_that("restore_suppressed_candidates errors when check_regional_overlap = TRUE but accession_col is missing", {
  m <- make_match()
  expect_error(
    restore_suppressed_candidates(
      m, make_ref(),
      rank_system = c("family", "genus", "species"),
      check_regional_overlap = TRUE, verbose = FALSE
    ),
    "accession"
  )
})

test_that("restore_suppressed_candidates errors when check_regional_overlap = TRUE but reference_df lacks composite_id/sequence", {
  m <- make_match()
  m$accession <- "ANCHOR_ACC"
  expect_error(
    restore_suppressed_candidates(
      m, make_ref(),
      rank_system = c("family", "genus", "species"),
      check_regional_overlap = TRUE, verbose = FALSE
    ),
    "composite_id"
  )
})

test_that("restore_suppressed_candidates(check_regional_overlap = TRUE) skips a congener with no overlap evidence", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession       <- "ANCHOR_ACC"
  m$subject_start   <- region_B_range[1]
  m$subject_end     <- region_B_range[2]

  ref <- make_overlap_ref_df()
  names(ref)[names(ref) == "species"] <- "species_full"
  ref$species <- c("anchorus", "candidatus")  # match make_match()'s bare species convention
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    verbose                 = FALSE
  )
  # No congener restored -- the only candidate (candidatus) fails the
  # regional-overlap check against the anchor's real hit position (region_B)
  expect_false(any(result$is_restored))
})

test_that("restore_suppressed_candidates(check_regional_overlap = TRUE) restores a congener with real overlap evidence", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession       <- "ANCHOR_ACC"
  m$subject_start   <- region_A_range[1]
  m$subject_end     <- region_A_range[2]

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    verbose                 = FALSE
  )
  expect_true(any(result$is_restored))
  expect_true("candidatus" %in% result$species[result$is_restored])
})

test_that("restore_suppressed_candidates(check_regional_overlap = TRUE): two observations sharing the same anchor accession are each still decided correctly (align_cache correctness, not just speed)", {
  # The align_cache fix (Session 159, continued further) memoizes the
  # (anchor, candidate) alignment across observations that share an anchor --
  # exactly this shape. Confirms the cache stores the ALIGNMENT, not the
  # final position-overlap verdict: obs1's real hit region (region_A) and
  # obs2's real hit region (region_B) must each get their own correct,
  # independent answer despite sharing every other input.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m1 <- make_match(obs_id = "obs_overlap", genus = "Testgenus", species = "anchorus")
  m1$accession <- "ANCHOR_ACC"; m1$subject_start <- region_A_range[1]; m1$subject_end <- region_A_range[2]
  m2 <- make_match(obs_id = "obs_no_overlap", genus = "Testgenus", species = "anchorus")
  m2$accession <- "ANCHOR_ACC"; m2$subject_start <- region_B_range[1]; m2$subject_end <- region_B_range[2]
  m <- dplyr::bind_rows(m1, m2)
  m$family <- "Kyphosidae"

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    verbose                 = FALSE
  )
  restored_obs <- unique(result$observation_id[result$is_restored])
  expect_equal(restored_obs, "obs_overlap")

  reg <- attr(result, "regional_unreferenced")
  expect_equal(reg$observation_id, "obs_no_overlap")
  expect_equal(reg$species, "candidatus")
  expect_equal(reg$basis, "regional_reject")
})

test_that("restore_suppressed_candidates(check_regional_overlap = TRUE, sequence_col = ...) uses Tier 2b when there's no subject_start/subject_end at all", {
  # Mirrors a match_obj with no live BLAST step (e.g. PtConception 12S/18S):
  # no accession-based coordinates, only a raw query sequence column.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession <- "ANCHOR_ACC"
  m$my_sequence <- region_B  # query "hit" region_B's real position

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    sequence_col            = "my_sequence",
    verbose                 = FALSE
  )
  # candidatus (built from region_A) does not overlap region_B -- must be
  # skipped, not restored, exactly as the accession-coordinate (Tier 2a)
  # tests above expect for the same real scenario.
  expect_false(any(result$is_restored))
})

test_that("restore_suppressed_candidates(candidate_species_filter = ...) excludes a real-overlap congener not on the plausibility list, from Level 4 itself now (Option A, 2026-07-18)", {
  # Cost-control redesign (2026-07-18, following real Mugu/PtConception
  # testing): candidate_species_filter is Level 4's own default gate again --
  # candidatus has REAL overlap evidence (region_A_range) but is excluded
  # here by the filter BEFORE the expensive alignment ever runs, not merely
  # denied admission afterward. Unlike the pre-redesign version, this is not
  # silent -- it's recorded in regional_unreferenced with basis
  # "no_reference_data" (never checked), distinct from "regional_reject"
  # (checked, found no overlap).
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession       <- "ANCHOR_ACC"
  m$subject_start   <- region_A_range[1]
  m$subject_end     <- region_A_range[2]

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system              = c("family", "genus", "species"),
    check_regional_overlap   = TRUE,
    candidate_species_filter = "some_other_species",  # candidatus not on the list
    verbose                   = FALSE
  )
  expect_false(any(result$is_restored))
  reg <- attr(result, "regional_unreferenced")
  expect_false(is.null(reg))
  expect_equal(reg$species, "candidatus")
  expect_equal(reg$basis, "no_reference_data")
})

test_that("restore_suppressed_candidates(candidate_species_filter = NULL) is unaffected (default, backward compatible)", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession       <- "ANCHOR_ACC"
  m$subject_start   <- region_A_range[1]
  m$subject_end     <- region_A_range[2]

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    verbose                 = FALSE
  )
  expect_true(any(result$is_restored))
  expect_true("candidatus" %in% result$species[result$is_restored])
})

test_that("restore_suppressed_candidates(check_regional_overlap = FALSE) restores via the free Levels 1-3 hierarchy alone, and never populates regional_unreferenced", {
  # No accession/subject_start/subject_end columns needed -- Levels 1-3 are
  # all seq_matrix lookups, no live alignment. Level 4 (the only source of
  # regional_unreferenced entries) is never reached when
  # check_regional_overlap = FALSE.
  ref <- make_ref()
  result <- restore_suppressed_candidates(
    make_match(), ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose = FALSE
  )
  expect_equal(nrow(result), 3L)
  expect_true(any(result$is_restored))
  expect_null(attr(result, "regional_unreferenced"))
})

# ---- restoration_level / restoration_source_accession (2026-08-08) ----------
# Lets a caller screen restored rows for reference-accession quality
# (e.g. TaxaMatch::evaluate_reference_accessions()) wherever that's
# actually possible -- Level 1 with exactly one contributing candidate
# accession only. make_match()/make_ref() have no `accession` column by
# default, so these tests add one explicitly to exercise Level 1 at all
# (without it, anchor_accession is NA and Level 1 never fires).

test_that("restore_suppressed_candidates: Level 1 with one contributing accession sets restoration_source_accession", {
  ref <- make_ref(species = c("simplicidens", "nigricans"))
  m <- make_match(species = "simplicidens")
  m$accession <- "ACC_simplicidens"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose     = FALSE
  )
  restored <- result[result$is_restored, , drop = FALSE]
  expect_equal(nrow(restored), 1L)
  expect_equal(restored$species, "nigricans")
  expect_equal(restored$restoration_level, 1L)
  expect_equal(restored$restoration_source_accession, "ACC_nigricans")
  # Original (non-restored) row gets NA for both new columns.
  orig <- result[!result$is_restored, , drop = FALSE]
  expect_true(is.na(orig$restoration_level))
  expect_true(is.na(orig$restoration_source_accession))
})

test_that("restore_suppressed_candidates: Level 1 with >1 contributing accession leaves restoration_source_accession NA", {
  ref <- make_ref(species = c("simplicidens", "nigricans"))
  ref <- rbind(ref, data.frame(
    family = "Kyphosidae", genus = "Girella", species = "nigricans",
    composite_id = "ACC_nigricans_2", stringsAsFactors = FALSE
  ))
  m <- make_match(species = "simplicidens")
  m$accession <- "ACC_simplicidens"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    seq_matrix  = make_seq_matrix_for_ref(ref),
    verbose     = FALSE
  )
  restored <- result[result$is_restored, , drop = FALSE]
  expect_equal(nrow(restored), 1L)
  expect_equal(restored$restoration_level, 1L)
  expect_true(is.na(restored$restoration_source_accession))
})

# ---- regional_unreferenced attribute (Session 159 extension) ----------------
# A congener rejected by check_regional_overlap is no longer just dropped --
# it's recorded via attr(result, "regional_unreferenced") so a caller can feed
# it to expand_unreferenced_hypotheses() as an observation-scoped addition.

test_that("restore_suppressed_candidates records a rejected congener in attr(result, \"regional_unreferenced\")", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(obs_id = "ASV_300", genus = "Testgenus", species = "anchorus")
  m$accession       <- "ANCHOR_ACC"
  m$subject_start   <- region_B_range[1]
  m$subject_end     <- region_B_range[2]

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    verbose                 = FALSE
  )
  reg <- attr(result, "regional_unreferenced")
  expect_false(is.null(reg))
  expect_equal(nrow(reg), 1L)
  expect_equal(reg$observation_id, "ASV_300")
  expect_equal(reg$species, "candidatus")
  expect_equal(reg$genus, "Testgenus")
  expect_equal(reg$family, "Kyphosidae")
  expect_equal(reg$basis, "regional_reject")
})

test_that("restore_suppressed_candidates: regional_unreferenced is NULL when nothing was rejected", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession       <- "ANCHOR_ACC"
  m$subject_start   <- region_A_range[1]
  m$subject_end     <- region_A_range[2]

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    verbose                 = FALSE
  )
  expect_true(any(result$is_restored))
  expect_null(attr(result, "regional_unreferenced"))
})

test_that("restore_suppressed_candidates(check_regional_overlap = TRUE) still checks a true singleton observation even when NO global suppression rule is detected", {
  # Real-data regression (Session 159, continued): a real 12S dataset with
  # TaxaMatch::blast_sequences(score_range = 8) is a genuine MIX of true
  # singletons and real multi-candidate ties -- neither purity threshold
  # clears its bar in aggregate (detect_suppressed_candidates() correctly
  # reports rule_detected = FALSE), even though a specific singleton
  # observation (like this fixture's "obs1") is exactly the case this
  # mechanism exists to catch. Before this fix, the whole per-observation
  # loop -- including check_regional_overlap -- never ran at all when no
  # global rule was detected, so obs1's rejected congener was silently lost.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- dplyr::bind_rows(
    data.frame(observation_id = "obs1", score_original = 90, family = "Kyphosidae",
               genus = "Testgenus", species = "anchorus", accession = "ANCHOR_ACC",
               subject_start = region_B_range[1], subject_end = region_B_range[2],
               stringsAsFactors = FALSE),
    data.frame(observation_id = "obs2", score_original = c(85, 80), family = "Kyphosidae",
               genus = "Girella", species = c("simplicidens", "nigricans"),
               accession = NA_character_, subject_start = NA_real_, subject_end = NA_real_,
               stringsAsFactors = FALSE),
    data.frame(observation_id = "obs3", score_original = 70, family = "Kyphosidae",
               genus = "Girella", species = "laevifrons",
               accession = NA_character_, subject_start = NA_real_, subject_end = NA_real_,
               stringsAsFactors = FALSE),
    data.frame(observation_id = "obs4", score_original = c(60, 55, 50), family = "Kyphosidae",
               genus = "Girella", species = c("simplicidens", "nigricans", "laevifrons"),
               accession = NA_character_, subject_start = NA_real_, subject_end = NA_real_,
               stringsAsFactors = FALSE)
  )
  # Self-checking precondition: confirms this fixture really does reproduce
  # the real-data "no global rule detected" scenario, not just a guess.
  expect_false(detect_suppressed_candidates(m)$rule_detected)

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    verbose                 = FALSE
  )
  reg <- attr(result, "regional_unreferenced")
  expect_false(is.null(reg))
  expect_equal(reg$observation_id, "obs1")
  expect_equal(reg$species, "candidatus")
})

test_that("restore_suppressed_candidates: regional_unreferenced feeds expand_unreferenced_hypotheses() correctly, scoped to one observation", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  # Two observations sharing the anchor genus/species; only ASV_300's anchor
  # hit region_B (non-overlapping with candidatus's real reference at
  # region_A), so only ASV_300 should get candidatus recorded as rejected.
  m1 <- make_match(obs_id = "ASV_300", genus = "Testgenus", species = "anchorus")
  m1$accession <- "ANCHOR_ACC"; m1$subject_start <- region_B_range[1]; m1$subject_end <- region_B_range[2]
  m2 <- make_match(obs_id = "ASV_099", genus = "Testgenus", species = "anchorus")
  m2$accession <- "ANCHOR_ACC"; m2$subject_start <- region_A_range[1]; m2$subject_end <- region_A_range[2]
  m <- dplyr::bind_rows(m1, m2)
  m$family <- "Kyphosidae"

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system            = c("family", "genus", "species"),
    check_regional_overlap = TRUE,
    verbose                 = FALSE
  )
  reg <- attr(result, "regional_unreferenced")
  expect_equal(nrow(reg), 1L)
  expect_equal(reg$observation_id, "ASV_300")

  # Feed straight into expand_unreferenced_hypotheses(): a minimal likelihood_df
  # with generic H2 rows for both observations -- candidatus should expand
  # only for ASV_300.
  lik <- data.frame(
    observation_id        = c("ASV_300", "ASV_099"),
    taxon_name            = c("Testgenus", "Testgenus"),
    taxon_name_rank       = c("genus", "genus"),
    hypothesis_type       = c("unreferenced_species", "unreferenced_species"),
    score_likelihood      = c(0.31, 0.31),
    score_likelihood_mean = c(0.31, 0.31),
    score_likelihood_sd   = c(0, 0),
    stringsAsFactors      = FALSE
  )
  expanded <- expand_unreferenced_hypotheses(lik, reg)
  h2_300 <- expanded[expanded$observation_id == "ASV_300", ]
  h2_099 <- expanded[expanded$observation_id == "ASV_099", ]
  expect_true("candidatus" %in% h2_300$taxon_name)
  expect_equal(nrow(h2_099), 0L)  # no match in reg for ASV_099 -- generic row dropped
})

# ---- Purpose A / Purpose B admission (design spec Section 2) -----------------

.simple_model_params <- function(sigma11 = 0.05) {
  list(
    H1_Sigma = matrix(c(sigma11, 0, 0, 1), nrow = 2,
                      dimnames = list(c("score_logit", "gap_logit"),
                                      c("score_logit", "gap_logit"))),
    H1_Lookup = NULL,
    Score_Transform = "logit"
  )
}

test_that("restore_suppressed_candidates: Purpose A (competitive_score) admits a candidate statistically close to the anchor's own observed score, Purpose B (plausible_prior) admits a farther-but-still-plausible one", {
  ref <- make_ref()
  # nigricans: p_match nearly identical to the anchor's own 95 -- should
  # clear Purpose A's tight outlier test. laevifrons: p_match well below
  # (80), still clears Purpose B's wide max_dist floor (>= 75) but is far
  # enough in logit space to fail Purpose A under this tight sigma.
  seq_matrix <- data.frame(
    id_x = c("ACC_simplicidens", "ACC_simplicidens"),
    id_y = c("ACC_nigricans", "ACC_laevifrons"),
    p_match = c(0.945, 0.80),
    coverage = 1.0,
    stringsAsFactors = FALSE
  )
  m <- make_match(score = 95)

  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    seq_matrix = seq_matrix, model_params = .simple_model_params(), verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  # nigricans clears BOTH gates here (no candidate_species_filter narrows
  # Purpose B), so its basis is "both", not just "competitive_score".
  expect_equal(restored$restoration_basis[restored$species == "nigricans"], "both")
  expect_equal(restored$restoration_basis[restored$species == "laevifrons"], "plausible_prior")
})

test_that("restore_suppressed_candidates: Purpose A is never gated by candidate_species_filter", {
  # Only two species in the genus -- avoids Level 3's genus-wide raw-median
  # fallback picking up a THIRD species via this one explicit pair (which
  # would otherwise also resolve and confound this test's single-candidate
  # expectation).
  ref <- make_ref(species = c("simplicidens", "nigricans"))
  seq_matrix <- data.frame(
    id_x = "ACC_simplicidens", id_y = "ACC_nigricans", p_match = 0.945, coverage = 1.0,
    stringsAsFactors = FALSE
  )
  m <- make_match(score = 95)

  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    seq_matrix = seq_matrix, model_params = .simple_model_params(),
    candidate_species_filter = "some_other_species_not_nigricans",
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  # Purpose B is blocked (nigricans isn't on the filter) but Purpose A still
  # admits it on score evidence alone -- exactly "competitive_score", not "both".
  expect_equal(restored$species, "nigricans")
  expect_equal(restored$restoration_basis, "competitive_score")
})

test_that("restore_suppressed_candidates: without model_params, Purpose A never admits anything (Purpose B only)", {
  # Only two species in the genus -- avoids Level 3's genus-wide raw-median
  # fallback picking up a THIRD species via this one explicit pair (which
  # would otherwise also resolve and confound this test's single-candidate
  # expectation).
  ref <- make_ref(species = c("simplicidens", "nigricans"))
  seq_matrix <- data.frame(
    id_x = "ACC_simplicidens", id_y = "ACC_nigricans", p_match = 0.945, coverage = 1.0,
    stringsAsFactors = FALSE
  )
  m <- make_match(score = 95)
  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    seq_matrix = seq_matrix, verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_equal(restored$restoration_basis, "plausible_prior")
})

# ---- Level 0 precheck routing (design spec Section 3a) -----------------------

test_that("restore_suppressed_candidates routes straight to Level 4 when the anchor species has zero seq_matrix presence anywhere", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession     <- "ANCHOR_ACC"
  m$subject_start <- region_A_range[1]
  m$subject_end   <- region_A_range[2]

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  # seq_matrix exists but has nothing to do with ANCHOR_ACC/CANDIDATE_ACC --
  # the Level 0 precheck must find zero presence and route straight to
  # Level 4 rather than silently (mis)resolving via an unrelated pair.
  seq_matrix <- data.frame(
    id_x = "SOME_OTHER_ACC1", id_y = "SOME_OTHER_ACC2", p_match = 0.5, coverage = 1.0,
    stringsAsFactors = FALSE
  )

  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    seq_matrix = seq_matrix, check_regional_overlap = TRUE, verbose = FALSE
  )
  expect_true(any(result$is_restored))
  expect_true("candidatus" %in% result$species[result$is_restored])
})

# ---- Compute-budget mechanism (design spec Section 3b) ------------------------

test_that("restore_suppressed_candidates: compute-budget mechanism skips Level 4 and records no_reference_data when R > budget_ratio_cap", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession     <- "ANCHOR_ACC"
  m$subject_start <- region_A_range[1]
  m$subject_end   <- region_A_range[2]
  m$grid_id       <- "grid1"

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  # anchor's own prior is 100x the candidate's -- ratio 100 > budget_ratio_cap (19)
  taxaexpect_priors <- data.frame(
    taxon_name = c("anchorus", "candidatus"),
    grid_id    = c("grid1", "grid1"),
    theta_mean = c(0.50, 0.005),
    stringsAsFactors = FALSE
  )

  # candidatus is NOT on candidate_species_filter -- the ratio fallback is
  # what this test exercises (Option A, 2026-07-18): a candidate ON the
  # filter would always be checked regardless of the ratio.
  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    check_regional_overlap = TRUE, taxaexpect_priors = taxaexpect_priors,
    candidate_species_filter = "some_other_species",
    verbose = FALSE
  )
  expect_false(any(result$is_restored))
  reg <- attr(result, "regional_unreferenced")
  expect_false(is.null(reg))
  expect_equal(reg$species, "candidatus")
  expect_equal(reg$basis, "no_reference_data")
})

test_that("restore_suppressed_candidates: compute-budget mechanism allows Level 4 spend when R <= budget_ratio_cap, for a candidate not on the filter", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession     <- "ANCHOR_ACC"
  m$subject_start <- region_A_range[1]
  m$subject_end   <- region_A_range[2]
  m$grid_id       <- "grid1"

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  taxaexpect_priors <- data.frame(
    taxon_name = c("anchorus", "candidatus"),
    grid_id    = c("grid1", "grid1"),
    theta_mean = c(0.50, 0.05),  # ratio 10 <= 19
    stringsAsFactors = FALSE
  )

  # candidate_species_filter deliberately excludes candidatus from Purpose B
  # too (isolating this test to the Level 4 gate specifically) -- a generous
  # model_params lets Purpose A admit it on score evidence once Level 4
  # resolves a real (high, since only 3/60bp mutated) score for it.
  model_params <- list(
    H1_Sigma = matrix(c(10, 0, 0, 1), nrow = 2,
                      dimnames = list(c("score_logit", "gap_logit"),
                                      c("score_logit", "gap_logit"))),
    H1_Lookup = NULL, Score_Transform = "logit"
  )

  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    check_regional_overlap = TRUE, taxaexpect_priors = taxaexpect_priors,
    candidate_species_filter = "some_other_species", model_params = model_params,
    verbose = FALSE
  )
  expect_true(any(result$is_restored))
  expect_true("candidatus" %in% result$species[result$is_restored])
})

test_that("restore_suppressed_candidates: a candidate ON candidate_species_filter is always checked, regardless of the ratio", {
  # Option A's default gate: candidate_species_filter alone is sufficient,
  # the ratio is only a fallback for candidates NOT on the filter.
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession     <- "ANCHOR_ACC"
  m$subject_start <- region_A_range[1]
  m$subject_end   <- region_A_range[2]
  m$grid_id       <- "grid1"

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  # Ratio of 100 would fail the budget test on its own, but candidatus IS on
  # the filter, so the ratio is never even consulted.
  taxaexpect_priors <- data.frame(
    taxon_name = c("anchorus", "candidatus"),
    grid_id    = c("grid1", "grid1"),
    theta_mean = c(0.50, 0.005),
    stringsAsFactors = FALSE
  )

  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    check_regional_overlap = TRUE, taxaexpect_priors = taxaexpect_priors,
    candidate_species_filter = "candidatus",
    verbose = FALSE
  )
  expect_true(any(result$is_restored))
  expect_true("candidatus" %in% result$species[result$is_restored])
})

test_that("restore_suppressed_candidates: compute-budget treats a candidate absent from taxaexpect_priors the same as R > budget_ratio_cap", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession     <- "ANCHOR_ACC"
  m$subject_start <- region_A_range[1]
  m$subject_end   <- region_A_range[2]
  m$grid_id       <- "grid1"

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  # candidatus never appears in taxaexpect_priors at all
  taxaexpect_priors <- data.frame(
    taxon_name = "anchorus", grid_id = "grid1", theta_mean = 0.5,
    stringsAsFactors = FALSE
  )

  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    check_regional_overlap = TRUE, taxaexpect_priors = taxaexpect_priors,
    candidate_species_filter = "some_other_species",
    verbose = FALSE
  )
  expect_false(any(result$is_restored))
  reg <- attr(result, "regional_unreferenced")
  expect_equal(reg$basis, "no_reference_data")
})

test_that("restore_suppressed_candidates: taxaexpect_priors = NULL (default) never gates Level 4 spend", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession     <- "ANCHOR_ACC"
  m$subject_start <- region_A_range[1]
  m$subject_end   <- region_A_range[2]

  ref <- make_overlap_ref_df()
  ref$species <- c("anchorus", "candidatus")
  ref$family  <- "Kyphosidae"
  m$family    <- "Kyphosidae"

  result <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    check_regional_overlap = TRUE, verbose = FALSE
  )
  expect_true(any(result$is_restored))
})

# ---- Level 4 pid score-sourcing (.check_regional_overlap return_detail) ------

test_that(".check_regional_overlap(return_detail = TRUE) returns overlap + a real percent-identity pid", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  detail <- .check_regional_overlap(
    anchor_accession     = "ANCHOR_ACC",
    candidate_accessions = "CANDIDATE_ACC",
    reference_df         = make_overlap_ref_df(),
    anchor_subject_range = region_A_range,
    return_detail         = TRUE
  )
  expect_true(isTRUE(detail$overlap))
  # candidate_seq is region_A with 3 point mutations out of 60bp -> ~95% identity
  expect_true(!is.na(detail$pid) && detail$pid > 85 && detail$pid <= 100)
})

test_that(".check_regional_overlap(return_detail = TRUE) returns overlap = FALSE, pid = NA when position doesn't overlap", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  detail <- .check_regional_overlap(
    anchor_accession     = "ANCHOR_ACC",
    candidate_accessions = "CANDIDATE_ACC",
    reference_df         = make_overlap_ref_df(),
    anchor_subject_range = region_B_range,
    return_detail         = TRUE
  )
  expect_false(isTRUE(detail$overlap))
  expect_true(is.na(detail$pid))
})

test_that(".check_regional_overlap(return_detail = TRUE) returns overlap = NA, pid = NA when there is no evidence at all", {
  detail <- .check_regional_overlap(
    anchor_accession     = NA_character_,
    candidate_accessions = "CANDIDATE_ACC",
    reference_df         = make_overlap_ref_df(),
    return_detail         = TRUE
  )
  expect_true(is.na(detail$overlap))
  expect_true(is.na(detail$pid))
})

# ---- Option C: max_level4_per_anchor backstop (2026-07-18) --------------------

test_that(".level4_attempt_allowed enforces a per-anchor cap and Inf disables it", {
  env <- new.env(parent = emptyenv())
  expect_true(.level4_attempt_allowed("ACC1", 2L, env))   # 1st: allowed
  expect_true(.level4_attempt_allowed("ACC1", 2L, env))   # 2nd: allowed
  expect_false(.level4_attempt_allowed("ACC1", 2L, env))  # 3rd: capped
  # a different anchor has its own independent counter
  expect_true(.level4_attempt_allowed("ACC2", 2L, env))
  # Inf disables the cap entirely, even after many prior calls
  for (i in 1:5) expect_true(.level4_attempt_allowed("ACC1", Inf, env))
  # no cache -- fails open (never blocks)
  expect_true(.level4_attempt_allowed("ACC1", 1L, NULL))
})

test_that("restore_suppressed_candidates: max_level4_per_anchor caps the number of live alignments attempted for one anchor", {
  skip_if_not_installed("Biostrings")
  skip_if_not_installed("pwalign")

  # Three independent candidates, each a distinct mutation of region_A, each
  # of which would individually pass the regional-overlap check on its own
  # (confirmed by the uncapped case below) -- the cap should still stop at
  # exactly 1 live alignment attempt when max_level4_per_anchor = 1L.
  cand1 <- .mutate_seq(region_A, c(5, 20, 40), c("T", "A", "G"))
  cand2 <- .mutate_seq(region_A, c(6, 21, 41), c("T", "A", "G"))
  cand3 <- .mutate_seq(region_A, c(7, 22, 42), c("T", "A", "G"))

  ref <- data.frame(
    composite_id = c("ANCHOR_ACC", "CAND1_ACC", "CAND2_ACC", "CAND3_ACC"),
    sequence      = c(anchor_full, cand1, cand2, cand3),
    genus         = "Testgenus",
    species       = c("Testgenus anchorus", "Testgenus cand1",
                      "Testgenus cand2", "Testgenus cand3"),
    stringsAsFactors = FALSE
  )
  ref$species <- c("anchorus", "cand1", "cand2", "cand3")
  ref$family  <- "Kyphosidae"

  m <- make_match(genus = "Testgenus", species = "anchorus")
  m$accession     <- "ANCHOR_ACC"
  m$subject_start <- region_A_range[1]
  m$subject_end   <- region_A_range[2]
  m$family        <- "Kyphosidae"

  result_capped <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    check_regional_overlap = TRUE, max_level4_per_anchor = 1L, verbose = FALSE
  )
  reg_capped <- attr(result_capped, "regional_unreferenced")
  # Exactly 1 candidate should have a real verdict (restored or
  # regional_reject); the rest must be "no_reference_data" (never attempted).
  n_reject <- if (is.null(reg_capped)) 0L else sum(reg_capped$basis == "regional_reject")
  n_attempted <- sum(result_capped$is_restored) + n_reject
  expect_equal(n_attempted, 1L)
  expect_true(sum(reg_capped$basis == "no_reference_data") >= 2L)

  result_uncapped <- restore_suppressed_candidates(
    m, ref, rank_system = c("family", "genus", "species"),
    check_regional_overlap = TRUE, max_level4_per_anchor = Inf, verbose = FALSE
  )
  # Uncapped: all three independently pass regional overlap and get restored.
  expect_equal(sum(result_uncapped$is_restored), 3L)
})
