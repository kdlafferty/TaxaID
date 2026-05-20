utils::globalVariables(c(
  "p_norm", "p_b", "score_logit", "id_x", "id_y",
  "max_foreign_score", "raw_gap", "gap_logit", "rank_category", "N_Obs",
  "rank_code_a.x", "rank_code_a",
  "median_self_match", "max_foreign_match", "n_self_neighbors",
  "integrity_gap", "error_type", "identifier",
  "species.x", "species.y", "p_match",
  "mu_score", "mu_gap", "sigma_score", "lookup_key", "rank",
  "score_logit_mean", "gap_logit_mean", "score_logit_var",
  "n_obs_species", "shrunk_mu_score", "shrunk_mu_gap", "shrunk_sigma",
  "w", "species"
))

# ==============================================================================
# MODULE B-QC: REFERENCE DATABASE ERROR DETECTION
# ==============================================================================

#' Flag mislabeled sequences in the reference database
#'
#' Examines a pairwise distance matrix (output of `build_reference_matrix()`)
#' and flags sequences whose best match is to a *different* species than their
#' own label -- a pattern consistent with mislabeling or contamination.
#'
#' Two error types are returned:
#' * **`"likely_mislabeled"`** -- the sequence's median within-species match is
#'   lower than its best cross-species match by more than `mislabel_threshold`.
#' * **`"unverified_singleton_high_match"`** -- the sequence has no within-species
#'   neighbours yet matches a foreign species at >= 0.98; it may be mislabeled or
#'   simply the only representative of its species.
#'
#' @param raw_df Data frame of pairwise match scores, as returned by
#'   `build_reference_matrix()`.  Must contain columns `id_x`, `id_y`,
#'   `species.x`, `species.y`, and `p_match` (raw scores on the 0-100 or 0-1
#'   scale used consistently within the matrix).
#' @param mislabel_threshold Numeric scalar (default `0.02`).  A reference
#'   sequence is flagged when its median within-species match score minus its
#'   maximum cross-species match score is below negative `mislabel_threshold`.
#'   The default 0.02 means a sequence is flagged if its best foreign match is
#'   within 2 percentage points of its typical self-match.  Adjust based on
#'   reference quality: lower values are stricter, flagging more sequences;
#'   higher values are more permissive, suitable for noisier markers.
#' @param return_all Logical (default `FALSE`).  If `TRUE`, returns all
#'   sequences including those flagged `"clean"`.
#'
#' @return A data frame with one row per unique `id_x` and columns:
#'   \describe{
#'     \item{`id_x`}{Sequence identifier.}
#'     \item{`species_x`}{Species label assigned to the sequence.}
#'     \item{`median_self_match`}{Median match score to within-species sequences.}
#'     \item{`max_foreign_match`}{Best match score to any cross-species sequence.}
#'     \item{`n_self_neighbors`}{Number of within-species neighbours.}
#'     \item{`integrity_gap`}{`median_self_match - max_foreign_match`.}
#'     \item{`error_type`}{`"likely_mislabeled"`, `"unverified_singleton_high_match"`,
#'       or `"clean"`.}
#'   }
#'
#' @seealso [build_reference_matrix()], [train_likelihood_model()]
#'
#' @examples
#' \dontrun{
#' ref_matrix <- build_reference_matrix(reference_df,
#'                                      rank_system = c("family", "genus", "species"))
#' flagged <- flag_reference_errors(ref_matrix, mislabel_threshold = 0.02)
#' table(flagged$flag)
#' }
#'
#' @export
flag_reference_errors <- function(raw_df,
                                  mislabel_threshold = 0.02,
                                  return_all = FALSE) {
  if (!is.data.frame(raw_df))
    stop("raw_df must be a data frame")
  needed <- c("id_x", "id_y", "species.x", "species.y", "p_match")
  missing_cols <- setdiff(needed, names(raw_df))
  if (length(missing_cols) > 0)
    stop(sprintf("raw_df is missing required columns: %s",
                 paste(missing_cols, collapse = ", ")))
  if (!is.numeric(mislabel_threshold) || length(mislabel_threshold) != 1L ||
      is.na(mislabel_threshold))
    stop("mislabel_threshold must be a single non-NA numeric value")
  if (!is.logical(return_all) || length(return_all) != 1L || is.na(return_all))
    stop("return_all must be TRUE or FALSE")

  qc <- raw_df |>
    dplyr::group_by(id_x, species.x) |>
    dplyr::summarise(
      median_self_match = stats::median(
        p_match[species.x == species.y & id_x != id_y], na.rm = TRUE
      ),
      max_foreign_match = suppressWarnings(
        max(p_match[species.x != species.y], na.rm = TRUE)
      ),
      n_self_neighbors = sum(species.x == species.y & id_x != id_y),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      max_foreign_match = ifelse(
        is.infinite(max_foreign_match) | is.na(max_foreign_match),
        0, max_foreign_match
      ),
      integrity_gap = median_self_match - max_foreign_match,
      error_type = dplyr::case_when(
        integrity_gap < -mislabel_threshold & n_self_neighbors > 0 ~
          "likely_mislabeled",
        # 98% identity is the conventional barcode gap threshold for many
        # markers. For ITS (fungi) where within-species variation is higher,
        # consider raising to 99%.
        n_self_neighbors == 0 & max_foreign_match > 0.98 ~
          "unverified_singleton_high_match",
        .default = "clean"
      )
    ) |>
    dplyr::rename(species_x = species.x)

  if (!return_all) {
    qc <- dplyr::filter(qc, error_type != "clean")
  }
  if (nrow(qc) == 0L && !return_all) {
    message("No reference errors detected.")
  }
  qc
}

