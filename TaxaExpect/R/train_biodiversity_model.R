utils::globalVariables(c(
  "grid_id", "n_total_at_site", "n_species", "n_other", "is_present",
  "n_detections", "total_detections", "theta_mean_emp", "theta_sd_emp",
  "taxon_name", "n_positive"
))

# =============================================================================
# Internal helpers
# =============================================================================

#' Screen habitats for random slope support
#'
#' Evaluates which habitat levels have sufficient Tier 1 positive observations
#' to support species-specific random slopes. Adds indicator columns to df_t1
#' for supported habitats only.
#'
#' @param df_t1 Data frame filtered to Tier 1 species, post effort-threshold.
#' @param habitat_col Character. Name of the habitat column.
#' @param taxon_col Character. Name of the taxon column.
#' @param min_positive_rows Integer. Minimum positive rows for a habitat to
#'   receive a random slope.
#' @return A list: $df (df_t1 with indicator columns added), $supported
#'   (character vector of habitat names), $sparse (character vector),
#'   $indicators (column names of indicator variables).
#' @noRd
screen_habitat_slopes <- function(df_t1, habitat_col, taxon_col,
                                  min_positive_rows) {

  hab_sym <- rlang::sym(habitat_col)

  hab_summary <- df_t1 |>
    dplyr::group_by(!!hab_sym) |>
    dplyr::summarise(n_positive = sum(n_species > 0), .groups = "drop")

  supported <- hab_summary |>
    dplyr::filter(n_positive >= min_positive_rows) |>
    dplyr::pull(!!hab_sym) |>
    as.character()

  sparse <- hab_summary |>
    dplyr::filter(n_positive < min_positive_rows) |>
    dplyr::pull(!!hab_sym) |>
    as.character()

  # Add 0/1 indicator columns for supported habitats.
  # make.names() sanitizes IUCN-style names that contain parentheses, slashes,
  # and spaces (e.g., "Pelagic (Supercolumnar)" -> "Pelagic..Supercolumnar.",
  # "Continental Slope/Bathyal Zone (200-4000m)" -> "Continental.Slope...").
  # The resulting column names are valid R identifiers. They are backtick-quoted
  # when inserted into the formula string by rewrite_habitat_formula().
  indicators <- character(0)
  for (hab in supported) {
    col_name        <- paste0("hab_", make.names(hab))
    df_t1[[col_name]] <- as.integer(df_t1[[habitat_col]] == hab)
    indicators      <- c(indicators, col_name)
  }

  list(
    df         = df_t1,
    supported  = supported,
    sparse     = sparse,
    indicators = indicators,
    summary    = hab_summary
  )
}


#' Rewrite the Tier 1 formula: replace diag() term with screened habitat slopes
#'
#' Replaces \code{diag(<habitat_col> | <taxon_col>)} in the user formula with
#' an indicator-based random slope term covering only supported habitats.
#' If no habitats are supported, the diag() term is dropped entirely.
#' All other terms pass through unchanged.
#'
#' @param formula User-supplied formula.
#' @param indicators Character vector of indicator column names (from
#'   screen_habitat_slopes).
#' @return A formula object.
#' @noRd
rewrite_habitat_formula <- function(formula, indicators) {
    f_chr <- paste(deparse(formula, width.cutoff = 500), collapse = " ")
    quoted <- paste0("`", indicators, "`")
    if (length(indicators) == 0) {
        f_chr <- gsub("\\+\\s*diag\\([^)]+\\)", "", f_chr)
        f_chr <- gsub("diag\\([^)]+\\)\\s*\\+", "", f_chr)
        f_chr <- gsub("diag\\([^)]+\\)", "", f_chr)
        message("  Habitat random slopes: none supported (all habitats sparse). ",
            "Habitat fixed effect retained.")
    }
    else if (length(quoted) == 1) {
        slope_term <- sprintf("(0 + %s | taxon_name)", quoted)
        f_chr <- gsub("diag\\([^)]+\\)", slope_term, f_chr)
    }
    else {
        # FIX: one independent (0 + hab_X | taxon_name) term per indicator
        # (previously joined into one correlated block — caused Hessian failures)
        slope_term <- paste(
            sprintf("(0 + %s | taxon_name)", quoted),
            collapse = " + "
        )
        f_chr <- gsub("diag\\([^)]+\\)", slope_term, f_chr)
    }
    f_chr <- gsub("\\s{2,}", " ", trimws(f_chr))
    stats::as.formula(f_chr)
}


