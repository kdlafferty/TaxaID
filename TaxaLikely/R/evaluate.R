utils::globalVariables(c(
  "p_med", "p_b", "score_logit", "gap_logit", "p_norm",
  "raw_likelihood", "raw_likelihood_cov", "raw_likelihood_evidence",
  "score_likelihood", "score_likelihood_mean", "score_likelihood_sd",
  "score_likelihood_cov", "score_likelihood_evidence",
  "hypothesis_type", "taxon_name", "taxon_name_rank",
  "observation_id", "Query_ID",
  ".data", "rank_score", "best_rank_score",
  "coverage",
  "is_restored", ".genus", ".all_restored", "h2_delta_source",
  "species_confusion_risk", "genus_confusion_risk", "family_confusion_risk",
  "own_rank_confusion_risk"
))

# ==============================================================================
# MODULE D: INFERENCE
# ==============================================================================

#' Evaluate H1/H2/H3 likelihoods for a single query
#'
#' Core inference function.  Given one query's candidate rows and a trained
#' model, computes likelihood ratios for:
#' * **H1 (specific_candidate):** a known species present in the reference DB.
#' * **H2 (unreferenced_species):** an unsampled species in a represented genus.
#' * **H3 (unreferenced_genus):** an unsampled species in an unrepresented genus.
#'
#' Uses a 2D bivariate normal over `(score_logit, gap_logit)` unless there is
#' only one candidate taxon, in which case a 1D normal over `score_logit` only
#' is used (gap is artificial when no competitor exists).
#'
#' @param candidate_df Data frame of match rows for **one** `observation_id`.
#'   Required columns: `taxon_name`, `score`.  Taxonomy columns matching
#'   `rank_system` are used for hierarchical lookup fallback and for deriving
#'   H2/H3 taxon labels via `TaxaTools::create_taxon_names()`.
#' @param model_params Named list of class `"taxa_model_params"` returned by
#'   [train_likelihood_model()].
#' @param rank_system Character vector of rank names **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`).
#' @param ratio_threshold Numeric (default `0.01`).  Minimum likelihood ratio
#'   relative to the best hypothesis; specific candidates below this are dropped.
#' @param min_match_threshold Numeric (default `0.50`).  Raw score below which
#'   a candidate receives likelihood 0 regardless of the model prediction.
#' @param alpha Numeric (default `0.001`).  Score-outlier p-value cutoff, ONE-SIDED
#'   (low side only): H1 candidates whose query score is anomalously LOW relative to the
#'   species' own score distribution (univariate normal) receive likelihood 0.  An
#'   anomalously HIGH score (e.g. a literal 100% match) is never rejected by this test --
#'   H2/H3 model missing-species/genus hypotheses via a leftward shift of H1's own mean,
#'   so a score far ABOVE H1's mean fits every alternative hypothesis strictly worse, not
#'   better; there is no hypothesis for a rejected H1 to hand its likelihood mass to that
#'   explains a near-perfect match. (Prior to this being made one-sided, the test was
#'   two-sided and could hard-zero H1 for exactly the evidence that most strongly supports
#'   it -- see `train_likelihood_model()`'s "Non-monotonic score->likelihood shape"
#'   section for the analysis that found this.) The gap feature is NOT included in this
#'   test -- a small gap (confusable congener present) correctly lowers the bivariate H1
#'   density but should not cause the candidate to be rejected as an outlier.  The default
#'   0.001 (1-in-1000 threshold, ~3.3 sigma on the low side) drops genuinely inconsistent
#'   cross-family BLAST hits (e.g. freshwater taxa at 91-93% in a marine sample) while
#'   retaining legitimate borderline H1s (e.g. a coastal species at 99% with a tight
#'   per-species distribution).  H1-intrinsic: no comparison to H2/H3 densities.
#' @param n_sims Integer (default `0`).  Number of Monte Carlo simulations for
#'   `score_likelihood_mean` and `score_likelihood_sd`.  `0` = deterministic only.
#' @param score_bounds Optional `c(min, max)` for score normalization.
#' @param logit_epsilon Logit clipping value (default `1e-4`).
#' @param max_gap_ceiling Gap cap (default `5.0`).  Caps gap at 5 logit units
#'   (roughly the gap between 99.3% and 50% identity) to prevent extreme
#'   outliers from dominating model estimates.
#' @param min_coverage Numeric or `NULL`.  When not `NULL` and a `coverage`
#'   column is present in `candidate_df`, candidate rows whose coverage is
#'   below this threshold are dropped before score aggregation.  See
#'   [evaluate_likelihoods()] for details.
#' @return A data frame with columns `hypothesis_type`, `taxon_name`,
#'   `taxon_name_rank`, `score_likelihood`, `score_likelihood_mean`,
#'   `score_likelihood_sd`, `score_likelihood_cov`, `h2_delta_source`
#'   (`"genus_specific"` or `"global_fallback"` for `unreferenced_species`/
#'   `unreferenced_genus` rows; `NA` for `specific_candidate` rows),
#'   sorted by `score_likelihood_mean` descending.
#'
#' @noRd
.evaluate_one_query <- function(candidate_df,
                                model_params,
                                rank_system,
                                ratio_threshold        = 0.01,
                                min_match_threshold    = 0.50,
                                alpha                  = 0.001,
                                n_sims                 = 0,
                                score_bounds           = NULL,
                                logit_epsilon          = 1e-4,
                                max_gap_ceiling        = NULL,
                                min_coverage           = NULL,
                                evidence_col           = NULL,
                                evidence_max_ratio     = 1,
                                verbose                = FALSE) {

  names(candidate_df) <- tolower(names(candidate_df))
  rank_cols <- tolower(rank_system)    # coarse to fine
  # Rank immediately coarser than the finest (species) -- genus, by this
  # package's rank_system convention. Used to look up a genus-specific H2
  # delta in model_params$H2_Lookup when available.
  genus_rank_col <- if (length(rank_cols) >= 2L) rank_cols[length(rank_cols) - 1L] else NA_character_
  # Rank two coarser than the finest -- family, by convention. Used for the
  # genus_confusion_risk/family_confusion_risk columns (see
  # model_params$Confusion_Risk_Curves and .lookup_confusion_risk_value()).
  family_rank_col <- if (length(rank_cols) >= 3L) rank_cols[length(rank_cols) - 2L] else NA_character_

  score_col <- if ("p_match"        %in% names(candidate_df)) "p_match" else
    if ("score_original" %in% names(candidate_df)) "score_original" else
    if ("score"          %in% names(candidate_df)) "score" else
      stop("candidate_df must have a 'score_original', 'score', or 'p_match' column")

  # ---- 0. COVERAGE FILTER (optional) ----------------------------------------
  # Drop candidates whose alignment/detection coverage is below min_coverage.
  # This implements the qcovs pre-filter for DNA (analogous to galaxy-tool-lca),
  # and the bbox-area pre-filter for images, without changing the model itself.
  # NA coverage is treated as fully covered (1.0) -- no penalty for missing data.
  if (!is.null(min_coverage) && "coverage" %in% names(candidate_df)) {
    cov_vals <- candidate_df[["coverage"]]
    keep <- is.na(cov_vals) | cov_vals >= min_coverage
    n_dropped <- sum(!keep)
    if (n_dropped > 0L) {
      candidate_df <- candidate_df[keep, , drop = FALSE]
      if (verbose) {
        message(sprintf("  Coverage filter (>= %.2f): dropped %d candidate row(s)",
                        min_coverage, n_dropped))
      }
    }
  }

  # Score transform (Session 158): read from the model itself rather than
  # requiring the caller to track/re-supply it -- a model trained with
  # score_transform = "sqrt_mismatch" must be evaluated with the identical
  # transform, since H1/H2/H3 are compared via density ratios at one shared
  # point (see train_likelihood_model()'s own score_transform documentation).
  # Absent for any model trained before this parameter existed -> "logit",
  # its original and only behavior -- but a SILENT fallback here is exactly
  # the mechanism that let a stale, undocumented-transform model object stay
  # dangerous (found during the statistical-critique session that produced
  # train_likelihood_model()'s "Non-monotonic score->likelihood shape"
  # section: a real cached model with no Score_Transform field at all was
  # silently read as "logit", the more fragile of the two transforms, with
  # no signal to the caller that this had happened). Now warns instead of
  # defaulting silently, so a caller inspecting an old/orphaned model_params
  # object gets a visible prompt to check whether it should be retrained.
  if (is.null(model_params$Score_Transform)) {
    warning(paste0(
      "model_params has no Score_Transform field -- this model predates ",
      "score_transform tracking (added Session 158) and is being evaluated as ",
      "\"logit\", its original and only behavior. logit's near-100%-identity region is ",
      "the fragile one (unbounded scale, position set by logit_epsilon rather than real ",
      "data -- see train_likelihood_model()'s \"Non-monotonic score->likelihood shape\" ",
      "section); if this model is stale, consider retraining with ",
      "train_likelihood_model(score_transform = \"sqrt_mismatch\") instead."
    ), call. = FALSE)
  }
  score_transform <- model_params$Score_Transform %||% "logit"
  max_gap_ceiling <- .resolve_gap_ceiling(max_gap_ceiling, score_transform)

  global_mu    <- as.numeric(model_params$H1_Global_Mu)
  global_sigma <- as.matrix(model_params$H1_Sigma)
  dimnames(global_sigma) <- list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit"))
  model_sd_score <- sqrt(global_sigma[1L, 1L])

  h2_delta <- model_params$H2$delta
  h3_delta <- model_params$H3$delta
  h2_sigma <- as.matrix(model_params$H2$sigma)
  h3_sigma <- as.matrix(model_params$H3$sigma)
  dimnames(h2_sigma) <- list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit"))
  dimnames(h3_sigma) <- list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit"))

  # ---- 1. FEATURE PREP: median score per taxon_name --------------------------
  existing_rank_cols <- intersect(rank_cols, names(candidate_df))

  cand <- candidate_df |>
    dplyr::mutate(p_norm = .normalize_scores(.data[[score_col]],
                                             bounds = score_bounds)) |>
    dplyr::group_by(taxon_name) |>
    dplyr::summarise(
      p_med = stats::median(p_norm, na.rm = TRUE),
      dplyr::across(dplyr::any_of("coverage"),
                    ~ stats::median(.x, na.rm = TRUE)),
      dplyr::across(dplyr::any_of(evidence_col),
                    ~ stats::median(.x, na.rm = TRUE)),
      dplyr::across(dplyr::any_of(existing_rank_cols), dplyr::first),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      score_logit = .transform_p(p_med, score_transform, logit_epsilon)
    )

  if (nrow(cand) == 0L) {
    return(data.frame(
      hypothesis_type          = character(0),
      taxon_name               = character(0),
      taxon_name_rank          = character(0),
      raw_likelihood           = numeric(0),
      raw_likelihood_cov       = numeric(0),
      raw_likelihood_evidence  = numeric(0),
      score_likelihood         = numeric(0),
      score_likelihood_mean    = numeric(0),
      score_likelihood_sd      = numeric(0),
      score_likelihood_cov     = numeric(0),
      score_likelihood_evidence = numeric(0),
      species_confusion_risk          = numeric(0),
      genus_confusion_risk            = numeric(0),
      family_confusion_risk           = numeric(0),
      own_rank_confusion_risk         = numeric(0),
      stringsAsFactors         = FALSE
    ))
  }

  is_singleton <- nrow(cand) == 1L
  if (is_singleton) {
    # Single-candidate queries use 1D mode with artificial max gap.
    # H2/H3 likelihoods may be inflated relative to H1 because the gap
    # dimension (which normally separates H1 from H2/H3) is uninformative.
    # Interpret H2/H3 results with caution for singleton queries.
  }

  # ---- 2. GAP PER CANDIDATE (vectorized) ------------------------------------
  all_scores <- cand$score_logit
  n_cand <- length(all_scores)
  if (n_cand <= 1L) {
    cand$gap_logit <- max_gap_ceiling
  } else {
    sorted <- sort(all_scores, decreasing = TRUE)
    # For each candidate: gap = score - max(others).
    # max(others) = sorted[1] unless this candidate IS sorted[1], then sorted[2].
    cand$gap_logit <- pmin(
      ifelse(all_scores >= sorted[1L] - .Machine$double.eps * 100,
             all_scores - sorted[2L],
             all_scores - sorted[1L]),
      max_gap_ceiling
    )
  }

  # ---- 3. LINEAGE MATRIX for hierarchical lookup fallback -------------------
  # finest rank -> column 1, coarser ranks -> subsequent columns
  lineage_mat <- if (length(existing_rank_cols) > 0L)
    as.data.frame(cand[, rev(existing_rank_cols), drop = FALSE])
  else
    data.frame(matrix(NA_character_, nrow = nrow(cand), ncol = 1L))

  # ---- 4. LIKELIHOOD CALCULATOR (shared by point-estimate and MC sims) ------
  # mu_override/delta_override (Session 157): when supplied, replace the
  # trained H1 mean_score / H2 delta with a caller-supplied value for this
  # call only -- used by the Monte Carlo section below to resample the
  # TRAINED MEAN by its own estimation uncertainty (how much reference data
  # calibrated it), rather than resampling the query's observed score. NULL
  # (default) reproduces the point-estimate behavior exactly. used_mu1/
  # used_sigma1/used_tau_sq1/used_h2_delta/used_h2_tau_sq are always returned
  # (whether or not an override was supplied) so the calling code can read
  # back exactly which values this call resolved -- letting the MC section
  # reuse the point-estimate pass's own resolution instead of re-deriving it.
  #
  # used_tau_sq1/used_h2_tau_sq (variance of the trained mean / H2 delta,
  # Session 157 continued): shrinkage-consistent, not naive sigma^2/n. When a
  # species/genus-specific estimate exists, it was itself computed as a
  # shrinkage blend `w*local + (1-w)*global`, `w = n/(n+prior_weight)` -- so
  # its own uncertainty is `w^2 * sigma^2/n`, NOT the naive `sigma^2/n` a
  # directly-observed (unshrunk) mean would have. This recovers the naive SE
  # as n grows (w -> 1) and correctly shrinks toward near-zero as n -> 0
  # (w -> 0): with almost no local data, the estimate is almost entirely the
  # well-known global/pooled value, and shrinkage is precisely the mechanism
  # that makes relying on that value legitimate, not a reason to doubt it
  # further. For a candidate with NO local estimate at all (no species/genus-
  # specific entry -- not a shrinkage blend, a pure fallback to the global/
  # pooled value), uncertainty is `sigma^2/prior_weight`: prior_weight is
  # this codebase's own definition of "the equivalent sample size of the
  # prior" (used identically for the shrinkage weight itself), NOT the true
  # pooled training count (`Stats$n_h1_pooled`/`n_h2_pooled`) -- found
  # necessary empirically: using the true pooled count (in the thousands)
  # made a candidate with ZERO local data look MORE confidently known than
  # one with substantial (but imperfect) local data, exactly backwards from
  # the intent, since a large pooled count reflects how precisely the
  # GLOBAL AVERAGE is known, not how safely it transfers to something never
  # directly observed.
  .calc_likelihoods <- function(s_vec, g_vec, p_raw, taxa_names, use_1d,
                                cov_vec = NULL, genus_vec = NULL, evidence_vec = NULL,
                                mu_override = NULL, delta_override = NULL) {
    h1_vals      <- numeric(length(s_vec))
    used_mu1     <- rep(NA_real_, length(s_vec))
    used_sigma1  <- rep(NA_real_, length(s_vec))
    used_tau_sq1 <- rep(NA_real_, length(s_vec))
    has_lookup <- !is.null(model_params$H1_Lookup) &&
      nrow(model_params$H1_Lookup) > 0L
    has_n_info <- has_lookup && "n_obs_species" %in% names(model_params$H1_Lookup)
    prior_weight_val <- if (has_n_info)
      (model_params$Stats$prior_weight %||% 10) else NA_real_

    for (i in seq_along(s_vec)) {
      if (p_raw[i] < min_match_threshold) next   # leave h1_vals[i] = 0

      use_mu       <- global_mu
      use_sigma    <- global_sigma
      n_i          <- NA_real_   # species-specific n_obs_species, if matched
      matched_local <- FALSE

      if (has_lookup) {
        idx <- match(taxa_names[i], model_params$H1_Lookup$lookup_key)
        if (is.na(idx) && ncol(lineage_mat) > 0L) {
          for (r_name in unlist(lineage_mat[i, ])) {
            if (!is.na(r_name)) {
              idx <- match(r_name, model_params$H1_Lookup$lookup_key)
              if (!is.na(idx)) break
            }
          }
        }
        if (!is.na(idx)) {
          sp_score <- model_params$H1_Lookup$mu_score[idx]
          sp_gap   <- model_params$H1_Lookup$mu_gap[idx]
          sp_var   <- model_params$H1_Lookup$sigma_score[idx]
          use_mu <- c(sp_score, sp_gap)
          # Floor at global sigma: species-specific sigma is estimated from
          # reference-vs-reference pairs and can be artificially tight for
          # well-sampled species whose references are nearly identical clones.
          # Real query-vs-reference scores span a wider range. Never allow a
          # per-species sigma tighter than the global sigma so that legitimate
          # eDNA queries at slightly sub-perfect scores still receive non-zero
          # H1 likelihoods.
          if (!is.na(sp_var) && sp_var > 0)
            use_sigma[1L, 1L] <- max(sp_var, global_sigma[1L, 1L])
          if (has_n_info) {
            n_i <- model_params$H1_Lookup$n_obs_species[idx]
            matched_local <- TRUE
          }
        } else if (verbose) {
          message(sprintf("  Taxon '%s': no species-specific params; using global mean",
                          taxa_names[i]))
        }
      }

      # Coverage inflation: widen sigma_score for low-coverage candidates.
      # Grounded in binomial sampling: SE(logit(score)) is proportional to 1/sqrt(N_aligned)
      # and N_aligned = coverage * N_total, so sigma_eff = sigma / sqrt(coverage).
      # Only activates when coverage < 1; does not affect H2/H3 sigmas.
      if (!is.null(cov_vec) && !is.na(cov_vec[i]) &&
          cov_vec[i] > 0 && cov_vec[i] < 1) {
        use_sigma[1L, 1L] <- use_sigma[1L, 1L] / sqrt(cov_vec[i])
      }

      # Evidence-quantity inflation/deflation: unlike coverage above, this can
      # be symmetric in principle -- an observation with MORE supporting
      # evidence than the model's calibration baseline (evidence_vec[i] > 1)
      # would TIGHTEN sigma, not just widen it. Capped at evidence_max_ratio
      # (default 1: never tighten, only widen) because uncapped tightening was
      # found to crash H1 to zero for a real, correctly-identified, high-depth
      # observation whose score wasn't EXACTLY at the trained mean (real
      # biological/technical variability doesn't vanish just because evidence
      # is abundant) -- the same failure mode `calibrate_query_noise()`'s
      # rejected flat sigma correction hit, re-triggered per-observation.
      # evidence_vec here is that raw per-candidate quantity (e.g. DNA read
      # depth, image detection count, acoustic recording duration) already
      # divided by calibrate_query_noise()'s "reference_evidence" baseline, so
      # a ratio of 1.0 means "typical" and is a no-op. Grounded in the same
      # binomial-sampling argument as the coverage inflation above
      # (SE(logit(score)) propto 1/sqrt(N)), applied to N = evidentiary
      # quantity rather than alignment overlap fraction.
      #
      # Crossover gate (replaces the previous unconditional rescale, which was
      # tested on real 12S data and found net negative even at this capped,
      # widen-only default -- 27 helped, 2053 hurt; see
      # evaluate_likelihoods()'s own @details and the TaxaID memory system's
      # evidence-ratio-sigma-reentry note for the full record). For a Gaussian
      # with variance V, rescaling V by a factor c (c > 1 widens, c < 1
      # tightens) changes the log-density at a point z = (x-mean)/sqrt(V)
      # standard deviations away by exactly:
      #   delta = -0.5*log(c) + 0.5*z^2*(1 - 1/c)
      # (elementary: both densities integrate to 1, so widening must lower the
      # peak while raising the tails, and vice versa for tightening -- this is
      # that tradeoff made explicit and exact, not an approximation).
      # Applying the rescale only when delta >= 0 means it is applied only
      # where it provably does not lower the density relative to leaving
      # sigma alone -- for widening (c > 1), that is the tail (z large); for
      # tightening (c < 1, reachable only if a caller sets
      # evidence_max_ratio > 1), that is near the mean (z small) -- exactly
      # the region symmetric widening was missing sigma correction for, and
      # exactly why the old unconditional version hurt the common case of a
      # low-depth observation that is still a close, correct match: it paid
      # the peak-lowering cost everywhere while only the tail region ever
      # benefits.
      #
      # z is standardized against whatever sigma is already in effect at this
      # point (after the species-lookup floor and coverage inflation above,
      # if either applied) -- not a separately-computed "clean" baseline --
      # so this gate composes correctly with those earlier adjustments rather
      # than re-deriving its own notion of the per-species distribution.
      #
      # For multi-candidate (bivariate) queries this uses the SCORE-ONLY
      # marginal z, not the true joint bivariate crossover (which would also
      # depend on the score/gap covariance term this code never modifies) --
      # deliberately consistent with the outlier alpha-test just below, which
      # already treats score as the sole outlier criterion for the documented
      # reason that gap should inform relative weighting, not admissibility.
      # For singleton (1D) queries the density actually evaluated below IS
      # exactly this univariate form, so the gate is exact there, not an
      # approximation.
      if (!is.null(evidence_vec) && !is.na(evidence_vec[i]) && evidence_vec[i] > 0) {
        widen_ratio <- min(evidence_vec[i], evidence_max_ratio)
        if (!isTRUE(all.equal(widen_ratio, 1))) {
          var_scale <- 1 / sqrt(widen_ratio)
          z_sq  <- (s_vec[i] - use_mu[1L])^2 / use_sigma[1L, 1L]
          delta_logdensity <- -0.5 * log(var_scale) +
            0.5 * z_sq * (1 - 1 / var_scale)
          if (delta_logdensity > 0)
            use_sigma[1L, 1L] <- use_sigma[1L, 1L] * var_scale
        }
      }

      # Record what this call resolved (species floor + coverage + evidence,
      # whichever applied) BEFORE any mu_override -- this is what the point-
      # estimate pass reports back to the Monte Carlo section below so it
      # knows what mean/variance to build a resampling distribution around.
      used_mu1[i]    <- use_mu[1L]
      used_sigma1[i] <- use_sigma[1L, 1L]
      if (has_n_info) {
        used_tau_sq1[i] <- if (matched_local) {
          w_i <- n_i / (n_i + prior_weight_val)
          w_i^2 * use_sigma[1L, 1L] / n_i
        } else {
          use_sigma[1L, 1L] / prior_weight_val
        }
      }

      # Mean-uncertainty override (Session 157): substitutes a simulated draw
      # of the trained mean for this candidate, used only by the Monte Carlo
      # section's resampling loop -- NULL (default) for the point estimate.
      if (!is.null(mu_override) && !is.na(mu_override[i]))
        use_mu[1L] <- mu_override[i]

      if (use_1d) {
        h1_vals[i] <- stats::dnorm(s_vec[i],
                                   mean = use_mu[1L],
                                   sd   = sqrt(use_sigma[1L, 1L]))
      } else {
        x_pt <- c(s_vec[i], g_vec[i])
        # Outlier filter: ONE-SIDED (low side only) score-only normal test,
        # calibrated against real 12S data in its original two-sided form
        # (Session 121 -- see this parameter's own @param alpha docs for the
        # real Cyprinidae/coastal-species numbers that calibration was based
        # on) and made one-sided in the statistical-critique session that
        # found the two-sided version incoherent for the high side: H2/H3's
        # own means sit BELOW H1's by construction (they model a missing-
        # species/genus hypothesis via a leftward shift), so a query score
        # anomalously ABOVE H1's mean fits every available alternative
        # hypothesis strictly worse, not better -- there is nothing for a
        # rejected H1 to hand its likelihood mass to that explains a
        # near-perfect match. The old two-sided test could hard-zero the
        # best-fitting hypothesis on exactly the evidence that most strongly
        # supports it. Verified this never actually fired on any current
        # production model (see the model_params$Score_Transform docs above
        # and train_likelihood_model()'s own "Non-monotonic score->likelihood
        # shape" section for the full record), but is a real, structural gap
        # independent of how rarely it fires in practice. Kept the identical
        # z-score/alpha calibration on the low side -- only the high side's
        # rejection is removed.
        # The gap measures how well-separated
        # H1 is from alternatives -- a small gap (confusable congener
        # present) is correctly handled by the bivariate density below, which
        # returns a lower H1 value. Including the gap in the outlier check
        # unfairly rejects legitimate H1 candidates whose gap is small purely
        # because a closely-scoring reference is present (e.g. a well-matched
        # species in a speciose family). The score alone determines whether
        # the query is consistent with this species' identity; the gap
        # informs the relative weight.
        z_score        <- (s_vec[i] - use_mu[1L]) / sqrt(use_sigma[1L, 1L])
        p_val_low_side <- stats::pnorm(z_score)
        if (p_val_low_side >= alpha)
          h1_vals[i] <- mvtnorm::dmvnorm(x_pt,
                                         mean  = as.numeric(use_mu),
                                         sigma = use_sigma)
      }
    }

    best_i <- which.max(s_vec)
    if (length(best_i) == 0L || all(s_vec == 0)) {
      return(list(h1 = h1_vals, h2 = 0, h3 = 0, h2_delta_source = "global_fallback",
                  used_mu1 = used_mu1, used_sigma1 = used_sigma1, used_tau_sq1 = used_tau_sq1,
                  used_h2_delta = h2_delta, used_h2_tau_sq = NA_real_))
    }

    best_pt <- c(s_vec[best_i], g_vec[best_i])

    # Per-genus H2 delta AND variance (see train_likelihood_model()'s
    # "Per-genus delta shrinkage" section): prefer the anchor candidate's own
    # genus-specific estimates when the model has one; otherwise fall back to
    # the pooled global values unchanged. H3 keeps the "+ constant taxonomic
    # step" heuristic on top of whichever delta (local or global) H2 used, so
    # a genus-specific H2 correction propagates to H3 consistently. H3's
    # sigma is not genus-specific (would need family-level congener data).
    use_h2_delta <- h2_delta
    use_h2_sigma <- h2_sigma
    delta_source <- "global_fallback"
    h2_n_used     <- NA_real_
    h2_matched_local <- FALSE
    if (!is.null(genus_vec) && !is.null(model_params$H2_Lookup) &&
        nrow(model_params$H2_Lookup) > 0L) {
      anchor_genus <- genus_vec[best_i]
      if (!is.na(anchor_genus)) {
        gidx <- match(anchor_genus, model_params$H2_Lookup$genus)
        if (!is.na(gidx)) {
          use_h2_delta <- model_params$H2_Lookup$delta_shrunk[gidx]
          delta_source <- "genus_specific"
          h2_n_used <- model_params$H2_Lookup$n_pairs[gidx]
          h2_matched_local <- TRUE
          # var_shrunk (Session 158) is absent from H2_Lookup objects built
          # before this session -- fall back to the pooled global h2_sigma
          # unchanged for those, exactly as before.
          if ("var_shrunk" %in% names(model_params$H2_Lookup)) {
            use_h2_sigma[1L, 1L] <- model_params$H2_Lookup$var_shrunk[gidx]
          }
        }
      }
    }
    # used_h2_delta/used_h2_tau_sq record what was resolved BEFORE
    # delta_override (see .calc_likelihoods()'s own header comment) -- read by
    # the Monte Carlo section to build its resampling distribution for H2/H3.
    # Same shrinkage-consistent treatment as H1's used_tau_sq1 above: a
    # genus-specific delta is itself a shrinkage blend (w = n_pairs/(n_pairs +
    # prior_weight)), so its uncertainty is w^2 * h2_var/n_pairs, not the naive
    # h2_var/n_pairs; a genus with no congener data at all falls back to
    # h2_var/prior_weight (not the true pooled foreign-match count -- see the
    # header comment for why that would understate uncertainty exactly where
    # it should be largest).
    resolved_h2_delta <- use_h2_delta
    resolved_h2_tau_sq <- if (has_n_info) {
      if (h2_matched_local) {
        w_h2 <- h2_n_used / (h2_n_used + prior_weight_val)
        w_h2^2 * use_h2_sigma[1L, 1L] / h2_n_used
      } else {
        use_h2_sigma[1L, 1L] / prior_weight_val
      }
    } else {
      NA_real_
    }
    if (!is.null(delta_override)) use_h2_delta <- delta_override
    use_h3_delta <- use_h2_delta + (h3_delta - h2_delta)

    # H2/H3 mean anchor (Session 158, "Effect 1"): anchored on the ANCHOR
    # CANDIDATE'S OWN resolved species mean (used_mu1[best_i], the same value
    # H1's own density used for this candidate -- species floor already
    # applied, mu_override NOT yet applied at this point in the primary/
    # point-estimate pass) rather than the population-wide global_mu. A
    # referenced species whose own trained mean sits above or below the
    # population average is real information about how conserved or variable
    # THIS lineage specifically is -- an unreferenced sister species should
    # inherit that, not be shifted from an unrelated population-wide
    # baseline. Falls back to global_mu when the anchor has no species-
    # specific entry at all (used_mu1[best_i] is then already global_mu,
    # since that is what use_mu starts as before any lookup).
    h2_anchor_mu <- if (!is.na(used_mu1[best_i])) used_mu1[best_i] else global_mu[1L]
    h2_mu   <- c(h2_anchor_mu - use_h2_delta, 0)
    h3_mu   <- c(h2_anchor_mu - use_h3_delta, 0)
    if (use_1d) {
      h2_val <- stats::dnorm(best_pt[1L], mean = h2_mu[1L],
                             sd = sqrt(use_h2_sigma[1L, 1L]))
      h3_val <- stats::dnorm(best_pt[1L], mean = h3_mu[1L],
                             sd = sqrt(h3_sigma[1L, 1L]))
    } else {
      h2_val <- mvtnorm::dmvnorm(best_pt, mean = h2_mu, sigma = use_h2_sigma)
      h3_val <- mvtnorm::dmvnorm(best_pt, mean = h3_mu, sigma = h3_sigma)
    }

    list(h1 = h1_vals, h2 = h2_val, h3 = h3_val, h2_delta_source = delta_source,
         used_mu1 = used_mu1, used_sigma1 = used_sigma1, used_tau_sq1 = used_tau_sq1,
         used_h2_delta = resolved_h2_delta, used_h2_tau_sq = resolved_h2_tau_sq)
  }

  # ---- 5. POINT ESTIMATE ----------------------------------------------------
  genus_vec <- if (!is.na(genus_rank_col) && genus_rank_col %in% names(cand))
    cand[[genus_rank_col]] else NULL

  primary <- .calc_likelihoods(cand$score_logit, cand$gap_logit,
                               cand$p_med, cand$taxon_name,
                               use_1d = is_singleton, genus_vec = genus_vec)

  # Coverage-adjusted point estimate: inflate sigma_score by 1/coverage for
  # each candidate taxon. When coverage is absent or all = 1, identical to
  # primary. H2/H3 sigmas are global fixed parameters and are not inflated.
  has_coverage <- "coverage" %in% names(cand)
  primary_cov  <- .calc_likelihoods(cand$score_logit, cand$gap_logit,
                                    cand$p_med, cand$taxon_name,
                                    use_1d = is_singleton,
                                    cov_vec = if (has_coverage) cand$coverage else NULL,
                                    genus_vec = genus_vec)

  # Evidence-adjusted point estimate: scale sigma_score by 1/sqrt(evidence_ratio)
  # for each candidate taxon, where evidence_ratio = the candidate's own raw
  # evidence quantity (e.g. DNA read depth) divided by model_params$Query_
  # Calibration$reference_evidence (a baseline set once, in bulk, by
  # calibrate_query_noise() -- never re-derived here, so this works
  # identically for a single-observation call as for a large batch). NULL
  # (no-op, identical to primary) when evidence_col isn't supplied, isn't
  # present in candidate_df, or the model was never calibrated with a
  # reference_evidence baseline -- never guessed.
  reference_evidence <- model_params$Query_Calibration$reference_evidence
  has_evidence <- !is.null(evidence_col) && evidence_col %in% names(cand) &&
    !is.null(reference_evidence) && !is.na(reference_evidence) && reference_evidence > 0
  primary_evidence <- .calc_likelihoods(
    cand$score_logit, cand$gap_logit, cand$p_med, cand$taxon_name,
    use_1d = is_singleton,
    evidence_vec = if (has_evidence) cand[[evidence_col]] / reference_evidence else NULL,
    genus_vec = genus_vec
  )

  # Build result rows for H1
  df_h1 <- cand |>
    dplyr::mutate(hypothesis_type          = "specific_candidate",
                  raw_likelihood           = primary$h1,
                  raw_likelihood_cov       = primary_cov$h1,
                  raw_likelihood_evidence  = primary_evidence$h1)

  # Build H2/H3 rows from the best candidate
  best_i   <- if (any(primary$h1 > 0)) which.max(primary$h1) else which.max(cand$score_logit)
  best_row <- cand[best_i, , drop = FALSE]

  # Derive H2 taxon_name: finest rank NA -> create_taxon_names picks genus
  # Derive H3 taxon_name: two finest ranks NA -> create_taxon_names picks family
  finest <- if (length(rank_cols) >= 1L) rank_cols[length(rank_cols)]       else NULL
  second  <- if (length(rank_cols) >= 2L) rank_cols[length(rank_cols) - 1L] else NULL

  row_h2 <- best_row
  if (!is.null(finest) && finest %in% names(row_h2))
    row_h2[[finest]] <- NA_character_
  row_h2 <- TaxaTools::create_taxon_names(row_h2, rank_cols)
  row_h2$hypothesis_type         <- "unreferenced_species"
  row_h2$raw_likelihood          <- primary$h2
  row_h2$raw_likelihood_cov      <- primary$h2   # H2 sigma is global fixed; no inflation
  row_h2$raw_likelihood_evidence <- primary$h2   # H2 sigma is global fixed; no inflation
  row_h2$h2_delta_source    <- primary$h2_delta_source

  row_h3 <- best_row
  if (!is.null(finest) && finest %in% names(row_h3))
    row_h3[[finest]] <- NA_character_
  if (!is.null(second) && second %in% names(row_h3))
    row_h3[[second]] <- NA_character_
  row_h3 <- TaxaTools::create_taxon_names(row_h3, rank_cols)
  row_h3$hypothesis_type         <- "unreferenced_genus"
  row_h3$raw_likelihood          <- primary$h3
  row_h3$raw_likelihood_cov      <- primary$h3   # H3 sigma is global fixed; no inflation
  row_h3$raw_likelihood_evidence <- primary$h3   # H3 sigma is global fixed; no inflation
  row_h3$h2_delta_source    <- primary$h2_delta_source

  res <- dplyr::bind_rows(df_h1, row_h2, row_h3)

  # Re-derive taxon_name for H1 rows too (ensures consistency with TaxaTools)
  res <- TaxaTools::create_taxon_names(res, rank_cols)

  # ---- CONFUSION-RISK COLUMNS (2026-07-23) -----------------------------------
  # species_confusion_risk/genus_confusion_risk/family_confusion_risk: a
  # model-independent, score-ONLY diagnostic of the risk that the raw match
  # score is equally well explained by a confusable relative at the rank a
  # hypothesis resolved to (P(a real congener/confamilial/cross-family pair
  # would score this high or higher), read off model_params$
  # Confusion_Risk_Curves -- see .lookup_confusion_risk_value()'s own header
  # for why HIGHER values mean MORE confusable, i.e. WEAKER evidence for the
  # call, matching this ecosystem's existing high=concern convention, e.g.
  # TaxaFlag::flag_contaminant()'s contaminant_score). Evaluated per row at
  # THAT row's own genus/family (H2 rows retain genus; H3 rows retain family
  # only) and its own observed score (best_row's p_med for H2/H3, i.e. the
  # anchor's score) -- res still carries genus_rank_col/family_rank_col
  # columns at this point (only nulled by create_taxon_names for
  # taxon_name/taxon_name_rank purposes, not the raw taxonomy columns
  # themselves). NA whenever the model has no Confusion_Risk_Curves for that
  # tier, or this row's own genus/family is NA (H3 rows always lack a genus;
  # family_confusion_risk only needs family, present for all three hypothesis
  # types when rank_system carries one at all).
  confusion_risk_curves <- model_params$Confusion_Risk_Curves
  n_res <- nrow(res)
  genus_vals_res  <- if (!is.na(genus_rank_col)  && genus_rank_col  %in% names(res))
    res[[genus_rank_col]]  else rep(NA_character_, n_res)
  family_vals_res <- if (!is.na(family_rank_col) && family_rank_col %in% names(res))
    res[[family_rank_col]] else rep(NA_character_, n_res)
  obs_pct_res <- res$p_med * 100

  res$species_confusion_risk <- if (!is.null(confusion_risk_curves) && !is.null(confusion_risk_curves$species)) {
    vapply(seq_len(n_res), function(i) {
      if (is.na(genus_vals_res[i])) return(NA_real_)
      .lookup_confusion_risk_value(obs_pct_res[i], genus_vals_res[i],
                           confusion_risk_curves$species$fpr_by_genus_shrunk,
                           confusion_risk_curves$species$fpr_pooled)
    }, numeric(1))
  } else {
    rep(NA_real_, n_res)
  }

  res$genus_confusion_risk <- if (!is.null(confusion_risk_curves) && !is.null(confusion_risk_curves$genus)) {
    vapply(seq_len(n_res), function(i) {
      if (is.na(family_vals_res[i])) return(NA_real_)
      .lookup_confusion_risk_value(obs_pct_res[i], family_vals_res[i],
                           confusion_risk_curves$genus$fpr_by_family_shrunk,
                           confusion_risk_curves$genus$fpr_pooled)
    }, numeric(1))
  } else {
    rep(NA_real_, n_res)
  }

  res$family_confusion_risk <- if (!is.null(confusion_risk_curves) && !is.null(confusion_risk_curves$family)) {
    vapply(seq_len(n_res), function(i) {
      .lookup_confusion_risk_value(obs_pct_res[i], NA_character_, NULL, confusion_risk_curves$family$fpr_pooled)
    }, numeric(1))
  } else {
    rep(NA_real_, n_res)
  }

  res_agg <- res |>
    dplyr::group_by(hypothesis_type, taxon_name, taxon_name_rank) |>
    dplyr::summarise(raw_likelihood          = max(raw_likelihood,          na.rm = TRUE),
                     raw_likelihood_cov      = max(raw_likelihood_cov,      na.rm = TRUE),
                     raw_likelihood_evidence = max(raw_likelihood_evidence, na.rm = TRUE),
                     species_confusion_risk = dplyr::first(species_confusion_risk),
                     genus_confusion_risk   = dplyr::first(genus_confusion_risk),
                     family_confusion_risk  = dplyr::first(family_confusion_risk),
                     # NA for specific_candidate rows (only H2/H3 rows carry this);
                     # each unreferenced_species/unreferenced_genus group has a
                     # single row, so first() is unambiguous.
                     h2_delta_source    = dplyr::first(h2_delta_source),
                     .groups = "drop")

  # own_rank_confusion_risk: convenience column pointing at whichever of the
  # three *_confusion_risk values matches this row's OWN resolved rank
  # (species_confusion_risk for specific_candidate, genus_confusion_risk for
  # unreferenced_species, family_confusion_risk for unreferenced_genus) --
  # species_confusion_risk/genus_confusion_risk/family_confusion_risk
  # themselves are always populated (where computable) for every row
  # regardless of hypothesis_type, so a reviewer can also see e.g. "resolved
  # to species, but genus_confusion_risk is also high."
  res_agg$own_rank_confusion_risk <- dplyr::case_when(
    res_agg$hypothesis_type == "specific_candidate"   ~ res_agg$species_confusion_risk,
    res_agg$hypothesis_type == "unreferenced_species" ~ res_agg$genus_confusion_risk,
    res_agg$hypothesis_type == "unreferenced_genus"   ~ res_agg$family_confusion_risk,
    TRUE ~ NA_real_
  )

  # ---- 6. NORMALISE TO LIKELIHOOD RATIOS ------------------------------------
  max_lik          <- max(res_agg$raw_likelihood,          na.rm = TRUE)
  max_lik_cov      <- max(res_agg$raw_likelihood_cov,      na.rm = TRUE)
  max_lik_evidence <- max(res_agg$raw_likelihood_evidence, na.rm = TRUE)
  if (max_lik          == 0 || is.na(max_lik))          max_lik          <- 1
  if (max_lik_cov      == 0 || is.na(max_lik_cov))      max_lik_cov      <- 1
  if (max_lik_evidence == 0 || is.na(max_lik_evidence)) max_lik_evidence <- 1

  res_agg <- res_agg |>
    dplyr::mutate(
      score_likelihood          = raw_likelihood          / max_lik,
      score_likelihood_cov      = raw_likelihood_cov      / max_lik_cov,
      score_likelihood_evidence = raw_likelihood_evidence / max_lik_evidence
    ) |>
    dplyr::filter(
      score_likelihood >= ratio_threshold |
        hypothesis_type != "specific_candidate"
    )

  # ---- 7. MONTE CARLO SIMULATION (optional) ---------------------------------
  # score_likelihood_mean/score_likelihood_sd represent genuine uncertainty in
  # the LIKELIHOOD ESTIMATE ITSELF -- driven by how much reference data
  # calibrated each candidate's trained mean (H1: n_obs_species; H2: n_pairs
  # behind its genus-specific delta, or prior_weight when no genus-specific
  # delta exists) -- not, as an earlier design did, by resampling the query's
  # own OBSERVED score around the population's overall spread (a different
  # quantity: how sensitive the density is to where the query happens to
  # land, not how confidently the species' own mean is known). Each simulated
  # draw perturbs the CANDIDATE'S TRAINED MEAN by its own (shrinkage-
  # consistent -- see .calc_likelihoods()'s used_tau_sq1/used_h2_tau_sq
  # comment) estimation uncertainty and evaluates the query's real, fixed
  # observed point against that draw -- so a poorly-referenced species, and
  # H2/H3 (which borrow rather than observe), correctly get a wider
  # score_likelihood_sd, while well-referenced species converge toward the
  # deterministic point estimate as n grows. Reuses primary_evidence's own
  # per-candidate resolved mean/variance (species floor + evidence gate,
  # whichever applied) rather than re-deriving them, so a low-depth
  # candidate's already-widened sigma also widens its mean uncertainty here at
  # no extra cost.
  #
  # Backward compatible: falls back to the previous behavior (resampling the
  # observed score by the global population sigma) when model_params was
  # trained before n_obs_species was retained in H1_Lookup.
  has_n_info <- !is.null(model_params$H1_Lookup) &&
    "n_obs_species" %in% names(model_params$H1_Lookup)

  if (n_sims > 0L && nrow(res_agg) > 0L) {
    sim_mat <- matrix(NA_real_, nrow = nrow(res_agg), ncol = n_sims)

    # Pre-compute index mapping: res_agg row -> cand row(s) for H1 lookup
    h1_idx_map <- vector("list", nrow(res_agg))
    h2_rows <- integer(0L)
    h3_rows <- integer(0L)
    for (r in seq_len(nrow(res_agg))) {
      ht <- res_agg$hypothesis_type[r]
      if (ht == "specific_candidate") {
        h1_idx_map[[r]] <- which(cand$taxon_name == res_agg$taxon_name[r])
      } else if (ht == "unreferenced_species") {
        h2_rows <- c(h2_rows, r)
      } else {
        h3_rows <- c(h3_rows, r)
      }
    }

    nc <- nrow(cand)

    if (has_n_info) {
      # SD of the TRAINED MEAN/delta itself (not of the observed score),
      # already shrinkage-consistent -- see .calc_likelihoods()'s
      # used_tau_sq1/used_h2_tau_sq comment for the derivation. Falls back to
      # 0 (no added uncertainty, matching the point estimate exactly) only
      # when genuinely unknown -- conservative, not a guess.
      mean_sd1 <- sqrt(primary_evidence$used_tau_sq1)
      mean_sd1[is.na(mean_sd1)] <- 0
      h2_delta_sd <- if (!is.na(primary$used_h2_tau_sq)) sqrt(primary$used_h2_tau_sq) else 0

      for (sim_i in seq_len(n_sims)) {
        mu_sim    <- stats::rnorm(nc, mean = primary_evidence$used_mu1, sd = mean_sd1)
        delta_sim <- stats::rnorm(1L, mean = primary$used_h2_delta, sd = h2_delta_sd)

        sim_res <- .calc_likelihoods(cand$score_logit, cand$gap_logit,
                                     cand$p_med, cand$taxon_name,
                                     use_1d = is_singleton, genus_vec = genus_vec,
                                     mu_override = mu_sim, delta_override = delta_sim)

        iter_liks <- numeric(nrow(res_agg))
        for (r in seq_len(nrow(res_agg))) {
          m <- h1_idx_map[[r]]
          if (!is.null(m) && length(m) > 0L) iter_liks[r] <- max(sim_res$h1[m])
        }
        if (length(h2_rows) > 0L) iter_liks[h2_rows] <- sim_res$h2
        if (length(h3_rows) > 0L) iter_liks[h3_rows] <- sim_res$h3

        iter_max <- max(iter_liks, na.rm = TRUE)
        if (iter_max == 0 || is.na(iter_max)) iter_max <- 1
        sim_mat[, sim_i] <- iter_liks / iter_max
      }
    } else {
      # Legacy fallback (model_params trained before n_obs_species was
      # retained in H1_Lookup): resample the observed score by the global
      # population sigma, exactly as before this session.
      for (sim_i in seq_len(n_sims)) {
        sim_scores <- stats::rnorm(nc, mean = cand$score_logit, sd = model_sd_score)

        if (nc <= 1L) {
          sim_gaps <- max_gap_ceiling
        } else {
          ss <- sort(sim_scores, decreasing = TRUE)
          sim_gaps <- pmin(
            ifelse(sim_scores >= ss[1L] - .Machine$double.eps * 100,
                   sim_scores - ss[2L],
                   sim_scores - ss[1L]),
            max_gap_ceiling
          )
        }

        sim_res <- .calc_likelihoods(sim_scores, sim_gaps,
                                     cand$p_med, cand$taxon_name,
                                     use_1d = is_singleton, genus_vec = genus_vec)

        iter_liks <- numeric(nrow(res_agg))
        for (r in seq_len(nrow(res_agg))) {
          m <- h1_idx_map[[r]]
          if (!is.null(m) && length(m) > 0L) {
            iter_liks[r] <- max(sim_res$h1[m])
          }
        }
        if (length(h2_rows) > 0L) iter_liks[h2_rows] <- sim_res$h2
        if (length(h3_rows) > 0L) iter_liks[h3_rows] <- sim_res$h3

        iter_max <- max(iter_liks, na.rm = TRUE)
        if (iter_max == 0 || is.na(iter_max)) iter_max <- 1
        sim_mat[, sim_i] <- iter_liks / iter_max
      }
    }

    res_agg$score_likelihood_mean <- rowMeans(sim_mat, na.rm = TRUE)
    res_agg$score_likelihood_sd   <- apply(sim_mat, 1L, stats::sd, na.rm = TRUE)
  } else {
    res_agg$score_likelihood_mean <- res_agg$score_likelihood
    res_agg$score_likelihood_sd   <- 0
  }

  # Final filter on mean (after simulation)
  res_agg <- dplyr::filter(res_agg, score_likelihood_mean >= ratio_threshold)

  res_agg |>
    dplyr::select(hypothesis_type, taxon_name, taxon_name_rank,
                  raw_likelihood, raw_likelihood_cov, raw_likelihood_evidence,
                  score_likelihood, score_likelihood_mean, score_likelihood_sd,
                  score_likelihood_cov, score_likelihood_evidence, h2_delta_source,
                  species_confusion_risk, genus_confusion_risk, family_confusion_risk,
                  own_rank_confusion_risk) |>
    dplyr::arrange(dplyr::desc(score_likelihood_mean))
}

