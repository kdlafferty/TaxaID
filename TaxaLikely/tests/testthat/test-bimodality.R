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
  #
  # 2026-09-14 ACCEPTANCE TEST (b): this fixture is ALSO discrete at the
  # spike (n_spike observations tied at exactly 100), so it is the real test
  # of whether the 2026-09-14 comb-awareness fix throws the baby out. It
  # does not: .estimate_score_quantum() correctly returns NA for this data
  # (the spike is far too small a share of the sample's total distinct-value
  # count once the hundreds of essentially-unique continuum values are
  # counted too -- see that function's own docs), so no smoothing is ever
  # applied here and this fixture is evaluated exactly as before the fix.
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

  # 2026-09-14: this genuinely bimodal case estimates no quantum at all
  # (confirms the "throws the baby out" risk above didn't materialize).
  expect_true(is.na(res$quantum))
})

# =============================================================================
# .estimate_score_quantum() -- 2026-09-14
# =============================================================================

test_that(".estimate_score_quantum: recovers the real 0.6-spaced quantum from a realistic comb", {
  # Quantized-Gaussian fixture: draw a continuous "true identity" and round
  # to the nearest 0.6-quantum grid point -- exactly what a discretely
  # scored fixed-length amplicon does in practice (each additional mismatch
  # costs a fixed slice of identity). No second population; a single,
  # realistic decaying frequency profile falls out automatically from the
  # rounding.
  set.seed(4242)
  raw <- rnorm(2000, mean = 98.8, sd = 1.0)
  x <- pmin(round(raw / 0.6) * 0.6, 100)
  expect_equal(.estimate_score_quantum(x), 0.6, tolerance = 1e-8)
})

test_that(".estimate_score_quantum: recovers the real quantum from the actual 2026-09-14 PtConception spacing", {
  # Directly mirrors the real run's own top values (98.8/99.4/98.2, each
  # 0.6 apart) at roughly their real relative shares, plus enough smaller
  # teeth to be a realistic comb, not just three points.
  teeth <- seq(100, 100 - 0.6 * 12, by = -0.6)
  weights <- c(0.05, 0.144, 0.382, 0.138, 0.08, 0.05, 0.03, 0.02, 0.01, 0.005, 0.005, 0.005, 0.005)
  weights <- weights / sum(weights)
  n <- 6596L
  counts <- round(weights * n)
  x <- rep(teeth, times = counts)
  expect_equal(.estimate_score_quantum(x), 0.6, tolerance = 1e-8)
})

test_that(".estimate_score_quantum: returns NA for genuinely continuous data (no meaningful repetition)", {
  set.seed(55)
  x <- rnorm(500, mean = 97, sd = 1.5)
  expect_true(is.na(.estimate_score_quantum(x)))
})

test_that(".estimate_score_quantum: returns NA for a real spike sitting on an otherwise-continuous population", {
  # The genuinely-bimodal Nanopore shape: this must NOT be read as a comb,
  # or the spike itself would get smoothed away and the real second mode
  # could be lost (see the acceptance-test note on the fixture above).
  set.seed(2026)
  n_total <- 1000L
  n_spike <- round(0.203 * n_total)
  x <- c(rep(100, n_spike), rnorm(n_total - n_spike, mean = 97, sd = 2.2))
  expect_true(is.na(.estimate_score_quantum(x)))
})

test_that(".estimate_score_quantum: returns NA below min_n, below min_unique, or with too few positive gaps", {
  expect_true(is.na(.estimate_score_quantum(rep(98.8, 5))))
  expect_true(is.na(.estimate_score_quantum(c(rep(98.8, 30), rep(99.4, 30)))))
  expect_true(is.na(.estimate_score_quantum(numeric(0))))
  expect_true(is.na(.estimate_score_quantum(c(NA_real_, NA_real_, Inf, -Inf))))
})

