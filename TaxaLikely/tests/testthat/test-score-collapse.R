# Tests for detect_score_collapse() and restore_suppressed_candidates()
# All tests are fully offline.

# ---- detect_score_collapse() -------------------------------------------------

test_that("detect_score_collapse detects perfect_only rule (0-100 scale)", {
  m <- data.frame(
    observation_id = c("obs1", "obs2", "obs3", "obs3"),
    score_original = c(100, 100, 98, 97),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D"),
    stringsAsFactors = FALSE
  )
  res <- detect_score_collapse(m)
  expect_true(res$rule_detected)
  expect_equal(res$type, "perfect_only")
  expect_equal(res$n_perfect_only, 2L)
  expect_equal(res$n_ties_only, 0L)
  expect_equal(res$n_total, 3L)
})

test_that("detect_score_collapse detects perfect_only rule (0-1 scale)", {
  m <- data.frame(
    observation_id = c("obs1", "obs2", "obs3", "obs3"),
    score_original = c(1.0, 1.0, 0.97, 0.95),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D"),
    stringsAsFactors = FALSE
  )
  res <- detect_score_collapse(m)
  expect_true(res$rule_detected)
  expect_equal(res$type, "perfect_only")
})

test_that("detect_score_collapse detects max_score_ties rule", {
  # obs1: two candidates at same score (ties); obs2: singleton below perfect
  m <- data.frame(
    observation_id = c("obs1", "obs1", "obs2"),
    score_original = c(98, 98, 97),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C"),
    stringsAsFactors = FALSE
  )
  res <- detect_score_collapse(m)
  expect_true(res$rule_detected)
  expect_equal(res$type, "max_score_ties")
  expect_equal(res$n_ties_only, 1L)
  expect_equal(res$n_perfect_only, 0L)
})

test_that("detect_score_collapse returns 'both' when both patterns present", {
  m <- data.frame(
    observation_id = c("obs1", "obs2", "obs2", "obs3", "obs3"),
    score_original = c(100,   98,    98,    97,    93),
    taxon_name     = c("A",   "B",   "C",   "D",   "E"),
    stringsAsFactors = FALSE
  )
  # obs1: singleton at 100 -> perfect_only
  # obs2: two candidates at same score -> ties_only
  # obs3: two candidates at different scores -> neither
  res <- detect_score_collapse(m)
  expect_true(res$rule_detected)
  expect_equal(res$type, "both")
})

test_that("detect_score_collapse returns none for normal multi-candidate data", {
  m <- data.frame(
    observation_id = c("obs1", "obs1", "obs2", "obs2"),
    score_original = c(98, 95, 97, 93),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D"),
    stringsAsFactors = FALSE
  )
  res <- detect_score_collapse(m)
  expect_false(res$rule_detected)
  expect_equal(res$type, "none")
})

test_that("detect_score_collapse respects min_fraction threshold", {
  # obs1 is singleton at 100; obs2..obs25 each have 2 candidates at different scores
  # fraction_perfect_only = 1/25 = 0.04
  obs_ids <- c("obs1", rep(paste0("obs", 2:25), each = 2L))
  scores  <- c(100, rep(c(98, 95), 24L))
  m <- data.frame(
    observation_id = obs_ids,
    score_original = scores,
    taxon_name     = paste0("Sp_", seq_along(obs_ids)),
    stringsAsFactors = FALSE
  )
  # 0.04 < 0.05 -> not detected at default threshold
  res <- detect_score_collapse(m, min_fraction = 0.05)
  expect_false(res$rule_detected)

  # 0.04 > 0.03 -> detected at relaxed threshold
  res2 <- detect_score_collapse(m, min_fraction = 0.03)
  expect_true(res2$rule_detected)
})

test_that("detect_score_collapse errors on missing score column", {
  m <- data.frame(observation_id = "obs1", taxon_name = "Sp_A")
  expect_error(detect_score_collapse(m), "score column")
})

