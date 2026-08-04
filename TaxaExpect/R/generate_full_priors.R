utils::globalVariables(c(
  ".habitat", "grid_id", "taxon_name", "alpha", "beta",
  "theta_mean", "theta_sd", "n_obs", "model_tier", "effort_flag",
  "observed_in_habitat", "extrapolation_warning",
  "undetected_type", "jeffreys_fallback", "n_total_at_site",
  "taxon_name", "source_taxon_name",
  "theta_mean_emp", "theta_sd_emp", "n_detections"
))

#' Generate Full Prior Object for TaxaAssign
#'
#' Predicts theta at each taxon_name x site x habitat combination in a prediction
#' grid, converts model predictions and their uncertainty to Beta(alpha, beta)
#' priors, appends undetected taxon_name proxies, and returns the complete prior
#' table ready for TaxaAssign.
#'
#' The prediction grid is passed in as-is -- filter it before calling this
#' function. Common patterns:
#' \itemize{
#'   \item \strong{All taxa at one or a few sites:} pass a grid filtered to
#'     those sites.
#'   \item \strong{One taxon across many sites (taxon_name map):} pass the full
#'     grid and filter the output to the taxon of interest.
#' }
#'
#' @param model_obj A biofreq_model object from train_biodiversity_model().
#' @param new_sites A data frame of prediction sites. Must contain grid_id,
#'   lat_r, lon_r, and the habitat column -- unless \code{model_obj} was
#'   trained with \code{habitat_col = NULL} (see
#'   \code{\link{train_biodiversity_model}}), in which case no habitat
#'   column is required or used, and the output has no habitat column
#'   either. Typically a subset of the output from create_sites_from_grid().
#'   Does NOT need taxon_name or count columns.
#'   If n_total_at_site is present, it is used for effort_flag; if absent,
#'   effort_flag is NA for all rows.
#' @param undetected A tibble from generate_undetected_diversity(), or NULL
#'   to omit undetected taxon_name priors.
#' @param min_phi Numeric. Minimum concentration (alpha + beta) for modelled
#'   priors. When the phi cap (from grid-level variance) forces concentration
#'   below this floor, phi is raised to \code{min_phi}. This prevents modelled
#'   priors from becoming so diffuse that Monte Carlo posterior estimates are
#'   unstable, and ensures that species observed in training data always receive
#'   more informative priors than undetected-diversity fallbacks. Default
#'   \code{2}, matching the singleton effective sample size in
#'   \code{generate_undetected_diversity()}.
#' @param theta_epsilon Numeric. Floor/ceiling applied to back-transformed
#'   theta before alpha/beta conversion, to avoid boundary values. Applied to
#'   \strong{Tier 1} predictions as supplied (default \code{1e-6}), preserving
#'   real differentiation among low-but-genuine probabilities.
#'
#'   For \strong{Tier 2} only, a separate, higher floor is derived
#'   automatically when \code{undetected} is supplied and contains
#'   \code{"singleton_mirror"} rows: the floor is raised to the mean
#'   singleton-mirror detection rate if that exceeds \code{theta_epsilon}.
#'   This ensures Tier 2 species (sparse but detected) always receive priors
#'   above the dark-diversity floor computed in \code{TaxaAssign::join_priors()},
#'   preventing conflation with species that have never been detected in the
#'   system. \strong{This raised floor is Tier-2-only} -- a real bug found
#'   2026-07-03 applied it globally, silently flattening every Tier 1 species
#'   whose real predicted probability fell below the floor to the same
#'   identical value (invisible with a handful of well-separated candidates,
#'   but visibly wrong with a broader, more realistic candidate pool where
#'   many species legitimately have low individual probabilities).
#'
#' @return A tibble with one row per taxon_name x site x habitat combination
#'   (plus undetected rows if provided), containing:
#'   \describe{
#'     \item{taxon_name}{taxon_name identifier (NA for undetected proxies).}
#'     \item{grid_id}{Site identifier.}
#'     \item{habitat}{Habitat identifier. Column absent entirely when
#'       \code{model_obj} was trained with \code{habitat_col = NULL}.}
#'     \item{alpha}{Alpha parameter of Beta(alpha, beta) prior.}
#'     \item{beta}{Beta parameter of Beta(alpha, beta) prior.}
#'     \item{theta_mean}{Derived: alpha / (alpha + beta).}
#'     \item{theta_sd}{Derived: SD of Beta(alpha, beta). Reflects model
#'       uncertainty at this site, not sampling effort.}
#'     \item{n_obs}{n_total_at_site from new_sites if present, otherwise NA.}
#'     \item{model_tier}{"tier1", "tier2", or "tier3_undetected".}
#'     \item{effort_flag}{Logical: was N below the training effort threshold?
#'       NA if n_total_at_site was not supplied in new_sites.}
#'     \item{observed_in_habitat}{Logical: was this taxon_name ever
#'       recorded in this habitat in the training data? FALSE indicates a
#'       habitat extrapolation.}
#'     \item{extrapolation_warning}{Logical: does this site fall outside the
#'       covariate range seen during training (|z| > 3)?}
#'     \item{undetected_type}{NA for modelled taxon_name; "singleton_mirror" or
#'       "global_floor" for Tier 3 proxies.}
#'     \item{source_taxon_name}{NA for modelled rows; taxon name of the
#'       singleton source species for "singleton_mirror" rows; NA for
#'       "global_floor". Used for taxonomy lookup in dark diversity grouping.
#'       Carried through from \code{generate_undetected_diversity()}.}
#'   }
#'
#' @details
#' \strong{What is theta?}
#' Theta is the expected relative abundance of a species at a site: the
#' probability that a randomly sampled individual from the community at that
#' location belongs to species X. Values near 0 indicate rare or absent species;
#' values near 1 indicate dominant species. Theta is estimated from occurrence
#' data by the biodiversity model and expressed as a Beta(alpha, beta) prior
#' for use in Bayesian taxonomic assignment (TaxaAssign).
#'
#' \strong{Habitat indicator columns:}
#' If \code{train_biodiversity_model()} identified supported habitats for
#' species-specific random slopes, it stored the indicator column names and
#' their corresponding habitat labels in \code{model_obj$habitat_screening}.
#' \code{generate_full_priors()} reconstructs these columns on
#' \code{new_sites} automatically. Prediction sites whose habitat is not in
#' \code{$habitat_screening$supported} receive 0 for all indicators, which is
#' correct -- those habitats are covered by the fixed \code{main_habitat}
#' effect only.
#'
#' \strong{Alpha/beta conversion and phi cap:}
#' glmmTMB predictions on the link (logit) scale include a standard error.
#' These are back-transformed to the probability scale and converted to Beta
#' parameters via moment-matching:
#' \preformatted{
#'   m     <- predicted theta (mean)
#'   v     <- predicted variance (from SE, delta method)
#'   phi   <- m * (1 - m) / v - 1   # precision = alpha + beta
#'   alpha <- m * phi
#'   beta  <- (1 - m) * phi
#' }
#' When theta is near 0 or 1, \code{m*(1-m)} is tiny and phi can explode even
#' with a modest logit-scale SE. Phi is capped at \code{1 / grid_var}, where
#' \code{grid_var} is the \code{taxon_name:grid_id} variance from the Tier 1
#' model. This is principled: the model's own estimate of grid-level
#' uncertainty sets the ceiling on prior concentration. No user input needed.
#'
#' If phi <= 0 after capping and flooring at \code{min_phi} (variance exceeds
#' the Bernoulli maximum, or the SE prediction itself was non-finite -- with
#' \code{min_phi > 0}, the default, the finite "too much variance" case is
#' already rescued by the floor, so this branch is reached almost exclusively
#' via a non-finite SE), the fallback preserves the model's
#' point-estimate mean \code{m} rather than discarding it for the agnostic
#' Jeffreys mean of 0.5 -- 0.5 is a poor stand-in for what a Tier 1/2
#' prediction almost always actually is (a low-theta species, not a coin
#' flip). The row instead receives a diffuse Beta at that same mean,
#' concentration \code{min_phi} (\code{alpha = m * min_phi},
#' \code{beta = (1 - m) * min_phi}), with \code{jeffreys_fallback = TRUE}
#' flagging that the variance side of the moment-match was unusable here. A
#' true, fully agnostic Jeffreys prior (\code{alpha = beta = 0.5}) is used
#' only when the mean itself is also non-finite (a total prediction failure,
#' not just an unreliable SE) -- confirmed empirically not to fire on real
#' PtConception 18S data (0/1200 rows) with defaults, since \code{min_phi}'s
#' floor already handles the ordinary finite-variance case.
#'
#' \strong{Covariate scaling:}
#' \code{new_sites} is scaled using \code{scale_params} stored in
#' \code{model_obj} (set during training), not re-scaled from prediction data.
#'
#' @note The output contains \code{taxon_name} but NOT \code{taxon_name_rank}.
#' If passing directly to \code{TaxaAssign::join_priors()} (which requires
#' \code{taxon_name_rank}), first call
#' \code{TaxaTools::create_taxon_names(priors, rank_system)} to add the column.
#' The \code{\link{build_priors}} wrapper handles this automatically.
#'
#' @references
#' Jeffreys, H. (1946). An invariant form for the prior probability in
#' estimation problems. \emph{Proceedings of the Royal Society of London A},
#' 186(1007), 453--461. \doi{10.1098/rspa.1946.0056}
#'
#' Gelman, A., Carlin, J.B., Stern, H.S., Dunson, D.B., Vehtari, A. and
#' Rubin, D.B. (2013). \emph{Bayesian Data Analysis}. 3rd edn. CRC Press.
#'
#' @seealso \code{train_biodiversity_model()},
#'   \code{generate_undetected_diversity()}
#'
#' @examples
#' \dontrun{
#' priors <- generate_full_priors(
#'   model_fit, new_sites = sample_meta,
#'   undetected = dark_priors
#' )
#' head(priors)
#' }
#'
#' @importFrom dplyr left_join mutate filter select bind_rows distinct rename all_of if_else
#' @importFrom tidyr crossing replace_na
#' @importFrom rlang sym :=
#' @export

