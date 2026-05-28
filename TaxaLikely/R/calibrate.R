# ==============================================================================
# calibrate.R
# TaxaLikely -- Coverage quality calibration for reference pair datasets
#
# Exported functions:
#   calibrate_coverage_filter()  Sweep coverage thresholds; return breadth and
#                                H1/H2 discrimination metrics per threshold
#   coverage_threshold()         Quantile-based coverage threshold selection
#
# Internal helpers:
#   .detect_finest_rank_col()    Auto-detect finest rank from .x/.y column pairs
# ==============================================================================


# ------------------------------------------------------------------------------
# Internal helper
# ------------------------------------------------------------------------------

#' @noRd
.detect_finest_rank_col <- function(df) {
  # Find all ranks present as paired .x / .y columns in df, then return the
  # finest (last in TaxaTools::standard_ranks, which runs coarse-to-fine).
  x_ranks <- sub("\\.x$", "", grep("\\.x$", names(df), value = TRUE))
  y_ranks <- sub("\\.y$", "", grep("\\.y$", names(df), value = TRUE))
  paired  <- intersect(x_ranks, y_ranks)
  if (length(paired) == 0L) return(NULL)
  std     <- TaxaTools::standard_ranks   # coarse-to-fine: kingdom ... species
  ordered <- std[std %in% paired]
  if (length(ordered) == 0L) return(paired[length(paired)])
  ordered[length(ordered)]   # last element = finest rank
}


# ==============================================================================
# calibrate_coverage_filter
# ==============================================================================

