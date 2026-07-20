# Tests for identify_confident_observations(). No coverage existed before
# this session -- this is its first regression coverage.

.make_priors <- function() {
  data.frame(
    taxon_name      = c("Genusone speciesa", "Genustwo speciesb", "Genustwo speciesc",
                       "Genusthree speciesd"),
    taxon_name_rank = "species",
    theta_mean      = c(0.5, 0.5, 0.4, 1e-6),
    stringsAsFactors = FALSE
  )
}

test_that("identify_confident_observations: genus with exactly one plausible species is confident", {
  match_df <- data.frame(
    observation_id = c("Q1", "Q2"),
    genus          = "Genusone",
    score_original = c(95, 96),
    stringsAsFactors = FALSE
  )
  out <- identify_confident_observations(match_df, .make_priors())
  expect_equal(nrow(out), 2L)
  expect_true(all(out$confident_genus == "Genusone"))
  expect_true(all(out$confident_species == "Genusone speciesa"))
})

test_that("identify_confident_observations: genus with two plausible species is excluded", {
  # Genustwo has two species above plausibility_threshold (speciesb, speciesc)
  # so it never enters genus_summary -- but Genusone (elsewhere in priors)
  # still qualifies, so genus_summary itself is non-empty and no warning
  # fires; match_df's only observation (Genustwo) simply matches zero rows.
  match_df <- data.frame(
    observation_id = "Q1", genus = "Genustwo", score_original = 90,
    stringsAsFactors = FALSE
  )
  out <- identify_confident_observations(match_df, .make_priors())
  expect_equal(nrow(out), 0L)
})

test_that("identify_confident_observations: genus with zero plausible species (below threshold) is excluded", {
  match_df <- data.frame(
    observation_id = c("Q1", "Q2"), genus = c("Genusone", "Genusthree"),
    score_original = c(95, 80), stringsAsFactors = FALSE
  )
  out <- identify_confident_observations(match_df, .make_priors())
  expect_false("Genusthree" %in% out$genus)
  expect_true("Genusone" %in% out$genus)
})

test_that("identify_confident_observations: keeps only the best-scoring row per observation_id", {
  match_df <- data.frame(
    observation_id = c("Q1", "Q1", "Q2"),
    genus          = "Genusone",
    score_original = c(80, 95, 90),
    stringsAsFactors = FALSE
  )
  out <- identify_confident_observations(match_df, .make_priors())
  expect_equal(nrow(out), 2L)
  q1 <- out[out$observation_id == "Q1", ]
  expect_equal(q1$score_original, 95)
})

test_that("identify_confident_observations: score column fallback order (score_original > score > p_match)", {
  match_df <- data.frame(
    observation_id = "Q1", genus = "Genusone", score = 88, p_match = 0.5,
    stringsAsFactors = FALSE
  )
  out <- identify_confident_observations(match_df, .make_priors())
  expect_equal(nrow(out), 1L)
})

test_that("identify_confident_observations: no genus qualifies warns; result keeps match_df's columns", {
  # Priors where every genus has either 0 or 2+ plausible species -- none
  # ever has exactly 1 -- so genus_summary itself is empty and the function
  # takes its early-return path (no confident_genus/confident_species
  # columns added, since the main pipeline never runs).
  priors_none_confident <- data.frame(
    taxon_name      = c("Genusfive speciese", "Genusfive speciesf",
                       "Genussix speciesg"),
    taxon_name_rank = "species",
    theta_mean      = c(0.5, 0.5, 1e-6),
    stringsAsFactors = FALSE
  )
  match_df <- data.frame(
    observation_id = "Q1", genus = "Genusfive", score_original = 90,
    stringsAsFactors = FALSE
  )
  expect_warning(
    out <- identify_confident_observations(match_df, priors_none_confident),
    "no genus had exactly one"
  )
  expect_equal(nrow(out), 0L)
  expect_equal(names(out), names(match_df))
})

test_that("identify_confident_observations: plausibility_threshold is user-adjustable", {
  # Genusthree's only species sits at theta_mean = 1e-6; raising the threshold
  # below that value makes it locally plausible (n_plausible = 1).
  match_df <- data.frame(
    observation_id = "Q1", genus = "Genusthree", score_original = 90,
    stringsAsFactors = FALSE
  )
  out <- identify_confident_observations(match_df, .make_priors(),
                                          plausibility_threshold = 1e-9)
  expect_equal(nrow(out), 1L)
  expect_equal(out$confident_species, "Genusthree speciesd")
})

test_that("identify_confident_observations: validates inputs", {
  expect_error(identify_confident_observations(list(), .make_priors()),
               "must be a data frame")
  expect_error(identify_confident_observations(data.frame(x = 1), .make_priors()),
               "missing column")
  expect_error(
    identify_confident_observations(
      data.frame(observation_id = "Q1", genus = "G", score_original = 1),
      data.frame(x = 1)
    ),
    "missing column"
  )
})
