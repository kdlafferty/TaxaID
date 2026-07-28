# Tests for add_posthoc_assessment()

.make_cons <- function() {
  data.frame(
    observation_id    = paste0("obs", 1:7),
    consensus_taxon   = c("Oncorhynchus mykiss", "Salmo salar",
                          "Homo sapiens",        "Sardina pilchardus",
                          "Rare sp.",            "Cottus sp.",
                          "Ghost fish"),
    consensus_rank    = c("species", "species", "species", "species",
                          "species", "genus", "species"),
    winner_likelihood = c(0.95, 0.15, 0.80, 0.03, 0.70, 0.90, NA),
    stringsAsFactors  = FALSE
  )
}

.make_tiers <- function() {
  data.frame(
    taxon_name = c("Oncorhynchus mykiss", "Salmo salar",
                   "Homo sapiens",        "Sardina pilchardus",
                   "Rare sp."),
    model_tier = c("tier1", "tier1", "tier1",
                   "tier3_undetected", "tier2"),
    stringsAsFactors = FALSE
  )
}

# ---- core classifications ------------------------------------------------------

test_that("tier1 + supported -> sensible", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs1"], "sensible")
})

test_that("tier1 + limited_evidence -> limited_evidence", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs2"], "limited_evidence")
})

test_that("tier1 + supported (contaminant) -> sensible", {
  # Homo sapiens is tier1 with high likelihood
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs3"], "sensible")
})

test_that("tier3_undetected + limited -> suspect", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs4"], "suspect")
})

test_that("tier2 + supported -> unexpected", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs5"], "unexpected")
})

test_that("non-species rank -> vague_rank", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs6"], "vague_rank")
})

test_that("NA consensus_rank -> vague_rank (not suspect)", {
  cons <- .make_cons()
  cons$consensus_rank[cons$observation_id == "obs7"] <- NA
  cons$consensus_taxon[cons$observation_id == "obs7"] <- NA
  cons$winner_likelihood[cons$observation_id == "obs7"] <- 0.10
  out <- add_posthoc_assessment(cons, .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs7"], "vague_rank")
})

test_that("NA winner_likelihood -> modeled", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs7"], "modeled")
})

# ---- tier3 + supported -> unprecedented ----------------------------------------

test_that("tier3_undetected + supported -> unprecedented", {
  cons <- .make_cons()
  cons$winner_likelihood[cons$observation_id == "obs4"] <- 0.80
  out <- add_posthoc_assessment(cons, .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs4"], "unprecedented")
})

# ---- tier2 + limited -> suspect ------------------------------------------------

test_that("tier2 + limited -> suspect", {
  cons <- .make_cons()
  cons$winner_likelihood[cons$observation_id == "obs5"] <- 0.10
  out <- add_posthoc_assessment(cons, .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs5"], "suspect")
})

# ---- taxon not in tiers --------------------------------------------------------

test_that("taxon not in tiers + supported -> unexpected", {
  # Ghost fish (obs7) has NA likelihood → modeled; make a new case
  cons <- .make_cons()
  cons$winner_likelihood[cons$observation_id == "obs7"] <- 0.90
  out <- add_posthoc_assessment(cons, .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs7"], "unexpected")
})

test_that("taxon not in tiers + limited -> suspect", {
  cons <- .make_cons()
  cons$winner_likelihood[cons$observation_id == "obs7"] <- 0.10
  out <- add_posthoc_assessment(cons, .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs7"], "suspect")
})

# ---- boundary: exactly at likelihood_threshold ---------------------------------

test_that("winner_likelihood exactly at threshold -> supported", {
  cons <- .make_cons()
  cons$winner_likelihood[cons$observation_id == "obs2"] <- 0.5
  out <- add_posthoc_assessment(cons, .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs2"], "sensible")
})

# ---- custom parameters ---------------------------------------------------------

test_that("custom likelihood_threshold respected", {
  # obs1 has likelihood 0.95; with threshold=0.99 it becomes limited_evidence
  out <- add_posthoc_assessment(.make_cons(), .make_tiers(), likelihood_threshold = 0.99)
  expect_equal(out$posthoc_assessment[out$observation_id == "obs1"], "limited_evidence")
})

test_that("custom finest_rank: genus rank no longer vague_rank", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers(), finest_rank = "genus")
  # obs6 is genus rank; with finest_rank="genus" it should classify normally
  expect_false(out$posthoc_assessment[out$observation_id == "obs6"] == "vague_rank")
})

test_that("custom column names accepted", {
  cons  <- .make_cons()
  names(cons)[names(cons) == "winner_likelihood"] <- "lik_col"
  names(cons)[names(cons) == "consensus_taxon"]   <- "taxon_col"
  names(cons)[names(cons) == "consensus_rank"]    <- "rank_col"
  tiers <- .make_tiers()
  names(tiers)[names(tiers) == "taxon_name"]  <- "tx"
  names(tiers)[names(tiers) == "model_tier"]  <- "tr"
  out <- add_posthoc_assessment(cons, tiers,
                                winner_likelihood_col = "lik_col",
                                consensus_taxon_col   = "taxon_col",
                                consensus_rank_col    = "rank_col",
                                taxon_col             = "tx",
                                tier_col              = "tr")
  expect_equal(out$posthoc_assessment[out$observation_id == "obs1"], "sensible")
})

# ---- output structure ----------------------------------------------------------

test_that("row count unchanged", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(nrow(out), nrow(.make_cons()))
})

test_that("posthoc_assessment column added", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_true("posthoc_assessment" %in% names(out))
})

test_that("all rows receive a non-NA assessment", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_false(any(is.na(out$posthoc_assessment)))
})

