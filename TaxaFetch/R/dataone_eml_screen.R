# ==============================================================================
# dataone_eml_screen.R
# TaxaExpect — EML pre-screening for DataONE / PASTA candidate datasets
#
# Exported functions:
#   screen_eml_columns()    Fetch EML for candidates; check bbox + column presence
#
# Internal helpers (@noRd):
#   .screen_one_eml()       Screen a single dataset ID
#   .eml_bounding_boxes()   Extract all boundingCoordinates from EML XML
#   .eml_attribute_names()  Extract all attributeName values from EML XML
#   .detect_lat_col()       Detect latitude column from attribute name list
#   .detect_lon_col()       Detect longitude column from attribute name list
#   .detect_species_col()   Detect species/taxon column from attribute name list
# ==============================================================================


# ==============================================================================
# screen_eml_columns()
# ==============================================================================

#' Pre-Screen DataONE Candidates via EML Metadata
#'
#' For each candidate dataset ID (typically the output of
#' \code{\link{parse_geo_screening_response}}), fetches the EML metadata
#' document and checks two things:
#' \enumerate{
#'   \item \strong{Bounding box overlap} — does the EML
#'     \code{<boundingCoordinates>} overlap the query bbox? Datasets without
#'     any bounding coordinates in their EML are retained (flagged
#'     \code{"no_eml_bbox"}) rather than dropped.
#'   \item \strong{Column presence} — do the EML \code{<attributeName>}
#'     elements suggest the data file contains latitude, longitude, and a
#'     species/taxon column?
#' }
#'
#' This is the step between geographic LLM screening and the expensive
#' data-file download in \code{\link{fetch_dataone_occurrences}}.
#'
#' @param ids Character vector of PASTA dataset IDs to screen
#'   (e.g. \code{"knb-lter-sbc.17.18"} or \code{"edi.123.4"}).
#' @param bbox Numeric vector \code{c(west, east, south, north)}.
#' @param pause_seconds Numeric. Pause between EML requests. Default
#'   \code{0.5}.
#' @param verbose Logical. Print per-dataset progress. Default \code{TRUE}.
#'
#' @return A tibble with one row per input ID and columns:
#'   \describe{
#'     \item{id}{Original dataset ID as supplied (2-part, e.g. \code{"edi.1835"}).
#'       Use this column to join back to \code{accepted}.}
#'     \item{resolved_id}{Fully-qualified 3-part PASTA ID (e.g. \code{"edi.1835.3"}).
#'       Use this column when calling \code{\link{fetch_dataone_eml}} or
#'       \code{\link{fetch_dataone_occurrences}} directly.}
#'     \item{eml_bbox_ok}{Logical. \code{TRUE} = EML bbox overlaps query;
#'       \code{NA} = no bbox in EML (dataset retained); \code{FALSE} = bbox
#'       confirmed outside query.}
#'     \item{has_lat}{Logical. A likely latitude column was found in the data tables.}
#'     \item{has_lon}{Logical. A likely longitude column was found in the data tables.}
#'     \item{has_species}{Logical. A likely species/taxon column was found.}
#'     \item{has_eml_sites}{Logical. At least one EML point site was found in
#'       \code{<geographicCoverage>} (bounding box where west==east and
#'       north==south). Datasets with EML point sites pass coordinate screening
#'       even when \code{has_lat} and \code{has_lon} are \code{FALSE} — Pass 5
#'       of \code{\link{fetch_dataone_occurrences}} will inject the coordinates.}
#'     \item{lat_col}{Character. Detected latitude column name, or \code{NA}.}
#'     \item{lon_col}{Character. Detected longitude column name, or \code{NA}.}
#'     \item{species_col}{Character. Detected species column name, or \code{NA}.}
#'     \item{n_tables}{Integer. Number of \code{<dataTable>} elements in EML.}
#'     \item{eml_status}{Character. One of \code{"pass"},
#'       \code{"fetch_failed"}, \code{"no_bbox_overlap"},
#'       \code{"no_coords"} (no lat/lon columns AND no EML point sites),
#'       \code{"no_species"}, \code{"no_eml_bbox"}.}
#'     \item{eml_pass}{Logical. \code{TRUE} if \code{eml_status == "pass"} or
#'       \code{"no_eml_bbox"} and coordinates + species columns detected.
#'       Use this column to filter before downloading.}
#'   }
#'
#' @details
#' \strong{Column detection} uses case-insensitive pattern matching against
#' the EML \code{<attributeName>} values across all \code{<dataTable>}
#' elements. Patterns:
#' \itemize{
#'   \item Latitude: \code{lat}, \code{latitude}, \code{decimallatitude},
#'     \code{y_coord}, \code{northing}, \code{yloc}
#'   \item Longitude: \code{lon}, \code{long}, \code{longitude},
#'     \code{decimallongitude}, \code{x_coord}, \code{easting}, \code{xloc}
#'   \item Species: \code{species}, \code{taxon}, \code{scientific},
#'     \code{organism}, \code{genus}, \code{sp_name}, \code{common_name},
#'     \code{accepted_name}, \code{vernacular}
#' }
#'
#' \strong{Bbox note:} Many EML documents lack \code{<boundingCoordinates>}
#' even when the data are geographically specific. These are flagged
#' \code{eml_bbox_ok = NA} and retained if column detection passes — the
#' record-level filter in \code{\link{fetch_dataone_occurrences}} will handle
#' the final spatial check.
#'
#' @seealso \code{\link{parse_geo_screening_response}},
#'   \code{\link{fetch_dataone_occurrences}},
#'   \code{\link{fetch_dataone_eml}}
#'
#' @importFrom dplyr tibble bind_rows
#' @importFrom httr2 request req_perform resp_body_string
#' @importFrom xml2 read_xml xml_ns_strip xml_find_all xml_find_first
#'   xml_text xml_attr
#' @export
#'
#' @examples
#' \dontrun{
#' accepted   <- parse_geo_screening_response(llm_raw, geo_prompt)
#' candidates <- accepted[accepted$geo_match, ]
#' eml_screen <- screen_eml_columns(candidates$id, bbox)
#'
#' # Datasets ready for download:
#' to_download <- eml_screen[eml_screen$eml_pass, ]
#' }

