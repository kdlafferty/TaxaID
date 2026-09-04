# test-apply_undetected_evidence.R
# Tests for apply_undetected_evidence().

library(testthat)
library(dplyr)

.make_mock_model_obj <- function(habitat_col = "main_habitat") {
  structure(
    list(N_total = 1000L, meta = list(habitat_col = habitat_col)),
    class = "biofreq_model"
  )
}

# A minimal, realistic taxaexpect_priors: one global_floor row, one
# singleton_mirror row at the test site, one modelled (Tier 1) named row.
.make_priors <- function(habitat_col = "main_habitat", grid = "Grid_A", hab = "Lentic") {
  floor_row <- tibble::tibble(
    taxon_name = NA_character_, taxon_name_rank = NA_character_,
    grid_id = NA_character_, alpha = 1, beta = 999,
    theta_mean = 1/1000, theta_sd = NA_real_,
    model_tier = "tier3_undetected", undetected_type = "global_floor",
    source_taxon_name = NA_character_
  )
  singleton_row <- tibble::tibble(
    taxon_name = NA_character_, taxon_name_rank = NA_character_,
    grid_id = grid, alpha = 0.05, beta = 1.95,
    theta_mean = 0.025, theta_sd = NA_real_,
    model_tier = "tier3_undetected", undetected_type = "singleton_mirror",
    source_taxon_name = "Sander vitreus"
  )
  modelled_row <- tibble::tibble(
    taxon_name = "Perca flavescens", taxon_name_rank = "species",
    grid_id = grid, alpha = 40, beta = 60,
    theta_mean = 0.4, theta_sd = NA_real_,
    model_tier = "tier1", undetected_type = NA_character_,
    source_taxon_name = NA_character_
  )
  out <- dplyr::bind_rows(floor_row, singleton_row, modelled_row)
  if (!is.null(habitat_col)) {
    out[[habitat_col]] <- c(NA_character_, hab, hab)
  }
  out
}

.make_evidence <- function(taxon_name = "Gymnocephalus cernua", weight = 0.5, p_conc = 4, source = "invasive_watch") {
  tibble::tibble(taxon_name = taxon_name, weight = weight, p_conc = p_conc, source = source)
}

# =============================================================================
# Input validation
# =============================================================================

test_that("stops when model_obj is not a biofreq_model", {
  expect_error(
    apply_undetected_evidence(.make_priors(), list(), .make_evidence(), grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "biofreq_model"
  )
})

test_that("stops when grid_id is missing/invalid", {
  expect_error(
    apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence(), grid_id = NA_character_, main_habitat = "Lentic"),
    regexp = "grid_id"
  )
})

test_that("stops when main_habitat is missing but habitat_col is non-NULL", {
  expect_error(
    apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence(), grid_id = "Grid_A"),
    regexp = "main_habitat"
  )
})

test_that("stops when main_habitat is supplied but habitat_col is NULL", {
  expect_error(
    apply_undetected_evidence(
      .make_priors(habitat_col = NULL), .make_mock_model_obj(habitat_col = NULL),
      .make_evidence(), grid_id = "Grid_A", main_habitat = "Lentic"
    ),
    regexp = "main_habitat"
  )
})

test_that("stops when evidence is missing required columns", {
  expect_error(
    apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), tibble::tibble(taxon_name = "X"), grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "evidence"
  )
})

test_that("stops when weight is out of [0,1]", {
  expect_error(
    apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence(weight = 1.5), grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "weight"
  )
})

test_that("stops when p_conc is non-positive", {
  expect_error(
    apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence(p_conc = 0), grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "p_conc"
  )
})

test_that("stops when taxaexpect_priors has no global_floor row", {
  priors_no_floor <- .make_priors() |> dplyr::filter(undetected_type != "global_floor" | is.na(undetected_type))
  expect_error(
    apply_undetected_evidence(priors_no_floor, .make_mock_model_obj(), .make_evidence(), grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "global_floor"
  )
})

# =============================================================================
# Empty / no-op paths
# =============================================================================

test_that("empty evidence returns an empty tibble with the documented schema", {
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), tibble::tibble(taxon_name=character(0), weight=numeric(0), p_conc=numeric(0), source=character(0)), grid_id = "Grid_A", main_habitat = "Lentic")
  expect_s3_class(out, "tbl_df")
  expect_equal(nrow(out), 0L)
  expect_true(all(c("taxon_name", "alpha", "beta", "undetected_type", "evidence_weight") %in% names(out)))
})

test_that("a taxon already modelled (Tier 1) is excluded, not elevated", {
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence("Perca flavescens"), grid_id = "Grid_A", main_habitat = "Lentic")
  expect_equal(nrow(out), 0L)
})

