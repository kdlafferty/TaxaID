utils::globalVariables(c(
  "inat_range_elevated"
))

#' Elevate priors for iNaturalist range-supported unobserved taxa
#'
#' For unobserved eDNA candidates (taxa detected by BLAST but absent from the
#' regional occurrence database), promotes any taxon that (a) falls within its
#' iNaturalist geomodel range polygon at the study site and (b) has sufficient
#' iNaturalist observation coverage to treat the polygon as reliable, from its
#' current group prior up to the Tier 2 singleton-mirror floor.
#'
#' @details
#' \strong{Superseded for the mixture pathway (2026-08-28):} workflows using
#' \code{TaxaExpect::apply_undetected_evidence()} should feed iNat evidence
#' through \code{TaxaExpect::generate_inat_range_evidence()} instead, so it
#' shares the anchors, moment-matched concentration, and multi-source
#' combination of the other evidence channels rather than this function's
#' post-join binary elevation. This function remains for workflows not yet on
#' the shared applier.
#'
#' Evidence from the iNaturalist range polygon is asymmetric: \code{in_range =
#' TRUE} is positive corroboration and warrants a prior boost; \code{in_range =
#' FALSE} is weak evidence (false negatives are common for aquatic taxa with low
#' iNaturalist observer effort) and must NOT suppress priors. This function
#' implements that asymmetry: only \code{in_range = TRUE} taxa are touched.
#'
#' The elevation target is the Tier 2 singleton-mirror floor — the mean
#' \code{alpha}/\code{beta} across singleton-mirror rows in
#' \code{taxaexpect_priors} at the focal site × habitat. This is already
#' computed by \code{join_priors()} and stored as \code{singleton_alpha} /
#' \code{singleton_beta} columns in \code{likelihoods_ready}. The interpretation
#' is: a range-supported unobserved taxon is treated as equivalent to a species
#' observed exactly once in the regional database.
#'
#' Only unmodelled rows (\code{is.na(alpha)}) are eligible for elevation.
#' Modelled rows (those with a TaxaExpect prior) are never modified. The
#' elevation is also guarded: if a taxon's current prior already exceeds the
#' singleton floor (which can occur in high-singleton clades), the prior is
#' left unchanged.
#'
#' @param likelihoods_ready Data frame. Output of \code{join_priors()}. Must
#'   contain \code{taxon_name}, \code{alpha}, \code{prior_alpha},
#'   \code{prior_beta}, \code{prior_mean}, \code{singleton_alpha},
#'   \code{singleton_beta}.
#' @param inat_range Data frame. Output of
#'   \code{TaxaFetch::check_inat_range()}. Must contain \code{taxon_name},
#'   \code{in_range}, \code{n_observations}.
#' @param require_name_match Logical, default \code{TRUE}. Exclude rows whose
#'   resolved iNat name (\code{name_match} column, \code{check_inat_range()}
#'   2026-08-28+) differs from the query or cannot be verified -- iNat's
#'   fuzzy text search can silently resolve a query to a different species,
#'   and an elevation must never ride on a misresolved name.
#' @param n_obs_threshold Integer. Minimum iNaturalist observation count
#'   required for the range polygon to be considered reliable. Default 500.
#'   Set higher for less-observed taxonomic groups. Taxa below this threshold
#'   are not elevated even if \code{in_range = TRUE}.
#' @param verbose Logical. If TRUE, reports the number of taxa and rows
#'   elevated. Default FALSE (a summary is always emitted via
#'   \code{cli::cli_inform}).
#' @return \code{likelihoods_ready} with \code{prior_alpha}, \code{prior_beta},
#'   and \code{prior_mean} elevated to the Tier 2 singleton-mirror floor for
#'   qualifying taxa. Adds a logical column \code{inat_range_elevated} (TRUE
#'   for elevated rows, FALSE otherwise).
#' @seealso \code{join_priors()}, \code{TaxaFetch::check_inat_range()},
#'   \code{compute_posterior()}
#' @examples
#' likelihoods_ready <- data.frame(
#'   taxon_name      = c("Species alpha", "Species beta"),
#'   alpha           = c(NA, 5), # NA = unmodelled
#'   prior_alpha     = c(1, 5),
#'   prior_beta      = c(99, 15),
#'   prior_mean      = c(0.01, 0.25),
#'   singleton_alpha = c(2, 2),
#'   singleton_beta  = c(18, 18)
#' )
#' inat_range <- data.frame(
#'   taxon_name = c("Species alpha", "Species beta"),
#'   in_range = c(TRUE, FALSE),
#'   n_observations = c(800, 5)
#' )
#' adjust_inat_range_priors(likelihoods_ready, inat_range, n_obs_threshold = 500L)
#' @export
adjust_inat_range_priors <- function(
  likelihoods_ready,
  inat_range,
  n_obs_threshold = 500L,
  require_name_match = TRUE,
  verbose = FALSE
) {
  # --- Input validation -------------------------------------------------------
  if (!is.data.frame(likelihoods_ready)) {
    cli::cli_abort("{.arg likelihoods_ready} must be a data frame.")
  }
  needed_lr <- c(
    "taxon_name", "alpha", "prior_alpha", "prior_beta",
    "prior_mean", "singleton_alpha", "singleton_beta"
  )
  missing_lr <- setdiff(needed_lr, names(likelihoods_ready))
  if (length(missing_lr) > 0L) {
    cli::cli_abort(c(
      "{.arg likelihoods_ready} is missing column(s): {.field {missing_lr}}.",
      "i" = "Ensure this is the unmodified output of {.fn join_priors}."
    ))
  }
  if (!is.data.frame(inat_range)) {
    cli::cli_abort("{.arg inat_range} must be a data frame.")
  }
  if (nrow(inat_range) == 0L) {
    likelihoods_ready$inat_range_elevated <- FALSE
    cli::cli_inform("adjust_inat_range_priors: inat_range is empty; nothing elevated.")
    return(likelihoods_ready)
  }
  needed_ir <- c("taxon_name", "in_range", "n_observations")
  missing_ir <- setdiff(needed_ir, names(inat_range))
  if (length(missing_ir) > 0L) {
    cli::cli_abort(c(
      "{.arg inat_range} is missing column(s): {.field {missing_ir}}.",
      "i" = "Ensure this is the output of {.fn TaxaFetch::check_inat_range}."
    ))
  }
  if (!is.numeric(n_obs_threshold) || length(n_obs_threshold) != 1L ||
    is.na(n_obs_threshold) || n_obs_threshold < 0) {
    cli::cli_abort("{.arg n_obs_threshold} must be a single non-negative number.")
  }

  # --- Initialise output column -----------------------------------------------
  likelihoods_ready$inat_range_elevated <- FALSE

  # --- Identify unmodelled rows (received group prior or floor) ---------------
  is_unmod <- is.na(likelihoods_ready$alpha)

  if (!any(is_unmod, na.rm = TRUE)) {
    cli::cli_inform("adjust_inat_range_priors: no unmodelled rows found; nothing elevated.")
    return(likelihoods_ready)
  }

  # --- Qualifying taxa: in_range = TRUE, n_observations >= threshold ----------
  qualifies <- !is.na(inat_range$in_range) & inat_range$in_range == TRUE &
    !is.na(inat_range$n_observations) & inat_range$n_observations >= n_obs_threshold

  # Fuzzy-match gate (2026-08-28): check_inat_range() resolves a query by best
  # TEXT match, so in_range = TRUE can describe a DIFFERENT species (real case:
  # Gasterosteus gymnurus -> G. aculeatus). An elevation must never ride on a
  # misresolved name; rows without a verified name_match are excluded by
  # default. Older inat_range tables lacking the column are wholly unverifiable
  # -- excluded with guidance to re-run the check.
  if (isTRUE(require_name_match)) {
    if (!"name_match" %in% names(inat_range)) {
      cli::cli_inform(c(
        "adjust_inat_range_priors: {.arg inat_range} has no {.field name_match} column (pre-2026-08-28 output) -- nothing elevated.",
        "i" = "Re-run {.fn TaxaFetch::check_inat_range} to get the column, or pass require_name_match = FALSE with a reviewed name mapping."
      ))
      qualifies <- qualifies & FALSE
    } else {
      n_dropped <- sum(qualifies & !(inat_range$name_match %in% TRUE))
      if (n_dropped > 0L) {
        cli::cli_inform(
          "adjust_inat_range_priors: {n_dropped} in-range taxon/taxa excluded -- resolved iNat name differs from the query (fuzzy-match risk)."
        )
      }
      qualifies <- qualifies & (inat_range$name_match %in% TRUE)
    }
  }
  qualifying_names <- inat_range$taxon_name[qualifies]

  if (length(qualifying_names) == 0L) {
    cli::cli_inform(
      "adjust_inat_range_priors: no taxa meet in_range = TRUE with n_observations >= {n_obs_threshold}; nothing elevated."
    )
    return(likelihoods_ready)
  }

  # --- Rows to elevate --------------------------------------------------------
  # Conditions: unmodelled, taxon in qualifying set, singleton floor available,
  # and the floor actually exceeds the current prior (guard for high-singleton clades).
  singleton_floor <- .beta_mean(
    likelihoods_ready$singleton_alpha,
    likelihoods_ready$singleton_beta
  )

  elevate_mask <- is_unmod &
    likelihoods_ready$taxon_name %in% qualifying_names &
    !is.na(likelihoods_ready$singleton_alpha) &
    !is.na(likelihoods_ready$singleton_beta) &
    !is.na(likelihoods_ready$prior_mean) &
    singleton_floor > likelihoods_ready$prior_mean

  n_rows <- sum(elevate_mask, na.rm = TRUE)
  n_taxa <- length(unique(likelihoods_ready$taxon_name[
    elevate_mask & !is.na(likelihoods_ready$taxon_name)
  ]))

  if (n_rows == 0L) {
    cli::cli_inform(
      "adjust_inat_range_priors: qualifying taxa found but no rows needed elevation (singleton floor already met or exceeded)."
    )
    return(likelihoods_ready)
  }

  # --- Apply elevation --------------------------------------------------------
  likelihoods_ready$prior_alpha[elevate_mask] <- likelihoods_ready$singleton_alpha[elevate_mask]
  likelihoods_ready$prior_beta[elevate_mask] <- likelihoods_ready$singleton_beta[elevate_mask]
  likelihoods_ready$prior_mean[elevate_mask] <-
    .beta_mean(
      likelihoods_ready$prior_alpha[elevate_mask],
      likelihoods_ready$prior_beta[elevate_mask]
    )
  likelihoods_ready$inat_range_elevated[elevate_mask] <- TRUE

  cli::cli_inform(
    "adjust_inat_range_priors: elevated {n_taxa} unobserved taxon/taxa ({n_rows} row(s)) to Tier 2 singleton-mirror floor (n_observations >= {n_obs_threshold})."
  )

  likelihoods_ready
}
