# test-generate_full_priors.R
# Tests for generate_full_priors().
#
# Structure:
#   - Input validation (no model needed)
#   - Integration tests (require glmmTMB; use minimal synthetic pipeline)
#
# generate_full_priors() wraps a fitted glmmTMB model, so integration tests
# build a minimal biofreq_model via train_biodiversity_model() on tiny data.

library(testthat)
library(dplyr)

# =============================================================================
# Minimal synthetic pipeline helpers
# (mirrors the approach in test-train_biodiversity_model.R)
# =============================================================================

.make_sites <- function(n_sites = 10, habitats = c("Rocky", "Sandy")) {
  set.seed(42)
  expand.grid(
    grid_id      = paste0("Grid_", seq_len(n_sites), "p0_m120p0"),
    main_habitat = habitats,
    stringsAsFactors = FALSE
  ) |>
    dplyr::mutate(
      lat_r          = runif(dplyr::n(), 33, 38),
      lon_r          = runif(dplyr::n(), -122, -117),
      n_total_at_site = sample(20:50, dplyr::n(), replace = TRUE)
    )
}

.make_model_data <- function(n_sites     = 10,
                              n_common    = 3,
                              n_rare      = 2,
                              habitats    = c("Rocky", "Sandy")) {
  set.seed(7)
  sites    <- .make_sites(n_sites, habitats)
  taxa_t1  <- paste0("Species_", seq_len(n_common))
  taxa_t2  <- paste0("Rare_",    seq_len(n_rare))
  all_taxa <- c(taxa_t1, taxa_t2)

  tidyr::crossing(
    dplyr::tibble(taxon_name = all_taxa),
    sites
  ) |>
    dplyr::mutate(
      n_species = ifelse(taxon_name %in% taxa_t1,
                         sample(0:8, dplyr::n(), replace = TRUE),
                         sample(0:2, dplyr::n(), replace = TRUE)),
      n_other   = n_total_at_site - n_species,
      is_present = as.integer(n_species > 0),
      lat_r_s   = as.numeric(scale(lat_r)),
      lon_r_s   = as.numeric(scale(lon_r)),
      main_habitat = factor(main_habitat)
    ) |>
    structure(
      scale_params = list(
        lat_r = list(center = mean(sites$lat_r), scale = sd(sites$lat_r)),
        lon_r = list(center = mean(sites$lon_r), scale = sd(sites$lon_r))
      )
    )
}

.fit_minimal_model <- function() {
  skip_if_not_installed("glmmTMB")
  data <- .make_model_data()
  train_biodiversity_model(
    data              = data,
    formula           = cbind(n_species, n_other) ~
      main_habitat + (1 | taxon_name) + (1 | taxon_name:grid_id),
    min_obs_threshold = 3L,
    effort_threshold  = 5L,
    min_positive_rows = 1L
  )
}

.make_new_sites <- function(n = 5) {
  set.seed(99)
  data.frame(
    grid_id         = paste0("Grid_", seq_len(n), "p0_m121p0"),
    main_habitat    = rep(c("Rocky", "Sandy"), length.out = n),
    lat_r           = runif(n, 34, 37),
    lon_r           = runif(n, -121, -118),
    n_total_at_site = sample(20:40, n, replace = TRUE),
    stringsAsFactors = FALSE
  )
}

# --- No-habitat variants (habitat_col = NULL) --------------------------------

.make_model_data_no_habitat <- function(n_sites = 10, n_common = 3, n_rare = 2) {
  d <- .make_model_data(n_sites = n_sites, n_common = n_common,
                        n_rare = n_rare, habitats = "Rocky")
  sp <- attr(d, "scale_params")
  d$main_habitat <- NULL
  structure(as.data.frame(d), scale_params = sp)
}

.fit_minimal_model_no_habitat <- function() {
  skip_if_not_installed("glmmTMB")
  data <- .make_model_data_no_habitat()
  train_biodiversity_model(
    data              = data,
    formula           = cbind(n_species, n_other) ~
      (1 | taxon_name) + (1 | taxon_name:grid_id),
    habitat_col       = NULL,
    min_obs_threshold = 3L,
    effort_threshold  = 5L,
    min_positive_rows = 1L
  )
}

.make_new_sites_no_habitat <- function(n = 5) {
  s <- .make_new_sites(n)
  s$main_habitat <- NULL
  s
}

# =============================================================================
# Input validation (no model needed)
# =============================================================================

test_that("stops if model_obj is not a biofreq_model", {
  expect_error(
    generate_full_priors(list(), new_sites = data.frame()),
    regexp = "biofreq_model"
  )
})

