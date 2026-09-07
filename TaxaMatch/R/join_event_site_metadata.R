# ==============================================================================
# join_event_site_metadata.R
# TaxaMatch -- Attach externally-supplied site metadata to event-level detections
#
# Exported functions:
#   join_event_site_metadata()   Join a detections table to a site-metadata table
# ==============================================================================

#' Join Event-Level Detections to a Site Metadata Table
#'
#' Produces a \code{site_df} suitable for \code{\link{build_site_table}} from
#' any event-level detections table (one row per \code{id_col} x
#' \code{event_col} pair actually observed) and a separately-maintained site
#' metadata table (\code{event_col} plus site attributes). This is the same
#' underlying operation for every data-type pathway that lacks embedded site
#' info -- DNA/BLAST (Reads-table sample columns) and acoustic (recording/
#' device identifiers) both reduce to "join an event identifier against a
#' metadata table of where/when that event happened" -- so one function
#' serves both rather than duplicating the join per pathway.
#'
#' @param detections Data frame. One row per \code{(id_col, event_col)} pair
#'   that was actually observed -- e.g. a Reads-table already pivoted to long
#'   format and filtered to \code{n_reads > 0} (DNA/BLAST), or a BirdNET match
#'   object's own \code{observation_id}/\code{source_file} pairs (acoustic,
#'   already one row per detection window). Must contain \code{id_col} and
#'   \code{event_col}.
#' @param site_metadata Data frame maintained separately from the detections
#'   table -- one row per \code{event_col} value, with at least
#'   \code{lat_col}/\code{lon_col} columns and optionally
#'   \code{observed_on_col}. This is the same kind of lookup table already
#'   used to identify blank/control samples (e.g. \code{BLANKS_MARCH},
#'   \code{BLANKS_AUG} in \code{PtConceptionWorkflow_12S.R}), generalized to
#'   carry site coordinates and collection date instead of (or in addition
#'   to) blank status.
#' @param event_col Character. Join key column name, present in both
#'   \code{detections} and \code{site_metadata}. Default \code{"event_id"}.
#' @param id_col Character. Observation ID column in \code{detections}.
#'   Default \code{"observation_id"}.
#' @param lat_col,lon_col Character. Latitude/longitude column names in
#'   \code{site_metadata}. Default \code{"lat"} / \code{"lon"}.
#' @param observed_on_col Character. Collection-date column name in
#'   \code{site_metadata}, or \code{NULL} if not available. Default
#'   \code{"observed_on"}.
#' @param control_samples Character vector of \code{event_col} values to
#'   exclude before joining (blanks/controls are not real site detections).
#'   Default \code{NULL} (no exclusion).
#'
#' @return A tibble in the long-format shape \code{\link{build_site_table}}'s
#'   \code{site_df} argument expects: \code{id_col}, \code{lat}, \code{lon},
#'   \code{observed_on} (\code{NA} if \code{observed_on_col = NULL}), plus
#'   \code{event_col} retained for traceability. May have more than one row
#'   per \code{id_col} value -- this is the correct shape for an
#'   \code{id_col} value (e.g. a sequence ASV) genuinely detected at more than
#'   one real event's site. Rows whose \code{event_col} value has no matching
#'   \code{site_metadata} row get \code{NA} \code{lat}/\code{lon}, with a
#'   warning naming them.
#'
#' @examples
#' detections <- data.frame(
#'   observation_id = c("ASV1", "ASV1", "ASV2"),
#'   event_id = c("site_A", "site_B", "site_A")
#' )
#' site_metadata <- data.frame(
#'   event_id    = c("site_A", "site_B"),
#'   lat         = c(34.41, 36.60),
#'   lon         = c(-119.86, -121.90),
#'   observed_on = c("2026-03-14", "2026-03-15")
#' )
#' join_event_site_metadata(detections, site_metadata)
#'
#' @seealso \code{\link{build_site_table}}
#' @importFrom dplyr left_join select any_of
#' @export
join_event_site_metadata <- function(detections,
                                     site_metadata,
                                     event_col = "event_id",
                                     id_col = "observation_id",
                                     lat_col = "lat",
                                     lon_col = "lon",
                                     observed_on_col = "observed_on",
                                     control_samples = NULL) {
  if (!is.data.frame(detections) || nrow(detections) == 0L) {
    stop("join_event_site_metadata: 'detections' must be a non-empty data frame.", call. = FALSE)
  }
  if (!is.data.frame(site_metadata) || nrow(site_metadata) == 0L) {
    stop("join_event_site_metadata: 'site_metadata' must be a non-empty data frame.", call. = FALSE)
  }

  missing_det <- setdiff(c(id_col, event_col), names(detections))
  if (length(missing_det) > 0L) {
    stop(sprintf(
      "join_event_site_metadata: 'detections' missing column(s): %s",
      paste(missing_det, collapse = ", ")
    ), call. = FALSE)
  }

  required_meta <- c(event_col, lat_col, lon_col)
  missing_meta <- setdiff(required_meta, names(site_metadata))
  if (length(missing_meta) > 0L) {
    stop(sprintf(
      "join_event_site_metadata: 'site_metadata' missing column(s): %s",
      paste(missing_meta, collapse = ", ")
    ), call. = FALSE)
  }

  if (!is.null(observed_on_col) && !observed_on_col %in% names(site_metadata)) {
    stop(sprintf(
      "join_event_site_metadata: 'site_metadata' missing observed_on_col '%s' (pass observed_on_col = NULL if not available).",
      observed_on_col
    ), call. = FALSE)
  }

  if (!is.null(control_samples)) {
    n_before <- nrow(detections)
    detections <- detections[!detections[[event_col]] %in% control_samples, , drop = FALSE]
    n_excluded <- n_before - nrow(detections)
    if (n_excluded > 0L) {
      message(sprintf(
        "join_event_site_metadata: excluded %d control/blank detection row(s).", n_excluded
      ))
    }
    if (nrow(detections) == 0L) {
      stop("join_event_site_metadata: all rows excluded as control_samples; nothing left to join.", call. = FALSE)
    }
  }

  meta <- site_metadata[, unique(c(
    event_col, lat_col, lon_col,
    if (!is.null(observed_on_col)) observed_on_col
  )), drop = FALSE]
  names(meta)[names(meta) == lat_col] <- "lat"
  names(meta)[names(meta) == lon_col] <- "lon"
  if (!is.null(observed_on_col)) {
    names(meta)[names(meta) == observed_on_col] <- "observed_on"
  } else {
    meta$observed_on <- NA_character_
  }

  out <- dplyr::left_join(detections, meta, by = event_col)

  unmatched <- unique(out[[event_col]][is.na(out$lat) | is.na(out$lon)])
  if (length(unmatched) > 0L) {
    warning(sprintf(
      "join_event_site_metadata: %d event(s) have no matching row in 'site_metadata' (NA lat/lon): %s",
      length(unmatched), paste(utils::head(unmatched, 5L), collapse = ", ")
    ), call. = FALSE)
  }

  tibble::as_tibble(
    out[, unique(c(id_col, "lat", "lon", "observed_on", event_col)), drop = FALSE]
  )
}