#' Calibrate a coverage filter for reference pairs
#'
#' Sweeps a grid of coverage thresholds over the pairwise reference dataset
#' produced by [build_sequence_matrix()] or [build_acoustic_reference()] and
#' returns per-threshold metrics quantifying the trade-off between retaining
#' query breadth and discriminating H1 (within-species) pairs from H2/H3
#' (cross-species) noise.
#'
#' @section Motivation:
#' Match scores (`p_match`) measure how similar two sequences or audio clips
#' are, but they do not capture *how much* of each observation contributed to
#' that score.  A 99% DNA identity computed from a 50 bp fragment of a 600 bp
#' barcode is far less reliable than the same identity computed from a 580 bp
#' overlap — yet both produce the same `p_match` value.  Similarly, a high
#' BirdNET confidence from a rain-soaked recording of a distant bird carries
#' less information than the same score from a quiet, close-range recording.
#'
#' The `coverage` column added by [build_sequence_matrix()] (pairwise alignment
#' overlap fraction) and [build_acoustic_reference()] (Xeno-canto quality grade
#' mapped to 0–1) places both data types on a common scale.  Removing low-coverage
#' pairs before model training filters out low-information observations that can
#' blur the H1/H2 boundary and inflate model variance.
#'
#' The threshold that maximises Youden's J is Pareto-optimal: it retains the
#' most H1 information while discarding the most H2/H3 noise.
#'
#' @section Metrics returned:
#' \describe{
#'   \item{`breadth`}{Fraction of unique queries (`id_x`) that still have at
#'     least one pair surviving the filter.  Decreasing breadth means some
#'     observations are completely excluded from training.}
#'   \item{`h1_retention`}{Fraction of within-species (H1) pairs retained
#'     relative to the unfiltered dataset.  Analogous to sensitivity in ROC
#'     analysis.}
#'   \item{`h2_retention`}{Fraction of cross-species (H2/H3) pairs retained.
#'     Analogous to (1 − specificity).}
#'   \item{`youden_j`}{Youden's J statistic: `h1_retention − h2_retention`.
#'     Bounded from -1 to 1; equals 0 at the no-filter baseline and is
#'     maximised at the Pareto-optimal threshold.  Treats H1 retention and
#'     H2/H3 exclusion symmetrically and has no divide-by-zero edge case.
#'     \emph{This is the primary criterion for threshold selection.}}
#'   \item{`discrimination`}{Ratio `h1_retention / h2_retention` (epsilon-guarded
#'     at 1e-9).  The multiplicative form of the same signal; useful for
#'     log-scale plots.  Equals 1.0 at the no-filter baseline; rises above 1.0
#'     when H1 pairs carry systematically higher coverage than H2/H3 pairs.}
#'   \item{`mean_h1_score`}{Mean `p_match` among retained H1 pairs.  Should
#'     be stable or increase slightly as low-coverage (and typically
#'     lower-scoring) H1 pairs are removed.}
#' }
#'
#' @section Acoustic data note:
#' Xeno-canto quality grades are properties of the *recording*, not the
#' individual detection pair.  Every pair produced from the same recording —
#' both H1 and H2/H3 — carries the same `coverage` value.  Filtering by
#' coverage therefore removes entire recordings and excludes H1 and H2/H3
#' pairs in equal proportion.  For acoustic reference data, `youden_j` and
#' `discrimination` will be near-flat across thresholds.  Use `breadth` and
#' `mean_h1_score` as the primary guides to decide which quality grades to
#' include.  The function detects categorical coverage (≤ 10 unique values)
#' and emits a message in this case.
#'
#' @param ref_pairs Data frame.  Output of [build_sequence_matrix()] or
#'   [build_acoustic_reference()].  Must contain columns `coverage`, `p_match`,
#'   `id_x`, and paired `{rank}.x` / `{rank}.y` columns for H1/H2
#'   classification.
#' @param rank_system Character vector of rank names coarse-to-fine
#'   (e.g., `c("genus", "species")`), used to identify the finest rank column
#'   for H1 vs H2/H3 classification.  Default `NULL` auto-detects from paired
#'   `.x`/`.y` columns via [TaxaTools::standard_ranks].
#' @param thresholds Numeric vector of coverage thresholds to evaluate.
#'   Default `seq(0, 0.99, by = 0.05)`.  Each value is a minimum: pairs with
#'   `coverage >= threshold` are retained.
#'
#' @return A data frame with one row per threshold and columns:
#'   \describe{
#'     \item{`threshold`}{Coverage threshold evaluated.}
#'     \item{`n_queries`}{Unique `id_x` values with at least one surviving pair.}
#'     \item{`breadth`}{`n_queries / total_queries`, range 0 to 1.}
#'     \item{`h1_pairs`}{Count of H1 pairs retained at this threshold.}
#'     \item{`h2_pairs`}{Count of H2/H3 pairs retained at this threshold.}
#'     \item{`h1_retention`}{`h1_pairs / total_h1_unfiltered`, range 0 to 1.}
#'     \item{`h2_retention`}{`h2_pairs / total_h2_unfiltered`, range 0 to 1.}
#'     \item{`youden_j`}{`h1_retention − h2_retention`.  Maximised at the
#'       Pareto-optimal threshold.  `NA` when H1/H2 classification is
#'       unavailable.}
#'     \item{`discrimination`}{`h1_retention / max(h2_retention, 1e-9)`.
#'       Ratio form; `NA` when unavailable.}
#'     \item{`mean_h1_score`}{Mean `p_match` of retained H1 pairs; `NA` when
#'       no H1 pairs survive or H1/H2 classification is unavailable.}
#'   }
#'
#' @seealso [build_sequence_matrix()], [build_acoustic_reference()],
#'   [coverage_threshold()], [train_likelihood_model()], [evaluate_likelihoods()]
#'
#' @examples
#' \dontrun{
#' ref_matrix <- build_sequence_matrix(reference_df)
#'
#' cal <- calibrate_coverage_filter(ref_matrix)
#'
#' # Select the Pareto-optimal threshold (maximises Youden's J)
#' best <- cal[which.max(cal$youden_j), ]
#' cat("Optimal threshold:", best$threshold,
#'     "| J =", round(best$youden_j, 3),
#'     "| breadth =", round(best$breadth, 3), "\n")
#'
#' # Visualise the breadth vs discrimination trade-off
#' plot(cal$breadth, cal$youden_j, type = "b",
#'      xlab = "Breadth (fraction of queries retained)",
#'      ylab = "Youden's J (H1 retention - H2 retention)",
#'      main = "Coverage filter calibration")
#' abline(v = best$breadth, lty = 2, col = "red")
#'
#' # Apply the chosen threshold before training
#' ref_filtered <- ref_matrix[ref_matrix$coverage >= best$threshold, ]
#' model <- train_likelihood_model(ref_filtered)
#' }
#'
#' @export
calibrate_coverage_filter <- function(ref_pairs,
                                       rank_system = NULL,
                                       thresholds  = seq(0, 0.99, by = 0.05)) {

  # ---- input validation -------------------------------------------------------
  if (!is.data.frame(ref_pairs))
    stop("calibrate_coverage_filter: 'ref_pairs' must be a data frame.")
  if (!"coverage" %in% names(ref_pairs))
    stop(paste0(
      "calibrate_coverage_filter: 'ref_pairs' must contain a 'coverage' column. ",
      "Build ref_pairs with build_sequence_matrix() or build_acoustic_reference()."
    ))
  if (!"p_match" %in% names(ref_pairs))
    stop("calibrate_coverage_filter: 'ref_pairs' must contain a 'p_match' column.")
  if (!"id_x" %in% names(ref_pairs))
    stop("calibrate_coverage_filter: 'ref_pairs' must contain an 'id_x' column.")
  if (!is.numeric(thresholds) || length(thresholds) == 0L || any(is.na(thresholds)))
    stop("calibrate_coverage_filter: 'thresholds' must be a non-empty numeric vector without NAs.")
  thresholds <- sort(unique(thresholds))

  # ---- detect finest rank for H1 vs H2/H3 classification ---------------------
  finest <- if (!is.null(rank_system)) {
    tolower(trimws(rank_system))[length(rank_system)]
  } else {
    .detect_finest_rank_col(ref_pairs)
  }

  h1_available <- FALSE
  is_h1        <- NULL

  if (!is.null(finest)) {
    x_col <- paste0(finest, ".x")
    y_col <- paste0(finest, ".y")
    if (all(c(x_col, y_col) %in% names(ref_pairs))) {
      is_h1        <- !is.na(ref_pairs[[x_col]]) &
                       !is.na(ref_pairs[[y_col]]) &
                       ref_pairs[[x_col]] == ref_pairs[[y_col]]
      h1_available <- TRUE
    } else {
      warning(sprintf(
        paste0("calibrate_coverage_filter: rank columns '%s' and/or '%s' not found. ",
               "H1/H2 metrics will be NA."),
        x_col, y_col
      ), call. = FALSE)
    }
  } else {
    warning(
      "calibrate_coverage_filter: finest rank could not be detected. H1/H2 metrics will be NA.",
      call. = FALSE
    )
  }

  # ---- baseline counts (exclude NA-coverage rows) ----------------------------
  n_queries_total <- length(unique(ref_pairs$id_x))
  cov_known       <- !is.na(ref_pairs$coverage)

  total_h1 <- if (h1_available) sum( is_h1 & cov_known) else NA_integer_
  total_h2 <- if (h1_available) sum(!is_h1 & cov_known) else NA_integer_

  # ---- categorical coverage detection ----------------------------------------
  n_uniq_cov     <- length(unique(ref_pairs$coverage[cov_known]))
  is_categorical  <- n_uniq_cov <= 10L

  # ---- sweep thresholds -------------------------------------------------------
  results <- lapply(thresholds, function(t) {
    keep_idx   <- cov_known & ref_pairs$coverage >= t
    n_queries  <- length(unique(ref_pairs$id_x[keep_idx]))
    breadth    <- if (n_queries_total > 0L) n_queries / n_queries_total else NA_real_

    if (h1_available) {
      sub_is_h1      <- is_h1[keep_idx]
      sub_pmatch     <- ref_pairs$p_match[keep_idx]
      n_h1_ret       <- sum(sub_is_h1)
      n_h2_ret       <- sum(!sub_is_h1)
      h1_retention   <- if (!is.na(total_h1) && total_h1 > 0L) n_h1_ret / total_h1  else NA_real_
      h2_retention   <- if (!is.na(total_h2) && total_h2 > 0L) n_h2_ret / total_h2  else NA_real_
      youden_j       <- if (!is.na(h1_retention) && !is.na(h2_retention))
                          h1_retention - h2_retention else NA_real_
      discrimination <- if (!is.na(h1_retention) && !is.na(h2_retention))
                          h1_retention / max(h2_retention, 1e-9) else NA_real_
      mean_h1_score  <- if (n_h1_ret > 0L) mean(sub_pmatch[sub_is_h1]) else NA_real_
    } else {
      n_h1_ret <- n_h2_ret <- NA_integer_
      h1_retention <- h2_retention <- youden_j <-
        discrimination <- mean_h1_score <- NA_real_
    }

    data.frame(
      threshold      = t,
      n_queries      = n_queries,
      breadth        = breadth,
      h1_pairs       = n_h1_ret,
      h2_pairs       = n_h2_ret,
      h1_retention   = h1_retention,
      h2_retention   = h2_retention,
      youden_j       = youden_j,
      discrimination = discrimination,
      mean_h1_score  = mean_h1_score,
      stringsAsFactors = FALSE
    )
  })

  out <- do.call(rbind, results)
  row.names(out) <- NULL

  if (is_categorical) {
    message(sprintf(paste0(
      "calibrate_coverage_filter: %d unique coverage values detected (categorical). ",
      "For acoustic data, coverage is per-recording quality grade; H1 and H2/H3 pairs ",
      "from the same recording share the same value, so youden_j and discrimination ",
      "will be near-flat. Use 'breadth' and 'mean_h1_score' as primary guides."
    ), n_uniq_cov))
  }

  out
}


