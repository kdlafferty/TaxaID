# ==============================================================================
# assign_scores()
# ==============================================================================

utils::globalVariables(c("score_norm", "score_softmax",
                          "score_likelihood", "score_likelihood_mean",
                          "score_likelihood_sd", "score_method"))

# Fixed likelihood weight for unreferenced_family rows.
# Analogous to the unknown_lik_weight in assign_taxa_llm() (0.05 * max exp-score,
# which converges to ~0.05 at typical max-normalized scale).
.UNREFERENCED_FAMILY_WEIGHT <- 0.05

#' Assign score_likelihood values to a hypotheses data frame
#'
#' Converts raw match scores (or absence of scores) into the
#' \code{score_likelihood} column required by \code{TaxaAssign::compute_posterior()}.
#' Works on the expanded hypotheses data frame produced by
#' [unreferenced_candidates()].
#'
#' @details
#' \strong{score_type values:}
#' \describe{
#'   \item{\code{"none"}}{No score column available.  All rows receive
#'     \code{score_likelihood = 1.0} (uniform / degenerate likelihoods).
#'     Posteriors are proportional to priors.}
#'   \item{\code{"direct"}}{Passes \code{score_col} through unchanged as
#'     \code{score_likelihood}.  Rows with \code{NA} scores receive
#'     \code{score_likelihood = 1.0}.  Intended for use after
#'     [restore_suppressed_candidates()], which pre-imputes scores for
#'     restored rows.  No per-observation aggregation is performed.}
#'   \item{\code{"probability"}}{Neural-net softmax outputs (e.g., BirdNET
#'     multi-candidate output, iNaturalist CV scores) already on a 0–1 scale.
#'     H1 scores are ratio-normalized (\eqn{/} max) so the best candidate
#'     always receives \code{score_likelihood = 1.0}.  H2/H3 receive the
#'     median H1 \code{score_likelihood} among same-genus (H2) or same-family
#'     (H3) candidates; overall median as fallback.}
#'   \item{\code{"similarity_softmax"}}{Similarity scores (0–100 or 0–1) with
#'     no trained statistical model available.  Scores are normalized to (0,1)
#'     via \code{.normalize_scores()}, exponentiated
#'     (\eqn{e^{sharpness \times score_{norm}}}), then ratio-normalized.
#'     H2/H3 are anchored at the median softmax-normalized score of same-genus
#'     (H2) or same-family (H3) H1 candidates.  Appropriate for the LLM
#'     shortcut pathway when no trained model exists.}
#'   \item{\code{"similarity"}}{Similarity scores that will be processed by
#'     the bivariate-normal model in [model_likelihoods()].  This function
#'     only adds \code{score_norm} to H1 rows and sets
#'     \code{score_method = "similarity"}; it does \strong{not} write
#'     \code{score_likelihood}.  Call [model_likelihoods()] to complete the
#'     pipeline.}
#' }
#'
#' \strong{Normalization convention:} all \code{score_likelihood} values are
#' likelihood \emph{ratios} (divided by the maximum H1 likelihood), not
#' probabilities.  H2/H3/H4 rows are added after H1 normalization so that H1
#' values are unaffected by the number of unreferenced hypotheses.
#' \code{TaxaAssign::compute_posterior()} normalizes posteriors, so the
#' absolute scale of likelihoods does not matter.
#'
#' @param hypotheses_df Data frame produced by [unreferenced_candidates()].
#'   Must contain \code{observation_id} and \code{hypothesis_type}.  For all
#'   \code{score_type} values except \code{"none"}, must also contain the
#'   column named by \code{score_col} for \code{"specific_candidate"} rows.
#' @param score_type Character scalar. One of \code{"none"}, \code{"direct"},
#'   \code{"probability"}, \code{"similarity_softmax"}, or
#'   \code{"similarity"}.
#' @param score_col Character. Name of the raw score column in
#'   \code{hypotheses_df} (default \code{"score_original"}).  Ignored when
#'   \code{score_type = "none"}.
#' @param score_sharpness Positive numeric (default \code{0.1}).  Exponent
#'   scaling factor for \code{score_type = "similarity_softmax"} only.
#'   Larger values create sharper discrimination between candidates; smaller
#'   values produce more uniform likelihoods.
#'
#' @return For \code{score_type = "similarity"}: the input data frame with
#'   \code{score_norm} (H1 rows only) and \code{score_method = "similarity"}
#'   added.  Pass to [model_likelihoods()] to complete the pipeline.
#'
#'   For all other \code{score_type} values: a data frame with one row per
#'   \code{observation_id} x hypothesis (H1 aggregated to one row per
#'   \code{taxon_name}, H2/H3/H4 unchanged), with columns
#'   \code{score_likelihood}, \code{score_likelihood_mean} (= point estimate),
#'   \code{score_likelihood_sd} (= 0), and \code{score_method} added.
#'
#' @seealso [unreferenced_candidates()], [model_likelihoods()],
#'   [compute_likelihoods()]
#'
#' @examples
#' \dontrun{
#' # No-score pathway (morphology IDs)
#' hyp_df <- unreferenced_candidates(match_df)
#' liks   <- assign_scores(hyp_df, score_type = "none")
#' # head(liks[, c("observation_id", "taxon_name", "score_likelihood")])
#'
#' # Probability pathway (BirdNET multi-candidate)
#' hyp_df <- unreferenced_candidates(match_df)
#' liks   <- assign_scores(hyp_df, score_type = "probability")
#' }
#'
#' @importFrom dplyr bind_rows
#' @importFrom stats median
#' @export
assign_scores <- function(hypotheses_df,
                          score_type,
                          score_col      = "score_original",
                          score_sharpness = 0.1) {

  # ---- validate ---------------------------------------------------------------
  if (!is.data.frame(hypotheses_df))
    stop("`hypotheses_df` must be a data frame.", call. = FALSE)
  valid_types <- c("none", "direct", "probability", "similarity_softmax", "similarity")
  if (!is.character(score_type) || length(score_type) != 1L ||
      !score_type %in% valid_types)
    stop(sprintf("`score_type` must be one of: %s.",
                 paste(valid_types, collapse = ", ")), call. = FALSE)
  if (!is.numeric(score_sharpness) || length(score_sharpness) != 1L ||
      is.na(score_sharpness) || score_sharpness <= 0)
    stop("`score_sharpness` must be a single positive number.", call. = FALSE)

  names(hypotheses_df) <- tolower(names(hypotheses_df))

  required <- c("observation_id", "hypothesis_type")
  missing_cols <- setdiff(required, names(hypotheses_df))
  if (length(missing_cols) > 0L)
    stop(sprintf("`hypotheses_df` is missing required column(s): %s",
                 paste(missing_cols, collapse = ", ")), call. = FALSE)

  # ---- "none" pathway ---------------------------------------------------------
  if (score_type == "none") {
    # Warn if score column exists with non-NA values — user may have passed
    # wrong score_type
    if (score_col %in% names(hypotheses_df)) {
      h1_scores <- hypotheses_df[[score_col]][
        hypotheses_df$hypothesis_type == "specific_candidate"
      ]
      if (any(!is.na(h1_scores)))
        warning(sprintf(
          "assign_scores: score_type = 'none' but column '%s' contains non-NA values. Scores will be ignored. If this is unintentional, change score_type.",
          score_col
        ), call. = FALSE)
    }
    hypotheses_df$score_likelihood      <- 1.0
    hypotheses_df$score_likelihood_mean <- 1.0
    hypotheses_df$score_likelihood_sd   <- 0.0
    hypotheses_df$score_method          <- "none"
    return(hypotheses_df)
  }

  # ---- "direct" pathway -------------------------------------------------------
  # Passes the score column through unchanged as score_likelihood.
  # NA rows receive 1.0 (non-discriminating).
  # Intended for use after restore_suppressed_candidates(), where original rows
  # carry their real scores and restored rows carry pre-imputed scores.
  if (score_type == "direct") {
    if (!score_col %in% names(hypotheses_df))
      stop(sprintf("`score_col` '%s' not found in `hypotheses_df`.", score_col),
           call. = FALSE)
    sc <- hypotheses_df[[score_col]]
    hypotheses_df$score_likelihood      <- ifelse(is.na(sc), 1.0, sc)
    hypotheses_df$score_likelihood_mean <- hypotheses_df$score_likelihood
    hypotheses_df$score_likelihood_sd   <- 0.0
    hypotheses_df$score_method          <- "direct"
    return(hypotheses_df)
  }

  # ---- score column required for all other types -----------------------------
  if (!score_col %in% names(hypotheses_df))
    stop(sprintf("`score_col` '%s' not found in `hypotheses_df`.", score_col),
         call. = FALSE)

  # ---- score column validations ----------------------------------------------
  is_h1 <- hypotheses_df$hypothesis_type == "specific_candidate"
  h1_scores <- hypotheses_df[[score_col]][is_h1]

  if (score_type %in% c("similarity", "similarity_softmax")) {
    if (all(is.na(h1_scores)))
      stop(sprintf(
        "score_type = '%s' but all `score_original` values for specific_candidate rows are NA.",
        score_type
      ), call. = FALSE)
    if (score_type == "similarity" && !all(is.na(h1_scores)) &&
        max(h1_scores, na.rm = TRUE) <= 1)
      message(
        "assign_scores: score_type = 'similarity' and all scores appear to be on the 0-1 ",
        "scale. .normalize_scores() will treat max value as 1.0. ",
        "If scores are percent identity (0-100), this may affect normalization."
      )
  }

  if (score_type == "probability") {
    if (any(h1_scores > 1, na.rm = TRUE))
      warning(
        "assign_scores: score_type = 'probability' but some scores > 1. ",
        "Probability scores should be in [0, 1]. Check scale.",
        call. = FALSE
      )
  }

  # ---- "similarity" pathway: add score_norm only, no score_likelihood --------
  if (score_type == "similarity") {
    hypotheses_df$score_norm   <- NA_real_
    hypotheses_df$score_norm[is_h1] <- .normalize_scores(h1_scores)
    hypotheses_df$score_method <- "similarity"
    return(hypotheses_df)
  }

  # ---- "probability" and "similarity_softmax": per-observation processing ----
  obs_ids <- unique(hypotheses_df$observation_id[!is.na(hypotheses_df$observation_id)])
  result_list <- vector("list", length(obs_ids))

  for (oi in seq_along(obs_ids)) {
    sid      <- obs_ids[oi]
    obs_rows <- hypotheses_df[
      !is.na(hypotheses_df$observation_id) &
      hypotheses_df$observation_id == sid, ,
      drop = FALSE
    ]

    h1_mask <- obs_rows$hypothesis_type == "specific_candidate"
    h2_mask <- obs_rows$hypothesis_type == "unreferenced_species"
    h3_mask <- obs_rows$hypothesis_type == "unreferenced_genus"
    h4_mask <- obs_rows$hypothesis_type == "unreferenced_family"

    h1_rows <- obs_rows[h1_mask, , drop = FALSE]
    h2_rows <- obs_rows[h2_mask, , drop = FALSE]
    h3_rows <- obs_rows[h3_mask, , drop = FALSE]
    h4_rows <- obs_rows[h4_mask, , drop = FALSE]

    if (nrow(h1_rows) == 0L) {
      # No H1 — pass through unchanged (will have NA score_likelihood)
      obs_rows$score_likelihood      <- NA_real_
      obs_rows$score_likelihood_mean <- NA_real_
      obs_rows$score_likelihood_sd   <- 0.0
      obs_rows$score_method          <- score_type
      result_list[[oi]] <- obs_rows
      next
    }

    # ---- aggregate H1 by taxon_name (median score across accessions) ----------
    taxa <- unique(h1_rows$taxon_name)
    h1_agg_list <- vector("list", length(taxa))
    for (ti in seq_along(taxa)) {
      tx_rows <- h1_rows[h1_rows$taxon_name == taxa[ti], , drop = FALSE]
      agg_row  <- tx_rows[1L, , drop = FALSE]
      agg_row[[score_col]] <- stats::median(tx_rows[[score_col]], na.rm = TRUE)
      h1_agg_list[[ti]] <- agg_row
    }
    h1_agg <- dplyr::bind_rows(h1_agg_list)

    # ---- compute H1 score_likelihood -------------------------------------------
    sc <- h1_agg[[score_col]]

    if (score_type == "probability") {
      max_sc <- max(sc, na.rm = TRUE)
      if (is.na(max_sc) || max_sc == 0) max_sc <- 1
      h1_agg$score_likelihood <- sc / max_sc

    } else {  # "similarity_softmax"
      sc_norm    <- .normalize_scores(sc)
      sc_softmax <- exp(score_sharpness * sc_norm)
      max_ss     <- max(sc_softmax, na.rm = TRUE)
      if (is.na(max_ss) || max_ss == 0) max_ss <- 1
      h1_agg$score_norm    <- sc_norm
      h1_agg$score_softmax <- sc_softmax
      h1_agg$score_likelihood <- sc_softmax / max_ss
    }

    h1_agg$score_likelihood_mean <- h1_agg$score_likelihood
    h1_agg$score_likelihood_sd   <- 0.0
    h1_agg$score_method          <- score_type

    h1_lik_vec  <- h1_agg$score_likelihood
    genus_col   <- if ("genus"  %in% names(h1_agg)) "genus"  else NULL
    family_col  <- if ("family" %in% names(h1_agg)) "family" else NULL

    # ---- H2: median of congener (same genus) H1 likelihoods -------------------
    if (nrow(h2_rows) > 0L) {
      h2_rows$score_likelihood      <- NA_real_
      h2_rows$score_likelihood_mean <- NA_real_
      h2_rows$score_likelihood_sd   <- 0.0
      h2_rows$score_method          <- score_type
      for (ri in seq_len(nrow(h2_rows))) {
        h2_genus <- if (!is.null(genus_col)) h2_rows[[genus_col]][ri] else NA_character_
        if (!is.na(h2_genus) && !is.null(genus_col)) {
          congener_idx <- !is.na(h1_agg[[genus_col]]) &
            tolower(h1_agg[[genus_col]]) == tolower(h2_genus)
          anchor <- if (any(congener_idx))
            stats::median(h1_lik_vec[congener_idx], na.rm = TRUE)
          else
            stats::median(h1_lik_vec, na.rm = TRUE)
        } else {
          anchor <- stats::median(h1_lik_vec, na.rm = TRUE)
        }
        h2_rows$score_likelihood[ri]      <- anchor
        h2_rows$score_likelihood_mean[ri] <- anchor
      }
      if (score_type == "similarity_softmax") {
        h2_rows$score_norm    <- NA_real_
        h2_rows$score_softmax <- NA_real_
      }
    }

    # ---- H3: median of same-family H1 likelihoods ----------------------------
    if (nrow(h3_rows) > 0L) {
      h3_rows$score_likelihood      <- NA_real_
      h3_rows$score_likelihood_mean <- NA_real_
      h3_rows$score_likelihood_sd   <- 0.0
      h3_rows$score_method          <- score_type
      for (ri in seq_len(nrow(h3_rows))) {
        h3_family <- if (!is.null(family_col)) h3_rows[[family_col]][ri] else NA_character_
        if (!is.na(h3_family) && !is.null(family_col)) {
          fam_idx <- !is.na(h1_agg[[family_col]]) &
            tolower(h1_agg[[family_col]]) == tolower(h3_family)
          anchor <- if (any(fam_idx))
            stats::median(h1_lik_vec[fam_idx], na.rm = TRUE)
          else
            stats::median(h1_lik_vec, na.rm = TRUE)
        } else {
          anchor <- stats::median(h1_lik_vec, na.rm = TRUE)
        }
        h3_rows$score_likelihood[ri]      <- anchor
        h3_rows$score_likelihood_mean[ri] <- anchor
      }
      if (score_type == "similarity_softmax") {
        h3_rows$score_norm    <- NA_real_
        h3_rows$score_softmax <- NA_real_
      }
    }

    # ---- H4: fixed small weight (unreferenced_family) ------------------------
    if (nrow(h4_rows) > 0L) {
      h4_rows$score_likelihood      <- .UNREFERENCED_FAMILY_WEIGHT
      h4_rows$score_likelihood_mean <- .UNREFERENCED_FAMILY_WEIGHT
      h4_rows$score_likelihood_sd   <- 0.0
      h4_rows$score_method          <- score_type
      if (score_type == "similarity_softmax") {
        h4_rows$score_norm    <- NA_real_
        h4_rows$score_softmax <- NA_real_
      }
    }

    result_list[[oi]] <- dplyr::bind_rows(h1_agg, h2_rows, h3_rows, h4_rows)
  }

  dplyr::bind_rows(result_list)
}