# =============================================================================
# Main function
# =============================================================================

#' Train the Biodiversity Model
#'
#' Fits a binomial GLMM to estimate theta (the probability that a sampled
#' individual belongs to each species) at each grid x habitat cell. Species are
#' automatically assigned to tiers based on observation counts:
#'
#' \describe{
#'   \item{Tier 1 (common)}{Fitted with the full user-supplied formula, after
#'     automatic habitat screening replaces \code{diag(main_habitat | taxon_name)}
#'     with indicator-based slopes for supported habitats only.}
#'   \item{Tier 2 (rare detected)}{Fitted with a simplified intercept-only
#'     formula to prevent convergence failures from near-empty random effect
#'     levels.}
#'   \item{Tier 3 (undetected)}{Not modelled here; handled by
#'     \code{generate_undetected_diversity()} after fitting.}
#' }
#'
#' The returned object is self-contained: it carries the fitted models, tier
#' assignments, scaling parameters, singleton records, habitat screening
#' results, and all metadata needed by \code{generate_full_priors()}.
#'
#' @param data A tibble. Output of \code{prepare_model_dataframe()}. Must carry
#'   the \code{"scale_params"} attribute set by that function.
#' @param formula A two-sided formula for Tier 1 species. The LHS must be
#'   \code{cbind(n_species, n_other)} for \code{response = "theta"}, or
#'   \code{is_present} for \code{response = "psi"}. The habitat random slope
#'   term must be written as \code{diag(main_habitat | taxon_name)} (using
#'   the actual habitat column name); this term is automatically rewritten to
#'   indicator-based slopes for habitats that pass the sparsity screen. See
#'   Details for recommended defaults.
#' @param taxon_col Character. Name of the species identifier column.
#'   Default \code{"taxon_name"}.
#' @param habitat_col Character. Name of the habitat column.
#'   Default \code{"main_habitat"}.
#' @param response Character. \code{"theta"} fits the proportion model
#'   (default). \code{"psi"} fits a presence-absence model.
#' @param min_obs_threshold Integer. Minimum positive detections across all
#'   sites for Tier 1. Species below threshold receive the intercept-only Tier
#'   2 formula. Default \code{5}.
#' @param effort_threshold Integer. Minimum total community count
#'   (\code{n_total_at_site}) for a cell to enter the likelihood. Default
#'   \code{10}.
#' @param min_positive_rows Integer. Minimum number of positive
#'   (species-detected) rows a habitat must contribute across Tier 1 species
#'   to receive a species-specific random slope. Habitats below this threshold
#'   are retained as fixed effects only. Default \code{50}.
#' @param full_data A tibble. The original pre-aggregated data (output of
#'   \code{create_sites_from_grid()}) used to identify singletons for
#'   \code{generate_undetected_diversity()}. If \code{NULL}, singletons are
#'   identified from \code{data} directly.
#'
#' @return An object of class \code{"biofreq_model"}, a named list containing:
#'   \describe{
#'     \item{models}{List: \code{$tier1} and \code{$tier2}, each a fitted
#'       glmmTMB object (or \code{NULL} if no species in that tier).}
#'     \item{tiers}{Tibble: taxon_name, tier ("tier1"/"tier2"),
#'       n_detections. One row per species.}
#'     \item{scale_params}{Named list of scaling parameters from
#'       \code{prepare_model_dataframe()}. Each entry: \code{$center} and
#'       \code{$scale}.}
#'     \item{singletons}{Data frame of single-detection species (species
#'       observed exactly once across all samples). Used by
#'       \code{generate_undetected_diversity()} to create Tier 3 proxy priors.
#'       Note: this ecological concept is distinct from "singleton sequences"
#'       in TaxaLikely (reference sequences with no within-species neighbours).}
#'     \item{N_total}{Integer. Sum of community counts across all
#'       effort-passing cells. Used for the global undetected floor prior.}
#'     \item{tier2_empirical}{Data frame of observed mean/SD theta per
#'       species x habitat for Tier 2 species. Fallback if Tier 2 model
#'       fails.}
#'     \item{habitat_screening}{List documenting the habitat slope screening
#'       result: \code{$supported}, \code{$sparse}, \code{$indicators},
#'       \code{$min_positive_rows}, \code{$summary} (positive row counts per
#'       habitat), \code{$formula_used} (the actual formula fitted).}
#'     \item{convergence_warnings}{Character vector of any convergence warnings
#'       captured during fitting.}
#'     \item{meta}{Named list of metadata: taxon_col, habitat_col, response,
#'       min_obs_threshold, effort_threshold, min_positive_rows,
#'       formula_tier1, formula_tier2, n_sites, n_species_tier1,
#'       n_species_tier2.}
#'   }
#'
#' @details
#' **Recommended default formula:**
#' \preformatted{
#' cbind(n_species, n_other) ~
#'   main_habitat +
#'   (1 | taxon_name) +
#'   diag(main_habitat | taxon_name) +
#'   (0 + lat_r_s | taxon_name) +
#'   (0 + lon_r_s | taxon_name) +
#'   (1 | taxon_name:grid_id)
#' }
#'
#' The \code{(1 | taxon_name)} term gives each species its own random intercept,
#' capturing overall rarity independently of habitat preference. Without it, all
#' species share the same baseline and a globally rare species is predicted at the
#' global average rate in any habitat where it has not been observed. The intercept
#' shrinks toward the global mean across all species, which is acceptable when
#' the species pool has a right-skewed abundance distribution (most species rare)
#' and the effort threshold ensures that singletons in low-effort cells do not
#' enter the likelihood. Species with many zero-detection cells in high-effort
#' grids are correctly pushed toward low intercepts by the data.
#'
#' The \code{diag(main_habitat | taxon_name)} term is a placeholder. The
#' function screens each habitat level for sufficient Tier 1 coverage (at least
#' \code{min_positive_rows} positive observations). Supported habitats receive
#' species-specific random slopes via indicator variables; sparse habitats are
#' captured by the fixed \code{main_habitat} effect only. The rewritten formula
#' actually fitted is stored in \code{$habitat_screening$formula_used}.
#'
#' The \code{(1 | taxon_name:grid_id)} term captures local grid-level
#' deviations from the spatial surface for each species. Its variance is
#' estimated from data, removing the need for the manual prior cap and Bayesian
#' local update steps previously required.
#'
#' **Tier 2 formula (automatic, not user-specified):**
#' \preformatted{cbind(n_species, n_other) ~ main_habitat + (1 | taxon_name)}
#'
#' **Convergence:** A non-positive-definite Hessian warning from glmmTMB
#' indicates unreliable uncertainty estimates. Warnings are captured in
#' \code{$convergence_warnings}. If persistent, simplify the formula or
#' increase \code{min_positive_rows}.
#'
#' \strong{Shared effort assumption:} The binomial response
#' \code{cbind(n_species, n_other)} divides a focal species count by the total
#' community count at a site. All taxa in \code{data} must therefore have been
#' detected through the same sampling method. Mixing taxa from incommensurable
#' surveys --- for example, eDNA reads from different gene markers, or
#' phytoplankton microscopy counts combined with bird point-count records ---
#' invalidates the shared denominator. Each taxon group with a distinct
#' detection process should be modelled separately and its priors passed to
#' TaxaAssign independently. See
#' \code{\link{prepare_model_dataframe}} for further discussion.
#'
#' @references
#' Brooks, M.E., Kristensen, K., van Benthem, K.J., Magnusson, A., Berg, C.W.,
#' Nielsen, A., Skaug, H.J., Maechler, M. and Bolker, B.M. (2017). glmmTMB
#' balances speed and flexibility among packages for zero-inflated generalized
#' linear mixed modeling. \emph{The R Journal}, 9(2), 378--400.
#' \doi{10.32614/RJ-2017-066}
#'
#' Warton, D.I., Blanchet, F.G., O'Hara, R.B., Ovaskainen, O., Taskinen, S.,
#' Walker, S.C. and Hui, F.K.C. (2015). So many variables: joint modeling in
#' community ecology. \emph{Trends in Ecology & Evolution}, 30(12), 766--779.
#' \doi{10.1016/j.tree.2015.09.007}
#'
#' MacKenzie, D.I., Nichols, J.D., Lachman, G.B., Droege, S., Royle, J.A. and
#' Langtimm, C.A. (2002). Estimating site occupancy rates when detection
#' probabilities are less than one. \emph{Ecology}, 83(8), 2248--2255.
#' \doi{10.1890/0012-9658(2002)083[2248:ESORWD]2.0.CO;2}
#'
#' @seealso \code{\link{prepare_model_dataframe}},
#'   \code{\link{generate_undetected_diversity}},
#'   \code{\link{generate_full_priors}}
#'
#' @examples
#' \dontrun{
#' model_fit <- train_biodiversity_model(
#'   model_df,
#'   formula = presence ~ lat_r + lon_r + (1 | taxon_name)
#' )
#' print(model_fit)
#' }
#'
#' @importFrom glmmTMB glmmTMB
#' @importFrom dplyr filter group_by summarise mutate pull left_join select
#'   distinct rename n_distinct all_of
#' @importFrom rlang sym :=
#' @importFrom stats sd setNames as.formula
#' @export

