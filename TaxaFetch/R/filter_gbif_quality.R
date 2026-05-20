utils::globalVariables(c(
  "basisOfRecord", "coordinateUncertaintyInMeters", "decimalLatitude",
  "decimalLongitude", "issues"
))

# ==============================================================================
# filter_gbif_quality.R
# TaxaExpect -- Quality-filter raw GBIF occurrence records
# ==============================================================================

#' Filter GBIF Occurrence Records by Quality
#'
#' Removes low-quality rows from a raw GBIF occurrence download. Applies up
#' to six sequential filters: coordinate completeness, basis of record,
#' geospatial issue codes, coordinate uncertainty, coordinate decimal-place
#' precision, and eDNA/metabarcoding keyword removal. Each filter is applied
#' only when the relevant column is present; absent columns produce an
#' informational message and are skipped rather than causing an error.
#'
#' @param data A data frame of GBIF occurrence records. Must contain
#'   \code{decimalLatitude} and \code{decimalLongitude}.
#' @param basis_keep Character vector. Values of \code{basisOfRecord} to
#'   retain. Records not in this vector are removed. Default retains human
#'   and machine observations and specimen records; excludes fossil and
#'   unknown sources.
#' @param exclude_edna Logical. If \code{TRUE} (default), records whose
#'   \code{samplingProtocol}, \code{occurrenceRemarks}, or
#'   \code{preparations} columns contain eDNA or metabarcoding keywords are
#'   removed. Set to \code{FALSE} if your workflow specifically targets
#'   eDNA data.
#' @param bad_issues Character vector. GBIF issue codes that indicate likely
#'   geospatial errors. Records whose \code{issues} field contains any of
#'   these codes are removed. Default covers the most consequential spatial
#'   errors; see Details for how to check which codes appear in your data.
#' @param max_coord_uncertainty Numeric. Maximum allowable value of
#'   \code{coordinateUncertaintyInMeters} in metres (default \code{500}).
#'   Records with a value exceeding this threshold are removed. The 500 m
#'   default is a commonly used GBIF quality threshold, stricter than GBIF's
#'   own default but appropriate for ecological analyses where grid cell sizes
#'   are typically 10+ km. Set to \code{1000} for coarser analyses or
#'   \code{Inf} to disable. Records where
#'   \code{coordinateUncertaintyInMeters} is \code{NA} are retained
#'   (uncertainty not reported is not the same as uncertainty being large).
#'   If the column is absent the filter is skipped with a message.
#' @param max_coord_decimal_places Integer or \code{NULL}. Minimum number
#'   of decimal places required in \emph{at least one} coordinate
#'   (latitude or longitude). Records where both coordinates are rounded to
#'   fewer decimal places than this threshold are removed as likely
#'   imprecise. \code{NULL} (default) disables this filter.
#'   \itemize{
#'     \item 1 decimal place ~ 11 km resolution
#'     \item 2 decimal places ~ 1 km resolution
#'     \item 3 decimal places ~ 111 m resolution
#'   }
#'   Recommended: \code{2} or \code{3} for habitat grids on the order of
#'   a few hundred metres to a kilometre.
#'
#' @return The input data frame with low-quality rows removed. Column
#'   structure is unchanged. A summary message reports the number of
#'   records retained.
#'
#' @details
#' \strong{Filter order:} Coordinates -> basis of record -> issue codes ->
#' coordinate uncertainty -> coordinate decimal-place precision -> eDNA.
#' Applying cheaper filters first reduces unnecessary string operations on
#' large datasets.
#'
#' \strong{Verifying issue codes in your data:}
#' \preformatted{
#' sort(table(unlist(strsplit(na.omit(your_data$issues), ";"))),
#'      decreasing = TRUE)
#' }
#'
#' \strong{Decimal-place precision (OR logic):} A record is retained if
#' \emph{either} its latitude or its longitude has at least
#' \code{max_coord_decimal_places} decimal places. This avoids discarding
#' records on coastlines or grid boundaries where one coordinate may be
#' rounded while the other is precise.
#'
#' @seealso \code{\link{fetch_gbif_occurrences}},
#'   \code{\link{stack_occurrences}}
#'
#' @importFrom dplyr filter
#' @export
#'
#' @examples
#' \dontrun{
#' # Default filters (500 m uncertainty threshold, no decimal-place filter)
#' clean <- filter_gbif_quality(gbif_raw)
#'
#' # Stricter: require at least 3 decimal places (~111 m) in at least one coord
#' clean <- filter_gbif_quality(gbif_raw, max_coord_decimal_places = 3)
#'
#' # Disable the uncertainty filter
#' clean <- filter_gbif_quality(gbif_raw, max_coord_uncertainty = Inf)
#'
#' # Compare thresholds
#' nrow(filter_gbif_quality(gbif_raw, max_coord_uncertainty = 500))
#' nrow(filter_gbif_quality(gbif_raw, max_coord_uncertainty = 1000))
#' nrow(filter_gbif_quality(gbif_raw, max_coord_uncertainty = Inf))
#' }

