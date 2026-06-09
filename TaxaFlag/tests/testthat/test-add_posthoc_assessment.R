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
