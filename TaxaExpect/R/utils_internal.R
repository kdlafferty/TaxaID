# ==============================================================================
# Shared internal helpers used by multiple exported functions in this
# package: beta_mean()/beta_sd(), the genus/family/order/class/phylum
# rank-column vector used to join taxonomy onto proxy prior rows, and the
# equirectangular-approximation distance formula shared by the kernel-prior
# machinery.
# ==============================================================================

#' Approximate planar distance in km between two lat/lon points
#'
#' The equirectangular approximation
#' \code{111 * sqrt(dlat^2 + (dlon * cos(ref_lat))^2)} used throughout this
#' package's kernel machinery: cheap, vectorized, and accurate enough at the
#' spatial scales these kernels operate over (lambda_km on the order of tens
#' to a few hundred km) -- it is NOT a substitute for a true geodesic
#' distance at scales where the flat-earth/small-angle assumption breaks
#' down (roughly, more than a few hundred km, or near the poles where a
#' degree of longitude is a very different physical distance depending on
#' exactly which latitude the \code{cos()} is evaluated at).
#'
#' Longitude difference is wrapped to \code{(-180, 180]} before the formula
#' is applied, so a pair straddling the antimeridian is measured as the
#' short way around, not the long way: lon 179.9 and lon -179.9 are ~22 km
#' apart in reality (and under this wrap), not the ~40,000 km a naive
#' \code{lon1 - lon2} would compute. Without the wrap, a kernel weight
#' \code{exp(-d_km / lambda_km)} on a real antimeridian pair underflows to
#' effectively zero (a record right next to the site reads as having none of
#' its evidence), or, at a small enough \code{lambda_km}, every weight in
#' the whole call underflows to exactly zero and the caller has no evidence
#' left to work with at all.
#'
#' @param lat1,lon1,lat2,lon2 Numeric (vectorized; must be mutually
#'   conformable, i.e. recyclable against each other the way any vectorized
#'   arithmetic in R is). Degrees.
#' @param ref_lat Numeric (vectorized; conformable with the above). The
#'   latitude, in degrees, at which the longitude-degree-to-km conversion
#'   factor \code{cos(ref_lat)} is evaluated. Callers differ on what they
#'   pass here (the site's own latitude, a block's reference latitude, ...);
#'   this function does not choose one for you, to keep every call site's
#'   existing behaviour identical away from the antimeridian.
#' @return Numeric vector of approximate distances in km.
#' @noRd
.approx_distance_km <- function(lat1, lon1, lat2, lon2, ref_lat) {
  dlat <- lat1 - lat2
  dlon <- ((lon1 - lon2 + 180) %% 360) - 180
  111 * sqrt(dlat^2 + (dlon * cos(ref_lat * pi / 180))^2)
}

#' Beta distribution mean from alpha/beta
#' @param a,b Numeric vectors. Beta shape parameters.
#' @return Numeric vector.
#' @noRd
.beta_mean <- function(a, b) a / (a + b)

#' Beta distribution SD from alpha/beta
#' @param a,b Numeric vectors. Beta shape parameters.
#' @return Numeric vector.
#' @noRd
.beta_sd <- function(a, b) sqrt((a * b) / ((a + b)^2 * (a + b + 1)))

#' Rank columns used to join taxonomy onto anonymous/named proxy prior rows
#'
#' Deliberately excludes \code{kingdom} (rarely useful for grouping proxy
#' rows) and \code{species} (proxy rows never carry a species-level identity
#' -- either \code{taxon_name} is NA (dark-diversity proxies) or the row's
#' species-level name IS \code{taxon_name} already, not a separate rank
#' column). Ordered finest to coarsest, matching the order both consumers
#' use.
#' @noRd
.dark_diversity_rank_cols <- c("genus", "family", "order", "class", "phylum")