screen_eml_columns <- function(ids,
                                bbox,
                                pause_seconds = 0.5,
                                verbose       = TRUE) {

  if (!is.character(ids) || length(ids) == 0L) {
    stop("screen_eml_columns: 'ids' must be a non-empty character vector.")
  }
  if (!is.numeric(bbox) || length(bbox) != 4L || any(!is.finite(bbox))) {
    stop("screen_eml_columns: 'bbox' must be a finite numeric vector c(west, east, south, north).")
  }

  query_bbox <- list(west = bbox[1], east = bbox[2],
                     south = bbox[3], north = bbox[4])

  if (verbose) {
    message(sprintf("screen_eml_columns: screening %d dataset(s)...", length(ids)))
  }

  results <- vector("list", length(ids))

  for (i in seq_along(ids)) {
    id <- ids[i]
    if (verbose) message(sprintf("  [%d/%d] %s", i, length(ids), id))

    results[[i]] <- tryCatch(
      .screen_one_eml(id, query_bbox),
      error = function(e) {
        warning(sprintf("screen_eml_columns: %s -- %s", id, conditionMessage(e)),
                call. = FALSE)
        dplyr::tibble(
          id            = id,
          resolved_id   = NA_character_,
          eml_bbox_ok   = NA,
          has_lat       = FALSE,
          has_lon       = FALSE,
          has_species   = FALSE,
          has_eml_sites = FALSE,
          lat_col       = NA_character_,
          lon_col       = NA_character_,
          species_col   = NA_character_,
          n_tables      = 0L,
          eml_status    = "fetch_failed",
          eml_pass      = FALSE
        )
      }
    )

    if (i < length(ids)) Sys.sleep(pause_seconds)
  }

  out <- dplyr::bind_rows(results)

  if (verbose) {
    message(sprintf(
      "screen_eml_columns: %d pass, %d fail, %d fetch_failed (of %d)",
      sum(out$eml_pass),
      sum(!out$eml_pass & out$eml_status != "fetch_failed"),
      sum(out$eml_status == "fetch_failed"),
      nrow(out)
    ))
  }

  out
}


# ==============================================================================
# Internal: screen one dataset
# ==============================================================================

