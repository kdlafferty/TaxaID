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
                site = list(grid_id = "G", main_habitat = "H"),
                backbone_id = 11L),
    "must be a data frame"
  )
})

test_that("join_priors errors on missing columns in likelihoods", {
  lik <- .make_likelihoods() |> select(-taxon_name)
  expect_error(
    join_priors(lik, .make_priors(),
                site = list(grid_id = "Grid_34p1_m119p1",
                            main_habitat = "Estuarine Bay"),
                backbone_id = 11L),
    "missing required column"
  )
})

test_that("site = list(main_habitat = ...) alone auto-fills lat/lon from taxaexpect_priors' search_center attribute", {
  priors <- .make_priors()
  attr(priors, "search_center") <- list(lat = 34.1, lon = -119.1)

  out <- suppressMessages(suppressWarnings(join_priors(
    .make_likelihoods(), priors,
    site        = list(main_habitat = "Estuarine Bay"),
    backbone_id = 11L
  )))
  expect_true(all(out$grid_id == "Grid_34p1_m119p1"))
  expect_true(all(out$main_habitat == "Estuarine Bay"))
})

test_that("site = list(main_habitat = ...) alone still errors when no search_center is available", {
  expect_error(
    join_priors(.make_likelihoods(), .make_priors(),
                site = list(main_habitat = "Estuarine Bay"),
                backbone_id = 11L),
    "missing element"
  )
})

test_that("join_priors errors on missing site elements", {
  expect_error(
    join_priors(.make_likelihoods(), .make_priors(),
                site = list(grid_id = "G"),
                backbone_id = 11L),
    "missing element"
  )
})

# ---- Single-site mode -------------------------------------------------------

test_that("join_priors works in single-site mode", {
  lik <- .make_likelihoods()
  pri <- .make_priors()
  site <- list(grid_id = "Grid_34p1_m119p1", main_habitat = "Estuarine Bay")

  out <- suppressMessages(join_priors(lik, pri, site = site, backbone_id = 11L))

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

  out <- suppressMessages(join_priors(lik, pri, site = site_df, backbone_id = 11L))
  expect_s3_class(out, "data.frame")
  expect_true(all(c("prior_mean", "prior_alpha", "prior_beta") %in% names(out)))
})

test_that("join_priors preserves one row per site for a genuine multi-site observation (Session 138)", {
  # One observation, two candidates, two sites -- each candidate has a strong
  # prior at one site and a weak prior at the other. Before the Session 138
  # grid_id/main_habitat-aware distinct() fix, this collapsed to one row per
  # candidate (each matched to its own best site), discarding the site it was
  # actually detected at.
  lik <- tibble(
    observation_id        = "obs1",
    taxon_name            = c("Species_a", "Species_b"),
    taxon_name_rank       = "species",
    hypothesis_type       = "specific_candidate",
    score_likelihood      = 1,
    score_likelihood_mean = 1,
    score_likelihood_sd   = 0,
    genus                 = "Species",
    family                = "Familyx",
    species               = c("Species_a", "Species_b")
  )
  pri <- tibble(
    taxon_name      = c("Species_a", "Species_a", "Species_b", "Species_b"),
    taxon_name_rank = "species",
    grid_id         = c("site1", "site2", "site1", "site2"),
    main_habitat    = "Marine",
    alpha           = c(8, 1, 1, 8),
    beta            = c(2, 9, 9, 2),
    undetected_type = NA_character_
  )
  site_df <- tibble(
    observation_id = c("obs1", "obs1"),
    grid_id        = c("site1", "site2"),
    main_habitat   = c("Marine", "Marine")
  )

  out <- suppressMessages(join_priors(lik, pri, site = site_df,
                                       rank_system = c("family", "genus", "species"),
                                       backbone_id = 11L))

  # 2 candidates x 2 sites = 4 rows, not collapsed to 2.
  expect_equal(nrow(out), 4L)
  expect_setequal(out$grid_id, c("site1", "site2"))
  a_site1 <- out$prior_mean[out$taxon_name == "Species_a" & out$grid_id == "site1"]
  a_site2 <- out$prior_mean[out$taxon_name == "Species_a" & out$grid_id == "site2"]
  expect_equal(a_site1, 0.8)
  expect_equal(a_site2, 0.1)
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
                rank_system = c("family", "genus", "species"),
                backbone_id = 11L)
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
                expansion_cumulative_prior = 0.75,
                backbone_id = 11L)
  )
  expect_equal(nrow(out_tight), 1L)
  expect_equal(out_tight$taxon_name, "Gillichthys mirabilis")

  # At 0.90, mirabilis alone (0.80) is insufficient; flavimanus added (cumsum 0.90)
  out_wide <- suppressMessages(
    join_priors(lik, pri, site = site, expansion_taxonomy = etax,
                rank_system = c("family", "genus", "species"),
                expansion_cumulative_prior = 0.90,
                backbone_id = 11L)
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
                expansion_cumulative_prior = 1.0,
                backbone_id = 11L)
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
                  rank_system = c("family", "genus", "species"),
                  backbone_id = 11L)
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
                rank_system = c("family", "genus", "species"),
                backbone_id = 11L)
  )

  # Gobiidae expansion finds no species in pri_estuarine → dark floor on family row
  expect_equal(nrow(out), 1L)
  expect_equal(out$taxon_name_rank, "family")
  expect_true(!is.na(out$prior_mean))
})

