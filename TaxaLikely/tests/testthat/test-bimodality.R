# Tests for the 2026-09-13 bimodality diagnostic (R/bimodality.R):
# .fit_two_component_normal(), .mixture_has_valley(), .bimodality_check(),
# and their wiring into calibrate_query_noise() (warns) and
# train_likelihood_model() (records only, in Stats$h1_bimodality).
#
# Fully offline and deterministic -- every simulated fixture is seeded.

# ---- Shared fixture builder for the calibrate_query_noise() wiring tests --

.make_bimodality_calib_fixture <- function(scores, mu_score = 4.5) {
  model_params <- structure(
    list(
      H1_Lookup = data.frame(
        lookup_key = "Genusone speciesa", rank = "species",
        mu_score = mu_score, mu_gap = 2.0, sigma_score = 2.0,
        stringsAsFactors = FALSE
      ),
      H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
      H1_Sigma = matrix(c(2.0, 0.2, 0.2, 1.0),
        nrow = 2L,
        dimnames = list(
          c("score_logit", "gap_logit"),
          c("score_logit", "gap_logit")
        )
      ),
      H2 = list(delta = 3.0, sigma = diag(2)),
      H3 = list(delta = 5.0, sigma = diag(2)),
      Stats = list(n_species = 1L, n_singletons = 0L),
      Score_Transform = "logit"
    ),
    class = "taxa_model_params"
  )
  match_df <- data.frame(
    observation_id = paste0("Q", seq_along(scores)),
    genus = "Genusone",
    score_original = scores,
    stringsAsFactors = FALSE
  )
  priors <- data.frame(
    taxon_name = "Genusone speciesa", taxon_name_rank = "species",
    theta_mean = 0.5, stringsAsFactors = FALSE
  )
  list(params = model_params, match_df = match_df, priors = priors)
}

# =============================================================================
# .fit_two_component_normal()
# =============================================================================

test_that(".fit_two_component_normal: returns NULL for too few points or no variance", {
  expect_null(.fit_two_component_normal(c(1, 2, 3)))
  expect_null(.fit_two_component_normal(rep(97, 50)))
  expect_null(.fit_two_component_normal(numeric(0)))
})

test_that(".fit_two_component_normal: sd floor prevents a repeated-value component from blowing up", {
  # Many rows at exactly 100 (the real Nanopore-spike risk) alongside a
  # spread-out component -- a component that lands on the exact-100 subset
  # has true variance exactly 0, which would otherwise send its likelihood
  # contribution to Inf.
  set.seed(101)
  x <- c(rep(100, 300), rnorm(300, mean = 90, sd = 3))
  fit <- .fit_two_component_normal(x)

  expect_false(is.null(fit))
  expect_true(all(is.finite(fit$sds)))
  expect_true(all(fit$sds > 0))
  expect_true(is.finite(fit$loglik))
  expect_true(all(is.finite(fit$weights)))
  expect_equal(sum(fit$weights), 1, tolerance = 1e-8)
})

test_that(".fit_two_component_normal: deterministic across repeated calls (no randomness)", {
  set.seed(202)
  x <- c(rnorm(150, 97, 1), rnorm(150, 90, 1))
  fit_a <- .fit_two_component_normal(x)
  fit_b <- .fit_two_component_normal(x)
  expect_equal(fit_a, fit_b)
})

# =============================================================================
# .bimodality_check() -- the six required scenarios
# =============================================================================

test_that(".bimodality_check: a genuinely unimodal, tight sample does NOT flag", {
  set.seed(11)
  x_uni <- pmin(pmax(rnorm(200, mean = 97, sd = 0.5), 0), 100)
  res <- .bimodality_check(x_uni)

  expect_identical(res$n, 200L)
  expect_false(res$flag)
  expect_true(is.character(res$explanation))
  expect_false(is.na(res$explanation))
})

test_that(".bimodality_check: a ceiling-skewed but unimodal sample does NOT flag (the false-positive case)", {
  # This is the exact shape (heavy mass near the ceiling, one mode, a long
  # left tail) that ruled out a skewness/kurtosis-based bimodality
  # coefficient for this diagnostic in the first place. A naive
  # delta-BIC-plus-separation test alone DOES flag this shape (confirmed
  # directly during development -- a 2-component fit routinely beats 1
  # component on skewed data, since one narrow "tail" component and one
  # broad "bulk" component fit the skew better than a single Gaussian, with
  # no real dip between them) -- this test exists specifically to hold the
  # implementation to not making that mistake.
  set.seed(12)
  x_skew <- pmin(100 - rexp(400, rate = 1), 100)
  res <- .bimodality_check(x_skew)

  expect_false(res$flag)
})

