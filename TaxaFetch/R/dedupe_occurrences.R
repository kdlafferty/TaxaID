# ==============================================================================
# dedupe_occurrences.R
# TaxaFetch -- Remove duplicate/redundant occurrence records
# ==============================================================================

#' Remove Duplicate Occurrence Records
#'
#' Removes duplicate occurrence records from a single data frame via two
#' independent mechanisms -- an exact-ID match on \code{gbifID}, and a
#' content-based match on species x date x coarse location. Deliberately
#' separate from \code{\link{stack_occurrences}}: deduplication is relevant
#' whether or not you are combining multiple sources, since duplicates can
#' occur entirely within a single fetch (see Details) -- a caller with only
#' one data source has no reason to skip this step, unlike
#' \code{stack_occurrences} itself.
#'
#' @param data A single data frame of occurrence records, typically the
#'   output of \code{\link{get_gbif_occurrences}}, \code{\link{stack_occurrences}},
#'   or any other TaxaFetch source function.
#' @param collapse_duplicate_occasions Logical. Default \code{TRUE}. Collapse
#'   rows describing the same species x date x location \emph{detection
#'   occasion} to one row, keeping the first. Unlike the \code{gbifID} check
#'   below (an exact-ID match, unambiguous), this is a content-based match --
#'   see Details for what it is for and why it defaults on.
#' @param taxon_col Character. Name of the taxon-identity column used to key
#'   \code{collapse_duplicate_occasions}. Default \code{"scientificName"} --
#'   every current TaxaFetch source (GBIF, DataONE, BioTime, literature/PDF)
#'   already produces this column under this exact name. Ignored if
#'   \code{collapse_duplicate_occasions = FALSE}.
#' @param date_col Character. Name of the date column used to key
#'   \code{collapse_duplicate_occasions}. Default \code{"eventDate"}. Falls
#'   back to a \code{year}/\code{month}/\code{day} triple (constructed as
#'   \code{"YYYY-MM-DD"}) for any row where \code{date_col} is absent or
#'   \code{NA} -- needed because \code{get_gbif_occurrences()}'s
#'   \code{"standard"} column set carries \code{year}/\code{month}/\code{day}
#'   but not \code{eventDate} itself. Ignored if
#'   \code{collapse_duplicate_occasions = FALSE}.
#' @param lat_col Character. Name of the latitude column, used to key
#'   \code{collapse_duplicate_occasions}. Default \code{"decimalLatitude"}.
#' @param lon_col Character. Name of the longitude column, used to key
#'   \code{collapse_duplicate_occasions}. Default \code{"decimalLongitude"}.
#' @param coord_precision Integer. Decimal places \code{lat_col}/\code{lon_col}
#'   are rounded to before matching in \code{collapse_duplicate_occasions}.
#'   Default \code{3} (~111 m at the equator). Ignored if
#'   \code{collapse_duplicate_occasions = FALSE}.
#'
#' @return \code{data} as a tibble with duplicate rows removed. If a
#'   \code{report_params} attribute is present (as attached by
#'   \code{\link{stack_occurrences}}), its \code{n_records} entry is
#'   refreshed to the post-dedup row count and a \code{n_duplicates_removed}
#'   entry is added.
#'
#' @details
#' \strong{gbifID deduplication:} If \code{data} has a \code{gbifID} column,
#' rows with a duplicated non-\code{NA} \code{gbifID} are dropped (first
#' occurrence kept). This is defense-in-depth against the same GBIF record
#' being counted twice -- e.g. two separately-issued queries with overlapping
#' search geometry, or a genuinely coincidental overlap between
#' separately-fetched taxa -- since neither \code{\link{get_gbif_occurrences}}
#' nor \code{\link{filter_gbif_quality}} dedupe records themselves. This can
#' happen within a \emph{single} \code{get_gbif_occurrences()} call (e.g. one
#' call querying overlapping taxon keys), not only when combining sources.
#' Sources without a \code{gbifID} column (e.g. literature or DataONE
#' occurrences) are unaffected.
#'
#' \strong{Duplicate detection occasions (\code{collapse_duplicate_occasions}):}
#' a different problem than the \code{gbifID} check above. That check catches
#' the identical GBIF record entering twice; this one catches \emph{different}
#' records -- often from different platforms and different observers
#' entirely -- that describe the same underlying detection event. GBIF
#' aggregates eBird, iNaturalist, Observation.org, OBIS, and museum
#' collections (see \code{\link{get_gbif_occurrences}}'s own Details), and
#' citizen-science platforms routinely produce many independent reports of
#' one detection: a rare-bird alert can draw dozens of separate eBird
#' checklists for the same individual; a bioblitz can produce a dozen
#' separate iNaturalist uploads of the same local population on the same day.
#' Each of those is a genuinely distinct GBIF record (a distinct \code{gbifID},
#' so the check above does not touch them) but not a distinct \emph{occasion}
#' on which the species was documented -- and critically, this can all happen
#' inside \emph{one} \code{get_gbif_occurrences()} call, since GBIF is the
#' aggregator across all of those platforms. A caller with only one data
#' source is not exempt from this.
#'
#' This matters beyond bookkeeping: \code{TaxaExpect::prepare_model_dataframe()}
#' counts raw records (\code{dplyr::n()}) as both \code{n_species} (the
#' binomial numerator for a taxon at a site) and \code{n_total_at_site} (the
#' shared effort denominator across every taxon at that site). Uncollapsed
#' repeat reports of one individual therefore inflate that species' modeled
#' relative detection frequency directly, not just its raw record count --
#' the model has no way to distinguish "documented once, seen by ten
#' observers" from "documented independently ten separate times." Collapsing
#' to one row per unique combination of \code{taxon_col} (case-insensitive),
#' \code{date_col} (or \code{year}/\code{month}/\code{day} when
#' \code{date_col} is absent), and \code{lat_col}/\code{lon_col} rounded to
#' \code{coord_precision} answers the occupancy-modeling question this
#' ecosystem actually wants: \emph{was the species documented here, on this
#' occasion} -- not \emph{how many people documented it}.
#'
#' Only rows with a non-missing value for every key component participate --
#' a row missing \code{taxon_col}, both \code{date_col} and
#' \code{year}/\code{month}/\code{day}, or either coordinate is always kept,
#' never dropped on incomplete information. This is a content-based match, not
#' an exact-ID match like \code{gbifID} -- it can only ever produce false
#' negatives (a real duplicate occasion missed, e.g. differing date precision
#' or coordinate rounding across platforms), never false positives, since two
#' records agreeing on species, date, and location to ~100 m are extremely
#' unlikely to be genuinely independent occasions. Set
#' \code{collapse_duplicate_occasions = FALSE} to keep one row per raw report
#' instead (e.g. if you deliberately want observer-effort/reporting-volume as
#' your own signal, rather than TaxaExpect's occupancy framing).
#'
#' \strong{Silent no-op on missing columns:} if \code{gbifID} is absent, that
#' check is skipped with no message. If \code{taxon_col}/\code{date_col} (and
#' no \code{year}/\code{month}/\code{day} triple) are absent,
#' \code{collapse_duplicate_occasions} is skipped with no message. Neither
#' condition is treated as an error -- a caller working with a data source
#' that genuinely lacks these columns should not see noise on every call.
#'
#' @seealso \code{\link{stack_occurrences}}, \code{\link{get_gbif_occurrences}},
#'   \code{\link[TaxaExpect]{prepare_model_dataframe}}
#'
#' @export
#'
#' @examples
#' \dontrun{
#' # Single source -- still worth deduping (see Details)
#' occ <- get_gbif_occurrences(keys, bbox)
#' occ <- dedupe_occurrences(occ)
#'
#' # Multiple sources -- dedupe after combining, so cross-platform occasion
#' # duplicates (only visible once sources are combined) are caught too
#' occ <- stack_occurrences(gbif_occ, dataone_occ)
#' occ <- dedupe_occurrences(occ)
#' }
dedupe_occurrences <- function(data,
                                collapse_duplicate_occasions = TRUE,
                                taxon_col = "scientificName",
                                date_col = "eventDate",
                                lat_col = "decimalLatitude",
                                lon_col = "decimalLongitude",
                                coord_precision = 3L) {

  if (!is.data.frame(data)) {
    stop("dedupe_occurrences: 'data' must be a data frame.", call. = FALSE)
  }

  out           <- data
  n_gbifid_dup  <- 0L
  n_occasion_dup <- 0L

  # --- Dedup by gbifID (see @details) ------------------------------------------
  if ("gbifID" %in% names(out)) {
    is_dup <- duplicated(out$gbifID) & !is.na(out$gbifID)
    if (any(is_dup)) {
      n_gbifid_dup <- sum(is_dup)
      message(sprintf(
        "dedupe_occurrences: dropped %d record(s) with a duplicate gbifID.",
        n_gbifid_dup
      ))
      out <- out[!is_dup, , drop = FALSE]
    }
  }

  # --- Collapse duplicate detection occasions (see @details) -------------------
  # Different problem than gbifID above: this catches DIFFERENT records (often
  # different platforms/observers entirely) describing the same underlying
  # detection event -- e.g. several eBird checklists for one rare-bird-alert
  # individual, or several iNaturalist uploads from one bioblitz. Content-based
  # match (species x date x coarse location), not an exact-ID match, so a row
  # missing any key component is always kept, never dropped on incomplete
  # information.
  if (isTRUE(collapse_duplicate_occasions)) {
    has_taxon <- taxon_col %in% names(out)
    has_ymd   <- all(c("year", "month", "day") %in% names(out))
    has_date  <- date_col %in% names(out) || has_ymd

    # Silent no-op when the key columns simply aren't present -- matches the
    # gbifID check's own convention (no message when that column is absent).
    if (has_taxon && has_date) {
      date_key <- if (date_col %in% names(out)) {
        as.character(out[[date_col]])
      } else {
        rep(NA_character_, nrow(out))
      }
      needs_ymd <- is.na(date_key) | !nzchar(date_key)
      if (has_ymd && any(needs_ymd)) {
        date_key[needs_ymd] <- sprintf(
          "%04d-%02d-%02d",
          as.integer(out$year[needs_ymd]),
          as.integer(out$month[needs_ymd]),
          as.integer(out$day[needs_ymd])
        )
      }

      taxon_key <- tolower(trimws(as.character(out[[taxon_col]])))
      lat_key   <- round(out[[lat_col]], coord_precision)
      lon_key   <- round(out[[lon_col]], coord_precision)

      key_complete <- !is.na(taxon_key) & nzchar(taxon_key) &
        !is.na(date_key) & nzchar(date_key) &
        !is.na(lat_key) & !is.na(lon_key)

      occasion_key    <- paste(taxon_key, date_key, lat_key, lon_key, sep = "|")
      is_dup_occasion <- rep(FALSE, nrow(out))
      is_dup_occasion[key_complete] <- duplicated(occasion_key[key_complete])

      if (any(is_dup_occasion)) {
        n_occasion_dup <- sum(is_dup_occasion)
        message(sprintf(
          paste0(
            "dedupe_occurrences: collapsed %d record(s) describing a repeat ",
            "report of the same species x date x location detection ",
            "occasion (e.g. multiple observers at a bioblitz or rare-",
            "species alert) -- see ?dedupe_occurrences, ",
            "collapse_duplicate_occasions."
          ),
          n_occasion_dup
        ))
        out <- out[!is_dup_occasion, , drop = FALSE]
      }
    }
  }

  out <- tibble::as_tibble(out)

  # --- Refresh report_params if present (see @return) --------------------------
  rp <- attr(data, "report_params")
  if (!is.null(rp)) {
    rp$n_records            <- nrow(out)
    rp$n_duplicates_removed <- n_gbifid_dup + n_occasion_dup
    attr(out, "report_params") <- rp
  }

  out
}