# ---- Habitat-agnostic named-species prior fallback --------------------------
# Real bug found and fixed this session: TaxaExpect::generate_domestic_food_priors()
# emits rows with main_habitat = NA on purpose (a food/domestic species has no
# single correct habitat value) and, until this session, also with
# taxon_name_rank unset -- both meant the primary composite-key join could
# never match these rows against a real observation. Confirmed on real
# GreatLakes2023 data (a real Gadus morhua domestic-food row never matched;
# the affected observation fell back to the generic floor instead).

.make_ha_lik <- function(taxon_name = "Gadus morhua", observation_id = "ESV_100") {
  tibble(
    observation_id        = observation_id,
    taxon_name             = taxon_name,
    taxon_name_rank        = "species",
    hypothesis_type        = "specific_candidate",
    score_likelihood       = 0.9,
    score_likelihood_mean  = 0.9,
    score_likelihood_sd    = 0.02,
    genus                  = "Gadus",
    family                 = "Gadidae",
    species                = taxon_name
  )
}

test_that("a habitat-agnostic named-species prior (main_habitat = NA) rescues an otherwise-unmatched taxon", {
  lik <- .make_ha_lik()
  pri <- tibble(
    taxon_name      = c("Gadus morhua", "undetected_placeholder"),
    taxon_name_rank = "species",
    grid_id         = "Grid_41p4_m86p7",
    main_habitat    = c(NA_character_, "Lentic"),
    alpha           = c(5, 0.5),
    beta            = c(8775, 9.5),
    undetected_type = c(NA, "global_floor")
  )
  site <- list(grid_id = "Grid_41p4_m86p7", main_habitat = "Lentic")

  out <- suppressMessages(join_priors(lik, pri, site = site, backbone_id = 11L))

  expect_equal(out$prior_alpha, 5)
  expect_equal(out$prior_beta, 8775)
})

test_that("a real per-habitat match still wins over a habitat-agnostic fallback row for the same taxon", {
  lik <- .make_ha_lik()
  pri <- tibble(
    taxon_name      = c("Gadus morhua", "Gadus morhua", "undetected_placeholder"),
    taxon_name_rank = "species",
    grid_id         = "Grid_41p4_m86p7",
    main_habitat    = c(NA_character_, "Lentic", "Lentic"),
    alpha           = c(5, 50, 0.5),
    beta            = c(8775, 50, 9.5),
    undetected_type = c(NA, NA, "global_floor")
  )
  site <- list(grid_id = "Grid_41p4_m86p7", main_habitat = "Lentic")

  out <- suppressMessages(join_priors(lik, pri, site = site, backbone_id = 11L))

  expect_equal(out$prior_alpha, 50)
  expect_equal(out$prior_beta, 50)
})

