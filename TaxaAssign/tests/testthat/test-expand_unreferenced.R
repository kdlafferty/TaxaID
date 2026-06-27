# ---- expand_unreferenced_hypotheses -----------------------------------------

# Fixture: H1 specific_candidate is Atherinops (different genus from H2 = Fundulus),
# so H2 expansion fires normally. Tests that verify suppression use separate fixtures.
.make_expand_lik <- function() {
  data.frame(
    observation_id        = "ESV_001",
    taxon_name            = c("Atherinops affinis", "Fundulus", "Fundulidae"),
    taxon_name_rank       = c("species", "genus", "family"),
    hypothesis_type       = c("specific_candidate",
                               "unreferenced_species", "unreferenced_genus"),
    score_likelihood      = c(0.95, 0.31, 0.04),
    score_likelihood_mean = c(0.95, 0.31, 0.04),
    score_likelihood_sd   = c(0,    0,    0),
    stringsAsFactors      = FALSE
  )
}

.make_unref_df <- function() {
  data.frame(
    species = c("Fundulus parvipinnis", "Fundulus zebrinus", "Lucania parva"),
    genus   = c("Fundulus",             "Fundulus",          "Lucania"),
    family  = c("Fundulidae",           "Fundulidae",        "Fundulidae"),
    stringsAsFactors = FALSE
  )
}

test_that("expand_unreferenced_hypotheses: H2 generic row replaced with named species", {
  out <- expand_unreferenced_hypotheses(.make_expand_lik(), .make_unref_df())
  h2  <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(sort(h2$taxon_name),
               sort(c("Fundulus parvipinnis", "Fundulus zebrinus")))
  expect_true(all(h2$taxon_name_rank == "species"))
  expect_true(all(h2$score_likelihood == 0.31))
  expect_false("Fundulus" %in% out$taxon_name)
})

test_that("expand_unreferenced_hypotheses: H3 generic row replaced with named species from other genus", {
  out <- expand_unreferenced_hypotheses(.make_expand_lik(), .make_unref_df())
  h3  <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_equal(h3$taxon_name, "Lucania parva")
  expect_equal(h3$taxon_name_rank, "species")
  expect_equal(h3$score_likelihood, 0.04)
  expect_false("Fundulidae" %in% out$taxon_name)
})

test_that("expand_unreferenced_hypotheses: H3 excludes species from H2 genus", {
  unref_extra <- rbind(
    .make_unref_df(),
    data.frame(species = "Fundulus nottatus", genus = "Fundulus",
               family = "Fundulidae", stringsAsFactors = FALSE)
  )
  out <- expand_unreferenced_hypotheses(.make_expand_lik(), unref_extra)
  h3  <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_false("Fundulus nottatus" %in% h3$taxon_name)
  expect_true("Fundulus nottatus" %in%
                out$taxon_name[out$hypothesis_type == "unreferenced_species"])
})

test_that("expand_unreferenced_hypotheses: H1 rows passed through unchanged", {
  out <- expand_unreferenced_hypotheses(.make_expand_lik(), .make_unref_df())
  h1  <- out[out$hypothesis_type == "specific_candidate", ]
  expect_equal(h1$taxon_name, "Atherinops affinis")
  expect_equal(h1$score_likelihood, 0.95)
})

test_that("expand_unreferenced_hypotheses: generic H2 dropped when no genus match", {
  unref_no_fundulus <- data.frame(
    species = "Lucania parva", genus = "Lucania", family = "Fundulidae",
    stringsAsFactors = FALSE
  )
  out <- expand_unreferenced_hypotheses(.make_expand_lik(), unref_no_fundulus)
  h2  <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(nrow(h2), 0L)
})

test_that("expand_unreferenced_hypotheses: generic H3 dropped when no family match", {
  unref_other_family <- data.frame(
    species = "Cottus bairdii", genus = "Cottus", family = "Cottidae",
    stringsAsFactors = FALSE
  )
  out <- expand_unreferenced_hypotheses(.make_expand_lik(), unref_other_family)
  h3  <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_equal(nrow(h3), 0L)
})

