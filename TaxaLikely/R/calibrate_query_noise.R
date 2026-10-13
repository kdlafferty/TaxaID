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
#' @return Data frame: one row per confident `observation_id` -- an
#'   observation whose top hit overall is the one locally plausible species
#'   of its genus (a top hit to any other species, including a congener, is
#'   excluded) -- with all
#'   `match_df` columns plus `confident_genus` (the genus that qualified) and
#'   `confident_species` (its single plausible species, from `priors`).
#'   Only binomial prior names count as species, and each distinct species
#'   counts once however many sites list it. Attributes `n_qualifying_genera`
#'   and `n_prior_names_not_binomial` (species-rank prior names such as
#'   "Ulva sp." or a family name that were not counted) qualify that result;
#'   `n_excluded_other_species` counts top hits in a qualifying genus that
#'   were not its plausible species. Only OBSERVED rows are considered: rows
#'   added by [restore_suppressed_candidates()] (`is_restored`, hypothesis
#'   type `"suppressed_candidate"`, any `restoration_basis`) are hypotheses,
#'   not measurements of query noise, and are removed first; attribute
#'   `n_restored_rows_excluded` counts them.
#'
#' @seealso [calibrate_query_noise()]
#'
#' @examples
#' match_df <- data.frame(
#'   observation_id = paste0("Q", 1:5),
#'   genus          = "Genusone",
#'   taxon_name     = "Genusone speciesa",
#'   score_original = c(95, 96, 94, 97, 93)
#' )
#' priors <- data.frame(
#'   taxon_name      = "Genusone speciesa",
#'   taxon_name_rank = "species",
#'   theta_mean      = 0.5
#' )
#' # Internal, not exported -- qualified here so the example is runnable.
#' TaxaLikely:::identify_confident_observations(match_df, priors)
#'
#' @importFrom dplyr filter mutate group_by summarise pull slice_max ungroup n
#' @keywords internal
identify_confident_observations <- function(match_df,
                                            priors,
                                            plausibility_threshold = 1e-3) {
  if (!is.data.frame(match_df)) {
    stop("identify_confident_observations: 'match_df' must be a data frame.", call. = FALSE)
  }
  if (!is.data.frame(priors)) {
    stop("identify_confident_observations: 'priors' must be a data frame.", call. = FALSE)
  }

  needed_match <- c("observation_id", "genus", "taxon_name")
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

  # Count DISTINCT plausible species per genus. A prior table stacked across
  # sites repeats each species once per site, so counting rows made a genus
  # with one plausible species look like it had several. Only binomials
  # count: a coarse record labelled species ("Cottidae") is not a species,
  # and would otherwise pose as a genus with exactly one member.
  sp_rank <- priors[priors$taxon_name_rank %in% "species" & !is.na(priors$taxon_name), , drop = FALSE]
  is_binom <- TaxaTools::is_plausible_binomial(sp_rank$taxon_name)
  n_names_not_binomial <- length(unique(sp_rank$taxon_name[!is_binom]))
  sp_priors <- sp_rank[is_binom, , drop = FALSE] |>
    dplyr::mutate(genus = sub(" .*$", "", taxon_name))

  genus_summary <- sp_priors |>
    dplyr::group_by(genus) |>
    dplyr::summarise(
      n_plausible = dplyr::n_distinct(taxon_name[theta_mean > plausibility_threshold]),
      confident_species = unique(taxon_name[theta_mean > plausibility_threshold])[1L],
      .groups = "drop"
    ) |>
    dplyr::filter(n_plausible == 1L)

  if (nrow(genus_summary) == 0L) {
    warning("identify_confident_observations: no genus had exactly one locally-plausible species at this threshold.",
      call. = FALSE
    )
    return(match_df[integer(0L), , drop = FALSE])
  }

  # OBSERVED rows only. A restored row (restore_suppressed_candidates():
  # is_restored, hypothesis_type "suppressed_candidate", a restoration_basis,
  # including dropped-hit replacements) is a hypothesis the pipeline added, not
  # a measurement of how a real query scores against its own species. Left
  # in, it sets the measured query noise from the restoration rule instead of
  # the data: imputed restored scores once WIDENED the COI spread (nanopore
  # ratio 2.26 vs 1.00 from observed rows), and measured ones then narrowed it
  # (illumina 2.25 vs about 3.2), gating thousands of observed candidates.
  is_restored_row <- rep(FALSE, nrow(match_df))
  if ("is_restored" %in% names(match_df)) is_restored_row <- is_restored_row | match_df$is_restored %in% TRUE
  if ("hypothesis_type" %in% names(match_df)) {
    is_restored_row <- is_restored_row | match_df$hypothesis_type %in% "suppressed_candidate"
  }
  if ("restoration_basis" %in% names(match_df)) {
    is_restored_row <- is_restored_row | !is.na(match_df$restoration_basis)
  }
  n_restored_excluded <- sum(is_restored_row)
  match_df <- match_df[!is_restored_row, , drop = FALSE]

  # Each observation's TOP hit overall, kept only when it IS the genus's one
  # locally plausible species. Taking the best hit within a qualifying genus
  # instead admits rows whose matched reference is a different species (a
  # congener, or the sequence of an unreferenced species matching a relative)
  # and observations whose best match lies in another genus; both pull the
  # observed scores below the confident species' own, biasing the offset.
  top <- match_df |>
    dplyr::group_by(observation_id) |>
    dplyr::slice_max(.data[[score_col]], n = 1L, with_ties = FALSE) |>
    dplyr::ungroup()
  top$confident_species <- genus_summary$confident_species[
    match(top$genus, genus_summary$genus)
  ]
  n_top_in_genus <- sum(!is.na(top$confident_species))
  confident <- top[!is.na(top$confident_species) &
    top$taxon_name == top$confident_species, , drop = FALSE]
  confident$confident_genus <- confident$genus

  # The qualifying-genus count is conditional on which names count as
  # species: open-nomenclature and coarse names ("Ulva sp.", "Mazzaella cf.
  # splendens", "Cottidae") are left out, so say how many there were.
  n_species_names <- length(unique(sp_rank$taxon_name))
  message(sprintf(
    paste0(
      "identify_confident_observations: %d genus/genera with exactly one plausible ",
      "species; %d of %d species-rank prior name(s) are not binomials ",
      "(e.g. 'sp.', 'cf.', genus- or family-only) and were not counted."
    ),
    nrow(genus_summary), n_names_not_binomial, n_species_names
  ))
  attr(confident, "n_qualifying_genera") <- nrow(genus_summary)
  # top hits in a qualifying genus that were NOT the confident species
  attr(confident, "n_excluded_other_species") <- n_top_in_genus - nrow(confident)
  attr(confident, "n_prior_names_not_binomial") <- n_names_not_binomial
  attr(confident, "n_restored_rows_excluded") <- n_restored_excluded

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
#' @section Sigma correction:
#' `train_likelihood_model()` estimates the H1 spread from reference pairs. A
#' field query is a reference-like sequence plus sequencing and amplification
#' noise, so its scatter around a species' mean can only be wider. The
#' correction measures that extra scatter on the confident observations
#' (variance of their residuals, 5 percent trimmed each side, over the trained
#' variance) and widens the spread by it; it never narrows. The variance is
#' used because identity scores on a short amplicon take few distinct values,
#' on which a median absolute deviation can collapse to zero; an earlier
#' MAD-based version narrowed the spread that way and zeroed correct
#' candidates. With fewer than `min_sigma_obs` confident observations the
#' scatter cannot be measured, and the spread is held at the conservative
#' floor of 1.0 transform unit^2.
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
#' 12S case). The slope is NOT constrained to \[0, 1\]. A negative slope means
#' the observed query score falls as the trained mean rises, so the remap
#' reverses the order of the species' expected scores; a slope above 1 stretches
#' it. On real COI data (California intertidal, two sequencing platforms fitted
#' separately) the fitted slope was negative on both platforms (-11 to -67,
#' depending on the confident set). Held-out tests supported it: holding out
#' whole families, the unconstrained line predicted the observed scores of unseen
#' species better than a single pooled location (weighted RMSE 0.18 vs 0.20 and
#' 0.13 vs 0.16), and controlling for each species' number of reference
#' sequences left the slope almost unchanged. The cause is not established. On
#' 18S the fitted slope was positive and did no better than the pooled location.
#' Inspect `$Query_Calibration$slope` rather than assuming it lies in \[0, 1\]. Only the H1 mean *location* is remapped; the H2/H3
#' congener-divergence deltas (defined relative to the H1 mean) and the gap
#' feature -- the structure that actually discriminates between candidate
#' species -- are untouched.
#'
#' One caveat bears on choosing between the two forms. The confident set is
#' selection-biased toward abundant, well-sampled, easy genera, and by construction has exactly one plausible species per genus
#' -- so it can measure absolute H1 *location* fit but cannot directly test
#' congener *discrimination*. A `"linear"` fit whose slope collapses to 0 removes
#' per-species location structure that is demonstrably not real on the inference
#' scale, but that this validation set cannot independently confirm is safe to
#' remove in hard congener-vs-congener cases.
#'
#' A SECOND caveat is sharper, and it governs how the default should be read.
#' The confident set is built by thresholding `theta_mean`, and `theta_mean` is
#' a SHARE of a pool denominator that includes coarse-rank records -- rows that
#' name no species at all -- so every species' value is diluted by them. An
#' independent review measured 72 percent of 18S rows and 60 percent of COI
#' rows in that set as not confident, which moves the fitted COI constant
#' offset from -0.069 to -0.221. So the set cannot adjudicate between the two
#' forms, and the held-out ratios quoted in this section inherit the same
#' problem. `"constant"` is therefore the default because it is the SIMPLEST
#' correction to state and applies one method to every marker -- a stated
#' default, not a measured winner. Choosing between the forms on evidence has
#' to wait for a confident set built on an undiluted denominator.
#' `"linear"` is available when a marker's own evidence
#' supports a slope; it reduces to `"constant"` automatically wherever the
#' per-species means transfer exactly (slope 1). `"linear"` requires at least
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
#' length and quality (a 12S/18S comparison validated this design) and does
#' not transfer as
#' either a fixed percentage or a fixed mismatch count. The same applies
#' across `score_transform` values: the offset is estimated on
#' whichever scale `model_params$Score_Transform` says the model was trained
#' on (read automatically), but a `"logit"`-scale offset and a
#' `"sqrt_mismatch"`-scale offset are different numbers in different units --
#' never reuse one for the other, and always recompute after retraining with
#' a different `score_transform`.
#'
#' @section Bimodality diagnostic:
#' `train_likelihood_model()` fits ONE Gaussian per species for H1, and this
#' function's own `offset_form = "linear"` fits a single line across species
#' -- both assume the underlying H1 score distribution is unimodal. Mixing
#' sequencing platforms (or markers, or primer sets) inside one calibration
#' run breaks that assumption silently: a real Nanopore top-hit distribution
#' had a 20.3% spike at exactly 100 and a tail reaching
#' 94.1 at the 10th percentile, while Illumina data for the same marker was
#' tight and unimodal. Fitting one Gaussian (or one line) across a mix like
#' that lands the mean between the two modes, where almost nothing actually
#' is.
#'
#' This function now runs an internal two-component-normal-mixture-vs-BIC
#' check (see `.bimodality_check()`) on the SAME confident-observation score
#' vector (`p_norm * 100`, i.e. raw percent identity, computed before the
#' `score_transform` step) that the calibration itself fits. The check flags
#' bimodality only when a 2-component fit beats a 1-component fit by
#' `delta_bic > 10` (Kass & Raftery 1995's "very strong" evidence band -- see
#' `.bimodality_check()`'s own docs for the verified citation) AND the two
#' fitted component means are separated by more than 1 percentage point (or
#' further, on discrete data -- see the next section) AND the fitted mixture
#' has a genuine density dip between the two means AND the smaller component
#' holds real mass -- all four guard against a false positive from ordinary,
#' ceiling-skewed-but-genuinely-unimodal H1 data (the reason a simpler
#' bimodality-coefficient test was explicitly rejected for this diagnostic:
#' H1 scores pile up near 100% identity by construction, and a
#' skewness/kurtosis-based test would flag that shape on its own).
#'
#' @section Percent identity is discrete, not continuous:
#' A second, structurally different false positive was found on a real
#' PtConception 12S production run: this function warned "H1
#' scores look bimodal: 4% near 95.4 (sd 3.0) and 96% near 98.8 (sd 0.4),
#' delta BIC 8297" on data that is genuinely unimodal. The cause is that
#' percent identity on a short, fixed-length amplicon is DISCRETE -- a
#' ~167bp amplicon can only take values spaced by roughly one mismatch's
#' worth of identity (measured `0.6` apart on that run: the three most
#' common of 219 distinct raw match-object values were 98.8/99.4/98.2,
#' exactly `0.6` apart, i.e. one mismatch). Real match-score data therefore
#' forms a "comb" of spikes at each mismatch count, not a continuum, and a
#' comb has LITERAL zero density in the gaps between teeth -- not a real
#' valley between two populations, just quantization. A two-component
#' Gaussian mixture always beats one component on comb-like data (hence a
#' `delta_bic` in the thousands), and the pre-existing valley guard, built
#' to reject a smoothly ceiling-skewed unimodal shape, PASSES on a comb
#' precisely because a real (if spurious) dip genuinely sits between the
#' teeth there.
#'
#' `.bimodality_check()` now (1) estimates the identity-per-mismatch
#' quantum directly from the data (`NA` when the data don't look
#' comb-shaped at all -- most continuous data, including a genuine
#' Nanopore-vs-Illumina platform mixture, estimates no quantum and is
#' checked exactly as before); (2) when a quantum is found, deterministically
#' smooths the comb before fitting (spreading each tied group of
#' observations evenly across its own quantum-wide cell -- a dependency-free
#' continuity correction, closing the literal zero-density gaps between
#' teeth without disturbing a real multi-quantum gap between two genuinely
#' separate populations); (3) requires the minority component to hold real
#' mass (`>= 15%`) before calling it a mode -- a thin tail is not a second
#' population, and this alone rejects the false positive
#' above (its minority component held only 4%); and (4) requires the two
#' fitted means to be separated by more than a few QUANTA, not just the
#' flat `1.0` percentage point, since `1.0` is under two mismatches on a
#' 167bp amplicon. See `.estimate_score_quantum()`, `.smooth_comb()`, and
#' `.bimodality_check()`'s own docs for the full mechanism and the exact
#' thresholds, each justified against this run's own real numbers.
#'
#' When the check fires, this function emits exactly ONE `warning()` naming
#' the fitted structure in plain numbers (component weights, means, sds, and
#' `delta_bic`) and pointing at the remedy -- calibrating mixed platforms or
#' markers separately, which this function does NOT do for you. **This is a
#' diagnostic only**: it never changes any fitted value (the offset,
#' `offset_form`, slope/intercept, or sigma ratio are computed exactly as
#' they always were) and calibration is never refused -- a caller who ignores
#' the warning still silently gets the same, now-suspect single offset back.
#' `train_likelihood_model()` runs the identical check on its own H1 training
#' scores and RECORDS the result in `Stats$h1_bimodality` (no warning there --
#' this function is where the warning belongs, since it is the one place
#' *inference*-time calibration is actually about to apply a single, possibly
#' wrong, offset/line).
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
#' @param offset_form Character (default `"constant"`). `"constant"` adds one
#'   additive offset to every H1 mean: the query scale is shifted to the
#'   reference scale by the amount the confident observations require, and the
#'   per-species locations keep their relative positions. `"linear"` instead
#'   remaps each H1 mean through `intercept + slope * trained_mean`, fit on
#'   per-species medians of the confident observations, so how much per-species
#'   structure transfers is estimated rather than assumed. The default is
#'   `"constant"` because it is the simplest correction to state and applies
#'   one method to every marker -- NOT because a held-out comparison selected
#'   it. The confident set such comparisons rest on is built by thresholding
#'   `theta_mean`, which is a SHARE of a pool denominator containing
#'   coarse-rank records, so it cannot adjudicate between the two forms; see
#'   \emph{Level-aware recalibration}. The linear form's negative COI slope
#'   remains unexplained.
#'   `"linear"` falls back to `"constant"` (with a warning) when fewer than
#'   `min_calib_species` confident species, or no spread of trained means, are
#'   available.
#' @param min_calib_species Integer (default `8L`). Minimum number of distinct
#'   confident species (spanning a range of trained means) required to fit the
#'   `offset_form = "linear"` line. Ignored when `offset_form = "constant"`.
#' @param calibrate_sigma Logical (default `TRUE`). Widen the H1 spread by
#'   the measured extra scatter of field queries over reference pairs: the
#'   ratio of the residual variance (5 percent trimmed each side) to the
#'   trained variance, never below 1. See the Sigma correction section.
#' @param min_sigma_obs Integer (default `100L`). Fewest confident
#'   observations from which the field scatter is measured. Below it the H1
#'   spread is held at the conservative floor of 1.0 transform unit^2 (it is
#'   never narrowed where it cannot be checked); `$Query_Calibration$sigma_source`
#'   records which applied.
#' @param evidence_col Character or `NULL` (default `NULL`). Name of a column
#'   in `match_df` giving each observation's raw evidence quantity (e.g. DNA
#'   read depth, image detection count, acoustic recording duration). When
#'   supplied, the median of this quantity across the confident observations
#'   is stored as `reference_evidence` in the returned `$Query_Calibration`
#'   slot -- the baseline [evaluate_likelihoods()]`(evidence_col=)` divides a
#'   query's own evidence quantity by, at inference time, to scale H1 sigma
#'   per-observation (more evidence than this baseline tightens sigma, less
#'   widens it -- unlike the rejected flat `calibrate_sigma` correction above,
#'   this is validated per-observation, not as one population-wide constant,
#'   based on the observed within-species correlation). Median chosen for the same robustness reason as the mean
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
                                  offset_form = c("constant", "linear"),
                                  min_calib_species = 8L,
                                  calibrate_sigma = TRUE,
                                  min_sigma_obs = 100L,
                                  evidence_col = NULL,
                                  logit_epsilon = 1e-4,
                                  verbose = TRUE) {
  offset_form <- match.arg(offset_form)
  if (!inherits(model_params, "taxa_model_params")) {
    stop("calibrate_query_noise: 'model_params' must be a 'taxa_model_params' object from train_likelihood_model().",
      call. = FALSE
    )
  }

  # Reads model_params$Score_Transform and applies the matching
  # transform via .transform_p() (see below) -- the offset/residual/sigma-
  # ratio computation itself is scale-agnostic arithmetic (differences,
  # medians, ratios). Only the reference-vs-reference-vs-real-query NOISE
  # MAGNITUDE (the estimated offset itself) is marker/scale-specific and must be
  # (re-)estimated per model, never reused across markers OR across
  # transforms -- unchanged from this function's existing "Scope" guidance.
  # train_likelihood_model() always records this field; a model_params
  # object without it cannot be calibrated safely (guessing wrong here
  # would silently mis-scale the noise estimate).
  if (is.null(model_params$Score_Transform)) {
    stop(paste0(
      "calibrate_query_noise: model_params has no Score_Transform field. ",
      "train_likelihood_model() always records which transform (\"logit\" ",
      "or \"sqrt_mismatch\") the model was fit under, so this model_params ",
      "object cannot be calibrated. Retrain with train_likelihood_model()."
    ), call. = FALSE)
  }
  model_score_transform <- model_params$Score_Transform

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

  # Uncalibrated exits: with too few confident observations nothing is
  # measured, so the spread is held at the conservative floor (1.0 transform
  # unit^2) rather than left at the narrower reference-trained value.
  .floor_exit <- function(mp, n_obs, n_gen) {
    ratio <- 1
    if (calibrate_sigma) {
      gv <- mp$H1_Sigma["score_logit", "score_logit"]
      ratio <- max(1, 1.0 * .transform_unit_ratio(model_score_transform)^2 / gv)
      mp$H1_Sigma["score_logit", "score_logit"] <- gv * ratio
      mp$H1_Lookup$sigma_score <- mp$H1_Lookup$sigma_score * ratio
    }
    mp$Query_Calibration <- list(
      offset_logit = 0, offset_form = "constant", slope = 1, intercept = 0,
      sigma_ratio = ratio,
      sigma_source = if (calibrate_sigma) sprintf("conservative floor (%d confident observations < %d)", n_obs, min_sigma_obs) else "not calibrated",
      reference_evidence = NA_real_, n_confident_obs = n_obs,
      n_confident_genera = n_gen, plausibility_threshold = plausibility_threshold
    )
    mp
  }

  if (nrow(confident) < min_confident_obs) {
    warning(sprintf(
      "calibrate_query_noise: only %d confident observation(s) found (need >= %d). No offset applied; the H1 spread is held at the conservative floor.",
      nrow(confident), min_confident_obs
    ), call. = FALSE)
    return(.floor_exit(model_params, nrow(confident), n_confident_genera))
  }

  p_raw <- confident[[score_col]]
  p_norm <- if (max(p_raw, na.rm = TRUE) > 1) p_raw / 100 else p_raw
  observed_logit <- .transform_p(p_norm, model_score_transform, logit_epsilon)

  # Bimodality diagnostic (see @section Bimodality diagnostic
  # above) -- runs on the SAME confident-observation score vector the
  # calibration itself fits, on the raw percent-identity scale (p_norm * 100,
  # BEFORE the score_transform step) rather than the transformed
  # `observed_logit` -- see .bimodality_check()'s own `min_separation` docs
  # for why: a spike at exactly 100% identity has no natural distance-to-a-
  # second-mode interpretation once clipped onto the logit scale, while a
  # percentage-point gap is directly the unit the real motivating comparison
  # (Nanopore vs Illumina) is stated in. Never errors, never changes any
  # fitted value -- see that section for the full reasoning.
  h1_bimodal <- .bimodality_check(p_norm * 100)
  if (isTRUE(h1_bimodal$flag)) {
    # A ceiling point mass (queries identical to a reference) over one continuum
    # is the shape every reference-based score set has; the platform advice
    # applies only when both components are spread out.
    advice <- if (isTRUE(h1_bimodal$point_mass_at_ceiling)) {
      paste0(
        "The narrower component is a point mass at the ceiling (queries identical to a ",
        "reference), not a second population; one offset is fitted to the whole set and no ",
        "platform or marker split can change this shape."
      )
    } else {
      paste0(
        "A single linear offset fits neither component; if this run mixes sequencing ",
        "platforms or markers, calibrate them separately."
      )
    }
    warning(sprintf(
      paste0(
        "calibrate_query_noise: H1 scores look bimodal: %.0f%% near %.1f (sd %.1f) and ",
        "%.0f%% near %.1f (sd %.1f), delta BIC %.0f. %s"
      ),
      100 * h1_bimodal$weights[1], h1_bimodal$means[1], h1_bimodal$sds[1],
      100 * h1_bimodal$weights[2], h1_bimodal$means[2], h1_bimodal$sds[2],
      h1_bimodal$delta_bic, advice
    ), call. = FALSE)
  }

  global_mu_score <- as.numeric(model_params$H1_Global_Mu["score_logit"])
  lookup_idx <- match(confident$confident_species, model_params$H1_Lookup$lookup_key)
  # A confident species with no trained mean has no expected score to compare
  # with; its rows are left out rather than compared with the global mean.
  n_no_trained_mean <- sum(is.na(lookup_idx))
  if (n_no_trained_mean > 0L) {
    keep <- !is.na(lookup_idx)
    confident <- confident[keep, , drop = FALSE]
    observed_logit <- observed_logit[keep]
    p_norm <- p_norm[keep]
    lookup_idx <- lookup_idx[keep]
  }
  expected_logit <- model_params$H1_Lookup$mu_score[lookup_idx]
  if (length(expected_logit) < min_confident_obs) {
    warning(sprintf(
      "calibrate_query_noise: only %d confident observation(s) have a trained species mean (need >= %d). No offset applied; the H1 spread is held at the conservative floor.",
      length(expected_logit), min_confident_obs
    ), call. = FALSE)
    return(.floor_exit(model_params, length(expected_logit), length(unique(confident$confident_genus))))
  }

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
  # Field-query widening: variance (5% trimmed each side) of the residuals
  # over the trained variance, never below 1 -- a field read is a
  # reference-like sequence plus noise, so it cannot be tighter than the
  # references. A MAD-based ratio collapses to 0 on the discrete identity
  # scores of a short amplicon and was the narrowing that once zeroed correct
  # candidates.
  # With too few confident observations to measure it, the field scatter is
  # not estimated and the spread is held at the conservative floor of 1.0
  # transform unit^2 instead (the earlier fixed value), so nothing narrows
  # where it cannot be checked.
  n_res <- sum(is.finite(residuals))
  sigma_source <- "not calibrated"
  sigma_ratio <- if (!calibrate_sigma) {
    1
  } else if (n_res >= min_sigma_obs) {
    sigma_source <- "measured"
    r <- residuals[is.finite(residuals)]
    q <- stats::quantile(r, c(0.05, 0.95), names = FALSE)
    r <- pmin(pmax(r, q[1]), q[2])
    max(1, stats::var(r) / global_sigma_score)
  } else {
    sigma_source <- sprintf("conservative floor (%d confident observations < %d)", n_res, min_sigma_obs)
    max(1, 1.0 * .transform_unit_ratio(model_score_transform)^2 / global_sigma_score)
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
    sigma_source = sigma_source,
    reference_evidence = reference_evidence,
    n_confident_obs = nrow(confident),
    n_confident_genera = n_confident_genera,
    n_excluded_other_species = attr(confident, "n_excluded_other_species") %||% NA_integer_,
    n_restored_rows_excluded = attr(confident, "n_restored_rows_excluded") %||% NA_integer_,
    n_excluded_no_trained_mean = n_no_trained_mean,
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