train_biodiversity_model <- function(data,
                                     formula,
                                     taxon_col         = "taxon_name",
                                     habitat_col       = "main_habitat",
                                     response          = c("theta", "psi"),
                                     min_obs_threshold = 5L,
                                     effort_threshold  = 10L,
                                     min_positive_rows = 50L,
                                     full_data         = NULL) {

  response <- match.arg(response)

  if (!requireNamespace("glmmTMB", quietly = TRUE)) {
    stop("train_biodiversity_model: package 'glmmTMB' is required. ",
         "Install it with: install.packages('glmmTMB')")
  }

  # ---------------------------------------------------------------------------
  # Input checks
  # ---------------------------------------------------------------------------
  required_cols <- c("grid_id", "n_species", "n_other",
                     "n_total_at_site", taxon_col, habitat_col)
  missing_cols  <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0) {
    stop("train_biodiversity_model: missing required columns: ",
         paste(missing_cols, collapse = ", "),
         "\nDid you run prepare_model_dataframe() first?")
  }

  if (!inherits(formula, "formula")) {
    stop("train_biodiversity_model: 'formula' must be a formula object.")
  }

  lhs <- deparse(formula[[2]])
  if (!grepl("cbind", lhs) && response == "theta") {
    stop("train_biodiversity_model: formula LHS must be cbind(n_species, n_other) ",
         "for response = 'theta'.")
  }

  # Check formula variables exist in data, excluding interaction terms
  # (e.g., taxon_name:grid_id is handled by glmmTMB, not a required column)
  formula_vars  <- all.vars(formula)
  response_vars <- c("n_species", "n_other", "is_present")
  # Exclude variables that are grouping factors in random effects — glmmTMB
  # resolves interactions like taxon_name:grid_id internally
  check_vars    <- setdiff(formula_vars, c(response_vars, taxon_col,
                                           habitat_col, "grid_id"))
  missing_vars  <- setdiff(check_vars, names(data))
  if (length(missing_vars) > 0) {
    old_style <- intersect(missing_vars, c("lat_s", "lon_s"))
    if (length(old_style) > 0) {
      scaled_cols <- paste(grep("_s$", names(data), value = TRUE),
                           collapse = ", ")
      stop("train_biodiversity_model: formula references '",
           paste(missing_vars, collapse = "', '"), "' which are not in data.\n",
           "Note: prepare_model_dataframe() names scaled columns <covariate>_s ",
           "(e.g., lat_r_s, lon_r_s, not lat_s/lon_s).\n",
           "Scaled columns available in your data: ", scaled_cols)
    }
    stop("train_biodiversity_model: formula references columns not found in data: ",
         paste(missing_vars, collapse = ", "))
  }

  # ---------------------------------------------------------------------------
  # Extract scale_params from data attribute
  # ---------------------------------------------------------------------------
  scale_params <- attr(data, "scale_params")
  if (is.null(scale_params)) {
    warning(
      "train_biodiversity_model: 'scale_params' attribute not found on data. ",
      "For consistent predictions at new sites, run prepare_model_dataframe() ",
      "before train_biodiversity_model(). Estimating scaling from data directly.",
      call. = FALSE
    )
    s_cols       <- grep("_s$", names(data), value = TRUE)
    orig_cols    <- sub("_s$", "", s_cols)
    present      <- orig_cols %in% names(data)
    scale_params <- setNames(
      lapply(orig_cols[present], function(oc) {
        list(center = mean(data[[oc]], na.rm = TRUE),
             scale  = sd(data[[oc]],   na.rm = TRUE))
      }),
      orig_cols[present]
    )
  }

  # ---------------------------------------------------------------------------
  # Apply effort threshold
  # ---------------------------------------------------------------------------
  n_total_rows <- nrow(data)
  n_dropped    <- sum(data$n_total_at_site < effort_threshold)
  if (n_dropped > 0) {
    message(sprintf(
      "Effort threshold: excluding %d site-habitat cells with N < %d (%.1f%% of rows).",
      n_dropped, effort_threshold, 100 * n_dropped / n_total_rows
    ))
  }
  df <- dplyr::filter(data, n_total_at_site >= effort_threshold)

  if (nrow(df) == 0) {
    stop("train_biodiversity_model: no rows remain after effort threshold filtering. ",
         "Consider reducing effort_threshold (currently ", effort_threshold, ").")
  }

  # ---------------------------------------------------------------------------
  # For psi response: swap LHS
  # ---------------------------------------------------------------------------
  formula_tier1 <- formula
  if (response == "psi") {
    if (!"is_present" %in% names(df)) {
      df <- dplyr::mutate(df, is_present = as.integer(n_species > 0))
    }
    formula_chr   <- deparse(formula)
    formula_tier1 <- stats::as.formula(
      gsub("cbind\\(n_species,\\s*n_other\\)", "is_present", formula_chr)
    )
    message("Response = 'psi': fitting presence-absence model.")
  }

  # ---------------------------------------------------------------------------
  # Species tier assignment
  # ---------------------------------------------------------------------------
  taxon_sym   <- rlang::sym(taxon_col)
  habitat_sym <- rlang::sym(habitat_col)

  species_detections <- df |>
    dplyr::group_by(!!taxon_sym) |>
    dplyr::summarise(
      n_detections = sum(n_species > 0),
      .groups = "drop"
    ) |>
    dplyr::rename(taxon_name = !!taxon_sym) |>
    dplyr::mutate(
      tier = dplyr::if_else(n_detections >= min_obs_threshold, "tier1", "tier2")
    )

  taxa_tier1 <- species_detections$taxon_name[species_detections$tier == "tier1"]
  taxa_tier2 <- species_detections$taxon_name[species_detections$tier == "tier2"]

  message(sprintf(
    "Species tiers: %d Tier 1 (full model), %d Tier 2 (intercept-only).",
    length(taxa_tier1), length(taxa_tier2)
  ))

  # ---------------------------------------------------------------------------
  # Tier 2 formula (always intercept-only, habitat fixed effect retained)
  # ---------------------------------------------------------------------------
  lhs_str       <- if (response == "psi") "is_present" else "cbind(n_species, n_other)"
  formula_tier2 <- stats::as.formula(
    paste0(lhs_str, " ~ ", habitat_col, " + (1 | ", taxon_col, ")")
  )

  # ---------------------------------------------------------------------------
  # N_total: sum of community counts across unique effort-passing site x
  # habitat cells (not species x site rows, which repeat n_total_at_site)
  # ---------------------------------------------------------------------------
  N_total <- df |>
    dplyr::distinct(grid_id, !!habitat_sym, n_total_at_site) |>
    dplyr::pull(n_total_at_site) |>
    sum()

  # ---------------------------------------------------------------------------
  # Identify singletons for generate_undetected_diversity()
  # ---------------------------------------------------------------------------
  singleton_src <- if (!is.null(full_data)) full_data else data
  is_raw        <- !"n_species" %in% names(singleton_src)

  if (is_raw) {
    species_totals <- singleton_src |>
      dplyr::group_by(!!rlang::sym(taxon_col)) |>
      dplyr::summarise(total_detections = dplyr::n(), .groups = "drop")
  } else {
    species_totals <- singleton_src |>
      dplyr::group_by(!!rlang::sym(taxon_col)) |>
      dplyr::summarise(total_detections = sum(n_species > 0), .groups = "drop")
  }

  singleton_names <- species_totals |>
    dplyr::filter(total_detections == 1) |>
    dplyr::pull(!!rlang::sym(taxon_col))

  if (is_raw) {
    site_totals_for_singletons <- df |>
      dplyr::distinct(grid_id, !!habitat_sym, n_total_at_site)

    singletons <- singleton_src |>
      dplyr::filter((!!rlang::sym(taxon_col)) %in% singleton_names) |>
      dplyr::group_by(!!rlang::sym(taxon_col), grid_id,
                      !!rlang::sym(habitat_col)) |>
      dplyr::summarise(n_species = dplyr::n(), .groups = "drop") |>
      dplyr::left_join(site_totals_for_singletons,
                       by = c("grid_id", habitat_col)) |>
      dplyr::mutate(
        theta_obs = dplyr::if_else(
          !is.na(n_total_at_site), n_species / n_total_at_site, NA_real_
        )
      ) |>
      dplyr::left_join(
        dplyr::rename(species_totals, !!taxon_col := !!rlang::sym(taxon_col)),
        by = taxon_col
      )
  } else {
    singletons <- singleton_src |>
      dplyr::filter(
        (!!rlang::sym(taxon_col)) %in% singleton_names,
        n_species > 0
      ) |>
      dplyr::mutate(theta_obs = n_species / n_total_at_site) |>
      dplyr::select(
        dplyr::all_of(c(taxon_col, "grid_id", habitat_col,
                        "n_species", "n_total_at_site", "theta_obs"))
      ) |>
      dplyr::left_join(
        dplyr::rename(species_totals, !!taxon_col := !!rlang::sym(taxon_col)),
        by = taxon_col
      )
  }

  message(sprintf(
    "Singletons identified: %d (basis for undetected species priors).",
    nrow(singletons)
  ))

  # ---------------------------------------------------------------------------
  # Empirical stats for Tier 2 (fallback if Tier 2 model fails)
  # ---------------------------------------------------------------------------
  tier2_empirical <- df |>
    dplyr::filter(
      (!!taxon_sym) %in% taxa_tier2,
      n_species > 0
    ) |>
    dplyr::group_by(!!taxon_sym, !!habitat_sym) |>
    dplyr::summarise(
      theta_mean_emp = mean(n_species / n_total_at_site, na.rm = TRUE),
      theta_sd_emp   = sd(n_species / n_total_at_site,   na.rm = TRUE),
      n_detections   = dplyr::n(),
      .groups        = "drop"
    ) |>
    dplyr::mutate(
      theta_sd_emp = dplyr::if_else(
        is.na(theta_sd_emp), theta_mean_emp * 0.5, theta_sd_emp
      )
    )

  # ---------------------------------------------------------------------------
  # Habitat screening for Tier 1 random slopes
  # Replaces diag(main_habitat | taxon_name) with indicator-based slopes
  # for habitats that pass the min_positive_rows threshold.
  # ---------------------------------------------------------------------------
  hab_screen    <- NULL
  formula_final <- formula_tier1   # default if no diag() term in formula

  has_diag_term <- grepl("diag\\(", deparse(formula_tier1, width.cutoff = 500))

  if (has_diag_term && length(taxa_tier1) > 0) {

    df_t1_screen <- df |>
      dplyr::filter((!!taxon_sym) %in% taxa_tier1)

    hab_screen <- screen_habitat_slopes(
      df_t1             = df_t1_screen,
      habitat_col       = habitat_col,
      taxon_col         = taxon_col,
      min_positive_rows = min_positive_rows
    )

    n_supported <- length(hab_screen$supported)
    n_sparse    <- length(hab_screen$sparse)

    message(sprintf(
      "Habitat random slopes: %d supported (%s)%s.",
      n_supported,
      if (n_supported > 0) paste(hab_screen$supported, collapse = ", ")
      else "none",
      if (n_sparse > 0) sprintf(
        "; %d sparse \u2014 fixed effect only (%s)",
        n_sparse, paste(hab_screen$sparse, collapse = ", ")
      ) else ""
    ))

    formula_final <- rewrite_habitat_formula(formula_tier1, hab_screen$indicators)

  } else if (!has_diag_term) {
    message("No diag() habitat term found in formula \u2014 using formula as supplied.")
  }

  # ---------------------------------------------------------------------------
  # Fit Tier 1 model
  # ---------------------------------------------------------------------------
  convergence_warnings <- character(0)
  mod_tier1            <- NULL

  if (length(taxa_tier1) > 0) {
    t0_tier1 <- proc.time()[["elapsed"]]
    message(sprintf("Fitting Tier 1 model (%d species)...", length(taxa_tier1)))

    # Build df_t1, adding indicator columns if habitat screening ran
    df_t1 <- df |>
      dplyr::filter((!!taxon_sym) %in% taxa_tier1) |>
      droplevels()

    # indicators and supported are positionally aligned (both from screen_habitat_slopes)
    if (!is.null(hab_screen) && length(hab_screen$indicators) > 0) {
      for (i in seq_along(hab_screen$indicators)) {
        df_t1[[ hab_screen$indicators[i] ]] <-
          as.integer(df_t1[[habitat_col]] == hab_screen$supported[i])
      }
    }

    tier1_warns <- character(0)
    tryCatch({
      withCallingHandlers(
        {
          mod_tier1 <- glmmTMB::glmmTMB(
            formula_final,
            data   = df_t1,
            family = stats::binomial()
          )
        },
        warning = function(w) {
          tier1_warns <<- c(tier1_warns, paste("Tier 1:", conditionMessage(w)))
          invokeRestart("muffleWarning")
        }
      )
    }, error = function(e) {
      stop(
        "train_biodiversity_model: Tier 1 model failed to fit.\n",
        "Error: ", conditionMessage(e), "\n",
        "Consider simplifying the formula or increasing min_positive_rows ",
        "to reduce random slope complexity."
      )
    })

    convergence_warnings <- c(convergence_warnings, tier1_warns)

    if (length(tier1_warns) > 0) {
      message(sprintf("Tier 1 convergence warnings captured (%.1fs; see $convergence_warnings).",
                      proc.time()[["elapsed"]] - t0_tier1))
    } else {
      message(sprintf("Tier 1 model fitted successfully (%.1fs).",
                      proc.time()[["elapsed"]] - t0_tier1))
    }

  } else {
    warning(
      "train_biodiversity_model: no Tier 1 species found at min_obs_threshold = ",
      min_obs_threshold, ". Consider reducing the threshold.",
      call. = FALSE
    )
  }

  # ---------------------------------------------------------------------------
  # Fit Tier 2 model
  # ---------------------------------------------------------------------------
  mod_tier2 <- NULL

  if (length(taxa_tier2) > 0) {
    message(sprintf(
      "Fitting Tier 2 model (%d species, intercept-only)...", length(taxa_tier2)
    ))
    df_t2 <- df |>
      dplyr::filter((!!taxon_sym) %in% taxa_tier2) |>
      droplevels()

    tier2_warns <- character(0)
    tryCatch({
      withCallingHandlers(
        {
          mod_tier2 <- glmmTMB::glmmTMB(
            formula_tier2,
            data   = df_t2,
            family = stats::binomial()
          )
        },
        warning = function(w) {
          tier2_warns <<- c(tier2_warns, paste("Tier 2:", conditionMessage(w)))
          invokeRestart("muffleWarning")
        }
      )
    }, error = function(e) {
      warning(
        "train_biodiversity_model: Tier 2 model failed to fit. ",
        "Tier 2 species will fall back to empirical means.\n",
        "Error: ", conditionMessage(e),
        call. = FALSE
      )
    })

    convergence_warnings <- c(convergence_warnings, tier2_warns)

    if (length(tier2_warns) > 0) {
      message("Tier 2 convergence warnings captured (see $convergence_warnings).")
    } else if (!is.null(mod_tier2)) {
      message("Tier 2 model fitted successfully.")
    }
  }

  # ---------------------------------------------------------------------------
  # Assemble and return model object
  # ---------------------------------------------------------------------------

  # habitat_screening stored with formula_used for reproducibility
  hab_screen_out <- if (!is.null(hab_screen)) {
    list(
      supported         = hab_screen$supported,
      sparse            = hab_screen$sparse,
      indicators        = hab_screen$indicators,
      min_positive_rows = min_positive_rows,
      summary           = hab_screen$summary,
      formula_used      = deparse(formula_final, width.cutoff = 500)
    )
  } else {
    list(
      supported         = character(0),
      sparse            = character(0),
      indicators        = character(0),
      min_positive_rows = min_positive_rows,
      summary           = NULL,
      formula_used      = deparse(formula_final, width.cutoff = 500)
    )
  }

  model_obj <- list(
    models = list(
      tier1 = mod_tier1,
      tier2 = mod_tier2
    ),
    tiers                = species_detections,
    scale_params         = scale_params,
    singletons           = singletons,
    N_total              = N_total,
    tier2_empirical      = tier2_empirical,
    habitat_screening    = hab_screen_out,
    convergence_warnings = convergence_warnings,
    meta = list(
      taxon_col         = taxon_col,
      habitat_col       = habitat_col,
      response          = response,
      min_obs_threshold = min_obs_threshold,
      effort_threshold  = effort_threshold,
      min_positive_rows = min_positive_rows,
      formula_tier1     = deparse(formula_final, width.cutoff = 500),
      formula_tier2     = deparse(formula_tier2, width.cutoff = 500),
      n_sites           = dplyr::n_distinct(df$grid_id),
      n_species_tier1   = length(taxa_tier1),
      n_species_tier2   = length(taxa_tier2)
    )
  )

  class(model_obj) <- "biofreq_model"

  message(sprintf(
    "--- Done: %d Tier 1, %d Tier 2, %d singletons, N_total = %d ---",
    length(taxa_tier1), length(taxa_tier2), nrow(singletons), N_total
  ))

  return(model_obj)
}