#' Convert match scores to likelihoods for all queries
#'
#' Applies the trained likelihood model to every `observation_id` in the match
#' object and returns a tidy data frame suitable for input to
#' `TaxaAssign::compute_posterior()`.
#'
#' For each query the function:
#' \enumerate{
#'   \item Groups candidates by `taxon_name` and takes the median score
#'     across references (robust to outlier accessions and sample-size bias).
#'   \item Logit-transforms and computes the gap relative to the runner-up
#'     taxon.
#'   \item Looks up species-specific parameters from the model (with
#'     hierarchical fallback to genus, then global mean).
#'   \item Evaluates H1/H2/H3 likelihoods and normalises to ratios.
#' }
#'
#' @param match_df Data frame in the canonical match-object format (output of
#'   `TaxaMatch::standardize_match_data()` or user-supplied).  Must contain
#'   `observation_id`, `score_original` (or `p_match`; legacy `score` also
#'   accepted), `taxon_name`, `taxon_name_rank`,
#'   and taxonomy columns matching `rank_system`.
#' @param model_params Object of class `"taxa_model_params"` from
#'   [train_likelihood_model()]. The scale H1/H2/H3 were trained on
#'   (`model_params$Score_Transform`, `"logit"` or `"sqrt_mismatch"`) is read
#'   automatically -- callers do not supply or track it separately.
#'   `evidence_col`/`min_coverage` work identically regardless of
#'   `Score_Transform`: their `SE(transform(score)) propto 1/sqrt(N)`
#'   justification holds (with a different, `p`-dependent proportionality
#'   constant) for either scale, confirmed via the delta method.
#' @param rank_system Character vector of rank names **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`). Default `NULL` auto-detects
#'   from columns in `match_df`.
#' @param ratio_threshold Minimum likelihood ratio to retain a hypothesis
#'   (default `0.01`).  Hypotheses with likelihood ratio less than 1% of the
#'   best hypothesis are dropped.  This removes noise hypotheses that would
#'   not meaningfully affect posterior probabilities.  Note: the per-species
#'   sigma floor (see Details) ensures that well-sampled species with
#'   artificially tight training distributions still clear this threshold at
#'   realistic query scores, so the default `0.01` is appropriate for most
#'   eDNA workflows.
#' @param min_match_threshold Minimum raw score to consider a candidate
#'   (default `0.50`).  Queries whose best candidate scores below 50% identity
#'   are considered unmatchable and routed to the `$unresolved` output for
#'   re-evaluation with a coarser `rank_system`.
#' @param alpha Mahalanobis p-value cutoff for outlier rejection (default
#'   `0.001`).  See `.evaluate_one_query()` for full description.
#' @param n_sims Monte Carlo simulations per query (default `0` = point
#'   estimate only).
#' @param score_bounds Optional `c(min, max)` for score normalization.
#' @param logit_epsilon Logit clipping value (default `1e-4`).
#' @param max_gap_ceiling Gap cap (default `5.0`).  Caps gap at 5 logit units
#'   (roughly the gap between 99.3% and 50% identity) to prevent extreme
#'   outliers from dominating model estimates.
#' @param min_coverage Numeric or `NULL` (default `NULL`).  When not `NULL`
#'   and the match object contains a `coverage` column (e.g., BLAST `qcovs`
#'   divided by 100, or bounding-box area from
#'   `TaxaMatch::read_animl_output(bbox_cols=)`), candidate rows below this
#'   threshold are dropped **before** per-taxon score aggregation.  A
#'   `coverage` column can be added to any match object via the `coverage_col`
#'   parameter of `TaxaMatch::standardize_match_data()`.
#'
#'   Typical values: `0.8` (80\% query coverage) for DNA BLAST results.
#'   `NA` coverage values are always retained (treated as fully covered).
#'   When `coverage` is absent from `match_df`, this parameter is silently
#'   ignored.
#' @param evidence_col Character or `NULL` (default `NULL`). Name of a column
#'   in `match_df` giving each candidate's raw evidence quantity (e.g. DNA read
#'   depth, image detection count, acoustic recording duration -- whatever is
#'   appropriate for the data type). When supplied, `H1` sigma is rescaled by
#'   a factor `1/sqrt(evidence_ratio)`, where `evidence_ratio` is this
#'   quantity divided by `model_params$Query_Calibration$reference_evidence`
#'   -- a baseline set once, in bulk, by [calibrate_query_noise()]`(evidence_col=)`.
#'   Unlike `min_coverage`/coverage inflation above, this is symmetric: an
#'   observation with *more* evidence than the baseline tightens sigma, not
#'   just widens it for less. The rescale is only ever **applied** when doing
#'   so is provably non-decreasing for the density at the query's own
#'   (pre-rescale) standardized distance from the species mean -- see
#'   `@section Evidence-based sigma rescaling` below for the exact criterion
#'   and why it replaced an earlier unconditional version. Produces
#'   `score_likelihood_evidence`, a parallel point-estimate column (no Monte
#'   Carlo variant, matching `score_likelihood_cov`'s own precedent) --
#'   identical to `score_likelihood` when `evidence_col` is absent, not
#'   present in a given candidate row, the model was never calibrated with a
#'   `reference_evidence` baseline, or the gate criterion below isn't met;
#'   never guessed. Works identically for a single-observation `match_df` as
#'   for a large batch, since the baseline is read from `model_params`, not
#'   re-derived from `match_df` itself.
#' @param evidence_max_ratio Numeric (default `1`). Caps how much
#'   `evidence_ratio` may *tighten* sigma (values above this are clipped to
#'   it before the `1/sqrt()` scaling); widening for `evidence_ratio < 1` is
#'   never capped. Default `1` means evidence never tightens sigma at all,
#'   only widens -- found necessary empirically: an uncapped ratio crashed a
#'   real, correctly-identified, high-depth observation's `H1` likelihood to
#'   exactly 0 (its score wasn't precisely at the trained mean, and real
#'   variability doesn't vanish just because evidence is abundant). Raise
#'   above `1` only after validating on your own data -- the gate described in
#'   `@section Evidence-based sigma rescaling` protects the tightening
#'   direction using the same criterion as widening, but has not itself been
#'   validated against real over-tightening cases the way the widen-only
#'   default has been.
#' @param verbose Logical (default `FALSE`). When `TRUE`, prints a message
#'   each time a species falls back to global parameters (no species-specific
#'   lookup entry found).
#'
#' @return A named list with two components:
#'   \describe{
#'     \item{`$likelihoods`}{Data frame with one row per `observation_id` x taxon
#'       hypothesis, suitable for input to `TaxaAssign::compute_posterior()`:
#'       `observation_id`, `taxon_name`, `taxon_name_rank`, `hypothesis_type`
#'       (`"specific_candidate"`, `"unreferenced_species"`, or `"unreferenced_genus"`),
#'       `raw_likelihood`, `raw_likelihood_cov`, `raw_likelihood_evidence` (the
#'       bivariate-normal density -- `mvtnorm::dmvnorm()` over `(score_logit,
#'       gap_logit)` jointly -- BEFORE ratio-normalization against the best
#'       candidate in the same observation; `score_likelihood` etc. below are
#'       each `raw_likelihood / max(raw_likelihood)` within that observation.
#'       Because `score_likelihood` is always exactly 1.0 for a candidate with
#'       no real competitor, it cannot say whether a "winning" match is
#'       actually a good absolute fit -- `raw_likelihood` can, and is
#'       comparable across observations within one trained model/marker in a
#'       way the ratio never was; not calibration-free in an absolute sense
#'       (still evaluated against `H1_Lookup`'s calibrated or uncalibrated
#'       mu/sigma), but a within-marker relative comparison such as "above or
#'       below this marker's own median" sidesteps that),
#'       `score_likelihood`, `score_likelihood_mean`, `score_likelihood_sd`,
#'       `score_likelihood_cov`, `score_likelihood_evidence`, `h2_delta_source`
#'       (`"genus_specific"` or `"global_fallback"` for
#'       `unreferenced_species`/`unreferenced_genus` rows; `NA` for
#'       `specific_candidate` rows), plus the `*_confusion_risk` columns
#'       described under \strong{Confusion risk} below.}
#'     \item{`$unresolved`}{Rows from `match_df` for any `observation_id` that
#'       produced no usable likelihoods (empty data frame if none).  Pass to
#'       a second call of `evaluate_likelihoods()` with a coarser
#'       `rank_system` to recover these queries.}
#'   }
#'
#' @details
#' \strong{Three hypotheses:}
#' For each query, three types of hypothesis are evaluated:
#' \itemize{
#'   \item \strong{H1 (specific_candidate):} The query comes from a known species
#'     in the reference database. The model predicts what a true match to this
#'     species looks like based on reference-vs-reference scores.
#'   \item \strong{H2 (unreferenced_species):} The query comes from a species not
#'     in the reference database, but whose genus is represented. The model
#'     shifts the H1 score distribution downward (by \code{H2$delta} logit
#'     units, or by a genus-specific shrunk delta from
#'     \code{model_params$H2_Lookup} when the anchor candidate's genus has
#'     real congener data -- see \code{h2_delta_source} below) to predict
#'     what a sister-species match looks like.
#'   \item \strong{H3 (unreferenced_genus):} The query comes from a genus not in
#'     the reference database at all. The score distribution is shifted further
#'     downward (by \code{H3$delta}).
#' }
#'
#' \strong{Features:}
#' \itemize{
#'   \item \strong{score_logit:} The raw match score (e.g., percent identity),
#'     normalised to 0-1 and logit-transformed. The logit maps the bounded
#'     score onto the real line, allowing Gaussian modelling.
#'   \item \strong{gap_logit:} The difference between the best within-taxon
#'     logit score and the best cross-taxon logit score. A large gap means the
#'     top candidate is much better than any alternative -- strong evidence for
#'     that identification. When only one candidate taxon exists, the gap is
#'     not computed (1D model used instead).
#' }
#'
#' \strong{Per-species sigma floor:}
#' When a species is found in \code{H1_Lookup}, its per-species
#' \code{sigma_score} (score variance) is used in place of the global
#' \code{H1_Sigma[1,1]}.  However, the per-species estimate can be
#' artificially small for well-sampled species whose reference sequences are
#' nearly identical (many NCBI accessions from the same voucher or
#' population).  Such a tight distribution wrongly rejects realistic eDNA
#' query scores that fall slightly below the near-perfect reference mean,
#' causing the species to receive a near-zero H1 likelihood and be silently
#' dropped by \code{ratio_threshold}.  To prevent this,
#' \code{evaluate_likelihoods()} floors the per-species sigma at the global
#' \code{H1_Sigma[1,1]}: species-specific sigma is used only when it is
#' \emph{larger} than global (i.e., more uncertain than average).  This has
#' negligible impact on discrimination between closely related species because
#' the global sigma (SD \eqn{\approx \sqrt{H1\_Sigma[1,1]}}) still spans the
#' logit range corresponding to a few percent identity difference.
#'
#' \strong{Coverage-adjusted likelihood (`score_likelihood_cov`):}
#' When the match object contains a `coverage` column (e.g., BLAST `qcovs / 100`
#' or bounding-box area), a parallel point estimate `score_likelihood_cov` is
#' computed alongside `score_likelihood`.  For each specific candidate, the H1
#' `sigma_score` is widened by \eqn{1 / \sqrt{\text{coverage}}} before
#' evaluating the likelihood -- grounded in binomial sampling theory where
#' \eqn{SE(\text{logit}(\hat{p})) \propto 1 / \sqrt{N_{\text{aligned}}}} and
#' \eqn{N_{\text{aligned}} = \text{coverage} \times N_{\text{total}}}.  H2 and
#' H3 sigmas are global fixed parameters and are not inflated.  When coverage is
#' absent or equals 1 for all candidates, `score_likelihood_cov` is identical to
#' `score_likelihood`.  Pass to `TaxaAssign::compute_posterior()` instead of
#' `score_likelihood` to apply the coverage adjustment; compare the two columns
#' to identify queries where coverage meaningfully shifts the likelihood ratios.
#'
#' \strong{Evidence-based sigma rescaling (`score_likelihood_evidence`) and its
#' crossover gate:} An earlier version of `evidence_col` rescaled every
#' candidate's H1 `sigma_score` unconditionally whenever `evidence_ratio < 1`
#' (widening for low-evidence candidates, exactly like the coverage adjustment
#' above). Tested against real 12S data, that version was net negative even
#' capped at `evidence_max_ratio = 1` (27 real observations helped, 2053 hurt;
#' mean H1 relative likelihood 0.899 -> 0.884). The reason is a basic property
#' of the normal density, not an implementation defect: because a Gaussian must
#' integrate to 1, widening its variance necessarily lowers its peak while
#' raising its tails. For a variance rescaled by a factor \eqn{c} (\eqn{c > 1}
#' widens, \eqn{c < 1} tightens), the log-density at a point \eqn{z} standard
#' deviations from the species mean changes by exactly:
#' \deqn{\Delta = -\tfrac{1}{2}\log(c) + \tfrac{1}{2}z^2\left(1 - \tfrac{1}{c}\right)}
#' which is non-negative only when \eqn{z} is large enough (for widening) or
#' small enough (for tightening) that the tail/peak tradeoff pays for itself.
#' Because most low-evidence real observations are still decent, close-to-mean
#' matches (small \eqn{z}), applying the widening formula to \emph{every}
#' low-evidence candidate paid the peak-lowering cost far more often than it
#' collected the tail-raising benefit -- exactly the pattern in the real-data
#' result above. `evaluate_likelihoods()` now computes \eqn{\Delta} directly
#' (using \eqn{z} standardized against whatever sigma is already in effect
#' after the per-species floor and coverage inflation) and only applies the
#' evidence rescale when \eqn{\Delta > 0} -- i.e., only where doing so is
#' provably not going to lower the candidate's H1 density relative to leaving
#' sigma untouched. This is an exact, closed-form condition, not a heuristic
#' threshold, and it degrades gracefully to a no-op as `evidence_ratio`
#' approaches 1 (nothing to gate). One caveat for multi-candidate queries: the
#' gate is computed on the score-only marginal \eqn{z}, not the exact bivariate
#' `(score_logit, gap_logit)` crossover (only `sigma_score` is ever rescaled;
#' the gap variance and score/gap covariance are untouched, so the true joint
#' crossover would also depend on the correlation term) -- deliberately
#' consistent with the score-only outlier test described above rather than a
#' new, unvalidated 2D derivation. For singleton (1D) queries, where the
#' density actually evaluated is exactly this univariate form, the gate is
#' exact, not an approximation. This replaces the unconditional version, and has
#' been re-validated end to end against the same real 12S PtConception dataset
#' the unconditional version was tested on: 163 helped / 3 hurt across 24,857
#' real H1 rows (vs. 27 helped / 2053 hurt for the unconditional version), mean
#' H1 relative likelihood 0.8014 -> 0.8016 (vs. the unconditional version's real
#' regression 0.899 -> 0.884). The 3 residual hurt cases were traced directly
#' (via `mvtnorm::dmvnorm` on the real fitted parameters) to this score-only
#' marginal approximation: each sits right at the marginal gate's own decision
#' boundary, where the neglected score/gap covariance term flips the sign of
#' the true joint density change relative to the marginal prediction. Bounded
#' in practice (largest observed swing under 1% of the score range) but a real,
#' understood limitation of the approximation, not a bug.
#'
#' \strong{Genus-specific H2/H3 delta (`h2_delta_source`):}
#' `H2$delta`/`H3$delta` are single values pooled across every genus seen
#' during training, which treats a genus with unusually tight (cryptic-like)
#' congeneric divergence the same as one with unusually loose divergence.
#' When `train_likelihood_model()` found at least one real congener pair for
#' the query's best-matching candidate's genus, `evaluate_likelihoods()` uses
#' a genus-specific delta (`model_params$H2_Lookup`, shrunk toward the pooled
#' value by how many congener pairs were available) instead, and marks the
#' row `h2_delta_source = "genus_specific"`. Rows marked
#' `"global_fallback"` (including every row when the genus has only one
#' referenced species, or when the model was trained without genus
#' information) used the pooled constant, which is the cruder approximation
#' -- treat `unreferenced_species`/`unreferenced_genus` likelihoods on those
#' rows with more caution. This correction only adjusts the shift's
#' \emph{magnitude} for the correct genus; it does not address the separate
#' case where the true taxon's nearest relative in evidence space (visual or
#' acoustic mimicry/convergence) is not its nearest phylogenetic relative --
#' see `inst/TaxaLikely_supplemental_methods.md` for that limitation.
#'
#' \strong{H2/H3 mean anchor and genus-specific variance (Session 158):} H2's
#' mean is `(anchor candidate's own resolved species mean) - delta`, not
#' `H1_Global_Mu - delta` as in earlier versions -- a referenced species
#' whose own trained mean sits above or below the population average is real
#' information about how conserved or variable that lineage specifically is,
#' and an unreferenced sister species should inherit it rather than being
#' shifted from an unrelated population-wide baseline. When a genus-specific
#' `H2_Lookup` entry exists, its own shrunk congener variance (`var_shrunk`)
#' is used for H2's sigma in place of the pooled global value -- genera whose
#' species are hard to tell apart (small delta) also tend to show more
#' *consistent* divergence (lower variance), and genera whose species are
#' easy to tell apart show more variable divergence; both the delta and the
#' variance now reflect this per genus, on the same footing. Absent from
#' `H2_Lookup` objects built before this session -- those fall back to the
#' pooled global variance unchanged, exactly as before. See
#' `train_likelihood_model()`'s `score_transform` documentation and
#' `[[project_job2_unreferenced_relatives]]` in the TaxaID memory system for
#' why this required moving off the plain logit scale to be correctly
#' signed: on real 12S congener data, the raw match-proportion scale shows
#' tight genera have lower variance as expected (Pearson r = -0.55), but
#' logit reverses this (r = +0.47) because nearly all real matches sit near
#' 100% identity, exactly where logit's derivative diverges fastest.
#'
#' \strong{Monte Carlo uncertainty (`score_likelihood_mean`/`score_likelihood_sd`):}
#' Represents genuine uncertainty in the likelihood estimate itself -- driven
#' by how much reference data calibrated the trained mean being evaluated
#' (`H1_Lookup$n_obs_species` for a specific candidate; `H2_Lookup$n_pairs`
#' for a genus-specific H2/H3 delta, or `Stats$n_h2_pooled` when no
#' genus-specific delta exists) -- not by resampling the query's own observed
#' score around the population's overall spread (an earlier design, which
#' answered a different question: how sensitive the density is to where the
#' query happens to land, not how confidently the candidate's own mean is
#' known). Each of the `n_sims` draws perturbs the candidate's trained mean by
#' its own estimation uncertainty (`Var(mean) ~= sigma^2/n`) and evaluates the
#' query's real, fixed observed point against that draw. Practical
#' consequence: a poorly-referenced species gets a wider `score_likelihood_sd`
#' than a well-referenced one for the identical observed score, and
#' `unreferenced_species`/`unreferenced_genus` rows -- which borrow a shifted
#' mean rather than being directly observed -- are systematically wider than
#' `specific_candidate` rows. Reuses whichever per-candidate sigma the
#' evidence-adjusted point estimate already resolved (species floor +
#' evidence gate, when applicable), so a low-depth candidate's evidence-widened
#' sigma also widens its mean uncertainty here at no additional cost.
#' Backward compatible: falls back to the previous (score-resampling)
#' behavior when `model_params$H1_Lookup` has no `n_obs_species` column
#' (i.e., any model trained before this mechanism was added).
#'
#' @section Confusion risk:
#' `species_confusion_risk`/`genus_confusion_risk`/`family_confusion_risk` are
#' an independent, model-independent diagnostic --
#' deliberately score-only and model-free, rather than a second application
#' of this function's own trained bivariate-normal likelihood. Each answers,
#' at its own rank: given this row's raw match score and its own genus (for
#' `species_confusion_risk`) or family (for `genus_confusion_risk`), how
#' often would a REAL congener/confamilial pair score this high or higher,
#' in this training reference database? Read off
#' `model_params$Confusion_Risk_Curves` (genus-/family-equal-weighted,
#' Empirical-Bayes-shrunk curves computed once by
#' `train_likelihood_model()`, not recomputed here -- see that function's
#' own `Confusion_Risk_Curves` documentation and
#' `diagnostics/score_floor_roc_sweep.R`, the reference implementation these
#' curves are built from).
#'
#' **Higher means MORE confusable, i.e. WEAKER evidence for the rank in
#' question** -- matching this ecosystem's existing high=concern convention
#' for risk-style metrics (e.g. `TaxaFlag::flag_contaminant()`'s
#' `contaminant_score`), not the higher-is-better convention `score_likelihood`/
#' `posterior_mean`/`confidence_score` use. These are one-sided tail
#' probabilities (a p-value-like quantity for the null hypothesis "this is
#' just a confusable relative"): `species_confusion_risk = 0.97` at a given
#' score means a real congener would score this high 97% of the time too --
#' high confusion risk, weak evidence the species call is correct -- while
#' `species_confusion_risk = 0.02` at the same score means a real congener
#' almost never scores this high -- low confusion risk, strong evidence.
#' (Renamed 2026-07-23 from `species_support`/etc. after noticing the
#' original name inverted this convention -- "support" implied
#' higher-is-better while the values themselves behave the opposite way;
#' no math changed, only the name.) `family_confusion_risk` has no grouping
#' variable (a single, ungrouped cross-family rate) since no rank exists
#' above family to equal-weight by. `own_rank_confusion_risk` is a
#' convenience column pointing at whichever of the three matches this row's
#' own `hypothesis_type` (`species_confusion_risk` for `specific_candidate`,
#' `genus_confusion_risk` for `unreferenced_species`, `family_confusion_risk`
#' for `unreferenced_genus`) -- but all three are populated for every row
#' (where computable) regardless of `hypothesis_type`, so a reviewer can
#' also see e.g. "resolved to species, but genus_confusion_risk is also
#' high, meaning even the genus call is shaky."
#'
#' Purely informational -- never zeroes
#' a likelihood or changes which hypothesis wins. `NA` when
#' `model_params$Confusion_Risk_Curves` lacks the relevant tier (e.g.
#' `rank_system` too short) or this row's own genus/family is unresolved
#' (e.g. `unreferenced_genus` rows have no genus, so `species_confusion_risk`
#' is always `NA` there). See `TaxaAssign::posterior_consensus()`'s
#' `winner_species_confusion_risk`/`winner_genus_confusion_risk`/
#' `winner_family_confusion_risk`/`winner_own_rank_confusion_risk`
#' pass-through for how a downstream consumer reads these off the winning
#' row.
#'
#' @references
#' Somervuo, P., Koskela, S., Pennanen, J., Nilsson, R.H. and Ovaskainen, O.
#' (2017). Unbiased probabilistic taxonomic classification for DNA barcoding.
#' \emph{Bioinformatics}, 33(19), 2997--3005.
#' \doi{10.1093/bioinformatics/btx369}
#'
#' Efron, B. and Morris, C. (1973). Stein's estimation rule and its
#' competitors -- an empirical Bayes approach. \emph{Journal of the American
#' Statistical Association}, 68(341), 117--130.
#' \doi{10.1080/01621459.1973.10481350}
#'
#' @seealso [train_likelihood_model()], [filter_top_hypotheses()]
#'
#' @note For a fully runnable, non-`\dontrun{}` demonstration (including how
#'   `match_df`/`model` are derived), see `inst/review_function_inputs.R`
#'   Section 6 in the package source.
#'
#' @examples
#' \dontrun{
#' result <- evaluate_likelihoods(
#'   match_df, model,
#'   rank_system = c("family", "genus", "species"),
#'   n_sims = 1000
#' )
#' head(result$likelihoods)
#' nrow(result$unresolved)
#' }
#'
#' @importFrom cli cli_progress_bar cli_progress_update cli_progress_done
#' @importFrom dplyr any_of arrange bind_rows desc filter group_by group_split mutate n_distinct n_groups select summarise ungroup across first
#' @importFrom mvtnorm dmvnorm
#' @importFrom stats dnorm mahalanobis pchisq rnorm sd
#' @export
evaluate_likelihoods <- function(match_df,
                                 model_params,
                                 rank_system            = NULL,
                                 ratio_threshold        = 0.01,
                                 min_match_threshold    = 0.50,
                                 alpha                  = 0.001,
                                 n_sims                 = 0L,
                                 score_bounds           = NULL,
                                 logit_epsilon          = 1e-4,
                                 max_gap_ceiling        = NULL,
                                 min_coverage           = NULL,
                                 evidence_col           = NULL,
                                 evidence_max_ratio     = 1,
                                 verbose                = FALSE) {
  if (!is.data.frame(match_df))
    stop("match_df must be a data frame")
  if (!inherits(model_params, "taxa_model_params"))
    stop("model_params must be a 'taxa_model_params' object from train_likelihood_model()")

  # Session 158, revised: evidence_col/min_coverage's sigma-modulation
  # mechanisms (the crossover gate and the coverage inflation) were initially
  # guarded here against score_transform = "sqrt_mismatch", on the
  # (mistaken) assumption that their "SE propto 1/sqrt(N)" justification was
  # logit-specific. Re-derived via the delta method and checked numerically:
  # for ANY reasonable transform of a binomial proportion, SE(transform(p_hat))
  # scales as 1/sqrt(N) with a p-dependent (not N-dependent) proportionality
  # constant -- confirmed the ratio of logit's and sqrt_mismatch's own SE
  # formulas is exactly constant across N. The crossover gate's own math
  # (evaluate.R, "Evidence-based sigma rescaling") is already fully
  # scale-agnostic (pure Gaussian peak-vs-tail tradeoff on a standardized z),
  # so nothing about either mechanism is actually logit-specific -- the guard
  # was removed rather than kept out of unwarranted caution. The coverage
  # inflation (`min_coverage`) remains an ungated, unconditional widen (never
  # received the Session 156 crossover-gate treatment evidence_col did) --
  # that is a separate, already-documented limitation
  # ([[project_quality_covariate_deferred]]) equally present on both scales,
  # not something new introduced here.

  # Auto-detect rank_system from match_df columns
  # This 14-rank ladder is deliberately NOT TaxaTools::standard_ranks (7
  # ranks -- too coarse, missing e.g. subphylum/superclass/suborder) or
  # TaxaTools::extended_ranks (21 ranks -- has domain/subkingdom/superorder/
  # superfamily/subfamily/tribe/subgenus/subspecies/variety/form instead of
  # this function's infraclass/cohort/suborder/infraorder). Investigated
  # during the human code review (2026-08) as a candidate for consolidation
  # onto one shared TaxaTools constant -- not done, since the three lists
  # have genuinely different rank sets (not just duplicated identical
  # values, unlike fetch.R's former .crabs_std_hierarchy, which WAS an
  # exact duplicate of TaxaTools::standard_ranks and now aliases it
  # directly). Reconciling all three into one canonical extended-rank list
  # would mean widening a shared, exported TaxaTools constant and checking
  # every downstream consumer's auto-detection behavior for a change --
  # flagged for a future dedicated cross-package session, not attempted here.
  if (is.null(rank_system)) {
    canonical <- c("kingdom", "phylum", "subphylum", "superclass", "class",
                   "subclass", "infraclass", "cohort", "order", "suborder",
                   "infraorder", "family", "genus", "species")
    rank_system <- canonical[canonical %in% tolower(names(match_df))]
    if (length(rank_system) < 2L)
      stop(
        "Could not auto-detect rank_system from match_df columns. ",
        "Found: ", paste(names(match_df), collapse = ", "),
        ". Supply rank_system explicitly.",
        call. = FALSE
      )
  }

  if (!is.character(rank_system) || length(rank_system) == 0L)
    stop("rank_system must be a non-empty character vector (coarse to fine)")

  names(match_df) <- tolower(names(match_df))
  if (!is.null(evidence_col)) evidence_col <- tolower(evidence_col)

  if (!"observation_id" %in% names(match_df))
    stop("match_df must have an 'observation_id' column")
  if (anyNA(match_df$observation_id))
    stop("match_df$observation_id contains NA values; all rows must have a valid observation_id")

  n_queries <- dplyr::n_distinct(match_df$observation_id)
  message(sprintf("Evaluating likelihoods for %d unique queries...", n_queries))

  query_groups <- dplyr::group_split(dplyr::group_by(match_df, observation_id))

  start_time <- proc.time()[["elapsed"]]
  results  <- vector("list", length(query_groups))
  n_failed <- 0L

  pb <- cli::cli_progress_bar("Evaluating queries", total = length(query_groups))
  for (i in seq_along(query_groups)) {
    cli::cli_progress_update(id = pb)
    chunk  <- query_groups[[i]]
    sid    <- chunk$observation_id[1L]
    result <- tryCatch(
      .evaluate_one_query(
        candidate_df        = chunk,
        model_params           = model_params,
        rank_system            = rank_system,
        ratio_threshold        = ratio_threshold,
        min_match_threshold    = min_match_threshold,
        alpha                  = alpha,
        n_sims                 = n_sims,
        score_bounds           = score_bounds,
        logit_epsilon          = logit_epsilon,
        max_gap_ceiling        = max_gap_ceiling,
        min_coverage           = min_coverage,
        evidence_col           = evidence_col,
        evidence_max_ratio     = evidence_max_ratio,
        verbose                = verbose
      ),
      error = function(e) {
        warning(sprintf("Query '%s' failed: %s", sid, conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(result)) {
      result$observation_id <- sid
      results[[i]] <- result
    } else {
      n_failed <- n_failed + 1L
    }
  }

  cli::cli_progress_done(id = pb)
  elapsed <- round(proc.time()[["elapsed"]] - start_time, 1L)
  message(sprintf("Evaluation complete in %.1f seconds.", elapsed))

  if (n_failed > 0L) {
    warning(sprintf(
      "evaluate_likelihoods: %d of %d observation_id(s) produced no usable likelihoods.",
      n_failed, length(query_groups)
    ))
  }

  out        <- dplyr::bind_rows(results)
  unresolved <- match_df[integer(0L), ]   # zero-row copy; populated below if needed

  # Identify rows where taxon_name resolved to NA (occurs when all taxonomy
  # columns are NA, e.g. reference identified only at a rank coarser than
  # rank_system specifies).  Rows are always dropped from $likelihoods.
  # observation_ids with NO surviving rows are returned in $unresolved with a warning.
  na_name <- is.na(out$taxon_name)
  if (any(na_name)) {
    sids_with_na   <- unique(out$observation_id[na_name])
    sids_with_good <- unique(out$observation_id[!na_name])
    all_na_sids    <- setdiff(sids_with_na, sids_with_good)

    if (length(all_na_sids) > 0L) {
      unresolved <- match_df[match_df$observation_id %in% all_na_sids, ]
      show_ids <- if (length(all_na_sids) <= 5L) {
        paste(all_na_sids, collapse = ", ")
      } else {
        paste0(paste(all_na_sids[1:5], collapse = ", "),
               sprintf(", ... (%d more)", length(all_na_sids) - 5L))
      }
      warning(sprintf(
        paste0(
          "%d observation_id(s) produced no usable likelihoods and are returned in ",
          "$unresolved: %s. These queries likely matched references identified ",
          "only at a coarser rank than rank_system specifies. Re-run ",
          "evaluate_likelihoods() on $unresolved with a rank_system that ",
          "includes the coarser rank, and re-run audit_reference_coverage() ",
          "with target_rank set to match."
        ),
        length(all_na_sids), show_ids
      ))
    }

    out <- out[!na_name, ]
  }

  likelihoods <- dplyr::select(out, observation_id, taxon_name, taxon_name_rank,
                               hypothesis_type,
                               raw_likelihood, raw_likelihood_cov, raw_likelihood_evidence,
                               score_likelihood,
                               score_likelihood_mean, score_likelihood_sd,
                               score_likelihood_cov, score_likelihood_evidence,
                               h2_delta_source,
                               species_confusion_risk, genus_confusion_risk, family_confusion_risk,
                               own_rank_confusion_risk)

  # Propagate is_restored from match_df when present.
  # For each (observation_id, taxon_name), is_restored = TRUE only when ALL
  # corresponding match_df rows are restored (i.e. added by
  # restore_suppressed_candidates()).  H2/H3 rows (unreferenced_*) are not in
  # match_df and receive is_restored = FALSE.
  if ("is_restored" %in% names(match_df)) {
    restored_per_taxon <- match_df |>
      dplyr::filter(!is.na(taxon_name)) |>
      dplyr::group_by(observation_id, taxon_name) |>
      dplyr::summarise(is_restored = all(is_restored == TRUE), .groups = "drop")
    likelihoods <- dplyr::left_join(likelihoods, restored_per_taxon,
                                     by = c("observation_id", "taxon_name"))
    likelihoods$is_restored[is.na(likelihoods$is_restored)] <- FALSE
  }

  list(likelihoods = likelihoods, unresolved = unresolved)
}

#' Keep only the finest-rank specific candidates per query
#'
#' After `evaluate_likelihoods()`, each query may have specific candidates at
#' multiple ranks (e.g., both species- and genus-level hits).  This function
#' retains only the finest-rank specific candidates -- coarser candidates are
#' redundant when a finer-rank hit exists -- while keeping all
#' `"unreferenced_species"` and `"unreferenced_genus"` rows.
#'
#' \strong{is_restored preservation:}
#' When the `$likelihoods` data frame contains an `is_restored` column
#' (propagated by [evaluate_likelihoods()] from [restore_suppressed_candidates()]),
#' a coarser-rank row (e.g., genus) is \emph{preserved} instead of dropped when
#' every finer-rank row for the same genus in the same observation has
#' `is_restored = TRUE`.  This situation arises in post-LCA / post-consensus
#' workflows: the genus row is a real LCA-collapsed identification, and the
#' species rows were added purely by restoration (not original BLAST hits).
#' Preserving the genus row allows [TaxaAssign::join_priors()] to expand it into
#' named species hypotheses -- including locally-expected species absent from the
#' reference library.  The all-restored species rows are simultaneously dropped
#' to prevent double-counting after expansion.
#'
#' @param likelihood_df Data frame -- the `$likelihoods` component of the list
#'   returned by [evaluate_likelihoods()].
#' @param rank_system Character vector of rank names **coarse to fine**.
#'   Used to assign numeric rank scores for comparison. Default `NULL`
#'   auto-detects from the `taxon_name_rank` values in `likelihood_df`.
#'
#' @return Filtered version of `likelihood_df`.
#'
#' @seealso [evaluate_likelihoods()]
#'
#' @note For a fully runnable, non-`\dontrun{}` demonstration, see
#'   `inst/review_function_inputs.R` Section 6 in the package source.
#'
#' @examples
#' \dontrun{
#' result <- evaluate_likelihoods(match_df, model)
#' filtered <- filter_top_hypotheses(result$likelihoods)
#' }
#'
#' @importFrom dplyr filter group_by mutate select ungroup
#' @export
filter_top_hypotheses <- function(likelihood_df, rank_system = NULL) {
  if (!is.data.frame(likelihood_df))
    stop("likelihood_df must be a data frame")
  needed <- c("observation_id", "taxon_name_rank", "hypothesis_type")
  missing_cols <- setdiff(needed, names(likelihood_df))
  if (length(missing_cols) > 0L)
    stop(sprintf("likelihood_df is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))

  # Auto-detect rank_system from taxon_name_rank values
  if (is.null(rank_system)) {
    canonical <- TaxaTools::standard_ranks
    observed  <- unique(tolower(likelihood_df$taxon_name_rank))
    observed  <- observed[!is.na(observed)]
    rank_system <- canonical[canonical %in% observed]
    if (length(rank_system) == 0L)
      rank_system <- c("family", "genus", "species")
    message("filter_top_hypotheses: auto-detected rank_system: ",
            paste(rank_system, collapse = ", "))
  }

  # Numeric rank score: finest rank = highest number
  rank_scores <- stats::setNames(
    seq_along(rank_system),
    tolower(rank_system)
  )

  non_specific <- dplyr::filter(likelihood_df,
                                hypothesis_type != "specific_candidate")
  specific     <- dplyr::filter(likelihood_df,
                                hypothesis_type == "specific_candidate")

  if (nrow(specific) == 0L) {
    warning("filter_top_hypotheses: no specific_candidate rows found. Returning only unreferenced hypotheses.")
    return(non_specific)
  }

  # Warn about unknown rank values (will get NA rank_score and be dropped)
  unknown_ranks <- setdiff(tolower(unique(specific$taxon_name_rank)), names(rank_scores))
  if (length(unknown_ranks) > 0L) {
    warning(sprintf(
      paste0("filter_top_hypotheses: taxon_name_rank value(s) not in rank_system: %s. These ",
             "rows will be dropped. Ensure rank_system includes all ranks present in your data."),
      paste(unknown_ranks, collapse = ", ")
    ))
  }

  # Score all specific rows and identify the finest rank per observation
  specific_scored <- specific |>
    dplyr::mutate(rank_score = rank_scores[tolower(taxon_name_rank)]) |>
    dplyr::filter(!is.na(rank_score)) |>
    dplyr::group_by(observation_id) |>
    dplyr::mutate(best_rank_score = max(rank_score, na.rm = TRUE)) |>
    dplyr::ungroup()

  finest_rows  <- dplyr::filter(specific_scored, rank_score == best_rank_score)
  coarser_rows <- dplyr::filter(specific_scored, rank_score <  best_rank_score)

  # When is_restored is present: preserve coarser (e.g. genus) rows whose
  # entire set of finest-rank (e.g. species) rows in the same observation are
  # ALL restored by restore_suppressed_candidates().  Those restored species
  # rows are then dropped to avoid double-counting when join_priors() expands
  # the preserved genus row into per-species hypotheses via expansion_taxonomy.
  #
  # Pre-consensus observations whose species rows are a mix of original BLAST
  # hits and restored candidates are unaffected (some is_restored = FALSE ->
  # genus row still dropped, species rows kept -- existing behaviour).
  if ("is_restored" %in% names(specific_scored) && nrow(coarser_rows) > 0L) {

    # sub(" .*$", "", taxon_name) below takes the first whitespace-delimited
    # token of finest_rows$taxon_name as its genus, on the assumption that
    # taxon_name at the finest observed rank always begins with the genus
    # name -- true for this package's own genus/species convention (a
    # species-rank taxon_name is always a "Genus species" binomial per
    # TaxaTools::create_taxon_names()/is_plausible_binomial()'s shared
    # convention) and degrades safely when the finest rank IS genus (a
    # single-word string with no space is returned unchanged by sub()).
    # Not verified against every possible custom rank_system a caller could
    # supply (e.g. a rank finer than species whose own column doesn't store
    # a full trinomial) -- this branch is only reached via the DNA/BLAST
    # restore_suppressed_candidates() pathway, which in every real workflow
    # this package ships uses family/genus/species specifically.

    # Per (observation_id, genus): are ALL finest-rank rows for that genus restored?
    genus_all_restored <- finest_rows |>
      dplyr::mutate(.genus = sub(" .*$", "", taxon_name)) |>
      dplyr::group_by(observation_id, .genus) |>
      dplyr::summarise(.all_restored = all(is_restored == TRUE), .groups = "drop")

    # Join status onto coarser rows (match genus taxon_name against .genus key)
    coarser_checked <- coarser_rows |>
      dplyr::left_join(genus_all_restored,
                       by = c("observation_id", "taxon_name" = ".genus"))

    preserved_coarser <- dplyr::filter(coarser_checked,
                                        !is.na(.all_restored) & .all_restored) |>
      dplyr::select(-rank_score, -best_rank_score, -.all_restored)

    if (nrow(preserved_coarser) > 0L) {
      # Drop the all-restored finest-rank rows whose genus row is now preserved;
      # they will be covered by join_priors() expansion of the genus row.
      preserved_genera <- preserved_coarser |>
        dplyr::select(observation_id, taxon_name) |>
        dplyr::rename(.genus = taxon_name)

      finest_rows <- finest_rows |>
        dplyr::mutate(.genus = sub(" .*$", "", taxon_name)) |>
        dplyr::anti_join(preserved_genera, by = c("observation_id", ".genus")) |>
        dplyr::select(-.genus, -rank_score, -best_rank_score)
    } else {
      preserved_coarser <- NULL
      finest_rows <- dplyr::select(finest_rows, -rank_score, -best_rank_score)
    }

  } else {
    preserved_coarser <- NULL
    finest_rows <- dplyr::select(finest_rows, -rank_score, -best_rank_score)
  }

  dplyr::bind_rows(finest_rows, preserved_coarser, non_specific)
}
