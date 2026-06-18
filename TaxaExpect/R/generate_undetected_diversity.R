#' Generate Priors for Undetected Species
#'
#' Constructs Beta(alpha, beta) prior objects for species that are plausibly
#' present in the regional pool but were not recorded anywhere in the dataset
#' (Tier 3 species). Two sources of priors are generated:
#'
#' 1. **Singleton mirrors**: For each single-detection species (a species
#'    observed exactly once across all samples in the dataset), one anonymous
#'    undetected species proxy is created, inheriting the singleton's habitat,
#'    location, and theta. The rationale is that locations and habitats with
#'    many single-detection species indicate high undetected diversity.
#'    (Note: "singleton" here refers to detection frequency, not to
#'    "singleton sequences" in TaxaLikely, which are reference sequences
#'    with no within-species neighbours.)
#'
#' 2. **Global floor prior**: A single effort-based prior always included
#'    regardless of whether singletons are present:
#'    theta = 1 / N_total, parameterized as Beta(1, N_total - 1).
#'    This ensures TaxaAssign always has at least one undetected competitor.
#'
#' @param model_obj A biofreq_model object. Output of
#'   train_biodiversity_model().
#' @param jeffreys_threshold Integer. If N_total is below this value, use a
#'   Jeffreys prior Beta(0.5, 0.5) for the global floor instead of
#'   Beta(1, N_total - 1). Default 2.
#' @param singleton_ess Integer. Effective sample size used for moment-matching
#'   singleton mirror priors. Controls how tightly the prior is concentrated
#'   around the observed singleton theta: \code{alpha = theta_obs * singleton_ess},
#'   \code{beta = (1 - theta_obs) * singleton_ess}. A small value (default 2)
#'   produces a diffuse prior appropriate for a species seen exactly once.
#'
#' @return A tibble with one row per undetected species proxy, containing:
#'   \describe{
#'     \item{taxon_name}{Always NA -- proxies have no taxonomic identity.}
#'     \item{grid_id}{Grid cell identifier inherited from singleton source, or
#'       NA for the global floor.}
#'     \item{habitat}{Habitat inherited from singleton source, or NA for
#'       global floor.}
#'     \item{alpha}{Alpha parameter of Beta(alpha, beta) prior.}
#'     \item{beta}{Beta parameter of Beta(alpha, beta) prior.}
#'     \item{theta_mean}{Derived: alpha / (alpha + beta).}
#'     \item{theta_sd}{Derived: SD of Beta(alpha, beta).}
#'     \item{n_obs}{Total community count N at the source cell, or N_total
#'       for the global floor.}
#'     \item{model_tier}{Always "tier3_undetected".}
#'     \item{undetected_type}{Character: "singleton_mirror" or
#'       "global_floor".}
#'     \item{source_taxon_name}{Taxon name of the singleton source, or NA for
#'       the global floor. For auditing only -- not passed to TaxaAssign.}
#'   }
#'
#' @details
#' **Alpha/beta conversion from observed theta:**
#' For singleton mirrors, the observed theta (n=1 / N) is converted to
#' Beta parameters using a moment-matching approach with a fixed effective
#' sample size (ESS). The ESS controls how tightly the prior is concentrated
#' around the observed theta:
#' \preformatted{
#'   alpha = theta_obs * ESS
#'   beta  = (1 - theta_obs) * ESS
#' }
#' A small ESS (default 2) produces a weak, diffuse prior appropriate for a
#' species seen exactly once. This is intentionally conservative -- we have
#' very little information about a singleton's true theta.
#'
#' **Global floor:**
#' Beta(1, N_total - 1) places the prior mean at 1/N_total, equivalent to
#' the theta expected if an undetected species appeared exactly once across
#' all sampling effort. This is always smaller than any singleton-derived
#' theta in a well-sampled dataset.
#'
#' **No singletons:**
#' If the dataset contains no singletons (as is common when rare species
#' have already been filtered upstream), only the global floor prior is
#' returned. This is the minimum viable undetected pool.
#'
#' **Taxonomic-group dilution (known limitation):**
#' N_total is computed across all taxa in the model regardless of taxonomic
#' group. When a marker captures groups of very different sizes (e.g. ~800
#' fish + ~20 mammals on a 12S marker), the global floor Beta(1, N_total - 1)
#' is diluted by the dominant group. For a mammal query the floor prior would
#' be Beta(1, 819) rather than the group-appropriate Beta(1, 19), making
#' unmodelled mammals appear ~41x less likely than they should be relative to
#' the mammal species pool. In practice the impact is modest: (1) modelled
#' species priors come from the Tier 1/2 model and are unaffected; (2) the
#' dark_mean used for modelled-species floor promotion is dominated by
#' singleton mirrors which are themselves group-weighted; and (3) minority-group
#' queries are typically rare on group-biased markers. If accurate dark
#' diversity priors are needed across multiple taxonomic groups of very
#' different sizes, run separate models per group and stack the prior tables.
#'
#' @seealso \code{train_biodiversity_model()}, \code{generate_full_priors()}
#'
#' @examples
#' \dontrun{
#' dark_priors <- generate_undetected_diversity(model_fit)
#' head(dark_priors)
#' }
#'
#' @importFrom dplyr mutate select tibble bind_rows
#' @export