test_that(".bimodality_check: a two-platform sample built to the real measured shape DOES flag, with weights/means close to the truth", {
  # 20.3% exactly at 100 (a real platform's ceiling spike), the rest centred
  # near 97 with enough spread that the whole sample's 10th percentile lands
  # close to the real measured value (~94.1) -- see this session's own
  # calibration of the generating sd against that target.
  set.seed(2026)
  n_total <- 1000L
  n_spike <- round(0.203 * n_total)
  n_rest <- n_total - n_spike
  true_weight_spike <- n_spike / n_total
  true_mean_rest <- 97
  x <- c(rep(100, n_spike), rnorm(n_rest, mean = true_mean_rest, sd = 2.2))

  # Confirms the fixture itself matches the motivating real-data description
  # before trusting the flag result below.
  expect_lt(abs(stats::quantile(x, 0.10, names = FALSE) - 94.1), 1.0)

  res <- .bimodality_check(x)

  expect_true(res$flag)
  expect_gt(res$delta_bic, 10)
  expect_true(is.na(res$explanation))

  # Component order is ascending by mean: [rest ~97, spike ~100].
  expect_equal(res$means, c(true_mean_rest, 100), tolerance = 0.5)
  expect_equal(res$weights, c(1 - true_weight_spike, true_weight_spike), tolerance = 0.05)
  expect_lt(abs(diff(res$means)), 5) # sanity: not a wild, implausible split
})

test_that(".bimodality_check: min_n and the no-variance case return flag = FALSE without error", {
  expect_no_error(res_n <- .bimodality_check(stats::rnorm(10)))
  expect_false(res_n$flag)
  expect_identical(res_n$n, 10L)
  expect_true(grepl("min_n|need >=", res_n$explanation) || grepl("50", res_n$explanation))

  expect_no_error(res_var <- .bimodality_check(rep(97.0, 200)))
  expect_false(res_var$flag)
  expect_true(grepl("variance", res_var$explanation))

  # min_n is itself adjustable.
  res_custom <- .bimodality_check(stats::rnorm(10), min_n = 5L)
  expect_true(is.na(res_custom$explanation) || !grepl("need >= 50", res_custom$explanation))
})

test_that(".bimodality_check: never errors on pathological input", {
  expect_no_error(.bimodality_check(numeric(0)))
  expect_no_error(.bimodality_check(c(NA_real_, NA_real_)))
  expect_no_error(.bimodality_check(c(1, NA, Inf, -Inf, NaN, 2, 3)))
})

# =============================================================================
# Wiring into calibrate_query_noise()
# =============================================================================

