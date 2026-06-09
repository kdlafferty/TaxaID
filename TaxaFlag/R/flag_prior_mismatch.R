utils::globalVariables(character(0))

#' Flag assignments where the winning hypothesis is driven by prior rather
#' than sequence-match evidence
#'
#' Inspects the \code{winner_likelihood} and \code{winner_prior} columns
#' produced by \code{TaxaAssign::posterior_consensus()} and flags two
#' anomalous patterns:
#'
#' \describe{
#'   \item{\code{"prior_driven"}}{The winning hypothesis has a weak
#'     sequence-match likelihood (\code{winner_likelihood <
#'     score_thresholds[2]}).  The prior is doing the heavy lifting; the
#'     assignment may be over-constrained by occurrence data.}
#'   \item{\code{"unexpected_winner"}}{The winning hypothesis has an adequate
#'     likelihood but a very low prior (\code{winner_prior <
#'     low_prior_threshold}).  The sequence matches well but the taxon was not
#'     expected at this site.  Flag for contamination review or as a
#'     potentially novel detection.}
#' }
#'
#' Rows where \code{winner_likelihood} is \code{NA} (e.g. output from
#' \code{assign_taxa_llm()} or unresolved observations) receive
#' \code{"low"} risk and \code{NA} score -- they cannot be assessed.
#'
#' @param consensus_df Data frame.  Output of
#'   \code{TaxaAssign::posterior_consensus()}, containing at least
#'   \code{winner_likelihood_col}.  \code{winner_prior_col} is optional;
#'   the unexpected-winner check is skipped when absent or all \code{NA}.
#' @param winner_likelihood_col Character.  Column name for the winner's
#'   sequence-match likelihood (default \code{"winner_likelihood"}).
#'   Pass \code{"winner_likelihood_cov"} to use the coverage-adjusted
#'   likelihood instead.
#' @param winner_prior_col Character.  Column name for the winner's prior
#'   probability (default \code{"winner_prior"}).
#' @param score_thresholds Numeric(2).  Likelihood thresholds for risk
#'   classification (default \code{c(0.05, 0.20)}).  Rows where
#'   \code{winner_likelihood < score_thresholds[1]} are flagged
#'   \code{"high"}; between the two thresholds \code{"moderate"}; at or
#'   above \code{score_thresholds[2]} \code{"low"}.
#' @param low_prior_threshold Numeric or \code{NULL}.  Prior values below
#'   this trigger the unexpected-winner check (default \code{0.01}).
#'   Set to \code{NULL} or \code{0} to suppress the check entirely.
#'
#' @return \code{consensus_df} with three columns appended:
#' \describe{
#'   \item{\code{prior_mismatch_risk}}{Character: \code{"high"} /
#'     \code{"moderate"} / \code{"low"}.}
#'   \item{\code{prior_mismatch_score}}{Numeric 0-1.  Equal to
#'     \code{winner_likelihood}; \code{NA} when the source column is
#'     \code{NA}.}
#'   \item{\code{prior_mismatch_reason}}{Character explanation;
#'     \code{NA} when risk is \code{"low"} and the unexpected-winner
#'     check does not apply.}
#' }
#'
#' @examples
#' cons <- data.frame(
#'   observation_id    = c("obs1", "obs2", "obs3", "obs4"),
#'   consensus_taxon   = c("Oncorhynchus mykiss", "Homo sapiens",
#'                         "Salmo salar", "Sardina pilchardus"),
#'   winner_likelihood = c(0.95, 0.03, 0.15, 0.80),
#'   winner_prior      = c(0.40, 0.80, 0.35, 0.002)
#' )
#' flag_prior_mismatch(cons)
#'
#' @seealso \code{\link{flag_contaminant}}, \code{\link{flag_handler}}
#' @export
flag_prior_mismatch <- function(
    consensus_df,
    winner_likelihood_col = "winner_likelihood",
    winner_prior_col      = "winner_prior",
    score_thresholds      = c(0.05, 0.20),
    low_prior_threshold   = 0.01) {

  # ---- validate ----------------------------------------------------------------
  if (!is.data.frame(consensus_df))
    stop("flag_prior_mismatch: 'consensus_df' must be a data frame.", call. = FALSE)
  if (!winner_likelihood_col %in% names(consensus_df))
    stop(sprintf("flag_prior_mismatch: column '%s' not found in consensus_df.",
                 winner_likelihood_col), call. = FALSE)
  if (!is.numeric(score_thresholds) || length(score_thresholds) != 2L ||
      any(is.na(score_thresholds)) || score_thresholds[1L] >= score_thresholds[2L])
    stop("flag_prior_mismatch: 'score_thresholds' must be a sorted numeric(2).",
         call. = FALSE)
  if (!is.null(low_prior_threshold)) {
    if (!is.numeric(low_prior_threshold) || length(low_prior_threshold) != 1L ||
        is.na(low_prior_threshold) || low_prior_threshold < 0)
      stop("flag_prior_mismatch: 'low_prior_threshold' must be a non-negative number or NULL.",
           call. = FALSE)
  }

  # ---- extract columns ---------------------------------------------------------
  n   <- nrow(consensus_df)
  lik <- consensus_df[[winner_likelihood_col]]

  has_prior <- winner_prior_col %in% names(consensus_df) &&
               !all(is.na(consensus_df[[winner_prior_col]]))
  pr <- if (has_prior) consensus_df[[winner_prior_col]] else rep(NA_real_, n)

  use_prior_check <- has_prior &&
                     !is.null(low_prior_threshold) &&
                     low_prior_threshold > 0

  # ---- primary risk: likelihood strength ----------------------------------------
  risk <- rep("low", n)
  risk[!is.na(lik) & lik < score_thresholds[2L]] <- "moderate"
  risk[!is.na(lik) & lik < score_thresholds[1L]] <- "high"

  # ---- reason: likelihood -------------------------------------------------------
  reason <- rep(NA_character_, n)

  high_mask <- risk == "high" & !is.na(lik)
  mod_mask  <- risk == "moderate" & !is.na(lik)

  if (any(high_mask))
    reason[high_mask] <- sprintf(
      "Winner likelihood %.3f below %.2f; prior likely drives assignment.",
      lik[high_mask], score_thresholds[1L]
    )
  if (any(mod_mask))
    reason[mod_mask] <- sprintf(
      "Winner likelihood %.3f below %.2f; assignment may be prior-influenced.",
      lik[mod_mask], score_thresholds[2L]
    )

  # ---- secondary check: unexpected winner (low prior + adequate likelihood) -----
  if (use_prior_check) {
    unexpected <- !is.na(pr) & pr < low_prior_threshold &
                  !is.na(lik) & lik >= score_thresholds[2L]

    if (any(unexpected)) {
      # Escalate "low" rows to "moderate" (prior-check only, likelihood adequate)
      risk[unexpected & risk == "low"] <- "moderate"

      unexp_msg <- sprintf(
        "Winner prior %.4f below %.4f; taxon not expected at this site.",
        pr[unexpected], low_prior_threshold
      )
      reason[unexpected] <- ifelse(
        is.na(reason[unexpected]),
        unexp_msg,
        paste0(reason[unexpected], " ", unexp_msg)
      )
    }
  }

  # ---- append columns ----------------------------------------------------------
  consensus_df$prior_mismatch_risk   <- risk
  consensus_df$prior_mismatch_score  <- lik
  consensus_df$prior_mismatch_reason <- reason
  consensus_df
}
