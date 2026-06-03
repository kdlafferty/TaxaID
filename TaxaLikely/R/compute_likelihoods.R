# ==============================================================================
# model_likelihoods()   — bivariate-normal modeling step
# compute_likelihoods() — orchestrating wrapper
# ==============================================================================

#' Apply the bivariate-normal model to produce score_likelihood values
#'
#' The bivariate-normal modeling step of the unified likelihood pipeline.
#' Accepts a data frame produced by [assign_scores()] with
#' \code{score_type = "similarity"} (which adds \code{score_norm} and
#' \code{score_method = "similarity"} but does \strong{not} write
#' \code{score_likelihood}).
#'
#' Internally calls [evaluate_likelihoods()] on the
#' \code{"specific_candidate"} rows and adds
#' \code{score_method = "bivariate_normal"} to the result.
#'
#' @param scored_df Data frame from [assign_scores()] with
#'   \code{score_type = "similarity"}.  Must contain \code{observation_id},
#'   \code{taxon_name}, \code{taxon_name_rank}, \code{hypothesis_type}, and
#'   \code{score_original} (or \code{score} / \code{p_match}).
#' @param model_params Object of class \code{"taxa_model_params"} from
#'   [train_likelihood_model()].
#' @param rank_system Character vector of rank names coarse to fine.
#'   \code{NULL} (default) auto-detects from \code{scored_df}.
#' @param ratio_threshold Numeric (default \code{0.01}). Minimum likelihood
#'   ratio; hypotheses below this threshold are dropped.
#' @param min_match_threshold Numeric (default \code{0.50}). Raw score below
#'   which a candidate receives likelihood 0.
#' @param n_sims Integer (default \code{0L}). Monte Carlo simulations.
#'   \code{0} = deterministic only.
#' @param min_coverage Numeric or \code{NULL}. Coverage pre-filter. See
#'   [evaluate_likelihoods()] for details.
#' @param verbose Logical (default \code{FALSE}). Print species-specific
#'   parameter fallback messages.
#'
#' @return A named list identical in structure to [evaluate_likelihoods()]:
#'   \describe{
#'     \item{\code{$likelihoods}}{Data frame with one row per
#'       \code{observation_id} x hypothesis, including \code{score_likelihood},
#'       \code{score_likelihood_mean}, \code{score_likelihood_sd}, and
#'       \code{score_method = "bivariate_normal"}.}
#'     \item{\code{$unresolved}}{Rows from \code{scored_df} for queries that
#'       produced no usable likelihoods. Empty data frame if none.}
#'   }
#'
#' @seealso [assign_scores()], [unreferenced_candidates()],
#'   [compute_likelihoods()], [evaluate_likelihoods()]
#'
#' @examples
#' \dontrun{
#' hyp_df  <- unreferenced_candidates(match_df)
#' sc_df   <- assign_scores(hyp_df, score_type = "similarity")
#' result  <- model_likelihoods(sc_df, model_params = model,
#'                              rank_system = c("family", "genus", "species"))
#' head(result$likelihoods)
#' }
#'
#' @export
model_likelihoods <- function(scored_df,
                              model_params,
                              rank_system         = NULL,
                              ratio_threshold     = 0.01,
                              min_match_threshold = 0.50,
                              n_sims              = 0L,
                              min_coverage        = NULL,
                              verbose             = FALSE) {

  if (!is.data.frame(scored_df))
    stop("`scored_df` must be a data frame.", call. = FALSE)

  names(scored_df) <- tolower(names(scored_df))

  # Validate score_method if present
  if ("score_method" %in% names(scored_df)) {
    sm <- unique(scored_df$score_method[!is.na(scored_df$score_method)])
    if (length(sm) > 0L && !all(sm == "similarity"))
      warning(
        "model_likelihoods: scored_df contains score_method != 'similarity'. ",
        "Only 'similarity' rows (H1) are processed; others are passed through.",
        call. = FALSE
      )
  }

  # Extract H1 rows for the bivariate-normal model
  if ("hypothesis_type" %in% names(scored_df)) {
    h1_df <- scored_df[
      is.na(scored_df$hypothesis_type) |
      scored_df$hypothesis_type == "specific_candidate", ,
      drop = FALSE
    ]
  } else {
    h1_df <- scored_df
  }

  result <- evaluate_likelihoods(
    match_df            = h1_df,
    model_params        = model_params,
    rank_system         = rank_system,
    ratio_threshold     = ratio_threshold,
    min_match_threshold = min_match_threshold,
    n_sims              = n_sims,
    min_coverage        = min_coverage,
    verbose             = verbose
  )

  if (!is.null(result$likelihoods) && nrow(result$likelihoods) > 0L)
    result$likelihoods$score_method <- "bivariate_normal"

  result
}


# ==============================================================================
# compute_likelihoods() — orchestrating wrapper
# ==============================================================================

