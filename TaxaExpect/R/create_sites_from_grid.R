utils::globalVariables(c("lat_r", "lon_r", "grid_id_raw", "grid_id"))

#' Create Grid IDs by Snapping Coordinates to a Regular Grid
#'
#' Snaps each occurrence record's latitude and longitude to the nearest grid
#' cell centre at a given resolution, then constructs a sanitised
#' \code{grid_id} string suitable for use as a random effect label in
#' \code{\link{train_biodiversity_model}}.
#'
#' Grid identity encodes \emph{spatial location only}. Habitat is not
#' included in \code{grid_id} because it enters the model as a fixed covariate,
#' not as part of the grouping structure. Run
#' \code{assign_habitat_to_points()} or
#' \code{assign_habitat_biological()} (TaxaHabitat) after this function to add a
#' \code{main_habitat} column.
#'
#' @param data A dataframe. Must contain columns named by \code{lat_col} and
#'   \code{lon_col}. All other columns are passed through unchanged.
#' @param grid_size Numeric. Spatial resolution in decimal degrees. All
#'   coordinates are rounded to the nearest multiple of this value.
#'   Typical values: 0.1 (approx. 10 km), 0.5, 1.0. Values above 10 trigger
#'   a warning because they are almost certainly in kilometres rather than
#'   degrees. Use \code{\link{optimize_grid_size}} to select
#'   an appropriate value for your dataset.
#' @param lat_col Character. Name of the latitude column.
#'   Default \code{"decimalLatitude"}.
#' @param lon_col Character. Name of the longitude column.
#'   Default \code{"decimalLongitude"}.
#'
#' @return The input dataframe with three columns added:
#'   \describe{
#'     \item{lat_r}{Latitude rounded to the grid cell centre.}
#'     \item{lon_r}{Longitude rounded to the grid cell centre.}
#'     \item{grid_id}{Character. Stable spatial identifier of the form
#'       \code{"Grid_{lat_r}_{lon_r}"}, with decimal points replaced by
#'       \code{"p"} and minus signs replaced by \code{"m"}, making the label
#'       safe for use as a factor level in R formulae and as a file or column
#'       name. For example, lat = -119.5, lon = 34.0 yields
#'       \code{"Grid_m119p5_34p0"}.}
#'   }
#'   Row order is unchanged.
#'
#' @details
#' \strong{Grid cell centre convention:} rounding places each coordinate at the
#' centre of its cell. With \code{grid_size = 0.5}, all points in
#' [34.25, 34.75) map to 34.5.
#'
#' \strong{Why habitat is excluded from grid_id:} A grid cell may contain
#' multiple habitat types. Including habitat in the identifier would split one
#' spatial location into multiple grid IDs, breaking the
#' \code{(1 | taxon_name:grid_id)} random effect structure in
#' \code{train_biodiversity_model}. Assign habitat after this step.
#'
#' @seealso \code{\link{prepare_model_dataframe}},
#'   \code{\link{optimize_grid_size}}
#'
#' @examples
#' \dontrun{
#' gridded <- create_sites_from_grid(occurrences, grid_size = 0.1)
#' head(gridded$grid_id)
#' }
#'
#' @importFrom dplyr mutate select
#' @importFrom rlang sym
#' @importFrom stringr str_replace_all
#' @export
create_sites_from_grid <- function(data,
                                   grid_size,
                                   lat_col = "decimalLatitude",
                                   lon_col = "decimalLongitude") {

  if (!is.data.frame(data)) {
    stop("create_sites_from_grid: 'data' must be a dataframe.")
  }

  missing_cols <- setdiff(c(lat_col, lon_col), names(data))
  if (length(missing_cols) > 0) {
    stop("create_sites_from_grid: column(s) not found in 'data': ",
         paste(missing_cols, collapse = ", "))
  }

  if (!is.numeric(grid_size) || length(grid_size) != 1L ||
      is.na(grid_size) || grid_size <= 0) {
    stop("create_sites_from_grid: 'grid_size' must be a single positive number. ",
         "Got: ", grid_size)
  }

  if (grid_size > 10) {
    warning(
      "create_sites_from_grid: 'grid_size' = ", grid_size,
      " degrees is unusually large. Did you mean a smaller value? ",
      "Use optimize_grid_size() to select an appropriate resolution.",
      call. = FALSE
    )
  }

  lat_sym <- rlang::sym(lat_col)
  lon_sym <- rlang::sym(lon_col)

  dplyr::select(
    dplyr::mutate(
      data,
      lat_r = round(!!lat_sym / grid_size) * grid_size,
      lon_r = round(!!lon_sym / grid_size) * grid_size,
      grid_id_raw = sprintf("Grid_%.1f_%.1f", lat_r, lon_r),
      grid_id = stringr::str_replace_all(grid_id_raw, "-", "m"),
      grid_id = stringr::str_replace_all(grid_id, "\\.", "p")
    ),
    -grid_id_raw
  )
}
