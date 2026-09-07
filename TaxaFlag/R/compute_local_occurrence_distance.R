#' Distance from a query point to the nearest already-fetched GBIF occurrence
#'
#' For each taxon in `taxon_names`, finds the nearest record of that taxon
#' already present in `occurrence_data` and reports the geodesic distance
#' from `query_lat`/`query_lon` to it. `occurrence_data` is meant to be data
#' a workflow already fetched for its own purposes (e.g. the
#' `all_occurrences`/`occurrences_clean` objects `TaxaFetch` produces during
#' the normal pipeline) -- this function costs nothing beyond arithmetic, no
#' new GBIF call, since that regional data is already in hand.
#'
#' Designed as the free, local, exact complement to
#' [check_gbif_tile_range()]'s cheap, global, approximate view: a taxon with
#' `n_local_records = 0` here is, by construction, exactly the situation that
#' produces `TaxaAssign::compute_group_priors()`'s
#' `consensus_has_occurrence_record = FALSE` (an "unprecedented" call from
#' [add_posthoc_assessment()]), so this answers *why* that flag fired using
#' data the pipeline already paid for, rather than re-querying GBIF. Because
#' `occurrence_data` is whatever bounding box a study's own GBIF fetch used,
#' this function can only speak to that regional extent -- a taxon absent
#' here may still occur well outside it; [check_gbif_tile_range()] is the
#' tool for that wider question.
#'
#' @param taxon_names Character vector. One or more taxon names to check
#'   (e.g. every `consensus_taxon` flagged `"unexpected"`/`"unprecedented"`
#'   in one review session). Matched exactly against
#'   `occurrence_data[[taxon_col]]`.
#' @param query_lat,query_lon Numeric scalars. The point to measure distance
#'   from -- typically the study site's own centroid.
#' @param occurrence_data Data frame of already-fetched occurrence records
#'   (e.g. `all_occurrences`, `occurrences_clean`). Must contain `taxon_col`,
#'   `lat_col`, `lon_col`.
#' @param taxon_col,lat_col,lon_col Character scalars. Column names in
#'   `occurrence_data`. Defaults match `TaxaFetch`'s DarwinCore-aligned
#'   convention.
#' @param date_col Character or `NULL`. Optional column in `occurrence_data`
#'   giving the nearest record's collection date/year (e.g. GBIF's own
#'   `"year"` standard column). When supplied and present, the matched
#'   nearest record's raw value is surfaced as `nearest_date` -- lets a
#'   caller weigh a fresh vs. a decades-old nearest record differently
#'   without a second lookup. Default `NULL` (no age column requested,
#'   fully backward compatible -- `nearest_date` is simply absent from the
#'   output). No parsing/normalization is done on the raw value; a `"year"`
#'   column comes back as whatever numeric/character type it already was.
#'
#' @return A data frame, one row per unique entry in `taxon_names`:
#'   \describe{
#'     \item{taxon_name}{As supplied.}
#'     \item{n_local_records}{Count of `occurrence_data` rows for this taxon
#'       with non-missing coordinates. `0` for a taxon with no local record
#'       at all -- for a genuinely unprecedented taxon this IS the answer,
#'       not a failure to find one.}
#'     \item{dist_nearest_km}{Geodesic (great-circle) distance in km from the
#'       query point to the nearest such record. `NA` when
#'       `n_local_records == 0`.}
#'     \item{nearest_lat, nearest_lon}{Coordinates of that nearest record.
#'       `NA` when `n_local_records == 0`.}
#'     \item{nearest_date}{The nearest record's raw `date_col` value. Only
#'       present when `date_col` is supplied and found in `occurrence_data`.
#'       `NA` when `n_local_records == 0` or the nearest record's own
#'       `date_col` value is missing.}
#'   }
#'
#' @seealso [check_gbif_tile_range()]
#'
#' @examples
#' occ <- data.frame(
#'   taxon_name        = c("Neogobius melanostomus", "Neogobius melanostomus"),
#'   decimalLatitude   = c(41.60, 42.10),
#'   decimalLongitude  = c(-87.10, -87.80),
#'   year              = c(2019, 2003)
#' )
#' compute_local_occurrence_distance(
#'   taxon_names = c("Neogobius melanostomus", "Salmo salar"),
#'   query_lat = 41.67, query_lon = -87.15,
#'   occurrence_data = occ,
#'   date_col = "year"
#' )
#'
#' @importFrom dplyr filter transmute count group_by slice_min ungroup select left_join mutate coalesce
#' @importFrom rlang .data
#' @export
compute_local_occurrence_distance <- function(taxon_names,
                                              query_lat,
                                              query_lon,
                                              occurrence_data,
                                              taxon_col = "taxon_name",
                                              lat_col = "decimalLatitude",
                                              lon_col = "decimalLongitude",
                                              date_col = NULL) {
  if (!is.character(taxon_names) || length(taxon_names) == 0L) {
    stop("compute_local_occurrence_distance: taxon_names must be a non-empty character vector.")
  }
  if (!is.numeric(query_lat) || length(query_lat) != 1L || is.na(query_lat) ||
    !is.numeric(query_lon) || length(query_lon) != 1L || is.na(query_lon)) {
    stop("compute_local_occurrence_distance: query_lat/query_lon must be single non-NA numeric values.")
  }
  if (!is.data.frame(occurrence_data)) {
    stop("compute_local_occurrence_distance: occurrence_data must be a data frame.")
  }
  missing_cols <- setdiff(c(taxon_col, lat_col, lon_col), names(occurrence_data))
  if (length(missing_cols) > 0L) {
    stop(
      "compute_local_occurrence_distance: occurrence_data is missing columns: ",
      paste(missing_cols, collapse = ", ")
    )
  }
  use_date <- !is.null(date_col) && date_col %in% names(occurrence_data)

  taxa_unique <- unique(taxon_names)

  occ_dist <- occurrence_data |>
    dplyr::filter(
      .data[[taxon_col]] %in% taxa_unique,
      !is.na(.data[[lat_col]]), !is.na(.data[[lon_col]])
    ) |>
    dplyr::transmute(
      taxon_name = .data[[taxon_col]],
      .lat       = .data[[lat_col]],
      .lon       = .data[[lon_col]],
      .date      = if (use_date) .data[[date_col]] else NA,
      .dist_km   = .haversine_km(query_lat, query_lon, .data[[lat_col]], .data[[lon_col]])
    )

  counts <- occ_dist |>
    dplyr::count(.data$taxon_name, name = "n_local_records")

  nearest_rows <- occ_dist |>
    dplyr::group_by(.data$taxon_name) |>
    dplyr::slice_min(order_by = .data$.dist_km, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(
      taxon_name      = "taxon_name",
      dist_nearest_km = ".dist_km",
      nearest_lat     = ".lat",
      nearest_lon     = ".lon",
      nearest_date    = ".date"
    )
  if (!use_date) nearest_rows$nearest_date <- NULL

  result <- data.frame(taxon_name = taxa_unique, stringsAsFactors = FALSE) |>
    dplyr::left_join(counts, by = "taxon_name") |>
    dplyr::left_join(nearest_rows, by = "taxon_name") |>
    dplyr::mutate(n_local_records = dplyr::coalesce(.data$n_local_records, 0L))

  result
}

#' Great-circle distance between two points (km)
#' @noRd
.haversine_km <- function(lat1, lon1, lat2, lon2) {
  r <- 6371 # mean Earth radius, km
  to_rad <- pi / 180
  dlat <- (lat2 - lat1) * to_rad
  dlon <- (lon2 - lon1) * to_rad
  a <- sin(dlat / 2)^2 + cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
  2 * r * asin(pmin(1, sqrt(a)))
}
