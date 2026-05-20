utils::globalVariables(c(
  "n_distinct_locs", "cv_N", "n_samples", "suitability_score",
  "median_N", "median_S", "n_habitats_kept", "passed",
  "log_locs", "norm_locs", "norm_quality", "norm_stability", "inv_cv",
  "S", "N", "n_locs", "prop", "loc_id", "grid_size", ".data",
  "max_habitat_locs"
))

#' Recommend Spatial Grid Resolutions for Biodiversity Modeling
#'
#' Searches a range of grid resolutions to identify sizes that balance
#' spatial coverage, site quality, and sampling stability for use with
#' \code{\link{prepare_model_dataframe}} and
#' \code{\link{train_biodiversity_model}}. Each resolution is scored on
#' three criteria and results are returned ranked by a composite suitability
#' index.
#'
#' When no resolution meets the \code{min_distinct_locs} threshold, the
#' function attempts three progressively coarser fallbacks rather than
#' returning \code{NA}:
#' \describe{
#'   \item{Fallback A}{The coarsest resolution at which the most-sampled
#'     habitat contains at least 10 distinct grid cells (enough for a
#'     meaningful average).}
#'   \item{Fallback B}{The coarsest resolution at which the most-sampled
#'     habitat contains at least 3 distinct grid cells (minimum needed to
#'     compute a standard deviation).}
#'   \item{Fallback C}{A single grid cell spanning the full bounding box of
#'     the dataset (all observations pooled; no spatial variance).}
#' }
#' In all fallback cases a warning is issued advising the user to expand
#' their bounding box or date range to generate more data.
#'
#' @param observation_data A dataframe of occurrence records. Must contain
#'   columns named by \code{lat_col}, \code{lon_col}, \code{species_col},
#'   and \code{habitat_col}. Rows with \code{NA} in any of these columns
#'   are silently dropped before analysis.
#' @param n_covariates Integer. The number of predictor variables intended
#'   for the final model. Used to calculate sample-size targets (10x and
#'   15x rules of thumb). E.g., for a model with 3 covariates, targets are
#'   40 and 60 site-habitat cells.
#' @param protected_habitat Character. Name of a habitat that must never be
#'   dropped, even if it fails the \code{min_locs_per_habitat} threshold.
#'   Useful when one habitat is ecologically important but sparse in GBIF
#'   data. \code{NULL} (default) applies the rarity threshold to all
#'   habitats equally.
#' @param min_s_threshold Integer. Minimum number of distinct species
#'   per grid cell for inclusion in analysis. Cells with fewer species lack
#'   sufficient community data for habitat assignment. Default 5.
#' @param min_N_threshold Integer. Minimum total observations per grid cell.
#'   Cells with fewer observations have high sampling variance. Default 10.
#'   Aligns with the \code{effort_threshold} argument of
#'   \code{\link{train_biodiversity_model}}.
#' @param min_distinct_locs Integer. Minimum number of unique geographic
#'   locations across all cells. Fewer locations indicate insufficient
#'   spatial coverage for grid optimization. Resolutions below this are
#'   excluded from the scored output. Default 20.
#' @param min_locs_per_habitat Integer. Minimum unique locations per habitat
#'   type. Ensures each habitat category is represented in multiple cells
#'   for reliable comparison. Habitats below this are dropped unless
#'   protected. Default 3.
#' @param min_grid Numeric. Minimum grid cell size in decimal degrees
#'   (~11 km at the equator). Prevents over-resolution that creates cells
#'   with too few observations for reliable estimation. Default 0.1.
#' @param max_grid Numeric. Maximum grid cell size in decimal degrees
#'   (~111 km at the equator). Prevents under-resolution that obscures
#'   spatial patterns. Default 1.0.
#' @param step_grid Numeric. Search increment in decimal degrees (~5.5 km).
#'   Smaller values give finer grid-size optimization but increase
#'   computation time. Default 0.05.
#' @param lat_col Character. Name of the latitude column. Default
#'   \code{"decimalLatitude"}.
#' @param lon_col Character. Name of the longitude column. Default
#'   \code{"decimalLongitude"}.
#' @param species_col Character. Name of the species identifier column.
#'   Default \code{"taxon_name"}.
#' @param habitat_col Character. Name of the habitat column. Default
#'   \code{"main_habitat"}.
#' @param weights Named numeric vector of length 3. Composite score weights
#'   for the three optimization criteria. \code{resolution} rewards smaller
#'   cells (finer spatial detail); \code{quality} rewards cells meeting
#'   minimum species and observation thresholds; \code{stability} penalizes
#'   grids where small changes cause large jumps in the number of qualifying
#'   cells. Must sum to 1. Default
#'   \code{c(resolution = 0.4, quality = 0.4, stability = 0.2)}. Adjust for
#'   study design: increase resolution weight for fine-scale studies,
#'   increase quality weight for sparse datasets.
#'
#' @return A named list with four elements:
#'   \describe{
#'     \item{summary_table}{A tibble of resolutions that met the
#'       \code{min_distinct_locs} threshold, sorted by descending
#'       \code{suitability_score}. Empty tibble when a fallback is used.
#'       Key columns: \code{grid_size}, \code{suitability_score},
#'       \code{n_distinct_locs}, \code{cv_N}, \code{n_samples},
#'       \code{median_N}, \code{median_S}, \code{n_habitats_kept}.}
#'     \item{best_grid}{Numeric. The selected grid size. Pass this to
#'       \code{\link{create_sites_from_grid}} as \code{grid_size}.}
#'     \item{explanation}{Character. Human-readable summary of why the
#'       winning resolution was selected, or which fallback was applied.}
#'     \item{fallback_level}{Character. One of \code{"none"} (optimal),
#'       \code{"A"} (10 grid cells in best habitat), \code{"B"} (3 grid
#'       cells in best habitat), or \code{"C"} (single bbox-spanning cell).
#'       Use this to branch programmatically on result quality.}
#'   }
#'
#' @details
#' \strong{Composite suitability score:} Three metrics are normalised to
#' the range 0 to 1 and combined with \code{weights}:
#' \enumerate{
#'   \item \strong{Resolution} (log-scaled distinct location count): log
#'     scale penalises the diminishing returns of very fine grids that
#'     merely splinter observations without adding spatial information.
#'   \item \strong{Quality} (median N per cell): higher median effort per
#'     cell produces more stable theta estimates.
#'   \item \strong{Stability} (inverse CV of N): low coefficient of
#'     variation means effort is evenly distributed; high CV means a few
#'     cells dominate.
#' }
#' When only one resolution passes all thresholds, normalisation is
#' undefined (max == min); scores default to 0 and the single candidate
#' is returned as the winner.
#'
#' \strong{Sample-size targets:} The 10x and 15x rules of thumb apply to
#' the number of site-habitat cells (rows in the model dataframe after
#' zero-filling), not the number of raw observations. They are printed as
#' messages for reference but do not gate the output.
#'
#' @seealso \code{\link{create_sites_from_grid}},
#'   \code{\link{prepare_model_dataframe}}
#'
#' @examples
#' \dontrun{
#' grid_results <- optimize_grid_size(
#'   observation_data = occurrences,
#'   grid_sizes = c(0.05, 0.10, 0.25),
#'   min_species = 5
#' )
#' }
#'
#' @importFrom dplyr mutate group_by summarise filter select arrange
#'   distinct n_distinct pull desc bind_rows all_of
#' @importFrom tidyr drop_na
#' @importFrom rlang sym !!
#' @importFrom stats sd median var
#' @importFrom tibble tibble
#' @export

