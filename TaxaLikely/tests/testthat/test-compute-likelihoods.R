# Tests for compute_likelihoods() and model_likelihoods()

.make_cl_match <- function() {
  data.frame(
    observation_id  = c("ESV_001", "ESV_001", "ESV_001", "ESV_002"),
    score_original  = c(0.95, 0.80, 0.60, 0.70),
    taxon_name      = c("Hybognathus nuchalis", "Rhinichthys obtusus",
                        "Campostoma anomalum", "Cottus carolinae"),
    taxon_name_rank = "species",
    family          = c("Leuciscidae", "Leuciscidae", "Leuciscidae", "Cottidae"),
    genus           = c("Hybognathus", "Rhinichthys", "Campostoma", "Cottus"),
    species         = c("Hybognathus nuchalis", "Rhinichthys obtusus",
                        "Campostoma anomalum", "Cottus carolinae"),
    stringsAsFactors = FALSE
  )
}

# ---- compute_likelihoods() — "none" pathway ---------------------------------

test_that("score_type='none': returns $likelihoods and $unresolved", {
  res <- compute_likelihoods(.make_cl_match(), score_type = "none")
  expect_true(is.list(res))
  expect_true(all(c("likelihoods", "unresolved") %in% names(res)))
})

test_that("score_type='none': all score_likelihood = 1.0", {
  res  <- compute_likelihoods(.make_cl_match(), score_type = "none")
  liks <- res$likelihoods
  expect_true(all(liks$score_likelihood == 1.0))
})

test_that("score_type='none': unresolved is empty data frame", {
  res <- compute_likelihoods(.make_cl_match(), score_type = "none")
  expect_true(is.data.frame(res$unresolved))
  expect_equal(nrow(res$unresolved), 0L)
})

test_that("score_type='none': likelihoods contains observation_id and hypothesis_type", {
  res  <- compute_likelihoods(.make_cl_match(), score_type = "none")
  liks <- res$likelihoods
  expect_true("observation_id"  %in% names(liks))
  expect_true("hypothesis_type" %in% names(liks))
})

# ---- compute_likelihoods() — "probability" pathway -------------------------

test_that("score_type='probability': best H1 gets score_likelihood = 1", {
  res  <- compute_likelihoods(.make_cl_match(), score_type = "probability")
  liks <- res$likelihoods
  h1_001 <- liks[liks$observation_id == "ESV_001" &
                   liks$hypothesis_type == "specific_candidate", ]
  expect_equal(max(h1_001$score_likelihood, na.rm = TRUE), 1.0)
})

test_that("score_type='probability': score_method = 'probability'", {
  res  <- compute_likelihoods(.make_cl_match(), score_type = "probability")
  liks <- res$likelihoods
  expect_true(all(liks$score_method == "probability"))
})

# ---- compute_likelihoods() — "similarity_softmax" pathway ------------------

test_that("score_type='similarity_softmax': returns valid likelihoods", {
  res  <- compute_likelihoods(.make_cl_match(),
                              score_type = "similarity_softmax",
                              rank_system = c("family", "genus", "species"))
  liks <- res$likelihoods
  expect_true(all(liks$score_likelihood >= 0, na.rm = TRUE))
  expect_equal(max(liks$score_likelihood[liks$observation_id == "ESV_001" &
                                           liks$hypothesis_type == "specific_candidate"],
                   na.rm = TRUE), 1.0, tolerance = 1e-9)
})

# ---- compute_likelihoods() — "similarity" pathway (requires model) ---------

test_that("score_type='similarity' without model_params stops with informative error", {
  expect_error(
    compute_likelihoods(.make_cl_match(), score_type = "similarity"),
    "model_params"
  )
})

# ---- model_likelihoods() ----------------------------------------------------

.make_model_params_cl <- function() {
  sigma <- matrix(c(2.0, 0.2, 0.2, 1.0), nrow = 2L,
                  dimnames = list(c("score_logit","gap_logit"),
                                  c("score_logit","gap_logit")))
  h2s <- diag(2); rownames(h2s) <- colnames(h2s) <- c("score_logit","gap_logit")
  h3s <- diag(2); rownames(h3s) <- colnames(h3s) <- c("score_logit","gap_logit")
  structure(
    list(
      H1_Lookup    = data.frame(lookup_key  = "Hybognathus nuchalis",
                                rank        = "species",
                                mu_score    = 4.5,
                                mu_gap      = 2.0,
                                sigma_score = 2.0,
                                stringsAsFactors = FALSE),
      H1_Global_Mu = c(score_logit = 3.5, gap_logit = 1.5),
      H1_Sigma     = sigma,
      H2           = list(delta = 3.0, sigma = h2s),
      H3           = list(delta = 5.0, sigma = h3s),
      Stats        = list(n_species = 1L, n_singletons = 0L)
    ),
    class = "taxa_model_params"
  )
}

test_that("model_likelihoods: returns $likelihoods and $unresolved", {
  skip_if_not_installed("TaxaTools")
  # Build a pre-scored similarity df (what assign_scores returns for "similarity")
  hyp_df <- unreferenced_candidates(
    .make_cl_match(),
    rank_system = c("family", "genus", "species")
  )
  sc_df <- assign_scores(hyp_df, score_type = "similarity")
  res <- model_likelihoods(sc_df, model_params = .make_model_params_cl(),
                           rank_system = c("family", "genus", "species"))
  expect_true(is.list(res))
  expect_true(all(c("likelihoods", "unresolved") %in% names(res)))
})

test_that("model_likelihoods: score_method = 'bivariate_normal'", {
  skip_if_not_installed("TaxaTools")
  hyp_df <- unreferenced_candidates(
    .make_cl_match(),
    rank_system = c("family", "genus", "species")
  )
  sc_df <- assign_scores(hyp_df, score_type = "similarity")
  res <- model_likelihoods(sc_df, model_params = .make_model_params_cl(),
                           rank_system = c("family", "genus", "species"))
  liks <- res$likelihoods
  expect_true(all(liks$score_method == "bivariate_normal"))
})

# ---- NA taxon_name exclusion ------------------------------------------------

test_that("compute_likelihoods excludes NA taxon_name for non-family hypotheses", {
  res  <- compute_likelihoods(.make_cl_match(), score_type = "none")
  liks <- res$likelihoods
  non_fam <- liks[liks$hypothesis_type != "unreferenced_family", ]
  expect_false(any(is.na(non_fam$taxon_name)))
})

# ---- include_unreferenced_family integration --------------------------------

test_that("include_unreferenced_family adds H4 rows to output", {
  res  <- compute_likelihoods(.make_cl_match(), score_type = "none",
                              include_unreferenced_family = TRUE)
  liks <- res$likelihoods
  expect_true("unreferenced_family" %in% liks$hypothesis_type)
})