test_that("expand_unreferenced_hypotheses: empty unreferenced_df drops H2/H3 rows", {
  empty <- data.frame(species = character(), genus = character(),
                      family = character(), stringsAsFactors = FALSE)
  out <- suppressMessages(expand_unreferenced_hypotheses(.make_expand_lik(), empty))
  expect_equal(nrow(out), 1L)  # only H1 row retained
  expect_true(all(out$hypothesis_type == "specific_candidate"))
})

test_that("expand_unreferenced_hypotheses: non-data-frame inputs error", {
  expect_error(expand_unreferenced_hypotheses(list(), .make_unref_df()),
               "must be a data frame")
  expect_error(expand_unreferenced_hypotheses(.make_expand_lik(), list()),
               "must be a data frame")
})

test_that("expand_unreferenced_hypotheses: missing required columns error", {
  expect_error(
    expand_unreferenced_hypotheses(data.frame(x = 1), .make_unref_df()),
    "missing required columns"
  )
  expect_error(
    expand_unreferenced_hypotheses(.make_expand_lik(), data.frame(species = "A b")),
    "missing required columns"
  )
})

test_that("expand_unreferenced_hypotheses: works across multiple observation_ids", {
  lik2 <- dplyr::bind_rows(
    .make_expand_lik(),
    dplyr::mutate(.make_expand_lik(), observation_id = "ESV_002")
  )
  out <- expand_unreferenced_hypotheses(lik2, .make_unref_df())
  expect_equal(dplyr::n_distinct(out$observation_id), 2L)
  for (sid in c("ESV_001", "ESV_002")) {
    h2 <- out[out$observation_id == sid & out$hypothesis_type == "unreferenced_species", ]
    expect_equal(nrow(h2), 2L)
  }
})

# ---- H1-coverage suppression (species-level) --------------------------------

test_that("expand_unreferenced_hypotheses: H2 suppresses only exact H1 species, not full genus", {
  # H1 = Fundulus heteroclitus; parvipinnis and zebrinus are different species —
  # species-level suppression allows them to expand as H2 candidates.
  lik_fundulus_h1 <- data.frame(
    observation_id        = "ESV_001",
    taxon_name            = c("Fundulus heteroclitus", "Fundulus", "Fundulidae"),
    taxon_name_rank       = c("species", "genus", "family"),
    hypothesis_type       = c("specific_candidate",
                               "unreferenced_species", "unreferenced_genus"),
    score_likelihood      = c(0.95, 0.31, 0.04),
    score_likelihood_mean = c(0.95, 0.31, 0.04),
    score_likelihood_sd   = c(0,    0,    0),
    stringsAsFactors      = FALSE
  )
  out <- expand_unreferenced_hypotheses(lik_fundulus_h1, .make_unref_df())
  h2  <- out[out$hypothesis_type == "unreferenced_species", ]
  # parvipinnis and zebrinus are NOT heteroclitus — they should expand as H2
  expect_equal(sort(h2$taxon_name), sort(c("Fundulus parvipinnis", "Fundulus zebrinus")))
  # H1 must still be present
  expect_true("Fundulus heteroclitus" %in% out$taxon_name)
  # H1 species should not appear in H2
  expect_false("Fundulus heteroclitus" %in% h2$taxon_name)
})

test_that("expand_unreferenced_hypotheses: H3 suppresses only exact H1 species, not full genus", {
  # H1 is Lucania goodei (species-rank). Lucania parva is a DIFFERENT species —
  # species-level suppression allows it to appear in H3.
  lik_lucania_h1 <- data.frame(
    observation_id        = "ESV_001",
    taxon_name            = c("Lucania goodei", "Atherinops", "Fundulidae"),
    taxon_name_rank       = c("species", "genus", "family"),
    hypothesis_type       = c("specific_candidate",
                               "unreferenced_species", "unreferenced_genus"),
    score_likelihood      = c(0.95, 0.31, 0.04),
    score_likelihood_mean = c(0.95, 0.31, 0.04),
    score_likelihood_sd   = c(0,    0,    0),
    stringsAsFactors      = FALSE
  )
  out <- expand_unreferenced_hypotheses(lik_lucania_h1, .make_unref_df())
  h3  <- out[out$hypothesis_type == "unreferenced_genus", ]
  # Lucania parva is a different species from H1 Lucania goodei — should appear in H3
  expect_true("Lucania parva" %in% h3$taxon_name)
  # Fundulus species should still expand into H3 (their genus is not covered by H1)
  expect_true(any(grepl("Fundulus", h3$taxon_name)))
})

