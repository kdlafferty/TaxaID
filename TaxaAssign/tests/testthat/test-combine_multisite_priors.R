# tests/testthat/test-combine_multisite_priors.R

library(dplyr)

# ---- Shared test data --------------------------------------------------------

.make_single_site_joined <- function() {
  tibble(
    observation_id   = c("obs1", "obs1"),
    taxon_name       = c("Species_a", "Species_b"),
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = "site1",
    main_habitat     = "Marine",
    prior_alpha      = c(8, 2),
    prior_beta       = c(2, 8),
    prior_mean       = c(0.8, 0.2)
  )
}

.make_multisite_joined <- function() {
  tibble(
    observation_id   = "obs1",
    taxon_name       = c("Species_a", "Species_a", "Species_b", "Species_b"),
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = c("site1", "site2", "site1", "site2"),
    main_habitat     = "Marine",
    prior_alpha      = c(8, 1, 1, 8),
    prior_beta       = c(2, 9, 9, 2),
    prior_mean       = c(0.8, 0.1, 0.1, 0.8)
  )
}

# ---- Input validation ---------------------------------------------------------

test_that("combine_multisite_priors errors on non-data-frame input", {
  expect_error(combine_multisite_priors(list()), "must be a data frame")
})

test_that("combine_multisite_priors errors on missing required columns", {
  df <- .make_single_site_joined() |> select(-prior_alpha)
  expect_error(combine_multisite_priors(df), "missing required column")
})

test_that("combine_multisite_priors errors on non-positive prior_alpha/prior_beta", {
  df <- .make_single_site_joined()
  df$prior_alpha[1] <- 0
  expect_error(combine_multisite_priors(df), "non-positive or non-finite")
})

# ---- Single-site passthrough ---------------------------------------------------

test_that("single-site observations pass through unchanged", {
  df <- .make_single_site_joined()
  out <- suppressMessages(combine_multisite_priors(df))

  expect_equal(nrow(out), nrow(df))
  expect_equal(out$prior_alpha, df$prior_alpha)
  expect_equal(out$prior_beta, df$prior_beta)
  expect_equal(out$prior_mean, df$prior_mean)
  expect_true(all(out$n_sites_combined == 1L))
  expect_true(all(is.na(out$combined_sites)))
})

# ---- Multi-site combination -----------------------------------------------------

test_that("multi-site candidates are combined to one row each", {
  df <- .make_multisite_joined()
  out <- suppressMessages(combine_multisite_priors(df))

  expect_equal(nrow(out), 2L)
  expect_setequal(out$taxon_name, c("Species_a", "Species_b"))
  expect_true(all(out$n_sites_combined == 2L))
  expect_true(all(is.na(out$grid_id)))
  expect_true(all(is.na(out$main_habitat)))
  expect_equal(
    sort(strsplit(out$combined_sites[1], "|", fixed = TRUE)[[1]]),
    c("site1", "site2")
  )
})

test_that("combination is symmetric and gives the confidently-supported candidate more than half", {
  # Species_a is confidently favored at site1 (phi=10) and only weakly
  # disfavored at site2 (also phi=10) -- symmetric setup, so Species_a's
  # combined mean should exceed 0.5 and exceed Species_b's.
  df <- .make_multisite_joined()
  out <- suppressMessages(combine_multisite_priors(df))

  a_mean <- out$prior_mean[out$taxon_name == "Species_a"]
  b_mean <- out$prior_mean[out$taxon_name == "Species_b"]
  expect_equal(a_mean, b_mean) # fully symmetric fixture -> tie is correct here
  expect_true(a_mean > 0 && a_mean < 1)
})

test_that("a low-confidence (low-phi) site is discounted relative to a high-confidence site", {
  # Site A: phi=100, confidently favors X (mean 0.8) over Y (mean 0.2).
  # Site B: phi=5, weakly favors Y (mean 0.6) over X (mean 0.4) -- sparse,
  # possibly spurious signal in the OPPOSITE direction from site A.
  # Precision-weighted combination should still let X win decisively,
  # discounting site B's low-confidence signal -- unlike a plain product of
  # means, which would only give X ~72.7% (see combine_multisite_priors()
  # roxygen for the full worked comparison).
  df <- tibble(
    observation_id   = "obs1",
    taxon_name       = c("X", "X", "Y", "Y"),
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = c("siteA", "siteB", "siteA", "siteB"),
    main_habitat     = "Marine",
    prior_alpha      = c(80, 2, 20, 3),
    prior_beta       = c(20, 3, 80, 2),
    prior_mean       = c(0.8, 0.4, 0.2, 0.6)
  )
  out <- suppressMessages(combine_multisite_priors(df))

  x_mean <- out$prior_mean[out$taxon_name == "X"]
  y_mean <- out$prior_mean[out$taxon_name == "Y"]
  combined_x_share <- x_mean / (x_mean + y_mean)

  expect_gt(combined_x_share, 0.75) # precision-weighted combination gives ~0.785
  expect_lt(combined_x_share, 0.80)
})

