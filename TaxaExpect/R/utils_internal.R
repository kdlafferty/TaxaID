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