test_that("a taxon that was a singleton (via source_taxon_name) is excluded, not elevated", {
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence("Sander vitreus"), grid_id = "Grid_A", main_habitat = "Lentic")
  expect_equal(nrow(out), 0L)
})

# =============================================================================
# Core elevation math
# =============================================================================

test_that("a genuinely unobserved taxon is elevated with the documented blend formula", {
  priors <- .make_priors()
  out <- apply_undetected_evidence(priors, .make_mock_model_obj(), .make_evidence("Gymnocephalus cernua", weight = 0.5, p_conc = 4), grid_id = "Grid_A", main_habitat = "Lentic")
  expect_equal(nrow(out), 1L)

  theta_floor     <- 1/1000
  theta_singleton <- 0.025
  expected_theta  <- theta_floor + (theta_singleton - theta_floor) * 0.5

  expect_equal(out$theta_mean, expected_theta, tolerance = 1e-8)
  # Concentration is MOMENT-MATCHED to the presence mixture (2026-08-26), not
  # the caller's p_conc: v = w*Var_c + (1-w)*Var_f + w(1-w)*(theta_c-theta_f)^2
  var_c <- 0.025 * 0.975 / (0.05 + 1.95 + 1)
  var_f <- (1/1000) * (999/1000) / (1 + 999 + 1)
  v_mix <- 0.5 * var_c + 0.5 * var_f + 0.25 * (theta_singleton - theta_floor)^2
  n_eff_mm <- expected_theta * (1 - expected_theta) / v_mix - 1
  expect_equal(out$alpha + out$beta, n_eff_mm, tolerance = 1e-6)
  expect_equal(out$prior_mix_w, 0.5, tolerance = 1e-8)
  expect_equal(out$prior_mix_theta_present, theta_singleton, tolerance = 1e-8)
  expect_equal(out$prior_mix_theta_absent, theta_floor, tolerance = 1e-8)
  expect_equal(out$prior_mix_p_conc, 4, tolerance = 1e-8)
  expect_equal(out$taxon_name_rank, "species")
  expect_equal(out$grid_id, "Grid_A")
  expect_equal(out$main_habitat, "Lentic")
  expect_equal(out$undetected_type, "evidence_blend")
  expect_equal(out$model_tier, "tier_undetected_evidence")
})

test_that("weight = 1 elevates exactly to the singleton-mirror ceiling, never beyond", {
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence("Gymnocephalus cernua", weight = 1, p_conc = 4), grid_id = "Grid_A", main_habitat = "Lentic")
  expect_equal(out$theta_mean, 0.025, tolerance = 1e-8)
})

test_that("weight = 0 leaves theta exactly at the floor", {
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence("Gymnocephalus cernua", weight = 0, p_conc = 4), grid_id = "Grid_A", main_habitat = "Lentic")
  expect_equal(out$theta_mean, 1/1000, tolerance = 1e-8)
})

# ---- Ceiling anchor ladder (2026-08-26 mixture redesign, D2) ----------------
# Previously, priors without singleton_mirror rows silently collapsed the
# ceiling onto the floor, making every elevation a weight-independent no-op.
# Now the ceiling descends a ladder: singleton mean -> min modelled theta
# (site-scoped preferred) -> 1/(median site effort + 1) -> only then the old
# floor-equals-ceiling warning.