#' Compute likelihoods from a match object (unified pipeline wrapper)
#'
#' Orchestrates the three-step unified likelihood pipeline:
#' [unreferenced_candidates()] → [assign_scores()] → [model_likelihoods()]
#' (similarity pathway only).
#'
#' This is the recommended high-level entry point for new workflows.  For the
#' bivariate-normal similarity pathway it is equivalent to
#' [evaluate_likelihoods()].  For other data types it replaces
#' \code{expand_consensus_candidates()} with a consistent interface.
#'
#' @param match_df Data frame. Canonical match object from
#'   \code{TaxaMatch::standardize_match_data()} or equivalent. Must contain
#'   \code{observation_id}, \code{taxon_name}, \code{taxon_name_rank}, and
#'   taxonomy columns. A \code{score_original} column is required unless
#'   \code{score_type = "none"}.
#' @param score_type Character scalar. One of \code{"none"},
#'   \code{"probability"}, \code{"similarity_softmax"}, or
#'   \code{"similarity"}.  See [assign_scores()] for full descriptions.
#' @param model_params Object of class \code{"taxa_model_params"} from
#'   [train_likelihood_model()].  Required when
#'   \code{score_type = "similarity"}; ignored otherwise.
#' @param rank_system Character vector of rank names coarse to fine.
#'   \code{NULL} (default) auto-detects from \code{match_df}.
#' @param include_unreferenced_family Logical (default \code{FALSE}). Passed
#'   to [unreferenced_candidates()]. See that function for guidance.
#' @param score_col Character (default \code{"score_original"}). Passed to
#'   [assign_scores()].
#' @param score_sharpness Positive numeric (default \code{0.1}). Passed to
#'   [assign_scores()]; applies to \code{score_type = "similarity_softmax"}
#'   only.
#' @param ratio_threshold Numeric (default \code{0.01}). Passed to
#'   [model_likelihoods()]; applies to \code{score_type = "similarity"} only.
#' @param min_match_threshold Numeric (default \code{0.50}). Passed to
#'   [model_likelihoods()]; applies to \code{score_type = "similarity"} only.
#' @param n_sims Integer (default \code{0L}). Monte Carlo simulations. Passed
#'   to [model_likelihoods()]; applies to \code{score_type = "similarity"}
#'   only.
#' @param min_coverage Numeric or \code{NULL}. Coverage pre-filter. Passed to
#'   [model_likelihoods()]; applies to \code{score_type = "similarity"} only.
#' @param verbose Logical (default \code{FALSE}). Passed to
#'   [model_likelihoods()].
#'
#' @return A named list:
#'   \describe{
#'     \item{\code{$likelihoods}}{Data frame with one row per
#'       \code{observation_id} x hypothesis, containing
#'       \code{observation_id}, \code{taxon_name}, \code{taxon_name_rank},
#'       \code{hypothesis_type}, \code{score_likelihood},
#'       \code{score_likelihood_mean}, \code{score_likelihood_sd}, and
#'       \code{score_method}.  Rows with \code{NA} \code{taxon_name} are
#'       excluded except for \code{"unreferenced_family"} rows (which have
#'       \code{taxon_name = NA} by design).}
#'     \item{\code{$unresolved}}{Rows from \code{match_df} for queries
#'       that produced no usable likelihoods. Empty data frame if none.
#'       Non-empty only when \code{score_type = "similarity"}.}
#'   }
#'
#' @seealso [unreferenced_candidates()], [assign_scores()],
#'   [model_likelihoods()], [evaluate_likelihoods()]
#'
#' @examples
#' \dontrun{
#' # No-score pathway (morphology or upranked consensus)
#' result <- compute_likelihoods(match_df, score_type = "none")
#' head(result$likelihoods)
#'
#' # Probability pathway (BirdNET or iNaturalist CV)
#' result <- compute_likelihoods(match_df, score_type = "probability")
#'
#' # Similarity pathway (eDNA BLAST + trained model)
#' result <- compute_likelihoods(
#'   match_df, score_type = "similarity",
#'   model_params = model,
#'   rank_system  = c("family", "genus", "species"),
#'   n_sims       = 200L
#' )
#' }
#'
#' @export
compute_likelihoods <- function(match_df,
                                score_type,
                                model_params               = NULL,
                                rank_system                = NULL,
                                include_unreferenced_family = FALSE,
                                score_col                  = "score_original",
                                score_sharpness            = 0.1,
                                ratio_threshold            = 0.01,
                                min_match_threshold        = 0.50,
                                n_sims                     = 0L,
                                min_coverage               = NULL,
                                verbose                    = FALSE) {

  if (score_type == "similarity" && is.null(model_params))
    stop(
      "score_type = 'similarity' requires `model_params`. ",
      "Train a model with train_likelihood_model() or use a different score_type.",
      call. = FALSE
    )

  # Step 1: expand with unreferenced hypotheses
  hyp_df <- unreferenced_candidates(
    match_df,
    rank_system                 = rank_system,
    include_unreferenced_family = include_unreferenced_family
  )

  # Step 2: assign scores
  sc_df <- assign_scores(
    hyp_df,
    score_type      = score_type,
    score_col       = score_col,
    score_sharpness = score_sharpness
  )

  # Step 3: bivariate-normal model (similarity only)
  if (score_type == "similarity") {
    return(model_likelihoods(
      scored_df           = sc_df,
      model_params        = model_params,
      rank_system         = rank_system,
      ratio_threshold     = ratio_threshold,
      min_match_threshold = min_match_threshold,
      n_sims              = n_sims,
      min_coverage        = min_coverage,
      verbose             = verbose
    ))
  }

  # Non-similarity: sc_df IS the likelihoods data frame.
  # Wrap in $likelihoods / $unresolved list structure.

  # Exclude NA taxon_name rows except unreferenced_family (intentionally NA)
  has_na_name <- is.na(sc_df$taxon_name) &
    sc_df$hypothesis_type != "unreferenced_family"
  likelihoods <- sc_df[!has_na_name, , drop = FALSE]

  # Identify required output columns (keep all present)
  keep_cols <- intersect(
    c("observation_id", "taxon_name", "taxon_name_rank", "hypothesis_type",
      "score_likelihood", "score_likelihood_mean", "score_likelihood_sd",
      "score_method"),
    names(likelihoods)
  )
  # Retain all columns (not just keep_cols) — downstream may use extra cols
  unresolved <- match_df[integer(0L), ]

  list(likelihoods = likelihoods, unresolved = unresolved)
}
