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

test_that(".evaluate_one_query: n_sims sd reflects reference sample size (n_obs_species), not query resampling", {
  # Session 157: score_likelihood_sd is redesigned to represent uncertainty in
  # the TRAINED MEAN (driven by how much reference data calibrated it), not a
  # resampling of the observed score. Two models identical except
  # n_obs_species for the matched species: the poorly-referenced one (n=3)
  # must show a LARGER sd than the well-referenced one (n=300), for the exact
  # same observed data.
  #
  # Uses a CLOSE two-way competition (90 vs 88, not .make_match_df()'s default
  # dominant 95 vs 80/60): when one candidate wins every single simulation
  # regardless of how its mean is perturbed, its normalized ratio is pinned at
  # exactly 1.0 (score_likelihood_sd = 0) either way, since normalization is
  # by the per-simulation max -- a real structural property of the ratio, not
  # a defect, but it means a dominant winner can never show this effect. A
  # close competition lets the winner occasionally flip, which is what
  # actually exposes the underlying mean uncertainty in the normalized output.
  skip_if_not_installed("TaxaTools")
  close_match_df <- .make_match_df()
  close_match_df$score <- c(90.0, 88.0, 60.0)

  params_low_n  <- .make_model_params()
  params_low_n$H1_Lookup$n_obs_species  <- 3
  params_low_n$Stats <- list(n_h1_pooled = 3, n_h2_pooled = NA_real_)

  params_high_n <- .make_model_params()
  params_high_n$H1_Lookup$n_obs_species <- 300
  params_high_n$Stats <- list(n_h1_pooled = 300, n_h2_pooled = NA_real_)

  set.seed(1)
  out_low_n <- TaxaLikely:::.evaluate_one_query(
    close_match_df, params_low_n, c("family", "genus", "species"),
    n_sims = 1000L, ratio_threshold = 0, min_match_threshold = 0
  )
  set.seed(1)
  out_high_n <- TaxaLikely:::.evaluate_one_query(
    close_match_df, params_high_n, c("family", "genus", "species"),
    n_sims = 1000L, ratio_threshold = 0, min_match_threshold = 0
  )

  sd_low_n  <- out_low_n[out_low_n$taxon_name == "Hybognathus nuchalis", "score_likelihood_sd"]
  sd_high_n <- out_high_n[out_high_n$taxon_name == "Hybognathus nuchalis", "score_likelihood_sd"]
  expect_true(sd_low_n > sd_high_n)
})

test_that(".evaluate_one_query: n_sims sd falls back to legacy (score-resampling) behavior when n_obs_species is absent", {
  # model_params trained before this session has no n_obs_species column at
  # all -- must reproduce the pre-existing behavior exactly (non-zero sd from
  # resampling the observed score), not silently produce sd = 0.
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  expect_false("n_obs_species" %in% names(params$H1_Lookup))
  set.seed(42)
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species"),
    n_sims = 20L
  )
  spec <- out[out$hypothesis_type == "specific_candidate", ]
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
  df_far$score <- c(5, 3, 1)   # 0-100 scale; ~5% identity -- extreme outlier
  out_far <- TaxaLikely:::.evaluate_one_query(df_far, params,
                                               c("family", "genus", "species"),
                                               ratio_threshold = 0, alpha = 0.001,
                                               min_match_threshold = 0)
  spec_far <- out_far[out_far$hypothesis_type == "specific_candidate", ]
  # All H1 candidates should have likelihood 0 (alpha filter rejects them)
  expect_true(all(spec_far$score_likelihood == 0))
})

test_that(".evaluate_one_query: alpha filter is one-sided -- an anomalously HIGH score is never rejected", {
  # Statistical-critique fix: the alpha gate used to be a two-sided chi-sq
  # test, which could hard-zero H1 for a query anomalously CLOSE to a perfect
  # match -- incoherent, since H2/H3's means sit below H1's by construction,
  # so a high score fits every alternative hypothesis strictly worse, not
  # better. Verify the high side is never rejected regardless of how far
  # above mu_score the query sits, while the low side (already covered above)
  # is unaffected.
  # Fixture: mu_score=4.5, H1_Sigma[1,1]=2.0 (sd ~= 1.414).
  # Score 99.999 -> logit(0.99999) ~= 11.51 -> ~4.96 SD ABOVE mu_score.
  # Old two-sided test: p ~= 7e-7 << 0.001 -> would have been rejected.
  # New one-sided (low-side-only) test: p_val_low_side = pnorm(4.96) ~= 1 -> retained.
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  df_high <- .make_match_df()
  df_high$score <- c(99.999, 80.0, 60.0)
  out_high <- TaxaLikely:::.evaluate_one_query(df_high, params,
                                                c("family", "genus", "species"),
                                                ratio_threshold = 0, alpha = 0.001)
  spec_high <- out_high[out_high$hypothesis_type == "specific_candidate" &
                           out_high$taxon_name == "Hybognathus nuchalis", ]
  expect_true(nrow(spec_high) > 0L)
  expect_true(any(spec_high$score_likelihood > 0))
})