test_that("only valid labels produced", {
  out    <- add_posthoc_assessment(.make_cons(), .make_tiers())
  valid  <- c("sensible", "limited_evidence", "unexpected",
               "suspect", "unprecedented", "vague_rank", "modeled")
  expect_true(all(out$posthoc_assessment %in% valid))
})

# ---- validation errors ---------------------------------------------------------

test_that("stops on non-data-frame consensus_df", {
  expect_error(add_posthoc_assessment("x", .make_tiers()), "must be a data frame")
})

test_that("stops on non-data-frame tiers", {
  expect_error(add_posthoc_assessment(.make_cons(), "x"), "must be a data frame")
})

test_that("stops when winner_likelihood_col missing", {
  cons <- .make_cons(); cons$winner_likelihood <- NULL
  expect_error(add_posthoc_assessment(cons, .make_tiers()), "not found")
})

test_that("stops when consensus_taxon_col missing", {
  cons <- .make_cons(); cons$consensus_taxon <- NULL
  expect_error(add_posthoc_assessment(cons, .make_tiers()), "not found")
})

test_that("stops when tier_col missing from tiers", {
  tiers <- .make_tiers(); tiers$model_tier <- NULL
  expect_error(add_posthoc_assessment(.make_cons(), tiers), "not found")
})

test_that("stops on invalid likelihood_threshold", {
  expect_error(
    add_posthoc_assessment(.make_cons(), .make_tiers(), likelihood_threshold = 1.5),
    "single number in"
  )
})

# ---- domestic-species caveat (Session 149) --------------------------------------

test_that("domestic_taxa = NULL (default) leaves tier2/tier3 classification unchanged", {
  # "Rare sp." is tier2 + lik_ok (0.70) -> "unexpected" without the feature
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_equal(out$posthoc_assessment[out$observation_id == "obs5"], "unexpected")
})

test_that("domestic_taxa re-labels a strong-likelihood tier2 domestic species", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers(), domestic_taxa = "Rare sp.")
  expect_equal(out$posthoc_assessment[out$observation_id == "obs5"], "domestic_prior_caveat")
})

test_that("domestic_taxa re-labels a strong-likelihood tier3_undetected domestic species", {
  # Sardina pilchardus is tier3_undetected but has low likelihood (0.03) in the
  # base fixture -- bump it so lik_ok is TRUE to exercise the tier3 branch.
  cons <- .make_cons()
  cons$winner_likelihood[cons$observation_id == "obs4"] <- 0.85
  out <- add_posthoc_assessment(cons, .make_tiers(), domestic_taxa = "Sardina pilchardus")
  expect_equal(out$posthoc_assessment[out$observation_id == "obs4"], "domestic_prior_caveat")
})

test_that("domestic_taxa does NOT re-label a low-likelihood domestic species (still suspect)", {
  cons <- .make_cons()
  cons$winner_likelihood[cons$observation_id == "obs5"] <- 0.10  # below threshold
  out <- add_posthoc_assessment(cons, .make_tiers(), domestic_taxa = "Rare sp.")
  expect_equal(out$posthoc_assessment[out$observation_id == "obs5"], "suspect")
})

test_that("domestic_taxa does not affect non-domestic taxa", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers(), domestic_taxa = "Rare sp.")
  expect_equal(out$posthoc_assessment[out$observation_id == "obs1"], "sensible")
})

test_that("domestic_prior_source = 'augmented' disables the re-labelling", {
  out <- add_posthoc_assessment(
    .make_cons(), .make_tiers(),
    domestic_taxa = "Rare sp.", domestic_prior_source = "augmented"
  )
  expect_equal(out$posthoc_assessment[out$observation_id == "obs5"], "unexpected")
})

