# Absolute-fit flag: best_identity / best_identity_rank / poor_absolute_fit.
# A flag only: no likelihood is touched.
#
# Fixtures below mirror test-evaluate_per_genus_rings.R (ASV_606 shape) and
# test-support-curves.R (.curve_fixture); test files do not share helpers.

.pg_params <- function(h2_lookup = NULL, rings = NULL) {
  nm <- c("score_logit", "gap_logit")
  sig <- matrix(c(2.0, 0.2, 0.2, 1.0), 2L, dimnames = list(nm, nm))
  h2s <- diag(c(1.0, 1.0)); dimnames(h2s) <- list(nm, nm)
  h3s <- diag(c(1.5, 1.0)); dimnames(h3s) <- list(nm, nm)
  p <- list(
    H1_Lookup = data.frame(
      lookup_key = "Hypsoblennius sordidus", rank = "species",
      mu_score = 3.9, mu_gap = 2.0, sigma_score = 2.0, n_obs_species = 5L,
      stringsAsFactors = FALSE
    ),
    H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
    H1_Sigma = sig,
    H2 = list(delta = 3.0, sigma = h2s),
    H3 = list(delta = 5.0, sigma = h3s),
    Stats = list(n_species = 1L, n_singletons = 0L),
    Score_Transform = "logit"
  )
  if (!is.null(h2_lookup)) p$H2_Lookup <- h2_lookup
  if (!is.null(rings)) p$Rings <- rings
  structure(p, class = "taxa_model_params")
}

.pg_lookup <- function() {
  data.frame(
    genus = c("Hypsoblennius", "Parablennius"),
    n_pairs = c(20L, 20L), delta_shrunk = c(2.0, 3.5),
    stringsAsFactors = FALSE
  )
}

# ASV_606 shape
.pg_asv606 <- function() {
  data.frame(
    observation_id = "ASV_606",
    taxon_name = c(
      "Hypsoblennius sordidus", "Parablennius sanguinolentus",
      "Parablennius incognitus", "Parablennius parvicornis",
      "Hypsoblennius hentz", "Hypsoblennius brevipinnis", "Hypsoblennius invemar"
    ),
    score = c(86.08, 86.08, 84.81, 84.81, 86.08, 86.08, 86.08),
    taxon_name_rank = "species",
    family = "Blenniidae",
    genus = c(rep("Hypsoblennius", 1), rep("Parablennius", 3), rep("Hypsoblennius", 3)),
    is_restored = c(FALSE, FALSE, FALSE, FALSE, TRUE, TRUE, TRUE),
    stringsAsFactors = FALSE
  ) |> transform(species = taxon_name)
}

.curve_fixture <- function() {
  mk <- function(sx, sy, gx, gy, fx, fy, p) {
    data.frame(
      id_x = paste0(sx, "_1"), id_y = paste0(sy, "_1"),
      species.x = sx, species.y = sy,
      genus.x = gx, genus.y = gy,
      family.x = fx, family.y = fy,
      p_match = p, stringsAsFactors = FALSE
    )
  }
  rbind(
    # within-species (high)
    mk("Aa sp1", "Aa sp1", "Aa", "Aa", "Fam1", "Fam1", 0.995),
    mk("Aa sp2", "Aa sp2", "Aa", "Aa", "Fam1", "Fam1", 0.990),
    mk("Bb sp1", "Bb sp1", "Bb", "Bb", "Fam1", "Fam1", 0.985),
    mk("Cc sp1", "Cc sp1", "Cc", "Cc", "Fam2", "Fam2", 0.992),
    # congeneric (mid) -- Aa has 2, Bb has 1 (different n, exercises shrinkage)
    mk("Aa sp3", "Aa sp1", "Aa", "Aa", "Fam1", "Fam1", 0.930),
    mk("Aa sp4", "Aa sp2", "Aa", "Aa", "Fam1", "Fam1", 0.910),
    mk("Bb sp2", "Bb sp1", "Bb", "Bb", "Fam1", "Fam1", 0.900),
    # confamilial (lower)
    mk("Aa sp5", "Bb sp1", "Aa", "Bb", "Fam1", "Fam1", 0.750),
    mk("Bb sp3", "Aa sp1", "Bb", "Aa", "Fam1", "Fam1", 0.700),
    # cross-family (lowest)
    mk("Aa sp6", "Cc sp1", "Aa", "Cc", "Fam1", "Fam2", 0.400),
    mk("Cc sp2", "Bb sp1", "Cc", "Bb", "Fam2", "Fam1", 0.350)
  )
}
.rs <- c("family", "genus", "species")