test_that("no singletons: ceiling falls back to the minimum modelled theta (site-scoped preferred)", {
  priors_no_singleton <- .make_priors() |>
    dplyr::filter(undetected_type != "singleton_mirror" | is.na(undetected_type)) |>
    dplyr::bind_rows(tibble::tibble(
      taxon_name = "Sander canadensis", taxon_name_rank = "species",
      grid_id = "Grid_B", alpha = 1, beta = 9,      # theta 0.1, but WRONG grid
      theta_mean = 0.1, theta_sd = NA_real_,
      model_tier = "tier1", undetected_type = NA_character_,
      source_taxon_name = NA_character_, main_habitat = "Lentic"
    ))
  expect_message(
    out <- apply_undetected_evidence(priors_no_singleton, .make_mock_model_obj(),
      .make_evidence("Gymnocephalus cernua", weight = 0.8, p_conc = 4),
      grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "minimum modelled theta"
  )
  # site-scoped min modelled theta at Grid_A is Perca's 40/(40+60) = 0.4,
  # NOT Grid_B's 0.1; blend = floor + (0.4 - floor) * 0.8
  expected <- 1/1000 + (0.4 - 1/1000) * 0.8
  expect_equal(out$theta_mean, expected, tolerance = 1e-8)
})

test_that("no singletons and no modelled rows: ceiling falls back to 1/(median site effort + 1)", {
  floor_only <- .make_priors() |>
    dplyr::filter(undetected_type %in% "global_floor")
  floor_only$n_obs <- 49
  expect_message(
    out <- apply_undetected_evidence(floor_only, .make_mock_model_obj(),
      .make_evidence("Gymnocephalus cernua", weight = 1, p_conc = 4),
      grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "site effort"
  )
  expect_equal(out$theta_mean, 1/50, tolerance = 1e-8)  # weight 1 -> ceiling exactly
})

test_that("no singletons, no modelled rows, no effort: warns and pins theta to the floor", {
  floor_only <- .make_priors() |>
    dplyr::filter(undetected_type %in% "global_floor")
  expect_warning(
    out <- apply_undetected_evidence(floor_only, .make_mock_model_obj(),
      .make_evidence("Gymnocephalus cernua", weight = 0.8, p_conc = 4),
      grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "no singleton_mirror"
  )
  expect_equal(out$theta_mean, 1/1000, tolerance = 1e-8)
})

test_that("ladder's modelled-theta rung ignores evidence/domestic named rows", {
  # Only 'modelled' named row is itself an evidence_blend row -- must NOT serve
  # as the ceiling anchor; with no true modelled rows and no n_obs, the ladder
  # bottoms out at the floor warning.
  pri <- .make_priors() |>
    dplyr::filter(undetected_type %in% "global_floor") |>
    dplyr::bind_rows(tibble::tibble(
      taxon_name = "Alburnus alburnus", taxon_name_rank = "species",
      grid_id = "Grid_A", alpha = 0.01, beta = 1.99,
      theta_mean = 0.005, theta_sd = NA_real_,
      model_tier = "tier_undetected_evidence", undetected_type = "evidence_blend",
      source_taxon_name = NA_character_, main_habitat = "Lentic"
    ))
  expect_warning(
    out <- apply_undetected_evidence(pri, .make_mock_model_obj(),
      .make_evidence("Gymnocephalus cernua", weight = 0.8, p_conc = 4),
      grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "no singleton_mirror"
  )
  expect_equal(out$theta_mean, 1/1000, tolerance = 1e-8)
})

# =============================================================================
# Multi-source combination
# =============================================================================

test_that("two sources for the same taxon combine weight via probabilistic-OR and p_conc via sum", {
  ev <- dplyr::bind_rows(
    .make_evidence("Gymnocephalus cernua", weight = 0.5, p_conc = 4, source = "invasive_watch"),
    .make_evidence("Gymnocephalus cernua", weight = 0.3, p_conc = 2, source = "regional_proximity")
  )
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), ev, grid_id = "Grid_A", main_habitat = "Lentic")
  expect_equal(nrow(out), 1L)

  w_expected <- 1 - (1 - 0.5) * (1 - 0.3)
  expect_equal(out$evidence_weight, w_expected, tolerance = 1e-8)
  expect_equal(out$prior_mix_w, w_expected, tolerance = 1e-8)
  expect_equal(out$prior_mix_p_conc, 6, tolerance = 1e-8)
  expect_true(grepl("invasive_watch", out$evidence_sources))
  expect_true(grepl("regional_proximity", out$evidence_sources))
})

test_that("combined weight from two sources never exceeds 1 / the singleton ceiling", {
  ev <- dplyr::bind_rows(
    .make_evidence("Gymnocephalus cernua", weight = 0.9, p_conc = 4, source = "invasive_watch"),
    .make_evidence("Gymnocephalus cernua", weight = 0.9, p_conc = 2, source = "regional_proximity")
  )
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), ev, grid_id = "Grid_A", main_habitat = "Lentic")
  expect_lt(out$evidence_weight, 1)
  expect_lte(out$theta_mean, 0.025 + 1e-8)
})

# =============================================================================
# Site-specific vs global singleton anchor
# =============================================================================

test_that("a site-specific singleton mean is preferred over the global one when both exist", {
  floor_row <- tibble::tibble(
    taxon_name = NA_character_, taxon_name_rank = NA_character_, grid_id = NA_character_,
    alpha = 1, beta = 999, theta_mean = 1/1000, theta_sd = NA_real_,
    model_tier = "tier3_undetected", undetected_type = "global_floor",
    source_taxon_name = NA_character_, main_habitat = NA_character_
  )
  singleton_site_a <- tibble::tibble(
    taxon_name = NA_character_, taxon_name_rank = NA_character_, grid_id = "Grid_A",
    alpha = 0.05, beta = 1.95, theta_mean = 0.025, theta_sd = NA_real_,
    model_tier = "tier3_undetected", undetected_type = "singleton_mirror",
    source_taxon_name = "Sander vitreus", main_habitat = "Lentic"
  )
  singleton_site_b <- tibble::tibble(
    taxon_name = NA_character_, taxon_name_rank = NA_character_, grid_id = "Grid_B",
    alpha = 0.5, beta = 1.5, theta_mean = 0.25, theta_sd = NA_real_,
    model_tier = "tier3_undetected", undetected_type = "singleton_mirror",
    source_taxon_name = "Esox lucius", main_habitat = "Lentic"
  )
  priors <- dplyr::bind_rows(floor_row, singleton_site_a, singleton_site_b)

  out <- apply_undetected_evidence(priors, .make_mock_model_obj(), .make_evidence("Gymnocephalus cernua", weight = 1, p_conc = 4), grid_id = "Grid_A", main_habitat = "Lentic")
  # Should use Grid_A's own singleton (0.025), not Grid_B's (0.25) or a pooled mean.
  expect_equal(out$theta_mean, 0.025, tolerance = 1e-8)
})