test_that("expand_unreferenced_hypotheses: H2 expands congeners even when one species is H1", {
  # H1 covers Fundulus heteroclitus but not parvipinnis/zebrinus — H2 should expand both.
  lik_fundulus_h1 <- data.frame(
    observation_id        = "ESV_001",
    taxon_name            = c("Fundulus heteroclitus", "Fundulus", "Fundulidae"),
    taxon_name_rank       = c("species", "genus", "family"),
    hypothesis_type       = c("specific_candidate",
                               "unreferenced_species", "unreferenced_genus"),
    score_likelihood      = c(0.95, 0.31, 0.04),
    score_likelihood_mean = c(0.95, 0.31, 0.04),
    score_likelihood_sd   = c(0,    0,    0),
    stringsAsFactors      = FALSE
  )
  out <- expand_unreferenced_hypotheses(lik_fundulus_h1, .make_unref_df())
  h2  <- out[out$hypothesis_type == "unreferenced_species", ]
  h3  <- out[out$hypothesis_type == "unreferenced_genus", ]
  # H2 expands parvipinnis and zebrinus (not heteroclitus)
  expect_equal(sort(h2$taxon_name), sort(c("Fundulus parvipinnis", "Fundulus zebrinus")))
  # H3 Lucania parva not covered by H1 — should appear
  expect_true("Lucania parva" %in% h3$taxon_name)
  # H3 should not duplicate H2 genus species
  expect_false(any(grepl("Fundulus", h3$taxon_name)))
})

test_that("expand_unreferenced_hypotheses: species-level suppression — H1 lima does not block H2 parvipinnis", {
  # Mugu ASV_354 scenario: F. lima appears as H1 (BLAST matched long mitogenome sequences).
  # F. parvipinnis is unreferenced (no short 12S barcodes in NCBI). Old genus-level
  # suppression blocked parvipinnis; species-level suppression allows it through as H2.
  lik_lima_h1 <- data.frame(
    observation_id        = "ASV_354",
    taxon_name            = c("Fundulus lima", "Fundulus", "Fundulidae"),
    taxon_name_rank       = c("species", "genus", "family"),
    hypothesis_type       = c("specific_candidate",
                               "unreferenced_species", "unreferenced_genus"),
    score_likelihood      = c(0.02, 0.31, 0.04),
    score_likelihood_mean = c(0.02, 0.31, 0.04),
    score_likelihood_sd   = c(0,    0,    0),
    stringsAsFactors      = FALSE
  )
  unref_parv <- data.frame(
    species = "Fundulus parvipinnis",
    genus   = "Fundulus",
    family  = "Fundulidae",
    stringsAsFactors = FALSE
  )
  out <- expand_unreferenced_hypotheses(lik_lima_h1, unref_parv)
  h2  <- out[out$hypothesis_type == "unreferenced_species", ]
  # parvipinnis is NOT lima — should appear as H2
  expect_true("Fundulus parvipinnis" %in% h2$taxon_name)
  # lima should not appear in H2 (it's already H1)
  expect_false("Fundulus lima" %in% h2$taxon_name)
})

test_that("expand_unreferenced_hypotheses: genus-rank H1 still suppresses all H2 in that genus", {
  # When H1 is genus-rank (species couldn't be resolved), the entire genus is suppressed.
  lik_genus_h1 <- data.frame(
    observation_id        = "ESV_001",
    taxon_name            = c("Fundulus", "Fundulus", "Fundulidae"),
    taxon_name_rank       = c("genus", "genus", "family"),
    hypothesis_type       = c("specific_candidate",
                               "unreferenced_species", "unreferenced_genus"),
    score_likelihood      = c(0.95, 0.31, 0.04),
    score_likelihood_mean = c(0.95, 0.31, 0.04),
    score_likelihood_sd   = c(0,    0,    0),
    stringsAsFactors      = FALSE
  )
  out <- expand_unreferenced_hypotheses(lik_genus_h1, .make_unref_df())
  h2  <- out[out$hypothesis_type == "unreferenced_species", ]
  # Genus-rank H1 suppresses all Fundulus H2 expansion
  expect_equal(nrow(h2), 0L)
})