test_that("other columns are inherited from the per-site rows on combined rows", {
  df <- .make_multisite_joined()
  out <- suppressMessages(combine_multisite_priors(df))

  expect_true(all(out$hypothesis_type == "specific_candidate"))
  expect_true(all(out$score_likelihood == 1))
  expect_true(all(out$observation_id == "obs1"))
})

test_that("a mixed batch (some multi-site, some single-site) handles both correctly", {
  multi <- .make_multisite_joined()
  single <- tibble(
    observation_id   = "obs2",
    taxon_name       = "Species_c",
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = "site1",
    main_habitat     = "Marine",
    prior_alpha      = 5,
    prior_beta       = 5,
    prior_mean       = 0.5
  )
  df <- bind_rows(multi, single)
  out <- suppressMessages(combine_multisite_priors(df))

  expect_equal(nrow(out), 3L) # 2 combined (obs1) + 1 passthrough (obs2)
  obs2_row <- out |> filter(observation_id == "obs2")
  expect_equal(obs2_row$n_sites_combined, 1L)
  expect_equal(obs2_row$grid_id, "site1")
})

test_that("prior_mean is required, not silently NA-filled", {
  # Regression: prior_mean was used (arrange + recomputed on combined rows)
  # but not validated. With mixed multi-/single-site input and no prior_mean
  # column, combined rows got a real value while single-site rows were
  # NA-filled by bind_rows -- an NA prior flowing into compute_posterior().
  df <- data.frame(
    observation_id = c("obs1", "obs1", "obs1"),
    taxon_name = c("Species_a", "Species_a", "Species_b"),
    taxon_name_rank = "species",
    grid_id = c("site1", "site2", "site1"),
    main_habitat = "Marine",
    prior_alpha = c(80, 3, 10),
    prior_beta = c(20, 2, 90),
    stringsAsFactors = FALSE
  )
  expect_error(combine_multisite_priors(df), "prior_mean")
})


# ---- J-shaped priors (2026-09-12) --------------------------------------------

test_that("all-sites J-shaped priors (dark-diversity floor) combine to finite, positive parameters", {
  # The exact real numbers from the first PtConception multi-site run: an
  # unreferenced species at two sites, each at the dark-diversity floor.
  df <- tibble(
    observation_id   = "ESV_000787",
    taxon_name       = c("Sardinops caeruleus", "Sardinops caeruleus"),
    taxon_name_rank  = "species",
    hypothesis_type  = "unreferenced_species",
    score_likelihood = 1,
    grid_id          = c("Site_BioD", "Site_Jalama"),
    main_habitat     = "Marine",
    prior_alpha      = c(1.913572e-06, 1.913572e-06),
    prior_beta       = c(1.999998, 1.999998),
    prior_mean       = c(9.567861e-07, 9.567861e-07)
  )
  out <- suppressMessages(combine_multisite_priors(df))
  expect_equal(nrow(out), 1L)
  expect_true(is.finite(out$prior_alpha) && out$prior_alpha > 0)
  expect_true(is.finite(out$prior_beta) && out$prior_beta > 0)
  expect_equal(out$prior_mean, 9.567861e-07, tolerance = 1e-6)
  # two identical priors -> same mean, at least twice the concentration
  expect_gte(out$prior_alpha + out$prior_beta, 2 * (1.913572e-06 + 1.999998) * 0.999)
  expect_equal(out$n_sites_combined, 2L)
  expect_no_error(compute_posterior(out |> mutate(score_likelihood_mean = 1, score_likelihood_sd = 0.1), n_sims = 50L))
})