# =============================================================================
# habitat_col = NULL model
# =============================================================================

test_that("habitat_col = NULL model works with main_habitat = NULL and produces no habitat column", {
  priors <- .make_priors(habitat_col = NULL)
  out <- apply_undetected_evidence(priors, .make_mock_model_obj(habitat_col = NULL), .make_evidence("Gymnocephalus cernua", weight = 0.5, p_conc = 4), grid_id = "Grid_A")
  expect_equal(nrow(out), 1L)
  expect_false("main_habitat" %in% names(out))
})

# =============================================================================
# Taxonomy join
# =============================================================================

test_that("taxonomy join adds rank columns when supplied", {
  taxonomy <- tibble::tibble(taxon_name = "Gymnocephalus cernua", genus = "Gymnocephalus", family = "Percidae")
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), .make_evidence("Gymnocephalus cernua", weight = 0.5, p_conc = 4), grid_id = "Grid_A", main_habitat = "Lentic", taxonomy = taxonomy)
  expect_equal(out$genus, "Gymnocephalus")
  expect_equal(out$family, "Percidae")
})

test_that("legacy n_eff column without p_conc errors with migration guidance", {
  ev <- tibble::tibble(taxon_name = "Gymnocephalus cernua", weight = 0.5,
                        n_eff = 4, source = "invasive_watch")
  expect_error(
    apply_undetected_evidence(.make_priors(), .make_mock_model_obj(), ev,
                               grid_id = "Grid_A", main_habitat = "Lentic"),
    regexp = "retired"
  )
})

test_that("prints the dataset-specific veto bound (D4)", {
  msgs <- capture_messages(
    apply_undetected_evidence(.make_priors(), .make_mock_model_obj(),
      .make_evidence(), grid_id = "Grid_A", main_habitat = "Lentic")
  )
  expect_true(any(grepl("veto bound", msgs)))
  # bound value for these anchors: ((0.05/0.95)*0.025 - 0.001)/(0.025 - 0.001)
  expect_true(any(grepl("0.013", msgs)))
})

# ==============================================================================
# Curve pricing (unobserved-taxa redesign, 2026-08-31): theta = w * theta_present
# ==============================================================================

.make_kernel_fit_for_curve <- function() {
  # Real estimator on a tiny fixture: 3 records of A near the site, 1 of B, 1
  # of C (two singletons), so theta_present = missing_mass / chao_missing is a
  # genuine, hand-checkable kernel quantity, not a mock.
  occ <- data.frame(
    taxon_name = c("A", "A", "A", "B", "C"),
    decimalLatitude = 34 + (1:5) * 1e-6, decimalLongitude = -120,
    main_habitat = "Lentic", depth_m = NA_real_, stringsAsFactors = FALSE)
  estimate_kernel_priors(occ, 34, -120, "Lentic", lambda_km = 1e9, m = 0)
}

test_that("kernel fit emits f1/f2/chao_missing/theta_present", {
  kp <- .make_kernel_fit_for_curve()
  expect_equal(kp$f1, 2L)              # B and C are singletons
  expect_equal(kp$f2, 0L)
  expect_equal(kp$chao_missing, 1)     # f2 = 0 fallback: f1*(f1-1)/2
  expect_equal(kp$missing_mass, 2/5, tolerance = 1e-6)
  expect_equal(kp$theta_present, (2/5) / 1, tolerance = 1e-6)
})

