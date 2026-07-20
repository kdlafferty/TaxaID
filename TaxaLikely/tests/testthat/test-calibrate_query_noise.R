# Minimal model_params/match_df/priors for testing calibrate_query_noise()
# across score_transform values. calibrate_query_noise()'s own confident-
# observation logic is otherwise untested in this package (Session 155-158
# note); this file covers the Session 158 score_transform support.
.make_calib_model_params <- function(score_transform = "logit") {
  sigma <- matrix(c(2.0, 0.2, 0.2, 1.0), nrow = 2L,
                  dimnames = list(c("score_logit", "gap_logit"),
                                  c("score_logit", "gap_logit")))
  structure(
    list(
      H1_Lookup    = data.frame(lookup_key = "Genusone speciesa", rank = "species",
                                mu_score = 4.5, mu_gap = 2.0, sigma_score = 2.0,
                                stringsAsFactors = FALSE),
      H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
      H1_Sigma     = sigma,
      H2           = list(delta = 3.0, sigma = diag(2)),
      H3           = list(delta = 5.0, sigma = diag(2)),
      Stats        = list(n_species = 1L, n_singletons = 0L),
      Score_Transform = score_transform
    ),
    class = "taxa_model_params"
  )
}

# 40 confident observations, all "Genusone speciesa" at 95% identity, so the
# genus qualifies as having exactly one locally-plausible species.
.make_calib_match_df <- function() {
  data.frame(
    observation_id = paste0("Q", 1:40),
    genus          = "Genusone",
    score_original = 95.0,
    stringsAsFactors = FALSE
  )
}

.make_calib_priors <- function() {
  data.frame(
    taxon_name      = "Genusone speciesa",
    taxon_name_rank = "species",
    theta_mean      = 0.5,
    stringsAsFactors = FALSE
  )
}

test_that("calibrate_query_noise: works end to end for score_transform = 'logit'", {
  params <- .make_calib_model_params("logit")
  out <- calibrate_query_noise(params, .make_calib_match_df(), .make_calib_priors(),
                                offset_form = "constant",
                                min_confident_obs = 30L, verbose = FALSE)
  expect_true(!is.null(out$Query_Calibration))
  expect_equal(out$Query_Calibration$n_confident_obs, 40L)
})

test_that("calibrate_query_noise: works end to end for score_transform = 'sqrt_mismatch' (Session 158)", {
  params <- .make_calib_model_params("sqrt_mismatch")
  out <- calibrate_query_noise(params, .make_calib_match_df(), .make_calib_priors(),
                                offset_form = "constant",
                                min_confident_obs = 30L, verbose = FALSE)
  expect_true(!is.null(out$Query_Calibration))
  expect_equal(out$Query_Calibration$n_confident_obs, 40L)

  # The offset must be estimated on the sqrt_mismatch scale, not logit --
  # confirm directly: observed score is 95% for all confident observations,
  # -sqrt(1-0.95) = -0.2236, a small, sqrt_mismatch-scale-appropriate number,
  # not anywhere near a plausible logit-scale offset (typically several units).
  observed_sqrt_mismatch <- -sqrt(1 - 0.95)
  expected <- 4.5   # species mu_score
  expect_equal(out$Query_Calibration$offset_logit, observed_sqrt_mismatch - expected)
})

test_that("calibrate_query_noise: logit and sqrt_mismatch produce different-scale offsets for the same underlying data", {
  match_df <- .make_calib_match_df()
  priors   <- .make_calib_priors()

  out_logit <- calibrate_query_noise(.make_calib_model_params("logit"), match_df, priors,
                                      offset_form = "constant",
                                      min_confident_obs = 30L, verbose = FALSE)
  out_sqrt  <- calibrate_query_noise(.make_calib_model_params("sqrt_mismatch"), match_df, priors,
                                      offset_form = "constant",
                                      min_confident_obs = 30L, verbose = FALSE)

  expect_false(isTRUE(all.equal(out_logit$Query_Calibration$offset_logit,
                                 out_sqrt$Query_Calibration$offset_logit)))
})

# ---- offset_form = "linear" (level-aware recalibration) --------------------
# Multi-species fixture: K species in K genera, each genus with exactly one
# locally-plausible species, trained means spanning a range so a slope is
# estimable. `score_fn(mu_i)` sets each species' confident-observation score
# (percent scale) as a function of that species' trained mean, letting a test
# dial in the observed-vs-trained relationship (constant gap -> slope 1;
# constant observed -> slope 0).
.make_multi_species_fixture <- function(n_species = 10L, n_obs_each = 4L,
                                        mu_range = c(3.0, 5.0), score_fn) {
  mu <- seq(mu_range[1L], mu_range[2L], length.out = n_species)
  keys <- sprintf("Genus%02d species%02d", seq_len(n_species), seq_len(n_species))
  h1 <- data.frame(lookup_key = keys, rank = "species",
                   mu_score = mu, mu_gap = 2.0, sigma_score = 2.0,
                   stringsAsFactors = FALSE)
  params <- structure(
    list(H1_Lookup = h1,
         H1_Global_Mu = c(score_logit = mean(mu), gap_logit = 1.5),
         H1_Sigma = matrix(c(2.0, 0.2, 0.2, 1.0), 2L,
                           dimnames = list(c("score_logit","gap_logit"),
                                           c("score_logit","gap_logit"))),
         H2 = list(delta = 3.0, sigma = diag(2)),
         H3 = list(delta = 5.0, sigma = diag(2)),
         Stats = list(n_species = n_species),
         Score_Transform = "logit"),
    class = "taxa_model_params")

  rows <- do.call(rbind, lapply(seq_len(n_species), function(i) {
    data.frame(observation_id = sprintf("Q%02d_%d", i, seq_len(n_obs_each)),
               genus = sprintf("Genus%02d", i),
               score_original = score_fn(mu[i]),
               stringsAsFactors = FALSE)
  }))
  priors <- data.frame(taxon_name = keys, taxon_name_rank = "species",
                       theta_mean = 0.5, stringsAsFactors = FALSE)
  list(params = params, match_df = rows, priors = priors, mu = mu)
}

