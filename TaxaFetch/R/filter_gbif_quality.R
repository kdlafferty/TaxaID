utils::globalVariables(c(
  "basisOfRecord", "coordinateUncertaintyInMeters", "decimalLatitude",
  "decimalLongitude", "issues", "occurrenceStatus", "species"
))

# ==============================================================================
# filter_gbif_quality.R
# TaxaFetch -- Quality-filter raw GBIF occurrence records
# ==============================================================================

#' Filter GBIF Occurrence Records by Quality
#'
#' Removes low-quality rows from a raw GBIF occurrence download. Applies up
#' to twelve sequential filters: coordinate completeness, absent occurrences,
#' basis of record, geospatial issue codes, coordinate uncertainty,
#' coordinate decimal-place precision, eDNA/metabarcoding keyword removal,
#' species-level requirement, and six \code{CoordinateCleaner}-backed checks
#' (identical lat/lon, near-zero coordinates, near GBIF headquarters, near a
#' country/province centroid, near a national capital, near a biodiversity
#' institution). Each filter is applied only when the relevant column (or
#' package) is present; absent columns or an unavailable optional package
#' produce an informational message and are skipped rather than causing an
#' error.
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
#' @param exclude_absent Logical. If \code{TRUE} (default), records where
#'   \code{occurrenceStatus} is \code{"ABSENT"} (case-insensitive) are
#'   removed. GBIF downloads can include explicit absence records from
#'   systematic surveys where a species was searched for but not found; these
#'   are non-detections and must not be used as presence data for priors or
#'   occurrence modelling. If the \code{occurrenceStatus} column is absent the
#'   filter is skipped silently.
#' @param require_species Logical. If \code{TRUE}, records where the
#'   \code{species} column is \code{NA} or empty are removed. Default
#'   \code{FALSE}. Set to \code{TRUE} when querying GBIF by family or genus
#'   key: GBIF returns records at all taxonomic ranks within the queried
#'   taxon, including observations identified only to family or genus level.
#'   Those coarse-rank records lack a \code{species} value and are unusable
#'   downstream in TaxaAssign. If the \code{species} column is absent, this
#'   filter is skipped with a message.
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
#' @param exclude_equal_coords Logical. If \code{TRUE} (default), records
#'   where \code{decimalLatitude} exactly equals \code{decimalLongitude}
#'   are removed (\code{CoordinateCleaner::cc_equ()}) -- a common
#'   data-entry/field-swap signature. Skipped with a message if the
#'   \code{CoordinateCleaner} package is not installed.
#' @param exclude_near_zero Logical. If \code{TRUE} (default), records near
#'   the (0, 0) "Null Island" point are removed
#'   (\code{CoordinateCleaner::cc_zero()}), using that function's own
#'   default buffer. This catches near-zero coordinates that fall short of
#'   GBIF's own exact-zero \code{ZERO_COORDINATE} issue flag. Skipped with a
#'   message if \code{CoordinateCleaner} is not installed.
#' @param exclude_near_gbif_hq Logical. If \code{TRUE} (default), records
#'   near GBIF's Copenhagen headquarters are removed
#'   (\code{CoordinateCleaner::cc_gbif()}), using that function's own
#'   default buffer -- catches a known GBIF pathology where a failed
#'   geocode silently defaults to GBIF's own office coordinates. Skipped
#'   with a message if \code{CoordinateCleaner} is not installed.
#' @param exclude_country_centroid Logical. If \code{TRUE} (default),
#'   records near a country or province centroid are removed
#'   (\code{CoordinateCleaner::cc_cen()}), using that function's own
#'   default buffer and bundled reference data (\code{test = "both"}) --
#'   catches coarse/administrative-level georeferencing that silently
#'   snapped to a centroid instead of a true locality. Skipped with a
#'   message if \code{CoordinateCleaner} is not installed.
#' @param exclude_capital Logical. If \code{TRUE} (default), records near a
#'   national capital are removed (\code{CoordinateCleaner::cc_cap()}),
#'   using that function's own default buffer and bundled reference data --
#'   a related, wider-radius version of the same coarse-georeferencing
#'   pathology \code{exclude_country_centroid} targets. Skipped with a
#'   message if \code{CoordinateCleaner} is not installed.
#' @param flag_institution Logical. If \code{TRUE} (default), records near a
#'   biodiversity institution (museum, zoo, herbarium, university) are
#'   \strong{flagged, not removed} (\code{CoordinateCleaner::cc_inst()}),
#'   using that function's own default buffer and bundled ~10,000-location
#'   reference table. Unlike every other \code{CoordinateCleaner} check in
#'   this function, proximity to an institution is not treated as an
#'   unambiguous error: field stations and marine labs are frequently sited
#'   exactly where good habitat is, so a nearby record may be a genuine wild
#'   observation, not an archived/captive specimen -- that judgment call
#'   needs a human (and often a map), not a silent drop. Adds six columns
#'   to the \strong{retained} data (see Value): \code{institution_flag},
#'   \code{institution_name}, \code{institution_type},
#'   \code{institution_dist_m}, \code{institution_lon}, \code{institution_lat}
#'   (the matched institution's own location, distinct from the record's own
#'   coordinates -- lets a downstream map-review tool plot both together).
#'   Skipped with a message if \code{CoordinateCleaner} is not installed.
#'
#' @return The input data frame with low-quality rows removed. Column
#'   structure is unchanged. A summary message reports the number of
#'   records retained.
#'
#'   Every removed record is also preserved, not just counted:
#'   \code{attr(result, "removed_records")} is a data frame with the same
#'   columns as the input plus \code{filter_reason}, one row per removed
#'   record (always present, possibly zero rows -- never \code{NULL}, so it
#'   can be inspected unconditionally). \code{filter_reason} identifies
#'   which filter removed the record: \code{"missing_coordinates"},
#'   \code{"absent_occurrence"}, \code{"basis_of_record"},
#'   \code{"flagged_issue_code:<code>"} (the specific \code{bad_issues} code
#'   that matched, not just that one did), \code{"coordinate_uncertainty"},
#'   \code{"coordinate_decimal_precision"}, \code{"edna_keyword"},
#'   \code{"no_species_id"}, or one or more of \code{"equal_coordinates"} /
#'   \code{"near_zero"} / \code{"near_gbif_hq"} / \code{"country_centroid"} /
#'   \code{"capital"} joined with \code{";"} when a \code{CoordinateCleaner}
#'   record was flagged by more than one of those five checks at once. A
#'   record is removed by exactly the filter that catches it first (filters
#'   run sequentially -- see Details), except within the
#'   \code{CoordinateCleaner} removal step itself, where several checks run
#'   against the same surviving data and any that flag a given record are
#'   all recorded together. Institution proximity is deliberately never a
#'   \code{filter_reason} value -- see the next paragraph.
#'
#'   Separately, the \strong{retained} data frame itself gains six columns
#'   when \code{flag_institution = TRUE} (the default):
#'   \code{institution_flag} (logical), \code{institution_name},
#'   \code{institution_type}, \code{institution_dist_m} (metres, to the
#'   nearest match), and \code{institution_lon}/\code{institution_lat} (that
#'   institution's own coordinates). Unlike everything in
#'   \code{removed_records}, these rows are never removed -- proximity to a
#'   biodiversity institution is flagged
#'   for human review, not treated as an automatic error. See
#'   \code{flag_institution}'s own documentation below for why.
#'
#' @details
#' \strong{Filter order:} Coordinates -> absent occurrences -> basis of record
#' -> issue codes -> coordinate uncertainty -> coordinate decimal-place
#' precision -> eDNA -> species-level requirement -> CoordinateCleaner removal
#' checks (equal coordinates / near-zero / near GBIF HQ / near a country or
#' province centroid / near a national capital) -> institution flagging
#' (retained, not removed).
#' Applying cheaper filters first reduces unnecessary string operations on
#' large datasets.
#'
#' \strong{Why keep the removed records at all:} two users who ran this
#' function with different arguments (a different \code{max_coord_uncertainty},
#' a different \code{bad_issues} set, \code{CoordinateCleaner} installed or
#' not) can otherwise get silently different results with no way to compare
#' notes. \code{attr(result, "removed_records")} makes that difference
#' inspectable rather than invisible, and doubles as a direct list of
#' candidate real GBIF data-quality problems (mislabelled coordinates,
#' institution/centroid-snapped georeferencing) worth reporting back to the
#' original data provider -- every original column, including \code{gbifID}
#' and \code{datasetKey}, is preserved on each removed record for exactly
#' that purpose.
#'
#' \strong{CoordinateCleaner checks use that package's own defaults:} this
#' function deliberately does not hard-code any of \code{cc_zero()}'s,
#' \code{cc_gbif()}'s, \code{cc_cen()}'s, \code{cc_cap()}'s, or
#' \code{cc_inst()}'s buffers, reference coordinates, or reference data
#' itself -- all are called directly with only \code{lon}/\code{lat}/
#' \code{value} supplied (\code{cc_cen()}/\code{cc_cap()}/\code{cc_inst()}
#' resolve their own \code{ref = NULL} default to that package's bundled
#' \code{countryref}/\code{institutions} data automatically, with no network
#' call), so any future correction to those defaults in
#' \code{CoordinateCleaner} is inherited automatically rather than silently
#' diverging from a hand-copied constant.
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
#'   \code{\link{download_gbif_occurrences}},
#'   \code{\link{stack_occurrences}}
#'
#' @importFrom dplyr bind_rows
#' @export
#'
#' @examples
#' \dontrun{
#' # Default filters (500 m uncertainty threshold, no decimal-place filter)
#' clean <- filter_gbif_quality(gbif_raw)
#'
#' # See exactly what got removed and why
#' removed <- attr(clean, "removed_records")
#' table(removed$filter_reason)
#'
#' # Stricter: require at least 3 decimal places (~111 m) in at least one coord
#' clean <- filter_gbif_quality(gbif_raw, max_coord_decimal_places = 3)
#'
#' # Disable the uncertainty filter
#' clean <- filter_gbif_quality(gbif_raw, max_coord_uncertainty = Inf)
#'
#' # Disable the CoordinateCleaner-backed checks (e.g. package not installed)
#' clean <- filter_gbif_quality(
#'   gbif_raw,
#'   exclude_equal_coords     = FALSE,
#'   exclude_near_zero        = FALSE,
#'   exclude_near_gbif_hq     = FALSE,
#'   exclude_country_centroid = FALSE,
#'   exclude_capital          = FALSE,
#'   flag_institution         = FALSE
#' )
#'
#' # Institution-flagged records are RETAINED, not removed -- review them
#' clean[
#'   clean$institution_flag %in% TRUE,
#'   c("species", "institution_name", "institution_type", "institution_dist_m")
#' ]
#'
#' # Compare thresholds
#' nrow(filter_gbif_quality(gbif_raw, max_coord_uncertainty = 500))
#' nrow(filter_gbif_quality(gbif_raw, max_coord_uncertainty = 1000))
#' nrow(filter_gbif_quality(gbif_raw, max_coord_uncertainty = Inf))
#' }
filter_gbif_quality <- function(
  data,
  basis_keep = c(
    "HUMAN_OBSERVATION", "MACHINE_OBSERVATION",
    "LIVING_SPECIMEN", "PRESERVED_SPECIMEN"
  ),
  exclude_edna = TRUE,
  exclude_absent = TRUE,
  bad_issues = c(
    "COORDINATE_OUT_OF_RANGE",
    "COUNTRY_COORDINATE_MISMATCH",
    "COORDINATE_INVALID",
    "ZERO_COORDINATE",
    "COORDINATE_PRECISION_INVALID"
  ),
  max_coord_uncertainty = 500,
  max_coord_decimal_places = NULL,
  require_species = FALSE,
  exclude_equal_coords = TRUE,
  exclude_near_zero = TRUE,
  exclude_near_gbif_hq = TRUE,
  exclude_country_centroid = TRUE,
  exclude_capital = TRUE,
  flag_institution = TRUE
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
    stop(
      "filter_gbif_quality: missing required columns: ",
      paste(setdiff(required_coord_cols, names(data)), collapse = ", ")
    )
  }

  # Empty-shape template for removed_records when nothing is ever removed --
  # built from the original input, since no step here drops columns.
  removed_template <- data[0, , drop = FALSE]
  removed_template$filter_reason <- character(0)
  removed_list <- list()

  keep <- !is.na(data$decimalLatitude) & !is.na(data$decimalLongitude)
  removed_list <- .track_removed(
    removed_list, data[!keep, , drop = FALSE],
    "missing_coordinates"
  )
  if (any(!keep)) {
    message(sprintf("  Removed %d records with missing coordinates.", sum(!keep)))
  }
  data <- data[keep, , drop = FALSE]

  # --- 2. Absent occurrences --------------------------------------------------
  if (exclude_absent && "occurrenceStatus" %in% names(data)) {
    keep <- is.na(data$occurrenceStatus) |
      toupper(trimws(data$occurrenceStatus)) != "ABSENT"
    removed_list <- .track_removed(
      removed_list, data[!keep, , drop = FALSE],
      "absent_occurrence"
    )
    if (any(!keep)) {
      message(sprintf(
        "  Removed %d absent-occurrence records (occurrenceStatus = ABSENT).",
        sum(!keep)
      ))
    }
    data <- data[keep, , drop = FALSE]
  }

  # --- 3. Basis of record -----------------------------------------------------
  if (!"basisOfRecord" %in% names(data)) {
    message("filter_gbif_quality: 'basisOfRecord' column not found -- skipping basis filter.")
  } else {
    # Normalize case/whitespace before comparing, matching the same
    # defensive treatment already applied to occurrenceStatus above
    # (2026-08 human review) -- basisOfRecord is a controlled Darwin Core
    # vocabulary and GBIF-native data is consistently upper-case already,
    # so this is a no-op for the default basis_keep against real GBIF data,
    # but protects against stray whitespace/case drift from any non-GBIF
    # source merged into the same pipeline.
    keep <- toupper(trimws(data$basisOfRecord)) %in% toupper(trimws(basis_keep))
    removed_list <- .track_removed(
      removed_list, data[!keep, , drop = FALSE],
      "basis_of_record"
    )
    if (any(!keep)) {
      message(sprintf(
        "  Removed %d records with excluded basis of record.",
        sum(!keep)
      ))
    }
    data <- data[keep, , drop = FALSE]
  }

  # --- 4. GBIF issue codes ----------------------------------------------------
  if (!"issues" %in% names(data)) {
    message("filter_gbif_quality: 'issues' column not found -- skipping issue filter.")
  } else if (length(bad_issues) > 0L) {
    issue_pattern <- paste(bad_issues, collapse = "|")
    keep <- is.na(data$issues) | !grepl(issue_pattern, data$issues, fixed = FALSE)
    removed_rows <- data[!keep, , drop = FALSE]
    if (nrow(removed_rows) > 0L) {
      matched <- vapply(strsplit(removed_rows$issues, ";"), function(codes) {
        paste(intersect(trimws(codes), bad_issues), collapse = ";")
      }, character(1L))
      removed_rows$filter_reason <- paste0("flagged_issue_code:", matched)
      removed_list <- .track_removed(removed_list, removed_rows)
      message(sprintf(
        "  Removed %d records with flagged geospatial issues.",
        nrow(removed_rows)
      ))
    }
    data <- data[keep, , drop = FALSE]
  }

  # --- 5. Coordinate uncertainty ----------------------------------------------
  if (!is.finite(max_coord_uncertainty)) {
    # Inf or NaN passed -- skip silently
  } else if (!"coordinateUncertaintyInMeters" %in% names(data)) {
    message("filter_gbif_quality: 'coordinateUncertaintyInMeters' column not found -- skipping uncertainty filter.")
  } else {
    keep <- is.na(data$coordinateUncertaintyInMeters) |
      data$coordinateUncertaintyInMeters <= max_coord_uncertainty
    removed_list <- .track_removed(
      removed_list, data[!keep, , drop = FALSE],
      "coordinate_uncertainty"
    )
    if (any(!keep)) {
      message(sprintf(
        "  Removed %d records with coordinateUncertaintyInMeters > %g m.",
        sum(!keep), max_coord_uncertainty
      ))
    }
    data <- data[keep, , drop = FALSE]
  }

  # --- 6. Coordinate decimal-place precision ----------------------------------
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
    keep <- (lat_dp >= d) | (lon_dp >= d)
    removed_list <- .track_removed(
      removed_list, data[!keep, , drop = FALSE],
      "coordinate_decimal_precision"
    )
    if (any(!keep)) {
      message(sprintf(
        "  Removed %d records where both coordinates have fewer than %d decimal place(s).",
        sum(!keep), d
      ))
    }
    data <- data[keep, , drop = FALSE]
  }

  # --- 7. eDNA / metabarcoding removal ----------------------------------------
  if (exclude_edna) {
    edna_cols <- intersect(
      c("samplingProtocol", "occurrenceRemarks", "preparations"),
      names(data)
    )
    edna_cols <- edna_cols[vapply(data[edna_cols], is.character, logical(1L))]
    if (length(edna_cols) == 0L) {
      message("filter_gbif_quality: no eDNA-detectable character columns found -- skipping eDNA filter.")
    } else {
      # "bulk sample"/"water sample" alone are deliberately excluded from
      # this pattern -- both phrases are generic enough to appear in
      # non-eDNA methods (plankton tows, water-quality-linked collection
      # remarks) and would over-exclude legitimate presence data. Real GBIF
      # eDNA/metabarcoding datasets consistently self-label with one of the
      # three terms below.
      edna_pattern <- paste("edna", "environmental dna", "metabarcod", sep = "|")
      search_text <- do.call(
        paste,
        c(
          lapply(edna_cols, function(col) {
            x <- data[[col]]
            ifelse(is.na(x), "", x)
          }),
          sep = " "
        )
      )
      keep <- !grepl(edna_pattern, search_text, ignore.case = TRUE)
      removed_list <- .track_removed(
        removed_list, data[!keep, , drop = FALSE],
        "edna_keyword"
      )
      if (any(!keep)) {
        message(sprintf("  Removed %d eDNA/metabarcoding records.", sum(!keep)))
      }
      data <- data[keep, , drop = FALSE]
    }
  }

  # --- 8. Species-level requirement -------------------------------------------
  if (require_species) {
    if (!"species" %in% names(data)) {
      message("filter_gbif_quality: 'species' column not found -- skipping require_species filter.")
    } else {
      keep <- !is.na(data$species) & nzchar(data$species)
      removed_list <- .track_removed(
        removed_list, data[!keep, , drop = FALSE],
        "no_species_id"
      )
      if (any(!keep)) {
        message(sprintf(
          "  Removed %d records with no species-level identification.",
          sum(!keep)
        ))
      }
      data <- data[keep, , drop = FALSE]
    }
  }

  # --- 9. CoordinateCleaner REMOVAL checks (equal coords / near-zero / near
  #        GBIF HQ / near country centroid / near capital) -------------------
  # Institution proximity is deliberately NOT in this list -- see step 10.
  # Field stations and marine labs are often sited exactly where good habitat
  # is, so "near an institution" can't be auto-removed the way the other five
  # (unambiguous data-entry-error signatures) can; it needs a flag a human
  # reviews, not a silent drop. See filter_gbif_quality.R's own 2026-07-23
  # session note (TaxaFetch/CLAUDE.md) for the real false-positive case (live
  # fish records near a university botanical garden pond) that motivated this.
  cc_remove_requested <- exclude_equal_coords || exclude_near_zero ||
    exclude_near_gbif_hq || exclude_country_centroid || exclude_capital
  cc_pkg_available <- TRUE
  if ((cc_remove_requested || flag_institution) && nrow(data) > 0L) {
    if (!requireNamespace("CoordinateCleaner", quietly = TRUE)) {
      cc_pkg_available <- FALSE
      message(
        "filter_gbif_quality: package 'CoordinateCleaner' not installed -- ",
        "skipping equal-coordinate/near-zero/near-GBIF-HQ/near-centroid/",
        "near-capital removal checks and institution flagging."
      )
    } else if (cc_remove_requested) {
      n_before_cc <- nrow(data)
      cc_results <- list()
      if (exclude_equal_coords) {
        cc_results[["equal_coordinates"]] <- CoordinateCleaner::cc_equ(
          x = data, lon = "decimalLongitude", lat = "decimalLatitude",
          value = "flagged", verbose = FALSE
        )
      }
      if (exclude_near_zero) {
        cc_results[["near_zero"]] <- CoordinateCleaner::cc_zero(
          x = data, lon = "decimalLongitude", lat = "decimalLatitude",
          value = "flagged", verbose = FALSE
        )
      }
      if (exclude_near_gbif_hq) {
        cc_results[["near_gbif_hq"]] <- CoordinateCleaner::cc_gbif(
          x = data, lon = "decimalLongitude", lat = "decimalLatitude",
          value = "flagged", verbose = FALSE
        )
      }
      if (exclude_country_centroid) {
        cc_results[["country_centroid"]] <- CoordinateCleaner::cc_cen(
          x = data, lon = "decimalLongitude", lat = "decimalLatitude",
          value = "flagged", verbose = FALSE
        )
      }
      if (exclude_capital) {
        cc_results[["capital"]] <- CoordinateCleaner::cc_cap(
          x = data, lon = "decimalLongitude", lat = "decimalLatitude",
          value = "flagged", verbose = FALSE
        )
      }

      keep <- Reduce(`&`, cc_results, rep(TRUE, n_before_cc))
      removed_rows <- data[!keep, , drop = FALSE]
      if (nrow(removed_rows) > 0L) {
        # A record can fail more than one of these checks at once (e.g. near
        # both a centroid and GBIF HQ) -- all reasons are joined with ";".
        reason_matrix <- vapply(
          cc_results, function(pass) !pass[!keep],
          logical(nrow(removed_rows))
        )
        if (is.null(dim(reason_matrix))) {
          reason_matrix <- matrix(reason_matrix,
            nrow = nrow(removed_rows),
            dimnames = list(NULL, names(cc_results))
          )
        }
        removed_rows$filter_reason <- apply(reason_matrix, 1L, function(r) {
          paste(names(cc_results)[r], collapse = ";")
        })
        removed_list <- .track_removed(removed_list, removed_rows)
        message(sprintf(
          paste0(
            "  Removed %d records via CoordinateCleaner checks ",
            "(equal coordinates / near-zero / near GBIF HQ / near country ",
            "centroid / near capital)."
          ),
          nrow(removed_rows)
        ))
      }
      data <- data[keep, , drop = FALSE]
    }
  }

  # --- 10. Institution proximity -- FLAG, do not remove -----------------------
  # Runs on whatever survived step 9, so a record near BOTH e.g. a country
  # centroid (removed above) and an institution never reaches here at all.
  if (flag_institution && cc_pkg_available && nrow(data) > 0L) {
    inst_pass <- CoordinateCleaner::cc_inst(
      x = data, lon = "decimalLongitude", lat = "decimalLatitude",
      value = "flagged", verbose = FALSE
    )
    data$institution_flag <- !inst_pass
    data$institution_name <- NA_character_
    data$institution_type <- NA_character_
    data$institution_dist_m <- NA_real_
    data$institution_lon <- NA_real_
    data$institution_lat <- NA_real_

    if (any(data$institution_flag)) {
      matched <- .nearest_institution(
        data$decimalLongitude[data$institution_flag],
        data$decimalLatitude[data$institution_flag]
      )
      data$institution_name[data$institution_flag] <- matched$name
      data$institution_type[data$institution_flag] <- matched$type
      data$institution_dist_m[data$institution_flag] <- matched$dist_m
      data$institution_lon[data$institution_flag] <- matched$inst_lon
      data$institution_lat[data$institution_flag] <- matched$inst_lat
      message(sprintf(
        paste0(
          "  Flagged %d records within an institution's proximity -- ",
          "retained, not removed. See institution_flag/institution_name/",
          "institution_type/institution_dist_m/institution_lon/institution_lat."
        ),
        sum(data$institution_flag)
      ))
    }
  }

  message(sprintf(
    "filter_gbif_quality: %d records retained of %d (%.1f%%).",
    nrow(data), n_start, 100 * nrow(data) / max(n_start, 1L)
  ))

  removed_records <- if (length(removed_list) > 0L) {
    dplyr::bind_rows(removed_list)
  } else {
    removed_template
  }
  attr(data, "removed_records") <- removed_records

  data
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Find the nearest CoordinateCleaner::institutions match for each point
#'
#' Used only for points \code{cc_inst()} has already flagged (\code{value =
#' "flagged"} only returns a logical -- this recovers which institution it
#' actually matched, needed for human review downstream). Haversine distance
#' against the full bundled institutions table; the point count here is
#' always small (only flagged rows), so no attempt is made to replicate
#' \code{cc_inst()}'s own internal spatial-indexing performance path.
#'
#' @param lon,lat Numeric vectors, same length, coordinates of flagged points.
#' @return A data frame (one row per input point) with \code{name},
#'   \code{type}, \code{dist_m}, \code{inst_lon}, \code{inst_lat} of the
#'   nearest institution. \code{inst_lon}/\code{inst_lat} (the institution's
#'   OWN location, distinct from the input point) exist specifically so a
#'   downstream map-review tool can plot both the flagged record and its
#'   matched institution together, without re-querying
#'   \code{CoordinateCleaner::institutions} itself.
#' @noRd
.nearest_institution <- function(lon, lat) {
  ref <- CoordinateCleaner::institutions
  ref <- ref[!is.na(ref$decimalLongitude) & !is.na(ref$decimalLatitude), ]

  earth_radius_m <- 6371000
  deg2rad <- pi / 180

  rows <- lapply(seq_along(lon), function(i) {
    dlat <- (ref$decimalLatitude - lat[i]) * deg2rad
    dlon <- (ref$decimalLongitude - lon[i]) * deg2rad
    a <- sin(dlat / 2)^2 +
      cos(lat[i] * deg2rad) * cos(ref$decimalLatitude * deg2rad) * sin(dlon / 2)^2
    d <- 2 * earth_radius_m * asin(pmin(1, sqrt(a)))
    idx <- which.min(d)
    data.frame(
      name = ref$name[idx],
      type = ref$type[idx],
      dist_m = round(d[idx], 1),
      inst_lon = ref$decimalLongitude[idx],
      inst_lat = ref$decimalLatitude[idx],
      stringsAsFactors = FALSE
    )
  })
  dplyr::bind_rows(rows)
}