test_that("stops on non-character domestic_taxa", {
  expect_error(
    add_posthoc_assessment(.make_cons(), .make_tiers(), domestic_taxa = 42),
    "character vector or NULL"
  )
})


test_that("confusion_risk_flag is NA when own_rank_confusion_risk_col is absent", {
  out <- add_posthoc_assessment(.make_cons(), .make_tiers())
  expect_true("confusion_risk_flag" %in% names(out))
  expect_true(all(is.na(out$confusion_risk_flag)))
})

test_that("confusion_risk_flag classifies above/below high_confusion_risk_threshold", {
  cons <- .make_cons()
  cons$winner_own_rank_confusion_risk <- 0.9   # high risk (weak evidence)
  cons$winner_own_rank_confusion_risk[cons$observation_id == "obs2"] <- 0.1  # low risk (strong evidence)
  out <- add_posthoc_assessment(cons, .make_tiers())
  expect_equal(out$confusion_risk_flag[out$observation_id == "obs1"], "high_confusion_risk")
  expect_equal(out$confusion_risk_flag[out$observation_id == "obs2"], "low_confusion_risk")
})

test_that("confusion_risk_flag is NA for NA own_rank_confusion_risk values", {
  cons <- .make_cons()
  cons$winner_own_rank_confusion_risk <- NA_real_
  out <- add_posthoc_assessment(cons, .make_tiers())
  expect_true(all(is.na(out$confusion_risk_flag)))
})

test_that("own_rank_confusion_risk_col respects a custom column name", {
  cons <- .make_cons()
  cons$my_risk <- 0.9
  out <- add_posthoc_assessment(cons, .make_tiers(), own_rank_confusion_risk_col = "my_risk")
  expect_true(all(out$confusion_risk_flag == "high_confusion_risk"))
})

test_that("confusion_risk_flag never overrides posthoc_assessment", {
  # The two are deliberately independent columns, not one override chain:
  # changing the confusion risk must leave posthoc_assessment untouched.
  cons_hi <- .make_cons(); cons_hi$winner_own_rank_confusion_risk <- 0.9
  cons_lo <- .make_cons(); cons_lo$winner_own_rank_confusion_risk <- 0.01
  out_hi <- add_posthoc_assessment(cons_hi, .make_tiers())
  out_lo <- add_posthoc_assessment(cons_lo, .make_tiers())
  expect_equal(out_hi$posthoc_assessment, out_lo$posthoc_assessment)
  expect_true(all(out_hi$confusion_risk_flag == "high_confusion_risk"))
  expect_true(all(out_lo$confusion_risk_flag == "low_confusion_risk"))
})

test_that("stops on invalid high_confusion_risk_threshold", {
  expect_error(
    add_posthoc_assessment(.make_cons(), .make_tiers(), high_confusion_risk_threshold = 1.5),
    "high_confusion_risk_threshold"
  )
})

test_that("stops on invalid own_rank_confusion_risk_col", {
  expect_error(
    add_posthoc_assessment(.make_cons(), .make_tiers(), own_rank_confusion_risk_col = 5),
    "own_rank_confusion_risk_col"
  )
})


# ==============================================================================
# Axis 1: occurrence plausibility (2026-07-28)
#   primary_plausibility / consensus_plausibility
# ==============================================================================
# The load-bearing design point: "unprecedented" is driven by RECORD PRESENCE,
# never by a low prior value. A never-reported taxon and a genuine singleton
# can carry the SAME numeric prior (both land on the dark-diversity floor)
# while meaning opposite things -- so no threshold on the value can separate
# them, and these tests pin that.

.make_plaus_cons <- function(prior = c(0.9, 0.01, 9.17e-06),
                              record = c(TRUE, TRUE, FALSE),
                              cons_prior = c(0.9, 0.01, NA_real_)) {
  data.frame(
    observation_id               = c("obs1", "obs2", "obs3"),
    consensus_taxon              = c("Aa one", "Bb one", "Cc one"),
    consensus_rank               = rep("species", 3),
    winner_likelihood            = rep(0.9, 3),
    winner_prior                 = prior,
    winner_has_occurrence_record = record,
    consensus_prior              = cons_prior,
    stringsAsFactors = FALSE
  )
}
.plaus_tiers <- function() data.frame(
  taxon_name = c("Aa one", "Bb one", "Cc one"),
  model_tier = c("tier1", "tier2", "tier2"),
  stringsAsFactors = FALSE
)

test_that("both plausibility columns are always appended", {
  out <- add_posthoc_assessment(.make_plaus_cons(), .plaus_tiers())
  expect_true(all(c("primary_plausibility", "consensus_plausibility") %in% names(out)))
})

