# Tests for expand_consensus_candidates()
# Covers: no-score pathway (uniform likelihoods), score_col pathway (BirdNET-style),
# input validation, and output structure consistency with evaluate_likelihoods().

# ---- shared fixtures --------------------------------------------------------

make_priors <- function() {
  data.frame(
    species = c("Salmo salar", "Salmo trutta", "Salmo obtusirostris",
                "Salvelinus alpinus", "Salvelinus fontinalis",
                "Esox lucius"),
    genus   = c("Salmo", "Salmo", "Salmo",
                "Salvelinus", "Salvelinus",
                "Esox"),
    family  = c("Salmonidae", "Salmonidae", "Salmonidae",
                "Salmonidae", "Salmonidae",
                "Esocidae"),
    stringsAsFactors = FALSE
  )
}

make_consensus <- function() {
  data.frame(
    observation_id  = c("obs1", "obs2", "obs3"),
    taxon_name      = c("Salmo salar", "Salvelinus", "Salmonidae"),
    taxon_name_rank = c("species", "genus", "family"),
    stringsAsFactors = FALSE
  )
}


# ---- no-score pathway (existing behavior) -----------------------------------

test_that("no-score pathway: all likelihoods are 1.0", {
  result <- suppressWarnings(
    suppressMessages(expand_consensus_candidates(make_consensus(), make_priors()))
  )
  lk <- result$likelihoods
  expect_true(all(lk$score_likelihood == 1.0))
  expect_true(all(lk$score_likelihood_mean      == 1.0))
  expect_true(all(lk$score_likelihood_sd        == 0.0))
})

test_that("no-score pathway: output columns match evaluate_likelihoods() schema", {
  result <- suppressWarnings(
    suppressMessages(expand_consensus_candidates(make_consensus(), make_priors()))
  )
  expected_cols <- c("observation_id", "taxon_name", "taxon_name_rank",
                     "hypothesis_type", "score_likelihood",
                     "score_likelihood_mean", "score_likelihood_sd")
  expect_true(all(expected_cols %in% names(result$likelihoods)))
})

test_that("no-score pathway: species-level obs includes consensus species", {
  result <- suppressWarnings(
    suppressMessages(expand_consensus_candidates(make_consensus(), make_priors()))
  )
  sp_rows <- result$likelihoods[result$likelihoods$observation_id == "obs1", ]
  expect_true("Salmo salar" %in% sp_rows$taxon_name)
})

test_that("no-score pathway: genus-level obs includes all species of that genus", {
  result <- suppressMessages(
    expand_consensus_candidates(make_consensus(), make_priors())
  )
  gn_rows <- result$likelihoods[result$likelihoods$observation_id == "obs2", ]
  expect_setequal(gn_rows$taxon_name,
                  c("Salvelinus alpinus", "Salvelinus fontinalis"))
})

test_that("no-score pathway: $unresolved is empty when all obs resolve", {
  result <- suppressWarnings(
    suppressMessages(expand_consensus_candidates(make_consensus(), make_priors()))
  )
  expect_equal(nrow(result$unresolved), 0L)
})


# ---- score_col pathway (BirdNET-style) --------------------------------------

make_birdnet <- function(score = 0.87) {
  data.frame(
    observation_id  = "clip_001",
    taxon_name      = "Salmo salar",
    taxon_name_rank = "species",
    confidence      = score,
    stringsAsFactors = FALSE
  )
}

test_that("score_col: consensus species gets likelihood = score", {
  result <- suppressWarnings(
    suppressMessages(
      expand_consensus_candidates(
        make_birdnet(0.87), make_priors(), score_col = "confidence"
      )
    )
  )
  lk <- result$likelihoods
  consensus_row <- lk[tolower(lk$taxon_name) == "salmo salar", ]
  expect_equal(consensus_row$score_likelihood, 0.87)
  expect_equal(consensus_row$score_likelihood_mean,      0.87)
})

test_that("score_col: non-consensus species get likelihood = 1 - score", {
  result <- suppressWarnings(
    suppressMessages(
      expand_consensus_candidates(
        make_birdnet(0.87), make_priors(), score_col = "confidence"
      )
    )
  )
  lk <- result$likelihoods
  other_rows <- lk[tolower(lk$taxon_name) != "salmo salar", ]
  expect_true(nrow(other_rows) > 0L)
  expect_true(all(other_rows$score_likelihood == 0.13))
  expect_true(all(other_rows$score_likelihood_mean      == 0.13))
})

test_that("score_col: score_likelihood_sd is still 0.0 for all rows", {
  result <- suppressWarnings(
    suppressMessages(
      expand_consensus_candidates(
        make_birdnet(0.87), make_priors(), score_col = "confidence"
      )
    )
  )
  expect_true(all(result$likelihoods$score_likelihood_sd == 0.0))
})

test_that("score_col: score = 0.5 gives equal likelihoods to H1 and others", {
  result <- suppressWarnings(
    suppressMessages(
      expand_consensus_candidates(
        make_birdnet(0.5), make_priors(), score_col = "confidence"
      )
    )
  )
  lk <- result$likelihoods
  expect_true(all(lk$score_likelihood == 0.5))
})

test_that("score_col: score = 1.0 gives 1.0 to consensus and 0.0 to others", {
  result <- suppressWarnings(
    suppressMessages(
      expand_consensus_candidates(
        make_birdnet(1.0), make_priors(), score_col = "confidence"
      )
    )
  )
  lk <- result$likelihoods
  consensus_row <- lk[tolower(lk$taxon_name) == "salmo salar", ]
  other_rows    <- lk[tolower(lk$taxon_name) != "salmo salar", ]
  expect_equal(consensus_row$score_likelihood, 1.0)
  expect_true(all(other_rows$score_likelihood == 0.0))
})

test_that("score_col = NULL gives same output as not supplying score_col", {
  priors <- make_priors()
  cons   <- make_birdnet(0.9)[, c("observation_id", "taxon_name", "taxon_name_rank")]
  r_null  <- suppressWarnings(suppressMessages(
    expand_consensus_candidates(cons, priors, score_col = NULL)
  ))
  r_omit  <- suppressWarnings(suppressMessages(
    expand_consensus_candidates(cons, priors)
  ))
  expect_equal(r_null$likelihoods$score_likelihood,
               r_omit$likelihoods$score_likelihood)
})


# ---- input validation -------------------------------------------------------

test_that("score_col not in consensus_df raises error", {
  expect_error(
    expand_consensus_candidates(make_birdnet(0.8), make_priors(),
                                score_col = "nonexistent"),
    "not found"
  )
})

test_that("score_col values outside [0, 1] raise error", {
  bad <- make_birdnet(1.5)
  expect_error(
    expand_consensus_candidates(bad, make_priors(), score_col = "confidence"),
    "outside \\[0, 1\\]"
  )
})

test_that("non-numeric score_col raises error", {
  bad <- data.frame(
    observation_id  = "clip_001",
    taxon_name      = "Salmo salar",
    taxon_name_rank = "species",
    confidence      = "high",
    stringsAsFactors = FALSE
  )
  expect_error(
    expand_consensus_candidates(bad, make_priors(), score_col = "confidence"),
    "numeric"
  )
})

test_that("missing required columns raises error", {
  bad <- data.frame(observation_id = "obs1", taxon_name = "Salmo salar")
  expect_error(
    expand_consensus_candidates(bad, make_priors()),
    "missing required columns"
  )
})

test_that("priors_df without species column raises error", {
  bad_priors <- data.frame(genus = "Salmo")
  expect_error(
    expand_consensus_candidates(make_consensus(), bad_priors),
    "species"
  )
})
