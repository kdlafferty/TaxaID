utils::globalVariables(c(
  "taxon_name_rank", "theta_mean", "taxon_name", "genus",
  "observation_id", "score_original", "n_plausible"
))

# ==============================================================================
# calibrate_query_noise.R
# TaxaLikely -- Non-circular, marker-specific query-noise calibration
# ==============================================================================

#' Identify confident, non-circular observations for query-noise calibration
#'
#' Finds genera where exactly one species clears a local occurrence-plausibility
#' threshold in `priors` (e.g. `TaxaExpect` output), then returns the best-scoring
#' row per `observation_id` for every `match_df` observation whose genus is one of
#' those. Because the single-plausible-species call comes from independent
#' occurrence/range data -- not from `match_df`'s own scores or the likelihood
#' model being calibrated -- these observations can be treated as (very likely)
#' correct species identifications without circularity.
#'
#' @param match_df Data frame. Canonical match object (e.g. `match_obj_restored`)
#'   with `observation_id`, `genus`, and a score column (`score_original`,
#'   `score`, or `p_match`, checked in that order).
#' @param priors Data frame. Occurrence-based priors (e.g. `TaxaExpect` output)
#'   with `taxon_name`, `taxon_name_rank`, and `theta_mean`.
#' @param plausibility_threshold Numeric (default `1e-3`). Minimum `theta_mean`
#'   for a species to count as "locally plausible" in a genus. Values are
#'   typically well-separated from background/floor priors (often ~1e-6); the
#'   default is a conservative gap above that floor.
#'
#' @return Data frame: one row per confident `observation_id`, with all
#'   `match_df` columns plus `confident_genus` (the genus that qualified) and
#'   `confident_species` (its single plausible species, from `priors`).
#'
#' @seealso [calibrate_query_noise()]
#'
#' @examples
#' match_df <- data.frame(
#'   observation_id = paste0("Q", 1:5),
#'   genus          = "Genusone",
#'   score_original = c(95, 96, 94, 97, 93)
#' )
#' priors <- data.frame(
#'   taxon_name      = "Genusone speciesa",
#'   taxon_name_rank = "species",
#'   theta_mean      = 0.5
#' )
#' identify_confident_observations(match_df, priors)
#'
#' @importFrom dplyr filter mutate group_by summarise pull slice_max ungroup n
#' @export
identify_confident_observations <- function(match_df,
                                            priors,
                                            plausibility_threshold = 1e-3) {
  if (!is.data.frame(match_df)) {
    stop("identify_confident_observations: 'match_df' must be a data frame.", call. = FALSE)
  }
  if (!is.data.frame(priors)) {
    stop("identify_confident_observations: 'priors' must be a data frame.", call. = FALSE)
  }

  needed_match <- c("observation_id", "genus")
  missing_match <- setdiff(needed_match, names(match_df))
  if (length(missing_match) > 0L) {
    stop(sprintf(
      "identify_confident_observations: 'match_df' is missing column(s): %s",
      paste(missing_match, collapse = ", ")
    ), call. = FALSE)
  }

  needed_priors <- c("taxon_name", "taxon_name_rank", "theta_mean")
  missing_priors <- setdiff(needed_priors, names(priors))
  if (length(missing_priors) > 0L) {
    stop(sprintf(
      "identify_confident_observations: 'priors' is missing column(s): %s",
      paste(missing_priors, collapse = ", ")
    ), call. = FALSE)
  }

  score_col <- if ("score_original" %in% names(match_df)) {
    "score_original"
  } else if ("score" %in% names(match_df)) {
    "score"
  } else if ("p_match" %in% names(match_df)) {
    "p_match"
  } else {
    stop("identify_confident_observations: 'match_df' must have a 'score_original', 'score', or 'p_match' column.",
      call. = FALSE
    )
  }

  sp_priors <- priors |>
    dplyr::filter(taxon_name_rank == "species") |>
    dplyr::mutate(genus = sub(" .*$", "", taxon_name))

  genus_summary <- sp_priors |>
    dplyr::group_by(genus) |>
    dplyr::summarise(
      n_plausible = sum(theta_mean > plausibility_threshold),
      confident_species = taxon_name[theta_mean > plausibility_threshold][1L],
      .groups = "drop"
    ) |>
    dplyr::filter(n_plausible == 1L)

  if (nrow(genus_summary) == 0L) {
    warning("identify_confident_observations: no genus had exactly one locally-plausible species at this threshold.",
      call. = FALSE
    )
    return(match_df[integer(0L), , drop = FALSE])
  }

  confident <- match_df |>
    dplyr::filter(genus %in% genus_summary$genus) |>
    dplyr::group_by(observation_id) |>
    dplyr::slice_max(.data[[score_col]], n = 1L, with_ties = FALSE) |>
    dplyr::ungroup()

  confident$confident_genus <- confident$genus
  confident$confident_species <- genus_summary$confident_species[
    match(confident$genus, genus_summary$genus)
  ]

  confident
}