# ==============================================================================
# MODULE C: TRAINING ENGINE (Empirical Bayes Shrinkage)
# ==============================================================================

#' Prepare within-species training pairs from a pairwise distance matrix
#'
#' Takes the output of `build_reference_matrix()` and produces the H1 training
#' data set used by `train_likelihood_model()`.  For each reference sequence the
#' function:
#' \enumerate{
#'   \item Normalises raw scores to (0, 1) then logit-transforms them.
#'   \item Computes the \emph{gap}: best within-species logit score minus the
#'     best cross-species logit score for the same query sequence.
#'   \item Retains the single best within-species match per query (reduces bias
#'     from variable per-species sequence counts).
#'   \item Adds \emph{singleton} rows (sequences with no within-species
#'     neighbours) with a fixed high gap.
#' }
#'
#' Taxonomy columns are renamed to `rank_code_a` ... `rank_code_z` so
#' that downstream training code does not depend on rank-name strings.
#' `rank_code_a` always corresponds to the finest rank (the last element of
#' `rank_system`).
#'
#' @param raw_df Data frame of pairwise match scores from
#'   `build_reference_matrix()`.  Must contain `id_x`, `id_y`, and either
#'   `p_match` or `raw_score`, plus taxonomy columns for each rank in
#'   `rank_system` with `.x` and `.y` suffixes (e.g., `species.x`, `genus.x`).
#' @param rank_system Character vector of rank names ordered **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`).  The finest rank (last element)
#'   is used as the primary grouping unit for H1 pairs.
#' @param score_bounds Optional length-2 numeric vector `c(min, max)`.  Passed
#'   to `.normalize_scores()`.  If `NULL` (default) the scale is auto-detected.
#' @param logit_epsilon Numeric scalar.  Clipping applied before logit to
#'   prevent infinite values (default `1e-4`).
#' @param max_gap_ceiling Numeric scalar.  Cap on `gap_logit` to prevent extreme
#'   outliers from dominating training (default `5.0`).  In logit space, 5.0
#'   corresponds roughly to the gap between 99.3% and 50% identity --
#'   differences larger than this are capped to prevent extreme outliers from
#'   dominating model estimates.
#'
#' @return A data frame with one row per query sequence containing:
#'   \describe{
#'     \item{`id_x`}{Query sequence identifier.}
#'     \item{`rank_code_a`, ...}{Generalized rank columns (finest = `a`).}
#'     \item{`score_logit`}{Logit-transformed normalized best within-species
#'       match score.}
#'     \item{`gap_logit`}{Score gap (capped at `max_gap_ceiling`).}
#'     \item{`rank_category`}{`"1_Known_Species"` or `"Singleton"`.}
#'     \item{`N_Obs`}{Number of within-species pairs for this taxon (used for
#'       shrinkage weight in `train_likelihood_model()`).}
#'   }
#'
#' @noRd
.prep_training_data <- function(raw_df,
                                rank_system,
                                score_bounds   = NULL,
                                logit_epsilon  = 1e-4,
                                max_gap_ceiling = 5.0) {
  if (!is.data.frame(raw_df))
    stop("raw_df must be a data frame")
  if (!is.character(rank_system) || length(rank_system) == 0L)
    stop("rank_system must be a non-empty character vector")

  names(raw_df) <- tolower(names(raw_df))
  rank_system   <- tolower(rank_system)

  # Validate rank columns exist (with .x/.y suffixes from build_reference_matrix)
  x_cols <- paste0(rank_system, ".x")
  missing_x <- setdiff(x_cols, names(raw_df))
  if (length(missing_x) > 0L) {
    stop(sprintf(
      "rank_system columns not found in raw_df: %s. Expected columns with '.x'/'.y' suffixes (e.g., '%s'). Check that rank_system matches the taxonomy columns in your reference matrix.",
      paste(missing_x, collapse = ", "), x_cols[1]
    ))
  }

  score_col <- if ("p_match" %in% names(raw_df)) "p_match" else "raw_score"
  raw_df$p_norm <- .normalize_scores(raw_df[[score_col]], bounds = score_bounds)

  # ---- STEP 1: GENERALISE TAXONOMY COLUMNS ----------------------------------
  # Rename rank columns to rank_code_a/b/c... (finest rank -> code_a).
  # Applied separately to .x and .y suffix sets, then recombined.
  .generalize_ranks <- function(df_sub, ranks) {
    present   <- intersect(ranks, names(df_sub))
    if (length(present) == 0L) return(df_sub)
    # rev(present): last element of ranks (finest) -> code_a
    codes     <- paste0("rank_code_", letters[seq_along(present)])
    rename_map <- stats::setNames(rev(present), codes)
    dplyr::rename(df_sub, !!rename_map)
  }

  df_x <- raw_df |>
    dplyr::select(dplyr::ends_with(".x")) |>
    dplyr::rename_with(~ sub("\\.x$", "", .x)) |>
    .generalize_ranks(rank_system) |>
    dplyr::rename_with(~ paste0(., ".x"))

  df_y <- raw_df |>
    dplyr::select(dplyr::ends_with(".y")) |>
    dplyr::rename_with(~ sub("\\.y$", "", .x)) |>
    .generalize_ranks(rank_system) |>
    dplyr::rename_with(~ paste0(., ".y"))

  if (!"rank_code_a.x" %in% names(df_x))
    stop("Taxonomy generalisation failed -- ensure input columns match rank_system")

  df_combined <- dplyr::bind_cols(
    dplyr::select(raw_df, id_x, id_y, p_norm),
    df_x, df_y
  )

  # ---- STEP 2: LOGIT TRANSFORM ----------------------------------------------
  # logit(0.01) = noise floor for foreign match scores; scores below 1%
  # identity are treated as random noise and replaced with this floor value.
  noise_floor_logit <- log(0.01 / (1 - 0.01))

  df_logit <- df_combined |>
    dplyr::mutate(
      p_b         = pmin(pmax(p_norm, logit_epsilon), 1 - logit_epsilon),
      score_logit = log(p_b / (1 - p_b))
    )

  # ---- STEP 3: FOREIGN STATS (max cross-species logit score per id_x) -------
  foreign_stats <- df_logit |>
    dplyr::filter(
      !is.na(.data[["rank_code_a.x"]]),
      !is.na(.data[["rank_code_a.y"]])
    ) |>
    dplyr::group_by(id_x) |>
    dplyr::summarise(
      max_foreign_score = suppressWarnings(
        max(score_logit[.data[["rank_code_a.x"]] != .data[["rank_code_a.y"]]],
            -Inf)
      ),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      max_foreign_score = ifelse(
        is.infinite(max_foreign_score), noise_floor_logit, max_foreign_score
      )
    )

  # ---- STEP 4: H1 PAIRS (same taxon, different sequence IDs) ----------------
  h1_pairs <- df_logit |>
    dplyr::filter(
      !is.na(.data[["rank_code_a.x"]]),
      !is.na(.data[["rank_code_a.y"]]),
      .data[["rank_code_a.x"]] == .data[["rank_code_a.y"]],
      id_x != id_y
    ) |>
    dplyr::left_join(foreign_stats, by = "id_x") |>
    dplyr::mutate(
      raw_gap       = score_logit - max_foreign_score,
      gap_logit     = pmin(raw_gap, max_gap_ceiling),
      rank_category = "1_Known_Species"
    )

  species_counts <- h1_pairs |>
    dplyr::group_by(rank_code_a.x) |>
    dplyr::summarise(N_Obs = dplyr::n(), .groups = "drop")

  df_h1 <- h1_pairs |>
    dplyr::group_by(id_x) |>
    dplyr::slice_max(score_logit, n = 1L, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::left_join(species_counts, by = "rank_code_a.x")

  # ---- STEP 5: SINGLETONS ---------------------------------------------------
  trained_ids <- unique(h1_pairs$id_x)
  all_ids     <- unique(df_logit$id_x)
  missing_ids <- setdiff(all_ids, trained_ids)

  # Singletons are identified as sequences absent from h1_pairs (no within-species
  # neighbours). They require self-match rows (id_x == id_y) in the distance matrix.
  # If the matrix lacks self-matches, singletons are identified by missing_ids alone.
  has_self_match <- any(df_logit$id_x == df_logit$id_y)
  if (length(missing_ids) > 0L && !has_self_match) {
    warning(sprintf(
      "%d singleton reference(s) found but distance matrix lacks self-matches. Singleton score estimates will use global mean instead of self-match scores.",
      length(missing_ids)
    ))
  }

  df_singletons <- if (has_self_match) {
    df_logit |>
      dplyr::filter(id_x %in% missing_ids, id_x == id_y) |>
      dplyr::distinct(id_x, .keep_all = TRUE)
  } else {
    # Fallback: take one row per missing_id with best score
    df_logit |>
      dplyr::filter(id_x %in% missing_ids) |>
      dplyr::group_by(id_x) |>
      dplyr::slice_max(score_logit, n = 1L, with_ties = FALSE) |>
      dplyr::ungroup()
  }

  df_singletons <- df_singletons |>
    dplyr::mutate(
      max_foreign_score = noise_floor_logit,
      gap_logit         = max_gap_ceiling,
      rank_category     = "Singleton",
      N_Obs             = 1L
    )

  # ---- COMBINE + STRIP .x SUFFIXES ------------------------------------------
  dplyr::bind_rows(df_h1, df_singletons) |>
    dplyr::rename_with(~ sub("\\.x$", "", .x), dplyr::ends_with(".x"))
}


#' Train the hierarchical likelihood model on reference-vs-reference scores
#'
#' Fits an Empirical Bayes model using pairwise within-species match scores
#' (from `build_reference_matrix()`) to learn species-specific score
#' distributions.  Per-species parameters are shrunk toward a global mean,
#' with shrinkage strength inversely proportional to the number of observations
#' for that species.  Optionally uses `lme4` random intercepts per taxonomic
#' rank for more robust estimation.
#'
#' @section Model structure:
#' For each candidate hypothesis the model uses a 2-dimensional multivariate
#' normal distribution over `(score_logit, gap_logit)`:
#' * **H1 (known species):** species-specific mean with shrinkage; global
#'   covariance matrix.
#' * **H2 (missing species):** H1 mean shifted left by `H2$delta` --
#'   approximately what a sister species looks like.
#' * **H3 (missing genus):** H1 mean shifted further left by `H3$delta`.
#'
#' @section Pseudo-data anchoring:
#' When `anchor_perfect = TRUE`, synthetic "perfect match" observations are
#' injected into the H1 training data before fitting the global mean.  This
#' prevents the **perfection penalty** -- a pathology where a 100\% match
#' receives a *lower* likelihood than the training mean (e.g., 98.5\%) because
#' the Gaussian density peaks at the mean.  Anchoring shifts the H1 mean
#' toward the theoretical maximum and expands the covariance, producing a
#' monotonically increasing likelihood surface as match quality approaches
#' 100\%.  The number of anchor points is 10\% of the H1 training rows
#' (minimum 5), weighted enough to nudge the mean without overwhelming real
#' data.
#'
#' @param raw_df Data frame of pairwise match scores, as returned by
#'   `build_reference_matrix()`.  Passed through `.prep_training_data()`.
#' @param rank_system Character vector of rank names, **coarse to fine**
#'   (e.g., `c("family", "genus", "species")`). Default `NULL` auto-detects
#'   from the `.x`-suffixed columns in `raw_df`.
#' @param score_bounds Optional `c(min, max)` for score normalization.
#' @param min_observed_sigma Numeric.  Floor on observed within-species score
#'   variance (default `1.0`).  Prevents overfitting on species with very low
#'   variance (e.g., a species with two nearly identical reference sequences).
#'   In logit space, 1.0 corresponds to meaningful within-species variation.
#' @param prior_weight Numeric.  Equivalent pseudo-sample size for Empirical
#'   Bayes shrinkage toward the global mean.  Controls how strongly
#'   species-specific estimates are regularized.  A value of 10 means each
#'   species estimate is pulled toward the global mean as if 10 additional
#'   observations at the global mean had been added.  Higher values produce
#'   more conservative (less species-specific) estimates; lower values trust
#'   per-species data more but risk overfitting for species with few
#'   references.  Default `10.0`.
#' @param use_hierarchy Logical (default `TRUE`).  If `TRUE` and `lme4` is
#'   available, fits random intercepts per rank level to stabilize estimates
#'   across the taxonomic hierarchy.
#' @param anchor_perfect Logical (default `TRUE`).  If `TRUE`, injects
#'   synthetic perfect-match observations into the H1 training data to
#'   prevent the perfection penalty (see section below).
#' @param mislabel_threshold Numeric.  Passed to `flag_reference_errors()` when
#'   removing mislabeled sequences before training (default `0.02`).  A
#'   reference sequence is flagged when its median within-species match score
#'   minus its maximum cross-species match score is below negative
#'   `mislabel_threshold`.  The default 0.02 means a sequence is flagged if
#'   its best foreign match is within 2 percentage points of its typical
#'   self-match.  Lower values are stricter, flagging more sequences.
#' @param logit_epsilon Numeric.  Logit-clipping value (default `1e-4`).
#' @param max_gap_ceiling Numeric.  Gap cap (default `5.0`).  Caps gap at 5
#'   logit units (roughly the gap between 99.3% and 50% identity) to prevent
#'   extreme outliers from dominating model estimates.
#'
#' @return A named list (class `"taxa_model_params"`) with slots:
#'   \describe{
#'     \item{`H1_Lookup`}{Data frame with per-species parameters: `lookup_key`,
#'       `rank`, `mu_score`, `mu_gap`, `sigma_score`.}
#'     \item{`H1_Global_Mu`}{Named numeric vector: `score_logit`, `gap_logit`
#'       (global fallback means).}
#'     \item{`H1_Sigma`}{2x2 covariance matrix for the global H1 distribution.}
#'     \item{`H2`}{List with `delta` and `sigma` for the missing-species
#'       hypothesis.}
#'     \item{`H3`}{List with `delta` and `sigma` for the missing-genus
#'       hypothesis.}
#'     \item{`Stats`}{List of diagnostics (e.g., `AIC_Score` if lmer succeeded,
#'       `n_species`, `n_singletons`).}
#'     \item{`reference_errors`}{Data frame of flagged references (output of
#'       \code{flag_reference_errors()}). Use with
#'       \code{\link{remove_flagged_references}} to clean a match object.}
#'   }
#'
#' @references
#' Efron, B. and Morris, C. (1973). Stein's estimation rule and its
#' competitors -- an empirical Bayes approach. \emph{Journal of the American
#' Statistical Association}, 68(341), 117--130.
#' \doi{10.1080/01621459.1973.10481350}
#'
#' Somervuo, P., Koskela, S., Pennanen, J., Nilsson, R.H. and Ovaskainen, O.
#' (2017). Unbiased probabilistic taxonomic classification for DNA barcoding.
#' \emph{Bioinformatics}, 33(19), 2997--3005.
#' \doi{10.1093/bioinformatics/btx369}
#'
#' Genz, A., Bretz, F., Miwa, T., Mi, X., Leisch, F., Scheipl, F. and
#' Hothorn, T. (2023). \emph{mvtnorm: Multivariate Normal and t
#' Distributions}. R package. \doi{10.5281/zenodo.10021696}
#'
#' Hebert, P.D.N., Cywinska, A., Ball, S.L. and deWaard, J.R. (2003).
#' Biological identifications through DNA barcodes. \emph{Proceedings of
#' the Royal Society of London B}, 270(1512), 313--321.
#' \doi{10.1098/rspb.2002.2218}
#'
#' @seealso [evaluate_likelihoods()], [interpret_model()]
#'
#' @examples
#' \dontrun{
#' ref_matrix <- build_reference_matrix(reference_df,
#'                                      rank_system = c("family", "genus", "species"))
#' model <- train_likelihood_model(ref_matrix,
#'                                 rank_system = c("family", "genus", "species"))
#' interpret_model(model)
#' }
#'
#' @importFrom dplyr bind_rows distinct ends_with filter group_by left_join
#'   mutate n rename_with select slice_max summarise ungroup case_when
#' @importFrom stats median setNames var lm coef
#' @export
train_likelihood_model <- function(raw_df,
                                   rank_system        = NULL,
                                   score_bounds       = NULL,
                                   min_observed_sigma = 1.0,
                                   prior_weight       = 10.0,
                                   use_hierarchy      = TRUE,
                                   anchor_perfect     = TRUE,
                                   mislabel_threshold  = 0.02,
                                   logit_epsilon      = 1e-4,
                                   max_gap_ceiling    = 5.0) {
  if (!is.data.frame(raw_df))
    stop("raw_df must be a data frame")

  # Auto-detect rank_system from .x-suffixed columns in raw_df
  if (is.null(rank_system)) {
    x_cols <- grep("\\.x$", tolower(names(raw_df)), value = TRUE)
    x_cols <- sub("\\.x$", "", x_cols)
    # Keep only recognised taxonomy ranks, in canonical coarse-to-fine order
    canonical <- c("kingdom", "phylum", "subphylum", "superclass", "class",
                   "subclass", "infraclass", "cohort", "order", "suborder",
                   "infraorder", "family", "genus", "species")
    rank_system <- canonical[canonical %in% x_cols]
    if (length(rank_system) < 2L)
      stop(
        "Could not auto-detect rank_system from raw_df columns. ",
        "Found .x columns: ", paste(x_cols, collapse = ", "),
        ". Supply rank_system explicitly.",
        call. = FALSE
      )
    message(sprintf("Auto-detected rank_system: %s",
                    paste(rank_system, collapse = ", ")))
  }

  if (!is.character(rank_system) || length(rank_system) == 0L)
    stop("rank_system must be a non-empty character vector (coarse to fine)")
  if (!is.numeric(prior_weight) || length(prior_weight) != 1L || prior_weight <= 0)
    stop("prior_weight must be a positive numeric scalar")
  if (!is.logical(use_hierarchy) || length(use_hierarchy) != 1L || is.na(use_hierarchy))
    stop("use_hierarchy must be TRUE or FALSE")
  if (!is.logical(anchor_perfect) || length(anchor_perfect) != 1L || is.na(anchor_perfect))
    stop("anchor_perfect must be TRUE or FALSE")

  message("Removing mislabeled references...")
  errors <- flag_reference_errors(raw_df,
                                  mislabel_threshold = mislabel_threshold,
                                  return_all        = FALSE)
  n_removed <- sum(errors$error_type == "likely_mislabeled")
  if (n_removed > 0)
    message(sprintf("Removed %d likely-mislabeled sequence(s) before training", n_removed))

  bad_ids <- errors$id_x[errors$error_type == "likely_mislabeled"]
  raw_clean <- dplyr::filter(raw_df, !id_x %in% bad_ids, !id_y %in% bad_ids)

  message("Preparing training data...")
  train_df <- .prep_training_data(
    raw_df          = raw_clean,
    rank_system     = rank_system,
    score_bounds    = score_bounds,
    logit_epsilon   = logit_epsilon,
    max_gap_ceiling = max_gap_ceiling
  )

  if (nrow(train_df) == 0L)
    stop("Training data is empty after preprocessing. Check that raw_df contains valid pairwise match scores and that rank_system columns are present.")

  h1_data <- dplyr::filter(train_df, rank_category == "1_Known_Species")
  n_species    <- dplyr::n_distinct(h1_data$rank_code_a)
  n_singletons <- sum(train_df$rank_category == "Singleton")

  if (nrow(h1_data) == 0L)
    stop("No H1 (within-species) pairs found -- cannot train model. All sequences may be singletons (only one per species in the reference database).")

  # ---- PSEUDO-DATA ANCHORING ------------------------------------------------
  # Anchoring is a form of informative pseudo-data, analogous to Bayesian
  # prior pseudo-counts. The 10% fraction nudges the global mean by ~0.5
  # logit units without overwhelming real data. For markers with very few
  # reference sequences (<50 total), anchoring has a larger relative effect;
  # inspect interpret_model() output to verify anchors did not distort the
  # H1 landscape.
  # Without anchoring, the H1 mean sits at the training average
  # (e.g., logit(0.985)) and a perfect 100% match falls in the tail.
  n_anchors <- 0L
  if (anchor_perfect) {
    perfect_logit <- log((1 - logit_epsilon) / logit_epsilon)
    real_pos_gaps <- h1_data$gap_logit[h1_data$gap_logit > 0]
    if (length(real_pos_gaps) == 0L || all(is.na(real_pos_gaps))) {
      anchor_gap <- max_gap_ceiling
      if (all(is.na(real_pos_gaps)))
        warning("All positive gaps are NA; using max_gap_ceiling for anchor gap.")
    } else {
      # 95th percentile of positive within-species gaps: represents "typical
      # good separation" for anchor pseudo-data.
      anchor_gap <- stats::quantile(real_pos_gaps, 0.95, na.rm = TRUE)
    }
    # Anchor count: max(5, 10% of training rows). 5 ensures anchoring even
    # for tiny datasets; 10% prevents dilution of real data.
    n_anchors <- max(5L, ceiling(nrow(h1_data) * 0.10))

    anchor_rows <- data.frame(
      score_logit   = rep(perfect_logit, n_anchors),
      gap_logit     = rep(as.numeric(anchor_gap), n_anchors),
      rank_category = "1_Known_Species",
      N_Obs         = 1L
    )
    # Fill taxonomy_code columns with placeholder so lme4 doesn't error
    code_cols_pre <- names(h1_data)[grepl("^rank_code_", names(h1_data))]
    for (cc in code_cols_pre) anchor_rows[[cc]] <- "ANCHOR_PERFECT"

    h1_data <- dplyr::bind_rows(h1_data, anchor_rows)
    message(sprintf("Anchoring: injected %d perfect-match pseudo-observations",
                    n_anchors))
  }

  # ---- GLOBAL PRIOR ---------------------------------------------------------
  global_mu_score <- mean(h1_data$score_logit, na.rm = TRUE)
  global_mu_gap   <- mean(h1_data$gap_logit,   na.rm = TRUE)
  global_var_score <- max(stats::var(h1_data$score_logit, na.rm = TRUE),
                          min_observed_sigma)
  global_var_gap   <- max(stats::var(h1_data$gap_logit,   na.rm = TRUE),
                          min_observed_sigma)
  global_cov <- tryCatch(
    stats::cov(cbind(score_logit = h1_data$score_logit, gap_logit = h1_data$gap_logit)),
    error = function(e) {
      warning("Covariance estimation failed (likely too few observations). Using diagonal fallback.")
      matrix(c(global_var_score, 0, 0, global_var_gap), 2, 2,
             dimnames = list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit")))
    }
  )
  if (any(!is.finite(global_cov))) {
    warning("Non-finite values in covariance matrix. Using diagonal fallback.")
    global_cov <- matrix(c(global_var_score, 0, 0, global_var_gap), 2, 2,
                         dimnames = list(c("score_logit", "gap_logit"), c("score_logit", "gap_logit")))
  }
  diag(global_cov) <- pmax(diag(global_cov), min_observed_sigma)

  # ---- OPTIONAL lme4 HIERARCHY ----------------------------------------------
  lmer_mu_score <- NULL
  lmer_mu_gap   <- NULL
  aic_score     <- NA_real_

  code_cols <- names(train_df)[grepl("^rank_code_[a-z]$", names(train_df))]

  # Early exit: lme4 hierarchy is uninformative with too few species
  if (use_hierarchy && n_species < 10L) {
    message(sprintf("Skipping lme4 hierarchy: only %d species (need >= 10).",
                    n_species))
    use_hierarchy <- FALSE
  }

  if (use_hierarchy && length(code_cols) >= 2L &&
      requireNamespace("lme4", quietly = TRUE)) {
    # Random intercepts for each rank level above species (code_b, code_c, ...)
    random_terms <- paste0("(1 | ", code_cols[-1L], ")", collapse = " + ")
    formula_score <- stats::as.formula(
      sprintf("score_logit ~ 1 + %s", random_terms)
    )
    formula_gap <- stats::as.formula(
      sprintf("gap_logit ~ 1 + %s", random_terms)
    )
    tryCatch({
      fit_score <- lme4::lmer(formula_score, data = h1_data,
                              control = lme4::lmerControl(optimizer = "bobyqa"))
      fit_gap   <- lme4::lmer(formula_gap,   data = h1_data,
                              control = lme4::lmerControl(optimizer = "bobyqa"))
      lmer_mu_score <- lme4::fixef(fit_score)[["(Intercept)"]]
      lmer_mu_gap   <- lme4::fixef(fit_gap)[["(Intercept)"]]
      aic_score <- stats::AIC(fit_score)
    }, error = function(e) {
      message(sprintf("lme4 fit failed (%s) -- falling back to global mean",
                      conditionMessage(e)))
    })
  }

  mu_score_global <- if (!is.null(lmer_mu_score)) lmer_mu_score else global_mu_score
  mu_gap_global   <- if (!is.null(lmer_mu_gap))   lmer_mu_gap   else global_mu_gap

  # ---- PER-SPECIES LOOKUP WITH SHRINKAGE ------------------------------------
  message("Fitting per-species parameters with Empirical Bayes shrinkage...")
  species_params <- h1_data |>
    dplyr::group_by(rank_code_a) |>
    dplyr::summarise(
      n_obs_species  = dplyr::n(),
      score_logit_mean = mean(score_logit, na.rm = TRUE),
      gap_logit_mean   = mean(gap_logit,   na.rm = TRUE),
      score_logit_var  = max(stats::var(score_logit, na.rm = TRUE),
                             min_observed_sigma, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::mutate(
      # Empirical Bayes shrinkage: w = N / (N + prior_weight).
      # James-Stein / Efron-Morris (1973) shrinkage estimator for Normal means.
      # prior_weight is the "equivalent sample size" of the prior: with
      # N = prior_weight observations, species and global means get equal weight.
      w             = n_obs_species / (n_obs_species + prior_weight),
      shrunk_mu_score = w * score_logit_mean + (1 - w) * mu_score_global,
      shrunk_mu_gap   = w * gap_logit_mean   + (1 - w) * mu_gap_global,
      # Variance shrinkage via linear combination is an approximation to the
      # inverse-chi-squared posterior. Adequate for typical barcode reference
      # sizes (3-20 sequences per species).
      shrunk_sigma    = sqrt(w * score_logit_var + (1 - w) * global_var_score)
    )

  # Remove anchor pseudo-species from lookup
  species_params <- dplyr::filter(species_params,
                                  rank_code_a != "ANCHOR_PERFECT")

  H1_Lookup <- tibble::tibble(
    lookup_key  = species_params$rank_code_a,
    rank        = rank_system[length(rank_system)],
    mu_score    = species_params$shrunk_mu_score,
    mu_gap      = species_params$shrunk_mu_gap,
    sigma_score = species_params$shrunk_sigma
  )

  # ---- H2 / H3 PARAMETERS ---------------------------------------------------
  # H2 delta estimated from observed foreign-match scores in the training data.
  # H3 delta = H2 delta + 2.0 (one additional rank step away).
  # Both sigma slots are 2x2 matrices for compatibility with dmvnorm.

  # Default H2 delta: 3 logit units ~ 95% vs 50% on the probability scale,
  # a reasonable default for typical barcode markers (COI, 12S). Marker-specific
  # tuning is handled automatically when sufficient foreign-match data exists
  # (see empirical override below).
  h2_delta_val  <- 3.0
  h2_sigma_mat  <- diag(2)
  rownames(h2_sigma_mat) <- colnames(h2_sigma_mat) <- c("score_logit", "gap_logit")

  if (nrow(h1_data) > 5L && "max_foreign_score" %in% names(train_df)) {
    # Filters extreme foreign-match scores below logit(0.007); prevents
    # outliers from inflating H2 delta.
    h2_scores <- train_df$max_foreign_score[
      train_df$rank_category == "1_Known_Species" &
        train_df$max_foreign_score > -5.0
    ]
    if (length(h2_scores) > 2L) {
      # Minimum H1-H2 separation of 0.5 ensures unreferenced-species
      # hypothesis is always distinguishable from known-species hypothesis.
      h2_delta_val <- max(0.5, mu_score_global - mean(h2_scores, na.rm = TRUE))
      # Minimum H2 variance of 0.1 prevents degenerate zero-variance
      # estimates when few foreign matches exist.
      h2_var        <- max(stats::var(h2_scores, na.rm = TRUE), 0.1)
      # Fixed gap variance of 1.0 for H2: when the true species is absent,
      # no candidate has a clear advantage, so gap is uninformative.
      h2_sigma_mat  <- matrix(c(h2_var, 0, 0, 1.0), ncol = 2L)
      rownames(h2_sigma_mat) <- colnames(h2_sigma_mat) <- c("score_logit", "gap_logit")
    }
  }

  h3_sigma_mat <- diag(2)
  rownames(h3_sigma_mat) <- colnames(h3_sigma_mat) <- c("score_logit", "gap_logit")

  H2 <- list(delta = h2_delta_val,           sigma = h2_sigma_mat)
  # H3 delta = H2 delta + 2.0: heuristic representing one additional
  # taxonomic rank step (genus-level mismatch vs species-level mismatch).
  # H3 is rarely decisive; inspect via interpret_model() if needed.
  # Alternative: estimate from genus-level foreign-match data (low priority).
  H3 <- list(delta = h2_delta_val + 2.0,     sigma = h3_sigma_mat)

  message(sprintf(
    "Model trained: %d species, %d singletons. Global mu_score=%.2f, mu_gap=%.2f",
    n_species, n_singletons, mu_score_global, mu_gap_global
  ))

  structure(
    list(
      H1_Lookup   = H1_Lookup,
      H1_Global_Mu = c(score_logit = mu_score_global,
                       gap_logit   = mu_gap_global),
      H1_Sigma    = global_cov,
      H2          = H2,
      H3          = H3,
      Stats       = list(
        AIC_Score    = aic_score,
        n_species    = n_species,
        n_singletons = n_singletons,
        n_anchors    = n_anchors
      ),
      reference_errors = errors
    ),
    class = "taxa_model_params"
  )
}
