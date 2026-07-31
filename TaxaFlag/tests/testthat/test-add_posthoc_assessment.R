# Tests for add_posthoc_assessment()
# posthoc_assessment (and its `tiers` input) retired 2026-07-30 -- see the
# function's own @section Retirement. Axis 1 (primary_plausibility/
# consensus_plausibility), Axis 2 (primary_discrimination/
# consensus_discrimination), and the domestic_prior_caveat flag are the
# entire surface now.

# expected_theta_threshold has no default and is a named-by-rank vector --
# most tests here don't exercise that specific behavior, so this wrapper
# supplies a fixed one unless a test overrides it explicitly.
.add_posthoc <- function(consensus_df, ...,
                         expected_theta_threshold = c(species = 0.05, genus = 0.05, family = 0.05)) {
  add_posthoc_assessment(consensus_df, ...,
                         expected_theta_threshold = expected_theta_threshold)
}

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

# ---- basic structure -----------------------------------------------------------

test_that("row count unchanged", {
  out <- .add_posthoc(.make_cons())
  expect_equal(nrow(out), nrow(.make_cons()))
})

test_that("posthoc_assessment column is NOT produced (retired)", {
  out <- .add_posthoc(.make_cons())
  expect_false("posthoc_assessment" %in% names(out))
})

test_that("all five expected output columns are present", {
  out <- .add_posthoc(.make_cons())
  expect_true(all(c("primary_plausibility", "consensus_plausibility",
                    "primary_discrimination", "consensus_discrimination",
                    "domestic_prior_caveat") %in% names(out)))
})

# ---- validation errors ---------------------------------------------------------

test_that("stops on non-data-frame consensus_df", {
  expect_error(.add_posthoc("x"), "must be a data frame")
})

test_that("stops when winner_likelihood_col missing", {
  cons <- .make_cons(); cons$winner_likelihood <- NULL
  expect_error(.add_posthoc(cons), "not found")
})

test_that("stops when consensus_taxon_col missing", {
  cons <- .make_cons(); cons$consensus_taxon <- NULL
  expect_error(.add_posthoc(cons), "not found")
})

test_that("stops when consensus_rank_col missing", {
  cons <- .make_cons(); cons$consensus_rank <- NULL
  expect_error(.add_posthoc(cons), "not found")
})

test_that("stops on invalid likelihood_threshold", {
  expect_error(
    .add_posthoc(.make_cons(), likelihood_threshold = 1.5),
    "single number in"
  )
})

test_that("custom column names accepted", {
  cons <- .make_cons()
  names(cons)[names(cons) == "winner_likelihood"] <- "lik_col"
  names(cons)[names(cons) == "consensus_taxon"]   <- "taxon_col"
  names(cons)[names(cons) == "consensus_rank"]    <- "rank_col"
  out <- .add_posthoc(cons,
                      winner_likelihood_col = "lik_col",
                      consensus_taxon_col   = "taxon_col",
                      consensus_rank_col    = "rank_col")
  expect_equal(nrow(out), nrow(cons))
})

# ==============================================================================
# domestic_prior_caveat (Session 149, redesigned 2026-07-30)
# Now its own additive logical column, driven by primary_plausibility
# (Axis 1) instead of the retired tier lookup.
# ==============================================================================

.make_domestic_cons <- function(theta = 0.001, record = TRUE, lik = 0.9) {
  data.frame(
    observation_id               = "obs1",
    consensus_taxon              = "Felis catus",
    consensus_rank                = "species",
    winner_likelihood            = lik,
    winner_theta_mean             = theta,
    winner_has_occurrence_record = record,
    stringsAsFactors = FALSE
  )
}

test_that("domestic_taxa = NULL (default) leaves domestic_prior_caveat FALSE", {
  out <- .add_posthoc(.make_domestic_cons())
  expect_false(out$domestic_prior_caveat)
})

test_that("domestic_taxa flags a strong-likelihood, occurrence-implausible domestic species", {
  out <- .add_posthoc(.make_domestic_cons(), domestic_taxa = "Felis catus")
  expect_true(out$domestic_prior_caveat)
  # primary_plausibility itself is untouched -- still correctly "unexpected".
  expect_equal(out$primary_plausibility, "unexpected")
})