#' Screen one dataset ID via its EML document
#' @noRd
.screen_one_eml <- function(id, query_bbox) {

  # ---- resolve to 3-part ID if needed (original id kept for join key) --------
  resolved_id <- .resolve_pasta_id(id)

  # ---- fetch EML -------------------------------------------------------------
  eml_text <- fetch_dataone_eml(resolved_id)

  xml_doc <- tryCatch(
    {
      doc <- xml2::read_xml(eml_text)
      xml2::xml_ns_strip(doc)
      doc
    },
    error = function(e) {
      stop(sprintf("XML parse failed: %s", conditionMessage(e)))
    }
  )

  # ---- bounding coordinates --------------------------------------------------
  bboxes    <- .eml_bounding_boxes(xml_doc)
  eml_bbox_ok <- if (length(bboxes) == 0L) {
    NA   # no bbox in EML — retain but flag
  } else {
    any(vapply(bboxes, .bbox_overlaps_query, logical(1), query = query_bbox))
  }

  if (identical(eml_bbox_ok, FALSE)) {
    return(dplyr::tibble(
      id             = id,
      resolved_id    = resolved_id,
      eml_bbox_ok    = FALSE,
      has_lat        = NA,
      has_lon        = NA,
      has_species    = NA,
      has_eml_sites  = FALSE,
      lat_col        = NA_character_,
      lon_col        = NA_character_,
      species_col    = NA_character_,
      n_tables       = length(xml2::xml_find_all(xml_doc, ".//dataTable")),
      eml_status     = "no_bbox_overlap",
      eml_pass       = FALSE
    ))
  }

  # ---- EML point sites (boundingCoordinates where W==E and N==S) -------------
  # Datasets like SONGS store coordinates only in <geographicCoverage> nodes,
  # not in data table columns. Detect these so Pass 5 of fetch_dataone_occurrences
  # can inject them even when has_lat / has_lon are FALSE.
  has_eml_sites <- length(bboxes) > 0L && any(vapply(bboxes, function(b) {
    isTRUE(b$west == b$east) && isTRUE(b$south == b$north)
  }, logical(1)))

  # ---- attribute names -------------------------------------------------------
  attrs    <- .eml_attribute_names(xml_doc)
  n_tables <- length(xml2::xml_find_all(xml_doc, ".//dataTable"))

  lat_col     <- .detect_lat_col(attrs)
  lon_col     <- .detect_lon_col(attrs)
  species_col <- .detect_species_col(attrs)

  has_lat     <- !is.na(lat_col)
  has_lon     <- !is.na(lon_col)
  has_species <- !is.na(species_col)

  # has_coords: either explicit lat/lon columns OR EML point sites
  has_coords <- (has_lat && has_lon) || has_eml_sites

  eml_status <- if (!has_coords) {
    "no_coords"
  } else if (!has_species) {
    "no_species"
  } else if (is.na(eml_bbox_ok)) {
    "no_eml_bbox"   # passed column check; bbox unknown
  } else {
    "pass"
  }

  eml_pass <- eml_status %in% c("pass", "no_eml_bbox")

  dplyr::tibble(
    id            = id,
    resolved_id   = resolved_id,
    eml_bbox_ok   = eml_bbox_ok,
    has_lat       = has_lat,
    has_lon       = has_lon,
    has_species   = has_species,
    has_eml_sites = has_eml_sites,
    lat_col       = lat_col,
    lon_col       = lon_col,
    species_col   = species_col,
    n_tables      = n_tables,
    eml_status    = eml_status,
    eml_pass      = eml_pass
  )
}


# ==============================================================================
# Internal: revision resolution
# ==============================================================================

#' Resolve a 2-part PASTA ID to its newest 3-part revision
#'
#' PASTA IDs from the Solr catalog are stored as scope.identifier (2 parts).
#' The EML endpoint requires scope/identifier/revision (3 parts).
#' This helper calls the PASTA revisions endpoint and appends the newest revision.
#'
#' For IDs that already have 3+ parts (e.g. "edi.1835.3") the ID is returned
#' unchanged.
#'
#' Endpoint: GET https://pasta.lternet.edu/package/eml/{scope}/{identifier}
#' Response: plain text, one revision per line (ascending); newest = last line.
#'
#' @noRd
.resolve_pasta_id <- function(id) {
  parts <- strsplit(id, "\\.")[[1L]]
  if (length(parts) >= 3L) return(id)   # already fully qualified

  if (length(parts) < 2L)
    stop(sprintf(".resolve_pasta_id: cannot parse ID '%s'. Expected scope.identifier.", id))

  scope <- paste(parts[seq_len(length(parts) - 1L)], collapse = ".")
  ident <- parts[length(parts)]

  url  <- sprintf("https://pasta.lternet.edu/package/eml/%s/%s", scope, ident)
  resp <- tryCatch(
    httr2::request(url) |> httr2::req_perform(),
    error = function(e) {
      stop(sprintf("revision fetch failed for '%s': %s", id, conditionMessage(e)))
    }
  )

  body <- trimws(httr2::resp_body_string(resp))
  revs <- strsplit(body, "\n")[[1L]]
  revs <- trimws(revs)
  revs <- revs[nzchar(revs)]

  if (length(revs) == 0L)
    stop(sprintf(".resolve_pasta_id: no revisions returned for '%s'.", id))

  newest <- revs[length(revs)]   # revisions are ascending; last = newest
  paste0(id, ".", newest)
}