test_that("curve pricing yields theta = w * theta_present with theta_absent = 0", {
  kp <- .make_kernel_fit_for_curve()
  priors <- dplyr::bind_rows(kp$priors,
                             .make_priors(grid = "budget", hab = "Lentic"))
  ev <- data.frame(taxon_name = c("Esox niger", "Ameiurus melas"),
                   weight = c(0.05, 0.5), source = "regional_proximity",
                   stringsAsFactors = FALSE)
  out <- apply_undetected_evidence(priors, kp, ev,
                                   grid_id = "budget", main_habitat = "Lentic",
                                   pricing = "curve")
  expect_equal(nrow(out), 2L)
  expect_equal(out$theta_mean, ev$weight * kp$theta_present, tolerance = 1e-6)
  expect_equal(out$prior_mix_theta_present, rep(kp$theta_present, 2))
  expect_equal(out$prior_mix_theta_absent, rep(0, 2))
  expect_equal(out$prior_mix_w, ev$weight)
  expect_equal(out$prior_branch, rep("resident_undetected", 2))
  # budget closure: branch evidence total = theta_present * sum(w)
  expect_equal(sum(out$theta_mean), kp$theta_present * sum(ev$weight),
               tolerance = 1e-9)
})

test_that("curve pricing prints f1/f2 next to the price it produced", {
  # Open decision #4 of the kernel budget/pricing re-entry doc: a budget figure
  # quoted without its doubleton count cannot be assessed by the reader.
  kp <- .make_kernel_fit_for_curve()
  priors <- dplyr::bind_rows(kp$priors,
                             .make_priors(grid = "budget", hab = "Lentic"))
  ev <- data.frame(taxon_name = "Esox niger", weight = 0.05,
                   source = "regional_proximity", stringsAsFactors = FALSE)
  msgs <- capture_messages(
    apply_undetected_evidence(priors, kp, ev, grid_id = "budget",
                              main_habitat = "Lentic", pricing = "curve"))
  expect_true(any(grepl("f1 = 2 singletons", msgs, fixed = TRUE)))
  expect_true(any(grepl("f2 = 0 doubletons", msgs, fixed = TRUE)))
  # f2 = 0 is the Chao fallback branch, not the single-digit caution branch
  expect_false(any(grepl("hypersensitive", msgs)))
})

test_that("curve pricing refuses a GLMM model_obj or a no-singleton kernel fit", {
  priors <- .make_priors()
  ev <- data.frame(taxon_name = "X y", weight = 0.1, source = "s",
                   stringsAsFactors = FALSE)
  expect_error(
    apply_undetected_evidence(priors, .make_mock_model_obj(), ev,
                              grid_id = "Grid_A", main_habitat = "Lentic",
                              pricing = "curve"),
    "theta_present")
  # kernel fit with no singletons (both species have 2+ records)
  occ <- data.frame(taxon_name = rep(c("A", "B"), each = 3),
                    decimalLatitude = 34, decimalLongitude = -120,
                    main_habitat = "Lentic", stringsAsFactors = FALSE)
  kp0 <- estimate_kernel_priors(occ, 34, -120, "Lentic", lambda_km = 1e9, m = 0)
  expect_error(
    apply_undetected_evidence(dplyr::bind_rows(kp0$priors, priors), kp0, ev,
                              grid_id = "Grid_A", main_habitat = "Lentic",
                              pricing = "curve"),
    "theta_present")
})

test_that("blend pricing is byte-identical with the pricing param defaulted", {
  kp <- .make_kernel_fit_for_curve()
  priors <- dplyr::bind_rows(kp$priors,
                             .make_priors(grid = "budget", hab = "Lentic"))
  ev <- data.frame(taxon_name = "Esox niger", weight = 0.3,
                   source = "regional_proximity", stringsAsFactors = FALSE)
  o1 <- apply_undetected_evidence(priors, kp, ev, grid_id = "budget",
                                  main_habitat = "Lentic")
  o2 <- apply_undetected_evidence(priors, kp, ev, grid_id = "budget",
                                  main_habitat = "Lentic", pricing = "blend")
  expect_identical(o1, o2)
})

# ==============================================================================
# Per-group curve pricing (2026-09-04). Open decision #2 of the kernel
# budget/pricing re-entry doc, unblocked by the real PtConception 18S
# diagnostic. The guards are exercised against the same failure shapes that
# diagnostic found on real data, not invented ones.
# ==============================================================================

