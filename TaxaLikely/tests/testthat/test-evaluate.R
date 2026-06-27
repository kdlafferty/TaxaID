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
                     "score_likelihood", "score_likelihood_mean", "score_likelihood_sd",
                     "score_likelihood_cov")
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

test_that(".evaluate_one_query: score_likelihood in [0, 1]", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species")
  )
  expect_true(all(out$score_likelihood >= 0 & out$score_likelihood <= 1))
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
  expect_true(any(spec$score_likelihood_sd > 0))
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

test_that(".evaluate_one_query: score-only alpha filter rejects extreme outlier, retains near-mean", {
  # Session 121: outlier check is score-only (df=1 chi-sq), NOT 2D Mahalanobis.
  # Fixture: mu_score=4.5, H1_Sigma[1,1]=2.0 (from .make_model_params()).
  # Score 95 -> logit(0.95)=2.94 -> d_sq=(4.5-2.94)^2/2.0=1.22 -> p=0.27 >> 0.001 -> kept.
  # Score 50 -> logit(0.50)=0    -> d_sq=(4.5-0)^2/2.0=10.1  -> p=0.0015 > 0.001 -> kept at alpha=0.001.
  # Score 1  -> logit(~0.01)=-4.6-> d_sq=(4.5-(-4.6))^2/2.0=41.4 -> p<1e-10 << 0.001 -> dropped.
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()

  # Near-mean score: should survive alpha filter
  df_near <- .make_match_df()
  df_near$score <- c(95, 80, 60)   # top score logit(0.95)=2.94, close to mu=4.5
  out_near <- TaxaLikely:::.evaluate_one_query(df_near, params,
                                                c("family", "genus", "species"),
                                                ratio_threshold = 0, alpha = 0.001)
  spec_near <- out_near[out_near$hypothesis_type == "specific_candidate", ]
  expect_true(nrow(spec_near) > 0L)
  expect_true(any(spec_near$score_likelihood > 0))

  # Extreme outlier score: should be rejected by alpha filter.
  # Fixture mu_score=4.5, use_sigma[1,1]=2.0.
  # score=5 on 0-100 scale -> normalized 0.05 -> logit(0.05)=-2.94 ->
  # d_sq=(4.5-(-2.94))^2/2.0=27.7 -> p~=0 << 0.001 -> alpha rejects.
  df_far <- .make_match_df()
  df_far$score <- c(5, 3, 1)   # 0-100 scale; ~5% identity — extreme outlier
  out_far <- TaxaLikely:::.evaluate_one_query(df_far, params,
                                               c("family", "genus", "species"),
                                               ratio_threshold = 0, alpha = 0.001,
                                               min_match_threshold = 0)
  spec_far <- out_far[out_far$hypothesis_type == "specific_candidate", ]
  # All H1 candidates should have likelihood 0 (alpha filter rejects them)
  expect_true(all(spec_far$score_likelihood == 0))
})

test_that(".evaluate_one_query: alpha filter uses score only, not gap (small-gap candidate retained)", {
  # A legitimate H1 candidate may have a tiny gap (confusable congener present) but a
  # reasonable score. The outlier filter must NOT reject it based on the gap — only the
  # score dimension is tested. Verify by providing a scenario where the 2D Mahalanobis
  # would reject but the score-only test passes.
  # Fixture: mu_score=4.5, mu_gap=2.0, H1_Sigma=[[2,0.2],[0.2,1]].
  # Score 95 (logit=2.94): 1D d_sq=1.22 -> p=0.27 -> passes at any reasonable alpha.
  # Gap 0.01 (logit=~0.01): extremely small, far below mu_gap=2.0.
  # If gap were included: 2D d_sq would be much larger and could exceed threshold.
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  df_tinygap <- .make_match_df()
  # Scores 95.0 and 94.9 give a tiny gap in logit space (~0.02 logit units)
  df_tinygap$score <- c(95.0, 94.9, 60.0)
  out <- TaxaLikely:::.evaluate_one_query(df_tinygap, params,
                                           c("family", "genus", "species"),
                                           ratio_threshold = 0, alpha = 0.001)
  spec <- out[out$hypothesis_type == "specific_candidate" &
                out$taxon_name == "Hybognathus nuchalis", ]
  # Despite the tiny gap, the H1 candidate should survive the outlier filter
  expect_true(nrow(spec) > 0L)
  expect_true(any(spec$score_likelihood > 0))
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
                     "hypothesis_type","score_likelihood",
                     "score_likelihood_mean","score_likelihood_sd",
                     "score_likelihood_cov") %in% names(liks)))
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

# (trivariate coverage path removed — coverage used as filter only)

# ---- score_likelihood_cov ---------------------------------------------------

test_that("score_likelihood_cov equals score_likelihood when no coverage column", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  out    <- evaluate_likelihoods(.make_match_df(), params,
                                 c("family", "genus", "species"))$likelihoods
  # No coverage column in match_df -> no inflation -> columns must be identical
  expect_equal(out$score_likelihood_cov, out$score_likelihood)
})