test_that("detect_score_collapse errors on missing observation_id column", {
  m <- data.frame(score_original = 100, taxon_name = "Sp_A")
  expect_error(detect_score_collapse(m), "observation ID column")
})

test_that("detect_score_collapse example_observations contains affected IDs", {
  m <- data.frame(
    observation_id = c("ESV001", "ESV002", "ESV003", "ESV003"),
    score_original = c(100, 100, 98, 95),
    taxon_name     = c("Sp_A", "Sp_B", "Sp_C", "Sp_D"),
    stringsAsFactors = FALSE
  )
  res <- detect_score_collapse(m)
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
  expect_setequal(result$taxon_name,
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

test_that("restore_suppressed_candidates imputes sub_max score on 0-100 scale", {
  result <- restore_suppressed_candidates(
    make_match(score = 100), make_ref(),
    rank_system = c("family", "genus", "species"),
    score_rule = "sub_max", verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(restored$score_original == 99))
})

test_that("restore_suppressed_candidates imputes sub_max score on 0-1 scale", {
  m <- make_match(score = 1.0)
  m$score_original <- 1.0
  result <- restore_suppressed_candidates(
    m, make_ref(),
    rank_system = c("family", "genus", "species"),
    score_rule = "sub_max", verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(abs(restored$score_original - 0.99) < 1e-9))
})

test_that("restore_suppressed_candidates accepts fixed numeric score_rule", {
  result <- restore_suppressed_candidates(
    make_match(), make_ref(),
    rank_system = c("family", "genus", "species"),
    score_rule = 97.5, verbose = FALSE
  )
  restored <- result[result$is_restored, ]
  expect_true(all(restored$score_original == 97.5))
})

test_that("restore_suppressed_candidates respects max_per_obs", {
  ref_big <- make_ref(species = paste0("Sp_", LETTERS[1:15]))
  result <- restore_suppressed_candidates(
    make_match(species = "Sp_A"), ref_big,
    rank_system = c("family", "genus", "species"),
    max_per_obs = 4L, verbose = FALSE
  )
  # original + 4 restored (cap applied; Sp_A excluded as H1)
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

test_that("restore_suppressed_candidates does nothing when no singletons", {
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

test_that("restore_suppressed_candidates perfect_only=FALSE restores sub-perfect singletons", {
  m <- make_match(score = 97)  # below perfect threshold (100)
  result_default <- restore_suppressed_candidates(
    m, make_ref(),
    rank_system = c("family", "genus", "species"),
    perfect_only = TRUE, verbose = FALSE
  )
  result_all <- restore_suppressed_candidates(
    m, make_ref(),
    rank_system = c("family", "genus", "species"),
    perfect_only = FALSE, verbose = FALSE
  )
  expect_equal(nrow(result_default), 1L)   # no restoration (perfect_only default)
  expect_equal(nrow(result_all), 3L)       # 1 + 2 restored
})

test_that("restore_suppressed_candidates respects min_score floor", {
  result <- restore_suppressed_candidates(
    make_match(score = 100), make_ref(),
    rank_system = c("family", "genus", "species"),
    score_rule = "sub_max",   # imputed = 99
    min_score  = 99.5,        # 99 < 99.5 -> nothing added
    verbose = FALSE
  )
  expect_equal(nrow(result), 1L)
  expect_false(any(result$is_restored))
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

test_that("restore_suppressed_candidates errors on missing score column", {
  expect_error(
    restore_suppressed_candidates(make_match(), make_ref(),
                                   score_col = "no_such_col",
                                   rank_system = c("family", "genus", "species")),
    "score column"
  )
})

test_that("restore_suppressed_candidates errors on invalid score_rule", {
  expect_error(
    restore_suppressed_candidates(make_match(), make_ref(),
                                   rank_system = c("family", "genus", "species"),
                                   score_rule = "h1_mean"),
    "score_rule"
  )
})