test_that(".estimate_score_quantum: never errors on pathological input", {
  expect_no_error(.estimate_score_quantum(numeric(0)))
  expect_no_error(.estimate_score_quantum(c(1, NA, Inf, -Inf, NaN, 2, 3)))
  expect_no_error(.estimate_score_quantum(rep(5, 100)))
})

# =============================================================================
# .smooth_comb() -- 2026-09-14
# =============================================================================

test_that(".smooth_comb: returns x unchanged when quantum is NA/non-finite/non-positive", {
  x <- c(1, 2, 2, 3, 3, 3)
  expect_identical(.smooth_comb(x, NA_real_), x)
  expect_identical(.smooth_comb(x, NaN), x)
  expect_identical(.smooth_comb(x, Inf), x)
  expect_identical(.smooth_comb(x, 0), x)
  expect_identical(.smooth_comb(x, -0.5), x)
})

test_that(".smooth_comb: spreads a tied group evenly inside its own quantum-wide cell, preserving order/length/mean", {
  x <- c(5, 98.8, 98.8, 98.8, 98.8, 98.8, 10)
  out <- .smooth_comb(x, 0.6)

  expect_length(out, length(x))
  # Untied values pass through unchanged.
  expect_equal(out[c(1, 7)], x[c(1, 7)])
  # The tied group is no longer a single repeated value...
  tied_out <- out[2:6]
  expect_equal(length(unique(tied_out)), 5L)
  # ...but stays centred on the original value and strictly inside its cell.
  expect_equal(mean(tied_out), 98.8, tolerance = 1e-8)
  expect_true(all(tied_out > 98.8 - 0.3 & tied_out < 98.8 + 0.3))
})

test_that(".smooth_comb: deterministic across repeated calls (no randomness)", {
  x <- c(rep(98.8, 20), rep(99.4, 15), rep(98.2, 10), 97.0)
  out_a <- .smooth_comb(x, 0.6)
  out_b <- .smooth_comb(x, 0.6)
  expect_identical(out_a, out_b)
})

test_that(".smooth_comb: adjacent teeth become contiguous (no zero-density gap left between them)", {
  x <- c(rep(98.2, 50), rep(98.8, 50))
  out <- sort(.smooth_comb(x, 0.6))
  gaps <- diff(out)
  # No gap in the smoothed data should exceed the within-cell spacing by
  # much -- in particular there must be no single large jump straddling
  # the old boundary between the two teeth.
  expect_lt(max(gaps), 0.6 / 49 * 3)
})

test_that(".smooth_comb: preserves non-finite values in their original positions", {
  x <- c(1, NA, 2, 2, Inf, 2)
  out <- .smooth_comb(x, 0.5)
  expect_true(is.na(out[2]))
  expect_true(is.infinite(out[5]))
  expect_equal(out[1], 1)
})

# =============================================================================
# .bimodality_check() -- 2026-09-14 comb-awareness: acceptance test (d)
# =============================================================================

test_that(".bimodality_check: an explicit comb with a realistic decaying frequency profile and no second population does NOT flag", {
  # Regression guard for exactly the false positive found on the real
  # 2026-09-14 PtConception 12S production run: scores fall ONLY at
  # integer-mismatch positions (100, 99.4, 98.8, 98.2, ... 0.6 apart), with
  # a realistic decaying frequency profile (a quantized Gaussian -- the
  # natural shape a continuous identity distribution takes once rounded to
  # discrete mismatch counts) and no second population at all.
  set.seed(4242)
  raw <- rnorm(2000, mean = 98.8, sd = 1.0)
  x_comb <- pmin(round(raw / 0.6) * 0.6, 100)

  # Confirms this really is a comb (few distinct values, no exact
  # continuum) before trusting the non-flag result below.
  expect_lt(length(unique(x_comb)), 20L)

  res <- .bimodality_check(x_comb)
  expect_false(res$flag)
  expect_equal(res$quantum, 0.6, tolerance = 1e-8)
})