# ==============================================================================
# Internal: EML bbox extraction
# ==============================================================================

#' Extract all boundingCoordinates blocks from an EML xml_document
#' Returns a list of lists, each with $north $south $east $west
#' @noRd
.eml_bounding_boxes <- function(xml_doc) {
  nodes <- xml2::xml_find_all(xml_doc, ".//boundingCoordinates")
  if (length(nodes) == 0L) return(list())

  .num <- function(node, tag) {
    n <- xml2::xml_find_first(node, tag)
    if (inherits(n, "xml_missing")) return(NA_real_)
    suppressWarnings(as.numeric(xml2::xml_text(n, trim = TRUE)))
  }

  bboxes <- lapply(nodes, function(node) {
    list(
      west  = .num(node, "westBoundingCoordinate"),
      east  = .num(node, "eastBoundingCoordinate"),
      north = .num(node, "northBoundingCoordinate"),
      south = .num(node, "southBoundingCoordinate")
    )
  })

  # Drop bboxes with any NA coordinate
  Filter(function(b) !any(is.na(unlist(b))), bboxes)
}


#' Test whether an EML bbox overlaps the query bbox (axis-aligned)
#' @noRd
.bbox_overlaps_query <- function(eml_bb, query) {
  !(eml_bb$east  < query$west  |
    eml_bb$west  > query$east  |
    eml_bb$north < query$south |
    eml_bb$south > query$north)
}


# ==============================================================================
# Internal: attribute name extraction and column detection
# ==============================================================================

#' Extract all attributeName values from all dataTables in EML
#' Returns a character vector (lowercased, trimmed).
#' @noRd
.eml_attribute_names <- function(xml_doc) {
  nodes <- xml2::xml_find_all(xml_doc, ".//attributeName")
  if (length(nodes) == 0L) return(character(0))
  vals <- xml2::xml_text(nodes, trim = TRUE)
  tolower(vals[nzchar(vals)])
}


#' Detect the most likely latitude column name from a list of attribute names.
#' Returns the original-case name, or NA_character_.
#' @noRd
.detect_lat_col <- function(attrs) {
  if (length(attrs) == 0L) return(NA_character_)

  # Exact matches first (highest confidence), then partial
  exact   <- c("lat", "latitude", "decimallatitude", "y", "ylat",
                "lat_dd", "latitude_dd", "site_lat", "start_lat",
                "end_lat", "northing", "y_coord", "yloc", "lat_wgs84",
                "latitude_wgs84", "point_y")
  partial <- c("lat", "latitude", "northing", "yloc", "y_coord")

  hit <- attrs[attrs %in% exact]
  if (length(hit) > 0L) return(hit[1L])

  hit <- attrs[grepl(paste(partial, collapse = "|"), attrs, fixed = FALSE)]
  if (length(hit) > 0L) return(hit[1L])

  NA_character_
}


#' Detect the most likely longitude column name from a list of attribute names.
#' Returns the lowercased name, or NA_character_.
#' @noRd
.detect_lon_col <- function(attrs) {
  if (length(attrs) == 0L) return(NA_character_)

  exact   <- c("lon", "long", "longitude", "decimallongitude", "x", "xlon",
                "lon_dd", "longitude_dd", "site_lon", "start_lon",
                "end_lon", "easting", "x_coord", "xloc", "lon_wgs84",
                "longitude_wgs84", "point_x")
  partial <- c("lon", "long", "longitude", "easting", "xloc", "x_coord")

  hit <- attrs[attrs %in% exact]
  if (length(hit) > 0L) return(hit[1L])

  hit <- attrs[grepl(paste(partial, collapse = "|"), attrs, fixed = FALSE)]
  if (length(hit) > 0L) return(hit[1L])

  NA_character_
}


#' Detect the most likely species/taxon column from a list of attribute names.
#' Returns the lowercased name, or NA_character_.
#' @noRd
.detect_species_col <- function(attrs) {
  if (length(attrs) == 0L) return(NA_character_)

  exact   <- c("species", "taxon", "taxon_name", "scientific_name",
                "scientificname", "organism", "genus", "sp_name",
                "common_name", "commonname", "accepted_name",
                "vernacular", "taxa", "taxon_code", "sp", "spp",
                "species_name", "genus_species")
  partial <- c("species", "taxon", "scientific", "organism",
                "common_name", "vernacular", "genus")

  hit <- attrs[attrs %in% exact]
  if (length(hit) > 0L) return(hit[1L])

  hit <- attrs[grepl(paste(partial, collapse = "|"), attrs, fixed = FALSE)]
  if (length(hit) > 0L) return(hit[1L])

  NA_character_
}
