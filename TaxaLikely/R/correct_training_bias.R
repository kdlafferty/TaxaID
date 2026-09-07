# ==============================================================================
# correct_training_bias()
# ==============================================================================

#' Correct classifier scores for training-database representation bias
#'
#' Discriminative classifiers (iNaturalist CV, BirdNET) trained by standard
#' cross-entropy estimate a Bayes posterior: their raw output for species
#' \eqn{i} is proportional to \eqn{L(obs \mid species_i) \times n_i}, where
#' \eqn{L(obs \mid species_i)} is the true visual/acoustic likelihood and
#' \eqn{n_i} is the number of training examples for species \eqn{i}. Raw
#' classifier scores therefore favor well-represented (common, well-
#' photographed/recorded) taxa over rare ones with equal true evidential
#' support. This function divides out an estimate of that training-count
#' bias so that scores across candidates are on a more comparable scale
#' before [assign_scores()] normalizes them.
#'
#' @details
#' ## Logit adjustment (Menon et al. 2020), not adaptive per-candidate shrinkage
#' The correction is \eqn{score_i / n_i^{\tau}}, where \eqn{\tau} is a single
#' **global, user-set scalar** applied identically to every candidate,
#' following the "logit adjustment" correction for long-tailed recognition
#' (Menon, Jayasumana, Rawat, Jain, Veit & Kumar, "Long-Tail Learning via
#' Logit Adjustment", ICLR 2021, arXiv:2007.07314). Their adjustment
#' subtracts \eqn{\tau \log(\pi_i)} from class \eqn{i}'s logit, where
#' \eqn{\pi_i} is class \eqn{i}'s training-set frequency; exponentiating,
#' this is equivalent to dividing the raw (pre-softmax) score by
#' \eqn{\pi_i^{\tau}}. Because \eqn{\pi_i = n_i / N} for a constant \eqn{N}
#' (total training count) shared by every candidate being compared for the
#' same observation, dividing by \eqn{n_i^{\tau}} instead of
#' \eqn{\pi_i^{\tau}} gives identical relative rankings and ratios among
#' candidates -- so \eqn{N} does not need to be known or estimated here.
#'
#' At \eqn{\tau = 1}, this fully removes the \eqn{n_i} factor,
#' recovering an estimate of the true likelihood \eqn{L_i} exactly under the
#' \eqn{score_i \propto L_i \times n_i} model -- the value Menon et al. derive
#' as Fisher-consistent for the class-balanced error from Bayes' rule
#' directly. The default is `tau = 0` (no correction), not `1` -- see
#' "Default changed (Session 151)" below for why. \eqn{\tau} remains a
#' tunable argument (not hardcoded to any one value) because Menon et al.'s
#' own empirical tuning did not always land on 1 --
#' on CIFAR-10-LT they found a validation-tuned optimum of 2.6, i.e.
#' *stronger* correction than the naive theoretical default improved
#' balanced accuracy further in that setting.
#'
#' ## This differs from the Session 125 version of this function
#' The original implementation used an **adaptive, per-candidate** exponent
#' \eqn{\tau_i = n_i / (n_i + prior\_weight)}, intended to shrink correction
#' strength toward zero for candidates with small \eqn{n_i} (treating a
#' small public-database count as a less trustworthy proxy). Literature
#' research (Session 127) found no support for a per-candidate adaptive
#' exponent in the long-tail/class-imbalance literature -- the standard,
#' theoretically justified form (logit adjustment) uses one fixed scalar
#' applied uniformly regardless of a given candidate's own \eqn{n_i}. The
#' adaptive version was also demonstrated to behave almost like a step
#' function centered on the candidate set's median count: candidates below
#' the median were barely corrected while candidates above it were divided
#' by nearly their full raw count, meaning any two candidates with
#' comparable raw scores but very different \eqn{n} would have the
#' correction decide the outcome almost entirely in favor of the lower-n
#' candidate regardless of which one was actually correct. This revision
#' replaces that scheme.
#'
#' ## Open caveat: noisy proxy counts
#' Menon et al.'s Fisher-consistency guarantee formally assumes \eqn{\pi_i}
#' (here, \eqn{n_i}) is a consistent estimate of the classifier's *actual*
#' internal training-set frequency. In this package's use case, \eqn{n_i} is
#' instead a noisy **external proxy** -- a public database's observation or
#' recording count (iNaturalist, Xeno-canto) -- not the classifier's true
#' internal training count, which is unknown. The literature research
#' conducted for this revision found no paper that directly studies how much
#' this guarantee degrades under a noisy external proxy; this is a genuine
#' open gap, not a settled question. \eqn{\tau} is therefore left tunable
#' (not fixed at the theoretical default) so it can be validated empirically
#' -- e.g. by bucketing real labeled observations by the log-ratio of the
#' true species' count to its best wrong competitor's count, and checking
#' whether correction helps or hurts accuracy in each bucket -- once enough
#' labeled data exists, rather than trusted uncritically at \eqn{\tau = 1}.
#'
#' **First real-data look (Session 128):** wired into
#' `TaxaLikely/inst/workflows/image_acoustic_likelihood_workflow.R` at
#' \eqn{\tau = 1} and run against real classifier output. Result was
#' data-type-dependent, not uniformly good or bad -- on 6 real camera-trap
#' photos, correction changed 2 winners and top-1 accuracy fell (5/6 to
#' 4/6): one flip was wrong-to-wrong (neutral) but the other was a correct
#' call turned wrong (*Sylvilagus bachmani* misassigned to *Megascops
#' kennicottii*, an owl -- likely driven by a very large `n_observations`
#' spread among candidates on such a small photo set). On 42 real BirdNET
#' sandpiper detection windows, correction changed 2 winners and top-1
#' accuracy rose (37/42 to 39/42), both flips wrong-to-right. Recorded at
#' the time as a first look, not a calibration, because both sets were
#' small -- see Session 129's resolution below for what actually turned out
#' to be true, and why the image number specifically needed revisiting.
#'
#' **Resolved for image (Session 129), superseding the number above:** the
#' original 5/6->4/6 image result was confounded by an unrelated real bug in
#' [assign_scores()] -- `.normalize_scores()` forced iNaturalist's unbounded
#' `combined_score` (real data reaches ~3000) through a fixed 0-100 divisor
#' meant for BLAST-style percent-identity scores, collapsing
#' `score_likelihood` to near-uniform (~0.999-1.000) for every candidate in
#' every photo, independent of \eqn{\tau} entirely -- so the 5/6->4/6 swing
#' was mostly argmax noise on a nearly flat distribution, not a clean read on
#' \eqn{\tau}'s effect. That bug is fixed (score scale is now auto-detected,
#' no configuration needed -- see `assign_scores()`'s own documentation).
#' Re-run on 51 real, taxonomic-scope-filtered camera-trap photos (8 species)
#' with `assign_scores()`'s `score_sharpness` calibrated jointly with
#' \eqn{\tau} (log-loss-minimizing, `TaxaLikely/inst/workflows/
#' calibrate_training_bias_tau.R`): log-loss and accuracy now agree, and
#' both are monotonic in \eqn{\tau} -- log-loss rises and accuracy falls
#' steadily from \eqn{\tau = 0} (82% top-1 accuracy) to \eqn{\tau = 1} (63%)
#' and beyond. **For this image pathway, \eqn{\tau \approx 0} is optimal --
#' the correction should not be applied.** The acoustic result above was
#' never affected by the `assign_scores()` bug in the first place (BirdNET
#' confidence is already 0-1 bounded and uses `score_type = "probability"`,
#' which does not call `.normalize_scores()` at all), but did NOT hold up
#' on its own terms -- see the next paragraph.
#'
#' **Acoustic re-tested at scale (Session 133), reversing the result above:**
#' the 42-window/3-species pilot's \eqn{\tau \approx 1} finding was flagged
#' by the user as too thin an evidence base and re-run on a deliberately
#' larger, more representative real dataset -- 8 confusable clusters, 24
#' species, 2487 real BirdNET detection windows. Pooled result:
#' \eqn{\tau \approx 0} is optimal for acoustic too, matching image, not
#' opposing it -- log-loss and accuracy both get monotonically worse from
#' \eqn{\tau = 0} through \eqn{\tau = 6}. Per-cluster results are genuinely
#' heterogeneous, though (2 of 8 clusters still prefer high \eqn{\tau} even
#' at ~150-170 windows each, unbracketed at the swept grid's edge) -- a
#' single global \eqn{\tau} does not fit this data well even now that the
#' pooled default has flipped; see
#' `ecosystem_docs/REENTRY_PROMPT_acoustic_tau_calibration_expanded.md` for
#' the full per-cluster breakdown.
#'
#' **Default changed (Session 151):** every real calibration run against
#' this function so far -- image (Session 129) and acoustic, on both the
#' original small pilot AND the later, properly-powered re-test (Session
#' 133) -- found \eqn{\tau \approx 0} optimal, not the theoretical
#' \eqn{\tau = 1}. The default changed from `1.0` to `0` accordingly: a
#' user who does nothing now gets no correction (matching every real result
#' obtained so far) rather than a correction contradicted by every real
#' result obtained so far. This is **not** a claim that \eqn{\tau = 0} is
#' correct in general or for every data type -- only that it is the
#' evidence-backed starting point given what has actually been measured.
#' \eqn{\tau} (and, for the `similarity_softmax` pathway, `score_sharpness`)
#' should still be calibrated per data type -- and, per the acoustic
#' per-cluster result above, potentially per taxon cluster -- before being
#' raised. Run `calibrate_training_bias_tau.R` against real labeled data for
#' any new data type before deciding whether to apply this correction at all.
#'
#' ## Missing or zero counts: deliberate deviation from strict logit adjustment
#' Strict logit adjustment assumes every class's \eqn{\pi_i} is known.
#' Candidates with `NA` or non-positive counts (failed lookups, or species
#' genuinely absent from the public database) instead fall through to the
#' **uncorrected** score (\eqn{\tau} effectively 0 for that row only) --
#' the same conservative choice made by the Session 125 version, and
#' retained here as a deliberate, practical deviation from the pure
#' literature form: applying full correction based on a missing or zero
#' count would either be undefined (division by zero at \eqn{\tau > 0}) or
#' arbitrary, and whether a zero/NA reflects genuine rarity or a lookup
#' failure cannot be distinguished from the count alone.
#'
#' ## Column contract
#' `score_col` is overwritten in place with the corrected value, so no
#' downstream call (e.g. [unreferenced_candidates()], [assign_scores()])
#' needs to change -- they already consume `score_col` by default. The
#' pre-correction value is preserved under `score_uncorrected` for
#' debugging. Diagnostic columns `n_used` (the count actually applied,
#' `NA` preserved as-is) and `tau_used` (the exponent actually applied per
#' row -- either the global `tau` or 0 for a fallen-through row) are also
#' added.
#'
#' ## Pipeline placement
#' Run this on the raw multi-candidate classifier output, before
#' [unreferenced_candidates()] adds H2/H3 placeholder rows -- those rows
#' have no real score to correct and are anchored off the corrected H1
#' rows downstream:
#' \preformatted{
#' raw scored_df -> correct_training_bias() -> unreferenced_candidates() -> assign_scores()
#' }
#'
#' @param scored_df Data frame of raw classifier output, one row per
#'   candidate species per observation. Must contain `score_col`.
#' @param count_col Character scalar. Name of the column holding each
#'   candidate's training-database representation count (e.g.
#'   `"n_observations"` for iNaturalist CV output, `"n_recordings"` for
#'   BirdNET/Xeno-canto output after joining
#'   `audit_acoustic_coverage(xc_recordings = TRUE)`'s census onto
#'   `scored_df` by taxon). If absent from `scored_df`, a warning is
#'   issued and every row falls through unchanged (equivalent to all
#'   counts being `NA`).
#' @param score_col Character scalar (default `"score_original"`, matching
#'   [assign_scores()]'s default `score_col`). Name of the raw score
#'   column to correct.
#' @param tau Non-negative numeric scalar (default `0`, changed from `1.0`
#'   in Session 151 -- see "Default changed" in Details). Global exponent
#'   applied to every candidate's count (see Details) -- `tau = 0` disables
#'   correction entirely (returns scores unchanged); `tau = 1` is the
#'   theoretically Fisher-consistent full correction; values above 1 apply
#'   stronger-than-theoretical correction (Menon et al.'s own tuned optimum
#'   on one benchmark was 2.6). Every real calibration run against this
#'   function's own real classifier output so far (image, and acoustic on a
#'   properly powered re-test) found `tau ~= 0` optimal -- raise it only
#'   after calibrating against real labeled data for your own data type
#'   (see Details).
#'
#' @return `scored_df` with `score_col` overwritten by the corrected
#'   score, plus three added columns: `score_uncorrected` (pre-correction
#'   value), `n_used` (count applied per row, `NA` where unavailable),
#'   and `tau_used` (exponent actually applied per row).
#'
#' @seealso [assign_scores()], [unreferenced_candidates()]
#'
#' @references Menon, A. K., Jayasumana, S., Rawat, A. S., Jain, H., Veit,
#'   A., & Kumar, S. (2021). Long-Tail Learning via Logit Adjustment. ICLR
#'   2021. \url{https://arxiv.org/abs/2007.07314}
#'
#' @examples
#' scored <- data.frame(
#'   observation_id = c("obs1", "obs1", "obs2"),
#'   taxon_name     = c("Turdus migratorius", "Turdus merula", "Limosa fedoa"),
#'   score_original = c(0.9, 0.85, 0.6),
#'   n_observations = c(500000, 20, 300)
#' )
#' corrected <- correct_training_bias(scored, count_col = "n_observations")
#' corrected[, c(
#'   "taxon_name", "score_uncorrected", "score_original",
#'   "n_used", "tau_used"
#' )]
#'
#' @export
correct_training_bias <- function(scored_df,
                                  count_col,
                                  score_col = "score_original",
                                  tau = 0) {
  if (!is.data.frame(scored_df)) {
    stop("correct_training_bias: 'scored_df' must be a data frame.", call. = FALSE)
  }
  if (!is.character(score_col) || length(score_col) != 1L || is.na(score_col)) {
    stop("correct_training_bias: 'score_col' must be a single character string.",
      call. = FALSE
    )
  }
  if (!score_col %in% names(scored_df)) {
    stop(sprintf(
      "correct_training_bias: column '%s' not found in 'scored_df'.",
      score_col
    ), call. = FALSE)
  }
  if (!is.numeric(scored_df[[score_col]])) {
    stop(sprintf("correct_training_bias: column '%s' must be numeric.", score_col),
      call. = FALSE
    )
  }
  if (!is.character(count_col) || length(count_col) != 1L || is.na(count_col)) {
    stop("correct_training_bias: 'count_col' must be a single character string.",
      call. = FALSE
    )
  }
  if (!is.numeric(tau) || length(tau) != 1L || is.na(tau) || tau < 0) {
    stop("correct_training_bias: 'tau' must be a single non-negative numeric value.",
      call. = FALSE
    )
  }

  score <- scored_df[[score_col]]

  if (!count_col %in% names(scored_df)) {
    warning(
      sprintf(
        "correct_training_bias: column '%s' not found in 'scored_df' -- ",
        count_col
      ),
      "no bias correction applied; every row falls through unchanged.",
      call. = FALSE
    )
    n <- rep(NA_real_, nrow(scored_df))
  } else {
    n <- as.numeric(scored_df[[count_col]])
  }

  if (any(n < 0, na.rm = TRUE)) {
    stop(sprintf(
      "correct_training_bias: '%s' contains negative values -- must be a non-negative count or NA.",
      count_col
    ), call. = FALSE)
  }

  # Rows with NA or non-positive counts fall through to the uncorrected
  # score (tau_used = 0 for that row only) -- see @details "Missing or zero
  # counts". n_for_power = 0 in this case too so 0^0 = 1 regardless (R's
  # power operator treats x^0 = 1 for any x, including NA).
  .bad <- is.na(n) | n <= 0
  n_for_power <- ifelse(.bad, 0, n)
  tau_used <- ifelse(.bad, 0, tau)

  scored_df$score_uncorrected <- score
  scored_df[[score_col]] <- score / (n_for_power^tau_used)
  scored_df$n_used <- n
  scored_df$tau_used <- tau_used

  scored_df
}