test_that("stops if new_sites missing required columns", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  expect_error(
    generate_full_priors(mod, new_sites = data.frame(lat_r = 1)),
    regexp = "missing columns"
  )
})

# =============================================================================
# Output structure
# =============================================================================

test_that("returns a data frame", {
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  sites <- .make_new_sites()
  out   <- generate_full_priors(mod, new_sites = sites)
  expect_true(is.data.frame(out))
})

test_that("output contains all documented columns", {
  skip_if_not_installed("glmmTMB")
  mod      <- .fit_minimal_model()
  sites    <- .make_new_sites()
  out      <- generate_full_priors(mod, new_sites = sites)
  required <- c("taxon_name", "grid_id", "main_habitat", "alpha", "beta",
                "theta_mean", "theta_sd", "n_obs", "model_tier",
                "effort_flag", "observed_in_habitat",
                "extrapolation_warning", "undetected_type")
  for (col in required) {
    expect_true(col %in% names(out), info = paste("Missing column:", col))
  }
})

test_that("model_tier values are valid", {
  skip_if_not_installed("glmmTMB")
  mod  <- .fit_minimal_model()
  out  <- generate_full_priors(mod, new_sites = .make_new_sites())
  valid_tiers <- c("tier1", "tier2", "tier3_undetected")
  expect_true(all(out$model_tier %in% valid_tiers))
})

test_that("alpha and beta are positive numeric", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expect_true(all(out$alpha > 0))
  expect_true(all(out$beta  > 0))
})

test_that("theta_mean is in (0, 1)", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expect_true(all(out$theta_mean > 0 & out$theta_mean < 1))
})

test_that("theta_mean equals alpha / (alpha + beta)", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expected <- out$alpha / (out$alpha + out$beta)
  expect_equal(out$theta_mean, expected, tolerance = 1e-6)
})

# =============================================================================
# Effort flag
# =============================================================================

test_that("effort_flag is NA when n_total_at_site is absent from new_sites", {
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  sites <- .make_new_sites()
  sites$n_total_at_site <- NULL
  out   <- generate_full_priors(mod, new_sites = sites)
  expect_true(all(is.na(out$effort_flag)))
})

test_that("effort_flag is logical when n_total_at_site is present", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expect_type(out$effort_flag, "logical")
})

# =============================================================================
# Undetected rows
# =============================================================================

test_that("undetected rows are appended when undetected is supplied", {
  skip_if_not_installed("glmmTMB")
  mod      <- .fit_minimal_model()
  sites    <- .make_new_sites()
  undet    <- generate_undetected_diversity(mod)
  out_with <- generate_full_priors(mod, new_sites = sites, undetected = undet)
  out_base <- generate_full_priors(mod, new_sites = sites, undetected = NULL)
  expect_gt(nrow(out_with), nrow(out_base))
})

test_that("Tier 1 predictions are unaffected by the Tier-2-only singleton-mirror floor", {
  # Regression test for a real bug found 2026-07-03: theta_epsilon's
  # singleton-mirror-derived auto-raise (meant to protect Tier 2 from
  # collapsing to the dark-diversity floor) was being applied globally,
  # silently flattening Tier 1 species whose real predicted probability fell
  # below the raised floor to an identical value. Tier 1's output must be
  # IDENTICAL whether or not `undetected` supplies singleton_mirror rows --
  # narrowed 2026-08-27 to singleton_mirror specifically (see the new
  # global_floor-only tests below): `undetected` CAN now legitimately change
  # Tier 1 output via the separate, smaller global_floor-derived raise added
  # that day, so this test isolates the ORIGINAL bug's own trigger
  # (singleton_mirror rows only, no global_floor row) to keep asserting
  # exactly what it always asserted.
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  sites <- .make_new_sites()
  undet <- generate_undetected_diversity(mod)
  undet_sm_only <- undet[is.na(undet$undetected_type) |
                           undet$undetected_type != "global_floor", , drop = FALSE]

  out_with <- generate_full_priors(mod, new_sites = sites, undetected = undet_sm_only)
  out_base <- generate_full_priors(mod, new_sites = sites, undetected = NULL)

  t1_with <- out_with |>
    dplyr::filter(model_tier == "tier1") |>
    dplyr::arrange(taxon_name, grid_id) |>
    dplyr::pull(theta_mean)
  t1_base <- out_base |>
    dplyr::filter(model_tier == "tier1") |>
    dplyr::arrange(taxon_name, grid_id) |>
    dplyr::pull(theta_mean)

  expect_equal(t1_with, t1_base)
})