# =============================================================================
# Print / Summary methods
# =============================================================================

#' Print a biofreq_model Object
#' @param x A biofreq_model object.
#' @param ... Ignored.
#' @return \code{x}, invisibly.
#' @export
print.biofreq_model <- function(x, ...) {
  cat("biofreq_model\n")
  cat("-------------\n")
  cat("Response:            ", x$meta$response, "\n")
  cat("Tier 1 species:      ", x$meta$n_species_tier1,
      " (threshold: >=", x$meta$min_obs_threshold, "detections)\n")
  cat("Tier 2 species:      ", x$meta$n_species_tier2,
      " (intercept-only)\n")
  cat("Sites modelled:      ", x$meta$n_sites, "\n")
  cat("Effort threshold:    ", x$meta$effort_threshold, " (min N per cell)\n")
  cat("Min positive rows:   ", x$meta$min_positive_rows,
      " (habitat random slope threshold)\n")
  cat("Singletons:          ", nrow(x$singletons),
      " (basis for undetected species priors)\n")
  cat("N_total:             ", x$N_total,
      " (global undetected floor denominator)\n")

  # Habitat screening summary
  hs <- x$habitat_screening
  if (length(hs$supported) > 0 || length(hs$sparse) > 0) {
    cat("\nHabitat random slopes:\n")
    if (length(hs$supported) > 0)
      cat("  Supported: ", paste(hs$supported, collapse = ", "), "\n")
    if (length(hs$sparse) > 0)
      cat("  Sparse (fixed effect only): ",
          paste(hs$sparse, collapse = ", "), "\n")
  }

  cat("\nTier 1 formula:\n  ", x$meta$formula_tier1, "\n")
  cat("Tier 2 formula:\n  ", x$meta$formula_tier2, "\n")
  cat("\nScale params stored for",
      length(x$scale_params), "covariate(s):",
      paste(names(x$scale_params), collapse = ", "), "\n")

  if (length(x$convergence_warnings) > 0) {
    cat("\n*** Convergence warnings (", length(x$convergence_warnings),
        ") ***\n", sep = "")
    cat("  Run x$convergence_warnings to view details.\n")
    cat("  If Tier 1: consider simplifying the formula or increasing ",
        "min_positive_rows.\n")
  } else {
    cat("\nNo convergence warnings.\n")
  }
  invisible(x)
}

#' Summary of a biofreq_model Object
#' @param object A biofreq_model object.
#' @param ... Ignored.
#' @return \code{object}, invisibly.
#' @export
summary.biofreq_model <- function(object, ...) {
  print(object)
  cat("\nTier assignments:\n")
  print(object$tiers)
  if (!is.null(object$habitat_screening$summary)) {
    cat("\nHabitat positive-row counts (Tier 1 species):\n")
    print(object$habitat_screening$summary)
  }
  invisible(object)
}
