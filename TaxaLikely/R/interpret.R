utils::globalVariables(c(
  "lookup_key", "rank", "mu_score", "mu_gap", "sigma_score",
  "expected_match_pct", "expected_runner_up_pct", "expected_gap_pct",
  "danger_gap", "danger_zone_pct", "status",
  "count", "avg_match_pct", "avg_gap_pct"
))

# ==============================================================================
# MODULE F: MODEL DIAGNOSTICS
# ==============================================================================

#' Summarise a trained likelihood model
#'
#' Converts the internal logit-space parameters of a `"taxa_model_params"`
#' object back to interpretable percentages and prints a formatted report.
#' Returns the summary tables invisibly for programmatic access.
#'
#' @param model_params Object of class `"taxa_model_params"` returned by
#'   [train_likelihood_model()].
#' @param print_report Logical (default `TRUE`).  If `FALSE`, suppresses
#'   console output.
#'
#' @return An invisible named list with elements:
#'   \describe{
#'     \item{`hypothesis_baselines`}{Data frame: expected match % and expected
#'       gap % for H1, H2, H3. The gap is the difference between the best
#'       match and the runner-up. H2/H3 have gap near 0 because when the true
#'       species or genus is absent, no candidate has a clear advantage.}
#'     \item{`global_h1`}{Data frame: global mean score, gap, and SD.}
#'     \item{`hierarchy`}{Data frame: per-rank counts and averages.}
#'     \item{`species_thresholds`}{Data frame: per-species expected match %, gap
#'       %, and status classification.}
#'     \item{`raw_sigma`}{The 2x2 covariance matrix from the model.}
#'   }
#'
#' @seealso [train_likelihood_model()], [evaluate_likelihoods()]
#'
#' @examples
#' \dontrun{
#' model <- train_likelihood_model(ref_matrix,
#'                                 rank_system = c("family", "genus", "species"))
#' summary_df <- interpret_model(model)
#' }
#'
#' @importFrom dplyr arrange case_when group_by mutate n select summarise
#' @export
interpret_model <- function(model_params, print_report = TRUE) {
  if (!inherits(model_params, "taxa_model_params"))
    stop("model_params must be a 'taxa_model_params' object from train_likelihood_model()")
  if (!is.logical(print_report) || length(print_report) != 1L || is.na(print_report))
    stop("print_report must be TRUE or FALSE")
  if (is.null(names(model_params$H1_Global_Mu)) ||
      !all(c("score_logit", "gap_logit") %in% names(model_params$H1_Global_Mu)))
    stop("model_params$H1_Global_Mu must be a named vector with 'score_logit' and 'gap_logit'")

  .inv_logit <- function(x) 1 / (1 + exp(-x))

  mu_score <- model_params$H1_Global_Mu[["score_logit"]]
  mu_gap   <- model_params$H1_Global_Mu[["gap_logit"]]
  sd_score <- if (!is.null(model_params$H1_Sigma))
    sqrt(model_params$H1_Sigma["score_logit", "score_logit"])
  else NA_real_

  # ---- H1 global profile ----------------------------------------------------
  mean_score_pct    <- round(.inv_logit(mu_score) * 100, 2)
  runner_up_pct     <- round(.inv_logit(mu_score - mu_gap) * 100, 2)
  effective_gap_pct <- round(mean_score_pct - runner_up_pct, 2)

  # ---- H2 / H3 expected scores ----------------------------------------------
  h2_logit <- mu_score - model_params$H2$delta
  h3_logit <- mu_score - model_params$H3$delta
  h2_pct   <- round(.inv_logit(h2_logit) * 100, 2)
  h3_pct   <- round(.inv_logit(h3_logit) * 100, 2)

  # ---- H2 / H3 expected gaps ------------------------------------------------
  # H2 and H3 distributions have expected gap = 0 (logit scale): when the

  # true species/genus is absent, no candidate has a clear advantage.
  # H1 gap comes from the global mean gap.
  h2_runner_pct <- round(.inv_logit(h2_logit - 0) * 100, 2)  # gap_logit = 0
  h3_runner_pct <- round(.inv_logit(h3_logit - 0) * 100, 2)
  h2_gap_pct    <- round(h2_pct - h2_runner_pct, 2)
  h3_gap_pct    <- round(h3_pct - h3_runner_pct, 2)

  # ---- Summary tables -------------------------------------------------------
  hyp_baselines <- data.frame(
    hypothesis         = c("H1: known species", "H2: unreferenced species", "H3: unreferenced genus"),
    expected_match_pct = c(mean_score_pct, h2_pct, h3_pct),
    expected_gap_pct   = c(effective_gap_pct, h2_gap_pct, h3_gap_pct),
    stringsAsFactors   = FALSE
  )

  global_h1 <- data.frame(
    metric         = c("mean match score", "mean runner-up gap", "score tolerance (SD)"),
    value_logit    = round(c(mu_score, mu_gap, sd_score), 2),
    value_pct      = c(mean_score_pct, effective_gap_pct, NA_real_),
    stringsAsFactors = FALSE
  )

  # ---- Per-species thresholds -----------------------------------------------
  sigma_gap_sd <- if (!is.null(model_params$H1_Sigma))
    sqrt(model_params$H1_Sigma["gap_logit", "gap_logit"])
  else 0

  if (nrow(model_params$H1_Lookup) > 0L) {
    species_thr <- model_params$H1_Lookup |>
      dplyr::mutate(
        expected_match_pct   = round(.inv_logit(mu_score) * 100, 2),
        expected_runner_up_pct = round(.inv_logit(mu_score - mu_gap) * 100, 2),
        expected_gap_pct     = round(expected_match_pct - expected_runner_up_pct, 2),
        danger_gap           = mu_gap - sigma_gap_sd,
        danger_zone_pct      = round(.inv_logit(mu_score - danger_gap) * 100, 2),
        status               = dplyr::case_when(
          mu_gap < 0.1 ~ "INDISTINGUISHABLE",
          mu_gap < 2.0 ~ "complex/cluster",
          .default     = "distinct"
        )
      ) |>
      dplyr::select(lookup_key, rank, status,
                    expected_match_pct, expected_gap_pct, danger_zone_pct) |>
      dplyr::arrange(lookup_key)

    hierarchy <- species_thr |>
      dplyr::group_by(rank) |>
      dplyr::summarise(
        count        = dplyr::n(),
        avg_match_pct = round(mean(expected_match_pct, na.rm = TRUE), 2),
        avg_gap_pct   = round(mean(expected_gap_pct,   na.rm = TRUE), 2),
        .groups       = "drop"
      )
  } else {
    species_thr <- data.frame(
      message = "No species-specific parameters (data too sparse -- global mean used)",
      stringsAsFactors = FALSE
    )
    hierarchy <- data.frame(
      message = "Flat model (no hierarchy)",
      stringsAsFactors = FALSE
    )
  }

  if (print_report) {
    message("=== TaxaLikely model interpretation ===\n")
    message("1. Hypothesis baselines:")
    print(hyp_baselines)
    message("\n2. Global H1 profile:")
    print(global_h1)
    message("\n3. Hierarchy summary:")
    print(hierarchy)
    message("\n4. Species thresholds (first 10):")
    print(utils::head(species_thr, 10L))
  }

  invisible(list(
    hypothesis_baselines = hyp_baselines,
    global_h1            = global_h1,
    hierarchy            = hierarchy,
    species_thresholds   = species_thr,
    raw_sigma            = model_params$H1_Sigma
  ))
}