test_that("multiple habitat-agnostic rows for the same taxon/site collapse to the strongest, not an ambiguous many-to-many join", {
  lik <- .make_ha_lik()
  pri <- tibble(
    taxon_name      = c("Gadus morhua", "Gadus morhua", "undetected_placeholder"),
    taxon_name_rank = "species",
    grid_id         = "Grid_41p4_m86p7",
    main_habitat    = c(NA_character_, NA_character_, "Lentic"),
    alpha           = c(5, 20, 0.5),   # theta_mean 5/8780 vs 20/8795 -- second stronger
    beta            = c(8775, 8775, 9.5),
    undetected_type = c(NA, NA, "global_floor")
  )
  site <- list(grid_id = "Grid_41p4_m86p7", main_habitat = "Lentic")

  out <- suppressMessages(join_priors(lik, pri, site = site, backbone_id = 11L))

  expect_equal(nrow(out), 1L)
  expect_equal(out$prior_alpha, 20)
})

test_that("a habitat-agnostic row at a DIFFERENT grid_id is never applied", {
  lik <- .make_ha_lik()
  pri <- tibble(
    taxon_name      = c("Gadus morhua", "undetected_placeholder"),
    taxon_name_rank = "species",
    grid_id         = c("Grid_99p9_m99p9", "Grid_41p4_m86p7"),
    main_habitat    = c(NA_character_, "Lentic"),
    alpha           = c(5, 0.5),
    beta            = c(8775, 9.5),
    undetected_type = c(NA, "global_floor")
  )
  site <- list(grid_id = "Grid_41p4_m86p7", main_habitat = "Lentic")

  out <- suppressMessages(join_priors(lik, pri, site = site, backbone_id = 11L))

  # Must NOT pick up the other grid's habitat-agnostic row -- falls back to
  # the generic global floor instead.
  expect_equal(out$prior_alpha, 0.5)
  expect_equal(out$prior_beta, 9.5)
})

test_that("join_priors reports how many habitat-agnostic fallback rows were applied", {
  lik <- .make_ha_lik()
  pri <- tibble(
    taxon_name      = c("Gadus morhua", "undetected_placeholder"),
    taxon_name_rank = "species",
    grid_id         = "Grid_41p4_m86p7",
    main_habitat    = c(NA_character_, "Lentic"),
    alpha           = c(5, 0.5),
    beta            = c(8775, 9.5),
    undetected_type = c(NA, "global_floor")
  )
  site <- list(grid_id = "Grid_41p4_m86p7", main_habitat = "Lentic")

  msgs <- capture_messages(
    join_priors(lik, pri, site = site, backbone_id = 11L)
  )
  expect_true(any(grepl("habitat-agnostic named-species prior", msgs)))
})

# ---- Modelled-species floor promotion: scoped by cause (2026-08-26) ---------
# The Session-117 promotion previously fired on ANY joined prior below the
# singleton-mirror mean. The 2026-08-26 GreatLakes upranking review showed this
# silently clamped every evidence_blend/domestic row to exact singleton parity,
# erasing the graded weight design (byte-identical consensus across a 4x d_half
# sweep). Now: evidence-derived rows are never promoted; modelled rows are
# promoted only on a genuine habitat mismatch (observed_in_habitat FALSE);
# priors lacking observed_in_habitat entirely keep the old blanket behavior.
# See ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md.

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

# Priors with a real singleton mirror (mean 0.02) so the promotion floor exists,
# plus a global floor row so unmodelled-species fallback machinery is satisfied.
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