filter_gbif_quality <- function(
    data,
    basis_keep             = c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION",
                               "LIVING_SPECIMEN",   "PRESERVED_SPECIMEN"),
    exclude_edna           = TRUE,
    bad_issues             = c("COORDINATE_OUT_OF_RANGE",
                               "COUNTRY_COORDINATE_MISMATCH",
                               "COORDINATE_INVALID",
                               "ZERO_COORDINATE",
                               "COORDINATE_PRECISION_INVALID"),
    max_coord_uncertainty  = 500,
    max_coord_decimal_places = NULL
) {

  # --- Input checks -----------------------------------------------------------
  if (!is.data.frame(data)) {
    stop("filter_gbif_quality: 'data' must be a data frame.")
  }

  n_start <- nrow(data)
  if (n_start == 0L) {
    message("filter_gbif_quality: input is empty -- returning as-is.")
    return(data)
  }

  # --- 1. Coordinate completeness ---------------------------------------------
  required_coord_cols <- c("decimalLatitude", "decimalLongitude")
  if (!all(required_coord_cols %in% names(data))) {
    stop("filter_gbif_quality: missing required columns: ",
         paste(setdiff(required_coord_cols, names(data)), collapse = ", "))
  }

  data         <- dplyr::filter(data, !is.na(decimalLatitude),
                                      !is.na(decimalLongitude))
  n_after      <- nrow(data)
  if (n_after < n_start) {
    message(sprintf("  Removed %d records with missing coordinates.",
                    n_start - n_after))
  }
  n_current <- n_after

  # --- 2. Basis of record -----------------------------------------------------
  if (!"basisOfRecord" %in% names(data)) {
    message("filter_gbif_quality: 'basisOfRecord' column not found -- skipping basis filter.")
  } else {
    data      <- dplyr::filter(data, basisOfRecord %in% basis_keep)
    n_after   <- nrow(data)
    if (n_after < n_current) {
      message(sprintf("  Removed %d records with excluded basis of record.",
                      n_current - n_after))
    }
    n_current <- n_after
  }

  # --- 3. GBIF issue codes ----------------------------------------------------
  if (!"issues" %in% names(data)) {
    message("filter_gbif_quality: 'issues' column not found -- skipping issue filter.")
  } else if (length(bad_issues) > 0L) {
    issue_pattern <- paste(bad_issues, collapse = "|")
    data      <- dplyr::filter(data,
                               is.na(issues) |
                               !grepl(issue_pattern, issues, fixed = FALSE))
    n_after   <- nrow(data)
    if (n_after < n_current) {
      message(sprintf("  Removed %d records with flagged geospatial issues.",
                      n_current - n_after))
    }
    n_current <- n_after
  }

  # --- 4. Coordinate uncertainty ----------------------------------------------
  if (!is.finite(max_coord_uncertainty)) {
    # Inf or NaN passed -- skip silently
  } else if (!"coordinateUncertaintyInMeters" %in% names(data)) {
    message("filter_gbif_quality: 'coordinateUncertaintyInMeters' column not found -- skipping uncertainty filter.")
  } else {
    data    <- dplyr::filter(data,
                             is.na(coordinateUncertaintyInMeters) |
                             coordinateUncertaintyInMeters <= max_coord_uncertainty)
    n_after <- nrow(data)
    if (n_after < n_current) {
      message(sprintf(
        "  Removed %d records with coordinateUncertaintyInMeters > %g m.",
        n_current - n_after, max_coord_uncertainty
      ))
    }
    n_current <- n_after
  }

  # --- 5. Coordinate decimal-place precision ----------------------------------
  if (!is.null(max_coord_decimal_places)) {
    if (!is.numeric(max_coord_decimal_places) ||
        length(max_coord_decimal_places) != 1L ||
        max_coord_decimal_places < 1L) {
      stop("filter_gbif_quality: 'max_coord_decimal_places' must be a single positive integer or NULL.")
    }
    d <- as.integer(max_coord_decimal_places)

    lat_dp <- .count_decimal_places(data$decimalLatitude)
    lon_dp <- .count_decimal_places(data$decimalLongitude)

    # OR logic: keep if EITHER coordinate meets the precision threshold
    keep   <- (lat_dp >= d) | (lon_dp >= d)
    data   <- data[keep, , drop = FALSE]
    n_after <- nrow(data)
    if (n_after < n_current) {
      message(sprintf(
        "  Removed %d records where both coordinates have fewer than %d decimal place(s).",
        n_current - n_after, d
      ))
    }
    n_current <- n_after
  }

  # --- 6. eDNA / metabarcoding removal ----------------------------------------
  if (exclude_edna) {
    edna_cols <- intersect(
      c("samplingProtocol", "occurrenceRemarks", "preparations"),
      names(data)
    )
    edna_cols <- edna_cols[vapply(data[edna_cols], is.character, logical(1L))]
    if (length(edna_cols) == 0L) {
      message("filter_gbif_quality: no eDNA-detectable character columns found -- skipping eDNA filter.")
    } else {
      edna_pattern <- paste(
        "edna", "environmental dna", "metabarcod",
        "bulk sample", "water sample",
        sep = "|"
      )
      search_text <- do.call(
        paste,
        c(lapply(edna_cols, function(col) {
          x <- data[[col]]
          ifelse(is.na(x), "", x)
        }),
        sep = " ")
      )
      data    <- data[!grepl(edna_pattern, search_text, ignore.case = TRUE), ]
      n_after <- nrow(data)
      if (n_after < n_current) {
        message(sprintf("  Removed %d eDNA/metabarcoding records.",
                        n_current - n_after))
      }
    }
  }

  message(sprintf(
    "filter_gbif_quality: %d records retained of %d (%.1f%%).",
    nrow(data), n_start, 100 * nrow(data) / max(n_start, 1L)
  ))

  data
}


# ==============================================================================
# Internal helper
# ==============================================================================

#' Count the number of decimal places in a numeric vector
#'
#' Uses arithmetic: for each value, increments d from 0 until
#' \code{round(v, d) == v} within floating-point tolerance.
#' Returns 0 for NA, NaN, and Inf values.
#'
#' @param v Numeric vector.
#' @return Integer vector of the same length as \code{v}.
#' @noRd
.count_decimal_places <- function(v) {
  result <- integer(length(v))          # initialise all to 0L
  finite_mask <- !is.na(v) & is.finite(v)
  if (any(finite_mask)) {
    result[finite_mask] <- vapply(v[finite_mask], function(x) {
      for (d in 0:10) {
        if (isTRUE(all.equal(round(x, d), x, tolerance = 1e-9))) return(d)
      }
      10L
    }, integer(1L))
  }
  result
}