# Hand-built Confusion_Risk_Curves whose per-rank Youden's J is exactly `thr`.
.af_tier <- function(T) {
  g <- seq(0, 100, by = 1)
  list(
    tpr_pooled = data.frame(threshold = g, pooled_rate = ifelse(g <= T, 1, 0)),
    fpr_pooled = data.frame(threshold = g, pooled_rate = ifelse(g <= T - 1, 1, 0))
  )
}
.af_curves <- function(species = 99, genus = 96, family = 96) {
  list(
    species = .af_tier(species), genus = .af_tier(genus),
    family = .af_tier(family), threshold_grid = seq(0, 100, by = 1)
  )
}
.af_params <- function(curves = .af_curves()) {
  p <- .pg_params(.pg_lookup())
  p$Confusion_Risk_Curves <- curves
  p
}

# ASV_606 shape (shared helper lives in test-evaluate_per_genus_rings.R)
.af_unit <- function(scores = c(86.08, 86.08, 84.81, 84.81, 86.08, 86.08, 86.08),
                     id = "ASV_606") {
  d <- .pg_asv606()
  d$score <- scores
  d$observation_id <- id
  d
}

.af_eval <- function(df, p = .af_params(), ...) {
  suppressMessages(evaluate_likelihoods(
    df, p,
    rank_system = c("family", "genus", "species"),
    ratio_threshold = 0, ...
  ))
}

test_that("ASV_606: 86.08% reaches no rank threshold -> poor fit on every row of the unit", {
  skip_if_not_installed("TaxaTools")
  res <- .af_eval(.af_unit())
  lk <- res$likelihoods
  expect_true(all(c("best_identity", "best_identity_rank", "poor_absolute_fit") %in% names(lk)))
  expect_true(nrow(lk) > 1L)
  expect_equal(lk$best_identity, rep(86.08, nrow(lk)), tolerance = 1e-8)
  expect_true(all(is.na(lk$best_identity_rank)))
  expect_true(all(lk$poor_absolute_fit))
  expect_equal(attr(lk, "rank_thresholds_used"),
    c(species = 99, genus = 96, family = 96))
  # the unit's winner is still confident: the flag does not touch likelihoods
  expect_equal(max(lk$score_likelihood), 1)
})

test_that("the flag does not change any likelihood", {
  skip_if_not_installed("TaxaTools")
  a <- .af_eval(.af_unit())$likelihoods
  p0 <- .af_params()
  p0$Confusion_Risk_Curves <- NULL
  b <- suppressMessages(.af_eval(.af_unit(), p0))$likelihoods
  cols <- c("taxon_name", "raw_likelihood", "score_likelihood", "score_likelihood_mean")
  expect_equal(as.data.frame(a)[, cols], as.data.frame(b)[, cols])
})

test_that("a good unit (best 99.4) reaches species", {
  skip_if_not_installed("TaxaTools")
  lk <- .af_eval(.af_unit(c(99.4, 99.4, 97, 97, 99.4, 99.4, 99.4)))$likelihoods
  expect_equal(lk$best_identity, rep(99.4, nrow(lk)), tolerance = 1e-8)
  expect_true(all(lk$best_identity_rank == "species"))
  expect_false(any(lk$poor_absolute_fit))
})

test_that("between thresholds (96.5; genus 96, species 99) reaches genus, not poor", {
  skip_if_not_installed("TaxaTools")
  lk <- .af_eval(.af_unit(c(96.5, 96.5, 90, 90, 96.5, 96.5, 96.5)))$likelihoods
  expect_true(all(lk$best_identity_rank == "genus"))
  expect_false(any(lk$poor_absolute_fit))
})