#' Record weights for the habitat stratum, counting unplaceable records
#'
#' The stratum filter every kernel-path function shares. With
#' `habitat_levels = NULL` (and `habitat_weights = NULL`) a record is kept
#' only when its habitat label equals `site_habitat`, at weight 1. With both
#' supplied, a record whose label is not one of the scheme's declared
#' habitats (`NA`, `""`, `"Uncertain"`, any sentinel) is UNPLACEABLE and is
#' kept at its taxon's own probability of occupying `site_habitat`, read
#' from `habitat_weights[[site_habitat]]`; a record in a different declared
#' habitat is excluded as before. A taxon with no weight contributes nothing
#' and is counted in `$n_no_weight`. The closed-world test is the one
#' `generate_uncertain_habitat_evidence()` uses, for the same reason: this
#' package must not track a habitat producer's sentinel vocabulary.
#'
#' @param hab Character vector of habitat labels, one per record.
#' @param taxa Character vector of taxon names, one per record.
#' @param site_habitat,habitat_levels,habitat_weights As documented on
#'   [estimate_kernel_priors()].
#' @param caller Character. Function name for messages.
#' @return A list: `keep` (logical, per record), `weight` (numeric, per
#'   record; 1 for stratum records, the taxon weight for unplaceable ones,
#'   0 otherwise), `lookup` (the two-column weight table actually used, or
#'   `NULL`), `n_unplaceable` (records counted), `n_no_weight` (unplaceable
#'   records left out for want of a weight), `n_taxa_no_weight`.
#' @noRd
.habitat_record_weights <- function(hab, taxa, site_habitat, habitat_levels,
                                    habitat_weights, caller) {
  hab <- as.character(hab)
  in_stratum <- !is.na(hab) & hab == site_habitat
  if (is.null(habitat_levels) && is.null(habitat_weights)) {
    return(list(keep = in_stratum, weight = as.numeric(in_stratum), lookup = NULL,
                n_unplaceable = 0L, n_no_weight = 0L, n_taxa_no_weight = 0L))
  }
  if (is.null(habitat_levels) || is.null(habitat_weights)) {
    stop(sprintf(
      "%s: supply `habitat_levels` and `habitat_weights` together, or neither. Unplaceable-habitat records are counted only at their taxon's habitat weight, never at full weight.",
      caller), call. = FALSE)
  }
  if (!is.character(habitat_levels) || length(habitat_levels) == 0L ||
      anyNA(habitat_levels) || !all(nzchar(trimws(habitat_levels)))) {
    stop(sprintf("%s: `habitat_levels` must be a non-empty character vector of the scheme's habitat names.", caller), call. = FALSE)
  }
  if (!site_habitat %in% habitat_levels) {
    stop(sprintf("%s: site_habitat '%s' is not one of `habitat_levels` (%s).",
                 caller, site_habitat, paste(habitat_levels, collapse = ", ")), call. = FALSE)
  }
  if (!is.data.frame(habitat_weights) || !"taxon_name" %in% names(habitat_weights) ||
      !site_habitat %in% names(habitat_weights)) {
    stop(sprintf(
      "%s: `habitat_weights` must be a data frame with a `taxon_name` column and a '%s' column (TaxaHabitat::build_habitat_lookup() output).",
      caller, site_habitat), call. = FALSE)
  }
  lk <- habitat_weights[!duplicated(habitat_weights$taxon_name), c("taxon_name", site_habitat), drop = FALSE]
  hv <- as.numeric(lk[[site_habitat]])
  if (any(!is.na(hv) & (hv < 0 | hv > 1))) {
    stop(sprintf("%s: `habitat_weights[['%s']]` has value(s) outside [0, 1].", caller, site_habitat), call. = FALSE)
  }
  unplaceable <- is.na(hab) | !nzchar(trimws(hab)) | !(hab %in% habitat_levels)
  odd <- unique(hab[unplaceable & !is.na(hab) & nzchar(trimws(hab)) &
                      !tolower(trimws(hab)) %in% c("uncertain", "unknown", "unassigned", "na")])
  if (length(odd)) {
    warning(sprintf(
      "%s: %d habitat label(s) are not in `habitat_levels` and are being counted as UNPLACEABLE: %s. If any is a real habitat, add it to `habitat_levels`.",
      caller, length(odd), paste(utils::head(odd, 10), collapse = ", ")), call. = FALSE)
  }
  h <- hv[match(as.character(taxa), lk$taxon_name)]
  w <- ifelse(in_stratum, 1, ifelse(unplaceable & !is.na(h), h, 0))
  no_w <- unplaceable & is.na(h)
  list(keep = w > 0, weight = w, lookup = lk,
       n_unplaceable = sum(unplaceable & !is.na(h) & h > 0),
       n_no_weight = sum(no_w), n_taxa_no_weight = length(unique(taxa[no_w])))
}