generate_undetected_diversity <- function(model_obj,
                                          jeffreys_threshold = 2L,
                                          singleton_ess      = 2L) {

  # --- Input checks -----------------------------------------------------------
  if (!inherits(model_obj, "biofreq_model")) {
    stop("generate_undetected_diversity: model_obj must be a biofreq_model ",
         "object from train_biodiversity_model().")
  }

  N_total     <- model_obj$N_total
  singletons  <- model_obj$singletons
  habitat_col <- model_obj$meta$habitat_col

  if (N_total <= 0) {
    stop("generate_undetected_diversity: N_total is zero or negative. ",
         "Check that train_biodiversity_model() ran successfully.")
  }

  # --- Helper: beta mean and SD from alpha/beta --------------------------------
  beta_mean <- function(a, b) a / (a + b)
  beta_sd   <- function(a, b) sqrt((a * b) / ((a + b)^2 * (a + b + 1)))

  # --- 1. Singleton mirrors ----------------------------------------------------
  proxy_rows <- list()

  if (nrow(singletons) == 0) {
    message(
      "generate_undetected_diversity: no singletons found in model_obj$singletons.\n",
      "Only the global floor prior will be generated.\n",
      "If this is unexpected, check that full_data was passed to ",
      "train_biodiversity_model() and that it contains pre-filter observations."
    )
  } else {
    message(sprintf(
      "Generating %d singleton mirror(s) (ESS = %d)...",
      nrow(singletons), singleton_ess
    ))

    for (i in seq_len(nrow(singletons))) {
      row        <- singletons[i, ]
      theta_obs  <- row$theta_obs

      # Guard against NA or boundary theta values
      if (is.na(theta_obs) || theta_obs <= 0 || theta_obs >= 1) {
        warning(sprintf(
          "generate_undetected_diversity: singleton '%s' has theta_obs = %s. ",
          row[[model_obj$meta$taxon_col]],
          ifelse(is.na(theta_obs), "NA", round(theta_obs, 6))
        ), "Skipping this singleton mirror.", call. = FALSE)
        next
      }

      # Moment-matching: alpha = theta * ESS, beta = (1 - theta) * ESS.
      # ESS = 2 is the minimum that produces a proper unimodal Beta.
      # Higher values (5-10) concentrate the prior more tightly around
      # the observed singleton theta; use only if you have external
      # evidence that undetected species have similar detectability to
      # observed singletons.
      alpha_i <- theta_obs * singleton_ess
      beta_i  <- (1 - theta_obs) * singleton_ess

      proxy_tbl <- tibble::tibble(
        taxon_name        = NA_character_,
        grid_id           = row$grid_id,
        alpha             = alpha_i,
        beta              = beta_i,
        theta_mean        = beta_mean(alpha_i, beta_i),
        theta_sd          = beta_sd(alpha_i, beta_i),
        n_obs             = row$n_total_at_site,
        model_tier        = "tier3_undetected",
        undetected_type   = "singleton_mirror",
        source_taxon_name = as.character(row[[model_obj$meta$taxon_col]])
      )
      proxy_tbl[[habitat_col]] <- row[[habitat_col]]
      proxy_rows[[i]] <- proxy_tbl
    }

    n_generated <- sum(!sapply(proxy_rows, is.null))
    message(sprintf("%d singleton mirror(s) generated.", n_generated))
  }

  # --- 2. Global floor prior --------------------------------------------------
  message("Generating global floor prior...")

  if (N_total < jeffreys_threshold) {
    # Jeffreys prior for very small N_total
    alpha_floor <- 0.5
    beta_floor  <- 0.5
    message(sprintf(
      "N_total (%d) below jeffreys_threshold (%d): using Jeffreys prior Beta(0.5, 0.5).",
      N_total, jeffreys_threshold
    ))
  } else {
    # Beta(1, N-1): posterior of a uniform Beta(1,1) prior updated with
    # 0 successes in N-1 trials. Places the prior mean at 1/N_total,
    # the expected theta if an undetected species appeared exactly once
    # across all sampling effort. A principled lower bound.
    alpha_floor <- 1
    beta_floor  <- N_total - 1
  }

  global_floor <- tibble::tibble(
    taxon_name        = NA_character_,
    grid_id           = NA_character_,
    alpha             = alpha_floor,
    beta              = beta_floor,
    theta_mean        = beta_mean(alpha_floor, beta_floor),
    theta_sd          = beta_sd(alpha_floor, beta_floor),
    n_obs             = N_total,
    model_tier        = "tier3_undetected",
    undetected_type   = "global_floor",
    source_taxon_name = NA_character_
  )
  global_floor[[habitat_col]] <- NA_character_

  # --- 3. Combine and return --------------------------------------------------
  proxy_list <- Filter(Negate(is.null), proxy_rows)
  result <- dplyr::bind_rows(c(proxy_list, list(global_floor)))

  message(sprintf(
    "--- Undetected diversity complete: %d singleton mirror(s) + 1 global floor = %d proxies ---",
    length(proxy_list), nrow(result)
  ))

  return(result)
}
