utils::globalVariables(c(
  "grid_id", "lat_r", "lon_r", ".habitat", "taxon_name",
  "n_species", "n_total_at_site", "n_other", "is_present",
  "habitat_observed_elsewhere"
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
#'   \item Computes the \code{habitat_observed_elsewhere} flag — \code{TRUE}
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
#' @param habitat_col Character. Name of the habitat column.
#'   Default \code{"main_habitat"}.
#' @param cor_threshold Numeric. Pairwise correlation threshold for
#'   collinearity screening. Predictor pairs with |r| above this threshold
#'   trigger a warning suggesting PCA reduction of correlated covariates.
#'   Following Dormann et al. (2013), 0.7 is the conventional threshold
#'   beyond which collinearity substantially inflates coefficient variance.
#'   Default \code{0.7}.
#'
#' @return A tibble with one row per species \eqn{\times} site-habitat
#'   combination (including implicit zeros). Columns are ordered as:
#'   \code{grid_id}, \code{lat_r}, \code{lon_r}, \code{<habitat_col>},
#'   \code{taxon_name}, \code{n_species}, \code{n_total_at_site},
#'   \code{n_other}, \code{is_present}, \code{habitat_observed_elsewhere},
#'   scaled covariate columns (\code{<cov>_s}), then all remaining columns.
#'
#'   The attribute \code{scale_params} is a named list — one entry per
#'   covariate — each containing \code{center} (mean) and \code{scale} (SD).
#'   These are extracted automatically by \code{\link{train_biodiversity_model}}
#'   and stored in the model object so new sites can be scaled consistently at
#'   prediction time.
#'
#' @details
#' \strong{habitat_observed_elsewhere:} computed from positive detections only,
#' before zero-filling. If a species is predicted with non-trivial theta at a
#' site where \code{habitat_observed_elsewhere} is \code{FALSE}, that
#' prediction is a habitat extrapolation and should be treated with caution.
#'
#' \strong{Extra covariates:} any covariate beyond \code{lat_r} / \code{lon_r}
#' is checked for within-site-habitat variance. If values differ within a cell
#' (e.g. depth recorded per occurrence), they are averaged with a warning.
#' Consider summarising to site level before calling this function.
#'
#' @seealso \code{\link{create_sites_from_grid}},
#'   \code{\link{train_biodiversity_model}}
#'
#' @examples
#' \dontrun{
#' model_df <- prepare_model_dataframe(gridded_data,
#'                                     covariates = c("lat_r", "lon_r"),
#'                                     habitat_col = "main_habitat")
#' }
#'
#' @importFrom dplyr rename filter group_by summarise mutate left_join
#'   distinct select ends_with across all_of as_tibble n
#' @importFrom tidyr complete nesting replace_na
#' @importFrom rlang sym :=
#' @importFrom stats cor
#' @export
prepare_model_dataframe <- function(data,
                                    covariates    = c("lat_r", "lon_r"),
                                    habitat_col   = "main_habitat",
                                    cor_threshold = 0.7) {

  # --- Required column check --------------------------------------------------
  required_cols <- c("grid_id", "lat_r", "lon_r", habitat_col, "taxon_name")
  missing_cols  <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0) {
    stop("prepare_model_dataframe: missing required columns: ",
         paste(missing_cols, collapse = ", "))
  }

  missing_covs <- setdiff(covariates, names(data))
  if (length(missing_covs) > 0) {
    stop("prepare_model_dataframe: covariate columns not found in data: ",
         paste(missing_covs, collapse = ", "))
  }

  # --- Multicollinearity check ------------------------------------------------
  if (length(covariates) > 1) {
    cor_matrix <- cor(as.matrix(data[, covariates]), use = "pairwise.complete.obs")
    cor_upper  <- cor_matrix
    cor_upper[lower.tri(cor_upper, diag = TRUE)] <- NA
    high_cor <- which(abs(cor_upper) > cor_threshold, arr.ind = TRUE)
    if (nrow(high_cor) > 0) {
      pairs <- apply(high_cor, 1, function(idx) {
        sprintf("%s and %s (r = %.2f)",
                covariates[idx[1]], covariates[idx[2]],
                cor_upper[idx[1], idx[2]])
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

  # --- Internal rename --------------------------------------------------------
  data <- dplyr::rename(data, .habitat = !!habitat_col)

  # --- Extra covariate handling -----------------------------------------------
  extra_covs <- setdiff(covariates, c("lat_r", "lon_r"))

  if (length(extra_covs) > 0) {
    cov_variance <- dplyr::summarise(
      dplyr::group_by(dplyr::filter(data, !is.na(.habitat)), grid_id, .habitat),
      dplyr::across(dplyr::all_of(extra_covs),
                    ~ length(unique(.x)) > 1,
                    .names = "{.col}_varies"),
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
    site_covs <- dplyr::summarise(
      dplyr::group_by(dplyr::filter(data, !is.na(.habitat)), grid_id, .habitat),
      dplyr::across(dplyr::all_of(extra_covs), \(x) mean(x, na.rm = TRUE)),
      .groups = "drop"
    )
  }

  # --- Site totals and species counts -----------------------------------------
  site_totals <- dplyr::summarise(
    dplyr::group_by(dplyr::filter(data, !is.na(.habitat)),
                    grid_id, lat_r, lon_r, .habitat),
    n_total_at_site = dplyr::n(),
    .groups = "drop"
  )

  model_df <- dplyr::mutate(
    dplyr::left_join(
      tidyr::complete(
        dplyr::summarise(
          dplyr::group_by(dplyr::filter(data, !is.na(.habitat)),
                          grid_id, lat_r, lon_r, .habitat, taxon_name),
          n_species = dplyr::n(),
          .groups = "drop"
        ),
        tidyr::nesting(grid_id, lat_r, lon_r, .habitat),
        taxon_name,
        fill = list(n_species = 0L)
      ),
      site_totals,
      by = c("grid_id", "lat_r", "lon_r", ".habitat")
    ),
    n_other    = n_total_at_site - n_species,
    is_present = as.integer(n_species > 0),
    .habitat   = as.factor(.habitat)
  )

  # --- Join extra covariates --------------------------------------------------
  if (length(extra_covs) > 0) {
    model_df <- dplyr::mutate(
      dplyr::left_join(model_df, site_covs, by = c("grid_id", ".habitat")),
      .habitat = as.factor(.habitat)
    )
  }

  # --- habitat_observed_elsewhere flag ----------------------------------------
  habitat_presence <- dplyr::mutate(
    dplyr::distinct(dplyr::filter(model_df, n_species > 0), taxon_name, .habitat),
    habitat_observed_elsewhere = TRUE
  )
  model_df <- dplyr::mutate(
    dplyr::left_join(model_df, habitat_presence, by = c("taxon_name", ".habitat")),
    habitat_observed_elsewhere = tidyr::replace_na(habitat_observed_elsewhere, FALSE)
  )

  # --- Scale covariates -------------------------------------------------------
  scale_params <- list()
  for (cov in covariates) {
    cov_center          <- mean(model_df[[cov]], na.rm = TRUE)
    cov_scale           <- sd(model_df[[cov]],   na.rm = TRUE)
    if (cov_scale == 0 || !is.finite(cov_scale)) {
      warning(sprintf(
        "Covariate '%s' has zero variance; centering only (no scaling).", cov
      ))
      cov_scale <- 1
    }
    scale_params[[cov]] <- list(center = cov_center, scale = cov_scale)
    new_col             <- paste0(cov, "_s")
    model_df[[new_col]] <- (model_df[[cov]] - cov_center) / cov_scale
  }
  attr(model_df, "scale_params") <- scale_params

  # --- Final column order and return ------------------------------------------
  model_df <- dplyr::select(
    dplyr::rename(model_df, !!habitat_col := .habitat),
    grid_id, lat_r, lon_r, !!habitat_col, taxon_name,
    n_species, n_total_at_site, n_other, is_present,
    habitat_observed_elsewhere,
    dplyr::ends_with("_s"),
    dplyr::everything()
  )

  return(dplyr::as_tibble(model_df))
}