#' Calibrate a trained likelihood model to real query-vs-reference behavior
#'
#' `train_likelihood_model()` estimates H1 (known-species) parameters entirely
#' from reference-vs-reference pairs -- two clean, curated database sequences
#' compared to each other. That process cannot see technical noise specific to
#' real queries (PCR error, sequencing error, degradation, ASV-inference
#' artifacts), so a real, correctly-identified query routinely scores lower
#' than the trained H1 mean predicts, and the "unreferenced" hypotheses (whose
#' means sit further down the score axis, exactly where real queries land) can
#' end up out-competing the correct referenced species.
#'
#' This function estimates a single, marker-wide additive correction from
#' observations where the true species can be identified with high confidence
#' from *independent, non-circular* evidence -- occurrence/range priors, not
#' the likelihood model's own scores -- via [identify_confident_observations()].
#' For each confident observation, the residual between its observed
#' `score_logit` and its species' own trained `mu_score` (or the global mean,
#' if that species has no `H1_Lookup` entry) is computed; the median residual
#' across all confident observations is the calibration offset.
#'
#' The offset is applied uniformly to `H1_Global_Mu["score_logit"]` and to
#' every `H1_Lookup$mu_score`, shifting the absolute anchor of the model
#' without altering the *relative* structure between species, or the
#' `H2`/`H3` congener-divergence deltas (which are differences from the
#' shifted mean, so they carry through unchanged).
#'
#' @section Sigma correction (opt-in, off by default -- use with caution):
#' The same confident-observation residuals can also be used to scale H1's
#' *variance* (`calibrate_sigma = TRUE`): reference-vs-reference pairs
#' understate real query-to-query scatter in the opposite direction from the
#' mean bias (in the one real dataset this was tested against, MAD-based
#' residual variance ran ~11x tighter than the reference-trained variance).
#' Applying that ratio to `H1_Sigma["score_logit", "score_logit"]` and every
#' `H1_Lookup$sigma_score` sounds like the natural complement to the mean fix,
#' but **empirically made things worse, not better**, on the one real dataset
#' this was tested against: it helped 0 of 13,442 real observations and hurt
#' 4,878, in some cases (including the motivating `Sardinops` case) zeroing
#' out a correct H1 candidate entirely. The likely mechanism: the confident
#' set is selection-biased toward the *easiest* cases (abundant, well-sampled
#' genera, clean high-depth reads) and its internal spread understates the
#' true population's variability, which includes rarer/lower-quality
#' specimens that never qualify as "confident" in the first place -- so a
#' sigma correction derived from it is too tight for the general population,
#' triggering exactly the failure mode `evaluate_likelihoods()`'s existing
#' per-species sigma floor (Session 121, see `TaxaLikely/CLAUDE.md`'s Known
#' Footguns) was built to prevent, just at the global-model level instead of
#' the per-species level. Left in as an opt-in, documented negative result
#' rather than removed outright, since a smarter correction (e.g. shrinking
#' toward the original reference-based sigma rather than fully replacing it)
#' may be worth revisiting -- but do not enable it without validating on your
#' own data first, the same way this was validated (and rejected) here.
#'
#' @section Level-aware recalibration (`offset_form = "linear"`):
#' The default `"constant"` form is correct only if the train-vs-inference
#' scale gap is a pure location shift -- the same additive offset for every
#' species, regardless of identity level. That assumption is exactly what a
#' single additive offset *cannot* check, and on real externally-scored 12S
#' data it does not hold: the per-species H1 means estimated from
#' `build_sequence_matrix()`'s DECIPHER reference-vs-reference MSA do not
#' transfer to the external scoring scale at all. Regressing each confident
#' species' required offset on its trained mean gives a slope near `-1` (i.e.,
#' real correct-species query scores collapse toward one identity level
#' regardless of what the reference MSA says that species' self-similarity is),
#' and a single pooled inference-scale mean predicts real confident queries
#' *better* than "per-species trained mean + one offset" in cross-validation.
#' `offset_form = "linear"` addresses this by remapping every H1 mean through a
#' robustly-fit line `intercept + slope * trained_mean` (fit on per-species
#' medians, weighted by observation count) instead of adding one constant. It
#' is a strict generalization: `slope = 1, intercept = offset` reproduces the
#' constant form exactly, so it degrades to "constant offset" when the
#' per-species structure *does* transfer (`slope -> 1`) and to "one pooled
#' inference location for all species" when it does not (`slope -> 0`, the real
#' 12S case). Only the H1 mean *location* is remapped; the H2/H3
#' congener-divergence deltas (defined relative to the H1 mean) and the gap
#' feature -- the structure that actually discriminates between candidate
#' species -- are untouched.
#'
#' One caveat governs why `"constant"` is retained as an opt-out rather than
#' removed. The confident set is selection-biased toward abundant, well-sampled,
#' easy genera, and by construction has exactly one plausible species per genus
#' -- so it can measure absolute H1 *location* fit but cannot directly test
#' congener *discrimination*. A `"linear"` fit whose slope collapses to 0 removes
#' per-species location structure that is demonstrably not real on the inference
#' scale, but that this validation set cannot independently confirm is safe to
#' remove in hard congener-vs-congener cases. For that reason `"constant"`
#' remains available for an analyst who would rather keep per-species locations
#' than collapse them; `"linear"` is the default because on every real dataset
#' examined the collapse was both indicated (slope near 0) and harmless-to-helpful
#' for assignment, and because it reduces to `"constant"` automatically wherever
#' the per-species means do transfer (slope near 1). `"linear"` requires at least
#' `min_calib_species` confident species spanning a range of trained means; it
#' falls back to `"constant"` with a warning otherwise.
#'
#' The collapse is not specific to the 12S external-pipeline data it was found
#' on: across five real datasets (one external-pipeline 12S run and BLAST-scored
#' 12S, 16S, and COI datasets) the fitted slope stayed far from 1 (roughly
#' `-0.28` to `0.02`), and cross-validation on the confident set found the
#' per-species trained means added no inference-scale predictive value over a
#' single pooled location -- so the reference-derived per-species locations do
#' not survive a change of scoring instrument (BLAST or an unknown external
#' tool alike). This is a post-hoc calibration against an independent,
#' non-circular anchor set, analogous in spirit to Platt scaling for classifier
#' outputs (Platt 1999) but linear-in-the-location rather than logistic, and it
#' addresses a train-vs-inference *dataset shift* (Quinonero-Candela et al.
#' 2009) that arises because percent identity is an operationally-defined
#' quantity whose value for a fixed pair of sequences depends on the alignment
#' method and denominator (May 2004; Raghava & Barton 2006). See
#' `inst/TaxaLikely_supplemental_methods.md` Section 11A for the full derivation,
#' the empirical result, and references.
#'
#' @section Scope:
#' This estimates one offset for the *whole model* (i.e., one marker/dataset),
#' not a per-species correction -- there usually isn't enough confident-genus
#' coverage to support anything finer, and the confident set can never contain
#' cross-species information anyway. Do not reuse an offset estimated on one
#' marker (or one primer set) for another: the size of this gap has been found
#' to vary by roughly an order of magnitude between markers of different
#' length and quality (see `TaxaLikely/CLAUDE.md` for the 12S/18S comparison
#' this function's design was validated against) and does not transfer as
#' either a fixed percentage or a fixed mismatch count. The same applies
#' across `score_transform` values (Session 158): the offset is estimated on
#' whichever scale `model_params$Score_Transform` says the model was trained
#' on (read automatically), but a `"logit"`-scale offset and a
#' `"sqrt_mismatch"`-scale offset are different numbers in different units --
#' never reuse one for the other, and always recompute after retraining with
#' a different `score_transform`.
#'
#' @param model_params Object of class `"taxa_model_params"` from
#'   [train_likelihood_model()].
#' @param match_df Data frame. Canonical match object for the *same* dataset
#'   `model_params` was trained for (e.g. `match_obj_restored`). Must contain
#'   `observation_id`, `genus`, and a score column.
#' @param priors Data frame. Occurrence-based priors for the same dataset
#'   (e.g. `TaxaExpect` output), with `taxon_name`, `taxon_name_rank`, and
#'   `theta_mean`.
#' @param plausibility_threshold Numeric (default `1e-3`). Passed to
#'   [identify_confident_observations()].
#' @param min_confident_obs Integer (default `30L`). Minimum number of
#'   confident observations required to compute an offset. Below this, the
#'   function warns and returns `model_params` unchanged (offset = 0, sigma
#'   ratio = 1).
#' @param offset_form Character (default `"linear"`). `"linear"` remaps each H1
#'   mean through a robustly-fit line `intercept + slope * trained_mean` (fit on
#'   per-species medians) -- a level-aware calibration that estimates, rather
#'   than assumes, how much per-species reference-scale structure transfers to
#'   the inference scale, and reduces to a pure additive offset when it fully
#'   transfers (slope = 1). It is the default because, across every real dataset
#'   tested (external-pipeline- and BLAST-scored DNA markers), the fitted slope
#'   collapsed toward 0 and a single calibrated location fit real query scores
#'   as well as or better than per-species-mean-plus-offset (see "Level-aware
#'   recalibration"). `"constant"` is the conservative opt-out -- one additive
#'   offset applied to every H1 mean (the package's original behavior),
#'   appropriate when you would rather retain per-species locations than collapse
#'   them on a location-only validation set. `"linear"` falls back to
#'   `"constant"` (with a warning) when fewer than `min_calib_species` confident
#'   species, or no spread of trained means, are available -- so a thin-reference
#'   marker (e.g. one with only a handful of referenced species) is handled
#'   safely without a caller having to special-case it.
#' @param min_calib_species Integer (default `8L`). Minimum number of distinct
#'   confident species (spanning a range of trained means) required to fit the
#'   `offset_form = "linear"` line. Ignored when `offset_form = "constant"`.
#' @param calibrate_sigma Logical (default `FALSE`). Also apply the
#'   MAD-based variance-scale correction described in the Sigma correction
#'   section below. **Empirically made results worse on the one real dataset
#'   this was tested against** -- read that section before enabling.
#' @param evidence_col Character or `NULL` (default `NULL`). Name of a column
#'   in `match_df` giving each observation's raw evidence quantity (e.g. DNA
#'   read depth, image detection count, acoustic recording duration). When
#'   supplied, the median of this quantity across the confident observations
#'   is stored as `reference_evidence` in the returned `$Query_Calibration`
#'   slot -- the baseline [evaluate_likelihoods()]`(evidence_col=)` divides a
#'   query's own evidence quantity by, at inference time, to scale H1 sigma
#'   per-observation (more evidence than this baseline tightens sigma, less
#'   widens it -- unlike the rejected flat `calibrate_sigma` correction above,
#'   this is validated per-observation, not as one population-wide constant;
#'   see `TaxaLikely/CLAUDE.md` for the within-species correlation this is
#'   based on). Median chosen for the same robustness reason as the mean
#'   offset (a real, right-skewed depth distribution can span 5+ orders of
#'   magnitude). A **global** median across the whole confident set, not
#'   per-species/genus -- per-observation evidence quantity already carries
#'   the relevant signal regardless of species, and normalizing away a
#'   species' typical evidence level would reintroduce the same
#'   population-mismatch problem that broke the flat sigma correction.
#'   Calibration (this function, needs bulk confident-observation data) and
#'   inference (`evaluate_likelihoods()`, works on any number of
#'   observations, including one) are deliberately decoupled: once
#'   `reference_evidence` is baked into `model_params` here, scoring a single
#'   new observation later needs no recalibration. When `NULL` (default) or
#'   too few confident observations exist, `reference_evidence` is left `NA`
#'   -- `evaluate_likelihoods()` then applies no evidence-based adjustment at
#'   all, rather than guessing a baseline from insufficient data.
#' @param logit_epsilon Logit clipping value (default `1e-4`), matching
#'   [evaluate_likelihoods()]'s own default.
#' @param verbose Logical (default `TRUE`). Print the estimated offset and how
#'   many confident observations/genera it was based on.
#'
#' @return `model_params`, with `H1_Global_Mu["score_logit"]` and
#'   `H1_Lookup$mu_score` shifted by the estimated offset; `H1_Sigma["score_logit",
#'   "score_logit"]` and every `H1_Lookup$sigma_score` scaled by the estimated
#'   variance ratio (unless `calibrate_sigma = FALSE`); and a new
#'   `$Query_Calibration` slot recording `offset_logit`, `offset_form`
#'   (the form actually applied, which may be `"constant"` after a `"linear"`
#'   fallback), `slope`/`intercept` (the applied mean remap: `slope = 1`,
#'   `intercept = offset_logit` for the constant form), `sigma_ratio`,
#'   `reference_evidence` (`NA` unless `evidence_col` supplied),
#'   `n_confident_obs`, `n_confident_genera`, and `plausibility_threshold` for
#'   auditability. Unchanged (with `offset_logit = 0`, `offset_form =
#'   "constant"`, `slope = 1`, `intercept = 0`, `sigma_ratio = 1`,
#'   `reference_evidence = NA`) if fewer than `min_confident_obs` confident
#'   observations are found.
#'
#' @seealso [identify_confident_observations()], [train_likelihood_model()],
#'   [evaluate_likelihoods()]
#'
#' @examples
#' \dontrun{
#' model <- train_likelihood_model(seq_matrix, rank_system = c("family", "genus", "species"))
#' model_calibrated <- calibrate_query_noise(model, match_obj_restored, taxaexpect_priors)
#' lik_result <- evaluate_likelihoods(match_obj_restored, model_calibrated,
#'   rank_system = c("family", "genus", "species")
#' )
#' }
#'
#' @importFrom stats median mad plogis
#' @export
calibrate_query_noise <- function(model_params,
                                  match_df,
                                  priors,
                                  plausibility_threshold = 1e-3,
                                  min_confident_obs = 30L,
                                  offset_form = c("linear", "constant"),
                                  min_calib_species = 8L,
                                  calibrate_sigma = FALSE,
                                  evidence_col = NULL,
                                  logit_epsilon = 1e-4,
                                  verbose = TRUE) {
  offset_form <- match.arg(offset_form)
  if (!inherits(model_params, "taxa_model_params")) {
    stop("calibrate_query_noise: 'model_params' must be a 'taxa_model_params' object from train_likelihood_model().",
      call. = FALSE
    )
  }

  # Session 158: reads model_params$Score_Transform and applies the matching
  # transform via .transform_p() (see below) -- the offset/residual/sigma-
  # ratio computation itself is scale-agnostic arithmetic (differences,
  # medians, ratios), so no other part of this function needed to change.
  # Only the reference-vs-reference-vs-real-query NOISE MAGNITUDE (the
  # estimated offset itself) is marker/scale-specific and must be
  # (re-)estimated per model, never reused across markers OR across
  # transforms -- unchanged from this function's existing "Scope" guidance.
  model_score_transform <- model_params$Score_Transform %||% "logit"

  confident <- identify_confident_observations(
    match_df, priors,
    plausibility_threshold = plausibility_threshold
  )

  score_col <- if ("score_original" %in% names(confident)) {
    "score_original"
  } else if ("score" %in% names(confident)) {
    "score"
  } else {
    "p_match"
  }

  n_confident_genera <- length(unique(confident$confident_genus))

  if (nrow(confident) < min_confident_obs) {
    warning(sprintf(
      "calibrate_query_noise: only %d confident observation(s) found (need >= %d). Returning model_params unchanged.",
      nrow(confident), min_confident_obs
    ), call. = FALSE)
    model_params$Query_Calibration <- list(
      offset_logit = 0,
      offset_form = "constant",
      slope = 1,
      intercept = 0,
      sigma_ratio = 1,
      reference_evidence = NA_real_,
      n_confident_obs = nrow(confident),
      n_confident_genera = n_confident_genera,
      plausibility_threshold = plausibility_threshold
    )
    return(model_params)
  }

  p_raw <- confident[[score_col]]
  p_norm <- if (max(p_raw, na.rm = TRUE) > 1) p_raw / 100 else p_raw
  observed_logit <- .transform_p(p_norm, model_score_transform, logit_epsilon)

  global_mu_score <- as.numeric(model_params$H1_Global_Mu["score_logit"])
  lookup_idx <- match(confident$confident_species, model_params$H1_Lookup$lookup_key)
  expected_logit <- ifelse(
    !is.na(lookup_idx),
    model_params$H1_Lookup$mu_score[lookup_idx],
    global_mu_score
  )

  residuals <- observed_logit - expected_logit
  offset <- stats::median(residuals, na.rm = TRUE)

  # --- Recalibration map: trained mean -> inference-scale mean ---------------
  # "constant" (default): new_mean = old_mean + offset -- one additive shift,
  # the package's original behavior. Correct only if the train-vs-inference
  # scale gap is a pure LOCATION shift (same for every species).
  #
  # "linear": new_mean = intercept + slope * old_mean, fit robustly from the
  # confident set. Generalizes the constant form (which is exactly slope = 1,
  # intercept = offset) to a scale gap that depends on the identity level. On
  # real externally-scored 12S data the per-species trained means (from
  # DECIPHER's reference-vs-reference MSA) were found NOT to transfer to the
  # external scoring scale at all -- a robust fit drives slope -> 0, i.e. real
  # correct-species query scores collapse to ~one identity level regardless of
  # what the reference MSA says that species' self-similarity is, so a single
  # additive offset is patching per-species structure that isn't real on the
  # inference scale (see @section Level-aware recalibration). The fit is on
  # PER-SPECIES medians (inherently robust to per-observation outliers,
  # weighted by observation count) rather than raw per-observation points, and
  # only the H1 mean LOCATION is remapped -- the H2/H3 congener-divergence
  # deltas (relative to the H1 mean) and gap structure that actually
  # discriminate between candidates are untouched.
  recal_form <- offset_form
  slope <- 1
  intercept <- offset
  if (recal_form == "linear") {
    sp_df <- data.frame(
      sp = confident$confident_species,
      obs = observed_logit,
      exp = expected_logit,
      stringsAsFactors = FALSE
    )
    sp_df <- sp_df[is.finite(sp_df$obs) & is.finite(sp_df$exp) & !is.na(sp_df$sp), ,
      drop = FALSE
    ]
    sp_agg <- stats::aggregate(cbind(obs, exp) ~ sp,
      data = sp_df,
      FUN = stats::median
    )
    sp_n <- as.numeric(table(sp_df$sp)[sp_agg$sp])
    enough_species <- nrow(sp_agg) >= min_calib_species
    # isTRUE() guards the single-species case, where sd() of one value is NA
    # (otherwise `if (!exp_varies)` below would error on a missing logical).
    exp_varies <- isTRUE(stats::sd(sp_agg$exp) > 1e-8)
    if (enough_species && exp_varies) {
      fit_lin <- stats::lm(obs ~ exp, data = sp_agg, weights = sp_n)
      intercept <- unname(stats::coef(fit_lin)[1L])
      slope <- unname(stats::coef(fit_lin)[2L])
    } else {
      warning(sprintf(
        paste0(
          "calibrate_query_noise: offset_form = 'linear' needs >= %d confident species ",
          "spanning a range of trained means; only %d usable%s. Falling back to constant ",
          "offset."
        ),
        min_calib_species, nrow(sp_agg),
        if (!exp_varies) " (trained means don't vary across them)" else ""
      ), call. = FALSE)
      recal_form <- "constant"
      slope <- 1
      intercept <- offset
    }
  }

  # Clamp remapped means to the range we actually have query evidence for
  # (linear form only -- a safety rail against linear extrapolation for a
  # species whose trained mean lies far outside the confident set's range;
  # the constant form is a rigid shift and never needs it, so its behavior is
  # left byte-identical to before this parameter existed).
  obs_iqr <- stats::IQR(observed_logit, na.rm = TRUE)
  clamp_lo <- min(observed_logit, na.rm = TRUE) - obs_iqr
  clamp_hi <- max(observed_logit, na.rm = TRUE) + obs_iqr
  recal_mean <- if (recal_form == "linear") {
    function(m) pmin(pmax(intercept + slope * m, clamp_lo), clamp_hi)
  } else {
    function(m) m + offset
  }

  global_sigma_score <- model_params$H1_Sigma["score_logit", "score_logit"]
  sigma_ratio <- if (calibrate_sigma) {
    (stats::mad(residuals, na.rm = TRUE)^2) / global_sigma_score
  } else {
    1
  }

  reference_evidence <- NA_real_
  if (!is.null(evidence_col)) {
    if (!evidence_col %in% names(confident)) {
      warning(sprintf(
        "calibrate_query_noise: evidence_col '%s' not found in match_df. No evidence-ratio baseline computed.",
        evidence_col
      ), call. = FALSE)
    } else {
      evidence_vals <- confident[[evidence_col]]
      reference_evidence <- stats::median(evidence_vals, na.rm = TRUE)
      if (is.na(reference_evidence) || reference_evidence <= 0) {
        warning(sprintf(
          paste0(
            "calibrate_query_noise: median '%s' among confident observations is NA or ",
            "<= 0. No evidence-ratio baseline computed."
          ),
          evidence_col
        ), call. = FALSE)
        reference_evidence <- NA_real_
      }
    }
  }

  new_global_mu <- recal_mean(global_mu_score)
  model_params$H1_Global_Mu["score_logit"] <- new_global_mu
  model_params$H1_Lookup$mu_score <- recal_mean(model_params$H1_Lookup$mu_score)

  model_params$H1_Sigma["score_logit", "score_logit"] <- global_sigma_score * sigma_ratio
  model_params$H1_Lookup$sigma_score <- model_params$H1_Lookup$sigma_score * sigma_ratio

  model_params$Query_Calibration <- list(
    offset_logit = offset,
    offset_form = recal_form,
    slope = slope,
    intercept = intercept,
    sigma_ratio = sigma_ratio,
    reference_evidence = reference_evidence,
    n_confident_obs = nrow(confident),
    n_confident_genera = n_confident_genera,
    plausibility_threshold = plausibility_threshold
  )

  if (verbose) {
    message(sprintf(
      "calibrate_query_noise: offset = %.3f logit units (%d confident observations across %d genera).",
      offset, nrow(confident), n_confident_genera
    ))
    if (recal_form == "linear") {
      message(sprintf(
        paste0(
          "  offset_form = 'linear': trained_mean -> %.4f + %.4f * trained_mean ",
          "(slope ~ 0 => per-species trained means don't transfer to the inference scale; ",
          "~ 1 => equivalent to a constant offset)."
        ),
        intercept, slope
      ))
    }
    message(sprintf(
      "  H1_Global_Mu[\"score_logit\"]: %.3f -> %.3f (%.2f%% -> %.2f%%)",
      global_mu_score, new_global_mu,
      100 * .untransform_p(global_mu_score, model_score_transform),
      100 * .untransform_p(new_global_mu, model_score_transform)
    ))
    if (calibrate_sigma) {
      message(sprintf(
        "  H1_Sigma[score_logit] variance ratio: %.4f (sd: %.3f -> %.3f)",
        sigma_ratio, sqrt(global_sigma_score), sqrt(global_sigma_score * sigma_ratio)
      ))
    }
    if (!is.null(evidence_col) && !is.na(reference_evidence)) {
      message(sprintf(
        "  reference_evidence ('%s', median of confident set): %.1f",
        evidence_col, reference_evidence
      ))
    }
  }

  model_params
}
