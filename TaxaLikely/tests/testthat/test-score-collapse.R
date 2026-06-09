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
  # obs1: singleton at 100 (pure); obs2: 100 + 97 (impure — has sub-threshold row)
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
    family  = "Kyphosidae",
    genus   = genus,
    species = species,
    stringsAsFactors = FALSE
  )
}

test_that("restore_suppressed_candidates adds congeners from reference", {
  result <- restore_suppressed_candidates(
    make_match(), make_ref(),
    rank_system = c("family", "genus", "species"),
    verbose = FALSE
  )
  expect_equal(nrow(result), 3L)  # 1 original + 2 restored
  expect_true(any(result$is_restored))
  expect_setequal(result$species,
                  c("simplicidens", "nigricans", "laevifrons"))
})

test_that("restore_suppressed_candidates adds is_restored column", {
  result <- restore_suppressed_candidates(
    make_match(), make_ref(),
    rank_system = c("family", "genus", "species"),
    verbose = FALSE
  )
  expect_true("is_restored" %in% names(result))
  expect_equal(sum(!result$is_restored), 1L)
  expect_equal(sum(result$is_restored), 2L)
})

test_that("restore_suppressed_candidates marks hypothesis_type = suppressed_candidate", {
  result <- restore_suppressed_candidates(
    make_match(), make_ref(),
    rank_system = c("family", "genus", "species"),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(restored$hypothesis_type == "suppressed_candidate"))
})

test_that("restore_suppressed_candidates imputes score using delta (0-100 scale)", {
  result <- restore_suppressed_candidates(
    make_match(score = 100), make_ref(),
    rank_system = c("family", "genus", "species"),
    delta = 0.5, verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(abs(restored$score_original - 99.5) < 1e-9))
})

test_that("restore_suppressed_candidates imputes score using delta (0-1 scale)", {
  m <- make_match(score = 1.0)
  result <- restore_suppressed_candidates(
    m, make_ref(),
    rank_system = c("family", "genus", "species"),
    delta = 0.5, verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  # delta/100 = 0.005; imputed = 1.0 - 0.005 = 0.995
  expect_true(all(abs(restored$score_original - 0.995) < 1e-9))
})

test_that("restore_suppressed_candidates respects max_per_obs", {
  ref_big <- make_ref(species = paste0("Sp_", LETTERS[1:15]))
  result <- restore_suppressed_candidates(
    make_match(species = "Sp_A"), ref_big,
    rank_system = c("family", "genus", "species"),
    max_per_obs = 4L, verbose = FALSE
  )
  expect_equal(sum(result$is_restored), 4L)
})

test_that("restore_suppressed_candidates skips when no congeners in reference", {
  ref_other <- data.frame(
    family = "Kyphosidae", genus = "Medialuna", species = "californiensis",
    stringsAsFactors = FALSE
  )
  result <- restore_suppressed_candidates(
    make_match(), ref_other,
    rank_system = c("family", "genus", "species"),
    verbose = FALSE
  )
  expect_equal(nrow(result), 1L)
  expect_false(any(result$is_restored))
})

test_that("restore_suppressed_candidates does nothing when no rule detected", {
  # Two rows at different scores -> no rule detected
  m <- rbind(make_match("obs1", 100, "Girella", "simplicidens"),
             make_match("obs1", 98,  "Girella", "nigricans"))
  result <- restore_suppressed_candidates(
    m, make_ref(),
    rank_system = c("family", "genus", "species"),
    verbose = FALSE
  )
  expect_equal(nrow(result), 2L)
  expect_false(any(result$is_restored))
})

test_that("restore_suppressed_candidates targets all obs for best_only rule", {
  # best_only: three singletons at sub-perfect scores
  m <- rbind(
    make_match("obs1", 97, "Girella", "simplicidens"),
    make_match("obs2", 96, "Girella", "nigricans"),
    make_match("obs3", 95, "Girella", "laevifrons")
  )
  result <- restore_suppressed_candidates(
    m, make_ref(),
    rank_system = c("family", "genus", "species"),
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
  m <- make_match()
  m$accession <- "AB12345.1"
  ref <- make_ref()
  ref$accession <- c("AB12345.1", "CD67890.1", "EF11111.1")

  result <- restore_suppressed_candidates(
    m, ref,
    rank_system = c("family", "genus", "species"),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(grepl("^RESTORED_", restored$accession)))
})

test_that("restore_suppressed_candidates clears coverage for restored rows", {
  m <- make_match()
  m$coverage <- 0.98
  result <- restore_suppressed_candidates(
    m, make_ref(),
    rank_system = c("family", "genus", "species"),
    verbose = FALSE
  )
  restored <- result[result$is_restored, ]
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