optimize_grid_size <- function(
    observation_data,
    n_covariates,
    protected_habitat    = NULL,
    min_s_threshold      = 5L,
    min_N_threshold      = 10L,
    min_distinct_locs    = 20L,
    min_locs_per_habitat = 3L,
    min_grid             = 0.1,
    max_grid             = 1.0,
    step_grid            = 0.05,
    lat_col              = "decimalLatitude",
    lon_col              = "decimalLongitude",
    species_col          = "taxon_name",
    habitat_col          = "main_habitat",
    weights              = c(resolution = 0.4, quality = 0.4, stability = 0.2)
) {

  # --- Input checks -----------------------------------------------------------
  if (abs(sum(weights) - 1) > 0.001) {
    stop("optimize_grid_size: 'weights' must sum to 1.")
  }
  if (!all(c("resolution", "quality", "stability") %in% names(weights))) {
    stop(
      "optimize_grid_size: 'weights' must be a named vector ",
      "with elements 'resolution', 'quality', and 'stability'."
    )
  }

  required_cols <- c(lat_col, lon_col, species_col, habitat_col)
  missing_cols  <- setdiff(required_cols, names(observation_data))
  if (length(missing_cols) > 0) {
    stop(
      "optimize_grid_size: missing columns in ",
      "'observation_data': ", paste(missing_cols, collapse = ", ")
    )
  }

  df_clean <- observation_data |>
    tidyr::drop_na(dplyr::all_of(required_cols))

  if (nrow(df_clean) == 0) {
    stop(
      "optimize_grid_size: no rows remain after removing NAs ",
      "from required columns."
    )
  }

  if (!is.null(protected_habitat)) {
    available_habitats <- unique(df_clean[[habitat_col]])
    if (!protected_habitat %in% available_habitats) {
      warning(
        "optimize_grid_size: protected_habitat '",
        protected_habitat, "' not found in data. Protection not applied.",
        call. = FALSE
      )
      protected_habitat <- NULL
    } else {
      message("Protected habitat: '", protected_habitat, "'")
    }
  }

  # Sample-size guidance (informational only)
  model_df  <- n_covariates + 1L
  target_10 <- 10L * model_df
  target_15 <- 15L * model_df
  message(sprintf(
    "Sample-size targets for %d covariate(s): 10x = %d cells, 15x = %d cells.",
    n_covariates, target_10, target_15
  ))

  # --- Grid search ------------------------------------------------------------
  resolutions <- seq(min_grid, max_grid, by = step_grid)

  results_list <- lapply(
    resolutions,
    .score_one_resolution,
    df_clean             = df_clean,
    lat_col              = lat_col,
    lon_col              = lon_col,
    species_col          = species_col,
    habitat_col          = habitat_col,
    min_s_threshold      = min_s_threshold,
    min_N_threshold      = min_N_threshold,
    min_distinct_locs    = min_distinct_locs,
    min_locs_per_habitat = min_locs_per_habitat,
    protected_habitat    = protected_habitat
  )

  results_df <- dplyr::bind_rows(results_list)

  # --- Shared fallback advisory message ---------------------------------------
  .fallback_advice <- paste0(
    "Consider expanding the spatial bounding box or broadening the date ",
    "range when retrieving GBIF data to increase grid coverage."
  )

  # --- Score passing resolutions (optimal path) -------------------------------
  if (nrow(results_df) > 0) {
    scored <- results_df |>
      dplyr::filter(passed) |>
      dplyr::mutate(
        log_locs       = log(n_distinct_locs),
        norm_locs      = .safe_normalise(log_locs),
        norm_quality   = .safe_normalise(median_N),
        inv_cv         = 1 / cv_N,
        norm_stability = .safe_normalise(inv_cv),
        suitability_score =
          weights["resolution"] * norm_locs +
          weights["quality"]    * norm_quality +
          weights["stability"]  * norm_stability
      ) |>
      dplyr::arrange(dplyr::desc(suitability_score)) |>
      dplyr::select(
        grid_size, suitability_score, n_distinct_locs, cv_N,
        n_samples, median_N, median_S, n_habitats_kept
      )
  } else {
    scored <- tibble::tibble()
  }

  if (nrow(scored) > 0) {
    winner      <- scored[1, ]
    explanation <- sprintf(
      paste0(
        "Recommended grid: %.2f degrees.\n",
        "Reasoning: highest composite score (%.2f) among %d valid resolution(s), ",
        "with %d distinct locations and effort CV of %.2f."
      ),
      winner$grid_size,
      winner$suitability_score,
      nrow(scored),
      winner$n_distinct_locs,
      winner$cv_N
    )
    message(explanation)
    return(list(
      summary_table  = scored,
      best_grid      = winner$grid_size,
      explanation    = explanation,
      fallback_level = "none"
    ))
  }

  # --- Fallback A: coarsest resolution with >= 10 grid cells in best habitat --
  if (nrow(results_df) > 0) {
    fallback_a_candidates <- results_df |>
      dplyr::filter(max_habitat_locs >= 10L) |>
      dplyr::arrange(dplyr::desc(grid_size))

    if (nrow(fallback_a_candidates) > 0) {
      winner_grid <- fallback_a_candidates$grid_size[1]
      winner_row  <- fallback_a_candidates[1, ]
      explanation <- sprintf(
        paste0(
          "Fallback A applied: no resolution met the min_distinct_locs = %d ",
          "threshold overall, but grid size %.2f degrees yields >= 10 distinct ",
          "cells in the most-sampled habitat (%d cells). ",
          "Averages are computable but spatial resolution is limited.\n",
          .fallback_advice
        ),
        min_distinct_locs,
        winner_grid,
        winner_row$max_habitat_locs
      )
      warning(explanation, call. = FALSE)
      return(list(
        summary_table  = tibble::tibble(),
        best_grid      = winner_grid,
        explanation    = explanation,
        fallback_level = "A"
      ))
    }
  }

  # --- Fallback B: coarsest resolution with >= 3 grid cells in best habitat ---
  if (nrow(results_df) > 0) {
    fallback_b_candidates <- results_df |>
      dplyr::filter(max_habitat_locs >= 3L) |>
      dplyr::arrange(dplyr::desc(grid_size))

    if (nrow(fallback_b_candidates) > 0) {
      winner_grid <- fallback_b_candidates$grid_size[1]
      winner_row  <- fallback_b_candidates[1, ]
      explanation <- sprintf(
        paste0(
          "Fallback B applied: no resolution yielded >= 10 grid cells in any ",
          "single habitat. Grid size %.2f degrees provides only %d cells in the ",
          "most-sampled habitat -- the minimum needed to compute a standard ",
          "deviation. Variance estimates will be unreliable.\n",
          .fallback_advice
        ),
        winner_grid,
        winner_row$max_habitat_locs
      )
      warning(explanation, call. = FALSE)
      return(list(
        summary_table  = tibble::tibble(),
        best_grid      = winner_grid,
        explanation    = explanation,
        fallback_level = "B"
      ))
    }
  }

  # --- Fallback C: single bbox-spanning grid cell (fully pooled) --------------
  lat_range        <- diff(range(df_clean[[lat_col]]))
  lon_range        <- diff(range(df_clean[[lon_col]]))
  bbox_span        <- max(lat_range, lon_range)
  single_grid_size <- ceiling((bbox_span + step_grid) * 100) / 100

  explanation <- sprintf(
    paste0(
      "Fallback C applied: data are too sparse for any multi-cell grid. ",
      "A single grid cell of %.2f degrees (spanning the full bounding box) ",
      "is returned. All observations are pooled into one site; no spatial ",
      "variance can be estimated. Theta estimates should be treated as a ",
      "coarse regional prior only.\n",
      .fallback_advice
    ),
    single_grid_size
  )
  warning(explanation, call. = FALSE)

  list(
    summary_table  = tibble::tibble(),
    best_grid      = single_grid_size,
    explanation    = explanation,
    fallback_level = "C"
  )
}