test_that(".bimodality_check: the actual real-run false-positive shape (4%/96% split, quantized 0.6 apart) does NOT flag", {
  # Directly mirrors the real calibrate_query_noise() warning this fix
  # exists for: "H1 scores look bimodal: 4% near 95.4 (sd 3.0) and 96% near
  # 98.8 (sd 0.4), delta BIC 8297" -- reproduced here as a synthetic comb
  # (quantum 0.6, the run's own measured spacing) with a thin low-identity
  # tail, rather than a real second population.
  set.seed(9911)
  n <- 6596L
  n_tail <- round(0.04 * n)
  n_bulk <- n - n_tail
  bulk <- rnorm(n_bulk, mean = 98.8, sd = 0.5)
  tail_part <- rnorm(n_tail, mean = 95.4, sd = 3.0)
  x <- pmin(round(c(bulk, tail_part) / 0.6) * 0.6, 100)

  res <- .bimodality_check(x)
  expect_false(res$flag)
})

test_that(".bimodality_check: min_minority_weight alone rejects a thin-tail comb even if separation/valley would otherwise pass", {
  # A comb where the two-component fit could plausibly find a real interior
  # dip and a separation of several quanta, but the "minority" side holds
  # only a token few percent of the mass -- must not be called bimodal.
  set.seed(321)
  n <- 2000L
  n_minor <- round(0.03 * n)
  x <- pmin(round(c(
    rnorm(n - n_minor, mean = 98.8, sd = 0.4),
    rnorm(n_minor, mean = 90.0, sd = 0.4)
  ) / 0.6) * 0.6, 100)

  res <- .bimodality_check(x)
  if (isTRUE(res$delta_bic > 10) && isTRUE(abs(diff(res$means)) > 1.8)) {
    # Only a meaningful test of the weight guard if the other three
    # conditions would otherwise have passed.
    expect_lt(min(res$weights), 0.15)
  }
  expect_false(res$flag)
})

test_that(".bimodality_check: quanta_separation_multiplier rejects a same-quantum-neighbor false split (train_likelihood_model's own h1_bimodality shape)", {
  # Mirrors the real Stats$h1_bimodality false positive from the same
  # 2026-09-14 run: weights 0.323/0.677, means 98.3/100 (separation 1.7,
  # under 3 quanta at a 0.6 quantum) -- the reference-matches-itself spike
  # at exactly 100, not a real second population.
  set.seed(707)
  n <- 1500L
  n_spike <- round(0.323 * n)
  bulk <- rnorm(n - n_spike, mean = 98.3, sd = 0.6)
  x <- c(rep(100, n_spike), pmin(round(bulk / 0.6) * 0.6, 100))

  res <- .bimodality_check(x)
  expect_false(res$flag)
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

test_that("calibrate_query_noise: does NOT warn about bimodality on a comb-shaped (discrete percent-identity) score vector -- 2026-09-14 regression", {
  # End-to-end reproduction, through the real calibrate_query_noise() call
  # path (not just .bimodality_check() directly), of the false positive
  # found on the real 2026-09-14 PtConception 12S run: "H1 scores look
  # bimodal: 4% near 95.4 (sd 3.0) and 96% near 98.8 (sd 0.4), delta BIC
  # 8297" -- reproduced as a synthetic comb (quantum 0.6, this run's own
  # measured spacing) with a thin low-identity tail, no real second
  # population.
  set.seed(9911)
  n <- 200L
  n_tail <- round(0.04 * n)
  n_bulk <- n - n_tail
  bulk <- rnorm(n_bulk, mean = 98.8, sd = 0.5)
  tail_part <- rnorm(n_tail, mean = 95.4, sd = 3.0)
  scores <- pmin(round(c(bulk, tail_part) / 0.6) * 0.6, 100)
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

  expect_length(grep("bimodal", warnings_seen, value = TRUE), 0L)
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