test_that("a score exactly at a threshold reaches it (>=)", {
  skip_if_not_installed("TaxaTools")
  lk <- .af_eval(.af_unit(c(99, 99, 90, 90, 99, 99, 99)))$likelihoods
  expect_true(all(lk$best_identity_rank == "species"))
})

test_that("a unit with only ring rows has all three NA", {
  skip_if_not_installed("TaxaTools")
  # ratio_threshold above 1 drops every specific_candidate row; the rings stay.
  res <- suppressMessages(evaluate_likelihoods(
    .af_unit(), .af_params(),
    rank_system = c("family", "genus", "species"), ratio_threshold = 2
  ))
  lk <- res$likelihoods
  expect_true(nrow(lk) > 0L)
  expect_false(any(lk$hypothesis_type == "specific_candidate"))
  expect_true(all(is.na(lk$best_identity)))
  expect_true(all(is.na(lk$best_identity_rank)))
  expect_true(all(is.na(lk$poor_absolute_fit)))
})

test_that("a 0-1 proportion score column gives the same flags as 0-100", {
  skip_if_not_installed("TaxaTools")
  for (sc in list(
    c(86.08, 86.08, 84.81, 84.81, 86.08, 86.08, 86.08),
    c(99.4, 99.4, 97, 97, 99.4, 99.4, 99.4),
    c(96.5, 96.5, 90, 90, 96.5, 96.5, 96.5)
  )) {
    a <- .af_eval(.af_unit(sc))$likelihoods
    d1 <- .af_unit(sc)
    d1$score <- d1$score / 100
    b <- .af_eval(d1)$likelihoods
    expect_equal(b$best_identity, a$best_identity, tolerance = 1e-8)
    expect_identical(b$best_identity_rank, a$best_identity_rank)
    expect_identical(b$poor_absolute_fit, a$poor_absolute_fit)
  }
})

test_that("a different unit gets its own value in a multi-unit call", {
  skip_if_not_installed("TaxaTools")
  d <- rbind(.af_unit(id = "poor"), .af_unit(c(99.4, 99.4, 97, 97, 99.4, 99.4, 99.4), id = "good"))
  lk <- .af_eval(d)$likelihoods
  expect_true(all(lk$poor_absolute_fit[lk$observation_id == "poor"]))
  expect_false(any(lk$poor_absolute_fit[lk$observation_id == "good"]))
})

test_that("an old model without usable curves gives NA columns and one message", {
  skip_if_not_installed("TaxaTools")
  for (cv in list(NULL, list(species = list(tpr_pooled = data.frame(threshold = 1), fpr_pooled = data.frame(threshold = 1))))) {
    p <- .af_params(cv)
    msgs <- character(0)
    res <- withCallingHandlers(
      evaluate_likelihoods(.af_unit(), p,
        rank_system = c("family", "genus", "species"), ratio_threshold = 0
      ),
      message = function(m) {
        msgs <<- c(msgs, conditionMessage(m))
        invokeRestart("muffleMessage")
      }
    )
    lk <- res$likelihoods
    expect_equal(sum(grepl("no usable true/false-positive curves", msgs)), 1L)
    expect_true(all(is.na(lk$best_identity_rank)))
    expect_true(all(is.na(lk$poor_absolute_fit)))
    expect_equal(lk$best_identity[1], 86.08, tolerance = 1e-8)
    expect_length(attr(lk, "rank_thresholds_used"), 0L)
  }
})

test_that("compute_rank_thresholds() is unchanged by the shared helper", {
  fx <- .curve_fixture()
  rt <- compute_rank_thresholds(fx, rank_system = .rs)
  cur <- .compute_rank_score_curves(fx, .rs)
  expect_equal(.rank_thresholds_from_curves(cur), rt)
  # value pinned from the pre-refactor implementation on this fixture
  expect_equal(rt, c(species = 94, genus = 76, family = 41))
})
