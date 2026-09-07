# ==============================================================================
# WORKFLOW: CALIBRATE tau AND score_sharpness JOINTLY (TaxaLikely)
# ==============================================================================
# Purpose: sweep correct_training_bias()'s tau AND assign_scores()'s
# score_sharpness together over a 2D grid, evaluate calibration quality
# (log-loss) and top-1 accuracy against real known ground truth, rather than
# trust either parameter's theoretical/inherited default in isolation.
#
# WHY JOINT, NOT SEQUENTIAL: the two parameters interact. tau reweights raw
# scores (score / n^tau) before normalization, changing the RELATIVE GAP
# between candidates; score_sharpness then decides how much that gap gets
# amplified into a likelihood difference (exp(score_sharpness * sc_norm)).
# Tuning one while holding the other at an untested default risks attributing
# an effect to the wrong parameter. This script replaces an earlier tau-only
# version once a real, separate bug was found and fixed in assign_scores()
# (see TaxaLikely/R/assign_scores.R's score-scale auto-detection): the
# original tau-only sweep on this same photo set showed log-loss essentially
# FLAT across all tau (2.4624 to 2.4638, a 0.05% relative range) while
# accuracy swung 22 points non-monotonically -- traced to score_likelihood
# collapsing to near-uniform (~0.999-1.000) for EVERY candidate in EVERY
# photo, independent of tau entirely. Root cause: .normalize_scores() forced
# iNaturalist's unbounded combined_score through a fixed 0-100 divisor
# (correct for BLAST-style percent-identity, wrong for combined_score, which
# real data shows reaching ~3000), compressing nearly all discriminating
# signal before tau or score_sharpness ever got a chance to matter. That bug
# is now fixed (auto-detected, no config needed) -- this script re-asks the
# calibration question on top of correctly-scaled data.
#
# WHY LOG-LOSS, NOT JUST ACCURACY: this correction feeds a Bayesian
# posterior downstream (TaxaAssign::compute_posterior()) -- the MAGNITUDE of
# the likelihood matters there, not just which candidate wins. Log-loss is a
# proper scoring rule for calibration; accuracy only checks the argmax and
# can't distinguish "correct and confident" from "correct and barely."
# Accuracy is still reported alongside for interpretability.
#
# WHY NEITHER PARAMETER IS SHARED ACROSS DATA TYPES: image (n_observations,
# iNaturalist) and acoustic (n_recordings, Xeno-canto) are different count
# sources with different noise/scale profiles -- Session 128 already found
# tau=1.0 helped acoustic (88%->93%) while (before this session's bug fix)
# appearing to hurt image. Run this script once per data type with COUNT_COL
# and MATCH_OBJ changed; do not assume one (tau, score_sharpness) pair fits
# both.
#
# REQUIRES: taxamatch_image_match_obj (or the acoustic equivalent) already
# loaded, with true_species and the count column populated, and the
# taxonomic-scope filter (TARGET_ICONIC_TAXA) already applied upstream --
# see score_image_workflow.R. This sweep assumes clean, in-scope candidate
# data; contaminated data (off-scope candidates like plants/birds) confounds
# the parameter estimate with scope-filter effects instead of isolating
# tau/score_sharpness's own.
# ==============================================================================

# ==============================================================================
# CONFIG
# ==============================================================================

# Object to sweep -- point this at whichever real checkpoint you want to
# calibrate against. Image: taxamatch_image_match_obj (from TaxaMatch::
# score_image_workflow.R). Acoustic: swap in the acoustic match object and
# change COUNT_COL to "n_recordings".
MATCH_OBJ <- taxamatch_image_match_obj
COUNT_COL <- "n_observations"
RANK_SYSTEM <- c("family", "genus", "species")

# assign_scores()'s score_type -- must match the pathway this data type
# actually uses downstream, NOT left at one hardcoded value for every data
# type. Image (iNaturalist combined_score, unbounded): "similarity_softmax",
# score_sharpness matters and is swept below. Acoustic (BirdNET confidence,
# already 0-1 bounded): "probability" -- a different code path that never
# references score_sharpness at all (see assign_scores.R); the sharpness
# grid is skipped automatically when SCORE_TYPE != "similarity_softmax"/
# "similarity", so acoustic calibration only sweeps tau.
SCORE_TYPE <- "similarity_softmax"