.make_grouped_kernel_fit <- function() {
  set.seed(11)
  # fish: well supported, several singletons and doubletons -> qualifies.
  fish_common <- do.call(rbind, lapply(1:8, function(i) data.frame(
    taxon_name = sprintf("Fish_%02d", i),
    decimalLatitude = 34 + rnorm(40, 0, 0.02),
    decimalLongitude = -119 + rnorm(40, 0, 0.02),
    main_habitat = "Marine", sampling_group = "fishes",
    stringsAsFactors = FALSE)))
  fish_rare <- do.call(rbind, lapply(1:12, function(i) data.frame(
    taxon_name = sprintf("FishRare_%02d", i),
    decimalLatitude = 34 + rnorm(1, 0, 0.02),
    decimalLongitude = -119 + rnorm(1, 0, 0.02),
    main_habitat = "Marine", sampling_group = "fishes",
    stringsAsFactors = FALSE)))
  fish_double <- do.call(rbind, lapply(1:3, function(i) data.frame(
    taxon_name = sprintf("FishDbl_%02d", i),
    decimalLatitude = 34 + rnorm(2, 0, 0.02),
    decimalLongitude = -119 + rnorm(2, 0, 0.02),
    main_habitat = "Marine", sampling_group = "fishes",
    stringsAsFactors = FALSE)))
  # plants: the real "downwash" shape -- a handful of records, mostly
  # singletons. Far too thin to price itself.
  plants <- do.call(rbind, lapply(1:5, function(i) data.frame(
    taxon_name = sprintf("Plant_%02d", i),
    decimalLatitude = 34 + rnorm(1, 0, 0.02),
    decimalLongitude = -119 + rnorm(1, 0, 0.02),
    main_habitat = "Marine", sampling_group = "plants",
    stringsAsFactors = FALSE)))
  # inverts: also well supported, but a different singleton structure, so it
  # qualifies with a genuinely DIFFERENT price -- the whole point of the
  # mechanism is that two qualifying groups do not share one.
  inv_common <- do.call(rbind, lapply(1:15, function(i) data.frame(
    taxon_name = sprintf("Inv_%02d", i),
    decimalLatitude = 34 + rnorm(30, 0, 0.02),
    decimalLongitude = -119 + rnorm(30, 0, 0.02),
    main_habitat = "Marine", sampling_group = "inverts",
    stringsAsFactors = FALSE)))
  inv_rare <- do.call(rbind, lapply(1:4, function(i) data.frame(
    taxon_name = sprintf("InvRare_%02d", i),
    decimalLatitude = 34 + rnorm(1, 0, 0.02),
    decimalLongitude = -119 + rnorm(1, 0, 0.02),
    main_habitat = "Marine", sampling_group = "inverts",
    stringsAsFactors = FALSE)))
  occ <- rbind(fish_common, fish_rare, fish_double, inv_common, inv_rare, plants)
  suppressWarnings(estimate_kernel_priors(
    occ, 34, -119, "Marine", lambda_km = 25, m = 1,
    sampling_group_col = "sampling_group"))
}

.grouped_priors_and_evidence <- function(kp) {
  priors <- dplyr::bind_rows(kp$priors,
                             .make_priors(grid = "budget", hab = "Marine"))
  ev <- data.frame(
    taxon_name = c("Watchfish alpha", "Watchfish beta"),
    weight = c(0.05, 0.2), source = "invasive_watch",
    stringsAsFactors = FALSE)
  list(priors = priors, evidence = ev)
}

test_that("a single-group curve fit is completely unaffected by the group machinery", {
  kp <- .make_kernel_fit_for_curve()
  priors <- dplyr::bind_rows(kp$priors,
                             .make_priors(grid = "budget", hab = "Lentic"))
  ev <- data.frame(taxon_name = c("Esox niger", "Ameiurus melas"),
                   weight = c(0.05, 0.5), source = "regional_proximity",
                   stringsAsFactors = FALSE)
  out <- apply_undetected_evidence(priors, kp, ev, grid_id = "budget",
                                   main_habitat = "Lentic", pricing = "curve")
  # the pre-2026-09-04 expectations, unchanged
  expect_equal(out$theta_mean, ev$weight * kp$theta_present, tolerance = 1e-6)
  expect_equal(out$prior_mix_theta_present, rep(kp$theta_present, 2))
  expect_equal(sum(out$theta_mean), kp$theta_present * sum(ev$weight),
               tolerance = 1e-9)
  # the guards do not fire, and would not even if this thin fit failed them
  expect_equal(out$pricing_basis, rep("own_group", 2))
  # ... which is the point: n_eff here is ~5, far below min_group_n_eff = 100
  expect_lt(kp$n_eff, 100)
})

test_that("each taxon is priced by its own sampling group's budget", {
  kp <- .make_grouped_kernel_fit()
  fx <- .grouped_priors_and_evidence(kp)
  out <- suppressMessages(apply_undetected_evidence(
    fx$priors, kp, fx$evidence, grid_id = "budget", main_habitat = "Marine",
    pricing = "curve", sampling_group = "fishes"))
  fish_price <- kp$budget$theta_present[kp$budget$sampling_group == "fishes"]
  expect_equal(out$sampling_group, rep("fishes", 2))
  expect_equal(out$prior_mix_theta_present, rep(fish_price, 2))
  expect_equal(out$theta_mean, fx$evidence$weight * fish_price, tolerance = 1e-9)
  # the group's own budget, NOT the pooled scalar (which is NA by design)
  expect_true(is.na(kp$theta_present))
})

