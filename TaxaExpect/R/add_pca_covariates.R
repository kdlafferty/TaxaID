#' Reduce Correlated Covariates via PCA Before Biodiversity Modeling
#'
#' @description
#' Replaces scaled covariate columns (`<cov>_s`) that exceed a pairwise
#' correlation threshold with orthogonal PCA scores.  Use this when
#' [prepare_model_dataframe()] warns about multicollinearity.
#'
#' The output has the same structure as [prepare_model_dataframe()] output and
#' can be passed directly to [train_biodiversity_model()].
#'
#' @param model_df A data frame, typically the output of
#'   [prepare_model_dataframe()].  Must contain at least two columns ending in
#'   `"_s"` (scaled covariates produced by `prepare_model_dataframe()`).
#' @param cor_threshold Numeric scalar.  Pairs of `_s` columns with
#'   `|r| > cor_threshold` are replaced by PCA scores.  Default `0.7` matches
#'   the threshold used in [prepare_model_dataframe()].
#' @param prefix Character scalar.  Prefix for the new PC column names.
#'   Default `"PC"`.  PC columns are named `<prefix>1_s`, `<prefix>2_s`, etc.
#'
#' @return The input data frame with correlated `_s` columns replaced by PC
#'   score columns (`<prefix>N_s`).  Two attributes are set:
#'   \describe{
#'     \item{`scale_params`}{Preserved unchanged from `model_df` (original
#'       covariate scaling parameters; retained for new-site prediction via
#'       [apply_pca_transform()]).}
#'     \item{`pca_rotation`}{Named list:
#'       `source_cols` (replaced `_s` column names),
#'       `pc_cols` (new PC column names),
#'       `rotation` (PCA loading matrix, n_source × n_pc),
#'       `prefix` (the prefix used).}
#'   }
#'   If no column pairs exceed `cor_threshold` the input is returned unchanged.
#'
#' @details
#' PCA is applied to all `_s` columns involved in any correlated pair;
#' uncorrelated `_s` columns are left in place.  All principal components are
#' retained — the output columns are orthogonal by construction, which
#' eliminates collinearity without discarding variance.
#'
#' `prcomp()` is called with `center = TRUE` so PC scores are zero-mean and
#' exactly orthogonal.  The `_s` columns are already ≈ 0-mean from
#' `prepare_model_dataframe()`; re-centering has negligible effect on values.
#'
#' **Prediction-time note:** [generate_full_priors()] scales new sites using the
#' original `scale_params` entries.  When a model was trained with PCA
#' covariates, call [apply_pca_transform()] on the scaled new-site data before
#' passing it to [generate_full_priors()].
#'
#' @seealso [prepare_model_dataframe()], [apply_pca_transform()],
#'   [train_biodiversity_model()]
#'
#' @examples
#' \dontrun{
#' model_df     <- prepare_model_dataframe(gridded_data,
#'                   covariates = c("lat_r", "lon_r", "depth"))
#' model_df_pca <- add_pca_covariates(model_df)
#' model_obj    <- train_biodiversity_model(
#'                   model_df_pca,
#'                   formula = cbind(n_species, n_other) ~
#'                     main_habitat + (1 | taxon_name) + (0 + PC1_s | taxon_name))
#' }
#'
#' @importFrom dplyr bind_cols as_tibble
#' @importFrom stats cor prcomp
#' @export
add_pca_covariates <- function(model_df,
                                cor_threshold = 0.7,
                                prefix        = "PC") {

  if (!is.data.frame(model_df))
    stop("model_df must be a data frame")
  if (!is.numeric(cor_threshold) || length(cor_threshold) != 1L ||
      is.na(cor_threshold) || cor_threshold <= 0 || cor_threshold >= 1)
    stop("cor_threshold must be a numeric scalar strictly between 0 and 1")
  if (!is.character(prefix) || length(prefix) != 1L || !nzchar(trimws(prefix)))
    stop("prefix must be a non-empty character scalar")

  # ---- Identify scaled covariate columns (_s suffix) -----------------------
  s_cols <- grep("_s$", names(model_df), value = TRUE)

  if (length(s_cols) < 2L) {
    message("add_pca_covariates: fewer than 2 scaled covariate columns (_s suffix); ",
            "returning unchanged.")
    return(model_df)
  }

  # ---- Correlation check among _s columns ----------------------------------
  cor_mat   <- stats::cor(as.matrix(model_df[, s_cols, drop = FALSE]),
                           use = "pairwise.complete.obs")
  cor_upper <- cor_mat
  cor_upper[lower.tri(cor_upper, diag = TRUE)] <- NA
  high_cor  <- which(abs(cor_upper) > cor_threshold, arr.ind = TRUE)

  if (nrow(high_cor) == 0L) {
    message(sprintf(
      "add_pca_covariates: no _s column pairs exceed |r| = %.2f; returning unchanged.",
      cor_threshold
    ))
    return(model_df)
  }

  # ---- Identify all involved columns ---------------------------------------
  involved <- unique(c(s_cols[high_cor[, 1L]], s_cols[high_cor[, 2L]]))

  pairs_msg <- apply(high_cor, 1L, function(idx) {
    sprintf("%s & %s (r = %.2f)",
            s_cols[idx[1L]], s_cols[idx[2L]], cor_upper[idx[1L], idx[2L]])
  })
  message(sprintf(
    "add_pca_covariates: replacing %d correlated column(s) with PCA scores (%s).",
    length(involved), paste(pairs_msg, collapse = "; ")
  ))

  # ---- PCA on involved columns ---------------------------------------------
  # Use center = TRUE (default) so PC scores are zero-mean and exactly
  # orthogonal. The _s columns are already ~0-mean from prepare_model_dataframe();
  # re-centering has negligible effect on values but guarantees orthogonality.
  pca_mat <- as.matrix(model_df[, involved, drop = FALSE])
  pca_fit <- stats::prcomp(pca_mat, center = TRUE, scale. = FALSE)

  n_pc    <- ncol(pca_fit$rotation)
  pc_cols <- paste0(prefix, seq_len(n_pc), "_s")

  # Guard against name collisions with columns we are keeping
  keep_names <- setdiff(names(model_df), involved)
  collisions <- intersect(pc_cols, keep_names)
  if (length(collisions) > 0L)
    stop(sprintf(
      "add_pca_covariates: PC column name(s) collide with existing columns: %s. Change 'prefix'.",
      paste(collisions, collapse = ", ")
    ))

  # ---- Build output data frame ---------------------------------------------
  out       <- model_df[, keep_names, drop = FALSE]
  pc_scores <- as.data.frame(pca_fit$x, stringsAsFactors = FALSE)
  names(pc_scores) <- pc_cols
  out <- dplyr::bind_cols(out, pc_scores)

  # ---- Preserve / update attributes ----------------------------------------
  # Keep scale_params unchanged: original covariate entries are needed when
  # generate_full_priors() scales raw new-site data before apply_pca_transform().
  attr(out, "scale_params") <- attr(model_df, "scale_params")
  attr(out, "pca_rotation") <- list(
    source_cols = involved,
    pc_cols     = pc_cols,
    rotation    = pca_fit$rotation,
    center      = pca_fit$center,   # per-column means used during prcomp
    prefix      = prefix
  )

  dplyr::as_tibble(out)
}


