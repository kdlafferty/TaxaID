utils::globalVariables(c(
  "p_med", "p_b", "score_logit", "gap_logit", "p_norm",
  "raw_likelihood", "likelihood_point_est", "likelihood_mean", "likelihood_sd",
  "hypothesis_type", "taxon_name", "taxon_name_rank",
  "observation_id", "Query_ID",
  ".data", "rank_score", "best_rank_score"
))

# ==============================================================================
# MODULE D: INFERENCE
# ==============================================================================

#' Evaluate H1/H2/H3 likelihoods for a single query
#'
#' Core inference function.  Given one query's candidate rows and a trained
#' model, computes likelihood ratios for:
#' * **H1 (specific_candidate):** a known species present in the reference DB.
#' * **H2 (unreferenced_species):** an unsampled species in a represented genus.
#' * **H3 (unreferenced_genus):** an unsampled species in an unrepresented genus.
#'
#' Uses a 2D bivariate normal over `(score_logit, gap_logit)` unless there is
#' only one candidate taxon, in which case a 1D normal over `score_logit` only
#' is used (gap is artificial when no competitor exists).
#'
#' @param candidate_df Data frame of match rows for **one** `observation_id`.
#'   Required columns: `taxon_name`, `score`.  Taxonomy columns matching
#'   `rank_system` are used for hierarchical lookup fallback and for deriving
#'   H2/H3 taxon labels via `TaxaTools::create_taxon_names()`.
#' @param model_params Named list of class `"taxa_model_params"` returned by
#'   [train_likelihood_model()].
#' @param rank_system Character vector of rank names **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`).
#' @param ratio_threshold Numeric (default `0.01`).  Minimum likelihood ratio
#'   relative to the best hypothesis; specific candidates below this are dropped.
#' @param min_match_threshold Numeric (default `0.50`).  Raw score below which
#'   a candidate receives likelihood 0 regardless of the model prediction.
#' @param alpha Numeric (default `1e-6`).  Mahalanobis p-value cutoff: candidates
#'   with smaller p-values are treated as outliers and receive likelihood 0.
#' @param n_sims Integer (default `0`).  Number of Monte Carlo simulations for
#'   `likelihood_mean` and `likelihood_sd`.  `0` = deterministic only.
#' @param score_bounds Optional `c(min, max)` for score normalization.
#' @param logit_epsilon Logit clipping value (default `1e-4`).
#' @param max_gap_ceiling Gap cap (default `5.0`).  Caps gap at 5 logit units
#'   (roughly the gap between 99.3% and 50% identity) to prevent extreme
#'   outliers from dominating model estimates.
#'
#' @return A data frame with columns `hypothesis_type`, `taxon_name`,
#'   `taxon_name_rank`, `likelihood_point_est`, `likelihood_mean`,
#'   `likelihood_sd`, sorted by `likelihood_mean` descending.
#'
#' @noRd
.evaluate_one_query <- function(candidate_df,
                                model_params,
                                rank_system,
                                ratio_threshold     = 0.01,
                                min_match_threshold = 0.50,
                                alpha               = 1e-6,
                                n_sims              = 0,
                                score_bounds        = NULL,
                                logit_epsilon       = 1e-4,
                                max_gap_ceiling     = 5.0,
                                verbose             = FALSE) {

  names(candidate_df) <- tolower(names(candidate_df))
  rank_cols <- tolower(rank_system)    # coarse to fine

  score_col <- if ("p_match" %in% names(candidate_df)) "p_match" else
    if ("score"   %in% names(candidate_df)) "score" else
      stop("candidate_df must have a 'score' or 'p_match' column")

  # Extract model parameters
  global_mu     <- as.numeric(model_params$H1_Global_Mu)   # [score_logit, gap_logit]
  global_sigma  <- as.matrix(model_params$H1_Sigma)
  rownames(global_sigma) <- colnames(global_sigma) <- c("score_logit", "gap_logit")
  model_sd_score <- sqrt(global_sigma[1L, 1L])

  h2_delta  <- model_params$H2$delta
  h3_delta  <- model_params$H3$delta
  h2_sigma  <- as.matrix(model_params$H2$sigma)
  h3_sigma  <- as.matrix(model_params$H3$sigma)

  # ---- 1. FEATURE PREP: median score per taxon_name --------------------------
  existing_rank_cols <- intersect(rank_cols, names(candidate_df))
  agg_cols <- c("taxon_name", existing_rank_cols)

  cand <- candidate_df |>
    dplyr::mutate(p_norm = .normalize_scores(.data[[score_col]],
                                             bounds = score_bounds)) |>
    dplyr::group_by(taxon_name) |>
    dplyr::summarise(
      p_med = stats::median(p_norm, na.rm = TRUE),
      dplyr::across(dplyr::any_of(existing_rank_cols), dplyr::first),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      p_b         = pmin(pmax(p_med, logit_epsilon), 1 - logit_epsilon),
      score_logit = log(p_b / (1 - p_b))
    )

  if (nrow(cand) == 0L) {
    return(data.frame(
      hypothesis_type      = character(0),
      taxon_name           = character(0),
      taxon_name_rank      = character(0),
      likelihood_point_est = numeric(0),
      likelihood_mean      = numeric(0),
      likelihood_sd        = numeric(0),
      stringsAsFactors     = FALSE
    ))
  }

  is_singleton <- nrow(cand) == 1L
  if (is_singleton) {
    # Single-candidate queries use 1D mode with artificial max gap.
    # H2/H3 likelihoods may be inflated relative to H1 because the gap
    # dimension (which normally separates H1 from H2/H3) is uninformative.
    # Interpret H2/H3 results with caution for singleton queries.
  }

  # ---- 2. GAP PER CANDIDATE (vectorized) ------------------------------------
  all_scores <- cand$score_logit
  n_cand <- length(all_scores)
  if (n_cand <= 1L) {
    cand$gap_logit <- max_gap_ceiling
  } else {
    sorted <- sort(all_scores, decreasing = TRUE)
    # For each candidate: gap = score - max(others).
    # max(others) = sorted[1] unless this candidate IS sorted[1], then sorted[2].
    cand$gap_logit <- pmin(
      ifelse(all_scores >= sorted[1L] - .Machine$double.eps * 100,
             all_scores - sorted[2L],
             all_scores - sorted[1L]),
      max_gap_ceiling
    )
  }

  # ---- 3. LINEAGE MATRIX for hierarchical lookup fallback -------------------
  # finest rank → column 1, coarser ranks → subsequent columns
  lineage_mat <- if (length(existing_rank_cols) > 0L)
    as.data.frame(cand[, rev(existing_rank_cols), drop = FALSE])
  else
    data.frame(matrix(NA_character_, nrow = nrow(cand), ncol = 1L))

  # ---- 4. LIKELIHOOD CALCULATOR (shared by point-estimate and MC sims) ------
  .calc_likelihoods <- function(s_vec, g_vec, p_raw, taxa_names, use_1d) {
    h1_vals <- numeric(length(s_vec))
    has_lookup <- !is.null(model_params$H1_Lookup) &&
      nrow(model_params$H1_Lookup) > 0L

    for (i in seq_along(s_vec)) {
      if (p_raw[i] < min_match_threshold) next   # leave h1_vals[i] = 0

      use_mu    <- global_mu
      use_sigma <- global_sigma

      if (has_lookup) {
        idx <- match(taxa_names[i], model_params$H1_Lookup$lookup_key)
        if (is.na(idx) && ncol(lineage_mat) > 0L) {
          for (r_name in unlist(lineage_mat[i, ])) {
            if (!is.na(r_name)) {
              idx <- match(r_name, model_params$H1_Lookup$lookup_key)
              if (!is.na(idx)) break
            }
          }
        }
        if (!is.na(idx)) {
          use_mu <- c(model_params$H1_Lookup$mu_score[idx],
                      model_params$H1_Lookup$mu_gap[idx])
          sp_var <- model_params$H1_Lookup$sigma_score[idx]
          if (!is.na(sp_var) && sp_var > 0) use_sigma[1L, 1L] <- sp_var
        } else if (verbose) {
          message(sprintf("  Taxon '%s': no species-specific params; using global mean",
                          taxa_names[i]))
        }
      }

      if (use_1d) {
        h1_vals[i] <- stats::dnorm(s_vec[i],
                                   mean = use_mu[1L],
                                   sd   = sqrt(use_sigma[1L, 1L]))
      } else {
        x_pt <- c(s_vec[i], g_vec[i])
        d_sq  <- tryCatch(
          stats::mahalanobis(x_pt, center = use_mu, cov = use_sigma),
          error = function(e) Inf
        )
        p_val <- stats::pchisq(d_sq, df = 2L, lower.tail = FALSE)
        if (p_val >= alpha)
          h1_vals[i] <- mvtnorm::dmvnorm(x_pt,
                                         mean  = as.numeric(use_mu),
                                         sigma = use_sigma)
      }
    }

    # H2 / H3 from the best-scoring candidate
    best_i <- which.max(s_vec)
    if (length(best_i) == 0L || all(s_vec == 0)) {
      return(list(h1 = h1_vals, h2 = 0, h3 = 0))
    }

    best_pt <- c(s_vec[best_i], g_vec[best_i])
    h2_mu   <- c(global_mu[1L] - h2_delta, 0)
    h3_mu   <- c(global_mu[1L] - h3_delta, 0)

    if (use_1d) {
      h2_val <- stats::dnorm(best_pt[1L], mean = h2_mu[1L],
                             sd = sqrt(h2_sigma[1L, 1L]))
      h3_val <- stats::dnorm(best_pt[1L], mean = h3_mu[1L],
                             sd = sqrt(h3_sigma[1L, 1L]))
    } else {
      h2_val <- mvtnorm::dmvnorm(best_pt, mean = h2_mu, sigma = h2_sigma)
      h3_val <- mvtnorm::dmvnorm(best_pt, mean = h3_mu, sigma = h3_sigma)
    }

    list(h1 = h1_vals, h2 = h2_val, h3 = h3_val)
  }

  # ---- 5. POINT ESTIMATE ----------------------------------------------------
  primary <- .calc_likelihoods(cand$score_logit, cand$gap_logit,
                               cand$p_med, cand$taxon_name,
                               use_1d = is_singleton)

  # Build result rows for H1
  df_h1 <- cand |>
    dplyr::mutate(hypothesis_type = "specific_candidate",
                  raw_likelihood  = primary$h1)

  # Build H2/H3 rows from the best candidate
  best_i   <- if (any(primary$h1 > 0)) which.max(primary$h1) else which.max(cand$score_logit)
  best_row <- cand[best_i, , drop = FALSE]

  # Derive H2 taxon_name: finest rank NA → create_taxon_names picks genus
  # Derive H3 taxon_name: two finest ranks NA → create_taxon_names picks family
  finest <- if (length(rank_cols) >= 1L) rank_cols[length(rank_cols)]       else NULL
  second  <- if (length(rank_cols) >= 2L) rank_cols[length(rank_cols) - 1L] else NULL

  row_h2 <- best_row
  if (!is.null(finest) && finest %in% names(row_h2))
    row_h2[[finest]] <- NA_character_
  row_h2 <- TaxaTools::create_taxon_names(row_h2, rank_cols)
  row_h2$hypothesis_type <- "unreferenced_species"
  row_h2$raw_likelihood  <- primary$h2

  row_h3 <- best_row
  if (!is.null(finest) && finest %in% names(row_h3))
    row_h3[[finest]] <- NA_character_
  if (!is.null(second) && second %in% names(row_h3))
    row_h3[[second]] <- NA_character_
  row_h3 <- TaxaTools::create_taxon_names(row_h3, rank_cols)
  row_h3$hypothesis_type <- "unreferenced_genus"
  row_h3$raw_likelihood  <- primary$h3

  res <- dplyr::bind_rows(df_h1, row_h2, row_h3)

  # Re-derive taxon_name for H1 rows too (ensures consistency with TaxaTools)
  res <- TaxaTools::create_taxon_names(res, rank_cols)

  res_agg <- res |>
    dplyr::group_by(hypothesis_type, taxon_name, taxon_name_rank) |>
    dplyr::summarise(raw_likelihood = max(raw_likelihood, na.rm = TRUE),
                     .groups = "drop")

  # ---- 6. NORMALISE TO LIKELIHOOD RATIOS ------------------------------------
  max_lik <- max(res_agg$raw_likelihood, na.rm = TRUE)
  if (max_lik == 0 || is.na(max_lik)) max_lik <- 1

  res_agg <- res_agg |>
    dplyr::mutate(likelihood_point_est = raw_likelihood / max_lik) |>
    dplyr::filter(
      likelihood_point_est >= ratio_threshold |
        hypothesis_type != "specific_candidate"
    )

  # ---- 7. MONTE CARLO SIMULATION (optional) ---------------------------------
  if (n_sims > 0L && nrow(res_agg) > 0L) {
    sim_mat <- matrix(NA_real_, nrow = nrow(res_agg), ncol = n_sims)

    # Pre-compute index mapping: res_agg row → cand row(s) for H1 lookup
    # Uses global model SD for computational efficiency. Species-specific SD
    # could be used but adds complexity with minimal impact on posterior
    # uncertainty, which is dominated by prior uncertainty from
    # prior_alpha/prior_beta in TaxaAssign::compute_posterior().
    h1_idx_map <- vector("list", nrow(res_agg))
    h2_rows <- integer(0L)
    h3_rows <- integer(0L)
    for (r in seq_len(nrow(res_agg))) {
      ht <- res_agg$hypothesis_type[r]
      if (ht == "specific_candidate") {
        h1_idx_map[[r]] <- which(cand$taxon_name == res_agg$taxon_name[r])
      } else if (ht == "unreferenced_species") {
        h2_rows <- c(h2_rows, r)
      } else {
        h3_rows <- c(h3_rows, r)
      }
    }

    nc <- nrow(cand)
    for (sim_i in seq_len(n_sims)) {
      sim_scores <- stats::rnorm(nc, mean = cand$score_logit, sd = model_sd_score)

      # Vectorized gap calculation
      if (nc <= 1L) {
        sim_gaps <- max_gap_ceiling
      } else {
        ss <- sort(sim_scores, decreasing = TRUE)
        sim_gaps <- pmin(
          ifelse(sim_scores >= ss[1L] - .Machine$double.eps * 100,
                 sim_scores - ss[2L],
                 sim_scores - ss[1L]),
          max_gap_ceiling
        )
      }

      sim_res <- .calc_likelihoods(sim_scores, sim_gaps,
                                   cand$p_med, cand$taxon_name,
                                   use_1d = is_singleton)

      # Map results using pre-computed indices
      iter_liks <- numeric(nrow(res_agg))
      for (r in seq_len(nrow(res_agg))) {
        m <- h1_idx_map[[r]]
        if (!is.null(m) && length(m) > 0L) {
          iter_liks[r] <- max(sim_res$h1[m])
        }
      }
      if (length(h2_rows) > 0L) iter_liks[h2_rows] <- sim_res$h2
      if (length(h3_rows) > 0L) iter_liks[h3_rows] <- sim_res$h3

      iter_max <- max(iter_liks, na.rm = TRUE)
      if (iter_max == 0 || is.na(iter_max)) iter_max <- 1
      sim_mat[, sim_i] <- iter_liks / iter_max
    }

    res_agg$likelihood_mean <- rowMeans(sim_mat, na.rm = TRUE)
    res_agg$likelihood_sd   <- apply(sim_mat, 1L, stats::sd, na.rm = TRUE)
  } else {
    res_agg$likelihood_mean <- res_agg$likelihood_point_est
    res_agg$likelihood_sd   <- 0
  }

  # Final filter on mean (after simulation)
  res_agg <- dplyr::filter(res_agg, likelihood_mean >= ratio_threshold)

  res_agg |>
    dplyr::select(hypothesis_type, taxon_name, taxon_name_rank,
                  likelihood_point_est, likelihood_mean, likelihood_sd) |>
    dplyr::arrange(dplyr::desc(likelihood_mean))
}