test_that("plausibility splits expected/unexpected at the prior threshold", {
  out <- add_posthoc_assessment(.make_plaus_cons(), .plaus_tiers())
  expect_equal(out$primary_plausibility[out$observation_id == "obs1"], "expected")    # 0.9
  expect_equal(out$primary_plausibility[out$observation_id == "obs2"], "unexpected")  # 0.01
})

test_that("a taxon with NO occurrence record is unprecedented regardless of its prior", {
  # The real-data case this exists for: no record, but a dark-diversity group
  # of only a few members gives it a HIGH prior. Value-thresholding alone would
  # call this "expected"; record presence must win.
  cons <- .make_plaus_cons(prior = c(0.9, 0.01, 0.975),
                           record = c(TRUE, TRUE, FALSE),
                           cons_prior = c(0.9, 0.01, NA_real_))
  out <- add_posthoc_assessment(cons, .plaus_tiers())
  expect_equal(out$primary_plausibility[out$observation_id == "obs3"], "unprecedented")
})

test_that("a singleton at the floor is NOT unprecedented -- it has a record", {
  # Same numeric prior as obs3 above, opposite meaning. This is the whole
  # reason record presence is a separate signal.
  cons <- .make_plaus_cons(prior = c(0.9, 9.17e-06, 9.17e-06),
                           record = c(TRUE, TRUE, FALSE),
                           cons_prior = c(0.9, 9.17e-06, NA_real_))
  out <- add_posthoc_assessment(cons, .plaus_tiers())
  expect_equal(out$primary_plausibility[out$observation_id == "obs2"], "unexpected")
  expect_equal(out$primary_plausibility[out$observation_id == "obs3"], "unprecedented")
})

test_that("consensus_prior = NA means unprecedented at consensus scope", {
  out <- add_posthoc_assessment(.make_plaus_cons(), .plaus_tiers())
  expect_equal(out$consensus_plausibility[out$observation_id == "obs3"], "unprecedented")
  expect_equal(out$consensus_plausibility[out$observation_id == "obs1"], "expected")
})

test_that("the two scopes can disagree", {
  # Winner itself has no record, but a recorded member of the consensus taxon
  # does -- primary unprecedented, consensus unexpected.
  cons <- .make_plaus_cons(prior = c(0.9, 0.01, 9.17e-06),
                           record = c(TRUE, TRUE, FALSE),
                           cons_prior = c(0.9, 0.01, 0.02))
  out <- add_posthoc_assessment(cons, .plaus_tiers())
  expect_equal(out$primary_plausibility[out$observation_id == "obs3"], "unprecedented")
  expect_equal(out$consensus_plausibility[out$observation_id == "obs3"], "unexpected")
})

test_that("expected_prior_threshold is user-tunable", {
  cons <- .make_plaus_cons(prior = c(0.9, 0.01, 9.17e-06))
  strict <- add_posthoc_assessment(cons, .plaus_tiers(), expected_prior_threshold = 0.95)
  expect_equal(strict$primary_plausibility[strict$observation_id == "obs1"], "unexpected")
  loose  <- add_posthoc_assessment(cons, .plaus_tiers(), expected_prior_threshold = 0.005)
  expect_equal(loose$primary_plausibility[loose$observation_id == "obs2"], "expected")
})

test_that("plausibility is not_modeled when the record flag is NA, and NA when columns are absent", {
  cons <- .make_plaus_cons(record = c(NA, TRUE, FALSE))
  out <- add_posthoc_assessment(cons, .plaus_tiers())
  expect_equal(out$primary_plausibility[out$observation_id == "obs1"], "not_modeled")

  bare <- .make_plaus_cons()
  bare$winner_has_occurrence_record <- NULL
  bare$consensus_prior <- NULL
  out2 <- add_posthoc_assessment(bare, .plaus_tiers())
  expect_true(all(is.na(out2$primary_plausibility)))
  expect_true(all(is.na(out2$consensus_plausibility)))
})

test_that("plausibility never alters posthoc_assessment", {
  base <- add_posthoc_assessment(.make_plaus_cons(), .plaus_tiers())$posthoc_assessment
  alt  <- add_posthoc_assessment(
    .make_plaus_cons(prior = c(1e-9, 1e-9, 1e-9), record = c(FALSE, FALSE, FALSE),
                     cons_prior = c(NA_real_, NA_real_, NA_real_)),
    .plaus_tiers())$posthoc_assessment
  expect_equal(base, alt)
})

test_that("stops on invalid expected_prior_threshold", {
  expect_error(
    add_posthoc_assessment(.make_plaus_cons(), .plaus_tiers(),
                           expected_prior_threshold = 1.5),
    "expected_prior_threshold"
  )
})
