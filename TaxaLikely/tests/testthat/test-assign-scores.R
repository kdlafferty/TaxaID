# Tests for assign_scores()

.make_hyp_df <- function(n_obs = 2L) {
  # Two observations; each has 3 H1 candidates + H2 + H3
  obs1_h1 <- data.frame(
    observation_id  = "ESV_001",
    score_original  = c(0.95, 0.80, 0.60),
    taxon_name      = c("Hybognathus nuchalis", "Rhinichthys obtusus", "Campostoma anomalum"),
    taxon_name_rank = "species",
    family          = "Leuciscidae",
    genus           = c("Hybognathus", "Rhinichthys", "Campostoma"),
    species         = c("Hybognathus nuchalis", "Rhinichthys obtusus", "Campostoma anomalum"),
    hypothesis_type = "specific_candidate",
    stringsAsFactors = FALSE
  )
  obs1_h2 <- data.frame(
    observation_id  = "ESV_001",
    score_original  = NA_real_,
    taxon_name      = "Hybognathus sp.",
    taxon_name_rank = "genus",
    family          = "Leuciscidae",
    genus           = "Hybognathus",
    species         = NA_character_,
    hypothesis_type = "unreferenced_species",
    stringsAsFactors = FALSE
  )
  obs1_h3 <- data.frame(
    observation_id  = "ESV_001",
    score_original  = NA_real_,
    taxon_name      = "Leuciscidae sp.",
    taxon_name_rank = "family",
    family          = "Leuciscidae",
    genus           = NA_character_,
    species         = NA_character_,
    hypothesis_type = "unreferenced_genus",
    stringsAsFactors = FALSE
  )
  if (n_obs == 1L) return(rbind(obs1_h1, obs1_h2, obs1_h3))

  obs2_h1 <- data.frame(
    observation_id  = "ESV_002",
    score_original  = 0.70,
    taxon_name      = "Cottus carolinae",
    taxon_name_rank = "species",
    family          = "Cottidae",
    genus           = "Cottus",
    species         = "Cottus carolinae",
    hypothesis_type = "specific_candidate",
    stringsAsFactors = FALSE
  )
  obs2_h2 <- data.frame(
    observation_id  = "ESV_002",
    score_original  = NA_real_,
    taxon_name      = "Cottus sp.",
    taxon_name_rank = "genus",
    family          = "Cottidae",
    genus           = "Cottus",
    species         = NA_character_,
    hypothesis_type = "unreferenced_species",
    stringsAsFactors = FALSE
  )
  obs2_h3 <- data.frame(
    observation_id  = "ESV_002",
    score_original  = NA_real_,
    taxon_name      = "Cottidae sp.",
    taxon_name_rank = "family",
    family          = "Cottidae",
    genus           = NA_character_,
    species         = NA_character_,
    hypothesis_type = "unreferenced_genus",
    stringsAsFactors = FALSE
  )
  rbind(obs1_h1, obs1_h2, obs1_h3, obs2_h1, obs2_h2, obs2_h3)
}

# ---- "none" pathway ---------------------------------------------------------

test_that("score_type='none': all score_likelihood = 1.0", {
  out <- assign_scores(.make_hyp_df(), score_type = "none")
  expect_true(all(out$score_likelihood == 1.0))
  expect_true(all(out$score_likelihood_mean == 1.0))
  expect_true(all(out$score_likelihood_sd == 0.0))
  expect_true(all(out$score_method == "none"))
})

test_that("score_type='none': row count unchanged", {
  df  <- .make_hyp_df()
  out <- assign_scores(df, score_type = "none")
  expect_equal(nrow(out), nrow(df))
})

test_that("score_type='none': warns when score_col has non-NA values", {
  expect_warning(
    assign_scores(.make_hyp_df(), score_type = "none"),
    "score_type = 'none'"
  )
})

# ---- "similarity" pathway ---------------------------------------------------

test_that("score_type='similarity': score_norm added to H1 rows only", {
  out <- assign_scores(.make_hyp_df(), score_type = "similarity")
  expect_true("score_norm" %in% names(out))
  h1  <- out[out$hypothesis_type == "specific_candidate", ]
  non <- out[out$hypothesis_type != "specific_candidate", ]
  expect_true(all(!is.na(h1$score_norm)))
  expect_true(all(is.na(non$score_norm)))
})

test_that("score_type='similarity': score_method = 'similarity', no score_likelihood", {
  out <- assign_scores(.make_hyp_df(), score_type = "similarity")
  expect_true(all(out$score_method == "similarity"))
  expect_false("score_likelihood" %in% names(out))
})

test_that("score_type='similarity': score_norm in [0, 1]", {
  out <- assign_scores(.make_hyp_df(), score_type = "similarity")
  h1  <- out[out$hypothesis_type == "specific_candidate", ]
  expect_true(all(h1$score_norm >= 0 & h1$score_norm <= 1, na.rm = TRUE))
})

# ---- "probability" pathway --------------------------------------------------

test_that("score_type='probability': best H1 gets score_likelihood = 1", {
  out <- assign_scores(.make_hyp_df(), score_type = "probability")
  h1  <- out[out$hypothesis_type == "specific_candidate" &
               out$observation_id == "ESV_001", ]
  expect_equal(max(h1$score_likelihood, na.rm = TRUE), 1.0)
})

test_that("score_type='probability': score_likelihood in [0, 1]", {
  out <- assign_scores(.make_hyp_df(), score_type = "probability")
  h1  <- out[out$hypothesis_type == "specific_candidate", ]
  expect_true(all(h1$score_likelihood >= 0 & h1$score_likelihood <= 1,
                  na.rm = TRUE))
})