#' Convert match scores to likelihoods for all queries
#'
#' Applies the trained likelihood model to every `observation_id` in the match
#' object and returns a tidy data frame suitable for input to
#' `TaxaAssign::compute_posterior()`.
#'
#' For each query the function:
#' \enumerate{
#'   \item Groups candidates by `taxon_name` and takes the median score
#'     across references (robust to outlier accessions and sample-size bias).
#'   \item Logit-transforms and computes the gap relative to the runner-up
#'     taxon.
#'   \item Looks up species-specific parameters from the model (with
#'     hierarchical fallback to genus, then global mean).
#'   \item Evaluates H1/H2/H3 likelihoods and normalises to ratios.
#' }
#'
#' @param match_df Data frame in the canonical match-object format (output of
#'   `TaxaMatch::standardize_match_data()` or user-supplied).  Must contain
#'   `observation_id`, `score` (or `p_match`), `taxon_name`, `taxon_name_rank`,
#'   and taxonomy columns matching `rank_system`.
#' @param model_params Object of class `"taxa_model_params"` from
#'   [train_likelihood_model()].
#' @param rank_system Character vector of rank names **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`). Default `NULL` auto-detects
#'   from columns in `match_df`.
#' @param ratio_threshold Minimum likelihood ratio to retain a hypothesis
#'   (default `0.01`).  Hypotheses with likelihood ratio less than 1% of the
#'   best hypothesis are dropped.  This removes noise hypotheses that would
#'   not meaningfully affect posterior probabilities.
#' @param min_match_threshold Minimum raw score to consider a candidate
#'   (default `0.50`).  Queries whose best candidate scores below 50% identity
#'   are considered unmatchable and routed to the `$unresolved` output for
#'   re-evaluation with a coarser `rank_system`.
#' @param alpha Mahalanobis p-value cutoff for outlier rejection (default
#'   `1e-6`).
#' @param n_sims Monte Carlo simulations per query (default `0` = point
#'   estimate only).
#' @param score_bounds Optional `c(min, max)` for score normalization.
#' @param logit_epsilon Logit clipping value (default `1e-4`).
#' @param max_gap_ceiling Gap cap (default `5.0`).  Caps gap at 5 logit units
#'   (roughly the gap between 99.3% and 50% identity) to prevent extreme
#'   outliers from dominating model estimates.
#' @param verbose Logical (default `FALSE`). When `TRUE`, prints a message
#'   each time a species falls back to global parameters (no species-specific
#'   lookup entry found).
#'
#' @return A named list with two components:
#'   \describe{
#'     \item{`$likelihoods`}{Data frame with one row per `observation_id` x taxon
#'       hypothesis, suitable for input to `TaxaAssign::compute_posterior()`:
#'       `observation_id`, `taxon_name`, `taxon_name_rank`, `hypothesis_type`
#'       (`"specific_candidate"`, `"unreferenced_species"`, or `"unreferenced_genus"`),
#'       `likelihood_point_est`, `likelihood_mean`, `likelihood_sd`.  Rows
#'       where `taxon_name` resolved to `NA` are excluded.}
#'     \item{`$unresolved`}{Rows from `match_df` for any `observation_id` that
#'       produced no usable likelihoods (empty data frame if none).  Pass to
#'       a second call of `evaluate_likelihoods()` with a coarser
#'       `rank_system` to recover these queries.}
#'   }
#'
#' @details
#' \strong{Three hypotheses:}
#' For each query, three types of hypothesis are evaluated:
#' \itemize{
#'   \item \strong{H1 (specific_candidate):} The query comes from a known species
#'     in the reference database. The model predicts what a true match to this
#'     species looks like based on reference-vs-reference scores.
#'   \item \strong{H2 (unreferenced_species):} The query comes from a species not
#'     in the reference database, but whose genus is represented. The model
#'     shifts the H1 score distribution downward (by \code{H2$delta} logit
#'     units) to predict what a sister-species match looks like.
#'   \item \strong{H3 (unreferenced_genus):} The query comes from a genus not in
#'     the reference database at all. The score distribution is shifted further
#'     downward (by \code{H3$delta}).
#' }
#'
#' \strong{Features:}
#' \itemize{
#'   \item \strong{score_logit:} The raw match score (e.g., percent identity),
#'     normalised to 0-1 and logit-transformed. The logit maps the bounded
#'     score onto the real line, allowing Gaussian modelling.
#'   \item \strong{gap_logit:} The difference between the best within-taxon
#'     logit score and the best cross-taxon logit score. A large gap means the
#'     top candidate is much better than any alternative -- strong evidence for
#'     that identification. When only one candidate taxon exists, the gap is
#'     not computed (1D model used instead).
#' }
#'
#' \strong{hypothesis_type values in output:}
#' \itemize{
#'   \item \code{"specific_candidate"} -- referenced species with an explicit
#'     match in the query data.
#'   \item \code{"unreferenced_species"} -- placeholder for species absent from
#'     the reference database but whose genus is represented. These rows have
#'     generic taxon_name (the genus name) and can be expanded into named
#'     species by \code{TaxaAssign::expand_unreferenced_hypotheses()}.
#'   \item \code{"unreferenced_genus"} -- placeholder for entirely absent genera.
#' }
#'
#' @references
#' Somervuo, P., Koskela, S., Pennanen, J., Nilsson, R.H. and Ovaskainen, O.
#' (2017). Unbiased probabilistic taxonomic classification for DNA barcoding.
#' \emph{Bioinformatics}, 33(19), 2997--3005.
#' \doi{10.1093/bioinformatics/btx369}
#'
#' Efron, B. and Morris, C. (1973). Stein's estimation rule and its
#' competitors -- an empirical Bayes approach. \emph{Journal of the American
#' Statistical Association}, 68(341), 117--130.
#' \doi{10.1080/01621459.1973.10481350}
#'
#' @seealso [train_likelihood_model()], [filter_top_hypotheses()]
#'
#' @examples
#' \dontrun{
#' result <- evaluate_likelihoods(
#'   match_df, model,
#'   rank_system = c("family", "genus", "species"),
#'   n_sims = 1000
#' )
#' head(result$likelihoods)
#' nrow(result$unresolved)
#' }
#'
#' @importFrom cli cli_progress_bar cli_progress_update cli_progress_done
#' @importFrom dplyr any_of arrange bind_rows desc filter group_by group_split
#'   mutate n_distinct n_groups select summarise ungroup across first
#' @importFrom mvtnorm dmvnorm
#' @importFrom stats dnorm mahalanobis pchisq rnorm sd
#' @export
evaluate_likelihoods <- function(match_df,
                                 model_params,
                                 rank_system         = NULL,
                                 ratio_threshold     = 0.01,
                                 min_match_threshold = 0.50,
                                 alpha               = 1e-6,
                                 n_sims              = 0L,
                                 score_bounds        = NULL,
                                 logit_epsilon       = 1e-4,
                                 max_gap_ceiling     = 5.0,
                                 verbose             = FALSE) {
  if (!is.data.frame(match_df))
    stop("match_df must be a data frame")
  if (!inherits(model_params, "taxa_model_params"))
    stop("model_params must be a 'taxa_model_params' object from train_likelihood_model()")

  # Auto-detect rank_system from match_df columns
  if (is.null(rank_system)) {
    canonical <- c("kingdom", "phylum", "subphylum", "superclass", "class",
                   "subclass", "infraclass", "cohort", "order", "suborder",
                   "infraorder", "family", "genus", "species")
    rank_system <- canonical[canonical %in% tolower(names(match_df))]
    if (length(rank_system) < 2L)
      stop(
        "Could not auto-detect rank_system from match_df columns. ",
        "Found: ", paste(names(match_df), collapse = ", "),
        ". Supply rank_system explicitly.",
        call. = FALSE
      )
  }

  if (!is.character(rank_system) || length(rank_system) == 0L)
    stop("rank_system must be a non-empty character vector (coarse to fine)")

  names(match_df) <- tolower(names(match_df))

  if (!"observation_id" %in% names(match_df))
    stop("match_df must have an 'observation_id' column")
  if (anyNA(match_df$observation_id))
    stop("match_df$observation_id contains NA values; all rows must have a valid observation_id")

  n_queries <- dplyr::n_distinct(match_df$observation_id)
  message(sprintf("Evaluating likelihoods for %d unique queries...", n_queries))

  query_groups <- dplyr::group_split(dplyr::group_by(match_df, observation_id))

  start_time <- proc.time()[["elapsed"]]
  results  <- vector("list", length(query_groups))
  n_failed <- 0L

  pb <- cli::cli_progress_bar("Evaluating queries", total = length(query_groups))
  for (i in seq_along(query_groups)) {
    cli::cli_progress_update(id = pb)
    chunk  <- query_groups[[i]]
    sid    <- chunk$observation_id[1L]
    result <- tryCatch(
      .evaluate_one_query(
        candidate_df        = chunk,
        model_params        = model_params,
        rank_system         = rank_system,
        ratio_threshold     = ratio_threshold,
        min_match_threshold = min_match_threshold,
        alpha               = alpha,
        n_sims              = n_sims,
        score_bounds        = score_bounds,
        logit_epsilon       = logit_epsilon,
        max_gap_ceiling     = max_gap_ceiling,
        verbose             = verbose
      ),
      error = function(e) {
        warning(sprintf("Query '%s' failed: %s", sid, conditionMessage(e)))
        NULL
      }
    )
    if (!is.null(result)) {
      result$observation_id <- sid
      results[[i]] <- result
    } else {
      n_failed <- n_failed + 1L
    }
  }

  cli::cli_progress_done(id = pb)
  elapsed <- round(proc.time()[["elapsed"]] - start_time, 1L)
  message(sprintf("Evaluation complete in %.1f seconds.", elapsed))

  if (n_failed > 0L) {
    warning(sprintf(
      "evaluate_likelihoods: %d of %d observation_id(s) produced no usable likelihoods.",
      n_failed, length(query_groups)
    ))
  }

  out        <- dplyr::bind_rows(results)
  unresolved <- match_df[integer(0L), ]   # zero-row copy; populated below if needed

  # Identify rows where taxon_name resolved to NA (occurs when all taxonomy
  # columns are NA, e.g. reference identified only at a rank coarser than
  # rank_system specifies).  Rows are always dropped from $likelihoods.
  # observation_ids with NO surviving rows are returned in $unresolved with a warning.
  na_name <- is.na(out$taxon_name)
  if (any(na_name)) {
    sids_with_na   <- unique(out$observation_id[na_name])
    sids_with_good <- unique(out$observation_id[!na_name])
    all_na_sids    <- setdiff(sids_with_na, sids_with_good)

    if (length(all_na_sids) > 0L) {
      unresolved <- match_df[match_df$observation_id %in% all_na_sids, ]
      show_ids <- if (length(all_na_sids) <= 5L) {
        paste(all_na_sids, collapse = ", ")
      } else {
        paste0(paste(all_na_sids[1:5], collapse = ", "),
               sprintf(", ... (%d more)", length(all_na_sids) - 5L))
      }
      warning(sprintf(
        paste0(
          "%d observation_id(s) produced no usable likelihoods and are returned in ",
          "$unresolved: %s. These queries likely matched references identified ",
          "only at a coarser rank than rank_system specifies. Re-run ",
          "evaluate_likelihoods() on $unresolved with a rank_system that ",
          "includes the coarser rank, and re-run audit_reference_coverage() ",
          "with target_rank set to match."
        ),
        length(all_na_sids), show_ids
      ))
    }

    out <- out[!na_name, ]
  }

  likelihoods <- dplyr::select(out, observation_id, taxon_name, taxon_name_rank,
                               hypothesis_type, likelihood_point_est,
                               likelihood_mean, likelihood_sd)

  list(likelihoods = likelihoods, unresolved = unresolved)
}


