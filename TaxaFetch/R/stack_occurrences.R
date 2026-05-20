# ==============================================================================
# stack_occurrences.R
# TaxaFetch -- Row-bind occurrence data frames and add point_id
# ==============================================================================

#' Stack Multiple Occurrence Data Frames
#'
#' Row-binds one or more occurrence data frames and adds a \code{point_id}
#' column constructed from the latitude and longitude columns. Checks that
#' every input frame contains the required coordinate columns before binding,
#' so a forgotten \code{\link[TaxaTools]{rename_cols}} call is caught immediately rather
#' than producing a frame full of \code{NA} coordinates.
#'
#' @param ... One or more data frames to combine, \emph{or} a single named
#'   list of data frames (the pattern used in the PDF and DataONE workflow
#'   scripts, e.g. \code{stack_occurrences(pdf_occ_list_clean)}).  When a
#'   single list is supplied its elements are used as the frames to combine.
#'   A single data frame is returned as-is with \code{point_id} added.
#' @param lat_col Character. Name of the latitude column. Default
#'   \code{"decimalLatitude"}.
#' @param lon_col Character. Name of the longitude column. Default
#'   \code{"decimalLongitude"}.
#'
#' @return A single tibble containing all rows from every input frame with
#'   an additional \code{point_id} column appended, formed by pasting
#'   \code{lat_col} and \code{lon_col} separated by \code{"_"}.
#'
#' @details
#' \strong{Single-frame input:} When only one data frame is supplied (or a
#' list with one element), it is returned directly with \code{point_id} added
#' and a message reporting the record count.  This avoids errors when the
#' upstream pipeline produced only one successful result.
#'
#' \strong{List input:} The workflow scripts pass a named list such as
#' \code{pdf_occ_list_clean} directly.  \code{stack_occurrences} detects this
#' and unpacks the list automatically -- no need to call
#' \code{do.call(stack_occurrences, list)} manually.
#'
#' \strong{Column alignment:} \code{dplyr::bind_rows} matches columns by name.
#' Rename columns to a common convention with \code{\link[TaxaTools]{rename_cols}}
#' before calling this function so that latitude, longitude, taxon name, and
#' date columns align correctly across sources.
#'
#' \strong{point_id:} If a \code{point_id} column already exists in any input
#' frame it will be overwritten in the combined output so that all rows use a
#' consistent format.
#'
#' @seealso \code{\link[TaxaTools]{rename_cols}}
#'
#' @importFrom dplyr bind_rows
#' @export
#'
#' @examples
#' \dontrun{
#' # Two sources passed directly
#' all_occ <- stack_occurrences(gbif_occ, dataone_occ)
#'
#' # From a list (workflow pattern)
#' all_occ <- stack_occurrences(pdf_occ_list_clean)
#'
#' # Single source -- point_id added, no error
#' all_occ <- stack_occurrences(gbif_occ)
#' }

stack_occurrences <- function(...,
                               lat_col = "decimalLatitude",
                               lon_col = "decimalLongitude") {

  dots <- list(...)

  # --- Unpack list input -------------------------------------------------------
  # Detect the workflow pattern: stack_occurrences(some_list)
  # A single argument that is itself a list of data frames -> unpack it.
  if (length(dots) == 1L && is.list(dots[[1L]]) &&
      !is.data.frame(dots[[1L]])) {
    frames <- dots[[1L]]
  } else {
    frames <- dots
  }

  # Drop any NULL entries (failed papers return NULL in the workflow loops)
  frames <- Filter(Negate(is.null), frames)

  # --- Input checks ------------------------------------------------------------
  if (length(frames) == 0L) {
    stop("stack_occurrences: no non-NULL data frames supplied.")
  }

  for (i in seq_along(frames)) {
    if (!is.data.frame(frames[[i]])) {
      stop(sprintf("stack_occurrences: element %d is not a data frame.", i))
    }
    missing_coords <- setdiff(c(lat_col, lon_col), names(frames[[i]]))
    if (length(missing_coords) > 0L) {
      stop(
        sprintf(
          "stack_occurrences: frame %d is missing coordinate column(s): %s\n",
          i, paste(missing_coords, collapse = ", ")
        ),
        "  Rename columns first with rename_cols(), or supply the correct\n",
        sprintf(
          "  column names via lat_col / lon_col (currently '%s' / '%s').",
          lat_col, lon_col
        )
      )
    }
  }

  # --- Bind and add point_id ---------------------------------------------------
  combined          <- dplyr::bind_rows(frames)
  combined$point_id <- paste(combined[[lat_col]], combined[[lon_col]], sep = "_")

  n_per_frame <- vapply(frames, nrow, integer(1L))

  if (length(frames) == 1L) {
    message(sprintf(
      "stack_occurrences: 1 frame -- %d record(s).",
      nrow(combined)
    ))
  } else {
    message(sprintf(
      "stack_occurrences: %d frame(s) combined -- %s = %d total record(s).",
      length(frames),
      paste(n_per_frame, collapse = " + "),
      nrow(combined)
    ))
  }

  combined <- tibble::as_tibble(combined)

  # --- Attach report_params with citations ------------------------------------
  rp <- list()
  if ("bibliographicCitation" %in% names(combined)) {
    cites <- unique(combined$bibliographicCitation)
    cites <- cites[!is.na(cites) & nzchar(cites)]
    if (length(cites) > 0L) rp$citations <- cites
  }
  rp$n_records <- nrow(combined)
  rp$n_sources <- length(frames)
  attr(combined, "report_params") <- rp

  combined
}
