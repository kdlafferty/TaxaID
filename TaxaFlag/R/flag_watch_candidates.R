# flag_watch_candidates.R
# TaxaFlag package

#' Flag observations where a watch-list species outscores the consensus winner
#'
#' The likelihood-side surveillance guarantee for watch-list species
#' (2026-08-26 mixture redesign, D4 -- see
#' \code{ecosystem_docs/REENTRY_PROMPT_undetected_evidence_mixture_redesign.md}).
#'
#' @section Why this exists:
#' A watch-list species' occurrence prior should be a small, honest
#' probability of local presence (the GreatLakes2023 calibration adopted
#' w = 0.05) -- which correctly stops such species from vetoing the species-
#' level resolution of genuinely observed natives, but also means a watch
#' species will rarely surface in the posterior-driven consensus at all. The
#' surveillance requirement ("if a watch species matches this sequence well,
#' a reviewer must see that, every time") cannot be honored through the
#' posterior without breaking the prior's honesty -- Bayes correctly
#' down-weights an unobserved species against an abundant native at any
#' likelihood ratio short of overwhelming. So the guarantee is honored on the
#' LIKELIHOOD side instead: this function compares raw match scores only --
#' no priors, no likelihood model -- and flags every observation where a
#' watch-list species scored at least as well as (within \code{score_margin}
#' of) the consensus winner's own best match. The flag is purely
#' informational: it never changes \code{consensus_taxon}/\code{consensus_rank},
#' matching this package's additive-column convention.
#'
#' @section How the comparison works:
#' Per observation: the best raw score among watch-list candidates is
#' compared against a reference score -- the winner's (\code{winner_col},
#' default \code{primary_taxon}) own best match score in \code{match_df}, or,
#' when the winner has no match row of its own (an unreferenced or
#' rank-expanded winner), the best score among non-watch candidates. The
#' observation is flagged when
#' \code{watch_score >= reference_score - score_margin}. An observation whose
#' winner IS itself a watch-list species is never flagged (surveillance
#' already succeeded through the front door). Observations with no watch-list
#' candidate rows at all get \code{watch_flag = FALSE} with NA detail
#' columns.
#'
#' @param consensus_df Data frame, one row per observation --
#'   \code{TaxaAssign::posterior_consensus()} output (or anything carrying
#'   \code{observation_col} and \code{winner_col}).
#' @param match_df Data frame of raw match candidates (e.g. the workflow's
#'   \code{match_obj_restored}) carrying \code{observation_col},
#'   \code{taxon_col}, and \code{score_col}.
#' @param watch_taxa Character vector of watch-list species names (e.g. the
#'   workflow's \code{INVASIVE_TAXA}). Required, no default.
#' @param observation_col Character. Observation identifier column shared by
#'   both inputs. Default \code{"observation_id"}.
#' @param taxon_col Character. Candidate taxon-name column in
#'   \code{match_df}. Default \code{"taxon_name"}.
#' @param score_col Character. Raw match-score column in \code{match_df}
#'   (higher = better). Default \code{"score_original"}.
#' @param winner_col Character. Winner column in \code{consensus_df}.
#'   Default \code{"primary_taxon"} (the top-posterior candidate -- present
#'   even when the final consensus upranked to a coarser rank).
#' @param score_margin Numeric >= 0. Flag when the best watch score is within
#'   this many score units of the reference score (0 = must tie or exceed).
#'   Default \code{0}.
#'
#' @return \code{consensus_df} with four added columns:
#'   \describe{
#'     \item{watch_flag}{Logical. TRUE when a watch-list species scored
#'       within \code{score_margin} of the winner's own best score.}
#'     \item{watch_taxon}{The best-scoring watch-list species for this
#'       observation (NA when no watch candidate exists).}
#'     \item{watch_score}{That species' best raw score (NA likewise).}
#'     \item{watch_reference_score}{The reference score the comparison used
#'       (winner's own best match, or best non-watch score).}
#'   }
#'
#' @examples
#' \dontrun{
#' consensus_final <- flag_watch_candidates(
#'   consensus_final, match_obj_restored,
#'   watch_taxa = INVASIVE_TAXA
#' )
#' table(consensus_final$watch_flag)
#' }
#'
#' @export
flag_watch_candidates <- function(
    consensus_df,
    match_df,
    watch_taxa,
    observation_col = "observation_id",
    taxon_col       = "taxon_name",
    score_col       = "score_original",
    winner_col      = "primary_taxon",
    score_margin    = 0
) {
  if (!is.data.frame(consensus_df)) {
    stop("flag_watch_candidates: `consensus_df` must be a data frame.")
  }
  if (!is.data.frame(match_df)) {
    stop("flag_watch_candidates: `match_df` must be a data frame.")
  }
  if (!is.character(watch_taxa) || length(watch_taxa) == 0L) {
    stop("flag_watch_candidates: `watch_taxa` must be a non-empty character vector.")
  }
  if (!is.numeric(score_margin) || length(score_margin) != 1L ||
      is.na(score_margin) || score_margin < 0) {
    stop("flag_watch_candidates: `score_margin` must be a single non-negative number.")
  }
  for (col in c(observation_col, winner_col)) {
    if (!col %in% names(consensus_df)) {
      stop(sprintf("flag_watch_candidates: `consensus_df` is missing required column '%s'.", col))
    }
  }
  for (col in c(observation_col, taxon_col, score_col)) {
    if (!col %in% names(match_df)) {
      stop(sprintf("flag_watch_candidates: `match_df` is missing required column '%s'.", col))
    }
  }

  obs_ids  <- consensus_df[[observation_col]]
  winners  <- consensus_df[[winner_col]]
  m_obs    <- match_df[[observation_col]]
  m_taxon  <- match_df[[taxon_col]]
  m_score  <- match_df[[score_col]]
  is_watch <- m_taxon %in% watch_taxa

  match_split <- split(seq_len(nrow(match_df)), m_obs)

  n <- nrow(consensus_df)
  watch_flag      <- rep(FALSE, n)
  watch_taxon     <- rep(NA_character_, n)
  watch_score     <- rep(NA_real_, n)
  reference_score <- rep(NA_real_, n)

  for (i in seq_len(n)) {
    idx <- match_split[[as.character(obs_ids[i])]]
    if (is.null(idx)) next
    w_idx <- idx[is_watch[idx] & !is.na(m_score[idx])]
    if (length(w_idx) == 0L) next

    winner_i <- winners[i]
    # winner is itself a watch species: surveillance succeeded, never flag
    if (!is.na(winner_i) && winner_i %in% watch_taxa) next

    best_w <- w_idx[which.max(m_score[w_idx])]
    watch_taxon[i] <- m_taxon[best_w]
    watch_score[i] <- m_score[best_w]

    # An NA winner (an observation the consensus left unresolved) has no match
    # row of its own by definition -- and comparing against it elementwise
    # would yield NA indices, an NA reference score, and finally an NA
    # watch_flag, which this function's own contract says is logical.
    ref_idx <- if (is.na(winner_i)) {
      integer(0)
    } else {
      idx[!is.na(m_score[idx]) & !is.na(m_taxon[idx]) & m_taxon[idx] == winner_i]
    }
    if (length(ref_idx) == 0L) {
      # winner has no match row of its own (unreferenced/rank-expanded):
      # compare against the best non-watch candidate instead
      ref_idx <- idx[!is_watch[idx] & !is.na(m_score[idx])]
    }
    if (length(ref_idx) == 0L) next
    reference_score[i] <- max(m_score[ref_idx])
    watch_flag[i] <- watch_score[i] >= reference_score[i] - score_margin
  }

  consensus_df$watch_flag            <- watch_flag
  consensus_df$watch_taxon           <- watch_taxon
  consensus_df$watch_score           <- watch_score
  consensus_df$watch_reference_score <- reference_score

  n_flagged <- sum(watch_flag)
  message(sprintf(
    "flag_watch_candidates: %d of %d observation(s) flagged (a watch-list species scored within %g of the winner's best match).",
    n_flagged, n, score_margin
  ))
  consensus_df
}
