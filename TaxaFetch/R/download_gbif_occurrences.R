utils::globalVariables("taxonKey")

# ==============================================================================
# download_gbif_occurrences.R
# TaxaFetch -- Async bulk GBIF occurrence download via the GBIF download API
# ==============================================================================

#' Download GBIF Occurrence Records via the Async Download API
#'
#' Submits a bulk download request to GBIF, polls until the file is ready,
#' downloads the result, and returns a tibble compatible with
#' \code{\link{fetch_gbif_occurrences}} output. Requires a free GBIF account.
#'
#' @param keys Integer or numeric vector. GBIF taxon usage keys. Typically the
#'   output of \code{\link{get_keys_from_context}} or
#'   \code{rgbif::name_backbone()}. Duplicates are removed before processing.
#' @param geometry Character. A WKT polygon string defining the geographic
#'   search area. Use \code{\link{make_bbox_wkt}} to generate from a centre
#'   lat/lon and radius. \strong{Note:} GBIF requires counter-clockwise
#'   winding order; \code{make_bbox_wkt} produces the correct winding order
#'   automatically.
#' @param year_range Character. Year range formatted as \code{"YYYY,YYYY"},
#'   e.g. \code{"2000,2024"}. Passed to GBIF as year >= and year <=
#'   predicates.
#' @param limit Integer or \code{NULL}. Maximum records to retain
#'   \strong{per taxon key} after import, matching the per-key semantics of
#'   \code{\link{fetch_gbif_occurrences}}. Records are kept in GBIF's return
#'   order; a message reports how many keys were truncated. \code{NULL}
#'   (default) retains all records for every key. When \code{taxonKey} is
#'   absent from the download, the cap is applied to the total row count
#'   instead, with a warning.
#' @param cache_dir Character or \code{NULL}. Directory for the downloaded
#'   zip file and a small metadata file. Defaults to a persistent user-level
#'   cache directory. Re-running with the same arguments reuses the cached
#'   zip and skips the GBIF download entirely. Set to \code{NULL} to
#'   disable caching.
#' @param overwrite Logical. If \code{FALSE} (default), an existing cached
#'   zip is reused. Set to \code{TRUE} to force a fresh download from GBIF.
#' @param status_ping Numeric. Seconds between download-status polls while
#'   waiting for GBIF to prepare the file. Default 15. Minimum enforced by
#'   rgbif is 3.
#' @param gbif_user Character. GBIF username. Defaults to the
#'   \code{GBIF_USER} environment variable; see Details for setup.
#' @param gbif_pwd Character. GBIF password. Defaults to the \code{GBIF_PWD}
#'   environment variable.
#' @param gbif_email Character. GBIF registered email address. Defaults to
#'   the \code{GBIF_EMAIL} environment variable.
#' @param exclude_absent Logical. When \code{TRUE} (default), adds a
#'   server-side \code{occurrenceStatus = PRESENT} predicate, excluding
#'   explicit absence records before the file is built by GBIF. Systematic
#'   surveys (e.g., eBird, iNaturalist) can contribute large numbers of
#'   \code{ABSENT} rows that inflate the download size without providing
#'   presence data. Set to \code{FALSE} only if you need absence records.
#'   Changing this parameter changes the cache key and triggers a fresh
#'   download.
#' @param basis_keep Character vector or \code{NULL}. When not \code{NULL},
#'   adds a server-side \code{basisOfRecord} predicate to the GBIF download
#'   request, reducing the size of the downloaded zip. Only occurrence records
#'   with a \code{basisOfRecord} value in this vector are included. Typical
#'   values: \code{"HUMAN_OBSERVATION"}, \code{"MACHINE_OBSERVATION"},
#'   \code{"LIVING_SPECIMEN"}, \code{"PRESERVED_SPECIMEN"},
#'   \code{"MATERIAL_SAMPLE"}. \code{NULL} (default) requests all basis types.
#'   Changing this parameter changes the cache key and triggers a fresh
#'   download. For eDNA projects where you want only field observations, use
#'   \code{c("HUMAN_OBSERVATION", "MACHINE_OBSERVATION")}.
#' @param select_cols Character vector or \code{NULL}. Columns to retain after
#'   import. Uses \code{data.table::fread}'s \code{select} argument so only
#'   the named columns are read into memory, which is much faster for large
#'   files. Does not reduce the downloaded zip size; use \code{basis_keep} for
#'   that. \code{NULL} loads all columns. The default is a set of ~35 columns
#'   covering the full TaxaID pipeline (taxonomy, spatial, temporal, quality,
#'   eDNA filter, and backbone keys). Unrecognised column names are silently
#'   ignored.
#' @param beep Logical. If \code{TRUE} and the \code{beepr} package is
#'   available, plays a sound on completion. Falls back to a system bell
#'   character if \code{beepr} is absent. Default \code{FALSE}.
#'
#' @return A tibble of occurrence records. Column structure matches
#'   \code{\link{fetch_gbif_occurrences}} for downstream compatibility with
#'   \code{\link{filter_gbif_quality}} and \code{\link{stack_occurrences}}.
#'   The \code{bibliographicCitation} column contains the GBIF download DOI
#'   (or the download key if DOI lookup fails). A \code{download_key}
#'   attribute stores the GBIF download key for citation purposes.
#'
#' @details
#' \strong{When to use this function vs \code{fetch_gbif_occurrences}:}
#' \itemize{
#'   \item Use \code{download_gbif_occurrences} for large taxon lists
#'     (roughly 50 or more keys), for any run where completeness matters
#'     (no per-key record cap), or when \code{fetch_gbif_occurrences} hits
#'     HTTP 429 rate-limit errors. Downloads are processed server-side so
#'     no per-key API calls are made from the client. A GBIF account is
#'     required.
#'   \item Use \code{fetch_gbif_occurrences} for small exploratory queries
#'     (fewer than roughly 50 keys), when you want immediate per-key
#'     progress feedback, or when you do not have a GBIF account.
#' }
#'
#' \strong{GBIF account setup:} Register for a free account at
#' \url{https://www.gbif.org/user/profile}. Then add your credentials to
#' \file{~/.Renviron} (run \code{usethis::edit_r_environ()} to open the
#' file):
#' \preformatted{
#' GBIF_USER=your_username
#' GBIF_PWD=your_password
#' GBIF_EMAIL=your@email.com
#' }
#' Save the file and restart R. Verify with \code{Sys.getenv("GBIF_USER")}.
#' You only need to do this once; the variables are loaded automatically
#' at the start of every R session.
#'
#' \strong{Caching:} The zip file returned by GBIF is saved to
#' \code{cache_dir} using a filename that encodes the call signature (key
#' count, key checksum, geometry length, year range, and \code{basis_keep}).
#' Changing any of these parameters automatically triggers a fresh download.
#' The cached zip is permanent and survives R sessions -- delete it manually
#' or set \code{overwrite = TRUE} to refresh. A small companion metadata file
#' (\code{_meta.rds}) stores the GBIF download key and timestamp.
#' \code{select_cols} is applied at import time and does not affect the cache
#' key; the same zip can be re-imported with different column sets.
#'
#' \strong{Rank-specific predicates:} Unlike the occurrence search API
#' (\code{occ_data}), the download API's \code{taxonKey} predicate is an
#' exact match, not a hierarchical search. Querying by a family key returns
#' only records where the occurrence's accepted taxon IS that family (i.e.,
#' identified only to family level), not records of species within it.
#' \code{download_gbif_occurrences} avoids this by using an OR across
#' \code{familyKey}, \code{genusKey}, \code{speciesKey}, and
#' \code{taxonKey}, so records at all ranks within the queried taxa are
#' returned.
#'
#' \strong{Cache invalidation:} If you have a cached download from a version
#' of this function that used only \code{taxonKey} (before the rank-specific
#' fix), re-run with \code{overwrite = TRUE} to fetch the correct data.
#'
#' \strong{Hierarchy validation:} Each returned record is checked to confirm
#' that one of its rank-specific key columns (\code{taxonKey},
#' \code{familyKey}, \code{genusKey}, \code{speciesKey}, etc.) matches one
#' of the requested keys. Off-target records are dropped with a diagnostic
#' message.
#'
#' \strong{Concurrent download limits:} GBIF limits accounts to 3
#' concurrent downloads (fewer for accounts with many prior downloads). If
#' a request is rejected, cancel in-progress downloads at
#' \url{https://www.gbif.org/user/download} and retry.
#'
#' @seealso \code{\link{fetch_gbif_occurrences}} (streaming alternative for
#'   small queries, no account required),
#'   \code{\link{make_bbox_wkt}}, \code{\link{get_keys_from_context}},
#'   \code{\link{filter_gbif_quality}}, \code{\link{stack_occurrences}}
#'
#' @importFrom dplyr tibble
#' @export
#'
#' @examples
#' \dontrun{
#' # --- One-time setup -------------------------------------------------------
#' # Add credentials to ~/.Renviron (run once, then restart R):
#' usethis::edit_r_environ()
#' # Add these three lines, save, and restart R:
#' #   GBIF_USER=your_username
#' #   GBIF_PWD=your_password
#' #   GBIF_EMAIL=your@email.com
#'
#' # --- Typical workflow -----------------------------------------------------
#' taxa_df <- data.frame(
#'   family  = "Gadidae",
#'   species = "Gadus morhua",
#'   stringsAsFactors = FALSE
#' )
#' keys_df    <- get_keys_from_context(taxa_df)
#' valid_keys <- keys_df$usageKey[!is.na(keys_df$usageKey)]
#'
#' bbox <- make_bbox_wkt(lat = 56.0, lon = 4.0, radius_deg = 2.0)
#' occ  <- download_gbif_occurrences(
#'   keys       = valid_keys,
#'   geometry   = bbox,
#'   year_range = "2010,2024"
#' )
#'
#' occ_clean <- filter_gbif_quality(occ)
#' attr(occ, "download_key")   # cite this in your methods section
#' }

