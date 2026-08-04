# ==============================================================================
# Shared internal helpers used by multiple exported functions in this package.
# Consolidated here (code-review response, 2026-08-04) to close out three
# separate instances of the same duplication flagged in inst/taxaexpect_review.Rmd:
#   - beta_mean()/beta_sd() were reimplemented identically in
#     generate_full_priors.R, generate_undetected_diversity.R, and
#     generate_domestic_food_priors.R.
#   - A grid_id-string-to-centroid parser was reimplemented (with two
#     different internal approaches) in compute_moran_basis.R and
#     plot_theta_map_interactive.R.
#   - The genus/family/order/class/phylum rank-column vector used to join
#     taxonomy onto proxy prior rows was reimplemented identically in
#     generate_undetected_diversity.R and generate_domestic_food_priors.R.
# ==============================================================================

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
#' historically used.
#' @noRd
.dark_diversity_rank_cols <- c("genus", "family", "order", "class", "phylum")

#' Parse a TaxaExpect grid_id string to centroid lat/lon
#'
#' Format: \code{"Grid_{lat_int}p{lat_dec}_{m}{lon_int}p{lon_dec}"}, where
#' \code{"p"} encodes a decimal point and a leading \code{"m"} encodes a
#' negative sign (see \code{\link{create_sites_from_grid}}).
#'
#' Uses \code{sub()} rather than \code{regmatches(regexpr(...))}: the latter
#' silently DROPS any element with no match (e.g. \code{NA} input) instead of
#' returning \code{NA}, which would desync the parsed lat/lon vectors' length
#' from \code{grid_id}'s own length whenever any input is \code{NA} or
#' malformed. \code{sub()} always preserves length (an \code{NA} input stays
#' \code{NA} in place).
#'
#' @param grid_id Character vector of grid_id strings.
#' @return A data frame with columns \code{lat}, \code{lon} (numeric, same
#'   length as \code{grid_id}; \code{NA} for unparseable entries).
#' @noRd
.parse_grid_id_coords <- function(grid_id) {
  x         <- sub("^Grid_", "", grid_id)
  parts     <- sub("_.*$", "", x)
  lon_parts <- sub("^[^_]+_", "", x)

  parse_coord <- function(s) {
    neg <- startsWith(s, "m")
    s   <- sub("^m", "", s)
    s   <- gsub("p", ".", s, fixed = TRUE)
    val <- suppressWarnings(as.numeric(s))
    ifelse(neg, -val, val)
  }

  data.frame(
    lat = parse_coord(parts),
    lon = parse_coord(lon_parts),
    stringsAsFactors = FALSE
  )
}
