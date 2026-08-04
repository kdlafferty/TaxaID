# screen_spatial_formula.R
# Fits a full spatial formula, screens random slope terms by SD, then runs
# a small targeted AIC comparison to suggest a parsimonious formula.
#
# Renaming log:
#   (new function -- Session 12, 2026-03-03)
#   (moved TaxaHabitat -> TaxaExpect, Session 29, 2026-03-27)

#' Screen spatial random slope terms and select a parsimonious formula
#'
#' Fits a full biodiversity model containing Moran eigenvector terms and
#' spatial gradient slopes, then uses a two-stage procedure to identify a
#' simpler formula: (1) a VarCorr pre-screen flags random slope terms with
#' near-zero standard deviations, and (2) a small targeted set of candidate
#' models is compared by AIC. The most parsimonious model within
#' \code{delta_aic_max} units of the best AIC is returned.
#'
#' @param data Data frame. Output of \code{\link{prepare_model_dataframe}} with
#'   Moran basis columns (B1 ... BK) already joined via
#'   \code{\link{compute_moran_basis}}.
#' @param formula_full Formula. The full starting formula, including all
#'   Moran eigenvector terms and spatial/covariate gradient terms. Moran
#'   columns must be named \code{B1}, \code{B2}, .... Gradient covariate
#'   columns (\code{lat_r_s}, \code{lon_r_s}, and any additional covariate
#'   passed to \code{\link{prepare_model_dataframe}}'s \code{covariates}
#'   argument, e.g. \code{depth_m_s}) are auto-detected from \code{data}'s
#'   own \code{scale_params} attribute (set by \code{prepare_model_dataframe}),
#'   so any covariate beyond the original two is screened identically --
#'   not just carried through unscreened. Falls back to
#'   \code{c("lat_r_s", "lon_r_s")} only if \code{data} has no
#'   \code{scale_params} attribute (e.g. hand-built data in older code/tests).
#' @param sd_threshold Numeric. Absolute logit-scale standard deviation
#'   threshold for spatial predictor screening (compared directly against
#'   each random slope's own fitted SD -- not a coefficient of variation;
#'   the code never divides by a mean). Predictors with an SD below this
#'   value show insufficient spatial variation to meaningfully explain
#'   species distributions. Default 0.20 -- a pragmatic minimum for
#'   ecological spatial predictors on the logit scale. Terms at or above
#'   this threshold are never removed.
#' @param delta_aic_max Numeric. Maximum delta-AIC for retaining a spatial
#'   predictor. Following Burnham & Anderson (2002), models within
#'   delta-AIC < 2 of the best model have substantial empirical support.
#'   If a simpler candidate is within \code{delta_aic_max} AIC units of
#'   the best model, it is preferred over the more complex model.
#'   Default 2.0.
#' @param verbose Logical. If TRUE (default), prints the VarCorr screen table,
#'   the AIC comparison table, and the recommendation.
#' @param ... Additional arguments passed to \code{\link{train_biodiversity_model}}
#'   (e.g. \code{min_obs_threshold}, \code{effort_threshold},
#'   \code{min_positive_rows}).
#'
#' @return A \code{biofreq_model} object (the recommended model) with an
#'   additional element \code{$model_selection}, a list containing:
#'   \describe{
#'     \item{aic_table}{Data frame with columns \code{model}, \code{AIC},
#'       \code{delta_AIC}, \code{n_var_params}, \code{recommended}.}
#'     \item{recommended_formula}{Character. The Tier 1 formula of the
#'       recommended model.}
#'     \item{flagged_terms}{Character vector of terms flagged by VarCorr
#'       screen.}
#'     \item{sd_table}{Data frame of all screened terms and their SDs.}
#'   }
#'
#' @details
#' **Tier 1:** "Tier 1" refers to the species tier assigned by
#' \code{\link{train_biodiversity_model}} -- species with enough detections
#' (\code{>= min_obs_threshold}) to fit the full, species-specific formula
#' being screened here. Every fit and comparison in this function operates on
#' the Tier 1 model only; Tier 2 (sparse species, intercept-only) is
#' untouched and always uses the same simplified formula regardless of what
#' this function recommends. See \code{\link{train_biodiversity_model}}'s own
#' documentation for the full tier definition.
#'
#' **Candidate models fitted:**
#' \enumerate{
#'   \item Full model (always -- reuses the first fit, no refitting).
#'   \item Flagged Moran dropped, spatial slopes kept.
#'   \item All flagged terms dropped (Moran + any flagged spatial slopes).
#'   \item Baseline: no Moran terms, spatial slopes only (always included
#'     as an anchor even if nothing is flagged).
#' }
#'
#' Candidates that would be identical to another candidate (e.g. if no Moran
#' terms are flagged, candidate 2 = candidate 1) are silently deduplicated.
#'
#' **Parsimony rule:** Among all candidates within \code{delta_aic_max} of
#' the best AIC, the model with the fewest parameters is returned. This
#' implements the standard ecological convention that a more complex model
#' must show a meaningful improvement to justify its extra parameters.
#'
#' **Caveat:** Candidates are informed by the full-model VarCorr estimates,
#' so this procedure is model \emph{simplification}, not independent
#' validation. Spatial block cross-validation should be used to evaluate
#' predictive accuracy.
#'
#' @seealso \code{\link{train_biodiversity_model}},
#'   \code{\link{compute_moran_basis}}
#'
#' @examples
#' \dontrun{
#' spatial_result <- screen_spatial_formula(
#'   data = model_df,
#'   formula_full = presence ~ lat_r + lon_r + (1 | species)
#' )
#' spatial_result$recommendation
#' }
#'
#' @importFrom stats AIC logLik as.formula
#' @importFrom glmmTMB VarCorr
#'
#' @export
screen_spatial_formula <- function(data,
                                   formula_full,
                                   sd_threshold  = 0.20,
                                   delta_aic_max = 2.0,
                                   verbose       = TRUE,
                                   ...) {

  # Capture ... and strip any arguments that belong to screen_spatial_formula
  # only (verbose, sd_threshold, delta_aic_max). If users call via do.call()
  # with a flat argument list, those names will already have been matched to
  # the explicit parameters above; this guard handles the edge case where they
  # are duplicated or passed by position into ....
  ssf_only <- c("verbose", "sd_threshold", "delta_aic_max")
  dot_args  <- list(...)
  tbm_args  <- dot_args[!names(dot_args) %in% ssf_only]

  # ---------------------------------------------------------------------------
  # Input checks
  # ---------------------------------------------------------------------------
  if (!inherits(formula_full, "formula")) {
    stop("screen_spatial_formula: 'formula_full' must be a formula object.")
  }
  if (!requireNamespace("glmmTMB", quietly = TRUE)) {
    stop("screen_spatial_formula: package 'glmmTMB' is required.")
  }
  if (!is.numeric(sd_threshold) || sd_threshold <= 0) {
    stop("screen_spatial_formula: 'sd_threshold' must be a positive number.")
  }
  if (!is.numeric(delta_aic_max) || delta_aic_max < 0) {
    stop("screen_spatial_formula: 'delta_aic_max' must be a non-negative number.")
  }

  # ---------------------------------------------------------------------------
  # Detect Moran and spatial terms present in the formula
  # ---------------------------------------------------------------------------
  formula_chr  <- paste(deparse(formula_full, width.cutoff = 500), collapse = " ")
  all_vars     <- all.vars(formula_full)

  moran_terms <- sort(grep("^B[0-9]+$", all_vars, value = TRUE))

  # Gradient covariate names come from prepare_model_dataframe()'s own
  # scale_params attribute (one entry per covariate it scaled, keyed by the
  # RAW covariate name -- "lat_r", "lon_r", "depth_m", etc. -- so the
  # formula's actual "_s"-suffixed slope term is scale_params name + "_s").
  # This generalizes screening to ANY covariate passed to that function's
  # covariates= argument, not just the original lat_r_s/lon_r_s pair --
  # confirmed the attribute survives a left_join() with a Moran basis (the
  # real GreatLakes2023_ConsensusWorkflow.R usage), so this is reliable in
  # practice, not just in isolation. Falls back to the original hardcoded
  # pair when the attribute is absent (data not produced by
  # prepare_model_dataframe(), e.g. hand-built in older code/tests).
  scaled_covariates <- names(attr(data, "scale_params"))
  spatial_terms <- if (!is.null(scaled_covariates)) {
    intersect(paste0(scaled_covariates, "_s"), all_vars)
  } else {
    intersect(c("lat_r_s", "lon_r_s"), all_vars)
  }

  if (length(moran_terms) == 0L && length(spatial_terms) == 0L) {
    message("screen_spatial_formula: formula contains no screenable spatial terms ",
            "(Moran B1..BK or scaled covariates from prepare_model_dataframe(), ",
            "e.g. lat_r_s/lon_r_s). Fitting formula as-is and returning.")
    model_out <- do.call(
      train_biodiversity_model,
      c(list(data = data, formula = formula_full), tbm_args)
    )
    model_out$model_selection <- list(
      aic_table           = NULL,
      recommended_formula = paste(deparse(formula_full, width.cutoff = 500), collapse = " "),
      flagged_terms       = character(0),
      sd_table            = data.frame(term = character(0), sd = numeric(0),
                                       flagged = logical(0), stringsAsFactors = FALSE)
    )
    return(model_out)
  }

  # Validate that Moran columns exist in data; strip any that are absent
  # (can happen with small datasets where compute_moran_basis() returns fewer
  # than k eigenvectors and the formula references the original k).
  missing_moran <- setdiff(moran_terms, names(data))
  if (length(missing_moran) > 0L) {
    message(sprintf(
      "screen_spatial_formula: %d Moran column(s) absent from data (%s); stripping from formula.",
      length(missing_moran), paste(missing_moran, collapse = ", ")))
    formula_chr_adj <- paste(deparse(formula_full, width.cutoff = 500), collapse = " ")
    for (v in missing_moran) {
      formula_chr_adj <- gsub(
        paste0("\\s*\\+\\s*\\(0 \\+ ", v, " \\|[^)]+\\)"),
        "", formula_chr_adj
      )
    }
    formula_full  <- stats::as.formula(formula_chr_adj)
    formula_chr   <- paste(deparse(formula_full, width.cutoff = 500), collapse = " ")
    moran_terms <- setdiff(moran_terms, missing_moran)
    # After stripping, re-check if any spatial terms remain
    if (length(moran_terms) == 0L && length(spatial_terms) == 0L) {
      message("screen_spatial_formula: no spatial terms remain after stripping absent Moran ",
              "columns. Fitting formula as-is and returning.")
      model_out <- do.call(
        train_biodiversity_model,
        c(list(data = data, formula = formula_full), tbm_args)
      )
      model_out$model_selection <- list(
        aic_table           = NULL,
        recommended_formula = formula_chr,
        flagged_terms       = character(0),
        sd_table            = data.frame(term = character(0), sd = numeric(0),
                                         flagged = logical(0), stringsAsFactors = FALSE)
      )
      return(model_out)
    }
  }

  # ---------------------------------------------------------------------------
  # Step 1: Fit full model
  # ---------------------------------------------------------------------------
  if (verbose) message("\n--- screen_spatial_formula: fitting full model ---")

  model_full <- do.call(
    train_biodiversity_model,
    c(list(data = data, formula = formula_full), tbm_args)
  )

  # No Tier 1 model exists when zero species meet min_obs_threshold (every
  # species falls to Tier 2/empirical) -- train_biodiversity_model() leaves
  # $models$tier1 as NULL in that case by design (see its own Tier 2 fallback
  # docs), but VarCorr()/AIC()/logLik() below all assume a fitted Tier 1
  # model exists to screen. Nothing to screen or compare in that case --
  # return the fitted model as-is, same "nothing to do" pattern already used
  # above for formulas with no screenable spatial terms.
  if (is.null(model_full$models$tier1)) {
    message("screen_spatial_formula: 0 Tier 1 species (none met min_obs_threshold) ",
            "-- nothing to VarCorr-screen or AIC-compare. Returning the fitted model ",
            "as-is; all species fall back to Tier 2 or empirical means. Consider ",
            "lowering min_obs_threshold if this is unexpected for your dataset.")
    model_full$model_selection <- list(
      aic_table           = NULL,
      recommended_formula = model_full$meta$formula_tier1,
      flagged_terms       = character(0),
      sd_table            = data.frame(term = character(0), sd = numeric(0),
                                       flagged = logical(0), stringsAsFactors = FALSE)
    )
    return(model_full)
  }

  # ---------------------------------------------------------------------------
  # Step 2: VarCorr pre-screen
  # ---------------------------------------------------------------------------
  vc_raw <- glmmTMB::VarCorr(model_full$models$tier1)
  vc_cond <- vc_raw$cond   # named list of variance-covariance matrices

  # glmmTMB VarCorr returns a named list of matrices (one per grouping factor).
  # Each matrix has rownames = random effect variable names.
  # as.data.frame() on this object does not reliably produce var1/sdcor columns
  # across glmmTMB versions, so we extract directly from the list.
  sd_rows <- lapply(names(vc_cond), function(grp) {
    mat  <- vc_cond[[grp]]
    vars <- rownames(mat)
    sds  <- sqrt(diag(as.matrix(mat)))
    data.frame(group = grp, term = vars, sd = sds,
               stringsAsFactors = FALSE, row.names = NULL)
  })
  sd_tbl <- do.call(rbind, sd_rows)

  # Keep only the spatial slope terms we care about screening (Moran basis +
  # whatever gradient covariates were detected above -- not a hardcoded
  # name list, so a new covariate is screened the same way lat_r_s/lon_r_s
  # always were, instead of silently passing through unscreened).
  sd_tbl <- sd_tbl[sd_tbl$term %in% c(moran_terms, spatial_terms),
                   c("term", "sd"), drop = FALSE]
  sd_tbl$flagged <- sd_tbl$sd < sd_threshold
  sd_tbl <- sd_tbl[order(sd_tbl$sd), ]
  rownames(sd_tbl) <- NULL

  flagged_moran   <- sd_tbl$term[sd_tbl$flagged & sd_tbl$term %in% moran_terms]
  flagged_spatial <- sd_tbl$term[sd_tbl$flagged & sd_tbl$term %in% spatial_terms]
  keep_moran      <- setdiff(moran_terms,   flagged_moran)
  keep_spatial    <- setdiff(spatial_terms, flagged_spatial)

  if (verbose) {
    cat(sprintf(
      "\n--- VarCorr screen (SD threshold = %.2f) ---\n", sd_threshold))
    print(sd_tbl, row.names = FALSE)
    cat(sprintf("  Flagged Moran:   %s\n",
                if (length(flagged_moran)   == 0L) "none"
                else paste(flagged_moran,   collapse = ", ")))
    cat(sprintf("  Flagged spatial: %s\n",
                if (length(flagged_spatial) == 0L) "none"
                else paste(flagged_spatial, collapse = ", ")))
  }

  # ---------------------------------------------------------------------------
  # Step 3: Build candidate formula set
  # ---------------------------------------------------------------------------
  f_full_chr <- paste(deparse(formula_full, width.cutoff = 500), collapse = " ")

  all_screened_vars <- c(moran_terms, spatial_terms)

  # Remove screened random slopes: (0 + <var> | <group>)
  for (v in all_screened_vars) {
    f_full_chr <- gsub(
      paste0("\\s*\\+\\s*\\(0 \\+ ", v, " \\|[^)]+\\)"),
      "", f_full_chr
    )
  }

  # Remove grid RE: (1 | <word>:<word>)
  f_full_chr <- gsub(
    "\\s*\\+\\s*\\(1 \\| [A-Za-z_.][A-Za-z0-9_.]*:[A-Za-z_.][A-Za-z0-9_.]*\\)",
    "", f_full_chr
  )

  lhs_fixed <- trimws(f_full_chr)
  grid_re   <- "(1 | taxon_name:grid_id)"

  .build_formula <- function(moran_keep, spatial_keep) {
    slope_terms <- c(
      if (length(moran_keep)   > 0L) paste0("(0 + ", moran_keep,   " | taxon_name)"),
      if (length(spatial_keep) > 0L) paste0("(0 + ", spatial_keep, " | taxon_name)"),
      grid_re
    )
    stats::as.formula(
      paste(lhs_fixed, paste(slope_terms, collapse = " + "), sep = " + ")
    )
  }

  candidates <- list()

  # Baseline: no Moran, full spatial slopes (always included as anchor)
  f_base     <- .build_formula(character(0), spatial_terms)
  f_base_chr <- paste(deparse(f_base, width.cutoff = 500), collapse = " ")
  candidates[["baseline"]] <- list(
    label   = "Baseline (no Moran, lat/lon only)",
    formula = f_base,
    model   = NULL
  )

  # Full model -- already fitted; add as separate candidate unless it IS the baseline
  f_full_cand_chr <- paste(deparse(formula_full, width.cutoff = 500), collapse = " ")
  if (f_full_cand_chr != f_base_chr) {
    candidates[["full"]] <- list(
      label   = sprintf("Full (%s + lat/lon)",
                        if (length(moran_terms) > 0L)
                          paste(moran_terms, collapse = "+") else "no Moran"),
      formula = formula_full,
      model   = model_full
    )
  } else {
    candidates[["baseline"]]$model <- model_full
  }

  # Drop flagged Moran, keep all spatial
  if (length(flagged_moran) > 0L) {
    f <- .build_formula(keep_moran, spatial_terms)
    f_chr <- paste(deparse(f, width.cutoff = 500), collapse = " ")
    if (!.formula_in_candidates(f_chr, candidates)) {
      lbl <- if (length(keep_moran) == 0L)
        "No Moran + lat/lon"
      else
        sprintf("Keep %s, drop %s",
                paste(keep_moran, collapse = "+"),
                paste(flagged_moran, collapse = "+"))
      candidates[["drop_moran"]] <- list(label = lbl, formula = f, model = NULL)
    }
  }

  # Drop all flagged terms
  if (length(c(flagged_moran, flagged_spatial)) > 0L) {
    f <- .build_formula(keep_moran, keep_spatial)
    f_chr <- paste(deparse(f, width.cutoff = 500), collapse = " ")
    if (!.formula_in_candidates(f_chr, candidates)) {
      dropped <- paste(c(flagged_moran, flagged_spatial), collapse = "+")
      candidates[["drop_all"]] <- list(
        label   = sprintf("Drop all flagged (%s)", dropped),
        formula = f,
        model   = NULL
      )
    }
  }

  # ---------------------------------------------------------------------------
  # Step 4: Fit candidates that need fitting
  # ---------------------------------------------------------------------------
  if (verbose) message("\n  Fitting ", sum(sapply(candidates, function(x) is.null(x$model))),
                       " candidate model(s)...")

  for (nm in names(candidates)) {
    if (is.null(candidates[[nm]]$model)) {
      candidates[[nm]]$model <- do.call(
        train_biodiversity_model,
        c(list(data = data, formula = candidates[[nm]]$formula), tbm_args)
      )
    }
  }

  # ---------------------------------------------------------------------------
  # Step 5: AIC comparison table
  # ---------------------------------------------------------------------------
  aic_vals  <- sapply(candidates, function(x) stats::AIC(x$model$models$tier1))
  n_var_par <- sapply(candidates, function(x) {
    attr(stats::logLik(x$model$models$tier1), "df")
  })
  labels    <- sapply(candidates, function(x) x$label)

  # Flag NA-AIC models (convergence failure) before comparison
  na_aic <- is.na(aic_vals)
  if (any(na_aic)) {
    message(sprintf(
      "  Note: %d candidate(s) have NA AIC (convergence failure): %s",
      sum(na_aic), paste(labels[na_aic], collapse = "; ")))
  }

  aic_table <- data.frame(
    model        = labels,
    AIC          = round(aic_vals, 1),
    delta_AIC    = NA_real_,
    n_var_params = n_var_par,
    row.names    = NULL,
    stringsAsFactors = FALSE
  )

  # Compute delta_AIC only over valid models
  valid_aic <- aic_vals[!na_aic]
  if (length(valid_aic) == 0L) {
    # Print convergence warnings from every candidate before stopping,
    # since the function cannot return $convergence_warnings on error.
    all_warns <- unlist(lapply(names(candidates), function(nm) {
      w <- candidates[[nm]]$model$convergence_warnings
      if (length(w)) paste0("[", candidates[[nm]]$label, "] ", w) else character(0)
    }))
    if (length(all_warns)) {
      message("  Convergence warnings from all candidates:")
      for (w in all_warns) message("    ", w)
    }
    stop(
      "screen_spatial_formula: AIC is NA for all candidate models ",
      "(glmmTMB convergence failure).\n",
      "  Possible causes and remedies:\n",
      "  1. Too many random-slope terms for the dataset size. Try removing\n",
      "     spatial covariates (lat_r_s, lon_r_s) and using only the Moran\n",
      "     basis (B1..Bk), or drop Moran terms entirely.\n",
      "  2. Multicollinearity between scaled covariates. Run\n",
      "     add_pca_covariates() on model_data before calling this function\n",
      "     and replace lat_r_s/lon_r_s with PC1_s/PC2_s in the formula.\n",
      "  3. Fit directly with train_biodiversity_model() using a simpler\n",
      "     formula (e.g. habitat intercepts + diag(habitat|taxon) +\n",
      "     (1|taxon:grid_id)) to establish a converging baseline, then\n",
      "     add complexity incrementally."
    )
  }
  aic_table$delta_AIC[!na_aic] <- round(valid_aic - min(valid_aic), 1)
  aic_table <- aic_table[order(is.na(aic_table$delta_AIC), aic_table$delta_AIC), ]

  # Parsimony rule: only among valid models
  within_window   <- aic_table[!is.na(aic_table$delta_AIC) & aic_table$delta_AIC <= delta_aic_max, ]
  recommended_lbl <- within_window$model[which.min(within_window$n_var_params)]
  if (length(recommended_lbl) == 0L) {
    recommended_lbl <- within_window$model[1L]
  }
  aic_table$recommended <- !is.na(aic_table$model) & aic_table$model == recommended_lbl

  if (verbose) {
    cat("\n--- Model comparison (Tier 1) ---\n")
    print(aic_table, row.names = FALSE)
    cat(sprintf(
      "\n  Recommended: %s\n  (most parsimonious within %.1f AIC units of best)\n",
      recommended_lbl, delta_aic_max
    ))
    cat("  Note: this is model simplification, not validation.\n")
    cat("  Use spatial block CV to evaluate predictive accuracy.\n")
  }

  # ---------------------------------------------------------------------------
  # Step 6: Return recommended model with $model_selection attached
  # ---------------------------------------------------------------------------
  rec_key   <- names(candidates)[labels == recommended_lbl]
  model_out <- candidates[[rec_key]]$model

  model_out$model_selection <- list(
    aic_table           = aic_table,
    recommended_formula = model_out$meta$formula_tier1,
    flagged_terms       = c(flagged_moran, flagged_spatial),
    sd_table            = sd_tbl
  )

  if (verbose) {
    cat(sprintf("\n  Final Tier 1 formula:\n  %s\n",
                model_out$meta$formula_tier1))
  }

  model_out
}

# ------------------------------------------------------------------------------
# Internal helper: check whether a formula string already exists in candidates
# ------------------------------------------------------------------------------
#' @noRd
.formula_in_candidates <- function(f_chr, candidates) {
  existing <- sapply(candidates, function(x) {
    paste(deparse(x$formula, width.cutoff = 500), collapse = " ")
  })
  any(existing == f_chr)
}
