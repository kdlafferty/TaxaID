# Tests for .ico(). No coverage existed before
# this session -- this is its first regression coverage.


# Fixtures name the matched species as the genus's plausible species (the
# function keeps a top hit only when it IS that species).
.sp_of <- function(genus) {
  map <- c(Genusone = "Genusone speciesa", Genustwo = "Genustwo speciesb",
    Genusthree = "Genusthree speciesd", Genusfive = "Genusfive speciese")
  out <- unname(map[genus])
  ifelse(is.na(out), genus, out)
}
.ico <- function(match_df, priors, ...) {
  if (!"taxon_name" %in% names(match_df)) match_df$taxon_name <- .sp_of(match_df$genus)
  identify_confident_observations(match_df, priors, ...)
}

.make_priors <- function() {
  data.frame(
    taxon_name = c(
      "Genusone speciesa", "Genustwo speciesb", "Genustwo speciesc",
      "Genusthree speciesd"
    ),
    taxon_name_rank = "species",
    theta_mean = c(0.5, 0.5, 0.4, 1e-6),
    stringsAsFactors = FALSE
  )
}

test_that("identify_confident_observations: genus with exactly one plausible species is confident", {
  match_df <- data.frame(
    observation_id = c("Q1", "Q2"),
    genus = "Genusone",
    score_original = c(95, 96),
    stringsAsFactors = FALSE
  )
  out <- .ico(match_df, .make_priors())
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
  out <- .ico(match_df, .make_priors())
  expect_equal(nrow(out), 0L)
})

test_that("identify_confident_observations: genus with zero plausible species (below threshold) is excluded", {
  match_df <- data.frame(
    observation_id = c("Q1", "Q2"), genus = c("Genusone", "Genusthree"),
    score_original = c(95, 80), stringsAsFactors = FALSE
  )
  out <- .ico(match_df, .make_priors())
  expect_false("Genusthree" %in% out$genus)
  expect_true("Genusone" %in% out$genus)
})

test_that("identify_confident_observations: keeps only the best-scoring row per observation_id", {
  match_df <- data.frame(
    observation_id = c("Q1", "Q1", "Q2"),
    genus = "Genusone",
    score_original = c(80, 95, 90),
    stringsAsFactors = FALSE
  )
  out <- .ico(match_df, .make_priors())
  expect_equal(nrow(out), 2L)
  q1 <- out[out$observation_id == "Q1", ]
  expect_equal(q1$score_original, 95)
})

test_that("identify_confident_observations: score column fallback order (score_original > score > p_match)", {
  match_df <- data.frame(
    observation_id = "Q1", genus = "Genusone", score = 88, p_match = 0.5,
    stringsAsFactors = FALSE
  )
  out <- .ico(match_df, .make_priors())
  expect_equal(nrow(out), 1L)
})

test_that("identify_confident_observations: no genus qualifies warns; result keeps match_df's columns", {
  # Priors where every genus has either 0 or 2+ plausible species -- none
  # ever has exactly 1 -- so genus_summary itself is empty and the function
  # takes its early-return path (no confident_genus/confident_species
  # columns added, since the main pipeline never runs).
  priors_none_confident <- data.frame(
    taxon_name = c(
      "Genusfive speciese", "Genusfive speciesf",
      "Genussix speciesg"
    ),
    taxon_name_rank = "species",
    theta_mean = c(0.5, 0.5, 1e-6),
    stringsAsFactors = FALSE
  )
  match_df <- data.frame(
    observation_id = "Q1", genus = "Genusfive", taxon_name = "Genusfive speciese",
    score_original = 90, stringsAsFactors = FALSE
  )
  expect_warning(
    out <- .ico(match_df, priors_none_confident),
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
  out <- .ico(match_df, .make_priors(),
    plausibility_threshold = 1e-9
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$confident_species, "Genusthree speciesd")
})

test_that("identify_confident_observations: validates inputs", {
  expect_error(
    .ico(list(), .make_priors()),
    "must be a data frame"
  )
  expect_error(
    identify_confident_observations(data.frame(x = 1), .make_priors()),
    "missing column"
  )
  expect_error(
    .ico(
      data.frame(observation_id = "Q1", genus = "G", score_original = 1),
      data.frame(x = 1)
    ),
    "missing column"
  )
})

test_that("identify_confident_observations: a species repeated across sites counts once", {
  # A prior table stacked across sites lists each species once per site.
  priors <- data.frame(
    taxon_name = rep("Genusone speciesa", 3),
    taxon_name_rank = "species",
    theta_mean = c(0.5, 0.3, 0.2),
    grid_id = c("s1", "s2", "s3"),
    stringsAsFactors = FALSE
  )
  match_df <- data.frame(observation_id = "Q1", genus = "Genusone", score_original = 95)
  out <- .ico(match_df, priors)
  expect_equal(out$confident_genus, "Genusone")
  expect_equal(out$confident_species, "Genusone speciesa")
})

test_that("identify_confident_observations: a coarse record labelled species is not a species", {
  priors <- data.frame(
    taxon_name = "Cottidae", taxon_name_rank = "species", theta_mean = 0.5,
    stringsAsFactors = FALSE
  )
  match_df <- data.frame(observation_id = "Q1", genus = "Cottidae", score_original = 95)
  expect_warning(out <- .ico(match_df, priors), "no genus")
  expect_equal(nrow(out), 0L)
})

test_that("identify_confident_observations: reports how many prior names were not binomials", {
  priors <- data.frame(
    taxon_name = c("Genusone speciesa", "Ulva sp.", "Mazzaella cf. splendens", "Cottidae"),
    taxon_name_rank = "species", theta_mean = 0.5, stringsAsFactors = FALSE
  )
  match_df <- data.frame(observation_id = "Q1", genus = "Genusone", score_original = 95)
  expect_message(out <- .ico(match_df, priors), "3 of 4")
  expect_equal(attr(out, "n_prior_names_not_binomial"), 3L)
  expect_equal(attr(out, "n_qualifying_genera"), 1L)
})

# ---- the confident set holds only top hits to the confident species --------
test_that("identify_confident_observations: a top hit to a congener is excluded", {
  match_df <- data.frame(
    observation_id = c("Q1", "Q2"), genus = "Genusone",
    taxon_name = c("Genusone speciesa", "Genusone speciesz"),
    score_original = c(97, 96), stringsAsFactors = FALSE
  )
  out <- identify_confident_observations(match_df, .make_priors())
  expect_equal(out$observation_id, "Q1")
  expect_equal(attr(out, "n_excluded_other_species"), 1L)
})

test_that("identify_confident_observations: an observation whose top hit is another genus is excluded", {
  match_df <- data.frame(
    observation_id = c("Q1", "Q1"), genus = c("Genusone", "Genusnine"),
    taxon_name = c("Genusone speciesa", "Genusnine speciesq"),
    score_original = c(90, 99), stringsAsFactors = FALSE
  )
  out <- suppressWarnings(identify_confident_observations(match_df, .make_priors()))
  expect_equal(nrow(out), 0L)
})