# Grids for the initial 2D sweep (coarse, for the printed table); a
# continuous 2D optimizer refines around the grid's best combination
# afterward. tau's range extends past 1.0 -- Menon et al. 2020's own
# CIFAR-10-LT tuned optimum was 2.6 (their theoretical Fisher-consistent
# value is 1.0, but their empirically best value was well above it), so
# ruling out tau > 1 a priori would be assuming the answer.
# score_sharpness grid is roughly log-spaced (it multiplies inside exp(),
# so linear spacing over-samples large values and under-samples small ones).
# Ignored entirely (collapsed to a single dummy value) when SCORE_TYPE is
# "probability" -- see SCORE_TYPE's own comment above.
TAU_GRID <- seq(0, 2, by = 0.25)
SHARPNESS_GRID <- if (SCORE_TYPE %in% c("similarity_softmax", "similarity")) {
  c(0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10)
} else {
  0.1 # unused by "probability"/"none"/"direct"; kept as a single valid placeholder
}

# ==============================================================================
# 1.  VALIDATE INPUT
# ==============================================================================

if (!is.data.frame(MATCH_OBJ)) {
  stop(
    "calibrate_training_bias_tau: MATCH_OBJ must be a data frame -- ",
    "point CONFIG's MATCH_OBJ at a real, already-scored match object."
  )
}
if (!"true_species" %in% names(MATCH_OBJ)) {
  stop(
    "calibrate_training_bias_tau: MATCH_OBJ has no true_species column -- ",
    "this sweep needs real ground truth to evaluate against."
  )
}
if (!COUNT_COL %in% names(MATCH_OBJ)) {
  stop(sprintf(
    "calibrate_training_bias_tau: COUNT_COL \"%s\" not found in MATCH_OBJ.",
    COUNT_COL
  ))
}

message(sprintf(
  "Calibrating tau x score_sharpness on %d row(s), %d photo(s)/detection(s), count_col = \"%s\".",
  nrow(MATCH_OBJ), length(unique(MATCH_OBJ$observation_id)), COUNT_COL
))

# ==============================================================================
# 2.  HELPER: run one (tau, score_sharpness) pair through the full pipeline
# ==============================================================================