test_that(".evaluate_one_query: alpha filter uses score only, not gap (small-gap candidate retained)", {
  # A legitimate H1 candidate may have a tiny gap (confusable congener present) but a
  # reasonable score. The outlier filter must NOT reject it based on the gap -- only the
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

test_that("evaluate_likelihoods: evidence_col works (no error) on a sqrt_mismatch model too (Session 158, corrected)", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  params$Score_Transform <- "sqrt_mismatch"
  df <- .make_match_df()
  df$depth <- 10
  expect_no_error(
    evaluate_likelihoods(df, params, c("family", "genus", "species"), evidence_col = "depth")
  )
})

test_that("evaluate_likelihoods: min_coverage works (no error) on a sqrt_mismatch model too (Session 158, corrected)", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  params$Score_Transform <- "sqrt_mismatch"
  df <- .make_match_df()
  df$coverage <- 0.9
  expect_no_error(
    evaluate_likelihoods(df, params, c("family", "genus", "species"), min_coverage = 0.5)
  )
})

test_that("evaluate_likelihoods: warns (not silent) when Score_Transform is absent from model_params", {
  # Statistical-critique fix: silently defaulting an absent Score_Transform to
  # "logit" is exactly the mechanism that let a stale/orphaned model object
  # (no Score_Transform field at all, from before Session 158) stay dangerous
  # with no signal to the caller. Now warns instead.
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()  # Score_Transform absent
  df <- .make_match_df()
  expect_warning(
    evaluate_likelihoods(df, params, c("family", "genus", "species")),
    "Score_Transform"
  )
})

test_that("evaluate_likelihoods: no Score_Transform warning when it is explicitly set", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()
  params$Score_Transform <- "logit"
  df <- .make_match_df()
  expect_no_warning(
    evaluate_likelihoods(df, params, c("family", "genus", "species"))
  )
  params$Score_Transform <- "sqrt_mismatch"
  expect_no_warning(
    evaluate_likelihoods(df, params, c("family", "genus", "species"))
  )
})

