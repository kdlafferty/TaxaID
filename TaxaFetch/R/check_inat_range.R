# ==============================================================================
# check_inat_range.R
# TaxaFetch -- iNaturalist geomodel range polygon check
#
# Exported functions:
#   check_inat_range()   -- point-in-polygon range check for a vector of taxa
#
# Internal helpers:
#   .inat_taxon_id()       -- resolve taxon name to iNat taxon ID via taxa API
#   .inat_range_polygon()  -- download (or load from cache) iNat geomodel GeoJSON
#   .point_in_inat_range() -- point-in-polygon test using sf
# ==============================================================================

#' Check whether taxa fall within iNaturalist range polygons
#'
#' For each taxon name, resolves the iNaturalist taxon ID, downloads the
#' corresponding geomodel range polygon from iNaturalist's S3 bucket, and
#' tests whether a query point (lat/lng) falls within the polygon. The range
#' polygons are thresholded binary outputs of iNaturalist's SINR geomodel —
#' the continuous probability surface is not publicly available.
#'
#' @details
#' Intended for use on the dark diversity set: taxa detected in eDNA but absent
#' from the regional occurrence database (i.e. lacking a TaxaExpect prior).
#' Evidence is asymmetric: \code{in_range = TRUE} warrants a prior boost;
#' \code{in_range = FALSE} should not suppress priors (false negatives are common
#' for aquatic taxa due to low iNaturalist observer effort in marine systems).
#' Use \code{n_observations} to gate the boost — geomodel reliability scales with
#' observation count. \code{in_range = NA} (no polygon exists) is neutral.
#'
#' @param taxon_names Character vector of species names to check.
#' @param lat Numeric. Latitude of the query point in decimal degrees.
#' @param lng Numeric. Longitude of the query point in decimal degrees.
#' @param api_token Character. iNaturalist API token for taxon name resolution.
#'   Defaults to the \code{INAT_API_TOKEN} environment variable.
#' @param cache_dir Character. Optional path to a directory for caching
#'   downloaded GeoJSON files. Speeds up repeated calls for the same taxa.
#' @param verbose Logical. If TRUE, prints progress for each taxon. Default FALSE.
#' @return A tibble with columns \code{taxon_name}, \code{taxon_id},
#'   \code{matched_name}, \code{rank}, \code{iconic_taxon_name},
#'   \code{n_observations}, \code{in_range}, \code{range_status}.
#' @export
check_inat_range <- function(
    taxon_names,
    lat,
    lng,
    api_token = Sys.getenv("INAT_API_TOKEN"),
    cache_dir = NULL,
    verbose   = FALSE
) {
  if (nchar(api_token) == 0L) {
    stop(
      "INAT_API_TOKEN is not set. ",
      "Add it to ~/.Renviron or call Sys.setenv(INAT_API_TOKEN = 'your_token')."
    )
  }
  if (!is.numeric(lat) || length(lat) != 1L || is.na(lat)) {
    stop("`lat` must be a single non-NA numeric value.")
  }
  if (!is.numeric(lng) || length(lng) != 1L || is.na(lng)) {
    stop("`lng` must be a single non-NA numeric value.")
  }

  results <- vector("list", length(taxon_names))

  for (i in seq_along(taxon_names)) {
    name <- taxon_names[[i]]
    if (verbose) message(sprintf("[%d/%d] %s", i, length(taxon_names), name))

    info <- .inat_taxon_id(name, api_token)

    if (is.na(info$taxon_id)) {
      results[[i]] <- tibble::tibble(
        taxon_name        = name,
        taxon_id          = NA_integer_,
        matched_name      = NA_character_,
        rank              = NA_character_,
        iconic_taxon_name = NA_character_,
        n_observations    = NA_integer_,
        in_range          = NA,
        range_status      = "taxon_not_found"
      )
      next
    }

    polygon_sf <- .inat_range_polygon(info$taxon_id, cache_dir)

    if (is.null(polygon_sf)) {
      results[[i]] <- tibble::tibble(
        taxon_name        = name,
        taxon_id          = info$taxon_id,
        matched_name      = info$matched_name,
        rank              = info$rank,
        iconic_taxon_name = info$iconic_taxon_name,
        n_observations    = info$n_observations,
        in_range          = NA,
        range_status      = "no_polygon"
      )
      next
    }

    in_range_val <- .point_in_inat_range(polygon_sf, lat, lng)

    results[[i]] <- tibble::tibble(
      taxon_name        = name,
      taxon_id          = info$taxon_id,
      matched_name      = info$matched_name,
      rank              = info$rank,
      iconic_taxon_name = info$iconic_taxon_name,
      n_observations    = info$n_observations,
      in_range          = in_range_val,
      range_status      = if (isTRUE(in_range_val)) "in_range" else "out_of_range"
    )
  }

  dplyr::bind_rows(results)
}


