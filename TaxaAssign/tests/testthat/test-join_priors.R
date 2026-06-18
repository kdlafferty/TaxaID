# tests/testthat/test-join_priors.R

library(dplyr)

# ---- Shared test data --------------------------------------------------------

.make_likelihoods <- function() {
  tibble(
    observation_id            = rep("ESV_001", 3),
    taxon_name           = c("Fundulus parvipinnis", "Fundulus lima", "Fundulidae"),
    taxon_name_rank      = c("species", "species", "family"),
    hypothesis_type      = c("specific_candidate", "specific_candidate", "unreferenced_genus"),
    score_likelihood = c(0.8, 0.3, 0.1),
    score_likelihood_mean      = c(0.8, 0.3, 0.1),
    score_likelihood_sd        = c(0.05, 0.04, 0.02),
    genus                = c("Fundulus", "Fundulus", NA),
    family               = c("Fundulidae", "Fundulidae", "Fundulidae"),
    species              = c("Fundulus parvipinnis", "Fundulus lima", NA)
  )
}

.make_priors <- function() {
  tibble(
    taxon_name      = c("Fundulus parvipinnis", "Fundulus lima", "undetected_placeholder"),
    taxon_name_rank = c("species", "species", "species"),
    grid_id         = "Grid_34p1_m119p1",
    main_habitat    = "Estuarine Bay",
    alpha           = c(5, 2, 0.5),
    beta            = c(5, 8, 9.5),
    undetected_type = c(NA, NA, "tier3")
  )
}

# ---- Input validation --------------------------------------------------------

test_that("join_priors errors on non-data-frame likelihoods", {
  expect_error(
    join_priors(list(), .make_priors(),
                site = list(grid_id = "G", main_habitat = "H")),
    "must be a data frame"
  )
})

test_that("join_priors errors on missing columns in likelihoods", {
  lik <- .make_likelihoods() |> select(-taxon_name)
  expect_error(
    join_priors(lik, .make_priors(),
                site = list(grid_id = "Grid_34p1_m119p1",
                            main_habitat = "Estuarine Bay")),
    "missing required column"
  )
})

test_that("join_priors errors on missing site elements", {
  expect_error(
    join_priors(.make_likelihoods(), .make_priors(),
                site = list(grid_id = "G")),
    "missing element"
  )
})

# ---- Single-site mode -------------------------------------------------------

test_that("join_priors works in single-site mode", {
  lik <- .make_likelihoods()
  pri <- .make_priors()
  site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine Bay")

  out <- suppressMessages(join_priors(lik, pri, site = site))

  expect_s3_class(out, "data.frame")
  expect_true(all(c("prior_mean", "prior_alpha", "prior_beta") %in% names(out)))
  # All rows should have non-NA prior_mean
  expect_true(all(!is.na(out$prior_mean)))
})

# ---- Multi-site mode --------------------------------------------------------

test_that("join_priors works in multi-site mode", {
  lik <- .make_likelihoods()
  pri <- .make_priors()
  site_df <- data.frame(
    observation_id    = "ESV_001",
    grid_id      = "Grid_34p1_m119p1",
    main_habitat = "Estuarine Bay",
    stringsAsFactors = FALSE
  )

  out <- suppressMessages(join_priors(lik, pri, site = site_df))
  expect_s3_class(out, "data.frame")
  expect_true(all(c("prior_mean", "prior_alpha", "prior_beta") %in% names(out)))
})

# ---- Coarse-rank expansion ---------------------------------------------------

# Fixtures for expansion tests: one observation with a family-rank match only.
.make_lik_family_only <- function() {
  tibble(
    observation_id        = "ESV_002",
    taxon_name            = "Gobiidae",
    taxon_name_rank       = "family",
    hypothesis_type       = "specific_candidate",
    score_likelihood      = 1.0,
    score_likelihood_mean = 1.0,
    score_likelihood_sd   = 0.0,
    genus                 = NA_character_,
    family                = "Gobiidae",
    species               = NA_character_
  )
}

.make_pri_gobiidae <- function() {
  # Three Gobiidae species: mirabilis dominates (prior_mean = 0.80),
  # flavimanus and ios each = 0.10 (after normalization within candidate set).
  tibble(
    taxon_name      = c("Gillichthys mirabilis", "Acanthogobius flavimanus",
                        "Clevelandia ios"),
    taxon_name_rank = "species",
    grid_id         = "Grid_34p1_m119p1",
    main_habitat    = "Estuarine",
    alpha           = c(8, 1, 1),
    beta            = c(2, 9, 9),
    undetected_type = NA_character_
  )
}

.make_expansion_taxonomy <- function() {
  tibble(
    taxon_name = c("Gillichthys mirabilis", "Acanthogobius flavimanus",
                   "Clevelandia ios"),
    genus  = c("Gillichthys", "Acanthogobius", "Clevelandia"),
    family = "Gobiidae"
  )
}