test_that("calibrate_query_noise: emits exactly one warning naming the fitted structure on bimodal input", {
  set.seed(2026)
  n_total <- 1000L
  n_spike <- round(0.203 * n_total)
  n_rest <- n_total - n_spike
  scores <- c(rep(100, n_spike), rnorm(n_rest, mean = 97, sd = 2.2))
  fx <- .make_bimodality_calib_fixture(scores)

  warnings_seen <- character(0)
  withCallingHandlers(
    out <- calibrate_query_noise(fx$params, fx$match_df, fx$priors,
      offset_form = "constant", min_confident_obs = 30L, verbose = FALSE
    ),
    warning = function(w) {
      warnings_seen[[length(warnings_seen) + 1L]] <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )

  bimodal_warnings <- grep("bimodal", warnings_seen, value = TRUE)
  expect_length(bimodal_warnings, 1L)
  expect_match(bimodal_warnings, "H1 scores look bimodal")
  expect_match(bimodal_warnings, "delta BIC")
  expect_match(bimodal_warnings, "calibrate them separately")
  # Plain numbers for both components' weight/mean/sd are present.
  expect_match(bimodal_warnings, "[0-9]+% near [0-9.]+ \\(sd [0-9.]+\\)")

  # The diagnostic is informational only -- calibration still completes and
  # produces an ordinary Query_Calibration slot.
  expect_false(is.null(out$Query_Calibration))
})

test_that("calibrate_query_noise: does not warn about bimodality on unimodal input, and fitted values are numerically identical to the pre-diagnostic formula", {
  set.seed(33)
  scores <- pmin(pmax(rnorm(200, mean = 95, sd = 1), 0), 100)
  fx <- .make_bimodality_calib_fixture(scores, mu_score = 4.5)

  warnings_seen <- character(0)
  withCallingHandlers(
    out <- calibrate_query_noise(fx$params, fx$match_df, fx$priors,
      offset_form = "constant", min_confident_obs = 30L, verbose = FALSE
    ),
    warning = function(w) {
      warnings_seen[[length(warnings_seen) + 1L]] <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )
  expect_length(grep("bimodal", warnings_seen, value = TRUE), 0L)

  # Hand-derive the expected constant offset exactly as calibrate_query_noise()
  # itself does (median residual = observed_logit - species mu_score), using
  # the same score_transform ("logit") -- this is the pre-existing formula,
  # completely untouched by the bimodality diagnostic; matching it exactly
  # confirms the new diagnostic changed no fitted value.
  observed_logit <- log((scores / 100) / (1 - scores / 100))
  expected_offset <- stats::median(observed_logit - 4.5)
  expect_equal(out$Query_Calibration$offset_logit, expected_offset, tolerance = 1e-8)
  expect_equal(out$Query_Calibration$sigma_ratio, 1)
  expect_equal(out$Query_Calibration$slope, 1)
})

# =============================================================================
# Wiring into train_likelihood_model() -- records only, never warns
# =============================================================================

.make_bimodal_training_raw_df <- function(n_per_species = 3L) {
  # A minimal build_sequence_matrix()-shaped pairwise data frame: several
  # species, each with a few within-species (H1) pairs, one species'
  # p_match values drawn from a real bimodal (two-platform) shape.
  set.seed(77)
  species <- paste0("sp", 1:6)
  rows <- list()
  bimodal_species <- "sp1"
  idx <- 1L
  for (sp in species) {
    n_seq <- 12L # enough sequences per species for several H1 pairs
    ids <- paste0(sp, "_", seq_len(n_seq))
    pairs <- utils::combn(ids, 2L, simplify = FALSE)
    for (pr in pairs) {
      if (sp == bimodal_species) {
        p_match <- if (stats::runif(1) < 0.203) 100 else stats::rnorm(1, 97, 2.2)
      } else {
        p_match <- stats::rnorm(1, 97, 0.5)
      }
      p_match <- min(max(p_match, 0), 100)
      rows[[idx]] <- data.frame(
        id_x = pr[1], id_y = pr[2],
        family.x = "Famone", family.y = "Famone",
        genus.x = "Genusone", genus.y = "Genusone",
        species.x = sp, species.y = sp,
        p_match = p_match,
        stringsAsFactors = FALSE
      )
      idx <- idx + 1L
    }
    # Also add a few cross-species (foreign) pairs so STEP 3 has data.
    other_sp <- setdiff(species, sp)[1]
    other_ids <- paste0(other_sp, "_", seq_len(n_seq))
    for (j in seq_len(5L)) {
      rows[[idx]] <- data.frame(
        id_x = ids[j], id_y = other_ids[j],
        family.x = "Famone", family.y = "Famone",
        genus.x = "Genusone", genus.y = "Genusone",
        species.x = sp, species.y = other_sp,
        p_match = stats::runif(1, 60, 85),
        stringsAsFactors = FALSE
      )
      idx <- idx + 1L
    }
  }
  do.call(rbind, rows)
}

test_that("train_likelihood_model(): records Stats$h1_bimodality and never warns about it", {
  skip_if_not_installed("TaxaTools")
  raw_df <- .make_bimodal_training_raw_df()

  warnings_seen <- character(0)
  withCallingHandlers(
    model <- train_likelihood_model(raw_df,
      rank_system = c("family", "genus", "species"),
      anchor_perfect = FALSE
    ),
    warning = function(w) {
      warnings_seen[[length(warnings_seen) + 1L]] <<- conditionMessage(w)
      invokeRestart("muffleWarning")
    }
  )

  expect_true(!is.null(model$Stats$h1_bimodality))
  expect_true(is.list(model$Stats$h1_bimodality))
  expect_true("flag" %in% names(model$Stats$h1_bimodality))
  # train_likelihood_model() records only -- it must never itself emit a
  # bimodality warning, regardless of what the check finds (that belongs to
  # calibrate_query_noise()).
  expect_length(grep("bimodal", warnings_seen, value = TRUE, ignore.case = TRUE), 0L)
})