# ==============================================================================
# coverage_threshold
# ==============================================================================

#' Select a coverage threshold by target retention quantile
#'
#' Returns the `coverage` value at the `(1 − keep_frac)` quantile of the
#' pairwise reference dataset — the minimum coverage that retains approximately
#' `keep_frac` of pairs.  Provides a fast, data-driven starting point for
#' coverage filtering when a full sweep via [calibrate_coverage_filter()] is
#' not needed.
#'
#' @section Method:
#' Setting `keep_frac = 0.95` computes `quantile(coverage, 0.05)` — the 5th
#' percentile of the coverage distribution — as the filter threshold.  Pairs
#' at or above this value are retained, discarding the bottom 5% by coverage.
#'
#' @section Categorical coverage:
#' When `coverage` takes ten or fewer unique values (e.g., the five Xeno-canto
#' quality grade levels A → 1.0, B → 0.8, C → 0.5, D → 0.3, E → 0.1), the
#' exact quantile rarely falls on an actual grade boundary.  The function snaps
#' to the nearest unique value and emits a message reporting the achieved
#' retention fraction so the caller can assess the approximation.
#'
#' @section Relationship to `calibrate_coverage_filter()`:
#' `coverage_threshold()` is a one-liner convenience wrapper that ignores H1/H2
#' structure.  When H1-based Pareto optimality matters — as it does for DNA
#' reference libraries where within-species pairs tend to have higher alignment
#' coverage than cross-species pairs — prefer [calibrate_coverage_filter()] and
#' select the threshold that maximises `youden_j`.
#'
#' @param ref_pairs Data frame.  Output of [build_sequence_matrix()] or
#'   [build_acoustic_reference()].  Must contain a `coverage` column.
#' @param keep_frac Numeric scalar in (0, 1).  Target fraction of pairs to
#'   retain (default `0.95`).  The threshold is set at the
#'   `(1 − keep_frac)` quantile so that approximately `keep_frac` of pairs
#'   have `coverage >= threshold`.
#'
#' @return A single numeric value: the coverage threshold.  Pairs at or above
#'   this value are retained.  Typical usage:
#'   ```r
#'   thresh       <- coverage_threshold(ref_matrix, keep_frac = 0.90)
#'   ref_filtered <- ref_matrix[ref_matrix$coverage >= thresh, ]
#'   model        <- train_likelihood_model(ref_filtered)
#'   ```
#'
#' @seealso [calibrate_coverage_filter()], [build_sequence_matrix()],
#'   [build_acoustic_reference()]
#'
#' @examples
#' \dontrun{
#' ref_matrix <- build_sequence_matrix(reference_df)
#'
#' # Retain the best 90% of reference pairs by alignment coverage
#' thresh       <- coverage_threshold(ref_matrix, keep_frac = 0.90)
#' ref_filtered <- ref_matrix[ref_matrix$coverage >= thresh, ]
#' model        <- train_likelihood_model(ref_filtered)
#'
#' # Acoustic: snaps to nearest Xeno-canto quality grade boundary
#' thresh <- coverage_threshold(ref_acoustic, keep_frac = 0.80)
#' # Message: "Snapping 0.72 -> 0.80 (retains 83.1%, requested 80.0%)"
#' }
#'
#' @importFrom stats quantile
#' @export
coverage_threshold <- function(ref_pairs, keep_frac = 0.95) {

  if (!is.data.frame(ref_pairs))
    stop("coverage_threshold: 'ref_pairs' must be a data frame.")
  if (!"coverage" %in% names(ref_pairs))
    stop(paste0(
      "coverage_threshold: 'ref_pairs' must contain a 'coverage' column. ",
      "Build ref_pairs with build_sequence_matrix() or build_acoustic_reference()."
    ))
  if (!is.numeric(keep_frac) || length(keep_frac) != 1L || is.na(keep_frac) ||
      keep_frac <= 0 || keep_frac >= 1)
    stop("coverage_threshold: 'keep_frac' must be a single numeric value in (0, 1).")

  cov <- ref_pairs$coverage[!is.na(ref_pairs$coverage)]
  if (length(cov) == 0L)
    stop("coverage_threshold: no non-NA coverage values found in 'ref_pairs$coverage'.")

  # Threshold at the (1 - keep_frac) quantile retains the top keep_frac fraction.
  raw_thresh <- stats::quantile(cov, probs = 1 - keep_frac, names = FALSE)

  uniq_cov <- sort(unique(cov))
  if (length(uniq_cov) <= 10L) {
    # Categorical coverage (e.g. Xeno-canto quality grades A-E mapped to 5 values).
    # Snap to the nearest unique value so the threshold falls on a grade boundary.
    nearest     <- uniq_cov[which.min(abs(uniq_cov - raw_thresh))]
    n_kept      <- sum(cov >= nearest)
    actual_frac <- n_kept / length(cov)
    message(sprintf(paste0(
      "coverage_threshold: %d unique coverage values (categorical). ",
      "Snapping threshold %.2f -> %.2f ",
      "(retains %.1f%% of pairs, requested %.1f%%)."
    ), length(uniq_cov), raw_thresh, nearest,
       100 * actual_frac, 100 * keep_frac))
    return(nearest)
  }

  raw_thresh
}
