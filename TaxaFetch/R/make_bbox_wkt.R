#' Create a WKT Bounding Box Around a Central Point
#'
#' Generates a Well-Known Text (WKT) POLYGON string representing a square
#' bounding box centred on a given latitude and longitude. The result is
#' ready to pass directly to the \code{geometry} argument of
#' \code{\link{fetch_gbif_occurrences}}.
#'
#' @param lat Numeric. Latitude of the centre point in decimal degrees
#'   (WGS 84). Must be in the range \code{[-90, 90]}.
#' @param lon Numeric. Longitude of the centre point in decimal degrees
#'   (WGS 84). Must be in the range \code{[-180, 180]}.
#' @param radius_deg Numeric. Half-width of the bounding box in decimal
#'   degrees. The box extends \code{radius_deg} degrees in each direction
#'   from the centre, giving a total side length of \code{2 * radius_deg}.
#'   Must be positive. For reference: 1 degree of latitude is approximately
#'   111 km; 0.5 degrees is approximately 55 km.
#'
#' @return A length-1 character vector: a WKT POLYGON string with vertices
#'   ordered counter-clockwise and the first and last vertex identical (closed
#'   ring), as required by the GBIF occurrence API.
#'
#' @details
#' \strong{Square vs. irregular polygons:} This function always produces a
#' square bounding box. For an irregular boundary (coastline, watershed,
#' administrative region) use \code{\link{define_search_polygon}} to draw a
#' custom polygon interactively, or construct a WKT string manually and pass
#' it directly to \code{fetch_gbif_occurrences(geometry = ...)}.
#'
#' \strong{Coordinate clamping:} If the box would extend beyond the poles
#' (\code{lat +/- radius_deg} outside \code{[-90, 90]}) or the antimeridian
#' (\code{lon +/- radius_deg} outside \code{[-180, 180]}), the function
#' stops with an informative error. Queries spanning the antimeridian are not
#' supported by this helper; split them into two overlapping queries instead.
#'
#' \strong{WKT coordinate order:} WKT uses (longitude latitude) order --
#' i.e., X before Y -- which is the opposite of the common (lat, lon)
#' convention. This function handles the swap internally; callers supply
#' (lat, lon) as is conventional in this package.
#'
#' @seealso \code{\link{fetch_gbif_occurrences}}, \code{\link{define_search_polygon}}
#'
#' @export
#'
#' @examples
#' # 1-degree box around a coastal sampling site
#' make_bbox_wkt(lat = 34.5, lon = -120.0, radius_deg = 1.0)
#'
#' # Smaller box for a freshwater study (approx. 55 km radius)
#' make_bbox_wkt(lat = 47.2, lon = 8.5, radius_deg = 0.5)
#'
#' # Use directly in fetch_gbif_occurrences()
#' \dontrun{
#' bbox <- make_bbox_wkt(lat = 34.5, lon = -120.0, radius_deg = 2.0)
#' fetch_gbif_occurrences(keys = my_keys, geometry = bbox)
#' }
make_bbox_wkt <- function(lat, lon, radius_deg) {

  # --- Input checks -----------------------------------------------------------
  if (!is.numeric(lat)    || length(lat)    != 1 || is.na(lat))
    stop("make_bbox_wkt: 'lat' must be a single non-NA numeric value.")
  if (!is.numeric(lon)    || length(lon)    != 1 || is.na(lon))
    stop("make_bbox_wkt: 'lon' must be a single non-NA numeric value.")
  if (!is.numeric(radius_deg) || length(radius_deg) != 1 || is.na(radius_deg))
    stop("make_bbox_wkt: 'radius_deg' must be a single non-NA numeric value.")

  if (lat < -90 || lat > 90)
    stop("make_bbox_wkt: 'lat' must be in [-90, 90]. Got: ", lat)
  if (lon < -180 || lon > 180)
    stop("make_bbox_wkt: 'lon' must be in [-180, 180]. Got: ", lon)
  if (radius_deg <= 0)
    stop("make_bbox_wkt: 'radius_deg' must be positive. Got: ", radius_deg)

  # --- Compute corners --------------------------------------------------------
  min_lat <- lat - radius_deg
  max_lat <- lat + radius_deg
  min_lon <- lon - radius_deg
  max_lon <- lon + radius_deg

  if (min_lat < -90 || max_lat > 90) {
    stop(
      "make_bbox_wkt: bounding box extends beyond the poles ",
      "(lat +/- radius_deg = ", min_lat, " to ", max_lat, "). ",
      "Reduce radius_deg or move the centre point."
    )
  }
  if (min_lon < -180 || max_lon > 180) {
    stop(
      "make_bbox_wkt: bounding box crosses the antimeridian ",
      "(lon +/- radius_deg = ", min_lon, " to ", max_lon, "). ",
      "Split into two queries or construct a custom WKT polygon manually."
    )
  }

  # --- Build WKT --------------------------------------------------------------
  # WKT POLYGON uses (lon lat) order (X Y). Vertices are counter-clockwise;
  # the ring is closed by repeating the first vertex.
  paste0(
    "POLYGON ((",
    min_lon, " ", min_lat, ", ",
    max_lon, " ", min_lat, ", ",
    max_lon, " ", max_lat, ", ",
    min_lon, " ", max_lat, ", ",
    min_lon, " ", min_lat,
    "))"
  )
}
