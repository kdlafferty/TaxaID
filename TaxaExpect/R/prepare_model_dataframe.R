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
#'   \item Computes the \code{observed_in_habitat} flag — \code{TRUE}
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
#'   The attribute \code{scale_params} is a named list — one entry per
#'   covariate — each containing \code{center} (mean) and \code{scale} (SD).
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
#' \code{train_biodiversity_model()} calls -- as of Session 149 this is no
#' longer purely a documentation-only recommendation: see
#' \code{sampling_group_col} below and \code{\link{train_biodiversity_model_by_group}}.
#'
#' @section Group-aware effort denominators (\code{sampling_group_col}, Session 149):
#' When supplied, \code{n_total_at_site} is computed \emph{within} each
#' \code{sampling_group_col} value at a site, instead of pooling every taxon
#' together -- this is the code-level fix for the Shared effort assumption
#' above, confirmed (2026-07-10) to have been previously documented only as
#' advisory prose, never enforced anywhere, including in the one real
#' production workflow (PtConception 18S) that actually mixes phytoplankton
#' counts with vertebrate counts. Internally, \code{data} is split by
#' \code{sampling_group_col} and this function's existing aggregation logic is
#' applied to each split independently (never a shared \code{tidyr::complete()}
#' cross-join across groups, which would itself reintroduce cross-group
#' contamination), then the results are combined with a \code{sampling_group}
#' column identifying each row's group. Pass the result to
#' \code{\link{train_biodiversity_model_by_group}} to fit one model per group
#' rather than one pooled model across all of them --
#' \code{\link{train_biodiversity_model}} itself will refuse to fit a single
#' model against multi-group data (see its own docs) as a safety check.
#' Default \code{NULL}: no grouping, output and behavior unchanged from before
#' Session 149.
#'
#' @seealso \code{\link{create_sites_from_grid}},
#'   \code{\link{train_biodiversity_model}},
#'   \code{\link{train_biodiversity_model_by_group}}
#'
#' @examples
#' \dontrun{
#' model_df <- prepare_model_dataframe(gridded_data,
#'                                     covariates = c("lat_r", "lon_r"),
#'                                     habitat_col = "main_habitat")
#'
#' # Group-aware effort denominators for a broad marker mixing detection
#' # processes (e.g. 18S phytoplankton + vertebrate counts):
#' model_df_grouped <- prepare_model_dataframe(
#'   gridded_data,
#'   habitat_col        = "main_habitat",
#'   sampling_group_col = "sampling_group"
#' )
#' }
#'
#' @importFrom dplyr rename filter group_by summarise mutate left_join
#'   distinct select ends_with across all_of as_tibble n bind_rows
#' @importFrom tidyr complete nesting replace_na
#' @importFrom rlang sym :=
#' @importFrom stats cor
#' @export
prepare_model_dataframe <- function(data,
                                    covariates    = c("lat_r", "lon_r"),
                                    habitat_col   = "main_habitat",
                                    cor_threshold = 0.7,
                                    sampling_group_col = NULL) {

  # --- Required column check --------------------------------------------------
  # habitat_col = NULL means "no habitat modeling" -- the caller has no habitat
  # column to supply and none is required. See @details.
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

  if (!is.null(sampling_group_col) && !sampling_group_col %in% names(data)) {
    stop("prepare_model_dataframe: sampling_group_col '", sampling_group_col,
         "' not found in data.")
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

  # --- Per-group processing (Session 149) -------------------------------------
  # sampling_group_col: rather than teach tidyr::complete()'s zero-filling to
  # respect group boundaries within one combined aggregation (fragile -- a
  # shared complete() call risks re-introducing cross-group zero-fill
  # contamination), split data by group and run the existing, already-tested
  # single-group aggregation logic (below) on each split independently, then
  # recombine. This guarantees n_total_at_site is never pooled across groups.
  .run_one_group <- function(data) {

  # --- Internal rename --------------------------------------------------------
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

  # --- observed_in_habitat flag ----------------------------------------
  habitat_presence <- dplyr::mutate(
    dplyr::distinct(dplyr::filter(model_df, n_species > 0), taxon_name, .habitat),
    observed_in_habitat = TRUE
  )
  model_df <- dplyr::mutate(
    dplyr::left_join(model_df, habitat_presence, by = c("taxon_name", ".habitat")),
    observed_in_habitat = tidyr::replace_na(observed_in_habitat, FALSE)
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
  if (no_habitat) {
    # Drop the internal placeholder entirely -- no habitat column in output.
    model_df <- dplyr::select(
      dplyr::select(model_df, -.habitat),
      grid_id, lat_r, lon_r, taxon_name,
      n_species, n_total_at_site, n_other, is_present,
      observed_in_habitat,
      dplyr::ends_with("_s"),
      dplyr::everything()
    )
  } else {
    model_df <- dplyr::select(
      dplyr::rename(model_df, !!habitat_col := .habitat),
      grid_id, lat_r, lon_r, !!habitat_col, taxon_name,
      n_species, n_total_at_site, n_other, is_present,
      observed_in_habitat,
      dplyr::ends_with("_s"),
      dplyr::everything()
    )
  }

  dplyr::as_tibble(model_df)
  } # end .run_one_group

  if (is.null(sampling_group_col)) {
    return(.run_one_group(data))
  }

  # --- Split by sampling group and recombine (Session 149) --------------------
  group_splits <- split(data, data[[sampling_group_col]])
  grouped_out  <- lapply(names(group_splits), function(g) {
    out <- .run_one_group(group_splits[[g]])
    out$sampling_group <- g
    out
  })
  dplyr::bind_rows(grouped_out)
}