test_that("domestic_prior_caveat does NOT fire for a low-likelihood domestic species", {
  out <- .add_posthoc(.make_domestic_cons(lik = 0.10), domestic_taxa = "Felis catus")
  expect_false(out$domestic_prior_caveat)
})

test_that("domestic_prior_caveat does NOT fire when primary_plausibility is 'expected'", {
  out <- .add_posthoc(.make_domestic_cons(theta = 0.9), domestic_taxa = "Felis catus")
  expect_equal(out$primary_plausibility, "expected")
  expect_false(out$domestic_prior_caveat)
})

test_that("domestic_prior_caveat does NOT fire for a non-domestic taxon", {
  cons <- .make_domestic_cons()
  cons$consensus_taxon <- "Not a cat"
  out <- .add_posthoc(cons, domestic_taxa = "Felis catus")
  expect_false(out$domestic_prior_caveat)
})

test_that("domestic_prior_source = 'augmented' disables the flag", {
  out <- .add_posthoc(.make_domestic_cons(), domestic_taxa = "Felis catus",
                      domestic_prior_source = "augmented")
  expect_false(out$domestic_prior_caveat)
})

test_that("stops on non-character domestic_taxa", {
  expect_error(
    .add_posthoc(.make_domestic_cons(), domestic_taxa = 42),
    "character vector or NULL"
  )
})

# ==============================================================================
# Axis 2: discrimination (2026-07-30)
#   primary_discrimination / consensus_discrimination
# ==============================================================================

test_that("both discrimination columns are always appended", {
  out <- .add_posthoc(.make_cons())
  expect_true(all(c("primary_discrimination", "consensus_discrimination") %in% names(out)))
})

test_that("primary_discrimination is NA when the source column is absent from consensus_df", {
  out <- .add_posthoc(.make_cons())
  expect_true(all(is.na(out$primary_discrimination)))
})

test_that("primary_discrimination tiers at the two thresholds", {
  cons <- .make_cons()
  cons$winner_own_rank_confusion_risk <- c(0.01, 0.05, 0.3, 0.5, 0.9, 0.02, NA)
  out <- .add_posthoc(cons)
  expect_equal(out$primary_discrimination[out$observation_id == "obs1"], "discriminating")   # 0.01 < 0.05
  expect_equal(out$primary_discrimination[out$observation_id == "obs2"], "weak")             # 0.05 (>= low)
  expect_equal(out$primary_discrimination[out$observation_id == "obs3"], "weak")             # 0.3
  expect_equal(out$primary_discrimination[out$observation_id == "obs4"], "indistinguishable") # 0.5 (>= high)
  expect_equal(out$primary_discrimination[out$observation_id == "obs5"], "indistinguishable") # 0.9
  expect_equal(out$primary_discrimination[out$observation_id == "obs7"], "not_modeled")       # NA
})

test_that("consensus_discrimination reads consensus_confusion_risk independently", {
  cons <- .make_cons()
  cons$winner_own_rank_confusion_risk <- 0.9
  cons$consensus_confusion_risk       <- 0.01
  out <- .add_posthoc(cons)
  expect_true(all(out$primary_discrimination == "indistinguishable"))
  expect_true(all(out$consensus_discrimination == "discriminating"))
})

test_that("custom column names and thresholds respected", {
  cons <- .make_cons()
  cons$my_risk <- 0.9
  out <- .add_posthoc(cons, primary_confusion_risk_col = "my_risk")
  expect_true(all(out$primary_discrimination == "indistinguishable"))

  cons2 <- .make_cons(); cons2$winner_own_rank_confusion_risk <- 0.2
  strict <- .add_posthoc(cons2,
                         discriminating_threshold = 0.25,
                         indistinguishable_threshold = 0.6)
  expect_true(all(strict$primary_discrimination == "discriminating"))
})

