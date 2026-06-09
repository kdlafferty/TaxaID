# Tests for flag_prior_mismatch()

.make_cons <- function() {
  data.frame(
    observation_id    = c("obs1", "obs2", "obs3", "obs4", "obs5"),
    consensus_taxon   = c("Oncorhynchus mykiss", "Homo sapiens",
                          "Salmo salar", "Sardina pilchardus", "Unknown sp."),
    winner_likelihood = c(0.95,  0.03,  0.15,  0.80,  NA),
    winner_prior      = c(0.40,  0.80,  0.35,  0.002, 0.10),
    stringsAsFactors  = FALSE
  )
}

# ---- risk classification -------------------------------------------------------

test_that("high likelihood -> low risk", {
  out <- flag_prior_mismatch(.make_cons())
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs1"], "low")
})

test_that("likelihood below lower threshold -> high risk", {
  out <- flag_prior_mismatch(.make_cons())
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs2"], "high")
})

test_that("likelihood between thresholds -> moderate risk", {
  out <- flag_prior_mismatch(.make_cons())
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs3"], "moderate")
})

test_that("NA likelihood -> low risk", {
  out <- flag_prior_mismatch(.make_cons())
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs5"], "low")
})

# ---- score column --------------------------------------------------------------

test_that("prior_mismatch_score equals winner_likelihood", {
  df  <- .make_cons()
  out <- flag_prior_mismatch(df)
  expect_equal(out$prior_mismatch_score, df$winner_likelihood)
})

test_that("NA likelihood -> NA score", {
  out <- flag_prior_mismatch(.make_cons())
  expect_true(is.na(out$prior_mismatch_score[out$observation_id == "obs5"]))
})

# ---- reason column -------------------------------------------------------------

test_that("low risk -> NA reason (no unexpected-winner flag)", {
  out <- flag_prior_mismatch(.make_cons())
  # obs1: high likelihood, not unexpected winner
  expect_true(is.na(out$prior_mismatch_reason[out$observation_id == "obs1"]))
})

test_that("high risk -> reason contains threshold value", {
  out <- flag_prior_mismatch(.make_cons())
  r   <- out$prior_mismatch_reason[out$observation_id == "obs2"]
  expect_match(r, "0.05")
})

test_that("moderate risk from likelihood -> reason contains upper threshold", {
  out <- flag_prior_mismatch(.make_cons())
  r   <- out$prior_mismatch_reason[out$observation_id == "obs3"]
  expect_match(r, "0.20")
})

test_that("NA likelihood -> NA reason", {
  out <- flag_prior_mismatch(.make_cons())
  expect_true(is.na(out$prior_mismatch_reason[out$observation_id == "obs5"]))
})

# ---- unexpected winner (low prior + adequate likelihood) -----------------------

test_that("low prior + adequate likelihood escalates low -> moderate", {
  out <- flag_prior_mismatch(.make_cons())
  # obs4: winner_likelihood=0.80 (>= 0.20), winner_prior=0.002 (< 0.01)
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs4"], "moderate")
})

test_that("unexpected winner reason mentions prior threshold", {
  out <- flag_prior_mismatch(.make_cons())
  r   <- out$prior_mismatch_reason[out$observation_id == "obs4"]
  expect_match(r, "0.0100")
})

test_that("unexpected winner does not escalate high-risk rows", {
  df <- .make_cons()
  df$winner_prior[df$observation_id == "obs2"] <- 0.001  # low prior on already-high-risk
  out <- flag_prior_mismatch(df)
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs2"], "high")
})

test_that("low_prior_threshold = NULL suppresses unexpected-winner check", {
  out <- flag_prior_mismatch(.make_cons(), low_prior_threshold = NULL)
  # obs4 should stay "low" (no prior check)
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs4"], "low")
})

test_that("low_prior_threshold = 0 suppresses unexpected-winner check", {
  out <- flag_prior_mismatch(.make_cons(), low_prior_threshold = 0)
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs4"], "low")
})

# ---- missing winner_prior column -----------------------------------------------

test_that("missing winner_prior column skips unexpected-winner check", {
  df  <- .make_cons()
  df$winner_prior <- NULL
  out <- flag_prior_mismatch(df)
  # obs4 would have been unexpected_winner but prior col absent -> stays "low"
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs4"], "low")
  expect_true(all(!is.na(out$prior_mismatch_risk)))
})

test_that("all-NA winner_prior column skips unexpected-winner check", {
  df <- .make_cons()
  df$winner_prior <- NA_real_
  out <- flag_prior_mismatch(df)
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs4"], "low")
})

# ---- custom thresholds ---------------------------------------------------------

test_that("custom score_thresholds respected", {
  out <- flag_prior_mismatch(.make_cons(), score_thresholds = c(0.10, 0.50))
  # obs3: winner_likelihood=0.15 -> moderate with default (0.05, 0.20)
  # obs3: winner_likelihood=0.15 -> moderate with (0.10, 0.50) too (0.10 <= 0.15 < 0.50)
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs3"], "moderate")
  # obs1: winner_likelihood=0.95 -> low with both
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs1"], "low")
})

test_that("winner_likelihood_col = 'winner_likelihood_cov' accepted", {
  df <- .make_cons()
  names(df)[names(df) == "winner_likelihood"] <- "winner_likelihood_cov"
  out <- flag_prior_mismatch(df, winner_likelihood_col = "winner_likelihood_cov")
  expect_true("prior_mismatch_risk" %in% names(out))
  expect_equal(out$prior_mismatch_risk[out$observation_id == "obs2"], "high")
})

# ---- row count preserved -------------------------------------------------------

test_that("row count unchanged", {
  df  <- .make_cons()
  out <- flag_prior_mismatch(df)
  expect_equal(nrow(out), nrow(df))
})

# ---- validation errors ---------------------------------------------------------

test_that("stops on non-data-frame", {
  expect_error(flag_prior_mismatch("x"), "must be a data frame")
})

test_that("stops when winner_likelihood_col missing", {
  df <- .make_cons()
  df$winner_likelihood <- NULL
  expect_error(flag_prior_mismatch(df), "not found")
})

test_that("stops on invalid score_thresholds (not sorted)", {
  expect_error(
    flag_prior_mismatch(.make_cons(), score_thresholds = c(0.5, 0.1)),
    "sorted"
  )
})

test_that("stops on invalid score_thresholds (wrong length)", {
  expect_error(
    flag_prior_mismatch(.make_cons(), score_thresholds = c(0.1)),
    "sorted"
  )
})

test_that("stops on negative low_prior_threshold", {
  expect_error(
    flag_prior_mismatch(.make_cons(), low_prior_threshold = -0.1),
    "non-negative"
  )
})