download_gbif_occurrences <- function(
    keys,
    geometry,
    year_range     = "2000,2024",
    limit          = NULL,
    cache_dir      = tools::R_user_dir("TaxaFetch", "cache"),
    overwrite      = FALSE,
    status_ping    = 15,
    exclude_absent = TRUE,
    basis_keep     = NULL,
    select_cols = c(
      # Taxonomy text (SIMPLE_CSV has text columns, not rank key columns)
      "kingdom", "phylum", "class", "order", "family",
      "genus", "species", "infraspecificEpithet",
      "taxonRank", "scientificName",
      # Backbone keys present in SIMPLE_CSV (taxonKey and speciesKey only;
      # familyKey/genusKey etc. are DWCA-only and silently absent here)
      "taxonKey", "speciesKey",
      # Spatial
      "decimalLatitude", "decimalLongitude",
      "coordinateUncertaintyInMeters",
      "countryCode", "stateProvince",
      # Temporal
      "year", "month", "day",
      # Quality / filter_gbif_quality inputs
      "basisOfRecord", "issue", "occurrenceStatus",
      # eDNA detection columns (filter_gbif_quality exclude_edna filter)
      "samplingProtocol", "occurrenceRemarks", "preparations",
      # ID / citation
      "gbifID", "datasetKey", "license"
    ),
    gbif_user   = Sys.getenv("GBIF_USER"),
    gbif_pwd    = Sys.getenv("GBIF_PWD"),
    gbif_email  = Sys.getenv("GBIF_EMAIL"),
    beep        = FALSE) {

  # --- Dependency check -------------------------------------------------------
  if (!requireNamespace("rgbif", quietly = TRUE)) {
    stop(
      "download_gbif_occurrences: package 'rgbif' is required.\n",
      "Install it with: install.packages('rgbif')"
    )
  }

  # --- Credential check -------------------------------------------------------
  missing_creds <- c(
    if (!nzchar(gbif_user))  "GBIF_USER",
    if (!nzchar(gbif_pwd))   "GBIF_PWD",
    if (!nzchar(gbif_email)) "GBIF_EMAIL"
  )
  if (length(missing_creds) > 0L) {
    stop(
      "download_gbif_occurrences: missing GBIF credentials: ",
      paste(missing_creds, collapse = ", "), ".\n",
      "Add them to ~/.Renviron (run usethis::edit_r_environ() to open):\n",
      "  GBIF_USER=your_username\n",
      "  GBIF_PWD=your_password\n",
      "  GBIF_EMAIL=your@email.com\n",
      "Register for a free account at https://www.gbif.org/user/profile\n",
      "Save the file, then restart R (run .rs.restartR() in the console)."
    )
  }

  # --- Input checks -----------------------------------------------------------
  keys <- unique(as.integer(keys))
  keys <- keys[!is.na(keys)]
  if (length(keys) == 0L) {
    stop("download_gbif_occurrences: 'keys' is empty after removing NAs.")
  }
  if (!is.character(geometry) || length(geometry) != 1L || !nzchar(geometry)) {
    stop("download_gbif_occurrences: 'geometry' must be a single non-empty WKT string.")
  }
  if (!is.null(limit)) {
    if (!is.numeric(limit) || length(limit) != 1L || is.na(limit) || limit < 1L) {
      stop("download_gbif_occurrences: 'limit' must be a single positive integer or NULL.")
    }
    limit <- as.integer(limit)
  }

  # --- Parse year range -------------------------------------------------------
  yr_parts <- suppressWarnings(as.integer(strsplit(year_range, ",")[[1L]]))
  if (length(yr_parts) != 2L || any(is.na(yr_parts))) {
    stop("download_gbif_occurrences: 'year_range' must be \"YYYY,YYYY\", e.g. \"1995,2026\".")
  }

  # --- Cache paths ------------------------------------------------------------
  if (!is.null(cache_dir)) {
    message(sprintf(
      "download_gbif_occurrences: cache directory: %s",
      normalizePath(cache_dir, mustWork = FALSE)
    ))
  }
  meta_path <- .gbif_dl_meta_path(cache_dir, keys, geometry, year_range,
                                  basis_keep, exclude_absent)
  dl_key    <- NULL
  zip_path  <- NULL

  if (!is.null(meta_path) && file.exists(meta_path) && !overwrite) {
    meta     <- readRDS(meta_path)
    dl_key   <- meta$dl_key
    zip_path <- meta$zip_path
    if (!file.exists(zip_path)) {
      message(sprintf(
        "download_gbif_occurrences: cached zip missing (%s); re-downloading.",
        zip_path
      ))
      dl_key   <- NULL
      zip_path <- NULL
    } else {
      message(sprintf(
        "download_gbif_occurrences: reusing cached zip from %s (key %s).\n  Set overwrite = TRUE to force a fresh download.",
        format(meta$timestamp, "%Y-%m-%d"), dl_key
      ))
    }
  }

  # --- Submit download if needed ----------------------------------------------
  if (is.null(zip_path)) {
    message(sprintf(
      "download_gbif_occurrences: submitting GBIF download request for %d key(s)...",
      length(keys)
    ))

    # Build predicate list. Rank-specific OR ensures family/genus keys reach
    # all descendant records (download API taxonKey is exact-match only).
    # basis_keep is optional -- when supplied it shrinks the download server-side.
    preds <- list(
      rgbif::pred_or(
        rgbif::pred_in("taxonKey",   keys),
        rgbif::pred_in("familyKey",  keys),
        rgbif::pred_in("genusKey",   keys),
        rgbif::pred_in("speciesKey", keys)
      ),
      rgbif::pred_within(geometry),
      rgbif::pred_gte("year",      yr_parts[1L]),
      rgbif::pred_lte("year",      yr_parts[2L]),
      rgbif::pred("hasCoordinate", TRUE)
    )
    if (isTRUE(exclude_absent)) {
      preds <- c(preds, list(rgbif::pred("occurrenceStatus", "PRESENT")))
    }
    if (!is.null(basis_keep)) {
      preds <- c(preds, list(rgbif::pred_in("basisOfRecord", basis_keep)))
    }
    dl_req <- do.call(
      rgbif::occ_download,
      c(preds, list(format = "SIMPLE_CSV",
                    user   = gbif_user,
                    pwd    = gbif_pwd,
                    email  = gbif_email))
    )
    dl_key <- as.character(dl_req)
    message(sprintf(
      "  Download key: %s\n  Waiting for GBIF to prepare the file (polling every %d s)...",
      dl_key, as.integer(max(status_ping, 3))
    ))

    rgbif::occ_download_wait(dl_req, status_ping = max(status_ping, 3L))

    # Download zip to cache_dir (or tempdir if caching disabled)
    dest_dir <- if (!is.null(cache_dir)) {
      dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
      cache_dir
    } else {
      tempdir()
    }
    rgbif::occ_download_get(dl_key, path = dest_dir, overwrite = TRUE)
    zip_path <- file.path(dest_dir, paste0(dl_key, ".zip"))

    if (!file.exists(zip_path)) {
      stop(sprintf(
        "download_gbif_occurrences: expected zip not found at %s after download.",
        zip_path
      ))
    }
    message(sprintf("  Zip saved to: %s", zip_path))

    # Save metadata
    if (!is.null(meta_path)) {
      saveRDS(
        list(dl_key = dl_key, zip_path = zip_path, timestamp = Sys.time()),
        meta_path
      )
      message(
        "  Zip cached. Starting import now -- please wait for the R prompt to return.\n",
        "  (Re-running with the same parameters will skip the GBIF wait.)"
      )
    }
  }

  # --- Import -----------------------------------------------------------------
  fsize_mb <- round(file.info(zip_path)$size / 1024^2, 1)
  message(sprintf(
    "download_gbif_occurrences: importing records (zip: %.1f MB) -- still working, please wait...",
    fsize_mb
  ))
  t_import <- proc.time()["elapsed"]
  raw <- .read_gbif_zip(zip_path, select_cols = select_cols)
  message(sprintf("  Imported %d rows in %.0f s.", nrow(raw),
                  proc.time()["elapsed"] - t_import))

  # Normalise SIMPLE_CSV column names to match occ_data() conventions so that
  # filter_gbif_quality() and other downstream functions work without changes.
  # Known divergences: SIMPLE_CSV uses singular forms for a few fields.
  simple_csv_renames <- c(issue = "issues")
  for (from in names(simple_csv_renames)) {
    to <- simple_csv_renames[[from]]
    if (from %in% names(raw) && !to %in% names(raw)) {
      names(raw)[names(raw) == from] <- to
    }
  }

  if (is.null(raw) || nrow(raw) == 0L) {
    warning(
      "download_gbif_occurrences: no records in download. ",
      "Check that keys are valid and the geometry intersects known records.",
      call. = FALSE
    )
    return(dplyr::tibble())
  }

  # Hierarchy validation is intentionally omitted here. The download API's
  # rank-specific predicates (familyKey, genusKey, speciesKey OR) already
  # filter server-side. GBIF SIMPLE_CSV does not include familyKey/genusKey/
  # etc. -- only taxonKey and speciesKey -- so key-based validation would
  # incorrectly drop every species-level record (whose taxonKey is a species
  # key, not the queried family key).

  # --- Apply per-key limit ----------------------------------------------------
  t_limit <- proc.time()["elapsed"]
  if (!is.null(limit)) {
    if ("taxonKey" %in% names(raw)) {
      counts  <- tapply(seq_len(nrow(raw)), raw$taxonKey, length)
      n_over  <- sum(counts > limit)
      if (n_over > 0L) {
        message(sprintf(
          "  %d taxon key(s) had more than %d records and were truncated.",
          n_over, limit
        ))
      }
      raw <- raw |>
        dplyr::group_by(taxonKey) |>
        dplyr::slice_head(n = limit) |>
        dplyr::ungroup() |>
        as.data.frame()
    } else if (nrow(raw) > limit) {
      warning(sprintf(
        "download_gbif_occurrences: taxonKey column absent; truncating total rows to %d (was %d). Per-key limit could not be applied.",
        limit, nrow(raw)
      ), call. = FALSE)
      raw <- raw[seq_len(limit), , drop = FALSE]
    }
    elapsed_limit <- proc.time()["elapsed"] - t_limit
    if (elapsed_limit > 2) {
      message(sprintf("  Per-key limit applied in %.0f s.", elapsed_limit))
    }
  }

  # --- Bibliographic citation -------------------------------------------------
  # Construct the GBIF download portal URL directly from the key — avoids an
  # occ_download_meta() network call that can hang indefinitely with no timeout.
  # The DOI (10.15468/dl.XXXXXX) is registered asynchronously by GBIF and is
  # accessible via the portal URL below once the download record is published.
  doi_url <- if (!is.null(dl_key) && nzchar(dl_key)) {
    paste0("https://www.gbif.org/occurrence/download/", dl_key)
  } else {
    "GBIF.org occurrence download (key unavailable)"
  }
  raw$bibliographicCitation <- doi_url

  message(sprintf(
    "download_gbif_occurrences: %d records retrieved for %d key(s).",
    nrow(raw), length(keys)
  ))

  # --- Attributes -------------------------------------------------------------
  attr(raw, "download_key") <- dl_key %||% NA_character_
  attr(raw, "report_params") <- list(
    source     = "GBIF (async download)",
    n_keys     = length(keys),
    n_records  = nrow(raw),
    doi        = doi_url,
    geometry   = geometry,
    year_range = year_range
  )

  # --- Completion sound -------------------------------------------------------
  if (beep) {
    if (requireNamespace("beepr", quietly = TRUE)) beepr::beep(sound = 2L) else cat("\007")
  }

  raw
}


