utils::globalVariables("issue")

# ==============================================================================
# get_gbif_occurrences.R
# TaxaFetch -- unified GBIF occurrence fetcher. Picks between
# fetch_gbif_occurrences() (direct API, small queries) and
# download_gbif_occurrences() (async bulk API, large queries) by key count,
# then standardizes both paths' output to one column contract. Neither
# backend function is modified by this wrapper.
# ==============================================================================

#' Fetch GBIF Occurrences -- Unified Entry Point
#'
#' Picks between \code{\link{fetch_gbif_occurrences}} (direct API, small
#' queries) and \code{\link{download_gbif_occurrences}} (async bulk API,
#' large queries) based on the number of distinct \code{keys}, then
#' standardizes both paths' output to one column contract and, by default,
#' filters to species-rank records. This is a thin wrapper -- neither
#' underlying function is modified; see Details for why they stay separate.
#'
#' @param keys Integer or numeric vector. GBIF taxon usage keys, typically
#'   from \code{\link{get_keys_from_context}}. Duplicates are removed before
#'   the key count is compared to \code{key_threshold}.
#' @param geometry Character. WKT polygon (see \code{\link{make_bbox_wkt}}).
#' @param year_range Character. \code{"YYYY,YYYY"}. Default \code{"2000,2024"}.
#' @param limit Integer or \code{NULL}. Per-key record cap, forwarded as-is.
#'   \code{NULL} (default) means "retain all records" on the download path
#'   (its own default); on the fetch path, \code{NULL} is translated to that
#'   function's own default (\code{10000L}) since it does not accept
#'   \code{NULL} directly.
#' @param key_threshold Integer. Number of distinct \code{keys} at or above
#'   which \code{download_gbif_occurrences} is used instead of
#'   \code{fetch_gbif_occurrences}. Default \code{50L}, matching both
#'   functions' own documented guidance. Lower it if the fetch path is
#'   hitting HTTP 429 rate limits below 50 keys; raise it if you would
#'   rather have the fetch path's immediate per-key feedback for a somewhat
#'   larger query and have a stable connection.
#' @param rank_filter Character or \code{FALSE}/\code{NULL}. \code{"species"}
#'   (default) keeps only records where \code{taxonRank} equals this value
#'   (case-insensitive) -- occurrences above species rank (family/genus-only
#'   identifications) are not usable by downstream taxon-level modelling
#'   (TaxaHabitat / TaxaExpect) and every existing caller already drops them
#'   post hoc. Set to \code{FALSE} or \code{NULL} to disable. See Details for
#'   why this is always a post-fetch filter, never a GBIF query predicate.
#' @param columns Character. \code{"standard"} (default) trims and reorders
#'   the output to a curated column set covering the spatial / temporal /
#'   taxonomic / quality fields used by \code{\link{filter_gbif_quality}}
#'   and \code{\link{stack_occurrences}} -- see \code{\link{filter_gbif_quality}}
#'   and Details below for the exact list and a known asymmetry.
#'   \code{"all"} skips trimming entirely (passes \code{select_cols = NULL}
#'   to \code{download_gbif_occurrences}; no trim on the fetch path -- you
#'   get whatever each backend natively returns). A character vector
#'   requests a custom column set instead; columns unavailable from the
#'   backend that fired are filled with \code{NA} rather than dropped, so
#'   the returned column set always matches what was requested.
#' @param cache_dir Character or \code{NULL}. Forwarded to whichever backend
#'   fires. Default \code{tools::R_user_dir("TaxaFetch", "cache")}.
#' @param overwrite Logical. Forwarded to \code{download_gbif_occurrences}
#'   only (no zip cache to overwrite on the fetch path). Default \code{FALSE}.
#' @param exclude_absent,basis_keep,status_ping,gbif_user,gbif_pwd,gbif_email
#'   Forwarded to \code{\link{download_gbif_occurrences}} when that path
#'   fires; see its own documentation. Ignored on the fetch path.
#' @param chunk_size,pause_seconds,pause_between_keys,max_retries Forwarded
#'   to \code{\link{fetch_gbif_occurrences}} when that path fires; see its
#'   own documentation. Ignored on the download path.
#' @param beep Logical. Forwarded to whichever backend fires. Default \code{FALSE}.
#'
#' @details
#' \strong{Why a wrapper, not one merged function:} the two backends have
#' genuinely different execution models. \code{fetch_gbif_occurrences} is
#' client-paced with per-key retries and needs no GBIF account; its cost
#' grows roughly with key count and carries real rate-limit (HTTP 429) risk
#' at high key counts. \code{download_gbif_occurrences} is server-side and
#' account-gated, with a largely fixed queue/prep overhead that does not
#' scale down -- a poor trade for a handful of keys, the right one for
#' hundreds. Their parameter sets barely overlap (one has
#' \code{exclude_absent}/\code{basis_keep}/GBIF credentials; the other has
#' \code{chunk_size}/\code{pause_seconds}/\code{max_retries}). Rather than
#' carry both sets in one function with half silently unused depending on
#' path, this wrapper forwards the relevant subset to whichever backend
#' actually runs and leaves both functions untouched.
#'
#' \strong{Why the rank filter is always post-fetch:} neither GBIF's
#' download predicate API nor \code{occ_data}'s search parameters expose a
#' taxonomic-rank field (confirmed against \code{rgbif}'s own predicate key
#' vocabulary) -- there is no server-side lever to send. The filter is
#' therefore always applied here, after the data comes back, identically
#' regardless of which backend produced it. It reduces R-side memory/size,
#' not GBIF's query cost.
#'
#' \strong{Column standardization and a known, unfixable asymmetry:} the
#' \code{"standard"} column list (see \code{TaxaFetch:::.gbif_standard_columns()})
#' is aligned across both backends, with two corrections applied uniformly:
#' \enumerate{
#'   \item The quality-issue column is renamed to \code{issues} (plural) on
#'     the download path before any column selection happens.
#'     \code{download_gbif_occurrences} imports GBIF's SIMPLE_CSV export,
#'     which names this field \code{issue} (singular); the search API used
#'     by \code{fetch_gbif_occurrences} returns \code{issues} (plural); and
#'     \code{\link{filter_gbif_quality}} checks for \code{issues} --
#'     without this rename, its issue-code filter silently no-ops on every
#'     download-path result (confirmed against a real cached SIMPLE_CSV file
#'     and a live \code{occ_data()} call).
#'   \item \code{familyKey}/\code{genusKey} are \code{NA} on the download
#'     path. This is not something the wrapper can fix: GBIF's SIMPLE_CSV
#'     format does not include these fields at all (they are DWCA-only),
#'     so there is nothing to rename or select -- they are genuinely absent
#'     upstream. \code{fetch_gbif_occurrences} output has them populated.
#'   \item Similarly, \code{samplingProtocol}/\code{occurrenceRemarks}/
#'     \code{preparations} (used by
#'     \code{filter_gbif_quality(exclude_edna = TRUE)}) are not present in
#'     GBIF's SIMPLE_CSV export either, and so are \code{NA} on the
#'     download path; they are included when present on the fetch path.
#' }
#'
#' @return A tibble. When \code{columns != "all"}, the column set and order
#'   are identical regardless of which backend produced the data (missing
#'   columns are \code{NA}-filled, not dropped) -- see Details for the two
#'   backend fields that are always \code{NA} on the download path
#'   specifically. Compatible with \code{\link{filter_gbif_quality}} and
#'   \code{\link{stack_occurrences}}.
#'
#' @seealso \code{\link{fetch_gbif_occurrences}},
#'   \code{\link{download_gbif_occurrences}}, \code{\link{make_bbox_wkt}},
#'   \code{\link{get_keys_from_context}}, \code{\link{filter_gbif_quality}},
#'   \code{\link{stack_occurrences}}
#'
#' @importFrom dplyr any_of as_tibble rename
#' @export
#'
#' @examples
#' \dontrun{
#' taxa_df    <- data.frame(family = "Felidae", stringsAsFactors = FALSE)
#' keys_df    <- get_keys_from_context(taxa_df)
#' valid_keys <- keys_df$usageKey[!is.na(keys_df$usageKey)]
#' bbox       <- make_bbox_wkt(lat = 34.41, lon = -119.86, radius_deg = 3.0)
#'
#' # Few keys -> fetch_gbif_occurrences() fires automatically (no GBIF account
#' # needed). Hundreds of keys -> download_gbif_occurrences() fires instead.
#' occ <- get_gbif_occurrences(
#'   keys       = valid_keys,
#'   geometry   = bbox,
#'   year_range = "2000,2024"
#' )
#' }
get_gbif_occurrences <- function(
    keys,
    geometry,
    year_range         = "2000,2024",
    limit               = NULL,
    key_threshold       = 50L,
    rank_filter         = "species",
    columns             = "standard",
    cache_dir           = tools::R_user_dir("TaxaFetch", "cache"),
    overwrite           = FALSE,
    exclude_absent      = TRUE,
    basis_keep          = NULL,
    status_ping         = 15,
    gbif_user           = Sys.getenv("GBIF_USER"),
    gbif_pwd            = Sys.getenv("GBIF_PWD"),
    gbif_email          = Sys.getenv("GBIF_EMAIL"),
    chunk_size          = 20L,
    pause_seconds       = 2,
    pause_between_keys  = 0.5,
    max_retries         = 4L,
    beep                = FALSE) {

  # --- Input checks -------------------------------------------------------
  keys <- unique(as.integer(keys))
  keys <- keys[!is.na(keys)]
  if (length(keys) == 0L) {
    stop("get_gbif_occurrences: no valid 'keys' supplied.", call. = FALSE)
  }
  if (!is.numeric(key_threshold) || length(key_threshold) != 1L ||
      is.na(key_threshold) || key_threshold <= 0) {
    stop("get_gbif_occurrences: 'key_threshold' must be a single positive number.",
         call. = FALSE)
  }
  if (!(isFALSE(rank_filter) || is.null(rank_filter) ||
        (is.character(rank_filter) && length(rank_filter) == 1L))) {
    stop("get_gbif_occurrences: 'rank_filter' must be a single character ",
         "string, FALSE, or NULL.", call. = FALSE)
  }
  if (!(identical(columns, "standard") || identical(columns, "all") ||
        is.character(columns))) {
    stop("get_gbif_occurrences: 'columns' must be \"standard\", \"all\", ",
         "or a character vector of column names.", call. = FALSE)
  }

  want_cols <- if (identical(columns, "all")) {
    NULL
  } else if (identical(columns, "standard")) {
    .gbif_standard_columns()
  } else {
    columns
  }

  n_keys       <- length(keys)
  use_download <- n_keys >= key_threshold

  if (use_download) {
    message(sprintf(
      "get_gbif_occurrences: %d key(s) >= key_threshold (%d) -- using download_gbif_occurrences() (async bulk API, requires a GBIF account).",
      n_keys, key_threshold
    ))

    # select_cols is a SIMPLE_CSV-native argument -- translate the wrapper's
    # canonical "issues" name to SIMPLE_CSV's actual "issue" column before
    # requesting it (see @details); everything else passes through unchanged.
    select_cols_dl <- if (is.null(want_cols)) {
      NULL
    } else {
      ifelse(want_cols == "issues", "issue", want_cols)
    }

    raw <- download_gbif_occurrences(
      keys           = keys,
      geometry       = geometry,
      year_range     = year_range,
      limit          = limit,
      cache_dir      = cache_dir,
      overwrite      = overwrite,
      status_ping    = status_ping,
      exclude_absent = exclude_absent,
      basis_keep     = basis_keep,
      select_cols    = select_cols_dl,
      gbif_user      = gbif_user,
      gbif_pwd       = gbif_pwd,
      gbif_email     = gbif_email,
      beep           = beep
    )

    # Known asymmetry (see @details, point 1): SIMPLE_CSV names this column
    # "issue" (singular); rename to the wrapper's canonical "issues" so
    # filter_gbif_quality()'s issue-code filter works regardless of source.
    if ("issue" %in% names(raw) && !"issues" %in% names(raw)) {
      raw <- dplyr::rename(raw, issues = issue)
    }

  } else {
    message(sprintf(
      "get_gbif_occurrences: %d key(s) < key_threshold (%d) -- using fetch_gbif_occurrences() (direct API, no GBIF account needed).",
      n_keys, key_threshold
    ))

    raw <- fetch_gbif_occurrences(
      keys               = keys,
      geometry           = geometry,
      year_range         = year_range,
      limit              = if (is.null(limit)) 10000L else limit,
      chunk_size         = chunk_size,
      pause_seconds      = pause_seconds,
      pause_between_keys = pause_between_keys,
      max_retries        = max_retries,
      cache_dir          = cache_dir,
      beep               = beep
    )
  }

  if (nrow(raw) == 0L) {
    warning("get_gbif_occurrences: no records returned.", call. = FALSE)
    return(dplyr::as_tibble(raw))
  }

  # --- Standardize columns (fixed schema regardless of backend) -----------
  if (!is.null(want_cols)) {
    missing_cols <- setdiff(want_cols, names(raw))
    for (col in missing_cols) raw[[col]] <- NA
    raw <- raw[, want_cols, drop = FALSE]
  }

  # --- Species-rank filter (post-fetch only -- see @details) ---------------
  if (!isFALSE(rank_filter) && !is.null(rank_filter)) {
    if (!"taxonRank" %in% names(raw)) {
      message("get_gbif_occurrences: 'taxonRank' column not found -- skipping rank_filter.")
    } else {
      n_before <- nrow(raw)
      raw <- raw[toupper(raw$taxonRank) == toupper(rank_filter), , drop = FALSE]
      message(sprintf(
        "get_gbif_occurrences: rank_filter = \"%s\" -- retained %d/%d record(s).",
        rank_filter, nrow(raw), n_before
      ))
    }
  }

  dplyr::as_tibble(raw)
}

# ==============================================================================
# Internal helpers
# ==============================================================================

#' @noRd
.gbif_standard_columns <- function() {
  c(
    # ID / citation
    "gbifID", "datasetKey", "license",
    # Taxonomy text
    "kingdom", "phylum", "class", "order", "family", "genus", "species",
    "infraspecificEpithet", "taxonRank", "scientificName",
    # Backbone keys (familyKey/genusKey are NA on the download path -- GBIF's
    # SIMPLE_CSV export does not include them; see @details)
    "taxonKey", "speciesKey", "familyKey", "genusKey",
    # Spatial
    "decimalLatitude", "decimalLongitude", "coordinateUncertaintyInMeters",
    "countryCode", "stateProvince",
    # Temporal
    "year", "month", "day",
    # Quality / filter_gbif_quality() inputs
    "basisOfRecord", "issues", "occurrenceStatus",
    # eDNA detection (filter_gbif_quality(exclude_edna=) inputs -- absent
    # from GBIF's SIMPLE_CSV export entirely, so NA on the download path;
    # present when available on the fetch path)
    "samplingProtocol", "occurrenceRemarks", "preparations"
  )
}