test_that("two qualifying groups in one call get two different prices", {
  kp <- .make_grouped_kernel_fit()
  fx <- .grouped_priors_and_evidence(kp)
  ev <- fx$evidence
  ev$sampling_group <- c("fishes", "inverts")
  out <- suppressMessages(apply_undetected_evidence(
    fx$priors, kp, ev, grid_id = "budget", main_habitat = "Marine",
    pricing = "curve"))
  expect_setequal(out$sampling_group, c("fishes", "inverts"))
  expect_equal(out$pricing_basis, rep("own_group", 2))
  expect_equal(length(unique(out$prior_mix_theta_present)), 2L)
  for (g in c("fishes", "inverts"))
    expect_equal(out$prior_mix_theta_present[out$sampling_group == g],
                 kp$budget$theta_present[kp$budget$sampling_group == g])
  # the evidence column wins over the argument
  out2 <- suppressMessages(apply_undetected_evidence(
    fx$priors, kp, ev, grid_id = "budget", main_habitat = "Marine",
    pricing = "curve", sampling_group = "fishes"))
  expect_equal(out2$sampling_group, out$sampling_group)
})

test_that("with only one qualifying group the borrowed price IS that group's", {
  # Not a coincidence to paper over -- it is what the group-wise combination
  # reduces to when the qualifying set has one member, and worth pinning.
  b <- data.frame(
    sampling_group = c("only", "thin"), n_taxa = c(20L, 2L), n_eff = c(500, 4),
    f1 = c(10L, 2L), f2 = c(2L, 0L), missing_mass = c(0.02, 0.5),
    chao_missing = c(25, 1), stringsAsFactors = FALSE)
  b$theta_present <- b$missing_mass / b$chao_missing
  kp <- structure(list(budget = b), class = "taxaexpect_kernel_priors")
  r <- TaxaExpect:::.resolve_group_prices(kp, 100, 1L, TRUE, "pooled_qualifying")
  expect_equal(r$n_qualifying, 1L)
  expect_equal(r$fallback_price, unname(r$price["only"]))
  expect_equal(unname(r$price["thin"]), unname(r$price["only"]))
  expect_equal(unname(r$basis["thin"]), "pooled_qualifying")
})

test_that("a group too thin to price itself borrows, and says so per row", {
  kp <- .make_grouped_kernel_fit()
  fx <- .grouped_priors_and_evidence(kp)
  ev <- fx$evidence
  ev$sampling_group <- c("fishes", "plants")
  msgs <- capture_messages(out <- apply_undetected_evidence(
    fx$priors, kp, ev, grid_id = "budget", main_habitat = "Marine",
    pricing = "curve"))
  plant_row <- out[out$sampling_group == "plants", ]
  expect_equal(plant_row$pricing_basis, "pooled_qualifying")
  expect_equal(out$pricing_basis[out$sampling_group == "fishes"], "own_group")
  expect_true(any(grepl("BORROWED price", msgs)))
  # the borrowed price is a real number, not the group's own untrusted one
  plants_own <- kp$budget$theta_present[kp$budget$sampling_group == "plants"]
  expect_false(isTRUE(all.equal(plant_row$prior_mix_theta_present, plants_own)))
})

test_that("group_fallback = 'error' and 'skip' behave as documented", {
  kp <- .make_grouped_kernel_fit()
  fx <- .grouped_priors_and_evidence(kp)
  ev <- fx$evidence
  ev$sampling_group <- c("fishes", "plants")
  expect_error(
    suppressMessages(apply_undetected_evidence(
      fx$priors, kp, ev, grid_id = "budget", main_habitat = "Marine",
      pricing = "curve", group_fallback = "error")),
    "failed the pricing guards")
  out <- suppressMessages(apply_undetected_evidence(
    fx$priors, kp, ev, grid_id = "budget", main_habitat = "Marine",
    pricing = "curve", group_fallback = "skip"))
  expect_equal(nrow(out), 1L)
  expect_equal(out$sampling_group, "fishes")
})

test_that("an unassigned taxon errors with actionable guidance, never a guess", {
  kp <- .make_grouped_kernel_fit()
  fx <- .grouped_priors_and_evidence(kp)
  expect_error(
    suppressMessages(apply_undetected_evidence(
      fx$priors, kp, fx$evidence, grid_id = "budget", main_habitat = "Marine",
      pricing = "curve")),
    "every evidence taxon needs one")
  expect_error(
    suppressMessages(apply_undetected_evidence(
      fx$priors, kp, fx$evidence, grid_id = "budget", main_habitat = "Marine",
      pricing = "curve", sampling_group = "not_a_real_group")),
    "not present in the fit's own budget")
})