#' @noRd
.evaluate_params <- function(match_obj, tau, score_sharpness, count_col, rank_system,
                             score_type = SCORE_TYPE) {
  corrected <- TaxaLikely::correct_training_bias(
    match_obj,
    count_col = count_col, tau = tau
  )
  hyp <- TaxaLikely::unreferenced_candidates(corrected, rank_system = rank_system)
  lik <- TaxaLikely::assign_scores(
    hyp,
    score_type = score_type, score_sharpness = score_sharpness
  )

  # Renormalize score_likelihood to a genuine per-observation probability
  # distribution -- assign_scores()'s own output is ratio-normalized to the
  # WINNER's score (winner always = 1.0 by construction), not a distribution
  # that sums to 1. Needed for log-loss, not needed for accuracy.
  lik <- lik |>
    dplyr::group_by(observation_id) |>
    dplyr::mutate(p = score_likelihood / sum(score_likelihood, na.rm = TRUE)) |>
    dplyr::ungroup()

  true_lookup <- match_obj |> dplyr::distinct(observation_id, true_species)

  # Probability mass assigned to the TRUE species specifically (not its
  # genus/family unreferenced placeholder). A photo whose true species never
  # appears among any candidate row at all is a scope/CV miss, not a
  # tau/score_sharpness problem -- floored at a small epsilon so it still
  # penalizes log-loss (correctly) without producing -Inf, and counted
  # separately below so it doesn't get silently absorbed into "these
  # parameters are bad" when they had nothing to do with it.
  true_match <- lik |>
    dplyr::filter(taxon_name == true_species) |>
    dplyr::group_by(observation_id) |>
    dplyr::summarise(p_true = sum(p, na.rm = TRUE), .groups = "drop")

  per_photo <- true_lookup |>
    dplyr::left_join(true_match, by = "observation_id") |>
    dplyr::mutate(
      complete_miss = is.na(p_true),
      p_true = pmax(ifelse(is.na(p_true), 0, p_true), 1e-6),
      log_loss = -log(p_true)
    )

  # Top-1 accuracy (winner = max score_likelihood per observation_id).
  # true_species is already a passthrough column on lik (survives
  # unreferenced_candidates()/assign_scores() unchanged) -- do NOT re-join
  # true_lookup here, it duplicates the column into true_species.x/.y and
  # breaks the bare reference below (same class of footgun as TaxaID/
  # CLAUDE.md's documented taxon_match/geo_match .x/.y collision).
  top1 <- lik |>
    dplyr::group_by(observation_id) |>
    dplyr::slice_max(score_likelihood, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::mutate(correct = taxon_name == true_species)

  data.frame(
    tau             = tau,
    score_sharpness = score_sharpness,
    mean_log_loss   = mean(per_photo$log_loss),
    accuracy        = mean(top1$correct, na.rm = TRUE),
    n_correct       = sum(top1$correct, na.rm = TRUE),
    n_complete_miss = sum(per_photo$complete_miss),
    n_photos        = nrow(true_lookup)
  )
}

# ==============================================================================
# 3.  COARSE 2D SWEEP
# ==============================================================================

.grid <- expand.grid(tau = TAU_GRID, score_sharpness = SHARPNESS_GRID)

# assign_scores()'s scale-detection message is a one-time diagnostic fact
# about this dataset (does score_col exceed 100 anywhere?), not something
# worth repeating once per grid cell -- print it here, explicitly, once, then
# suppress it for the sweep itself so the results table isn't buried under
# dozens of identical lines.
invisible(.evaluate_params(MATCH_OBJ, TAU_GRID[1], SHARPNESS_GRID[1], COUNT_COL, RANK_SYSTEM))

message(sprintf("\n--- Sweeping %d (tau, score_sharpness) combination(s) ---", nrow(.grid)))

results <- suppressMessages(dplyr::bind_rows(lapply(seq_len(nrow(.grid)), function(i) {
  .evaluate_params(MATCH_OBJ, .grid$tau[i], .grid$score_sharpness[i], COUNT_COL, RANK_SYSTEM)
})))

message("Sweep complete. Top 15 combinations by log-loss:")
print(head(results[order(results$mean_log_loss), ], 15))

.best_grid <- results[which.min(results$mean_log_loss), ]
message(sprintf(
  "\nBest on the grid (by log-loss): tau = %.2f, score_sharpness = %.2f (log-loss = %.4f, accuracy = %.0f%%)",
  .best_grid$tau, .best_grid$score_sharpness, .best_grid$mean_log_loss, 100 * .best_grid$accuracy
))

# Log-loss minimized over score_sharpness at each tau -- shows tau's own
# marginal effect once score_sharpness is no longer held at an untested
# default, without needing the full 2D table to read that off.
.by_tau <- results |>
  dplyr::group_by(tau) |>
  dplyr::slice_min(mean_log_loss, n = 1, with_ties = FALSE) |>
  dplyr::ungroup() |>
  dplyr::arrange(tau)
message("\nBest score_sharpness at each tau (log-loss-minimizing):")
print(as.data.frame(.by_tau))

# ==============================================================================
# 4.  CONTINUOUS 2D REFINEMENT AROUND THE GRID OPTIMUM
# ==============================================================================
# stats::optim() with box constraints refines within the grid's range using
# the grid optimum as the starting point -- the printed grid table above is
# there specifically so a bimodal or non-monotonic surface would be visible
# before trusting the optimizer to have found a global, not local, minimum.

message("\n--- Continuous 2D refinement ---")

.opt <- suppressMessages(stats::optim(
  par    = c(.best_grid$tau, .best_grid$score_sharpness),
  fn     = function(p) .evaluate_params(MATCH_OBJ, p[1], p[2], COUNT_COL, RANK_SYSTEM)$mean_log_loss,
  method = "L-BFGS-B",
  lower  = c(0, 0.01),
  upper  = c(max(TAU_GRID), max(SHARPNESS_GRID) * 2)
))

message(sprintf(
  "Continuous optimum: tau = %.3f, score_sharpness = %.3f (log-loss = %.4f)",
  .opt$par[1], .opt$par[2], .opt$value
))

.final <- .evaluate_params(MATCH_OBJ, .opt$par[1], .opt$par[2], COUNT_COL, RANK_SYSTEM)
message(sprintf(
  "At this optimum: accuracy = %d/%d (%.0f%%)",
  .final$n_correct, .final$n_photos, 100 * .final$accuracy
))

message(sprintf(
  "\nFor reference -- tau=0, score_sharpness=0.1 (no correction, old default): log-loss = %.4f, accuracy = %.0f%%",
  results$mean_log_loss[results$tau == 0 & results$score_sharpness == 0.1],
  100 * results$accuracy[results$tau == 0 & results$score_sharpness == 0.1]
))
message(sprintf(
  "                  tau=1, score_sharpness=0.1 (Session 127 default before this fix): log-loss = %.4f, accuracy = %.0f%%",
  results$mean_log_loss[results$tau == 1 & results$score_sharpness == 0.1],
  100 * results$accuracy[results$tau == 1 & results$score_sharpness == 0.1]
))

# ==============================================================================
# Output
# ==============================================================================
# results  -- one row per grid (tau, score_sharpness) pair: mean_log_loss,
#   accuracy, n_correct, n_complete_miss (photos whose true species never
#   appeared among any candidate -- a scope/CV limitation, not something
#   either parameter can fix), n_photos.
# .opt$par -- continuous-optimized (tau, score_sharpness) (log-loss minimizing).
#
# Next: re-run with COUNT_COL <- "n_recordings" and MATCH_OBJ <- the acoustic
# match object to get an independent (tau, score_sharpness) pair for that
# pathway -- do not assume the image result transfers.
# ==============================================================================
