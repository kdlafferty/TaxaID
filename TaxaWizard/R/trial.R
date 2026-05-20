#' Subset Inputs for Trial Mode
#'
#' Creates a small subset of the input data for estimating run time
#' before committing to the full dataset.
#'
#' @param df Data frame to subset.
#' @param n Integer. Number of rows (or unique observation_ids) to keep.
#'   Default 20.
#' @param by Character or NULL. Column to subset by unique values
#'   (e.g. \code{"observation_id"}). When NULL, subsets rows directly.
#'
#' @return Subsetted data frame.
#' @noRd
.subset_for_trial <- function(df, n = 20L, by = "observation_id") {

  if (!is.null(by) && by %in% names(df)) {
    unique_vals <- unique(df[[by]])
    keep_vals   <- utils::head(unique_vals, n)
    df[df[[by]] %in% keep_vals, , drop = FALSE]
  } else {
    utils::head(df, n)
  }
}


#' Estimate Scaling Factor
#'
#' Given trial timing and data sizes, estimates full-run duration.
#'
#' @param trial_time Numeric. Elapsed seconds for trial run.
#' @param trial_n Integer. Number of units in trial.
#' @param full_n Integer. Number of units in full dataset.
#' @param scaling Character. Scaling behavior: \code{"linear"},
#'   \code{"quadratic"}, \code{"api_limited"}.
#'
#' @return Named list with \code{estimated_seconds} and \code{note}.
#' @noRd
.estimate_scaling <- function(trial_time, trial_n, full_n,
                              scaling = "linear") {

  ratio <- full_n / trial_n

  estimated <- switch(scaling,
    linear      = trial_time * ratio,
    quadratic   = trial_time * ratio^2,
    api_limited = trial_time * ratio * 1.2,  # 20% overhead for rate limits
    trial_time * ratio  # default to linear
  )

  note <- switch(scaling,
    linear      = "Linear scaling assumed.",
    quadratic   = "Quadratic scaling (e.g., pairwise alignment).",
    api_limited = "API-limited; includes 20% overhead for rate limits and retries.",
    "Linear scaling assumed."
  )

  list(
    estimated_seconds = round(estimated, 1),
    estimated_minutes = round(estimated / 60, 1),
    note              = note
  )
}