test_that("evaluate_likelihoods: evidence_col/min_coverage guards do not fire for a logit model", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()  # Score_Transform absent -> defaults to logit
  df <- .make_match_df()
  df$depth <- 10
  expect_no_error(
    evaluate_likelihoods(df, params, c("family", "genus", "species"), evidence_col = "depth")
  )
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

# (trivariate coverage path removed -- coverage used as filter only)

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

# ---- score_likelihood_evidence: crossover gate -------------------------------
#
# Session 156: the evidence-based sigma rescale only applies when doing so is
# provably non-decreasing for the candidate's own H1 density (see
# evaluate_likelihoods()'s "Evidence-based sigma rescaling" @details section
# for the derivation). These fixtures use .make_model_params()'s
# mu_score = 4.5, H1_Sigma[1,1] = 2.0, and a Query_Calibration$reference_evidence
# of 10, giving evidence_ratio = 0.1 (var_scale = 1/sqrt(0.1) = 3.162,
# z*^2 = log(3.162)/(1-1/3.162) = 1.68) for a depth of 1.

.add_query_calibration <- function(params, reference_evidence) {
  params$Query_Calibration <- list(reference_evidence = reference_evidence)
  params
}

test_that("score_likelihood_evidence: gate blocks the rescale for a near-mean low-evidence candidate", {
  skip_if_not_installed("TaxaTools")
  params  <- .add_query_calibration(.make_model_params(), reference_evidence = 10)
  df_near <- .make_match_df()
  df_near$depth <- c(1, 10, 10)   # top candidate: evidence_ratio = 1/10 = 0.1
  # Top candidate score 95 -> logit(0.95)=2.94, z^2 = (4.5-2.94)^2/2.0 = 1.21,
  # below z*^2 = 1.68 -- the gate must leave sigma (and thus the likelihood)
  # unchanged even though evidence_ratio < 1.
  out <- evaluate_likelihoods(df_near, params, c("family", "genus", "species"),
                              ratio_threshold = 0, evidence_col = "depth")$likelihoods
  h1 <- out[out$hypothesis_type == "specific_candidate" &
              out$taxon_name == "Hybognathus nuchalis", ]
  expect_equal(h1$score_likelihood_evidence, h1$score_likelihood)
})

test_that("score_likelihood_evidence: gate allows the rescale for a far low-evidence candidate", {
  skip_if_not_installed("TaxaTools")
  params <- .add_query_calibration(.make_model_params(), reference_evidence = 10)
  df_far <- .make_match_df()
  df_far$score <- c(75, 50, 30)   # top candidate score logit(0.75)=1.10
  df_far$depth <- c(1, 10, 10)    # top candidate: evidence_ratio = 0.1
  # z^2 = (4.5-1.10)^2/2.0 = 5.79, above z*^2 = 1.68 -- the gate must apply
  # the widened sigma, so the two columns differ for this candidate.
  out <- evaluate_likelihoods(df_far, params, c("family", "genus", "species"),
                              ratio_threshold = 0, min_match_threshold = 0,
                              evidence_col = "depth")$likelihoods
  h1 <- out[out$hypothesis_type == "specific_candidate" &
              out$taxon_name == "Hybognathus nuchalis", ]
  expect_false(isTRUE(all.equal(h1$score_likelihood_evidence, h1$score_likelihood)))
})

test_that("score_likelihood_evidence equals score_likelihood when evidence_col is absent", {
  skip_if_not_installed("TaxaTools")
  params <- .add_query_calibration(.make_model_params(), reference_evidence = 10)
  out <- evaluate_likelihoods(.make_match_df(), params,
                              c("family", "genus", "species"))$likelihoods
  expect_equal(out$score_likelihood_evidence, out$score_likelihood)
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

  # Genus row should be dropped (G. nigricans is not restored -> existing behaviour)
  expect_false("genus" %in% spec$taxon_name_rank)
  # Both species rows should be kept
  expect_true("Girella nigricans"    %in% spec$taxon_name)
  expect_true("Girella simplicidens" %in% spec$taxon_name)
})

test_that("filter_top_hypotheses: is_restored absent -> existing behaviour unchanged", {
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

# ---- H2_Lookup: per-genus delta at inference time ----------------------------
#
# .make_match_df()'s best-scoring candidate is "Hybognathus nuchalis"
# (genus "Hybognathus", score 95). These tests attach an H2_Lookup entry for
# that genus to .make_model_params()'s output and confirm .evaluate_one_query()
# prefers it over the pooled global H2$delta = 3.0.

.add_h2_lookup <- function(params, genus, delta_shrunk, n_pairs = 5L) {
  params$H2_Lookup <- data.frame(
    genus = genus, n_pairs = n_pairs, delta_shrunk = delta_shrunk,
    stringsAsFactors = FALSE
  )
  params
}

test_that(".evaluate_one_query: uses genus-specific delta when anchor's genus is in H2_Lookup", {
  skip_if_not_installed("TaxaTools")
  params <- .add_h2_lookup(.make_model_params(), "Hybognathus", delta_shrunk = 1.0)
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species"),
    ratio_threshold = 0
  )
  h2_row <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(h2_row$h2_delta_source, "genus_specific")
})

test_that(".evaluate_one_query: falls back to global delta when anchor's genus is absent from H2_Lookup", {
  skip_if_not_installed("TaxaTools")
  params <- .add_h2_lookup(.make_model_params(), "SomeOtherGenus", delta_shrunk = 1.0)
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species"),
    ratio_threshold = 0
  )
  h2_row <- out[out$hypothesis_type == "unreferenced_species", ]
  h3_row <- out[out$hypothesis_type == "unreferenced_genus", ]
  expect_equal(h2_row$h2_delta_source, "global_fallback")
  expect_equal(h3_row$h2_delta_source, "global_fallback")
})

test_that(".evaluate_one_query: model_params without H2_Lookup slot falls back cleanly (backward compatibility)", {
  skip_if_not_installed("TaxaTools")
  params <- .make_model_params()   # no $H2_Lookup element at all
  expect_null(params$H2_Lookup)
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species"),
    ratio_threshold = 0
  )
  h2_row <- out[out$hypothesis_type == "unreferenced_species", ]
  expect_equal(h2_row$h2_delta_source, "global_fallback")
})