# ==============================================================================
# Internal helpers
# ==============================================================================

#' Build the metadata RDS path for a download_gbif_occurrences call
#'
#' Encodes key count, key checksum, geometry length, and year range.
#' Changing any parameter produces a different path and triggers a fresh
#' download.
#'
#' @param cache_dir Character or NULL.
#' @param keys Integer vector (deduped, NA-free).
#' @param geometry WKT string.
#' @param year_range Character year range.
#' @return A file path string, or NULL if cache_dir is NULL.
#' @noRd
.gbif_dl_meta_path <- function(cache_dir, keys, geometry, year_range,
                               basis_keep = NULL, exclude_absent = TRUE) {
  if (is.null(cache_dir)) return(NULL)
  dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  basis_tag   <- if (!is.null(basis_keep)) paste0("_b", sum(nchar(basis_keep))) else ""
  absent_tag  <- if (isTRUE(exclude_absent)) "_pres" else ""
  sig <- sprintf(
    "%dk_s%d_g%d_%s%s%s",
    length(keys),
    as.integer(sum(as.numeric(keys)) %% 1e9),
    nchar(geometry),
    gsub("[^0-9]", "", year_range),
    basis_tag,
    absent_tag
  )
  file.path(cache_dir, paste0("gbif_dl_", sig, "_meta.rds"))
}