test_that("Tier 1 predictions are raised to the global_floor value when they fall below it", {
  # New 2026-08-27: a genuinely fitted Tier 1 estimate for a real,
  # in-habitat species must never sit below that study's own dark-diversity
  # global_floor (the "we have zero occurrence evidence for this taxon at
  # all" baseline) -- real motivating case: GreatLakes2023's Salmo trutta
  # (18 real occurrence records, observed_in_habitat = TRUE, fitted
  # theta_mean = 4.18e-6) sat below that dataset's own global_floor
  # (~9.59e-5), letting several zero-evidence Old World Salmo relatives
  # (correctly at the generic floor) outscore it on posterior mass. An
  # artificially extreme synthetic global_floor (theta = 0.999) is used here
  # to guarantee every real Tier 1 prediction from the minimal fitted model
  # falls below it, so the raise is deterministically exercised without
  # needing to engineer a specific tiny model fit.
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  sites <- .make_new_sites()

  out_base <- generate_full_priors(mod, new_sites = sites, undetected = NULL)
  t1_base  <- out_base[out_base$model_tier == "tier1", ]
  expect_true(all(t1_base$theta_mean < 0.999))  # sanity: the raise must have real work to do

  extreme_floor <- generate_undetected_diversity(mod)
  extreme_floor <- extreme_floor[extreme_floor$undetected_type == "global_floor", ]
  extreme_floor$alpha <- 999
  extreme_floor$beta  <- 1
  out_raised <- generate_full_priors(mod, new_sites = sites, undetected = extreme_floor)
  t1_raised  <- out_raised[out_raised$model_tier == "tier1", ]

  expect_true(all(t1_raised$theta_mean >= 0.999 - 1e-9))
})

test_that("a global_floor-only undetected does NOT trigger the separate Tier-2/singleton-mirror raise", {
  # The two mechanisms must stay independent: supplying only a global_floor
  # row (no singleton_mirror rows) must not accidentally also raise Tier 2's
  # own, separate floor.
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  sites <- .make_new_sites()

  out_base <- generate_full_priors(mod, new_sites = sites, undetected = NULL)
  extreme_floor <- generate_undetected_diversity(mod)
  extreme_floor <- extreme_floor[extreme_floor$undetected_type == "global_floor", ]
  extreme_floor$alpha <- 999
  extreme_floor$beta  <- 1
  out_gf <- generate_full_priors(mod, new_sites = sites, undetected = extreme_floor)

  t2_base <- out_base[out_base$model_tier == "tier2", ] |> dplyr::arrange(taxon_name, grid_id) |> dplyr::pull(theta_mean)
  t2_gf   <- out_gf[out_gf$model_tier == "tier2", ]   |> dplyr::arrange(taxon_name, grid_id) |> dplyr::pull(theta_mean)
  expect_equal(t2_base, t2_gf)
})

test_that("real generate_undetected_diversity() output never leaves a Tier 1 row below its own global_floor", {
  # General invariant check against the real (not synthetic-extreme)
  # generate_undetected_diversity() output, confirming the fix holds under
  # realistic conditions too, not just the deterministic extreme-floor case
  # above.
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  sites <- .make_new_sites()
  undet <- generate_undetected_diversity(mod)
  gf_row <- undet[!is.na(undet$undetected_type) & undet$undetected_type == "global_floor", ]
  skip_if(nrow(gf_row) == 0, "no global_floor row produced for this fixture")
  floor_val <- gf_row$alpha[1] / (gf_row$alpha[1] + gf_row$beta[1])

  out <- generate_full_priors(mod, new_sites = sites, undetected = undet)
  t1  <- out[out$model_tier == "tier1", ]
  expect_true(all(t1$theta_mean >= floor_val - 1e-9))
})

test_that("undetected rows have taxon_name = NA", {
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model()
  undet <- generate_undetected_diversity(mod)
  out   <- generate_full_priors(mod, new_sites = .make_new_sites(),
                                undetected = undet)
  undet_rows <- out[out$model_tier == "tier3_undetected", ]
  if (nrow(undet_rows) > 0) {
    expect_true(all(is.na(undet_rows$taxon_name)))
  }
})

# =============================================================================
# Extrapolation flag
# =============================================================================

test_that("extrapolation_warning is logical", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  expect_type(out$extrapolation_warning, "logical")
})

# =============================================================================
# undetected_type column
# =============================================================================

test_that("undetected_type is NA for modelled rows", {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  out <- generate_full_priors(mod, new_sites = .make_new_sites())
  modelled <- out[!is.na(out$taxon_name), ]
  expect_true(all(is.na(modelled$undetected_type)))
})

# =============================================================================
# habitat_col = NULL (no-habitat path)
# =============================================================================