#' Apply a Stored PCA Transformation to New Sites
#'
#' @description
#' Applies the PCA rotation produced by [add_pca_covariates()] to a new-sites
#' data frame that already has the source `_s` columns (e.g., produced by
#' [generate_full_priors()]'s internal scaling step).
#'
#' Use this as a pre-processing step before [generate_full_priors()] when the
#' training model used PCA-transformed covariates.
#'
#' @param new_sites A data frame containing the `_s` columns listed in
#'   `pca_rotation$source_cols` (e.g., `lat_r_s`, `lon_r_s`).
#' @param pca_rotation The `pca_rotation` attribute from the output of
#'   [add_pca_covariates()], or the `$pca_rotation` slot of the fitted model
#'   object returned by [train_biodiversity_model()].
#'
#' @return `new_sites` with the source `_s` columns replaced by the PC score
#'   columns.
#'
#' @seealso [add_pca_covariates()], [generate_full_priors()]
#'
#' @examples
#' \dontrun{
#' # Typical workflow when model was trained with PCA covariates:
#' pca_rot       <- attr(model_df_pca, "pca_rotation")
#' new_sites_pca <- apply_pca_transform(new_sites_scaled, pca_rot)
#' priors        <- generate_full_priors(model_obj, new_sites_pca)
#' }
#'
#' @importFrom dplyr bind_cols
#' @export
apply_pca_transform <- function(new_sites, pca_rotation) {

  if (!is.data.frame(new_sites))
    stop("new_sites must be a data frame")
  if (!is.list(pca_rotation) ||
      !all(c("source_cols", "pc_cols", "rotation") %in% names(pca_rotation)))
    stop("pca_rotation must be a list with elements 'source_cols', 'pc_cols', 'rotation'")

  missing_src <- setdiff(pca_rotation$source_cols, names(new_sites))
  if (length(missing_src) > 0L)
    stop(sprintf(
      "apply_pca_transform: source columns not found in new_sites: %s",
      paste(missing_src, collapse = ", ")
    ))

  src_mat <- as.matrix(new_sites[, pca_rotation$source_cols, drop = FALSE])
  # Subtract training center (matches prcomp(center = TRUE) projection)
  if (!is.null(pca_rotation$center)) {
    src_mat <- sweep(src_mat, 2L, pca_rotation$center, "-")
  }
  pc_scores <- as.data.frame(src_mat %*% pca_rotation$rotation,
                              stringsAsFactors = FALSE)
  names(pc_scores) <- pca_rotation$pc_cols

  keep <- setdiff(names(new_sites), pca_rotation$source_cols)
  dplyr::bind_cols(new_sites[, keep, drop = FALSE], pc_scores)
}