test_that("an evidence-blend row (alpha ~ 6e-5, beta ~ 3e5) at three sites combines finitely", {
  df <- tibble(
    observation_id   = "obs1",
    taxon_name       = "Sardinops melanosticta",
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = c("s1", "s2", "s3"),
    main_habitat     = "Marine",
    prior_alpha      = rep(6.36355e-05, 3),
    prior_beta       = rep(262890, 3),
    prior_mean       = rep(2.420613e-10, 3)
  )
  out <- suppressMessages(combine_multisite_priors(df))
  expect_true(all(is.finite(c(out$prior_alpha, out$prior_beta, out$prior_mean))))
  expect_true(out$prior_alpha > 0 && out$prior_beta > 0)
  expect_equal(out$prior_mean, 2.420613e-10, tolerance = 1e-6)
})

test_that("J-shaped site plus moderate site: logit rule ignores the floor, confident site dominates", {
  df <- tibble(
    observation_id   = "obs1",
    taxon_name       = "X",
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = c("floor_site", "data_site"),
    main_habitat     = "Marine",
    prior_alpha      = c(2e-6, 80),
    prior_beta       = c(2, 20),
    prior_mean       = c(1e-6, 0.8)
  )
  out <- suppressMessages(combine_multisite_priors(df))
  expect_true(all(is.finite(c(out$prior_alpha, out$prior_beta))))
  # The floor's logit weight is ~alpha^2, so the result is the informative
  # site alone: plogis(digamma(80) - digamma(20)) = 0.803 (the logit-scale
  # mean of a Beta is not the logit of its mean).
  expect_equal(out$prior_mean, stats::plogis(digamma(80) - digamma(20)), tolerance = 1e-3)
})

test_that("moderate priors still use the logit rule (worked numbers unchanged)", {
  df <- tibble(
    observation_id   = "obs1",
    taxon_name       = c("X", "X", "Y", "Y"),
    taxon_name_rank  = "species",
    hypothesis_type  = "specific_candidate",
    score_likelihood = 1,
    grid_id          = c("siteA", "siteB", "siteA", "siteB"),
    main_habitat     = "Marine",
    prior_alpha      = c(80, 2, 20, 3),
    prior_beta       = c(20, 3, 80, 2),
    prior_mean       = c(0.8, 0.4, 0.2, 0.6)
  )
  out <- suppressMessages(combine_multisite_priors(df))
  x <- out$prior_mean[out$taxon_name == "X"]
  y <- out$prior_mean[out$taxon_name == "Y"]
  expect_equal(x / (x + y), 0.785, tolerance = 0.01)
})


test_that("presence-mixture columns that differ across sites are blanked with a warning (2026-09-13)", {
  joined <- data.frame(
    observation_id = c("ASV_1", "ASV_1", "ASV_2", "ASV_2"),
    taxon_name = c("Cervus elaphus", "Cervus elaphus", "Gadus morhua", "Gadus morhua"),
    taxon_name_rank = "species",
    grid_id = c("Site_A", "Site_B", "Site_A", "Site_B"),
    main_habitat = "Marine",
    prior_alpha = c(6e-5, 6e-5, 5, 5),
    prior_beta = c(3e5, 3e5, 100, 100),
    prior_mean = c(2e-10, 2e-10, 0.048, 0.048),
    prior_mix_w = c(0.35, 6.36e-5, 0.2, 0.2),
    prior_mix_theta_present = c(0.02, 0.02, 0.05, 0.05),
    prior_mix_theta_absent = c(0, 0, 0, 0),
    stringsAsFactors = FALSE
  )
  expect_warning(out <- combine_multisite_priors(joined), "DIFFER across sites")
  ce <- out[out$taxon_name == "Cervus elaphus", ]
  gm <- out[out$taxon_name == "Gadus morhua", ]
  expect_equal(nrow(ce), 1L)
  expect_equal(nrow(gm), 1L)
  expect_true(is.na(ce$prior_mix_w))
  expect_true(is.na(ce$prior_mix_theta_present))
  expect_true(is.finite(ce$prior_alpha) && ce$prior_alpha > 0)
  # identical mixture across sites is inherited unchanged, no warning
  expect_equal(gm$prior_mix_w, 0.2)
  expect_false(".mix_dropped" %in% names(out))
  expect_no_warning(combine_multisite_priors(joined[joined$taxon_name == "Gadus morhua", ]))
})