test_that("habitat_col = NULL: output has no habitat column, Tier 2 included", {
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model_no_habitat()
  sites <- .make_new_sites_no_habitat()
  out   <- generate_full_priors(mod, new_sites = sites)

  expect_true(is.data.frame(out))
  expect_false("main_habitat" %in% names(out))
  expect_true(all(c("taxon_name", "grid_id", "alpha", "beta",
                    "theta_mean", "theta_sd", "model_tier") %in% names(out)))
  # Tier 2 species (Rare_*) must have received a prior, whether from the
  # GLMM or the empirical fallback -- not silently dropped.
  expect_true(any(grepl("^Rare_", out$taxon_name)))
})

test_that("habitat_col = NULL: undetected diversity appends cleanly", {
  skip_if_not_installed("glmmTMB")
  mod   <- .fit_minimal_model_no_habitat()
  sites <- .make_new_sites_no_habitat()
  undet <- generate_undetected_diversity(mod)
  out   <- generate_full_priors(mod, new_sites = sites, undetected = undet)

  expect_false("main_habitat" %in% names(out))
  undet_rows <- out[out$model_tier == "tier3_undetected", ]
  expect_true(nrow(undet_rows) > 0)
  expect_true(all(is.na(undet_rows$taxon_name)))
})

# =============================================================================
# moment_match() fallback (Session 149): preserve the mean instead of
# discarding it for an agnostic Jeffreys mean of 0.5, exercised via the Tier 2
# empirical fallback path (predict_tier_empirical()) so theta_sd_emp can be
# controlled directly without needing a real GLMM to produce a degenerate SE.
# =============================================================================

.make_empirical_fallback_model <- function(sd_values, mean_values = c(0.001, 0.002)) {
  skip_if_not_installed("glmmTMB")
  mod <- .fit_minimal_model()
  mod$models$tier2 <- NULL
  mod$tiers <- dplyr::bind_rows(
    mod$tiers[mod$tiers$tier == "tier1", ],
    tibble::tibble(taxon_name = c("Rare_probe1", "Rare_probe2"),
                   tier = "tier2", n_detections = 1L)
  )
  mod$tier2_empirical <- tibble::tibble(
    taxon_name     = c("Rare_probe1", "Rare_probe2"),
    main_habitat   = c("Rocky", "Rocky"),
    theta_mean_emp = mean_values,
    theta_sd_emp   = sd_values,
    n_detections   = 1L
  )
  mod
}

test_that("non-finite variance (NA SE) with default min_phi preserves the mean, not 0.5", {
  mod <- .make_empirical_fallback_model(sd_values = c(NA_real_, 0.01))
  out <- suppressWarnings(
    generate_full_priors(mod, new_sites = .make_new_sites(), min_phi = 2)
  )

  row <- out[out$taxon_name == "Rare_probe1" & !is.na(out$taxon_name), ][1, ]
  expect_true(row$jeffreys_fallback)
  # Mean-preserving fallback at concentration min_phi=2: alpha = 0.001*2, beta = 0.999*2.
  expect_equal(unname(row$alpha), 0.001 * 2, tolerance = 1e-8)
  expect_equal(unname(row$beta),  0.999 * 2, tolerance = 1e-8)
  expect_false(isTRUE(all.equal(unname(c(row$alpha, row$beta)), c(0.5, 0.5))))
})

test_that("large-but-finite variance with min_phi = 0 also preserves the mean, not 0.5", {
  mod <- .make_empirical_fallback_model(sd_values = c(0.01, 50))
  out <- suppressWarnings(
    generate_full_priors(mod, new_sites = .make_new_sites(), min_phi = 0)
  )

  row <- out[out$taxon_name == "Rare_probe2" & !is.na(out$taxon_name), ][1, ]
  expect_true(row$jeffreys_fallback)
  # min_phi = 0 -> fallback concentration is 1 (true Jeffreys concentration),
  # but the mean is still the model's own 0.002, not the agnostic 0.5.
  expect_equal(unname(row$alpha), 0.002, tolerance = 1e-8)
  expect_equal(unname(row$beta),  0.998, tolerance = 1e-8)
})

test_that("a genuinely unusable mean (NaN) still falls back to true Jeffreys Beta(0.5, 0.5)", {
  mod <- .make_empirical_fallback_model(
    sd_values   = c(0.01, 0.01),
    mean_values = c(NaN, 0.002)
  )
  out <- suppressWarnings(
    generate_full_priors(mod, new_sites = .make_new_sites(), min_phi = 2)
  )

  row <- out[out$taxon_name == "Rare_probe1" & !is.na(out$taxon_name), ][1, ]
  expect_true(row$jeffreys_fallback)
  expect_equal(unname(row$alpha), 0.5)
  expect_equal(unname(row$beta),  0.5)
})