test_that("stops on invalid discrimination thresholds", {
  expect_error(
    .add_posthoc(.make_cons(), discriminating_threshold = 1.5),
    "discriminating_threshold"
  )
  expect_error(
    .add_posthoc(.make_cons(), indistinguishable_threshold = 1.5),
    "indistinguishable_threshold"
  )
  expect_error(
    .add_posthoc(.make_cons(), discriminating_threshold = 0.6, indistinguishable_threshold = 0.1),
    "discriminating_threshold"
  )
})

test_that("stops on invalid primary_confusion_risk_col", {
  expect_error(
    .add_posthoc(.make_cons(), primary_confusion_risk_col = 5),
    "primary_confusion_risk_col"
  )
})

# ==============================================================================
# Axis 1: occurrence plausibility (2026-07-28, theta-based 2026-07-30)
#   primary_plausibility / consensus_plausibility
# ==============================================================================
# The load-bearing design point: "unprecedented" is driven by RECORD PRESENCE,
# never by a low occurrence-share value. A never-reported taxon and a genuine
# singleton can carry the SAME numeric value (both land on the dark-diversity
# floor) while meaning opposite things -- so no threshold on the value can
# separate them, and these tests pin that.
#
# theta (not prior) is used throughout -- theta_mean is immune to
# update_prior_from_consensus()'s cross-observation confirmation boost,
# which prior_mean is not.

.make_plaus_cons <- function(theta = c(0.9, 0.01, 9.17e-06),
                              record = c(TRUE, TRUE, FALSE),
                              cons_theta = c(0.9, 0.01, NA_real_),
                              cons_record = c(TRUE, TRUE, NA)) {
  data.frame(
    observation_id               = c("obs1", "obs2", "obs3"),
    consensus_taxon              = c("Aa one", "Bb one", "Cc one"),
    consensus_rank               = rep("species", 3),
    winner_likelihood            = rep(0.9, 3),
    winner_theta_mean             = theta,
    winner_has_occurrence_record = record,
    consensus_prior              = cons_theta,
    consensus_has_occurrence_record = cons_record,
    stringsAsFactors = FALSE
  )
}

test_that("expected_theta_threshold has no default and errors when omitted", {
  expect_error(
    add_posthoc_assessment(.make_plaus_cons()),
    "expected_theta_threshold.*no default"
  )
})

test_that("both plausibility columns are always appended", {
  out <- .add_posthoc(.make_plaus_cons())
  expect_true(all(c("primary_plausibility", "consensus_plausibility") %in% names(out)))
})

test_that("plausibility splits expected/unexpected at the theta threshold", {
  out <- .add_posthoc(.make_plaus_cons())
  expect_equal(out$primary_plausibility[out$observation_id == "obs1"], "expected")    # 0.9
  expect_equal(out$primary_plausibility[out$observation_id == "obs2"], "unexpected")  # 0.01
})

test_that("a taxon with NO occurrence record is unprecedented regardless of its theta", {
  # The real-data case this exists for: no record, but a dark-diversity group
  # of only a few members gives it a HIGH boosted value. Value-thresholding
  # alone would call this "expected"; record presence must win.
  cons <- .make_plaus_cons(theta = c(0.9, 0.01, 0.975),
                           record = c(TRUE, TRUE, FALSE),
                           cons_theta = c(0.9, 0.01, NA_real_))
  out <- .add_posthoc(cons)
  expect_equal(out$primary_plausibility[out$observation_id == "obs3"], "unprecedented")
})

test_that("a singleton at the floor is NOT unprecedented -- it has a record", {
  # Same numeric value as obs3 above, opposite meaning. This is the whole
  # reason record presence is a separate signal.
  cons <- .make_plaus_cons(theta = c(0.9, 9.17e-06, 9.17e-06),
                           record = c(TRUE, TRUE, FALSE),
                           cons_theta = c(0.9, 9.17e-06, NA_real_))
  out <- .add_posthoc(cons)
  expect_equal(out$primary_plausibility[out$observation_id == "obs2"], "unexpected")
  expect_equal(out$primary_plausibility[out$observation_id == "obs3"], "unprecedented")
})