#' Append removed rows (with a filter_reason column) to the running list
#'
#' @param removed_list List of data frames accumulated so far.
#' @param removed_rows Data frame of rows removed at this step. If it
#'   already has a \code{filter_reason} column (per-row reasons, e.g. issue
#'   codes or combined CoordinateCleaner checks), that is used as-is; a
#'   single \code{reason} string is recycled across all rows otherwise.
#' @param reason Character. Single reason string, ignored if
#'   \code{removed_rows} already has its own \code{filter_reason} column.
#' @return Updated list.
#' @noRd
.track_removed <- function(removed_list, removed_rows, reason = NULL) {
  if (nrow(removed_rows) == 0L) {
    return(removed_list)
  }
  if (is.null(removed_rows[["filter_reason"]])) {
    removed_rows$filter_reason <- reason
  }
  c(removed_list, list(removed_rows))
}

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
  result <- integer(length(v)) # initialise all to 0L
  finite_mask <- !is.na(v) & is.finite(v)
  if (any(finite_mask)) {
    result[finite_mask] <- vapply(v[finite_mask], function(x) {
      for (d in 0:10) {
        if (isTRUE(all.equal(round(x, d), x, tolerance = 1e-9))) {
          return(d)
        }
      }
      10L
    }, integer(1L))
  }
  result
}