test_that("score_type='probability': H2 gets median congener H1 likelihood", {
  out <- assign_scores(.make_hyp_df(n_obs = 1L), score_type = "probability")
  h2  <- out[out$hypothesis_type == "unreferenced_species", ]
  h1  <- out[out$hypothesis_type == "specific_candidate" &
               out$genus == "Hybognathus", ]
  expect_equal(h2$score_likelihood, stats::median(h1$score_likelihood, na.rm = TRUE))
})

test_that("score_type='probability': score_likelihood_sd = 0", {
  out <- assign_scores(.make_hyp_df(), score_type = "probability")
  expect_true(all(out$score_likelihood_sd == 0.0))
})

test_that("score_type='probability': score_method = 'probability'", {
  out <- assign_scores(.make_hyp_df(), score_type = "probability")
  expect_true(all(out$score_method == "probability"))
})

# ---- "similarity_softmax" pathway -------------------------------------------

test_that("score_type='similarity_softmax': best H1 gets score_likelihood = 1", {
  out <- assign_scores(.make_hyp_df(), score_type = "similarity_softmax")
  h1  <- out[out$hypothesis_type == "specific_candidate" &
               out$observation_id == "ESV_001", ]
  expect_equal(max(h1$score_likelihood, na.rm = TRUE), 1.0, tolerance = 1e-9)
})

test_that("score_type='similarity_softmax': score_norm and score_softmax added", {
  out <- assign_scores(.make_hyp_df(), score_type = "similarity_softmax")
  h1  <- out[out$hypothesis_type == "specific_candidate", ]
  expect_true("score_norm"    %in% names(h1))
  expect_true("score_softmax" %in% names(h1))
})

# ---- H4 (unreferenced_family) fixed weight ----------------------------------

test_that("H4 rows get fixed 0.05 weight", {
  df <- .make_hyp_df(n_obs = 1L)
  df_h4 <- data.frame(
    observation_id  = "ESV_001",
    score_original  = NA_real_,
    taxon_name      = NA_character_,
    taxon_name_rank = NA_character_,
    family          = NA_character_,
    genus           = NA_character_,
    species         = NA_character_,
    hypothesis_type = "unreferenced_family",
    stringsAsFactors = FALSE
  )
  df_all <- rbind(df, df_h4)
  out <- assign_scores(df_all, score_type = "probability")
  h4  <- out[out$hypothesis_type == "unreferenced_family", ]
  expect_equal(h4$score_likelihood, 0.05)
})

# ---- aggregation: multiple accessions per taxon ----------------------------

test_that("multiple accessions per taxon are aggregated (median)", {
  # Three rows for the same species (different accessions)
  df <- data.frame(
    observation_id  = "ESV_A",
    score_original  = c(0.90, 0.80, 0.70),
    taxon_name      = "Hybognathus nuchalis",
    taxon_name_rank = "species",
    family          = "Leuciscidae",
    genus           = "Hybognathus",
    species         = "Hybognathus nuchalis",
    hypothesis_type = "specific_candidate",
    stringsAsFactors = FALSE
  )
  out <- assign_scores(df, score_type = "probability")
  h1  <- out[out$hypothesis_type == "specific_candidate", ]
  expect_equal(nrow(h1), 1L)   # aggregated to one row
  expect_equal(h1$score_likelihood, 1.0)  # only one taxon so ratio = 1
})

# ---- validation errors ------------------------------------------------------

test_that("stops on non-data-frame", {
  expect_error(assign_scores("x", score_type = "none"), "must be a data frame")
})

test_that("stops on invalid score_type", {
  expect_error(assign_scores(.make_hyp_df(), score_type = "bad"),
               "score_type.*must be one of")
})

test_that("stops on invalid score_sharpness", {
  expect_error(assign_scores(.make_hyp_df(), score_type = "similarity_softmax",
                             score_sharpness = -1),
               "positive number")
})

test_that("stops when score_col missing for non-none types", {
  df      <- .make_hyp_df()
  df$score_original <- NULL
  expect_error(assign_scores(df, score_type = "probability"),
               "not found")
})


# ---- score_type = "direct" ---------------------------------------------------

test_that("assign_scores direct passes scores through as score_likelihood", {
  df <- .make_hyp_df(n_obs = 1L)
  out <- assign_scores(df, score_type = "direct")
  h1  <- out[out$hypothesis_type == "specific_candidate", ]
  expect_equal(h1$score_likelihood, h1$score_original)
})

test_that("assign_scores direct sets NA scores to 1.0", {
  df <- .make_hyp_df(n_obs = 1L)
  # H2 / H3 rows have NA score_original
  out <- assign_scores(df, score_type = "direct")
  na_rows <- out[is.na(df$score_original), ]
  expect_true(all(na_rows$score_likelihood == 1.0))
})

test_that("assign_scores direct sets score_likelihood_sd to 0", {
  df  <- .make_hyp_df(n_obs = 1L)
  out <- assign_scores(df, score_type = "direct")
  expect_true(all(out$score_likelihood_sd == 0.0))
})

test_that("assign_scores direct sets score_method to 'direct'", {
  df  <- .make_hyp_df(n_obs = 1L)
  out <- assign_scores(df, score_type = "direct")
  expect_true(all(out$score_method == "direct"))
})

test_that("assign_scores direct score_likelihood_mean equals score_likelihood", {
  df  <- .make_hyp_df(n_obs = 1L)
  out <- assign_scores(df, score_type = "direct")
  expect_equal(out$score_likelihood_mean, out$score_likelihood)
})

test_that("assign_scores direct errors when score_col missing", {
  df <- .make_hyp_df(n_obs = 1L)
  df$score_original <- NULL
  expect_error(assign_scores(df, score_type = "direct"), "not found")
})
