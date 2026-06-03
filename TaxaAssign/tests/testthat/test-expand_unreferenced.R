# ---- expand_unreferenced_hypotheses -----------------------------------------

.make_expand_lik <- function() {
  data.frame(
    observation_id            = "ESV_001",
    taxon_name           = c("Fundulus lima", "Fundulus diaphanus",
                             "Fundulus", "Fundulidae"),
    taxon_name_rank      = c("species", "species", "genus", "family"),
    hypothesis_type      = c("specific_candidate", "specific_candidate",
                             "unreferenced_species", "unreferenced_genus"),
    score_likelihood = c(0.95, 0.38, 0.31, 0.04),
    score_likelihood_mean      = c(0.95, 0.38, 0.31, 0.04),
    score_likelihood_sd        = c(0, 0, 0, 0),
    stringsAsFactors     = FALSE
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
  expect_equal(sort(h1$taxon_name), sort(c("Fundulus lima", "Fundulus diaphanus")))
  expect_equal(h1$score_likelihood[h1$taxon_name == "Fundulus lima"], 0.95)
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
  expect_equal(nrow(out), 2L)  # only H1 rows retained
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