# ------------------------------------------------------------------------------
# Internal helpers -- not exported
# ------------------------------------------------------------------------------

#' Score one resolution in the grid search
#'
#' @param res Numeric. Grid resolution in decimal degrees.
#' @param df_clean Cleaned observation dataframe.
#' @param lat_col,lon_col,species_col,habitat_col Column names.
#' @param min_s_threshold,min_N_threshold,min_distinct_locs,min_locs_per_habitat
#'   Thresholds as passed from the parent function.
#' @param protected_habitat Character or NULL.
#' @return A one-row tibble of metrics, or NULL if no valid sites.
#' @noRd

.score_one_resolution <- function(res,
                                   df_clean,
                                   lat_col,
                                   lon_col,
                                   species_col,
                                   habitat_col,
                                   min_s_threshold,
                                   min_N_threshold,
                                   min_distinct_locs,
                                   min_locs_per_habitat,
                                   protected_habitat) {

  hab_sym     <- rlang::sym(habitat_col)
  species_sym <- rlang::sym(species_col)

  # Snap to grid and summarise per site-habitat cell
  site_data <- df_clean |>
    dplyr::mutate(
      lat_r  = round(.data[[lat_col]] / res) * res,
      lon_r  = round(.data[[lon_col]] / res) * res,
      loc_id = paste(lat_r, lon_r, sep = "_")
    ) |>
    dplyr::group_by(loc_id, !!hab_sym) |>
    dplyr::summarise(
      S = dplyr::n_distinct(!!species_sym),
      N = dplyr::n(),
      .groups = "drop"
    )

  # Apply per-cell quality thresholds
  valid_sites <- site_data |>
    dplyr::filter(S >= min_s_threshold, N >= min_N_threshold)

  if (nrow(valid_sites) == 0) return(NULL)

  # Drop habitats with too few distinct locations (unless protected)
  habitat_locs <- valid_sites |>
    dplyr::group_by(!!hab_sym) |>
    dplyr::summarise(n_locs = dplyr::n_distinct(loc_id), .groups = "drop")

  if (!is.null(protected_habitat)) {
    kept_habs <- habitat_locs |>
      dplyr::filter(n_locs >= min_locs_per_habitat |
                      (!!hab_sym) == protected_habitat) |>
      dplyr::pull(!!hab_sym)
  } else {
    kept_habs <- habitat_locs |>
      dplyr::filter(n_locs >= min_locs_per_habitat) |>
      dplyr::pull(!!hab_sym)
  }

  final_sites <- valid_sites |>
    dplyr::filter((!!hab_sym) %in% kept_habs)

  if (nrow(final_sites) == 0) return(NULL)

  n_locs <- dplyr::n_distinct(final_sites$loc_id)
  mean_n <- mean(final_sites$N)
  sd_n   <- stats::sd(final_sites$N)
  if (mean_n == 0 || !is.finite(mean_n)) {
    cv_n <- Inf
  } else {
    cv_n <- sd_n / mean_n
  }

  # Max distinct grid cells in any single habitat -- used by fallback logic
  max_hab_locs <- final_sites |>
    dplyr::group_by(!!hab_sym) |>
    dplyr::summarise(n_locs = dplyr::n_distinct(loc_id), .groups = "drop") |>
    dplyr::pull(n_locs) |>
    max()

  tibble::tibble(
    grid_size         = res,
    n_samples         = nrow(final_sites),
    n_distinct_locs   = n_locs,
    n_habitats_kept   = length(kept_habs),
    median_S          = stats::median(final_sites$S),
    median_N          = stats::median(final_sites$N),
    cv_N              = cv_n,
    max_habitat_locs  = max_hab_locs,
    passed            = n_locs >= min_distinct_locs
  )
}


#' Normalise a numeric vector to the range 0 to 1; returns 0 everywhere if max == min
#'
#' @param x Numeric vector.
#' @return Numeric vector of the same length.
#' @noRd

.safe_normalise <- function(x) {
  x[is.infinite(x)] <- NA_real_
  rng <- range(x, na.rm = TRUE)
  if (!is.finite(rng[1]) || !is.finite(rng[2])) return(rep(NA_real_, length(x)))
  if (rng[2] - rng[1] < .Machine$double.eps)     return(rep(0,         length(x)))
  (x - rng[1]) / (rng[2] - rng[1])
}
