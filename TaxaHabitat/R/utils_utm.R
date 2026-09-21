# ==============================================================================
# utils_utm.R
# TaxaHabitat -- local equal-distance projection helper
# ==============================================================================

#' Pick a Local UTM CRS for a Set of Points
#'
#' Returns the EPSG code of the UTM zone containing the centroid of \code{x},
#' for use as a local equal-distance projection when buffering or measuring
#' distances in metres.
#'
#' @details
#' Distances and buffers must not be computed in EPSG:3857 (Web Mercator):
#' Mercator inflates true ground distance by \code{1 / cos(latitude)}, which is
#' 21% at 34 degrees, 35% at 42 degrees and 47% at 47 degrees. UTM matches
#' geodesic distance to within ~0.1% inside its own zone, so a study area that
#' fits within a zone or two is measured essentially exactly.
#'
#' For data spanning many zones a single UTM is imperfect, but it remains far
#' closer to truth than Mercator; the function warns above \code{max_span_deg}
#' degrees of longitude so a genuinely global input is not measured silently.
#'
#' Polar data (|latitude| > 84) falls back to UPS North/South, where UTM is
#' undefined.
#'
#' Longitude is unwrapped at the antimeridian before the centroid and span
#' are computed: a raw bounding box on points at e.g. -179 and 179 degrees
#' reports a centroid of 0 and a 358-degree span, when the points are really
#' ~2 degrees apart on the correct side of the globe (Aleutians, Fiji, New
#' Zealand's eastern extent, eastern Russia).
#'
#' @param x An \code{sf} object or geometry in any CRS.
#' @param max_span_deg Numeric. Warn when the longitude span exceeds this many
#'   degrees (default 12, i.e. two UTM zones).
#'
#' @return Integer EPSG code.
#'
#' @keywords internal
#' @noRd
.utm_crs_for <- function(x, max_span_deg = 12) {
  g <- sf::st_geometry(x)
  if (is.na(sf::st_crs(g))) sf::st_crs(g) <- 4326L
  g <- sf::st_transform(g, 4326L)

  bb <- sf::st_bbox(g)
  xmin <- bb[["xmin"]]
  xmax <- bb[["xmax"]]
  lat <- mean(c(bb[["ymin"]], bb[["ymax"]]))

  # st_bbox() does not wrap at the antimeridian: two points at lon -179 and
  # 179 are ~2 degrees apart on the globe but the raw bbox reports xmin=-179,
  # xmax=179, an apparent 358-degree span and a centroid of 0 -- EPSG:32631,
  # a zone on the literal opposite side of the planet from where the points
  # actually are. When the naive span exceeds 180 degrees, shift the
  # negative side of the bbox onto the positive side of the antimeridian
  # (+360) before taking the centroid, so a cluster straddling +/-180 is
  # measured as the narrow span it actually is. This is a bbox-level
  # correction (two extreme values, not every point), which is enough to
  # fix a genuine antimeridian cluster; it does not attempt to distinguish
  # that from data that is honestly spread across most of the globe -- both
  # naively span >180 degrees, and only the wrapped span (below) tells them
  # apart.
  naive_span <- xmax - xmin
  if (is.finite(naive_span) && naive_span > 180) {
    xmin_w <- if (xmin < 0) xmin + 360 else xmin
    xmax_w <- if (xmax < 0) xmax + 360 else xmax
    span <- abs(xmax_w - xmin_w)
    lon <- mean(c(xmin_w, xmax_w))
    if (lon > 180) lon <- lon - 360
  } else {
    span <- naive_span
    lon <- mean(c(xmin, xmax))
  }

  if (is.finite(span) && span > max_span_deg) {
    warning(sprintf(
      paste0("Points span %.1f degrees of longitude; a single UTM zone is an ",
             "approximation. Distances remain far more accurate than Web ",
             "Mercator but consider splitting the data by region."),
      span
    ), call. = FALSE)
  }

  if (!is.finite(lat) || !is.finite(lon)) return(4326L)
  if (lat >  84) return(5041L)   # UPS North
  if (lat < -84) return(5042L)   # UPS South

  zone <- floor((lon + 180) / 6) + 1
  zone <- max(1L, min(60L, as.integer(zone)))
  if (lat >= 0) 32600L + zone else 32700L + zone
}