test_that(".evaluate_one_query: H2 sd reflects n_pairs behind its genus-specific delta (unreferenced taxa get more uncertainty)", {
  # Session 157: H2/H3 borrow rather than directly observe -- a genus-specific
  # delta backed by few congener pairs must produce a WIDER unreferenced_species
  # sd than one backed by many, for the same observed data.
  skip_if_not_installed("TaxaTools")
  base <- .make_model_params()
  base$H1_Lookup$n_obs_species <- 50
  base$Stats <- list(n_h1_pooled = 50, n_h2_pooled = NA_real_)

  params_low_pairs  <- .add_h2_lookup(base, "Hybognathus", delta_shrunk = 2.0, n_pairs = 2L)
  params_high_pairs <- .add_h2_lookup(base, "Hybognathus", delta_shrunk = 2.0, n_pairs = 500L)

  set.seed(7)
  out_low <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params_low_pairs, c("family", "genus", "species"),
    n_sims = 500L, ratio_threshold = 0
  )
  set.seed(7)
  out_high <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params_high_pairs, c("family", "genus", "species"),
    n_sims = 500L, ratio_threshold = 0
  )

  sd_low  <- out_low[out_low$hypothesis_type == "unreferenced_species", "score_likelihood_sd"]
  sd_high <- out_high[out_high$hypothesis_type == "unreferenced_species", "score_likelihood_sd"]
  expect_true(sd_low > sd_high)
})

test_that(".evaluate_one_query: specific_candidate rows carry NA h2_delta_source", {
  skip_if_not_installed("TaxaTools")
  params <- .add_h2_lookup(.make_model_params(), "Hybognathus", delta_shrunk = 1.0)
  out <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params, c("family", "genus", "species"),
    ratio_threshold = 0
  )
  spec <- out[out$hypothesis_type == "specific_candidate", ]
  expect_true(all(is.na(spec$h2_delta_source)))
})

test_that(".evaluate_one_query: a smaller genus-specific delta raises H2 likelihood relative to the global fallback", {
  skip_if_not_installed("TaxaTools")
  # H2$delta = 3.0 (global, from .make_model_params()); a genus-specific
  # delta of 1.0 shifts the H2 mean much closer to the observed top score,
  # so the H2 density -- and hence score_likelihood -- should be higher than
  # under the pooled global delta alone.
  params_global <- .make_model_params()
  params_local  <- .add_h2_lookup(.make_model_params(), "Hybognathus", delta_shrunk = 1.0)

  out_global <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params_global, c("family", "genus", "species"),
    ratio_threshold = 0
  )
  out_local <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params_local, c("family", "genus", "species"),
    ratio_threshold = 0
  )

  h2_global <- out_global$score_likelihood[out_global$hypothesis_type == "unreferenced_species"]
  h2_local  <- out_local$score_likelihood[out_local$hypothesis_type == "unreferenced_species"]
  expect_gt(h2_local, h2_global)
})

test_that(".evaluate_one_query: H2 mean anchors on the ANCHOR SPECIES' own resolved mean, not the population-wide global mean (Session 158)", {
  # A referenced species whose own trained mean differs from H1_Global_Mu is
  # real information about how conserved/variable that specific lineage is --
  # H2 (unreferenced sister species) should inherit it. Two models identical
  # except the anchor's own species-specific mu_score; H1_Global_Mu and
  # h2_delta held fixed. If H2 anchors on the SPECIES mean (fixed behavior),
  # moving the species mean further from the observed query changes H2's
  # likelihood. If it still anchored on H1_Global_Mu (old behavior), the two
  # would be identical, since nothing about the global mean changed.
  skip_if_not_installed("TaxaTools")
  params_near <- .make_model_params()
  params_near$H1_Lookup$mu_score <- 4.5   # observed query logit ~2.94; anchor at 4.5-3.0=1.5
  params_far  <- .make_model_params()
  params_far$H1_Lookup$mu_score  <- 8.0   # same delta shifts anchor to 8.0-3.0=5.0, farther from 2.94

  out_near <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params_near, c("family", "genus", "species"), ratio_threshold = 0
  )
  out_far <- TaxaLikely:::.evaluate_one_query(
    .make_match_df(), params_far, c("family", "genus", "species"), ratio_threshold = 0
  )

  h2_near <- out_near$score_likelihood[out_near$hypothesis_type == "unreferenced_species"]
  h2_far  <- out_far$score_likelihood[out_far$hypothesis_type == "unreferenced_species"]
  # Both scenarios share the identical H1_Global_Mu -- a difference here can
  # only come from anchoring on the (deliberately varied) species mean.
  expect_false(isTRUE(all.equal(h2_near, h2_far)))
  expect_gt(h2_near, h2_far)
})