test_that("an evidence_blend row below the singleton mean is NEVER promoted", {
  pri <- .make_promo_priors(tibble(
    taxon_name      = "Sander lucioperca",
    taxon_name_rank = "species",
    grid_id         = "Grid_41p4_m86p7",
    main_habitat    = "Lentic",
    alpha           = 0.01,   # theta = 0.005, below the 0.02 singleton mean
    beta            = 1.99,
    undetected_type = "evidence_blend",
    model_tier      = "tier_undetected_evidence"
  ))
  out <- suppressMessages(suppressWarnings(join_priors(
    .make_promo_lik("Sander lucioperca"), pri,
    site = .promo_site, backbone_id = 11L
  )))
  row <- out[out$taxon_name == "Sander lucioperca", ]
  expect_equal(row$prior_mean[1], 0.005, tolerance = 1e-8)
  expect_equal(row$prior_alpha[1], 0.01, tolerance = 1e-8)
})

test_that("a habitat-agnostic tier_domestic_food row rescued by the fallback is not promoted either", {
  pri <- .make_promo_priors(tibble(
    taxon_name      = "Gadus morhua",
    taxon_name_rank = "species",
    grid_id         = "Grid_41p4_m86p7",
    main_habitat    = NA_character_,   # habitat-agnostic by design
    alpha           = 5,
    beta            = 8775,            # theta ~= 0.00057, far below 0.02
    undetected_type = NA_character_,
    model_tier      = "tier_domestic_food"
  ))
  out <- suppressMessages(suppressWarnings(join_priors(
    .make_promo_lik("Gadus morhua"), pri,
    site = .promo_site, backbone_id = 11L
  )))
  row <- out[out$taxon_name == "Gadus morhua", ]
  expect_equal(row$prior_mean[1], 5 / 8780, tolerance = 1e-8)
})

test_that("a modelled row below the singleton mean IS promoted when observed_in_habitat is FALSE", {
  pri <- .make_promo_priors(tibble(
    taxon_name          = "Perca flavescens",
    taxon_name_rank     = "species",
    grid_id             = "Grid_41p4_m86p7",
    main_habitat        = "Lentic",
    alpha               = 0.01,  # theta = 0.001 -- habitat-extrapolated collapse
    beta                = 9.99,
    undetected_type     = NA_character_,
    model_tier          = "tier1",
    observed_in_habitat = FALSE
  ))
  out <- suppressMessages(suppressWarnings(join_priors(
    .make_promo_lik("Perca flavescens"), pri,
    site = .promo_site, backbone_id = 11L
  )))
  row <- out[out$taxon_name == "Perca flavescens", ]
  expect_equal(row$prior_mean[1], 0.02, tolerance = 1e-8)  # singleton mean
})

test_that("a modelled row below the singleton mean is NOT promoted when observed_in_habitat is TRUE", {
  pri <- .make_promo_priors(tibble(
    taxon_name          = "Perca flavescens",
    taxon_name_rank     = "species",
    grid_id             = "Grid_41p4_m86p7",
    main_habitat        = "Lentic",
    alpha               = 0.01,  # theta = 0.001 -- genuine in-habitat rarity
    beta                = 9.99,
    undetected_type     = NA_character_,
    model_tier          = "tier1",
    observed_in_habitat = TRUE
  ))
  out <- suppressMessages(suppressWarnings(join_priors(
    .make_promo_lik("Perca flavescens"), pri,
    site = .promo_site, backbone_id = 11L
  )))
  row <- out[out$taxon_name == "Perca flavescens", ]
  expect_equal(row$prior_mean[1], 0.001, tolerance = 1e-8)
})

test_that("priors with no observed_in_habitat column keep the pre-redesign blanket promotion", {
  pri <- .make_promo_priors(tibble(
    taxon_name      = "Perca flavescens",
    taxon_name_rank = "species",
    grid_id         = "Grid_41p4_m86p7",
    main_habitat    = "Lentic",
    alpha           = 0.01,
    beta            = 9.99,
    undetected_type = NA_character_
  ))
  out <- suppressMessages(suppressWarnings(join_priors(
    .make_promo_lik("Perca flavescens"), pri,
    site = .promo_site, backbone_id = 11L
  )))
  row <- out[out$taxon_name == "Perca flavescens", ]
  expect_equal(row$prior_mean[1], 0.02, tolerance = 1e-8)  # old behavior retained
})
