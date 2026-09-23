# Extracted from test-join_priors.R:707

# setup ------------------------------------------------------------------------
library(testthat)
test_env <- simulate_test_env(package = "TaxaAssign", path = "..")
attach(test_env, warn.conflicts = FALSE)

# prequel ----------------------------------------------------------------------
library(dplyr)
.make_likelihoods <- function() {
  tibble(
    observation_id = rep("ESV_001", 3),
    taxon_name = c("Fundulus parvipinnis", "Fundulus lima", "Fundulidae"),
    taxon_name_rank = c("species", "species", "family"),
    hypothesis_type = c("specific_candidate", "specific_candidate", "unreferenced_genus"),
    score_likelihood = c(0.8, 0.3, 0.1),
    score_likelihood_mean = c(0.8, 0.3, 0.1),
    score_likelihood_sd = c(0.05, 0.04, 0.02),
    genus = c("Fundulus", "Fundulus", NA),
    family = c("Fundulidae", "Fundulidae", "Fundulidae"),
    species = c("Fundulus parvipinnis", "Fundulus lima", NA)
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
    taxon_name = c(
      "Gillichthys mirabilis", "Acanthogobius flavimanus",
      "Clevelandia ios"
    ),
    taxon_name_rank = "species",
    grid_id = "Grid_34p1_m119p1",
    main_habitat = "Estuarine",
    alpha = c(8, 1, 1),
    beta = c(2, 9, 9),
    undetected_type = NA_character_
  )
}
.make_expansion_taxonomy <- function() {
  tibble(
    taxon_name = c(
      "Gillichthys mirabilis", "Acanthogobius flavimanus",
      "Clevelandia ios"
    ),
    genus = c("Gillichthys", "Acanthogobius", "Clevelandia"),
    family = "Gobiidae"
  )
}
.make_ha_lik <- function(taxon_name = "Gadus morhua", observation_id = "ESV_100") {
  tibble(
    observation_id = observation_id,
    taxon_name = taxon_name,
    taxon_name_rank = "species",
    hypothesis_type = "specific_candidate",
    score_likelihood = 0.9,
    score_likelihood_mean = 0.9,
    score_likelihood_sd = 0.02,
    genus = "Gadus",
    family = "Gadidae",
    species = taxon_name
  )
}
.make_promo_lik <- function(taxa) {
  tibble(
    observation_id        = "ESV_200",
    taxon_name            = taxa,
    taxon_name_rank       = "species",
    hypothesis_type       = "specific_candidate",
    score_likelihood      = 0.9,
    score_likelihood_mean = 0.9,
    score_likelihood_sd   = 0.02,
    genus                 = "Perca",
    family                = "Percidae",
    species               = taxa
  )
}
.make_promo_priors <- function(extra) {
  base <- tibble(
    taxon_name      = c(NA_character_, NA_character_),
    taxon_name_rank = "species",
    grid_id         = "Grid_41p4_m86p7",
    main_habitat    = "Lentic",
    alpha           = c(0.04, 1),
    beta            = c(1.96, 999),
    undetected_type = c("singleton_mirror", "global_floor")
  )
  dplyr::bind_rows(base, extra)
}
.promo_site <- list(grid_id = "Grid_41p4_m86p7", main_habitat = "Lentic")

# test -------------------------------------------------------------------------
priors <- data.frame(
    taxon_name = c("Gadus morhua", "Pollachius virens"), grid_id = "Grid_34p4_m120p4",
    main_habitat = "Marine", prior_branch = "kernel_estimated", theta_mean = c(0.6, 0.4),
    taxon_name_rank = "species", alpha = c(6, 4), beta = c(4, 6),
    stringsAsFactors = FALSE
  )
likelihoods <- data.frame(observation_id = "obs1", taxon_name = "Gadus morhua",
                            taxon_name_rank = "species", likelihood = 1, stringsAsFactors = FALSE)
expect_error(
    join_priors(likelihoods, priors, site = list(grid_id = "Grid_00p0_m000p0", main_habitat = "Marine"),
                backbone_id = 4L),
    "has no rows in"
  )