test_that("coarse-rank family row is expanded to species-level hypotheses", {
  lik  <- .make_lik_family_only()
  pri  <- .make_pri_gobiidae()
  site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine")
  etax <- .make_expansion_taxonomy()

  out <- suppressMessages(
    join_priors(lik, pri, site = site, expansion_taxonomy = etax,
                rank_system = c("family", "genus", "species"))
  )

  # Original family-rank row should be replaced by species-level rows
  expect_true(all(out$taxon_name_rank == "species"))
  expect_true(all(out$hypothesis_type == "rank_expanded"))
  # All expanded rows carry the same observation_id
  expect_true(all(out$observation_id == "ESV_002"))
  # All rows have valid priors
  expect_true(all(!is.na(out$prior_mean)))
  expect_true(all(out$prior_mean > 0))
})

test_that("expansion_cumulative_prior limits the number of species retained", {
  lik  <- .make_lik_family_only()
  pri  <- .make_pri_gobiidae()
  site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine")
  etax <- .make_expansion_taxonomy()

  # mirabilis norm_prior = 0.80; cumulative reaches 0.75 with mirabilis alone
  out_tight <- suppressMessages(
    join_priors(lik, pri, site = site, expansion_taxonomy = etax,
                rank_system = c("family", "genus", "species"),
                expansion_cumulative_prior = 0.75)
  )
  expect_equal(nrow(out_tight), 1L)
  expect_equal(out_tight$taxon_name, "Gillichthys mirabilis")

  # At 0.90, mirabilis alone (0.80) is insufficient; flavimanus added (cumsum 0.90)
  out_wide <- suppressMessages(
    join_priors(lik, pri, site = site, expansion_taxonomy = etax,
                rank_system = c("family", "genus", "species"),
                expansion_cumulative_prior = 0.90)
  )
  expect_equal(nrow(out_wide), 2L)
  expect_true("Gillichthys mirabilis"    %in% out_wide$taxon_name)
  expect_true("Acanthogobius flavimanus" %in% out_wide$taxon_name)
})

test_that("expansion_min_prior floor removes low-probability species", {
  lik  <- .make_lik_family_only()
  pri  <- .make_pri_gobiidae()
  site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine")
  etax <- .make_expansion_taxonomy()

  # With expansion_min_prior = 0.15, all three species have norm_prior <= 0.10
  # for flavimanus and ios — both are excluded; only mirabilis (0.80) survives
  out <- suppressMessages(
    join_priors(lik, pri, site = site, expansion_taxonomy = etax,
                rank_system = c("family", "genus", "species"),
                expansion_min_prior = 0.15,
                expansion_cumulative_prior = 1.0)
  )
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name, "Gillichthys mirabilis")
})

test_that("NULL expansion_taxonomy emits a warning and falls back to dark floor", {
  lik  <- .make_lik_family_only()
  pri  <- .make_pri_gobiidae()
  site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine")

  # Add a global_floor row so the dark fallback has something to use
  pri_with_floor <- bind_rows(
    pri,
    tibble(taxon_name = NA_character_, taxon_name_rank = "species",
           grid_id = NA_character_, main_habitat = NA_character_,
           alpha = 1, beta = 99, undetected_type = "global_floor")
  )

  expect_warning(
    out <- suppressMessages(
      join_priors(lik, pri_with_floor, site = site,
                  expansion_taxonomy = NULL,
                  rank_system = c("family", "genus", "species"))
    ),
    regexp = "coarse-rank"
  )

  # Row remains at family rank and receives the dark floor prior
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name_rank, "family")
  expect_true(!is.na(out$prior_mean))
})

test_that("expansion falls back to dark floor when family absent from priors", {
  lik  <- .make_lik_family_only()
  # Priors only contain Fundulidae species, not Gobiidae
  pri  <- .make_priors()
  site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine Bay")
  etax <- .make_expansion_taxonomy()  # has Gobiidae species

  # The priors grid/habitat don't match either, but even if we use a compatible
  # site, Gobiidae is absent from .make_priors() → fallback
  pri_gobiidae_site <- tibble(
    taxon_name = NA_character_, taxon_name_rank = "species",
    grid_id = NA_character_,    main_habitat = NA_character_,
    alpha = 1, beta = 99, undetected_type = "global_floor"
  )
  pri_estuarine <- bind_rows(
    mutate(.make_priors(), main_habitat = "Estuarine"),
    pri_gobiidae_site
  )

  out <- suppressMessages(
    join_priors(.make_lik_family_only(), pri_estuarine,
                site = list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine"),
                expansion_taxonomy = etax,
                rank_system = c("family", "genus", "species"))
  )

  # Gobiidae expansion finds no species in pri_estuarine → dark floor on family row
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name_rank, "family")
  expect_true(!is.na(out$prior_mean))
})