test_that("score_likelihood_cov differs from score_likelihood for low-coverage H1", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  df_cov <- .make_match_df()
  # First candidate (best H1) gets very low coverage; others at full coverage
  df_cov$coverage <- c(0.3, 1.0, 1.0)
  out <- evaluate_likelihoods(df_cov, params,
                              c("family", "genus", "species"))$likelihoods
  h1_rows <- out[out$hypothesis_type == "specific_candidate", ]
  # At least the best H1 candidate should be penalised (cov value differs from 1)
  expect_false(isTRUE(all.equal(h1_rows$score_likelihood_cov,
                                h1_rows$score_likelihood)))
  # score_likelihood_cov in [0, 1]
  expect_true(all(out$score_likelihood_cov >= 0 & out$score_likelihood_cov <= 1))
})

# ---- filter_top_hypotheses --------------------------------------------------

test_that("filter_top_hypotheses: removes coarser specific candidates", {
  df <- tibble::tibble(
    observation_id            = "ESV_001",
    taxon_name           = c("Hybognathus nuchalis", "Hybognathus", "NA"),
    taxon_name_rank      = c("species", "genus", NA_character_),
    hypothesis_type      = c("specific_candidate", "specific_candidate", "unreferenced_species"),
    score_likelihood = c(1.0, 0.9, 0.5),
    score_likelihood_mean      = c(1.0, 0.9, 0.5),
    score_likelihood_sd        = 0
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
    score_likelihood = c(1.0, 0.5, 0.1),
    score_likelihood_mean      = c(1.0, 0.5, 0.1),
    score_likelihood_sd        = 0
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

# ---- filter_top_hypotheses: is_restored behaviour ---------------------------

test_that("filter_top_hypotheses: preserves genus row when all species rows are restored", {
  # Simulates a post-LCA observation: genus-level BLAST hit + restored species rows
  df <- tibble::tibble(
    observation_id   = "ESV_001",
    taxon_name       = c("Girella", "Girella simplicidens", "Girella japonica"),
    taxon_name_rank  = c("genus", "species", "species"),
    hypothesis_type  = "specific_candidate",
    score_likelihood = c(0.9, 0.8, 0.7),
    score_likelihood_mean = c(0.9, 0.8, 0.7),
    score_likelihood_sd   = 0,
    is_restored      = c(FALSE, TRUE, TRUE)   # genus original; species restored
  )
  out  <- filter_top_hypotheses(df, c("family", "genus", "species"))
  spec <- out[out$hypothesis_type == "specific_candidate", ]

  # Genus row should be kept (all species rows were restored)
  expect_true("genus" %in% spec$taxon_name_rank)
  expect_true("Girella" %in% spec$taxon_name)
})

test_that("filter_top_hypotheses: drops all-restored species rows when genus row is preserved", {
  df <- tibble::tibble(
    observation_id   = "ESV_001",
    taxon_name       = c("Girella", "Girella simplicidens", "Girella japonica"),
    taxon_name_rank  = c("genus", "species", "species"),
    hypothesis_type  = "specific_candidate",
    score_likelihood = c(0.9, 0.8, 0.7),
    score_likelihood_mean = c(0.9, 0.8, 0.7),
    score_likelihood_sd   = 0,
    is_restored      = c(FALSE, TRUE, TRUE)
  )
  out  <- filter_top_hypotheses(df, c("family", "genus", "species"))
  spec <- out[out$hypothesis_type == "specific_candidate", ]

  # All-restored species rows should be gone (covered by genus expansion)
  expect_false("Girella simplicidens" %in% spec$taxon_name)
  expect_false("Girella japonica"     %in% spec$taxon_name)
})

test_that("filter_top_hypotheses: does not preserve genus row when any species row is original", {
  # One species row is an original BLAST hit (is_restored = FALSE)
  df <- tibble::tibble(
    observation_id   = "ESV_001",
    taxon_name       = c("Girella", "Girella nigricans", "Girella simplicidens"),
    taxon_name_rank  = c("genus", "species", "species"),
    hypothesis_type  = "specific_candidate",
    score_likelihood = c(0.9, 1.0, 0.8),
    score_likelihood_mean = c(0.9, 1.0, 0.8),
    score_likelihood_sd   = 0,
    is_restored      = c(FALSE, FALSE, TRUE)   # G. nigricans is original
  )
  out  <- filter_top_hypotheses(df, c("family", "genus", "species"))
  spec <- out[out$hypothesis_type == "specific_candidate", ]

  # Genus row should be dropped (G. nigricans is not restored → existing behaviour)
  expect_false("genus" %in% spec$taxon_name_rank)
  # Both species rows should be kept
  expect_true("Girella nigricans"    %in% spec$taxon_name)
  expect_true("Girella simplicidens" %in% spec$taxon_name)
})

test_that("filter_top_hypotheses: is_restored absent → existing behaviour unchanged", {
  # No is_restored column: genus row should be dropped as before
  df <- tibble::tibble(
    observation_id   = "ESV_001",
    taxon_name       = c("Girella", "Girella simplicidens"),
    taxon_name_rank  = c("genus", "species"),
    hypothesis_type  = "specific_candidate",
    score_likelihood = c(0.9, 0.8),
    score_likelihood_mean = c(0.9, 0.8),
    score_likelihood_sd   = 0
    # no is_restored column
  )
  out  <- filter_top_hypotheses(df, c("family", "genus", "species"))
  spec <- out[out$hypothesis_type == "specific_candidate", ]

  expect_false("genus"   %in% spec$taxon_name_rank)
  expect_true("species"  %in% spec$taxon_name_rank)
})