# --- Internal helpers ---------------------------------------------------------

#' Resolve a taxon name to iNaturalist taxon ID and metadata
#' @noRd
.inat_taxon_id <- function(taxon_name, api_token) {
  url <- sprintf(
    "https://api.inaturalist.org/v1/taxa?q=%s&rank=species&per_page=1",
    utils::URLencode(taxon_name, reserved = TRUE)
  )

  resp <- tryCatch(
    httr::GET(url, httr::add_headers(Authorization = paste("Bearer", api_token))),
    error = function(e) NULL
  )
  Sys.sleep(0.3)

  empty <- list(
    taxon_id          = NA_integer_,
    matched_name      = NA_character_,
    rank              = NA_character_,
    iconic_taxon_name = NA_character_,
    n_observations    = NA_integer_
  )

  if (is.null(resp) || httr::status_code(resp) != 200L) return(empty)

  parsed <- tryCatch(
    httr::content(resp, as = "parsed", type = "application/json"),
    error = function(e) NULL
  )
  if (is.null(parsed) || length(parsed$results) == 0L) return(empty)

  r <- parsed$results[[1]]
  list(
    taxon_id          = as.integer(r$id),
    matched_name      = as.character(r$name %||% NA_character_),
    rank              = as.character(r$rank %||% NA_character_),
    iconic_taxon_name = as.character(r$iconic_taxon_name %||% NA_character_),
    n_observations    = as.integer(r$observations_count %||% NA_integer_)
  )
}


#' Download iNaturalist geomodel GeoJSON for a taxon ID (with optional caching)
#' @noRd
.inat_range_polygon <- function(taxon_id, cache_dir) {
  if (!is.null(cache_dir)) {
    cache_path <- file.path(cache_dir, sprintf("%d.geojson", taxon_id))
    if (file.exists(cache_path)) {
      return(tryCatch(
        sf::st_read(cache_path, quiet = TRUE),
        error = function(e) NULL
      ))
    }
  }

  url <- sprintf(
    "https://inaturalist-open-data.s3.us-east-1.amazonaws.com/geomodel/geojsons/latest/%d.geojson",
    taxon_id
  )

  resp <- tryCatch(httr::GET(url), error = function(e) NULL)

  if (is.null(resp)) return(NULL)
  if (httr::status_code(resp) %in% c(403L, 404L)) return(NULL)

  geojson_text <- tryCatch(
    httr::content(resp, as = "text", encoding = "UTF-8"),
    error = function(e) NULL
  )
  if (is.null(geojson_text)) return(NULL)

  polygon_sf <- tryCatch(
    sf::st_read(geojson_text, quiet = TRUE),
    error = function(e) NULL
  )
  if (is.null(polygon_sf)) return(NULL)

  if (!is.null(cache_dir) && dir.exists(cache_dir)) {
    tryCatch(
      writeLines(geojson_text, file.path(cache_dir, sprintf("%d.geojson", taxon_id))),
      error = function(e) NULL
    )
  }

  polygon_sf
}


#' Test whether a lat/lng point falls within an sf polygon object
#' @noRd
.point_in_inat_range <- function(polygon_sf, lat, lng) {
  query_pt <- sf::st_sfc(sf::st_point(c(lng, lat)), crs = 4326L)
  tryCatch(
    as.logical(sf::st_within(query_pt, sf::st_union(polygon_sf), sparse = FALSE)),
    error = function(e) NA
  )
}