test_that("consensus_prior = NA means not_modeled, NOT unprecedented, at consensus scope", {
  # 2026-07-30 fix: consensus_prior's NA no longer reliably means "never
  # reported" -- it's ALSO NA whenever group_priors was never supplied to
  # posterior_consensus() at all (true of every real production workflow
  # today). Claiming "unprecedented" from that would be a false claim, not a
  # cautious default -- confirmed as a real bug on real production data,
  # where consensus_plausibility read "unprecedented" for all 616 rows
  # simply because group_priors was never wired in.
  out <- .add_posthoc(.make_plaus_cons())
  expect_equal(out$consensus_plausibility[out$observation_id == "obs3"], "not_modeled")
  expect_equal(out$consensus_plausibility[out$observation_id == "obs1"], "expected")
})

test_that("consensus_plausibility is never unprecedented when consensus_prior is entirely NA (group_priors not wired in)", {
  # Direct regression test for the real production-data bug: every real
  # workflow currently calls posterior_consensus() without group_priors, so
  # consensus_prior is NA for every single row. consensus_plausibility must
  # NOT read "unprecedented" for all of them -- that would be claiming every
  # taxon was checked and confirmed absent, when in fact none were checked.
  cons <- .make_plaus_cons()
  cons$consensus_prior <- NA_real_
  cons$consensus_has_occurrence_record <- NA
  out <- .add_posthoc(cons)
  expect_true(all(out$consensus_plausibility == "not_modeled"))
  expect_false(any(out$consensus_plausibility == "unprecedented"))
})

test_that("the two scopes can disagree", {
  # Winner itself has no record, but a recorded member of the consensus taxon
  # does -- primary unprecedented, consensus unexpected.
  cons <- .make_plaus_cons(theta = c(0.9, 0.01, 9.17e-06),
                           record = c(TRUE, TRUE, FALSE),
                           cons_theta = c(0.9, 0.01, 0.02),
                           cons_record = c(TRUE, TRUE, TRUE))
  out <- .add_posthoc(cons)
  expect_equal(out$primary_plausibility[out$observation_id == "obs3"], "unprecedented")
  expect_equal(out$consensus_plausibility[out$observation_id == "obs3"], "unexpected")
})

test_that("expected_theta_threshold is user-tunable", {
  cons <- .make_plaus_cons(theta = c(0.9, 0.01, 9.17e-06))
  strict <- .add_posthoc(cons, expected_theta_threshold = c(species = 0.95))
  expect_equal(strict$primary_plausibility[strict$observation_id == "obs1"], "unexpected")
  loose  <- .add_posthoc(cons, expected_theta_threshold = c(species = 0.005))
  expect_equal(loose$primary_plausibility[loose$observation_id == "obs2"], "expected")
})

test_that("plausibility is not_modeled when the record flag is NA, and NA when columns are absent", {
  cons <- .make_plaus_cons(record = c(NA, TRUE, FALSE))
  out <- .add_posthoc(cons)
  expect_equal(out$primary_plausibility[out$observation_id == "obs1"], "not_modeled")

  bare <- .make_plaus_cons()
  bare$winner_has_occurrence_record <- NULL
  bare$consensus_prior <- NULL
  out2 <- .add_posthoc(bare)
  expect_true(all(is.na(out2$primary_plausibility)))
  expect_true(all(is.na(out2$consensus_plausibility)))
})

test_that("stops on invalid expected_theta_threshold", {
  expect_error(
    .add_posthoc(.make_plaus_cons(), expected_theta_threshold = 1.5),
    "expected_theta_threshold"
  )
})

test_that("primary_plausibility is unaffected by a boosted winner_prior (only winner_theta_mean matters)", {
  # winner_prior is deliberately NOT read by add_posthoc_assessment() at all
  # any more -- confirm a wildly boosted prior_mean/winner_prior value present
  # on consensus_df has no effect on primary_plausibility.
  cons <- .make_plaus_cons(theta = c(0.01, 0.01, 0.01), record = c(TRUE, TRUE, TRUE))
  cons$winner_prior <- c(0.9999, 0.9999, 0.9999)  # boosted, should be ignored
  out <- .add_posthoc(cons, expected_theta_threshold = c(species = 0.05))
  expect_true(all(out$primary_plausibility == "unexpected"))
})

