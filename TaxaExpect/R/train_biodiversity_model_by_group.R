# train_biodiversity_model_by_group.R
# TaxaExpect package
#
# Orchestrates prepare_model_dataframe() + train_biodiversity_model() once per
# sampling group, for broad-marker data spanning multiple detection processes
# (e.g. an 18S survey mixing phytoplankton microscopy counts with vertebrate
# eDNA reads). Added Session 149 -- see the "Shared effort assumption" section
# in prepare_model_dataframe()'s docs for the underlying problem this solves.

#' Train One Biodiversity Model Per Sampling Group
#'
#' Splits raw occurrence data by \code{sampling_group_col} and runs the
#' standard \code{\link{prepare_model_dataframe}} -> \code{\link{train_biodiversity_model}}
#' pipeline independently for each group, so that each group gets its own
#' \code{n_total_at_site} effort denominator, its own covariate scaling, and
#' its own fitted model -- rather than one pooled model treating every group's
#' detection process as equally comparable effort (see the Shared effort
#' assumption section in \code{\link{prepare_model_dataframe}}'s docs).
#'
#' This is the recommended entry point for broad-marker data (e.g. 18S)
#' spanning multiple detection processes. \code{\link{train_biodiversity_model}}
#' itself will refuse to fit a single model against data carrying more than
#' one \code{sampling_group} value, as a safety check -- but that function
#' does not do the splitting/re-scaling for you, which is what this wrapper is
#' for.
#'
#' @param data Raw occurrence data -- the same shape you would otherwise pass
#'   directly to \code{\link{prepare_model_dataframe}} (typically the output
#'   of \code{\link{create_sites_from_grid}} after habitat assignment). Must
#'   contain \code{sampling_group_col} in addition to
#'   \code{\link{prepare_model_dataframe}}'s usual required columns.
#' @param formula A formula object, passed unchanged to
#'   \code{\link{train_biodiversity_model}} for every group. If different
#'   groups need different formulas (e.g. one group has too few sites for a
#'   spatial random slope), call \code{\link{prepare_model_dataframe}} and
#'   \code{\link{train_biodiversity_model}} directly per group instead of
#'   using this wrapper.
#' @param sampling_group_col Character. Name of the column in \code{data}
#'   identifying each record's detection process/sampling method (e.g.
#'   \code{"phytoplankton"} vs. \code{"vertebrate"}). Required -- this
#'   function's whole purpose is per-group modelling, so there is no
#'   \code{NULL} default the way there is for \code{habitat_col}.
#' @param covariates,habitat_col,cor_threshold Passed to
#'   \code{\link{prepare_model_dataframe}} for every group.
#' @param taxon_col,response,min_obs_threshold,effort_threshold,min_positive_rows
#'   Passed to \code{\link{train_biodiversity_model}} for every group.
#' @param verbose Logical. Print per-group progress messages. Default
#'   \code{TRUE}.
#'
#' @return A named list of \code{"biofreq_model"} objects, one per distinct
#'   value of \code{sampling_group_col} that fit successfully, named by that
#'   value. Pass \code{\link{generate_undetected_diversity}} and
#'   \code{\link{generate_full_priors}} once per element, then
#'   \code{dplyr::bind_rows()} the resulting prior tables together before
#'   passing the combined table to \code{TaxaAssign::join_priors()}.
#'
#' @section Groups that fail to fit are dropped, not fatal:
#' Each group's \code{\link{prepare_model_dataframe}} +
#' \code{\link{train_biodiversity_model}} call is wrapped in its own
#' \code{tryCatch()}. A group that errors (e.g. too few records to clear
#' \code{effort_threshold}, or a single remaining habitat level degenerating
#' the habitat fixed effect -- both observed fitting real broad-marker
#' data with very unevenly sized sampling groups) is skipped with a message
#' (when \code{verbose = TRUE}) and a single summary \code{warning()} naming
#' every dropped group, rather than aborting the whole call and losing every
#' other group's result. Check \code{names(models)} against your expected
#' groups if you need to know which ones were dropped.
#'
#' @examples
#' \dontrun{
#' models <- train_biodiversity_model_by_group(
#'   occurrences_gridded,
#'   formula             = cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name),
#'   sampling_group_col  = "sampling_group"
#' )
#'
#' priors_by_group <- lapply(names(models), function(g) {
#'   undet  <- generate_undetected_diversity(models[[g]])
#'   generate_full_priors(models[[g]], new_sites = sites_for_group[[g]], undetected = undet)
#' })
#' priors_combined <- dplyr::bind_rows(priors_by_group)
#' }
#'
#' @seealso \code{\link{prepare_model_dataframe}}, \code{\link{train_biodiversity_model}}
#'
#' @importFrom dplyr n_distinct
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
train_biodiversity_model_by_group <- function(data,
                                              formula,
                                              sampling_group_col,
                                              covariates        = c("lat_r", "lon_r"),
                                              habitat_col       = "main_habitat",
                                              cor_threshold     = 0.7,
                                              taxon_col         = "taxon_name",
                                              response          = c("theta", "psi"),
                                              min_obs_threshold = 5L,
                                              effort_threshold  = 10L,
                                              min_positive_rows = 50L,
                                              verbose           = TRUE) {

  .glmm_deprecation_notice("train_biodiversity_model_by_group")

  response <- match.arg(response)

  if (missing(sampling_group_col) || is.null(sampling_group_col) ||
      length(sampling_group_col) != 1L || !is.character(sampling_group_col)) {
    stop("train_biodiversity_model_by_group: 'sampling_group_col' is required ",
         "(a single column name). For ungrouped data, use train_biodiversity_model() directly.")
  }
  if (!sampling_group_col %in% names(data)) {
    stop("train_biodiversity_model_by_group: sampling_group_col '", sampling_group_col,
         "' not found in data.")
  }

  # sort(unique(x)) silently DROPS NA (sort()'s default na.last = NA removes
  # it), and split(data, data[[col]]) silently drops NA-grouped rows entirely
  # -- both confirmed directly. Keep NA as its own real group instead of
  # dropping it: a row with an unclassified sampling_group_col value should
  # be surfaced as its own group, not silently vanish from every fitted
  # model. Mirrors the equivalent fix in prepare_model_dataframe().
  group_vals <- data[[sampling_group_col]]
  groups     <- sort(unique(group_vals[!is.na(group_vals)]))
  if (anyNA(group_vals)) {
    groups <- c(groups, NA)
    message(sprintf(
      "train_biodiversity_model_by_group: %d row(s) have NA in '%s'; grouped as its own group rather than dropped.",
      sum(is.na(group_vals)), sampling_group_col
    ))
  }
  if (length(groups) < 2L) {
    warning(
      "train_biodiversity_model_by_group: only ", length(groups), " distinct value(s) ",
      "found in '", sampling_group_col, "' -- there is nothing to separate. ",
      "Consider calling prepare_model_dataframe()/train_biodiversity_model() directly.",
      call. = FALSE
    )
  }

  data_splits <- split(data, factor(group_vals, exclude = NULL))

  # Session 149, found via real-data testing (real PtConception 18S
  # occurrences): a single group's fit failing (e.g. a group whose records
  # all share one habitat value, degenerating the habitat fixed effect --
  # "contrasts can be applied only to factors with 2 or more levels") must
  # not take down every other group's result. Wrapped in tryCatch(), mirroring
  # the same guard already used in the real workflow script this function is
  # meant to replace/generalize -- without this, a real multi-group dataset
  # with even one problematic group made this function unusable end to end.
  # Index data_splits by POSITION (via match()), not by name: when g is NA,
  # list[[NA]] returns NULL rather than the actual NA-named element (the
  # same list-indexing footgun already documented and fixed elsewhere in
  # this package, e.g. compute_adaptive_sampling_groups.R) -- a by-name
  # lookup would silently treat the NA group's data as empty.
  models <- stats::setNames(lapply(groups, function(g) {
    split_data <- data_splits[[match(g, names(data_splits))]]
    if (verbose) message(sprintf("--- Sampling group '%s' (%d record(s)) ---",
                                  g, nrow(split_data)))

    tryCatch({
      model_df <- prepare_model_dataframe(
        split_data,
        covariates    = covariates,
        habitat_col   = habitat_col,
        cor_threshold = cor_threshold
      )

      train_biodiversity_model(
        model_df,
        formula           = formula,
        taxon_col         = taxon_col,
        habitat_col       = habitat_col,
        response          = response,
        min_obs_threshold = min_obs_threshold,
        effort_threshold  = effort_threshold,
        min_positive_rows = min_positive_rows,
        full_data         = split_data
      )
    }, error = function(e) {
      if (verbose) message(sprintf("  Group '%s' failed to fit: %s", g, conditionMessage(e)))
      NULL
    })
  }), groups)

  n_failed <- sum(vapply(models, is.null, logical(1)))
  if (n_failed > 0L) {
    warning(sprintf(
      "train_biodiversity_model_by_group: %d of %d group(s) failed to fit and were dropped: %s",
      n_failed, length(models), paste(names(models)[vapply(models, is.null, logical(1))], collapse = ", ")
    ), call. = FALSE)
  }
  models <- models[!vapply(models, is.null, logical(1))]

  models
}
