# Minimal model_params for testing (bypasses training)
.make_model_params <- function() {
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

# Minimal match object for one query
.make_match_df <- function() {
  data.frame(
    observation_id       = "ESV_001",
    score           = c(95.0, 80.0, 60.0),
    taxon_name      = c("Hybognathus nuchalis", "Rhinichthys obtusus", "Campostoma anomalum"),
    taxon_name_rank = "species",
    family          = "Leuciscidae",
    genus           = c("Hybognathus", "Rhinichthys", "Campostoma"),
    species         = c("Hybognathus nuchalis", "Rhinichthys obtusus", "Campostoma anomalum"),
    stringsAsFactors = FALSE
  )
}

# ---- .evaluate_one_query -----------------------------------------------------

test_that(".evaluate_one_query: returns required columns", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species")
  )
  expect_true(all(c("hypothesis_type", "taxon_name", "taxon_name_rank",
                     "likelihood_point_est", "likelihood_mean", "likelihood_sd")
                  %in% names(out)))
})

test_that(".evaluate_one_query: includes all three hypothesis types when ratio_threshold = 0", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  # With ratio_threshold = 0 all hypotheses are retained regardless of likelihood
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species"),
    ratio_threshold = 0
  )
  expect_true("specific_candidate" %in% out$hypothesis_type)
  expect_true("unreferenced_species"    %in% out$hypothesis_type)
  expect_true("unreferenced_genus"      %in% out$hypothesis_type)
})

test_that(".evaluate_one_query: likelihood_point_est in [0, 1]", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species")
  )
  expect_true(all(out$likelihood_point_est >= 0 & out$likelihood_point_est <= 1))
})

test_that(".evaluate_one_query: singleton uses 1D (no error)", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  single_row <- .make_match_df()[1L, ]
  expect_no_error(
    TaxaLikely:::.evaluate_one_query(single_row, params,
                                      c("family", "genus", "species"))
  )
})

test_that(".evaluate_one_query: n_sims > 0 produces non-zero sd", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  set.seed(42)
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species"),
    n_sims = 20L
  )
  spec <- out[out$hypothesis_type == "specific_candidate", ]
  # At least one specific candidate should have non-zero sd from simulation
  expect_true(any(spec$likelihood_sd > 0))
})

test_that(".evaluate_one_query: min_match_threshold filters low scores", {
  skip_if_not_installed("TaxaTools")
  params  <- .make_model_params()
  df_low  <- .make_match_df()
  df_low$score <- c(10, 5, 3)   # all below 0.5 after normalisation
  out <- TaxaLikely:::.evaluate_one_query(df_low, params,
                                           c("family", "genus", "species"),
                                           min_match_threshold = 0.5)
  spec <- out[out$hypothesis_type == "specific_candidate", ]
  # All H1 likelihoods should be 0, so they are filtered out
  expect_equal(nrow(spec), 0L)
})

# ---- evaluate_likelihoods ---------------------------------------------------

test_that("evaluate_likelihoods: returns list with $likelihoods and $unresolved", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  out    <- evaluate_likelihoods(.make_match_df(), params,
                                 c("family", "genus", "species"))
  expect_true(is.list(out))
  expect_named(out, c("likelihoods", "unresolved"))
  expect_true(is.data.frame(out$likelihoods))
  expect_true(is.data.frame(out$unresolved))
})

test_that("evaluate_likelihoods: $likelihoods has required columns", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  liks   <- evaluate_likelihoods(.make_match_df(), params,
                                 c("family", "genus", "species"))$likelihoods
  expect_true(all(c("observation_id","taxon_name","taxon_name_rank",
                     "hypothesis_type","likelihood_point_est",
                     "likelihood_mean","likelihood_sd") %in% names(liks)))
})

test_that("evaluate_likelihoods: processes multiple observation_ids", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  df2 <- rbind(.make_match_df(),
               dplyr::mutate(.make_match_df(), observation_id = "ESV_002"))
  liks <- evaluate_likelihoods(df2, params, c("family", "genus", "species"))$likelihoods
  expect_true(all(c("ESV_001", "ESV_002") %in% liks$observation_id))
})

test_that("evaluate_likelihoods: non-taxa_model_params errors", {
  expect_error(evaluate_likelihoods(.make_match_df(), list(), "species"),
               "taxa_model_params")
})

test_that("evaluate_likelihoods: $likelihoods has no NA taxon_name", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  liks   <- evaluate_likelihoods(.make_match_df(), params,
                                 c("family", "genus", "species"))$likelihoods
  expect_false(any(is.na(liks$taxon_name)))
})

test_that("evaluate_likelihoods: all-NA observation_id warns and appears in $unresolved", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  bad_df <- .make_match_df()
  bad_df$taxon_name <- NA_character_
  bad_df$genus      <- NA_character_
  bad_df$species    <- NA_character_
  bad_df$family     <- NA_character_
  expect_warning(
    evaluate_likelihoods(bad_df, params, c("family", "genus", "species")),
    "no usable likelihoods"
  )
  out <- suppressWarnings(
    evaluate_likelihoods(bad_df, params, c("family", "genus", "species"))
  )
  expect_true(nrow(out$unresolved) > 0L)
  expect_equal(nrow(out$likelihoods), 0L)
})

# ---- filter_top_hypotheses --------------------------------------------------

test_that("filter_top_hypotheses: removes coarser specific candidates", {
  df <- tibble::tibble(
    observation_id            = "ESV_001",
    taxon_name           = c("Hybognathus nuchalis", "Hybognathus", "NA"),
    taxon_name_rank      = c("species", "genus", NA_character_),
    hypothesis_type      = c("specific_candidate", "specific_candidate", "unreferenced_species"),
    likelihood_point_est = c(1.0, 0.9, 0.5),
    likelihood_mean      = c(1.0, 0.9, 0.5),
    likelihood_sd        = 0
  )
  out <- filter_top_hypotheses(df, c("family", "genus", "species"))
  spec <- out[out$hypothesis_type == "specific_candidate", ]
  # Genus-level candidate should be dropped (species is finest)
  expect_false("genus" %in% spec$taxon_name_rank)
  expect_true("species" %in% spec$taxon_name_rank)
})

test_that("filter_top_hypotheses: unreferenced_species/genus rows always kept", {
  df <- tibble::tibble(
    observation_id            = "ESV_001",
    taxon_name           = c("Hybognathus nuchalis", "Hybognathus", "Leuciscidae"),
    taxon_name_rank      = c("species", "genus", "family"),
    hypothesis_type      = c("specific_candidate", "unreferenced_species", "unreferenced_genus"),
    likelihood_point_est = c(1.0, 0.5, 0.1),
    likelihood_mean      = c(1.0, 0.5, 0.1),
    likelihood_sd        = 0
  )
  out <- filter_top_hypotheses(df, c("family", "genus", "species"))
  expect_true("unreferenced_species" %in% out$hypothesis_type)
  expect_true("unreferenced_genus"   %in% out$hypothesis_type)
})

test_that("filter_top_hypotheses: invalid input errors", {
  expect_error(filter_top_hypotheses(list(), "species"), "must be a data frame")
  expect_error(
    filter_top_hypotheses(data.frame(x = 1), "species"),
    "missing required columns"
  )
})