test_that("calibrate_query_noise: offset_form default is 'linear'", {
  # With enough confident species spanning a range of trained means, the default
  # (no offset_form supplied) must fit the affine form.
  fx <- .make_multi_species_fixture(
    score_fn = function(mu) rep(100 * stats::plogis(mu - 0.8), 4L))
  out <- calibrate_query_noise(fx$params, fx$match_df, fx$priors,
                                min_confident_obs = 30L, verbose = FALSE)
  expect_equal(out$Query_Calibration$offset_form, "linear")
})

test_that("calibrate_query_noise: default 'linear' falls back to 'constant' on thin reference data", {
  # A single-species reference set cannot support the affine fit; the default
  # must degrade gracefully to the additive offset (with a warning).
  expect_warning(
    out <- calibrate_query_noise(.make_calib_model_params("logit"), .make_calib_match_df(),
                                  .make_calib_priors(), min_confident_obs = 30L, verbose = FALSE),
    "Falling back to constant"
  )
  expect_equal(out$Query_Calibration$offset_form, "constant")
  expect_equal(out$Query_Calibration$slope, 1)
})

test_that("calibrate_query_noise: offset_form='linear' with a constant gap recovers the constant offset (strict generalization)", {
  # observed_logit = trained_mean + c exactly, for every species -> the linear
  # fit must give slope ~ 1, intercept ~ c, and remap H1 means identically to
  # the constant form. c chosen so scores stay well inside (0,100).
  cc <- -0.8
  fx <- .make_multi_species_fixture(
    score_fn = function(mu) rep(100 * stats::plogis(mu + cc), 4L))

  out_lin <- calibrate_query_noise(fx$params, fx$match_df, fx$priors,
                                    offset_form = "linear",
                                    min_confident_obs = 30L, verbose = FALSE)
  out_con <- calibrate_query_noise(fx$params, fx$match_df, fx$priors,
                                    offset_form = "constant",
                                    min_confident_obs = 30L, verbose = FALSE)

  expect_equal(out_lin$Query_Calibration$offset_form, "linear")
  expect_equal(out_lin$Query_Calibration$slope, 1, tolerance = 1e-3)
  expect_equal(out_lin$Query_Calibration$intercept, cc, tolerance = 1e-3)
  # Remapped per-species means identical to the constant form (the definition
  # of "strict generalization": constant is the slope=1 special case).
  expect_equal(out_lin$H1_Lookup$mu_score, out_con$H1_Lookup$mu_score, tolerance = 1e-3)
})

test_that("calibrate_query_noise: offset_form='linear' collapses toward a pooled mean when trained means don't transfer (real-12S regime)", {
  # observed score is (nearly) constant across species regardless of trained
  # mean -> slope ~ 0, and all remapped H1 means collapse toward one value.
  set.seed(42)
  fx <- .make_multi_species_fixture(
    n_obs_each = 6L,
    score_fn = function(mu) 90 + stats::runif(6L, -1, 1))  # independent of mu

  out <- calibrate_query_noise(fx$params, fx$match_df, fx$priors,
                                offset_form = "linear",
                                min_confident_obs = 30L, verbose = FALSE)
  expect_equal(out$Query_Calibration$offset_form, "linear")
  expect_lt(abs(out$Query_Calibration$slope), 0.1)          # ~0 slope
  # Remapped means far tighter than the original spread (collapsed).
  expect_lt(stats::sd(out$H1_Lookup$mu_score), 0.2 * stats::sd(fx$mu))
})

test_that("calibrate_query_noise: offset_form='linear' falls back to constant (with warning) when too few confident species", {
  # 3 species only (< default min_calib_species = 8) but >= min_confident_obs.
  fx <- .make_multi_species_fixture(
    n_species = 3L, n_obs_each = 12L,
    score_fn = function(mu) rep(100 * stats::plogis(mu - 0.8), 12L))

  expect_warning(
    out <- calibrate_query_noise(fx$params, fx$match_df, fx$priors,
                                  offset_form = "linear",
                                  min_confident_obs = 30L, verbose = FALSE),
    "Falling back to constant"
  )
  expect_equal(out$Query_Calibration$offset_form, "constant")
  expect_equal(out$Query_Calibration$slope, 1)
})

test_that("calibrate_query_noise: model_params without Score_Transform (pre-Session-158) defaults to logit", {
  params <- .make_calib_model_params("logit")
  params$Score_Transform <- NULL
  out <- calibrate_query_noise(params, .make_calib_match_df(), .make_calib_priors(),
                                offset_form = "constant",
                                min_confident_obs = 30L, verbose = FALSE)
  # Should behave identically to an explicit "logit" model.
  ref <- calibrate_query_noise(.make_calib_model_params("logit"), .make_calib_match_df(),
                                .make_calib_priors(), offset_form = "constant",
                                min_confident_obs = 30L, verbose = FALSE)
  expect_equal(out$Query_Calibration$offset_logit, ref$Query_Calibration$offset_logit)
})