#' Keep only the finest-rank specific candidates per query
#'
#' After `evaluate_likelihoods()`, each query may have specific candidates at
#' multiple ranks (e.g., both species- and genus-level hits).  This function
#' retains only the finest-rank specific candidates — coarser candidates are
#' redundant when a finer-rank hit exists — while keeping all
#' `"unreferenced_species"` and `"unreferenced_genus"` rows.
#'
#' @param likelihood_df Data frame -- the `$likelihoods` component of the list
#'   returned by [evaluate_likelihoods()].
#' @param rank_system Character vector of rank names **coarse to fine**.
#'   Used to assign numeric rank scores for comparison. Default `NULL`
#'   auto-detects from the `taxon_name_rank` values in `likelihood_df`.
#'
#' @return Filtered version of `likelihood_df`.
#'
#' @seealso [evaluate_likelihoods()]
#'
#' @examples
#' \dontrun{
#' result <- evaluate_likelihoods(match_df, model)
#' filtered <- filter_top_hypotheses(result$likelihoods)
#' }
#'
#' @importFrom dplyr filter group_by mutate select ungroup
#' @export
filter_top_hypotheses <- function(likelihood_df, rank_system = NULL) {
  if (!is.data.frame(likelihood_df))
    stop("likelihood_df must be a data frame")
  needed <- c("observation_id", "taxon_name_rank", "hypothesis_type")
  missing_cols <- setdiff(needed, names(likelihood_df))
  if (length(missing_cols) > 0L)
    stop(sprintf("likelihood_df is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))

  # Auto-detect rank_system from taxon_name_rank values
  if (is.null(rank_system)) {
    canonical <- TaxaTools::standard_ranks
    observed  <- unique(tolower(likelihood_df$taxon_name_rank))
    observed  <- observed[!is.na(observed)]
    rank_system <- canonical[canonical %in% observed]
    if (length(rank_system) == 0L)
      rank_system <- c("family", "genus", "species")
    message("filter_top_hypotheses: auto-detected rank_system: ",
            paste(rank_system, collapse = ", "))
  }

  # Numeric rank score: finest rank = highest number
  rank_scores <- stats::setNames(
    seq_along(rank_system),
    tolower(rank_system)
  )

  non_specific <- dplyr::filter(likelihood_df,
                                hypothesis_type != "specific_candidate")
  specific     <- dplyr::filter(likelihood_df,
                                hypothesis_type == "specific_candidate")

  if (nrow(specific) == 0L) {
    warning("filter_top_hypotheses: no specific_candidate rows found. Returning only unreferenced hypotheses.")
    return(non_specific)
  }

  # Warn about unknown rank values (will get NA rank_score and be dropped)
  unknown_ranks <- setdiff(tolower(unique(specific$taxon_name_rank)), names(rank_scores))
  if (length(unknown_ranks) > 0L) {
    warning(sprintf(
      "filter_top_hypotheses: taxon_name_rank value(s) not in rank_system: %s. These rows will be dropped. Ensure rank_system includes all ranks present in your data.",
      paste(unknown_ranks, collapse = ", ")
    ))
  }

  best_rank_per_query <- specific |>
    dplyr::mutate(
      rank_score = rank_scores[tolower(taxon_name_rank)]
    ) |>
    dplyr::filter(!is.na(rank_score)) |>
    dplyr::group_by(observation_id) |>
    dplyr::mutate(best_rank_score = max(rank_score, na.rm = TRUE)) |>
    dplyr::filter(rank_score == best_rank_score) |>
    dplyr::select(-rank_score, -best_rank_score) |>
    dplyr::ungroup()

  dplyr::bind_rows(best_rank_per_query, non_specific)
}
