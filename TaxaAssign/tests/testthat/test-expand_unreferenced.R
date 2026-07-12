# ---- expand_unreferenced_hypotheses (deprecated forwarding wrapper) ---------
# Real implementation + full test coverage moved to TaxaLikely (Session 150).
# This file only confirms the wrapper still warns and forwards correctly.

test_that("expand_unreferenced_hypotheses: warns and forwards to TaxaLikely", {
  skip_if_not_installed("TaxaLikely")

  lik <- data.frame(
    observation_id        = "ESV_001",
    taxon_name            = c("Atherinops affinis", "Fundulus"),
    taxon_name_rank       = c("species", "genus"),
    hypothesis_type       = c("specific_candidate", "unreferenced_species"),
    score_likelihood      = c(0.95, 0.31),
    score_likelihood_mean = c(0.95, 0.31),
    score_likelihood_sd   = c(0, 0),
    stringsAsFactors      = FALSE
  )
  unref <- data.frame(
    species = "Fundulus parvipinnis",
    genus   = "Fundulus",
    family  = "Fundulidae",
    stringsAsFactors = FALSE
  )

  expect_warning(
    out <- suppressMessages(expand_unreferenced_hypotheses(lik, unref)),
    "moved to TaxaLikely"
  )
  expect_true("Fundulus parvipinnis" %in% out$taxon_name)

  direct <- suppressMessages(TaxaLikely::expand_unreferenced_hypotheses(lik, unref))
  expect_equal(out, direct)
})
