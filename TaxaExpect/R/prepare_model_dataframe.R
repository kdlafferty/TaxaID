utils::globalVariables(c(
  "grid_id", "lat_r", "lon_r", ".habitat", "taxon_name",
  "n_species", "n_total_at_site", "n_other", "is_present",
  "observed_in_habitat"
))

#' Prepare Data for Biodiversity Modeling
#'
#' Converts raw occurrence records into the format required by
#' \code{\link{train_biodiversity_model}}. The function:
#' \enumerate{
#'   \item Checks for multicollinear covariates and warns if any pair exceeds
#'     \code{cor_threshold}.
#'   \item Aggregates records to species \eqn{\times} site-habitat counts and
#'     fills implicit zeros for species not observed at a site.
#'   \item Computes the \code{observed_in_habitat} flag -- \code{TRUE}
#'     if the species has been recorded in that habitat type at any site.
#'   \item Scales all covariate columns to zero mean / unit SD, storing the
#'     scaling parameters as an attribute for use at prediction time.
#' }
#'
#' @param data A dataframe. Must contain \code{grid_id}, \code{lat_r},
#'   \code{lon_r}, \code{taxon_name}, and the column named by
#'   \code{habitat_col}. Typically the output of
#'   \code{\link{create_sites_from_grid}} after habitat assignment.
#' @param covariates Character vector. Names of numeric covariate columns to
#'   scale and pass to the model. Default \code{c("lat_r", "lon_r")}.
#'   Additional covariates (beyond \code{lat_r} / \code{lon_r}) are checked
#'   for within-site variance and averaged to the site-habitat level if they
#'   vary within a cell.
#' @param habitat_col Character or \code{NULL}. Name of the habitat column.
#'   Default \code{"main_habitat"}. Set to \code{NULL} when no habitat
#'   classification is available (e.g. \code{TaxaHabitat} was not run) --
#'   the returned tibble then has no habitat column, and downstream
#'   \code{\link{train_biodiversity_model}} fits without a habitat term
#'   instead of degenerating to a single-level fixed effect.
#' @param cor_threshold Numeric. Pairwise correlation threshold for
#'   collinearity screening. Predictor pairs with |r| above this threshold
#'   trigger a warning suggesting PCA reduction of correlated covariates.
#'   Following Dormann et al. (2013), 0.7 is the conventional threshold
#'   beyond which collinearity substantially inflates coefficient variance.
#'   Default \code{0.7}.
#' @param sampling_group_col Character or \code{NULL}. Name of a column in
#'   \code{data} identifying which detection process/sampling method each
#'   taxon's records came from (e.g. \code{"phytoplankton"} vs.
#'   \code{"vertebrate"} on a broad marker). When supplied,
#'   \code{n_total_at_site} is computed separately within each group instead
#'   of pooling all taxa together, and the output gains a \code{sampling_group}
#'   column. Default \code{NULL} (no grouping; existing behavior unchanged).
#'   See the Shared effort assumption and Group-aware effort denominators
#'   sections below.
#'
#' @return A tibble with one row per species \eqn{\times} site-habitat
#'   combination (including implicit zeros). Columns are ordered as:
#'   \code{grid_id}, \code{lat_r}, \code{lon_r}, \code{<habitat_col>},
#'   \code{taxon_name}, \code{n_species}, \code{n_total_at_site},
#'   \code{n_other}, \code{is_present}, \code{observed_in_habitat},
#'   scaled covariate columns (\code{<cov>_s}), then all remaining columns.
#'
#'   The attribute \code{scale_params} is a named list -- one entry per
#'   covariate -- each containing \code{center} (mean) and \code{scale} (SD).
#'   These are extracted automatically by \code{\link{train_biodiversity_model}}
#'   and stored in the model object so new sites can be scaled consistently at
#'   prediction time.
#'
#' @details
#' \strong{No habitat (habitat_col = NULL):} the two-path design is: if you
#' have a habitat column, generate real habitat classifications (via
#' \code{TaxaHabitat}) and pass it here so habitat enters the model as a real
#' predictor; if you don't, pass \code{NULL} and skip habitat entirely rather
#' than defaulting to a single hardcoded category, which previously produced
#' a degenerate single-level factor that \code{train_biodiversity_model()}'s
#' Tier 2 formula could not fit (a real bug found 2026-07-03 testing a
#' single-observation prior pipeline that skipped \code{TaxaHabitat} to save
#' cost). With \code{habitat_col = NULL}, the returned tibble has no habitat
#' column at all.
#'
#' \strong{observed_in_habitat:} computed from positive detections only,
#' before zero-filling. If a species is predicted with non-trivial theta at a
#' site where \code{observed_in_habitat} is \code{FALSE}, that
#' prediction is a habitat extrapolation and should be treated with caution.
#'
#' \strong{Extra covariates:} any covariate beyond \code{lat_r} / \code{lon_r}
#' is checked for within-site-habitat variance. If values differ within a cell
#' (e.g. depth recorded per occurrence), they are averaged with a warning.
#' Consider summarising to site level before calling this function.
#'
#' @section Shared effort assumption:
#' \code{n_total_at_site} is the count of \emph{all} records at a grid cell
#' and serves as the shared effort denominator for every taxon in the binomial
#' model \code{cbind(n_species, n_other)}. This is only valid when all taxa
#' were detected through the \emph{same sampling process}. Combining taxa
#' collected by incommensurable methods --- for example, phytoplankton cell
#' counts and bird point-count sightings, or eDNA reads from two different gene
#' markers --- makes \code{n_total_at_site} a mixture of independent effort
#' denominators. The model would then treat effort from one survey as
#' informative about relative abundance in the other, which is not defensible.
#' Taxa with different detection methods should be modelled in separate
#' \code{train_biodiversity_model()} calls -- this is enforced, not just
#' documented advice: see \code{sampling_group_col} below and
#' \code{\link{train_biodiversity_model_by_group}}.
#'
#' @section Group-aware effort denominators (\code{sampling_group_col}):
#' When supplied, \code{n_total_at_site} is computed \emph{within} each
#' \code{sampling_group_col} value at a site, instead of pooling every taxon
#' together -- this is the code-level fix for the Shared effort assumption
#' above. Internally, \code{data} is split by
#' \code{sampling_group_col} and this function's existing aggregation logic is
#' applied to each split independently (never a shared \code{tidyr::complete()}
#' cross-join across groups, which would itself reintroduce cross-group
#' contamination), then the results are combined with a \code{sampling_group}
#' column identifying each row's group. Pass the result to
#' \code{\link{train_biodiversity_model_by_group}} to fit one model per group
#' rather than one pooled model across all of them --
#' \code{\link{train_biodiversity_model}} itself will refuse to fit a single
#' model against multi-group data (see its own docs) as a safety check.
#' Default \code{NULL}: no grouping.
#'
#' A row whose \code{sampling_group_col} value is \code{NA} is kept as its
#' own group (\code{sampling_group = NA}), not silently dropped. When
#' grouping is active, the \code{scale_params} attribute described above is
#' NOT attached (each group has its own covariate center/scale, and
#' combining them into one flat list would silently keep only one group's
#' values) -- instead the combined output carries
#' \code{scale_params_by_group}, a named list of per-group \code{scale_params}
#' lists, keyed by \code{sampling_group} value.
#' \code{\link{train_biodiversity_model_by_group}} does not read either
#' attribute from this combined output -- it re-derives its own per-group
#' \code{scale_params} by calling this function once per group internally --
#' so this only matters if you consume the combined, grouped output of this
#' function directly.
#'
#' @seealso \code{\link{create_sites_from_grid}},
#'   \code{\link{train_biodiversity_model}},
#'   \code{\link{train_biodiversity_model_by_group}}
#'
#' @examples
#' gridded_data <- data.frame(
#'   grid_id = rep(c("Grid_34p0_m119p0", "Grid_34p5_m119p5"), each = 4),
#'   lat_r = rep(c(34.0, 34.5), each = 4),
#'   lon_r = rep(c(-119.0, -119.5), each = 4),
#'   main_habitat = rep(c("Marine", "Freshwater"), 4),
#'   taxon_name = c(
#'     "Sp_a", "Sp_b", "Sp_a", "Sp_c",
#'     "Sp_a", "Sp_b", "Sp_b", "Sp_a"
#'   )
#' )
#' model_df <- prepare_model_dataframe(gridded_data,
#'   covariates = c("lat_r", "lon_r"),
#'   habitat_col = "main_habitat"
#' )
#' head(model_df)
#'
#' \dontrun{
#' # Group-aware effort denominators for a broad marker mixing detection
#' # processes (e.g. 18S phytoplankton + vertebrate counts):
#' model_df_grouped <- prepare_model_dataframe(
#'   gridded_data,
#'   habitat_col        = "main_habitat",
#'   sampling_group_col = "sampling_group"
#' )
#' }
#'
#' @importFrom dplyr rename filter group_by summarise mutate left_join distinct select ends_with across all_of as_tibble n bind_rows
#' @importFrom tidyr complete nesting replace_na
#' @importFrom rlang sym :=
#' @importFrom stats cor
#' @section Deprecated (kernel-priors redesign, 2026-08-31):
#' This function is part of the grid/GLMM prior-fitting path, which is
#' deprecated in favor of site-centered kernel estimation -- see
#' \code{\link{estimate_kernel_priors}} and
#' \code{\link{calibrate_kernel_bandwidth}}. Leave-one-block-out
#' validation on real data found single-cell prediction scored worse than
#' ignoring space entirely, while the kernel estimator improved both
#' composition prediction and downstream assignment precision. The GLMM
#' path remains fully functional (existing workflows still run it) and
#' emits a once-per-session notice; it will be archived once remaining
#' workflows migrate.
#'
#' @export
prepare_model_dataframe <- function(data,
                                    covariates = c("lat_r", "lon_r"),
                                    habitat_col = "main_habitat",
                                    cor_threshold = 0.7,
                                    sampling_group_col = NULL) {
  .glmm_deprecation_notice("prepare_model_dataframe")

  # --- Required column check --------------------------------------------------
  # habitat_col = NULL means "no habitat modeling" -- the caller has no habitat
  # column to supply and none is required. See @details.
  required_cols <- c("grid_id", "lat_r", "lon_r", habitat_col, "taxon_name")
  missing_cols <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0) {
    stop(
      "prepare_model_dataframe: missing required columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }

  missing_covs <- setdiff(covariates, names(data))
  if (length(missing_covs) > 0) {
    stop(
      "prepare_model_dataframe: covariate columns not found in data: ",
      paste(missing_covs, collapse = ", ")
    )
  }

  if (!is.null(sampling_group_col) && !sampling_group_col %in% names(data)) {
    stop(
      "prepare_model_dataframe: sampling_group_col '", sampling_group_col,
      "' not found in data."
    )
  }

  # --- Multicollinearity check ------------------------------------------------
  if (length(covariates) > 1) {
    cor_matrix <- cor(as.matrix(data[, covariates]), use = "pairwise.complete.obs")
    cor_upper <- cor_matrix
    cor_upper[lower.tri(cor_upper, diag = TRUE)] <- NA
    high_cor <- which(abs(cor_upper) > cor_threshold, arr.ind = TRUE)
    if (nrow(high_cor) > 0) {
      pairs <- apply(high_cor, 1, function(idx) {
        sprintf(
          "%s and %s (r = %.2f)",
          covariates[idx[1]], covariates[idx[2]],
          cor_upper[idx[1], idx[2]]
        )
      })
      warning(
        "prepare_model_dataframe: the following covariate pairs are correlated ",
        "above |r| = ", cor_threshold, ":\n  ",
        paste(pairs, collapse = "\n  "),
        "\nMulticollinearity may destabilize coefficient estimates. ",
        "Consider reducing correlated covariates via PCA before modeling.",
        call. = FALSE
      )
    }
  }

  # --- Per-group processing ----------------------------------------------------
  # sampling_group_col: rather than teach tidyr::complete()'s zero-filling to
  # respect group boundaries within one combined aggregation (fragile -- a
  # shared complete() call risks re-introducing cross-group zero-fill
  # contamination), split data by group and run the existing, already-tested
  # single-group aggregation logic (.prepare_one_group(), below) on each split
  # independently, then recombine. This guarantees n_total_at_site is never
  # pooled across groups.
  grid_size <- attr(data, "grid_size")

  if (is.null(sampling_group_col)) {
    out <- .prepare_one_group(data, covariates, habitat_col)
    if (!is.null(grid_size)) attr(out, "grid_size") <- grid_size
    return(out)
  }

  # --- Split by sampling group and recombine (Session 149) --------------------
  # base R's split() silently DROPS rows whose grouping value is NA -- fixed
  # by splitting on an explicit factor with exclude = NULL, which keeps NA as
  # its own real level (mirrors the pattern already used correctly nearby in
  # compute_adaptive_sampling_groups.R for the identical reason).
  group_vals <- data[[sampling_group_col]]
  if (anyNA(group_vals)) {
    message(sprintf(
      "prepare_model_dataframe: %d row(s) have NA in '%s'; grouped as sampling_group = NA rather than dropped.",
      sum(is.na(group_vals)), sampling_group_col
    ))
  }
  group_splits <- split(data, factor(group_vals, exclude = NULL))

  # Iterate by POSITION, not by name: when a name is the literal NA level
  # produced above, list[["<the NA-named element>"]] returns NULL (not the
  # element itself) rather than erroring, so a by-name loop would silently
  # skip the NA group here even though split() itself kept it.
  group_names <- names(group_splits)
  grouped_out <- lapply(seq_along(group_splits), function(i) {
    out <- .prepare_one_group(group_splits[[i]], covariates, habitat_col)
    out$sampling_group <- group_names[i]
    out
  })

  # dplyr::bind_rows() keeps only the FIRST element's value for a custom
  # attribute like scale_params (verified directly) -- every group after the
  # first would silently lose its own covariate center/scale to the first
  # group's values. Store scale_params per group instead of a single flat
  # attribute so no group's scaling is lost.
  scale_params_by_group <- stats::setNames(
    lapply(grouped_out, attr, which = "scale_params"),
    group_names
  )
  out <- dplyr::bind_rows(grouped_out)
  attr(out, "scale_params") <- NULL
  attr(out, "scale_params_by_group") <- scale_params_by_group
  if (!is.null(grid_size)) attr(out, "grid_size") <- grid_size
  out
}


#' Aggregate one group's occurrence data to species x site-habitat counts
#'
#' The single-group aggregation logic behind \code{\link{prepare_model_dataframe}}
#' -- extracted to a top-level, explicitly-parameterized helper (rather than a
#' closure nested inside \code{prepare_model_dataframe()}) so its body reads
#' at its own indentation level and so it can be called identically whether or
#' not \code{sampling_group_col} splits the input into several groups first.
#'
#' @param data A dataframe for ONE group (already split by
#'   \code{sampling_group_col} if applicable). Must contain \code{grid_id},
#'   \code{lat_r}, \code{lon_r}, \code{taxon_name}, and \code{habitat_col}
#'   (unless \code{habitat_col} is \code{NULL}).
#' @param covariates Character vector of numeric covariate columns to scale.
#' @param habitat_col Character or \code{NULL}. Name of the habitat column.
#' @return A tibble, the per-group column layout documented in
#'   \code{\link{prepare_model_dataframe}}'s own \code{@return}.
#' @noRd
.prepare_one_group <- function(data, covariates, habitat_col) {
  # --- Internal rename ---------------------------------------------------------
  # No habitat_col supplied: use a single constant internal placeholder so the
  # existing grouping/join logic below runs unchanged (grouping by a constant
  # is equivalent to not grouping by it). Dropped from the final output below
  # -- never exposed to the caller, and never enters any model formula (that
  # guarantee is enforced in train_biodiversity_model(), not here).
  no_habitat <- is.null(habitat_col)
  if (no_habitat) {
    data$.habitat <- "_no_habitat_"
  } else {
    data <- dplyr::rename(data, .habitat = !!habitat_col)
  }

  # --- Extra covariate handling -------------------------------------------------
  extra_covs <- setdiff(covariates, c("lat_r", "lon_r"))

  if (length(extra_covs) > 0) {
    cov_variance <- data |>
      dplyr::filter(!is.na(.habitat)) |>
      dplyr::group_by(grid_id, .habitat) |>
      dplyr::summarise(
        dplyr::across(dplyr::all_of(extra_covs),
          ~ length(unique(.x)) > 1,
          .names = "{.col}_varies"
        ),
        .groups = "drop"
      )
    vary_cols <- names(cov_variance)[
      grepl("_varies$", names(cov_variance)) &
        sapply(
          names(cov_variance)[grepl("_varies$", names(cov_variance))],
          function(v) any(cov_variance[[v]])
        )
    ]
    if (length(vary_cols) > 0) {
      orig_names <- sub("_varies$", "", vary_cols)
      warning(
        "prepare_model_dataframe: the following covariates vary within ",
        "site-habitat combinations and will be averaged: ",
        paste(orig_names, collapse = ", "),
        ". Consider summarizing to site level before modeling.",
        call. = FALSE
      )
    }
    site_covs <- data |>
      dplyr::filter(!is.na(.habitat)) |>
      dplyr::group_by(grid_id, .habitat) |>
      dplyr::summarise(
        dplyr::across(dplyr::all_of(extra_covs), \(x) mean(x, na.rm = TRUE)),
        .groups = "drop"
      )
  }

  # --- Site totals and species counts -------------------------------------------
  site_totals <- data |>
    dplyr::filter(!is.na(.habitat)) |>
    dplyr::group_by(grid_id, lat_r, lon_r, .habitat) |>
    dplyr::summarise(n_total_at_site = dplyr::n(), .groups = "drop")

  model_df <- data |>
    dplyr::filter(!is.na(.habitat)) |>
    dplyr::group_by(grid_id, lat_r, lon_r, .habitat, taxon_name) |>
    dplyr::summarise(n_species = dplyr::n(), .groups = "drop") |>
    tidyr::complete(
      tidyr::nesting(grid_id, lat_r, lon_r, .habitat),
      taxon_name,
      fill = list(n_species = 0L)
    ) |>
    dplyr::left_join(site_totals, by = c("grid_id", "lat_r", "lon_r", ".habitat")) |>
    dplyr::mutate(
      n_other    = n_total_at_site - n_species,
      is_present = as.integer(n_species > 0),
      .habitat   = as.factor(.habitat)
    )

  # --- Join extra covariates -----------------------------------------------------
  if (length(extra_covs) > 0) {
    model_df <- model_df |>
      dplyr::left_join(site_covs, by = c("grid_id", ".habitat")) |>
      dplyr::mutate(.habitat = as.factor(.habitat))
  }

  # --- observed_in_habitat flag --------------------------------------------------
  habitat_presence <- model_df |>
    dplyr::filter(n_species > 0) |>
    dplyr::distinct(taxon_name, .habitat) |>
    dplyr::mutate(observed_in_habitat = TRUE)
  model_df <- model_df |>
    dplyr::left_join(habitat_presence, by = c("taxon_name", ".habitat")) |>
    dplyr::mutate(observed_in_habitat = tidyr::replace_na(observed_in_habitat, FALSE))

  # --- Scale covariates -----------------------------------------------------------
  scale_params <- list()
  for (covariate in covariates) {
    cov_center <- mean(model_df[[covariate]], na.rm = TRUE)
    cov_scale <- sd(model_df[[covariate]], na.rm = TRUE)
    if (cov_scale == 0 || !is.finite(cov_scale)) {
      warning(sprintf(
        "Covariate '%s' has zero variance; centering only (no scaling).", covariate
      ))
      cov_scale <- 1
    }
    scale_params[[covariate]] <- list(center = cov_center, scale = cov_scale)
    new_col <- paste0(covariate, "_s")
    model_df[[new_col]] <- (model_df[[covariate]] - cov_center) / cov_scale
  }
  attr(model_df, "scale_params") <- scale_params

  # --- Final column order and return -----------------------------------------------
  if (no_habitat) {
    # Drop the internal placeholder entirely -- no habitat column in output.
    model_df <- model_df |>
      dplyr::select(-.habitat) |>
      dplyr::select(
        grid_id, lat_r, lon_r, taxon_name,
        n_species, n_total_at_site, n_other, is_present,
        observed_in_habitat,
        dplyr::ends_with("_s"),
        dplyr::everything()
      )
  } else {
    model_df <- model_df |>
      dplyr::rename(!!habitat_col := .habitat) |>
      dplyr::select(
        grid_id, lat_r, lon_r, !!habitat_col, taxon_name,
        n_species, n_total_at_site, n_other, is_present,
        observed_in_habitat,
        dplyr::ends_with("_s"),
        dplyr::everything()
      )
  }

  dplyr::as_tibble(model_df)
}
