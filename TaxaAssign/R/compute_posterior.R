# compute_posterior.R
# TaxaAssign package
#
# Renaming log:
#   2026-02-19: calculate_final_posteriors() -> compute_posterior()
#   2026-02-19: prior_df        -> likelihood_w_prior  (input dataframe)
#   2026-02-19: Query_ID        -> observation_id
#   2026-02-19: LR_PointEst     -> likelihood_point_est
#   2026-02-19: LR_Mean         -> likelihood_mean
#   2026-02-19: LR_SD           -> likelihood_sd
#   2026-02-19: Prior_Prob      -> prior_mean
#   2026-02-19: (new)           -> prior_sd  (optional, defaults to 0) [removed 2026-04-04]
#   2026-02-19: Posterior_Mean  -> posterior_mean
#   2026-02-19: Posterior_SD    -> posterior_sd
#   2026-02-19: Posterior_PointEst -> posterior_point_est
#   2026-02-19: Confidence_Score -> confidence_score
#   2026-04-04: prior_sd replaced by prior_alpha + prior_beta (Beta-distributed priors)
#
#' Compute Bayesian Posterior Probabilities
#'
#' Performs the Bayesian update: Posterior ~ Likelihood * Prior.
#' Adds posterior columns to the input dataframe and returns the full dataframe,
#' so all existing columns (e.g., taxon name, hypothesis type, rank) are preserved.
#'
#' Two computation paths are available:
#' - **Point estimate path** (fast): uses `likelihood_point_est` and `prior_mean`
#'   directly. Always computed.
#' - **Monte Carlo path** (robust): samples from prior and likelihood distributions,
#'   propagating uncertainty into the posterior. Likelihoods are sampled from
#'   Normal(mean, sd). Priors are sampled from Beta(alpha, beta) when `prior_alpha`
#'   and `prior_beta` columns are present, correctly bounded on \[0, 1\].
#'   Only runs when `n_sims > 0` AND at least one source of uncertainty exists
#'   (non-zero `likelihood_sd`, or `prior_alpha`/`prior_beta` columns present).
#'
#' Within each `observation_id`, likelihoods and posteriors are normalized to sum to 1
#' across all competing hypotheses.
#'
#' @param likelihood_w_prior Dataframe. One row per hypothesis per observation.
#'   Must contain columns: `observation_id`, `likelihood_point_est`, `likelihood_mean`,
#'   `likelihood_sd`, `prior_mean`.
#'   Optional columns: `prior_alpha` and `prior_beta` (Beta distribution parameters).
#'   When present, Monte Carlo simulation samples priors from Beta(alpha, beta).
#'   When absent, priors are treated as fixed (no prior uncertainty).
#' @param n_sims Integer. Number of Monte Carlo simulations. Default 1000.
#'   Set to 0 to skip simulation and return point estimates only.
#'
#' @return The input dataframe with four new columns added:
#'   - `posterior_point_est`: deterministic posterior from point estimates
#'   - `posterior_mean`: mean posterior across Monte Carlo simulations
#'   - `posterior_sd`: SD of posterior across Monte Carlo simulations
#'   - `confidence_score`: fraction of simulations in which this hypothesis won
#'
#' @details
#' \strong{Bayesian framework:}
#' Each query (\code{observation_id}) has multiple competing hypotheses (candidate
#' taxa). The posterior probability for hypothesis \eqn{i} is:
#' \deqn{P(H_i | data) = \frac{L(data | H_i) \times \pi(H_i)}{\sum_j L(data | H_j) \times \pi(H_j)}}
#' where \eqn{L} is the likelihood (from TaxaLikely or score-based proxy) and
#' \eqn{\pi} is the prior (from TaxaExpect or LLM-based estimation).
#'
#' \strong{Prior uncertainty (Beta distribution):}
#' When \code{prior_alpha} and \code{prior_beta} columns are present, the prior
#' for each hypothesis is modelled as \eqn{Beta(\alpha, \beta)} rather than a
#' fixed point. The concentration \eqn{\phi = \alpha + \beta} controls how
#' tightly the prior is held: large \eqn{\phi} (e.g., 50) means high confidence
#' in the prior estimate; small \eqn{\phi} (e.g., 3) means the prior is
#' diffuse. Monte Carlo simulation samples from this Beta distribution to
#' propagate prior uncertainty into the posterior.
#'
#' \strong{hypothesis_type values (inherited from input):}
#' \itemize{
#'   \item \code{"specific_candidate"} -- referenced species with a direct match.
#'   \item \code{"unreferenced_species"} -- species absent from the reference DB
#'     but plausible at this location (from TaxaLikely H2 or LLM suggestion).
#'   \item \code{"unreferenced_genus"} -- genus absent from the reference DB
#'     (from TaxaLikely H3).
#'   \item \code{"unknown_species"} -- catch-all for uncharacterised diversity
#'     (from \code{assign_taxa_llm()}).
#'   \item \code{"unresolved_species"} -- ambiguous among referenced members of
#'     a fully-sampled genus (from \code{apply_coverage_constraints()}).
#' }
#'
#' @examples
#' \dontrun{
#' result <- compute_posterior(likelihood_w_prior, n_sims = 1000)
#' head(result[, c("observation_id", "taxon_name", "posterior_mean")])
#' }
#'
#' @importFrom rlang .data
#' @importFrom stats rnorm rbeta sd
#'
#' @export
compute_posterior <- function(likelihood_w_prior, n_sims = 1000) {

  # --- Input validation ---
  required_cols <- c("observation_id", "likelihood_point_est", "likelihood_mean",
                     "likelihood_sd", "prior_mean")
  missing_cols <- setdiff(required_cols, names(likelihood_w_prior))
  if (length(missing_cols) > 0) {
    cli::cli_abort(
      "Input dataframe is missing required column(s): {.field {missing_cols}}"
    )
  }

  # --- Detect prior uncertainty mode ---
  has_alpha <- "prior_alpha" %in% names(likelihood_w_prior)
  has_beta  <- "prior_beta" %in% names(likelihood_w_prior)

  if (has_alpha != has_beta) {
    cli::cli_abort(
      "Both {.field prior_alpha} and {.field prior_beta} must be present, or neither."
    )
  }

  use_beta_prior <- has_alpha && has_beta

  if (use_beta_prior) {
    # Validate alpha/beta values
    bad_alpha <- !is.finite(likelihood_w_prior$prior_alpha) |
      likelihood_w_prior$prior_alpha <= 0
    bad_beta  <- !is.finite(likelihood_w_prior$prior_beta) |
      likelihood_w_prior$prior_beta <= 0
    n_bad <- sum(bad_alpha | bad_beta)
    if (n_bad > 0) {
      cli::cli_abort(
        "{n_bad} row(s) have non-positive or non-finite {.field prior_alpha}/{.field prior_beta}. All values must be > 0."
      )
    }
  } else {
    cli::cli_inform(
      "No {.field prior_alpha}/{.field prior_beta} columns found. Treating priors as fixed (no prior uncertainty)."
    )
  }

  # Replace any NA likelihood SDs with 0 and warn the user
  na_lik_sd <- sum(is.na(likelihood_w_prior$likelihood_sd))
  if (na_lik_sd > 0) {
    cli::cli_warn("{na_lik_sd} NA value(s) in {.field likelihood_sd} replaced with 0.")
    likelihood_w_prior$likelihood_sd[is.na(likelihood_w_prior$likelihood_sd)] <- 0
  }

  # Decide whether MC simulation will add any information
  any_lik_uncertainty   <- any(likelihood_w_prior$likelihood_sd > 0)
  any_prior_uncertainty <- use_beta_prior
  run_sims <- n_sims > 0 && (any_lik_uncertainty || any_prior_uncertainty)

  if (n_sims > 0 && !run_sims) {
    cli::cli_inform(
      "No uncertainty to propagate. Skipping Monte Carlo simulation and returning point estimates only."
    )
  }

  # --- Helper: normalize a vector to sum to 1 ---
  # If all values are 0, return uniform distribution (avoids division by zero)
  normalize_vec <- function(x) {
    s <- sum(x, na.rm = TRUE)
    if (s == 0) return(rep(1 / length(x), length(x)))
    x / s
  }

  # --- Process each observation_id group ---
  cli::cli_inform("Computing posteriors for {dplyr::n_distinct(likelihood_w_prior$observation_id)} observation(s)...")

  results_list <- likelihood_w_prior |>
    dplyr::group_split(.data$observation_id) |>
    lapply(function(chunk) {

      n_rows <- nrow(chunk)
      if (n_rows == 0) return(chunk)

      # --- Point estimate path ---
      # Normalize likelihoods first, then multiply by prior, then normalize again
      norm_lik  <- normalize_vec(chunk$likelihood_point_est)
      raw_post  <- norm_lik * chunk$prior_mean
      chunk$posterior_point_est <- normalize_vec(raw_post)

      # --- Monte Carlo path ---
      if (run_sims) {

        # Sample likelihoods: Normal(mean, sd), floor at 0
        sim_lik <- matrix(
          rnorm(n_rows * n_sims, mean = chunk$likelihood_mean, sd = chunk$likelihood_sd),
          nrow = n_rows
        )
        sim_lik[sim_lik < 0] <- 0

        # Sample priors: Beta(alpha, beta) — bounded [0, 1] by construction
        if (use_beta_prior) {
          sim_prior <- matrix(
            rbeta(n_rows * n_sims,
                  shape1 = chunk$prior_alpha,
                  shape2 = chunk$prior_beta),
            nrow = n_rows
          )
        } else {
          # Fixed priors: replicate prior_mean across all simulations
          sim_prior <- matrix(
            rep(chunk$prior_mean, n_sims),
            nrow = n_rows
          )
        }

        # Normalize likelihoods within each simulation (column = one simulation).
        # When all likelihoods in a simulation are 0, assign uniform weights so
        # the posterior falls back to the prior -- matching normalize_vec() in the
        # point-estimate path.
        col_sums_lik  <- colSums(sim_lik)
        all_zero_cols <- col_sums_lik == 0
        n_zero_cols   <- sum(all_zero_cols)
        if (n_zero_cols > 0L) {
          warning(sprintf(
            "compute_posterior: %d of %d simulation(s) for observation_id '%s' had all-zero likelihoods; using uniform fallback for those simulations.",
            n_zero_cols, n_sims, chunk$observation_id[1L]
          ), call. = FALSE)
        }
        sim_lik_norm  <- sweep(sim_lik, 2,
                               ifelse(all_zero_cols, 1, col_sums_lik), "/")
        sim_lik_norm[, all_zero_cols] <- 1 / n_rows

        # Bayesian update: normalized likelihood * prior
        sim_raw <- sim_lik_norm * sim_prior

        # Normalize posterior within each simulation.
        # When a simulation draws zero prior for every hypothesis,
        # assign uniform weight so the failed simulation is uninformative.
        col_sums_post   <- colSums(sim_raw)
        zero_post_cols  <- col_sums_post == 0
        col_sums_post[zero_post_cols] <- 1
        sim_probs <- sweep(sim_raw, 2, col_sums_post, "/")
        sim_probs[, zero_post_cols] <- 1 / n_rows

        # Summarize across simulations
        chunk$posterior_mean    <- rowMeans(sim_probs)
        chunk$posterior_sd      <- apply(sim_probs, 1, sd)

        # Confidence score: fraction of MC simulations in which this hypothesis
        # had the highest posterior. Complements posterior_mean: a hypothesis can
        # have a high mean posterior but low confidence_score if another hypothesis
        # frequently wins. Analogous to the "posterior probability of being the
        # best hypothesis" in decision theory.
        winners    <- apply(sim_probs, 2, which.max)
        win_counts <- table(factor(winners, levels = 1:n_rows))
        chunk$confidence_score  <- as.numeric(win_counts) / n_sims

      } else {
        # No simulation: MC outputs mirror point estimate
        chunk$posterior_mean   <- chunk$posterior_point_est
        chunk$posterior_sd     <- 0
        chunk$confidence_score <- as.numeric(chunk$posterior_point_est == max(chunk$posterior_point_est))
      }

      return(chunk)
    })

  # Return full dataframe sorted by observation_id, then best hypothesis first
  out <- dplyr::bind_rows(results_list) |>
    dplyr::arrange(.data$observation_id, dplyr::desc(.data$posterior_mean))

  attr(out, "report_params") <- list(n_sims = n_sims)
  out
}