# ==============================================================================
# Rank-relative expected_theta_threshold (2026-07-30): a genus/family
# consensus_prior (a SUM over group members) is mechanically larger than a
# species-level value, so it must be compared against a rank-matched entry,
# not the same threshold used for species.
# ==============================================================================

.make_rank_cons <- function() {
  data.frame(
    observation_id               = c("obs1", "obs2", "obs3"),
    consensus_taxon              = c("Aa one", "Bb", "Cc"),
    consensus_rank                = c("species", "genus", "family"),
    winner_likelihood            = rep(0.9, 3),
    winner_theta_mean             = c(0.003, 0.01, 0.05),
    winner_has_occurrence_record = c(TRUE, TRUE, TRUE),
    consensus_prior              = c(0.003, 0.01, 0.05),
    consensus_has_occurrence_record = c(TRUE, TRUE, TRUE),
    stringsAsFactors = FALSE
  )
}

test_that("consensus_plausibility compares against the threshold matching its OWN rank", {
  # genus (0.01) clears the genus threshold (0.008) but would NOT clear the
  # family threshold (0.02) or the species one (0.005) if compared wrongly.
  out <- add_posthoc_assessment(
    .make_rank_cons(),
    expected_theta_threshold = c(species = 0.005, genus = 0.008, family = 0.02)
  )
  expect_equal(out$consensus_plausibility[out$observation_id == "obs2"], "expected")
  # family (0.05) clears the family threshold (0.02).
  expect_equal(out$consensus_plausibility[out$observation_id == "obs3"], "expected")
})

test_that("using the species threshold at every rank would give the wrong answer", {
  # Sanity check the test above actually exercises rank-matching: applying
  # the species-scale threshold (0.005) to the genus/family values would
  # ALSO call them "expected" here, since 0.01 and 0.05 both clear 0.005 --
  # so this specific fixture needs a threshold high enough to flip under the
  # wrong (species-only) comparison to prove rank-matching is doing real work.
  out_wrong_would_be <- add_posthoc_assessment(
    .make_rank_cons(),
    expected_theta_threshold = c(species = 0.5, genus = 0.008, family = 0.02)
  )
  # genus (0.01) still clears its OWN threshold (0.008) -- proving genus
  # rows are compared against "genus", not against species' 0.5.
  expect_equal(out_wrong_would_be$consensus_plausibility[out_wrong_would_be$observation_id == "obs2"], "expected")
})

test_that("consensus_plausibility is not_modeled when consensus_rank has no matching threshold entry", {
  out <- add_posthoc_assessment(
    .make_rank_cons(),
    expected_theta_threshold = c(species = 0.005, genus = 0.008)   # no family entry
  )
  expect_equal(out$consensus_plausibility[out$observation_id == "obs3"], "not_modeled")
  # species/genus rows are unaffected by the missing family entry.
  expect_equal(out$consensus_plausibility[out$observation_id == "obs1"], "unexpected")
  expect_equal(out$consensus_plausibility[out$observation_id == "obs2"], "expected")
})

test_that("primary_plausibility always uses the species entry regardless of consensus_rank", {
  # obs2/obs3 have consensus_rank genus/family, but primary_plausibility
  # (the WINNER's own share) must still compare against "species".
  cons <- .make_rank_cons()
  cons$winner_theta_mean <- c(0.003, 0.003, 0.003)   # same value for all three
  out <- add_posthoc_assessment(
    cons,
    expected_theta_threshold = c(species = 0.005, genus = 0.001, family = 0.001)
  )
  # If obs2/obs3 wrongly used genus/family (0.001), 0.003 would be "expected".
  # Using species (0.005) correctly, they must be "unexpected".
  expect_true(all(out$primary_plausibility == "unexpected"))
})

test_that("stops when expected_theta_threshold has no species entry", {
  expect_error(
    add_posthoc_assessment(.make_rank_cons(),
                           expected_theta_threshold = c(genus = 0.01, family = 0.02)),
    "species"
  )
})