test_that("the singleton cap binds exactly when f1 < 2*f2, and not otherwise", {
  # Constructed to the real PtConception 18S zooplankton shape: Chao < f1, so
  # mass/Chao prices an unseen species ABOVE a once-seen one.
  b <- data.frame(
    sampling_group = c("normal", "inverted"),
    n_taxa = c(10L, 10L), n_eff = c(500, 500),
    f1 = c(10L, 3L), f2 = c(2L, 7L),
    missing_mass = c(0.02, 0.02),
    chao_missing = c(25, 9 / 14),
    stringsAsFactors = FALSE)
  b$theta_present <- b$missing_mass / b$chao_missing
  kp <- structure(list(budget = b), class = "taxaexpect_kernel_priors")

  capped <- TaxaExpect:::.resolve_group_prices(kp, 100, 1L, TRUE, "pooled_qualifying")
  expect_equal(unname(capped$basis["normal"]), "own_group")
  expect_equal(unname(capped$basis["inverted"]), "own_group_capped")
  expect_equal(unname(capped$price["inverted"]), 0.02 / 3)   # mass/f1
  expect_equal(unname(capped$price["normal"]), 0.02 / 25)    # untouched

  uncapped <- TaxaExpect:::.resolve_group_prices(kp, 100, 1L, FALSE, "pooled_qualifying")
  expect_equal(unname(uncapped$price["inverted"]), 0.02 / (9 / 14))
  expect_gt(uncapped$price["inverted"], uncapped$price["inverted"] * 0 +
              b$missing_mass[2] / b$f1[2])  # genuinely above the singleton mean
})

test_that("the pooled-qualifying fallback combines group-wise, not by re-pooling", {
  b <- data.frame(
    sampling_group = c("big", "small", "thin"),
    n_taxa = c(50L, 20L, 2L), n_eff = c(900, 100, 5),
    f1 = c(30L, 5L, 2L), f2 = c(10L, 2L, 0L),
    missing_mass = c(0.01, 0.05, 0.4),
    chao_missing = c(45, 6.25, 1),
    stringsAsFactors = FALSE)
  b$theta_present <- b$missing_mass / b$chao_missing
  kp <- structure(list(budget = b), class = "taxaexpect_kernel_priors")
  r <- TaxaExpect:::.resolve_group_prices(kp, 100, 1L, TRUE, "pooled_qualifying")
  # "thin" fails min_group_n_eff and must not contribute to the fallback
  expect_equal(unname(r$basis["thin"]), "pooled_qualifying")
  expect_equal(r$n_qualifying, 2L)
  n_q <- 900 + 100
  expect_equal(r$fallback_price,
               ((900 / n_q) * 0.01 + (100 / n_q) * 0.05) / (45 + 6.25))
  # and the borrowed price is nowhere near the thin group's own absurd one
  expect_lt(r$fallback_price, b$theta_present[b$sampling_group == "thin"] / 100)
})

test_that("a fit where no group clears the guards refuses to price anything", {
  b <- data.frame(
    sampling_group = c("a", "b"), n_taxa = c(2L, 2L), n_eff = c(5, 9),
    f1 = c(1L, 2L), f2 = c(0L, 0L), missing_mass = c(0.3, 0.4),
    chao_missing = c(0, 1), stringsAsFactors = FALSE)
  b$theta_present <- ifelse(b$chao_missing > 0, b$missing_mass / b$chao_missing,
                            NA_real_)
  kp <- structure(
    list(budget = b, theta_present = NA_real_, f1 = NA_integer_,
         f2 = NA_integer_, missing_mass = NA_real_,
         params = list(n_sampling_groups = 2L,
                       sampling_group_col = "sampling_group")),
    class = "taxaexpect_kernel_priors")
  ev <- data.frame(taxon_name = "X y", weight = 0.1, source = "s",
                   sampling_group = "a", stringsAsFactors = FALSE)
  expect_error(
    apply_undetected_evidence(.make_priors(), kp, ev, grid_id = "Grid_A",
                              main_habitat = "Lentic", pricing = "curve"),
    "not one of this fit's 2 sampling groups clears the pricing guards")
})

test_that("the per-group budget table is printed with the price adopted for each", {
  kp <- .make_grouped_kernel_fit()
  fx <- .grouped_priors_and_evidence(kp)
  msgs <- capture_messages(apply_undetected_evidence(
    fx$priors, kp, fx$evidence, grid_id = "budget", main_habitat = "Marine",
    pricing = "curve", sampling_group = "fishes"))
  expect_true(any(grepl("PER-GROUP curve pricing", msgs)))
  expect_true(any(grepl("price_used", msgs)))
  expect_true(any(grepl("basis", msgs)))
})

test_that("blend mode gains no group columns", {
  out <- apply_undetected_evidence(.make_priors(), .make_mock_model_obj(),
                                   .make_evidence(), grid_id = "Grid_A",
                                   main_habitat = "Lentic")
  expect_false("sampling_group" %in% names(out))
  expect_false("pricing_basis" %in% names(out))
})