#' Import occurrence records from a GBIF SIMPLE_CSV zip file
#'
#' Unzips to a temporary directory and reads the tab-delimited occurrence
#' file. Uses \code{data.table::fread} when available (much faster for large
#' files); falls back to \code{utils::read.table}.
#'
#' @param zip_path Character. Path to the downloaded GBIF zip file.
#' @return A data frame of occurrence records.
#' @noRd
.read_gbif_zip <- function(zip_path, select_cols = NULL) {
  tmp <- tempfile(pattern = "gbif_unzip_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)

  utils::unzip(zip_path, exdir = tmp)
  all_files <- list.files(tmp, full.names = TRUE, recursive = TRUE)

  # SIMPLE_CSV zip typically contains: occurrence.csv, citations.txt,
  # rights.txt, dataset/ subdirectory. We want the occurrence data file.
  data_file <- all_files[grepl("occurrence\\.(csv|txt)$", all_files,
                               ignore.case = TRUE)]
  if (length(data_file) == 0L) {
    # Fallback: any .csv or .txt that is not a metadata file
    data_file <- all_files[grepl("\\.(csv|txt)$", all_files) &
                           !grepl("citation|rights|dataset|meta|readme",
                                  basename(all_files), ignore.case = TRUE)]
  }
  if (length(data_file) == 0L) {
    stop("download_gbif_occurrences: no data file found in zip at ", zip_path)
  }
  data_file <- data_file[1L]

  if (requireNamespace("data.table", quietly = TRUE)) {
    # Intersect select_cols with available columns to avoid fread errors on
    # unrecognised names.  Read header-only first (cheap: 0 data rows).
    use_cols <- if (!is.null(select_cols)) {
      available <- names(data.table::fread(data_file, nrows = 0L,
                                           showProgress = FALSE))
      intersect(select_cols, available)
    } else NULL
    as.data.frame(data.table::fread(
      data_file, sep = "\t", quote = "", fill = TRUE,
      encoding = "UTF-8", showProgress = FALSE,
      select = if (length(use_cols) > 0L) use_cols else NULL
    ))
  } else {
    message("  data.table not available; using readr (install data.table for faster imports).")
    as.data.frame(readr::read_tsv(
      data_file, show_col_types = FALSE, progress = FALSE
    ))
  }
}