generate_full_priors <- function(model_obj,
                                 new_sites,
                                 undetected    = NULL,
                                 min_phi       = 2,
                                 theta_epsilon = 1e-6) {

  # ---------------------------------------------------------------------------
  # Input checks
  # ---------------------------------------------------------------------------
  if (!inherits(model_obj, "biofreq_model")) {
    stop("generate_full_priors: model_obj must be a biofreq_model object.")
  }

  taxon_col    <- model_obj$meta$taxon_col
  habitat_col  <- model_obj$meta$habitat_col
  effort_thr   <- model_obj$meta$effort_threshold
  scale_params <- model_obj$scale_params

  required_site_cols <- c("grid_id", "lat_r", "lon_r", habitat_col)
  missing_cols <- setdiff(required_site_cols, names(new_sites))
  if (length(missing_cols) > 0) {
    stop("generate_full_priors: new_sites is missing columns: ",
         paste(missing_cols, collapse = ", "))
  }

  if (!is.numeric(min_phi) || length(min_phi) != 1L || is.na(min_phi) || min_phi < 0) {
    stop("generate_full_priors: min_phi must be a non-negative numeric scalar.")
  }

  has_n_total  <- "n_total_at_site" %in% names(new_sites)
  no_habitat   <- is.null(habitat_col)
  habitat_sym  <- if (no_habitat) NULL else rlang::sym(habitat_col)
  taxon_sym    <- rlang::sym(taxon_col)

  # ---------------------------------------------------------------------------
  # Derive a Tier-2-only theta_epsilon floor from singleton mirrors when the
  # undetected pool is available. Singleton mirrors represent the detection
  # probability of species observed exactly once in training data. Using
  # their mean as a floor ensures Tier 2 (sparse but detected) species have
  # theta >= the rarest known detection rate, so they don't collapse to the
  # same prior as species never detected at all (dark diversity), which
  # join_priors() would otherwise conflate via its dark_mean promotion step.
  #
  # IMPORTANT: this floor is applied ONLY to Tier 2 predictions below (and to
  # the Tier 2 empirical fallback), never to Tier 1. A real bug found
  # 2026-07-03: applying this floor globally (the previous behavior) silently
  # flattened every Tier 1 species whose genuinely differentiated, real
  # predicted probability happened to fall below the floor to the SAME
  # identical value -- invisible with a handful of well-separated candidates,
  # but very visible (and wrong) with a broader, more realistic candidate
  # pool where many real species legitimately have low individual
  # probabilities. `theta_epsilon` (the function argument, used for Tier 1)
  # is left untouched here; `theta_epsilon_floor` is the Tier-2-only raised
  # value.
  # ---------------------------------------------------------------------------
  theta_epsilon_floor <- theta_epsilon
  if (!is.null(undetected) && nrow(undetected) > 0 &&
      "undetected_type" %in% names(undetected)) {
    sm_rows <- undetected[
      !is.na(undetected$undetected_type) &
        undetected$undetected_type == "singleton_mirror" &
        !is.na(undetected$alpha) &
        !is.na(undetected$beta), , drop = FALSE
    ]
    if (nrow(sm_rows) > 0) {
      singleton_floor <- mean(sm_rows$alpha / (sm_rows$alpha + sm_rows$beta))
      if (singleton_floor > theta_epsilon_floor) {
        message(sprintf(
          "theta_epsilon (Tier 2 only) raised from %.2e to %.2e (mean singleton-mirror detection rate, n=%d mirrors). Tier 2 priors will not collapse to dark-diversity floor.",
          theta_epsilon_floor, singleton_floor, nrow(sm_rows)
        ))
        theta_epsilon_floor <- singleton_floor
      }
    }
  }

  # ---------------------------------------------------------------------------
  # Derive phi cap from taxon_name:grid_id random effect variance
  # ---------------------------------------------------------------------------
  # phi (= alpha + beta) is the effective sample size of the Beta prior.
  # When predicted theta is near 0 or 1, the delta-method variance is tiny
  # and phi explodes to astronomically large values even with a modest logit-SE.
  # We cap phi at 1 / grid_var, where grid_var is the taxon_name:grid_id
  # variance estimated during training. This is principled: the model itself
  # quantifies how much grid-level uncertainty exists, so the prior cannot
  # claim more certainty than that variance implies. No user input is needed.
  # glmmTMB stores a "taxon_name:grid_id" interaction random effect under
  # its VarCorr()$cond list keyed by the literal "taxon_name:grid_id" name
  # (a colon, matching the formula syntax) -- confirmed directly against a
  # real fitted glmmTMB model. An earlier version of this line used a
  # period, which never matches, so this phi cap silently never fired on
  # the package's own recommended formula (see CLAUDE.md's recommended
  # formula: "... + (1 | taxon_name:grid_id)") -- max_phi fell through to
  # NULL every time, and phi was instead capped only by the hardcoded 1000
  # fallback below, with no error or warning either way.
  grid_term <- paste0(taxon_col, ":grid_id")
  max_phi   <- tryCatch({
    vc  <- glmmTMB::VarCorr(model_obj$models$tier1)
    mat <- vc$cond[[grid_term]]
    if (!is.null(mat) && is.numeric(mat) && as.numeric(mat) > 0)
      1 / as.numeric(mat)
    else
      NULL
  }, error = function(e) NULL)

  if (!is.null(max_phi)) {
    if (min_phi > 0 && max_phi < min_phi) {
      message(sprintf(
        "Phi cap: %.4f (1 / grid variance %.4f) is below min_phi (%.1f); floor applies.",
        max_phi, 1 / max_phi, min_phi
      ))
    } else {
      message(sprintf(
        "Phi cap: %.4f (1 / grid variance %.4f). Min phi floor: %.1f.",
        max_phi, 1 / max_phi, min_phi
      ))
    }
  } else {
    # Fallback: cap phi at 1000 to prevent astronomically tight priors
    # when theta is near 0 or 1 and no grid_id variance is available.
    max_phi <- 1000
    message("No taxon_name:grid_id term found in Tier 1 model -- using fallback phi cap of 1000.")
  }

  taxa_tier1 <- model_obj$tiers$taxon_name[model_obj$tiers$tier == "tier1"]
  taxa_tier2 <- model_obj$tiers$taxon_name[model_obj$tiers$tier == "tier2"]

  message(sprintf(
    "Predicting %d Tier 1 + %d Tier 2 taxon_name at %d site-habitat rows...",
    length(taxa_tier1), length(taxa_tier2), nrow(new_sites)
  ))

  # ---------------------------------------------------------------------------
  # Scale covariates using TRAINING scale_params
  # ---------------------------------------------------------------------------
  sites_scaled <- new_sites
  extrap_flags <- rep(FALSE, nrow(new_sites))

  for (covariate in names(scale_params)) {
    if (!covariate %in% names(sites_scaled)) next
    center  <- scale_params[[covariate]]$center
    sc      <- scale_params[[covariate]]$scale
    if (sc == 0 || !is.finite(sc)) {
      warning(sprintf(
        "generate_full_priors: scale_params for '%s' has zero/non-finite scale; centering only.", covariate
      ))
      sc <- 1
    }
    scaled  <- (sites_scaled[[covariate]] - center) / sc
    sites_scaled[[paste0(covariate, "_s")]] <- scaled
    extrap_flags <- extrap_flags | (abs(scaled) > 3)
  }
  sites_scaled$extrapolation_warning <- extrap_flags

  if (any(extrap_flags)) {
    message(sprintf(
      "%d site-habitat row(s) have covariates outside training range (|z| > 3).",
      sum(extrap_flags)
    ))
  }

  # ---------------------------------------------------------------------------
  # Add habitat indicator columns required by Tier 1 formula
  # $supported and $indicators are positionally aligned (set during training).
  # Sites whose habitat is not in $supported get 0 for all indicators, which
  # is correct -- those habitats are covered by the fixed main_habitat effect.
  # ---------------------------------------------------------------------------
  hs <- model_obj$habitat_screening
  if (!is.null(hs) && length(hs$indicators) > 0) {
    for (i in seq_along(hs$indicators)) {
      sites_scaled[[hs$indicators[i]]] <-
        as.integer(sites_scaled[[habitat_col]] == hs$supported[i])
    }
  }

  # ---------------------------------------------------------------------------
  # Helper: moment-match (mean, variance) -> (alpha, beta)
  # ---------------------------------------------------------------------------
  moment_match <- function(m, v, epsilon, max_phi = NULL, min_phi = 0) {
    m        <- pmax(pmin(m, 1 - epsilon), epsilon)
    phi      <- m * (1 - m) / v - 1
    # Cap phi at the model-derived ceiling before checking for the fallback below.
    # This prevents astronomically tight priors when theta is near 0 or 1,
    # where m*(1-m) is tiny and phi explodes even with a modest logit-SE.
    if (!is.null(max_phi) && is.finite(max_phi))
      phi    <- pmin(phi, max_phi)
    # Floor: ensure phi never drops below min_phi. When the phi cap is very low
    # (high grid variance), unchecked phi produces alpha/beta so small that MC
    # posterior simulation is unstable and modelled priors become less informative
    # than dark-diversity fallbacks. The floor guarantees that species observed in
    # training data always have more informative priors than undetected species.
    # With min_phi > 0 (the generate_full_priors() default), this floor already
    # rescues every *finite* phi <= 0 case (the "too much variance" scenario) --
    # the fallback below can then only be reached via a non-finite phi (NA/NaN/Inf
    # propagated from an unusable SE), a narrower and rarer failure than a plain
    # large-but-finite variance. With min_phi = 0, the finite phi <= 0 case is
    # reachable again and hits the same fallback.
    if (min_phi > 0)
      phi    <- pmax(phi, min_phi)
    # phi <= 0, or non-finite (NA/NaN/Inf: a genuinely failed/unreliable SE
    # prediction for this row): the variance side of the moment-match is
    # unusable. Session 149 fix -- do NOT discard the mean `m` for an agnostic
    # Jeffreys mean of 0.5: `m` is usually still a valid, real point estimate
    # (glmmTMB's Wald SE computation can fail/return NaN for a specific
    # new-level combination even when the fixed+random-effect mean prediction
    # itself is fine), and 0.5 is wildly wrong for what a Tier 1/2 species
    # prediction almost always actually is -- a low-theta species, not a coin
    # flip. Fall back to a diffuse Beta AT THE SAME MEAN using min_phi as the
    # concentration (the same "informative-enough floor" value used
    # everywhere else in this function) when the mean is itself finite; only
    # degrade to a true, fully agnostic Jeffreys(0.5, 0.5) -- the standard
    # non-informative prior for a Bernoulli parameter (Jeffreys, 1946) -- when
    # even the mean is unusable (a total prediction failure, not just an
    # unreliable SE).
    jeffreys      <- phi <= 0 | !is.finite(phi)
    mean_usable   <- is.finite(m)
    fallback_conc <- if (min_phi > 0) min_phi else 1
    fb_mean       <- dplyr::if_else(mean_usable, m, 0.5)
    fb_conc       <- dplyr::if_else(mean_usable, fallback_conc, 1)
    alpha    <- dplyr::if_else(jeffreys, fb_mean * fb_conc, m * phi)
    beta     <- dplyr::if_else(jeffreys, (1 - fb_mean) * fb_conc, (1 - m) * phi)
    list(alpha = alpha, beta = beta, jeffreys_fallback = jeffreys)
  }

  # ---------------------------------------------------------------------------
  # Helper: delta-method back-transform from logit scale
  # logit(theta) ~ N(eta, se^2)
  # theta_mean ~ plogis(eta)  (approximate)
  # theta_var  ~ se^2 * (dlogis(eta))^2  (delta method)
  # ---------------------------------------------------------------------------
  backxform <- function(eta, se) {
    m <- stats::plogis(eta)
    # derivative of plogis: m * (1 - m)
    v <- se^2 * (m * (1 - m))^2
    list(mean = m, var = v)
  }

  # ---------------------------------------------------------------------------
  # Helper: attach effort_flag/n_obs -- identical in predict_tier() and
  # predict_tier_empirical(), factored out once rather than duplicated.
  # ---------------------------------------------------------------------------
  .assign_effort_flag <- function(grid) {
    if (has_n_total) {
      grid$effort_flag <- grid$n_total_at_site < effort_thr
      grid$n_obs       <- grid$n_total_at_site
    } else {
      grid$effort_flag <- NA
      grid$n_obs       <- NA_integer_
    }
    grid
  }

  # ---------------------------------------------------------------------------
  # Helper: observed_in_habitat lookup
  # Extract from tier2_empirical (reliable) and tier1 model frame (best effort)
  # ---------------------------------------------------------------------------
  observed_combos <- if (no_habitat) {
    tryCatch({
      t1_frame <- model_obj$models$tier1$frame
      resp_col <- t1_frame[[1]]
      n_sp     <- if (is.matrix(resp_col)) resp_col[, 1] else resp_col
      t1_obs   <- t1_frame[n_sp > 0, c(taxon_col), drop = FALSE]
      names(t1_obs) <- "taxon_name"
      t2_obs <- model_obj$tier2_empirical |>
        dplyr::select(dplyr::all_of(taxon_col)) |>
        dplyr::rename(taxon_name = !!taxon_sym)
      dplyr::bind_rows(t1_obs, t2_obs) |>
        dplyr::distinct() |>
        dplyr::mutate(observed_in_habitat = TRUE)
    }, error = function(e) {
      model_obj$tier2_empirical |>
        dplyr::select(dplyr::all_of(taxon_col)) |>
        dplyr::rename(taxon_name = !!taxon_sym) |>
        dplyr::distinct() |>
        dplyr::mutate(observed_in_habitat = TRUE)
    })
  } else {
    tryCatch({
      t1_frame <- model_obj$models$tier1$frame
      # response is cbind -- first column is n_taxon_name
      resp_col  <- t1_frame[[1]]
      if (is.matrix(resp_col)) {
        n_sp <- resp_col[, 1]
      } else {
        n_sp <- resp_col
      }
      t1_obs <- t1_frame[n_sp > 0, c(taxon_col, habitat_col), drop = FALSE]
      names(t1_obs) <- c("taxon_name", ".habitat")
      t2_obs <- model_obj$tier2_empirical |>
        dplyr::select(dplyr::all_of(c(taxon_col, habitat_col))) |>
        dplyr::rename(taxon_name = !!taxon_sym, .habitat = !!habitat_sym)
      dplyr::bind_rows(t1_obs, t2_obs) |>
        dplyr::distinct() |>
        dplyr::mutate(observed_in_habitat = TRUE)
    }, error = function(e) {
      # Fallback: tier2_empirical only
      model_obj$tier2_empirical |>
        dplyr::select(dplyr::all_of(c(taxon_col, habitat_col))) |>
        dplyr::rename(taxon_name = !!taxon_sym, .habitat = !!habitat_sym) |>
        dplyr::distinct() |>
        dplyr::mutate(observed_in_habitat = TRUE)
    })
  }

  # ---------------------------------------------------------------------------
  # Helper: predict one tier
  # ---------------------------------------------------------------------------
  predict_tier <- function(model, taxon_name_vec, tier_label, epsilon) {
    if (is.null(model) || length(taxon_name_vec) == 0) return(NULL)

    # Reduce to unique site rows before crossing -- sites_scaled is derived
    # from model_data which contains taxon_name (one row per taxon_name x site).
    # Drop taxon_name-level columns so crossing() produces taxon_name x site combos
    # without duplicate column names.
    # Detect Moran basis columns present in sites_scaled (B1, B2, ... BK)
    moran_cols <- grep("^B[0-9]+$", names(sites_scaled), value = TRUE)

    site_cols <- c("grid_id", habitat_col,
                   names(scale_params),
                   paste0(names(scale_params), "_s"),
                   hs$indicators,
                   moran_cols,
                   "extrapolation_warning",
                   "n_total_at_site")
    sites_unique <- sites_scaled |>
      dplyr::select(dplyr::any_of(site_cols)) |>
      dplyr::distinct()

    # Restore training factor levels onto habitat column so glmmTMB can predict
    # even if some levels are absent from new_sites (e.g. a habitat not present
    # in the prediction area). Without this, predict() errors on missing levels.
    training_levels <- tryCatch(
      levels(model$frame[[habitat_col]]),
      error = function(e) NULL
    )
    if (!is.null(training_levels) && habitat_col %in% names(sites_unique)) {
      sites_unique[[habitat_col]] <- factor(
        sites_unique[[habitat_col]],
        levels = training_levels
      )
    }

    # Filter sites with NA predictors BEFORE crossing to avoid large intermediate
    pred_cols <- c(habitat_col,
                   paste0(names(scale_params), "_s"),
                   moran_cols,
                   hs$indicators)
    site_pred_cols <- intersect(pred_cols, names(sites_unique))
    if (length(site_pred_cols) > 0L) {
      na_sites <- !stats::complete.cases(sites_unique[, site_pred_cols, drop = FALSE])
      if (any(na_sites)) {
        message(sprintf(
          "  %s: dropping %d site(s) with NA predictor values before crossing.",
          tier_label, sum(na_sites)
        ))
        sites_unique <- sites_unique[!na_sites, , drop = FALSE]
      }
    }

    grid <- tidyr::crossing(
      dplyr::tibble(!!taxon_col := taxon_name_vec),
      sites_unique
    )
    if (nrow(grid) == 0) {
      warning("generate_full_priors: no valid rows remain for ",
              tier_label, " after NA removal. Returning NULL.",
              call. = FALSE)
      return(NULL)
    }

    # Predict on link scale with SE
    pred <- tryCatch(
      stats::predict(model,
                     newdata          = grid,
                     type             = "link",
                     se.fit           = TRUE,
                     allow.new.levels = TRUE),
      error = function(e) {
        stop("generate_full_priors: prediction failed for ", tier_label,
             " model.\nError: ", conditionMessage(e))
      }
    )

    eta <- pred$fit
    se  <- pred$se.fit

    # Back-transform and moment-match to Beta parameters
    bt  <- backxform(eta, se)
    ab  <- moment_match(bt$mean, bt$var, epsilon, max_phi = max_phi,
                        min_phi = min_phi)

    grid$alpha              <- ab$alpha
    grid$beta               <- ab$beta
    grid$jeffreys_fallback  <- ab$jeffreys_fallback
    grid$model_tier         <- tier_label

    .assign_effort_flag(grid)
  }

  # ---------------------------------------------------------------------------
  # Helper: predict Tier 2 from empirical means (fallback when the Tier 2
  # GLMM did not fit -- e.g. a fixed-effect factor with a single level in
  # this training run). train_biodiversity_model() already documents this
  # scenario ("Tier 2 species will fall back to empirical means", its own
  # warning message) and computes $tier2_empirical for exactly this purpose,
  # but until now nothing downstream actually consumed it: predict_tier()
  # just returns NULL when model is NULL, so every Tier 2 species silently
  # vanished from the prior table instead of falling back.
  #
  # NOT spatially resolved: $tier2_empirical holds one theta_mean_emp/
  # theta_sd_emp per taxon_name x habitat (no grid_id), since there is no
  # spatial model to interpolate from -- every site sharing a habitat gets
  # the same empirical value. Only species x habitat combinations with at
  # least one positive detection in training data are covered (same filter
  # $tier2_empirical itself already applies); species with zero detections
  # get no row here, same as before this fallback existed -- they fall
  # through to generate_undetected_diversity()/join_priors()'s dark-diversity
  # handling instead, which is the correct mechanism for them.
  # ---------------------------------------------------------------------------
  predict_tier_empirical <- function(taxon_name_vec, tier_label, epsilon) {
    emp <- model_obj$tier2_empirical
    if (length(taxon_name_vec) == 0 || is.null(emp) || nrow(emp) == 0) return(NULL)

    emp <- emp[emp[[taxon_col]] %in% taxon_name_vec, , drop = FALSE]
    if (nrow(emp) == 0) return(NULL)

    site_cols <- c("grid_id", habitat_col, "n_total_at_site")
    sites_unique <- sites_scaled |>
      dplyr::select(dplyr::any_of(site_cols)) |>
      dplyr::distinct()

    # No habitat: tier2_empirical carries one row per taxon (no habitat/grid_id
    # dimension at all), so every prediction site gets the same taxon-level
    # empirical value -- a cross join, not a keyed join.
    grid <- if (no_habitat) {
      tidyr::crossing(emp, sites_unique)
    } else {
      dplyr::inner_join(emp, sites_unique, by = habitat_col)
    }
    if (nrow(grid) == 0) return(NULL)

    ab <- moment_match(grid$theta_mean_emp, grid$theta_sd_emp^2, epsilon,
                       max_phi = max_phi, min_phi = min_phi)

    grid$alpha                 <- ab$alpha
    grid$beta                  <- ab$beta
    grid$jeffreys_fallback     <- ab$jeffreys_fallback
    grid$model_tier            <- tier_label
    # Empirical means carry no covariate-based extrapolation to flag.
    grid$extrapolation_warning <- FALSE

    grid <- .assign_effort_flag(grid)
    grid |> dplyr::select(-theta_mean_emp, -theta_sd_emp, -n_detections)
  }

  # ---------------------------------------------------------------------------
  # Run predictions
  # ---------------------------------------------------------------------------
  t0_pred <- proc.time()[["elapsed"]]
  message("Generating priors...")
  # Tier 1 uses the base (un-raised) epsilon so genuinely low-but-real
  # probabilities stay differentiated; Tier 2 uses the raised floor so sparse
  # species don't collapse toward the dark-diversity floor. See the comment
  # above theta_epsilon_floor's derivation for why these must differ.
  result_t1 <- predict_tier(model_obj$models$tier1, taxa_tier1, "tier1",
                            epsilon = theta_epsilon)
  result_t2 <- predict_tier(model_obj$models$tier2, taxa_tier2, "tier2",
                            epsilon = theta_epsilon_floor)

  if (is.null(model_obj$models$tier2) && length(taxa_tier2) > 0) {
    message("Tier 2 model is not fitted -- falling back to per-species empirical ",
            "means ($tier2_empirical) instead of GLMM predictions for Tier 2 species.")
    result_t2 <- predict_tier_empirical(taxa_tier2, "tier2", epsilon = theta_epsilon_floor)
  }

  predictions <- dplyr::bind_rows(result_t1, result_t2)
  message(sprintf("Prior generation complete (%.1fs).",
                  proc.time()[["elapsed"]] - t0_pred))

  if (nrow(predictions) == 0) {
    stop("generate_full_priors: no predictions generated. ",
         "Check that model_obj contains fitted models.")
  }

  if (any(predictions$jeffreys_fallback, na.rm = TRUE)) {
    n_jf <- sum(predictions$jeffreys_fallback, na.rm = TRUE)
    warning(sprintf(
      "generate_full_priors: %d row(s) had an unusable prediction variance ",
      n_jf
    ), "(>= Bernoulli maximum, or a non-finite SE) and received a diffuse ",
    "fallback prior -- at the model's own predicted mean when that mean was ",
    "itself finite, or the fully agnostic Jeffreys Beta(0.5, 0.5) only when ",
    "it was not. This may indicate extrapolation beyond the training range.",
    call. = FALSE)
  }

  # ---------------------------------------------------------------------------
  # Habitat-observed-elsewhere flag
  # ---------------------------------------------------------------------------
  predictions <- if (no_habitat) {
    predictions |>
      dplyr::left_join(observed_combos, by = "taxon_name") |>
      dplyr::mutate(
        observed_in_habitat = tidyr::replace_na(observed_in_habitat, FALSE)
      )
  } else {
    predictions |>
      dplyr::rename(.habitat = !!habitat_sym) |>
      dplyr::left_join(observed_combos,
                       by = c("taxon_name", ".habitat")) |>
      dplyr::mutate(
        observed_in_habitat = tidyr::replace_na(
          observed_in_habitat, FALSE)
      ) |>
      dplyr::rename(!!habitat_col := .habitat)
  }

  # ---------------------------------------------------------------------------
  # Finalise columns
  # ---------------------------------------------------------------------------
  output_cols <- c("taxon_name", "grid_id", habitat_col,
                   "alpha", "beta", "theta_mean", "theta_sd",
                   "n_obs", "model_tier", "effort_flag",
                   "observed_in_habitat",
                   "extrapolation_warning",
                   "undetected_type",
                   "source_taxon_name",
                   "jeffreys_fallback")

  predictions <- predictions |>
    dplyr::mutate(
      taxon_name        = !!taxon_sym,
      theta_mean        = .beta_mean(alpha, beta),
      theta_sd          = .beta_sd(alpha, beta),
      undetected_type   = NA_character_,
      source_taxon_name = NA_character_
    ) |>
    dplyr::select(dplyr::all_of(output_cols))

  # ---------------------------------------------------------------------------
  # Append undetected diversity priors
  # source_taxon_name is retained here so it survives into taxaexpect_priors
  # and can be used for taxonomy lookup in Issue 3 (dark diversity groups).
  # ---------------------------------------------------------------------------
  if (!is.null(undetected) && nrow(undetected) > 0) {
    undetected_out <- undetected |>
      dplyr::mutate(
        effort_flag           = FALSE,
        observed_in_habitat   = FALSE,
        extrapolation_warning = FALSE,
        jeffreys_fallback     = FALSE
      ) |>
      dplyr::select(dplyr::all_of(output_cols))
    predictions <- dplyr::bind_rows(predictions, undetected_out)
  }

  n_mod    <- sum(!is.na(predictions$taxon_name))
  n_undet  <- sum(is.na(predictions$taxon_name))
  message(sprintf(
    "--- Priors complete: %d modelled rows, %d undetected rows, %d total ---",
    n_mod, n_undet, nrow(predictions)
  ))

  # Propagate the training grid resolution (set by create_sites_from_grid(),
  # carried through model_obj$meta) so a downstream consumer that only has
  # this output (e.g. plot_theta_map_interactive()) can read the real cell
  # half-width instead of inferring it from whichever grid_ids happen to be
  # present in a later, possibly-filtered selection.
  if (!is.null(model_obj$meta$grid_size)) {
    attr(predictions, "grid_size") <- model_obj$meta$grid_size
  }

  predictions
}
